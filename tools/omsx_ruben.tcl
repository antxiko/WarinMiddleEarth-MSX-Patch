# LAS PANTALLAS Y LAS CANCIONES DE RUBEN, EN UNA PARTIDA DE VERDAD
#
# Lo que comprueba (make verifica_ruben, y el cotejo lo hace
# tools/coteja_ruben.py con lo que deja aqui):
#
#   1. la PORTADA: la VRAM al llegar el juego a 0x5E00 (el cargador acaba de
#      repintar la imagen de carga)                       -> vram_portada.bin
#   2. que cancion suena en cada fase, y que el PSG se escribe en ella:
#      el menu (0, niebla), la partida (1, taberna), la batalla (2) y la
#      vuelta al mapa despues de la batalla (1)          -> ruben.log
#   3. que NADIE mas que el cargador escribe en la RAM de las canciones, y
#      nadie mas que el reproductor en su area de trabajo (0x5C00)
#   4. las dos FINALES: se pone PC en 0x83E7 con HL = 0x094F y luego 0x244F,
#      como hacen VICTORIA y DERROTA, y al llegar a F_PARADO se vuelca la VRAM,
#      el PSG y el gancho                  -> vram_victoria.bin, vram_derrota.bin
#
# La partida se arranca como tools/omsx_fondo_batalla.tcl: menu, dos, cero, el
# reloj en marcha y destino al sur para las diez primeras unidades.
#
#   WAR_OUT=<dir> WAR_DIRS=work/unificada/musica.tcl openmsx -machine <maq> \
#       -carta <rom> -romtype ascii16 -script tools/omsx_ruben.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/ruben.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
proc b {a} { return [debug read memory $a] }
source $::env(WAR_DIRS)

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::NOMBRES {niebla taberna batalla}

proc guarda {nombre datos} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f $datos
    close $f
}

# Las escrituras al PSG (puerto 0xA1) por fase: si la cancion suena, el
# reproductor las hace en cada cuadro.
set ::psg 0
debug set_watchpoint write_io 0xA1 {} { incr ::psg }

proc fase {que esperada} {
    set s [b $::PUENTE_SONANDO]
    set p [b $::PEDIDA]
    set ::psg 0
    after time 1 [list fase_fin $que $esperada $s $p]
}
proc fase_fin {que esperada s p} {
    set s2 [b $::PUENTE_SONANDO]
    set nombre [lindex $::NOMBRES $s2]
    if {$s2 == $esperada && $::psg > 0} { set v "BIEN" } else { set v "MAL" }
    say "FASE $que: suena la $s2 ($nombre), pedida $p, esperada $esperada; $::psg escrituras al PSG en 1 s -> $v"
}

# Quien escribe donde no debe. Se arman al llegar al menu: antes, el que
# escribe es el cargador, y es lo que tiene que hacer.
set ::intrusos_canciones {}
set ::intrusos_wyz {}
proc arma_vigilancia {} {
    debug set_watchpoint write_mem [list $::CANCIONES_INI $::CANCIONES_FIN] {} {
        if {[llength $::intrusos_canciones] < 20} {
            lappend ::intrusos_canciones [format "PC=0x%04X en 0x%04X" [reg PC] $::wp_last_address]
        }
    }
    debug set_watchpoint write_mem [list $::WYZ_AREA_INI $::WYZ_AREA_FIN] {} {
        set pc [reg PC]
        if {($pc < $::MUSICA_INI || $pc > $::MUSICA_FIN) && [llength $::intrusos_wyz] < 20} {
            lappend ::intrusos_wyz [format "PC=0x%04X en 0x%04X" $pc $::wp_last_address]
        }
    }
    say "vigilando 0x[format %04X $::CANCIONES_INI]-0x[format %04X $::CANCIONES_FIN] (canciones) y 0x[format %04X $::WYZ_AREA_INI]-0x[format %04X $::WYZ_AREA_FIN] (WYZ)"
}

proc reloj_en_marcha {} {
    debug write memory 0x7F66 0x19
    debug write memory 0x7F67 0x67
    debug write memory 0x7F6C 0x1B
    debug write memory 0x7F6D 0x83
}
proc en_marcha {} {
    reloj_en_marcha
    for {set n 0} {$n < 10} {incr n} {
        debug write memory [expr {0xB900 + $n}] [expr {[b [expr {0xB900 + $n}]] & 0x7F}]
        debug write memory [expr {0xBA00 + $n}] [expr {[b [expr {0xBA00 + $n}]] & 0x7F}]
        debug write memory [expr {0xBB00 + $n}] 0x66
        debug write memory [expr {0xBC00 + $n}] 0x3D
    }
    say "partida en marcha, destino (0x66,0x3D) para las diez primeras unidades"
    fase "partida" 1
}
set ::fuego 0
proc fuego {} {
    if {$::fuego} { return }
    set ::fuego 1
    keymatrixdown {*}$::ESPACIO
    after time 0.4 { keymatrixup {*}$::ESPACIO ; after time 0.4 { set ::fuego 0 } }
}

set ::batallas 0
debug set_bp 0x9021 {} { incr ::batallas ; say "BATALLA en la casilla [b 0x8F78],[b 0x8F79]" }
debug set_bp 0x9141 {} { if {$::batallas == 1} { after time 1 { fase "batalla" 2 } } }
debug set_bp 0x91D1 {} { say "  se acabo la batalla" }
set ::a_las_finales 0
debug set_bp 0x920A {} {
    if {$::batallas == 1 && !$::a_las_finales} {
        set ::a_las_finales 1
        fase "despues de la batalla" 1
        after time 1.5 { set ::a_las_finales 2 }
    }
}
debug set_bp 0x7564 {} { fuego }
debug set_bp 0x9264 {} { fuego }
debug set_bp 0x81E7 {} { reloj_en_marcha }
debug set_bp 0x7FD5 {} { reg PC 0x7FD8 }

# LAS FINALES. En el bucle de partida, y solo cuando ya se ha visto todo lo de
# arriba: PC a 0x83E7 con la HL de VICTORIA; al pararse, la de DERROTA.
set ::finales {0x094F victoria 0x244F derrota}
set ::cual 0
proc a_la_final {} {
    set hl [lindex $::finales [expr {$::cual * 2}]]
    set nombre [lindex $::finales [expr {$::cual * 2 + 1}]]
    say "FINAL $nombre: PC a 0x83E7 con HL = $hl"
    reg HL $hl
    reg PC 0x83E7
}
debug set_bp 0x7F57 {} {
    if {$::a_las_finales == 2} {
        set ::a_las_finales 3
        say "intrusos en la RAM de las canciones: [llength $::intrusos_canciones] $::intrusos_canciones"
        say "intrusos en el area del WYZ: [llength $::intrusos_wyz] $::intrusos_wyz"
        a_la_final
    }
}
debug set_bp $::F_PARADO {} {
    # el bucle cerrado vuelve a pasar por aqui hasta que el `exit` surte efecto
    if {$::cual >= 2} { return }
    set nombre [lindex $::finales [expr {$::cual * 2 + 1}]]
    set f [open "$::OUT/vram_$nombre.bin" wb]
    fconfigure $f -translation binary
    for {set i 0} {$i < 0x4000} {incr i} { puts -nonewline $f [binary format c [debug read "VRAM" $i]] }
    close $f
    set vol {}
    foreach r {8 9 10} { lappend vol [debug read "PSG regs" $r] }
    say "  parada: gancho [format 0x%04X [expr {[b 0x0415] + 256*[b 0x0416]}]], volumenes $vol, R1 [format 0x%02X [debug read {VDP regs} 1]], IFF [reg IFF]"
    incr ::cual
    if {$::cual < 2} {
        a_la_final
    } else {
        say "FIN"
        exit 0
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_menu
    say "PC en 0x5E00: el juego arranca; se vuelca la VRAM (la portada)"
    guarda "vram_portada.bin" [debug read_block VRAM 0 0x4000]
    arma_vigilancia
    after time 1 { fase "menu" 0 }
    after time 3 { type "2" ; after time 2 { type "0" ; after time 3 { en_marcha } } }
}]

after realtime 400 { say "TIMEOUT" ; exit 1 }
