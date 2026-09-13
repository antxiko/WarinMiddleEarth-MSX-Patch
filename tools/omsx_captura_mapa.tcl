# CAPTURAS DEL MAPA GENERAL, DEL EMULADOR DE VERDAD
#
# Hermana de tools/omsx_captura_vista.tcl, pero para la otra pantalla: el mapa
# general, donde el cursor es el GUANTE. Con el guante como sprite hay que ver
# lo que openMSX pinta de verdad, no lo que una herramienta crea que el VDP
# pinta, asi que el renderer va encendido (SDLGL-PP) y `screenshot` saca la
# ventana.
#
#   mapa.png         recien dibujado el mapa, con el guante donde entra
#   guante.png       despues de moverlo: abajo y a la derecha
#
# Las pulsaciones van por VUELTAS del bucle de partida (breakpoint en 0x7F57),
# no por reloj: con el acelerador quitado una pulsacion de reloj de pared son
# decenas de vueltas.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 -script tools/omsx_captura_mapa.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/captura_mapa.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

set r [catch {set renderer SDLGL-PP} msg]
say "renderer rc=$r: $msg"
set throttle off
say "maquina: [machine_info config_name]"

set ::ABAJO {8 0x40}
set ::DERECHA {8 0x80}
proc abajo {t} { keymatrixdown {*}$t }
proc arriba {t} { keymatrixup {*}$t }

proc captura {nombre} {
    global OUT
    set r [catch {screenshot -raw -doublesize $OUT/$nombre.png} msg]
    say "captura $nombre rc=$r: $msg  (vuelta $::k, cursor [debug read memory 0x6543],[debug read memory 0x6544])"
}

set ::k 0
set ::paso 0
set ::n 0

# Cada vuelta del bucle de partida.
debug set_bp 0x7F57 {} {
    incr ::k
    if {$::k == 3} {
        set throttle on
        after realtime 3 { captura mapa; set ::paso 1; set ::n 0 }
    } elseif {$::paso == 1} {
        incr ::n
        # veinte pasos a la derecha y diez abajo, uno por vuelta
        if {$::n <= 40} {
            if {$::n % 2} { abajo $::DERECHA } else { arriba $::DERECHA }
        } elseif {$::n <= 60} {
            if {$::n % 2} { abajo $::ABAJO } else { arriba $::ABAJO }
        } elseif {$::n == 62} {
            set ::paso 0
            after realtime 3 { captura guante; say "FIN"; exit 0 }
        }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 {
        type "2"
        after time 2 { type "0" }
    }
}]

after realtime 120 { say "TIMEOUT en la vuelta $::k"; exit 1 }
