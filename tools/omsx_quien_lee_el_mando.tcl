# ¿QUIEN LEE EL MANDO AQUI, Y A QUE VELOCIDAD SE MUEVE?
#
# Un tester dice que en tal sitio "va a toda hostia" al pulsar arriba y abajo.
# Para saber QUE hay que frenar, no vale suponer: se carga su replay, se deja
# al final, se mantiene una direccion pulsada y se anota QUIEN llama a
# LEE_LOS_MANDOS (0x066D) -por la direccion de retorno que hay en la pila- y
# cuantas veces por segundo.
#
# Asi sale el sitio exacto donde meter el limite, igual que se hizo con
# MI_MUEVE (mapa), MI_ELECCION (menu de la casilla) y MI_CURSOR_BATALLA.
#
#   WAR_REPLAY=<omr> WAR_OUT=<dir> openmsx -script tools/omsx_quien_lee_el_mando.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/mando.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer SDLGL-PP}
say "abriendo el replay"

set ::LEE_LOS_MANDOS 0x066D
set ::ARRIBA {8 0x20}
set ::ABAJO {8 0x40}
set ::SEGUNDOS 3.0
set ::llamadores [dict create]
set ::lecturas 0
set ::midiendo 0

# Quien llama: la direccion de retorno esta en el tope de la pila al entrar.
# Los pasos de verdad: SIGUIENTE_DE_LAS_TUYAS y ANTERIOR_DE_LAS_TUYAS.
set ::pasos 0
debug set_bp 0x7573 {} { if {$::midiendo} { incr ::pasos } }
debug set_bp 0x757C {} { if {$::midiendo} { incr ::pasos } }

debug set_bp $::LEE_LOS_MANDOS {} {
    if {$::midiendo} {
        incr ::lecturas
        set sp [reg SP]
        set v [expr {[debug read memory $sp] | ([debug read memory [expr {$sp+1}]] << 8)}]
        dict incr ::llamadores [format 0x%04X $v]
    }
}

proc remata {} {
    keymatrixup {*}$::ARRIBA
    keymatrixup {*}$::ABAJO
    set ::midiendo 0
    say "-------------------------------------------------------------"
    say [format "%d lecturas del mando en %.1f s = %.0f por segundo" \
             $::lecturas $::SEGUNDOS [expr {$::lecturas / $::SEGUNDOS}]]
    say "quien lo lee (direccion de retorno -> veces):"
    foreach {pc n} [list {*}$::llamadores] { say "   $pc   $n" }
    set f [open "$OUT/mando.txt" w]
    puts $f "lecturas $::lecturas"
    puts $f "pasos $::pasos"
    puts $f "segundos $::SEGUNDOS"
    foreach {pc n} [list {*}$::llamadores] { puts $f "llamador $pc $n" }
    close $f
    say "FIN"
    after realtime 1 { exit 0 }
}

set r [catch {reverse loadreplay $::env(WAR_REPLAY)} msg]
say "loadreplay rc=$r: $msg"

after realtime 3 {
    catch {reverse goto [dict get [reverse status] end]}
    after realtime 2 {
        catch {reverse stop}
        say "en el final del replay; se pulsa ABAJO $::SEGUNDOS s"
        set ::midiendo 1
        keymatrixdown {*}$::ABAJO
        after time $::SEGUNDOS remata
    }
}

after realtime 90 { say "TIMEOUT" ; exit 1 }
