# LA MUSICA DEL CARTUCHO EN openMSX: ¿suena de verdad, y calla cuando debe?
#
# Arranca la maquina con war_musica.rom puesta, deja llegar al menu y mira las
# cuatro cosas que tienen que ser ciertas para que suene, en orden, porque cada
# una explica el fallo de la siguiente:
#
#   1. el gancho por cuadro apunta al puente y no al `ret` de siempre;
#   2. el puente esta copiado en su sitio y su `or` lleva una ranura, no un cero;
#   3. el puente se EJECUTA, una vez por cuadro;
#   4. los registros del PSG se mueven: tonos y volumenes distintos entre
#      muestras. Esto es lo unico que distingue "suena" de "corre y no suena".
#
# Luego pulsa el '0' que empieza la partida y comprueba lo contrario: que el
# gancho vuelve a su `ret`, que los tres volumenes se quedan a cero y que el
# PSG no se mueve. La musica es del MENU.
#
# Y de paso mide lo que hace falta para decidir si puede seguir durante la
# partida: cuanto del cuadro se pasa dentro del puente, repartido en tramos.
#
# Las direcciones NO se escriben aqui: las genera tools/haz_rom.py leyendolas
# del .sym con el que acaba de ensamblar el puente, y se pasan en WAR_DIRS.
# Escritas a mano se quedan viejas en cuanto el puente cambia de tamano, y
# entonces la sonda lee otra cosa y canta un valor que no es: PUENTE_SONANDO se
# movio de 0x006E a 0x007C al anadirle el parar, y el informe dio por bueno un
# 0x28 que era un byte de codigo.
#
#   WAR_ROM=<war_musica.rom> WAR_OUT=<dir> WAR_DIRS=<work/musica.tcl> \
#     openmsx -machine <maquina> -carta <rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/musica.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

source $::env(WAR_DIRS)

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
say "cartucho: [carta]"

proc hex {v {n 2}} { return [format 0x%0${n}X $v] }

proc lee_bloque {addr n} {
    set out {}
    for {set i 0} {$i < $n} {incr i} {
        lappend out [format %02X [debug read memory [expr {$addr + $i}]]]
    }
    return [join $out ""]
}

proc gancho {} {
    return [expr {[debug read memory $::GANCHO] + 256 * [debug read memory [expr {$::GANCHO + 1}]]}]
}

proc psg {} {
    set out {}
    for {set r 0} {$r < 14} {incr r} {
        lappend out [format %02X [debug read "PSG regs" $r]]
    }
    return [join $out " "]
}

# --------------------------------------------------------------- el contador
# Cada entrada al puente y lo que se pasa dentro. La cuenta va con el reloj de
# emulacion -`machine_info time`, en segundos- y NO con el contador del VDP,
# que se reinicia en cada barrido y da restas negativas o disparatadas en
# cuanto el puente cruza el final de un cuadro.
#
# La salida se marca en 0x0417, la instruccion siguiente al `call` del gancho
# en la INTERRUPCION de 0x0400: es por donde vuelve el puente.
set ::Z80 3579545.0
set ::CUADRO [expr {$::Z80 / 50.0}]
set ::VUELVE 0x0417
set ::veces 0
set ::seg_total 0.0
set ::seg_max 0.0
set ::entrada -1.0
set ::TRAMOS {5 10 15 20 30 50}
set ::histograma {0 0 0 0 0 0 0}

debug set_bp $::PUENTE {} {
    incr ::veces
    set ::entrada [machine_info time]
}
debug set_bp $::VUELVE {} {
    if {$::entrada >= 0.0} {
        set d [expr {[machine_info time] - $::entrada}]
        if {$d > 0.0} {
            set ::seg_total [expr {$::seg_total + $d}]
            if {$d > $::seg_max} { set ::seg_max $d }
            # En que tramo del cuadro cae. Sin esto la medida no sirve para
            # decidir nada: una media del 7,8% con una maxima del 47,9% puede
            # ser un juego que se atasca a menudo o un unico pico al arrancar,
            # que es lo que resulta ser -la vuelta que lleva PT3_INIT dentro,
            # montando la tabla de volumenes entera, y no se repite-.
            set pc [expr {100.0 * $d * $::Z80 / $::CUADRO}]
            set i 0
            foreach tope $::TRAMOS {
                if {$pc < $tope} { break }
                incr i
            }
            lset ::histograma $i [expr {[lindex $::histograma $i] + 1}]
        }
        set ::entrada -1.0
    }
}

proc informe {} {
    say "--------------------------------------------------------------"
    say "1. el gancho de [hex $::GANCHO 4] = [hex [gancho] 4]   ([hex $::PUENTE 4] = llama al puente)"
    say "2. el puente en [hex $::PUENTE 4] = [lee_bloque $::PUENTE 16]..."
    say "   la ranura del `or` de [hex $::PUENTE_RANURA 4] = [hex [debug read memory $::PUENTE_RANURA]]  (0x00 = sin rellenar)"
    say "   PUENTE_SONANDO [hex $::PUENTE_SONANDO 4] = [hex [debug read memory $::PUENTE_SONANDO]]  (0xFF = ya arranco)"
    say "3. el puente se ha ejecutado $::veces veces"
    if {$::veces > 1} {
        set media [expr {$::seg_total / $::veces * $::Z80}]
        set maxi [expr {$::seg_max * $::Z80}]
        say [format "   coste por cuadro: %.0f ciclos de media (%.1f%% del cuadro), maxima %.0f (%.1f%%)" \
                 $media [expr {100.0 * $media / $::CUADRO}] $maxi [expr {100.0 * $maxi / $::CUADRO}]]
        set desde 0
        set i 0
        foreach tope [concat $::TRAMOS {999}] {
            set n [lindex $::histograma $i]
            if {$n > 0} { say [format "     %3d-%3d%% del cuadro: %d veces" $desde $tope $n] }
            set desde $tope
            incr i
        }
    }
    say "4. PSG: [psg]"
    say "   area de trabajo [hex $::PT3_SETUP 4] = [lee_bloque $::PT3_SETUP 16]..."
    say "   AYREGS [hex $::AYREGS 4] = [lee_bloque $::AYREGS 14]"
}

# ------------------------------------------------------------------ la traza
# Al llegar al menu se toman varias muestras del PSG separadas en el tiempo. Si
# la musica suena, no pueden salir todas iguales.
set ::muestras {}
set ::suena 0
proc muestrea {n} {
    lappend ::muestras [psg]
    say "muestra [llength $::muestras]: [lindex $::muestras end]"
    if {$n > 1} {
        after time 0.5 [list muestrea [expr {$n - 1}]]
    } else {
        informe
        set distintas [llength [lsort -unique $::muestras]]
        say "de [llength $::muestras] muestras del PSG, $distintas distintas"
        if {$distintas > 1 && [gancho] == $::PUENTE} {
            set ::suena 1
            say "SUENA"
        } else {
            say "NO SUENA: el PSG no se mueve"
        }
        calla
    }
}

# ----------------------------------------------------- y que calle al empezar
proc calla {} {
    say "--------------------------------------------------------------"
    say "se pulsa 0 para empezar la partida"
    type "0"
    after time 2 {
        set ::despues {}
        muestrea_final 4
    }
}

proc muestrea_final {n} {
    lappend ::despues [psg]
    say "tras el 0, muestra [llength $::despues]: [lindex $::despues end]"
    if {$n > 1} {
        after time 0.5 [list muestrea_final [expr {$n - 1}]]
        return
    }
    set g [gancho]
    say "el gancho de [hex $::GANCHO 4] = [hex $g 4]   ([hex $::GANCHO_VACIO 4] = ya no llama al puente)"
    say "PUENTE_SONANDO [hex $::PUENTE_SONANDO 4] = [hex [debug read memory $::PUENTE_SONANDO]]"
    say "el puente se llamo $::veces veces en total"
    set quietas [llength [lsort -unique $::despues]]
    set vol {}
    foreach r {8 9 10} { lappend vol [debug read "PSG regs" $r] }
    say "volumenes A/B/C = [join $vol /]  ; muestras distintas tras el 0: $quietas"
    set mudo [expr {$quietas == 1 && $g == $::GANCHO_VACIO
                    && [lindex $vol 0] == 0 && [lindex $vol 1] == 0 && [lindex $vol 2] == 0}]
    if {$mudo} { say "CALLA" } else { say "NO CALLA: sigue sonando tras empezar la partida" }
    # El `exit` de openMSX no corta el procedimiento en el acto: sin el `else`
    # se escribian las dos lineas, "OK" y detras "FALLA".
    if {$::suena && $mudo} {
        say "OK"
        exit 0
    } else {
        say "FALLA"
        exit 1
    }
}

set ::bp_5e00 [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el juego arranca"
    debug remove_bp $::bp_5e00
    after time 2 { muestrea 6 }
}]

after time 60 { say "TIMEOUT: no se llego al menu"; informe; exit 1 }
