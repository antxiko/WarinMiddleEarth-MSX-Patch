# LA FICHA DE GOLLUM, POR EL CAMINO DEL JUGADOR
#
# El parche le cambia la raza a Gollum -la unidad 21- del tipo 8, que era suyo
# solo, al 6, el de los hobbits. Aqui se comprueba con el juego CORRIENDO: se
# entra en la vista de cerca, se teleporta el cursor a su casilla y se pulsa
# fuego, que es lo que hace el jugador; se lee el buffer de texto de la ficha
# (0x7C17, 24 columnas por fila) y el byte de su raza en la RAM viva (0xBD15).
#
# OJO CON LO QUE ESTO PUEDE PROBAR: en la ficha de una unidad CON NOMBRE la
# raza no sale. 0x6F2C mira si el numero es menor que 0x18 y, si lo es, copia
# el nombre de la lista de 0x6B46; NOMBRE_DEL_TIPO (0x6DF3) solo entra en las
# formaciones sin nombre y en el perseguido. O sea que buscar "Hobbit" en la
# ficha de Gollum no demuestra nada: lo que se comprueba aqui es que su ficha
# se sigue pintando y que el byte de la raza es el 6.
#
# No se le puede escribir el selector 0x6EAD desde el depurador para ver la
# ficha de otra unidad: el juego actua sobre ella y acaba pisando el parche. El
# unico camino que vale es este.
#
# La posicion de cada unidad son dos arrays: 0xB900+n y 0xBA00+n. Cual de los
# dos es la fila se prueba en el sitio: si con uno no sale su ficha, se prueba
# con el otro.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_ficha_gollum.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/ficha_gollum.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
proc b {a} { return [debug read memory $a] }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"

set ::ESPACIO {8 0x01}
# Por defecto Gollum, la 21; con WAR_UNIDAD se mira la ficha de otra (13 es
# Brand III, el nombre que el parche NO traduce).
set ::GOLLUM [expr {[info exists ::env(WAR_UNIDAD)] ? $::env(WAR_UNIDAD) : 21}]
set ::ESPERO [expr {[info exists ::env(WAR_TEXTO)] ? $::env(WAR_TEXTO) : "Gollum"}]
# El tipo que se espera en 0xBD00+n. Por defecto solo se comprueba en Gollum
# (la 21, que tiene que ser del 6); con WAR_TIPO se comprueba en cualquiera.
set ::TIPO [expr {[info exists ::env(WAR_TIPO)] ? $::env(WAR_TIPO) : ($::GOLLUM == 21 ? 6 : -1)}]
set ::intento 0
set ::entrar 0
set ::puesto 0
set ::teleporta 0
set ::acabado 0

proc texto {dir n} {
    set s ""
    for {set i 0} {$i < $n} {incr i} {
        set c [expr {[b [expr {$dir + $i}]] & 0x7F}]
        append s [expr {($c >= 32 && $c < 127) ? [format %c $c] : "."}]
    }
    return $s
}

proc filas_de_la_ficha {} {
    # la ventana de la ficha son 24 columnas desde 0x7C17, en filas de 34
    set r {}
    for {set f 0} {$f < 6} {incr f} {
        lappend r [texto [expr {0x7C17 + $f * 34}] 24]
    }
    return $r
}

proc mira {} {
    # `exit` no se lleva por delante los `after time` ya encolados, asi que sin
    # esta guarda el log seguia creciendo DESPUES del FIN, y con lineas que se
    # contradecian.
    if {$::acabado} { return }
    set ::acabado 1
    set filas [filas_de_la_ficha]
    say "ficha (intento $::intento):"
    foreach f $filas { say "    |$f|" }
    set todo [join $filas " "]
    if {![string match "*$::ESPERO*" $todo]} {
        incr ::intento
        if {$::intento > 1} { remata 1 "no he dado con la casilla de la unidad $::GOLLUM" ; return }
        say "esa no es su ficha: se prueban las coordenadas al reves"
        set ::acabado 0
        set ::teleporta 1
        set ::puesto 0
        return
    }
    say "en la ficha de la unidad $::GOLLUM sale \"$::ESPERO\""
    if {$::TIPO < 0} { remata 0 "" ; return }
    set raza [expr {[b [expr {0xBD00 + $::GOLLUM}]] & 0x0F}]
    say "su ficha se pinta, y su raza en la RAM viva (0x[format %04X [expr {0xBD00 + $::GOLLUM}]]) es el tipo $raza"
    if {$::TIPO == 6} {
        foreach {n quien} {6 Sam 7 Merry 8 Pippin} {
            say "    la unidad $n ($quien) es del tipo [expr {[b [expr {0xBD00 + $n}]] & 0x0F}]"
        }
    }
    if {$raza != $::TIPO} { remata 1 "NO es el $::TIPO: el parche no ha llegado a la RAM" ; return }
    remata 0 "LA UNIDAD $::GOLLUM ES DEL TIPO $::TIPO"
}

# OJO: el `exit` de openMSX NO corta el procedimiento, solo encola la salida, y
# lo que venga detras se ejecuta igual. Por eso se sale SIEMPRE por aqui y con
# un `return` detras de la llamada: sin eso el log seguia creciendo despues del
# FIN, y con lineas que se contradecian.
proc remata {codigo que} {
    if {$que ne ""} { say $que }
    say FIN
    exit $codigo
}

# El cursor solo vale como posicion en 0x721F, que es donde el juego lo lee.
debug set_bp 0x721F {} {
    if {$::teleporta && !$::puesto} {
        set x [b [expr {0xB900 + $::GOLLUM}]]
        set y [b [expr {0xBA00 + $::GOLLUM}]]
        if {$::intento == 0} { set h $y ; set l $x } else { set h $x ; set l $y }
        reg HL [expr {($h << 8) | $l}]
        set ::puesto 1
        say "cursor a HL=[format 0x%04X [expr {($h << 8) | $l}]] (unidad $::GOLLUM: 0xB900+n=$x, 0xBA00+n=$y)"
        after time 1.0 {
            keymatrixdown {*}$::ESPACIO
            after time 0.3 { keymatrixup {*}$::ESPACIO ; after time 1.5 { mira } }
        }
    }
}
debug set_bp 0x7F57 {} {
    if {$::entrar} { set ::entrar 0 ; keymatrixdown {*}$::ESPACIO
        after time 0.3 { keymatrixup {*}$::ESPACIO ; set ::teleporta 1 } }
}
set ::bp_menu [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_menu
    say "menu"
    after time 2 { type "2" ; after time 2 { type "0"
        set ::bp_mapa [debug set_bp 0x6A47 {} { debug remove_bp $::bp_mapa ; after time 2 { set ::entrar 1 } }]
    } }
}]
after realtime 600 { say "TIMEOUT" ; exit 1 }
