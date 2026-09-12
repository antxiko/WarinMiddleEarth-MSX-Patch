; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LAS DOS PANTALLAS FINALES,
; DESCOMPRIMIDAS DE LA ROM CUANDO EL JUEGO LAS PIDE
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
; Asi que primero se COPIA el bloque comprimido a un bufer en RAM -ahi si se
; cruza de banco, con un bucle que no toca la pila- y despues se llama a ZX0
; con las cuatro paginas en RAM, sin cartucho a la vista.
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

DESTINO         equ 04000h      ; donde el juego copiaba la pantalla y donde la lee 0x05BD

FINALES:
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

                ; --- cual de las dos piden. HL trae la direccion a la que el
                ; juego iba a ir a buscarla.
                ld a,h
                cp F1_DIR / 256
                jr nc,F_DERROTA
                ld a,F0_BANCO
                ld hl,F0_SRC
                ld bc,F0_TAM
                jr F_ELEGIDA
F_DERROTA:
                ld a,F1_BANCO
                ld hl,F1_SRC
                ld bc,F1_TAM
F_ELEGIDA:
                ld (F_BANCO),a
                ld de,BUFER_ZX0

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

                ; --- y ahora si: ZX0, con las cuatro paginas en RAM
                ld hl,BUFER_ZX0
                ld de,DESTINO
                call dzx0_standard
                ei
                ret

F_A8_RAM:       defb 0                  ; 0xA8 tal y como lo dejo el juego
F_A8_CART2:     defb 0                  ; ... con la ROM en la pagina 2
F_A8_CART12:    defb 0                  ; ... y en la 1 tambien, para el registro
F_BANCO:        defb 0                  ; el banco que se esta leyendo

                include "dzx0.asm"

FINALES_FIN:
