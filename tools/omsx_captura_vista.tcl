# TRES CAPTURAS DE LA VISTA DE CERCA, DEL EMULADOR DE VERDAD
#
# Los PNG de tools/coteja_vista.py los dibuja tools/render_vram.py a partir de
# la VRAM, o sea que enseñan lo que ESA herramienta cree que el VDP pinta. Para
# el cursor como sprite eso no basta: hay que ver lo que openMSX pinta. Aqui
# el renderer va encendido de verdad (SDLGL-PP) y `screenshot` saca lo que
# hay en la ventana:
#
#   entrada.png      recien entrado en la vista
#   movido.png       dos casillas a la derecha y una abajo: el cursor se ha
#                    movido dentro de la ventana, que sigue quieta
#   recentrado.png   cuatro mas a la derecha: se salio del margen y el trozo
#                    se ha recentrado
#
# Las teclas van por vueltas del bucle (breakpoint en 0x721F) como en la
# sonda del cotejo, porque con el acelerador puesto una pulsacion de reloj de
# pared son decenas de vueltas. Las capturas, con `after realtime` y el
# acelerador PUESTO: con `throttle off` el renderer se salta los cuadros y la
# captura sale negra (ver tools/omsx_captura.tcl).
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 -script tools/omsx_captura_vista.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/captura_vista.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

set r [catch {set renderer SDLGL-PP} msg]
say "renderer rc=$r: $msg"
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::ABAJO {8 0x40}
set ::DERECHA {8 0x80}
proc abajo {t} { keymatrixdown {*}$t }
proc arriba {t} { keymatrixup {*}$t }

proc captura {nombre} {
    global OUT
    set r [catch {screenshot -raw -doublesize $OUT/$nombre.png} msg]
    say "captura $nombre rc=$r: $msg  (vuelta $::k, HL=[format %04X [reg HL]], VDP R1=[format %02X [debug read {VDP regs} 1]])"
}

set ::k 0
set ::paso 0
set ::n 0
set ::entrar 0

debug set_bp 0x71F1 {} { arriba $::ESPACIO }
debug set_bp 0x7599 {} { arriba $::ESPACIO }

# Cada vuelta de la vista, justo despues de leer el mando.
debug set_bp 0x721F {} {
    incr ::k
    if {$::k == 3} {
        set throttle on
        after realtime 3 { captura entrada; set ::paso 1; set ::n 0 }
    } elseif {$::paso == 1} {
        incr ::n
        switch $::n {
            1 - 3 { abajo $::DERECHA }
            2 - 4 { arriba $::DERECHA }
            5 { abajo $::ABAJO }
            6 { arriba $::ABAJO }
            8 { set ::paso 0; after realtime 3 { captura movido; set ::paso 2; set ::n 0 } }
        }
    } elseif {$::paso == 2} {
        incr ::n
        switch $::n {
            1 - 3 - 5 - 7 { abajo $::DERECHA }
            2 - 4 - 6 - 8 { arriba $::DERECHA }
            10 { set ::paso 0; after realtime 3 { captura recentrado; say "FIN"; exit 0 } }
        }
    }
}

debug set_bp 0x7F57 {} {
    if {$::entrar} {
        set ::entrar 0
        say "en el mapa: ESPACIO para entrar a la vista"
        abajo $::ESPACIO
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 {
        type "2"
        after time 2 {
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                debug remove_bp $::bp_mapa
                after time 2 { set ::entrar 1 }
            }]
        }
    }
}]

after realtime 120 { say "TIMEOUT en la vuelta $::k"; exit 1 }
