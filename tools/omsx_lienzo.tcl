# EL MAPA GENERAL: EL LIENZO, LA PANTALLA Y EL GUANTE
#
# Vuelca lo que hace falta para cotejar el mapa general de dos ROMs sin
# depender de ninguna herramienta que lo interprete:
#
#   terreno.bin    RAM 0x4000-0x57FF en 0x81C1, o sea justo cuando las dos
#                  pasadas de terreno acaban y antes de subirlo al VDP. Es lo
#                  que tools/mapa_general.py tiene que sacar clavado.
#   <n>.ram        RAM 0x4000-0x5AFF (bitmap y atributos) en la vuelta n del
#                  bucle de partida
#   <n>.vram       los 16 KB de VRAM en esa misma vuelta
#   <n>.txt        el cursor (0x6543/0x6544), los 24 bytes de fondo que el
#                  sprite por software guarda en 0x62FF y la direccion de
#                  pantalla de 0x64DA: con eso se borra el guante del lienzo
#                  de la ROM vieja para poder compararlo con el de la nueva
#
# Y de paso MIDE: los ciclos de DIBUJA_EL_MAPA (de 0x8166 a 0x81E7) y los de
# una vuelta del bucle de partida.
#
# Las pulsaciones van por vueltas del bucle, no por reloj: las dos ROMs van a
# distinta velocidad y por reloj no verian la misma partida.
#
#   WAR_OUT=<dir> [WAR_VUELTAS=a,b,c] openmsx -machine <maq> -carta <rom> \
#       -romtype ascii16 -script tools/omsx_lienzo.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/lienzo.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer SDLGL-PP}
set throttle off
say "maquina: [machine_info config_name]"

set ::Z80 3579545.0
set ::ABAJO {8 0x40}
set ::DERECHA {8 0x80}
proc tecla_abajo {t} { keymatrixdown {*}$t }
proc tecla_arriba {t} { keymatrixup {*}$t }

# Las vueltas en las que se vuelca: al entrar, tras mover a la derecha y tras
# mover abajo. La ultima es tambien el final. La primera NO puede ser la 1 ni
# la 2: el volcado se hace al entrar en la vuelta, ANTES de que REFRESCA_EL_CURSOR
# suba el recuadro, y hasta la tercera la ROM vieja tiene el guante estampado en
# el lienzo pero todavia no en la VRAM.
set ::VUELTAS {5 45 70}
if {[info exists ::env(WAR_VUELTAS)]} { set ::VUELTAS [split $::env(WAR_VUELTAS) ,] }

proc guarda {nombre datos} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f $datos
    close $f
}

proc hex {debuggable dire n} {
    set s ""
    for {set i 0} {$i < $n} {incr i} {
        append s [format %02X [debug read $debuggable [expr {$dire + $i}]]]
    }
    return $s
}

proc vuelca {n} {
    global OUT
    guarda "$n.ram" [debug read_block memory 0x4000 0x1B00]
    guarda "$n.vram" [debug read_block VRAM 0 0x4000]
    set f [open "$OUT/$n.txt" w]
    puts $f "col [debug read memory 0x6543]"
    puts $f "fila [debug read memory 0x6544]"
    puts $f "fondo [hex memory 0x62FF 24]"
    puts $f "direccion [hex memory 0x64DA 2]"
    puts $f "borrado [debug read memory 0x64D9]"
    puts $f "regs [hex {VDP regs} 0 8]"
    close $f
    say "vuelta $n: cursor [debug read memory 0x6543],[debug read memory 0x6544] direccion [hex memory 0x64DA 2] borrado [format %02X [debug read memory 0x64D9]]"
}

# --- LA PANTALLA SE APAGA antes de dibujar el mapa. Con la pantalla encendida
# el TMS9918 no admite dos accesos a la VRAM a menos de unos 29 ciclos y al que
# va mas rapido se le caen bytes; el `call 005bdh` de 0x81C1 -que es del juego,
# no del cartucho- va mas rapido, asi que en un MSX1 pierde bytes SIEMPRE, con
# cartucho y sin el (ver INVESTIGACION.md). Como las dos ROMs no pierden los
# mismos, con la pantalla encendida el cotejo no compararia el cambio sino el
# ruido. Se apaga quitando SOLO el bit 6 de R1: el bit 1 -sprites de 16x16- hay
# que conservarlo. Con WAR_PANTALLA=encendida no se apaga, que es como se mide
# cuantos bytes se pierden.
set ::APAGAR [expr {![info exists ::env(WAR_PANTALLA)] || $::env(WAR_PANTALLA) ne "encendida"}]
set ::apagada 0

# --- la medida de DIBUJA_EL_MAPA: 0x8166 entra, 0x81E7 sale
set ::t_mapa 0
debug set_bp 0x8166 {} {
    if {$::APAGAR && !$::apagada} {
        set r1 [debug read "VDP regs" 1]
        debug write "VDP regs" 1 [expr {$r1 & 0xBF}]
        set ::apagada 1
        say [format "pantalla apagada antes de dibujar el mapa (R1 = 0x%02X -> 0x%02X)" $r1 [expr {$r1 & 0xBF}]]
    }
    set ::t_mapa [machine_info time]
}
debug set_bp 0x81E7 {} {
    if {$::t_mapa > 0} {
        say [format "DIBUJA_EL_MAPA: %.0f ciclos (%.3f s)" \
                 [expr {([machine_info time] - $::t_mapa) * $::Z80}] \
                 [expr {[machine_info time] - $::t_mapa}]]
        set ::t_mapa 0
    }
}

# --- el lienzo del terreno, en cuanto las dos pasadas acaban
set ::bp_terreno [debug set_bp 0x81C1 {} {
    debug remove_bp $::bp_terreno
    guarda "terreno.bin" [debug read_block memory 0x4000 0x1800]
    say "terreno.bin: el lienzo con las dos pasadas hechas"
}]

# --- el bucle de partida. El punto de corte es 0x7F5A, o sea DESPUES de la
# primera linea: en la ROM vieja ahi ya ha corrido REFRESCA_EL_CURSOR (y la
# VRAM es el lienzo) y en la nueva ha corrido MI_GUANTE (y los sprites estan
# donde dice el cursor). Cortando en 0x7F57 se mira medio paso antes y las dos
# van una vuelta atrasadas.
set ::k 0
set ::t_vuelta 0
set ::suma 0.0
set ::veces 0
debug set_bp 0x7F5A {} {
    incr ::k
    if {$::t_vuelta > 0} {
        set ::suma [expr {$::suma + [machine_info time] - $::t_vuelta}]
        incr ::veces
    }
    set ::t_vuelta [machine_info time]
    if {[lsearch -exact $::VUELTAS $::k] >= 0} { vuelca $::k }
    if {$::k == [lindex $::VUELTAS end]} {
        if {$::veces} {
            say [format "una vuelta del bucle de partida: %.0f ciclos, %.1f por segundo" \
                     [expr {$::suma / $::veces * $::Z80}] [expr {$::veces / $::suma}]]
        }
        say "FIN"
        exit 0
    }
    # entre el primer volcado y el segundo, a la derecha; despues, abajo
    set a [lindex $::VUELTAS 0]
    set b [lindex $::VUELTAS 1]
    set c [lindex $::VUELTAS 2]
    if {$::k > $a && $::k < $b} {
        if {($::k - $a) % 2} { tecla_abajo $::DERECHA } else { tecla_arriba $::DERECHA }
    } elseif {$::k > $b && $::k < $c} {
        if {($::k - $b) % 2} { tecla_abajo $::ABAJO } else { tecla_arriba $::ABAJO }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 { type "2"; after time 2 { type "0" } }
}]

after realtime 180 { say "TIMEOUT en la vuelta $::k"; exit 1 }
