# LAS DOS PANTALLAS FINALES DEL CARTUCHO EN openMSX: ¿salen como salian?
#
# Lo dificil de comprobar esto no es escribirlo, es PROBARLO: para ver una
# pantalla final hay que terminarse el juego. Asi que la sonda lo fuerza.
#
# Arranca la ROM, deja llegar al menu, pulsa el 0 que empieza la partida y
# despues pone el PC en PINTA_LA_PANTALLA_FINAL (0x83E7) con HL en la pantalla
# que toca, que es exactamente el estado con el que el juego llega ahi desde
# cualquiera de sus cuatro finales. Luego espera a 0x83EF -la instruccion
# siguiente, el `call 005bdh` que sube el bitmap al VDP- y vuelca:
#
#   pantalla_N.bin   los 6.912 bytes de 0x4000-0x5AFF, que es lo unico que el
#                    juego lee: de ahi los sacan 0x05BD y 0x0604
#   vram_N.bin       la VRAM entera despues de pintarla, para poder cotejar
#                    dos ROMs entre si
#
# Y apunta SP y el estado de las interrupciones al llegar, que es la suposicion
# en la que se apoya la rutina: la pila del juego vive en la pagina 1, la misma
# que la rutina conmuta un momento para escribir el registro del mapper.
#
#   WAR_ROM=<rom> WAR_OUT=<dir> \
#     openmsx -machine <maquina> -carta <rom> -romtype ascii16 -script este.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/finales.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
say "cartucho: [carta]"

# Donde los cuatro finales convergen, y las dos pantallas que piden.
set ::PINTA      0x83E7
set ::TRAS_PINTA 0x83EF
set ::FIN_JUEGO  0x83F5
set ::PANTALLAS  {0x094F 0x244F}
set ::NOMBRES    {victoria derrota}
set ::DESTINO    0x4000
set ::TAM        6912

set ::cual 0
set ::bp_tras -1
set ::bp_fin -1

proc vuelca {ruta ini n} {
    set f [open $ruta wb]
    fconfigure $f -translation binary
    for {set i 0} {$i < $n} {incr i} {
        puts -nonewline $f [binary format c [debug read memory [expr {$ini + $i}]]]
    }
    close $f
}

proc vuelca_vram {ruta} {
    set f [open $ruta wb]
    fconfigure $f -translation binary
    # El debuggable "VRAM" devuelve 128 KB aunque la maquina tenga 16: solo se
    # quiere el primer banco, que es el que usa el juego.
    for {set i 0} {$i < 0x4000} {incr i} {
        puts -nonewline $f [binary format c [debug read "VRAM" $i]]
    }
    close $f
}

# ---------------------------------------------------- que el cotejo sea justo
# Forzar el PC a mitad de una partida deja dos cosas al azar, y las dos
# ensucian la comparacion de la VRAM entre dos ROMs:
#
#   1. La INTERRUPCION del juego sigue viva y repinta el mapa mientras 0x05BD
#      sube el bitmap. Se cierra en el VDP -bit 5 de R1, que es quien las pide-
#      y no en la RAM del juego: asi no se toca un solo byte de lo que se esta
#      comprobando, y se hace igual en las dos pasadas.
#
#      Ojo con la salida facil: poner `ei / ret` en 0x0038 NO vale. La peticion
#      del VDP solo se retira al leer su puerto de estado, asi que la
#      interrupcion se reentra sin parar y el juego no avanza ni una
#      instruccion. Costo una pasada entera contra el TIMEOUT.
#   2. Lo que ya hubiera en la VRAM. Las dos rutinas del final escriben el
#      bitmap (0x0000-0x17FF) y los colores (0x2000-0x37FF), pero no la tabla
#      de nombres ni los sprites: eso se hereda del mapa que estuviera pintado,
#      que depende de por donde iba la partida. Se pone la VRAM entera a cero
#      antes de pintar.
#
#   3. Y la tercera, que costo dos pasadas entenderla: EL JUEGO PIERDE BYTES AL
#      ESCRIBIR LA VRAM. UN_TERCIO_A_VRAM (0x05D6) hace `ld a,(hl) / out
#      (098h),a / inc h` en bucle apretado, y con la pantalla ENCENDIDA el VDP
#      no tiene ranuras de acceso para tanto: se le caen bytes. Cuales se caen
#      depende de en que punto del barrido se empiece, asi que dos ROMs que
#      tardan distinto en cargar pintan bitmaps distintos AUNQUE los 6.912
#      bytes de 0x4000 sean identicos -medido: 3.996 bytes de diferencia en la
#      victoria y 4.603 en la derrota, y CERO en cuanto se apaga la pantalla-.
#
#      O sea que la pantalla final del juego original ya sale con bytes
#      perdidos, y no siempre los mismos. Aqui se apaga la pantalla para que el
#      VDP de abasto y el cotejo compare lo que el juego ESCRIBE, que es lo
#      unico que este cambio podria alterar.
#
# Con las tres, lo que queda en la VRAM es funcion UNICAMENTE de la pantalla
# que se pinta, y comparar dos ROMs byte a byte significa algo.
proc prepara_para_pintar {} {
    # R1 = 0x80: pantalla APAGADA (bit 6 a cero) y sin interrupciones (bit 5).
    # El juego solo escribe R7, asi que esto se queda puesto. Lo de apagarla se
    # explica abajo, en el punto 3.
    debug write "VDP regs" 1 0x80
    for {set i 0} {$i < 0x4000} {incr i} {
        debug write "VRAM" $i 0
    }
    say "   interrupciones del VDP cerradas (R1 = 0xC0) y VRAM a cero"
}

# --------------------------------------------------------------- una pantalla
proc pinta_la_siguiente {} {
    if {$::cual >= [llength $::PANTALLAS]} {
        say "OK"
        exit 0
    }
    set dir [lindex $::PANTALLAS $::cual]
    set nombre [lindex $::NOMBRES $::cual]
    say "--------------------------------------------------------------"
    say "$nombre: se pone PC en [format 0x%04X $::PINTA] con HL = [format 0x%04X $dir]"
    say "   al llegar: SP = [format 0x%04X [reg SP]]  (0x4000-0x7FFF es la pagina 1)"
    say "   IFF1 = [reg IFF]   (1 = interrupciones abiertas, como llega el juego)"
    prepara_para_pintar
    reg HL $dir
    reg PC $::PINTA
    set ::bp_tras [debug set_bp $::TRAS_PINTA {} {
        debug remove_bp $::bp_tras
        set nombre [lindex $::NOMBRES $::cual]
        say "   en [format 0x%04X $::TRAS_PINTA]: la pantalla ya esta en 0x4000"
        say "   SP = [format 0x%04X [reg SP]]   IFF1 = [reg IFF]"
        vuelca "$::env(WAR_OUT)/pantalla_$nombre.bin" $::DESTINO $::TAM
        # y ahora se la deja pintar, que es lo que ve el jugador
        set ::bp_fin [debug set_bp $::FIN_JUEGO {} {
            debug remove_bp $::bp_fin
            set nombre [lindex $::NOMBRES $::cual]
            say "   en [format 0x%04X $::FIN_JUEGO]: pintada; se vuelca la VRAM"
            vuelca_vram "$::env(WAR_OUT)/vram_$nombre.bin"
            incr ::cual
            after time 0.1 pinta_la_siguiente
        }]
    }]
}

# ------------------------------------------------------------------ arrancar
set ::bp_5e00 [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el juego arranca"
    debug remove_bp $::bp_5e00
    after time 2 {
        say "se pulsa 0 para empezar la partida"
        type "0"
        after time 4 pinta_la_siguiente
    }
}]

after time 120 { say "TIMEOUT: no se llego a pintar las dos pantallas"; exit 1 }
