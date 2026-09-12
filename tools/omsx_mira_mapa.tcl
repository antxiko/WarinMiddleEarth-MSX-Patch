# ¿SE QUEDA COLGADO AL ENTRAR AL MAPA?
#
# El usuario dice que al pasar del menu al mapa general "se queda ahi y no hace
# nada mas". Esta sonda separa las tres cosas que ese sintoma puede ser, que se
# ven distintas y no hay que confundirlas:
#
#   1. la CPU esta en un bucle cerrado (colgado de verdad);
#   2. la CPU corre por todas partes pero la pantalla no cambia sola, que es lo
#      normal en un juego de estrategia esperando ordenes;
#   3. la CPU corre y la pantalla NO reacciona a las teclas (colgado por dentro).
#
# Lo que mide, en este orden:
#   - los PC por los que pasa, muestreados (si son cuatro, es un bucle);
#   - la VRAM en varios instantes: si cambia sola, algo se dibuja;
#   - la RAM en varios instantes: si cambia, el juego avanza aunque no pinte;
#   - y luego pulsa teclas (R = menu del juego, 1 = pausa, 0) y vuelve a mirar
#     la VRAM. Esto es lo unico que distingue "esperando" de "colgado".
#
# Vale para el cartucho y para la cinta, que es con quien hay que compararlo:
#   WAR_OUT=<dir> [WAR_ESTADO=<war_5e00.oms>] [WAR_SEGUNDOS=20] \
#     openmsx -machine <maq> [-carta <rom> -romtype ascii16] -script este.tcl
#
# Sin WAR_ESTADO arranca del cartucho y espera al menu (PC 0x5E00). Con
# WAR_ESTADO restaura el estado de la CINTA, que ya esta en el menu.

set OUT $::env(WAR_OUT)
file mkdir $OUT
set SEG [expr {[info exists ::env(WAR_SEGUNDOS)] ? $::env(WAR_SEGUNDOS) : 20}]

set LOG [open "$OUT/mapa.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off

if {[info exists ::env(WAR_ESTADO)]} {
    set r [catch {
        set nuevo [restore_machine $::env(WAR_ESTADO)]
        set viejo [machine]
        if {$viejo ne ""} { delete_machine $viejo }
        activate_machine $nuevo
    } msg]
    say "estado restaurado rc=$r: $msg"
    if {$r} { exit 1 }
    set ::ORIGEN "cinta (estado $::env(WAR_ESTADO))"
} else {
    set ::ORIGEN "cartucho [carta]"
}
say "maquina: [machine_info config_name]"
say "origen: $::ORIGEN"

proc regs_vdp {} {
    set out {}
    for {set r 0} {$r < 28} {incr r} {
        lappend out [format %02X [debug read "VDP regs" $r]]
    }
    return [join $out " "]
}

proc vuelca {nombre} {
    global OUT
    set n [debug size VRAM]
    set f [open "$OUT/$nombre.vram" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block VRAM 0 $n]
    close $f
    say "VDP: [regs_vdp]"
    set f [open "$OUT/$nombre.ram" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory 0 0x10000]
    close $f
    say "volcado $nombre (VRAM $n + RAM 64K)"
}

# --------------------------------------------------------- muestreo de los PC
set ::pcs [dict create]
set ::muestras 0
set ::muestreando 0
proc muestrea {} {
    if {!$::muestreando} { return }
    dict incr ::pcs [reg PC]
    incr ::muestras
    after time 0.002 muestrea
}

proc informe_pcs {titulo} {
    say "--- $titulo: $::muestras muestras, [dict size $::pcs] PC distintos"
    set l {}
    dict for {pc n} $::pcs { lappend l [list $n $pc] }
    set l [lsort -integer -decreasing -index 0 $l]
    set i 0
    foreach e $l {
        say [format "      %04X  %d veces (%.1f%%)" [lindex $e 1] [lindex $e 0] \
                 [expr {100.0 * [lindex $e 0] / $::muestras}]]
        incr i
        if {$i >= 12} { break }
    }
    set f [open "$::env(WAR_OUT)/mapa.pcs" w]
    dict for {pc n} $::pcs { puts $f [format "%04X %d" $pc $n] }
    close $f
}

# --------------------------------------------------------------- el recorrido
# Paso 3: ya en el mapa. Se mira solo, sin tocar nada, y luego se le habla.
proc en_el_mapa {} {
    say "=============== EN EL MAPA. Se mira SIN TOCAR NADA ==============="
    set ::muestreando 1
    muestrea
    vuelca "mapa_00"
    after time 2 { vuelca "mapa_02" }
    after time 5 { vuelca "mapa_05" }
    after time 10 { vuelca "mapa_10" }
    after time $::SEG {
        vuelca "mapa_quieto"
        informe_pcs "quieto en el mapa"
        habla
    }
}

# Paso 4: las teclas. Del listado: R = menu del juego, 1 = pausa.
proc habla {} {
    say "=============== AHORA LAS TECLAS ==============="
    set ::pcs [dict create]
    set ::muestras 0
    say "se pulsa R (menu del juego)"
    type "r"
    after time 3 {
        vuelca "tras_R"
        say "se pulsa ESPACIO"
        type " "
        after time 3 {
            vuelca "tras_espacio"
            say "se pulsa 1 (pausa)"
            type "1"
            after time 3 {
                vuelca "tras_1"
                say "se pulsan las flechas (cursor)"
                flechas
            }
        }
    }
}

proc flechas {} {
    # Las flechas no son caracteres: van por la matriz de teclado. Fila 8:
    # bit 4 izquierda, 5 arriba, 6 abajo, 7 derecha.
    foreach b {4 5 6 7} {
        keymatrixdown 8 [expr {1 << $b}]
        after time 0.2 [list keymatrixup 8 [expr {1 << $b}]]
    }
    after time 3 {
        vuelca "tras_flechas"
        informe_pcs "despues de las teclas"
        say "FIN"
        exit 0
    }
}

# ------------------------------------------------------------- puesta en marcha
# Paso 2: en el menu, se pulsa 0 y se espera a que arranque la partida (0x6A47).
proc desde_el_menu {} {
    vuelca "menu"
    say "se pulsa 0 para empezar la partida"
    type "0"
    set ::bp_mapa [debug set_bp 0x6A47 {} {
        say "PC en 0x6A47: la partida ha arrancado"
        debug remove_bp $::bp_mapa
        after time 1 { en_el_mapa }
    }]
    after time 30 {
        if {!$::muestreando} {
            say "TIMEOUT: se pulso 0 y NUNCA se llego a 0x6A47 (PC = [format %04X [reg PC]])"
            vuelca "atascado_antes_del_mapa"
            set ::muestreando 1
            muestrea
            after time 3 { informe_pcs "atascado antes del mapa"; exit 1 }
        }
    }
}

if {[info exists ::env(WAR_ESTADO)]} {
    # El estado de la cinta ya esta en el menu.
    after time 3 { desde_el_menu }
} else {
    set ::bp_menu [debug set_bp 0x5E00 {} {
        say "PC en 0x5E00: el menu"
        debug remove_bp $::bp_menu
        after time 3 { desde_el_menu }
    }]
    after time 60 { say "TIMEOUT: no se llego al menu"; exit 1 }
}
