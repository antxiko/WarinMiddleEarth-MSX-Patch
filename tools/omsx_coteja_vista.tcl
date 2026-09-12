# LA VISTA DE CERCA, VOLCADA EN INSTANTES QUE SE REPITEN IGUAL EN DOS ROMs
#
# Sirve para cotejar la ROM con la vista por tabla de nombres y el cursor como
# sprite contra la ROM de antes. Las dos VRAM ya no se parecen byte a byte -una
# lleva bitmap y la otra nombres- y, desde el cursor como sprite, ni siquiera
# la pantalla de caracteres de 0x5E00 es la misma: en la nueva la ventana del
# trozo se queda quieta mientras el cursor se mueve dentro. Asi que la sonda
# vuelca lo que tools/coteja_vista.py necesita para reconstruir lo que la
# nueva TIENE que ensenar a partir de lo que ensena la vieja:
#
#   - en CADA vuelta del bucle de la vista, el trozo PURO: la pantalla de
#     caracteres justo despues de PINTA_LA_VISTA_DE_CERCA (0x71FC), antes de
#     que se dibujen las ventanas; con la posicion del cursor (HL), el modo
#     (0x71CF) y si en esa vuelta se ejecuto DIBUJA_EL_TROZO_DE_MAPA (0x7643);
#   - en los instantes elegidos, el estado entero: la VRAM, los registros del
#     VDP y los 64 KB de RAM, tras subir la pantalla (0x721F).
#
# Todo se cuenta POR VUELTAS del bucle -no por reloj: las dos ROMs van a
# distinta velocidad- y las teclas se pulsan y se sueltan tambien por vuelta.
# Hasta entrar en la vista las dos ROMs corren el mismo codigo al mismo ritmo,
# y en la vista el estado del juego no avanza: solo cuenta lo que se pulsa.
#
# Pantalla APAGADA desde antes de la primera vuelta de la vista: con la
# pantalla encendida el VDP pierde bytes cuando se le escribe seguido (ver
# INVESTIGACION.md), y la ROM nueva sube sus patrones UNA vez. Se apaga
# quitando SOLO el bit 6 de R1, porque la ROM nueva lleva en R1 el tamano de
# sprite (bit 1) y hay que conservarlo. Con WAR_PANTALLA=encendida no se apaga:
# es la pasada que comprueba que a la ROM nueva no se le cae ningun byte.
#
# El recorrido, pensado para que el cursor salga de la ventana fija por los
# tres lados que caben (margen 3: 10 columnas y 7 filas de recorrido):
#
#   vista_a  vuelta 3   recien entrado
#   vista_b  vuelta 6   una casilla a la derecha (dentro de la ventana)
#   menu_r              el menu de entrega del Anillo, que es de bitmap
#   vista_c  vuelta 9   de vuelta del menu: el trozo se repinta
#   vista_k  vuelta 10  lo mismo, una vuelta despues: la vieja lleva el cursor
#                       ENCENDIDO (parpadea por vuelta: en las pares) y las dos
#                       imagenes tienen que ser identicas, sprite incluido
#   vista_e  vuelta 21  cinco mas a la derecha: la ultima columna que cabe
#   vista_f  vuelta 25  una mas: se sale y se recentra
#   vista_g  vuelta 35  cuatro abajo: la ultima fila que cabe
#   vista_h  vuelta 39  una mas: se recentra
#   vista_i  vuelta 45  dos arriba: la primera fila que cabe
#   vista_j  vuelta 49  una mas: se recentra; y se sale con fuego
#   mapa                el mapa general, de bitmap (o menu_ordenes y vista_d
#                       si habia una unidad bajo el cursor)
#
#   WAR_OUT=<dir> [WAR_PANTALLA=encendida] [WAR_DIRS=<vista.tcl>] \
#       openmsx -machine <maq> -carta <rom> -romtype ascii16 -script tools/omsx_coteja_vista.tcl
#
# WAR_DIRS es el fichero de direcciones que genera haz_rom.py para la ROM
# nueva (work/musica/vista.tcl): con el, cada vuelta apunta ademas la esquina
# y la validez de la cache, para leerlas en el informe.

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/coteja_vista.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
set VUELTAS [open "$OUT/vueltas.txt" w]
proc apunta {m} { global VUELTAS; puts $VUELTAS $m; flush $VUELTAS }

catch {set renderer none}
set throttle off
set ::APAGAR [expr {![info exists ::env(WAR_PANTALLA)] || $::env(WAR_PANTALLA) ne "encendida"}]
set ::CON_DIRS [expr {[info exists ::env(WAR_DIRS)] && $::env(WAR_DIRS) ne ""}]
if {$::CON_DIRS} { source $::env(WAR_DIRS) }
say "maquina: [machine_info config_name]"
catch {say "cartucho: [carta]"}
say "pantalla: [expr {$::APAGAR ? "se apaga al entrar en la vista" : "ENCENDIDA"}]"

proc regs_vdp {} {
    set out {}
    for {set r 0} {$r < 8} {incr r} {
        lappend out [format %02X [debug read "VDP regs" $r]]
    }
    return [join $out " "]
}

# El estado entero: la VRAM, los registros y los 64 KB de RAM.
proc vuelca {nombre} {
    global OUT
    set f [open "$OUT/$nombre.vram" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block VRAM 0 0x4000]
    close $f
    set f [open "$OUT/$nombre.regs" w]
    puts $f [regs_vdp]
    close $f
    set f [open "$OUT/$nombre.ram" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory 0 0x10000]
    close $f
    apunta "estado $nombre $::k"
    say "volcado $nombre en la vuelta $::k  (VDP [regs_vdp], HL=[format %04X [reg HL]])"
}

# El trozo puro de una vuelta: 0x5E00 tal como lo deja PINTA_LA_VISTA_DE_CERCA.
proc vuelca_trozo {} {
    global OUT
    set f [open "$OUT/trozo_$::k.bin" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory 0x5E00 850]
    close $f
    set extra ""
    if {$::CON_DIRS} {
        set extra [format " esquina %02X%02X valida %d" \
                       [debug read memory $::ESQUINA_H] [debug read memory $::ESQUINA_L] \
                       [debug read memory $::CACHE_VALIDA]]
    }
    apunta [format "vuelta %d hl %04X modo %02X dibujado %d%s" \
                $::k [reg HL] [debug read memory 0x71CF] $::dibujado $extra]
}

set ::ESPACIO {8 0x01}
set ::IZQUIERDA {8 0x10}
set ::ARRIBA {8 0x20}
set ::ABAJO {8 0x40}
set ::DERECHA {8 0x80}
set ::R {4 0x80}
proc abajo {t} { keymatrixdown {*}$t }
proc arriba {t} { keymatrixup {*}$t }

set ::k 0
set ::dibujado 0
set ::en_menu 0
set ::eligiendo 0
set ::tras_salir 0
set ::entrar 0
set ::apagada 0

# La entrada a la vista: la pantalla se apaga (una vez, y solo el bit 6) y se
# suelta el fuego, que ENTRA_EN_LA_VISTA espera a que se suelte.
debug set_bp 0x71F1 {} {
    if {$::APAGAR && !$::apagada} {
        set r1 [debug read "VDP regs" 1]
        debug write "VDP regs" 1 [expr {$r1 & 0xBF}]
        set ::apagada 1
        say [format "en 0x71F1: pantalla apagada (R1 = 0x%02X -> 0x%02X, las interrupciones siguen)" $r1 [expr {$r1 & 0xBF}]]
    }
    arriba $::ESPACIO
}
# Cada ESPERA_A_SOLTAR_FUEGO: se suelta.
debug set_bp 0x7599 {} { arriba $::ESPACIO }

# DIBUJA_EL_TROZO_DE_MAPA: se apunta que en esta vuelta se ha repintado.
debug set_bp 0x7643 {} { set ::dibujado 1 }

# Justo despues de PINTA_LA_VISTA_DE_CERCA: empieza la vuelta k.
debug set_bp 0x71FC {} {
    incr ::k
    vuelca_trozo
    set ::dibujado 0
}

# 0x721F, justo despues de leer el mando: el estado de la vuelta k, y las teclas.
proc pulsa {tecla} { abajo $tecla }
proc suelta {tecla} { arriba $tecla }
proc vuelta {} {
    set ::en_menu 0
    switch $::k {
        3 { vuelca vista_a; pulsa $::DERECHA }
        4 { suelta $::DERECHA }
        6 { vuelca vista_b; pulsa $::R }
        9 { vuelca vista_c }
        10 { vuelca vista_k; pulsa $::DERECHA }
        12 - 14 - 16 - 18 { pulsa $::DERECHA }
        11 - 13 - 15 - 17 - 19 { suelta $::DERECHA }
        21 { vuelca vista_e; }
        22 { pulsa $::DERECHA }
        23 { suelta $::DERECHA }
        25 { vuelca vista_f }
        26 - 28 - 30 - 32 { pulsa $::ABAJO }
        27 - 29 - 31 - 33 { suelta $::ABAJO }
        35 { vuelca vista_g }
        36 { pulsa $::ABAJO }
        37 { suelta $::ABAJO }
        39 { vuelca vista_h }
        40 - 42 { pulsa $::ARRIBA }
        41 - 43 { suelta $::ARRIBA }
        45 { vuelca vista_i }
        46 { pulsa $::ARRIBA }
        47 { suelta $::ARRIBA }
        49 { vuelca vista_j; pulsa $::ESPACIO; set ::tras_salir 1 }
        52 { vuelca vista_d; say "FIN"; exit 0 }
    }
}
debug set_bp 0x721F {} { vuelta }

# ESPERA_MANDO, dentro de LISTA_*: el menu ya esta pintado. Se suelta la R, se
# vuelca y se pulsa fuego, que elige lo marcado (en el de entrega, el que ya
# lleva el Anillo: no cambia nada; en el de ordenes, Vuelve).
debug set_bp 0x6478 {} {
    if {!$::en_menu} {
        set ::en_menu 1
        arriba $::R
        vuelca [expr {$::tras_salir ? "menu_ordenes" : "menu_r"}]
        apunta "menu"
        abajo $::ESPACIO
    }
}
# MANDO_DE_LA_ELECCION: si habia unidad bajo el cursor, fuego la elige.
debug set_bp 0x7758 {} {
    if {!$::eligiendo} { set ::eligiendo 1; abajo $::ESPACIO }
}
# BUCLE_DE_PARTIDA: al principio, para entrar en la vista; al final, el mapa.
debug set_bp 0x7F57 {} {
    if {$::tras_salir} {
        vuelca mapa
        say "FIN"
        exit 0
    }
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
        say "se pulsa 2 (cursores)"
        type "2"
        after time 2 {
            say "se pulsa 0 (empezar)"
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                debug remove_bp $::bp_mapa
                after time 2 { set ::entrar 1 }
            }]
        }
    }
}]

after time 300 { say "TIMEOUT en la vuelta $::k"; exit 1 }
