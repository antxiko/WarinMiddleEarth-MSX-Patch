# ¿CABE EL MAPA EMPAQUETADO, Y VUELVE ENTERO?
#
# La prueba del arreglo de la tercera tanda, con el mapa de Ruben metido a
# mano: su terreno de la primera hora con las 1048 marcas de bando que tenia
# al final de la partida. Asi no hace falta jugar hasta alli ni esperar a que
# el juego recentre: se le mete el mapa, se le manda por COMPRIME_EL_MAPA
# (0x9394) y luego por DESCOMPRIME_EL_MAPA (0x9366), que es exactamente lo que
# hace al entrar y salir de una batalla.
#
# Mide las dos cosas que importan:
#   - lo que mide el paquete (DE al llegar a 0x93A7) contra el 0x16EC que el
#     codigo copia de vuelta: si se pasa, la cola del mapa se pierde;
#   - y si el mapa vuelve IGUAL celda a celda. Con el arreglo tiene que volver
#     igual salvo el bit 5, que es justo lo que se quita para que quepa.
#
#   WAR_MAPA=<mapa.bin> WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> \
#       -romtype ascii16 -script tools/omsx_cabe_el_mapa.tcl
set MAPA $::env(WAR_MAPA)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/cabe.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off
set f [open $MAPA r]; fconfigure $f -translation binary
set ::mapa [read $f]; close $f
di "mapa de prueba: [string length $::mapa] bytes"
set ::fase 0

proc marcas {d} {
    set n 0
    for {set i 0} {$i<0x33CC} {incr i} { if {[scan [string index $d $i] %c] & 0x20} {incr n} }
    return $n
}

debug set_bp 0x7F57 {} {
    if {$::fase == 0} {
        set ::fase 1
        debug write_block memory 0xCC00 $::mapa
        set ::antes [debug read_block memory 0xCC00 0x33CC]
        di "metido el mapa: [marcas $::antes] casillas con el bit 5"
        reg PC 0x9394
    }
}
debug set_bp 0x93A7 {} {
    if {$::fase == 1} {
        set ::fase 2
        set n [expr {[reg DE] - 0x4000}]
        di "EMPAQUETADO: [format 0x%04X $n] ($n B) contra los [format 0x%04X 0x16EC] (5868) que copia 0x93A7 -> [expr {$n - 0x16EC}]"
        # El liston no es el 0x16EC pelado: el mapa LIMPIO ya da 0x16EE (5870),
        # o sea que al original le sobran dos bytes y pierde con ellos la ultima
        # pareja, que es borde y no se ve. Lo que hay que igualar es ESO.
        set base [expr {[info exists ::env(WAR_BASE)] ? $::env(WAR_BASE) : 5870}]
        if {$n > $base} {
            di "   ***  SE PASA [expr {$n - $base}] B por encima del mapa limpio ($base): se come mapa de verdad  ***"
        } else {
            di "   como el mapa limpio ($base B): no se pierde nada que se vea"
        }
    }
}
debug set_bp 0x93AE {} { if {$::fase == 2} { set ::fase 3; di "comprimido; mando a DESCOMPRIME"; reg PC 0x9366 } }
# El `ret z` de 0x938C es la SALIDA de DESCOMPRIME, y solo vuelve cuando el
# contador de 0x33CD llega a cero. Ahi es donde hay que mirar el mapa: esperar
# un rato no vale, porque tras volver el juego sigue y entra otra vez.
debug set_bp 0x938C {} {
    if {$::fase == 3 && ([reg F] & 0x40)} {
        set ::fase 4
        set ::despues [debug read_block memory 0xCC00 0x33CC]
    }
}

proc remata {} {
    global OUT
    if {$::fase < 4} { after time 0.2 remata; return }
    if {1} {
        set d $::despues
        set dif 0; set sin5 0; set colmin 999; set colmax -1; set pri ""
        for {set i 0} {$i<0x33CC} {incr i} {
            set a [scan [string index $::antes $i] %c]
            set b [scan [string index $d $i] %c]
            if {$a != $b} { incr dif }
            if {($a & 0xDF) != ($b & 0xDF)} {
                incr sin5
                set c [expr {$i/102-1}]
                if {$c < $colmin} {set colmin $c}
                if {$c > $colmax} {set colmax $c}
                if {$pri eq ""} { set pri [format "1a en 0x%04X col=%d %02X->%02X" [expr {0xCC00+$i}] $c $a $b] }
            }
        }
        set f [open "$OUT/mapa_vuelto.bin" w]; fconfigure $f -translation binary
        puts -nonewline $f $d; close $f
        di "VUELTA: celdas distintas=$dif ; SIN contar el bit 5=$sin5 (col $colmin..$colmax) $pri"
        di "        marcas despues: [marcas $d]"
        if {$sin5 == 0} { di "OK: el mapa vuelve entero" } else { di "MAL: el mapa PIERDE $sin5 celdas" }
        di FIN
        exit 0
    }
}
after time 12 { type "1" }
after time 14 { type "0" }
after time 20 remata
after time 200 { di "TIMEOUT fase=$::fase"; exit 1 }
