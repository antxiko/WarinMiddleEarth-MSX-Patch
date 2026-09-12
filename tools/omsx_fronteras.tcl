# ¿QUIEN ESCRIBE LA VRAM, Y QUIEN TOCA LA PANTALLA ZX, MIENTRAS SE ESTA EN
# LA VISTA DE CERCA?
#
# Es el reconocimiento previo a cambiar la vista de cerca por una tabla de
# nombres. El listado dice que en la vista todo se pinta en la pantalla de
# caracteres de 0x5E00 y que solo 0x75A5 lo sube a la VRAM; y que lo unico
# ajeno que escribe la VRAM en la vista son BORRA_PANTALLA y los menus de
# LISTA_*, que si son de bitmap. Esto lo mide en vez de creerselo:
#
#   - por cada rutina de VRAM del banco bajo, QUIEN la llama (la direccion de
#     retorno que hay en la pila al entrar) y cuantas veces, por fase;
#   - por cada PC que lee o escribe la pantalla ZX emulada (0x4000-0x5AFF),
#     cuantas veces, por fase.
#
# Las fases las marcan breakpoints en las entradas de cada modo: el mapa, la
# vista, el menu de la R y los menus de lista. El recorrido: menu -> 2 -> 0 ->
# mapa -> ESPACIO (vista) -> R (menu de entrega) -> ESPACIO (Vuelve, a la
# vista) -> derecha (mueve el cursor) -> ESPACIO (sale al mapa, o abre el menu
# de ordenes si hay una unidad debajo) -> ESPACIO otra vez.
#
#   WAR_OUT=<dir> openmsx -machine <maq> -carta <rom> -romtype ascii16 \
#       -script tools/omsx_fronteras.tcl

set OUT $::env(WAR_OUT)
file mkdir $OUT
set LOG [open "$OUT/fronteras.log" w]
proc say {m} { global LOG; puts $LOG "\[[format %8.2f [machine_info time]]\] $m"; flush $LOG }

catch {set renderer none}
set throttle off
say "maquina: [machine_info config_name]"
catch {say "cartucho: [carta]"}

# ------------------------------------------------- las rutinas de VRAM
set ::RUTINAS {
    0x0429 LLENA_VRAM
    0x0439 VUELCA_A_VRAM
    0x044B VRAM_A_ESCRIBIR
    0x05BD PANTALLA_A_VRAM
    0x0604 ATRIBUTOS_A_VRAM
    0x0702 RECUADRO_A_VRAM
    0x074E FILA_CON_COLOR_A_VRAM
    0x07C3 REFRESCA_EL_CURSOR
    0x0467 COLOR_DEL_BORDE
}
set ::fase arranque
set ::cuenta [dict create]
proc apunta {nombre} {
    set sp [reg SP]
    set ret [expr {[debug read memory $sp] | ([debug read memory [expr {$sp + 1}]] << 8)}]
    dict incr ::cuenta [list $::fase $nombre [format %04X $ret]]
}
foreach {dir nombre} $::RUTINAS {
    debug set_bp $dir {} [list apunta $nombre]
}

# --------------------------------------- la pantalla ZX emulada, en RAM
set ::lee [dict create]
set ::escribe [dict create]
debug set_watchpoint read_mem {0x4000 0x5AFF} {} { dict incr ::lee [list $::fase [format %04X [reg PC]]] }
debug set_watchpoint write_mem {0x4000 0x5AFF} {} { dict incr ::escribe [list $::fase [format %04X [reg PC]]] }

# ------------------------------------------------------------ las fases
set ::FASES {
    0x6A47 mapa
    0x71F1 vista
    0x71F4 vista
    0x72F5 menu_R
    0x640A lista
    0x641A lista
    0x7F54 mapa
}
foreach {dir nombre} $::FASES {
    debug set_bp $dir {} [list entra_en $nombre $dir]
}
set ::n_fase 0
set ::fase_nombre ""
proc entra_en {nombre dir} {
    # 0x6A47 esta DENTRO del bucle del mapa y salta en cada vuelta: solo se
    # abre una fase nueva cuando cambia el nombre, no en cada golpe.
    if {$nombre eq $::fase_nombre} { return }
    incr ::n_fase
    set ::fase_nombre $nombre
    set ::fase "[format %02d $::n_fase]_$nombre"
    say "PC en [format 0x%04X $dir]: fase $::fase"
}

# ------------------------------------------------------------- informe
proc informe {} {
    global OUT
    set f [open "$OUT/fronteras.txt" w]
    puts $f "== RUTINAS DE VRAM: fase, rutina, quien la llama (direccion de retorno), veces"
    foreach k [lsort [dict keys $::cuenta]] {
        lassign $k fase rutina ret
        puts $f [format "%-12s %-22s desde %s  x%d" $fase $rutina $ret [dict get $::cuenta $k]]
    }
    puts $f ""
    puts $f "== LECTURAS de 0x4000-0x5AFF: fase, PC, veces"
    foreach k [lsort [dict keys $::lee]] {
        lassign $k fase pc
        puts $f [format "%-12s %s  x%d" $fase $pc [dict get $::lee $k]]
    }
    puts $f ""
    puts $f "== ESCRITURAS en 0x4000-0x5AFF: fase, PC, veces"
    foreach k [lsort [dict keys $::escribe]] {
        lassign $k fase pc
        puts $f [format "%-12s %s  x%d" $fase $pc [dict get $::escribe $k]]
    }
    close $f
}

# ------------------------------------------------------------ conducir
proc pulsa {fila masc dur} {
    keymatrixdown $fila $masc
    after time $dur [list keymatrixup $fila $masc]
}
set ::ESPACIO {8 0x01}
set ::DERECHA {8 0x80}
set ::R {4 0x80}

proc en_el_mapa {} {
    say "en el mapa: ESPACIO para entrar a la vista"
    pulsa {*}$::ESPACIO 0.3
    after time 3 {
        say "en la vista: R, el menu de entrega"
        pulsa {*}$::R 0.5
        after time 2.5 {
            say "en el menu: ESPACIO, que elige Vuelve"
            pulsa {*}$::ESPACIO 0.3
            after time 3 {
                say "en la vista otra vez: derecha, mueve el cursor"
                pulsa {*}$::DERECHA 0.3
                after time 2 {
                    say "ESPACIO: sale al mapa, o abre el menu de ordenes si hay unidad"
                    pulsa {*}$::ESPACIO 0.3
                    after time 3 {
                        say "ESPACIO otra vez"
                        pulsa {*}$::ESPACIO 0.3
                        after time 3 {
                            say "FIN"
                            informe
                            exit 0
                        }
                    }
                }
            }
        }
    }
}

set ::bp_menu [debug set_bp 0x5E00 {} {
    say "PC en 0x5E00: el menu"
    debug remove_bp $::bp_menu
    after time 2 {
        say "se pulsa 2 (cursores)"
        type "2"
        after time 2 {
            say "se pulsa 0 (empezar)"
            type "0"
            set ::bp_mapa [debug set_bp 0x6A47 {} {
                debug remove_bp $::bp_mapa
                after time 2 { en_el_mapa }
            }]
        }
    }
}]

after time 240 { say "TIMEOUT"; informe; exit 1 }
