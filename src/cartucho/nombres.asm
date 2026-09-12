; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LA VISTA DE CERCA, POR TABLA
; DE NOMBRES
;
; QUE PROBLEMA RESUELVE
;
; La vista de cerca (BUCLE_DE_LA_VISTA, 0x71F9) es la pantalla que mas se
; repinta del juego, y lo hace a lo bruto: PANTALLA_DE_CARACTERES_A_LA_ZX
; (0x75A5) expande las 768 celdas de la pantalla de caracteres de 0x5E00 a
; 6.144 bytes de bitmap y 768 de atributos en RAM, y despues sube los 12.288
; bytes de dibujo y color a la VRAM, EN CADA VUELTA del bucle. Medido en un
; NMS 8250 (tools/omsx_vista.tcl): 800.857 ciclos de los 1.132.000 que
; cuesta una vuelta, o sea 3,2 vueltas por segundo.
;
; Y no hace falta: esa pantalla YA es una tabla de nombres. Un byte por
; celda; con el bit 7 a 1 es uno de los 128 dibujos de 0x9E00 (8 bytes de
; patron y uno de atributo), y con el bit 7 a 0 es uno de los 128 caracteres
; de la fuente de 0xC800, siempre con el atributo 0x78. 128 + 128 = 256
; patrones justos, y el color es funcion del codigo. O sea: el byte de 0x5E00
; ES el indice de patron del SCREEN 2, sin traducir.
;
; QUE HACE
;
; CARACTERES_A_NOMBRES sustituye a 0x75A5 entera: tools/haz_rom.py cambia
; sus tres primeros bytes por un `jp` aqui, y asi cubre a sus tres
; llamadores (0x7218, 0x7560 y 0x779A). Sube a la tabla de nombres de la
; VRAM (0x1800) los 32 primeros bytes de cada una de las 24 filas de 0x5E00,
; que miden 34. Son 768 bytes por vuelta en vez de 12.288, y ni un byte de
; RAM que expandir. No lleva sombra de lo ya subido: comparar una celda
; cuesta lo mismo que subirla (el VDP pide ~29 ciclos entre bytes), asi que
; se suben las 768 siempre.
;
; La primera vez despues de que alguien haya pintado en modo bitmap,
; PONE_LOS_PATRONES sube antes los 256 patrones y sus 256 colores a la VRAM,
; replicados en los TRES tercios de la pantalla (0x0000/0x0800/0x1000 y
; 0x2000/0x2800/0x3000): asi NO se toca ni R3 ni R4 -que en el modo grafico
; 2 son base y mascara y se prestan a equivocarse- y cualquier tercio con
; el nombre n ensena el mismo dibujo. Cuesta lo que costaba UNA vuelta de
; antes, y solo se paga al entrar.
;
; LAS FRONTERAS: EL GUARDIAN
;
; El resto del juego pinta en modo bitmap y cuenta con la tabla de nombres
; IDENTIDAD (0,1,..255 tres veces) que dejo el `SCREEN 2` del BASIC: el mapa
; general, los menus de LISTA_* (que se abren DESDE la vista), la batalla y
; las pantallas finales. Y todos ellos, sin excepcion, ponen la direccion de
; la VRAM con VRAM_A_ESCRIBIR (0x044B): es la unica rutina del juego que
; escribe una direccion en el puerto 0x99 (0x044D y 0x0454 son las dos
; unicas `out (099h)` de direccion del listado; y medido con
; tools/omsx_fronteras.tcl: en la vista solo escribe la VRAM 0x074E desde
; 0x7610, dentro de 0x75A5). Asi que ahi va el GUARDIAN: los cuatro primeros
; bytes de 0x044B pasan a ser un `call` aqui, y si la tabla de nombres es la
; de la vista, la devuelve a la identidad antes de dejar que escriban. La
; rutina de la vista NO pasa por 0x044B a proposito: pone la direccion ella
; misma.
;
; MODO_NOMBRES dice en cual de las dos disposiciones esta la VRAM: 0 la de
; siempre (identidad), 1 la de la vista. Lo pone PONE_LOS_PATRONES y lo
; quita el guardian.
;
; EL RITMO DEL VDP
;
; Con la pantalla encendida, el TMS9918 no admite dos accesos a la VRAM a
; menos de unos 29 ciclos: al que va mas rapido se le caen bytes (le pasa al
; propio juego, ver INVESTIGACION.md). Todos los bucles de aqui van a 36
; ciclos o mas por byte, que es el ritmo de los del juego que no pierden.
;
; DONDE VIVE
;
; En la RAM que liberaron las pantallas finales, detras de los dos bufers de
; ZX0 -que solo se usan mientras carga-, en la pagina 0, que es la que nunca
; se conmuta. La direccion la calcula tools/haz_rom.py y la pasa como
; NOMBRES_ORG; no se escribe a mano.
;
; REGISTROS: se pisan AF, BC, DE y HL, que es lo que pisaba 0x75A5 (que
; ademas pisaba el juego alternativo, que aqui no se toca). Los llamadores
; guardan HL alrededor de la llamada. IX e IY no se tocan.
; ==========================================================================

                org NOMBRES_ORG

TABLA_COLOR     equ 00200h      ; atributo ZX -> byte de color del MSX: la llena 0x5E15 y la usa 0x074E
FUENTE          equ 0C800h      ; los 128 caracteres de la fuente, 8 bytes cada uno
DIBUJOS         equ 09E00h      ; los 128 dibujos del mapa, 9 bytes: 8 de patron y el atributo
PANTALLA        equ 05E00h      ; la pantalla de caracteres: 25 filas de 34 bytes; se ven 24 de 32
ATRIBUTO_TEXTO  equ 078h        ; el atributo de todo caracter de la fuente (war_medio.asm, 0x763E)
VRAM_PATRONES   equ 00000h
VRAM_NOMBRES    equ 01800h
VRAM_COLORES    equ 02000h
FILAS           equ 24

; --------------------------------------------------------------------------
; La vista: 768 bytes a la tabla de nombres. Sustituye a 0x75A5.
;
; Hay DOS versiones, y se elige al ensamblar con `--equ SOMBRA=1` (o 0; el
; simbolo tiene que existir siempre, que pasmo no tiene IFDEF):
;
;   SIN sombra: se suben las 768 celdas siempre, a 37 ciclos por byte.
;   CON sombra: se guarda una copia de lo ultimo subido (SOMBRA_BUF, 768 B) y
;     cada fila se compara con ella; solo se suben las filas que cambian. La
;     comparacion son ~32 ciclos por byte -ld a,(de) / cp (hl) / jr nz / inc de
;     / inc l, desenrollado-, o sea casi lo que cuesta subir un byte, que es lo
;     que dice si la sombra paga o no. Se midio: ver INVESTIGACION.md.
; --------------------------------------------------------------------------
                IF SOMBRA
CARACTERES_A_NOMBRES:
                ld a,(MODO_NOMBRES)
                or a
                jr nz,CON_SOMBRA
                ; La primera vez tras un pintado en bitmap: patrones, y las 768
                ; celdas enteras, que de paso se copian a la sombra.
                call PONE_LOS_PATRONES
                ld hl,VRAM_NOMBRES
                call DIRECCION_VRAM
                ld de,PANTALLA
                ld hl,SOMBRA_BUF
                ld c,FILAS
T_FILA:         ld b,32
T_CELDA:        ld a,(de)               ; 7
                out (098h),a            ; 11
                ld (hl),a               ; 7   a la sombra
                inc de                  ; 6
                inc hl                  ; 6
                djnz T_CELDA            ; 13 = 50 ciclos por byte, solo esta vez
                inc de
                inc de
                dec c
                jr nz,T_FILA
                ret

; La sombra vale: fila a fila, 32 celdas contra la copia. DE recorre la
; pantalla (filas de 34, cruza paginas: `inc de`) y HL la sombra (filas de 32
; en un bufer alineado a 256: `inc l` no da la vuelta dentro de una fila). Los
; dos punteros al principio de la fila van a la pila por si hay que subirla.
CON_SOMBRA:     ld de,PANTALLA
                ld hl,SOMBRA_BUF
                ld c,FILAS
S_FILA:         push hl
                push de
                ld b,2                  ; dos mitades de 16 celdas desenrolladas
S_MITAD:
                REPT 16
                ld a,(de)               ; 7
                cp (hl)                 ; 7
                jr nz,S_CAMBIO          ; 7
                inc de                  ; 6
                inc l                   ; 4 = 31 ciclos por celda igual
                ENDM
                djnz S_MITAD
                pop af                  ; la fila era igual: fuera los punteros
                pop af
S_SIGUIENTE:    inc de                  ; los dos bytes que sobran de la fila de 34
                inc de
                ld a,l                  ; la sombra pasa de pagina cada 8 filas
                or a
                jr nz,S_MISMA_PAGINA
                inc h
S_MISMA_PAGINA: dec c
                jr nz,S_FILA
                ret
S_CAMBIO:       pop de                  ; los punteros al principio de la fila
                pop hl
                push hl
                push de
                ld de,VRAM_NOMBRES - SOMBRA_BUF
                add hl,de               ; la sombra y la tabla de nombres van paralelas
                call DIRECCION_VRAM
                pop de
                pop hl
                REPT 32
                ld a,(de)               ; 7
                out (098h),a            ; 11
                ld (hl),a               ; 7   y a la sombra
                inc de                  ; 6
                inc l                   ; 4 = 35 ciclos por celda
                ENDM
                jp S_SIGUIENTE          ; las 32 celdas desenrolladas no caben en un jr
                ELSE
CARACTERES_A_NOMBRES:
                ld a,(MODO_NOMBRES)
                or a
                call z,PONE_LOS_PATRONES
                ld hl,VRAM_NOMBRES
                call DIRECCION_VRAM
                ld hl,PANTALLA
                ld c,FILAS
N_FILA:         ld b,32
N_CELDA:        ld a,(hl)               ; 7
                out (098h),a            ; 11  el byte de la pantalla ES el nombre
                inc hl                  ; 6
                djnz N_CELDA            ; 13 = 37 ciclos por byte
                inc hl                  ; los dos bytes que sobran en cada fila de 34
                inc hl
                dec c
                jr nz,N_FILA
                ret
                ENDIF

; --------------------------------------------------------------------------
; Los 256 patrones y sus colores, replicados en los tres tercios. Una vez
; por entrada a la vista (o por vuelta de un menu, que borra la VRAM).
; --------------------------------------------------------------------------
PONE_LOS_PATRONES:
                ld hl,VRAM_PATRONES
                call DIRECCION_VRAM
                call UN_TERCIO_DE_PATRONES
                call UN_TERCIO_DE_PATRONES
                call UN_TERCIO_DE_PATRONES
                ld hl,VRAM_COLORES
                call DIRECCION_VRAM
                call UN_TERCIO_DE_COLORES
                call UN_TERCIO_DE_COLORES
                call UN_TERCIO_DE_COLORES
                ld a,1
                ld (MODO_NOMBRES),a
                ret

UN_TERCIO_DE_PATRONES:          ; 2 KB: 0..127 la fuente tal cual, 128..255 los dibujos sin su noveno byte
                ld hl,FUENTE
                ld c,4                  ; 4 x 256 = 1.024 bytes
                ld b,0
P_FUENTE:       ld a,(hl)
                out (098h),a
                inc hl
                djnz P_FUENTE           ; 37 ciclos por byte
                dec c
                jr nz,P_FUENTE
                ld hl,DIBUJOS
                ld c,128
P_DIBUJO:       ld b,8
P_LINEA:        ld a,(hl)
                out (098h),a
                inc hl
                djnz P_LINEA            ; 37 ciclos por byte
                inc hl                  ; el noveno byte es el atributo: no es patron
                dec c
                jr nz,P_DIBUJO
                ret

UN_TERCIO_DE_COLORES:           ; 2 KB: el color de cada patron, ocho veces
                ld a,ATRIBUTO_TEXTO
                call COLOR_DE_ATRIBUTO
                ld c,4                  ; 128 caracteres x 8 = 1.024 bytes, todos iguales
                ld b,0
C_TEXTO:        out (098h),a
                inc de                  ; inc de / dec de: el respiro que necesita el VDP, como en 0x07AC
                dec de
                djnz C_TEXTO            ; 36 ciclos por byte
                dec c
                jr nz,C_TEXTO
                ld hl,DIBUJOS+8         ; el atributo del primer dibujo
                ld de,9                 ; y de ahi al siguiente
                ld c,128
C_DIBUJO:       ld a,(hl)
                call COLOR_DE_ATRIBUTO
                ld b,8
C_OCHO:         out (098h),a
                inc de                  ; DE vuelve a 9: el respiro no lo estropea
                dec de
                djnz C_OCHO             ; 36 ciclos por byte
                add hl,de
                dec c
                jr nz,C_DIBUJO
                ret

COLOR_DE_ATRIBUTO:              ; A = atributo ZX -> A = byte de color, por la tabla que usa el propio juego
                push hl
                ld h,TABLA_COLOR/256
                ld l,a
                ld a,(hl)
                pop hl
                ret

; --------------------------------------------------------------------------
; El guardian: los cuatro primeros bytes de VRAM_A_ESCRIBIR (0x044B) -`di /
; ld a,l / out (099h),a`- pasan a ser `call GUARDIAN / nop`. Si la tabla de
; nombres es la de la vista, la devuelve a la identidad antes de que nadie
; escriba. Preserva BC, DE y HL, que los llamadores de 0x044B necesitan al
; volver; A y F se pisan, como ya los pisaba 0x044B. Se queda con las
; interrupciones cerradas: las abre 0x0458, como siempre.
; --------------------------------------------------------------------------
GUARDIAN:
                di
                ld a,(MODO_NOMBRES)
                or a
                jr z,G_SIGUE
                push hl
                call TABLA_IDENTIDAD
                pop hl
                xor a
                ld (MODO_NOMBRES),a
G_SIGUE:        ld a,l
                out (099h),a
                ret

TABLA_IDENTIDAD:                ; 0,1,..255 tres veces en 0x1800: la tabla de nombres con la que el juego cuenta
                push bc
                push de
                ld hl,VRAM_NOMBRES
                call PON_DIRECCION      ; sin abrir las interrupciones: estamos dentro de 0x044B
                ld c,3
                xor a
I_TERCIO:       ld b,0
I_BYTE:         out (098h),a
                inc a                   ; da la vuelta en 255: cada tercio empieza otra vez en 0
                inc de
                dec de
                djnz I_BYTE             ; 40 ciclos por byte
                dec c
                jr nz,I_TERCIO
                pop de
                pop bc
                ret

; --------------------------------------------------------------------------
; La direccion de escritura de la VRAM, sin pasar por 0x044B. El mismo
; retardo de dos `ex (sp),hl` que pone el juego.
; --------------------------------------------------------------------------
DIRECCION_VRAM: di
                call PON_DIRECCION
                ei
                ret
PON_DIRECCION:  ld a,l
                out (099h),a
                ld a,h
                and 03fh
                or 040h                 ; bit 6: lo que venga detras son escrituras
                out (099h),a
                ex (sp),hl
                ex (sp),hl
                ret

MODO_NOMBRES:   defb 0                  ; 0 = la VRAM esta como siempre; 1 = como la deja la vista

                IF SOMBRA
; La sombra: 24 filas de 32, alineadas a 256 para que `inc l` recorra una fila
; sin dar la vuelta. Viaja en la ROM como ceros y no importa lo que traiga:
; MODO_NOMBRES a 0 la invalida.
ALINEA:         defs (256 - (ALINEA and 255)) and 255
SOMBRA_BUF:     defs 768
                ENDIF

NOMBRES_FIN:
