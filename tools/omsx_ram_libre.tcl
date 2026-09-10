# Que RAM toca el juego DE VERDAD, medido sobre una partida grabada.
#
# Para que: antes de meterle nada nuevo al juego -un reproductor de musica, un
# cargador de cartucho- hay que saber que bytes de los 64 KB no lee ni escribe
# nadie. El listado dice que hay en la cinta; esto dice que se USA.
#
# Como: los 64 KB en bandas de BANDA bytes, y por cada banda un punto de
# observacion de LECTURA y otro de ESCRITURA que SE QUITAN SOLOS al primer
# toque. Asi una banda caliente -la pantalla del ZX, la pila- cuesta UNA llamada
# a Tcl y no millones, y la medida entera va a la velocidad del emulador. Lo
# que se apunta de cada toque: la banda, si fue lectura o escritura, el PC que
# lo hizo y el instante. Una banda sin toque al acabar es RAM que nadie mira.
#
# Ademas, cada segundo emulado se muestrea SP y se guarda el minimo: la pila
# baja desde 0x5BFF y hay que saber hasta donde.
#
# Sobre que: el replay de Araubi (work/replay/war_replay.omr, preparado con
# tools/prepara_replay.py), entrando DESPUES de la carga con `reverse goto`,
# que reproducir desde t=0 relee la cinta y diverge (ver la memoria de la
# serie). Se comprueba al entrar que la interrupcion del juego ya esta en
# 0x0038 (jp 0x0400), que es la firma de que el juego corre.
#
#   WAR_OUT=<dir> WAR_T_INI=<s> [WAR_T_FIN=<s>] [WAR_BANDA=256] [WAR_NOMBRE=x] \
#       openmsx -script tools/omsx_ram_libre.tcl
#
# Sin -machine: el replay trae la suya dentro.
set OUT   $::env(WAR_OUT)
set T_INI $::env(WAR_T_INI)
set T_FIN [expr {[info exists ::env(WAR_T_FIN)] ? $::env(WAR_T_FIN) : 0}]
set BANDA [expr {[info exists ::env(WAR_BANDA)] ? $::env(WAR_BANDA) : 256}]
set NOMBRE [expr {[info exists ::env(WAR_NOMBRE)] ? $::env(WAR_NOMBRE) : "ram"}]
set W [file dirname [file dirname [info script]]]
file mkdir $OUT

set L [open "$OUT/$NOMBRE.log" w]
proc say {m} { global L; puts $L "[clock seconds] [format %9.2f [machine_info time]] $m"; flush $L }

catch {set renderer none}
say "arranque, maquina [machine_info config_name]"
set r [catch {reverse loadreplay -viewonly $W/work/replay/war_replay.omr} msg]
say "loadreplay rc=$r: $msg"
if {$r} { say ABORTADO; exit 1 }
array set st [reverse status]
set FIN $st(end)
if {$T_FIN <= 0 || $T_FIN > $FIN} { set T_FIN [expr {$FIN - 0.5}] }
say "replay: dura $FIN s; se mide de $T_INI a $T_FIN en bandas de $BANDA"

set t0 [clock milliseconds]
set r [catch {reverse goto $T_INI} msg]
say "goto $T_INI rc=$r $msg ([expr {[clock milliseconds]-$t0}] ms) PC=[format %04X [reg PC]] SP=[format %04X [reg SP]]"
if {$r} { say ABORTADO; exit 1 }

# --- las bandas
set ::N [expr {65536 / $BANDA}]
set ::toque [dict create]      ;# "i r" / "i w" -> "pc t"
set ::wp [dict create]         ;# "i r" / "i w" -> id del watchpoint
proc toque {i tipo} {
    # Se apunta el primer toque y se quita el punto de observacion: la banda ya
    # esta clasificada y no hace falta volver a oirla.
    set k "$i $tipo"
    if {![dict exists $::toque $k]} {
        dict set ::toque $k [list [reg PC] [machine_info time]]
        catch {debug remove_watchpoint [dict get $::wp $k]}
    }
}
proc arma {} {
    global BANDA
    for {set i 0} {$i < $::N} {incr i} {
        set a [expr {$i * $BANDA}]
        set b [expr {$a + $BANDA - 1}]
        dict set ::wp "$i r" [debug set_watchpoint read_mem  [list $a $b] {} [list toque $i r]]
        dict set ::wp "$i w" [debug set_watchpoint write_mem [list $a $b] {} [list toque $i w]]
    }
    say "puestos [expr {2*$::N}] puntos de observacion; PC=[format %04X [reg PC]]"
}

# La firma de que el juego esta cargado y corriendo: 0x0038 = jp 0x0400. Si en
# T_INI todavia no esta -se ha entrado durante la carga-, se espera al salto al
# arranque del juego (0x5E00) y se arma justo ahi: asi se ve desde su primera
# instruccion.
set v38 [format "%02X%02X%02X" [debug read memory 0x38] [debug read memory 0x39] [debug read memory 0x3A]]
say "0x0038 = $v38 (C30004 = el juego ya corre)"
if {$v38 eq "C30004"} {
    arma
} else {
    say "aun cargando: se arma al llegar a 0x5E00"
    debug set_bp 0x5E00 {} { if {![dict size $::wp]} { say "el juego arranca (0x5E00)"; arma } }
}

# --- la pila y el latido
set ::spmin 0xFFFF
set ::latidos 0
proc latido {} {
    after time 1 latido
    catch {
        set sp [reg SP]
        if {$sp < $::spmin} { set ::spmin $sp }
        incr ::latidos
        if {$::latidos % 30 == 0} {
            say "latido: [dict size $::toque] toques, SP min [format %04X $::spmin], PC=[format %04X [reg PC]]"
        }
        if {[machine_info time] >= $::T_FIN} { vuelca; exit 0 }
    }
}
set ::T_FIN $T_FIN

proc vuelca {} {
    global OUT NOMBRE BANDA
    set f [open "$OUT/$NOMBRE.bandas" w]
    puts $f "# banda ini fin lectura(PC t) escritura(PC t)   -- '-' = nadie"
    for {set i 0} {$i < $::N} {incr i} {
        set a [expr {$i * $BANDA}]
        set b [expr {$a + $BANDA - 1}]
        set rr "-"; set ww "-"
        if {[dict exists $::toque "$i r"]} { lassign [dict get $::toque "$i r"] pc t; set rr [format "%04X@%.2f" $pc $t] }
        if {[dict exists $::toque "$i w"]} { lassign [dict get $::toque "$i w"] pc t; set ww [format "%04X@%.2f" $pc $t] }
        puts $f [format "%3d %04X %04X %s %s" $i $a $b $rr $ww]
    }
    close $f
    say "volcado $OUT/$NOMBRE.bandas: [dict size $::toque] toques de [expr {2*$::N}], SP min [format %04X $::spmin]"
}

set throttle off
latido
