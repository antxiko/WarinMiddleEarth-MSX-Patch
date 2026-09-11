# ¿QUIEN ESCRIBE EN 0x003B-0x0086, DONDE VIVE EL PUENTE DE LA MUSICA?
#
# El diseno da esa zona por tierra de nadie: esta detras del `jp 0x0400` que el
# juego arma en 0x0038 y muy por debajo del buzon de POKEs de 0x012C. Pero la
# medicion de RAM libre (tools/ram_libre.py) va por bandas de 256 bytes y
# 0x0000-0x00FF NO sale como libre, o sea que ALGO escribe en esa banda; y tras
# empezar la partida, PUENTE_SONANDO -0x006E- aparecio con un 0x28 que nadie
# del puente pone.
#
# Aqui se pone un watchpoint de escritura en todo el tramo y se apunta quien la
# hace: direccion escrita, valor y PC del que escribe. Si el que pisa es el
# juego, el puente no puede vivir ahi.
#
#   WAR_ROM=<rom> WAR_OUT=<dir> \
#     openmsx -machine <maquina> -carta <rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/pisa.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::PUENTE_INI 0x003B
set ::PUENTE_FIN 0x0086
set ::avisos 0
set ::vistos {}

proc apunta {} {
    # El puente se escribe a si mismo una vez -PUENTE_SONANDO- y el cargador le
    # mete la ranura; eso no cuenta. Lo que se busca es quien mas lo toca.
    set pc [reg PC]
    set dir $::wp_last_address
    set val $::wp_last_value
    set clave [format "PC=%04X->%04X" $pc $dir]
    if {[lsearch -exact $::vistos $clave] < 0} {
        lappend ::vistos $clave
        say [format "escribe 0x%02X en 0x%04X desde PC=0x%04X" $val $dir $pc]
    }
    incr ::avisos
}

debug set_watchpoint write_mem [list $::PUENTE_INI $::PUENTE_FIN] {} { apunta }

# Se deja llegar al menu, se pulsa 0 y se juega un rato sin tocar nada.
set ::bp_5e00 [debug set_bp 0x5E00 {} {
    say "el juego arranca"
    debug remove_bp $::bp_5e00
    after time 4 {
        say "--- se pulsa 0: empieza la partida ---"
        type "0"
        after time 12 {
            say "--------------------------------------------------------"
            say "escrituras en 0x[format %04X $::PUENTE_INI]-0x[format %04X $::PUENTE_FIN]: $::avisos, de [llength $::vistos] sitios distintos"
            say "OK"
            exit 0
        }
    }
}]

after time 60 { say "TIMEOUT"; exit 1 }
