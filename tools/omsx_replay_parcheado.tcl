# EL REPLAY DE RUBEN, CON Y SIN EL ARREGLO
#
# El .omr lleva dentro el estado de la maquina con la ROM de entonces, asi que
# no se puede reproducir con la ROM nueva. Pero el juego CORRE DESDE LA RAM -el
# cartucho lo vuelca ahi al arrancar-, o sea que el parche se puede meter en la
# RAM al principio del replay y dejarlo correr: a partir de ahi la partida es
# la misma -la misma entrada grabada- pero con el arreglo puesto.
#
# Vuelca la pantalla ZX emulada (0x4000, 0x1B00), la tabla de color (0x0200) y
# el mapa (0xCC00), para dibujarlos con tools/render_zx.py.
#
#   WAR_REPLAY=<omr> WAR_OUT=<dir> [WAR_PARCHE=<bin>] [WAR_FIN=n] \
#       openmsx -script tools/omsx_replay_parcheado.tcl
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
set FIN [expr {[info exists ::env(WAR_FIN)] ? $::env(WAR_FIN) : 20300}]
set PARCHE [expr {[info exists ::env(WAR_PARCHE)] ? $::env(WAR_PARCHE) : ""}]
file mkdir $OUT
set LOG [open "$OUT/replay.log" w]
proc di {m} { global LOG; puts $LOG "\[[format %8.1f [machine_info time]]\] $m"; flush $LOG }
catch {set renderer none}
set throttle off
# OJO: con -viewonly openMSX RECHAZA las escrituras a memoria -se aceptan sin
# error y el byte se queda como estaba-, asi que para meter el arreglo hay que
# cargar el replay SIN ese flag. La entrada grabada se reproduce igual.
if {$PARCHE eq ""} {
    set r [catch {reverse loadreplay -viewonly $REPLAY} m]
} else {
    set r [catch {reverse loadreplay $REPLAY} m]
}
if {$r} { di "rc: $m"; exit 1 }

proc vuelca {tag} {
    global OUT
    foreach {n a s} [list zx_$tag.bin 0x4000 0x1B00  tabla_$tag.bin 0x0200 0x0100  mapa_$tag.bin 0xCC00 0x33CC] {
        set f [open "$OUT/$n" w]; fconfigure $f -translation binary
        puts -nonewline $f [debug read_block memory $a $s]; close $f
    }
    set m [debug read_block memory 0xCC00 0x33CC]
    set b5 0
    for {set i 0} {$i<0x33CC} {incr i} { if {[scan [string index $m $i] %c] & 0x20} {incr b5} }
    di "volcado $tag: mes=[debug read memory 0x8355] dia=[debug read memory 0x8326] marcas=$b5"
}

if {$PARCHE eq ""} {
    # Tal cual: los snapshots del propio replay llevan hasta el final de un salto.
    reverse goto $FIN
    di "en el final del replay, sin tocar nada"
    vuelca "sin"
    di FIN
    exit 0
}

# Con el arreglo: se planta antes de la PRIMERA compresion (la primera batalla
# fue a los 331 s) y se corre hacia delante, que es la unica forma de que el
# cambio sobreviva: un `reverse goto` volveria a un snapshot sin el.
reverse goto 250
set f [open $PARCHE r]; fconfigure $f -translation binary
set rutina [read $f]; close $f
debug write_block memory 0x66E2 $rutina
debug write memory 0x93A5 0xE2
debug write memory 0x93A6 0x66
di "arreglo metido en la RAM: [string length $rutina] bytes en 0x66E2, y 0x93A5 = 0x66E2"
if {[debug read memory 0x66E2] != 0xE5 || [debug read memory 0x93A5] != 0xE2} {
    di "NO HA ENTRADO: 0x66E2=[format %02X [debug read memory 0x66E2]] 0x93A5=[format %02X [debug read memory 0x93A5]]"
    exit 1
}
di "comprobado: el arreglo esta en la RAM"
vuelca "arranque"

# El volcado NO se hace por reloj: si cae en una batalla, 0xCC00 lleva el mapa
# COMPRIMIDO y la pantalla esta en negro. Se hace en el bucle de partida
# (0x7F57), que es justo cuando el mapa esta entero y en pantalla, y se va
# pisando el anterior: el ultimo antes de FIN es el bueno.
set ::ultimo 0
set ::DESDE [expr {[info exists ::env(WAR_DESDE)] ? $::env(WAR_DESDE) : 19000}]
debug set_bp 0x7F57 {} {
    set t [machine_info time]
    if {$t > $::DESDE && $t - $::ultimo > 60} {
        set ::ultimo $t
        vuelca "con"
    }
}
proc espera {} {
    global FIN
    if {[machine_info time] >= $FIN} {
        di "FIN (el ultimo volcado bueno es de t=[format %.0f $::ultimo])"
        exit 0
    }
    di "... [format %.0f [machine_info time]] de $FIN"
    after time 250 espera
}
after time 10 espera
