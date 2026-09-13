# Reproduce una partida grabada y apunta POR DONDE se llega a la derrota.
#
# CUIDADO CON LOS PUNTOS DE RUPTURA CONDICIONALES: los cinco caminos a DERROTA
# (0x83E1) son saltos CONDICIONALES, asi que parar en el `jp` NO quiere decir
# que se tome. La primera version de esto declaraba la derrota al llegar a
# 0x9309 y se equivocaba: por ahi se pasa en cada vuelta en la que no queda
# nadie del jugador en la casilla vigilada, y casi nunca se salta.
#
# Lo que si vale: apuntar por cual de los cinco cruces se ha pasado la ULTIMA
# vez y esperar a que el programa llegue de verdad a DERROTA (0x83E1). El
# camino bueno es el ultimo visitado, porque entre el y 0x83E1 no hay nada.
#
#   0x6A73  entrega del Anillo a una unidad con el nibble bajo de 0xC000 a cero
#   0x8338  la cuenta atras de meses (operando de 0x8333) ha llegado a cero
#   0x9218  al cerrar la batalla, el portador ya no esta en el mapa
#   0x927C  la tecla R agota los usos de 0xC000 del ejercito del jugador
#   0x9309  en la casilla (0x56,0x3F) solo quedan unidades del otro bando
#
# Uso:
#   WAR_REPLAY=<replay.omr> WAR_OUT=<dir> openmsx -script este.tcl

set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
file mkdir $OUT

set L [open "$OUT/porque.log" w]
proc di {m} {
    global L
    puts $L "\[[format %9.3f [machine_info time]]\] $m"
    flush $L
}

proc byte {a} { return [debug read memory $a] }

proc estado {} {
    return "mes [byte 0x8355] dia [byte 0x8326] tic [byte 0x831C] | PLAZO [byte 0x8333]"
}

set ::batallas 0
set ::entregas 0
set ::ultimo "ninguno"
set ::ultimo_t -1
set ::fin 0

# Quien hay en la casilla vigilada, contado EXACTAMENTE como lo cuenta 0x92DE:
# con el byte crudo, sin quitarle el bit 7 (el de la bandera de rodeo).
proc quien_hay_en_la_casilla {} {
    set mios {}
    set suyos {}
    for {set n 0} {$n < 256} {incr n} {
        if {[byte [expr {0xB900 + $n}]] == 0x56 && [byte [expr {0xBA00 + $n}]] == 0x3F} {
            if {$n == 0x16 || $n == 0x17 || $n >= 0x78} {
                lappend suyos [format 0x%02X $n]
            } else {
                lappend mios [format 0x%02X $n]
            }
        }
    }
    return [list $mios $suyos]
}

proc paso_por {via} {
    set ::ultimo $via
    set ::ultimo_t [machine_info time]
}

proc muerte {} {
    if {$::fin} return
    set ::fin 1
    di "==================== DERROTA (0x83E1) ===================="
    di "  ultimo cruce visitado: $::ultimo  (hace [format %.4f [expr {[machine_info time] - $::ultimo_t}]] s)"
    di "  estado: [estado]"
    di "  batallas jugadas: $::batallas ; entregas del Anillo: $::entregas"
    lassign [quien_hay_en_la_casilla] mios suyos
    di "  en la casilla vigilada (0x56,0x3F): [llength $mios] del jugador, [llength $suyos] del bando oscuro"
    di "    jugador: $mios"
    di "    oscuro : $suyos"
    set f [open "$OUT/tiras_al_perder.txt" w]
    puts $f "# n  B900  BA00  BB00  BC00  BD00  C000  C200  C500  C600"
    for {set n 0} {$n < 256} {incr n} {
        puts $f [format "%3d %5d %5d %5d %5d %5d %5d %5d %5d %5d" $n \
            [byte [expr {0xB900 + $n}]] [byte [expr {0xBA00 + $n}]] \
            [byte [expr {0xBB00 + $n}]] [byte [expr {0xBC00 + $n}]] \
            [byte [expr {0xBD00 + $n}]] [byte [expr {0xC000 + $n}]] \
            [byte [expr {0xC200 + $n}]] [byte [expr {0xC500 + $n}]] \
            [byte [expr {0xC600 + $n}]]]
    }
    close $f
    di "  tiras volcadas en tiras_al_perder.txt"
    after realtime 2 {exit 0}
}

set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
di "loadreplay rc=$r: $msg"
if {$r} { di "ABORTADO"; exit 1 }
di "arranca: [estado]"

# Los cinco cruces, solo como testigos.
debug set_bp 0x6A73 {} {paso_por "entrega del Anillo (0x6A73)"}
debug set_bp 0x8338 {} {paso_por "plazo de meses (0x8338)"}
debug set_bp 0x9218 {} {paso_por "portador fuera del mapa al cerrar la batalla (0x9218)"}
debug set_bp 0x927C {} {paso_por "tecla R agotada (0x927C)"}
debug set_bp 0x9309 {} {paso_por "casilla vigilada (0x9309)"}

# Y la derrota de verdad.
debug set_bp 0x83E1 {} {muerte}

debug set_bp 0x9021 {} {incr ::batallas; di "batalla numero $::batallas en [estado]"}
debug set_bp 0x6A6C {} {incr ::entregas; di "entrega del Anillo numero $::entregas: [estado]"}

proc vigila {} {
    if {$::fin} return
    lassign [quien_hay_en_la_casilla] mios suyos
    di "... [estado] | casilla vigilada: [llength $mios] mios, [llength $suyos] suyos | ultimo cruce: $::ultimo"
    after time 30 vigila
}
after time 30 vigila

set throttle off
after realtime 870 {di "se acabo el tiempo sin llegar a la derrota: [estado]"; exit 2}
