# Verifica los VALORES en la ficha (peticiones 2 y 3), por el camino NATURAL del
# juego: centra la vista de cerca sobre la unidad PORTADORA del Anillo (Frodo);
# como el cursor queda encima de ella, el propio juego arma y pinta su ficha,
# que ahora pasa por el trampolin de 0x708A y la rutina nueva de 0x6600.
# Se comprueba que los digitos escritos en el buffer (0x7C17) coinciden con los
# valores reales de 0xC000/0xC100/0xC200/0xC300, y se captura la pantalla.
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> openmsx -machine Philips_VG_8020 -script este.tcl
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/ficha.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id"
if {$r} { exit 1 }
catch {activate_machine $id}

set ::st 0
set ::port -1
set ::corrio 0

debug set_bp 0x6600 {} {
    incr ::corrio
    global OUT
    set f [open "$OUT/ficha_buf.bin" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory 0x7C17 240]
    close $f
    say "rutina de la ficha (0x6600) corrio #$::corrio para la unidad [debug read memory 0x6EAD]"
}

proc reporta {} {
    set n $::port
    set c0 [debug read memory [expr {0xC000+$n}]]
    set c1 [debug read memory [expr {0xC100+$n}]]
    set c2 [debug read memory [expr {0xC200+$n}]]
    set c3 [debug read memory [expr {0xC300+$n}]]
    say "valores reales de la unidad [format 0x%02X $n] (portador del Anillo):"
    say "  Valioso=[expr {$c0&15}]  Habil=[expr {($c0>>4)&15}]  Duro=[expr {$c1&15}]  Bravo=[expr {($c1>>4)&15}]  Energico=$c2  Decidido/Anillo=$c3"
    foreach {etq addr val} [list \
        Energico 0x7C73 $c2 \
        Decidido 0x7C8B $c3 \
        Habil    0x7CA3 [expr {($c0>>4)&15}] \
        Valioso  0x7CBB [expr {$c0&15}] \
        Duro     0x7CD3 [expr {$c1&15}] \
        Bravo    0x7CEB [expr {($c1>>4)&15}]] {
        set d0 [debug read memory $addr]
        set d1 [debug read memory [expr {$addr+1}]]
        set d2 [debug read memory [expr {$addr+2}]]
        say "  $etq -> digitos en la ficha: '[format %c%c%c $d0 $d1 $d2]'  (esperado [format %03d $val])"
    }
}

debug set_bp 0x7F57 {} {
    if {$::st == 0} {
        set port -1
        for {set n 0} {$n < 256} {incr n} {
            if {[debug read memory [expr {0xBD00+$n}]] & 0x10} { set port $n; break }
        }
        if {$port < 0} { set port 5 }
        set ::port $port
        set x [expr {[debug read memory [expr {0xB900+$port}]] & 0x7F}]
        set y [expr {[debug read memory [expr {0xBA00+$port}]] & 0x7F}]
        debug write memory 0x6543 [expr {(($x-8)*2) & 0xFF}]
        debug write memory 0x6544 [expr {(($y-3)*2) & 0xFF}]
        say "portador=[format 0x%02X $port] en X=$x Y=$y; centro la vista ahi"
        set ::st 1
    }
}
debug set_bp 0x7F86 {} {
    if {$::st == 1} { set ::st 2; reg A [expr {[reg A] | 0x10}]; say "disparo -> RECENTRA sobre el portador" }
}

set throttle off
after time 2 { type "0" }
after time 6 { if {$::st == 0} { type "0" } }
after time 18 {
    say "st=$::st  la rutina corrio $::corrio veces"
    if {$::corrio > 0} { reporta }
    set throttle on
    after realtime 2 {
        catch {screenshot $OUT/ficha.png} e
        say "screenshot=$e"
        say "FIN"
        exit 0
    }
}
