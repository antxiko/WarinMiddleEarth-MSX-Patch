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
; EL CURSOR COMO SPRITE, Y LA CACHE DEL TROZO
;
; Con la tabla de nombres la vuelta bajo de 1.132.000 a 363.884 ciclos, y de
; esos, 330.031 eran DIBUJA_EL_TROZO_DE_MAPA (0x7643): repintar las 16 x 13
; celdas del trozo EN CADA VUELTA, aunque el cursor no se moviera. Y se
; repintaba porque el cursor iba dentro de la pantalla de caracteres -cuatro
; caracteres de 0x77B5+modo*4 escritos encima del centro- y parpadeaba.
;
; Ahora el cursor es un SPRITE de 16x16 -dos, uno por color, solapados: el
; dibujo y el bloque de detras, que salen de src/cartucho/cursor.png-, SIEMPRE
; en el centro, la celda (7, 5) del trozo, como en el original: lo que se
; mueve es el mapa. El trozo solo se repinta cuando cambia la posicion del
; cursor o el modo; en las demas vueltas -el reposo, que es donde se iba el
; 91 % del tiempo, y el menu de la casilla- la pantalla de caracteres limpia
; (el trozo sin ventanas) vuelve de CACHE (850 B) con un `ldir`, y las
; ventanas de posicion, ficha y sitio se dibujan encima como siempre. (Hubo
; una version con la ventana del trozo quieta y el cursor moviendose dentro,
; con un margen de tres celdas; el usuario prefirio el cursor fijo y el mapa
; moviendose, que es como se juega al original, y se quito.)
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
; La cache vale mientras no cambie la posicion, ni el modo (0x71CF: el trozo
; lleva la marca de la casilla de partida de una orden, que se quita al volver
; al modo mirar), ni haya pasado el guardian (todo menu es de bitmap y por el
; pasa; y las ordenes marcan la casilla justo despues de un menu). El reloj
; del juego no corre en la vista: solo lo mueve BUCLE_DE_PARTIDA.
;
; Los atributos de los dos sprites -Y = 79 y X = 112, la celda (7, 5), y el
; patron y el color segun el modo- los deja MI_PINTA en ATRIBUTOS y los sube
; CARACTERES_A_NOMBRES detras de los nombres, en cada vuelta; los 192 bytes
; de patrones los sube PONE_LOS_PATRONES al entrar. El tamano 16x16 lo pone
; el cargador en R1 (0xE2): el juego nunca escribe R1. El guardian, al
; devolver la identidad, deja los dos sprites como los dejo el cargador
; (Y=209: fuera de la pantalla). En el centro no lo tapa ninguna ventana: la
; ficha va de la fila 13 de caracteres para abajo (0x5FBD; en los modos 0x12
; y 0x17, en la fila 20) y los carteles de posicion, destino y sitio no pasan
; de la fila 3. En el original tampoco lo tapaba nada.
;
; ELEGIR ENTRE LAS UNIDADES DE LA CASILLA, POR TOQUE
;
; Con fuego sobre una casilla con varias unidades, ELIGE_ENTRE_LAS_DE_LA_CASILLA
; (0x7751) entra en un bucle en el que arriba y abajo pasan de una unidad a
; otra y cada paso repinta la vista. En el original una vuelta de ese bucle
; era un repintado entero (3 por segundo); con la cache va a mas de 40, y con
; la tecla pulsada era imposible parar en la unidad que se queria. Decision
; del usuario: arriba y abajo van por TOQUE, no por tiempo. MI_ELECCION
; sustituye al `call LEE_LOS_MANDOS` de 0x7758 y solo deja pasar esos dos
; bits en la vuelta en que se pulsan: hasta soltar y volver a pulsar no hay
; otro paso.
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
CURSOR_COL      equ 7           ; la celda del trozo (16 x 13) en la que cae el cursor: el centro
CURSOR_FILA     equ 5           ; (0x71B5 hace `inc h` y resta 720 = 7 columnas y 6 filas)
CURSOR_X        equ 16*CURSOR_COL       ; los sprites: 16 pixels por celda
CURSOR_Y        equ 16*CURSOR_FILA-1    ; y el VDP pinta el sprite una linea por debajo de Y
MUEVE_POR_EL_MAPA equ 0734Bh    ; A = mando, HL = posicion; mueve una casilla
LEE_LOS_MANDOS  equ 0066Dh      ; A = el mando: bits 0-3 direcciones, 4 fuego, 5 la tecla 1, 6 la R
PASO_DEL_CURSOR equ 10          ; cuadros entre casilla y casilla con la tecla pulsada: 5 por segundo a 50 Hz (6 a 60)
PASO_EN_LA_BATALLA equ 16       ; y en la batalla, 3,1 por segundo: los que daba la cinta antes de acelerar el tablero
                                ; CUADROS lo lleva el gancho de la interrupcion (puente.asm) y llega como --equ
DESPLAZA_ESQUINA equ -720       ; lo que resta 0x71B9 a la celda de (H+1, L)
TAM_PANTALLA    equ 850         ; 25 filas de 34

; El guante del mapa general
GUANTE_COL      equ 06543h      ; la columna del cursor del mapa, en pixeles (operando de 0x6542)
GUANTE_FILA     equ 06544h      ; y su fila; las dos las mueve MUEVE_EL_CURSOR (0x650D)
GUANTE_PAT_A    equ 24          ; los dos planos van detras de los seis del cursor (192 B = patron 24)
GUANTE_PAT_B    equ 28          ; en 16x16 el numero de patron va de cuatro en cuatro
FUERA_DE_LA_PANTALLA equ 209    ; la Y con la que el cargador aparca los 32 sprites

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
; MI_PINTA dejo en ATRIBUTOS: Y, X, patron y color de cada uno.
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
                ld a,(GUANTE_PUESTO)
                or a
                call nz,ESCONDE_EL_GUANTE
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
; Si la cache vale y la posicion y el modo son los de la ultima vez, la
; pantalla vuelve a ser el trozo limpio de la cache. Si no, se repinta como
; lo hacia 0x71A7-0x71C5 y se guarda. Y en los dos casos se dejan en
; ATRIBUTOS el patron y el color de los dos sprites segun el modo; Y y X no
; cambian nunca: el cursor esta siempre en el centro.
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
                ld a,(POSICION_L)
                cp b
                jr nz,MP_REPINTA
                ld a,h
                and 07fh
                ld b,a
                ld a,(POSICION_H)
                cp b
                jr nz,MP_REPINTA
                push hl                 ; la misma casilla y el mismo modo: el trozo limpio, de la cache
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
                ld (POSICION_L),a
                ld a,h
                and 07fh
                ld (POSICION_H),a
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
MP_CURSOR:      ld a,(MODO_DE_LA_VISTA) ; el dibujo segun el modo: 0x10 -> 0, 0x12 -> 1, 0x17 -> 2
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

CACHE_VALIDA:   defb 0                  ; 1 mientras CACHE sea el trozo de POSICION con ULTIMO_MODO
ULTIMO_MODO:    defb 0
POSICION_H:     defb 0                  ; la posicion del cursor con la que se pinto el trozo de la cache
POSICION_L:     defb 0
ATRIBUTOS:      defb CURSOR_Y,CURSOR_X,0,1, CURSOR_Y,CURSOR_X,1,1   ; los dos sprites: Y, X, patron, color

; --------------------------------------------------------------------------
; MI_MUEVE: sustituye al `call MUEVE_POR_EL_MAPA` de 0x7225. Con la vuelta a
; mas de 40 por segundo en reposo -y a unas 10 moviendo, que cada paso repinta
; el trozo-, el cursor, que avanza una casilla POR VUELTA con la tecla
; pulsada, iria disparado. Se limita a una casilla
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

; --------------------------------------------------------------------------
; MI_ELECCION: sustituye al `call LEE_LOS_MANDOS` de 0x7758, el del bucle de
; ELIGE_ENTRE_LAS_DE_LA_CASILLA (ver la cabecera). Arriba y abajo (bits 0 y
; 1) solo pasan en la vuelta en que se pulsan: un toque es un paso, y hasta
; soltar y volver a pulsar no hay otro. Fuego y la tecla 1 (bits 4 y 5), que
; son las dos salidas del bucle, pasan tal cual, y al salir se olvida lo
; pulsado: la proxima entrada empieza sin nada apretado. Devuelve A como
; LEE_LOS_MANDOS, y como ella no toca BC, DE ni HL.
; --------------------------------------------------------------------------
MI_ELECCION:
                call LEE_LOS_MANDOS
                push bc
                ld b,a                  ; el mando de ahora
                ld a,(ULTIMA_ELECCION)
                cpl
                and b                   ; pulsado ahora y no en la vuelta anterior
                and 003h                ; solo arriba y abajo van por toque
                ld c,a
                ld a,b
                ld (ULTIMA_ELECCION),a
                and 030h                ; fuego o la tecla 1: se sale del bucle
                jr z,ME_TOQUES
                xor a
                ld (ULTIMA_ELECCION),a  ; la proxima entrada, de cero
                ld a,b                  ; y el mando entero: 0x775B y 0x7760 miran esos bits
                pop bc
                ret
ME_TOQUES:      ld a,b
                and 0FCh                ; el resto de bits, tal cual
                or c                    ; y arriba/abajo solo si acaban de pulsarse
                pop bc
                ret
ULTIMA_ELECCION: defb 0                 ; el mando de la vuelta anterior del bucle de eleccion

; --------------------------------------------------------------------------
; MI_CURSOR_BATALLA: sustituye al `call LEE_LOS_MANDOS` de 0x8E10, el de
; MUEVE_EL_CURSOR_DE_BATALLA (0x8E0D). Ese cursor se corre UNA casilla por
; vuelta del bucle de batalla, asi que su velocidad es la del bucle: con el
; tablero subiendo solo lo que cambia la vuelta paso de 0,3170 a 0,1068 s, o
; sea de 3,2 a 9,4 casillas por segundo, y el cursor se volvio ingobernable.
; Es el mismo problema que arreglo MI_MUEVE en el mapa y se arregla igual: las
; cuatro direcciones (bits 0-3) solo pasan una vez cada PASO_EN_LA_BATALLA
; cuadros; el disparo y la tecla 1 pasan SIEMPRE, que ya tienen su propia
; espera a soltar en PULSA_EN_LA_BATALLA. Sin ninguna direccion pulsada el
; contador se deja listo, asi que una pulsacion suelta mueve al instante: lo
; que se limita es MANTENER pulsado. Devuelve A como LEE_LOS_MANDOS y, como
; ella, no toca BC, DE ni HL (en 0x8E13 el HL de 0x8E0D sigue vivo).
; --------------------------------------------------------------------------
MI_CURSOR_BATALLA:
                call LEE_LOS_MANDOS
                push bc
                ld b,a
                and 00fh                ; bits 0-3: las cuatro diagonales
                jr nz,MCB_DIRECCION
                ld a,(CUADROS)          ; nada pulsado: la siguiente pulsacion mueve al instante
                sub PASO_EN_LA_BATALLA
                ld (ULTIMO_PASO_BATALLA),a
                jr MCB_TAL_CUAL
MCB_DIRECCION:  ld a,(ULTIMO_PASO_BATALLA)
                ld c,a
                ld a,(CUADROS)
                sub c                   ; cuadros desde el ultimo paso (modulo 256)
                cp PASO_EN_LA_BATALLA
                jr nc,MCB_AHORA
                ld a,b
                and 0F0h                ; todavia no: se caen las direcciones y lo demas pasa
                pop bc
                ret
MCB_AHORA:      ld a,(CUADROS)
                ld (ULTIMO_PASO_BATALLA),a
MCB_TAL_CUAL:   ld a,b
                pop bc
                ret
ULTIMO_PASO_BATALLA: defb 0             ; el cuadro del ultimo paso del cursor de la batalla

; --------------------------------------------------------------------------
; MI_GUANTE: sustituye al `call REFRESCA_EL_CURSOR` (0x07C3) de 0x7F57, la
; primera linea del bucle de partida. Sube los ocho bytes de atributos de los
; sprites 2 y 3 -el guante- leyendo la posicion de donde la deja MUEVE_EL_CURSOR,
; y los 64 de patrones la primera vez despues de cada escondida. Pisa AF, BC y
; HL; el bucle de partida no lleva nada vivo en ese punto.
;
; El VDP pinta el sprite una linea POR DEBAJO de su Y, asi que Y = fila - 1; con
; la fila 0 sale 255, que el TMS9918 entiende como -1 y pinta desde la linea 0.
; --------------------------------------------------------------------------
MI_GUANTE:
                ld a,(GUANTE_PUESTO)
                or a
                call z,PON_EL_GUANTE
                ld a,(GUANTE_FILA)
                dec a
                ld (GUANTE_AT),a
                ld (GUANTE_AT+4),a
                ld a,(GUANTE_COL)
                ld (GUANTE_AT+1),a
                ld (GUANTE_AT+5),a
                ld hl,VRAM_SPRITES+8    ; los sprites 2 y 3: los 0 y 1 son el cursor de la vista
                call DIRECCION_VRAM
                ld hl,GUANTE_AT
                ld b,8
MG_BYTE:        ld a,(hl)               ; 7
                out (098h),a            ; 11
                inc hl                  ; 6
                djnz MG_BYTE            ; 13 = 37 ciclos por byte
                ret

PON_EL_GUANTE:                  ; los dos planos, detras de los seis del cursor
                ld hl,VRAM_SPRITES_PAT+CURSOR_COLORES-CURSOR_PATRONES
                call DIRECCION_VRAM
                ld hl,GUANTE_PATRONES
                ld b,64
PG_BYTE:        ld a,(hl)
                out (098h),a
                inc hl
                djnz PG_BYTE            ; 37 ciclos por byte
                ld a,1
                ld (GUANTE_PUESTO),a
                ret

; El guante fuera de la pantalla. Lo llama el GUARDIAN: cualquiera que vaya a
; pintar -un menu, la ficha, la vista, la batalla, una pantalla final- pasa por
; 0x044B, y un sprite se quedaria por delante de lo que venga. Se vuelve a ver
; en la vuelta siguiente del bucle de partida, que es la unica que lo pone.
; Preserva BC y HL, que es lo que el guardian le debe a los llamadores de
; 0x044B, y no abre las interrupciones: estamos dentro de 0x044B.
ESCONDE_EL_GUANTE:
                push bc
                push hl
                ld hl,VRAM_SPRITES+8
                call PON_DIRECCION
                ld hl,GUANTE_ESCONDIDO
                ld b,8
EG_BYTE:        ld a,(hl)
                out (098h),a
                inc hl
                djnz EG_BYTE            ; 37 ciclos por byte
                xor a
                ld (GUANTE_PUESTO),a
                pop hl
                pop bc
                ret

GUANTE_PUESTO:  defb 0                  ; 1 mientras el guante este en la VRAM, patrones incluidos
GUANTE_AT:      defb 0,0,GUANTE_PAT_A,GUANTE_COLOR_A, 0,0,GUANTE_PAT_B,GUANTE_COLOR_B
GUANTE_ESCONDIDO: defb FUERA_DE_LA_PANTALLA,0,GUANTE_PAT_A,GUANTE_COLOR_A
                defb FUERA_DE_LA_PANTALLA,0,GUANTE_PAT_B,GUANTE_COLOR_B

                include "cursor.inc"    ; CURSOR_PATRONES (192 B) y CURSOR_COLORES (6), de cursor.png
                include "guante.inc"    ; GUANTE_PATRONES (64 B) y sus dos colores, de guante.png

CACHE:          defs TAM_PANTALLA       ; el trozo limpio; viaja en la ROM como ceros

                IF SOMBRA
; La sombra: 24 filas de 32, alineadas a 256 para que `inc l` recorra una fila
; sin dar la vuelta. Viaja en la ROM como ceros y no importa lo que traiga:
; MODO_NOMBRES a 0 la invalida.
ALINEA:         defs (256 - (ALINEA and 255)) and 255
SOMBRA_BUF:     defs 768
                ENDIF

; --------------------------------------------------------------------------
; MI_FUERZA: sustituye el calculo de FUERZA_DE_LA_TROPA (0x8DE4), que estaba
; roto de fabrica.
;
; QUE HACIA EL ORIGINAL. Al montar una batalla, cada figura nace con una vida
; que sale de restarle algo a 255 (0x8D40), y ese algo tenia que ser lo que a
; su tipo de tropa le cuesta el terreno donde se pelea: la tabla de 0x6D47,
; diez fichas de dieciseis bytes, la misma que se consulta para andar.
;
; Pero la rutina NO recibe el tipo de tropa. 0x8D37 le pasa en A el 0xC200 de
; la unidad -lo que le queda de andar-, lo multiplica por ocho, le suma 0x47 y
; le mete el terreno con un `or`, asi que la direccion recorre toda la pagina
; 0x6D00: cae dentro de la tabla, en el bufer de la ficha en curso (0x6D37),
; en la red de caminos chica o en el codigo que empieza en 0x6DE7. Ejecutada
; con las 4.096 parejas posibles devuelve ONCE valores distintos (medido con
; tools/omsx_barre_fuerza.tcl, en el repositorio del desensamblado): un 3 en
; dos de cada tres casos, porque la tabla esta llena de treses, y ademas 40,
; 57, 65, 66, 71, 72, 78, 88, 205 y 217.
;
; QUE HACE ESTA. Lo que se pretendia, y lo que hace bien el otro lector de esa
; misma tabla, TECLA_R_EN_LA_BATALLA (0x9296): coger el tipo de tropa de
; 0xBD00 -el llamador deja HL en 0xC200+n, asi que L ya trae el numero de
; unidad-, apuntar a su ficha con tipo*16 y leer dentro con el terreno. Un
; tipo sin ficha (de 10 arriba, que la cinta no usa) cae en la primera, para
; no leer fuera de la tabla.
;
; Devuelve en A el byte de la tabla, que es lo que 0x8DF1 espera, y como la
; original no toca ni DE ni la pila. B se usa de paso: el llamador no lo
; necesita (0x8D40-0x8D46 solo miran A, C y D).
; --------------------------------------------------------------------------
TERRENO_DE_LA_BATALLA:  equ 08deah      ; el nibble del terreno, que escribe 0x902F

MI_FUERZA:
                ld h,0bdh               ; L trae el numero de unidad: 0xBD00+n
                ld a,(hl)
                and 00fh                ; el tipo de tropa
                cp 00ah
                jr c,MF_CON_FICHA
                xor a                   ; de 10 arriba no hay ficha: la primera
MF_CON_FICHA:   add a,a
                add a,a
                add a,a
                add a,a                 ; por dieciseis: el principio de su ficha
                ld b,a
                ld a,(TERRENO_DE_LA_BATALLA)
                add a,b                 ; + el terreno donde se pelea
                add a,047h              ; 0x6D47 + tipo*16 + terreno
                ld l,a
                ld h,06dh               ; 9*16 + 15 + 0x47 = 230: nunca hay acarreo
                ld a,(hl)
                ret

; --------------------------------------------------------------------------
; LA BATALLA: SUBIR SOLO LO QUE CAMBIA
;
; Cada vuelta del tablero acababa subiendo la pantalla ENTERA al VDP:
;
;     8849  call 005bdh   ; BITMAP_A_VRAM     los 6.144 bytes del dibujo
;     884C  call 00604h   ; ATRIBUTOS_A_VRAM  los 768, traducidos a 6.144 escrituras
;     884F  ret
;
; Medido en una batalla de verdad -63 vueltas del replay de Ruben, VG-8020-:
;
;     BITMAP_A_VRAM       169.529 ciclos
;     ATRIBUTOS_A_VRAM    597.698 ciclos
;     las dos             757.888 ciclos = 0,212 s por vuelta
;
; LOS ATRIBUTOS NO HACEN FALTA. ARMA_LOS_DOS_BANDOS (0x90A6) ya los sube al
; montar la batalla, las fichas se dibujan solo en el bitmap (DOS_LINEAS_*
; escriben en 0x4000-0x57FF) y el texto de abajo escribe su atributo DIRECTO a
; la VRAM. Medido con un punto de observacion de escritura sobre 0x5800-0x5AFF
; durante esas 63 vueltas: NADIE los toca. Asi que ese `call` se quita entero.
;
; Y DEL BITMAP SOLO CAMBIAN 10,2 FICHAS DE 256 por vuelta (medido; el reparto
; va 10, 1, 30, 1, 14, 1 ... segun le toque mover a un bando o a otro). Cada
; ficha son dos celdas, y RECUADRO_A_VRAM (0x0702) cuesta unos 311 ciclos por
; celda: el punto de equilibrio son 552 celdas y el tablero entero son 512, o
; sea que subir ficha a ficha gana hasta repintandolo completo.
;
; No hace falta lista de sucias: el bucle YA sabe cuales son. 0x872F pone a
; cero las banderas de las fichas iguales y 0x87A2 se las salta, y en
; SIGUIENTE_FICHA (0x8825) DE trae la direccion de pantalla de la ficha que se
; acaba de mirar. Se engancha ahi, en el `ld hl,(0x87DC)` de 0x8828.
;
; LA PRIMERA VUELTA de cada batalla sube el tablero entero: el fondo no son
; fichas y nadie lo subiria. MI_ARMA la marca al montar la batalla.
; --------------------------------------------------------------------------
BITMAP_A_VRAM:    equ 005BDh    ; los 6.144 bytes del bitmap, de golpe
LOS_ATRIBUTOS:    equ 00604h    ; los 768 atributos
RECUADRO_A_VRAM:  equ 00702h    ; D=fila, E=columna, B=filas, C=columnas
FICHA_EN_LA_LISTA: equ 087DCh   ; operando de 0x87DB: la ficha que se esta mirando

TABLERO_SIN_SUBIR: defb 1       ; 1 mientras el tablero de esta batalla este por subir entero

; Sustituye al `call LOS_ATRIBUTOS` de 0x90A6 (ARMA_LOS_DOS_BANDOS): hace lo
; mismo y ademas apunta que el tablero de esta batalla esta sin subir.
MI_ARMA:
                ld a,1
                ld (TABLERO_SIN_SUBIR),a
                jp LOS_ATRIBUTOS

; Sustituye al `call BITMAP_A_VRAM` de 0x8849: solo sube el tablero entero la
; primera vuelta de cada batalla; de ahi en adelante cada ficha se ha subido
; sola.
MI_SUBE_TABLERO:
                ld a,(TABLERO_SIN_SUBIR)
                or a
                ret z
                xor a
                ld (TABLERO_SIN_SUBIR),a
                jp BITMAP_A_VRAM

; Sustituye al `ld hl,(0x87DC)` de 0x8828, dentro de SIGUIENTE_FICHA. Ahi DE
; trae la direccion de pantalla ZX de la ficha que se acaba de mirar. Se entra
; con el juego de registros ALTERNATIVO (0x8798 hizo `exx`), y ni
; RECUADRO_A_VRAM ni el guardian de 0x044B usan `exx`, asi que basta con
; guardar los tres pares. A no hace falta: de 0x882B a 0x8831 nadie lo mira.
MI_SUBE_FICHA:
                ld hl,(FICHA_EN_LA_LISTA)   ; lo que hacia 0x8828
                ld a,(hl)
                or a
                ret z                       ; esta ficha no cambio: nada que subir
                ld a,(TABLERO_SIN_SUBIR)
                or a
                ret nz                      ; la primera vuelta la sube entera 0x8849
                push hl
                push de
                push bc
                ; La direccion ZX lleva la columna en los bits 4-0 de E, la fila
                ; dentro del tercio en los 7-5, y el tercio en los bits 4-3 de D.
                ld a,e
                and 01Fh
                ld c,a                      ; la columna
                ld a,e
                rlca
                rlca
                rlca
                and 007h                    ; la fila dentro del tercio
                ld b,a
                ld a,d
                and 018h                    ; el tercio ...
                rrca
                rrca
                rrca
                add a,a                     ; ... por ocho
                add a,a
                add a,a
                add a,b
                ld d,a                      ; la fila, de 0 a 23
                ld e,c                      ; la columna
                ld bc,00102h                ; una fila de celdas, dos columnas
                call RECUADRO_A_VRAM
                pop bc
                pop de
                pop hl
                ret

; --------------------------------------------------------------------------
; EL INFILTRADO DEL CENTRO DEL CAMPO DE BATALLA
;
; Al montar cada batalla, 0x914B llama a DEJA_DE_LLEVARLA_A_MANO (0x8C6C) para
; dejar el cursor, el despachador y el aviso en su sitio. Esa rutina termina
; con `jp PON_LA_UNIDAD_EN_EL_TABLERO`, que planta en la casilla del CENTRO de
; la pantalla la unidad que dice 0x8C63, "la que se lleva a mano".
;
; Y 0x8C63 no lo reinicia nadie: lo escribe un unico sitio de toda la ROM
; (0x8B98, al coger una unidad) y conserva su valor de una batalla a la
; siguiente. Como cada batalla monta las figuras que necesita -y son muchas
; menos que en la anterior-, ese numero acaba senalando a una figura que ya no
; existe: aparece en el centro del tablero con el dibujo, el fotograma, la vida
; y el DUENO de la batalla vieja, porque al plantarla no se toca ninguno de sus
; datos. Es el "infiltrado" que se mueve y no ataca, o da vueltas, o se
; convierte en orco, o es casi inmortal.
;
; Y cuando lo matan, FIGURA_ABATIDA (0x8EFD) mira de quien era en 0xC600+figura
; y sale un numero bajo heredado -00 Gandalf, 01 Aragorn, 02 Boromir...-; como
; los 24 personajes con nombre llevan 0xC500 = 0 figuras, el cero se lee como
; "ejercito agotado" y BORRA_EL_EJERCITO_DEL_MAPA se lleva del mapa a un heroe
; que no estaba en la batalla.
;
; Medido en el replay de Araubi (mes 1 dia 32): cogio a mano la figura 0x53 en
; una batalla de 161 figuras, y tres batallas despues, con solo 60 montadas,
; esa 0x53 aparecio en el centro y al matarla se llevo a Aragorn por delante.
;
; MI_MONTA_BATALLA sustituye al `call DEJA_DE_LLEVARLA_A_MANO` de 0x914B: hace
; la misma puesta a cero, y ademas deja 0x8C63 sin unidad, pero NO planta nada
; en el centro. El `jp PON_LA_UNIDAD_EN_EL_TABLERO` sigue donde estaba para
; cuando el jugador suelte una unidad de verdad, que es cuando hay que
; plantarla.
; --------------------------------------------------------------------------
CURSOR_DE_BATALLA:  equ 08E0Dh   ; el `ld hl` que mueve el cursor
INTERRUPTOR_8A68:   equ 08A68h   ; su gemelo, el opcode de 0x8A68
DIBUJO_DE_FICHA_3:  equ 08851h   ; el operando del dibujo de la ficha 3
FICHA_3_DE_SIEMPRE: equ 095A8h
AVISO_DE_BATALLA:   equ 09190h   ; 1 = "La Batalla ha comenzado."
DESPACHADOR_4:      equ 094BDh   ; la cuarta palabra del despachador de 0x9163
NO_HACE_NADA:       equ 08F19h   ; el `ret` suelto al que vuelve de fabrica
UNIDAD_ELEGIDA:     equ 08B23h   ; operando de 0x8B22: 0 si ninguna
UNIDAD_A_MANO:      equ 08C63h   ; operando de 0x8C62: la que se lleva a mano

MI_MONTA_BATALLA:
                ld a,021h                   ; 0x21 = ld hl: el cursor vuelve
                ld (CURSOR_DE_BATALLA),a    ;   a ser su rutina de siempre
                ld (INTERRUPTOR_8A68),a     ;   y el interruptor de opcode
                ld de,FICHA_3_DE_SIEMPRE
                ld (DIBUJO_DE_FICHA_3),de
                ld a,001h
                ld (AVISO_DE_BATALLA),a     ; "La Batalla ha comenzado."
                ld hl,NO_HACE_NADA
                ld (DESPACHADOR_4),hl       ; nadie lleva nada a mano
                xor a
                ld (UNIDAD_ELEGIDA),a       ; ni hay unidad elegida
                ld (UNIDAD_A_MANO),a        ; ni se arrastra la de la batalla
                ld a,001h                   ;   anterior: aqui NO se planta
                ld (TURBO_CUENTA),a         ; y la batalla empieza pintando
                ret

; --------------------------------------------------------------------------
; LA TECLA F: LA BATALLA DEPRISA
;
; Una batalla se resuelve en cientos de vueltas de BUCLE_DE_LA_BATALLA
; (0x914E), y cada vuelta va casi entera en dibujar. Medido en una batalla de
; verdad (work/rapido/mide_vuelta.tcl, VG-8020, 400 vueltas):
;
;     vuelta entera                462.251 ciclos = 0,1291 s   7,7 vueltas/s
;       MONTA_LA_PANTALLA (0x9160) 412.258 ciclos = 0,1152 s   el 89,2 %
;       el despachador    (0x917A) )
;       el cursor         (0x917D) ) lo que queda: 49.993 ciclos, el 10,8 %
;       el aviso de abajo (0x9186) )
;
; O sea que lo que marca el ritmo de la batalla NO son los calculos -mover las
; unidades y resolver los combates, que es el despachador- sino repintar el
; tablero. Por cada vuelta que se deja de pintar, la batalla avanza igual pero
; nueve veces mas deprisa.
;
; MI_TURBO sustituye al `call MONTA_LA_PANTALLA_DE_BATALLA` de 0x9160. Mira la
; tecla F y, si esta el modo rapido encendido, solo deja pintar una vuelta de
; cada PINTA_CADA; las demas vuelve sin hacer nada. La cuenta no se salta nada
; del juego: el despachador, el mando y los avisos siguen corriendo en TODAS
; las vueltas, y lo unico que se espacia es el dibujo.
;
; Saltarse el montaje entero es seguro porque MONTA_LA_PANTALLA_DE_BATALLA no
; guarda nada que haga falta despues: rellena las listas de 0xE800/0xEB00
; desde el tablero, las compara con las copias de 0xEE00/0xF000 -que son lo
; ULTIMO QUE SE PINTO, no lo de la vuelta anterior- y dibuja la diferencia. Al
; volver a pintar, esa comparacion saca todo lo que ha cambiado desde el
; ultimo dibujo, se pinten las vueltas que se pinten. Y el cursor del jugador
; (0x8E0D) lee el tablero de 0x5E00 directamente, no estas listas.
;
; La F se lee de la matriz como hace el propio juego con la 1 y la R en
; LEE_1_Y_R (0x067D): fila 3 -J I H G F E D C-, bit 3. Va por flanco, asi que
; conmuta una vez por pulsacion. El aviso se mete en el operando de 0x9180,
; que es de donde el bucle saca el texto de la linea de abajo en esta misma
; vuelta; 0x918C lo devuelve a la cadena vacia en cuanto se ha escrito, y el
; texto se ve aunque no se repinte el tablero porque PINTA_UN_CARACTER
; (0x82DC) sube cada celda a la VRAM por su cuenta.
; --------------------------------------------------------------------------
; PINTA_CADA lo pasa tools/haz_rom.py con --equ: alli esta el valor.
FILA_DE_LA_F:       equ 0F3h     ; fila 3 de la matriz: J I H G F E D C
BIT_DE_LA_F:        equ 008h     ; y la F es su bit 3
MONTA_LA_PANTALLA:  equ 086AFh   ; lo que habia en el `call` de 0x9160
AVISO_ESCRITO:      equ 09181h   ; operando de 0x9180: el texto de la linea de abajo

TURBO_ESTADO:   defb 0           ; 0 = como siempre, 1 = deprisa
TURBO_F_ANTES:  defb 0           ; la F tal como estaba en la vuelta anterior
TURBO_CUENTA:   defb 1           ; vueltas que faltan para volver a pintar

MI_TURBO:
                ld a,FILA_DE_LA_F
                out (0AAh),a
                in a,(0A9h)
                cpl                         ; un 1 es tecla pulsada
                and BIT_DE_LA_F
                ld hl,TURBO_F_ANTES
                cp (hl)
                ld (hl),a                   ; la de ahora pasa a ser la de antes
                jr z,TURBO_SIN_TOCAR        ; sigue como estaba
                or a
                jr z,TURBO_SIN_TOCAR        ; la acaban de soltar: no conmuta
                ld hl,TURBO_ESTADO          ; flanco de pulsacion: se conmuta
                ld a,(hl)
                xor 001h
                ld (hl),a
                ld hl,TEXTO_RAPIDO_NO
                or a
                jr z,TURBO_AVISA
                ld hl,TEXTO_RAPIDO_SI
TURBO_AVISA:
                ld (AVISO_ESCRITO),hl       ; el aviso sale en esta misma vuelta
                jp MONTA_LA_PANTALLA        ; y al conmutar se pinta siempre
TURBO_SIN_TOCAR:
                ld a,(TURBO_ESTADO)
                or a
                jp z,MONTA_LA_PANTALLA      ; modo normal: se pinta cada vuelta
                ld hl,TURBO_CUENTA
                dec (hl)
                ret nz                      ; aun no toca pintar
                ld (hl),PINTA_CADA
                jp MONTA_LA_PANTALLA

; Los dos avisos, de 30 caracteres como los de 0x93E5, para que tapen entero
; al que hubiera antes.
TEXTO_RAPIDO_SI:  defb "Batalla rapida: SI.           ",0
TEXTO_RAPIDO_NO:  defb "Batalla rapida: NO.           ",0

; ==========================================================================
; LA MARCA DE LAS UNIDADES EN EL MAPA GENERAL
;
; QUE PROBLEMA RESUELVE
;
; En el mapa general una unidad NO es un dibujo: REPINTA_LOS_EJERCITOS
; (0x6AAF) devuelve los 768 atributos al 0x30 del fondo -respetando el del
; panel- y le escribe UN BYTE al atributo de la celda de cada unidad (0x6AE0).
; O sea que una unidad es una CELDA DE OTRO COLOR, y por eso dos unidades
; juntas se funden en una mancha en la que no se puede contar cuantas hay.
;
; Aqui esa celda pasa a llevar ademas un DIBUJO de 8x8 -el Anillo, que sale de
; src/cartucho/marca.png-, que es lo que se puede contar de un vistazo.
;
; POR QUE NO HACE FALTA GUARDAR UNA COPIA DEL MAPA
;
; Estampar pixeles obliga a saber BORRARLOS cuando la unidad se mueve, y de
; ahi salio la idea de guardar una copia limpia del lienzo -6.144 bytes- en la
; RAM libre. No hace falta: esa copia YA EXISTE. El juego es un port del
; Spectrum y mantiene su pantalla emulada en 0x4000, en la pagina 1, que es
; RAM durante toda la partida (el puente conmuta la pagina 2, no esta). El
; dibujo se estampa SOLO EN LA VRAM, el lienzo de 0x4000 no se toca, y borrar
; una marca es volver a subir a la VRAM los ocho bytes que el lienzo ya tiene.
; Cuesta 2 bytes por marca -la fila y la columna- en vez de 6.144.
;
; Y por eso es correcto por construccion: el lienzo es la verdad y la VRAM su
; copia, asi que restaurar desde el lienzo siempre devuelve lo que el juego
; cree que hay en pantalla, haya pasado lo que haya pasado entre medias.
;
; LO QUE CUESTA
;
; REPINTA_LOS_EJERCITOS no corre por fotograma: el bucle de partida mueve UNA
; unidad por vuelta (0x6719) y solo la llama cuando el contador da la vuelta,
; o sea una vez cada 256. Y lo que ya pagaba ahi son los 597.698 ciclos de
; LOS_ATRIBUTOS -la misma cuenta que quito el parche de la batalla-. Esto
; anade el borrado de las marcas viejas, el barrido de los 768 atributos y el
; estampado de las nuevas: unos 110.000 ciclos, un 18 % sobre lo que ya
; costaba una rutina que corre una vez cada 256 vueltas.
;
; EL RITMO
;
; Los dos bucles van a 39 y 37 ciclos por byte. Con la pantalla encendida el
; TMS9918 no admite dos accesos a menos de ~29 y se le caen bytes: le pasa a
; PANTALLA_A_VRAM (0x05BD) y a RECUADRO_A_VRAM (0x0702), que van a 22 y
; pierden casi 4.000 bytes de los 6.144 (INVESTIGACION.md). Por eso ninguna de
; las dos se reutiliza aqui: una marca con un byte caido se quedaria sucia
; hasta el repintado siguiente, que son 256 vueltas mas tarde.
;
; DE DONDE SALE EL ATRIBUTO
;
; No se escribe aqui: se LEE de 0x6AE1, el operando del `ld a,070h` de 0x6AE0,
; que es donde el juego dice con que atributo marca. El parche del panel
; intercambia ese byte y el del panel, y asi la marca sigue al parche sola.
; Y por eso el barrido de los 768 encuentra exactamente las celdas marcadas:
; el bucle de limpieza deja el resto en 0x30 y el panel en el suyo.
; ==========================================================================

LOS_ATRIBUTOS_ZX: equ 05800h    ; los 768 atributos de la pantalla emulada
BITMAP_ZX:        equ 04000h    ; y su bitmap, que es la copia limpia del mapa
ATRIBUTO_MARCA:   equ 06AE1h    ; operando del `ld a,070h` de 0x6AE0: con que se marca
COLUMNAS:         equ 32
MAX_MARCAS:       equ 118       ; unidades 0x00..0x77 menos la 0x16 y la 0x17,
                                ; que 0x6AE3 se salta: no puede haber mas celdas marcadas

MARCAS_N:       defb 0                  ; cuantas marcas hay puestas ahora mismo
MARCAS_TAB:     defs MAX_MARCAS*2       ; y donde: fila y columna de cada una

; Sustituye al `call LOS_ATRIBUTOS` de 0x6AF1, lo ultimo que hace
; REPINTA_LOS_EJERCITOS. Los atributos se suben igual, y ademas se borran las
; marcas de la vuelta anterior y se estampan las de esta.
;
; Los atributos van PRIMERO a proposito: LOS_ATRIBUTOS pasa por
; VRAM_A_ESCRIBIR (0x044B) y con ella por el guardian, que devuelve la tabla
; de nombres a la identidad si la vista de cerca la habia cambiado. A partir
; de ahi la VRAM es la de siempre y se puede estampar.
;
; REGISTROS: lo llamaba un `call` seguido de `ret`, asi que no hay que
; devolver nada; pisa lo mismo que pisaba LOS_ATRIBUTOS (AF, BC, DE, HL y el
; juego alternativo) mas IX, que se guarda.
MI_MARCAS:
                call LOS_ATRIBUTOS      ; lo que hacia el 0x6AF1 de siempre
                push ix
                call MM_BORRA_LAS_VIEJAS
                call MM_PONE_LAS_NUEVAS
                pop ix
                ret

; Las de la vuelta anterior: cada una vuelve a ser lo que el lienzo dice.
MM_BORRA_LAS_VIEJAS:
                ld a,(MARCAS_N)
                or a
                ret z                   ; la primera vez no hay ninguna
                ld b,a
                ld ix,MARCAS_TAB
MM_UNA_VIEJA:   push bc
                ld d,(ix+000h)          ; la fila
                ld e,(ix+001h)          ; y la columna
                call MM_RESTAURA
                inc ix
                inc ix
                pop bc
                djnz MM_UNA_VIEJA
                ret

; Y las de ahora: los 768 atributos, y donde este el de marca va el dibujo.
; La cuenta se apunta segun se recorre, que es lo que borrara la vez que viene.
MM_PONE_LAS_NUEVAS:
                ld a,(ATRIBUTO_MARCA)
                ld (MM_EL_ATRIBUTO),a   ; el operando del `cp` de aqui abajo
                ld ix,MARCAS_TAB
                ld hl,LOS_ATRIBUTOS_ZX
                ld c,000h               ; cuantas van
                ld d,000h               ; la fila
MM_UNA_FILA:    ld e,000h               ; y la columna
MM_UNA_CELDA:   ld a,(hl)
                cp 000h                 ; automodificado: el atributo de marca
MM_EL_ATRIBUTO: equ $-1
                call z,MM_APUNTA_Y_ESTAMPA
                inc hl
                inc e
                ld a,e
                cp COLUMNAS
                jr nz,MM_UNA_CELDA
                inc d
                ld a,d
                cp FILAS
                jr nz,MM_UNA_FILA
                ld a,c
                ld (MARCAS_N),a
                ret

; D = fila, E = columna. Apunta la celda y le estampa el dibujo, si cabe.
MM_APUNTA_Y_ESTAMPA:
                ld a,c
                cp MAX_MARCAS
                ret z                   ; la tabla esta llena: no puede pasar, pero no se desborda
                ld (ix+000h),d
                ld (ix+001h),e
                inc ix
                inc ix
                inc c
                push hl
                push bc
                call MM_ESTAMPA
                pop bc
                pop hl
                ret

; --------------------------------------------------------------------------
; Los dos de verdad. En los dos, D = fila (0..23) y E = columna (0..31), y la
; celda son ocho bytes seguidos en la VRAM: fila*0x100 + columna*8.
; --------------------------------------------------------------------------

; El dibujo de la marca, a la VRAM. El lienzo de 0x4000 NO se toca.
MM_ESTAMPA:     call MM_APUNTA_LA_VRAM
                ld hl,DIBUJO_MARCA
                ld b,8
ME_LINEA:       ld a,(hl)               ; 7
                out (098h),a            ; 11
                inc hl                  ; 6
                djnz ME_LINEA           ; 13 = 37 ciclos por byte
                ret

; Y al reves: lo que el lienzo tiene en esa celda, a la VRAM. Las ocho lineas
; de una celda del Spectrum no van seguidas, estan a 256 bytes una de otra.
MM_RESTAURA:    push de
                call MM_APUNTA_LA_VRAM
                pop de
                ld a,d
                and 018h                ; el tercio ...
                or 040h                 ; ... y el 0x40: el byte alto del bitmap
                ld h,a
                ld a,d
                and 007h                ; la fila dentro del tercio, por 32
                rrca                    ; tres rrca en un byte de ocho bits
                rrca                    ; son un desplazamiento de cinco a la izquierda
                rrca
                or e
                ld l,a
                ld b,8
MR_LINEA:       ld a,(hl)               ; 7
                out (098h),a            ; 11
                inc h                   ; 4   +256: la linea de abajo
                nop                     ; 4   para no bajar de los 29 del VDP
                djnz MR_LINEA           ; 13 = 39 ciclos por byte
                ret

; D = fila, E = columna -> la VRAM queda apuntando a los ocho bytes de esa
; celda. D y E se conservan.
MM_APUNTA_LA_VRAM:
                ld h,d                  ; fila*0x100 ...
                ld a,e
                add a,a                 ; ... mas columna*8
                add a,a
                add a,a
                ld l,a
                jp DIRECCION_VRAM

; El dibujo, ocho bytes. Lo pone tools/haz_rom.py desde src/cartucho/marca.png
; y de fabrica es el Anillo: el caracter 0x5F de la fuente del juego, el mismo
; que el parche pinta en la ficha del Portador.
DIBUJO_MARCA:
                include "marca.inc"

; ==========================================================================
; LA LISTA DE NOMBRES, MUDADA: DOS HEROES MAS
;
; QUE PROBLEMA RESUELVE
;
; El juego guarda un nombre por unidad para las ranuras 0x00-0x17, en una
; lista de 0x6B46 separada por bytes 0xB7. Mide 181 bytes CLAVADOS: delante
; lleva la cabecera del menu de entrega (0x6B3D: renglones y columnas) con
; "Vuelve" detras, y en 0x6BFB justo empieza la red de caminos de 64 puntos
; que lee 0x69C6. No hay ni un byte de holgura, asi que los dos nombres
; nuevos -22 bytes- no caben ahi.
;
; Pero solo CINCO sitios miran la lista, y por eso se puede mudar entera:
;
;   0x6982  el puntero de BUSCA_EL_NOMBRE (0x6981)
;   0x6985  el largo, que es el tope del `cpir` que cuenta separadores
;   0x7302  el puntero a la cabecera, en MENU_DE_ENTREGA (0x72F5)
;   0x72F8  y 0x7309: las dos escrituras del byte de CORTE, que es el 0xB7
;           de "Faramir". El menu mete un 0 ahi para que la lista se acabe
;           antes de Gollum, y se lo devuelve al salir.
;
; Mas los dos topes por numero de unidad, que suben de 0x17/0x18 a 0x1A:
; 0x6E19 (a quien persigue) y 0x6F2D (la ficha).
;
; POR QUE AQUI Y NO EN EL IPS DE LA CINTA
;
; Porque en la cinta no hay donde meterlos: el mapa de RAM
; (tools/mapa_ram.py) dice que dentro de los tres bloques no queda hueco de
; fiar, y un IPS solo puede escribir donde la cinta carga. O sea que los dos
; heroes son cosa del CARTUCHO, como la musica, el mapa dibujado o la vista
; de cerca. La cinta se queda como esta.
;
; LO QUE NO HACE
;
; Los dos nuevos NO salen en el menu de entrega del Anillo: van detras de
; Saruman y el corte deja la lista en "Faramir". Es a proposito y esta
; decidido; lo que costaria meterlos esta en la memoria del proyecto.
; ==========================================================================

MI_NOMBRES_CABECERA:
                defb 21                 ; renglones del menu, como en la cinta
                defb 9                  ; y su anchura en columnas
                defb "Vuelve",0B7h
MI_NOMBRES:
                defb "Gandalf",0B7h     ; 0x00
                defb "Aragorn",0B7h     ; 0x01
                defb "Boromir",0B7h     ; 0x02
                defb "Legolas",0B7h     ; 0x03
                defb "Gimli",0B7h       ; 0x04
                defb "Frodo",0B7h       ; 0x05
                defb "Sam",0B7h         ; 0x06
                defb "Merry",0B7h       ; 0x07
                defb "Pippin",0B7h      ; 0x08
                defb "Elrond",0B7h      ; 0x09
                defb "Dain II",0B7h     ; 0x0A
                defb "Celeborn",0B7h    ; 0x0B
                defb "Thranduil",0B7h   ; 0x0C
                defb "Brand III",0B7h   ; 0x0D
                defb "Theodred",0B7h    ; 0x0E
                defb "Theoden",0B7h     ; 0x0F
                defb "Eowyn",0B7h       ; 0x10
                defb "Eomer",0B7h       ; 0x11
                defb "Imrahil",0B7h     ; 0x12
                defb "Denethor",0B7h    ; 0x13
                defb "Faramir"          ; 0x14
MI_NOMBRES_CORTE:                      ; el 0xB7 que el menu de entrega pisa con un 0
                defb 0B7h
                defb "Gollum",0B7h      ; 0x15
                defb "Sauron",0B7h      ; 0x16  (del otro bando)
                defb "Saruman",0B7h     ; 0x17  (del otro bando)
                defb "Tom Bombadil",0B7h ; 0x18  NUEVO: enano, el Bosque Viejo
                defb "Radagast",0B7h    ; 0x19  NUEVO: mago, Rhosgobel
MI_NOMBRES_FIN:
MI_NOMBRES_LARGO: equ MI_NOMBRES_FIN-MI_NOMBRES

NOMBRES_FIN:
