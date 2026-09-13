# ¿CAMBIA EL TERRENO DURANTE LA PARTIDA?
#
# El mapa general ya dibujado (--mapa) se apoya en una suposicion: que el
# dibujo del terreno no cambia nunca. Y el dibujo depende SOLO del nibble bajo
# del byte de mapa -las dos pasadas de 0x8180 y 0x81A0 hacen `and 00fh`, y los
# vecinos de PINTA_CASILLA_UNIDA tambien-, asi que la pregunta exacta es:
#
#   ¿alguien cambia los bits 0-3 de alguna casilla de 0xCC00-0xFFCB mientras
#   se juega?
#
# Del listado se sabe quien escribe ahi: el `set 7,(hl)` de 0x7FCC, que marca
# donde hay una unidad, y el bucle de 0x7FF0, que lo quita con `and 07fh`. Los
# dos tocan el BIT 7 y nada mas. Esto lo COMPRUEBA sobre una partida de verdad,
# y de dos maneras que no dependen la una de la otra:
#
#   1. UN VOLCADO AL EMPEZAR Y OTRO AL ACABAR. Los 13.260 bytes del mapa en
#      cuanto el juego entra en el bucle de partida, y otra vez al final del
#      replay. Se comparan los nibbles bajos, que es lo unico que se dibuja.
#      Esto no depende de cuando salte un watchpoint ni de si se lee antes o
#      despues de la escritura: es el estado, medido.
#   2. QUIEN ESCRIBE EN EL MAPA mientras se juega. Un watchpoint, armado SOLO
#      desde que empieza la partida -si no, lo que se ve es la cinta cargando-,
#      que apunta el PC de cada escritura. Se espera 0x7FCC y 0x7FF2 y nada mas.
#
# La partida es el replay de Araubi, reproducido sobre la CINTA: lo que se
# pregunta es del juego, no del cartucho.
#
#   WAR_REPLAY=<replay.omr> WAR_OUT=<dir> [WAR_HASTA=<segundos>] \
#       openmsx -machine <maq> -script tools/omsx_terreno_quieto.tcl

set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/terreno_quieto.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

set ::MAPA_INI 0xCC00
set ::MAPA_TAM 0x33CC

catch {set renderer SDLGL-PP}
set throttle off

set r [catch {reverse loadreplay -viewonly $REPLAY} msg]
say "loadreplay rc=$r: $msg"
if {$r} { say "ABORTADO"; exit 1 }
array set st [reverse status]
set ::FIN $st(end)
if {[info exists ::env(WAR_HASTA)]} { set ::FIN $::env(WAR_HASTA) }
say "replay cargado, se mira hasta el segundo $::FIN"

proc guarda {nombre} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory $::MAPA_INI $::MAPA_TAM]
    close $f
}

set ::escribe [dict create]
set ::empezo 0
set ::wp 0

# En cuanto el juego entra en el bucle de partida: el primer volcado y el
# watchpoint armado. Antes que eso lo que hay es la cinta cargando, que
# escribe el mapa entero porque ahi es donde lo descomprime.
set ::bp [debug set_bp 0x7F57 {} {
    if {!$::empezo} {
        set ::empezo 1
        debug remove_bp $::bp
        guarda "mapa_antes.bin"
        say "el juego esta en el bucle de partida: volcado el mapa y armado el watchpoint"
        set ::wp [debug set_watchpoint write_mem [list $::MAPA_INI [expr {$::MAPA_INI + $::MAPA_TAM - 1}]] {} {
            dict incr ::escribe [format %04X [reg PC]]
        }]
    }
}]

proc informe {} {
    guarda "mapa_despues.bin"
    say "-------------------------------------------------------------"
    if {!$::empezo} {
        say "el replay no llego al bucle de partida: no se ha medido nada"
        say "ROJO"
        exit 1
    }
    set n 0
    dict for {pc veces} $::escribe { say [format "  escribe desde PC=%s  %d veces" $pc $veces]; incr n }
    say "$n sitios del juego escriben en el mapa mientras se juega"
    say "VERDE-PARCIAL: falta comparar los dos volcados (lo hace tools/coteja_terreno.py)"
}

proc vigila {} {
    if {[machine_info time] >= $::FIN} {
        informe
        exit 0
    }
    after time 5 vigila
}
after time 5 vigila
