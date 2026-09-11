; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: EL PUENTE DE LA MUSICA
;
; Treinta y tantos bytes que viven en la RAM de la pagina 0, en 0x003B: justo
; detras del `jp 0x0400` que el juego arma en 0x0038 y muy por debajo del
; buzon de POKEs de 0x012C, o sea en tierra de nadie.
;
; QUE PINTA AQUI
;
; El juego corre con las cuatro paginas en RAM: el cartucho no se ve por
; ninguna parte. Pero el reproductor y la musica estan en la ROM, en el ultimo
; banco, que el cargador dejo puesto en la ventana de 0x8000 antes de saltar.
; Este puente es quien la asoma: conmuta la pagina 2 a la ranura del cartucho,
; llama al reproductor y devuelve la RAM. Mientras dura -unos pocos cientos de
; ciclos- los 0x8000-0xBFFF del juego no existen; por eso no se toca nada de
; ahi, ni siquiera la pila, que vive en 0x5BFF, en la pagina 1.
;
; QUIEN LO LLAMA
;
; El gancho por cuadro de 0x0415, que el juego deja apuntando al `ret` de
; 0x0428 y aqui apunta a esta rutina (tools/haz_rom.py cambia el operando del
; `ld hl,00428h` de 0x5E0F, dos bytes del bloque medio). Lo llama la
; INTERRUPCION de 0x0400 DESPUES de salvar todos los registros -los normales,
; los alternativos, IX e IY-, asi que aqui no hay que salvar nada.
;
; LA RANURA
;
; Solo se toca la primaria, en 0xA8. El subslot de una ranura expandida se
; elige en 0xFFFF, que unicamente se puede escribir teniendo esa primaria en la
; pagina 3 -donde esta la RAM del juego y la pila-, asi que no se intenta: se
; confia en que el que dejo puesto el arranque siga siendo el del cartucho,
; que es lo que pasa mientras nadie lo cambie. En una ranura sin expandir, que
; es el caso normal, esto no aplica.
; ==========================================================================

; PT3_SETUP y el resto del area de trabajo. Las cuatro rutinas del reproductor
; -PT3_INIT, PT3_PLAY, PT3_ROUT- y la direccion del MODULO no se escriben aqui:
; las pasa tools/haz_rom.py leyendolas del .sym con el que se acaba de
; ensamblar musica.asm, que es la unica forma de que no se queden viejas.
                include "pt3_trabajo.inc"

                org PUENTE_ORG

PUENTE:
                in a,(0A8h)
                push af                 ; la pagina 2 como estaba: RAM del juego
                and 0CFh                ; fuera los bits 4-5, que son los suyos
PUENTE_RANURA:
                or 000h                 ; <- el cargador escribe aqui la primaria
                out (0A8h),a            ; ya se ve la ROM en 0x8000-0xBFFF

                ; PUENTE_SONANDO dice en cual de las tres estamos: 0x00 sin
                ; arrancar, 0xFF sonando, y cualquier otra cosa -la pone
                ; PARA_LA_MUSICA- es que hay que callar.
                ld a,(PUENTE_SONANDO)
                or a
                jr z,PUENTE_ARRANCA
                inc a
                jr z,PUENTE_CUADRO      ; 0xFF: la cancion sigue

                ; Se acabo: el PSG a cero y el gancho de vuelta al `ret` de
                ; siempre, que es lo que deja la partida exactamente como
                ; estaba, sin gastar un ciclo por cuadro en mirar una variable.
                call PT3_MUTE
                ld hl,GANCHO_VACIO
                ld (GANCHO),hl
                jr PUENTE_SALE

PUENTE_ARRANCA:
                ; La primera vuelta arranca la cancion. Se hace aqui y no en el
                ; cargador para no tener que asomar la ROM dos veces ni repetir
                ; la conmutacion en el stub.
                dec a                   ; A = 0xFF: sonando
                ld (PUENTE_SONANDO),a
                xor a
                ld (PT3_SETUP),a        ; bit 0 a cero: la cancion se repite
                ld hl,MODULO-100        ; PT3_INIT quiere el modulo MENOS 100
                call PT3_INIT

PUENTE_CUADRO:
                ; Primero al PSG lo que se calculo en la interrupcion anterior,
                ; que es lo que mantiene el ritmo parejo, y luego se prepara el
                ; cuadro siguiente. Es el orden de msx-msxlib.
                call PT3_ROUT
                ld a,(PT3_SETUP)
                bit 7,a                 ; lo pone el reproductor al pasar el bucle
                jr z,PUENTE_PLAY
                res 7,a                 ; y se rearma, que aqui se toca en bucle
                ld (PT3_SETUP),a
PUENTE_PLAY:
                call PT3_PLAY

PUENTE_SALE:
                pop af
                out (0A8h),a            ; y la RAM del juego otra vez en su sitio
                ret

PUENTE_SONANDO:
                defb 0                  ; 0 hasta que suena la primera nota

; --------------------------------------------------------------------------
; PARA_LA_MUSICA: la musica es del MENU, asi que calla al empezar la partida.
;
; Lo llama el propio menu: en MENU_TECLA_0, cuando ya se sabe que la tecla es
; el '0' de empezar, tools/haz_rom.py cambia su `ld a,(MENU_NIVEL)` por un
; `call` aqui. Por eso lo ultimo que hace es ese mismo `ld`: lo que se llevo
; por delante hay que devolverlo.
;
; No se calla aqui mismo porque PT3_MUTE vive en la ROM, que en este momento no
; se ve: solo se deja el aviso, y el puente lo recoge en la interrupcion
; siguiente, que es donde la ROM si esta asomada.
; --------------------------------------------------------------------------
PARA_LA_MUSICA:
                ld a,1
                ld (PUENTE_SONANDO),a
                ld a,(MENU_NIVEL)       ; el nivel elegido, que es lo que iba aqui
                ret

PUENTE_FIN:
