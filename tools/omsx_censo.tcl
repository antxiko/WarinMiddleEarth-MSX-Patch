# Censo de las 256 ranuras de unidad nada mas empezar la partida: coordenadas,
# byte de tipo/bando y los seis valores. Sirve para ELEGIR donde centrar la
# vista antes de capturar el antes/despues del parche (que casilla tiene mas
# enemigas alrededor).
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> openmsx -machine Philips_VG_8020 -script este.tcl
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/censo.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer none}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id"
if {$r} { exit 1 }
catch {activate_machine $id}

set ::hecho 0
debug set_bp 0x7F57 {} {
    if {$::hecho} { return }
    set ::hecho 1
    global OUT
    set f [open "$OUT/censo.txt" w]
    puts $f "n x y bd c0 c1 c2 c3 c6 c7"
    for {set n 0} {$n < 256} {incr n} {
        puts $f [format "%d %d %d %d %d %d %d %d %d %d" $n \
            [debug read memory [expr {0xB900+$n}]] \
            [debug read memory [expr {0xBA00+$n}]] \
            [debug read memory [expr {0xBD00+$n}]] \
            [debug read memory [expr {0xC000+$n}]] \
            [debug read memory [expr {0xC100+$n}]] \
            [debug read memory [expr {0xC200+$n}]] \
            [debug read memory [expr {0xC300+$n}]] \
            [debug read memory [expr {0xC600+$n}]] \
            [debug read memory [expr {0xC700+$n}]]]
    }
    close $f
    say "censo escrito"
    say [format "vista: 0x6543=%d 0x6544=%d" [debug read memory 0x6543] [debug read memory 0x6544]]
}

set throttle off
after time 2 { type "0" }
after time 6 { if {!$::hecho} { type "0" } }
after time 14 {
    say "hecho=$::hecho"
    say "FIN"
    exit 0
}
