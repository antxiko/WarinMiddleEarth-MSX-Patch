# Comprueba MI_FUERZA: que devuelve la ficha de SU tipo en SU terreno.
#
# El original (0x8DE4) leia un byte cualquiera de la pagina 0x6D00 porque le
# llegaba el 0xC200 de la unidad en vez del tipo de tropa. MI_FUERZA coge el
# tipo de 0xBD00 -el llamador deja HL en 0xC200+n, o sea L = n- y lee
# 0x6D47 + tipo*16 + terreno.
#
# Aqui se le da a probar las 160 parejas (tipo, terreno) y se compara lo que
# devuelve con lo que dice la tabla leida de la RAM. Cada caso se prepara como
# lo dejaria el juego: 0xBD00+n con el tipo, HL en 0xC200+n y el terreno en
# 0x8DEA, que es donde lo escribe 0x902F.
#
# Uso:  WAR_OUT=<dir> openmsx -carta <rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set L [open "$OUT/comprueba_fuerza.log" w]
proc di {m} { global L; puts $L "\[[format %8.2f [machine_info time]]\] $m"; flush $L }
proc byte {a} { return [debug read memory $a] }

set ::caso 0
set ::malos 0
set ::hechos 0
set N 7

proc prepara {} {
    global N
    set tipo [expr {$::caso / 16}]
    set terr [expr {$::caso % 16}]
    debug write memory [expr {0xBD00 + $N}] $tipo
    debug write memory 0x8DEA $terr
    reg hl [expr {0xC200 + $N}]
    reg a 0
    reg pc 0x8DE4
}

proc recoge {} {
    set tipo [expr {$::caso / 16}]
    set terr [expr {$::caso % 16}]
    set v [reg a]
    set esperado [byte [expr {0x6D47 + $tipo * 16 + $terr}]]
    incr ::hechos
    if {$v != $esperado} {
        incr ::malos
        di "MAL: tipo $tipo terreno $terr -> $v, y la ficha dice $esperado"
    } elseif {$terr == 0} {
        di "  tipo $tipo: HL=[format 0x%04X [reg hl]] y devuelve $v (la ficha dice $esperado)"
    }
    incr ::caso
    if {$::caso < 160} { prepara; return }
    di "-------- $::hechos casos, $::malos mal --------"
    if {$::malos == 0} {
        di "MI_FUERZA devuelve la ficha correcta en los 160 casos."
        di "Con el original, esos mismos 160 daban un byte cualquiera de 0x6D00."
    }
    after realtime 1 {exit [expr {$::malos ? 1 : 0}]}
}

proc espera_carga {} {
    set f "[format %02X [byte 0x6D47]] [format %02X [byte 0x6D48]] [format %02X [byte 0x6D49]]"
    if {$f ne "03 FF FF"} { after time 1 espera_carga; return }
    di "el juego ya esta en la RAM (0x6D47 = $f)"
    debug set_bp 0x8DF1 {} {recoge}
    prepara
}
after time 2 espera_carga

set throttle off
after realtime 180 {di "se acabo el tiempo en el caso $::caso"; exit 3}
