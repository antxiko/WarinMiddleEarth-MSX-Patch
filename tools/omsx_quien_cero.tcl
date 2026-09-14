# QUIEN ESCRIBE EN LA COLA DEL MAPA: el censo de escritores, con su PC
#
# Asi salio el culpable: 0x9385, el `ld (de),a` de REPITE_EL_BYTE, dentro de
# DESCOMPRIME_EL_MAPA (0x9366). 29.004 escrituras con valor 0x00 en un solo
# tramo de partida.
#
# Medido sobre el replay de Ruben: el terreno de las ultimas columnas se va a
# 0x00, de la 122 hacia la izquierda, y no vuelve. Esto se planta en medio de
# su partida, pone un punto de observacion de escritura en esa cola -por
# encima de 0xF400, para no recoger el trasiego de la batalla, que usa
# 0xE800-0xF3FF- y apunta quien escribe el cero, con el PC, la pila y los
# bytes de alrededor para reconocer la instruccion.
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
set DESDE [expr {[info exists ::env(WAR_DESDE)] ? $::env(WAR_DESDE) : 1300}]
set HASTA [expr {[info exists ::env(WAR_HASTA)] ? $::env(WAR_HASTA) : 6000}]
file mkdir $OUT
set LOG [open "$OUT/quien_cero.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off
set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
di "loadreplay rc=$r: $msg"
if {$r} { exit 1 }
reverse goto $DESDE
di "plantado en t=[machine_info time]"

set ::n 0
proc ctx {pc} { set s ""; for {set i -5} {$i<=4} {incr i} { append s [format "%02X " [debug read memory [expr {($pc+$i)&0xFFFF}]]] }; return $s }

# OJO: dentro del callback, `debug read memory` ya devuelve el valor ESCRITO,
# asi que no sirve para saber el valor viejo. Se censan todos los escritores.
set ::pcs [dict create]
set ::ej [dict create]
debug set_watchpoint write_mem {0xF400 0xFD70} {} {
    set a $::wp_last_address
    set v $::wp_last_value
    set pc [format 0x%04X [reg PC]]
    dict incr ::pcs $pc
    if {![dict exists $::ej $pc]} {
        dict set ::ej $pc "t=[format %.1f [machine_info time]] dir=[format 0x%04X $a] col=[expr {($a-0xCC00)/102-1}] val=[format 0x%02X $v] SP=[format 0x%04X [reg SP]] bytes: [ctx [reg PC]]"
    }
    incr ::n
}
proc vigila {} {
    if {[machine_info time] > $::HASTA} {
        di "escrituras totales=$::n"
        foreach pc [lsort [dict keys $::pcs]] { di "  $pc  x[dict get $::pcs $pc]   [dict get $::ej $pc]" }
        di FIN; exit 0
    }
    after time 20 vigila
}
after time 5 vigila
