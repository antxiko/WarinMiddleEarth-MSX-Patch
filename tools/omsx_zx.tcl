# Vuelca la PANTALLA ZX EMULADA del juego (0x4000-0x57FF de bitmap y
# 0x5800-0x5AFF de atributos) y la dibuja despues tools/render_zx.py.
#
# Por que no una captura de pantalla: el juego resube la pantalla al VDP sin
# parar, asi que dos fotos del MISMO estado, separadas 3 s, ya difieren un 37 %
# de los pixels. Volcando la RAM en un instante fijo la imagen es determinista,
# y ademas se vuelca DOS veces para comprobar sobre los datos que ya no cambia
# (dos volcados a 15 s emulados: 32 bytes distintos, el parpadeo del cursor).
#
#   WAR_OMS=<estado.oms> WAR_OUT=<dir> WAR_CX=<col> WAR_CY=<fila> WAR_TAG=<nombre>
#   [WAR_ESPERA=<s>]    segundos emulados antes de volcar (40)
#   [WAR_UNIDAD=<n>]    para ver la ficha de esa unidad de la casilla
set OMS $::env(WAR_OMS)
set OUT $::env(WAR_OUT)
set CX  $::env(WAR_CX)
set CY  $::env(WAR_CY)
set TAG $::env(WAR_TAG)
set UNI [expr {[info exists ::env(WAR_UNIDAD)] ? $::env(WAR_UNIDAD) : -1}]
set ESPERA [expr {[info exists ::env(WAR_ESPERA)] ? $::env(WAR_ESPERA) : 40}]
file mkdir $OUT
set LOG [open "$OUT/zx_$TAG.log" w]
proc say {m} { global LOG; puts $LOG "t=[format %9.2f [machine_info time]]  $m"; flush $LOG }

catch {set renderer none}
set r [catch {restore_machine $OMS} id]
say "restore rc=$r id=$id  centro=($CX,$CY)  unidad=$UNI"
if {$r} { say "ABORTADO: no se pudo restaurar el estado"; exit 1 }
catch {activate_machine $id}

set ::CX $CX
set ::CY $CY
set ::TAG $TAG
set ::UNI $UNI
set ::st 0
set ::pulsos 0

proc vuelca {nombre addr size} {
    global OUT
    set f [open "$OUT/$nombre" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block memory $addr $size]
    close $f
}

# Centrar la vista donde se pida: se le escribe al cursor su posicion en la
# primera vuelta del bucle de partida y se le fuerza un disparo, que es lo que
# dispara RECENTRA_EL_MAPA.
#
# OJO: openMSX no encadena dos puntos de ruptura en la misma direccion -el
# segundo se pierde sin decir nada-, y un `return` dentro del cuerpo de uno lo
# mata para siempre, tambien en silencio.
debug set_bp 0x7F57 {} {
    if {$::st == 0} {
        debug write memory 0x6543 [expr {(($::CX-8)*2) & 0xFF}]
        debug write memory 0x6544 [expr {(($::CY-3)*2) & 0xFF}]
        set ::st 1
        say "cursor puesto en ($::CX,$::CY)"
    }
}
debug set_bp 0x7F86 {} {
    if {$::st == 1} { set ::st 2; reg A [expr {[reg A] | 0x10}]; say "disparo -> RECENTRA" }
}

# WAR_UNIDAD: para ver la ficha de una unidad concreta de la casilla, por el
# CAMINO DEL JUGADOR, sin tocar memoria.
#
# Escribirle el selector 0x6EAD desde el depurador NO vale: no es solo de
# dibujo, el resto del juego tambien lo usa, y dejarlo cambiado -aunque sea un
# instante- acaba sacando al juego de la vista y montando otra cosa encima. Se
# nota porque 0x7FD1 y 0x664C dejan de tener los bytes del parche. Tres pasadas
# costo, con el temporizador, con una sola escritura y guardando el valor viejo.
#
# El camino bueno esta en el propio listado: en BUCLE_DE_LA_VISTA, el disparo
# sobre una casilla con unidad (0x7229) entra en ELIGE_ENTRE_LAS_DE_LA_CASILLA
# (0x7751), y ahi "arriba" y "abajo" pasan de una unidad a otra repintando la
# ficha. Asi que se le da un disparo y luego "siguiente" hasta llegar.
if {$UNI >= 0} {
    set ::entrado 0
    debug set_bp 0x7229 {} {
        if {$::st == 2 && $::entrado == 0} {
            set ::entrado 1
            reg A [expr {[reg A] | 0x10}]
            say "disparo sobre la casilla -> elegir entre sus unidades"
        }
    }
    # 0x775B es el `bit 4,a` de MANDO_DE_LA_ELECCION, justo tras leer el mando:
    # bit 0 es "la siguiente de la casilla". Se pulsa hasta llegar a la pedida.
    debug set_bp 0x775B {} {
        if {[debug read memory 0x6EAD] != $::UNI && $::pulsos < 40} {
            incr ::pulsos
            reg A [expr {([reg A] & 0xCE) | 0x01}]
        }
    }
}

# El volcado va por TIEMPO EMULADO, no por punto de ruptura: tras el disparo el
# juego se queda repintando la vista de cerca (BUCLE_DE_LA_VISTA, 0x71F9) y no
# vuelve a pasar por 0x7F57 (medido: 393 s emulados sin una sola vuelta).
set throttle off
after time 2 { type "0" }
after time 6 { if {$::st == 0} { type "0" } }
after time $ESPERA {
    vuelca "zx_$TAG.bin" 0x4000 0x1B00
    vuelca "tabla_color_$TAG.bin" 0x0200 0x0100
    vuelca "mapa_$TAG.bin" 0xCC00 0x33CC
    say "volcada la pantalla ZX (t=$ESPERA)"
    say "ficha de la unidad [format 0x%02X [debug read memory 0x6EAD]] (el bp corrio $::pulsos veces)"
    say "parche: 0x7FD1=[format %02X [debug read memory 0x7FD1]]  0x708A=[format %02X [debug read memory 0x708A]]  0x664C=[format %02X [debug read memory 0x664C]]"
    after time 15 {
        vuelca "zx_${TAG}_b.bin" 0x4000 0x1B00
        say "segundo volcado 15 s despues (control de estabilidad)"
        say "FIN"
        exit 0
    }
}
after time 400 { say "TIMEOUT"; exit 2 }
