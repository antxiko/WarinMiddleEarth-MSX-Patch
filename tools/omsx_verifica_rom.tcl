# EL CARTUCHO EN openMSX: los mismos volcados que se hicieron con la cinta
#
# La cinta se volco en dos instantes (tools/omsx_arranque.tcl del parche):
# al llegar a 0x0190 con los tres bloques cargados y sin recolocar, y al
# llegar a 0x5E00 con el juego arrancando. Aqui se arranca la maquina con el
# cartucho puesto y se vuelca lo mismo en los mismos dos sitios, mas la VRAM,
# los registros del VDP y los del PSG en 0x5E00. tools/coteja_rom.py compara.
#
# Con WAR_CAPTURA=1 ademas deja correr el juego, captura el menu, pulsa 0
# (empezar) y captura el mapa. Eso va con el acelerador puesto y en tiempo
# real, que es lo unico con lo que openMSX pinta de verdad.
#
#   WAR_ROM=<war.rom> WAR_OUT=<dir> [WAR_CAPTURA=1] \
#     openmsx -machine <maquina> -carta <war.rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/verifica_rom.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
set CAPTURA [expr {[info exists ::env(WAR_CAPTURA)] && $::env(WAR_CAPTURA) ne ""}]

if {$CAPTURA} {
    set r [catch {set renderer SDLGL-PP} msg]
    say "renderer rc=$r: $msg"
} else {
    catch {set renderer none}
}
set throttle off
say "maquina: [machine_info config_name]"
say "cartucho: [carta]"

proc dumpd {name dbg addr size} {
    global OUT
    set f [open "$OUT/$name" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block $dbg $addr $size]
    close $f
    say "volcado $name <- $dbg\[[format 0x%04X $addr] .. [format 0x%04X [expr {$addr+$size-1}]]\]"
}
proc ranuras {} {
    return [format "A8=0x%02X FFFF=0x%02X" [debug read ioports 0xA8] [debug read memory 0xFFFF]]
}

set ::bp_stub [debug set_bp 0xD800 {} {
    say "stub en marcha en 0xD800 ([ranuras])"
    debug remove_bp $::bp_stub
}]
set ::bp_0190 [debug set_bp 0x0190 {} {
    say "PC en 0x0190: los bloques cargados, sin recolocar ([ranuras])"
    dumpd ram_0190.bin memory 0 0x10000
    debug remove_bp $::bp_0190
}]
set ::bp_5e00 [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el juego arranca ([ranuras] SP=[format 0x%04X [reg SP]])"
    dumpd ram_5e00.bin memory 0 0x10000
    dumpd vram_5e00.bin VRAM 0 0x4000
    dumpd vdpregs_5e00.bin {VDP regs} 0 8
    dumpd psgregs_5e00.bin {PSG regs} 0 16
    debug remove_bp $::bp_5e00
    if {$::CAPTURA} {
        set throttle on
        after realtime 4 {
            set r [catch {screenshot -raw -doublesize $::OUT/menu.png} msg]
            say "captura del menu rc=$r: $msg"
            type "0"
            after realtime 5 {
                set r [catch {screenshot -raw -doublesize $::OUT/mapa.png} msg]
                say "captura del mapa rc=$r: $msg  PC=[format 0x%04X [reg PC]]"
                say "OK"
                exit 0
            }
        }
    } else {
        say "OK"
        exit 0
    }
}]

after time 30 { say "TIMEOUT: no se llego a 0x5E00"; exit 1 }
