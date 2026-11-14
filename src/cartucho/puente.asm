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

; WYZ_FLAGS y el resto del area de trabajo. Las cuatro rutinas del reproductor
; -WYZ_PLAYER_INIT, WYZ_CARGA_CANCION_HL, WYZ_REPRODUCE_FRAME y WYZ_PLAYER_OFF-
; y la direccion del MODULO no se escriben aqui: las pasa tools/haz_rom.py
; leyendolas del .sym con el que se acaba de ensamblar musica.asm, que es la
; unica forma de que no se queden viejas.
                include "wyz_trabajo.inc"

                org PUENTE_ORG

                IF TRES_CANCIONES
; ==========================================================================
; LAS TRES CANCIONES DE RUBEN (2026-11-14, `haz_rom.py --canciones`)
;
; La musica ya no calla al empezar la partida: cambia de cancion segun la
; fase. La 0 (niebla) suena en el MENU, la 1 (taberna) mientras se juega -el
; mapa general y la vista de cerca- y la 2 (batalla) desde la pantalla de
; antes de la batalla hasta el cartel de "La Batalla ha finalizado".
;
; Quien elige es el juego, por tres sitios, y solo deja la cancion PEDIDA;
; el cambio de verdad lo hace la interrupcion siguiente, que es la que tiene
; la ROM asomada:
;
;   PARA_LA_MUSICA  al pulsar 0 en el menu (MENU_TECLA_0)    -> 1, taberna
;   PIDE_BATALLA    el `call PANTALLA_DE_BATALLA` de 0x9021   -> 2, batalla
;   PIDE_TABERNA    el `call DESCOMPRIME_EL_MAPA` de 0x91FC   -> 1, taberna
;
; Las canciones y sus instrumentos viven en la RAM de la pagina 0, que nadie
; pisa en toda la partida; los descomprime el cargador. El reproductor sigue
; en la ROM y busca la cancion en su TABLA_SONG con WYZ_CARGA_CANCION.
; Y los cuadros se cuentan SIEMPRE aqui, porque el gancho ya no pasa nunca a
; CUENTA_CUADROS: el paso del cursor de la vista sale de CUADROS.
; ==========================================================================
PUENTE:
                in a,(0A8h)
                push af                 ; la pagina 2 como estaba: RAM del juego
                and 0CFh                ; fuera los bits 4-5, que son los suyos
PUENTE_RANURA:
                or 000h                 ; <- el cargador escribe aqui la primaria
                out (0A8h),a            ; ya se ve la ROM en 0x8000-0xBFFF

                ld hl,CUADROS
                inc (hl)

                ; LA TECLA M (pedida por el usuario el 2026-11-14): calla o
                ; devuelve la musica en cualquier momento. Fila 4 del teclado
                ; (R Q P O N M L K), bit 2, a cero si esta pulsada. La fila que
                ; tuviera puesta el juego se devuelve enseguida: si la
                ; interrupcion cae entre su `out (0AAh)` y su `in (0A9h)`, el
                ; juego lee lo que esperaba.
                in a,(0AAh)
                ld b,a
                and 0F0h                ; los cuatro bits de arriba no son la fila
                or 004h
                out (0AAh),a
                in a,(0A9h)
                ld c,a
                ld a,b
                out (0AAh),a            ; la fila del juego, como estaba
                ld a,c
                cpl
                and 004h                ; 4: la M esta pulsada
                ld hl,TECLA_M
                ld c,(hl)               ; como estaba el cuadro anterior
                ld (hl),a
                xor c                   ; lo que ha cambiado ...
                and (hl)                ; ... y esta pulsado: se ACABA de pulsar
                jr z,PUENTE_SIN_M
                ld a,(MUDA)
                cpl
                ld (MUDA),a
                or a
                jr z,PUENTE_VUELVE
                call WYZ_PLAYER_OFF     ; callada: el PSG a cero
                jr PUENTE_FUERA
PUENTE_VUELVE:
                ld a,0FFh               ; vuelve: la cancion de la fase, desde el principio
                ld (PUENTE_SONANDO),a
PUENTE_SIN_M:
                ld a,(MUDA)
                or a
                jr nz,PUENTE_FUERA      ; callada: ni cambia de cancion ni suena

                ld a,(PEDIDA)
                ld hl,PUENTE_SONANDO
                cp (hl)
                jr z,PUENTE_CUADRO      ; la de siempre: un cuadro mas
                ld (hl),a               ; otra: se arranca desde el principio
                call WYZ_PLAYER_INIT    ; calla lo que sonaba y deja el area de trabajo limpia
                ld a,(PEDIDA)
                call WYZ_CARGA_CANCION  ; A = numero en TABLA_SONG

PUENTE_CUADRO:
                ; Una sola llamada: WYZ_REPRODUCE_FRAME vuelca primero al PSG
                ; lo que se calculo en la interrupcion anterior -que es lo que
                ; mantiene el ritmo parejo- y luego prepara el cuadro siguiente.
                call WYZ_REPRODUCE_FRAME

PUENTE_FUERA:
                pop af
                out (0A8h),a            ; y la RAM del juego otra vez en su sitio
                ret

PUENTE_SONANDO: defb 0FFh               ; la que suena; 0xFF: ninguna todavia
PEDIDA:         defb 0                  ; la que el juego quiere: niebla al encender
CUADROS:        defb 0
TECLA_M:        defb 0                  ; 4 si la M estaba pulsada el cuadro anterior
MUDA:           defb 0                  ; 0xFF: callada con la M

; Se queda por el nombre, que lo citan las sondas: con tres canciones el
; gancho no pasa nunca por aqui.
CUENTA_CUADROS: ret

PARA_LA_MUSICA:
                ld a,1                  ; taberna: empieza la partida
                ld (PEDIDA),a
                ld a,(MENU_NIVEL)       ; el nivel elegido, que es lo que iba aqui
                ret

PIDE_BATALLA:
                ld a,2
                ld (PEDIDA),a
                jp PANTALLA_DE_BATALLA

PIDE_TABERNA:
                ld a,1
                ld (PEDIDA),a
                jp DESCOMPRIME_EL_MAPA

                ELSE

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
                ; WYZ_PLAYER_OFF apaga los interruptores, borra el bufer de
                ; registros y lo vuelca: el PSG se queda mudo de verdad.
                call WYZ_PLAYER_OFF
                ld hl,CUENTA_CUADROS    ; desde aqui el gancho solo cuenta cuadros: el paso del cursor
                ld (GANCHO),hl
                jr PUENTE_SALE

PUENTE_ARRANCA:
                ; La primera vuelta arranca la cancion. Se hace aqui y no en el
                ; cargador para no tener que asomar la ROM dos veces ni repetir
                ; la conmutacion en el stub.
                dec a                   ; A = 0xFF: sonando
                ld (PUENTE_SONANDO),a
                ; WYZ_PLAYER_INIT deja el area de trabajo en su sitio -en RAM,
                ; donde el juego no ha puesto nada- y ademas calla el PSG; sin
                ; el, la cancion arrancaria sobre los bufers sin estrenar.
                call WYZ_PLAYER_INIT
                ld hl,MODULO
                call WYZ_CARGA_CANCION_HL
                ; Que la cancion se repita NO se decide aqui: va en el bit 0
                ; del segundo byte de su cabecera, y WYZ_CARGA_CANCION_HL lo
                ; lee y arma WYZ_BIT_LOOP solo.

PUENTE_CUADRO:
                ; Una sola llamada: WYZ_REPRODUCE_FRAME vuelca primero al PSG
                ; lo que se calculo en la interrupcion anterior -que es lo que
                ; mantiene el ritmo parejo- y luego prepara el cuadro
                ; siguiente.
                call WYZ_REPRODUCE_FRAME

PUENTE_SALE:
                pop af
                out (0A8h),a            ; y la RAM del juego otra vez en su sitio
                ret

PUENTE_SONANDO:
                defb 0                  ; 0 hasta que suena la primera nota

; Cuando la musica calla, el gancho por cuadro pasa a esto en vez de al `ret`
; vacio: un contador de cuadros que la vista usa para limitar el paso del
; cursor (MI_MUEVE, en nombres.asm). Corre en cada interrupcion, en la RAM de
; la pagina 0 y sin asomar la ROM: cuatro bytes y unos 30 ciclos por cuadro.
CUENTA_CUADROS: ld hl,CUADROS
                inc (hl)
                ret
CUADROS:        defb 0

; --------------------------------------------------------------------------
; PARA_LA_MUSICA: la musica es del MENU, asi que calla al empezar la partida.
;
; Lo llama el propio menu: en MENU_TECLA_0, cuando ya se sabe que la tecla es
; el '0' de empezar, tools/haz_rom.py cambia su `ld a,(MENU_NIVEL)` por un
; `call` aqui. Por eso lo ultimo que hace es ese mismo `ld`: lo que se llevo
; por delante hay que devolverlo.
;
; No se calla aqui mismo porque WYZ_PLAYER_OFF vive en la ROM, que ahora no
; se ve: solo se deja el aviso, y el puente lo recoge en la interrupcion
; siguiente, que es donde la ROM si esta asomada.
; --------------------------------------------------------------------------
PARA_LA_MUSICA:
                ld a,1
                ld (PUENTE_SONANDO),a
                ld a,(MENU_NIVEL)       ; el nivel elegido, que es lo que iba aqui
                ret

                ENDIF

PUENTE_FIN:
