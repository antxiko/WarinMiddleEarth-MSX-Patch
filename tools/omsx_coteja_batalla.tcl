# LA BATALLA, ANTES Y DESPUES, EN LA MISMA BATALLA
#
# El .omr lleva la ROM de entonces dentro, asi que no se puede reproducir con
# la nueva. Pero el juego corre desde la RAM: se planta el replay dentro de una
# batalla y, si WAR_RUTINAS esta puesto, se le mete el codigo nuevo en la RAM
# -las tres rutinas y los cuatro parches- antes de dejarlo correr. Sin el, la
# misma batalla tal cual. Las dos pasadas dan los mismos ciclos y la misma VRAM
# si el cambio es correcto... salvo en lo que se quiere: el tiempo.
#
#   WAR_REPLAY=<omr> WAR_OUT=<dir> [WAR_RUTINAS=<bin>] [WAR_VUELTAS=n]
set REPLAY $::env(WAR_REPLAY)
set OUT $::env(WAR_OUT)
set RUTINAS [expr {[info exists ::env(WAR_RUTINAS)] ? $::env(WAR_RUTINAS) : ""}]
set VUELTAS [expr {[info exists ::env(WAR_VUELTAS)] ? $::env(WAR_VUELTAS) : 30}]
file mkdir $OUT
set LOG [open "$OUT/coteja.log" w]
proc di {m} { global LOG; puts $LOG $m; flush $LOG }
catch {set renderer none}
set throttle off
if {[catch {reverse loadreplay $REPLAY} m]} { di "rc: $m"; exit 1 }
reverse goto 340
di "plantado en t=[format %.1f [machine_info time]], dentro de la primera batalla"

if {$RUTINAS ne ""} {
    set f [open $RUTINAS r]; fconfigure $f -translation binary
    set r [read $f]; close $f
    debug write_block memory 0x3954 $r
    # Los cuatro parches, los mismos que mete tools/haz_rom.py
    foreach {dir bytes} [list 0x90A6 {0xCD 0x55 0x39} \
                              0x8849 {0xCD 0x5D 0x39} \
                              0x884C {0x00 0x00 0x00} \
                              0x8828 {0xCD 0x69 0x39}] {
        set i 0
        foreach b $bytes { debug write memory [expr {$dir + $i}] $b ; incr i }
    }
    debug write memory 0x3954 0x00      ; # el tablero ya esta subido: a subir por fichas
    if {[debug read memory 0x8828] != 0xCD || [debug read memory 0x3969] == 0} {
        di "NO HA ENTRADO EL CODIGO NUEVO"; exit 1
    }
    di "codigo nuevo metido: [string length $r] bytes en 0x3954 y los cuatro parches"
} else {
    di "sin tocar: la batalla tal cual"
}

set ::n 0
set ::t0 [machine_info time]
debug set_bp 0x914E {} {
    incr ::n
    if {$::n == $::VUELTAS} {
        set dt [expr {[machine_info time] - $::t0}]
        di [format "%d vueltas en %.4f s -> %.4f s por vuelta (%.0f ciclos)" \
            $::VUELTAS $dt [expr {$dt/$::VUELTAS}] [expr {$dt/$::VUELTAS*3579545.0}]]
        set f [open "$OUT/vram.bin" w]; fconfigure $f -translation binary
        puts -nonewline $f [debug read_block VRAM 0 0x4000]; close $f
        set f [open "$OUT/zx.bin" w]; fconfigure $f -translation binary
        puts -nonewline $f [debug read_block memory 0x4000 0x1B00]; close $f
        # LA PRUEBA BUENA, y no depende de comparar dos partidas: se guarda la
        # VRAM, se obliga a la vuelta siguiente a subir el tablero ENTERO
        # (TABLERO_SIN_SUBIR = 1) y se vuelve a mirar. Si lo que fue subiendo
        # ficha a ficha estaba completo, el refresco no cambia ni un byte.
        set ::vram_antes [debug read_block VRAM 0 0x4000]
        debug write memory 0x3954 0x01
        set ::n 0
        set ::refresco 1
        return
    }
    if {[info exists ::refresco] && $::n == 2} {
        set v [debug read_block VRAM 0 0x4000]
        set d 0
        for {set i 0} {$i < 0x4000} {incr i} {
            if {[string index $v $i] ne [string index $::vram_antes $i]} { incr d }
        }
        di "refresco completo despues: $d bytes de VRAM cambian (0 = lo que se subio por fichas estaba entero)"
        di FIN
        exit 0
    }
}
after time 400 { di "TIMEOUT n=$::n"; exit 1 }
