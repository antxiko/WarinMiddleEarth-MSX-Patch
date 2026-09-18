# ¿A CUANTAS CASILLAS POR SEGUNDO VA EL CURSOR DE LA BATALLA?
#
# MUEVE_EL_CURSOR_DE_BATALLA (0x8E0D) corre el cursor UNA casilla por vuelta
# del bucle de batalla, asi que su velocidad es la del bucle. Al subir al VDP
# solo lo que cambia, la vuelta paso de 0,3170 a 0,1068 s y el cursor se volvio
# ingobernable; MI_CURSOR_BATALLA lo limita a una casilla cada diez cuadros,
# igual que MI_MUEVE en el mapa.
#
# Aqui se mide LAS DOS COSAS EN LA MISMA BATALLA y en la misma partida: se
# mantiene una direccion pulsada dos segundos emulados con el parche puesto, y
# luego otros dos con los tres bytes de 0x8E10 devueltos a su `call
# LEE_LOS_MANDOS` original. Un cotejo entre dos ROMs distintas no valdria: las
# batallas no son iguales y la vuelta no dura lo mismo.
#
# La partida se arranca como work/rapido/mide_vuelta.tcl: menu, dos, cero, el
# reloj en marcha y destino al sur para las diez primeras unidades, que es lo
# que provoca encuentros.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_cursor_batalla.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/cursor_batalla.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
proc b {a} { return [debug read memory $a] }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
set ::ABAJO_DERECHA {8 0x80}      ; # la flecha derecha: bit 3 del mando, diagonal (+1,+1)
set ::SEGUNDOS 2.0
set ::DESDE_FILA 0x02             ; # se planta el cursor arriba a la izquierda para que quepa el recorrido
set ::DESDE_COL 0x02
set ::PARCHE {}                   ; # los tres bytes que hay hoy en 0x8E10
set ::ORIGINAL {0xCD 0x6D 0x06}   ; # el `call LEE_LOS_MANDOS` de la cinta
set ::fase 0                      ; # 0 esperando batalla, 1 con parche, 2 sin el, 3 hecho
set ::vueltas 0
set ::en_batalla 0
set ::montada 0                   ; # 0x9141 ya ha puesto el cursor en el centro
set ::pasos 0                     ; # escrituras de 0x8E0E que MUEVEN el cursor
set ::ultima -1
set ::medidas {}

# LA TRAMPA QUE COSTO UNA MEDIDA ENTERA: plantar el cursor nada mas empezar la
# batalla no sirve, porque 0x9141 lo recoloca en el centro (16,16) DESPUES, ya
# dentro de la ventana de medida. El recorrido salia contado desde donde no
# estaba: 18 casillas donde habian sido 4. Por eso se espera a 0x9141 y ademas
# se cuentan los pasos con un punto de observacion, que no depende de donde
# empiece ni de si topa con el borde.
debug set_watchpoint write_mem 0x8E0E {} {
    if {$::fase > 0 && [reg PC] == 0x8E60} {
        set v [debug read memory 0x8E0E]
        if {$::ultima >= 0 && $v != $::ultima} { incr ::pasos }
        set ::ultima $v
    }
}

proc lee_tres {dir} {
    set v {}
    for {set n 0} {$n < 3} {incr n} { lappend v [b [expr {$dir + $n}]] }
    return $v
}
proc escribe_tres {dir v} {
    set n 0
    foreach x $v { debug write memory [expr {$dir + $n}] $x ; incr n }
}
proc hex3 {v} {
    set s {}
    foreach x $v { append s [format %02X $x] }
    return $s
}

# --- arranque de la partida, como mide_vuelta.tcl ---------------------------
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
}
set ::fuego 0
proc fuego {} {
    if {$::fuego} { return }
    set ::fuego 1
    keymatrixdown {*}$::ESPACIO
    after time 0.4 { keymatrixup {*}$::ESPACIO ; after time 0.4 { set ::fuego 0 } }
}

# --- la medida --------------------------------------------------------------
proc arranca_fase {n} {
    set ::fase $n
    set ::vueltas 0
    set ::pasos 0
    debug write memory 0x8E0E $::DESDE_FILA
    debug write memory 0x8E0F $::DESDE_COL
    set ::ultima $::DESDE_FILA
    say "fase $n: cursor en ([b 0x8E0E],[b 0x8E0F]), 0x8E10 = [hex3 [lee_tres 0x8E10]]; derecha pulsada $::SEGUNDOS s"
    keymatrixdown {*}$::ABAJO_DERECHA
    after time $::SEGUNDOS remata_fase
}

proc remata_fase {} {
    keymatrixup {*}$::ABAJO_DERECHA
    if {!$::en_batalla} { say "  la batalla se acabo a mitad: se descarta" ; set ::fase 0 ; return }
    set casillas $::pasos
    set porseg [expr {$casillas / $::SEGUNDOS}]
    set vueltaseg [expr {$::vueltas / $::SEGUNDOS}]
    set como [expr {$::fase == 1 ? "con MI_CURSOR_BATALLA" : "como en la cinta"}]
    say [format "  %-22s %2d casillas en %.1f s = %5.2f casillas/s  (%d vueltas = %.1f vueltas/s)" \
        $como $casillas $::SEGUNDOS $porseg $::vueltas $vueltaseg]
    lappend ::medidas [list $::fase $casillas $porseg $vueltaseg]
    if {$::fase == 1} {
        escribe_tres 0x8E10 $::ORIGINAL
        say "  0x8E10 devuelto a [hex3 [lee_tres 0x8E10]]: el cursor vuelve a leer el mando en cada vuelta"
        after time 0.5 { arranca_fase 2 }
        return
    }
    escribe_tres 0x8E10 $::PARCHE
    remata
}

proc remata {} {
    say "-------------------------------------------------------------"
    set uno {} ; set dos {}
    foreach m $::medidas {
        if {[lindex $m 0] == 1} { set uno $m } else { set dos $m }
    }
    if {$uno eq "" || $dos eq ""} { say "FALTAN MEDIDAS: $::medidas" ; exit 1 }
    say [format "con el parche  %5.2f casillas/s ; sin el  %5.2f casillas/s  (x%.2f mas lento)" \
        [lindex $uno 2] [lindex $dos 2] [expr {[lindex $dos 2] / [lindex $uno 2]}]]
    say "FIN"
    exit 0
}

# --- los enganches ----------------------------------------------------------
debug set_bp 0x914E {} { incr ::vueltas }
debug set_bp 0x9021 {} {
    set ::en_batalla 1
    set ::montada 0
    say "BATALLA en la casilla [b 0x8F78],[b 0x8F79]"
}
# 0x9141, dentro del montaje, planta el cursor en el centro del tablero: hasta
# que no ha pasado no se puede colocar para medir.
debug set_bp 0x9141 {} {
    set ::montada 1
    if {$::fase == 0} { after time 1.0 { if {$::en_batalla && $::fase == 0} { arranca_fase 1 } } }
}
debug set_bp 0x91D1 {} { set ::en_batalla 0 ; say "  se acabo la batalla" }
debug set_bp 0x7564 {} { fuego }
debug set_bp 0x9264 {} { fuego }
debug set_bp 0x81E7 {} { reloj_en_marcha }
debug set_bp 0x7FD5 {} { reg PC 0x7FD8 }

set ::bp_menu [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_menu
    say "menu"
    after time 2 { type "2" ; after time 2 { type "0"
        set ::bp_mapa [debug set_bp 0x6A47 {} {
            debug remove_bp $::bp_mapa
            set ::PARCHE [lee_tres 0x8E10]
            say "0x8E10 trae [hex3 $::PARCHE]"
            after time 2 { en_marcha }
        }]
    } }
}]

after realtime 900 { say "TIMEOUT sin medir: fase=$::fase medidas=$::medidas" ; exit 1 }
