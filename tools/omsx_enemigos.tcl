# Captura del mapa centrado en una unidad ENEMIGA, para ver que el parche las
# hace visibles. Parte del estado del menu (war_5e00.oms), arranca partida,
# coloca el cursor sobre el primer enemigo (indice >= 0x78 con coordenadas) y
# fuerza un disparo, que dispara RECENTRA_EL_MAPA: la vista se centra en el
# enemigo y, con el parche, su silueta ya esta sembrada en el mapa.
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> openmsx -machine Philips_VG_8020 -script este.tcl
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/enemigos.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id"
if {$r} { exit 1 }
catch {activate_machine $id}

set ::st 0
set ::enN -1
debug set_bp 0x7F57 {} {
    if {$::st == 0} {
        for {set n 0x78} {$n <= 0xFF} {incr n} {
            set x [expr {[debug read memory [expr {0xB900+$n}]] & 0x7F}]
            set y [expr {[debug read memory [expr {0xBA00+$n}]] & 0x7F}]
            if {$x || $y} {
                set ::enN $n; set ::enX $x; set ::enY $y
                debug write memory 0x6543 [expr {(($x-8)*2) & 0xFF}]
                debug write memory 0x6544 [expr {(($y-3)*2) & 0xFF}]
                say "cursor sobre enemigo n=[format 0x%02X $n] en X=$x Y=$y"
                set ::st 1
                break
            }
        }
        if {$::st == 0} { say "no hay enemigos con coordenadas (aun)"; }
    }
}
debug set_bp 0x7F86 {} {
    if {$::st == 1} { set ::st 2; reg A [expr {[reg A] | 0x10}]; say "disparo -> RECENTRA sobre el enemigo" }
}

set throttle off
after time 2 { type "0" }
after time 6 { if {$::st == 0} { type "0" } }
after time 16 {
    say "estado final st=$::st  enemigo=[format 0x%02X $::enN]"
    set throttle on
    after realtime 2 {
        catch {screenshot $OUT/enemigos.png} e
        say "screenshot=$e"
        say "FIN"
        exit 0
    }
}
