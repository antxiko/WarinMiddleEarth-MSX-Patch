# LA MARCA DE LAS UNIDADES EN EL MAPA GENERAL
#
# Vuelca lo que hace falta para comprobar que el dibujo de 8x8 que MI_MARCAS
# le estampa a la celda de cada unidad se PONE donde toca y, sobre todo, que
# se BORRA cuando la unidad se mueve.
#
# El bucle de partida mueve UNA unidad por vuelta y solo repinta cuando el
# contador de unidad da la vuelta, o sea una vez cada 256. Asi que aqui se
# cuenta por REPINTADOS (0x6AAF), no por vueltas ni por reloj, y se vuelca
# DESPUES de cada uno -en el `ret` de 0x6AF4-, que es cuando la pantalla ya
# esta como el jugador la ve:
#
#   <n>.ram     RAM 0x4000-0x5AFF: el lienzo del Spectrum y sus 768 atributos
#   <n>.vram    los 16 KB de VRAM
#   <n>.txt     el atributo con el que se marca (0x6AE1) y la cuenta de marcas
#               que MI_MARCAS lleva apuntada, para cotejarla con la de verdad
#
# LA PANTALLA SE QUEDA ENCENDIDA, que es como se juega: con ella encendida el
# TMS9918 no admite dos accesos a la VRAM a menos de ~29 ciclos, y si los
# bucles de MI_MARCAS fueran demasiado rapidos se les caerian bytes y las
# celdas marcadas no saldrian clavadas. O sea que este volcado tambien mide el
# ritmo.
#
#   WAR_OUT=<dir> [WAR_REPINTADOS=a,b] openmsx -machine <maq> -carta <rom> \
#       -romtype ascii16 -script tools/omsx_marcas.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/marcas.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set throttle off
say "maquina: [machine_info config_name]"

# Los repintados en los que se vuelca. Hacen falta DOS por lo menos: con uno
# solo no se veria si las marcas viejas se borran, que es lo que se comprueba.
set ::CUALES {2 3}
if {[info exists ::env(WAR_REPINTADOS)]} { set ::CUALES [split $::env(WAR_REPINTADOS) ,] }

# Y LAS UNIDADES SE MUEVEN A MANO, porque solas no se mueven lo bastante.
# Medido: 1.027 vueltas del bucle -cuatro repintados de verdad, sin forzar
# nada- y CERO celdas cambiadas. Al principio de la partida las unidades
# apenas se desplazan, y una celda de caracter son CUATRO casillas de mapa:
# hacen falta meses de juego para que alguna cruce de celda.
#
# Asi que entre el primer volcado y el segundo se le suman ocho casillas a la
# x de unas cuantas unidades, que son dos columnas de caracter. La x de la
# unidad n esta en 0xB900+n y la y en 0xBA00+n: es de donde las lee
# MARCA_UNA_UNIDAD (0x6AC5), columna = x >> 2.
#
# Esto mueve la UNIDAD, no la marca: quien decide donde va la marca sigue
# siendo el juego, y MI_MARCAS se entera por donde quedo el atributo. Lo que
# se comprueba es justo eso: que al cambiar de celda, el dibujo viejo se va.
# Y NO VALE MOVER OCHO CUALESQUIERA: probado, las ocho primeras estaban en la
# MISMA celda y ahi seguian otras, asi que la celda no se quedo vacia y el
# borrado no llego a ejercitarse (19 -> 20 celdas: una de mas, ninguna de
# menos). Hay que VACIAR una celda entera, o sea mover TODAS las unidades que
# comparten una.
set ::EMPUJE 8

# Las unidades que pinta el bucle de 0x6AE3: de la 0 a la 0x77, saltandose la
# 0x16 y la 0x17. La x de la unidad n esta en 0xB900+n y la y en 0xBA00+n, y
# MARCA_UNA_UNIDAD (0x6AC5) saca de ahi columna = x >> 2 y fila = (y - 4) >> 2.
proc celda_de {u} {
    set x [debug read memory [expr {0xB900 + $u}]]
    set y [expr {[debug read memory [expr {0xBA00 + $u}]] & 0x7F}]
    return [list [expr {($y - 4) >> 2}] [expr {$x >> 2}]]
}

proc vacia_una_celda {} {
    # Se agrupan las unidades por celda y se elige la que menos tenga: es la
    # mas barata de vaciar y la que deja el cambio mas limpio.
    array set quien {}
    for {set u 0} {$u < 0x78} {incr u} {
        if {$u == 0x16 || $u == 0x17} { continue }
        set c [celda_de $u]
        lappend quien($c) $u
    }
    set elegida {}
    foreach c [array names quien] {
        if {$elegida eq {} || [llength $quien($c)] < [llength $quien($elegida)]} {
            set elegida $c
        }
    }
    foreach u $quien($elegida) {
        set x [debug read memory [expr {0xB900 + $u}]]
        debug write memory [expr {0xB900 + $u}] [expr {($x + $::EMPUJE) & 0xFF}]
    }
    say "celda [lindex $elegida 0],[lindex $elegida 1] vaciada: las unidades $quien($elegida) se van $::EMPUJE casillas a la derecha"
}

# NO SE FUERZA EL REPINTADO. Se penso en forzar el repintado escribiendo el contador
# de unidad (0x671A), y se probo: con 40 vueltas entre repintado y repintado
# el cotejo salio INUTIL, porque una celda de caracter son CUATRO casillas de
# mapa y en 40 vueltas ninguna unidad llega a cruzar de celda. O sea que
# acortar no valia: hay que dejar correr los 256 de verdad.
# Y ANTES HAY QUE ARRANCAR LA PARTIDA, que si no no se mueve NADIE. Al entrar
# al mapa, 0x81DE-0x81E4 desvia al retardo de 0x8274 los dos `call` del bucle
# de partida -el de mover la unidad siguiente (0x7F65) y el del reloj
# (0x7F6B)-, asi que mientras el jugador no pulsa abajo del todo el juego da
# vueltas sin mover una sola unidad ni avanzar el calendario. Medido: 729.052
# vueltas del bucle y un unico repintado, el de la entrada.
#
# PULSA_ABAJO_DEL_TODO (0x81EA) los devuelve a su sitio, y eso es lo que se
# hace aqui: escribir los dos operandos, exactamente lo que escribe 0x81F4.
# 0x7F66 es el operando del `call` de 0x7F65 y 0x7F6C el del de 0x7F6B.
set ::LLAMA_MUEVE 0x7F66
set ::MUEVE 0x6719
set ::LLAMA_RELOJ 0x7F6C
set ::RELOJ 0x831B
set ::arrancada 0

proc arranca {} {
    debug write memory $::LLAMA_MUEVE [expr {$::MUEVE & 0xFF}]
    debug write memory [expr {$::LLAMA_MUEVE + 1}] [expr {$::MUEVE >> 8}]
    debug write memory $::LLAMA_RELOJ [expr {$::RELOJ & 0xFF}]
    debug write memory [expr {$::LLAMA_RELOJ + 1}] [expr {$::RELOJ >> 8}]
    set ::arrancada 1
    say "partida arrancada: los dos call del bucle vuelven a 0x6719 y 0x831B"
}

proc guarda {nombre datos} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f $datos
    close $f
}

proc vuelca {n} {
    global OUT
    guarda "$n.ram" [debug read_block memory 0x4000 0x1B00]
    guarda "$n.vram" [debug read_block VRAM 0 0x4000]
    set f [open "$OUT/$n.txt" w]
    puts $f "atributo [debug read memory 0x6AE1]"
    puts $f "marcas [debug read memory $::MARCAS_N]"
    puts $f "regs [format %02X [debug read {VDP regs} 1]]"
    close $f
    say "repintado $n: atributo [format %02X [debug read memory 0x6AE1]], [debug read memory $::MARCAS_N] marcas apuntadas"
}

# MARCAS_N lo pasa el Makefile: sale de work/unificada/nombres.sym, que es
# quien sabe donde acabo la tabla. Aqui no se adivina.
set ::MARCAS_N [expr {$::env(WAR_MARCAS_N)}]
say [format "MARCAS_N en 0x%04X" $::MARCAS_N]

set ::n 0
set ::k 0
set ::desde 0
debug set_bp 0x6AF4 {} {
    incr ::n
    say "repintado $::n en la vuelta $::k"
    if {[lsearch -exact $::CUALES $::n] >= 0} { vuelca $::n }
    if {$::n == [lindex $::CUALES end]} { say "FIN"; exit 0 }
    if {$::n == [lindex $::CUALES 0]} { vacia_una_celda }
    set ::desde $::k
}

# Una vuelta del bucle de partida: lo unico que se hace aqui es arrancar la
# partida en cuanto el mapa esta puesto. De ahi en adelante el juego corre
# solo y repinta cuando le toca, cada 256 vueltas.
debug set_bp 0x7F5A {} {
    incr ::k
    if {!$::arrancada && $::k > 2} { arranca }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 { type "2"; after time 2 { type "0" } }
}]

after realtime 300 { say "TIMEOUT en el repintado $::n, vuelta $::k"; exit 1 }
