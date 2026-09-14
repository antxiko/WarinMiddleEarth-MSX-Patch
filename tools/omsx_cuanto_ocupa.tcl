# CUANTO OCUPA DE VERDAD EL MAPA COMPRIMIDO
#
# Antes de cada batalla, COMPRIME_EL_MAPA (0x9394) empaqueta los 0x33CC bytes
# del mapa en 0x4000 con EMPAQUETA y despues copia de vuelta a 0xCC00 una
# cantidad CLAVADA: `ld bc,016ech` en 0x93A7. Si lo empaquetado pasa de 0x16EC,
# la cola se pierde, y al salir de la batalla DESCOMPRIME_EL_MAPA (0x9366) ya
# no tiene con que rellenar el final del mapa.
#
# Esto se planta en la partida y, en cada compresion, apunta lo que mide de
# verdad (DE al volver de EMPAQUETA, menos 0x4000) contra el 0x16EC del codigo,
# junto con cuantas casillas llevan puesto el bit 5 del parche.
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/cuanto.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off
set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
if {$r} { di "loadreplay rc=$r: $msg"; exit 1 }
set fin [dict get [reverse status] end]
di "replay de 0 a $fin s"

proc cuenta_bits {} {
    set m [debug read_block memory 0xCC00 0x33CC]
    set b5 0; set b6 0; set b7 0
    for {set i 0} {$i < 0x33CC} {incr i} {
        set v [scan [string index $m $i] %c]
        if {$v & 0x20} {incr b5}; if {$v & 0x40} {incr b6}; if {$v & 0x80} {incr b7}
    }
    return [list $b5 $b6 $b7]
}

# Justo antes de empaquetar: cuantas marcas lleva el mapa.
debug set_bp 0x9394 {} { set ::antes [cuenta_bits] }
# Y justo despues: lo que ha salido.
debug set_bp 0x93A7 {} {
    set n [expr {[reg DE] - 0x4000}]
    lassign $::antes b5 b6 b7
    set sobra [expr {$n - 0x16EC}]
    di [format "t=%8.1f  COMPRIME: mide 0x%04X (%d B) contra el 0x16EC del codigo -> %+d   | bit5=%d bit6=%d bit7=%d" \
        [machine_info time] $n $n $sobra $b5 $b6 $b7]
}
debug set_bp 0x9366 {} { di "t=[format %8.1f [machine_info time]]  DESCOMPRIME" }

proc vigila {} {
    if {[machine_info time] > [expr {$::fin - 5}]} { di FIN; exit 0 }
    after time 50 vigila
}
after time 5 vigila
