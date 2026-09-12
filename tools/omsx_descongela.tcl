# EL MAPA NO ESTA COLGADO: EL RELOJ ARRANCA PARADO, Y HAY QUE ARRANCARLO
#
# Al dibujar el mapa, DIBUJA_EL_MAPA (0x8166) desvia DOS `call` del bucle de
# partida al retardo de 0x8274:
#
#     0x7F66 (el operando de `call MUEVE_LA_SIGUIENTE_UNIDAD`)  -> 0x8274
#     0x7F6C (el operando de `call RELOJ`)                      -> 0x8274
#
# Mientras sigan asi, el calendario no avanza y las unidades no se mueven: el
# mapa se queda quieto para siempre. Los devuelve a su sitio PULSA_ABAJO_DEL_TODO
# (0x81EA), que es lo que ocurre al DISPARAR sobre el panel de abajo:
#
#     0x7F66 -> 0x6719 (MUEVE_LA_SIGUIENTE_UNIDAD)
#     0x7F6C -> 0x831B (RELOJ)
#
# Y hay una segunda trampa: el mando por defecto (0x96F0) es CERO, o sea el
# JOYSTICK. Con el teclado no se mueve nada hasta que en el menu se pulsa 2
# (cursores) o 3 (teclas redefinidas).
#
# Esta sonda lo comprueba de punta a punta, y lleva contadores en los cuatro
# sitios por donde tiene que pasar el disparo, para que un fallo diga DONDE se
# quedo y no solo que no funciono.
#
#   WAR_OUT=<dir> [WAR_COLUMNA=<pixeles>] openmsx -machine <maq> \
#       -carta <rom> -romtype ascii16 -script tools/omsx_descongela.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/descongela.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
catch {say "cartucho: [carta]"}

# La fila 8 de la matriz: bit 0 espacio, 4 izquierda, 5 arriba, 6 abajo, 7 derecha.
set ::ABAJO     0x40
set ::DERECHA   0x80
set ::ESPACIO   0x01

proc pal {a} { return [expr {[debug read memory $a] + 256 * [debug read memory [expr {$a + 1}]]}] }

proc estado {etiqueta} {
    say [format "%-26s  0x96F0=%d  0x7F66=0x%04X  0x7F6C=0x%04X  cursor=(%d,%d)  ZX=0x%04X" \
             $etiqueta [debug read memory 0x96F0] [pal 0x7F66] [pal 0x7F6C] \
             [debug read memory 0x6543] [debug read memory 0x6544] [pal 0x64DA]]
}

# Los cuatro puntos del camino del disparo.
set ::paso [dict create disparo 0 panel 0 abajo 0 cinta 0]
proc pon_bps {} {
    debug set_bp 0x7F8B {} { dict incr ::paso disparo }
    debug set_bp 0x7FFF {} { dict incr ::paso panel }
    debug set_bp 0x81EA {} { dict incr ::paso abajo }
    debug set_bp 0x800B {} { dict incr ::paso cinta }
}
proc pasos {etiqueta} {
    say "$etiqueta: disparo leido [dict get $::paso disparo], sobre panel [dict get $::paso panel], panel de ABAJO [dict get $::paso abajo], menu de cinta [dict get $::paso cinta]"
    set ::paso [dict create disparo 0 panel 0 abajo 0 cinta 0]
}

# Cuantos estados distintos toma la VRAM: es lo que dice si la pantalla se mueve.
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
    say "$etiqueta: la VRAM toma [dict size $::vistos] estados distintos en $::tomas tomas"
    set ::vistos [dict create]
    set ::tomas 0
}

# Se dispara varias veces, subiendo el cursor una fila de celda entre intento e
# intento, porque el panel no ocupa toda la franja de abajo.
# Cuanto se deja rodar con el reloj ya en marcha: WAR_SOAK segundos.
set ::SOAK [expr {[info exists ::env(WAR_SOAK)] ? $::env(WAR_SOAK) : 5}]
set ::intentos 8
proc dispara {} {
    keymatrixdown 8 $::ESPACIO
    after time 0.4 { suelta_y_mira }
}
proc suelta_y_mira {} {
    keymatrixup 8 $::ESPACIO
    estado "tras disparar"
    pasos "  camino del disparo"
    if {[pal 0x7F6C] == 0x831B} {
        say "EL RELOJ HA ARRANCADO: 0x7F6C ya apunta a RELOJ (0x831B)"
        set ::vistos [dict create]
        set ::tomas 0
        after time $::SOAK {
            set ::mirando 0
            cuenta "$::SOAK segundos CON el reloj en marcha"
            estado "al final"
            say "OK"
            exit 0
        }
        return
    }
    incr ::intentos -1
    if {$::intentos <= 0} {
        set ::mirando 0
        say "FALLA: tras varios disparos el reloj sigue parado"
        exit 1
    }
    say "no fue: el cursor se mueve una celda a la DERECHA y se repite"
    keymatrixdown 8 $::DERECHA
    after time 0.35 {
        keymatrixup 8 $::DERECHA
        after time 0.3 { dispara }
    }
}

proc en_el_mapa {} {
    estado "recien entrado al mapa"
    set ::mirando 1
    mira
    after time 5 {
        cuenta "cinco segundos SIN tocar nada"
        pasos "  en esos cinco segundos"
        say "se mantiene ABAJO para llevar el cursor al panel de abajo"
        keymatrixdown 8 $::ABAJO
        after time 4 {
            keymatrixup 8 $::ABAJO
            estado "con el cursor abajo"
            say "se dispara (ESPACIO) sobre el panel"
            dispara
        }
    }
}

# El mismo recorrido se puede hacer sobre la CINTA, restaurando el estado que
# guardo tools/omsx_arranque.tcl al llegar a 0x5E00: es la unica forma de decir
# si lo que se ve es del juego o del cartucho.
proc el_menu {} {
    after time 2 {
        estado "en el menu, antes de elegir"
        say "se pulsa 2: el mando pasa a ser los CURSORES"
        type "2"
        after time 2 {
            estado "en el menu, tras el 2"
            say "se pulsa 0: empieza la partida"
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                say "PC en 0x6A47: la partida ha arrancado"
                debug remove_bp $::bp_mapa
                after time 1 { en_el_mapa }
            }]
        }
    }
}

if {[info exists ::env(WAR_ESTADO)]} {
    set r [catch {
        set nuevo [restore_machine $::env(WAR_ESTADO)]
        set viejo [machine]
        if {$viejo ne ""} { delete_machine $viejo }
        activate_machine $nuevo
    } msg]
    say "estado de la CINTA restaurado rc=$r: $msg"
    if {$r} { exit 1 }
    say "maquina del estado: [machine_info config_name]"
    pon_bps
    el_menu
} else {
    set ::bp_menu [debug set_bp 0x5E00 {} {
        say "PC en 0x5E00: el menu"
        debug remove_bp $::bp_menu
        pon_bps
        el_menu
    }]
}

after time 180 { say "TIMEOUT"; exit 1 }
