# LA VISTA DE CERCA, VOLCADA EN INSTANTES QUE SE REPITEN IGUAL EN DOS ROMs
#
# Sirve para cotejar POR PIXEL la ROM con la vista por tabla de nombres contra
# la ROM de antes. Las dos VRAM ya no se parecen byte a byte -una lleva bitmap
# y la otra nombres-, asi que lo que se compara es lo que el VDP ensena
# (tools/render_vram.py), y para eso los volcados tienen que salir en el MISMO
# estado del juego en las dos ROMs. Por reloj no vale: la vista va a distinta
# velocidad en cada una y el cursor parpadea por vuelta. Asi que todo se cuenta
# POR VUELTAS del bucle de la vista -breakpoint en 0x721F, la instruccion que
# sigue a la lectura del mando-, y las teclas se pulsan y se sueltan tambien
# por vuelta. Hasta entrar en la vista las dos ROMs corren el mismo codigo al
# mismo ritmo, y en la vista el estado del juego no avanza: solo cuenta lo que
# se pulsa.
#
# Pantalla APAGADA desde antes de la primera vuelta de la vista: con la
# pantalla encendida el VDP pierde bytes cuando se le escribe seguido (ver
# INVESTIGACION.md), y la ROM nueva sube sus patrones UNA vez, asi que lo que
# se perdiera no se repintaria nunca. Con WAR_PANTALLA=encendida no se apaga:
# es la pasada que comprueba que a la ROM nueva no se le cae ningun byte.
#
# Instantes: vista_a (vuelta 3), vista_b (vuelta 6, con el cursor una casilla
# a la derecha), menu_r (el menu de entrega del Anillo, que es de bitmap),
# vista_c (vuelta 9, de vuelta del menu) y mapa (el mapa general, al salir con
# fuego). Si al salir hubiera una unidad bajo el cursor saldria el menu de
# ordenes en vez del mapa: entonces se vuelca menu_ordenes y, de vuelta a la
# vista, vista_d.
#
#   WAR_OUT=<dir> [WAR_PANTALLA=encendida] \
#       openmsx -machine <maq> -carta <rom> -romtype ascii16 -script tools/omsx_coteja_vista.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/coteja_vista.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
set ::APAGAR [expr {![info exists ::env(WAR_PANTALLA)] || $::env(WAR_PANTALLA) ne "encendida"}]
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

# La VRAM, los registros y la RAM de 0x4000 a 0x6151: el bitmap y los
# atributos del ZX, la pila y la pantalla de caracteres (0x5E00, 850 bytes).
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
    puts -nonewline $f [debug read_block memory 0x4000 0x2152]
    close $f
    say "volcado $nombre en la vuelta $::k  (VDP [regs_vdp])"
}

set ::ESPACIO {8 0x01}
set ::DERECHA {8 0x80}
set ::R {4 0x80}
proc abajo {t} { keymatrixdown {*}$t }
proc arriba {t} { keymatrixup {*}$t }

set ::k 0
set ::en_menu 0
set ::eligiendo 0
set ::tras_salir 0
set ::entrar 0
set ::apagada 0

# La entrada a la vista: la pantalla se apaga (una vez) y se suelta el fuego,
# que ENTRA_EN_LA_VISTA espera a que se suelte.
debug set_bp 0x71F1 {} {
    if {$::APAGAR && !$::apagada} {
        debug write "VDP regs" 1 0xA0
        set ::apagada 1
        say "en 0x71F1: pantalla apagada (R1 = 0xA0, las interrupciones siguen)"
    }
    arriba $::ESPACIO
}
# Cada ESPERA_A_SOLTAR_FUEGO: se suelta.
debug set_bp 0x7599 {} { arriba $::ESPACIO }

# Una vuelta de la vista: 0x721F, justo despues de leer el mando.
proc vuelta {} {
    incr ::k
    set ::en_menu 0
    switch $::k {
        3 { vuelca vista_a; abajo $::DERECHA }
        4 { arriba $::DERECHA }
        6 { vuelca vista_b; abajo $::R }
        9 { vuelca vista_c; abajo $::ESPACIO; set ::tras_salir 1 }
        12 { vuelca vista_d; say "FIN"; exit 0 }
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

after time 240 { say "TIMEOUT en la vuelta $::k"; exit 1 }
