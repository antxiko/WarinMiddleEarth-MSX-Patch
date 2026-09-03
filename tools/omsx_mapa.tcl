# Vuelca el MAPA en RAM (0xCC00, 0x33CC bytes) despues de que RECENTRA_EL_MAPA
# lo haya sembrado, centrado en (WAR_CX, WAR_CY). El bit 7 de cada celda es
# "aqui hay una unidad": comparando el volcado con y sin parche se ve, celda a
# celda y sin depender de la pantalla, que siluetas anade el parche.
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> WAR_CX=<col> WAR_CY=<fila> WAR_TAG=<nombre>
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
set CX  $::env(WAR_CX)
set CY  $::env(WAR_CY)
set TAG $::env(WAR_TAG)
file mkdir $OUT
set LOG [open "$OUT/mapa_$TAG.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id  centro=($CX,$CY)"
if {$r} { exit 1 }
catch {activate_machine $id}

set ::CX $CX
set ::CY $CY
set ::st 0

proc vuelca {nombre addr size} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory $addr $size]
    close $f
    say "volcado $nombre"
}

debug set_bp 0x7F57 {} {
    if {$::st == 0} {
        debug write memory 0x6543 [expr {(($::CX-8)*2) & 0xFF}]
        debug write memory 0x6544 [expr {(($::CY-3)*2) & 0xFF}]
        set ::st 1
        say "cursor puesto en ($::CX,$::CY)"
    }
}
debug set_bp 0x7F86 {} {
    if {$::st == 1} { set ::st 2; reg A [expr {[reg A] | 0x10}]; say "disparo -> RECENTRA" }
}

set ESPERA [expr {[info exists ::env(WAR_ESPERA)] ? $::env(WAR_ESPERA) : 14}]
set throttle off
after time 2 { type "0" }
after time 6 { if {$::st == 0} { type "0" } }
after time $ESPERA {
    say "st=$::st  parche: 0x7FD1=[format %02X [debug read memory 0x7FD1]]  0x708A=[format %02X [debug read memory 0x708A]]"
    vuelca "mapa_$TAG.bin" 0xCC00 0x33CC
    vuelca "unidades_$TAG.bin" 0xB900 0x0B00
    set throttle on
    after realtime 2 {
        catch {screenshot $OUT/pantalla_$TAG.png} e
        say "screenshot A = $e"
        after realtime 3 {
            catch {screenshot $OUT/pantalla_${TAG}_b.png} e2
            say "screenshot B = $e2"
            vuelca "mapa_${TAG}_b.bin" 0xCC00 0x33CC
            say "FIN"
            exit 0
        }
    }
}
