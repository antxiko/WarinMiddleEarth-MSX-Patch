# LA PARTIDA DE RUBEN, MUESTREADA: en que momento y donde se le come el mapa.
#
# Carga el replay y va saltando por el con `reverse goto`. En cada parada
# vuelca el MAPA (0xCC00, 0x33CC bytes) y los ATRIBUTOS de la pantalla ZX
# (0x5800, 768) y los compara con la primera parada, para separar de una vez
# las dos hipotesis: si cambia el nibble bajo del mapa es que alguien PISA los
# datos; si solo cambian los atributos es que el mapa sigue entero y lo que
# falla es el color.
#
#   WAR_REPLAY=<omr> WAR_OUT=<dir> [WAR_PASOS=n] openmsx -script este.tcl
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
set PASOS [expr {[info exists ::env(WAR_PASOS)] ? $::env(WAR_PASOS) : 20}]
file mkdir $OUT
set LOG [open "$OUT/mordor.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off

set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
di "loadreplay rc=$r: $msg"
if {$r} { exit 1 }
set st [reverse status]
set ini [dict get $st begin]
set fin [dict get $st end]
di "replay: de $ini a $fin  ([expr {$fin-$ini}] s)"

set ::base_mapa ""
set ::base_atr ""
proc parada {t} {
    reverse goto $t
    set m [debug read_block memory 0xCC00 0x33CC]
    set at [debug read_block memory 0x5800 768]
    if {$::base_mapa eq ""} { set ::base_mapa $m ; set ::base_atr $at }
    set terreno 0; set bit5 0; set bit6 0; set bit7 0
    set colmin 999; set colmax -1; set muestra {}
    for {set i 0} {$i < 0x33CC} {incr i} {
        set a [scan [string index $::base_mapa $i] %c]
        set b [scan [string index $m $i] %c]
        if {$b & 0x20} {incr bit5}; if {$b & 0x40} {incr bit6}; if {$b & 0x80} {incr bit7}
        if {($a & 0x0F) != ($b & 0x0F)} {
            incr terreno
            set c [expr {$i/102 - 1}]
            if {$c < $colmin} {set colmin $c}
            if {$c > $colmax} {set colmax $c}
            if {[llength $muestra] < 4} { lappend muestra [format "0x%04X col=%d f=%d %02X->%02X" [expr {0xCC00+$i}] $c [expr {$i%102-1}] $a $b] }
        }
    }
    set atdist 0; set ciegas 0
    for {set i 0} {$i < 768} {incr i} {
        set v [scan [string index $at $i] %c]
        if {[string index $at $i] ne [string index $::base_atr $i]} { incr atdist }
        if {($v & 7) == (($v >> 3) & 7)} { incr ciegas }
    }
    di [format "t=%7.1f  mes=%2d dia=%2d | TERRENO pisado=%5d (col %d..%d) | bit5=%5d bit6=%4d bit7=%4d | atributos distintos=%3d ciegos=%3d" \
        $t [debug read memory 0x8355] [debug read memory 0x8326] $terreno $colmin $colmax $bit5 $bit6 $bit7 $atdist $ciegas]
    if {[llength $muestra]} { di "         primeras: [join $muestra {; }]" }
}

# El t=0 no sirve de referencia: el juego todavia no ha cargado y la RAM
# esta a 0xFF. La base es la primera parada YA dentro de la partida.
set ARRANQUE [expr {[info exists ::env(WAR_ARRANQUE)] ? $::env(WAR_ARRANQUE) : 1300}]
for {set k 0} {$k <= $PASOS} {incr k} {
    parada [expr {$ARRANQUE + ($fin-$ARRANQUE)*$k/double($PASOS)}]
}
set f [open "$OUT/mapa_final.bin" w]; fconfigure $f -translation binary
puts -nonewline $f [debug read_block memory 0xCC00 0x33CC]; close $f
set f [open "$OUT/zx_final.bin" w]; fconfigure $f -translation binary
puts -nonewline $f [debug read_block memory 0x4000 0x1B00]; close $f
di FIN
exit 0
