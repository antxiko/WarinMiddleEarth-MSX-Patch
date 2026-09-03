; ==========================================================================
; War in Middle Earth (MSX) - PARCHE de Araubi
; Segunda tanda: EL OJO DE SAURON para las unidades enemigas, y el PLAZO que
; queda antes de sucumbir, al lado del Anillo.
;
; Vive en 0x664C, justo detras de la rutina de los valores (0x6600-0x664B),
; dentro de la misma zona muerta: el motor del altavoz del ZX Spectrum, que en
; esta conversion no lo llama nadie.
;
; --------------------------------------------------------------------------
; 1) EL OJO DE SAURON
;
; El juego decide el dibujo de una casilla mirando SOLO el byte del mapa
; (0xCC00 + (x+1)*102 + (y+1); el mapa va por columnas de 0x66):
;
;     PINTA_LA_UNIDAD (0x7708):  bit 7 = "aqui hay alguien"
;                                bit 6 = casilla con una orden en marcha -> 0x11
;                                si no                                   -> 0x15
;
; O sea que al dibujar no sabe de que bando es la unidad. El bit 5 del byte de
; mapa esta LIBRE (medido: cero usos en las 13.260 casillas), asi que:
;
;   - SIEMBRA_CON_BANDO le pone el bit 5 a la casilla si la unidad es del
;     enemigo (indice 0x78 o mayor), ademas del bit 7 de siempre;
;   - DIBUJO_SEGUN_BANDO mira ese bit 5 antes que nada y estampa cuatro tiles
;     nuevos del final de la tabla de 0x9E00 (los 111 a 114, que estaban a cero).
;
; OJO CON LA TABLA DE CUADROS DE 0x77B5: sus huecos a cero NO estan libres. Los
; indices 0x00-0x0F los elige PINTA_LO_DE_ENCIMA (0x7714) con un `and 00fh`
; sobre el nibble bajo del terreno, asi que meter el dibujo en el hueco 0x03
; se lo pone a las 447 casillas de terreno tipo 3. Probado, y se ve. Por eso
; aqui no se usa un indice: se pone HL a una lista propia de cuatro codigos y
; se entra en ESTAMPA_DOS_POR_DOS pasada su aritmetica, en 0x7720.
;
; --------------------------------------------------------------------------
; 2) EL PLAZO DEL ANILLO
;
; El reloj del juego (0x831B) cuenta tics, dias y meses. Cada mes:
;
;     8332  ld a,000h      ; el operando de 0x8333 es la CUENTA ATRAS de meses
;     8334  dec a          ; 0x7F4F la deja en 255 al empezar la partida
;     8335  ld (08333h),a
;     8338  jp z,DERROTA   ; a cero, la pantalla de Sauron
;
; y el mensaje de ese mes es "El Anillo corrompe al que lo usa.". Ese operando
; es, literalmente, lo que queda antes de sucumbir.
;
; MARCA_AL_PORTADOR (0x6F6E) pinta el anillo -el caracter 0x5F- en 0x7C46, la
; ultima columna de la segunda fila de la ficha. ANILLO_CON_PLAZO hace lo mismo
; y ademas escribe el numero en 0x7C43, las tres columnas de su izquierda.
;
; Y GUARDA LOS REGISTROS. Lo que sigue en la ficha es `call DESCRIBE_EL_DESTINO`
; (0x6F7C), que se aprovecha del HL que venia de antes -0x7C27, donde lo dejo el
; ESCRIBE_A_EN_TRES_CIFRAS de 0x6F6B-. Llamar a esa misma rutina aqui sin
; guardar HL deja la ficha escrita en otro sitio: sale con los nombres de media
; Comunidad encima. Probado, y se ve.
; ==========================================================================

CELDA    equ 08108h        ; CELDA_DEL_MAPA: H=Y, L=X -> HL dentro de 0xCC00
ESTAMPA  equ 07717h        ; ESTAMPA_DOS_POR_DOS: A = indice en la tabla 0x77B5
ESTAMPAHL equ 07720h       ; ... y por aqui, con HL ya en los cuatro codigos
CIFRAS   equ 07113h        ; ESCRIBE_A_EN_TRES_CIFRAS: A=valor, HL=destino
PLAZO    equ 08333h        ; operando: meses que quedan (255 al empezar)
RING     equ 07C46h        ; ultima columna de la 2a fila de la ficha
RINGNUM  equ 07C43h        ; y las tres columnas de su izquierda

CUADRO_ORDEN     equ 011h  ; el que ya usaba el juego para "orden en marcha"
CUADRO_UNIDAD    equ 015h  ; y el de siempre para una unidad

         org 0664Ch

; --------------------------------------------------------------------------
; Siembra la casilla de la unidad C, marcando de que bando es.
; Sustituye al `call CELDA_DEL_MAPA` + `set 7,(hl)` de 0x7FC9.
; Entra: H = Y, L = X (como los dejo el bucle), C = numero de unidad.
; --------------------------------------------------------------------------
SIEMBRA_CON_BANDO:
         call CELDA        ; HL a la casilla del mapa
         set  7,(hl)       ; "aqui hay alguien", como siempre
         ld   a,c
         cp   078h         ; de la 0 a la 0x77 son las tuyas
         ret  c
         set  5,(hl)       ; de la 0x78 arriba, el enemigo
         ret

; --------------------------------------------------------------------------
; Elige el cuadro de 2x2 segun el byte de mapa que llega en A.
; Sustituye al cuerpo de PINTA_LA_UNIDAD desde 0x770A (el bit 7 ya lo miro
; ella misma con `or a` / `ret p`).
; --------------------------------------------------------------------------
DIBUJO_SEGUN_BANDO:
         bit  5,a                  ; el bit que siembra SIEMBRA_CON_BANDO
         jr   z,NO_ES_ENEMIGA
         ld   hl,CUADRO_OJO        ; los cuatro tiles del Ojo de Sauron
         jp   ESTAMPAHL
NO_ES_ENEMIGA:
         bit  6,a                  ; casilla con una orden en marcha
         ld   a,CUADRO_ORDEN       ; `ld a,n` no toca las banderas
         jp   nz,ESTAMPA
         ld   a,CUADRO_UNIDAD
         jp   ESTAMPA

; --------------------------------------------------------------------------
; El anillo del portador y, a su izquierda, los meses que le quedan.
; Sustituye al `ld a,05fh` + `ld (0x7C46),a` de 0x6F77.
; --------------------------------------------------------------------------
ANILLO_CON_PLAZO:
         ld   a,05Fh       ; el caracter del anillo, como hacia el juego
         ld   (RING),a
         push bc           ; CIFRAS usa C, y HL se lo lleva tres bytes mas alla
         push de
         push hl
         ld   a,(PLAZO)    ; los meses que quedan antes de sucumbir
         ld   hl,RINGNUM
         call CIFRAS       ; las tres cifras, pegadas al anillo
         pop  hl
         pop  de
         pop  bc
         ld   a,05Fh       ; y A como lo dejaba el juego
         ret

; --------------------------------------------------------------------------
; El cuadro del Ojo de Sauron: cuatro codigos con el bit 7 puesto, que es lo
; que le dice a UN_CARACTER (0x75B3) que son tiles de nueve bytes de 0x9E00.
; 0xEF..0xF2 = tiles 111 a 114, los cuatro primeros que estaban a cero.
; --------------------------------------------------------------------------
CUADRO_OJO:
         defb 0EFh, 0F0h          ; arriba-izquierda, arriba-derecha
         defb 0F1h, 0F2h          ; abajo-izquierda, abajo-derecha

         end
