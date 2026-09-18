# ABRIR UN REPLAY DE UN TESTER Y DEJARLO JUGABLE
#
# Carga el .omr que diga WAR_REPLAY y devuelve el mando al jugador, para poder
# mirar lo que el tester describe y seguir jugando desde ahi. A diferencia de
# las sondas, esto NO va con throttle off ni renderer apagado: se quiere ver el
# juego a su velocidad de verdad, que es justo lo que se esta juzgando.
#
#   WAR_REPLAY=<fichero.omr> openmsx -script tools/omsx_mira_replay.tcl

set REPLAY $::env(WAR_REPLAY)

# El replay lleva dentro la maquina y el medio, asi que no hay que pasar ROM.
# `-goto` al final y luego `reverse stop` para soltar el mando: si se deja en
# modo replay, las teclas no llegan al juego.
set r [catch {reverse loadreplay $REPLAY} msg]
puts "loadreplay rc=$r: $msg"

after realtime 2 {
    catch {reverse goto [dict get [reverse status] end]}
    after realtime 1 {
        catch {reverse stop}
        puts "el mando vuelve al jugador; velocidad normal"
    }
}
