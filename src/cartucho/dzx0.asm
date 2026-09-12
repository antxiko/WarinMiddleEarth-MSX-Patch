; ==========================================================================
; ZX0: EL DESCOMPRESOR, 68 BYTES
;
; ZX0 decoder by Einar Saukas & Urusergi, "Standard" version.
;   https://github.com/einar-saukas/ZX0
;
; Este cartucho usa ZX0. Su licencia lo pide y esta dicho tambien en el
; README y en AVISO-LEGAL.md: "The decompressors can be used freely within
; your own programs (either for the ZX Spectrum or any other platform), even
; for commercial releases. The only condition is that you must indicate
; somehow in your documentation that you have used ZX0."
;
; Lo unico que se ha tocado es la SINTAXIS: viene de
; MSXgl/engine/src/compress/zx0.c, que lo lleva en ensamblador de SDCC
; (`#0x80`), y aqui esta en la de pasmo (`080h`). Los nombres de las
; etiquetas se dejan como en el original, en minuscula y con el prefijo
; `dzx0s_`, para que se pueda cotejar linea a linea con la fuente. El resto
; del cartucho usa MAYUSCULAS; la diferencia es a proposito y marca lo que no
; es nuestro.
;
; POR QUE ZX0 Y NO EL RLE DE MARCA
;
;   intro patrones   6.144 -> 5.236 con RLE -> 3.663 con ZX0
;   intro colores    6.144 -> 2.511         -> 1.030
;   victoria         6.912 -> 5.519         -> 3.847
;   derrota          6.912 -> 5.763         -> 4.060
;
; 6.429 bytes de ROM, a cambio de 68 de descompresor.
;
; LO QUE HAY QUE SABER PARA USARLO
;
; 1. **El destino tiene que ser RAM**, y legible: ZX0 es LZ, o sea que la
;    mayor parte de lo que escribe son copias de LO QUE YA ESCRIBIO (el
;    `add hl,de` de abajo calcula destino-offset y copia de ahi). Contra la
;    VRAM no se puede, que es lo que si permitia el RLE de marca. De ahi el
;    bufer en RAM.
; 2. **Usa la pila a fondo**: guarda el ultimo offset con `push bc` y lo saca
;    y mete con `ex (sp),hl`. Asi que NO puede correr con la pagina de la pila
;    conmutada al cartucho. Por eso, en las pantallas finales, el bloque
;    comprimido se trae primero a RAM y solo despues se llama aqui.
; 3. **El origen se lee de corrido**: no sabe cruzar de banco. Se le da
;    siempre un bloque que ya esta entero en RAM.
;
; Entra con HL = origen (comprimido) y DE = destino. Sale con el destino
; escrito. Se lleva por delante A, BC, DE y HL.
; ==========================================================================

dzx0_standard:
                ld      bc,0FFFFh       ; el offset por defecto es 1
                push    bc
                inc     bc
                ld      a,080h          ; el deposito de bits
dzx0s_literals:
                call    dzx0s_elias     ; cuantos literales
                ldir                    ; y se copian tal cual
                add     a,a             ; ¿del ultimo offset o de uno nuevo?
                jr      c,dzx0s_new_offset
                call    dzx0s_elias     ; cuantos bytes se copian
dzx0s_copy:
                ex      (sp),hl         ; guarda el origen, recupera el offset
                push    hl              ; y lo conserva
                add     hl,de           ; destino - offset
                ldir                    ; copia de lo ya escrito
                pop     hl              ; el offset
                ex      (sp),hl         ; lo guarda y recupera el origen
                add     a,a             ; ¿literales o un offset nuevo?
                jr      nc,dzx0s_literals
dzx0s_new_offset:
                pop     bc              ; fuera el offset viejo
                ld      c,0FEh          ; se prepara en negativo
                call    dzx0s_elias_loop ; el byte alto del offset
                inc     c
                ret     z               ; la marca de fin
                ld      b,c
                ld      c,(hl)          ; y el byte bajo
                inc     hl
                rr      b               ; el ultimo bit del offset es el
                rr      c               ; primero de la longitud
                push    bc              ; el offset nuevo, a la pila
                ld      bc,1            ; la longitud
                call    nc,dzx0s_elias_backtrack
                inc     bc
                jr      dzx0s_copy

; Elias gamma entrelazado: los bits de la longitud van intercalados con los
; que dicen si queda mas longitud.
dzx0s_elias:
                inc     c
dzx0s_elias_loop:
                add     a,a
                jr      nz,dzx0s_elias_skip
                ld      a,(hl)          ; se acabaron los ocho bits: otros ocho
                inc     hl
                rla
dzx0s_elias_skip:
                ret     c
dzx0s_elias_backtrack:
                add     a,a
                rl      c
                rl      b
                jr      dzx0s_elias_loop
dzx0_fin:
