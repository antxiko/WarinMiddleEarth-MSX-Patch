# ¿CUANTO CUESTA UNA VUELTA DE LA VISTA DE CERCA?
#
# Es la medida "de antes" de la optimizacion de la tabla de nombres: sin este
# numero no hay forma de decir despues que sirvio de algo.
#
# La vuelta del bucle de la vista (0x71F9) se reparte en tres tramos, y hay que
# separarlos porque la optimizacion solo ataca los dos ultimos:
#
#   0x71F9 -> 0x75A5   dibujar el trozo de mapa en la pantalla de CARACTERES
#   0x75A5 -> 0x7603   expandir las 768 celdas a bitmap + atributos en RAM
#   0x7603 -> 0x7615   subir 12.288 bytes a la VRAM (24 llamadas a 0x074E)
#
# El reloj es `machine_info time`, en segundos de emulacion, como en
# tools/omsx_musica.tcl: el contador del VDP se reinicia en cada barrido y da
# restas disparatadas en cuanto un tramo cruza el final de un cuadro.
#
# Para llegar a la vista: en el menu 2 (cursores) y 0 (empezar); en el mapa, el
# cursor arranca ya sobre el mapa, asi que basta disparar con ESPACIO.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_vista.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/vista.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
catch {say "cartucho: [carta]"}

set ::Z80 3579545.0
set ::CUADRO [expr {$::Z80 / 50.0}]
set ::ESPACIO 0x01

# marca[nombre] = instante de entrada; suma/veces por tramo.
set ::t [dict create]
set ::suma [dict create trozo 0.0 expande 0.0 sube 0.0 vuelta 0.0]
set ::veces [dict create trozo 0 expande 0 sube 0 vuelta 0]
set ::midiendo 0

proc apunta {tramo desde} {
    if {!$::midiendo} { return }
    if {![dict exists $::t $desde]} { return }
    set d [expr {[machine_info time] - [dict get $::t $desde]}]
    if {$d <= 0.0} { return }
    dict set ::suma $tramo [expr {[dict get $::suma $tramo] + $d}]
    dict incr ::veces $tramo
}

proc pon_bps {} {
    debug set_bp 0x71F9 {} {
        apunta vuelta arriba
        dict set ::t arriba [machine_info time]
    }
    debug set_bp 0x75A5 {} {
        apunta trozo arriba
        dict set ::t expande [machine_info time]
    }
    debug set_bp 0x7603 {} {
        apunta expande expande
        dict set ::t sube [machine_info time]
    }
    debug set_bp 0x7615 {} {
        apunta sube sube
    }
}

proc informe {} {
    say "-------------------------------------------------------------"
    set total 0.0
    foreach tramo {trozo expande sube} {
        set n [dict get $::veces $tramo]
        if {$n == 0} { say [format "  %-8s  no se ejecuto" $tramo]; continue }
        set c [expr {[dict get $::suma $tramo] / $n * $::Z80}]
        set total [expr {$total + $c}]
        say [format "  %-8s  %8.0f ciclos de media  (%5.1f%% de un cuadro)  x%d" \
                 $tramo $c [expr {100.0 * $c / $::CUADRO}] $n]
    }
    set n [dict get $::veces vuelta]
    if {$n > 0} {
        set c [expr {[dict get $::suma vuelta] / $n * $::Z80}]
        say [format "  %-8s  %8.0f ciclos de media  (%5.2f cuadros)  x%d" \
                 "VUELTA" $c [expr {$c / $::CUADRO}] $n]
        say [format "  o sea %.1f vueltas por segundo" [expr {$::Z80 / $c}]]
    }
    say [format "  los tres tramos suman %.0f ciclos" $total]
}

set ::bp_mapa 0
proc en_el_mapa {} {
    say "en el mapa; se dispara con ESPACIO para entrar a la VISTA DE CERCA"
    keymatrixdown 8 $::ESPACIO
    after time 0.4 {
        keymatrixup 8 $::ESPACIO
        after time 2 {
            set ::midiendo 1
            say "midiendo..."
            after time 10 {
                set ::midiendo 0
                say "=== VISTA DE CERCA, diez segundos ==="
                informe
                say "FIN"
                exit 0
            }
        }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    pon_bps
    after time 2 {
        say "se pulsa 2 (cursores)"
        type "2"
        after time 2 {
            say "se pulsa 0 (empezar)"
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                debug remove_bp $::bp_mapa
                after time 2 { en_el_mapa }
            }]
        }
    }
}]

after time 120 { say "TIMEOUT"; informe; exit 1 }
