; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LO QUE SE DESCOMPRIME DE LA ROM
; CUANDO EL JUEGO LO PIDE: LAS DOS PANTALLAS FINALES Y EL MAPA GENERAL
;
; QUE PROBLEMA RESUELVE
;
; Las dos pantallas del final -la victoria en 0x094F y la derrota en 0x244F,
; 6.912 bytes cada una- ocupaban 13.824 bytes de RAM desde que arrancaba el
; cartucho hasta que acababa la partida, y se usan UNA VEZ, en los ultimos
; segundos. Estaban ahi por herencia: la cinta las cargaba asi y el cartucho
; se limitaba a reproducir lo que dejaba la cinta.
;
; Aqui se quedan solo en la ROM, comprimidas con ZX0, y se descomprimen a
; 0x4000 -que es a donde el juego las copiaba- en el momento de pintarlas.
;
; Y POR EL MISMO CAMINO, EL MAPA GENERAL (con --mapa)
;
; DIBUJA_EL_MAPA (0x8166) tarda 3,9 segundos en recorrer 23.500 casillas
; estampando pixeles de dos en dos, y lo hace CADA VEZ que se vuelve al mapa
; -o sea cada vez que se sale de la vista de cerca-. Pero ese dibujo no cambia
; nunca: solo depende del nibble bajo del byte de mapa, y lo que se mueve -las
; unidades- son ATRIBUTOS, que pinta REPINTA_LOS_EJERCITOS (0x6AAF) aparte.
; Asi que el lienzo va ya dibujado en la ROM, comprimido con ZX0, y aqui se
; descomprime en su sitio: los mismos 6.144 bytes, en una decima parte del
; tiempo. Quien lo dibuja al montar la ROM es tools/mapa_general.py, que es una
; transcripcion de las rutinas del juego cotejada byte a byte con el emulador.
;
; QUIEN LA LLAMA
;
; El juego, en PINTA_LA_PANTALLA_FINAL (0x83E7), donde los cuatro finales
; convergen. Alli habia ocho bytes:
;
;       ld de,04000h / ld bc,01b00h / ldir        11 00 40 01 00 1B ED B0
;
; y tools/haz_rom.py los cambia por `call FINALES` y cinco ceros. HL llega con
; 0x094F o con 0x244F, o sea que la rutina sabe cual le piden sin tocar
; VICTORIA ni DERROTA. Lo que viene detras -los dos `call` que suben la
; pantalla al VDP, el `di` y el bucle cerrado- no se toca.
;
; Y para el mapa, DIBUJA_EL_MAPA: sus tres bytes de 0x816B -el `ld hl,04000h`
; del `ldir` que ponia el lienzo a cero- pasan a ser `jp MAPA`. MAPA hace lo
; unico de 0x816B-0x81C0 que se nota fuera -borrar la pantalla-, descomprime
; el lienzo y sigue en 0x81C1, que es donde el juego lo sube al VDP. El `ldir`
; de 0x816B sobraba: BORRA_PANTALLA, dos instrucciones mas alla, vuelve a poner
; a cero ese mismo tramo. Y la trama de arranque que 0x817B dejaba en el
; operando de 0x7E75 (ELIGE_EL_RELLENO) tampoco hace falta: solo la leia
; PINTA_EL_PUNTO, que con el mapa ya dibujado no corre nunca. Hasta el
; 2026-09-19 MAPA la seguia eligiendo por fidelidad; se quito para que todo
; 0x7E4F-0x7EF9 quede sin un solo escritor y cuente como hueco.
;
; POR QUE EN DOS PASOS Y NO EN UNO
;
; El RLE de marca que habia antes descomprimia leyendo de la ventana de 0x8000
; y escribiendo en 0x4000 a la vez, cruzando de banco a mitad del flujo. Con
; ZX0 eso NO se puede, por dos razones:
;
;   1. **ZX0 usa la pila a fondo** -guarda el ultimo offset con `push bc` y lo
;      saca y mete con `ex (sp),hl`-, y la pila del juego vive en 0x5BFF, o sea
;      en la pagina 1, que es justo la que hay que conmutar al cartucho para
;      poder escribir el registro del mapper de 0x7000.
;   2. **ZX0 lee el origen de corrido** y no sabe cruzar de banco.
;
; Asi que primero se COPIA el bloque comprimido a la RAM -ahi si se cruza de
; banco, con un bucle que no toca la pila- y despues se llama a ZX0 con las
; cuatro paginas en RAM, sin cartucho a la vista.
;
; Y LA COPIA VA EN EL SITIO, SIN BUFER. Hasta el 2026-09-19 el comprimido se
; dejaba en un bufer de 4.096 B de la pagina 0 y de ahi se descomprimia a
; 0x4000. ZX0 esta hecho para no necesitarlo: si el comprimido se coloca
; PEGADO AL FINAL del destino -acabando `delta` bytes mas alla de donde acaba
; la salida-, la salida nunca alcanza a la entrada. Ese `delta` lo imprime el
; compresor y vale 2 en los tres bloques de aqui; tools/haz_rom.py lo apunta y
; calcula el sitio de cada uno (F0_DST, F1_DST y M_DST), que entra en DE. Los
; dos bytes que sobresalen caen en los atributos (el mapa: los repinta
; PINTA_TODOS_LOS_ATRIBUTOS tres instrucciones despues de volver) o en el
; fondo de la pila (las finales: el juego ha acabado y no vuelve). El bufer
; son 4.096 B de RAM que quedan libres.
;
; DONDE VIVE
;
; En la RAM que ella misma libera (0x094F-0x3F4E, 13.824 bytes seguidos en la
; pagina 0). Detras del puente de la musica ya no cabe: con el descompresor
; dentro pasa de los 166 bytes que hay hasta el buzon de POKEs. Y tiene que
; estar en la pagina 0 porque la 1 y la 2 se conmutan, y del stub de 0xD800 no
; hay que fiarse: en tiempo de juego puede estar pisado.
;
; Corre con `di`: mientras dura la copia, la pagina 2 es la ROM, y la
; interrupcion del juego usa datos que viven ahi. Se devuelve con `ei`, que es
; como llego.
; ==========================================================================

                include "direcciones.inc"

                org FINALES_ORG

DESTINO         equ DESTINO_PANTALLA    ; 0x4000: donde el juego copiaba la pantalla y donde la lee 0x05BD (lo pasa haz_rom.py)

; Las dos direcciones del juego que usa MAPA
BORRA_PANTALLA  equ 07F12h      ; A = atributo ZX: bitmap a cero y los 768 atributos a A, en RAM y en VRAM
SIGUE_EL_MAPA   equ 081C1h      ; el `call 005bdh` que sube el lienzo al VDP: por ahi sigue DIBUJA_EL_MAPA

; --------------------------------------------------------------------------
; Las dos pantallas finales. HL trae 0x094F o 0x244F, que es donde el juego
; iba a buscarlas. DE y BC estan libres: el `ld de,04000h / ld bc,01b00h` que
; el parche sustituye los iba a cargar justo aqui.
; --------------------------------------------------------------------------
FINALES:
                ld a,h
                cp F1_DIR / 256
                jr nc,F_DERROTA
                ld a,F0_BANCO
                ld hl,F0_SRC
                ld bc,F0_TAM
                ld de,F0_DST            ; pegado al final de la pantalla: en el sitio
                jp TRAE_Y_DESCOMPRIME
F_DERROTA:
                ld a,F1_BANCO
                ld hl,F1_SRC
                ld bc,F1_TAM
                ld de,F1_DST
                jp TRAE_Y_DESCOMPRIME

                IF HAY_MAPA
; --------------------------------------------------------------------------
; EL MAPA GENERAL. Entra por el `jp` que sustituye al `ld hl,04000h` de
; 0x816B y sale por 0x81C1, o sea que ocupa el sitio de 0x816B-0x81C0: el
; borrado del lienzo, la trama de arranque y las dos pasadas de terreno.
;
; De todo eso solo se nota fuera BORRA_PANTALLA, que deja la VRAM y el lienzo
; a cero y, de paso, pasa por el guardian de 0x044B, que devuelve la tabla de
; nombres a la identidad si se venia de la vista. El `ldir` de 0x816B no hace
; falta: BORRA_PANTALLA borra ese mismo tramo dos instrucciones mas alla. Y la
; trama de arranque (`ld a,3 / call ELIGE_EL_RELLENO`, como 0x817B) tampoco:
; solo la leia PINTA_EL_PUNTO, que ya no corre.
; --------------------------------------------------------------------------
MAPA:
                xor a                   ; como 0x8177: pantalla en negro
                call BORRA_PANTALLA
                ld a,M_BANCO
                ld hl,M_SRC
                ld bc,M_TAM
                ld de,M_DST             ; pegado al final del lienzo: en el sitio
                call TRAE_Y_DESCOMPRIME
                jp SIGUE_EL_MAPA
                ENDIF

; --------------------------------------------------------------------------
; A = banco, HL = donde se ve el bloque en la ventana de 0x8000, BC = lo que
; ocupa comprimido, DE = donde copiarlo en la RAM: al final de la pantalla,
; `delta` bytes mas alla de donde acaba lo descomprimido (ver arriba). Lo trae
; ahi y lo descomprime en el sitio, sobre 0x4000.
; --------------------------------------------------------------------------
TRAE_Y_DESCOMPRIME:
                ld (F_BANCO),a
                ld (F_DST),de           ; de aqui leera ZX0 cuando el bloque este en la RAM
                di

                ; --- los tres valores de 0xA8 que hacen falta, calculados una
                ; sola vez de lo que HAY: asi las paginas que no se tocan
                ; quedan como estuvieran.
                in a,(0A8h)
                ld (F_A8_RAM),a         ; todo como lo dejo el juego
                and 0CFh                ; fuera los bits 4-5: la pagina 2
F_RANURA2:
                or 000h                 ; <- el cargador escribe la primaria<<4
                ld (F_A8_CART2),a       ; ROM en la pagina 2, RAM en la 1
                and 0F3h                ; fuera tambien los bits 2-3: la pagina 1
F_RANURA1:
                or 000h                 ; <- ... y aqui la primaria<<2
                ld (F_A8_CART12),a      ; ROM en las dos: solo para el registro

                ; --- el banco a la ventana de 0x8000 (cartucho un momento en
                ; la pagina 1) y la ROM asomada en la pagina 2
                ld a,(F_A8_CART12)
                out (0A8h),a
                ld a,(F_BANCO)
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_CART2)
                out (0A8h),a

                ; --- el bloque comprimido, al bufer. Aqui NO se toca la pila:
                ; en el tramo del cruce de banco el cartucho esta en la pagina
                ; 1, donde vive, y un push o un ret leerian la ROM.
F_COPIA:
                ld a,(hl)
                ld (de),a
                inc hl
                inc de
                dec bc
                ld a,b
                or c
                jr z,F_COPIADO
                bit 6,h                 ; la ventana es 0x8000-0xBFFF: al pasar, H=0xC0
                jr z,F_COPIA
                ; cruzar de banco. El byte ya esta copiado, asi que A se puede
                ; gastar: no hace falta salvarlo en ninguna parte.
                ld a,(F_A8_CART12)
                out (0A8h),a            ; cartucho en la pagina 1
                ld a,(F_BANCO)
                inc a
                ld (F_BANCO),a
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_CART2)
                out (0A8h),a            ; y la RAM de vuelta
                ld h,080h
                jr F_COPIA

F_COPIADO:
                ; --- las paginas como estaban y el banco de la musica otra vez
                ; en la ventana de 0x8000, que es lo que el puente espera
                ; encontrar. Aqui ya no deberia llamarse: la musica se paro al
                ; empezar la partida. Cuesta once bytes y quita un modo de fallo.
                ld a,(F_A8_CART12)
                out (0A8h),a
                ld a,BANCO_VUELVE
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_RAM)
                out (0A8h),a

                ; --- y ahora si: ZX0, con las cuatro paginas en RAM, en el
                ; sitio: lee el comprimido de donde se acaba de dejar y va
                ; escribiendo desde 0x4000 sin alcanzarlo nunca.
                ld hl,(F_DST)
                ld de,DESTINO
                call dzx0_standard
                ei
                ret

F_A8_RAM:       defb 0                  ; 0xA8 tal y como lo dejo el juego
F_A8_CART2:     defb 0                  ; ... con la ROM en la pagina 2
F_A8_CART12:    defb 0                  ; ... y en la 1 tambien, para el registro
F_BANCO:        defb 0                  ; el banco que se esta leyendo
F_DST:          defw 0                  ; donde se deja el comprimido: al final de la pantalla

                include "dzx0.asm"

FINALES_FIN:
