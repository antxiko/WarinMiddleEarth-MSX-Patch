# GRABA LA SECUENCIA DEL PSG, UN VOLCADO POR CUADRO DE MUSICA
#
# Para cotejar dos ROMs que tocan LA MISMA cancion: si el reproductor y el
# modulo son los mismos, la secuencia de registros tiene que ser la misma. Es la
# unica forma objetiva de distinguir "suena" de "suena BIEN": que el PSG se
# mueva no dice nada sobre si se mueve como debe.
#
# LA MUESTRA VA ENGANCHADA AL PROPIO REPRODUCTOR, no al reloj. El reproductor
# escribe los 14 registros seguidos, del 0 al 13, una vez por cuadro; asi que
# cada escritura del registro 0 abre un volcado nuevo y cierra el anterior. Asi
# no hace falta saber donde vive el reproductor en cada ROM ni acertar con la
# duracion del cuadro.
#
# La primera version muestreaba con `after time 0.02`. Un cuadro PAL dura
# 0,019968 s, asi que el muestreo resbalaba y se saltaba volcados en momentos
# distintos en cada ROM: las dos grabaciones salian desfasadas y parecia que la
# musica perdia cuadros cuando el que los perdia era el medidor.
#
#   WAR_OUT=<dir> WAR_NOMBRE=<como.psg> [WAR_CUADROS=N] \
#     openmsx -machine <maquina> -carta <rom> [-romtype <tipo>] -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set NOMBRE $::env(WAR_NOMBRE)
set CUADROS 300
if {[info exists ::env(WAR_CUADROS)] && $::env(WAR_CUADROS) ne ""} {
    set CUADROS $::env(WAR_CUADROS)
}

set LOG [open "$OUT/$NOMBRE" w]
catch {set renderer none}
set throttle off

set ::reg 0
set ::n 0
set ::hay 0
set ::vals [lrepeat 14 0]
set ::CUADROS $CUADROS

proc emite {} {
    if {!$::hay} { return }
    incr ::n
    set out {}
    foreach v $::vals { lappend out [format %02X $v] }
    puts $::LOG "[format %4d $::n] [join $out " "]"
    if {$::n >= $::CUADROS} {
        flush $::LOG
        close $::LOG
        exit 0
    }
}

debug set_watchpoint write_io 0xA0 {} { set ::reg $::wp_last_value }
debug set_watchpoint write_io 0xA1 {} {
    if {$::reg == 0} {
        emite                       ; # se cierra el volcado anterior
        set ::hay 1
    }
    if {$::reg < 14} { lset ::vals $::reg $::wp_last_value }
}

after time 120 {
    catch {flush $::LOG; close $::LOG}
    exit [expr {$::n > 0 ? 0 : 1}]
}
