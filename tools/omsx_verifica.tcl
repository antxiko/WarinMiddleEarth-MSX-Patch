# Verifica el parche de Araubi en openMSX, partiendo del estado guardado en el
# menu (work/omsx_parche/war_5e00.oms).
#
#  1) Confirma que los bytes parcheados estan en RAM.
#  2) Arranca una partida (tecla 0) y fuerza UN disparo sobre el mapa, que es lo
#     que dispara RECENTRA_EL_MAPA (0x7FAC): la siembra del bit 7.
#  3) Instrumenta el bucle de siembra (0x7FCC) para apuntar QUE unidades se
#     siembran; con el parche debe llegar a indices >= 0x78 (el bando enemigo).
#  4) Cuenta las celdas del mapa con bit 7 antes y despues.
#  5) Captura la rutina nueva de la ficha (0x6600) si el juego la llama.
#
# openMSX no pasa argv a -script: los parametros van por entorno.
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> openmsx -machine Philips_VG_8020 -script este.tcl

set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/verifica.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer SDLGL-PP} e
say "renderer=[set renderer]"

set r [catch {restore_machine $OMS} msg]
say "restore rc=$r  id=$msg"
if {$r} { say "ABORTADO: no se pudo restaurar el estado"; exit 1 }
catch {activate_machine $msg} e2
say "activate=$e2"

# 1) Bytes parcheados en RAM
say [format "0x7FD0=%02X %02X (siembra)  0x708A=%02X %02X %02X (trampolin)  0x6600=%02X %02X (rutina)" \
     [debug read memory 0x7FD0] [debug read memory 0x7FD1] \
     [debug read memory 0x708A] [debug read memory 0x708B] [debug read memory 0x708C] \
     [debug read memory 0x6600] [debug read memory 0x6601]]

# Estado e instrumentacion
set ::sown {}
set ::passes 0
set ::disparado 0
set ::ficha 0
set ::ingame 0

proc contar_bit7 {cuando} {
    set d [debug read_block memory 0xCC00 0x33CC]
    binary scan $d c* vs
    set n 0
    foreach v $vs { if {$v < 0} { incr n } }
    say "celdas del mapa con bit7 ($cuando) = $n"
}

debug set_bp 0x7FB0 {} { incr ::passes; set ::sown {} }
debug set_bp 0x7FCC {} { lappend ::sown [expr {[reg BC] & 0xFF}] }
debug set_bp 0x7F86 {} {
    if {!$::disparado} { set ::disparado 1; reg A [expr {[reg A] | 0x10}]; say "disparo forzado (bit4 de A)" }
}
debug set_bp 0x6600 {} {
    incr ::ficha
    global OUT
    set f [open "$OUT/ficha_buf_$::ficha.bin" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory 0x7C17 240]
    close $f
    say "rutina de ficha (0x6600) llamada #$::ficha para la unidad [debug read memory 0x6EAD]"
}
debug set_bp 0x7F57 {} {
    if {!$::ingame} { set ::ingame 1; say "EN JUEGO: bucle de partida (0x7F57)"; contar_bit7 "antes del disparo" }
}

set throttle off
after time 2 { say "tecleo 0 para empezar"; type "0" }
after time 6 { if {!$::ingame} { say "reintento tecla 0"; type "0" } }

after time 25 {
    say "== RESULTADO =="
    say "pasadas de RECENTRA vistas = $::passes"
    set mx -1; set en 0; set am 0
    foreach c $::sown {
        if {$c > $mx} { set mx $c }
        if {$c >= 0x78} { incr en } else { incr am }
    }
    say "sembradas en la ultima pasada = [llength $::sown]  (amigas<0x78 = $am, enemigas>=0x78 = $en)  indice maximo = $mx"
    contar_bit7 "despues del disparo"
    set pres 0
    for {set n 0x78} {$n <= 0xFF} {incr n} {
        set x [expr {[debug read memory [expr {0xB900+$n}]] & 0x7F}]
        set y [expr {[debug read memory [expr {0xBA00+$n}]] & 0x7F}]
        if {$x || $y} { incr pres }
    }
    say "unidades enemigas (0x78-0xFF) con coordenadas en el mapa = $pres"
    say "veces que corrio la rutina de la ficha = $::ficha"
    set throttle on
    after realtime 2 {
        catch {screenshot -raw -doublesize $OUT/parche_juego.png} e
        say "screenshot=$e"
        say "FIN"
        exit 0
    }
}
