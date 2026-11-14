# LAS TRES CANCIONES DE RUBEN, GRABADAS EN WAV DESDE EL CARTUCHO
#
# Arranca la ROM y, ya en el menu, le pide al puente cada cancion escribiendo
# PEDIDA (0 niebla, 1 taberna, 2 batalla), que es lo mismo que hacen el menu y
# los dos ganchos de la batalla. Graba WAR_SEGUNDOS de cada una en WAR_OUT.
#
#   WAR_OUT=<dir> WAR_DIRS=work/unificada/musica.tcl openmsx -machine <maq> \
#       -carta <rom> -romtype ascii16 -script tools/omsx_graba_musicas.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
source $::env(WAR_DIRS)
set SEG 40
if {[info exists ::env(WAR_SEGUNDOS)]} { set SEG $::env(WAR_SEGUNDOS) }
set LOG [open "$OUT/graba.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }
set throttle off
set ::nombres {niebla taberna batalla}

proc graba {n} {
    if {$n >= 3} { say "FIN" ; exit 0 }
    set nombre [lindex $::nombres $n]
    debug write memory $::PEDIDA $n
    # un cuadro para que el puente cambie, y a grabar
    after time 0.1 [list empieza $n $nombre]
}
proc empieza {n nombre} {
    record start -audioonly "$::OUT/$nombre"
    say "grabando $nombre (suena [debug read memory $::PUENTE_SONANDO])"
    after time $::SEG [list acaba $n]
}
proc acaba {n} {
    record stop
    graba [expr {$n + 1}]
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    debug remove_bp $::bp_menu
    say "en el menu"
    after time 0.5 { graba 0 }
}]
after realtime 300 { say "TIMEOUT" ; exit 1 }
