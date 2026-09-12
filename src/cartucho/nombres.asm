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
; EL CURSOR COMO SPRITE, Y LA VENTANA FIJA
;
; Con la tabla de nombres la vuelta bajo de 1.132.000 a 363.884 ciclos, y de
; esos, 330.031 eran DIBUJA_EL_TROZO_DE_MAPA (0x7643): repintar las 16 x 13
; celdas del trozo EN CADA VUELTA, aunque el cursor no se moviera. Y se
; repintaba porque el cursor iba dentro de la pantalla de caracteres -cuatro
; caracteres de 0x77B5+modo*4 escritos encima del centro- y la ventana del
; trozo se desplazaba con el (el cursor siempre en la celda (7,5) de la
; ventana).
;
; Ahora el cursor es un SPRITE de 16x16 -dos, uno por color, solapados: el
; dibujo y el bloque de detras, que salen de src/cartucho/cursor.png- y la
; ventana del trozo se queda QUIETA: el cursor se mueve dentro sin repintar
; nada, y el trozo solo se vuelve a dibujar cuando el cursor se acerca a menos
; de MARGEN celdas del borde, recentrandolo como lo pintaria el original (10
; columnas y 7 filas de recorrido entre repintados). La pantalla de
; caracteres limpia -el trozo sin ventanas- se guarda en CACHE (850 B) y en
; las vueltas sin repintado se restaura con un `ldir`: las ventanas de
; posicion, ficha y sitio se dibujan encima como siempre.
;
; MI_PINTA sustituye a PINTA_LA_VISTA_DE_CERCA (0x71A4): sus tres primeros
; bytes pasan a ser un `jp` aqui, y eso cubre a sus tres llamadores (0x71F9,
; 0x7547 y 0x778A). Cuando hay que repintar hace lo mismo que hacia 0x71A7-
; 0x71C5, llamando a las mismas rutinas del juego (CELDA_DEL_MAPA,
; DIBUJA_EL_TROZO_DE_MAPA y TAPA_LOS_BORDES); lo que NO hace es escribir el
; cursor en la pantalla ni parpadear (0x71C6 en adelante queda sin ejecutar,
; y da igual que 0x752E siga escribiendo en 0x71C7). El cursor no parpadea:
; esta siempre visible.
;
; La cache vale mientras no cambie la esquina, ni el modo (0x71CF: el trozo
; lleva la marca de la casilla de partida de una orden, que se quita al volver
; al modo mirar), ni haya pasado el guardian (todo menu es de bitmap y por el
; pasa; y las ordenes marcan la casilla justo despues de un menu). El reloj
; del juego no corre en la vista: solo lo mueve BUCLE_DE_PARTIDA.
;
; Los atributos de los dos sprites (Y, X, patron, color) se calculan aqui y
; los sube CARACTERES_A_NOMBRES detras de los nombres, en cada vuelta; los
; 192 bytes de patrones los sube PONE_LOS_PATRONES al entrar. El tamano 16x16
; lo pone el cargador en R1 (0xE2): el juego nunca escribe R1. El guardian, al
; devolver la identidad, deja los dos sprites como los dejo el cargador
; (Y=209: fuera de la pantalla).
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
; REGISTROS: CARACTERES_A_NOMBRES pisa AF, BC, DE y HL, que es lo que pisaba
; 0x75A5 (que ademas pisaba el juego alternativo, que aqui no se toca); los
; llamadores guardan HL alrededor de la llamada, y IX e IY no se tocan.
; MI_PINTA devuelve HL intacto y pisa lo mismo que pisaba 0x71A4: AF, BC, DE,
; IX, IY y el juego alternativo (por DIBUJA_EL_TROZO_DE_MAPA).
; ==========================================================================

                org NOMBRES_ORG

TABLA_COLOR     equ 00200h      ; atributo ZX -> byte de color del MSX: la llena 0x5E15 y la usa 0x074E
FUENTE          equ 0C800h      ; los 128 caracteres de la fuente, 8 bytes cada uno
DIBUJOS         equ 09E00h      ; los 128 dibujos del mapa, 9 bytes: 8 de patron y el atributo
PANTALLA        equ 05E00h      ; la pantalla de caracteres: 25 filas de 34 bytes; se ven 24 de 32
ATRIBUTO_TEXTO  equ 0763Fh      ; el OPERANDO del `ld a,078h` de 0x763E: el atributo de todo caracter de la fuente.
                                ; Se lee de ahi y no se copia: el parche de Araubi lo cambia a 0x70 (amarillo claro)
VRAM_PATRONES   equ 00000h
VRAM_NOMBRES    equ 01800h
VRAM_COLORES    equ 02000h
VRAM_SPRITES    equ 01B00h      ; los atributos: R5 = 0x36
VRAM_SPRITES_PAT equ 03800h     ; los patrones: R6 = 0x07
FILAS           equ 24

; El cursor y la ventana del trozo
MODO_DE_LA_VISTA equ 071CFh     ; el operando de 0x71CE: 0x10 mirar, 0x12 elegir destino, 0x17 batalla
CELDA_DEL_MAPA  equ 08108h      ; H = fila, L = columna -> IX = la casilla en el mapa
DIBUJA_EL_TROZO equ 07643h      ; las 16 x 13 celdas desde la esquina IX
TAPA_LOS_BORDES equ 07129h      ; y lo que se sale del mapa, a 0xD5
ANCHO_VENTANA   equ 16          ; celdas de mapa
ALTO_VENTANA    equ 13
CURSOR_COL      equ 7           ; donde cae el cursor en la ventana cuando se recentra
CURSOR_FILA     equ 5           ; (0x71B5 hace `inc h` y resta 720 = 7 columnas y 6 filas)
MARGEN          equ 3           ; a menos de esto del borde se recentra
MUEVE_POR_EL_MAPA equ 0734Bh    ; A = mando, HL = posicion; mueve una casilla
PASO_DEL_CURSOR equ 10          ; cuadros entre casilla y casilla con la tecla pulsada: 5 por segundo a 50 Hz (6 a 60)
                                ; CUADROS lo lleva el gancho de la interrupcion (puente.asm) y llega como --equ
DESPLAZA_ESQUINA equ -720       ; lo que resta 0x71B9 a la celda de (H+1, L)
TAM_PANTALLA    equ 850         ; 25 filas de 34

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
                jp SUBE_EL_CURSOR

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
                jp SUBE_EL_CURSOR
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
                ENDIF

; Detras de los nombres, los ocho atributos de los dos sprites del cursor, que
; MI_PINTA dejo calculados en ATRIBUTOS: Y, X, patron y color de cada uno.
SUBE_EL_CURSOR: ld hl,VRAM_SPRITES
                call DIRECCION_VRAM
                ld hl,ATRIBUTOS
                ld b,8
SC_BYTE:        ld a,(hl)               ; 7
                out (098h),a            ; 11
                inc hl                  ; 6
                djnz SC_BYTE            ; 13 = 37 ciclos por byte
                ret

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
                ; y los seis planos del cursor: dos por modo, 32 bytes cada uno
                ld hl,VRAM_SPRITES_PAT
                call DIRECCION_VRAM
                ld hl,CURSOR_PATRONES
                ld b,CURSOR_COLORES-CURSOR_PATRONES     ; 192
P_CURSOR:       ld a,(hl)
                out (098h),a
                inc hl
                djnz P_CURSOR           ; 37 ciclos por byte
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
                ld a,(ATRIBUTO_TEXTO)
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
                call ESCONDE_EL_CURSOR
                pop hl
                xor a
                ld (MODO_NOMBRES),a
                ld (CACHE_VALIDA),a     ; lo que venga puede cambiar el mapa: el trozo se repinta al volver
G_SIGUE:        ld a,l
                out (099h),a
                ret

ESCONDE_EL_CURSOR:              ; los dos sprites como los dejo el cargador: Y=209 (fuera de la pantalla), X=0, patron n, color 1
                push bc
                ld hl,VRAM_SPRITES
                call PON_DIRECCION      ; sin abrir las interrupciones: estamos dentro de 0x044B
                ld hl,ESCONDIDOS
                ld b,8
E_BYTE:         ld a,(hl)
                out (098h),a
                inc hl
                djnz E_BYTE             ; 37 ciclos por byte
                pop bc
                ret
ESCONDIDOS:     defb 209,0,0,1, 209,0,1,1

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

; --------------------------------------------------------------------------
; MI_PINTA: sustituye a PINTA_LA_VISTA_DE_CERCA (0x71A4). Entra por un `jp`
; con HL = la posicion del cursor (H fila, L columna; el bit 7 de cada uno es
; una bandera y no cuenta) y vuelve con HL intacto, como el original.
;
; Si la cache vale, el modo es el de entonces y el cursor sigue a MARGEN o mas
; celdas del borde de la ventana, la pantalla vuelve a ser el trozo limpio de
; la cache. Si no, se repinta como lo hacia 0x71A7-0x71C5, con la esquina en
; (H-5, L-7), y se guarda. Y en los dos casos se dejan calculados los ocho
; atributos de los dos sprites del cursor.
; --------------------------------------------------------------------------
MI_PINTA:
                ld a,(CACHE_VALIDA)
                or a
                jr z,MP_REPINTA
                ld a,(MODO_DE_LA_VISTA)
                ld b,a
                ld a,(ULTIMO_MODO)
                cp b
                jr nz,MP_REPINTA
                ld a,l
                and 07fh
                ld b,a
                ld a,(ESQUINA_L)        ; la columna del cursor cuando se recentro
                ld c,a
                ld a,b
                sub c                   ; columna - la de entonces: de -4 a 5 si sigue dentro
                add a,CURSOR_COL-MARGEN ; de 0 a 9; fuera de ahi, sin signo, es grande
                cp ANCHO_VENTANA-2*MARGEN
                jr nc,MP_REPINTA
                ld a,h
                and 07fh
                ld b,a
                ld a,(ESQUINA_H)
                ld c,a
                ld a,b
                sub c                   ; fila - la de entonces: de -2 a 4
                add a,CURSOR_FILA-MARGEN
                cp ALTO_VENTANA-2*MARGEN
                jr nc,MP_REPINTA
                push hl                 ; dentro: el trozo limpio, de la cache
                ld hl,CACHE
                ld de,PANTALLA
                ld bc,TAM_PANTALLA
                ldir                    ; 21 ciclos por byte
                pop hl
                jr MP_CURSOR
MP_REPINTA:     ld a,(MODO_DE_LA_VISTA)
                ld (ULTIMO_MODO),a
                ld a,l
                and 07fh
                ld (ESQUINA_L),a
                ld a,h
                and 07fh
                ld (ESQUINA_H),a
                push hl
                ld hl,PANTALLA          ; como 0x71A7: las 850 celdas a 0x80, el fondo de la vista
                ld de,PANTALLA+1
                ld bc,TAM_PANTALLA-1
                ld (hl),080h
                ldir
                pop hl
                push hl
                inc h                   ; como 0x71B5: la celda de (H+1, L) menos 7 columnas y 6 filas
                call CELDA_DEL_MAPA
                ld de,DESPLAZA_ESQUINA
                add ix,de
                call DIBUJA_EL_TROZO    ; las 16 x 13 celdas: terreno, encima y unidades
                pop hl
                push hl
                call TAPA_LOS_BORDES    ; y a 0xD5 lo que caiga fuera del mapa
                pop hl
                push hl
                ld hl,PANTALLA          ; el trozo limpio, a la cache
                ld de,CACHE
                ld bc,TAM_PANTALLA
                ldir
                pop hl
                ld a,1
                ld (CACHE_VALIDA),a
MP_CURSOR:      ; X = 16 * (columna - esquina + 7); Y = 16 * (fila - esquina + 5) - 1, que el VDP
                ; pinta el sprite una linea por debajo de Y
                ld a,l
                and 07fh
                ld b,a
                ld a,(ESQUINA_L)
                ld c,a
                ld a,b
                sub c
                add a,CURSOR_COL
                add a,a
                add a,a
                add a,a
                add a,a
                ld (ATRIBUTOS+1),a
                ld (ATRIBUTOS+5),a
                ld a,h
                and 07fh
                ld b,a
                ld a,(ESQUINA_H)
                ld c,a
                ld a,b
                sub c
                add a,CURSOR_FILA
                add a,a
                add a,a
                add a,a
                add a,a
                dec a
                ld (ATRIBUTOS+0),a
                ld (ATRIBUTOS+4),a
                ld a,(MODO_DE_LA_VISTA) ; el dibujo segun el modo: 0x10 -> 0, 0x12 -> 1, 0x17 -> 2
                ld c,0
                cp 010h
                jr z,MP_MODO
                inc c
                cp 012h
                jr z,MP_MODO
                inc c
MP_MODO:        ld a,c
                add a,a
                add a,a
                add a,a                 ; por 8: cada modo son dos planos de cuatro patrones de 8x8
                ld (ATRIBUTOS+2),a
                add a,4
                ld (ATRIBUTOS+6),a
                push hl
                ld hl,CURSOR_COLORES
                ld a,c
                add a,a                 ; por 2: los dos colores del modo
                add a,l
                ld l,a
                ld a,0
                adc a,h
                ld h,a
                ld a,(hl)
                ld (ATRIBUTOS+3),a
                inc hl
                ld a,(hl)
                ld (ATRIBUTOS+7),a
                pop hl
                ret

CACHE_VALIDA:   defb 0                  ; 1 mientras CACHE sea el trozo de ESQUINA con ULTIMO_MODO
ULTIMO_MODO:    defb 0
ESQUINA_H:      defb 0                  ; la posicion del cursor la ultima vez que se repinto
ESQUINA_L:      defb 0
ATRIBUTOS:      defb 209,0,0,1, 209,0,1,1       ; los dos sprites: Y, X, patron, color

; --------------------------------------------------------------------------
; MI_MUEVE: sustituye al `call MUEVE_POR_EL_MAPA` de 0x7225. Con la vuelta a
; mas de 40 por segundo, el cursor -que avanza una casilla POR VUELTA con la
; tecla pulsada- iria a 25-43 casillas por segundo. Se limita a una casilla
; cada PASO_DEL_CURSOR cuadros, contados por el gancho de la interrupcion.
; Sin ninguna direccion pulsada el contador se deja listo, asi que una
; pulsacion suelta mueve al instante: lo que se limita es MANTENER pulsado.
; A = el mando, HL = la posicion; pisa lo que pisaba MUEVE_POR_EL_MAPA.
; --------------------------------------------------------------------------
MI_MUEVE:
                ld b,a
                and 00fh                ; bits 0-3: arriba, abajo, izquierda, derecha
                jr nz,MM_DIRECCION
                ld a,(CUADROS)          ; nada pulsado: la siguiente pulsacion mueve al instante
                sub PASO_DEL_CURSOR
                ld (ULTIMO_PASO),a
                ret
MM_DIRECCION:   ld a,(ULTIMO_PASO)
                ld c,a
                ld a,(CUADROS)
                sub c                   ; cuadros desde el ultimo paso (modulo 256)
                cp PASO_DEL_CURSOR
                ret c                   ; todavia no
                ld a,(CUADROS)
                ld (ULTIMO_PASO),a
                ld a,b
                jp MUEVE_POR_EL_MAPA
ULTIMO_PASO:    defb 0                  ; el cuadro del ultimo paso del cursor

                include "cursor.inc"    ; CURSOR_PATRONES (192 B) y CURSOR_COLORES (6), de cursor.png

CACHE:          defs TAM_PANTALLA       ; el trozo limpio; viaja en la ROM como ceros

                IF SOMBRA
; La sombra: 24 filas de 32, alineadas a 256 para que `inc l` recorra una fila
; sin dar la vuelta. Viaja en la ROM como ceros y no importa lo que traiga:
; MODO_NOMBRES a 0 la invalida.
ALINEA:         defs (256 - (ALINEA and 255)) and 255
SOMBRA_BUF:     defs 768
                ENDIF

NOMBRES_FIN:
