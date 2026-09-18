# ¿DE QUE COLOR ES EL FONDO DE UNA BATALLA, Y QUIEN LO PONE?
#
# Para poder pintarlo segun el terreno hay que saber primero QUIEN manda en el
# color de las 16 filas centrales de la pantalla. Leyendo el listado solo se ve
# esto en el montaje (0x9021-0x904B):
#
#   0x9394  COMPRIME_EL_MAPA pone el atributo 0x09 en las 768 celdas
#   0x9037  las dos primeras filas, a 0x46
#   0x9043  las seis ultimas, a 0x00
#
# o sea que las centrales se quedarian en 0x09, que es tinta azul sobre papel
# azul y NO PUEDE ser lo que se ve. Asi que se mira una batalla de verdad:
#
#   fondo.png       la pantalla, del emulador
#   atributos.bin   los 768 de 0x5800: lo que el juego cree que hay
#   color.bin       la tabla de color de la VRAM (0x2000): lo que el VDP pinta
#   fondo.txt       el terreno de la batalla (0x8DEA), su byte de mapa (0x8DCD)
#                   y un punto de observacion: QUIEN escribio los atributos del
#                   tablero, con su PC
#
# La partida se arranca como tools/omsx_cursor_batalla.tcl: menu, dos, cero, el
# reloj en marcha y destino al sur para las diez primeras unidades, que es lo
# que provoca encuentros.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_fondo_batalla.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/fondo_batalla.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
proc b {a} { return [debug read memory $a] }

# El renderer va encendido: se quiere la pantalla tal como la compone el VDP.
catch {set renderer SDLGL-PP}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::en_batalla 0
set ::hecho 0

# Con WAR_TERRENO puesto se le PLANTA ese terreno a la batalla, escribiendo
# 0x8DEA justo antes de que COMPRIME_EL_MAPA elija el color. Hace falta para
# comprobar el cambio: las batallas caen casi siempre en llano -el 47 % del
# mapa-, y una batalla verde en un terreno verde no probaria nada.
#
# Lo que se fuerza es el TERRENO, no el color: quien elige el color sigue
# siendo MI_FONDO leyendo ese byte, que es justo lo que se quiere comprobar.
set ::TERRENO -1
if {[info exists ::env(WAR_TERRENO)]} { set ::TERRENO [expr {$::env(WAR_TERRENO)}] }

# Los atributos del TABLERO son las filas 2..17, o sea 0x5840-0x5A3F. Quien
# escriba ahi queda anotado con su PC, que es lo que se busca.
set ::escritores {}

# Y QUIEN ESCRIBE LA VRAM: cada `out (0x98)` se cuenta por PC. Es lo unico que
# dice de verdad por donde se esta subiendo el tablero, sin suponer nada. Con
# WAR_PUERTO=1 se enciende; va aparte porque cuesta caro (son miles).
set ::porpc [dict create]
if {[info exists ::env(WAR_PUERTO)]} {
    debug set_watchpoint write_io 0x98 {} {
        if {$::en_batalla} {
            set pc [format 0x%04X [reg PC]]
            dict incr ::porpc $pc
        }
    }
}

proc guarda {nombre datos} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f $datos
    close $f
}

proc vuelca {} {
    global OUT
    if {$::hecho} { return }
    set ::hecho 1
    guarda "atributos.bin" [debug read_block memory 0x5800 0x300]
    guarda "color.bin" [debug read_block VRAM 0x2000 0x1800]
    # Y LO QUE DE VERDAD IMPORTA para saber si se pierden bytes: el bitmap que
    # el juego CREE que hay (0x4000, su pantalla del Spectrum emulada) y el que
    # el VDP tiene de verdad (la tabla de patrones). Si no son el mismo, es que
    # alguna escritura se cayo por ir mas rapido de lo que el TMS9918 admite.
    guarda "bitmap.bin" [debug read_block memory 0x4000 0x1800]
    guarda "patrones.bin" [debug read_block VRAM 0 0x1800]
    set f [open "$OUT/fondo.txt" w]
    puts $f "terreno [b 0x8DEA]"
    puts $f "byte_de_mapa [b 0x8DCD]"
    puts $f "casilla [b 0x8F78] [b 0x8F79]"
    puts $f "atributo_centro [debug read memory [expr {0x5800 + 12*32 + 16}]]"
    puts $f "escritores_de_la_VRAM"
    foreach {pc n} [dict get [list {*}$::porpc]] { puts $f "  $pc  $n escrituras" }
    puts $f "escritores"
    foreach e [lsort -unique $::escritores] { puts $f "  $e" }
    close $f
    say "volcado: terreno [b 0x8DEA], atributo del centro del tablero [format 0x%02X [debug read memory [expr {0x5800 + 12*32 + 16}]]]"
    say "quien escribio los atributos del tablero: [lsort -unique $::escritores]"
    after realtime 2 { screenshot -raw "$OUT/fondo.png" ; say "FIN" ; after realtime 1 { exit 0 } }
}

debug set_watchpoint write_mem {0x5840 0x5A3F} {} {
    if {$::en_batalla && [llength $::escritores] < 40} {
        lappend ::escritores [format "PC=0x%04X" [reg PC]]
    }
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

debug set_bp 0x9021 {} {
    set ::en_batalla 1
    set ::escritores {}
    say "BATALLA en la casilla [b 0x8F78],[b 0x8F79]"
}
# 0x9032 es el `call COMPRIME_EL_MAPA`: aqui el terreno ya esta en 0x8DEA y el
# color aun no se ha elegido.
debug set_bp 0x9032 {} {
    if {$::TERRENO >= 0} {
        say "  terreno [b 0x8DEA] -> se le planta el $::TERRENO"
        debug write memory 0x8DEA $::TERRENO
    }
}
# 0x9141 es lo ultimo del montaje: el cursor ya esta en el centro y el tablero
# pintado. Se deja correr un poco para que se dibujen las figuras y se vuelca.
debug set_bp 0x9141 {} {
    if {!$::hecho} { after time 1.5 { if {$::en_batalla} { vuelca } } }
}
debug set_bp 0x91D1 {} { set ::en_batalla 0 ; say "  se acabo la batalla" }
debug set_bp 0x7564 {} { fuego }
debug set_bp 0x9264 {} { fuego }
debug set_bp 0x81E7 {} { reloj_en_marcha }
debug set_bp 0x7FD5 {} { reg PC 0x7FD8 }

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 { type "2" ; after time 2 { type "0" ; after time 3 { en_marcha } } }
}]

after realtime 300 { say "TIMEOUT sin llegar a una batalla" ; exit 1 }
