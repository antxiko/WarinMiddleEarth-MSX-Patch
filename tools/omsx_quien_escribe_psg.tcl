# ¿QUIEN ESCRIBE EN EL PSG, APARTE DEL REPRODUCTOR?
#
# La musica sonaba, pero desordenada. El sospechoso estaba anotado como riesgo
# desde antes de empezar: LEE_JOYSTICK (0x046E) selecciona el registro 7 -el
# MIXER, el que dice que canales suenan-, lo LEE, le hace `or 0C0h` y lo vuelve
# a escribir. Dos problemas:
#
#   - el reproductor deja ese registro con el bit 6 a CERO (`res 6,(hl)` en
#     PT3_ROUT) y el juego se lo pone a UNO;
#   - y reescribe el mixer ENTERO con lo que leyo antes, asi que si entre medias
#     el reproductor lo cambio, se pierde.
#
# Aqui se cuenta cada escritura al puerto 0xA1 durante el menu, con el registro
# al que iba y el PC de quien la hizo. Si el juego aparece escribiendo el
# registro 7, esta confirmado.
#
#   WAR_ROM=<rom> WAR_OUT=<dir> \
#     openmsx -machine <maquina> -carta <rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/psg.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::reg 0
set ::quien [dict create]
set ::mide 0

# El puerto 0xA0 elige registro; el 0xA1 escribe el dato.
debug set_watchpoint write_io 0xA0 {} {
    set ::reg $::wp_last_value
}
debug set_watchpoint write_io 0xA1 {} {
    if {$::mide} {
        set pc [reg PC]
        set clave [format "PC=%04X reg=%d" $pc $::reg]
        dict incr ::quien $clave
        # Del registro 7 interesa ademas QUE valor se escribe: el bit 6 dice
        # quien gano, porque el reproductor lo quiere a 0 y el juego a 1.
        if {$::reg == 7} {
            set b6 [expr {($::wp_last_value >> 6) & 1}]
            dict incr ::quien [format "   ^ reg 7 desde PC=%04X con bit6=%d" $pc $b6]
        }
    }
}

set ::bp_5e00 [debug set_bp 0x5E00 {} {
    say "el juego arranca; se mide el menu durante 4 segundos"
    debug remove_bp $::bp_5e00
    after time 2 {
        set ::mide 1
        # SE PULSAN TECLAS: la medicion anterior fue con el menu quieto, y asi
        # LEE_JOYSTICK -que reescribe el registro 7- no llegaba a entrar.
        after time 0.5 { type "6" }
        after time 1.0 { type "6" }
        after time 1.5 { type "5" }
        after time 2.0 { type "6" }
        after time 2.5 { type "6" }
        after time 3.0 { type "6" }
        after time 4 {
            set ::mide 0
            say "--------------------------------------------------------"
            foreach k [lsort [dict keys $::quien]] {
                say [format "%-44s %6d veces" $k [dict get $::quien $k]]
            }
            say "OK"
            exit 0
        }
    }
}]

after time 60 { say "TIMEOUT"; exit 1 }
