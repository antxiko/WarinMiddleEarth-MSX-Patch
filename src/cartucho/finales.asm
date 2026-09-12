; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LAS DOS PANTALLAS FINALES,
; DESCOMPRIMIDAS DE LA ROM CUANDO EL JUEGO LAS PIDE
;
; QUE PROBLEMA RESUELVE
;
; Las dos pantallas del final -la victoria en 0x094F y la derrota en 0x244F,
; 6.912 bytes cada una- ocupan 13.824 bytes de RAM desde que arranca el
; cartucho hasta que acaba la partida, y se usan UNA VEZ, en los ultimos
; segundos. Estaban ahi por herencia: la cinta las cargaba asi y el cartucho
; se limitaba a reproducir lo que dejaba la cinta.
;
; Con esta rutina se quedan solo en la ROM, comprimidas, y se descomprimen
; directamente a 0x4000 -que es a donde el juego las copiaba- en el momento de
; pintarlas. La RAM libre pasa de 1.922 a ~15.600 bytes.
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
; POR QUE VIVE EN LA PAGINA 0
;
; Detras del puente de la musica quedan bytes libres hasta el buzon de POKEs
; de 0x012C, y esta es la unica pagina que sirve: la 1 hay que conmutarla al
; cartucho a mitad (el registro del mapper vive en 0x7000) y la 2 tambien
; (por ahi se asoma la ROM), y del stub de 0xD800 no hay que fiarse, que en
; tiempo de juego puede estar pisado.
;
; LAS DOS CONMUTACIONES, Y POR QUE ESTE ORDEN
;
; El registro que manda en la ventana de 0x8000 -por donde se lee el bloque
; comprimido- vive en 0x7000, o sea en la PAGINA 1, que en tiempo de juego es
; RAM. Asi que para elegir banco hay que poner un momento el cartucho ahi,
; escribir el registro y devolver la RAM. En ese tramo NO SE TOCA LA PILA: la
; del juego esta en 0x5BFF, pagina 1, y cualquier push, pop, call o ret
; mientras el cartucho esta puesto escribiria o leeria la ROM. Por eso las
; conmutaciones van con instrucciones sueltas y el `push af` de F_LEE queda
; fuera, antes de la primera y despues de la ultima.
;
; Y por eso mismo esto corre con `di`: durante la descompresion la pagina 2 es
; la ROM, y la interrupcion del juego (0x0400) usa datos que viven ahi. Se
; devuelve con `ei`, que es como llego.
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
                ld c,F0_MARCA
                jr F_ELEGIDA
F_DERROTA:
                ld a,F1_BANCO
                ld hl,F1_SRC
                ld c,F1_MARCA
F_ELEGIDA:
                ld (F_BANCO),a
                ld a,c
                ld (F_ES_MARCA+1),a     ; la marca, dentro del `cp` de abajo
                ld de,DESTINO

                ; --- el banco a la ventana de 0x8000 (cartucho un momento en
                ; la pagina 1) y la ROM asomada en la pagina 2
                ld a,(F_A8_CART12)
                out (0A8h),a
                ld a,(F_BANCO)
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_CART2)
                out (0A8h),a

                ; --- el RLE de marca de tools/comprime.py:
                ;   <b>             si b no es la marca, un byte literal
                ;   marca <n> <v>   n veces el byte v   (1 <= n <= 255)
                ;   marca 0         se acabo
F_BUCLE:
                call F_LEE
F_ES_MARCA:
                cp 000h
                jr z,F_RACHA
                ld (de),a
                inc de
                jr F_BUCLE
F_RACHA:
                call F_LEE
                or a
                jr z,F_FIN
                ld b,a                  ; cuantas veces
                call F_LEE              ; y que byte
F_REPITE:
                ld (de),a
                inc de
                djnz F_REPITE
                jr F_BUCLE

F_FIN:
                ; La ventana de 0x8000 se devuelve al banco que tenia -el de la
                ; musica-, que es lo que espera el puente si alguna vez volviera
                ; a llamarse. Aqui ya no deberia: la musica se paro al empezar
                ; la partida. Cuesta once bytes y quita un modo de fallo.
                ld a,(F_A8_CART12)
                out (0A8h),a
                ld a,BANCO_VUELVE
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_RAM)
                out (0A8h),a
                ei
                ret

; --------------------------------------------------------------------------
; Un byte del flujo, cruzando de banco solo cuando el puntero se sale de la
; ventana. La ventana es 0x8000-0xBFFF: pasarse se ve en el bit 6 de H, que
; esta a cero en todo 0x80-0xBF y a uno en 0xC0.
;
; Cruzar solo es lo que permite que los bloques se coloquen en la ROM sin
; cuidar de que no caigan a caballo de dos bancos -la victoria cae asi hoy-.
; --------------------------------------------------------------------------
F_LEE:
                ld a,(hl)
                inc hl
                bit 6,h
                ret z
                push af                 ; el byte leido, a salvo ANTES de conmutar
                ld a,(F_A8_CART12)
                out (0A8h),a            ; cartucho en la pagina 1: la pila NO se toca
                ld a,(F_BANCO)
                inc a
                ld (F_BANCO),a
                ld (BANCO_VENTANA_2),a
                ld a,(F_A8_CART2)
                out (0A8h),a            ; y la RAM de vuelta
                ld h,080h
                pop af
                ret

F_A8_RAM:       defb 0                  ; 0xA8 tal y como lo dejo el juego
F_A8_CART2:     defb 0                  ; ... con la ROM en la pagina 2
F_A8_CART12:    defb 0                  ; ... y en la 1 tambien, para el registro
F_BANCO:        defb 0                  ; el banco que se esta leyendo

FINALES_FIN:
