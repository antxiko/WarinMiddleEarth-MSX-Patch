# UNA PASADA LINEAL POR EL REPLAY, CON INSTRUMENTACION, POR VENTANAS DE TIEMPO
#
# Entra con `reverse goto T_INI` (nunca antes de que el juego este cargado: hasta
# entonces corre la BIOS en la pagina 0 y sus PC caen encima de los graficos del
# bloque bajo, que es la lectura falsa que ya contamino Stardust) y deja correr
# la maquina con throttle off hasta T_FIN. Por cada ventana de VENTANA segundos
# emulados escribe:
#   indice.txt            idx t_ini t_fin PC SP n38 muestras muestras_fuera nuevos_distintos
#   zx.bin                0x4000-0x5AFF (la pantalla ZX emulada), 6912 B por ventana
#   sys.bin               0x5B00-0x5DFF, 768 B por ventana
#   est.bin               0xB8E8-0xC7FF (tablas de estado), 3864 B por ventana
#   fin.bin               0xE400-0xE677, 632 B por ventana
#   alta.bin              0xE678-0xFFFF, 6536 B por ventana
#   baja.bin              0x0000-0x018F, 400 B por ventana
#   pcs_ventanas.txt      histograma del PC muestreado cada 1 ms ("== idx t" y "PC n")
#   nuevos_ventanas.txt   PCs FUERA del trazado vistos en la ventana (muestreo o fetch), con cuenta
#   nuevos_primera_vez.txt PC, primer instante y como se vio (muestra / fetch leyendo X)
#   lecturas_ventanas.txt quien lee cada region vigilada en la ventana: "region PC n"
#   escrituras_ventanas.txt quien escribe en los bloques de codigo en la ventana: "PC direccion n"
#   full_NNNNN.bin        los 64K enteros cada FULL_CADA ventanas
#
# COMO SE CAZA LO QUE CORRE FUERA DEL TRAZADO. Dos vias, las dos baratas:
#   1. el muestreo del PC cada milisegundo (after time 0.001; medido: 75x);
#   2. watchpoints de LECTURA sobre las regiones que el trazado no marca como
#      codigo (work/replay/regiones.tcl): un fetch es una lectura, y en el
#      callback `reg PC` es la direccion de la instruccion que se esta leyendo
#      (medido en el jp de 0x0038: las tres lecturas 0038/0039/003A dan PC=0038).
#      Si ese PC cae fuera del trazado, es ejecucion nueva, con su instante exacto.
#      De paso salen los PC que LEEN cada region, que es lo que hace falta para
#      declarar los graficos con su lector.
# Lo que NO vale: un breakpoint por cada direccion fuera del trazado. openMSX 21
# recorre la lista entera de bps en cada instruccion (checkBreakPoints es un
# bucle lineal) y con 54430 bps la emulacion cae a 0,05x (medido).
#
# Las regiones muy leidas por datos (mapa, fuente, tiles, tablas de estado, la
# pantalla ZX, la tabla de mandos de 0x06D0 con 47000 lecturas/s y la variable
# 0x96F0 con 4000/s) van excluidas; una region que supere TOPE lecturas en una
# ventana se desactiva hasta la ventana siguiente.
#
# Ademas, watchpoints de ESCRITURA sobre los dos bloques de codigo (0x0190-0x3F4E
# y 0x5E00-0x96F0): toda escritura ahi es automodificacion o RAM de trabajo
# encima del codigo (0x5E00-0x6316 aparece machacado en la partida).
#
# Control: las lecturas de 0x0038 (el jp de la interrupcion) tienen que dar ~50
# por segundo emulado (n38 en el indice).
#
# Los parametros van en un fichero, no en el entorno ni en argumentos:
#   source work/replay/cfg.tcl   define NOMBRE T_INI T_FIN VENTANA FULL_CADA MAX_REAL
set W C:/Users/Antxiko/Documents/DES_ASM/desensamblados/WARINMIDDLEEARTH_DISAM
source $W/work/replay/cfg.tcl
set OUT $W/work/replay/$NOMBRE
file mkdir $OUT
set L [open $OUT/pasada.log w]
proc say {m} { global L; puts $L "[clock seconds] [format %10.2f [machine_info time]] $m"; flush $L }
source $W/work/replay/fuera.tcl
source $W/work/replay/regiones.tcl
foreach pc $::FUERA { set ::fuera($pc) 1 }
unset ::FUERA
set TOPE 5000

set ::ARCHIVOS {}
proc abre {nombre binario} {
    global OUT
    set f [open $OUT/$nombre [expr {$binario ? "wb" : "w"}]]
    if {$binario} { fconfigure $f -translation binary }
    lappend ::ARCHIVOS $f
    return $f
}
proc termina {rc} {
    say "termina rc=$rc"
    foreach f $::ARCHIVOS { catch {close $f} }
    exit $rc
}

catch {set renderer none}
say "arranque, maquina [machine_info config_name], renderer [set renderer]"
set r [catch {reverse loadreplay -viewonly $W/work/replay/war_replay.omr} msg]
say "loadreplay rc=$r: $msg"
if {$r} { say ABORTADO; exit 1 }
array set st [reverse status]
set FIN $st(end)
if {$T_FIN <= 0 || $T_FIN > $FIN} { set T_FIN [expr {$FIN - 0.5}] }
say "replay: fin en $FIN; pasada de $T_INI a $T_FIN, ventana $VENTANA"
set t0 [clock milliseconds]
set r [catch {reverse goto $T_INI} msg]
say "goto $T_INI rc=$r $msg tardo [expr {[clock milliseconds]-$t0}] ms; PC=[format %04X [reg PC]] SP=[format %04X [reg SP]]"
if {$r} { say ABORTADO; exit 1 }

set ::IDX [abre indice.txt 0]
puts $::IDX "# idx t_ini t_fin PC SP n38 muestras muestras_fuera nuevos_distintos"
set ::FZX [abre zx.bin 1]
set ::FSYS [abre sys.bin 1]
set ::FEST [abre est.bin 1]
set ::FFIN [abre fin.bin 1]
set ::FALTA [abre alta.bin 1]
set ::FBAJA [abre baja.bin 1]
set ::FPCS [abre pcs_ventanas.txt 0]
set ::FNUE [abre nuevos_ventanas.txt 0]
set ::FVEZ [abre nuevos_primera_vez.txt 0]
set ::FLEE [abre lecturas_ventanas.txt 0]
set ::FESC [abre escrituras_ventanas.txt 0]

# --- watchpoints de lectura por region
set ::n38 0
set ::vnue [dict create]
set ::vlee [dict create]
set ::REG {}
set i 0
foreach {a b} $::REGIONES {
    lappend ::REG [list $i $a $b]
    set ::rcnt($i) 0
    set ::rwp($i) ""
    incr i
}
proc arma_lectura {i} {
    lassign [lindex $::REG $i] _ a b
    set ::rwp($i) [debug set_watchpoint read_mem [list $a [expr {$b - 1}]] {} "lee $i"]
}
proc lee {i} {
    set a $::wp_last_address
    if {$a == 0x38} { incr ::n38; return }
    set pc [reg PC]
    dict incr ::vlee "$i $pc"
    if {[info exists ::fuera($pc)]} {
        if {![info exists ::vez($pc)]} {
            set ::vez($pc) 1
            puts $::FVEZ [format "%04X %.3f fetch leyendo %04X" $pc [machine_info time] $a]
            flush $::FVEZ
        }
        dict incr ::vnue $pc
    }
    if {[incr ::rcnt($i)] >= $::TOPE} {
        debug remove_watchpoint $::rwp($i)
        set ::rwp($i) ""
        lappend ::quitados $i
    }
}
set ::quitados {}
foreach r $::REG { arma_lectura [lindex $r 0] }
say "puestos [llength $::REG] watchpoints de lectura"

# --- watchpoints de escritura sobre los bloques de codigo
set ::vesc [dict create]
set ::ESC {{0 0x0190 0x3F4E} {1 0x5E00 0x96F0}}
proc arma_escritura {i} {
    lassign [lindex $::ESC $i] _ a b
    set ::ewp($i) [debug set_watchpoint write_mem [list $a [expr {$b - 1}]] {} "escribe $i"]
}
proc escribe {i} {
    dict incr ::vesc [format "%04X %04X" [reg PC] $::wp_last_address]
    if {[incr ::ecnt($i)] >= $::TOPE} {
        debug remove_watchpoint $::ewp($i)
        set ::ewp($i) ""
        lappend ::equitados $i
    }
}
set ::equitados {}
foreach i {0 1} { set ::ecnt($i) 0; arma_escritura $i }
say "puestos 2 watchpoints de escritura"

# --- muestreo del PC
set ::pcs [dict create]
set ::nm 0
proc muestrea {} {
    after time 0.001 muestrea
    dict incr ::pcs [reg PC]
    incr ::nm
}

set ::idx 0
set ::tv $T_INI
set ::t_real0 [clock seconds]
proc cierra_ventana {} {
    global OUT
    set t [machine_info time]
    puts -nonewline $::FZX [debug read_block memory 0x4000 0x1B00]
    puts -nonewline $::FSYS [debug read_block memory 0x5B00 0x300]
    puts -nonewline $::FEST [debug read_block memory 0xB8E8 0xF18]
    puts -nonewline $::FFIN [debug read_block memory 0xE400 0x278]
    puts -nonewline $::FALTA [debug read_block memory 0xE678 0x1988]
    puts -nonewline $::FBAJA [debug read_block memory 0x0000 0x190]
    set mf 0
    foreach pc [dict keys $::pcs] {
        if {[info exists ::fuera($pc)]} {
            incr mf [dict get $::pcs $pc]
            dict incr ::vnue $pc [dict get $::pcs $pc]
            if {![info exists ::vez($pc)]} {
                set ::vez($pc) 1
                puts $::FVEZ [format "%04X %.3f muestra (ventana %d)" $pc $t $::idx]
                flush $::FVEZ
            }
        }
    }
    puts $::IDX [format "%d %.2f %.2f %04X %04X %d %d %d %d" $::idx $::tv $t [reg PC] [reg SP] $::n38 $::nm $mf [dict size $::vnue]]
    puts $::FPCS [format "== %d %.2f" $::idx $t]
    foreach pc [lsort -integer [dict keys $::pcs]] { puts $::FPCS [format "%04X %d" $pc [dict get $::pcs $pc]] }
    if {[dict size $::vnue]} {
        puts $::FNUE [format "== %d %.2f" $::idx $t]
        foreach pc [lsort -integer [dict keys $::vnue]] { puts $::FNUE [format "%04X %d" $pc [dict get $::vnue $pc]] }
    }
    if {[dict size $::vlee]} {
        puts $::FLEE [format "== %d %.2f" $::idx $t]
        foreach k [lsort -dictionary [dict keys $::vlee]] {
            lassign $k i pc
            puts $::FLEE [format "%d %04X %d" $i $pc [dict get $::vlee $k]]
        }
    }
    if {[dict size $::vesc]} {
        puts $::FESC [format "== %d %.2f" $::idx $t]
        foreach k [lsort -dictionary [dict keys $::vesc]] { puts $::FESC "$k [dict get $::vesc $k]" }
    }
    if {$::idx % $::FULL_CADA == 0} {
        set f [open $OUT/full_[format %05d $::idx].bin wb]
        fconfigure $f -translation binary
        puts -nonewline $f [debug read_block memory 0 0x10000]
        close $f
    }
    foreach i $::quitados { arma_lectura $i }
    set ::quitados {}
    foreach i [array names ::rcnt] { set ::rcnt($i) 0 }
    foreach i $::equitados { arma_escritura $i }
    set ::equitados {}
    foreach i [array names ::ecnt] { set ::ecnt($i) 0 }
    set ::pcs [dict create]
    set ::vnue [dict create]
    set ::vlee [dict create]
    set ::vesc [dict create]
    set ::n38 0
    set ::nm 0
    set ::tv $t
    incr ::idx
    foreach f $::ARCHIVOS { flush $f }
    if {$t >= $::T_FIN} { say "FIN de la pasada"; termina 0 }
}
proc ventana {} {
    after time $::VENTANA ventana
    if {[catch {cierra_ventana} msg]} { say "ventana error: $msg" }
}
proc latido {} {
    after realtime 60 latido
    set t [machine_info time]
    say [format "latido: ventana %d, %d s reales, ritmo %.1fx, fuera vistos %d" $::idx [expr {[clock seconds]-$::t_real0}] [expr {($t-$::T_INI)/double([clock seconds]-$::t_real0+1)}] [array size ::vez]]
}

after realtime $MAX_REAL { say "tope de tiempo real"; catch {cierra_ventana}; termina 2 }
after realtime 60 latido
set throttle off
after time $VENTANA ventana
muestrea
say "en marcha"
