# ¿A CUANTAS UNIDADES POR SEGUNDO SE PASA EN LA PANTALLA DE PRE-BATALLA?
#
# PANTALLA_DE_BATALLA (0x752C) es el modo 0x17: enseña las unidades propias
# una a una con el cartel "Comienza la Batalla" antes de entrar. Arriba y abajo
# pasan de una a otra UNA POR VUELTA del bucle, y ese bucle repinta la vista de
# cerca, que con la cache va muchisimo mas rapido que en la cinta.
#
# Medido sobre el replay de Ruben con la ROM de la WIME04: 32 lecturas del
# mando por segundo. El tester: "va a toda putisima hostia". MI_PREBATALLA lo
# limita a una cada PASO_EN_LA_PREBATALLA cuadros.
#
# Aqui se cuentan los CAMBIOS DE UNIDAD de verdad -las llamadas a
# SIGUIENTE_DE_LAS_TUYAS (0x7573) y ANTERIOR_DE_LAS_TUYAS (0x757C)-, no las
# lecturas del mando: con el limite puesto el mando se sigue leyendo igual y lo
# que tiene que bajar son los pasos.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 #       -script tools/omsx_prebatalla.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/prebatalla.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
proc b {a} { return [debug read memory $a] }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::ABAJO {8 0x40}
set ::SEGUNDOS 3.0
set ::pasos 0
set ::lecturas 0
set ::midiendo 0
set ::hecho 0

debug set_bp 0x7573 {} { if {$::midiendo} { incr ::pasos } }
debug set_bp 0x757C {} { if {$::midiendo} { incr ::pasos } }
debug set_bp 0x7564 {} { if {$::midiendo} { incr ::lecturas } }

proc remata {} {
    keymatrixup {*}$::ABAJO
    set ::midiendo 0
    say "-------------------------------------------------------------"
    say [format "lecturas del mando: %d en %.1f s = %.0f/s"              $::lecturas $::SEGUNDOS [expr {$::lecturas / $::SEGUNDOS}]]
    say [format "CAMBIOS DE UNIDAD:  %d en %.1f s = %.2f/s"              $::pasos $::SEGUNDOS [expr {$::pasos / $::SEGUNDOS}]]
    set f [open "$OUT/prebatalla.txt" w]
    puts $f "lecturas $::lecturas"
    puts $f "pasos $::pasos"
    puts $f "segundos $::SEGUNDOS"
    close $f
    say "FIN"
    after realtime 1 { exit 0 }
}

proc reloj_en_marcha {} {
    debug write memory 0x7F66 0x19
    debug write memory 0x7F67 0x67
    debug write memory 0x7F6C 0x1B
    debug write memory 0x7F6D 0x83
}
proc en_marcha {} {
    reloj_en_marcha
    for {set n 0} {$n < 10} {incr n} {
        debug write memory [expr {0xB900 + $n}] [expr {[b [expr {0xB900 + $n}]] & 0x7F}]
        debug write memory [expr {0xBA00 + $n}] [expr {[b [expr {0xBA00 + $n}]] & 0x7F}]
        debug write memory [expr {0xBB00 + $n}] 0x66
        debug write memory [expr {0xBC00 + $n}] 0x3D
    }
    say "partida en marcha, destino (0x66,0x3D) para las diez primeras unidades"
}
set ::fuego 0
proc fuego {} {
    if {$::fuego} { return }
    set ::fuego 1
    keymatrixdown {*}$::ESPACIO
    after time 0.4 { keymatrixup {*}$::ESPACIO ; after time 0.4 { set ::fuego 0 } }
}


# 0x752C: se entra en la pantalla de pre-batalla. Se deja asentar y se
# mantiene ABAJO pulsado.
debug set_bp 0x752C {} {
    if {!$::hecho} {
        set ::hecho 1
        say "PANTALLA DE PRE-BATALLA (modo 0x17)"
        after time 1.0 {
            set ::midiendo 1
            keymatrixdown {*}$::ABAJO
            after time $::SEGUNDOS remata
        }
    }
}
debug set_bp 0x7564 {} {}
debug set_bp 0x7FD5 {} { reg PC 0x7FD8 }
debug set_bp 0x81E7 {} { reloj_en_marcha }

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 { type "2" ; after time 2 { type "0" ; after time 3 { en_marcha } } }
}]

after realtime 240 { say "TIMEOUT sin llegar a la pre-batalla" ; exit 1 }
