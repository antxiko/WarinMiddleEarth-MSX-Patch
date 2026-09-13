# Quien saca del mapa a las 21 unidades que empiezan en la casilla vigilada.
#
# En la cinta, (0x56,0x3F) -Minas Tirith- arranca con 21 unidades del jugador:
# la 0x13 (Denethor) y los ejercitos 0x61-0x74. Si se quedan sin ninguna y
# llega una del otro bando, 0x92DE manda a DERROTA sin que haya habido una sola
# batalla. En la partida de Ruben ya no habia ninguna a los 30 segundos.
#
# Esto pone un punto de observacion de ESCRITURA sobre las coordenadas de tres
# de ellas y apunta quien las toca y desde donde.
#
# Uso:
#   WAR_REPLAY=<replay.omr> WAR_OUT=<dir> openmsx -script este.tcl

set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
file mkdir $OUT

set L [open "$OUT/quien_vacia.log" w]
proc di {m} {
    global L
    puts $L "\[[format %9.3f [machine_info time]]\] $m"
    flush $L
}

proc byte {a} { return [debug read memory $a] }

proc cuantos_hay {} {
    set n_mios 0
    for {set n 0} {$n < 256} {incr n} {
        if {[byte [expr {0xB900 + $n}]] == 0x56 && [byte [expr {0xBA00 + $n}]] == 0x3F} {
            if {!($n == 0x16 || $n == 0x17 || $n >= 0x78)} { incr n_mios }
        }
    }
    return $n_mios
}

set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
di "loadreplay rc=$r: $msg"
if {$r} { di "ABORTADO"; exit 1 }

# Las tres primeras de la casilla, segun la cinta: Denethor y dos ejercitos.
foreach n {0x13 0x61 0x62} {
    debug set_watchpoint write_mem [expr {0xB900 + $n}] {} \
        "di \"ESCRIBEN la columna de la unidad $n: [format %%d \$::wp_value] desde PC=\[format 0x%04X \[reg PC\]\]  (quedan [cuantos_hay] en la casilla)\""
    debug set_watchpoint write_mem [expr {0xBA00 + $n}] {} \
        "di \"ESCRIBEN la fila de la unidad $n desde PC=\[format 0x%04X \[reg PC\]\]  (quedan [cuantos_hay] en la casilla)\""
}

# Y el momento en que empieza la partida.
debug set_bp 0x7F43 {} {di "EMPIEZA_PARTIDA_NUEVA: en la casilla hay [cuantos_hay] del jugador"}
debug set_bp 0x7F57 {} {
    if {![info exists ::primera]} {
        set ::primera 1
        di "primera vuelta del bucle de partida: en la casilla hay [cuantos_hay] del jugador"
    }
}

proc vigila {} {
    di "... en la casilla quedan [cuantos_hay] del jugador"
    after time 10 vigila
}
after time 10 vigila

set throttle off
after realtime 300 {di "fin del muestreo"; exit 0}
