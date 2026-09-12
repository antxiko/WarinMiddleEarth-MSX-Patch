# ¿A CUANTAS CASILLAS POR SEGUNDO VA EL CURSOR CON LA TECLA PULSADA?
#
# Con la ventana fija la vuelta de la vista va a mas de 40 por segundo, y el
# cursor avanzaba una casilla por vuelta: MI_MUEVE lo limita a una casilla
# cada diez cuadros. Aqui se entra en la vista, se mantiene la derecha pulsada
# DOS SEGUNDOS de tiempo emulado y se cuenta cuantas columnas avanzo HL. A
# 50 Hz tienen que ser 10; en una ROM sin el limite salen mas de 50.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 -script tools/omsx_paso_cursor.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/paso_cursor.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::DERECHA {8 0x80}
set ::k 0
set ::entrar 0
set ::desde -1

debug set_bp 0x71F1 {} { keymatrixup {*}$::ESPACIO }
debug set_bp 0x7599 {} { keymatrixup {*}$::ESPACIO }
# HL solo vale como posicion en 0x721F: el `after time` cae en cualquier
# instruccion, asi que ahi solo se suelta la tecla y se cuenta en la vuelta
# siguiente (con una casilla de mas como mucho, si la lectura ya habia pasado).
set ::acabar 0
debug set_bp 0x721F {} {
    incr ::k
    if {$::acabar} {
        set hasta [expr {[reg HL] & 0x7F}]
        say "columna $hasta: [expr {$hasta - $::desde}] casillas en 2 s = [expr {($hasta - $::desde) / 2.0}] por segundo (vuelta $::k)"
        say "FIN"
        exit 0
    }
    if {$::k == 3} {
        set ::desde [expr {[reg HL] & 0x7F}]
        say "vuelta 3: columna [set ::desde]; derecha pulsada durante 2 s"
        keymatrixdown {*}$::DERECHA
        after time 2 { keymatrixup {*}$::DERECHA; set ::acabar 1 }
    }
}
debug set_bp 0x7F57 {} {
    if {$::entrar} { set ::entrar 0; keymatrixdown {*}$::ESPACIO }
}
set ::bp_menu [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_menu
    after time 2 { type "2"; after time 2 { type "0"
        set ::bp_mapa [debug set_bp 0x6A47 {} { debug remove_bp $::bp_mapa; after time 2 { set ::entrar 1 } }] } }
}]
after time 120 { say "TIMEOUT"; exit 1 }
