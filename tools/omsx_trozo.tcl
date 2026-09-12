# ¿EN QUE SE VAN LOS CICLOS DE UNA VUELTA DE LA VISTA, TRAMO A TRAMO?
#
# Hermana de tools/omsx_vista.tcl, pero con la vuelta partida mas fina. Con la
# tabla de nombres puesta, el 91 % de la vuelta es "dibujar el trozo", y eso son
# varias cosas: el relleno de la pantalla de caracteres, las TRES pasadas de
# DIBUJA_EL_TROZO_DE_MAPA (terreno, lo que va encima y las unidades), tapar los
# bordes, el cursor, las ventanas (posicion, ficha, sitio) y la subida a la
# VRAM. Esta sonda dice cuanto cuesta cada una: es lo que hace falta para
# decidir que se cachea y que no.
#
# Los tramos se nombran por el breakpoint que los ABRE; el siguiente los cierra.
# El reloj es `machine_info time`, como en omsx_vista.tcl.
#
#   WAR_OUT=<dir> [WAR_MUEVE=1] openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_trozo.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/trozo.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
catch {say "cartucho: [carta]"}

set ::Z80 3579545.0
set ::CUADRO [expr {$::Z80 / 50.0}]
set ::ESPACIO 0x01
set ::MUEVE [expr {[info exists ::env(WAR_MUEVE)] && $::env(WAR_MUEVE) ne "0"}]

# Cada marca abre el tramo que lleva su nombre y cierra el anterior.
set ::MARCAS {
    0x71F9 vuelta_arranca
    0x71A4 relleno_850
    0x7643 pasada_terreno
    0x764D pasada_encima
    0x7653 pasada_unidades
    0x71C1 tapa_bordes
    0x71C5 cursor
    0x71FC ventanas
    0x7218 nombres_a_vram
    0x721B mando_y_resto
}
set ::ORDEN {}
foreach {dir nombre} $::MARCAS { lappend ::ORDEN $nombre }

set ::suma [dict create]
set ::veces [dict create]
set ::ultimo_t -1.0
set ::ultimo ""
set ::midiendo 0
set ::t_vuelta -1.0
set ::suma_vuelta 0.0
set ::n_vuelta 0

proc marca {nombre} {
    set ahora [machine_info time]
    if {$::midiendo && $::ultimo ne "" && $::ultimo_t >= 0.0} {
        set d [expr {$ahora - $::ultimo_t}]
        if {$d > 0.0} {
            dict incr ::veces $::ultimo
            dict set ::suma $::ultimo [expr {[dict exists $::suma $::ultimo] ? [dict get $::suma $::ultimo] + $d : $d}]
        }
    }
    if {$nombre eq "vuelta_arranca"} {
        if {$::midiendo && $::t_vuelta >= 0.0} {
            set ::suma_vuelta [expr {$::suma_vuelta + $ahora - $::t_vuelta}]
            incr ::n_vuelta
        }
        set ::t_vuelta $ahora
    }
    set ::ultimo $nombre
    set ::ultimo_t $ahora
}
foreach {dir nombre} $::MARCAS {
    debug set_bp $dir {} [list marca $nombre]
}

proc informe {} {
    say "-------------------------------------------------------------"
    set total 0.0
    foreach tramo $::ORDEN {
        if {![dict exists $::veces $tramo]} { say [format "  %-16s no se ejecuto" $tramo]; continue }
        set n [dict get $::veces $tramo]
        set c [expr {[dict get $::suma $tramo] / $n * $::Z80}]
        set total [expr {$total + $c}]
        say [format "  %-16s %8.0f ciclos de media  x%d" $tramo $c $n]
    }
    if {$::n_vuelta > 0} {
        set c [expr {$::suma_vuelta / $::n_vuelta * $::Z80}]
        say [format "  %-16s %8.0f ciclos de media  (%5.2f cuadros)  x%d" VUELTA $c [expr {$c / $::CUADRO}] $::n_vuelta]
        say [format "  o sea %.1f vueltas por segundo" [expr {$::Z80 / $c}]]
    }
    say [format "  los tramos suman %.0f ciclos" $total]
}

set ::bp_mapa 0
proc en_el_mapa {} {
    say "en el mapa; ESPACIO para entrar a la vista"
    keymatrixdown 8 $::ESPACIO
    after time 0.4 {
        keymatrixup 8 $::ESPACIO
        after time 2 {
            set ::midiendo 1
            if {$::MUEVE} {
                say "midiendo MOVIENDO el cursor: 5 s a la derecha y 5 a la izquierda..."
                keymatrixdown 8 0x80
                after time 5 { keymatrixup 8 0x80; keymatrixdown 8 0x10 }
            } else {
                say "midiendo en reposo..."
            }
            after time 10 {
                set ::midiendo 0
                catch { keymatrixup 8 0x10 }
                say [expr {$::MUEVE ? "=== diez segundos MOVIENDO ===" : "=== diez segundos en reposo ==="}]
                informe
                say "FIN"
                exit 0
            }
        }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 {
        type "2"
        after time 2 {
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                debug remove_bp $::bp_mapa
                after time 2 { en_el_mapa }
            }]
        }
    }
}]

after time 120 { say "TIMEOUT"; informe; exit 1 }
