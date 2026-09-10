# UN PREVIO DE LOS TILES NUEVOS EN UNA PANTALLA DEL JUEGO DE VERDAD
#
# Los 128 tiles del mapa son datos puros en 0x9E00-0xA280, asi que no hace falta
# volver a cargar la cinta para verlos: se restaura el estado guardado, se
# conduce el juego hasta el mapa y ahi se ESCRIBEN los bytes nuevos en la RAM.
# A partir de ese momento pinta el juego, con su propia traduccion de atributos
# (ATRIBUTO_A_COLOR, 0x049F) y su propio VDP; lo unico prestado son los datos.
#
# OJO, dos trampas que ya costaron caro en este repositorio:
#   - lanzado con `-script` el emulador arranca con el renderer sin inicializar
#     y `screenshot` devuelve un PNG en negro. Hay que encenderlo a mano.
#   - meter los bytes NO redibuja nada. La pantalla ya pintada sigue como
#     estaba; hay que mover el cursor para que el juego rehaga el trozo de mapa.
#
#   WAR_OMS=<estado.oms> WAR_TILES=<fichero de 1152 bytes> WAR_OUT=<dir> \
#   WAR_TECLAS="t tecla;t FOTO;t POKE" [WAR_FIN=<segundos>] \
#       openmsx -machine Philips_VG_8020 -script este.tcl
set OMS   $::env(WAR_OMS)
set TILES $::env(WAR_TILES)
set OUT   $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/previo.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

set r [catch {
    set nuevo [restore_machine $OMS]
    set viejo [machine]
    if {$viejo ne ""} { delete_machine $viejo }
    activate_machine $nuevo
} msg]
say "restore rc=$r: $msg"
if {$r} { exit 1 }
set renderer SDLGL-PP
set throttle on

set n 0
proc foto {} {
    global OUT n
    incr n
    set f [format "%s/previo_%02d.png" $OUT $n]
    catch {screenshot $f} e
    say "foto $f -> $e"
}

# Los bytes nuevos, escritos uno a uno en 0x9E00. Se comprueba al vuelo: si lo
# que se relee no es lo que se escribio, ahi no hay RAM y el previo no vale.
proc mete_los_tiles {} {
    global TILES
    set f [open $TILES rb]
    set d [read $f]
    close $f
    set cuantos [string length $d]
    set malos 0
    for {set i 0} {$i < $cuantos} {incr i} {
        binary scan [string index $d $i] c v
        set v [expr {$v & 0xFF}]
        debug write memory [expr {0x9E00 + $i}] $v
        if {[debug read memory [expr {0x9E00 + $i}]] != $v} { incr malos }
    }
    say "metidos $cuantos bytes en 0x9E00, $malos no se releen igual"
}

if {[info exists ::env(WAR_TECLAS)]} {
    foreach par [split $::env(WAR_TECLAS) ";"] {
        lassign $par t k
        if {$k eq "FOTO"} {
            after realtime $t foto
        } elseif {$k eq "POKE"} {
            after realtime $t mete_los_tiles
        } elseif {$k eq "SPC"} {
            # El fuego por la matriz del MSX (fila 8, mascara 0x01) y MANTENIDO:
            # `type` lo suelta enseguida y el juego lee la matriz cada cuadro.
            after realtime $t { say "fuego"; keymatrixdown 8 0x01 }
            after realtime [expr {$t + 0.3}] { keymatrixup 8 0x01 }
        } else {
            after realtime $t [list apply {{k} { say "tecla '$k'"; type $k }} $k]
        }
    }
}
set FIN [expr {[info exists ::env(WAR_FIN)] ? $::env(WAR_FIN) : 30}]
after realtime $FIN { say "FIN"; exit 0 }
