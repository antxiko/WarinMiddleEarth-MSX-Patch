# ¿EL JUEGO PINTA EN EL MAPA, O NO PINTA?
#
# Los volcados de VRAM separados por segundos no valen para decidirlo: el mapa
# tiene un mensaje que rueda en bucle, asi que dos volcados distantes pueden
# salir iguales por coincidencia de fase. Esto lo mide de las dos maneras que
# no se pueden confundir:
#
#   1. CUANTAS VECES se escribe el puerto de datos del VDP (0x98) por segundo.
#      Si el juego pinta, son miles; si no pinta, cero.
#   2. Cuantos estados DISTINTOS toma la VRAM muestreandola cada 0.1 s.
#
# Y luego pulsa las teclas del juego y repite la cuenta: si al pulsar R sube el
# numero de escrituras, el juego responde.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_pinta_o_no.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/pinta.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
say "cartucho: [carta]"

set ::escrituras98 0
set ::escrituras99 0
debug set_watchpoint write_io 0x98 {} { incr ::escrituras98 }
debug set_watchpoint write_io 0x99 {} { incr ::escrituras99 }

set ::vistos [dict create]
set ::tomas 0
set ::mirando 0
proc mira {} {
    if {!$::mirando} { return }
    dict set ::vistos [debug read_block VRAM 0 0x4000] 1
    incr ::tomas
    after time 0.1 mira
}

proc cuenta {etiqueta} {
    say [format "%-22s  0x98: %7d escrituras   0x99: %6d   VRAM: %d estados de %d tomas" \
             $etiqueta $::escrituras98 $::escrituras99 [dict size $::vistos] $::tomas]
    set ::escrituras98 0
    set ::escrituras99 0
    set ::vistos [dict create]
    set ::tomas 0
}

proc en_el_mapa {} {
    say "=============== EN EL MAPA ==============="
    set ::mirando 1
    mira
    cuenta "arranque (se descarta)"
    after time 5 {
        cuenta "5 s SIN TOCAR NADA"
        after time 5 {
            cuenta "otros 5 s sin tocar"
            say "se pulsa R (menu del juego)"
            type "r"
            after time 3 {
                cuenta "3 s tras la R"
                say "se pulsa ESPACIO"
                type " "
                after time 3 {
                    cuenta "3 s tras el espacio"
                    say "se pulsa 1 (pausa)"
                    type "1"
                    after time 3 {
                        cuenta "3 s tras el 1"
                        say "FIN"
                        exit 0
                    }
                }
            }
        }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 3 {
        cuenta "3 s en el menu"
        say "se pulsa 0 para empezar la partida"
        type "0"
        set ::bp_mapa [debug set_bp 0x6A47 {} {
            say "PC en 0x6A47: la partida ha arrancado"
            debug remove_bp $::bp_mapa
            after time 1 { en_el_mapa }
        }]
    }
}]

after time 90 { say "TIMEOUT"; exit 1 }
