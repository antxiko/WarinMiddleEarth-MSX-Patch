# VER UNA PANTALLA FINAL SIN TERMINARSE EL JUEGO
#
# Las dos pantallas del final -la victoria de Gandalf y la derrota de Sauron-
# son lo que mas ha cambiado en el cartucho: ya no viajan a la RAM, se quedan
# comprimidas con ZX0 en la ROM y se descomprimen a 0x4000 cuando el juego las
# pide. Y para verlas hay que ganar o perder una partida entera.
#
# Esto las fuerza: arranca, deja llegar al menu, pulsa el 0 que empieza la
# partida y pone el PC en PINTA_LA_PANTALLA_FINAL (0x83E7) con HL en la que se
# pida, que es exactamente el estado con el que el juego llega ahi desde
# cualquiera de sus cuatro finales.
#
# A diferencia de tools/omsx_finales.tcl -que es el que COMPRUEBA, y para eso
# apaga la pantalla y vuelca ficheros-, este deja la maquina corriendo y a la
# vista: es para mirarla, no para cotejarla.
#
#   WAR_ROM=<rom> [WAR_PANTALLA=victoria|derrota] \
#     openmsx -machine <maquina> -carta <rom> -romtype ascii16 -script este.tcl

set ::CUAL "victoria"
if {[info exists ::env(WAR_PANTALLA)]} { set ::CUAL $::env(WAR_PANTALLA) }
set ::DIR [expr {$::CUAL eq "derrota" ? 0x244F : 0x094F}]

proc di {m} { puts $m }

di "openMSX: se va a forzar la pantalla final '$::CUAL' (HL = [format 0x%04X $::DIR])"
di "  Espera a que cargue; el 0 lo pulsa el script."

set ::bp_5e00 [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_5e00
    after time 2 {
        di "  ... el juego arranca: se pulsa 0"
        type "0"
        after time 4 {
            di "  ... PC a 0x83E7. Lo que salga sale de la ROM, descomprimido con ZX0."
            reg HL $::DIR
            reg PC 0x83E7
        }
    }
}]
