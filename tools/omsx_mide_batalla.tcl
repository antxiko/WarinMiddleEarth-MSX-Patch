# LA BATALLA, MEDIDA DE VERDAD
#
# El plan del 2026-09-13 dejo dos cosas por medir y las dos necesitaban una
# partida que llegara a una batalla. El replay de Ruben tiene treinta y tantas.
#
# Cada vuelta del tablero acaba subiendo la pantalla ENTERA al VDP:
#     8849  call 005bdh   ; BITMAP_A_VRAM   (6.144 B)
#     884C  call 00604h   ; ATRIBUTOS_A_VRAM (768 -> 6.144 escrituras)
#     884F  ret
# Esto mide lo que cuesta cada uno EN UNA BATALLA REAL, cuenta cuantas fichas
# cambian por vuelta -las que NO se salta el `jp z` de 0x87A2- y vigila si
# alguien escribe los atributos (0x5800-0x5AFF) dentro del bucle: si nadie lo
# hace, el `call` de 0x884C sobra entero.
#
#   WAR_REPLAY=<omr> WAR_OUT=<dir> [WAR_DESDE=n] [WAR_HASTA=n] \
#       openmsx -machine <maq> -script tools/omsx_mide_batalla.tcl
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
set DESDE [expr {[info exists ::env(WAR_DESDE)] ? $::env(WAR_DESDE) : 340}]
set HASTA [expr {[info exists ::env(WAR_HASTA)] ? $::env(WAR_HASTA) : 360}]
file mkdir $OUT
set LOG [open "$OUT/batalla.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off
if {[catch {reverse loadreplay -viewonly $REPLAY} m]} { di "rc: $m"; exit 1 }

set ::RELOJ 3579545.0
set ::vueltas 0 ; set ::nbit 0 ; set ::natr 0
set ::tbit 0.0  ; set ::tatr 0.0
set ::fichas 0  ; set ::cambian 0
set ::t0 0.0    ; set ::t1 0.0
set ::escrituras [dict create]
set ::porvuelta {}
set ::cambian_vuelta 0

reverse goto $DESDE
di "plantado en t=[format %.1f [machine_info time]] (la batalla va de 331,8 a 484,2)"

debug set_bp 0x914E {} { incr ::vueltas }
debug set_bp 0x8849 {} { set ::t0 [machine_info time] ; incr ::nbit }
debug set_bp 0x884C {} {
    set t [machine_info time]
    set ::tbit [expr {$::tbit + $t - $::t0}]
    set ::t1 $t ; incr ::natr
}
debug set_bp 0x884F {} {
    set ::tatr [expr {$::tatr + [machine_info time] - $::t1}]
    lappend ::porvuelta $::cambian_vuelta
    set ::cambian_vuelta 0
}
debug set_bp 0x8798 {} { incr ::fichas }
debug set_bp 0x87A5 {} { incr ::cambian ; incr ::cambian_vuelta }
debug set_watchpoint write_mem {0x5800 0x5AFF} {} {
    dict incr ::escrituras [format 0x%04X [reg PC]]
}

proc remata {} {
    if {[machine_info time] < $::HASTA} { after time 1 remata ; return }
    di "vueltas del bucle de batalla (0x914E): $::vueltas"
    di "subidas: bitmap $::nbit, atributos $::natr"
    if {$::nbit} {
        di [format "  BITMAP_A_VRAM    (0x05BD): %9.0f ciclos de media" \
            [expr {$::tbit / $::nbit * $::RELOJ}]]
    }
    if {$::natr} {
        di [format "  ATRIBUTOS_A_VRAM (0x0604): %9.0f ciclos de media" \
            [expr {$::tatr / $::natr * $::RELOJ}]]
    }
    if {$::nbit} {
        di [format "  las dos juntas:            %9.0f ciclos = %.3f s por vuelta" \
            [expr {($::tbit + $::tatr) / $::nbit * $::RELOJ}] \
            [expr {($::tbit + $::tatr) / $::nbit}]]
    }
    di "fichas miradas: $::fichas ; fichas que CAMBIAN: $::cambian"
    if {$::nbit} { di [format "  por vuelta: %.1f miradas, %.1f cambian" \
        [expr {$::fichas / double($::nbit)}] [expr {$::cambian / double($::nbit)}]] }
    di "  reparto por vuelta: [lrange $::porvuelta 0 19]"
    di "ESCRITURAS en 0x5800-0x5AFF (los atributos): [expr {[dict size $::escrituras] ? $::escrituras : {NINGUNA}}]"
    di FIN
    exit 0
}
after time 1 remata
