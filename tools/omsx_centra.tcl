# Centra la vista del mapa en la casilla (WAR_CX, WAR_CY) y captura la pantalla.
# Sirve para comparar la MISMA casilla con y sin parche: si el parche esta,
# las unidades enemigas de alrededor salen dibujadas; si no, no.
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> WAR_CX=<col> WAR_CY=<fila> WAR_SHOT=<png>
#     openmsx -machine Philips_VG_8020 -script este.tcl
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
set CX  $::env(WAR_CX)
set CY  $::env(WAR_CY)
set SHOT [expr {[info exists ::env(WAR_SHOT)] ? $::env(WAR_SHOT) : "centra.png"}]
file mkdir $OUT
set LOG [open "$OUT/centra.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id  centro pedido=($CX,$CY)"
if {$r} { exit 1 }
catch {activate_machine $id}

set ::st 0
debug set_bp 0x7F57 {} {
    if {$::st == 0} {
        debug write memory 0x6543 [expr {(($::CX-8)*2) & 0xFF}]
        debug write memory 0x6544 [expr {(($::CY-3)*2) & 0xFF}]
        say "cursor puesto para centrar en ($::CX,$::CY)"
        set ::st 1
    }
}
debug set_bp 0x7F86 {} {
    if {$::st == 1} { set ::st 2; reg A [expr {[reg A] | 0x10}]; say "disparo -> RECENTRA" }
}

# el bp necesita las variables globales
set ::CX $CX
set ::CY $CY

set throttle off
after time 2 { type "0" }
after time 6 { if {$::st == 0} { type "0" } }
after time 16 {
    say "st=$::st"
    set throttle on
    after realtime 2 {
        catch {screenshot $OUT/$SHOT} e
        say "screenshot $SHOT = $e"
        say "FIN"
        exit 0
    }
}
