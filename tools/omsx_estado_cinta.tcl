# QUE DEJA LA CINTA CUANDO EL JUEGO ARRANCA: el estado de referencia
#
# El juego nunca escribe los registros 0-6 del VDP ni la tabla de nombres:
# hereda el `COLOR 1,1,1:SCREEN 2` de las dos lineas de BASIC de la cinta. El
# cartucho no tiene BASIC delante, asi que tiene que dejar el VDP, la VRAM y
# el PSG exactamente como los deja la cinta. Este script restaura el estado
# guardado en el instante en que la cinta llega a 0x5E00 (war_5e00.oms, hecho
# por omsx_arranque.tcl del parche) y vuelca todo lo que el cartucho debe
# reproducir.
#
#   WAR_STATE=<war_5e00.oms> WAR_OUT=<dir> openmsx -script este.tcl

set STATE $::env(WAR_STATE)
set OUT   $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/estado_cinta.log" w]
proc say {m} { global LOG; puts $LOG $m; flush $LOG }

set throttle off
catch {set renderer none}

set r [catch {set id [restore_machine $STATE]} msg]
say "restore_machine rc=$r: $msg"
if {$r} { say "ABORTADO"; exit 1 }
activate_machine $id
say "maquina activa: [machine_info config_name]"
say [format "PC=0x%04X SP=0x%04X" [reg PC] [reg SP]]
say "debuggables: [debug list]"

proc dumpd {name dbg addr size} {
    global OUT
    set f [open "$OUT/$name" w]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block $dbg $addr $size]
    close $f
    say "volcado $name <- $dbg\[$addr .. [expr {$addr+$size-1}]\] ($size bytes)"
}

dumpd ram_5e00.bin memory 0 0x10000
foreach {name dbg} {vram_5e00.bin VRAM vdpregs_5e00.bin {VDP regs} vdpstatus_5e00.bin {VDP status regs} psgregs_5e00.bin {PSG regs}} {
    if {[catch {set n [debug size $dbg]} e]} { say "sin debuggable '$dbg': $e"; continue }
    dumpd $name $dbg 0 $n
}
say [format "A8=0x%02X" [debug read ioports 0xA8]]
catch { say "slotselect: [debug read_block slotselect 0 4]" }
catch { say "slotmap: [openmsx_info ...]" }
say "FIN"
exit 0
