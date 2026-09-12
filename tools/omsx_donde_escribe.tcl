# ¿DONDE CAEN LAS ESCRITURAS DEL VDP?
#
# El juego escribe al puerto 0x98 el mismo numero de veces en una MSX1 y en una
# MSX2, pero en la MSX2 la pantalla no cambia. O los bytes se pierden, o caen en
# otro sitio. En un V9938 la direccion tiene 17 bits: los catorce de los puertos
# y los tres de R14, que el propio VDP SUBE SOLO cuando el contador pasa de
# 0x3FFF. Si eso ocurre, todo lo que el juego pinte despues se va a otra pagina
# de 16K y la pantalla se queda helada para siempre.
#
# Esto lo mira sin suponer nada: muestrea los 128K enteros y dice en que bloques
# de 1K cambia algo, y de paso apunta R14 en cada muestra.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_donde_escribe.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/donde.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
say "cartucho: [carta]"

set ::N [debug size VRAM]
say "VRAM del debuggable: $::N bytes"

set ::previa ""
set ::bloques [dict create]
set ::r14 [dict create]
set ::tomas 0
set ::mirando 0

proc mira {} {
    if {!$::mirando} { return }
    set v [debug read_block VRAM 0 $::N]
    dict incr ::r14 [debug read "VDP regs" 14]
    if {$::previa ne ""} {
        for {set b 0} {$b < $::N} {incr b 1024} {
            if {[string range $v $b [expr {$b + 1023}]] ne
                [string range $::previa $b [expr {$b + 1023}]]} {
                dict incr ::bloques $b
            }
        }
    }
    set ::previa $v
    incr ::tomas
    after time 0.1 mira
}

proc informe {} {
    say "--- $::tomas muestras de los 128K"
    if {[dict size $::bloques] == 0} {
        say "    NINGUN bloque de 1K cambia en toda la VRAM: las escrituras se pierden"
    } else {
        foreach b [lsort -integer [dict keys $::bloques]] {
            say [format "    0x%05X-0x%05X cambia en %d muestras" $b [expr {$b + 1023}] [dict get $::bloques $b]]
        }
    }
    say "--- R14 (los tres bits altos de la direccion) visto asi:"
    foreach v [lsort -integer [dict keys $::r14]] {
        say [format "    R14 = 0x%02X en %d muestras" $v [dict get $::r14 $v]]
    }
    say "--- VDP R0-R23 ahora:"
    set l {}
    for {set r 0} {$r < 24} {incr r} { lappend l [format %02X [debug read "VDP regs" $r]] }
    say "    [join $l { }]"
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    # Primero se mira el MENU, donde si se ve pintar, para tener el contraste.
    after time 1 {
        set ::mirando 1
        mira
        after time 2 {
            set ::mirando 0
            say "=== EL MENU ==="
            informe
            set ::previa ""
            set ::bloques [dict create]
            set ::r14 [dict create]
            set ::tomas 0
            say "se pulsa 0 para empezar la partida"
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                say "PC en 0x6A47: la partida ha arrancado"
                debug remove_bp $::bp_mapa
                after time 1 {
                    set ::previa ""
                    set ::bloques [dict create]
                    set ::r14 [dict create]
                    set ::tomas 0
                    set ::mirando 1
                    mira
                    after time 6 {
                        set ::mirando 0
                        say "=== EL MAPA ==="
                        informe
                        say "FIN"
                        exit 0
                    }
                }
            }]
        }
    }
}]

after time 90 { say "TIMEOUT"; exit 1 }
