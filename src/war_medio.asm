; ==========================================================================
; WAR IN MIDDLE EARTH - MSX - bloque medio (0x5E00): el juego
; ==========================================================================
; Generado por tools/mkasm.py a partir del trazado de flujo real.
; Los comentarios provienen de tools/../src/*.notes y estan anclados a
; direccion, de modo que sobreviven a un retrazado.
; ==========================================================================

	org 0x05e00


; ----------------------------------------------------------------------
; Direcciones que solo aparecen como VALOR -en un `ld`, no en
; un salto-: son punteros que el codigo se pasa o numeros que
; casualmente coinciden con una direccion. No hay nada que
; trazar en ellas; el equ existe para que el listado ensamble.
; ----------------------------------------------------------------------
l5fb7h:	equ 0x05fb7

; ======================================================================
; CODIGO 0x5e00..0x5fb8  (440 bytes)
; ======================================================================



; ----------------------------------------------------------------------
; Puerta del bloque medio: aqui salta 0x01C2 en cuanto el bloque bajo
; ----------------------------------------------------------------------
ARRANQUE_DEL_MEDIO:		; Interrupcion, tabla de color de 0x0200 y menu
	di			;5e00
	ld sp,05bffh		;5e01   ; La pila justo debajo de la pantalla emulada del Spectrum (0x4000-0x5AFF)
	ld a,0c3h		;5e04   ; 0xC3 es el opcode de jp: el vector del modo 1 se arma a mano
	ld (00038h),a		;5e06
	ld hl,00400h		;5e09   ; 0x0038 queda como "jp 0x0400", la INTERRUPCION del bloque bajo
	ld (00039h),hl		;5e0c
	ld hl,00428h		;5e0f   ; 0x0415 es el gancho por fotograma; arranca en el ret de 0x0428 (GANCHO_VACIO)
	ld (00415h),hl		;5e12
	ld hl,00200h		;5e15   ; 0x0200-0x02FF: la tabla que 0x0614 y 0x07A3 usan para traducir atributos
	xor a			;5e18
	ld b,a			;5e19   ; B = 0 son 256 vueltas: un byte por cada atributo posible
TRADUCE_LOS_256_ATRIBUTOS:		; Deja en 0x0200+n el color MSX del atributo ZX n
	push af			;5e1a
	call 0049fh		;5e1b   ; 0x049F (ATRIBUTO_A_COLOR) hace la traduccion una sola vez por atributo
	ld (hl),a			;5e1e
	inc hl			;5e1f
	pop af			;5e20
	inc a			;5e21
	djnz TRADUCE_LOS_256_ATRIBUTOS		;5e22   ; Doscientas cincuenta y seis vueltas, de 0 a 255
	ld hl,07f43h		;5e24   ; 0x7F43 se queda en la pila: es a donde salta el ret de 0x5EA0, el juego
	push hl			;5e27
	call DESCOMPRIME_EL_MAPA		;5e28   ; 0x9366 vuelca 0x16ED bytes desde 0xCC00 a la pantalla y desempaqueta
MENU_PINTA_LA_PORTADA:		; Pinta el cartel del menu y cae en la lista de opciones
	ld hl,0610eh		;5e2b   ; 0x610E: el marco con "War In Middle Earth" y las seis opciones
	call ESCRIBE_TEXTO		;5e2e
MENU_ESPERA_OPCION:		; Escribe el rotulo del control elegido y espera una tecla
	ld a,(096f0h)		;5e31   ; 0x96F0 es el modo de control: 0 joystick, 1 cursores, 3 teclado definido
	add a,a			;5e34
	add a,0f0h		;5e35   ; HL = 0x5FF0 + modo*2, con el acarreo propagado a mano
	ld l,a			;5e37
	adc a,05fh		;5e38
	sub l			;5e3a
	ld h,a			;5e3b
	ld e,(hl)			;5e3c   ; De la tabla sale el puntero a uno de los cuatro rotulos de 0x600F
	inc hl			;5e3d
	ld d,(hl)			;5e3e
	ld hl,04865h		;5e3f   ; 0x4865: fila 11, columna 5 de la pantalla del Spectrum
	ex de,hl			;5e42
	call ESCRIBE_TEXTO		;5e43
	call PINTA_LAS_CINCO_TECLAS		;5e46   ; 0x5F33 refresca la fila con los nombres de las cinco teclas
	call 005b7h		;5e49   ; 0x05B7 (ESPERA_TECLA) no vuelve hasta que hay una tecla con nombre
	cp 031h		;5e4c   ; Tecla 1: joystick
	jr nz,MENU_TECLA_2		;5e4e
	xor a			;5e50
	jr MENU_GUARDA_EL_MODO		;5e51
MENU_TECLA_2:		; Tecla 2: los cursores
	cp 032h		;5e53
	jr nz,MENU_TECLA_3		;5e55
	ld a,001h		;5e57   ; Modo 1: la tabla de mandos de 0x06D5 le da las cuatro flechas
	jr MENU_GUARDA_EL_MODO		;5e59
MENU_TECLA_3:		; Tecla 3: el teclado definido, que es el modo 3, no el 2
	cp 033h		;5e5b
	jr nz,MENU_TECLA_5_O_6		;5e5d
	ld a,003h		;5e5f   ; El modo 2 (Interface Two) no lo ofrece el menu: su puntero en 0x06D7 es 0x0000
MENU_GUARDA_EL_MODO:		; Escribe el modo de control y vuelve a pintar
	ld (096f0h),a		;5e61
	jr MENU_ESPERA_OPCION		;5e64
MENU_TECLA_5_O_6:		; Tecla 5: definir teclas. Tecla 6: nivel
	cp 035h		;5e66
	jp z,DEFINIR_LAS_CINCO_TECLAS		;5e68
	cp 036h		;5e6b
	jr nz,MENU_TECLA_0		;5e6d
	ld a,001h		;5e6f   ; El operando de 0x5E70 es el NIVEL: este ld a,nn se lee a si mismo
MENU_SIGUIENTE_NIVEL:		; El nivel da la vuelta de 15 a 1 y se repinta en el rotulo
	inc a			;5e71
	and 00fh		;5e72   ; Solo el nibble bajo: 15 vuelve a 1, el cero se salta
	jr z,MENU_SIGUIENTE_NIVEL		;5e74
	ld (05e70h),a		;5e76   ; El nivel se guarda dentro del propio ld a,nn de 0x5E6F
	ld hl,061cah		;5e79   ; 0x61CA son los tres digitos de "6. Nivel 001", en el texto del menu
	call ESCRIBE_A_EN_TRES_CIFRAS		;5e7c   ; 0x7113 escribe A en decimal, tres cifras, donde apunta HL
	jp MENU_PINTA_LA_PORTADA		;5e7f
MENU_TECLA_0:		; Tecla 0: reparte el nivel elegido y arranca la partida
	cp 030h		;5e82
	jr nz,MENU_ESPERA_OPCION		;5e84
	ld a,(05e70h)		;5e86   ; El nivel que dejo 0x5E71 en su operando
	ld c,a			;5e89
	ld hl,0bd00h		;5e8a
REPARTE_EL_NIVEL:		; A las unidades de tipo 5 les mete el nivel en 0xC100
	ld a,(hl)			;5e8d
	and 00fh		;5e8e   ; Nibble bajo de 0xBD00+n: el tipo de unidad
	cp 005h		;5e90   ; Solo las de tipo 5, que segun la lista de razas de 0x7D06 son los Orcos
	jr nz,REPARTE_SIGUIENTE		;5e92
	ld h,0c1h		;5e94   ; Misma unidad, otro array: 0xC100+n
	ld a,(hl)			;5e96
	and 0f0h		;5e97
	or c			;5e99
	ld (hl),a			;5e9a   ; Nibble alto intacto, nibble bajo = el nivel
	ld h,0bdh		;5e9b
REPARTE_SIGUIENTE:		; Las 256 unidades, de la 0 a la 255
	inc l			;5e9d
	jr nz,REPARTE_EL_NIVEL		;5e9e
	ret			;5ea0   ; Este ret NO vuelve al que llamo: salta a 0x7F43 por el push de 0x5E24
BORRA_LA_FILA_DE_TECLAS:		; Deja a espacios los 30 caracteres de 0x60CD
	ld hl,060cdh		;5ea1   ; 0x60CD: la fila de debajo de "-ARRI- ABAJ- IZDA- DCHA-FUEGO-"
	ld b,01eh		;5ea4   ; Treinta columnas, las mismas que ocupan los cinco rotulos
L_5EA6:
	ld (hl),020h		;5ea6
	inc hl			;5ea8
	djnz L_5EA6		;5ea9
	ret			;5eab
BUSCA_NOMBRE_DE_TECLA_C:		; Deja en DE el nombre de la tecla numero C de la matriz del ZX
	ld de,l5fb7h		;5eac   ; Empieza uno antes de 0x5FB8 porque la cuenta arranca con el inc de
SIGUIENTE_NOMBRE:		; Una tecla menos; al llegar a cero, DE senala su nombre
	inc de			;5eaf
	dec c			;5eb0
	ret z			;5eb1
SALTA_LAS_LETRAS_ENLAZADAS:		; Los nombres largos llevan el bit 7 en todas sus letras menos la ultima
	ld a,(de)			;5eb2
	or a			;5eb3
	jp p,SIGUIENTE_NOMBRE		;5eb4   ; Bit 7 a cero: ultima letra del nombre, la entrada se acaba aqui
	inc de			;5eb7   ; "SYM", "SPC", "ENT" y "CAP" ocupan tres bytes; las otras 36 teclas uno
	jr SALTA_LAS_LETRAS_ENLAZADAS		;5eb8
DEFINIR_LAS_CINCO_TECLAS:		; Pide arriba, abajo, izquierda, derecha y fuego, y las guarda en 0x06E5
	ld a,002h		;5eba   ; El 2 va al operando de 0x5EDA: las dos primeras teclas de 0x6008 (1 y R) son fijas
	ld (05edbh),a		;5ebc
	ld bc,060ceh		;5ebf   ; 0x60CE es la primera de las cinco casillas de seis columnas de la fila
	ld (05f10h),bc		;5ec2
	call BORRA_LA_FILA_DE_TECLAS		;5ec6   ; Antes de nada, la fila de nombres a espacios
	ld hl,06067h		;5ec9
	call ESCRIBE_TEXTO		;5ecc   ; 0x6067: el marco con "Las Teclas Actuales Son:"
	ld hl,006e5h		;5ecf   ; 0x06E5 es la tabla de parejas fila/mascara que lee 0x06B2 en el modo 3
PIDE_UNA_TECLA:		; Espera a que se suelte todo y coge la siguiente tecla
	push hl			;5ed2
	call 00667h		;5ed3   ; 0x0667 (ESPERA_SIN_TECLAS) evita que una tecla cuente dos veces
	call 005b7h		;5ed6   ; 0x05B7 devuelve A = codigo, D = fila de la matriz, E = mascara del bit
	pop hl			;5ed9
	ld b,000h		;5eda   ; El operando de 0x5EDB va de 2 a 6: cuantas teclas hay ya cogidas
	ld ix,06008h		;5edc   ; 0x6008: la lista de teclas ya elegidas, empezando por 1 y R
GUARDA_LA_TECLA:		; Si la tecla ya estaba cogida vuelve a pedir; si no, apunta fila y mascara
	cp (ix+000h)		;5ee0   ; Comparar con las que ya hay evita repetir tecla
	jr z,PIDE_UNA_TECLA		;5ee3
	inc ix		;5ee5
	djnz GUARDA_LA_TECLA		;5ee7
	ld (hl),d			;5ee9   ; En 0x06E5 van la fila (D) y la mascara (E), en ese orden
	inc hl			;5eea
	ld (hl),e			;5eeb
	inc hl			;5eec
	push hl			;5eed
	ld (ix+000h),a		;5eee   ; Y el codigo de la tecla se anade a la lista de 0x6008
	call PINTA_LA_TECLA_ELEGIDA		;5ef1   ; 0x5F0B pinta el nombre de la tecla recien elegida
	pop hl			;5ef4
	ld ix,05edbh		;5ef5   ; 0x5EDB es el contador, dentro del ld b,nn de 0x5EDA
	inc (ix+000h)		;5ef9
	ld a,(ix+000h)		;5efc
	cp 007h		;5eff   ; Cinco teclas: la cuenta acaba al llegar a 7
	jr nz,PIDE_UNA_TECLA		;5f01
	call 00667h		;5f03
	ld a,003h		;5f06   ; Definir teclas deja elegido el modo 3
	jp MENU_GUARDA_EL_MODO		;5f08
PINTA_LA_TECLA_ELEGIDA:		; Copia el nombre de la tecla a su casilla y repinta el marco
	ld c,a			;5f0b
	call 00627h		;5f0c   ; 0x0627 (NOMBRE_DE_TECLA) deja el nombre de tres letras en 0x0656
	ld bc,00000h		;5f0f   ; El destino esta en el operando de 0x5F10, que 0x5EBF puso en 0x60CE
	call 00659h		;5f12   ; 0x0659 copia las tres letras al texto del menu
	ld hl,(05f10h)		;5f15
	ld bc,00006h		;5f18
	add hl,bc			;5f1b   ; Seis columnas hasta la casilla siguiente
	ld (05f10h),hl		;5f1c
	ld hl,06067h		;5f1f   ; Repintar el marco entero es lo que hace que se vea el cambio
	jp ESCRIBE_TEXTO		;5f22
COPIA_NOMBRE_COLGADA:		; Copia un nombre quitando el bit 7, pero se cuelga en 0x5F2F. Nadie la llama
	ld a,(de)			;5f25
	or a			;5f26   ; Con el bit 7 puesto copia UNA letra y cae en el bucle sin salida
	jp p,L_5F31		;5f27
	and 07fh		;5f2a
	ld (bc),a			;5f2c
	inc de			;5f2d
	inc bc			;5f2e
L_5F2F:
	jr L_5F2F		;5f2f   ; jr a si mismo: aqui se queda para siempre
L_5F31:
	ld (bc),a			;5f31
	ret			;5f32
PINTA_LAS_CINCO_TECLAS:		; Escribe en el marco los nombres de las cinco teclas de 0x600A
	call BORRA_LA_FILA_DE_TECLAS		;5f33   ; Primero la fila a espacios
	ld hl,0600ah		;5f36   ; 0x600A: las cinco teclas de direccion y fuego, detras del 1 y la R
	ld c,(hl)			;5f39
	call 00627h		;5f3a   ; 0x0627 traduce el codigo a un nombre de tres letras
	ld bc,060ceh		;5f3d   ; Casilla 1 de la fila: ARRIBA
	call 00659h		;5f40
	inc hl			;5f43
	ld c,(hl)			;5f44
	call 00627h		;5f45
	ld bc,060d4h		;5f48   ; Casilla 2: ABAJO
	call 00659h		;5f4b
	inc hl			;5f4e
	ld c,(hl)			;5f4f
	call 00627h		;5f50
	ld bc,060dah		;5f53   ; Casilla 3: IZQUIERDA
	call 00659h		;5f56
	inc hl			;5f59
	ld c,(hl)			;5f5a
	call 00627h		;5f5b
	ld bc,060e0h		;5f5e   ; Casilla 4: DERECHA
	call 00659h		;5f61
	inc hl			;5f64
	ld c,(hl)			;5f65
	call 00627h		;5f66
	ld bc,060e6h		;5f69   ; Casilla 5: FUEGO
	call 00659h		;5f6c
	ld hl,06067h		;5f6f
	jp ESCRIBE_TEXTO		;5f72   ; Y a repintar el marco de 0x6067 con los cinco nombres dentro
ESPERA_SIN_TECLAS_ZX:		; Lee el puerto 0xFE del ZX; en el MSX ese puerto no contesta. Nadie la llama
	xor a			;5f75
	in a,(0feh)		;5f76   ; Puerto 0xFE: las cinco teclas de la primera media fila del Spectrum
	cpl			;5f78
	and 01fh		;5f79
L_5F7B:
	jr nz,L_5F7B		;5f7b   ; Si algun bit llegara a uno se colgaria aqui: A ya no cambia
	ret			;5f7d
CRONOMETRA_TECLA_ZX:		; Cuenta lo que se tarda en pulsar, leyendo el teclado del ZX. Nadie la llama
	push hl			;5f7e
	push bc			;5f7f
ESPERA_A_SOLTAR:		; 0x0667 hasta que D da la vuelta
	call 00667h		;5f80
	inc d			;5f83
	jr nz,ESPERA_A_SOLTAR		;5f84
ESPERA_A_PULSAR:		; Da vueltas a 0x5F98 hasta que hay tecla, contando en D
	call LEE_MATRIZ_ZX		;5f86
	jr nz,ESPERA_A_PULSAR		;5f89   ; Mientras 0x5F98 no encuentre tecla, otra vuelta
	inc d			;5f8b
	jr z,ESPERA_A_PULSAR		;5f8c
	push de			;5f8e
	xor a			;5f8f
	call SIN_SONIDO		;5f90   ; Efecto de sonido 0, o sea nada: 0x65FF es un ret
	pop de			;5f93
	ld a,d			;5f94
	pop bc			;5f95
	pop hl			;5f96
	ret			;5f97
LEE_MATRIZ_ZX:		; Recorre las ocho medias filas del teclado del Spectrum por el puerto 0xFE
	ld de,0ff2fh		;5f98   ; E = 0x2F: el numero de tecla va bajando de 47 hacia 0
	ld bc,0fefeh		;5f9b   ; 0xFEFE es la primera media fila del Spectrum (CAPS a V)
MEDIA_FILA_ZX:		; Cinco bits por media fila, invertidos
	in a,(c)		;5f9e
	cpl			;5fa0
	and 01fh		;5fa1   ; Solo los cinco bits bajos son teclas
	jr z,SIGUIENTE_MEDIA_FILA		;5fa3
	inc d			;5fa5
	ret nz			;5fa6   ; Con dos teclas a la vez se sale sin nada
	ld h,a			;5fa7
	ld a,e			;5fa8
CUENTA_LA_COLUMNA:		; Ocho por cada bit que hay que bajar hasta dar con el uno
	sub 008h		;5fa9
	srl h		;5fab
	jr nc,CUENTA_LA_COLUMNA		;5fad
	ret nz			;5faf
	ld d,a			;5fb0
SIGUIENTE_MEDIA_FILA:		; Rota el bit de fila; el acarreo dice que quedan filas
	dec e			;5fb1
	rlc b		;5fb2
	jr c,MEDIA_FILA_ZX		;5fb4
	cp a			;5fb6   ; cp a pone el cero: no habia ninguna tecla
L_5FB7:
	ret			;5fb7

; ----------------------------------------------------------------------
; DATOS nombres_de_tecla_spectrum: Nombres de tecla en el orden de la matriz
;   del Spectrum, con codigos >=0x80 para las teclas especiales (ld de,0x5FB7
;   en 0x5EAC, que empieza con inc de; ld hl,0x5FBD en 0x708A)
;   0x5fb8..0x5ff0  (56 bytes)
DATA_nombres_de_tecla_spectrum:
	defb 042h,048h,059h,036h,035h,054h,047h,056h,04eh,04ah,055h,037h,034h,052h,046h,043h	; 5fb8  BHY65TGVNJU74RFC
	defb 04dh,04bh,049h,038h,033h,045h,044h,058h,0d3h,0d9h,04dh,04ch,04fh,039h,032h,057h	; 5fc8  MKI83EDX..MLO92W
	defb 053h,05ah,0d3h,0d0h,043h,0c5h,0ceh,054h,050h,030h,031h,051h,041h,0c3h,0c1h,050h	; 5fd8  SZ..C..TP01QA..P
	defb 0f8h,05fh,0fah,05fh,001h,060h,008h,060h	; 5fe8  ._._.`.`

; ----------------------------------------------------------------------
; DATOS punteros_de_control_actual: Punteros a los cuatro rotulos de "Control
;   Actual" (0x5E31 indexa con (0x96F0)*2)
;   0x5ff0..0x5ff8  (8 bytes)
DATA_punteros_de_control_actual:
	defw 0600fh	; 5ff0  -> DATA_textos_del_menu
	defw 06025h	; 5ff2
	defw 0603bh	; 5ff4
	defw 06051h	; 5ff6

; ----------------------------------------------------------------------
; DATOS tabla_de_teclas_definidas: Tabla de la lectura de teclas definidas (ld
;   hl,0x600A en 0x5F36)
;   0x5ff8..0x6008  (16 bytes)
DATA_tabla_de_teclas_definidas:
	defb 031h,052h,031h,052h,018h,015h,016h,017h,011h,00eh,025h,01ch,014h,004h,00ch,024h	; 5ff8  1R1R......%....$

; ----------------------------------------------------------------------
; DATOS teclas_definidas: Las cinco teclas definidas: "1RQAOP" y un byte (ld
;   ix,0x6008 en 0x5EDC; ld hl,0x6010 en 0x9144)
;   0x6008..0x600f  (7 bytes)
DATA_teclas_definidas:
	defb 031h,052h,051h,041h,04fh,050h,011h	; 6008

; ----------------------------------------------------------------------
; DATOS textos_del_menu: Textos del menu: rotulos de control, "Las Teclas
;   Actuales Son", "War In Middle Earth / 1. Usa Joystick ... 0. Empieza
;   Juego", "Pausa/Abandona - 1 / Menu - R", creditos "Programado por
;   C.J.Pink. Conversion por ANIMAGIC" y la frase en ingles
;   0x600f..0x62ff  (752 bytes)
DATA_textos_del_menu:
	defb 021h,020h,04ah,06fh,079h,073h,074h,069h,063h,06bh,020h,053h,074h,061h,06eh,064h	; 600f  ! Joystick Stand
	defb 061h,072h,064h,020h,021h,000h,021h,020h,054h,065h,063h,06ch,061h,073h,020h,044h	; 601f  ard !.! Teclas D
	defb 065h,06ch,020h,043h,075h,072h,073h,06fh,072h,020h,021h,000h,021h,020h,020h,020h	; 602f  el Cursor !.!   
	defb 049h,06eh,074h,065h,072h,066h,061h,063h,065h,020h,054h,077h,06fh,020h,020h,020h	; 603f  Interface Two   
	defb 021h,000h,021h,020h,054h,065h,063h,06ch,061h,064h,06fh,020h,044h,065h,066h,069h	; 604f  !.! Teclado Defi
	defb 06eh,069h,064h,06fh,020h,020h,021h,000h,0d0h,060h,023h,022h,022h,022h,022h,022h	; 605f  nido  !..`#"""""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 606f  """"""""""""""""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,023h,0b7h,021h,020h,020h,020h,04ch	; 607f  """""""""#.!   L
	defb 061h,073h,020h,054h,065h,063h,06ch,061h,073h,020h,041h,063h,074h,075h,061h,06ch	; 608f  as Teclas Actual
	defb 065h,073h,020h,053h,06fh,06eh,03ah,020h,020h,020h,021h,0b7h,021h,02dh,041h,052h	; 609f  es Son:   !.!-AR
	defb 052h,049h,02dh,020h,041h,042h,041h,04ah,02dh,020h,049h,05ah,044h,041h,02dh,020h	; 60af  RI- ABAJ- IZDA- 
	defb 044h,043h,048h,041h,02dh,046h,055h,045h,047h,04fh,02dh,021h,0b7h,021h,020h,020h	; 60bf  DCHA-FUEGO-!.!  
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 60cf                  
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,021h,0b7h,023h,022h	; 60df              !.#"
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 60ef  """"""""""""""""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,023h,000h,0c0h	; 60ff  """""""""""""#..
	defb 005h,023h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 610f  .#""""""""""""""
	defb 022h,022h,022h,022h,022h,023h,0b7h,021h,057h,061h,072h,020h,049h,06eh,020h,04dh	; 611f  """""#.!War In M
	defb 069h,064h,064h,06ch,065h,020h,045h,061h,072h,074h,068h,021h,0b7h,023h,022h,022h	; 612f  iddle Earth!.#""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 613f  """"""""""""""""
	defb 022h,023h,0b7h,021h,031h,02eh,020h,055h,073h,061h,020h,04ah,06fh,079h,073h,074h	; 614f  "#.!1. Usa Joyst
	defb 069h,063h,06bh,020h,020h,020h,020h,021h,0b7h,021h,032h,02eh,020h,055h,073h,061h	; 615f  ick    !.!2. Usa
	defb 020h,043h,075h,072h,073h,06fh,072h,065h,073h,020h,020h,020h,020h,021h,0b7h,021h	; 616f   Cursores    !.!
	defb 033h,02eh,020h,055h,073h,061h,020h,054h,065h,063h,06ch,061h,064h,06fh,020h,020h	; 617f  3. Usa Teclado  
	defb 020h,020h,020h,021h,0b7h,021h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 618f     !.!          
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,021h,0b7h,021h,035h,02eh,020h,044h	; 619f           !.!5. D
	defb 065h,066h,069h,06eh,065h,020h,054h,065h,063h,06ch,061h,073h,020h,020h,020h,021h	; 61af  efine Teclas   !
	defb 0b7h,021h,036h,02eh,020h,04eh,069h,076h,065h,06ch,020h,030h,030h,031h,020h,020h	; 61bf  .!6. Nivel 001  
	defb 020h,020h,020h,020h,020h,021h,0b7h,021h,030h,02eh,020h,045h,06dh,070h,069h,065h	; 61cf       !.!0. Empie
	defb 07ah,061h,020h,04ah,075h,065h,067h,06fh,020h,020h,020h,021h,0b7h,021h,020h,043h	; 61df  za Juego   !.! C
	defb 06fh,06eh,074h,072h,06fh,06ch,020h,041h,063h,074h,075h,061h,06ch,03ah,020h,020h	; 61ef  ontrol Actual:  
	defb 020h,021h,0b7h,0b7h,023h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 61ff   !..#"""""""""""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,023h,0b7h,021h,050h,061h,075h,073h,061h	; 620f  """"""""#.!Pausa
	defb 02fh,041h,062h,061h,06eh,064h,06fh,06eh,061h,02dh,020h,020h,031h,020h,021h,0b7h	; 621f  /Abandona-  1 !.
	defb 021h,04dh,065h,06eh,075h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,02dh	; 622f  !Menu          -
	defb 020h,020h,052h,020h,021h,0b7h,023h,022h,022h,022h,022h,022h,022h,022h,022h,022h	; 623f    R !.#"""""""""
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,023h,000h,050h,072h,06fh,067h	; 624f  """"""""""#.Prog
	defb 072h,061h,06dh,061h,064h,06fh,020h,070h,06fh,072h,020h,043h,02eh,04ah,02eh,050h	; 625f  ramado por C.J.P
	defb 069h,06eh,06bh,02eh,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 626f  ink.            
	defb 020h,020h,020h,020h,043h,06fh,06eh,076h,065h,072h,073h,069h,06fh,06eh,020h,070h	; 627f      Conversion p
	defb 06fh,072h,020h,041h,04eh,049h,04dh,041h,047h,049h,043h,020h,020h,020h,020h,020h	; 628f  or ANIMAGIC     
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,059h,06fh,075h,072h	; 629f              Your
	defb 020h,06fh,06eh,06ch,079h,020h,061h,073h,020h,067h,06fh,06fh,064h,020h,061h,073h	; 62af   only as good as
	defb 020h,074h,068h,065h,020h,06ch,061h,073h,074h,020h,067h,072h,065h,061h,074h,020h	; 62bf   the last great 
	defb 074h,068h,069h,06eh,067h,020h,079h,06fh,075h,020h,064h,069h,064h,02ch,020h,077h	; 62cf  thing you did, w
	defb 068h,065h,072h,065h,020h,068h,061h,076h,065h,020h,079h,06fh,075h,020h,062h,065h	; 62df  here have you be
	defb 065h,06eh,020h,073h,069h,06eh,063h,065h,020h,074h,068h,065h,06eh,000h,000h,000h	; 62ef  en since then...

; ----------------------------------------------------------------------
; DATOS respaldo_bajo_el_cursor: Los 24 bytes donde el cursor GUARDA el fondo
;   que tapa, no su dibujo. 0x6580 mete 0x62FF en el HL alternativo y el bucle
;   de 0x65B4-0x65D5, por cada uno de los tres bytes de la columna, primero
;   LEE la pantalla (ld a,(iy+n)), la copia ahi (exx / ld (hl),a / inc hl /
;   exx) y solo despues compone el cursor (and mascara / or dibujo / ld
;   (iy+n),a); 0x64DC hace el camino de vuelta (ld a,(de) / ld (hl),a) para
;   borrarlo. El dibujo de verdad esta en 0x6345 con su mascara detras (ld
;   ix,0x6345 en 0x657B). Los 0xAD que trae la cinta son lo que habia bajo el
;   cursor al grabarla
;   0x62ff..0x6317  (24 bytes)
DATA_respaldo_bajo_el_cursor:
	defb 0adh,0adh,0adh	; 62ff
	defb 0adh,0adh,0adh	; 6302
	defb 0adh,0adh,0adh	; 6305
	defb 0adh,0adh,0adh	; 6308
	defb 0adh,0adh,0adh	; 630b
	defb 0adh,0adh,0adh	; 630e
	defb 0adh,0adh,0adh	; 6311
	defb 0adh,0adh,0adh	; 6314

; ----------------------------------------------------------------------
; DATOS tabla_6317: Tabla que leen 0x6593-0x659C (formato pendiente)
;   0x6317..0x63fb  (228 bytes)
DATA_tabla_6317:
	defb 0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh	; 6317  ................
	defb 0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,0adh,02dh,000h,000h,008h	; 6327  ............-...
	defb 004h,00ch,002h,00ah,006h,00eh,001h,009h,005h,00dh,003h,00bh,007h,00fh,03ch,070h	; 6337  ..............<p
	defb 043h,09eh,060h,051h,0e0h,07eh,0c0h,090h,0c7h,060h,099h,0c0h,0e0h,000h,0c3h,08fh	; 6347  C.`Q.~...`......
	defb 080h,001h,080h,000h,000h,001h,000h,00fh,000h,01fh,006h,03fh,01fh,0ffh,06fh,063h	; 6357  ...........?..oc
	defb 084h,063h,099h,063h,0aeh,063h,0c3h,063h,02dh,000h,005h,000h,002h,000h,001h,000h	; 6367  .c.c.c.c-.......
	defb 001h,000h,001h,000h,001h,000h,001h,000h,001h,000h,001h,000h,001h,00ch,000h,003h	; 6377  ................
	defb 000h,00ch,000h,000h,000h,002h,000h,000h,000h,000h,000h,00ch,000h,038h,000h,022h	; 6387  .............8."
	defb 000h,064h,028h,000h,021h,000h,003h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; 6397  .d(.!...........
	defb 000h,000h,000h,000h,000h,000h,005h,046h,000h,02dh,000h,001h,000h,003h,000h,003h	; 63a7  .......F.-......
	defb 000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,00fh,064h,000h,002h,000h	; 63b7  ............d...
	defb 003h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; 63c7  ................
	defb 028h,0d0h,0e0h,020h,045h,06ch,065h,067h,069h,072h,03ah,020h,041h,072h,072h,069h	; 63d7  (.. Elegir: Arri
	defb 062h,061h,02ch,020h,041h,062h,061h,06ah,06fh,020h,079h,020h,046h,075h,065h,067h	; 63e7  ba, Abajo y Fueg
	defb 06fh,02eh,020h,000h	; 63f7

; ======================================================================
; CODIGO 0x63fb..0x64da  (223 bytes)
; ======================================================================


SIGUIENTE_AL_AZAR:		; Registro de desplazamiento de 16 bits; la semilla vive en su propio operando
	ld hl,0fedch		;63fb   ; La semilla esta en 0x63FC, dentro de este mismo ld hl,nn
	ld a,h			;63fe
	rra			;63ff   ; El bit que sale se realimenta con un xor de las dos mitades
	xor l			;6400
	rra			;6401
	rr h		;6402
	rr l		;6404
	ld (063fch),hl		;6406   ; El resultado se guarda como semilla de la vuelta siguiente y sale en HL
	ret			;6409

; ----------------------------------------------------------------------
; Las listas del juego (personajes, ordenes, opciones) se pintan y se
; ----------------------------------------------------------------------
LISTA_DE_UNA_FILA:		; Menu de lista con un renglon por opcion; A entra con la opcion marcada
	ld (064c5h),a		;640a   ; 0x64C5 es la opcion marcada, dentro del ld b,nn de 0x64C4
	ld de,00020h		;640d   ; 0x20 = una fila de atributos por renglon; va al operando de 0x64C1
	ld (064c2h),de		;6410
	ld a,(hl)			;6414   ; Primer byte de la lista: cuantos renglones tiene
	ld (06496h),a		;6415   ; El tope se guarda en el cp nn de 0x6495
	jr PINTA_LA_LISTA_Y_ELIGE		;6418
LISTA_DE_DOS_FILAS:		; Igual, pero cada opcion ocupa dos renglones y empieza marcada la primera
	xor a			;641a
	ld (064c5h),a		;641b
	ld de,00040h		;641e   ; 0x40 = dos filas de atributos por opcion
	ld (064c2h),de		;6421
	ld a,(hl)			;6425
	ld (06496h),a		;6426
	add a,a			;6429   ; El doble, porque cada opcion ocupa dos renglones de pantalla
PINTA_LA_LISTA_Y_ELIGE:		; Centra la lista en pantalla, la pinta y no vuelve hasta que se elige
	call 006efh		;642a   ; 0x06EF (BORRA_LA_PANTALLA_ZX) deja limpio el bitmap y los atributos
	ld c,a			;642d
	ld a,016h		;642e   ; 22 filas utiles: (22 - renglones) / 2 es la fila de arriba, centrada
	sub c			;6430
	rra			;6431
	inc hl			;6432
	ld b,a			;6433
	ld a,(hl)			;6434   ; Segundo byte de la lista: la anchura en columnas
	ld (L_64CD+1),a		;6435   ; La anchura va al ld b,nn de 0x64CD: es lo que se pinta de color
	ld c,a			;6438
	inc hl			;6439
	push hl			;643a
	ld a,020h		;643b   ; (32 - anchura) / 2: la columna de la izquierda, tambien centrada
	sub c			;643d
	srl a		;643e
	ld c,a			;6440
	ld a,b			;6441
	and 0f8h		;6442   ; Direccion de pantalla del ZX: 0x40 + tercio, y fila*32 + columna
	add a,040h		;6444
	ld h,a			;6446
	ld a,b			;6447
	and 007h		;6448
	rrca			;644a
	rrca			;644b
	rrca			;644c
	add a,c			;644d
	ld l,a			;644e
	ld (0827eh),hl		;644f   ; 0x827E es el operando del ld de,nn de 0x827D: donde escribe el texto
	ld a,h			;6452   ; De direccion de bitmap a direccion de atributo: 0x5800 + los dos bits altos
	rrca			;6453
	rrca			;6454
	rrca			;6455
	and 003h		;6456
	or 058h		;6458
	ld h,a			;645a
	ld (PINTA_EL_RENGLON+1),hl		;645b   ; La direccion de atributo se guarda en el ld hl,nn de 0x64BE
	call ESPERA_A_SOLTAR_FUEGO		;645e   ; Antes de nada, esperar a que se suelte el disparo
	call BORRA_PANTALLA_BLANCA		;6461   ; 0x7F10 borra la VRAM y la deja toda de atributo 0x47
	pop hl			;6464
	ld a,006h		;6465   ; 0x82F6 es el atributo con el que 0x82DC pinta: 6 = amarillo sin brillo
	ld (082f6h),a		;6467
	call ESCRIBE_TEXTO_DONDE_TOCA		;646a
	ld hl,063d8h		;646d   ; 0x63D8: "Elegir: Arriba, Abajo y Fuego." en la ultima fila
	call ESCRIBE_TEXTO_DONDE_TOCA		;6470
	ld a,047h		;6473   ; 0x47 = blanco con brillo: asi se marca la opcion elegida
	call PINTA_EL_RENGLON		;6475
ESPERA_MANDO:		; El efecto de sonido 4 no suena: 0x65FF es un ret
	ld a,004h		;6478
	call SIN_SONIDO		;647a
LEE_EL_MANDO:		; Da vueltas hasta que se mueve algo en el mando
	call 0066dh		;647d   ; 0x066D (LEE_LOS_MANDOS) devuelve los cinco bits mas el 1 y la R
	and a			;6480
	jr z,LEE_EL_MANDO		;6481
	ld b,a			;6483
	ld a,(064c5h)		;6484   ; La opcion marcada esta guardada en el operando de 0x64C4
	bit 0,b		;6487   ; Bit 0: arriba
	jr z,MIRA_SI_BAJA		;6489
	and a			;648b
	jr z,ESPERA_MANDO		;648c   ; Ya esta en la primera: no sube mas
	dec a			;648e
	jr CAMBIA_DE_RENGLON		;648f
MIRA_SI_BAJA:		; Bit 1: abajo, con el tope de renglones que puso 0x6415
	bit 1,b		;6491
	jr z,MIRA_EL_DISPARO		;6493
	cp 000h		;6495   ; El operando de 0x6496 es el numero de renglones de esta lista
	jr nc,ESPERA_MANDO		;6497
	inc a			;6499
CAMBIA_DE_RENGLON:		; Apaga el renglon viejo, apunta el nuevo y lo enciende
	ld c,a			;649a
	ld a,006h		;649b   ; Amarillo sin brillo: el renglon que se deja
	call PINTA_EL_RENGLON		;649d
	ld a,c			;64a0
	ld (064c5h),a		;64a1
	ld a,047h		;64a4   ; Blanco con brillo: el renglon nuevo
	call PINTA_EL_RENGLON		;64a6
	jp ESPERA_MANDO		;64a9
MIRA_EL_DISPARO:		; Bit 4: fuego, elige lo marcado
	bit 4,b		;64ac
	jr z,MIRA_LA_TECLA_1		;64ae
	jr SALE_DE_LA_LISTA		;64b0
MIRA_LA_TECLA_1:		; Bit 5: la tecla 1 vale como elegir el renglon cero
	bit 5,b		;64b2
	jp z,ESPERA_MANDO		;64b4
	xor a			;64b7
SALE_DE_LA_LISTA:		; Espera a soltar el disparo y devuelve el renglon en A
	push af			;64b8
	call ESPERA_A_SOLTAR_FUEGO		;64b9
	pop af			;64bc
	ret			;64bd
PINTA_EL_RENGLON:		; Pinta de atributo A la fila del renglon marcado y la sube a la VRAM
	ld hl,00000h		;64be   ; La direccion de atributo del primer renglon, puesta por 0x645B
	ld de,00000h		;64c1   ; El salto por renglon: 0x20 o 0x40, puesto por 0x6410 o 0x6421
	ld b,000h		;64c4   ; El renglon marcado, puesto por 0x640A, 0x641A o 0x64A1
	inc b			;64c6
	dec b			;64c7
	jr z,L_64CD		;64c8
SUMA_UN_RENGLON:		; Tantos saltos como renglones haya por encima
	add hl,de			;64ca
	djnz SUMA_UN_RENGLON		;64cb
L_64CD:
	ld b,000h		;64cd
PINTA_LA_ANCHURA:		; Tantos atributos como columnas mida la lista
	ld (hl),a			;64cf
	inc hl			;64d0
	djnz PINTA_LA_ANCHURA		;64d1
	push bc			;64d3
	call 00604h		;64d4   ; 0x0604 (ATRIBUTOS_A_VRAM) sube los 768 atributos ya traducidos
	pop bc			;64d7
	ret			;64d8
DEVUELVE_EL_FONDO:		; Interruptor: ret pelado hasta que 0x65FB lo convierte en ld hl,nn
	ret			;64d9   ; 0x65FB mete aqui un 0x21 y el ld hl,nn de 0x64DA apunta al cursor viejo

; ----------------------------------------------------------------------
; DATOS dos_nop_64da: Dos nop tras el ret-interruptor de 0x64D9 (que 0x65FB
;   convierte en ld hl,0x0000)
;   0x64da..0x64dc  (2 bytes)
DATA_dos_nop_64da:
	defb 000h,000h	; 64da

; ======================================================================
; CODIGO 0x64dc..0x6712  (566 bytes)
; ======================================================================


BORRA_EL_CURSOR:		; Devuelve a la pantalla los 24 bytes que el cursor tapaba
	ld de,062ffh		;64dc   ; 0x62FF: los tres bytes por linea que 0x65B4 guardo antes de dibujar
	ld c,008h		;64df   ; Ocho lineas de pixel, tres bytes cada una
UNA_LINEA_DEL_CURSOR:		; Tres bytes; si ya se ha pasado de 0x58 es que no hay pantalla
	ld b,003h		;64e1
	ld a,h			;64e3
	cp 058h		;64e4   ; 0x5800 es el final del bitmap: mas abajo estan los atributos
	jr nc,DESARMA_EL_BORRADO		;64e6
	push hl			;64e8
DEVUELVE_TRES_BYTES:		; Copia los tres bytes guardados y baja una linea de pixel
	ld a,(de)			;64e9
	ld (hl),a			;64ea
	inc hl			;64eb
	inc de			;64ec
	djnz DEVUELVE_TRES_BYTES		;64ed
	pop hl			;64ef
	inc h			;64f0   ; Bajar una linea de pixel dentro de la celda es sumar 256
	ld a,h			;64f1
	and 007h		;64f2   ; Cada ocho lineas hay que saltar a la celda de abajo
	jr nz,SIGUIENTE_LINEA_DEL_CURSOR		;64f4
	ld a,h			;64f6
	sub 008h		;64f7
	ld h,a			;64f9
	ld a,l			;64fa
	add a,020h		;64fb   ; Y eso son 32 bytes mas, con el acarreo al tercio siguiente
	ld l,a			;64fd
	jr nc,SIGUIENTE_LINEA_DEL_CURSOR		;64fe
	ld a,008h		;6500
	add a,h			;6502
	ld h,a			;6503
SIGUIENTE_LINEA_DEL_CURSOR:		; Las ocho lineas de alto que mide el cursor
	dec c			;6504
	jr nz,UNA_LINEA_DEL_CURSOR		;6505
DESARMA_EL_BORRADO:		; Vuelve a poner el ret en 0x64D9: el fondo ya esta devuelto
	ld a,0c9h		;6507   ; 0xC9 = ret: hasta que no se dibuje otra vez, no hay nada que borrar
	ld (064d9h),a		;6509
	ret			;650c

; ----------------------------------------------------------------------
; El cursor del mapa es un sprite de 16x8 con mascara (dibujo en 0x6345,
; ----------------------------------------------------------------------
MUEVE_EL_CURSOR:		; Mueve el cursor con el mando y, si ha cambiado de sitio, lo redibuja
	call 0066dh		;650d   ; 0x066D deja el byte de mandos en 0x6511, que es el operando de aqui abajo
	ld a,000h		;6510   ; Este ld a,nn LEE el byte de mandos: 0x6511 es su propio operando
	ld d,a			;6512
	ld hl,0b8e8h		;6513   ; Los topes: fila hasta 0xB8 (192-8) y columna hasta 0xE8 (256-24)
	ld a,(06544h)		;6516   ; 0x6544 es la fila del cursor, en pixeles
	rr d		;6519   ; Bit 0 del mando: arriba
	jr nc,CURSOR_ABAJO		;651b
	or a			;651d
	jr z,CURSOR_ABAJO		;651e   ; En la fila 0 ya no sube mas
	dec a			;6520
CURSOR_ABAJO:		; Bit 1: abajo, hasta la fila 0xB8
	rr d		;6521
	jr nc,CURSOR_IZQUIERDA		;6523
	inc a			;6525
	cp h			;6526   ; 0xB8 = 184: ocho lineas menos de las 192, que es lo que mide el cursor
	jr c,CURSOR_IZQUIERDA		;6527
	ld a,h			;6529
CURSOR_IZQUIERDA:		; Bit 2: a la izquierda, con 0x6543 de columna
	ld h,a			;652a
	ld a,(06543h)		;652b
	rr d		;652e   ; Bit 2 del mando: izquierda
	jr nc,CURSOR_DERECHA		;6530
	or a			;6532
	jr z,CURSOR_DERECHA		;6533
	dec a			;6535
CURSOR_DERECHA:		; Bit 3: a la derecha, hasta la columna 0xE8
	rr d		;6536
	jr nc,DIBUJA_EL_CURSOR		;6538
	cp l			;653a   ; 0xE8 = 232: 24 pixeles menos de 256, que es lo que mide el cursor de ancho
	jr nc,DIBUJA_EL_CURSOR		;653b
	inc a			;653d
DIBUJA_EL_CURSOR:		; Si el cursor ha cambiado de celda, lo borra de donde estaba y lo estampa donde esta
	ld l,a			;653e
	ld (06543h),hl		;653f
	ld de,03a2ah		;6542   ; Este ld de,nn lee las coordenadas del cursor: son sus propios operandos
	ld hl,00000h		;6545   ; Y este ld hl,nn lleva las coordenadas de la vuelta anterior
	or a			;6548
	sbc hl,de		;6549   ; Si no se ha movido no hay nada que redibujar
	ret z			;654b
	ld (06546h),de		;654c   ; Las nuevas pasan a ser las viejas
	push de			;6550
	call DEVUELVE_EL_FONDO		;6551   ; Borrar el cursor de donde estaba, si es que estaba dibujado
	pop de			;6554
	ld a,d			;6555   ; De aqui a 0x656B, la cuenta del ZX: fila y columna a direccion de pantalla
	and 0c0h		;6556
	rra			;6558
	scf			;6559
	rra			;655a
	rrca			;655b
	xor d			;655c
	and 0f8h		;655d   ; H = 0x40 + (fila y 0xC0)/8 + (fila y 7)
	xor d			;655f
	ld h,a			;6560
	ld a,e			;6561
	rlca			;6562
	rlca			;6563
	rlca			;6564
	xor d			;6565
	and 0c7h		;6566   ; L = (fila y 0x38)*4 + columna/8
	xor d			;6568
	rlca			;6569
	rlca			;656a
	ld l,a			;656b
	ld a,e			;656c   ; Los tres bits de abajo de la columna son el desplazamiento al pixel
	and 007h		;656d
	ld (0659fh),a		;656f   ; El desplazamiento va al operando de 0x659E, que cuenta los rr
	ld (064dah),hl		;6572   ; La direccion queda en el ld hl,nn de 0x64D9, listo para borrar
	push hl			;6575
	pop iy		;6576
	ld hl,(06543h)		;6578   ; Este ld hl no sirve de nada: 0x658F lo pisa antes de usarlo
	ld ix,06345h		;657b   ; 0x6345: ocho lineas de dos bytes de dibujo, y su mascara en 0x6355
	exx			;657f
	ld hl,062ffh		;6580   ; El juego alternativo: HL guarda el fondo en 0x62FF y DE avanza de dos en dos
	ld de,00002h		;6583
	ld b,008h		;6586
UNA_LINEA_DEL_SPRITE:		; Ocho lineas; cada una son tres bytes de pantalla
	exx			;6588
	defb 0fdh,07ch	;ld a,iyh		;6589
	cp 058h		;658b   ; A partir de 0x58 ya no hay bitmap: se acabo la pantalla
	jr nc,ARMA_EL_BORRADO		;658d
	ld hl,0ff00h		;658f   ; El tercer byte empieza vacio y con la mascara toda a unos
	ld b,(ix+000h)		;6592   ; Dos bytes de dibujo de la linea
	ld c,(ix+001h)		;6595
	ld e,(ix+010h)		;6598   ; Y dos de mascara, 16 bytes mas alla
	ld d,(ix+011h)		;659b
	ld a,000h		;659e   ; El desplazamiento al pixel que dejo 0x656F
	or a			;65a0
	jr z,ESTAMPA_LA_LINEA		;65a1
DESPLAZA_UN_PIXEL:		; Corre dibujo y mascara un bit a la derecha, sobre tres bytes
	or a			;65a3
	rr b		;65a4
	rr c		;65a6
	rr l		;65a8
	scf			;65aa   ; La mascara entra con unos: por ahi el fondo se ve
	rr e		;65ab
	rr d		;65ad
	rr h		;65af
	dec a			;65b1
	jr nz,DESPLAZA_UN_PIXEL		;65b2
ESTAMPA_LA_LINEA:		; Guarda el fondo, mete el dibujo y baja una linea de pixel
	ld a,(iy+000h)		;65b4
	exx			;65b7
	ld (hl),a			;65b8   ; El byte de pantalla se guarda en 0x62FF antes de taparlo
	inc hl			;65b9
	exx			;65ba
	and e			;65bb   ; and mascara / or dibujo: el sprite con su recorte
	or b			;65bc
	ld (iy+000h),a		;65bd
	ld a,(iy+001h)		;65c0
	exx			;65c3
	ld (hl),a			;65c4
	inc hl			;65c5
	exx			;65c6
	and d			;65c7
	or c			;65c8
	ld (iy+001h),a		;65c9
	ld a,(iy+002h)		;65cc
	exx			;65cf
	ld (hl),a			;65d0
	inc hl			;65d1
	exx			;65d2
	and h			;65d3
	or l			;65d4
	ld (iy+002h),a		;65d5
	defb 0fdh,024h	;inc iyh		;65d8   ; Una linea de pixel mas abajo
	defb 0fdh,07ch	;ld a,iyh		;65da
	ld c,a			;65dc
	and 007h		;65dd   ; Cada ocho lineas, a la celda de abajo: menos 8 arriba y mas 32 abajo
	jr nz,SIGUIENTE_LINEA_DEL_SPRITE		;65df
	ld a,c			;65e1
	sub 008h		;65e2
	defb 0fdh,067h	;ld iyh,a		;65e4
	defb 0fdh,07dh	;ld a,iyl		;65e6
	add a,020h		;65e8
	defb 0fdh,06fh	;ld iyl,a		;65ea
	jr nc,SIGUIENTE_LINEA_DEL_SPRITE		;65ec
	ld a,008h		;65ee
	defb 0fdh,084h	;add a,iyh		;65f0
	defb 0fdh,067h	;ld iyh,a		;65f2
SIGUIENTE_LINEA_DEL_SPRITE:		; Dos bytes mas de dibujo y vuelta
	exx			;65f4
	add ix,de		;65f5
	djnz UNA_LINEA_DEL_SPRITE		;65f7
ARMA_EL_BORRADO:		; Deja 0x64D9 como ld hl,nn: ahora si hay cursor que borrar
	ld a,021h		;65f9   ; 0x21 = ld hl,nn: el interruptor de 0x64D9 queda armado
	ld (064d9h),a		;65fb
	ret			;65fe
SIN_SONIDO:		; Un ret pelado. Los cuatro que piden efecto (0x5F90, 0x647A, 0x6AA1, 0x833D) acaban aqui
	ret			;65ff

; ----------------------------------------------------------------------
; El motor del altavoz del ZX Spectrum: dos voces que se hacen sonar
; ----------------------------------------------------------------------
EFECTO_DE_SONIDO_ZX:		; A = efecto 0..4; carga sus diez parametros y lo hace sonar. Nadie la llama
	add a,a			;6600   ; HL = 0x6365 + efecto*2: la tabla de los cinco punteros
	add a,065h		;6601
	ld l,a			;6603
	adc a,063h		;6604
	sub l			;6606
	ld h,a			;6607
	ld a,(hl)			;6608   ; Y de ahi sale el bloque de 21 bytes del efecto
	inc hl			;6609
	ld h,(hl)			;660a
	ld l,a			;660b
	call LEE_PALABRA		;660c   ; Los diez parametros se meten uno a uno DENTRO de las instrucciones
	ld (BARRE_LA_VOZ_1+1),de		;660f
	call LEE_PALABRA		;6613
	ld (066bah),de		;6616
	call LEE_PALABRA		;661a
	ld (XOR_DE_LA_VOZ_1+1),de		;661d
	call LEE_PALABRA		;6621
	ld (XOR_DE_LA_VOZ_2+1),de		;6624
	call LEE_PALABRA		;6628
	ld (06683h),de		;662b
	call LEE_PALABRA		;662f
	ld (066bdh),de		;6632
	call LEE_PALABRA		;6636
	ld (066c6h),de		;6639
	call LEE_PALABRA		;663d
	ld (TOPE_DE_LA_VOZ_2+1),de		;6640
	call LEE_PALABRA		;6644
	ld (0668ch),de		;6647
	call LEE_PALABRA		;664b
	ld (TOPE_DE_LA_VOZ_1+1),de		;664e
	ld a,(hl)			;6652   ; El byte 21 es cuantas veces se repite el efecto entero
UNA_REPETICION:		; Suena una vez con los periodos que haya en ese momento
	push af			;6653
	ld hl,(BARRE_LA_VOZ_1+1)		;6654   ; Periodo de la voz 1; a cero, no suena
	ld a,h			;6657
	or l			;6658
	jr z,BARRE_LA_VOZ_1		;6659
	ld bc,(066bah)		;665b   ; Duracion en ciclos de la voz 1
	ld a,b			;665f
	or c			;6660
	jr z,BARRE_LA_VOZ_1		;6661
	ld (0667ah),hl		;6663   ; La recarga del contador de medio ciclo
	xor a			;6666
	ex af,af'			;6667
MEDIO_CICLO:		; Da la vuelta al bit 4 del puerto 0xFE, el altavoz del ZX
	ex af,af'			;6668
	out (0feh),a		;6669   ; Puerto 0xFE del Spectrum: bit 4 altavoz, bit 3 cinta, bits 0-2 borde
	xor 010h		;666b   ; El bit 4 cambia en cada medio ciclo: eso es el tono
	ex af,af'			;666d
ESPERA_EL_PERIODO:		; Cuenta hasta cero sin hacer nada: cuanto mas alto, mas grave
	dec hl			;666e
	ld a,l			;666f
	or h			;6670
	jp nz,ESPERA_EL_PERIODO		;6671
	dec bc			;6674   ; Un ciclo menos de los que dura la nota
	ld a,c			;6675
	or b			;6676
	jr z,BARRE_LA_VOZ_1		;6677
	ld hl,00000h		;6679   ; Recarga del contador de periodo, puesta por 0x6663
	jp MEDIO_CICLO		;667c
BARRE_LA_VOZ_1:		; Suma el incremento al periodo y da la vuelta al llegar al tope
	ld hl,00000h		;667f   ; Periodo de la voz 1
	ld de,00000h		;6682   ; Incremento por repeticion: asi sube o baja el tono
	add hl,de			;6685
	ld a,000h		;6686   ; La bandera de sentido, en el operando de 0x6687
	or a			;6688
	jr z,TOPE_DE_LA_VOZ_1		;6689
	ld de,00000h		;668b   ; El tope de la voz 1
	sbc hl,de		;668e
	add hl,de			;6690
	jr c,XOR_DE_LA_VOZ_1		;6691
	ld c,000h		;6693
VUELVE_LA_VOZ_1:		; Al llegar al tope se le da la vuelta al incremento
	ld hl,(BARRE_LA_VOZ_1+1)		;6695
	ld de,(06683h)		;6698
	ld a,0ffh		;669c   ; Complemento a dos: el incremento cambia de signo
	xor d			;669e
	ld d,a			;669f
	ld a,0ffh		;66a0
	xor e			;66a2
	ld e,a			;66a3
	inc de			;66a4
	ld (06683h),de		;66a5   ; El incremento, ya con el signo cambiado, vuelve a su operando
	ld a,c			;66a9
	ld (06687h),a		;66aa
XOR_DE_LA_VOZ_1:		; El periodo se retuerce con una mascara antes de sonar
	ld de,00000h		;66ad   ; La mascara de xor, otro de los diez parametros
	ld a,h			;66b0
	xor d			;66b1
	ld h,a			;66b2
	ld a,l			;66b3
	xor e			;66b4
	ld l,a			;66b5
	ld (BARRE_LA_VOZ_1+1),hl		;66b6   ; Y el periodo retorcido se guarda para la repeticion siguiente
	ld hl,00000h		;66b9   ; Lo mismo otra vez para la voz 2
	ld de,00000h		;66bc
	add hl,de			;66bf
	ld a,000h		;66c0
	or a			;66c2
	jr z,TOPE_DE_LA_VOZ_2		;66c3
	ld de,00000h		;66c5
	sbc hl,de		;66c8
	jr c,XOR_DE_LA_VOZ_2		;66ca
	ld c,000h		;66cc
VUELVE_LA_VOZ_2:		; Igual que 0x6695 pero para la segunda voz
	ld hl,(066bah)		;66ce   ; Periodo de la voz 2
	ld de,(066bdh)		;66d1
	ld a,0ffh		;66d5
	xor d			;66d7
	ld d,a			;66d8
	ld a,0ffh		;66d9
	xor e			;66db
	ld e,a			;66dc
	inc de			;66dd
	ld (066bdh),de		;66de   ; El incremento de la voz 2, con el signo cambiado
	ld a,c			;66e2
	ld (066c1h),a		;66e3
XOR_DE_LA_VOZ_2:		; Igual que 0x66AD pero para la segunda voz
	ld de,00000h		;66e6   ; La mascara de xor de la voz 2
	ld a,h			;66e9
	xor d			;66ea
	ld h,a			;66eb
	ld a,l			;66ec
	xor e			;66ed
	ld l,a			;66ee
	ld (066bah),hl		;66ef
	pop af			;66f2
	dec a			;66f3   ; Una repeticion menos de las que pedia el byte 21
	jp nz,UNA_REPETICION		;66f4
	ret			;66f7
TOPE_DE_LA_VOZ_1:		; El otro tope de la voz 1, para el sentido contrario
	ld de,00000h		;66f8   ; El otro tope de la voz 1, para cuando el incremento va al reves
	sbc hl,de		;66fb
	add hl,de			;66fd
	jr nc,XOR_DE_LA_VOZ_1		;66fe
	ld c,000h		;6700
	jp VUELVE_LA_VOZ_1		;6702
TOPE_DE_LA_VOZ_2:		; El otro tope de la voz 2, para el sentido contrario
	ld de,00000h		;6705   ; El otro tope de la voz 2
	sbc hl,de		;6708
	add hl,de			;670a
	jr nc,XOR_DE_LA_VOZ_2		;670b
	ld c,000h		;670d
	jp VUELVE_LA_VOZ_2		;670f

; ----------------------------------------------------------------------
; DATOS cola_del_motor_de_sonido: Pop af / ret al que no llega nadie: cola del
;   motor de sonido del Spectrum
;   0x6712..0x6714  (2 bytes)
DATA_cola_del_motor_de_sonido:
	defb 0f1h,0c9h	; 6712

; ======================================================================
; CODIGO 0x6714..0x6af5  (993 bytes)
; ======================================================================


LEE_PALABRA:		; Saca en DE la palabra a la que apunta HL y lo deja detras
	ld e,(hl)			;6714
	inc hl			;6715
	ld d,(hl)			;6716
	inc hl			;6717
	ret			;6718

; ----------------------------------------------------------------------
; El corazon del juego. Cada vuelta del bucle de partida mueve UNA
; ----------------------------------------------------------------------
MUEVE_LA_SIGUIENTE_UNIDAD:		; Una unidad por vuelta; el numero de unidad esta en su propio operando
	ld a,0ffh		;6719   ; El operando de 0x671A es el numero de unidad: va de 0 a 255 y da la vuelta
	inc a			;671b
	ld (0671ah),a		;671c
	ld l,a			;671f
	push af			;6720
	jr nz,CARGA_LA_FICHA_DEL_TIPO		;6721   ; Al dar la vuelta (unidad 0) toca repintar el mapa
	push hl			;6723
	call REPINTA_LOS_EJERCITOS		;6724   ; 0x6AAF vuelve a marcar en los atributos donde esta cada ejercito
	pop hl			;6727
CARGA_LA_FICHA_DEL_TIPO:		; Copia a 0x6D37 los 16 costes de terreno del tipo de esta unidad
	ld h,0bdh		;6728   ; Nibble bajo de 0xBD00+n: el tipo de unidad, de 0 a 15
	ld a,(hl)			;672a
	and 00fh		;672b
	add a,a			;672d
	add a,a			;672e
	add a,a			;672f
	add a,a			;6730
	add a,047h		;6731   ; HL = 0x6D47 + tipo*16: la ficha de ese tipo
	ld l,a			;6733
	adc a,06dh		;6734
	sub l			;6736
	ld h,a			;6737
	ld de,06d37h		;6738   ; Los 16 costes, uno por clase de terreno, a 0x6D37
	ld bc,00010h		;673b
	ldir		;673e
	pop af			;6740
	ld l,a			;6741
	ld h,0c6h		;6742   ; 0xC600+n es el estado de la unidad
	ld a,(hl)			;6744
	bit 6,a		;6745   ; Bit 6: ya esta andando, con la direccion en los tres bits de abajo
	jr nz,TOCA_MOVERSE		;6747
	or a			;6749
	jp m,DESCANSA		;674a   ; Bit 7: parada, descansando
	dec (hl)			;674d   ; Mientras la cuenta no llegue a cero, la unidad sigue quieta este turno
	jr nz,SOLO_APUNTALA		;674e
	ld h,0c2h		;6750
	dec (hl)			;6752   ; 0xC200+n baja al andar; por debajo de 11 la unidad se planta
	ld a,(hl)			;6753
	cp 00bh		;6754
	jp c,SE_PLANTA		;6756
TOCA_MOVERSE:		; Busca el destino, da un paso y guarda la posicion nueva
	ld a,l			;6759
	call BUSCA_EL_DESTINO		;675a   ; 0x6956 devuelve DE = destino y HL apuntando a 0xBA00+n
	ld a,(hl)			;675d   ; La posicion de ahora: fila en 0xBA00+n y columna en 0xB900+n
	dec h			;675e
	ld l,(hl)			;675f
	ld h,a			;6760
	or l			;6761
	ret z			;6762   ; La unidad en (0,0) no esta en el mapa: no hay nada que mover
	call APUNTA_DONDE_ESTA		;6763   ; Antes de moverla, se apunta donde esta
	push hl			;6766
	res 7,h		;6767   ; Los bits 7 de la posicion no son coordenada: dicen por que lado rodea
	res 7,l		;6769
	ld (06777h),hl		;676b   ; La posicion de antes se guarda en el operando de 0x6776
	pop hl			;676e
	ld a,h			;676f
	or l			;6770
	call nz,MIRA_SI_VENIA_RODEANDO		;6771   ; 0x67B0 es quien da el paso; vuelve con la posicion nueva en HL
	ld d,h			;6774
	ld e,l			;6775
	ld hl,00000h		;6776
	ld a,l			;6779
	and 07fh		;677a
	sub e			;677c
	jr nc,MIRA_EL_SALTO_EN_COLUMNA		;677d
	cpl			;677f
MIRA_EL_SALTO_EN_COLUMNA:		; Un paso solo puede mover una celda; si no, no vale
	cp 002h		;6780
	jr nc,PASO_DESCARTADO		;6782   ; Diferencia de 2 o mas: el paso es malo y se descarta
	ld a,h			;6784
	and 07fh		;6785
	sub d			;6787
	jr nc,MIRA_EL_SALTO_EN_FILA		;6788
	cpl			;678a
MIRA_EL_SALTO_EN_FILA:		; Lo mismo con la fila
	cp 002h		;678b
	jr c,GUARDA_LA_POSICION		;678d
PASO_DESCARTADO:		; La unidad se queda donde estaba
	ld d,h			;678f
	ld e,l			;6790
GUARDA_LA_POSICION:		; Columna en 0xB900+n y fila en 0xBA00+n
	ld a,(0671ah)		;6791   ; El numero de unidad, del operando de 0x671A
	ld l,a			;6794
	ld h,0b9h		;6795
	ld (hl),e			;6797
	inc h			;6798
	ld (hl),d			;6799
	ret			;679a
SOLO_APUNTALA:		; La unidad no anda este turno, pero hay que apuntar donde esta
	ld a,l			;679b
	call BUSCA_EL_DESTINO		;679c   ; 0x6956 deja el destino en DE y HL en 0xBA00+n
	ld a,(hl)			;679f
	dec h			;67a0
	ld l,(hl)			;67a1
	ld h,a			;67a2
	or l			;67a3
	ret z			;67a4
APUNTA_DONDE_ESTA:		; Pasa la posicion HL a 0x8F70, que es quien lleva la cuenta
	ld (08f78h),hl		;67a5   ; 0x8F78 es el operando por el que 0x8F70 recibe la posicion
	push hl			;67a8
	push de			;67a9
	call REPARTE_LOS_QUE_ENTRAN		;67aa
	pop de			;67ad
	pop hl			;67ae
	ret			;67af
MIRA_SI_VENIA_RODEANDO:		; Los bits 7 de la posicion dicen si la unidad venia bordeando un obstaculo
	ld c,000h		;67b0
	ld a,h			;67b2   ; Bit 7 de la fila: venia rodeando
	or a			;67b3
	jp p,DA_UN_PASO		;67b4
	and 07fh		;67b7
	ld h,a			;67b9
	ld c,002h		;67ba   ; C = 2 si solo la fila lleva bandera
	ld a,l			;67bc
	or a			;67bd
	jp p,DA_UN_PASO		;67be
	inc c			;67c1   ; C = 3 si tambien la columna: el otro sentido de giro
	and 07fh		;67c2
	ld l,a			;67c4
DA_UN_PASO:		; Calcula la direccion al destino y avanza una celda si el terreno deja
	ld a,c			;67c5
	or a			;67c6
	push af			;67c7
	ld (067dah),hl		;67c8   ; La posicion va al operando de 0x67D9 y el destino al de 0x67D6
	ld (067d7h),de		;67cb
	call CELDA_DEL_MAPA		;67cf   ; 0x8108 pasa la posicion a direccion de mapa: 0xCC67 + columna*102 + fila
	pop af			;67d2
	jp nz,SIGUE_RODEANDO		;67d3   ; Si venia rodeando un obstaculo, sigue por donde iba
	ld de,00000h		;67d6
	ld hl,00000h		;67d9
	ld a,l			;67dc
	ld iy,06b34h		;67dd   ; 0x6B34: el salto de mapa de cada una de las ocho direcciones
	cp e			;67e1   ; Comparar columna con columna y fila con fila da la direccion de la brujula
	ld a,h			;67e2
	jr z,MISMA_COLUMNA		;67e3
	jr nc,COLUMNA_MAYOR		;67e5
	ld c,002h		;67e7   ; Columna menor y fila igual: direccion 2
	cp d			;67e9
	jr z,TRES_INTENTOS		;67ea
	inc c			;67ec   ; Columna menor y fila mayor: 3; columna menor y fila menor: 1
	jr c,TRES_INTENTOS		;67ed
	ld c,001h		;67ef
	jr TRES_INTENTOS		;67f1
MISMA_COLUMNA:		; Con la columna clavada solo cabe subir (0) o bajar (4)
	cp d			;67f3
	jp z,YA_HA_LLEGADO		;67f4   ; Misma columna y misma fila: ya ha llegado
	ld c,004h		;67f7
	jr c,TRES_INTENTOS		;67f9
	ld c,000h		;67fb
	jr TRES_INTENTOS		;67fd
COLUMNA_MAYOR:		; Direcciones 5, 6 y 7: el otro lado de la brujula
	ld c,006h		;67ff
	cp d			;6801   ; Misma fila: direccion 6, de lleno hacia un lado
	jr z,TRES_INTENTOS		;6802
	inc c			;6804
	jr nc,TRES_INTENTOS		;6805
	ld c,005h		;6807
TRES_INTENTOS:		; Prueba tres veces la direccion buena con un bandazo al azar
	ld b,003h		;6809
	ld a,c			;680b
	ld (06864h),a		;680c   ; La direccion elegida, al operando de 0x6864
PRUEBA_UNA_DIRECCION:		; Suma un bandazo al azar y mira si el terreno de esa celda deja pasar
	call SIGUIENTE_AL_AZAR		;680f
	and 00fh		;6812   ; 0x6B23: 16 bandazos de -1, 0 o +1, elegidos al azar
	add a,023h		;6814
	ld l,a			;6816
	adc a,06bh		;6817
	sub l			;6819
	ld h,a			;681a
	ld a,(hl)			;681b
	add a,c			;681c
	ld (06822h),a		;681d   ; La direccion con el bandazo va al desplazamiento de 0x6820
	ld a,(iy+000h)		;6820   ; IY = 0x6B34: -1, +101, +102, +103, +1, -101, -102 y -103 en el mapa
	call COSTE_DEL_TERRENO		;6823   ; 0x68AB dice lo que cuesta ese terreno; negativo es intransitable
	jp p,PASO_NORMAL		;6826
	djnz PRUEBA_UNA_DIRECCION		;6829   ; Tres intentos y despues hay que rodear
	push ix		;682b   ; 0x3C es el opcode de inc a: buscar hueco girando en un sentido
	ld iy,06b34h		;682d
	ld a,03ch		;6831
	call BUSCA_HUECO_GIRANDO		;6833
	ld a,e			;6836
	ld (06844h),a		;6837   ; Los pasos que costaba por ese lado, al operando de 0x6844
	pop ix		;683a
	ld a,03dh		;683c   ; 0x3D es el opcode de dec a: y ahora girando al reves
	call BUSCA_HUECO_GIRANDO		;683e
	ld d,000h		;6841
	ld a,000h		;6843
	cp 0ffh		;6845   ; 0xFF es que por ese lado no habia salida
	jr nz,RODEA_POR_UN_LADO		;6847
	sub e			;6849   ; Se queda con el lado que cueste menos pasos
	jr c,RODEA_POR_EL_OTRO		;684a
	add a,e			;684c
RODEA_POR_UN_LADO:		; Bandera solo en la fila: se recordara como C = 2
	ld e,a			;684d
	call APUNTA_EL_RODEO		;684e
	set 7,h		;6851
	ret			;6853
RODEA_POR_EL_OTRO:		; Bandera en fila y columna: se recordara como C = 3
	ld e,a			;6854
	call APUNTA_EL_RODEO		;6855
	set 7,h		;6858
	set 7,l		;685a
	ret			;685c
APUNTA_EL_RODEO:		; Deja en 0xC600+n la direccion con el bit 6 y en 0xC700+n los pasos
	ld a,(0671ah)		;685d
	ld l,a			;6860
	ld h,0c6h		;6861
	ld a,000h		;6863   ; La direccion viene del operando de 0x6864
	set 6,a		;6865   ; Bit 6: la unidad esta rodeando, no buscando
	ld (hl),a			;6867
	inc h			;6868
	ld (hl),e			;6869   ; 0xC700+n: los pasos que le quedan de rodeo
	ld hl,(067dah)		;686a
	ret			;686d
BUSCA_HUECO_GIRANDO:		; A = 0x3C o 0x3D: el opcode que se mete en 0x688D para girar en un sentido o en el otro
	ld (GIRA_UNA_DIRECCION),a		;686e   ; El opcode se escribe DENTRO de la instruccion de 0x688D
	ld e,000h		;6871
PRUEBA_OCHO_DIRECCIONES:		; Vuelve a la direccion buena y gira hasta ocho veces
	ld a,(06864h)		;6873   ; La direccion de partida, la que apunta al destino
	ld (068a3h),a		;6876
	ld (06884h),a		;6879
	ld b,008h		;687c
	inc e			;687e   ; Un paso mas de rodeo; si desborda, se abandona
	jr z,SIN_SALIDA		;687f
GIRA_Y_MIRA:		; Mira el terreno de la direccion de turno
	ex af,af'			;6881
	ld a,(iy+000h)		;6882
	call COSTE_DEL_TERRENO		;6885   ; Positivo: por ahi se puede
	or a			;6888
	jp p,AVANZA_EN_EL_MAPA		;6889
	ex af,af'			;688c
GIRA_UNA_DIRECCION:		; inc a o dec a, segun el opcode que le hayan escrito
	inc a			;688d
	and 007h		;688e   ; Las ocho direcciones dan la vuelta
	ld (06884h),a		;6890
	djnz GIRA_Y_MIRA		;6893
SIN_SALIDA:		; 0xFF: no hay hueco por este lado
	ld e,0ffh		;6895
	ret			;6897
AVANZA_EN_EL_MAPA:		; Suma al puntero de mapa el salto de la direccion buena
	push de			;6898
	ex af,af'			;6899
	ld e,a			;689a
	add a,a			;689b   ; Extension de signo: el salto de mapa es un byte con signo
	sbc a,a			;689c
	ld d,a			;689d
	add ix,de		;689e
	pop de			;68a0
	ld a,(iy+000h)		;68a1   ; Y desde la celda nueva se vuelve a mirar la direccion buena
	call COSTE_DEL_TERRENO		;68a4
	jp m,PRUEBA_OCHO_DIRECCIONES		;68a7
	ret			;68aa
COSTE_DEL_TERRENO:		; Lee el mapa en la direccion A y devuelve lo que cuesta ese terreno
	ld (068b0h),a		;68ab   ; La direccion va al desplazamiento del ld a,(ix+d) de 0x68AE
	ld a,(ix+000h)		;68ae
	and 00fh		;68b1   ; Nibble bajo del byte de mapa: la clase de terreno, de 0 a 15
	add a,037h		;68b3   ; 0x6D37: la ficha de costes del tipo de unidad, copiada por 0x6738
	ld l,a			;68b5
	adc a,06dh		;68b6
	sub l			;68b8
	ld h,a			;68b9
	ld a,(hl)			;68ba
	or a			;68bb   ; El signo lo dice todo: negativo es intransitable
	ret			;68bc
SIGUE_RODEANDO:		; La unidad venia bordeando un obstaculo: busca hueco desde la direccion que llevaba
	ld a,(0671ah)		;68bd
	ld l,a			;68c0
	ld h,0c6h		;68c1
	push hl			;68c3
	ld a,(hl)			;68c4   ; La direccion que llevaba, en el nibble bajo de 0xC600+n
	and 00fh		;68c5
	ex af,af'			;68c7
	ld a,03ch		;68c8   ; Aqui hay un fallo: C solo vale 2 o 3, el bit 1 siempre esta puesto y A sale siempre 0x3D
	bit 1,c		;68ca
	jr z,L_68CF		;68cc
	inc a			;68ce
L_68CF:
	ld (GIRA_RODEANDO),a		;68cf   ; El opcode se mete dentro del inc a de 0x68E7
	ex af,af'			;68d2
	ld (068dfh),a		;68d3
	ld iy,06b34h		;68d6
	ld b,008h		;68da
PRUEBA_LA_SIGUIENTE:		; Hasta ocho direcciones a partir de la que llevaba
	ex af,af'			;68dc
	ld a,(iy+000h)		;68dd
	call COSTE_DEL_TERRENO		;68e0
	jp p,PASO_DE_RODEO		;68e3
	ex af,af'			;68e6
GIRA_RODEANDO:		; inc a o dec a; 0x68CF decide cual
	inc a			;68e7
	and 007h		;68e8
	ld (068dfh),a		;68ea
	djnz PRUEBA_LA_SIGUIENTE		;68ed   ; Ocho direcciones probadas y ninguna libre
	pop hl			;68ef
	ld hl,(067dah)		;68f0
	ret			;68f3
PASO_DE_RODEO:		; Suma el paso a la posicion y descuenta uno a los pasos que quedan
	ld hl,(067dah)		;68f4
	ex af,af'			;68f7
	add a,a			;68f8   ; 0x6B13 + direccion*2: la pareja (fila, columna) que hay que sumar
	add a,013h		;68f9
	ld e,a			;68fb
	adc a,06bh		;68fc
	sub e			;68fe
	ld d,a			;68ff
	ld a,(de)			;6900
	add a,h			;6901
	ld h,a			;6902
	inc de			;6903
	ld a,(de)			;6904
	add a,l			;6905
	ld l,a			;6906
	ex (sp),hl			;6907   ; 0xC700+n: un paso menos de los que quedan de rodeo
	inc h			;6908
	ld e,(hl)			;6909
	dec e			;690a
	ld (hl),e			;690b
	jr nz,MARCA_EL_LADO		;690c
	dec h			;690e
	ld (hl),001h		;690f   ; Sin pasos, la unidad vuelve al estado 1 y busca camino de nuevo
	pop hl			;6911
	ret			;6912
MARCA_EL_LADO:		; Deja en la posicion los bits 7 que dicen por que lado se rodeaba
	ld a,(GIRA_RODEANDO)		;6913   ; 0x3D es dec a: se estaba rodeando por el segundo lado
	pop hl			;6916
	set 7,h		;6917
	cp 03dh		;6919
	ret nz			;691b
	set 7,l		;691c
	ret			;691e
PASO_NORMAL:		; Suma el paso y cobra en 0xC600+n lo que cuesta el terreno
	ld (06942h),a		;691f   ; El coste del terreno va al operando de 0x6941
	ld a,(06822h)		;6922   ; La direccion que se ha podido tomar, bandazo incluido
	add a,a			;6925   ; 0x6B13 + direccion*2: fila y columna que hay que sumar
	add a,013h		;6926
	ld l,a			;6928
	adc a,06bh		;6929
	sub l			;692b
	ld h,a			;692c
	ld d,(hl)			;692d
	inc hl			;692e
	ld e,(hl)			;692f
	ld a,(067dbh)		;6930   ; Fila de antes mas el salto de fila
	add a,d			;6933
	ld h,a			;6934
	ld a,(067dah)		;6935   ; Columna de antes mas el salto de columna
	add a,e			;6938
	ld l,a			;6939
	push hl			;693a
	ld a,(0671ah)		;693b
	ld l,a			;693e
	ld h,0c6h		;693f
	ld (hl),000h		;6941   ; 0xC600+n = lo que cuesta el terreno: los turnos que estara quieta
	pop hl			;6943
	ret			;6944
DESCANSA:		; Parada: 0xC200+n sube hasta 40 y entonces se vuelve a andar
	ld h,0c2h		;6945
	inc (hl)			;6947
	ld a,(hl)			;6948
	cp 028h		;6949   ; Cuarenta: hasta ahi llega el descanso
	ret c			;694b
	ld h,0c6h		;694c
	res 7,(hl)		;694e   ; Bit 7 fuera: la unidad vuelve a moverse
	ret			;6950
SE_PLANTA:		; 0xC200+n por los suelos: bit 7 puesto y a descansar
	ld h,0c6h		;6951
	set 7,(hl)		;6953
	ret			;6955
BUSCA_EL_DESTINO:		; Devuelve en DE el destino de la unidad, siguiendo la cadena si persigue a otra
	ld c,000h		;6956
	ld l,a			;6958
	ld h,0bch		;6959   ; 0xBC00+n es la fila del destino, salvo que valga 0xFE o mas
	ld a,(hl)			;695b
	cp 0feh		;695c
	jr c,DESTINO_FIJO		;695e   ; Menos de 0xFE: es una fila de verdad, destino fijo
	ld b,l			;6960
SIGUE_LA_CADENA:		; 0xBC00+n a 0xFE o mas quiere decir que 0xBB00+n es OTRA unidad
	inc c			;6961
	jr z,CADENA_ROTA		;6962   ; Doscientos cincuenta y seis saltos: la cadena se muerde la cola
	dec h			;6964
	ld l,(hl)			;6965   ; 0xBB00+n lleva el numero de la unidad a la que se persigue
	inc h			;6966
	ld a,(hl)			;6967
	cp 0feh		;6968
	jr nc,SIGUE_LA_CADENA		;696a   ; Y esa puede estar persiguiendo a otra
	dec h			;696c
	ld e,(hl)			;696d
	ld c,l			;696e
	ld l,b			;696f
	dec h			;6970
	jp SALE_CON_EL_DESTINO		;6971
DESTINO_FIJO:		; Fila y columna del destino, tal cual
	dec h			;6974
	ld e,(hl)			;6975
	dec h			;6976
SALE_CON_EL_DESTINO:		; D = fila y E = columna del destino; HL en 0xBA00+n
	ld d,a			;6977
	ret			;6978
CADENA_ROTA:		; Si la cadena no acaba, se persigue la posicion de la ultima unidad
	ld h,0b9h		;6979
	ld e,(hl)			;697b   ; Columna y fila de la ultima unidad de la cadena
	inc h			;697c
	ld d,(hl)			;697d
	ld c,l			;697e
	ld l,b			;697f
	ret			;6980
BUSCA_EL_NOMBRE:		; Deja HL en el nombre numero E de la lista de personajes
	ld hl,06b46h		;6981   ; 0x6B46: los 24 nombres, de Gandalf a Saruman
	ld bc,000b5h		;6984   ; 181 bytes es lo que ocupan los 24 nombres
	ld a,0b7h		;6987   ; 0xB7 es el separador: en el texto vale por un salto de linea
	inc e			;6989
SALTA_UN_NOMBRE:		; Un separador por nombre
	dec e			;698a
	jr z,L_6992		;698b
	cpir		;698d
	jp SALTA_UN_NOMBRE		;698f
L_6992:
	ret			;6992
DESTINO_POR_LA_RED_CHICA:		; Elige destino nuevo en la red de caminos de 0x6CFB, la de 15 puntos
	push hl			;6993
	ld bc,(067dah)		;6994   ; La posicion a la que se acaba de llegar
	ld hl,06cfbh		;6998   ; 0x6CFB: 15 puntos de cuatro bytes (columna, fila, salida 1, salida 2)
	ld a,00fh		;699b
	call BUSCA_EN_LA_RED		;699d   ; Busca en la red el punto en el que se esta
	ld d,h			;69a0
	ld e,l			;69a1
	call SIGUIENTE_AL_AZAR		;69a2   ; Y una moneda al aire decide por cual de las dos salidas se sigue
	bit 7,h		;69a5
	jr z,APUNTA_EL_DESTINO_CHICO		;69a7
	inc de			;69a9
APUNTA_EL_DESTINO_CHICO:		; Del punto elegido salen columna y fila, que van a 0xBB00 y 0xBC00
	ld a,(de)			;69aa
	add a,a			;69ab   ; Cuatro bytes por punto
	add a,a			;69ac
	add a,0fbh		;69ad
	ld l,a			;69af
	adc a,06ch		;69b0
	sub l			;69b2
	ld h,a			;69b3
	ld e,(hl)			;69b4
	inc hl			;69b5
	ld d,(hl)			;69b6
	pop hl			;69b7
	ld h,0bbh		;69b8   ; 0xBB00+n y 0xBC00+n: el destino nuevo
	ld (hl),e			;69ba
	inc h			;69bb
	ld (hl),d			;69bc
	ld hl,(067dah)		;69bd
	ret			;69c0
DESTINO_POR_LA_RED_GRANDE:		; Igual pero con la red de 0x6BFB, la de 64 puntos
	push hl			;69c1
	ld bc,(067dah)		;69c2
	ld hl,06bfbh		;69c6   ; 0x6BFB: 64 puntos de cuatro bytes; los dos ultimos son a donde se puede seguir
	ld a,040h		;69c9   ; Sesenta y cuatro puntos que mirar
	call BUSCA_EN_LA_RED		;69cb
	ld d,h			;69ce
	ld e,l			;69cf
	call SIGUIENTE_AL_AZAR		;69d0
	bit 7,h		;69d3
	jr z,APUNTA_EL_DESTINO_GRANDE		;69d5
	inc de			;69d7
APUNTA_EL_DESTINO_GRANDE:		; Cuatro bytes por punto, pero con la cuenta a 16 bits
	ld a,(de)			;69d8
	add a,a			;69d9   ; Indice por cuatro, esta vez sin que se pierda el acarreo
	ld l,a			;69da
	ld h,000h		;69db
	add hl,hl			;69dd
	ld a,l			;69de
	add a,0fbh		;69df
	ld l,a			;69e1
	ld a,h			;69e2
	adc a,06bh		;69e3
	ld h,a			;69e5
	ld e,(hl)			;69e6   ; Del punto de la red salen su columna y su fila
	inc hl			;69e7
	ld d,(hl)			;69e8
	pop hl			;69e9
	ld h,0bbh		;69ea   ; 0xBB00+n y 0xBC00+n: el destino nuevo
	ld (hl),e			;69ec
	inc h			;69ed
	ld (hl),d			;69ee
	ld hl,(067dah)		;69ef
	ret			;69f2
BUSCA_EN_LA_RED:		; Busca en la tabla el punto que esta en la posicion BC; A dice cuantos hay
	ld (06a08h),hl		;69f3   ; La base de la tabla se guarda en el operando de 0x6A07
UN_PUNTO_DE_LA_RED:		; Compara fila y columna del punto con la posicion buscada
	ex af,af'			;69f6
	ld e,(hl)			;69f7
	inc hl			;69f8
	ld a,(hl)			;69f9
	inc hl			;69fa
	cp b			;69fb   ; Primero la fila, y solo si coincide, la columna
	jr nz,PUNTO_SIGUIENTE		;69fc
	ld a,e			;69fe
	cp c			;69ff
	ret z			;6a00
PUNTO_SIGUIENTE:		; Los otros dos bytes del punto son sus dos salidas
	inc hl			;6a01
	inc hl			;6a02
	ex af,af'			;6a03
	dec a			;6a04
	jr nz,UN_PUNTO_DE_LA_RED		;6a05
	ld hl,00000h		;6a07   ; Si no aparece, se cogen las salidas del primer punto de la tabla
	inc hl			;6a0a
	inc hl			;6a0b
	ret			;6a0c
YA_HA_LLEGADO:		; La unidad esta en su destino: le toca destino nuevo
	ld a,(0671ah)		;6a0d   ; 0xC200+n sube, sin pasar de 255
	ld l,a			;6a10
	ld h,0c2h		;6a11
	inc (hl)			;6a13
	jr nz,REPARTE_POR_NUMERO		;6a14
	dec (hl)			;6a16
REPARTE_POR_NUMERO:		; El numero de unidad decide por que red de caminos se busca destino
	cp 0ddh		;6a17   ; De 0xDD para arriba, red chica
	jp nc,DESTINO_POR_LA_RED_CHICA		;6a19
	cp 078h		;6a1c   ; De 0x78 a 0xDC, red grande
	jp nc,DESTINO_POR_LA_RED_GRANDE		;6a1e
	cp 016h		;6a21   ; La unidad 0x16 va por la red grande
	jp z,DESTINO_POR_LA_RED_GRANDE		;6a23
	cp 017h		;6a26   ; Y la 0x17 por la chica
	jp z,DESTINO_POR_LA_RED_CHICA		;6a28
	ld h,0c6h		;6a2b
	ld (hl),001h		;6a2d   ; Las demas se quedan quietas con el estado 1
	ld hl,(067dah)		;6a2f
	ret			;6a32

; ----------------------------------------------------------------------
; La entrega del Anillo. 0x72F5 apunta en 0x6A4C quien lo lleva y le
; ----------------------------------------------------------------------
DEJA_LA_PERSECUCION:		; Le pone al elegido su propia posicion de destino y apaga la bandera
	ld e,l			;6a33
	ld d,0b9h		;6a34
	ld h,0bbh		;6a36
	ld a,(de)			;6a38   ; De 0xB900 y 0xBA00 a 0xBB00 y 0xBC00: destino igual a la posicion
	and 07fh		;6a39
	ld (hl),a			;6a3b
	inc d			;6a3c
	inc h			;6a3d
	ld a,(de)			;6a3e
	and 07fh		;6a3f
	ld (hl),a			;6a41
	xor a			;6a42
	ld (06a48h),a		;6a43   ; La bandera de 0x6A48 se apaga: ya no hay entrega en marcha
	ret			;6a46
MIRA_SI_YA_SE_HAN_JUNTADO:		; Si el portador ha alcanzado a la unidad elegida, le pasa el Anillo
	ld a,000h		;6a47   ; El operando de 0x6A48 es la bandera: sin ella no hay nada que mirar
	or a			;6a49
	ret z			;6a4a
	ld hl,0bb00h		;6a4b   ; El operando de 0x6A4C es el portador; lo puso 0x7327
	ld a,(hl)			;6a4e   ; 0xBB00+portador lleva el NUMERO de la unidad elegida, no una coordenada
	dec h			;6a4f
	ld b,(hl)			;6a50
	dec h			;6a51
	ld c,(hl)			;6a52
	ld l,a			;6a53   ; Y con ese numero se mira donde esta la elegida
	ld a,b			;6a54
	or c			;6a55
	jr z,DEJA_LA_PERSECUCION		;6a56
	ld a,(hl)			;6a58
	and 07fh		;6a59   ; Los bits 7 son banderas de rodeo: fuera antes de comparar
	res 7,c		;6a5b
	cp c			;6a5d   ; Misma columna
	ret nz			;6a5e
	inc h			;6a5f
	ld a,(hl)			;6a60
	and 07fh		;6a61
	res 7,b		;6a63
	cp b			;6a65   ; Y misma fila: se han juntado
	ret nz			;6a66
	inc h			;6a67   ; A la elegida se le pone de destino la celda en la que estan
	ld (hl),c			;6a68
	inc h			;6a69
	ld (hl),b			;6a6a
	inc h			;6a6b
	set 4,(hl)		;6a6c   ; Bit 4 de 0xBD00: el Anillo pasa a la elegida
	ld h,0c0h		;6a6e
	ld a,(hl)			;6a70
	and 00fh		;6a71
	jp z,DERROTA		;6a73   ; Si el nibble bajo de 0xC000 de la elegida es cero, DERROTA (0x83E1)
	ld a,(08333h)		;6a76   ; El operando de 0x8333, que es la cuenta atras de meses
	push bc			;6a79
	ld b,a			;6a7a
	add a,a			;6a7b
	add a,a			;6a7c
	add a,a			;6a7d
	add a,a			;6a7e
	ld (08333h),a		;6a7f   ; Se guarda multiplicado por 16: pierde su nibble alto
	ld a,(06a4ch)		;6a82
	ld l,a			;6a85
	ld a,(hl)			;6a86   ; Del byte de 0xC000 del portador solo se conserva el nibble alto
	and 0f0h		;6a87
	ld e,a			;6a89
	ld a,b			;6a8a
	rrca			;6a8b   ; El nibble alto de la cuenta atras, menos uno, es el nibble bajo nuevo
	rrca			;6a8c
	rrca			;6a8d
	rrca			;6a8e
	and 00fh		;6a8f
	jr z,EL_ANILLO_CAMBIA_DE_MANO		;6a91
	dec a			;6a93
EL_ANILLO_CAMBIA_DE_MANO:		; Apaga el bit 4 del portador viejo y saca el mensaje
	or e			;6a94
	ld (hl),a			;6a95
	ld h,0bdh		;6a96   ; Bit 4 fuera: el portador viejo ya no lleva el Anillo
	res 4,(hl)		;6a98
	pop bc			;6a9a
	dec h			;6a9b   ; Y se queda con la celda en la que estan como destino
	ld (hl),b			;6a9c
	dec h			;6a9d
	ld (hl),c			;6a9e
	ld a,004h		;6a9f   ; Efecto 4, que no suena
	call SIN_SONIDO		;6aa1
	ld hl,06af5h		;6aa4   ; 0x6AF5 es "El Anillo se ha perdido."; 0x8242 es el mensaje que se muestra
	ld (08242h),hl		;6aa7
	xor a			;6aaa
	ld (06a48h),a		;6aab   ; Bandera apagada: la entrega esta hecha
	ret			;6aae
REPINTA_LOS_EJERCITOS:		; Deja el mapa de fondo y vuelve a marcar donde esta cada unidad
	ld hl,05800h		;6aaf   ; 0x5800: los 768 atributos de la pantalla del Spectrum
	ld bc,00300h		;6ab2
LIMPIA_UN_ATRIBUTO:		; Todo lo que no sea 0x78 vuelve a 0x30
	ld a,078h		;6ab5   ; 0x78 es blanco con brillo: eso se respeta, es del dibujo del mapa
	cp (hl)			;6ab7
	jr z,SIGUIENTE_ATRIBUTO		;6ab8
	ld (hl),030h		;6aba   ; 0x30 es papel amarillo sin brillo: el fondo del mapa
SIGUIENTE_ATRIBUTO:		; Las 768 celdas de la pantalla
	inc hl			;6abc
	dec bc			;6abd
	ld a,b			;6abe
	or c			;6abf
	jr nz,LIMPIA_UN_ATRIBUTO		;6ac0
	ld hl,0b900h		;6ac2   ; Y ahora, una marca por unidad, empezando por la 0
MARCA_UNA_UNIDAD:		; Pone de atributo 0x70 la celda en la que esta la unidad
	ld a,(hl)			;6ac5   ; Columna de la unidad; cuatro celdas de mapa por columna de caracter
	rrca			;6ac6
	rrca			;6ac7
	and 01fh		;6ac8
	ld e,a			;6aca
	inc h			;6acb
	ld a,(hl)			;6acc   ; Fila de la unidad, sin el bit 7 de rodeo
	and 07fh		;6acd
	dec h			;6acf
	sub 004h		;6ad0   ; Las cuatro primeras filas de mapa no se ven
	rlca			;6ad2   ; Fila por 8: asi salen los bits de la direccion de atributo
	rlca			;6ad3
	rlca			;6ad4
	ld b,a			;6ad5
	and 003h		;6ad6
	or 058h		;6ad8   ; 0x5800 mas los dos bits altos de la fila
	ld d,a			;6ada
	ld a,b			;6adb
	and 0e0h		;6adc
	or e			;6ade
	ld e,a			;6adf
	ld a,070h		;6ae0   ; 0x70: papel amarillo CON brillo, que es como se ve un ejercito
	ld (de),a			;6ae2
SIGUIENTE_UNIDAD_DEL_MAPA:		; Marca las unidades 0 a 0x77, saltandose la 0x16 y la 0x17
	inc l			;6ae3
	ld a,l			;6ae4
	cp 016h		;6ae5   ; La 0x16 no se pinta en el mapa
	jr z,SIGUIENTE_UNIDAD_DEL_MAPA		;6ae7
	cp 017h		;6ae9   ; La 0x17 tampoco
	jr z,SIGUIENTE_UNIDAD_DEL_MAPA		;6aeb
	cp 078h		;6aed   ; De la 0x78 para arriba, ninguna se marca
	jr c,MARCA_UNA_UNIDAD		;6aef
	call 00604h		;6af1   ; 0x0604 (ATRIBUTOS_A_VRAM) sube los 768 atributos ya traducidos
	ret			;6af4

; ----------------------------------------------------------------------
; DATOS textos_y_tablas_del_anillo: Textos ("El Anillo se ha perdido.") y
;   tablas (0x6B13, 0x6B34, 0x6B3D, 0x6B46, 0x6BE4 los apuntan; formato
;   pendiente)
;   0x6af5..0x6de7  (754 bytes)
DATA_textos_y_tablas_del_anillo:
	defb 045h,06ch,020h,041h,06eh,069h,06ch,06ch,06fh,020h,073h,065h,020h,068h,061h,020h	; 6af5  El Anillo se ha 
	defb 070h,065h,072h,064h,069h,064h,06fh,02eh,020h,020h,020h,020h,020h,000h,0ffh,000h	; 6b05  perdido.     ...
	defb 0ffh,001h,000h,001h,001h,001h,001h,000h,001h,0ffh,000h,0ffh,0ffh,0ffh,000h,001h	; 6b15  ................
	defb 000h,0ffh,000h,001h,000h,000h,001h,000h,000h,0ffh,000h,000h,000h,001h,099h,0ffh	; 6b25  ................
	defb 065h,066h,067h,001h,09bh,09ah,099h,0ffh,015h,009h,056h,075h,065h,06ch,076h,065h	; 6b35  efg.......Vuelve
	defb 0b7h,047h,061h,06eh,064h,061h,06ch,066h,0b7h,041h,072h,061h,067h,06fh,072h,06eh	; 6b45  .Gandalf.Aragorn
	defb 0b7h,042h,06fh,072h,06fh,06dh,069h,072h,0b7h,04ch,065h,067h,06fh,06ch,061h,073h	; 6b55  .Boromir.Legolas
	defb 0b7h,047h,069h,06dh,06ch,069h,0b7h,046h,072h,06fh,064h,06fh,0b7h,053h,061h,06dh	; 6b65  .Gimli.Frodo.Sam
	defb 0b7h,04dh,065h,072h,072h,079h,0b7h,050h,069h,070h,070h,069h,06eh,0b7h,045h,06ch	; 6b75  .Merry.Pippin.El
	defb 072h,06fh,06eh,064h,0b7h,044h,061h,069h,06eh,020h,049h,049h,0b7h,043h,065h,06ch	; 6b85  rond.Dain II.Cel
	defb 065h,062h,06fh,072h,06eh,0b7h,054h,068h,072h,061h,06eh,064h,075h,069h,06ch,0b7h	; 6b95  eborn.Thranduil.
	defb 042h,072h,061h,06eh,064h,020h,049h,049h,049h,0b7h,054h,068h,065h,06fh,064h,072h	; 6ba5  Brand III.Theodr
	defb 065h,064h,0b7h,054h,068h,065h,06fh,064h,065h,06eh,0b7h,045h,06fh,077h,079h,06eh	; 6bb5  ed.Theoden.Eowyn
	defb 0b7h,045h,06fh,06dh,065h,072h,0b7h,049h,06dh,072h,061h,068h,069h,06ch,0b7h,044h	; 6bc5  .Eomer.Imrahil.D
	defb 065h,06eh,065h,074h,068h,06fh,072h,0b7h,046h,061h,072h,061h,06dh,069h,072h,0b7h	; 6bd5  enethor.Faramir.
	defb 047h,06fh,06ch,06ch,075h,06dh,0b7h,053h,061h,075h,072h,06fh,06eh,0b7h,053h,061h	; 6be5  Gollum.Sauron.Sa
	defb 072h,075h,06dh,061h,06eh,0b7h,06fh,040h,005h,003h,068h,03fh,000h,000h,068h,046h	; 6bf5  ruman.o@..h?..hF
	defb 001h,003h,063h,041h,004h,005h,05fh,040h,003h,009h,064h,03ah,000h,007h,061h,03ch	; 6c05  ..cA.._@..d:..a<
	defb 005h,005h,060h,037h,01eh,013h,05ch,043h,013h,004h,05bh,046h,008h,00ah,059h,046h	; 6c15  ..`7..\C..[F..YF
	defb 009h,00bh,057h,046h,012h,015h,05ch,04bh,009h,009h,060h,056h,00ch,00ch,063h,05ah	; 6c25  ..WF..\K..`V..cZ
	defb 00dh,00dh,044h,063h,00eh,00eh,051h,049h,00bh,012h,046h,04ch,010h,017h,04eh,046h	; 6c35  ..Dc..QI..FL..NF
	defb 011h,017h,05bh,03eh,007h,014h,05ah,03eh,03eh,015h,058h,03fh,016h,03eh,056h,03fh	; 6c45  ..[>..Z>>.X?.>V?
	defb 016h,016h,048h,044h,010h,018h,042h,03eh,017h,019h,041h,03bh,01ah,018h,041h,03ah	; 6c55  ..HD..B>..A;..A:
	defb 019h,01dh,042h,038h,01ch,01ah,041h,036h,01dh,02bh,047h,039h,03eh,01bh,05dh,032h	; 6c65  ..B8..A6.+G9>.]2
	defb 01fh,014h,05ah,028h,020h,021h,054h,027h,029h,01eh,05ah,01ah,022h,023h,064h,00fh	; 6c75  ..Z( !T').Z."#d.
	defb 021h,021h,051h,019h,024h,029h,04ch,019h,025h,025h,046h,019h,026h,027h,045h,017h	; 6c85  !!Q.$)L.%%F.&'E.
	defb 027h,028h,043h,019h,032h,028h,045h,01eh,029h,027h,04eh,021h,028h,02ah,049h,024h	; 6c95  '(C.2(E.)'N!(*I$
	defb 03fh,03fh,038h,02ah,01ch,02ch,035h,028h,02bh,02dh,033h,022h,02bh,02eh,02fh,022h	; 6ca5  ??8*.,5(+-3"+./"
	defb 02dh,02fh,02ch,021h,02eh,030h,025h,01eh,031h,038h,025h,01bh,02fh,02fh,03ch,019h	; 6cb5  -/,!.0%.18%.//<.
	defb 033h,033h,035h,019h,034h,034h,033h,01ah,035h,02dh,030h,01bh,036h,02fh,02bh,019h	; 6cc5  335.443.5-0.6/+.
	defb 037h,037h,029h,019h,038h,039h,029h,01bh,031h,02fh,028h,016h,031h,03ah,022h,017h	; 6cd5  77).89).1/(.1:".
	defb 03bh,039h,01fh,017h,03ah,03ch,019h,019h,03bh,03dh,014h,01eh,03ch,030h,04eh,03ch	; 6ce5  ;9..:<..;=..<0N<
	defb 01dh,015h,044h,02fh,01dh,01dh,057h,046h,003h,003h,04eh,046h,000h,000h,05ah,03eh	; 6cf5  ..D/..WF..NF..Z>
	defb 004h,004h,058h,03fh,003h,00dh,056h,03fh,004h,004h,048h,044h,001h,001h,042h,03eh	; 6d05  ..X?..V?..HD..B>
	defb 005h,005h,041h,03bh,006h,00bh,041h,03ah,007h,00ch,042h,038h,008h,00bh,041h,036h	; 6d15  ..A;..A:..B8..A6
	defb 009h,00eh,047h,039h,00dh,00ah,038h,02ah,00ah,00ah,04eh,03ch,00bh,003h,044h,02fh	; 6d25  ..G9..8*..N<..D/
	defb 008h,00bh,003h,0ffh,0ffh,00fh,003h,003h,003h,00fh,003h,003h,00fh,003h,0ffh,003h	; 6d35  ................
	defb 0ffh,003h,003h,0ffh,0ffh,003h,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,003h	; 6d45  ................
	defb 00fh,003h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,00fh	; 6d55  ................
	defb 00fh,003h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,00fh	; 6d65  ................
	defb 00fh,003h,003h,0ffh,0ffh,003h,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,003h	; 6d75  ................
	defb 00fh,003h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,00fh	; 6d85  ................
	defb 003h,002h,003h,0ffh,0ffh,00fh,003h,003h,002h,003h,003h,003h,003h,003h,00fh,00fh	; 6d95  ................
	defb 003h,002h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,003h	; 6da5  ................
	defb 00fh,003h,003h,0ffh,0ffh,003h,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,003h	; 6db5  ................
	defb 00fh,003h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,00fh	; 6dc5  ................
	defb 00fh,003h,003h,0ffh,0ffh,00fh,003h,003h,002h,00fh,003h,003h,003h,003h,00fh,00fh	; 6dd5  ................
	defb 00fh,003h	; 6de5

; ======================================================================
; CODIGO 0x6de7..0x7697  (2224 bytes)
; ======================================================================



; ----------------------------------------------------------------------
; La ficha que sale al pulsar fuego sobre el mapa. El texto se arma en
; ----------------------------------------------------------------------
DESCRIBE_EL_DESTINO:		; Segunda linea de la ficha: a quien o a que sigue esta unidad
	exx			;6de7
	ld h,0bch		;6de8   ; 0xBC00+n a 0xFE: el destino es otra unidad, no una casilla
	ld a,(hl)			;6dea
	ld h,0bdh		;6deb
	cp 0feh		;6ded
	jr z,NOMBRE_DEL_PERSEGUIDO		;6def
	ld a,(hl)			;6df1   ; Si no, se describe por su tipo, del nibble bajo de 0xBD00+n
	exx			;6df2
NOMBRE_DEL_TIPO:		; Copia a 0x7C2F el nombre en singular de la raza
	and 00fh		;6df3
	ld b,a			;6df5
	ld hl,07d39h		;6df6   ; 0x7D39: los nombres en singular, uno detras de otro, con el bit 7 en su ultima letra
	call SALTA_B_TEXTOS		;6df9
	ld de,07c2fh		;6dfc   ; 0x7C2F es la segunda fila de la ventana de 24 columnas
	call COPIA_TEXTO		;6dff
	ex af,af'			;6e02
	ret c			;6e03
CIERRA_LA_LINEA:		; Detras va el texto fijo de 0x7D90
	ld hl,07d90h		;6e04
	jp COPIA_TEXTO		;6e07
DESCRIBE_AL_PERSEGUIDO:		; De la 0x17 para arriba no hay nombre: se describe por su tipo
	or a			;6e0a
	ex af,af'			;6e0b
	ld l,c			;6e0c
	ld h,0bdh		;6e0d   ; El tipo del perseguido, en 0xBD00
	ld a,(hl)			;6e0f
	jr NOMBRE_DEL_TIPO		;6e10
NOMBRE_DEL_PERSEGUIDO:		; Si persigue a una unidad con nombre, se pone el nombre
	ld a,l			;6e12
	exx			;6e13
	call BUSCA_EL_DESTINO		;6e14   ; 0x6956 devuelve en C la unidad a la que persigue
	ld a,c			;6e17
	cp 017h		;6e18   ; Solo las unidades 0 a 0x16 tienen nombre en la lista de 0x6B46
	jr nc,DESCRIBE_AL_PERSEGUIDO		;6e1a
	ld e,a			;6e1c
	call BUSCA_EL_NOMBRE		;6e1d   ; 0x6981 deja HL en el nombre numero E
	ld de,07c2fh		;6e20
COPIA_EL_NOMBRE:		; Hasta el 0xB7, que es lo que separa un nombre del siguiente
	ld a,(hl)			;6e23   ; Letra a letra hasta el separador
	cp 0b7h		;6e24
	jr z,CIERRA_LA_LINEA		;6e26
	ld (de),a			;6e28
	inc de			;6e29
	inc hl			;6e2a
	jr COPIA_EL_NOMBRE		;6e2b
VENTANA_DEL_SITIO:		; Busca el sitio en la tabla de 0x7A5E y saca su cartel
	call BUSCA_EL_SITIO		;6e2d   ; 0x6E50 busca la posicion en la tabla de sitios
	ret c			;6e30
	push bc			;6e31
	ex de,hl			;6e32
	inc hl			;6e33
	ld a,(hl)			;6e34   ; Nibble alto: las columnas que mide el cartel
	rra			;6e35
	rra			;6e36
	rra			;6e37
	rra			;6e38
	and 00fh		;6e39
	ld c,a			;6e3b
	ld a,(hl)			;6e3c
	inc hl			;6e3d
	and 00fh		;6e3e   ; Nibble bajo: las filas
	ex de,hl			;6e40
	ld hl,05e1eh		;6e41   ; 0x5E1E es la columna 30 de la fila 0: el cartel se pega a la derecha
	or a			;6e44
	ld b,000h		;6e45
	sbc hl,bc		;6e47
	ld b,c			;6e49
	ld c,a			;6e4a
	call DIBUJA_UNA_VENTANA		;6e4b   ; 0x70D6 dibuja el marco y mete dentro el texto
	pop hl			;6e4e
	ret			;6e4f
BUSCA_EL_SITIO:		; Recorre 0x7A5E buscando el registro cuya posicion es BC
	ld b,h			;6e50
	ld c,l			;6e51
	ld hl,07a5eh		;6e52   ; 0x7A5E: los sitios del mapa, cada uno con su posicion delante
UN_SITIO:		; Compara la posicion del registro con la que se busca
	ld e,(hl)			;6e55
	inc hl			;6e56
	ld d,(hl)			;6e57
	inc hl			;6e58
	or a			;6e59
	ex de,hl			;6e5a
	sbc hl,bc		;6e5b
	ex de,hl			;6e5d
	jr z,SITIO_ENCONTRADO		;6e5e   ; Coincide: HL se queda en el texto del sitio
	ld a,(hl)			;6e60   ; El byte siguiente dice cuanto ocupa este registro
	or a			;6e61
	jr z,SITIO_NO_ENCONTRADO		;6e62
	add a,l			;6e64   ; Y con eso se salta al registro siguiente
	ld l,a			;6e65
	adc a,h			;6e66
	sub l			;6e67
	ld h,a			;6e68
	jp UN_SITIO		;6e69
SITIO_NO_ENCONTRADO:		; Sale con acarreo: en esa celda no hay ningun sitio con nombre
	ld h,b			;6e6c
	ld l,c			;6e6d
	scf			;6e6e
	ret			;6e6f
SITIO_ENCONTRADO:		; Sale sin acarreo y con HL en el texto
	ex de,hl			;6e70
	ld h,b			;6e71
	ld l,c			;6e72
	ret			;6e73
COPIA_SI_NO_ESTA_VACIO:		; Un 0xA0 solo quiere decir que ahi no hay nada que decir
	ld a,(hl)			;6e74
	cp 0a0h		;6e75
	ret z			;6e77
COPIA_TEXTO:		; Copia de (HL) a (DE) hasta la letra que lleve el bit 7
	ld a,(hl)			;6e78
	or a			;6e79
	jp m,ULTIMA_LETRA		;6e7a   ; Bit 7 puesto: esa es la ultima letra
	ld (de),a			;6e7d
	inc hl			;6e7e
	inc de			;6e7f
	jp COPIA_TEXTO		;6e80
ULTIMA_LETRA:		; Se copia sin el bit 7 y se acaba
	and 07fh		;6e83
	ld (de),a			;6e85
	inc de			;6e86
	ret			;6e87
REPARTE_EN_OCHO:		; A entre 2, en ocho tramos: elige el adverbio de 0x7D9A
	ld c,002h		;6e88
	jr L_6E8E		;6e8a
REPARTE_EN_OCHO_GORDO:		; Lo mismo pero A entre 32, para los contadores de byte entero
	ld c,020h		;6e8c
L_6E8E:
	ld b,007h		;6e8e   ; Ocho tramos: Realmente, Muy, Es muy, Es algo, No muy, No, No es muy
BAJA_UN_TRAMO:		; Cuanto mas alto el valor, mas arriba en la lista
	sub c			;6e90
	jr c,LISTA_DE_ADVERBIOS		;6e91
	djnz BAJA_UN_TRAMO		;6e93
LISTA_DE_ADVERBIOS:		; 0x7D9A es donde empiezan los siete adverbios
	ld hl,07d9ah		;6e95
SALTA_B_TEXTOS:		; Deja HL en el texto numero B de la lista que empieza en HL
	inc b			;6e98
SALTA_UNO:		; Uno menos; si ya no quedan, aqui esta
	inc hl			;6e99
	djnz BUSCA_EL_FINAL		;6e9a
	ret			;6e9c
BUSCA_EL_FINAL:		; Corre hasta la letra con el bit 7, que es donde acaba el texto
	ld a,(hl)			;6e9d
	or a			;6e9e
	jp m,SALTA_UNO		;6e9f
	inc hl			;6ea2
	jp BUSCA_EL_FINAL		;6ea3
BUSCA_UNIDAD_ADELANTE:		; Con la posicion en HL, busca hacia arriba una unidad que este ahi
	ld a,h			;6ea6
	or l			;6ea7
	ret z			;6ea8   ; La posicion (0,0) no vale
	ex de,hl			;6ea9
	ld b,000h		;6eaa   ; B = 0: las 256 unidades
MIRA_UNA_UNIDAD:		; El operando de 0x6EAD es el numero de unidad que se esta mirando
	ld hl,0b900h		;6eac
	ld a,(hl)			;6eaf
	and 07fh		;6eb0   ; Sin el bit 7, que es bandera de rodeo
	cp e			;6eb2   ; Misma columna
	jr nz,SIGUIENTE_UNIDAD		;6eb3
	inc h			;6eb5
	ld a,(hl)			;6eb6
	dec h			;6eb7
	and 07fh		;6eb8
	cp d			;6eba   ; Y misma fila
	jr nz,SIGUIENTE_UNIDAD		;6ebb
	ld a,l			;6ebd
	cp 078h		;6ebe   ; De la 0x78 para arriba no cuentan
	jr nc,SIGUIENTE_UNIDAD		;6ec0
	cp 016h		;6ec2   ; La 0x16 tampoco
	jr z,SIGUIENTE_UNIDAD		;6ec4
	cp 017h		;6ec6   ; Ni la 0x17
	jr z,SIGUIENTE_UNIDAD		;6ec8
	ex de,hl			;6eca
	scf			;6ecb   ; Acarreo: se ha encontrado, y su numero queda en el operando de 0x6EAD
	ret			;6ecc
SIGUIENTE_UNIDAD:		; Uno mas, y el numero se guarda en el operando de 0x6EAD
	inc l			;6ecd
	ld (MIRA_UNA_UNIDAD+1),hl		;6ece   ; El numero por el que va la busqueda vuelve al operando de 0x6EAD
	djnz MIRA_UNA_UNIDAD		;6ed1
	ex de,hl			;6ed3
	or a			;6ed4
	ret			;6ed5
BUSCA_UNIDAD_ATRAS:		; Igual que 0x6EAC pero contando hacia abajo
	ld a,h			;6ed6
	or l			;6ed7
	ret z			;6ed8
	ex de,hl			;6ed9
	ld b,000h		;6eda   ; B = 0: las 256 unidades
MIRA_LA_ANTERIOR:		; Empieza por donde se quedo 0x6EAC
	ld hl,(MIRA_UNA_UNIDAD+1)		;6edc
	ld a,(hl)			;6edf
	and 07fh		;6ee0
	cp e			;6ee2   ; Misma columna
	jr nz,ANTERIOR_UNIDAD		;6ee3
	inc h			;6ee5
	ld a,(hl)			;6ee6
	dec h			;6ee7
	and 07fh		;6ee8
	cp d			;6eea   ; Y misma fila
	jr nz,ANTERIOR_UNIDAD		;6eeb
	ld a,l			;6eed
	cp 078h		;6eee   ; De la 0x78 para arriba, la 0x16 y la 0x17 no se ensenan
	jr nc,ANTERIOR_UNIDAD		;6ef0
	cp 016h		;6ef2
	jp z,ANTERIOR_UNIDAD		;6ef4
	cp 017h		;6ef7
	jp z,ANTERIOR_UNIDAD		;6ef9
	ex de,hl			;6efc
	scf			;6efd
	ret			;6efe
ANTERIOR_UNIDAD:		; Uno menos
	dec l			;6eff
	ld (MIRA_UNA_UNIDAD+1),hl		;6f00   ; Igual que 0x6ECE, pero contando hacia atras
	djnz MIRA_LA_ANTERIOR		;6f03
	ex de,hl			;6f05
	or a			;6f06
	ret			;6f07
FICHA_SIN_MIRAR_EL_MODO:		; Entra directo a armar la ficha entera
	push hl			;6f08
	jr ARMA_LA_FICHA		;6f09
FICHA_DE_LA_UNIDAD:		; Arma en 0x7C17 la ficha de la unidad marcada y la pinta
	push hl			;6f0b
	ld hl,060abh		;6f0c   ; 0x60AB es la fila 20, columna 3 de la pantalla de caracteres
	ld bc,01801h		;6f0f   ; Una ventana de 24 columnas por una sola fila
	ld a,(071cfh)		;6f12   ; Si 0x71CF no vale 0x10, se pinta solo esa fila, sin armar nada
	cp 010h		;6f15
	jp nz,PINTA_LA_VENTANA		;6f17
ARMA_LA_FICHA:		; Deja el hueco de la ficha a espacios y escribe encima
	ld hl,07c17h		;6f1a   ; 0x7C17: 24 columnas por 10 filas, el hueco de la ficha
	ld d,h			;6f1d
	ld e,l			;6f1e
	inc de			;6f1f
	ld bc,000d7h		;6f20
	ld (hl),020h		;6f23   ; 0xD7+1 = 216 bytes a espacios
	ldir		;6f25
	ld a,(MIRA_UNA_UNIDAD+1)		;6f27   ; El numero de unidad que dejo 0x6EAC en su operando
	ld l,a			;6f2a
	exx			;6f2b
	cp 018h		;6f2c   ; De la 0x18 para arriba no hay nombre en la lista
	jr nc,FORMACION_SIN_NOMBRE		;6f2e
	ld e,a			;6f30
	ex af,af'			;6f31
	call BUSCA_EL_NOMBRE		;6f32   ; 0x6981 deja HL en el nombre
	ld de,07c18h		;6f35   ; El nombre va en la primera fila de la ventana
COPIA_EL_NOMBRE_A_LA_FICHA:		; Hasta el 0xB7 que lo separa del siguiente
	ld a,(hl)			;6f38
	cp 0b7h		;6f39   ; 0xB7 cierra el nombre
	jr z,MARCA_AL_PORTADOR		;6f3b
	ld (de),a			;6f3d
	inc de			;6f3e
	inc hl			;6f3f
	jr COPIA_EL_NOMBRE_A_LA_FICHA		;6f40
FORMACION_SIN_NOMBRE:		; Sin nombre se pone "Formacion de", el numero y la raza
	ex af,af'			;6f42
	ld hl,07d84h		;6f43   ; 0x7D84 es "Formacion de"
	ld de,07c17h		;6f46
	call COPIA_TEXTO		;6f49
	ld h,0bdh		;6f4c   ; El tipo, del nibble bajo de 0xBD00+n
	ld a,(MIRA_UNA_UNIDAD+1)		;6f4e
	ld l,a			;6f51
	ld a,(hl)			;6f52
	and 00fh		;6f53
	exx			;6f55
	ld b,a			;6f56
	ld hl,07d06h		;6f57   ; 0x7D06: los nombres de raza en plural
	call SALTA_B_TEXTOS		;6f5a
	ld de,07c28h		;6f5d
	call COPIA_TEXTO		;6f60
	exx			;6f63
	ld h,0c5h		;6f64   ; 0xC500+n: cuantos son, en tres cifras
	ld a,(hl)			;6f66
	exx			;6f67
	ld hl,07c24h		;6f68
	call ESCRIBE_A_EN_TRES_CIFRAS		;6f6b
MARCA_AL_PORTADOR:		; Bit 4 de 0xBD00+n: esta unidad lleva el Anillo
	exx			;6f6e
	ld h,0bdh		;6f6f
	ld a,(hl)			;6f71
	exx			;6f72
	and 010h		;6f73   ; Bit 4: el mismo que busca 0x733E
	jr z,RELLENA_EL_DESTINO		;6f75
	ld a,05fh		;6f77
	ld (07c46h),a		;6f79   ; 0x7C46 es la ultima columna de la segunda fila de la ficha
RELLENA_EL_DESTINO:		; Segunda y tercera fila: a quien sigue y a donde va
	call DESCRIBE_EL_DESTINO		;6f7c   ; 0x6DE7 escribe a quien o a que persigue
	ld bc,00008h		;6f7f
	ld hl,07c01h		;6f82   ; "Destino:" al principio de la tercera fila
	ld de,07c47h		;6f85
	ldir		;6f88
	ld a,(MIRA_UNA_UNIDAD+1)		;6f8a
	call BUSCA_EL_DESTINO		;6f8d   ; 0x6956 devuelve en DE la casilla de destino
	push de			;6f90
	ld h,d			;6f91
	ld l,e			;6f92
	call BUSCA_EL_SITIO		;6f93   ; 0x6E50 mira si esa casilla tiene nombre de sitio
	jr c,DESTINO_SIN_NOMBRE		;6f96
	inc de			;6f98
	ld a,(de)			;6f99
	and 00fh		;6f9a   ; Nibble bajo del primer byte: cuantas lineas ocupa el cartel
	ld c,a			;6f9c
	ld a,(de)			;6f9d
	call NIBBLE_ALTO		;6f9e   ; Nibble alto: cuantas columnas
	ld b,a			;6fa1
	ld hl,07c50h		;6fa2
	inc de			;6fa5
UNA_LINEA_DEL_CARTEL:		; Copia el nombre del sitio al hueco del destino
	ex af,af'			;6fa6
COPIA_HASTA_EL_ESPACIO:		; Un espacio corta la linea; si no, se copian todas las columnas
	ld a,(de)			;6fa7
	ld (hl),a			;6fa8
	inc hl			;6fa9
	inc de			;6faa
	cp 020h		;6fab   ; Un espacio corta la linea del cartel
	jr z,SALTA_LO_QUE_SOBRA		;6fad
	djnz COPIA_HASTA_EL_ESPACIO		;6faf
	ld (hl),020h		;6fb1
	inc hl			;6fb3
	jr SIGUIENTE_LINEA_DEL_CARTEL		;6fb4
SALTA_LO_QUE_SOBRA:		; Lo que quede de linea en el cartel se salta
	inc de			;6fb6
	djnz SALTA_LO_QUE_SOBRA		;6fb7
	dec de			;6fb9
SIGUIENTE_LINEA_DEL_CARTEL:		; Una linea menos del cartel
	ex af,af'			;6fba
	ld b,a			;6fbb
	dec c			;6fbc   ; Una linea menos de las que mide el cartel
	jr nz,UNA_LINEA_DEL_CARTEL		;6fbd
	pop de			;6fbf
	jr LAS_SEIS_CUALIDADES		;6fc0
DESTINO_SIN_NOMBRE:		; Sin sitio con nombre, se escriben las coordenadas
	pop de			;6fc2
	ld a,d			;6fc3
	ld hl,07c50h		;6fc4   ; 0x7C50 es donde va el destino, detras de "Destino:"
	call ESCRIBE_99_MENOS_A		;6fc7   ; 0x710F escribe 99 menos la fila: la coordenada crece hacia el norte
	ld (hl),05eh		;6fca   ; Los tres caracteres del remate: 0x5E, N y la coma
	inc hl			;6fcc
	ld (hl),04eh		;6fcd
	inc hl			;6fcf
	ld (hl),02ch		;6fd0
	inc hl			;6fd2
	ld a,e			;6fd3
	call ESCRIBE_A_EN_TRES_CIFRAS		;6fd4   ; Y la columna, en tres cifras, con 0x5E y E detras
	ld (hl),05eh		;6fd7
	inc hl			;6fd9
	ld (hl),045h		;6fda
LAS_SEIS_CUALIDADES:		; Escribe las seis cualidades de la unidad, cada una con su adverbio
	ld h,0c0h		;6fdc   ; 0xC000+n, nibble bajo
	ld a,(MIRA_UNA_UNIDAD+1)		;6fde
	ld l,a			;6fe1
	ld a,(hl)			;6fe2
	exx			;6fe3
	and 00fh		;6fe4
	call REPARTE_EN_OCHO		;6fe6   ; 0x6E88 elige uno de los siete adverbios segun lo alto que sea
	ld de,07ca7h		;6fe9   ; 0x7CA7 es donde va esa cualidad dentro de la ficha
	call COPIA_SI_NO_ESTA_VACIO		;6fec
	ld hl,07defh		;6fef   ; 0x7DEF: el adjetivo que acompana, "Valioso"
	call COPIA_TEXTO		;6ff2
	ld a,02ch		;6ff5   ; Coma detras
	ld (de),a			;6ff7
	exx			;6ff8
	call NIBBLE_ALTO_DE_HL		;6ff9   ; 0xC000+n, nibble alto
	exx			;6ffc
	call REPARTE_EN_OCHO		;6ffd
	ld de,07c8fh		;7000
	call COPIA_SI_NO_ESTA_VACIO		;7003
	ld hl,07de6h		;7006   ; 0x7DE6: "Habil"
	call COPIA_TEXTO		;7009
	ld a,02ch		;700c
	ld (de),a			;700e
	exx			;700f
	inc h			;7010   ; 0xC100+n, nibble bajo
	ld a,(hl)			;7011
	and 00fh		;7012
	exx			;7014
	call REPARTE_EN_OCHO		;7015
	ld de,07cbfh		;7018
	call COPIA_SI_NO_ESTA_VACIO		;701b
	ld hl,07df7h		;701e   ; 0x7DF7: "Duro"
	call COPIA_SI_NO_ESTA_VACIO		;7021
	ld a,02ch		;7024
	ld (de),a			;7026
	exx			;7027
	call NIBBLE_ALTO_DE_HL		;7028   ; 0xC100+n, nibble alto
	exx			;702b
	call REPARTE_EN_OCHO		;702c
	ld de,07cd7h		;702f
	call COPIA_SI_NO_ESTA_VACIO		;7032
	ld hl,07dfch		;7035   ; 0x7DFC: "Bravo"
	call COPIA_TEXTO		;7038
	ld a,02ch		;703b
	ld (de),a			;703d
	exx			;703e
	inc h			;703f   ; 0xC200+n entero, el contador que gasta al andar
	ld a,(hl)			;7040
	exx			;7041
	call REPARTE_EN_OCHO_GORDO		;7042   ; Byte entero: se reparte en ocho tramos de 32
	ld de,07c5fh		;7045
	call COPIA_SI_NO_ESTA_VACIO		;7048
	ld hl,07dd3h		;704b   ; 0x7DD3: "Energico"
	call COPIA_TEXTO		;704e
	ld a,02ch		;7051
	ld (de),a			;7053
	exx			;7054
	inc h			;7055   ; 0xC300+n entero, el contador que sube un mes si y otro tambien
	ld a,(hl)			;7056
	exx			;7057
	call REPARTE_EN_OCHO_GORDO		;7058
	ld de,07c77h		;705b
	call COPIA_SI_NO_ESTA_VACIO		;705e
	ld hl,07ddch		;7061   ; 0x7DDC: "Decidido"
	call COPIA_TEXTO		;7064
	ld a,02ch		;7067
	ld (de),a			;7069
	exx			;706a
	ld h,0bdh		;706b   ; Los dos bits altos de 0xBD00+n: de que bando es
	ld a,(hl)			;706d
	rlca			;706e
	rlca			;706f
	and 003h		;7070
	ld b,a			;7072
	ld hl,07d6ah		;7073   ; 0x7D6A: los cuatro carteles de bando
	call SALTA_B_TEXTOS		;7076
	ld de,07cf9h		;7079   ; 0x7CF9 es la ultima fila de la ficha
	call COPIA_TEXTO		;707c
	ld a,020h		;707f
	ex de,hl			;7081
RELLENA_CON_ESPACIOS:		; Deja a espacios lo que quede de linea
	cp (hl)			;7082
	ld (hl),a			;7083
	inc hl			;7084
	jr nz,RELLENA_CON_ESPACIOS		;7085
	ld bc,0180ah		;7087   ; 24 columnas por 10 filas
	ld hl,05fbdh		;708a   ; 0x5FBD es la fila 13, columna 3 de la pantalla de caracteres
PINTA_LA_VENTANA:		; Dibuja el marco y mete dentro el texto que empieza en 0x7C17
	ld de,07c17h		;708d
	call DIBUJA_UNA_VENTANA		;7090
	pop hl			;7093
	ret			;7094
NIBBLE_ALTO_DE_HL:		; Devuelve en A el nibble alto del byte al que apunta HL
	ld a,(hl)			;7095
NIBBLE_ALTO:		; Baja el nibble alto de A a la parte de abajo
	rrca			;7096
	rrca			;7097
	rrca			;7098
	rrca			;7099
	and 00fh		;709a   ; Solo el nibble que se acaba de bajar
	ret			;709c
VENTANA_DE_DESTINO:		; Escribe la casilla de destino en su ventana de 11 por 2
	push hl			;709d
	ld a,h			;709e   ; Sin los bits 7, que son banderas de rodeo
	and 07fh		;709f
	push af			;70a1
	ld a,l			;70a2
	and 07fh		;70a3
	ld hl,07c12h		;70a5   ; 0x7C12: los tres digitos de la columna
	call ESCRIBE_A_EN_TRES_CIFRAS		;70a8
	ld hl,07c0ch		;70ab   ; 0x7C0C: los tres digitos de la fila
	pop af			;70ae
	call ESCRIBE_99_MENOS_A		;70af   ; 0x710F escribe 99 menos la fila
	ld de,07c01h		;70b2   ; 0x7C01 es "Destino:   " y debajo "###^N,###^E"
	jr VENTANA_ARRIBA_A_LA_IZQUIERDA		;70b5
VENTANA_DE_POSICION:		; Escribe la posicion del cursor en su ventana de 11 por 2
	push hl			;70b7
	ld a,h			;70b8
	push af			;70b9
	ld a,l			;70ba
	ld hl,07bfch		;70bb   ; 0x7BFC: los tres digitos de la columna
	call ESCRIBE_A_EN_TRES_CIFRAS		;70be
	ld hl,07bf6h		;70c1   ; 0x7BF6: los tres digitos de la fila
	pop af			;70c4
	call ESCRIBE_99_MENOS_A		;70c5
	ld de,07bebh		;70c8   ; 0x7BEB es " Posicion: " y debajo "###^N,###^E"
VENTANA_ARRIBA_A_LA_IZQUIERDA:		; Las dos ventanas van a la fila 0, columna 0, y miden 11 por 2
	ld hl,05e00h		;70cb   ; 0x5E00 es la esquina de arriba a la izquierda de la pantalla de caracteres
	ld bc,00b02h		;70ce   ; Once columnas de ancho por dos filas de alto
	call DIBUJA_UNA_VENTANA		;70d1
	pop hl			;70d4
	ret			;70d5
DIBUJA_UNA_VENTANA:		; Marco de B columnas por C filas en (HL), con el texto de (DE) dentro
	ld (hl),0e7h		;70d6   ; 0xE7 es la esquina de arriba a la izquierda
	inc hl			;70d8
	push bc			;70d9
	ld a,0e8h		;70da   ; 0xE8 es el borde de arriba, repetido B veces
BORDE_DE_ARRIBA:		; Tantos como columnas tenga la ventana
	ld (hl),a			;70dc
	inc hl			;70dd
	djnz BORDE_DE_ARRIBA		;70de
	ld (hl),0e9h		;70e0   ; 0xE9 cierra la fila de arriba
	pop bc			;70e2
	call SIGUIENTE_FILA_DE_TEXTO		;70e3   ; 0x7106 baja a la fila siguiente de la pantalla de caracteres
UNA_FILA_DE_LA_VENTANA:		; 0xEA a la izquierda, el texto y 0xEB a la derecha
	ld (hl),0eah		;70e6
	inc hl			;70e8
	push bc			;70e9
COPIA_LA_FILA:		; B caracteres de la ficha
	ld a,(de)			;70ea
	inc de			;70eb
	ld (hl),a			;70ec
	inc hl			;70ed
	djnz COPIA_LA_FILA		;70ee
	ld (hl),0ebh		;70f0   ; 0xEB cierra la fila por la derecha
	pop bc			;70f2
	call SIGUIENTE_FILA_DE_TEXTO		;70f3
	dec c			;70f6   ; Una fila menos de las que mide la ventana
	jp nz,UNA_FILA_DE_LA_VENTANA		;70f7
	ld (hl),0ech		;70fa   ; 0xEC es la esquina de abajo a la izquierda
	inc hl			;70fc
	ld a,0edh		;70fd   ; 0xED es el borde de abajo
BORDE_DE_ABAJO:		; Y 0xEE cierra la ventana por la esquina de abajo
	ld (hl),a			;70ff
	inc hl			;7100
	djnz BORDE_DE_ABAJO		;7101
	ld (hl),0eeh		;7103
	ret			;7105
SIGUIENTE_FILA_DE_TEXTO:		; Suma 0x21 - B: la fila de la pantalla de caracteres mide 34
	ld a,021h		;7106   ; 33 menos el ancho, contando desde la esquina derecha, son 34 por fila
	sub b			;7108
	add a,l			;7109
	ld l,a			;710a
	adc a,h			;710b
	sub l			;710c
	ld h,a			;710d
	ret			;710e
ESCRIBE_99_MENOS_A:		; Las filas del mapa se ensenan al reves: 99 menos la fila
	ld c,a			;710f
	ld a,063h		;7110
	sub c			;7112
ESCRIBE_A_EN_TRES_CIFRAS:		; Centenas, decenas y unidades de A en (HL)
	ld c,064h		;7113   ; Cien
	call UNA_CIFRA		;7115
	ld c,00ah		;7118   ; Diez
	call UNA_CIFRA		;711a
	ld c,001h		;711d   ; Uno
UNA_CIFRA:		; 0x2F es el "0" menos uno: el inc de 0x7121 lo deja en su sitio
	ld (hl),02fh		;711f
RESTA_HASTA_QUE_NO_QUEPA:		; Una vuelta por unidad de esa cifra
	inc (hl)			;7121
	sub c			;7122   ; Una vuelta por cada cien, cada diez o cada uno que quepa
	jp nc,RESTA_HASTA_QUE_NO_QUEPA		;7123
	add a,c			;7126
	inc hl			;7127
	ret			;7128

; ----------------------------------------------------------------------
; La vista de cerca. 0x7643 dibuja 16 por 13 celdas de mapa alrededor
; ----------------------------------------------------------------------
TAPA_LOS_BORDES:		; Rellena de 0xD5 lo que se sale del mapa por los cuatro lados
	push hl			;7129
	ld a,l			;712a
	cp 007h		;712b   ; Columna por debajo de 7: por la izquierda se sale del mapa
	jr nc,MIRA_EL_BORDE_DERECHO		;712d
	ld a,007h		;712f   ; Dos caracteres por celda de mapa
	sub l			;7131
	add a,a			;7132
	ld c,a			;7133
	ld hl,05e00h		;7134   ; 0x5E00 es la esquina de la pantalla de caracteres
	call TAPA_UNA_COLUMNA		;7137
	jr TAPA_ARRIBA		;713a
MIRA_EL_BORDE_DERECHO:		; De la columna 0x78 para arriba tambien se sale
	cp 078h		;713c
	jr c,TAPA_ARRIBA		;713e
	sub 077h		;7140   ; Lo que sobra por la derecha, en caracteres
	add a,a			;7142
	ld c,a			;7143
	ld a,020h		;7144   ; Y se empieza a tapar 32 menos eso
	sub c			;7146
	add a,000h		;7147
	ld l,a			;7149
	adc a,05eh		;714a
	sub l			;714c
	ld h,a			;714d
	call TAPA_UNA_COLUMNA		;714e
TAPA_ARRIBA:		; Con la fila por debajo de 5 se tapan las filas de arriba
	pop hl			;7151
	ld a,h			;7152
	cp 005h		;7153   ; Fila por debajo de 5: se sale por arriba
	jr nc,TAPA_ABAJO		;7155
	ld a,005h		;7157   ; Dos caracteres por celda
	sub h			;7159
	add a,a			;715a
	ld c,a			;715b
	ld b,000h		;715c
	add a,a			;715e
	add a,a			;715f
	add a,a			;7160
	ld l,a			;7161
	ld h,b			;7162
	add hl,hl			;7163
	add hl,bc			;7164
	add hl,hl			;7165
	dec hl			;7166   ; Filas por 34, que es lo que mide una fila de la pantalla de caracteres
	ld c,l			;7167
	ld b,h			;7168
	ld hl,05e00h		;7169
	ld (hl),0d5h		;716c   ; 0xD5 es el caracter con el que se tapa lo que no es mapa
	ld d,h			;716e
	ld e,l			;716f
	inc de			;7170
	ldir		;7171
	ret			;7173
TAPA_ABAJO:		; Y de la fila 0x5C para abajo, las de abajo
	cp 05ch		;7174
	ret c			;7176   ; Por debajo de 0x5C no hay nada que tapar
	sub 05bh		;7177
	add a,a			;7179
	ld c,a			;717a
	ld b,000h		;717b
	add a,a			;717d
	add a,a			;717e
	add a,a			;717f
	ld l,a			;7180
	ld h,b			;7181
	add hl,hl			;7182
	add hl,bc			;7183
	add hl,hl			;7184
	ld c,l			;7185
	ld b,h			;7186
	ld hl,061b6h		;7187   ; Se tapa hacia atras desde 0x61B6, por debajo de la ultima fila que se ve
	ld d,h			;718a
	ld e,l			;718b
	dec de			;718c
	ld (hl),0d5h		;718d
	lddr		;718f   ; lddr: se rellena de abajo hacia arriba
	ret			;7191
TAPA_UNA_COLUMNA:		; C columnas enteras de 0xD5, de arriba abajo
	ld a,0d5h		;7192
	ld de,00022h		;7194   ; 34 bytes por fila de la pantalla de caracteres
L_7197:
	push hl			;7197
	ld b,01ah		;7198   ; Veintiseis filas: dos por cada celda de mapa de las trece
TAPA_DE_ARRIBA_ABAJO:		; Las 26 filas de la columna
	ld (hl),a			;719a
	add hl,de			;719b   ; 34 bytes: la fila de abajo de la pantalla de caracteres
	djnz TAPA_DE_ARRIBA_ABAJO		;719c
	pop hl			;719e
	inc hl			;719f
	dec c			;71a0
	jr nz,L_7197		;71a1
	ret			;71a3
PINTA_LA_VISTA_DE_CERCA:		; Trozo de mapa alrededor de HL, con el cursor parpadeando en medio
	push hl			;71a4
	push hl			;71a5
	exx			;71a6
	ld hl,05e00h		;71a7   ; 850 bytes, o sea 25 filas de 34, todas a 0x80: el fondo de la vista
	ld de,05e01h		;71aa
	ld bc,00351h		;71ad
	ld (hl),080h		;71b0
	ldir		;71b2
	exx			;71b4
	inc h			;71b5
	call CELDA_DEL_MAPA		;71b6   ; 0x8108 pone en IX la direccion de mapa de la posicion
	ld de,0fd30h		;71b9   ; Menos 720 = 7 columnas a la izquierda y 6 filas arriba: la esquina del trozo
	add ix,de		;71bc
	call DIBUJA_EL_TROZO_DE_MAPA		;71be   ; 0x7643 dibuja las 16 por 13 celdas
	pop hl			;71c1
	call TAPA_LOS_BORDES		;71c2   ; Y se tapa lo que caiga fuera del mapa
	pop hl			;71c5
	ld a,000h		;71c6   ; El operando de 0x71C7 va cambiando de 0 a 1: el cursor parpadea
	xor 001h		;71c8
	ld (071c7h),a		;71ca
	ret nz			;71cd
	ld a,010h		;71ce   ; El operando de 0x71CF es el modo: 0x10 mirar, 0x12 elegir destino, 0x17 batalla
	ld iy,05f62h		;71d0   ; 0x5F62 es la fila 10, columna 14: el centro de la pantalla
	add a,a			;71d4
	add a,a			;71d5
	add a,0b5h		;71d6   ; 0x77B5 + modo*4: los cuatro caracteres del cursor
	ld e,a			;71d8
	adc a,077h		;71d9
	sub e			;71db
	ld d,a			;71dc
	ld a,(de)			;71dd
	ld (iy+000h),a		;71de
	inc de			;71e1
	ld a,(de)			;71e2
	ld (iy+001h),a		;71e3
	inc de			;71e6
	ld a,(de)			;71e7
	ld (iy+022h),a		;71e8   ; 0x22 = 34 es la fila de abajo de la pantalla de caracteres
	inc de			;71eb
	ld a,(de)			;71ec
	ld (iy+023h),a		;71ed
	ret			;71f0
ENTRA_EN_LA_VISTA:		; Espera a soltar el disparo y entra en modo mirar
	call ESPERA_A_SOLTAR_FUEGO		;71f1
MODO_MIRAR:		; El modo 0x10 es mirar por el mapa
	ld a,010h		;71f4
	ld (071cfh),a		;71f6
BUCLE_DE_LA_VISTA:		; Repinta, lee el mando y despacha lo que se pulse
	call PINTA_LA_VISTA_DE_CERCA		;71f9
	ld a,(071cfh)		;71fc   ; En modo mirar se ensena la posicion; en los otros, la ficha y el destino
	cp 010h		;71ff
	jr z,VENTANA_DE_MIRAR		;7201
	call FICHA_DE_LA_UNIDAD		;7203
	call VENTANA_DE_DESTINO		;7206
	jr LEE_EL_MANDO_DE_LA_VISTA		;7209
VENTANA_DE_MIRAR:		; Ensena la posicion y, si hay unidad debajo, su ficha
	call VENTANA_DE_POSICION		;720b
	call BUSCA_UNIDAD_ADELANTE		;720e   ; 0x6EA6 busca una unidad en esta casilla
	call c,FICHA_DE_LA_UNIDAD		;7211
LEE_EL_MANDO_DE_LA_VISTA:		; Pinta la pantalla y reparte lo que se pulse
	call VENTANA_DEL_SITIO		;7214   ; El cartel del sitio, si la casilla tiene nombre
	push hl			;7217
	call PANTALLA_DE_CARACTERES_A_LA_ZX		;7218   ; 0x75A5 pasa la pantalla de caracteres al bitmap del Spectrum
	pop hl			;721b
	call 0066dh		;721c
	bit 6,a		;721f   ; Bit 6 es la tecla R: el menu de a quien se le pasa el Anillo
	call nz,MENU_DE_ENTREGA		;7221
	push af			;7224
	call MUEVE_POR_EL_MAPA		;7225   ; 0x734B mueve el cursor por el mapa con las direcciones
	pop af			;7228
	bit 4,a		;7229   ; Sin disparo, otra vuelta
	jr z,BUCLE_DE_LA_VISTA		;722b
	ld a,(071cfh)		;722d
	cp 010h		;7230
	jp nz,DA_LA_ORDEN		;7232   ; En modo elegir destino, el disparo confirma
	call BUSCA_UNIDAD_ADELANTE		;7235   ; Sin unidad debajo del cursor no hay ordenes que dar
	ret nc			;7238
	call ELIGE_ENTRE_LAS_DE_LA_CASILLA		;7239   ; 0x7751 deja elegir entre las unidades que compartan casilla
	jr c,BUCLE_DE_LA_VISTA		;723c
	ld a,000h		;723e
	or a			;7240
	jp nz,MODO_MIRAR		;7241
	push hl			;7244
	ld hl,07e02h		;7245   ; 0x7E02: "Vuelve / Elige destino / Elige Union / Elige camino"
	call LISTA_DE_DOS_FILAS		;7248
	push af			;724b
	call BORRA_PANTALLA_NEGRA		;724c
	pop af			;724f
	pop hl			;7250
	or a			;7251
	jp z,MODO_MIRAR		;7252   ; La primera opcion es Vuelve: no se hace nada
	dec a			;7255
	jr nz,GUARDA_LA_ORDEN		;7256
	push af			;7258
	push hl			;7259
	ld hl,07e38h		;725a   ; 0x7E38: "Individual / Todos", que decide a quien afecta la orden
	call LISTA_DE_DOS_FILAS		;725d
	ld (072b4h),a		;7260   ; La respuesta al operando de 0x72B4
	call BORRA_PANTALLA_NEGRA		;7263
	pop hl			;7266
	ld (07282h),hl		;7267   ; La casilla se guarda en el operando de 0x7282
	pop af			;726a
GUARDA_LA_ORDEN:		; Apunta la orden elegida y pasa al modo de elegir destino
	ld (072afh),a		;726b   ; El numero de orden, al operando de 0x72AF
	ld a,012h		;726e   ; Modo 0x12: ahora se elige a donde
	ld (071cfh),a		;7270
	push hl			;7273
	call CELDA_DEL_MAPA		;7274   ; Bit 6 del byte de mapa: la casilla de partida queda marcada
	ld (QUITA_LA_MARCA+1),hl		;7277
	set 6,(hl)		;727a
	pop hl			;727c
	jp BUCLE_DE_LA_VISTA		;727d
ORDEN_PARA_TODOS:		; La misma orden a todas las unidades que haya en la casilla
	exx			;7280
	ld hl,00000h		;7281   ; La casilla que guardo 0x7267
	call BUSCA_UNIDAD_ADELANTE		;7284
	ld (072a0h),a		;7287   ; La primera unidad de la casilla, al operando de 0x729F
UNA_UNIDAD_MAS:		; Recorre las unidades de la casilla y a todas les pone el mismo destino
	inc a			;728a
	ld (MIRA_UNA_UNIDAD+1),a		;728b   ; La busqueda sigue desde el numero siguiente
	call BUSCA_UNIDAD_ADELANTE		;728e
	exx			;7291
	ld l,a			;7292
	res 7,(hl)		;7293   ; Fuera los bits 7 de rodeo
	inc h			;7295
	res 7,(hl)		;7296
	inc h			;7298
	ld (hl),e			;7299   ; Destino nuevo en 0xBB00 y 0xBC00
	inc h			;729a
	ld (hl),d			;729b
	ld h,0b9h		;729c
	exx			;729e
	cp 000h		;729f   ; Hasta volver a la primera
	jr nz,UNA_UNIDAD_MAS		;72a1
	exx			;72a3
	jr QUITA_LA_MARCA		;72a4
DA_LA_ORDEN:		; Con el destino ya elegido, se apunta en la unidad
	call ESPERA_A_SOLTAR_FUEGO		;72a6
	ld d,h			;72a9
	ld e,l			;72aa
	ld hl,(MIRA_UNA_UNIDAD+1)		;72ab   ; El numero de unidad esta en el operando de 0x6EAD
	ld a,000h		;72ae   ; El operando de 0x72AF es la orden: 0 destino, 1 union, 2 camino
	or a			;72b0
	jr nz,ORDEN_DE_SEGUIR		;72b1
	ld a,000h		;72b3   ; El operando de 0x72B4 es si la orden vale para todos
	or a			;72b5
	jr nz,ORDEN_PARA_TODOS		;72b6
	res 7,(hl)		;72b8   ; Fuera los bits 7 de rodeo
	inc h			;72ba
	res 7,(hl)		;72bb
	inc h			;72bd
	ld (hl),e			;72be   ; Destino: columna en 0xBB00+n y fila en 0xBC00+n
	inc h			;72bf
	ld (hl),d			;72c0
QUITA_LA_MARCA:		; Bit 6 fuera del byte de mapa y de vuelta al modo mirar
	ld hl,00000h		;72c1   ; La casilla que marco 0x727A
	res 6,(hl)		;72c4
	ex de,hl			;72c6
	jp MODO_MIRAR		;72c7
ORDEN_DE_SEGUIR:		; Union o camino: el destino es otra unidad, no una casilla
	push de			;72ca
	push hl			;72cb
	ex de,hl			;72cc
	call BUSCA_UNIDAD_ADELANTE		;72cd   ; Tiene que haber una unidad en la casilla elegida
	pop hl			;72d0
	pop de			;72d1
	jp nc,QUITA_LA_MARCA		;72d2
	push de			;72d5
	push hl			;72d6
	ex de,hl			;72d7
	call ELIGE_UNIDAD_CON_FICHA		;72d8   ; 0x773F deja elegir cual de las que hay
	pop hl			;72db
	pop de			;72dc
	jr c,QUITA_LA_MARCA		;72dd
	ld a,(MIRA_UNA_UNIDAD+1)		;72df
	res 7,(hl)		;72e2
	inc h			;72e4
	res 7,(hl)		;72e5
	inc h			;72e7
	ld (hl),a			;72e8   ; 0xBB00+n = el numero de la otra unidad
	inc h			;72e9
	ld (hl),0ffh		;72ea   ; 0xBC00+n = 0xFF: en vez de una casilla, se sigue a esa unidad
	ld a,(072afh)		;72ec   ; La orden 2 deja 0xFE en vez de 0xFF
	dec a			;72ef
	jr nz,QUITA_LA_MARCA		;72f0
	dec (hl)			;72f2
	jr QUITA_LA_MARCA		;72f3
MENU_DE_ENTREGA:		; Elige a quien se le entrega el Anillo y lo manda para alla
	push hl			;72f5
	xor a			;72f6
	ld (06be4h),a		;72f7   ; Un cero en 0x6BE4 corta la lista justo antes de Gollum
	call BUSCA_AL_PORTADOR		;72fa   ; 0x733E devuelve quien lleva el Anillo
	ld (07316h),a		;72fd   ; Su numero va al operando de 0x7316 y se marca en la lista
	inc a			;7300
	ld hl,06b3dh		;7301   ; 0x6B3D: 21 nombres de 9 columnas, con Vuelve delante
	call LISTA_DE_UNA_FILA		;7304
	push af			;7307
	ld hl,06be4h		;7308   ; El 0xB7 vuelve a su sitio: la lista queda entera otra vez
	ld (hl),0b7h		;730b
	call BORRA_PANTALLA_NEGRA		;730d
	pop af			;7310
	pop hl			;7311
	or a			;7312
	ret z			;7313   ; Opcion 0, que es Vuelve: no se hace nada
	dec a			;7314
	cp 000h		;7315   ; Si es el mismo que ya lo lleva, tampoco
	ret z			;7317
	push hl			;7318
	ld h,0b9h		;7319
	ld c,a			;731b
	ld l,a			;731c
	ld a,(hl)			;731d   ; Si el elegido no esta en el mapa, no vale
	inc h			;731e
	or (hl)			;731f
	and 07fh		;7320
	jr z,L_733A		;7322
	ld a,(07316h)		;7324
	ld (06a4ch),a		;7327   ; El portador, al operando de 0x6A4C
	ld l,a			;732a
	dec h			;732b
	res 7,(hl)		;732c
	inc h			;732e
	res 7,(hl)		;732f
	inc h			;7331
	ld (hl),c			;7332   ; 0xBB00 del portador = la unidad elegida
	inc h			;7333
	ld a,0ffh		;7334   ; Y 0xBC00 = 0xFF: a por ella
	ld (hl),a			;7336
	ld (06a48h),a		;7337   ; Bandera encendida: 0x6A47 vigilara si se juntan
L_733A:
	pop hl			;733a
	jp ESPERA_A_SOLTAR_FUEGO		;733b
BUSCA_AL_PORTADOR:		; Devuelve en A la primera unidad con el bit 4 de 0xBD00
	ld hl,0bd00h		;733e
MIRA_EL_BIT_4:		; Bit 4 de 0xBD00+n: esa lleva el Anillo
	ld a,(hl)			;7341
	and 010h		;7342
	jr nz,L_7349		;7344
	inc l			;7346
	jr MIRA_EL_BIT_4		;7347
L_7349:
	ld a,l			;7349
	ret			;734a
MUEVE_POR_EL_MAPA:		; Mueve la posicion HL con el mando, sin salirse del mapa
	ld d,a			;734b   ; A entra con el byte de mandos de 0x066D
	ld e,000h		;734c
	ld bc,0809ch		;734e   ; 0x80 es el tope de columna (127) y 0x9C el de fila (99)
	ld a,h			;7351
	rr d		;7352   ; Bit 0: arriba
	sbc a,e			;7354   ; Restar con tope: en la fila 0 ya no sube
	adc a,e			;7355
	rr d		;7356   ; Bit 1: abajo
	adc a,c			;7358   ; Sumar con tope: la fila no pasa de 99
	sbc a,c			;7359
	ld h,a			;735a
	ld a,l			;735b
	rr d		;735c   ; Bit 2: izquierda
	sbc a,e			;735e
	adc a,e			;735f
	rr d		;7360   ; Bit 3: derecha, y la columna no pasa de 127
	adc a,b			;7362
	sbc a,b			;7363
	ld l,a			;7364
	ret			;7365
VECINOS_IGUALES:		; Devuelve en C un bit por cada vecino del mismo terreno
	ld c,000h		;7366
ANADE_VECINOS:		; Anade a C los vecinos que sean del terreno D
	ld e,00fh		;7368
	ld a,(ix-067h)		;736a   ; -103 en el mapa: la celda de arriba a la izquierda
	and e			;736d   ; Solo el nibble bajo: la clase de terreno
	cp d			;736e
	jr nz,L_7373		;736f
	set 7,c		;7371
L_7373:
	ld a,(ix-001h)		;7373   ; -1: la de arriba
	and e			;7376
	cp d			;7377
	jr nz,L_737C		;7378
	set 6,c		;737a
L_737C:
	ld a,(ix+065h)		;737c   ; +101: arriba a la derecha
	and e			;737f
	cp d			;7380
	jr nz,L_7385		;7381
	set 5,c		;7383
L_7385:
	ld a,(ix-066h)		;7385   ; -102: la de la izquierda
	and e			;7388
	cp d			;7389
	jr nz,L_738E		;738a
	set 4,c		;738c
L_738E:
	ld a,(ix+066h)		;738e   ; +102: la de la derecha
	and e			;7391
	cp d			;7392
	jr nz,L_7397		;7393
	set 3,c		;7395
L_7397:
	ld a,(ix-065h)		;7397   ; -101: abajo a la izquierda
	and e			;739a
	cp d			;739b
	jr nz,L_73A0		;739c
	set 2,c		;739e
L_73A0:
	ld a,(ix+001h)		;73a0   ; +1: la de abajo
	and e			;73a3
	cp d			;73a4
	jr nz,L_73A9		;73a5
	set 1,c		;73a7
L_73A9:
	ld a,(ix+067h)		;73a9   ; +103: abajo a la derecha
	and e			;73ac
	cp d			;73ad
	jr nz,L_73B1		;73ae
	inc c			;73b0
L_73B1:
	ld a,c			;73b1
	ret			;73b2
SIN_DIBUJO:		; Si los vecinos no cambian nada, las cuatro casillas quedan a 0x81
	and 05ah		;73b3   ; 0x5A deja solo los cuatro vecinos en cruz
	cp c			;73b5
	ld c,a			;73b6
	jr nz,L_73D2		;73b7
	ld (iy+000h),081h		;73b9   ; 0x81 es el caracter de relleno de esa celda
	ld (iy+001h),081h		;73bd
	ld (iy+022h),081h		;73c1
	ld (iy+023h),081h		;73c5
	ret			;73c9
ELIGE_EL_DIBUJO:		; Busca en la tabla de HL el dibujo que le toca a esta combinacion de vecinos
	ld a,c			;73ca
	ld (L_73D2+1),hl		;73cb   ; La tabla se guarda en el operando de 0x73D2
	ld (073f3h),de		;73ce   ; Y la base de los caracteres, en el operando de 0x73F3
L_73D2:
	ld hl,00000h		;73d2
UNA_ENTRADA_DE_LA_TABLA:		; Cada entrada trae su umbral y dos bytes de mascara
	cp (hl)			;73d5   ; Si el umbral es mayor que los vecinos, esta es la entrada
	jr c,SIN_DIBUJO		;73d6
	inc hl			;73d8
	ld d,(hl)			;73d9   ; Los dos bytes dicen cuales de las 16 casillas se pintan
	inc hl			;73da
	ld e,(hl)			;73db
	inc hl			;73dc
	jr z,PINTA_LAS_16_CASILLAS		;73dd
SALTA_LOS_BYTES_DE_LA_MASCARA:		; Un byte de dibujo por cada bit puesto
	srl d		;73df
	jr nc,L_73E4		;73e1
	inc hl			;73e3
L_73E4:
	jr nz,SALTA_LOS_BYTES_DE_LA_MASCARA		;73e4
SALTA_LOS_DEL_SEGUNDO_BYTE:		; Lo mismo con la segunda mitad
	srl e		;73e6
	jr nc,L_73EB		;73e8
	inc hl			;73ea
L_73EB:
	jr nz,SALTA_LOS_DEL_SEGUNDO_BYTE		;73eb
	jp UNA_ENTRADA_DE_LA_TABLA		;73ed
PINTA_LAS_16_CASILLAS:		; Estampa un cuadro de 4 por 4 caracteres alrededor de la celda
	ld a,e			;73f0
	ex af,af'			;73f1
	ld bc,00000h		;73f2   ; La base de los caracteres, puesta por 0x73CE
	ld e,c			;73f5
	rl d		;73f6   ; Bit a bit: cada uno es una de las 16 casillas del cuadro
	jr nc,CASILLA_2		;73f8
	ld a,(hl)			;73fa
	inc hl			;73fb
	add a,e			;73fc
	ld c,a			;73fd
	adc a,b			;73fe
	sub c			;73ff
	ld b,a			;7400
	ld a,(bc)			;7401
	ld (iy-023h),a		;7402   ; Fila de arriba, columna de la izquierda
CASILLA_2:		; Fila de arriba, misma columna
	rl d		;7405   ; Bit 2 de la mascara
	jr nc,CASILLA_3		;7407
	ld a,(hl)			;7409
	inc hl			;740a
	add a,e			;740b
	ld c,a			;740c
	adc a,b			;740d
	sub c			;740e
	ld b,a			;740f
	ld a,(bc)			;7410
	ld (iy-022h),a		;7411   ; -0x22 es una fila entera de 34 caracteres
CASILLA_3:		; Fila de arriba, columna siguiente
	rl d		;7414   ; Bit 3 de la mascara
	jr nc,CASILLA_4		;7416
	ld a,(hl)			;7418
	inc hl			;7419
	add a,e			;741a
	ld c,a			;741b
	adc a,b			;741c
	sub c			;741d
	ld b,a			;741e
	ld a,(bc)			;741f
	ld (iy-021h),a		;7420   ; -0x21: una fila arriba y una columna a la derecha
CASILLA_4:		; Fila de arriba, dos columnas a la derecha
	rl d		;7423   ; Bit 4 de la mascara
	jr nc,CASILLA_5		;7425
	ld a,(hl)			;7427
	inc hl			;7428
	add a,e			;7429
	ld c,a			;742a
	adc a,b			;742b
	sub c			;742c
	ld b,a			;742d
	ld a,(bc)			;742e
	ld (iy-020h),a		;742f   ; -0x20: una fila arriba y dos columnas
CASILLA_5:		; Misma fila, columna de la izquierda
	rl d		;7432   ; Bit 5 de la mascara
	jr nc,CASILLA_6		;7434
	ld a,(hl)			;7436
	inc hl			;7437
	add a,e			;7438
	ld c,a			;7439
	adc a,b			;743a
	sub c			;743b
	ld b,a			;743c
	ld a,(bc)			;743d
	ld (iy-001h),a		;743e   ; -1: la columna de al lado
CASILLA_6:		; La casilla de arriba a la izquierda de la celda
	rl d		;7441   ; Bit 6 de la mascara
	jr nc,CASILLA_7		;7443
	ld a,(hl)			;7445
	inc hl			;7446
	add a,e			;7447
	ld c,a			;7448
	adc a,b			;7449
	sub c			;744a
	ld b,a			;744b
	ld a,(bc)			;744c
	ld (iy+000h),a		;744d   ; Aqui esta IY: la esquina de la celda de mapa
CASILLA_7:		; La de arriba a la derecha de la celda
	rl d		;7450   ; Bit 7 de la mascara
	jr nc,CASILLA_8		;7452
	ld a,(hl)			;7454
	inc hl			;7455
	add a,e			;7456
	ld c,a			;7457
	adc a,b			;7458
	sub c			;7459
	ld b,a			;745a
	ld a,(bc)			;745b
	ld (iy+001h),a		;745c   ; +1: la segunda columna de la celda
CASILLA_8:		; Misma fila, dos columnas a la derecha
	rl d		;745f   ; Bit 8 de la mascara
	jr nc,CASILLA_9		;7461
	ld a,(hl)			;7463
	inc hl			;7464
	add a,e			;7465
	ld c,a			;7466
	adc a,b			;7467
	sub c			;7468
	ld b,a			;7469
	ld a,(bc)			;746a
	ld (iy+002h),a		;746b   ; +2: ya fuera de la celda
CASILLA_9:		; Segunda fila, columna de la izquierda
	ex af,af'			;746e   ; La segunda mitad de la mascara, que se habia guardado
	ld d,a			;746f
	rl d		;7470
	jr nc,CASILLA_10		;7472
	ld a,(hl)			;7474
	inc hl			;7475
	add a,e			;7476
	ld c,a			;7477
	adc a,b			;7478
	sub c			;7479
	ld b,a			;747a
	ld a,(bc)			;747b
	ld (iy+021h),a		;747c   ; +0x21: una fila abajo y una columna a la izquierda
CASILLA_10:		; La de abajo a la izquierda de la celda
	rl d		;747f   ; Bit 10 de la mascara
	jr nc,CASILLA_11		;7481
	ld a,(hl)			;7483
	inc hl			;7484
	add a,e			;7485
	ld c,a			;7486
	adc a,b			;7487
	sub c			;7488
	ld b,a			;7489
	ld a,(bc)			;748a
	ld (iy+022h),a		;748b   ; +0x22: la fila de abajo
CASILLA_11:		; La de abajo a la derecha de la celda
	rl d		;748e   ; Bit 11 de la mascara
	jr nc,CASILLA_12		;7490
	ld a,(hl)			;7492
	inc hl			;7493
	add a,e			;7494
	ld c,a			;7495
	adc a,b			;7496
	sub c			;7497
	ld b,a			;7498
	ld a,(bc)			;7499
	ld (iy+023h),a		;749a   ; +0x23: fila de abajo, segunda columna
CASILLA_12:		; Segunda fila, dos columnas a la derecha
	rl d		;749d   ; Bit 12 de la mascara
	jr nc,CASILLA_13		;749f
	ld a,(hl)			;74a1
	inc hl			;74a2
	add a,e			;74a3
	ld c,a			;74a4
	adc a,b			;74a5
	sub c			;74a6
	ld b,a			;74a7
	ld a,(bc)			;74a8
	ld (iy+024h),a		;74a9   ; +0x24: fila de abajo, tercera columna
CASILLA_13:		; Tercera fila, columna de la izquierda
	rl d		;74ac   ; Bit 13 de la mascara
	jr nc,CASILLA_14		;74ae
	ld a,(hl)			;74b0
	inc hl			;74b1
	add a,e			;74b2
	ld c,a			;74b3
	adc a,b			;74b4
	sub c			;74b5
	ld b,a			;74b6
	ld a,(bc)			;74b7
	ld (iy+043h),a		;74b8   ; +0x43: dos filas abajo
CASILLA_14:		; Tercera fila, primera columna de la celda
	rl d		;74bb   ; Bit 14 de la mascara
	jr nc,CASILLA_15		;74bd
	ld a,(hl)			;74bf
	inc hl			;74c0
	add a,e			;74c1
	ld c,a			;74c2
	adc a,b			;74c3
	sub c			;74c4
	ld b,a			;74c5
	ld a,(bc)			;74c6
	ld (iy+044h),a		;74c7   ; +0x44: dos filas abajo, misma columna
CASILLA_15:		; Tercera fila, segunda columna de la celda
	rl d		;74ca
	jr nc,CASILLA_16		;74cc
	ld a,(hl)			;74ce
	inc hl			;74cf
	add a,e			;74d0
	ld c,a			;74d1
	ld a,(bc)			;74d2
	ld (iy+045h),a		;74d3   ; +0x45
CASILLA_16:		; Y la ultima, abajo a la derecha del todo
	rl d		;74d6
	ret nc			;74d8
	ld a,(hl)			;74d9
	inc hl			;74da
	add a,e			;74db
	ld c,a			;74dc
	ld a,(bc)			;74dd
	ld (iy+046h),a		;74de   ; +0x46: la esquina de abajo a la derecha del cuadro
	ret			;74e1
SIGUIENTE_DE_LAS_TUYAS:		; Busca hacia arriba la siguiente unidad marcada con el bit 5
	ld a,01ch		;74e2   ; 0x1C es el opcode de inc e: se busca hacia adelante
	jr MONTA_LA_BUSQUEDA		;74e4
ANTERIOR_DE_LAS_TUYAS:		; Igual pero hacia atras
	ld a,01dh		;74e6   ; 0x1D es el opcode de dec e: se busca hacia atras
MONTA_LA_BUSQUEDA:		; El opcode se mete dentro de la instruccion de 0x74EE
	ld (BUSCA_UNA_TUYA),a		;74e8
	ld de,0bd00h		;74eb   ; Por donde se iba se guarda en el operando de 0x74EC
BUSCA_UNA_TUYA:		; Bit 5 de 0xBD00+n, y ni la 0x16, ni la 0x17, ni de la 0x78 para arriba
	inc e			;74ee
	ld a,(de)			;74ef
	bit 5,a		;74f0   ; Bit 5 de 0xBD00+n: unidad de las que se pueden mandar
	jr z,BUSCA_UNA_TUYA		;74f2
	ld a,e			;74f4
	ld (074ech),a		;74f5   ; Por donde se ha quedado la busqueda
	cp 078h		;74f8   ; De la 0x78 para arriba son del otro bando
	jr nc,BUSCA_UNA_TUYA		;74fa
	cp 016h		;74fc   ; La 0x16 tampoco es tuya
	jr z,BUSCA_UNA_TUYA		;74fe
	cp 017h		;7500   ; Ni la 0x17
	jr z,BUSCA_UNA_TUYA		;7502
APUNTA_LA_ELEGIDA:		; Su numero va al operando de 0x6EAD, que es la unidad de la ficha
	ld (MIRA_UNA_UNIDAD+1),a		;7504
	ret			;7507
SIGUIENTE_DEL_ENEMIGO:		; Lo mismo pero al reves: solo valen la 0x16, la 0x17 y de la 0x78 arriba
	ld a,01ch		;7508   ; 0x1C: inc e, hacia adelante
	jr MONTA_LA_OTRA_BUSQUEDA		;750a
ANTERIOR_DEL_ENEMIGO:		; 0x1D: dec e, hacia atras
	ld a,01dh		;750c
MONTA_LA_OTRA_BUSQUEDA:		; El opcode va dentro de la instruccion de 0x7514
	ld (BUSCA_UNA_DEL_ENEMIGO),a		;750e
	ld de,0bd00h		;7511
BUSCA_UNA_DEL_ENEMIGO:		; Solo se aceptan las que 0x74EE descarta
	inc e			;7514
	ld a,(de)			;7515
	bit 5,a		;7516   ; Bit 5 de 0xBD00+n
	jr z,BUSCA_UNA_DEL_ENEMIGO		;7518
	ld a,e			;751a
	ld (07512h),a		;751b
	cp 078h		;751e   ; De la 0x78 para arriba: esa vale
	jr nc,APUNTA_LA_ELEGIDA		;7520
	cp 016h		;7522   ; La 0x16 vale
	jr z,APUNTA_LA_ELEGIDA		;7524
	cp 017h		;7526   ; Y la 0x17 tambien; las demas, no
	jr nz,BUSCA_UNA_DEL_ENEMIGO		;7528
	jr APUNTA_LA_ELEGIDA		;752a
PANTALLA_DE_BATALLA:		; Modo 0x17: ensena las unidades una a una con el cartel de 0x77A0
	ld a,001h		;752c   ; El cursor de la vista arranca encendido
	ld (071c7h),a		;752e
	ld a,(071cfh)		;7531   ; El modo de antes se guarda en el operando de 0x7594
	ld (SALE_DE_LA_BATALLA+1),a		;7534
	ld a,017h		;7537   ; Modo 0x17
	ld (071cfh),a		;7539
	push hl			;753c
	call BORRA_PANTALLA_NEGRA		;753d
	pop hl			;7540
	call SIGUIENTE_DE_LAS_TUYAS		;7541   ; Se empieza por la primera unidad propia
	call ESPERA_A_SOLTAR_FUEGO		;7544
BUCLE_DE_BATALLA:		; Repinta el trozo de mapa, la posicion, la ficha y el cartel
	call PINTA_LA_VISTA_DE_CERCA		;7547
	call VENTANA_DE_POSICION		;754a
	call FICHA_SIN_MIRAR_EL_MODO		;754d
	call VENTANA_DEL_SITIO		;7550
	push hl			;7553
	ld de,077a0h		;7554   ; 0x77A0: "Comienza la Batalla" y compania
	ld hl,05e8ch		;7557   ; 0x5E8C es la fila 4, columna 4 de la pantalla de caracteres
	ld bc,01501h		;755a   ; Una ventana de 21 columnas por una fila
	call DIBUJA_UNA_VENTANA		;755d
	call PANTALLA_DE_CARACTERES_A_LA_ZX		;7560   ; Y a pantalla
	pop hl			;7563
MANDO_DE_LA_BATALLA:		; Con fuego o con la tecla 1 se sale; las direcciones cambian de unidad
	call 0066dh		;7564
	bit 4,a		;7567   ; Bit 4, disparo: se sale
	jr nz,SALE_DE_LA_BATALLA		;7569
	bit 5,a		;756b   ; Bit 5, tecla 1: tambien
	jr nz,SALE_DE_LA_BATALLA		;756d
	bit 0,a		;756f   ; Bit 0, arriba: la siguiente unidad propia
	jr z,BATALLA_ABAJO		;7571
	call SIGUIENTE_DE_LAS_TUYAS		;7573
	jr BUCLE_DE_BATALLA		;7576
BATALLA_ABAJO:		; Bit 1: la anterior de las tuyas
	bit 1,a		;7578
	jr z,BATALLA_IZQUIERDA		;757a
	call ANTERIOR_DE_LAS_TUYAS		;757c
	jr BUCLE_DE_BATALLA		;757f
BATALLA_IZQUIERDA:		; Bit 2: la anterior del enemigo
	bit 2,a		;7581
	jr z,BATALLA_DERECHA		;7583
	call ANTERIOR_DEL_ENEMIGO		;7585
	jr BUCLE_DE_BATALLA		;7588
BATALLA_DERECHA:		; Bit 3: la siguiente del enemigo
	bit 3,a		;758a
	jr z,MANDO_DE_LA_BATALLA		;758c
	call SIGUIENTE_DEL_ENEMIGO		;758e
	jr BUCLE_DE_BATALLA		;7591
SALE_DE_LA_BATALLA:		; Devuelve el modo que habia antes, guardado en su propio operando
	ld a,000h		;7593
	ld (071cfh),a		;7595
	ret			;7598
ESPERA_A_SOLTAR_FUEGO:		; No vuelve hasta que el disparo esta suelto
	push hl			;7599
	push af			;759a
DISPARO_TODAVIA_PULSADO:		; Bit 4 del byte de mandos
	call 0066dh		;759b
	bit 4,a		;759e   ; Bit 4: mientras siga pulsado, aqui se queda
	jr nz,DISPARO_TODAVIA_PULSADO		;75a0
	pop af			;75a2
	pop hl			;75a3
	ret			;75a4

; ----------------------------------------------------------------------
; La pantalla de caracteres de 0x5E00 mide 34 bytes por fila y 24
; ----------------------------------------------------------------------
PANTALLA_DE_CARACTERES_A_LA_ZX:		; Pinta las 24 filas de 32 caracteres en el bitmap del Spectrum y las sube a la VRAM
	ld hl,04000h		;75a5   ; 0x4000: el bitmap de la pantalla emulada
	exx			;75a8
	ld hl,05800h		;75a9   ; 0x5800: los atributos, en el juego alternativo de registros
	ld c,018h		;75ac   ; Veinticuatro filas
	ld de,05e00h		;75ae   ; 0x5E00: la pantalla de caracteres, encima del codigo de arranque
UNA_FILA_DE_CARACTERES:		; Treinta y dos columnas por fila
	ld b,020h		;75b1
UN_CARACTER:		; Bit 7: dibujo de nueve bytes en 0x9E00; si no, fuente normal
	ld a,(de)			;75b3
	inc de			;75b4
	exx			;75b5
	ld c,a			;75b6
	res 7,c		;75b7   ; El codigo sin el bit 7
	add a,a			;75b9
	jp nc,UN_CARACTER_NORMAL		;75ba   ; Sin bit 7 es un caracter de la fuente normal
	ld d,000h		;75bd
	add a,a			;75bf
	rl d		;75c0
	add a,a			;75c2
	rl d		;75c3
	add a,c			;75c5   ; DE = 0x9E00 + codigo*9: ocho lineas y un atributo
	ld e,a			;75c6
	ld a,09eh		;75c7
	adc a,d			;75c9
	ld d,a			;75ca
	ld c,h			;75cb
	ld a,(de)			;75cc   ; Las ocho lineas de pixel, cada una 256 bytes mas abajo
	ld (hl),a			;75cd
	inc de			;75ce
	inc h			;75cf
	ld a,(de)			;75d0
	ld (hl),a			;75d1
	inc de			;75d2
	inc h			;75d3
	ld a,(de)			;75d4
	ld (hl),a			;75d5
	inc de			;75d6
	inc h			;75d7
	ld a,(de)			;75d8
	ld (hl),a			;75d9
	inc de			;75da
	inc h			;75db
	ld a,(de)			;75dc
	ld (hl),a			;75dd
	inc de			;75de
	inc h			;75df
	ld a,(de)			;75e0
	ld (hl),a			;75e1
	inc de			;75e2
	inc h			;75e3
	ld a,(de)			;75e4
	ld (hl),a			;75e5
	inc de			;75e6
	inc h			;75e7
	ld a,(de)			;75e8
	ld (hl),a			;75e9
	inc de			;75ea
	ld a,(de)			;75eb   ; El noveno byte es el atributo de esta celda
EL_ATRIBUTO_DE_LA_CELDA:		; Lo escribe en 0x5800 y pasa a la columna siguiente
	exx			;75ec
	ld (hl),a			;75ed   ; Los atributos van en el juego alternativo, que apunta a 0x5800
	inc hl			;75ee
	exx			;75ef
	ld h,c			;75f0   ; Vuelve la parte alta del bitmap, que se habia guardado en C
	inc hl			;75f1
	ld a,l			;75f2   ; Al dar la vuelta el byte bajo hay que sumar 7 al alto: geometria del ZX
	or a			;75f3
	jr nz,SIGUIENTE_COLUMNA		;75f4
	ld a,h			;75f6
	add a,007h		;75f7
	ld h,a			;75f9
SIGUIENTE_COLUMNA:		; Treinta y dos por fila y dos bytes de mas al final
	exx			;75fa
	djnz UN_CARACTER		;75fb
	inc de			;75fd   ; Cada fila de la pantalla de caracteres mide 34, no 32
	inc de			;75fe
	dec c			;75ff
	jp nz,UNA_FILA_DE_CARACTERES		;7600
	ld de,00000h		;7603
	ld b,018h		;7606
SUBE_LA_PANTALLA:		; Las 24 filas al VDP, una a una, con sus colores
	push de			;7608
	push bc			;7609
	ld bc,00120h		;760a   ; B = 1 fila, C = 32 columnas
	call 0074eh		;760d   ; 0x074E (FILA_CON_COLOR_A_VRAM) sube dibujo y color
	pop bc			;7610
	pop de			;7611
	inc d			;7612
	djnz SUBE_LA_PANTALLA		;7613
	ret			;7615
UN_CARACTER_NORMAL:		; Fuente de 0xC800, ocho bytes, y atributo 0x78 para todos
	ld d,032h		;7616   ; DE = 0xC800 + codigo*8
	add a,a			;7618
	rl d		;7619
	add a,a			;761b
	rl d		;761c
	ld e,a			;761e
	ld c,h			;761f
	ld a,(de)			;7620   ; Las ocho lineas de la celda
	ld (hl),a			;7621
	inc e			;7622
	inc h			;7623
	ld a,(de)			;7624
	ld (hl),a			;7625
	inc e			;7626
	inc h			;7627
	ld a,(de)			;7628
	ld (hl),a			;7629
	inc e			;762a
	inc h			;762b
	ld a,(de)			;762c
	ld (hl),a			;762d
	inc e			;762e
	inc h			;762f
	ld a,(de)			;7630
	ld (hl),a			;7631
	inc e			;7632
	inc h			;7633
	ld a,(de)			;7634
	ld (hl),a			;7635
	inc e			;7636
	inc h			;7637
	ld a,(de)			;7638
	ld (hl),a			;7639
	inc e			;763a
	inc h			;763b
	ld a,(de)			;763c
	ld (hl),a			;763d
	ld a,078h		;763e   ; 0x78 es el atributo del texto normal
	jp EL_ATRIBUTO_DE_LA_CELDA		;7640   ; Y sale por el mismo sitio que los caracteres con dibujo propio
DIBUJA_EL_TROZO_DE_MAPA:		; Tres pasadas por las 16 por 13 celdas: terreno, encima y unidades
	ld (UNA_PASADA+2),ix		;7643   ; La esquina del trozo se guarda en el operando de 0x7656
	ld hl,DESPACHA_POR_TERRENO		;7647   ; Primera pasada: 0x7687, el terreno
	call UNA_PASADA		;764a
	ld hl,07714h		;764d   ; Segunda: 0x7714, lo que va encima del terreno
	call UNA_PASADA		;7650
	ld hl,07708h		;7653   ; Tercera: 0x7708, las unidades
UNA_PASADA:		; Recorre las 16 por 13 celdas llamando a la rutina que le digan
	ld ix,UNA_PASADA		;7656
	ld iy,05e00h		;765a   ; 0x5E00: la esquina de la pantalla de caracteres
	ld (UNA_CELDA+1),hl		;765e   ; La rutina de la pasada se mete dentro del call de 0x766C
	ld c,00dh		;7661   ; Trece filas de celdas
UNA_FILA_DE_CELDAS:		; Dieciseis celdas por fila; 102 bytes de mapa entre columnas
	ld b,010h		;7663
	ld de,00066h		;7665
L_7668:
	ld a,(ix+000h)		;7668
	exx			;766b
UNA_CELDA:		; Llama a la rutina de la pasada con el byte de mapa en A
	call UNA_CELDA		;766c   ; El operando es la rutina de esta pasada, puesta por 0x765E
	exx			;766f
	inc iy		;7670   ; Dos caracteres de ancho por celda
	inc iy		;7672
	add ix,de		;7674
	djnz L_7668		;7676
	ld de,0f9a1h		;7678   ; Menos 1631: dieciseis columnas atras y una fila abajo
	add ix,de		;767b
	ld de,00024h		;767d   ; Mas 36: dos filas de la pantalla de caracteres menos las 32 ya andadas
	add iy,de		;7680
	dec c			;7682
	jp nz,UNA_FILA_DE_CELDAS		;7683
	ret			;7686
DESPACHA_POR_TERRENO:		; El nibble bajo del byte de mapa elige el dibujo en la tabla de 0x7697
	add a,a			;7687   ; Indice por dos y solo el nibble bajo
	and 01eh		;7688
	ld hl,07697h		;768a   ; 0x7697: dieciseis palabras, una por clase de terreno
	add a,l			;768d
	ld l,a			;768e
	adc a,h			;768f
	sub l			;7690
	ld h,a			;7691
	ld e,(hl)			;7692
	inc hl			;7693
	ld d,(hl)			;7694
	push de			;7695   ; push de / ret: asi se salta a la rutina que toque
L_7696:
	ret			;7696

; ----------------------------------------------------------------------
; DATOS tabla_de_16_palabras_7697: Tabla de 16 palabras que 0x7687 indexa con
;   A*2 & 0x1E y despacha con push de / ret
;   0x7697..0x76b7  (32 bytes)
DATA_tabla_de_16_palabras_7697:
	defw 07696h	; 7697  -> L_7696
	defw 076b7h	; 7699  -> TERRENO_2
	defw 07696h	; 769b  -> L_7696
	defw 076c7h	; 769d  -> TERRENO_3
	defw 076e4h	; 769f  -> TERRENO_CON_VECINO_6
	defw 07696h	; 76a1  -> L_7696
	defw 076f0h	; 76a3  -> TERRENO_6
	defw 07696h	; 76a5  -> L_7696
	defw 07696h	; 76a7  -> L_7696
	defw 07696h	; 76a9  -> L_7696
	defw 07696h	; 76ab  -> L_7696
	defw 07696h	; 76ad  -> L_7696
	defw 07696h	; 76af  -> L_7696
	defw 07696h	; 76b1  -> L_7696
	defw 07696h	; 76b3  -> L_7696
	defw 07696h	; 76b5  -> L_7696

; ======================================================================
; CODIGO 0x76b7..0x77a0  (233 bytes)
; ======================================================================


TERRENO_2:		; Terreno 2: mira los vecinos y elige dibujo en 0x797D
	ld d,002h		;76b7   ; Terreno 2
	call VECINOS_IGUALES		;76b9
	cpl			;76bc   ; Al reves: aqui interesan los vecinos que NO son iguales
	ld c,a			;76bd
	ld hl,0797dh		;76be
	ld de,07819h		;76c1
	jp ELIGE_EL_DIBUJO		;76c4
TERRENO_3:		; Terreno 3, que ademas se pega a los terrenos 2, 4 y 5
	ld d,003h		;76c7   ; Vecinos del terreno 3
	call VECINOS_IGUALES		;76c9
	ld d,002h		;76cc
	call ANADE_VECINOS		;76ce   ; Los del 2 tambien cuentan
	ld d,004h		;76d1   ; Y los del 4
	call ANADE_VECINOS		;76d3
	ld d,005h		;76d6   ; Y los del 5
	call ANADE_VECINOS		;76d8
	ld hl,0784dh		;76db
	ld de,0782dh		;76de
	jp ELIGE_EL_DIBUJO		;76e1
TERRENO_CON_VECINO_6:		; Segun lo que haya a la izquierda, dibujo 0x14 o 0x13
	ld a,(ix-001h)		;76e4
	cp 006h		;76e7   ; La celda de arriba: si es del terreno 6, el otro dibujo
	ld a,014h		;76e9
	jr z,ESTAMPA_DOS_POR_DOS		;76eb
	dec a			;76ed
	jr ESTAMPA_DOS_POR_DOS		;76ee
TERRENO_6:		; Terreno 6, pegado al 4 y al 5
	ld d,006h		;76f0   ; Vecinos del terreno 6
	call VECINOS_IGUALES		;76f2
	ld d,004h		;76f5
	call ANADE_VECINOS		;76f7
	ld d,005h		;76fa
	call ANADE_VECINOS		;76fc
	ld hl,0784dh		;76ff   ; Tabla de dibujos del 6
	ld de,0783dh		;7702
	jp ELIGE_EL_DIBUJO		;7705
PINTA_LA_UNIDAD:		; Bit 7 del byte de mapa: ahi hay algo que ensenar
	or a			;7708   ; Sin el bit 7 no hay nada
	ret p			;7709
	bit 6,a		;770a   ; Bit 6: la casilla marcada por una orden en marcha
	ld a,011h		;770c
	jr nz,ESTAMPA_DOS_POR_DOS		;770e
	ld a,015h		;7710
	jr ESTAMPA_DOS_POR_DOS		;7712
PINTA_LO_DE_ENCIMA:		; El nibble bajo elige un cuadro de dos por dos en 0x77B5
	and 00fh		;7714
	ret z			;7716
ESTAMPA_DOS_POR_DOS:		; Cuatro caracteres desde 0x77B5 + indice*4; los ceros no se pintan
	add a,a			;7717
	add a,a			;7718
	add a,0b5h		;7719   ; 0x77B5: cuatro bytes por dibujo
	ld l,a			;771b
	adc a,077h		;771c
	sub l			;771e
	ld h,a			;771f
	ld a,(hl)			;7720
	or a			;7721
	jr z,SEGUNDO_CARACTER		;7722   ; Un cero deja ver lo que ya habia
	ld (iy+000h),a		;7724
SEGUNDO_CARACTER:		; El de arriba a la derecha
	inc hl			;7727
	ld a,(hl)			;7728
	or a			;7729
	jr z,TERCER_CARACTER		;772a
	ld (iy+001h),a		;772c
TERCER_CARACTER:		; El de abajo a la izquierda, 34 mas alla
	inc hl			;772f
	ld a,(hl)			;7730
	or a			;7731
	jr z,CUARTO_CARACTER		;7732
	ld (iy+022h),a		;7734
CUARTO_CARACTER:		; Y el de abajo a la derecha
	inc hl			;7737
	ld a,(hl)			;7738
	or a			;7739   ; Un cero deja ver lo que ya habia debajo
	ret z			;773a
	ld (iy+023h),a		;773b
	ret			;773e
ELIGE_UNIDAD_CON_FICHA:		; Como 0x7751, pero armando la ficha entera en cada cambio
	ld de,06f08h		;773f   ; 0x6F08 arma la ficha; el puntero va al operando de 0x7794
	ld (07794h),de		;7742
	call ELIGE_ENTRE_LAS_DE_LA_CASILLA		;7746
	ld de,06f0bh		;7749   ; Al salir se deja otra vez 0x6F0B, que mira el modo
	ld (07794h),de		;774c
	ret			;7750
ELIGE_ENTRE_LAS_DE_LA_CASILLA:		; Arriba y abajo pasan de una unidad a otra de la misma casilla
	xor a			;7751
	ld (0723fh),a		;7752   ; El operando de 0x723F dice si se ha llegado a cambiar algo
	call ESPERA_A_SOLTAR_FUEGO		;7755
MANDO_DE_LA_ELECCION:		; Fuego elige; la tecla 1 sale con acarreo
	call 0066dh		;7758
	bit 4,a		;775b   ; Bit 4: elegida
	jp nz,ESPERA_A_SOLTAR_FUEGO		;775d
	bit 5,a		;7760   ; Bit 5, tecla 1: se sale sin elegir
	jp z,PASA_A_LA_SIGUIENTE		;7762
	scf			;7765
	ret			;7766
PASA_A_LA_SIGUIENTE:		; Bit 0: la unidad siguiente de la casilla
	bit 0,a		;7767
	jr z,PASA_A_LA_ANTERIOR		;7769
	ld a,(06eadh)		;776b   ; El operando de 0x6EAD es la unidad de la ficha
	inc a			;776e
	ld (06eadh),a		;776f
	call BUSCA_UNIDAD_ADELANTE		;7772   ; 0x6EA6 busca hacia arriba
	jr REPINTA_LA_ELECCION		;7775
PASA_A_LA_ANTERIOR:		; Bit 1: la unidad anterior
	bit 1,a		;7777
	jr z,MANDO_DE_LA_ELECCION		;7779
	ld a,(06eadh)		;777b
	dec a			;777e
	ld (06eadh),a		;777f
	call BUSCA_UNIDAD_ATRAS		;7782   ; 0x6ED6 busca hacia abajo
REPINTA_LA_ELECCION:		; Vuelve a pintar mapa, posicion, ficha y cartel
	ld a,001h		;7785   ; Ya se ha cambiado de unidad al menos una vez
	ld (0723fh),a		;7787
	call PINTA_LA_VISTA_DE_CERCA		;778a   ; El trozo de mapa
	call VENTANA_DE_POSICION		;778d   ; La ventana de posicion
	call BUSCA_UNIDAD_ADELANTE		;7790
	call c,FICHA_DE_LA_UNIDAD		;7793   ; Solo si hay unidad en la casilla
	call VENTANA_DEL_SITIO		;7796
	push hl			;7799
	call PANTALLA_DE_CARACTERES_A_LA_ZX		;779a
	pop hl			;779d
	jr MANDO_DE_LA_ELECCION		;779e

; ----------------------------------------------------------------------
; DATOS textos_y_tablas_de_batalla: Textos de batalla ("Comienza la Batalla")
;   y tablas (0x7554, 0x76C1, 0x76DE, 0x7702, 0x76DB, 0x76BE las apuntan;
;   formato pendiente)
;   0x77a0..0x7e4f  (1711 bytes)
DATA_textos_y_tablas_de_batalla:
	defb 043h,06fh,06dh,069h,065h,06eh,07ah,061h,020h,06ch,061h,020h,042h,061h,074h,061h	; 77a0  Comienza la Bata
	defb 06ch,06ch,061h,02eh,02eh,000h,000h,000h,000h,000h,000h,000h,000h,081h,081h,081h	; 77b0  lla.............
	defb 081h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; 77c0  ................
	defb 000h,08ah,08bh,08ch,08dh,08eh,08fh,090h,091h,092h,093h,094h,095h,096h,097h,098h	; 77d0  ................
	defb 099h,09ah,09bh,09ch,09dh,09eh,09fh,0a0h,0a1h,0a2h,0a3h,0a4h,0a5h,0a6h,0a7h,08ch	; 77e0  ................
	defb 0a8h,0a9h,0aah,0abh,0ach,0e5h,0e6h,0e6h,0e5h,0e1h,0e2h,0e3h,0e4h,0e4h,0e3h,0e2h	; 77f0  ................
	defb 0e1h,0b3h,0b4h,0b5h,0b6h,0b7h,0b8h,0b9h,0bah,0d1h,0d2h,0d3h,0d4h,0d5h,0d6h,0d7h	; 7800  ................
	defb 0d8h,0d9h,0dah,0dbh,0dch,0ddh,0deh,0dfh,0e0h,086h,087h,088h,089h,0afh,0b0h,0b1h	; 7810  ................
	defb 0b2h,0c1h,0c2h,0c3h,0c4h,0c5h,0c6h,0c7h,0c8h,0c9h,0cah,0cbh,0cch,082h,083h,084h	; 7820  ................
	defb 085h,0bbh,0bch,0bdh,0beh,0bfh,0c0h,080h,080h,080h,080h,000h,000h,086h,087h,088h	; 7830  ................
	defb 089h,0adh,0aeh,0afh,0b0h,0b1h,0b2h,0cdh,0ceh,0cfh,0d0h,000h,000h,001h,006h,070h	; 7840  ...............p
	defb 000h,001h,002h,005h,001h,002h,006h,060h,000h,001h,007h,009h,004h,006h,064h,000h	; 7850  .......`......d.
	defb 001h,004h,003h,003h,005h,006h,074h,000h,001h,004h,005h,001h,003h,008h,006h,060h	; 7860  ......t........`
	defb 000h,008h,002h,006h,00ch,006h,064h,000h,008h,004h,006h,003h,010h,006h,060h,008h	; 7870  ......d.......`.
	defb 001h,006h,003h,011h,006h,070h,008h,001h,006h,005h,001h,018h,006h,060h,008h,008h	; 7880  .....p.......`..
	defb 006h,006h,01ah,006h,060h,008h,008h,00ch,00dh,020h,026h,060h,000h,000h,004h,002h	; 7890  ....`.... &`....
	defb 003h,021h,026h,070h,000h,000h,004h,002h,005h,001h,022h,026h,060h,000h,000h,004h	; 78a0  .!&p......"&`...
	defb 007h,009h,024h,026h,064h,000h,000h,004h,004h,003h,003h,025h,026h,074h,000h,000h	; 78b0  ..$&d......%&t..
	defb 004h,004h,005h,001h,003h,030h,026h,060h,000h,008h,004h,006h,003h,031h,026h,070h	; 78c0  .....0&`.....1&p
	defb 000h,008h,004h,006h,005h,001h,040h,006h,060h,007h,009h,002h,003h,041h,006h,070h	; 78d0  ......@.`....A.p
	defb 007h,009h,002h,005h,001h,042h,006h,060h,007h,009h,007h,009h,044h,006h,064h,007h	; 78e0  .....B.`....D.d.
	defb 009h,004h,003h,003h,045h,006h,074h,007h,009h,004h,005h,001h,003h,04ah,006h,060h	; 78f0  ....E.t......J.`
	defb 007h,00bh,007h,00dh,052h,006h,060h,00ah,009h,00ch,009h,058h,006h,060h,00ah,00bh	; 7900  ....R.`....X.`..
	defb 006h,006h,05ah,006h,060h,00ah,00bh,00ch,00dh,080h,00eh,060h,002h,005h,001h,002h	; 7910  ..Z.`......`....
	defb 003h,081h,00eh,070h,002h,005h,001h,002h,005h,001h,082h,00eh,060h,002h,005h,001h	; 7920  ...p........`...
	defb 007h,009h,084h,00eh,064h,002h,005h,001h,004h,003h,003h,085h,00eh,074h,002h,005h	; 7930  ....d........t..
	defb 001h,004h,005h,001h,003h,088h,00eh,060h,002h,005h,008h,002h,006h,08ch,00eh,064h	; 7940  .......`.......d
	defb 002h,005h,008h,004h,006h,003h,0a0h,02eh,060h,000h,002h,005h,004h,002h,003h,0a1h	; 7950  ........`.......
	defb 02eh,070h,000h,002h,005h,004h,002h,005h,001h,0a2h,02eh,060h,000h,002h,005h,004h	; 7960  .p.........`....
	defb 007h,009h,0a4h,02eh,064h,000h,002h,005h,004h,004h,003h,003h,0ffh,007h,006h,060h	; 7970  ....d..........`
	defb 00eh,011h,009h,00ch,00fh,006h,060h,00eh,00dh,009h,004h,017h,006h,060h,00dh,011h	; 7980  ......`......`..
	defb 004h,00ch,01fh,006h,060h,00dh,00dh,004h,004h,029h,006h,060h,00eh,009h,00ah,00bh	; 7990  ....`....).`....
	defb 02bh,006h,060h,00eh,009h,008h,007h,02fh,006h,060h,00eh,009h,009h,003h,03fh,006h	; 79a0  +.`..../.`....?.
	defb 060h,00dh,009h,004h,003h,069h,006h,060h,008h,007h,00ah,00bh,06bh,006h,060h,008h	; 79b0  `....i.`....k.`.
	defb 007h,008h,007h,06fh,006h,060h,008h,007h,009h,003h,094h,006h,060h,00ch,011h,00fh	; 79c0  ...o.`......`...
	defb 013h,096h,006h,060h,00ch,011h,005h,010h,097h,006h,060h,00ch,011h,002h,00ch,09fh	; 79d0  ...`......`.....
	defb 006h,060h,00ch,00dh,002h,004h,0bfh,006h,060h,00ch,009h,002h,003h,0d4h,006h,060h	; 79e0  .`......`......`
	defb 005h,010h,00fh,013h,0d6h,006h,060h,005h,010h,005h,010h,0d7h,006h,060h,005h,010h	; 79f0  ......`......`..
	defb 002h,00ch,0e0h,006h,060h,00bh,00fh,00ah,013h,0e8h,006h,060h,00bh,006h,00ah,012h	; 7a00  ....`......`....
	defb 0e9h,006h,060h,00bh,001h,00ah,00bh,0ebh,006h,060h,00bh,001h,008h,007h,0efh,006h	; 7a10  ..`......`......
	defb 060h,00bh,001h,009h,003h,0f0h,006h,060h,006h,00fh,012h,013h,0f4h,006h,060h,000h	; 7a20  `......`......`.
	defb 00fh,00fh,013h,0f6h,006h,060h,000h,00fh,005h,010h,0f7h,006h,060h,000h,00fh,002h	; 7a30  .....`......`...
	defb 00ch,0f8h,006h,060h,006h,006h,012h,012h,0f9h,006h,060h,006h,001h,012h,00bh,0fch	; 7a40  ...`......`.....
	defb 006h,060h,000h,006h,00fh,012h,0fdh,006h,060h,000h,001h,00fh,00bh,0ffh,041h,036h	; 7a50  .`......`.....A6
	defb 009h,071h,04fh,072h,074h,068h,061h,06eh,063h,068h,03fh,00ah,081h,04fh,072h,06fh	; 7a60  .qOrthanch?..Oro
	defb 064h,072h,075h,069h,06eh,060h,037h,00ah,081h,04dh,06fh,072h,061h,06eh,06eh,06fh	; 7a70  druin`7..Moranno
	defb 06eh,056h,03fh,00eh,062h,04dh,069h,06eh,061h,073h,020h,054h,069h,072h,069h,074h	; 7a80  nV?.bMinas Tirit
	defb 068h,05fh,040h,00eh,062h,04dh,069h,06eh,061h,073h,020h,04dh,06fh,072h,067h,075h	; 7a90  h_@.bMinas Morgu
	defb 06ch,045h,017h,00bh,091h,052h,069h,076h,065h,06eh,064h,065h,06ch,06ch,064h,03ah	; 7aa0  lE...Rivendelld:
	defb 00ch,0a1h,049h,073h,065h,06eh,06dh,06fh,075h,074h,068h,065h,06fh,040h,00bh,091h	; 7ab0  ..Isenmoutheo@..
	defb 042h,061h,072h,061h,064h,02dh,044h,075h,072h,063h,041h,00eh,062h,043h,069h,072h	; 7ac0  Barad-DurcA.bCir
	defb 069h,074h,068h,055h,06eh,067h,06fh,06ch,020h,061h,03ch,00ah,081h,044h,075h,072h	; 7ad0  ithUngol a<..Dur
	defb 074h,068h,061h,06eh,067h,054h,027h,00eh,062h,044h,06fh,06ch,020h,020h,020h,047h	; 7ae0  thangT'.bDol   G
	defb 075h,06ch,064h,075h,072h,044h,063h,007h,051h,055h,06dh,062h,061h,072h,014h,01eh	; 7af0  uldurDc.QUmbar..
	defb 009h,071h,048h,061h,072h,06ch,06fh,06eh,064h,064h,00fh,006h,041h,044h,061h,06ch	; 7b00  .qHarlondd..ADal
	defb 065h,035h,019h,006h,041h,042h,072h,065h,065h,033h,010h,009h,071h,046h,06fh,072h	; 7b10  e5..ABree3..qFor
	defb 06eh,06fh,073h,074h,030h,01bh,00ah,081h,042h,075h,063h,06bh,06ch,061h,06eh,064h	; 7b20  nost0...Buckland
	defb 028h,016h,009h,071h,042h,079h,077h,061h,074h,065h,072h,025h,01bh,00ah,081h,048h	; 7b30  (..qBywater%...H
	defb 06fh,062h,062h,069h,074h,06fh,06eh,022h,017h,010h,072h,04dh,069h,063h,068h,065h	; 7b40  obbiton"..rMiche
	defb 06ch,020h,044h,065h,06ch,076h,069h,06eh,067h,01fh,017h,00bh,091h,046h,061h,072h	; 7b50  l Delving....Far
	defb 020h,044h,06fh,077h,06eh,073h,035h,028h,009h,071h,054h,068h,061h,072h,062h,061h	; 7b60   Downs5(.qTharba
	defb 064h,045h,038h,008h,061h,045h,064h,06fh,072h,061h,073h,041h,03bh,00ch,052h,048h	; 7b70  dE8.aEdorasA;.RH
	defb 065h,06ch,06dh,073h,044h,065h,065h,070h,020h,046h,04ch,00eh,062h,044h,06fh,06ch	; 7b80  elmsDeep FL.bDol
	defb 020h,020h,020h,041h,06dh,072h,06fh,074h,068h,051h,049h,008h,061h,04ch,069h,06eh	; 7b90     AmrothQI.aLin
	defb 068h,069h,072h,05ch,043h,00ah,081h,050h,065h,06ch,061h,072h,067h,069h,072h,049h	; 7ba0  hir\C..PelargirI
	defb 007h,012h,082h,04dh,06fh,06eh,074h,065h,020h,020h,020h,047h,075h,06eh,064h,061h	; 7bb0  ...Monte   Gunda
	defb 062h,061h,064h,019h,019h,00eh,062h,047h,072h,065h,079h,020h,020h,048h,061h,076h	; 7bc0  bad...bGrey  Hav
	defb 065h,06eh,073h,00ah,004h,000h,0a2h,048h,065h,063h,068h,06fh,020h,070h,06fh,072h	; 7bd0  ens....Hecho por
	defb 03ah,020h,043h,02eh,04ah,02eh,050h,069h,06eh,06bh,020h,020h,050h,06fh,073h,069h	; 7be0  : C.J.Pink  Posi
	defb 063h,069h,06fh,06eh,03ah,020h,023h,023h,023h,05eh,04eh,02ch,023h,023h,023h,05eh	; 7bf0  cion: ###^N,###^
	defb 045h,044h,065h,073h,074h,069h,06eh,06fh,03ah,020h,020h,020h,023h,023h,023h,05eh	; 7c00  EDestino:   ###^
	defb 04eh,02ch,023h,023h,023h,05eh,045h,041h,020h,043h,06fh,06dh,061h,06eh,064h,06fh	; 7c10  N,###^EA Comando
	defb 020h,064h,065h,020h,023h,023h,023h,020h,045h,06eh,061h,06eh,06fh,073h,020h,045h	; 7c20   de ### Enanos E
	defb 06eh,061h,06eh,06fh,03ah,063h,061h,072h,061h,063h,074h,065h,072h,03ah,020h,020h	; 7c30  nano:caracter:  
	defb 020h,020h,020h,020h,020h,020h,020h,064h,065h,073h,074h,069h,06eh,06fh,03ah,020h	; 7c40         destino: 
	defb 023h,023h,023h,05eh,04eh,02ch,023h,023h,023h,05eh,057h,020h,020h,020h,020h,04eh	; 7c50  ###^N,###^W    N
	defb 06fh,020h,06dh,075h,079h,020h,065h,06eh,065h,072h,067h,069h,063h,06fh,020h,020h	; 7c60  o muy energico  
	defb 020h,020h,020h,020h,020h,020h,020h,04eh,06fh,020h,06dh,075h,079h,020h,064h,065h	; 7c70         No muy de
	defb 063h,069h,064h,069h,064h,06fh,020h,020h,020h,020h,020h,020h,020h,020h,020h,04eh	; 7c80  cidido         N
	defb 06fh,020h,06dh,075h,079h,020h,068h,061h,062h,069h,06ch,020h,020h,020h,020h,020h	; 7c90  o muy habil     
	defb 020h,020h,020h,020h,020h,020h,020h,04eh,06fh,020h,06dh,075h,079h,020h,076h,061h	; 7ca0         No muy va
	defb 06ch,065h,072h,06fh,073h,06fh,020h,020h,020h,020h,020h,020h,020h,020h,020h,04eh	; 7cb0  leroso         N
	defb 06fh,020h,06dh,075h,079h,020h,062h,072h,061h,076h,06fh,020h,020h,020h,020h,020h	; 7cc0  o muy bravo     
	defb 020h,020h,020h,020h,020h,020h,020h,04eh,06fh,020h,06dh,075h,079h,020h,066h,075h	; 7cd0         No muy fu
	defb 065h,072h,074h,065h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,046h	; 7ce0  erte           F
	defb 06fh,072h,06dh,061h,020h,075h,06eh,061h,020h,061h,06ch,069h,061h,06eh,07ah,061h	; 7cf0  orma una alianza
	defb 020h,020h,020h,020h,020h,020h,020h,042h,072h,075h,06ah,06fh,073h,0a0h,04eh,061h	; 7d00         Brujos.Na
	defb 07ah,067h,075h,0ech,048h,075h,0edh,045h,06ch,066h,06fh,0f3h,045h,06eh,061h,06eh	; 7d10  zgu.Hu.Elfo.Enan
	defb 06fh,073h,0a0h,04fh,072h,063h,0f3h,048h,06fh,062h,062h,069h,074h,0f3h,042h,072h	; 7d20  os.Orc.Hobbit.Br
	defb 075h,06ah,06fh,0a0h,047h,06fh,06ch,06ch,075h,0edh,042h,072h,075h,06ah,06fh,0a0h	; 7d30  ujo.Gollu.Brujo.
	defb 04eh,061h,07ah,067h,075h,0ech,048h,075h,0edh,045h,06ch,0e6h,045h,06eh,061h,06eh	; 7d40  Nazgu.Hu.El.Enan
	defb 0efh,04fh,072h,0e3h,048h,06fh,062h,062h,069h,0f4h,042h,072h,075h,06ah,06fh,0a0h	; 7d50  .Or.Hobbi.Brujo.
	defb 047h,06fh,06ch,06ch,075h,0edh,04dh,075h,06ah,065h,0f2h,020h,053h,06fh,063h,069h	; 7d60  Gollu.Muje. Soci
	defb 065h,064h,061h,064h,020h,0a0h,0adh,020h,075h,06eh,069h,06fh,06eh,0a0h,020h,075h	; 7d70  edad .. union. u
	defb 06eh,069h,06fh,0eeh,046h,06fh,072h,06dh,061h,063h,069h,06fh,06eh,020h,064h,0e5h	; 7d80  nio.Formacion d.
	defb 03ah,063h,061h,072h,061h,063h,074h,065h,072h,03ah,0a0h,052h,065h,061h,06ch,06dh	; 7d90  :caracter:.Realm
	defb 065h,06eh,074h,065h,0a0h,020h,04dh,075h,079h,0a0h,020h,045h,073h,020h,06dh,075h	; 7da0  ente. Muy. Es mu
	defb 0f9h,0a0h,020h,045h,073h,020h,061h,06ch,067h,06fh,0a0h,020h,04eh,06fh,020h,06dh	; 7db0  .. Es algo. No m
	defb 075h,079h,020h,0a0h,020h,04eh,06fh,0a0h,020h,04eh,06fh,020h,065h,073h,020h,06dh	; 7dc0  uy . No. No es m
	defb 075h,079h,0a0h,020h,045h,06eh,065h,072h,067h,069h,063h,0efh,020h,044h,065h,063h	; 7dd0  uy. Energic. Dec
	defb 069h,064h,069h,064h,06fh,0a0h,020h,048h,061h,062h,069h,06ch,020h,020h,0a0h,020h	; 7de0  idido. Habil  . 
	defb 056h,061h,06ch,069h,06fh,073h,0efh,020h,044h,075h,072h,0efh,020h,042h,072h,061h	; 7df0  Valios. Dur. Bra
	defb 076h,0efh,003h,011h,056h,075h,065h,06ch,076h,065h,0b7h,0b7h,045h,06ch,069h,067h	; 7e00  v...Vuelve..Elig
	defb 065h,020h,064h,065h,073h,074h,069h,06eh,06fh,020h,020h,0b7h,0b7h,045h,06ch,069h	; 7e10  e destino  ..Eli
	defb 067h,065h,020h,055h,06eh,069h,06fh,06eh,0b7h,0b7h,045h,06ch,069h,067h,065h,020h	; 7e20  ge Union..Elige 
	defb 063h,061h,06dh,069h,06eh,06fh,020h,000h,001h,00bh,049h,06eh,064h,069h,076h,069h	; 7e30  camino ...Indivi
	defb 064h,075h,061h,06ch,0b7h,0b7h,054h,06fh,064h,06fh,073h,020h,020h,020h,000h	; 7e40  dual..Todos   .

; ======================================================================
; CODIGO 0x7e4f..0x8030  (481 bytes)
; ======================================================================



; ----------------------------------------------------------------------
; En el mapa grande cada celda son DOS pixeles por dos. Estas rutinas
; ----------------------------------------------------------------------
PUNTO_A_DIRECCION:		; B = fila y C = columna en celdas; sale HL en pantalla y la mascara en BC
	ld a,b			;7e4f
	and 0c0h		;7e50   ; La cuenta del ZX: H = 0x40 + tercio + linea
	rra			;7e52
	scf			;7e53
	rra			;7e54
	rrca			;7e55
	xor b			;7e56
	and 0f8h		;7e57
	xor b			;7e59
	ld h,a			;7e5a
	ld a,c			;7e5b
	rlca			;7e5c   ; L = (fila y 0x38)*4 + columna/8
	rlca			;7e5d
	rlca			;7e5e
	xor b			;7e5f
	and 0c7h		;7e60
	xor b			;7e62
	rlca			;7e63
	rlca			;7e64
	ld l,a			;7e65
	ld a,c			;7e66   ; Los dos bits de abajo de la columna dicen que par de pixeles es
	rrca			;7e67
	and 003h		;7e68
	ld b,a			;7e6a
	inc b			;7e6b
	ld a,0fch		;7e6c   ; 0xFC son los seis unos que dejan un hueco de dos pixeles
CORRE_LA_MASCARA:		; Dos rotaciones por cada par de pixeles
	rrca			;7e6e
	rrca			;7e6f
	djnz CORRE_LA_MASCARA		;7e70
	ld b,a			;7e72   ; B es la mascara y C su contrario
	cpl			;7e73
	ld c,a			;7e74
	ld a,0ffh		;7e75   ; El operando de 0x7E76 es el relleno que puso 0x7E7A
	and c			;7e77
	ld c,a			;7e78
	ret			;7e79
ELIGE_EL_RELLENO:		; A entre 0 y 3: coge de 0x83F8 el relleno con el que se pintara
	and 003h		;7e7a   ; 0x83F8: cuatro rellenos distintos
	add a,0f8h		;7e7c
	ld l,a			;7e7e
	ld h,083h		;7e7f
	ld a,(hl)			;7e81
	ld (07e76h),a		;7e82   ; Y se guarda en el operando de 0x7E75
	ret			;7e85
PINTA_EL_PUNTO:		; Mete en la pantalla los dos pixeles, con su relleno
	ld a,l			;7e86
	rrca			;7e87   ; Los dos bits de abajo de L eligen una de las cuatro tramas de 0x83FC
	and 003h		;7e88
	add a,0fch		;7e8a
	ld e,a			;7e8c
	adc a,083h		;7e8d
	sub e			;7e8f
	ld d,a			;7e90
	ld a,(de)			;7e91
	ld c,a			;7e92
	ld a,h			;7e93   ; Los tres bits de abajo de H son la linea dentro de la celda
	and 007h		;7e94
	add a,000h		;7e96
	ld e,a			;7e98
	adc a,000h		;7e99
	sub e			;7e9b
	ld d,a			;7e9c
	ld a,b			;7e9d
	cpl			;7e9e   ; La mascara al reves: asi se coge solo el relleno
	ld b,a			;7e9f
	ld a,(de)			;7ea0
	and b			;7ea1
	ld c,a			;7ea2
	ld a,b			;7ea3
	cpl			;7ea4
	ld b,a			;7ea5
	ld a,(hl)			;7ea6   ; Lo que ya habia por fuera de la mascara se respeta
	and b			;7ea7
	or c			;7ea8
	ld (hl),a			;7ea9
	ret			;7eaa
PINTA_Y_BAJA:		; Pinta el punto y baja una linea
	call PINTA_EL_PUNTO		;7eab
BAJA_UNA_LINEA:		; Una linea de pixel mas abajo, con el salto de celda del ZX
	inc h			;7eae
	ld a,h			;7eaf
	and 007h		;7eb0   ; Cada ocho lineas se cambia de celda
	ret nz			;7eb2
	ld a,h			;7eb3
	sub 008h		;7eb4
	ld h,a			;7eb6
	ld a,l			;7eb7
	add a,020h		;7eb8   ; Y eso son 32 bytes mas, con el acarreo al tercio de abajo
	ld l,a			;7eba
	ret nc			;7ebb
	ld a,h			;7ebc
	add a,008h		;7ebd
	ld h,a			;7ebf
	ret			;7ec0
PINTA_Y_SUBE:		; Pinta el punto y sube una linea
	call PINTA_EL_PUNTO		;7ec1
SUBE_UNA_LINEA:		; Lo contrario de 0x7EAE
	dec h			;7ec4
	ld a,h			;7ec5
	and 007h		;7ec6   ; Al pasar de la linea 0 se cambia de celda
	cp 007h		;7ec8
	ret nz			;7eca
	ld a,h			;7ecb
	add a,008h		;7ecc
	ld h,a			;7ece
	ld a,l			;7ecf
	sub 020h		;7ed0   ; Treinta y dos bytes menos, y el tercio de arriba si hace falta
	ld l,a			;7ed2
	ret nc			;7ed3
	ld a,h			;7ed4
	sub 008h		;7ed5
	ld h,a			;7ed7
	ret			;7ed8
PINTA_Y_DERECHA:		; Pinta el punto y corre la mascara dos pixeles a la derecha
	call PINTA_EL_PUNTO		;7ed9
CORRE_A_LA_DERECHA:		; Dos rotaciones de la mascara; si da la vuelta, byte siguiente
	rrc c		;7edc
	rrc c		;7ede
	rrc b		;7ee0
	rrc b		;7ee2
	ret c			;7ee4   ; Si el hueco se sale del byte, se pasa al de al lado
	inc hl			;7ee5
	ret			;7ee6
PINTA_Y_IZQUIERDA:		; Pinta el punto y corre la mascara dos pixeles a la izquierda
	call PINTA_EL_PUNTO		;7ee7
CORRE_A_LA_IZQUIERDA:		; Igual pero al reves
	rlc c		;7eea
	rlc c		;7eec
	rlc b		;7eee
	rlc b		;7ef0
	ret c			;7ef2   ; Y aqui el byte anterior
	dec hl			;7ef3
	ret			;7ef4
PINTA_SIN_MOVER:		; Mete el relleno en la pantalla y se queda donde esta
	ld a,(hl)			;7ef5
	and b			;7ef6
	or c			;7ef7
	ld (hl),a			;7ef8
	ret			;7ef9
PON_EL_CURSOR_DE_TEXTO:		; D = fila y E = columna; deja la direccion en 0x827E
	ld de,00000h		;7efa   ; El operando de 0x7EFB es la fila y la columna de destino
	ld a,d			;7efd
	and 007h		;7efe   ; Los tres bits de abajo de la fila, por 32
	rrca			;7f00   ; Los bits 0-2 de D suben a los bits 5-7: la fila dentro del tercio, por 32
	rrca			;7f01
	rrca			;7f02
	or e			;7f03   ; Y abajo la columna, que venia en E
	ld e,a			;7f04
	ld a,d			;7f05
	and 018h		;7f06   ; Bits 3-4 de D: el tercio de pantalla
	or 040h		;7f08   ; 0x40: la pantalla del Spectrum empieza en 0x4000
	ld d,a			;7f0a
	ld (0827eh),de		;7f0b   ; 0x827E es el operando de 0x827D: donde escribira el proximo texto
	ret			;7f0f

; ----------------------------------------------------------------------
; Borrar la pantalla del Spectrum emulada, con el atributo que se diga
; ----------------------------------------------------------------------
BORRA_PANTALLA_BLANCA:		; Borra dejandolo todo con el atributo 0x47: tinta blanca con brillo sobre papel negro
	ld a,047h		;7f10   ; 0x47 = tinta 7 (blanca), papel 0 y el bit 6, el BRIGHT del Spectrum
BORRA_PANTALLA:		; A = atributo ZX: pone el bitmap a cero y todos los atributos a A, en la VRAM y en la copia de RAM
	ld (07f2ch),a		;7f12   ; 0x7F2C es el operando del ld a,nn de 0x7F2B: se guarda el atributo para la copia de RAM
	call 0049fh		;7f15   ; ATRIBUTO_A_COLOR: el atributo ZX se vuelve un byte de color del MSX
	ld hl,02000h		;7f18   ; 0x2000: la tabla de color del SCREEN 2
	ld bc,01800h		;7f1b   ; 0x1800 = las 768 celdas por 8 bytes de color
	call 00429h		;7f1e   ; LLENA_VRAM: el mismo color en toda la pantalla
	ld hl,00000h		;7f21   ; 0x0000: la tabla de patrones
	ld bc,01800h		;7f24
	xor a			;7f27   ; Sin ningun pixel encendido
	call 00429h		;7f28
	ld a,000h		;7f2b   ; Operando automodificado en 0x7F12: el atributo que pidio el llamador
	ld hl,05affh		;7f2d   ; 0x5AFF es el ultimo atributo de la pantalla ZX emulada
	ld de,05afeh		;7f30
	ld bc,00300h		;7f33   ; 0x300 = 768 atributos, de atras adelante
	ld (hl),a			;7f36
	lddr		;7f37
	ld (hl),c			;7f39   ; Tras el lddr BC vale 0, asi que esto escribe un cero
	ld bc,017ffh		;7f3a   ; 0x1800 bytes de bitmap: 0x4000-0x57FF a cero
	lddr		;7f3d
	ret			;7f3f
BORRA_PANTALLA_NEGRA:		; Borra con el atributo 0 (todo negro)
	xor a			;7f40   ; Atributo 0: tinta y papel negros
	jr BORRA_PANTALLA		;7f41

; ----------------------------------------------------------------------
; Empezar una partida nueva. Aqui apunta el ld hl de 0x5E24
; ----------------------------------------------------------------------
EMPIEZA_PARTIDA_NUEVA:		; Pone a 1 los 255 bytes de 0xC600 y la cuenta atras a 255, y cae en el juego
	ld hl,0c600h		;7f43   ; 0xC600-0xC6FE: 255 bytes puestos a 1
	ld de,0c601h		;7f46
	ld bc,000feh		;7f49
	ld (hl),e			;7f4c   ; El 1 sale del byte bajo de DE, que es 0xC601
	ldir		;7f4d
	ld a,0ffh		;7f4f   ; 255 meses de plazo: la cuenta atras que lleva 0x8332
	ld (08333h),a		;7f51
DIBUJA_EL_MAPA_Y_JUEGA:		; Redibuja el mapa entero y entra en el bucle de partida
	call DIBUJA_EL_MAPA		;7f54
BUCLE_DE_PARTIDA:		; Una vuelta: cursor, mando, las rutinas del turno, el reloj y la comprobacion de victoria
	call 007c3h		;7f57   ; REFRESCA_EL_CURSOR: sube al VDP el recuadro de alrededor de (0x6543, 0x6544)
	ld a,(06511h)		;7f5a   ; 0x6511 es el operando donde LEE_LOS_MANDOS deja el byte del mando
	bit 5,a		;7f5d   ; Bit 5 = la tecla 1, la de "Pausa/Abandona" del menu
	call nz,PAUSA		;7f5f
	call MUEVE_EL_CURSOR		;7f62   ; Mueve el cursor con el mando
	call MUEVE_LA_SIGUIENTE_UNIDAD		;7f65   ; Operando en 0x7F66: 0x8166 lo desvia al retardo de 0x8274
	call MIRA_SI_YA_SE_HAN_JUNTADO		;7f68
	call RELOJ		;7f6b   ; Operando en 0x7F6C: el reloj, que 0x8166 tambien desvia al retardo
	call BUSCA_AL_PORTADOR		;7f6e   ; Devuelve en A el primer indice de 0xBD00 con el bit 4 puesto
	ld l,a			;7f71
	ld h,0b9h		;7f72   ; 0xB900+n: la coordenada X de esa unidad
	ld a,(hl)			;7f74
	cp 068h		;7f75   ; 0x68 en X y ...
	jr nz,PULSA_EL_JUGADOR		;7f77
	inc h			;7f79   ; 0xBA00+n: su coordenada Y
	ld a,(hl)			;7f7a
	cp 03fh		;7f7b   ; ... 0x3F en Y: llegar ahi es la VICTORIA
	jp z,VICTORIA		;7f7d   ; A la pantalla final de Gandalf
PULSA_EL_JUGADOR:		; Mira el disparo; si la celda de al lado del cursor lleva el atributo 0x78, es un panel
	call MIRA_QUIEN_ESTA_EN_LA_CASILLA_56_3F		;7f80
	ld a,(06511h)		;7f83
	bit 4,a		;7f86   ; Bit 4 del byte del mando: el disparo
	jp z,BUCLE_DE_PARTIDA		;7f88   ; Sin disparo, otra vuelta del bucle
	ld hl,(064dah)		;7f8b   ; 0x64DA es el operando del ld hl,0x0000 que escribe 0x65FB: la direccion ZX del cursor
	ld a,h			;7f8e
	rrca			;7f8f   ; Bits 3-4 del byte alto son el tercio ...
	rrca			;7f90
	rrca			;7f91
	and 003h		;7f92
	or 058h		;7f94   ; ... y con 0x58 sale la direccion del ATRIBUTO de esa celda
	ld h,a			;7f96
	inc hl			;7f97   ; La celda de la derecha del cursor
	ld a,(hl)			;7f98
	cp 078h		;7f99   ; 0x78 = papel 7 y tinta 0, el atributo con que 0x8166 escribe los paneles
	jr z,PULSA_EN_EL_PANEL		;7f9b
	ld hl,(06543h)		;7f9d   ; 0x6543/0x6544 son la posicion del cursor en pixeles
	ld a,l			;7fa0
	srl a		;7fa1   ; Entre dos: el mapa se dibuja a media resolucion
	add a,008h		;7fa3   ; +8 y +3: el desfase del cursor respecto al centro
	ld c,a			;7fa5
	ld a,h			;7fa6
	srl a		;7fa7
	add a,003h		;7fa9
	ld b,a			;7fab
RECENTRA_EL_MAPA:		; Borra, vuelve a marcar en el mapa donde esta cada unidad y recoloca el cursor
	push bc			;7fac
	call BORRA_PANTALLA_NEGRA		;7fad   ; Pantalla en negro antes de repintar
	ld c,000h		;7fb0   ; Recorre las 0x78 unidades
MARCA_UNA_UNIDAD_7FB2:		; Pone el bit 7 en la casilla del mapa donde esta la unidad C
	ld a,c			;7fb2
	cp 016h		;7fb3   ; Las unidades 0x16 y 0x17 no se marcan
	jr z,L_7FCE		;7fb5
	cp 017h		;7fb7
	jr z,L_7FCE		;7fb9
	ld b,0b9h		;7fbb   ; 0xB900+n: la coordenada X, sin el bit 7
	ld a,(bc)			;7fbd
	and 07fh		;7fbe
	ld l,a			;7fc0
	inc b			;7fc1   ; 0xBA00+n: la coordenada Y, sin el bit 7
	ld a,(bc)			;7fc2
	and 07fh		;7fc3
	ld h,a			;7fc5
	or l			;7fc6
	jr z,L_7FCE		;7fc7   ; Las dos a cero quiere decir que esa unidad no esta en el mapa
	call CELDA_DEL_MAPA		;7fc9   ; CELDA_DEL_MAPA: de (X,Y) a la direccion dentro de 0xCC00
	set 7,(hl)		;7fcc   ; Bit 7 = "en esta casilla hay alguien"
L_7FCE:
	inc c			;7fce   ; Siguiente unidad
	ld a,c			;7fcf
	cp 078h		;7fd0   ; 0x78 = 120 unidades en total
	jr nz,MARCA_UNA_UNIDAD_7FB2		;7fd2
	pop hl			;7fd4
	call ENTRA_EN_LA_VISTA		;7fd5   ; Recoloca el mapa alrededor de la casilla que se pidio
	ld (06546h),hl		;7fd8
	ld a,h			;7fdb   ; La coordenada vuelve a pixeles: por dos ...
	add a,a			;7fdc
	sub 006h		;7fdd   ; ... menos 6 y menos 0x10, que es el desfase del cursor
	ld h,a			;7fdf
	ld a,l			;7fe0
	add a,a			;7fe1
	sub 010h		;7fe2
	ld l,a			;7fe4
	ld (06543h),hl		;7fe5   ; La nueva posicion del cursor
	ld hl,0cc00h		;7fe8   ; Barrido de 0xCC00 a 0xFFCB: el mapa entero
	ld e,07fh		;7feb   ; Mascara 0x7F: baja el bit 7 de "hay alguien" de todas las casillas
	ld bc,033cch		;7fed   ; 0x33CC = 13260 = 130 columnas de 0x66 bytes
L_7FF0:
	ld a,(hl)			;7ff0
	and e			;7ff1
	ld (hl),a			;7ff2
	inc hl			;7ff3
	dec bc			;7ff4
	ld a,b			;7ff5
	or c			;7ff6
	jr nz,L_7FF0		;7ff7
	jp DIBUJA_EL_MAPA_Y_JUEGA		;7ff9   ; Y a repintar el mapa desde cero
SIGUE_LA_PARTIDA:		; Vuelve al bucle sin hacer nada
	jp BUCLE_DE_PARTIDA		;7ffc
PULSA_EN_EL_PANEL:		; El disparo cayo sobre texto: segun la altura, el menu de cinta o el panel de mensajes
	ld a,(06544h)		;7fff   ; 0x6544 es la altura del cursor en pixeles
	cp 062h		;8002   ; Por encima de la linea 0x62 no hay panel
	jr c,SIGUE_LA_PARTIDA		;8004
	cp 081h		;8006   ; De 0x81 para abajo es el panel de mensajes
	jp nc,PULSA_ABAJO_DEL_TODO		;8008
	ld hl,08400h		;800b   ; 0x8400: el menu "Volver / Cargar / Salvar" (3 opciones de 11 caracteres)
	call LISTA_DE_DOS_FILAS		;800e   ; Menu centrado; devuelve en A la opcion elegida
	and a			;8011   ; Cero es "Volver": no se hace nada
	jp z,DIBUJA_EL_MAPA_Y_JUEGA		;8012
	ld hl,09627h		;8015   ; Opcion 1: cargar la partida de la cinta
	dec a			;8018
	jr z,LLAMA_A_LA_CINTA		;8019
	ld hl,09654h		;801b   ; Opcion 2: salvarla
	dec a			;801e
	jr z,LLAMA_A_LA_CINTA		;801f
	jp DIBUJA_EL_MAPA_Y_JUEGA		;8021
LLAMA_A_LA_CINTA:		; Mete la rutina elegida en el operando del call de 0x802A y la ejecuta
	ld (06546h),hl		;8024   ; 0x6546 guarda tambien la eleccion
	ld (0802bh),hl		;8027   ; 0x802B es el OPERANDO del call de abajo: aqui se elige a quien se llama
	call 00000h		;802a   ; BIOS CHKRAM - Tests RAM and sets RAM slot for the system  [alias: STARTUP, RESET, BOOT] | No es un call a 0x0000: el operando lo acaba de escribir 0x8027
	jp DIBUJA_EL_MAPA_Y_JUEGA		;802d

; ----------------------------------------------------------------------
; DATOS tabla_de_10_palabras_8030: Tabla de 10 palabras (indice 1..10) que
;   0x804D-0x805B indexa con A y salta con jp (hl)
;   0x8030..0x8044  (20 bytes)
DATA_tabla_de_10_palabras_8030:
	defw 08071h	; 8030  -> PINTA_CASILLA_UNIDA
	defw 08062h	; 8032  -> TERRENO_2_8062
	defw 08068h	; 8034  -> TERRENO_3_Y_4
	defw 08068h	; 8036  -> TERRENO_3_Y_4
	defw 0805ch	; 8038  -> TERRENO_5
	defw 080aeh	; 803a  -> TERRENO_6_80AE
	defw 080adh	; 803c  -> NO_SE_PINTA
	defw 080adh	; 803e  -> NO_SE_PINTA
	defw 080adh	; 8040  -> NO_SE_PINTA
	defw 080adh	; 8042  -> NO_SE_PINTA

; ======================================================================
; CODIGO 0x8044..0x83f8  (948 bytes)
; ======================================================================



; ----------------------------------------------------------------------
; Pintar una casilla de mapa. El nibble bajo del byte manda: aqui van los tipos 1..9
; ----------------------------------------------------------------------
PINTA_TERRENO_BAJO:		; A = tipo de terreno 1..9, B = fila, C = columna; despacha por la tabla de 0x8030
	and a			;8044   ; El tipo 0 no se dibuja
	ret z			;8045
	push bc			;8046
	push af			;8047
	call ELIGE_EL_RELLENO		;8048   ; Elige la trama de 2 bits segun A y 3: 0x00, 0xFF, 0xAA o 0x55
	pop af			;804b
	pop bc			;804c
	ld e,a			;804d   ; E se lleva el tipo: las rutinas de abajo lo comparan con el de las casillas vecinas
	add a,a			;804e
	add a,02eh		;804f   ; HL = 0x802E + A*2, o sea la entrada A de la tabla de 0x8030
	ld l,a			;8051
	adc a,080h		;8052   ; El acarreo del byte bajo, propagado a mano
	sub l			;8054
	ld h,a			;8055
	ld a,(hl)			;8056   ; De la tabla sale la direccion a la que saltar
	inc hl			;8057
	ld h,(hl)			;8058
	ld l,a			;8059
	ld a,e			;805a
	jp (hl)			;805b   ; Se entra con A = E = el tipo de terreno
TERRENO_5:		; Tipo 5: se pinta con la trama llena y se une con las casillas de tipo 1
	push bc			;805c
	ld a,001h		;805d   ; Trama 1 y 3 = 1: 0xFF, todos los bits
	ld e,a			;805f   ; Pero se une con el terreno 1, no con el 5
	jr FIJA_LA_TRAMA		;8060
TERRENO_2_8062:		; Tipo 2: trama 0xAA y se une con las casillas de tipo 2
	push bc			;8062
	ld a,002h		;8063   ; Trama 2 y 3 = 2: 0xAA
	ld e,a			;8065
	jr FIJA_LA_TRAMA		;8066
TERRENO_3_Y_4:		; Tipos 3 y 4: los dos se pintan llenos y se unen con las casillas de tipo 3
	push bc			;8068
	ld a,001h		;8069   ; Trama llena para los dos
	ld e,003h		;806b   ; Y los dos se unen con el tipo 3
FIJA_LA_TRAMA:		; Deja la trama elegida en el operando de 0x7E75 y cae en el pintado
	call ELIGE_EL_RELLENO		;806d
	pop bc			;8070
PINTA_CASILLA_UNIDA:		; Pinta el pixel de la casilla y los puentes a las vecinas que sean del tipo E
	push bc			;8071
	sla b		;8072   ; Por dos: cada casilla de mapa es un pixel doble en pantalla
	sla c		;8074
	call PUNTO_A_DIRECCION		;8076   ; Direccion de pantalla ZX y mascaras del pixel para (fila*2, columna*2)
	call PINTA_SIN_MOVER		;8079   ; El pixel de la casilla
	call CORRE_A_LA_DERECHA		;807c   ; Un pixel a la derecha, sin pintar
	ld a,(iy+066h)		;807f   ; La casilla de al lado: +0x66 es la columna siguiente del mapa
	and 00fh		;8082
	cp e			;8084   ; Solo se une si es del mismo tipo
	call z,PINTA_SIN_MOVER		;8085
	call BAJA_UNA_LINEA		;8088   ; Baja una linea de pixeles
	ld a,(iy+067h)		;808b   ; +0x67: la casilla en diagonal, columna y fila siguientes
	and 00fh		;808e
	cp e			;8090
	call z,PINTA_SIN_MOVER		;8091
	call CORRE_A_LA_IZQUIERDA		;8094   ; Un pixel a la izquierda
	ld a,(iy+001h)		;8097   ; +1: la casilla de la fila siguiente
	and 00fh		;809a
	cp e			;809c
	call z,PINTA_SIN_MOVER		;809d
	call CORRE_A_LA_IZQUIERDA		;80a0   ; Otro pixel a la izquierda
	ld a,(iy-065h)		;80a3   ; -0x65: la diagonal hacia la otra columna
	and 00fh		;80a6
	cp e			;80a8
	call z,PINTA_SIN_MOVER		;80a9
	pop bc			;80ac
NO_SE_PINTA:		; Los tipos 7, 8 y 9 no dibujan nada
	ret			;80ad
TERRENO_6_80AE:		; Tipo 6: un pixel suelto, sin unirse a nadie
	push bc			;80ae
	sla b		;80af   ; Coordenadas por dos, igual que en 0x8071
	sla c		;80b1
	call PUNTO_A_DIRECCION		;80b3
	call PINTA_SIN_MOVER		;80b6   ; Un solo pixel y se acabo
	pop bc			;80b9
	ret			;80ba
SALE_SIN_PINTAR:		; Recupera A y vuelve
	pop af			;80bb
	ret			;80bc

; ----------------------------------------------------------------------
; Los tipos 10..15 del mapa: en vez de trama de 2 bits llevan un dibujo de 8x8
; ----------------------------------------------------------------------
PINTA_TERRENO_ALTO:		; A = tipo menos 10; escoge un dibujo de 8 bytes y pinta una cruz de cinco pixeles dobles
	push af			;80bd
	ld a,b			;80be
	cp 061h		;80bf   ; De la fila 0x61 para abajo no se pinta
	jr nc,SALE_SIN_PINTAR		;80c1
	pop af			;80c3
	ld hl,0848fh		;80c4   ; Este jr z NO prueba el tipo: el `inc b` de 0x818F ya piso el Z del `sub 00ah`, y B+1 nunca vale cero. 0x848F es dibujo MUERTO y el tipo 10 acaba en 0x80DB
	jr z,PINTA_CON_DIBUJO		;80c7
	dec a			;80c9
	ld hl,0847fh		;80ca   ; A = 1 (tipo 11): el de 0x847F. De aqui en adelante el Z si es el del dec a de al lado, asi que 11, 12 y 13 aciertan
	jr z,PINTA_CON_DIBUJO		;80cd
	dec a			;80cf
	ld hl,08487h		;80d0   ; A = 2 (tipo 12): el de 0x8487
	jr z,PINTA_CON_DIBUJO		;80d3
	dec a			;80d5
	ld hl,0846fh		;80d6   ; A = 3 (tipo 13): el de 0x846F
	jr z,PINTA_CON_DIBUJO		;80d9
	ld hl,08477h		;80db   ; Y los demas, el de 0x8477: los tipos 14 y 15 ... y tambien el 10, por lo del Z pisado
PINTA_CON_DIBUJO:		; Mete el dibujo elegido en los operandos de 0x7E96/0x7E99 y pinta cinco pixeles en cruz
	ld a,l			;80de
	ld (07e97h),a		;80df   ; 0x7E97 es el operando del add a,nn de 0x7E96: el byte bajo del dibujo
	ld a,h			;80e2
	ld (07e9ah),a		;80e3   ; 0x7E9A el del adc a,nn de 0x7E99: el byte alto
	push bc			;80e6
	sla b		;80e7   ; Coordenadas por dos
	sla c		;80e9
	call PUNTO_A_DIRECCION		;80eb   ; Direccion de pantalla y mascaras del pixel
	call PINTA_Y_DERECHA		;80ee   ; Pinta y va a la derecha
	call PINTA_Y_BAJA		;80f1   ; Pinta y baja una linea
	call CORRE_A_LA_IZQUIERDA		;80f4   ; A la izquierda, sin pintar
	call PINTA_Y_SUBE		;80f7   ; Pinta y sube una linea
	call CORRE_A_LA_IZQUIERDA		;80fa   ; Otra vez a la izquierda
	call PINTA_Y_DERECHA		;80fd   ; Pinta y vuelve a la derecha
	call SUBE_UNA_LINEA		;8100   ; Sube una linea, sin pintar
	call PINTA_EL_PUNTO		;8103   ; El quinto y ultimo pixel de la cruz
	pop bc			;8106
	ret			;8107

; ----------------------------------------------------------------------
; De una casilla del mapa a su direccion en RAM
; ----------------------------------------------------------------------
CELDA_DEL_MAPA:		; H = coordenada Y, L = coordenada X; devuelve en HL e IX la direccion dentro del mapa
	ld a,h			;8108   ; Los dos bits 7 son banderas y no cuentan como coordenada
	and 07fh		;8109
	res 7,l		;810b
	ld h,000h		;810d
	ld e,l			;810f
	ld d,h			;8110
	add hl,hl			;8111   ; A partir de aqui, multiplicar X por 102 a base de sumas
	push hl			;8112   ; Se aparta 2*X para el final
	add hl,hl			;8113
	add hl,de			;8114   ; 5*X
	add hl,hl			;8115
	ld e,l			;8116
	ld d,h			;8117
	add hl,hl			;8118   ; 40*X
	add hl,hl			;8119
	add hl,de			;811a   ; 50*X
	add hl,hl			;811b   ; 100*X
	pop de			;811c
	add hl,de			;811d   ; Mas los 2*X apartados: 102*X, la anchura de una columna del mapa
	ld de,00067h		;811e   ; El mapa no arranca en 0xCC00 raso: lleva 0x67 de margen
	add hl,de			;8121
	ld e,a			;8122   ; 0xCC00 + Y: el mapa vive de 0xCC00 a 0xFFCB
	ld d,0cch		;8123
	add hl,de			;8125
	ld a,(hl)			;8126   ; De paso se devuelve en A el byte de esa casilla
	ex de,hl			;8127
	defb 0ddh,06bh	;ld ixl,e		;8128   ; La direccion se deja tambien en IX, que es como la quieren los que pintan
	defb 0ddh,062h	;ld ixh,d		;812a
	ex de,hl			;812c
	ret			;812d

; ----------------------------------------------------------------------
; La pausa: se llega con la tecla 1 desde el bucle de partida
; ----------------------------------------------------------------------
PAUSA:		; El borde parpadea entre dos colores hasta que se pulsa disparo
	call RETARDO		;812e   ; Un retardo antes de empezar, para no comerse la pulsacion
	ld a,002h		;8131   ; Atributo 2: tinta roja sobre papel negro
	call 0049fh		;8133   ; Que se vuelve el byte de color del MSX
	push af			;8136
PARPADEA_EL_BORDE:		; Cambia el color del borde y mira el disparo
	pop af			;8137
	call 00467h		;8138   ; Registro 7 del VDP: el borde
	xor 002h		;813b   ; Se le da la vuelta al bit 1 del color: de ahi el parpadeo
	push af			;813d
	call 0066dh		;813e   ; Lee el mando
	bit 4,a		;8141   ; Bit 4: el disparo. Mientras no se pulse, sigue parpadeando
	jr z,PARPADEA_EL_BORDE		;8143
	pop af			;8145
	xor a			;8146   ; Borde negro otra vez
	call 00467h		;8147
	jp ESPERA_A_SOLTAR_FUEGO		;814a   ; Y se vuelve por 0x7599, no por el ret

; ----------------------------------------------------------------------
; Repintar de un color TODA la pantalla sin tocar el dibujo
; ----------------------------------------------------------------------
PINTA_TODOS_LOS_ATRIBUTOS:		; A = atributo ZX: lo pone en las 768 celdas, en la VRAM y en la copia de RAM
	call 0049fh		;814d   ; Atributo ZX a byte de color del MSX
	ld hl,02000h		;8150   ; 0x2000: la tabla de color del SCREEN 2
	ld bc,01800h		;8153   ; 0x1800 = 768 celdas por 8 bytes
	call 00429h		;8156
	ld hl,05800h		;8159   ; 0x5800: los atributos de la pantalla emulada
	ld d,h			;815c
	ld e,l			;815d
	inc e			;815e
	ld (hl),a			;815f   ; El primero se escribe a mano y el ldir copia los otros 767
	ld bc,00300h		;8160   ; 768 atributos
	ldir		;8163
	ret			;8165

; ----------------------------------------------------------------------
; Dibujar el mapa entero y montar los paneles. Es lo que hace 0x7F54 antes de jugar
; ----------------------------------------------------------------------
DIBUJA_EL_MAPA:		; Recorre las 126 columnas por 93 filas del mapa, pinta cada casilla, y monta los paneles File/Memo/Time
	ld a,078h		;8166   ; 0x82F6 es el operando de 0x82F5: los textos se escribiran con el atributo 0x78
	ld (082f6h),a		;8168
	ld hl,04000h		;816b   ; 0x4000-0x5AFF a cero: bitmap y atributos de la pantalla emulada
	ld de,04001h		;816e
	ld (hl),l			;8171   ; ld (hl),l con L = 0 es el cero de arranque del ldir
	ld bc,01affh		;8172
	ldir		;8175
	xor a			;8177
	call BORRA_PANTALLA		;8178   ; Y tambien se limpia la VRAM, con atributo 0
	ld a,003h		;817b   ; Trama 3 y 3 = 3: 0x55, la de arranque
	call ELIGE_EL_RELLENO		;817d
	ld iy,0ff60h		;8180   ; 0xFF60 es la ultima casilla que se pinta; de ahi se va hacia atras
	ld c,07eh		;8184   ; 0x7E = 126 columnas de mapa
COLUMNA_DE_TERRENO_ALTO:		; Una columna: 93 casillas de tipo 10..15
	ld b,05dh		;8186   ; 0x5D = 93 filas por columna
CASILLA_DE_TERRENO_ALTO:		; Pinta la casilla si su nibble bajo es 10 o mas
	ld a,(iy+000h)		;8188
	and 00fh		;818b   ; El nibble bajo del byte del mapa es el tipo de terreno
	sub 00ah		;818d   ; Menos 10: sin acarreo son los tipos 10..15
	inc b			;818f   ; B es la fila, y se pasa una mas. OJO: `inc b` PISA EL FLAG Z, y de eso vive la errata de 0x80C4; el acarreo del `sub`, que es lo que mira el call, si sobrevive
	call nc,PINTA_TERRENO_ALTO		;8190
	dec b			;8193
	dec iy		;8194   ; Atras una casilla: dentro de la columna se va hacia abajo
	djnz CASILLA_DE_TERRENO_ALTO		;8196
	ld de,0fff7h		;8198   ; -9: las 93 filas mas esto son los 0x66 bytes de una columna
	add iy,de		;819b
	dec c			;819d
	jr nz,COLUMNA_DE_TERRENO_ALTO		;819e
	ld iy,0ff62h		;81a0   ; Segunda pasada, ahora los tipos 1..9, empezando dos casillas mas alla
	ld c,07eh		;81a4   ; Otras 126 columnas
COLUMNA_DE_TERRENO_BAJO:		; Una columna: 95 casillas de tipo 1..9
	ld b,05fh		;81a6   ; 0x5F = 95 filas, dos mas que la otra pasada
CASILLA_DE_TERRENO_BAJO:		; Pinta la casilla si su nibble bajo es menor que 10
	ld a,(iy+000h)		;81a8
	and 00fh		;81ab
	cp 00ah		;81ad   ; Menor que 10: los tipos que sabe pintar 0x8044
	call c,PINTA_TERRENO_BAJO		;81af
	dec iy		;81b2
	dec b			;81b4
	jp p,CASILLA_DE_TERRENO_BAJO		;81b5   ; jp p en vez de djnz: el bucle llega hasta B = 0
	ld de,0fffah		;81b8   ; -6: con las 95 filas hacen los 0x66 de la columna
	add iy,de		;81bb
	dec c			;81bd
	jp p,COLUMNA_DE_TERRENO_BAJO		;81be
	call 005bdh		;81c1   ; El mapa ya esta dibujado en RAM: ahora sube al VDP
	ld a,030h		;81c4   ; Atributo 0x30: papel 6 (amarillo) y tinta 0 en toda la pantalla
	call PINTA_TODOS_LOS_ATRIBUTOS		;81c6
	ld hl,08499h		;81c9   ; El marco de los paneles File y Memo, en 0x4860
	call ESCRIBE_TEXTO_DONDE_TOCA		;81cc
	ld a,0b7h		;81cf   ; 0x8504 es el byte de salto de linea del texto del panel Time
	ld (08504h),a		;81d1   ; Se le devuelve el 0xB7 que 0x81DB le quito la vez anterior
	ld hl,084e1h		;81d4   ; El panel Time entero, marco de arriba, hueco y marco de abajo
	call ESCRIBE_TEXTO_DONDE_TOCA		;81d7
	xor a			;81da
	ld (08504h),a		;81db   ; Y ahora un 0x00 ahi: a partir de aqui ese texto acaba tras la linea del hueco
	ld hl,RETARDO		;81de   ; El retardo de 0x8274 se cuela en dos call del bucle de partida ...
	ld (07f66h),hl		;81e1   ; ... en el operando de 0x7F65 ...
	ld (07f6ch),hl		;81e4   ; ... y en el del reloj, 0x7F6B: mientras tanto el calendario no avanza
	jp REPINTA_LOS_EJERCITOS		;81e7   ; Y a 0x6AAF, que es por donde sigue
PULSA_ABAJO_DEL_TODO:		; Si el bucle sigue con los dos call desviados, los devuelve a su sitio; si no, abre el panel de mensajes
	call ESPERA_A_SOLTAR_FUEGO		;81ea
	ld a,(07f67h)		;81ed   ; 0x7F67 es el byte alto del operando del call de 0x7F65
	cp 082h		;81f0   ; 0x82 quiere decir que sigue apuntando al retardo de 0x8274
	jr nz,PANEL_DE_MENSAJES		;81f2
	ld hl,06719h		;81f4   ; Se le devuelve su rutina ...
	ld (07f66h),hl		;81f7
	ld hl,RELOJ		;81fa   ; ... y al otro el reloj: el calendario echa a andar
	ld (07f6ch),hl		;81fd
	call ESPERA_A_SOLTAR_FUEGO		;8200
	jp BUCLE_DE_PARTIDA		;8203   ; Y de vuelta al bucle de partida

; ----------------------------------------------------------------------
; El panel Memo: el mensaje pasa rodando por la linea 22
; ----------------------------------------------------------------------
PANEL_DE_MENSAJES:		; Hace rodar el texto de 0x8242 por una ventana de 14 celdas, hasta que se pulsa disparo
	ld hl,(08242h)		;8206   ; 0x8242 es el buzon: apunta al mensaje que toca leer
	push hl			;8209
	ld hl,0846ah		;820a   ; Cuatro espacios en 0x50A1: borra el rotulo
	ld de,050a1h		;820d
	call ESCRIBE_TEXTO		;8210
OCHO_DESPLAZAMIENTOS:		; Ocho pixeles de desplazamiento, que es una celda entera
	ld e,008h		;8213   ; Ocho pixeles: lo que mide una celda
UN_PIXEL_DE_SCROLL:		; Rota a la izquierda las 14 celdas de la ventana y las sube al VDP
	ld hl,050ceh		;8215   ; 0x50CE es la ultima celda de la ventana; se va hacia atras
	ld c,008h		;8218   ; Las ocho lineas de pixeles de la fila
UNA_LINEA_DE_SCROLL:		; Una linea de pixeles: 14 bytes rotados en cadena
	push hl			;821a
	ld b,00eh		;821b   ; 14 celdas de ancho
	or a			;821d   ; El acarreo entra a cero: por la derecha se mete negro
ROTA_UN_BYTE:		; rl encadenado: el bit que sale de un byte entra en el de su izquierda
	rl (hl)		;821e
	dec hl			;8220   ; De derecha a izquierda, que es como corre el acarreo
	djnz ROTA_UN_BYTE		;8221
	pop hl			;8223
	inc h			;8224   ; +0x100: la linea de pixeles de abajo, a la manera del Spectrum
	dec c			;8225
	jr nz,UNA_LINEA_DE_SCROLL		;8226
	push de			;8228
	ld de,01601h		;8229   ; Fila 0x16 (22), columna 1 ...
	ld bc,0010eh		;822c   ; ... una fila de 14 celdas: el recuadro que se sube al VDP
	call 00702h		;822f
	pop de			;8232
	ld bc,00012h		;8233   ; Este ld bc no sirve de nada: 0x8274 lo primero que hace es pisarlo
	call RETARDO		;8236   ; Retardo: es lo que marca la velocidad del texto
	dec e			;8239   ; Otro pixel
	jr nz,UN_PIXEL_DE_SCROLL		;823a
	pop hl			;823c
	ld a,(hl)			;823d   ; El byte del mensaje que toca
	and a			;823e   ; Un 0x00 es el final del texto
	jr nz,METE_UN_CARACTER		;823f
	ld hl,0855eh		;8241   ; 0x855E - 1: al acabar se repite "Ningun mensaje"
	dec hl			;8244
	ld a,020h		;8245   ; 0x20: y lo que entra ahora es un espacio
METE_UN_CARACTER:		; Escribe el caracter en la celda de la derecha de la ventana y mira el disparo
	inc hl			;8247
	push hl			;8248
	ld de,050ceh		;8249   ; 0x50CE: la celda que acaba de quedar libre
	ld l,a			;824c
	call PINTA_UN_CARACTER		;824d   ; Pinta el caracter L en esa celda
	call 0066dh		;8250
	bit 4,a		;8253   ; Bit 4: el disparo. Sin el, sigue rodando el mensaje
	jr z,OCHO_DESPLAZAMIENTOS		;8255
	ld hl,0855eh		;8257   ; Leido el aviso, el buzon vuelve a "Ningun mensaje"
	ld (08242h),hl		;825a
	pop hl			;825d   ; Empareja el push hl de 0x8248
	ld hl,084e1h		;825e   ; El panel Time se vuelve a escribir ...
	call ESCRIBE_TEXTO		;8261
	inc hl			;8264   ; Este inc hl no sirve: el ld hl de abajo lo pisa
	ld de,050c1h		;8265
	ld hl,084f5h		;8268   ; ... y su linea del medio, con la fecha, en 0x50C1
	call ESCRIBE_TEXTO		;826b
	call ESPERA_A_SOLTAR_FUEGO		;826e   ; Se vuelve por 0x7599 al bucle de partida
	jp BUCLE_DE_PARTIDA		;8271
RETARDO:		; Espera 6 vueltas de 256 djnz. Es lo que 0x8166 mete en los dos call del bucle para congelar el reloj
	ld bc,00006h		;8274   ; Aqui se pisa el BC del llamador: el retardo es siempre el mismo
CUENTA_ATRAS_DEL_RETARDO:		; Bucle de dos pisos, B por dentro y C por fuera
	djnz CUENTA_ATRAS_DEL_RETARDO		;8277
	dec c			;8279
	jr nz,CUENTA_ATRAS_DEL_RETARDO		;827a
	ret			;827c

; ----------------------------------------------------------------------
; Escribir una cadena en la pantalla del Spectrum emulada
; ----------------------------------------------------------------------
ESCRIBE_TEXTO_DONDE_TOCA:		; Como 0x8280 pero la posicion la trae el operando de 0x827E, que dejo puesto 0x7EFA o 0x644F
	ld de,00000h		;827d   ; 0x827E es la variable de posicion: la escriben 0x7F0B y 0x644F
ESCRIBE_TEXTO:		; HL = cadena, DE = direccion ZX. Termina en 0x00; de 0x80 arriba son ordenes
	ld a,(hl)			;8280   ; Byte a byte
	inc hl			;8281
	or a			;8282   ; El 0x00 cierra la cadena
	ret z			;8283
	jp m,ORDEN_DEL_TEXTO		;8284   ; Bit 7 puesto: no es un caracter, es una orden
	push hl			;8287
	ld l,a			;8288   ; L = el codigo del caracter
	call PINTA_UN_CARACTER		;8289   ; Lo pinta en la celda DE
	pop hl			;828c
	inc e			;828d   ; Columna siguiente
	jr nz,ESCRIBE_TEXTO		;828e   ; Si E no da la vuelta, se sigue en la misma banda de 256 bytes
	ld a,008h		;8290   ; Y si la da, hay que pasar de tercio: +8 en el byte alto
	add a,d			;8292
	ld d,a			;8293
	jr ESCRIBE_TEXTO		;8294
ORDEN_DEL_TEXTO:		; Los codigos de 0x80 arriba: cambiar de sitio o mover el cursor
	and 07fh		;8296   ; Se le quita el bit 7 que lo marcaba como orden
	bit 6,a		;8298   ; Bit 6: de 0xC0 arriba es "sigue escribiendo en esta direccion"
	jr z,MUEVE_EL_CURSOR_82A5		;829a
	ld d,a			;829c   ; El propio codigo sin el bit 7 es el byte ALTO (0x40-0x7F, la pantalla ZX)
	ld e,(hl)			;829d   ; Y el byte que viene detras es el bajo
	inc hl			;829e
	ld (ESCRIBE_TEXTO_DONDE_TOCA+1),de		;829f   ; Se apunta como nueva posicion de linea
	jr ESCRIBE_TEXTO		;82a3
MUEVE_EL_CURSOR_82A5:		; Codigos 0x80-0xBF: los bits 0-1 dicen que hacer y los 2-5 cuanto
	ld c,a			;82a5
	and 003h		;82a6   ; Bits 0-1: la orden
	ld b,a			;82a8
	ld a,c			;82a9
	rra			;82aa   ; Bits 2-5: la cuenta
	rra			;82ab
	and 00fh		;82ac
	ld c,a			;82ae
	ld a,b			;82af
	or a			;82b0   ; Orden 0: no hace nada
	jr z,ESCRIBE_TEXTO		;82b1
	dec a			;82b3
	jr nz,SALTO_DE_LINEA		;82b4   ; Orden 1 abajo; las otras a 0x82C2
	ld a,c			;82b6   ; Adelanta cuenta+1 columnas
	inc a			;82b7
	add a,e			;82b8
	ld e,a			;82b9
	jr nc,ESCRIBE_TEXTO		;82ba   ; Si no ha dado la vuelta, misma banda
	ld a,008h		;82bc   ; Y si la ha dado, tercio siguiente
	add a,d			;82be
	ld d,a			;82bf
	jr ESCRIBE_TEXTO		;82c0
SALTO_DE_LINEA:		; Orden 3: baja a la linea de abajo desde donde empezo la actual
	dec a			;82c2
	jr z,ESCRIBE_TEXTO		;82c3   ; La orden 2 no hace nada
	ld de,(ESCRIBE_TEXTO_DONDE_TOCA+1)		;82c5   ; Se parte del principio de la linea de ahora, no de donde se ha quedado
	ld a,e			;82c9
	add a,020h		;82ca   ; +32: la fila de caracteres de abajo
	ld e,a			;82cc
	ld a,000h		;82cd   ; El acarreo del +32 dice si hay que cambiar de tercio ...
	rla			;82cf
	add a,a			;82d0   ; ... y ese acarreo, por 8, es lo que se le suma al byte alto
	add a,a			;82d1
	add a,a			;82d2
	add a,d			;82d3
	ld d,a			;82d4
	ld (ESCRIBE_TEXTO_DONDE_TOCA+1),de		;82d5   ; La nueva linea queda apuntada como origen
	jp ESCRIBE_TEXTO		;82d9

; ----------------------------------------------------------------------
; Pintar un caracter: en la VRAM y en la pantalla del Spectrum emulada
; ----------------------------------------------------------------------
PINTA_UN_CARACTER:		; L = codigo, DE = direccion ZX. La fuente esta en 0xC800, 8 bytes por caracter
	ld h,019h		;82dc   ; H = 0x19 con L = codigo, y tres add hl,hl: 0xC800 + codigo*8
	add hl,hl			;82de
	add hl,hl			;82df
	add hl,hl			;82e0
	push de			;82e1
	push hl			;82e2
	call 004deh		;82e3   ; CELDA_A_VRAM: de la direccion ZX sale la del patron en la VRAM
	push de			;82e6
	ld bc,00008h		;82e7   ; Los 8 bytes del dibujo del caracter
	call 00439h		;82ea
	pop hl			;82ed
	ld de,02000h		;82ee   ; La tabla de color esta 0x2000 por encima de la de patrones
	add hl,de			;82f1
	ld bc,00008h		;82f2
	ld a,047h		;82f5   ; Operando automodificado (0x82F6): el atributo de los textos. 0x8166 le mete 0x78
	ld (08317h),a		;82f7   ; 0x8317 es el operando de 0x8316: la copia en RAM lleva el mismo atributo
	call 0049fh		;82fa   ; Atributo a byte de color
	call 00429h		;82fd   ; Los 8 bytes de color de la celda, todos iguales
	pop hl			;8300
	pop de			;8301
	ld c,d			;8302   ; C guarda el byte alto de la direccion ZX, que el bucle va a pisar
	ld b,007h		;8303   ; Siete inc, y la octava linea fuera del bucle
OCHO_LINEAS_DE_PIXEL:		; Copia el dibujo tambien a la pantalla emulada
	ld a,(hl)			;8305
	ld (de),a			;8306
	inc l			;8307   ; inc l dentro de la fuente, inc d en la pantalla: +256, la geometria del ZX
	inc d			;8308
	djnz OCHO_LINEAS_DE_PIXEL		;8309
	ld a,(hl)			;830b
	ld (de),a			;830c
	ld a,c			;830d   ; Con el byte alto de partida se saca la direccion del atributo ...
	rra			;830e
	rra			;830f
	rra			;8310
	and 003h		;8311
	or 058h		;8313   ; ... que es 0x58 mas el tercio
	ld d,a			;8315
	ld a,000h		;8316   ; Operando automodificado en 0x82F7: el mismo atributo de antes
	ld (de),a			;8318
	ld d,c			;8319   ; DE vuelve a apuntar a la celda con que se entro
	ret			;831a
RELOJ:		; Cuenta las vueltas del bucle; cada 256 avanza un dia y, al pasar de 60, un mes
	ld a,0ffh		;831b   ; Reloj: el operando de 0x831C es el TIC (0..255); lo llama el bucle de partida a cada vuelta (0x7F6B) y solo sigue una de cada 256
	inc a			;831d
	ld (RELOJ+1),a		;831e   ; La cuenta se guarda en el propio operando
	ret nz			;8321   ; Solo una de cada 256 vueltas sigue adelante
	ld hl,084f6h		;8322   ; 0x84F6: el hueco del panel Time donde se escribe la fecha
	ld a,000h		;8325   ; Reloj: el operando de 0x8326 es el DIA (1..60); se reescribe en 0x8367
	inc a			;8327   ; Un dia mas
	ld c,a			;8328
	cp 03dh		;8329   ; Dia 61: vuelve al 1 y pasa al mes siguiente
	jr nz,PINTA_LA_FECHA		;832b   ; Mientras no llegue a 61, solo hay que repintar el panel
	sub 03ch		;832d   ; Dia 61 pasa a ser el dia 1
	ld c,a			;832f
	push af			;8330
	push hl			;8331
	ld a,000h		;8332   ; Reloj: el operando de 0x8333 es la CUENTA ATRAS de meses (0x7F4F la pone a 255); a cero, derrota (0x83E1)
	dec a			;8334
	ld (08333h),a		;8335   ; Un mes menos de plazo
	jp z,DERROTA		;8338
	ld a,004h		;833b   ; 0x65FF con A = 4: pendiente de identificar
	call SIN_SONIDO		;833d
	ld hl,0853ah		;8340   ; Cada mes: mensaje "El Anillo corrompe al que lo usa." y +1 a los 256 contadores de 0xC300 (saturando en 255)
	ld (08242h),hl		;8343   ; 0x8242 es el buzon del panel Memo
	ld l,000h		;8346   ; 0xC300-0xC3FF: 256 contadores, uno por byte
	ld h,0c3h		;8348
SUMA_UN_MES_A_LOS_CONTADORES:		; Sube uno los 256 bytes de 0xC300, sin pasar de 255
	inc (hl)			;834a
	jr nz,SIGUIENTE_CONTADOR		;834b
	ld (hl),0ffh		;834d
SIGUIENTE_CONTADOR:		; Los 256 bytes de la pagina
	inc l			;834f
	jr nz,SUMA_UN_MES_A_LOS_CONTADORES		;8350
	pop hl			;8352
	pop af			;8353
	ld a,001h		;8354   ; Reloj: el operando de 0x8355 es el MES (1..12); se reescribe en 0x835D
	inc a			;8356   ; Un mes mas
	cp 00dh		;8357   ; Del 12 se vuelve al 1
	jr nz,GUARDA_EL_MES		;8359
	sub 00ch		;835b
GUARDA_EL_MES:		; Deja el mes en el operando de 0x8354
	ld (08355h),a		;835d
PINTA_LA_FECHA:		; Escribe "mes dia" en romanos en el hueco del panel Time y lo sube a pantalla
	ld a,(08355h)		;8360   ; Panel Time: escribe "mes dia" en romanos en 0x84F6 y lo pinta con 0x8280 (0x84F5 en 0x50C1)
	call NUMERO_EN_ROMANOS		;8363   ; Primero el mes
	ld a,c			;8366   ; C traia el dia
	ld (08326h),a		;8367   ; Se guarda en el operando de 0x8325
	ld (hl),020h		;836a   ; Un espacio entre el mes y el dia
	inc hl			;836c
	call NUMERO_EN_ROMANOS		;836d   ; Y ahora el dia
BORRA_LO_QUE_SOBRA:		; Rellena de espacios hasta el 0x21 que cierra el panel
	ld a,(hl)			;8370
	cp 021h		;8371   ; 0x21 es el caracter del marco: ahi se para
	jr z,SUBE_LA_FECHA		;8373
	ld (hl),020h		;8375   ; Lo que quedara de la fecha anterior se tapa con espacios
	inc hl			;8377
	jr BORRA_LO_QUE_SOBRA		;8378
SUBE_LA_FECHA:		; Escribe la linea del medio del panel Time en 0x50C1
	ld hl,084f5h		;837a   ; 0x84F5: la linea del hueco del panel Time
	ld de,050c1h		;837d   ; 0x50C1 es su sitio en la pantalla
	jp ESCRIBE_TEXTO		;8380
NUMERO_EN_ROMANOS:		; A = numero, HL = donde escribirlo. Suma L, X y las unidades de la tabla de 0x8516
	ld de,08538h		;8383   ; Numero A en romanos en (hl): L si A >= 50, una X por decena, y las unidades de la tabla de 0x8517 (4 bytes por entrada, la ultima letra con el bit 7)
	cp 031h		;8386   ; El 49 es el unico caso especial: se escribe IL, y ese IL esta en 0x8538
	jr z,COPIA_LAS_LETRAS		;8388
	cp 032h		;838a   ; Por debajo de 50 no hay L
	jr c,CUENTA_LAS_DECENAS		;838c
	sub 032h		;838e   ; Se le quita el 50 que vale la L
	ld (hl),04ch		;8390
	inc hl			;8392
CUENTA_LAS_DECENAS:		; Divide lo que queda entre 10 a base de restas
	ld b,000h		;8393
L_8395:
	inc b			;8395
	sub 00ah		;8396   ; Restando de diez en diez hasta pasarse
	jr nc,L_8395		;8398
	add a,00ah		;839a   ; Se deshace la resta que se paso ...
	dec b			;839c   ; ... y B queda con las decenas
	jr z,ESCRIBE_LAS_UNIDADES		;839d
ESCRIBE_LAS_DECENAS:		; Una X por cada decena
	ld (hl),058h		;839f   ; 0x58 = X. Nada de XL ni de XC: aqui se suma y ya
	inc hl			;83a1
	djnz ESCRIBE_LAS_DECENAS		;83a2
ESCRIBE_LAS_UNIDADES:		; Copia de la tabla las letras de las unidades
	and a			;83a4
	jr z,SIN_UNIDADES		;83a5   ; Sin unidades no hay nada mas que escribir
	dec a			;83a7
	add a,a			;83a8
	add a,a			;83a9
	add a,016h		;83aa   ; E = (unidades-1)*4 + 0x16: la tabla empieza en 0x8516, cuatro bytes por entrada
	ld e,a			;83ac
	adc a,085h		;83ad   ; El acarreo, propagado a mano sobre el 0x85 de arriba
	sub e			;83af
	ld d,a			;83b0
COPIA_LAS_LETRAS:		; Copia letra a letra hasta la que lleva el bit 7
	ld a,(de)			;83b1
	and a			;83b2
	jp m,ULTIMA_LETRA_83BC		;83b3   ; La ultima letra de cada entrada va con el bit 7 puesto
	ld (hl),a			;83b6
	inc hl			;83b7
	inc de			;83b8
	jp COPIA_LAS_LETRAS		;83b9
ULTIMA_LETRA_83BC:		; Le quita el bit 7 y la escribe
	and 07fh		;83bc   ; Sin el bit 7 ya es la letra de verdad
	ld (hl),a			;83be
	inc hl			;83bf
SIN_UNIDADES:		; Vuelve sin escribir nada
	ret			;83c0

; ----------------------------------------------------------------------
; El final del juego: primero "Pulsa Fuego", luego la pantalla que toque
; ----------------------------------------------------------------------
ESPERA_ANTES_DEL_FINAL:		; Pantalla en negro, "Pulsa Fuego." y espera a que se suelte y se vuelva a pulsar
	call BORRA_PANTALLA_NEGRA		;83c1
	ld hl,08427h		;83c4   ; 0x8427: el codigo 0xC0 0x00 lo pone en 0x4000 y detras va "Pulsa Fuego."
	call ESCRIBE_TEXTO		;83c7
ESPERA_A_SOLTAR_83CA:		; No sigue mientras el disparo siga pulsado
	call 0066dh		;83ca
	bit 4,a		;83cd
	jr nz,ESPERA_A_SOLTAR_83CA		;83cf
ESPERA_A_PULSAR_83D1:		; Y ahora espera a que se pulse
	call 0066dh		;83d1
	bit 4,a		;83d4
	jr z,ESPERA_A_PULSAR_83D1		;83d6
	ret			;83d8
VICTORIA:		; La pantalla de Gandalf: "THE FORCES OF EVIL HAVE BEEN DESTROYED"
	call ESPERA_ANTES_DEL_FINAL		;83d9
	ld hl,0094fh		;83dc   ; 0x094F, en el bloque bajo: la pantalla ZX completa de la victoria
	jr PINTA_LA_PANTALLA_FINAL		;83df
DERROTA:		; La pantalla de Sauron: "May the Forces of Evil Never be Defeated"
	call ESPERA_ANTES_DEL_FINAL		;83e1
	ld hl,0244fh		;83e4   ; 0x244F: la pantalla ZX completa de la derrota
PINTA_LA_PANTALLA_FINAL:		; Copia los 6912 bytes a 0x4000, los sube al VDP y se queda parado
	ld de,04000h		;83e7   ; 0x4000: la pantalla del Spectrum emulada
	ld bc,01b00h		;83ea   ; 0x1B00 = 6912 = 6144 de bitmap mas 768 de atributos
	ldir		;83ed
	call 005bdh		;83ef   ; El bitmap al VDP ...
	call 00604h		;83f2   ; ... y los atributos, traducidos a color
	di			;83f5   ; Se cierran las interrupciones: de aqui no se sale
FIN_DEL_JUEGO:		; Bucle cerrado sobre si mismo. El unico modo de salir es apagar
	jr FIN_DEL_JUEGO		;83f6

; ----------------------------------------------------------------------
; DATOS rellenos_del_mapa: Los cuatro rellenos de ELIGE_EL_RELLENO (0x7E7A),
;   que los mete en el operando de 0x7E75: 0x00, 0xFF, 0xAA y 0x55
;   0x83f8..0x83fc  (4 bytes)
DATA_rellenos_del_mapa:
	defb 000h,0ffh,0aah,055h	; 83f8

; ----------------------------------------------------------------------
; DATOS tramas_de_pinta_el_punto: Las cuatro que PINTA_EL_PUNTO (0x7E86)
;   indexa con los dos bits de abajo de L ... y se pisa antes de usarlas
;   (0x7E92): son datos MUERTOS
;   0x83fc..0x8400  (4 bytes)
DATA_tramas_de_pinta_el_punto:
	defb 003h,00ch,030h,0c0h	; 83fc

; ----------------------------------------------------------------------
; DATOS textos_de_los_paneles: Textos y marcos: "Volver/Cargar/Salvar", "Pulsa
;   Fuego" y los cuatro espacios de 0x846A con los que 0x820A borra el rotulo
;   0x8400..0x846f  (111 bytes)
DATA_textos_de_los_paneles:
	defb 003h,00bh,056h,06fh,06ch,076h,065h,072h,0b7h,0b7h,043h,061h,072h,067h,061h,072h	; 8400  ..Volver..Cargar
	defb 020h,020h,020h,0b7h,0b7h,053h,061h,06ch,076h,061h,072h,020h,020h,020h,0b7h,0b7h	; 8410     ..Salvar   ..
	defb 056h,06fh,06ch,076h,065h,072h,000h,0c0h,000h,020h,020h,020h,020h,020h,020h,020h	; 8420  Volver...       
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 8430                  
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 8440                  
	defb 020h,020h,020h,050h,075h,06ch,073h,061h,020h,046h,075h,065h,067h,06fh,02eh,020h	; 8450     Pulsa Fuego. 
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,000h,020h,020h,020h,020h,000h	; 8460           .    .

; ----------------------------------------------------------------------
; DATOS dibujos_del_terreno_alto: Cinco dibujos de 8x8 con los que
;   PINTA_TERRENO_ALTO (0x80BD) recorta sus cinco pixeles dobles: 0x846F el
;   tipo 13, 0x8477 los tipos 10, 14 y 15, 0x847F el 11, 0x8487 el 12 y 0x848F
;   NINGUNO (ver la errata del Z pisado en 0x80C4)
;   0x846f..0x8497  (40 bytes)
DATA_dibujos_del_terreno_alto:
	defb 044h,0aah,0eeh,044h,022h,055h,077h,022h	; 846f  D..D"Uw"
	defb 0ddh,0beh,06eh,0c4h,09bh,07dh,0f7h,0e3h	; 8477  ..n..}..
	defb 022h,077h,077h,000h,022h,077h,077h,000h	; 847f  "ww."ww.
	defb 0aah,055h,0aah,055h,0aah,055h,0aah,055h	; 8487  .U.U.U.U
	defb 022h,041h,091h,03bh,064h,082h,008h,01ch	; 848f  "A.;d...

; ----------------------------------------------------------------------
; DATOS textos_de_los_paneles_2: File/Memo/Time, numeros romanos I..VII, "El
;   Anillo corrompe al que lo usa", "Ningun mensaje" (los leen 0x8280 y
;   0x81C9)
;   0x8497..0x8572  (219 bytes)
DATA_textos_de_los_paneles_2:
	defb 000h,000h,0c8h,060h,023h,022h,022h,022h,022h,023h,0b7h,021h,020h,020h,020h,020h	; 8497  ...`#""""#.!    
	defb 021h,0b7h,021h,020h,07bh,07dh,020h,021h,0b7h,021h,020h,07eh,07fh,020h,021h,0b7h	; 84a7  !.! {} !.! ~. !.
	defb 021h,046h,069h,06ch,065h,021h,0b7h,021h,020h,020h,020h,020h,021h,0b7h,021h,020h	; 84b7  !File!.!    !.! 
	defb 07bh,07dh,020h,021h,0b7h,021h,020h,07eh,07fh,020h,021h,0b7h,021h,04dh,065h,06dh	; 84c7  {} !.! ~. !.!Mem
	defb 06fh,021h,0b7h,021h,020h,020h,020h,020h,021h,000h,0d0h,0a0h,021h,054h,069h,06dh	; 84d7  o!.!    !...!Tim
	defb 065h,023h,022h,022h,022h,022h,022h,022h,022h,022h,022h,023h,0b7h,021h,020h,020h	; 84e7  e#"""""""""#.!  
	defb 020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h,021h,0b7h,023h,022h	; 84f7              !.#"
	defb 022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,022h,023h,000h,0c9h	; 8507  """""""""""""#..
	defb 020h,020h,020h,049h,0c9h,020h,020h,049h,049h,0c9h,020h,049h,0d6h,020h,020h,0d6h	; 8517     I.  II. I.  .
	defb 020h,020h,020h,056h,0c9h,020h,020h,056h,049h,0c9h,020h,056h,049h,049h,0c9h,049h	; 8527     V.  VI. VII.I
	defb 0d8h,049h,0cch,045h,06ch,020h,041h,06eh,069h,06ch,06ch,06fh,020h,063h,06fh,072h	; 8537  .I.El Anillo cor
	defb 072h,06fh,06dh,070h,065h,020h,061h,06ch,020h,071h,075h,065h,020h,06ch,06fh,020h	; 8547  rompe al que lo 
	defb 075h,073h,061h,02eh,020h,020h,000h,04eh,069h,06eh,067h,075h,06eh,020h,06dh,065h	; 8557  usa.  .Ningun me
	defb 06eh,073h,061h,06ah,065h,020h,020h,020h,02eh,020h,000h	; 8567  nsaje   . .

; ======================================================================
; CODIGO 0x8572..0x8a51  (1247 bytes)
; ======================================================================


BORRA_UNA_FICHA_DE_LAS_DOS_LISTAS:		; Pone a cero los dos bytes de la ficha en las dos capas: asi 0x87A1 se la salta
	xor a			;8572   ; Cero quiere decir "esta ficha no ha cambiado, no la redibujes"
	ld (hl),a			;8573
	ld (de),a			;8574
	dec de			;8575
	dec hl			;8576
	ld (hl),a			;8577
	ld (de),a			;8578
	inc de			;8579
	inc hl			;857a
	ret			;857b

; ----------------------------------------------------------------------
; Averiguar que ficha va en una casilla del tablero
; ----------------------------------------------------------------------
FICHA_DE_LA_CASILLA:		; H,L = casilla; escribe en (DE) las fichas de la capa de abajo y las tres de la de arriba
	push hl			;857c
	push de			;857d
	call COORDENADAS_A_CASILLA		;857e   ; COORDENADAS_A_CASILLA: HL sale apuntando dentro del tablero de 0x5E00
	pop de			;8581
	ld a,(hl)			;8582   ; El contenido de la casilla: 0, 0xFF o el numero de unidad mas uno
	ld c,a			;8583
	pop hl			;8584
	ld b,001h		;8585   ; Ficha 1: casilla vacia
	or a			;8587
	jr z,FICHA_FIJA		;8588   ; Un cero es casilla vacia
	inc b			;858a   ; Ficha 2 si la casilla vale 0xFF ...
	inc a			;858b
	jr z,FICHA_FIJA		;858c
	inc b			;858e   ; ... y ficha 3 si vale 0xFE
	inc a			;858f
	jr nz,FICHA_DE_UNA_UNIDAD		;8590
FICHA_FIJA:		; Escribe la misma ficha en los dos bytes de la casilla
	ld a,b			;8592
	ld (de),a			;8593
	inc de			;8594
	ld (de),a			;8595
	jp PASA_DE_CASILLA		;8596   ; Y a por la casilla siguiente
FICHA_DE_UNA_UNIDAD:		; Busca en la tabla de 0x94C7 los cuatro pisos del dibujo de la unidad
	dec c			;8599   ; Del contenido de la casilla se quita el uno: queda el numero de unidad
	push hl			;859a
	ld b,0beh		;859b   ; 0xBE00+n: la X y las banderas de la unidad
	ld a,(bc)			;859d
	ld b,0c4h		;859e   ; 0xC400+n: el tipo de unidad
	bit 6,a		;85a0   ; Bit 6 de 0xBE00: la unidad esta en contacto con otra
	ld a,(bc)			;85a2
	ld b,0c8h		;85a3   ; 0xC800+n: el byte de direccion y fotograma
	jr z,DIBUJO_NORMAL		;85a5
	ex af,af'			;85a7
	ld a,(bc)			;85a8
	and 001h		;85a9   ; En contacto y con el bit 0 puesto, el dibujo sale de la otra tabla
	jr nz,DIBUJO_ADELANTADO		;85ab
	ex af,af'			;85ad
DIBUJO_NORMAL:		; HL = 0x94C7 + tipo*8 + (fotograma y 3)*4: cuatro numeros de ficha
	add a,a			;85ae   ; Tres add a,a: el tipo por ocho
	add a,a			;85af
	add a,a			;85b0
	add a,0c7h		;85b1   ; 0x94C7 es donde empieza la tabla de dibujos
	ld l,a			;85b3
	adc a,094h		;85b4
	sub l			;85b6
	ld h,a			;85b7
	ld a,(bc)			;85b8   ; 0xC800+n otra vez: se queda en C como byte de banderas de la ficha
	ld c,a			;85b9
	and 003h		;85ba   ; Bits 0-1: cuatro poses de cuatro bytes cada una
	add a,a			;85bc
	add a,a			;85bd
	add a,l			;85be
	ld l,a			;85bf
	adc a,h			;85c0
	sub l			;85c1
	ld h,a			;85c2
	set 6,c		;85c3   ; El bit 6 siempre puesto en las banderas de la ficha
REPARTE_LOS_CUATRO_PISOS:		; El piso de abajo a la capa 0xE800 y los tres de arriba a la 0xEB00
	push de			;85c5   ; IX e IY arrancan los dos en la ficha de la casilla
	push de			;85c6
	pop iy		;85c7
	pop ix		;85c9
	ld a,(hl)			;85cb   ; Primer numero de ficha de la tabla
	inc hl			;85cc
	ld (ix+001h),a		;85cd   ; El piso de abajo, en la capa de abajo
	ld (ix+000h),c		;85d0   ; Y sus banderas al lado
	defb 0ddh,07ch	;ld a,ixh		;85d3   ; IX sube 0x300: de la capa de 0xE800 a la de 0xEB00
	add a,003h		;85d5
	defb 0ddh,067h	;ld ixh,a		;85d7
	ld a,(hl)			;85d9
	inc hl			;85da
	ld (ix-01fh),a		;85db   ; -0x20 = una fila mas arriba: 32 bytes por fila de fichas
	ld (ix-020h),c		;85de
	ld a,(hl)			;85e1
	inc hl			;85e2
	ld (ix-03fh),a		;85e3   ; -0x40: dos filas mas arriba
	ld (ix-040h),c		;85e6
	ld a,(hl)			;85e9
	or a			;85ea   ; Un cero en la tabla quiere decir que el dibujo no tiene cuarto piso
	jr z,SIGUIENTE_CASILLA		;85eb
	ld a,(ix-05fh)		;85ed   ; Si en ese hueco de la capa de arriba ya habia algo ...
	or a			;85f0
	jr z,PONE_EL_PISO_ALTO		;85f1
	ld (iy-05fh),a		;85f3   ; ... se baja a la capa de abajo, que es la que tapa
	ld a,(ix-060h)		;85f6
	ld (iy-060h),a		;85f9
PONE_EL_PISO_ALTO:		; Escribe el cuarto piso en la capa de arriba
	ld a,(hl)			;85fc
	ld (ix-05fh),a		;85fd   ; -0x60: tres filas mas arriba, la cabeza del dibujo
	ld (ix-060h),c		;8600
SIGUIENTE_CASILLA:		; Recupera la casilla y sigue el barrido de 0x86CE
	pop hl			;8603
	inc de			;8604
	jp PASA_DE_CASILLA		;8605
DIBUJO_ADELANTADO:		; Igual que 0x85AE pero con la tabla de 0x9537 y corrido una casilla hacia donde mira
	ex af,af'			;8608
	add a,a			;8609
	add a,a			;860a
	add a,a			;860b
	add a,037h		;860c   ; 0x9537: la otra tabla de dibujos, la de las unidades en contacto
	ld l,a			;860e
	adc a,095h		;860f
	sub l			;8611
	ld h,a			;8612
	ld a,(bc)			;8613
	ld c,a			;8614
	and 002h		;8615   ; Aqui solo cuenta el bit 1: dos poses de ocho bytes
	add a,a			;8617
	add a,a			;8618
	add a,l			;8619
	ld l,a			;861a
	adc a,h			;861b
	sub l			;861c
	ld h,a			;861d
	set 6,c		;861e   ; Bit 6 de las banderas, como en el otro camino
	push de			;8620
	push de			;8621
	pop iy		;8622
	pop ix		;8624
	ld a,003h		;8626   ; IX se sube 0x300: la capa de arriba
	defb 0ddh,084h	;add a,ixh		;8628
	defb 0ddh,067h	;ld ixh,a		;862a
	ld a,c			;862c
	or a			;862d   ; Bit 7 de las banderas: la unidad mira a la izquierda
	jp p,ADELANTA_A_LA_IZQUIERDA		;862e
	ld a,e			;8631   ; Los cinco bits bajos de E son la columna dentro de la fila de 32 bytes
	and 01fh		;8632
	cp 01eh		;8634   ; 0x1E es la ultima columna: ahi no se puede correr a la derecha
	jr z,NO_CABE_ADELANTADO		;8636
	inc ix		;8638   ; Dos bytes = una ficha a la derecha
	inc ix		;863a
	inc iy		;863c
	inc iy		;863e
	jr TRES_PISOS_ADELANTADOS		;8640
ADELANTA_A_LA_IZQUIERDA:		; Corre el dibujo una ficha hacia la izquierda
	ld a,e			;8642   ; Y por el otro lado, la columna 0 no puede correrse a la izquierda
	and 01fh		;8643
	jr z,NO_CABE_ADELANTADO		;8645
	dec ix		;8647   ; Dos bytes = una ficha a la izquierda
	dec ix		;8649
	dec iy		;864b
	dec iy		;864d
TRES_PISOS_ADELANTADOS:		; Escribe los tres pisos altos; el de abajo no se dibuja
	inc hl			;864f   ; El primer byte de la entrada se salta: aqui no hay piso de abajo
	ld a,(hl)			;8650
	inc hl			;8651
	or a			;8652   ; Un cero corta el dibujo
	jr z,PISO_2_ADELANTADO		;8653
	ex af,af'			;8655
	ld a,(ix-01fh)		;8656   ; Si el hueco de la capa de arriba estaba ocupado, se baja a la de abajo
	or a			;8659
	jr z,PISO_1_ADELANTADO		;865a
	ld (iy-01fh),a		;865c
	ld a,(ix-020h)		;865f
	ld (iy-020h),a		;8662
PISO_1_ADELANTADO:		; Deja el primer piso en la capa de arriba
	ex af,af'			;8665
	ld (ix-01fh),a		;8666
	ld (ix-020h),c		;8669
PISO_2_ADELANTADO:		; Segundo piso, dos filas mas arriba
	ld a,(hl)			;866c
	inc hl			;866d   ; El byte siguiente de la tabla de dibujos
	or a			;866e   ; Un cero cierra el dibujo
	jr z,PISO_3_ADELANTADO		;866f
	ex af,af'			;8671
	ld a,(ix-03fh)		;8672   ; La capa de arriba, dos filas por encima
	or a			;8675
	jr z,GUARDA_PISO_2		;8676
	ld (iy-03fh),a		;8678   ; Lo que hubiera ahi se baja a la capa de abajo
	ld a,(ix-040h)		;867b
	ld (iy-040h),a		;867e
GUARDA_PISO_2:		; Escribe el segundo piso
	ex af,af'			;8681
	ld (ix-03fh),a		;8682
	ld (ix-040h),c		;8685
PISO_3_ADELANTADO:		; Tercer piso, tres filas mas arriba
	ld a,(hl)			;8688
	inc hl			;8689   ; El tercer piso
	or a			;868a
	jp z,REPARTE_LOS_CUATRO_PISOS		;868b   ; Un cero: el dibujo no llega tan arriba
	ex af,af'			;868e
	ld a,(ix-05fh)		;868f   ; Tres filas por encima, en la capa de arriba
	or a			;8692
	jr z,GUARDA_PISO_3		;8693
	ld (iy-05fh),a		;8695   ; Y lo que hubiera, a la capa de abajo
	ld a,(ix-060h)		;8698
	ld (iy-060h),a		;869b
GUARDA_PISO_3:		; Escribe el tercer piso y vuelve al barrido
	ex af,af'			;869e
	ld (ix-05fh),a		;869f
	ld (ix-060h),c		;86a2
	jp REPARTE_LOS_CUATRO_PISOS		;86a5
NO_CABE_ADELANTADO:		; En los bordes no se dibuja: se saltan los cuatro bytes de la entrada
	inc hl			;86a8
	inc hl			;86a9
	inc hl			;86aa
	inc hl			;86ab
	jp REPARTE_LOS_CUATRO_PISOS		;86ac

; ----------------------------------------------------------------------
; Montar la pantalla de batalla: de las casillas del tablero a las listas de fichas
; ----------------------------------------------------------------------
MONTA_LA_PANTALLA_DE_BATALLA:		; Rellena las listas de 0xE800/0xEB00 con lo que se ve alrededor de 0x8E0E y lo dibuja
	ld hl,0e800h		;86af   ; 0xE800-0xECFF a cero: las dos capas de fichas
	push hl			;86b2
	ld de,0e801h		;86b3
	ld bc,004ffh		;86b6
	ld (hl),000h		;86b9
	ldir		;86bb
	pop de			;86bd
	ld hl,(08e0eh)		;86be   ; 0x8E0E es la casilla del centro de la pantalla
	ld a,h			;86c1   ; Ocho casillas hacia atras en las dos coordenadas: la esquina de arriba
	sub 008h		;86c2
	ld h,a			;86c4
	ld a,l			;86c5
	sub 008h		;86c6
	ld (086d0h),a		;86c8   ; 0x86D0 es el operando del ld l,nn de 0x86CF: la columna de partida
	exx			;86cb
	ld c,013h		;86cc   ; 0x13 = 19 filas de casillas
UNA_FILA_DEL_TABLERO:		; Recorre 16 casillas de la fila, de izquierda a derecha
	exx			;86ce
	ld l,000h		;86cf   ; Operando automodificado en 0x86C8
	ld a,h			;86d1
	or a			;86d2
	jp m,FILA_ENTERA_FUERA		;86d3   ; Coordenada negativa: fuera del tablero
	cp 020h		;86d6   ; De 0x20 arriba tambien: el tablero es de 32x32
	jr c,FILA_DENTRO		;86d8
FILA_ENTERA_FUERA:		; Toda la fila cae fuera: 32 bytes de ficha 1, la vacia
	ld b,020h		;86da   ; 32 bytes = las 16 fichas de la fila
	ld a,001h		;86dc   ; Ficha 1: la que borra la celda
RELLENA_DE_VACIO:		; Escribe la ficha vacia 32 veces
	ld (de),a			;86de
	inc de			;86df
	djnz RELLENA_DE_VACIO		;86e0
	jp PASA_DE_FILA		;86e2
FILA_DENTRO:		; La fila esta dentro: se miran sus 16 casillas una a una
	exx			;86e5
	ld b,010h		;86e6   ; 16 fichas de ancho
UNA_CASILLA_DE_LA_FILA:		; Mira si la casilla cae dentro del tablero y va a por su ficha
	exx			;86e8
	ld a,l			;86e9
	or a			;86ea
	jp m,CASILLA_FUERA		;86eb   ; Columna negativa: fuera
	cp 020h		;86ee   ; De 0x20 arriba, tambien fuera
	jp c,FICHA_DE_LA_CASILLA		;86f0   ; Dentro: se busca que ficha le toca
CASILLA_FUERA:		; Las dos fichas de una casilla que no existe
	ld a,001h		;86f3
	ld (de),a			;86f5
	inc de			;86f6
	ld (de),a			;86f7
PASA_DE_CASILLA:		; Dos bytes por ficha, una columna mas
	inc de			;86f8
	inc l			;86f9
	exx			;86fa
	djnz UNA_CASILLA_DE_LA_FILA		;86fb
	exx			;86fd
PASA_DE_FILA:		; Fila siguiente del tablero
	inc h			;86fe
	exx			;86ff
	dec c			;8700
	jr nz,UNA_FILA_DEL_TABLERO		;8701
	ld ix,0e910h		;8703   ; 0xE910 es la ficha del centro de la pantalla (fila 8, columna 8)
	ld iy,0ec10h		;8707   ; 0xEC10, la misma en la capa de arriba
	ld b,(ix+000h)		;870b
	ld c,(ix+001h)		;870e
	ld a,b			;8711
	cp 004h		;8712   ; Las fichas 0, 1, 2 y 3 son las fijas: no hay unidad
	jr c,CENTRO_SIEMPRE_MARCADO		;8714
	ld a,(iy+000h)		;8716   ; Si el hueco de arriba esta libre ...
	or a			;8719
	jr nz,BUSCA_LO_QUE_HA_CAMBIADO		;871a
	ld (iy+000h),b		;871c   ; ... la unidad del centro se sube a la capa de arriba
	ld (iy+001h),c		;871f
CENTRO_SIEMPRE_MARCADO:		; El centro se pone a ficha 3 y se fuerza su redibujado
	ld (ix+000h),003h		;8722   ; Ficha 3, la del cursor de batalla (dibujo en 0x95A8)
	ld (ix+001h),003h		;8726
	ld a,0ffh		;872a
	ld (0ef10h),a		;872c   ; 0xEF10 es la copia vieja del centro: un 0xFF ahi obliga a repintarlo
BUSCA_LO_QUE_HA_CAMBIADO:		; Compara las dos capas con las de la vuelta anterior y borra las fichas iguales
	ld b,000h		;872f   ; B = 0: 256 fichas
	ld ix,0f000h		;8731   ; 0xF000: la copia vieja de la capa de arriba
	ld iy,0ee00h		;8735   ; 0xEE00: la copia vieja de la capa de abajo
	ld de,0eb00h		;8739   ; 0xEB00: la capa de arriba de ahora
	ld hl,0e800h		;873c   ; 0xE800: la capa de abajo de ahora
COMPARA_UNA_FICHA:		; Compara los cuatro bytes de una ficha con los de la vuelta anterior
	ld a,(hl)			;873f
	cp (iy+000h)		;8740   ; Contra la copia vieja ...
	ld (iy+000h),a		;8743   ; ... que de paso se pone al dia
	jr z,SIGUE_COMPARANDO		;8746   ; Igual: aun puede ser que no haya cambiado nada
	ld a,(de)			;8748   ; Distinto: se copia sin comparar y se dara por cambiada
	ld (ix+000h),a		;8749
COPIA_SIN_COMPARAR:		; Ha cambiado algo: solo hay que poner al dia las copias
	inc hl			;874c
	inc de			;874d   ; Los cuatro punteros avanzan a la vez
	inc ix		;874e
	inc iy		;8750
	ld a,(hl)			;8752   ; El byte nuevo pisa al viejo en la copia
	ld (iy+000h),a		;8753
COPIA_EL_ULTIMO_BYTE:		; Ultimo byte a la copia vieja
	ld a,(de)			;8756
	ld (ix+000h),a		;8757
	jp PASA_A_LA_FICHA_SIGUIENTE		;875a
SIGUE_COMPARANDO:		; Los tres bytes que quedan; si los cuatro son iguales, la ficha se borra
	ld a,(de)			;875d
	cp (ix+000h)		;875e   ; Segundo byte contra su copia
	ld (ix+000h),a		;8761   ; Y la copia se pone al dia
	jr nz,COPIA_SIN_COMPARAR		;8764   ; Distinto: la ficha ha cambiado
	inc de			;8766
	inc hl			;8767
	inc ix		;8768
	inc iy		;876a
	ld a,(hl)			;876c   ; Tercer byte
	cp (iy+000h)		;876d
	ld (iy+000h),a		;8770
	jr nz,COPIA_EL_ULTIMO_BYTE		;8773
	ld a,(de)			;8775   ; Y el cuarto
	cp (ix+000h)		;8776
	ld (ix+000h),a		;8779
	call z,BORRA_UNA_FICHA_DE_LAS_DOS_LISTAS		;877c   ; Los cuatro bytes iguales: la ficha se pone a cero y no se redibuja
PASA_A_LA_FICHA_SIGUIENTE:		; Los cuatro punteros avanzan un byte mas
	inc hl			;877f
	inc de			;8780
	inc ix		;8781
	inc iy		;8783
	djnz COMPARA_UNA_FICHA		;8785
	ld de,04040h		;8787   ; 0x4040: la pantalla de batalla empieza en la fila 2
	ld hl,0e800h		;878a
	exx			;878d
	ld c,010h		;878e   ; 16 filas de fichas
DIBUJA_UNA_FILA:		; Guarda donde empieza la fila y recorre sus 16 fichas
	exx			;8790
	ld (08836h),de		;8791   ; 0x8836 es el operando del ld de de 0x8835: el principio de la fila
	exx			;8795
	ld b,010h		;8796   ; 16 fichas por fila
DIBUJA_UNA_FICHA:		; Pinta la ficha de la capa de abajo y luego la de la de arriba
	exx			;8798
	ld (SIGUIENTE_FICHA+1),de		;8799   ; 0x8826 es el operando del ld de de 0x8825: donde va esta ficha
	ld (087dch),hl		;879d   ; 0x87DC es el operando del ld hl de 0x87DB: la ficha en la lista
	ld a,(hl)			;87a0
	or a			;87a1   ; Un cero: esta ficha no ha cambiado
	jp z,SIGUIENTE_FICHA		;87a2
	ld c,a			;87a5   ; El byte de banderas
	inc hl			;87a6
	ld a,(hl)			;87a7
	dec a			;87a8   ; Ficha 1: borrar la celda
	jp z,FICHA_1_BORRA		;87a9
	dec a			;87ac   ; Ficha 2: el dibujo de 0x9608
	jp z,FICHA_2		;87ad
	dec a			;87b0   ; Ficha 3: el de 0x95A8
	jp z,FICHA_3		;87b1
	dec a			;87b4   ; De la 4 en adelante, la tabla de dibujos ...
	ld l,a			;87b5
	ld h,000h		;87b6
	add hl,hl			;87b8   ; ... con 32 bytes por ficha: 16 parejas de mascara y dato
	add hl,hl			;87b9
	add hl,hl			;87ba
	add hl,hl			;87bb
	add hl,hl			;87bc
	ld a,l			;87bd
	add a,0e8h		;87be   ; 0xA2E8, en el bloque alto: ahi estan los dibujos de las fichas
	ld l,a			;87c0
	ld a,h			;87c1
	adc a,0a2h		;87c2
	ld h,a			;87c4
	inc hl			;87c5   ; Un byte mas: la capa de abajo entra en el DATO de la primera pareja
	ld a,c			;87c6
	or a			;87c7
	jp m,FICHA_DE_ABAJO_REFLEJADA		;87c8   ; Bit 7 de las banderas: la ficha se pinta reflejada
PINTA_LA_FICHA_DE_ABAJO:		; Cuatro pasadas de dos lineas: 16x8 pixeles sin mascara
	call DOS_LINEAS_SIN_MASCARA		;87cb   ; La capa de abajo se escribe tal cual, sin recortar
	call DOS_LINEAS_SIN_MASCARA		;87ce
	call DOS_LINEAS_SIN_MASCARA		;87d1
	call DOS_LINEAS_SIN_MASCARA		;87d4
PINTA_LA_FICHA_DE_ARRIBA:		; La misma celda, ahora con la lista de 0xEB00 y respetando lo que ya hay
	ld de,(SIGUIENTE_FICHA+1)		;87d7   ; Vuelve a la direccion de pantalla de la celda
	ld hl,00000h		;87db   ; Operando automodificado en 0x879D: la ficha en la lista de abajo
	ld a,h			;87de   ; +0x300: la misma ficha en la lista de arriba
	add a,003h		;87df
	ld h,a			;87e1
	ld a,(hl)			;87e2
	or a			;87e3
	jp z,SIGUIENTE_FICHA		;87e4   ; Cero: tampoco ha cambiado
	ld c,a			;87e7
	inc hl			;87e8
	ld a,(hl)			;87e9
	sub 004h		;87ea   ; Aqui no hay fichas fijas: se resta 4 y se va a la tabla
	ld l,a			;87ec
	ld h,000h		;87ed
	add hl,hl			;87ef
	add hl,hl			;87f0
	add hl,hl			;87f1
	add hl,hl			;87f2
	add hl,hl			;87f3
	ld a,l			;87f4
	add a,0e8h		;87f5
	ld l,a			;87f7
	ld a,h			;87f8
	adc a,0a2h		;87f9
	ld h,a			;87fb
	ld a,c			;87fc
	or a			;87fd   ; Bit 7: reflejada
	jp m,FICHA_DE_ARRIBA_REFLEJADA		;87fe
	call DOS_LINEAS_CON_MASCARA		;8801   ; Tres pasadas de dos lineas ...
	call DOS_LINEAS_CON_MASCARA		;8804
	call DOS_LINEAS_CON_MASCARA		;8807
	ld a,(de)			;880a   ; ... y la cuarta escrita a pelo, sin call
	and (hl)			;880b
	inc hl			;880c
	or (hl)			;880d
	inc hl			;880e
	ld (de),a			;880f
	inc e			;8810
	ld a,(de)			;8811
	and (hl)			;8812
	inc hl			;8813
	or (hl)			;8814
	inc hl			;8815
	ld (de),a			;8816
	inc d			;8817
	ld a,(de)			;8818
	and (hl)			;8819
	inc hl			;881a
	or (hl)			;881b
	inc hl			;881c
	ld (de),a			;881d
	dec e			;881e
	ld a,(de)			;881f
	and (hl)			;8820
	inc hl			;8821
	or (hl)			;8822
	inc hl			;8823
	ld (de),a			;8824
SIGUIENTE_FICHA:		; Operando automodificado en 0x8799: la celda que toca
	ld de,00000h		;8825
	ld hl,(087dch)		;8828   ; Operando automodificado en 0x879D: la ficha en la lista
	inc e			;882b   ; Dos celdas: cada ficha mide 16 pixeles de ancho
	inc e			;882c
	inc l			;882d   ; Y dos bytes en la lista de fichas
	inc hl			;882e
	exx			;882f
	dec b			;8830
	jp nz,DIBUJA_UNA_FICHA		;8831
	exx			;8834
	ld de,00000h		;8835   ; Operando automodificado en 0x8791: donde empezaba la fila
	ld a,e			;8838
	add a,020h		;8839   ; +32: la fila de caracteres de abajo
	ld e,a			;883b
	ld a,000h		;883c   ; El acarreo dice si se cambia de tercio ...
	rla			;883e
	add a,a			;883f   ; ... y por ocho es lo que se le suma al byte alto
	add a,a			;8840
	add a,a			;8841
	add a,d			;8842
	ld d,a			;8843
	exx			;8844
	dec c			;8845
	jp nz,DIBUJA_UNA_FILA		;8846
	call 005bdh		;8849   ; Toda la pantalla al VDP: primero el dibujo ...
	call 00604h		;884c   ; ... y luego los atributos
	ret			;884f
FICHA_3:		; El dibujo de la ficha 3 esta en 0x95A8
	ld hl,095a8h		;8850
	jp PINTA_LA_FICHA_DE_ABAJO		;8853
FICHA_2:		; El de la ficha 2, en 0x9608
	ld hl,09608h		;8856
	jp PINTA_LA_FICHA_DE_ABAJO		;8859
FICHA_1_BORRA:		; Pone a cero las dos celdas de la ficha: es la ficha vacia
	ex de,hl			;885c
	push hl			;885d
	xor a			;885e   ; Cero: se apaga todo
	call APAGA_CUATRO_LINEAS		;885f   ; Cuatro lineas por llamada, ocho en total
	call APAGA_CUATRO_LINEAS		;8862
	pop hl			;8865
	ex de,hl			;8866
	jp PINTA_LA_FICHA_DE_ARRIBA		;8867
APAGA_CUATRO_LINEAS:		; Ocho bytes a cero en dos columnas por cuatro lineas
	ld (hl),a			;886a
	inc l			;886b   ; Dos bytes seguidos: las dos celdas de la ficha
	ld (hl),a			;886c
	inc h			;886d   ; inc h: la linea de pixeles de abajo, a la manera del Spectrum
	ld (hl),a			;886e
	dec l			;886f
	ld (hl),a			;8870
	inc h			;8871   ; Cuatro lineas por vuelta
	ld (hl),a			;8872
	inc l			;8873
	ld (hl),a			;8874
	inc h			;8875
	ld (hl),a			;8876
	dec l			;8877
	ld (hl),a			;8878
	inc h			;8879
	ret			;887a
DOS_LINEAS_CON_MASCARA:		; Dos lineas de 16 pixeles: and con la mascara y or con el dibujo
	ld a,(de)			;887b   ; Byte de la pantalla, recortado con la mascara ...
	and (hl)			;887c
	inc hl			;887d
	or (hl)			;887e   ; ... y encima el dibujo
	inc hl			;887f
	ld (de),a			;8880
	inc e			;8881   ; La celda de la derecha
	ld a,(de)			;8882
	and (hl)			;8883
	inc hl			;8884
	or (hl)			;8885
	inc hl			;8886
	ld (de),a			;8887
	inc d			;8888   ; Linea de pixeles siguiente
	ld a,(de)			;8889
	and (hl)			;888a
	inc hl			;888b
	or (hl)			;888c
	inc hl			;888d
	ld (de),a			;888e
	dec e			;888f
	ld a,(de)			;8890
	and (hl)			;8891
	inc hl			;8892
	or (hl)			;8893
	inc hl			;8894
	ld (de),a			;8895
	inc d			;8896   ; Y otra linea mas
	ret			;8897
FICHA_DE_ARRIBA_REFLEJADA:		; La misma ficha con mascara pero dandole la vuelta a cada byte
	inc e			;8898   ; Se empieza por la celda derecha: el dibujo va al reves
	ld b,003h		;8899   ; B = 3: la tabla de bytes invertidos vive en 0x0300
	call DOS_LINEAS_REFLEJADAS		;889b
	inc d			;889e
	call DOS_LINEAS_REFLEJADAS		;889f
	inc d			;88a2
	call DOS_LINEAS_REFLEJADAS		;88a3
	inc d			;88a6
	call DOS_LINEAS_REFLEJADAS		;88a7
	jp SIGUIENTE_FICHA		;88aa
DOS_LINEAS_REFLEJADAS:		; Las dos celdas de dos lineas, cada byte por la tabla de 0x0300
	call UN_BYTE_REFLEJADO		;88ad   ; Primero la celda de la derecha: el dibujo reflejado va de derecha a izquierda
	dec e			;88b0   ; Y luego la de la izquierda
	call UN_BYTE_REFLEJADO		;88b1
	inc d			;88b4   ; Linea de pixeles siguiente
	call UN_BYTE_REFLEJADO		;88b5
	inc e			;88b8
UN_BYTE_REFLEJADO:		; Mascara y dibujo, los dos pasados por la tabla de bytes invertidos
	ld c,(hl)			;88b9
	inc hl			;88ba
	ld a,(bc)			;88bb   ; 0x0300 + byte: el mismo byte con los bits del reves
	ld c,a			;88bc
	ld a,(de)			;88bd
	and c			;88be   ; La mascara recorta lo que ya habia
	ld (de),a			;88bf
	ld c,(hl)			;88c0
	inc hl			;88c1
	ld a,(bc)			;88c2
	ld c,a			;88c3
	ld a,(de)			;88c4
	or c			;88c5   ; Y el dibujo se le suma encima
	ld (de),a			;88c6
	ret			;88c7
FICHA_DE_ABAJO_REFLEJADA:		; La capa de abajo reflejada: cuatro pasadas de dos lineas
	inc e			;88c8
	ld b,003h		;88c9   ; La tabla de bytes invertidos de 0x0300
	call DOS_LINEAS_REFLEJADAS_SIN_MASCARA		;88cb
	call DOS_LINEAS_REFLEJADAS_SIN_MASCARA		;88ce
	call DOS_LINEAS_REFLEJADAS_SIN_MASCARA		;88d1
	call DOS_LINEAS_REFLEJADAS_SIN_MASCARA		;88d4
	jp PINTA_LA_FICHA_DE_ARRIBA		;88d7
DOS_LINEAS_REFLEJADAS_SIN_MASCARA:		; Cuatro bytes invertidos escritos tal cual
	ld c,(hl)			;88da   ; La mascara, invertida por la tabla de 0x0300
	ld a,(bc)			;88db
	ld (de),a			;88dc
	inc hl			;88dd
	inc hl			;88de   ; inc hl dos veces: de cada pareja mascara/dato solo se coge el dato
	dec e			;88df   ; Se retrocede: en la ficha reflejada se va de derecha a izquierda
	ld c,(hl)			;88e0
	ld a,(bc)			;88e1
	ld (de),a			;88e2
	inc hl			;88e3
	inc hl			;88e4
	inc d			;88e5   ; Linea de pixeles siguiente
	ld c,(hl)			;88e6
	ld a,(bc)			;88e7
	ld (de),a			;88e8
	inc hl			;88e9
	inc hl			;88ea
	inc e			;88eb   ; Vuelve a la celda de la derecha
	ld c,(hl)			;88ec
	ld a,(bc)			;88ed
	ld (de),a			;88ee
	inc hl			;88ef
	inc hl			;88f0
	inc d			;88f1   ; Y otra linea mas
	ret			;88f2
DOS_LINEAS_SIN_MASCARA:		; Cuatro bytes escritos tal cual, sin recortar lo que hubiera
	ld a,(hl)			;88f3   ; El dato, escrito tal cual
	ld (de),a			;88f4
	inc e			;88f5   ; La celda de la derecha
	inc hl			;88f6   ; inc hl dos veces: aqui tampoco se usa la mascara, la capa de abajo no recorta nada
	inc hl			;88f7
	ld a,(hl)			;88f8
	ld (de),a			;88f9
	inc hl			;88fa
	inc hl			;88fb
	inc d			;88fc   ; Linea de pixeles siguiente
	ld a,(hl)			;88fd
	ld (de),a			;88fe
	inc hl			;88ff
	inc hl			;8900
	dec e			;8901   ; Vuelve a la celda de la izquierda
	ld a,(hl)			;8902
	ld (de),a			;8903
	inc hl			;8904
	inc hl			;8905
	inc d			;8906   ; Y otra linea
	ret			;8907

; ----------------------------------------------------------------------
; A donde moverse para acercarse al objetivo. Devuelve el codigo de direccion, que es el mismo byte que dice como se dibuja
; ----------------------------------------------------------------------
HACIA_EL_OBJETIVO_A:		; B,C = donde estoy, D,E = adonde voy. Compara primero la coordenada C
	ld a,c			;8908   ; Primero la coordenada C contra la E ...
	cp e			;8909
	ld a,b			;890a
	jr z,MISMA_COLUMNA_8915		;890b
	jr c,C_MENOR		;890d
	cp d			;890f   ; ... y luego la B contra la D
	jr nc,DIAGONAL_LAS_DOS_MENOS		;8910
	jp DIAGONAL_B_MAS_C_MENOS		;8912
MISMA_COLUMNA_8915:		; Coinciden en C: solo queda decidir por la otra coordenada
	cp d			;8915
	jr z,YA_ESTA_AL_LADO		;8916   ; Las dos iguales: ya se ha llegado
	jr nc,DIAGONAL_LAS_DOS_MENOS		;8918
	jp DIAGONAL_LAS_DOS_MAS		;891a
C_MENOR:		; Con C por debajo de E, el otro eje decide entre dos diagonales
	cp d			;891d
	jr c,DIAGONAL_LAS_DOS_MAS		;891e
	jr z,DIAGONAL_LAS_DOS_MAS		;8920
	jp DIAGONAL_C_MAS_B_MENOS		;8922
HACIA_EL_OBJETIVO_B:		; Lo mismo pero mirando primero B contra D. 0x89B4 sortea cual de las dos se usa
	ld a,b			;8925   ; Aqui se empieza por la coordenada B
	cp d			;8926
	ld a,c			;8927
	jr z,MISMA_FILA		;8928
	jr c,B_MENOR		;892a
	cp e			;892c
	jr c,DIAGONAL_C_MAS_B_MENOS		;892d
	jr z,DIAGONAL_C_MAS_B_MENOS		;892f
	jr DIAGONAL_LAS_DOS_MENOS		;8931
MISMA_FILA:		; Coinciden en B: decide la otra coordenada
	cp e			;8933
	jr z,YA_ESTA_AL_LADO		;8934
	jr nc,DIAGONAL_B_MAS_C_MENOS		;8936
	jp DIAGONAL_C_MAS_B_MENOS		;8938
B_MENOR:		; Con B por debajo de D, decide la otra coordenada
	cp e			;893b
	jr c,DIAGONAL_LAS_DOS_MAS		;893c
DIAGONAL_B_MAS_C_MENOS:		; B sube y C baja. Devuelve 0x80: mira a la izquierda
	ld a,b			;893e
	cp 01eh		;893f   ; El tablero acaba en 0x1E: no se sale del borde
	jr nc,DEVUELVE_80		;8941
	ld a,c			;8943
	cp 002h		;8944   ; Ni por el otro lado del 2
	jr c,DEVUELVE_80		;8946
	inc b			;8948   ; Las dos coordenadas a la vez: solo se anda en diagonal
	dec c			;8949
DEVUELVE_80:		; Codigo de direccion 0x80
	ld a,080h		;894a   ; 0x80 es el codigo de direccion, y su bit 7 es "dibujate reflejada"
	ret			;894c
DIAGONAL_C_MAS_B_MENOS:		; C sube y B baja. Devuelve 0x02
	ld a,b			;894d
	cp 002h		;894e
	jr c,DEVUELVE_02		;8950
	ld a,c			;8952
	cp 01eh		;8953
	jr nc,DEVUELVE_02		;8955
	inc c			;8957   ; Las dos a la vez, como todas
	dec b			;8958
DEVUELVE_02:		; Codigo de direccion 0x02
	ld a,002h		;8959
	ret			;895b
DIAGONAL_LAS_DOS_MENOS:		; Las dos coordenadas bajan. Devuelve 0x00
	ld a,c			;895c
	cp 002h		;895d   ; Con la coordenada C por debajo de 2 no se puede bajar mas
	jr c,DEVUELVE_00		;895f
	ld a,b			;8961   ; Ni con la B
	cp 002h		;8962
	jr c,DEVUELVE_00		;8964
	dec b			;8966   ; Las dos bajan a la vez
	dec c			;8967
DEVUELVE_00:		; Codigo de direccion 0x00
	ld a,000h		;8968
	ret			;896a
DIAGONAL_LAS_DOS_MAS:		; Las dos coordenadas suben. Devuelve 0x82
	ld a,b			;896b
	cp 01eh		;896c   ; Con la coordenada B en 0x1E se ha llegado al borde
	jr nc,DEVUELVE_82		;896e
	ld a,c			;8970
	cp 01eh		;8971   ; Y lo mismo con la C
	jr nc,DEVUELVE_82		;8973
	inc b			;8975   ; Las dos suben a la vez
	inc c			;8976
DEVUELVE_82:		; Codigo de direccion 0x82
	ld a,082h		;8977
	ret			;8979
YA_ESTA_AL_LADO:		; Se salta un nivel de retorno: no hay que moverse
	ex (sp),hl			;897a
	pop hl			;897b
	ret			;897c

; ----------------------------------------------------------------------
; La ronda de la maquina: mover cada unidad de un bando. Es la tercera entrada del despachador de 0x94B7
; ----------------------------------------------------------------------
MUEVE_LAS_UNIDADES:		; Recorre la lista de 0xBE00 hacia atras desde el indice de 0x897E y mueve o ataca a cada una
	ld hl,0be00h		;897d   ; 0x897E es el operando: el ultimo indice de la lista, que pone 0x9115
	ld a,0d0h		;8980   ; 0xD0 = ret nc, el opcode que se cuela en 0x8AF3
	ld (08af3h),a		;8982   ; 0x8AF3 es el OPCODE del ret de 0x8AF1: asi se elige a que bando se ignora
UNA_UNIDAD:		; Prepara los tres operandos que dependen del numero de unidad
	ld a,l			;8985
	ld (08afdh),a		;8986   ; 0x8AFD es el byte bajo del ld hl,0xC700 de 0x8AFC: queda 0xC700 + n
	inc a			;8989
	ld (08af5h),a		;898a   ; 0x8AF5 es el operando del segundo cp de 0x8AF4: el propio n mas uno
	cp 000h		;898d   ; Operando en 0x898E: la raya entre los dos bandos, que pone 0x90DD
	jr nc,MIRA_LA_UNIDAD		;898f
	ld a,0d8h		;8991   ; 0xD8 = ret c: para las unidades del otro lado de la raya se invierte el filtro
	ld (08af3h),a		;8993
MIRA_LA_UNIDAD:		; Si esta viva y suelta, busca a quien pegar y adonde ir
	ld a,(hl)			;8996
	and 060h		;8997   ; Bits 5 y 6: no esta, o ya esta en contacto. En los dos casos no se mueve
	jp nz,UNIDAD_ANTERIOR		;8999
	ld a,l			;899c
	inc a			;899d
	ld (08a5fh),a		;899e   ; 0x8A5F es el operando del ld (hl),nn de 0x8A5E: el n+1 que se deja en la casilla
	ld a,(hl)			;89a1   ; Bits 0-4 de 0xBE00+n: la coordenada X
	and 01fh		;89a2
	ld c,a			;89a4
	push hl			;89a5
	inc h			;89a6   ; 0xBF00+n: la coordenada Y
	ld b,(hl)			;89a7
	ld (08a54h),bc		;89a8   ; 0x8A54 es el operando del ld bc de 0x8A53: la casilla de la que se sale
	push bc			;89ac
	push hl			;89ad
	call BUSCA_ENEMIGO_PEGADO		;89ae   ; Mira las cuatro diagonales por si hay un enemigo pegado
	pop hl			;89b1
	pop bc			;89b2
	exx			;89b3
	call SIGUIENTE_AL_AZAR		;89b4   ; Un bit al azar del generador de 0x63FB ...
	and 004h		;89b7   ; ... elige cual de las dos rutinas de direccion se usa
	ld de,HACIA_EL_OBJETIVO_B		;89b9
	jr nz,L_89C1		;89bc
	ld de,HACIA_EL_OBJETIVO_A		;89be
L_89C1:
	ld (DA_UN_PASO_8A06+1),de		;89c1   ; 0x8A07 es el operando del call de 0x8A06
	exx			;89c5
	ld h,0c7h		;89c6   ; 0xC700+n: a quien persigue esta unidad
	ld a,(hl)			;89c8
	cp 0ffh		;89c9   ; 0xFF quiere decir que no persigue a nadie
	jp z,BUSCA_A_QUIEN_PERSEGUIR		;89cb
	ld (089fdh),a		;89ce   ; 0x89FD es el byte bajo del ld hl de 0x89FC: 0xBE00 + el perseguido
	ld l,a			;89d1
	ld h,0beh		;89d2   ; 0xBE00 del perseguido
	bit 5,(hl)		;89d4   ; Bit 5: el perseguido ya no esta
	jp nz,EL_PERSEGUIDO_YA_NO_ESTA		;89d6
	ld a,(hl)			;89d9
	and 01fh		;89da   ; Bits 0-4: su coordenada X
	ld e,a			;89dc
	inc h			;89dd   ; 0xBF00: su coordenada Y
	ld d,(hl)			;89de
	pop hl			;89df
	push hl			;89e0
	ld h,0c8h		;89e1
	ld a,b			;89e3
	sub d			;89e4   ; Diferencia en una coordenada ...
	jr nc,L_89E9		;89e5
	neg		;89e7
L_89E9:
	cp 002h		;89e9   ; ... si es de 0 o 1 en las dos, ya estan pegados
	jr nc,DA_UN_PASO_8A06		;89eb
	ld a,c			;89ed
	sub e			;89ee
	jr nc,L_89F3		;89ef
	neg		;89f1
L_89F3:
	cp 002h		;89f3
	jr nc,DA_UN_PASO_8A06		;89f5
	pop hl			;89f7
	set 6,(hl)		;89f8   ; Bit 6 en 0xBE00+n: esta unidad pasa a estar en contacto
	ld a,l			;89fa
	push hl			;89fb
	ld hl,0be00h		;89fc   ; Operando automodificado en 0x89CE: el perseguido
	set 6,(hl)		;89ff   ; Y el perseguido tambien queda en contacto
	ld h,0c7h		;8a01
	ld (hl),a			;8a03   ; 0xC700 del perseguido: ahora se persiguen el uno al otro
	jr $+92		;8a04
DA_UN_PASO_8A06:		; Pide una direccion y mira si la casilla esta libre; si no, prueba una al azar
	call HACIA_EL_OBJETIVO_B		;8a06   ; Operando automodificado en 0x89C1: una de las dos rutinas de 0x8908/0x8925
	call APUNTA_DIRECCION_Y_MIRA_LA_CASILLA		;8a09   ; Apunta la direccion y mira si la casilla destino esta libre
	jr z,GUARDA_LA_POSICION_NUEVA		;8a0c
	call SIGUIENTE_AL_AZAR		;8a0e   ; Ocupada: se prueba una diagonal al azar
	and 003h		;8a11   ; Cuatro direcciones
	add a,a			;8a13
	add a,0bfh		;8a14   ; 0x94BF: la tabla de las cuatro rutinas de diagonal
	ld l,a			;8a16
	add a,094h		;8a17
	sub l			;8a19
	ld h,a			;8a1a
	ld e,(hl)			;8a1b
	inc hl			;8a1c
	ld d,(hl)			;8a1d
	ld (PRUEBA_UNA_DIAGONAL+1),de		;8a1e   ; 0x8A27 es el operando del call de 0x8A26
	ld bc,(08a54h)		;8a22   ; Se vuelve a partir de la casilla de origen
PRUEBA_UNA_DIAGONAL:		; Operando automodificado en 0x8A1E: una diagonal al azar
	call PRUEBA_UNA_DIAGONAL		;8a26   ; Operando automodificado en 0x8A1E
	ld h,0c8h		;8a29
	call APUNTA_DIRECCION_Y_MIRA_LA_CASILLA		;8a2b   ; Si esta tambien esta ocupada, la unidad se queda donde esta
	jr nz,$+50		;8a2e
GUARDA_LA_POSICION_NUEVA:		; Escribe las coordenadas nuevas y da la vuelta al fotograma
	ld a,b			;8a30
	and 01fh		;8a31   ; Las coordenadas se guardan de cinco bits
	ld b,a			;8a33
	ld a,c			;8a34
	and 01fh		;8a35
	ld c,a			;8a37
	push bc			;8a38
	ld a,002h		;8a39
	ld bc,00000h		;8a3b   ; Este ld bc no hace nada: el pop bc de abajo lo pisa
	pop bc			;8a3e
	pop hl			;8a3f
	ld a,(hl)			;8a40
	and 0e0h		;8a41   ; En 0xBE00+n solo se cambian los cinco bits bajos
	or c			;8a43
	ld (hl),a			;8a44
	inc h			;8a45
	ld (hl),b			;8a46   ; 0xBF00+n se lleva la otra coordenada entera
	ld h,0c8h		;8a47
	ld a,(hl)			;8a49
	xor 001h		;8a4a   ; Bit 0 de 0xC800+n: el fotograma de andar cambia en cada paso
	ld (hl),a			;8a4c
	ld h,0beh		;8a4d
	jr $+3		;8a4f   ; El jr se salta el pop hl de 0x8A51, al que no llega nadie

; ----------------------------------------------------------------------
; DATOS pop_hl_sin_uso: Un pop hl que el jr de 0x8A4F salta y al que nadie
;   llega (entrada alternativa sin uso)
;   0x8a51..0x8a52  (1 bytes)
DATA_pop_hl_sin_uso:
	defb 0e1h	; 8a51

; ======================================================================
; CODIGO 0x8a52..0x8a68  (22 bytes)
; ======================================================================


DEJA_LIBRE_LA_CASILLA_VIEJA:		; Borra la casilla de la que se sale y ocupa la nueva
	push hl			;8a52
	ld bc,00000h		;8a53   ; Operando automodificado en 0x89A8: la casilla de partida
	call CASILLA_DEL_TABLERO		;8a56
	ld (hl),000h		;8a59   ; Se queda vacia
	ld hl,00000h		;8a5b   ; Operando automodificado en 0x8ACD: la casilla nueva
	ld (hl),000h		;8a5e   ; Operando automodificado en 0x899E: el numero de unidad mas uno
RECUPERA_LA_UNIDAD:		; Vuelve al bucle con HL en 0xBE00+n
	pop hl			;8a60
UNIDAD_ANTERIOR:		; Baja un indice; al pasar de 0 se acaba la ronda
	dec l			;8a61
	ld a,l			;8a62
	inc a			;8a63   ; Al dar la vuelta del 0 al 0xFF se termina
	jp nz,UNA_UNIDAD		;8a64
	ret			;8a67

; ----------------------------------------------------------------------
; DATOS interruptor_por_opcode: Interruptor por opcode: en la cinta ret / 00 /
;   BE; 0x8BEE escribe 0x21 y 0x8BCC el byte de 0x8A69, y queda ld hl,0xBExx
;   que cae en 0x8A6B
;   0x8a68..0x8a6b  (3 bytes)
DATA_interruptor_por_opcode:
	defb 0c9h,000h,0beh	; 8a68

; ======================================================================
; CODIGO 0x8a6b..0x93d9  (2414 bytes)
; ======================================================================


ENGANCHA_A_LA_UNIDAD:		; Se llega por el interruptor de opcode de 0x8A68: pone en el tablero la unidad que lleva el jugador
	ld e,l			;8a6b
	inc e			;8a6c
	ld a,(hl)			;8a6d   ; Bits 0-4 de 0xBE00+n: la X
	and 01fh		;8a6e
	ld c,a			;8a70
	inc h			;8a71   ; 0xBF00+n: la Y
	ld a,(hl)			;8a72
	call CASILLA_DEL_TABLERO_CON_A		;8a73   ; De las coordenadas a la casilla del tablero
	ld (hl),e			;8a76
	ld a,0c9h		;8a77   ; 0xC9 = ret: el interruptor de 0x8A68 se apaga solo tras usarse una vez
	ld (08a68h),a		;8a79
	ret			;8a7c
EL_PERSEGUIDO_YA_NO_ESTA:		; Se olvida de a quien perseguia y sigue con la siguiente unidad
	pop hl			;8a7d
	ld h,0c7h		;8a7e
	ld (hl),0ffh		;8a80   ; 0xC700+n a 0xFF: no persigue a nadie
	ld h,0beh		;8a82
	jr $-35		;8a84
BUSCA_A_QUIEN_PERSEGUIR:		; De las unidades del otro bando, se queda con la mas cercana dentro de una distancia al azar
	ld a,l			;8a86
	cp 000h		;8a87   ; Operando en 0x8A88: la raya entre los dos bandos
	jr nc,$-41		;8a89
	ld (08abfh),a		;8a8b   ; 0x8ABF es el byte bajo del ld hl de 0x8ABE: 0xC700 + n
	call SIGUIENTE_AL_AZAR		;8a8e   ; Una distancia al azar ...
	and 03fh		;8a91   ; ... entre 0x10 y 0x4F
	or 010h		;8a93
	ld e,a			;8a95
	ld a,0ffh		;8a96   ; 0x8ABC es el operando del ld l,nn de 0x8ABB: si nadie vale, se queda 0xFF
	ld (08abch),a		;8a98
	ld hl,0be00h		;8a9b
MIRA_UN_CANDIDATO:		; Distancia en cruz a esta unidad; si es la mas corta hasta ahora, se queda con ella
	bit 5,(hl)		;8a9e   ; Bit 5: esta unidad ya no esta
	jr nz,SIGUIENTE_CANDIDATO		;8aa0
	ld a,l			;8aa2
	ld (08abch),a		;8aa3   ; Se apunta como mejor candidata
	ld a,(hl)			;8aa6
	and 01fh		;8aa7   ; Bits 0-4: su coordenada X
	ld d,a			;8aa9
	inc h			;8aaa
	ld a,(hl)			;8aab
	dec h			;8aac
	and 01fh		;8aad   ; Y su coordenada Y
	add a,d			;8aaf
	sub b			;8ab0   ; Distancia en cruz: la suma de las dos coordenadas menos la de aqui
	sub c			;8ab1
	cp e			;8ab2   ; Si es mas corta que la ultima, esta gana
	jr c,APUNTA_EL_PERSEGUIDO		;8ab3
SIGUIENTE_CANDIDATO:		; Pasa al indice siguiente
	inc l			;8ab5
	ld a,l			;8ab6
	cp 000h		;8ab7   ; Operando en 0x8AB8: hasta donde llega el bando contrario
	jr nz,MIRA_UN_CANDIDATO		;8ab9
	ld l,0ffh		;8abb   ; Operando automodificado en 0x8A96: la mejor candidata, o 0xFF
APUNTA_EL_PERSEGUIDO:		; Deja en 0xC700+n a quien va a perseguir
	ld a,l			;8abd
	ld hl,0c700h		;8abe   ; Operando automodificado en 0x8A8B: 0xC700 + n
	ld (hl),a			;8ac1
	jr $-98		;8ac2
APUNTA_DIRECCION_Y_MIRA_LA_CASILLA:		; Guarda el codigo de direccion en 0xC800+n y devuelve Z si la casilla B,C esta libre
	ld e,a			;8ac4
	ld a,(hl)			;8ac5
	and 001h		;8ac6   ; Del byte viejo solo se conserva el bit 0, el del fotograma
	or e			;8ac8
	ld (hl),a			;8ac9
	call CASILLA_DEL_TABLERO		;8aca   ; De las coordenadas a la casilla del tablero
	ld (08a5ch),hl		;8acd   ; 0x8A5C es el operando del ld hl de 0x8A5B: la casilla a la que se va
	ld a,(hl)			;8ad0
	or a			;8ad1   ; Un cero: la casilla esta vacia
	ret z			;8ad2
	cp 0ffh		;8ad3   ; Un 0xFF es un obstaculo: tampoco se puede pasar
	ret			;8ad5
BUSCA_ENEMIGO_PEGADO:		; Mira las cuatro casillas en diagonal por si hay una unidad del otro bando
	call CASILLA_DEL_TABLERO		;8ad6   ; La casilla propia
	push hl			;8ad9
	pop iy		;8ada
	ld a,(iy-021h)		;8adc   ; -0x21: la diagonal de arriba a la izquierda
	call SI_ES_ENEMIGO_LO_APUNTA		;8adf
	ld a,(iy-01fh)		;8ae2   ; -0x1F: arriba a la derecha
	call SI_ES_ENEMIGO_LO_APUNTA		;8ae5
	ld a,(iy+01fh)		;8ae8   ; +0x1F: abajo a la izquierda
	call SI_ES_ENEMIGO_LO_APUNTA		;8aeb
	ld a,(iy+021h)		;8aee   ; +0x21: abajo a la derecha
SI_ES_ENEMIGO_LO_APUNTA:		; Filtra el contenido de una casilla y, si es del otro bando, lo deja en 0xC700+n
	cp 000h		;8af1   ; Operando en 0x8AF2: la raya entre los dos bandos, que pone 0x90D7
	ret c			;8af3   ; OPCODE automodificado en 0x8982/0x8993: ret nc o ret c segun de que bando sea quien mira
	cp 000h		;8af4   ; Operando en 0x898A: el propio numero de unidad mas uno, para no mirarse a si misma
	ret z			;8af6
	or a			;8af7   ; Casilla vacia
	ret z			;8af8
	cp 0ffh		;8af9   ; Obstaculo
	ret z			;8afb
	ld hl,0c700h		;8afc   ; Operando automodificado en 0x8986: 0xC700 + n
	dec a			;8aff   ; Del contenido de la casilla se quita el uno: el numero de la unidad de al lado
	push hl			;8b00
	ld l,a			;8b01
	ld h,0beh		;8b02
	bit 5,(hl)		;8b04   ; Bit 5: esa unidad ya no esta
	jr z,GUARDA_EL_ENEMIGO		;8b06
	push af			;8b08
	push bc			;8b09
	push de			;8b0a
	ld e,a			;8b0b
	inc e			;8b0c
	call BORRA_LA_UNIDAD_DEL_TABLERO		;8b0d   ; Se le borran del tablero las casillas que aun ocupara
	pop de			;8b10
	pop bc			;8b11
	pop af			;8b12
	pop hl			;8b13
	ret			;8b14
GUARDA_EL_ENEMIGO:		; 0xC700+n pasa a apuntar al enemigo de al lado
	pop hl			;8b15
	ld (hl),a			;8b16
	ret			;8b17

; ----------------------------------------------------------------------
; Lo que pasa cuando el jugador pulsa sobre una casilla de la batalla
; ----------------------------------------------------------------------
PULSA_EN_LA_BATALLA:		; Segun lo que haya en la casilla: elige unidad, le manda atacar, o suelta un aviso
	ld a,000h		;8b18   ; Operando en 0x8B19: lo que hay en la casilla pulsada, que deja 0x8E6A
	cp 0fdh		;8b1a   ; De 0xFD arriba es obstaculo ...
	jr nc,AVISO_NO_HAY_NADIE		;8b1c
	or a			;8b1e   ; ... y un cero es casilla vacia: en los dos casos, "Aqui no hay nadie"
	jr z,AVISO_NO_HAY_NADIE		;8b1f
	ld c,a			;8b21
	ld a,000h		;8b22   ; Operando en 0x8B23: la unidad que se tenia elegida, 0 si ninguna
	or a			;8b24
	jr z,ELIGE_UNIDAD		;8b25   ; Sin nada elegido, esta pulsacion es para elegir
	cp c			;8b27   ; Pulsar dos veces la misma unidad: se pasa a llevarla a mano
	jr z,LLEVA_LA_UNIDAD_A_MANO		;8b28
	ld l,a			;8b2a
	ld a,c			;8b2b
	ld c,l			;8b2c
	dec c			;8b2d
	dec a			;8b2e
	cp 000h		;8b2f   ; Operando en 0x8B30: la raya entre los dos bandos, que pone 0x90EA
	jr nc,AVISO_ES_UN_AMIGO		;8b31   ; De la raya arriba es de tu bando: no se le puede atacar
	ld h,0c7h		;8b33   ; 0xC700 + la unidad elegida: a partir de ahora persigue a la pulsada
	ld l,c			;8b35
	ld (hl),a			;8b36
	xor a			;8b37
	ld (08b23h),a		;8b38   ; 0x8B23 vuelve a cero: ya no hay unidad elegida
	ld de,095a8h		;8b3b   ; 0x8851 es el operando del ld hl de 0x8850, el dibujo de la ficha 3
	ld (08851h),de		;8b3e
	ld a,005h		;8b42   ; Aviso 5: "Nuevo destino elegido."
DEJA_EL_AVISO:		; Guarda en 0x9190 el numero de aviso que toca
	ld (09190h),a		;8b44   ; 0x9190 es el operando de 0x918F: el aviso que se pintara abajo
ESPERA_A_SOLTAR_EL_MANDO:		; No vuelve hasta que no se toca nada
	call 0066dh		;8b47
	or a			;8b4a   ; Mientras haya algo pulsado, se espera
	jr nz,ESPERA_A_SOLTAR_EL_MANDO		;8b4b
	jp ESPERA_A_SOLTAR_FUEGO		;8b4d
AVISO_NO_HAY_NADIE:		; Aviso 6: "Aqui no hay nadie."
	ld a,006h		;8b50
	jr DEJA_EL_AVISO		;8b52
AVISO_ES_UN_AMIGO:		; Aviso 3: "No puedes atacar a un amigo."
	ld a,003h		;8b54
	jr DEJA_EL_AVISO		;8b56
AVISO_NO_ES_DE_TU_ALIANZA:		; Aviso 4: "No pertenece a tu Alianza."
	ld a,004h		;8b58
	jr DEJA_EL_AVISO		;8b5a
ELIGE_UNIDAD:		; Si la unidad pulsada es de tu bando, queda elegida; si no, salta el aviso
	ld a,c			;8b5c
	cp 000h		;8b5d   ; Operando en 0x8B5E: la raya mas uno, que pone 0x90DA
	jr c,AVISO_NO_ES_DE_TU_ALIANZA		;8b5f   ; Por debajo de la raya, la unidad es del otro bando
	ld a,c			;8b61
	ld (08b23h),a		;8b62   ; 0x8B23 se queda con la unidad elegida
	ld de,095c8h		;8b65   ; 0x95C8: el dibujo de ficha 3 que marca la unidad elegida
	ld (08851h),de		;8b68
	ld a,002h		;8b6c   ; Aviso 2: "Elige el enemigo a atacar."
	jr DEJA_EL_AVISO		;8b6e
LLEVA_LA_UNIDAD_A_MANO:		; Se ha pulsado dos veces la misma unidad: el jugador pasa a moverla el mismo
	ld l,c			;8b70
	dec l			;8b71
	ld h,0beh		;8b72
	bit 6,(hl)		;8b74   ; Bit 6: si ya esta en contacto, no se puede
	ret nz			;8b76
	ld (08be8h),hl		;8b77   ; 0x8BE8 es el operando del ld a,(nn) de 0x8BE7: 0xBE00 + la unidad
	ld h,0c7h		;8b7a
	ld (hl),0ffh		;8b7c   ; 0xC700 a 0xFF: deja de perseguir a nadie
	ld a,0c9h		;8b7e   ; 0xC9 = ret: se desconecta el manejo normal del cursor de 0x8E0D
	ld (MUEVE_EL_CURSOR_DE_BATALLA),a		;8b80
	ld de,095e8h		;8b83   ; 0x95E8: el tercer dibujo de ficha 3, el de la unidad que se lleva a mano
	ld (08851h),de		;8b86
	ld hl,(MUEVE_EL_CURSOR_DE_BATALLA+1)		;8b8a   ; La casilla del centro de la pantalla ...
	ld (MUEVE_LA_UNIDAD_A_MANO+1),hl		;8b8d   ; ... pasa a ser el operando del ld hl de 0x8BE4
	ld hl,00000h		;8b90
	ld (08bfah),hl		;8b93   ; 0x8BFA es el operando del ld (nn),a de 0x8BF9: la casilla ocupada
	ld a,c			;8b96
	dec a			;8b97
	ld (08c63h),a		;8b98   ; 0x8C63 es el operando del ld a,nn de 0x8C62: la unidad que se lleva
	call PON_LA_UNIDAD_EN_EL_TABLERO		;8b9b
	ld de,MUEVE_LA_UNIDAD_A_MANO		;8b9e
	ld (094bdh),de		;8ba1   ; 0x94BD es la CUARTA palabra del despachador de 0x9163: pasa a ser 0x8BE4
	pop hl			;8ba5   ; Dos pop hl: se tiran dos niveles de retorno
	pop hl			;8ba6
	jp ESPERA_A_SOLTAR_EL_MANDO		;8ba7
PON_LA_UNIDAD_EN_EL_TABLERO:		; Borra del tablero las casillas de la unidad y la coloca en la del centro de la pantalla
	push af			;8baa
	push hl			;8bab
	ld a,(08c63h)		;8bac   ; 0x8C63: la unidad que se lleva a mano
	ld e,a			;8baf
	inc e			;8bb0
	call BORRA_LA_UNIDAD_DEL_TABLERO		;8bb1   ; Le borra del tablero cualquier casilla que aun ocupe
	ld hl,(MUEVE_EL_CURSOR_DE_BATALLA+1)		;8bb4   ; La casilla del centro de la pantalla
	push hl			;8bb7
	call COORDENADAS_A_CASILLA		;8bb8   ; De coordenadas a casilla del tablero
	ld a,(08c63h)		;8bbb
	ld e,a			;8bbe
	inc e			;8bbf
	ld (hl),e			;8bc0   ; Y ahi se pone la unidad
	pop de			;8bc1
	ld l,a			;8bc2
	ld h,0beh		;8bc3
	ld (hl),d			;8bc5   ; 0xBE00+n con la coordenada X ...
	inc h			;8bc6
	ld (hl),e			;8bc7   ; ... y 0xBF00+n con la Y
	pop hl			;8bc8
	ld a,(08c63h)		;8bc9
	ld (08a69h),a		;8bcc   ; 0x8A69 es el byte bajo del ld hl del interruptor de 0x8A68
	pop af			;8bcf
	ret			;8bd0
BORRA_LA_UNIDAD_DEL_TABLERO:		; Recorre las 1024 casillas y vacia las que valgan E
	ld hl,05e00h		;8bd1   ; El tablero, de 0x5E00 en adelante
	ld bc,00400h		;8bd4   ; 0x400 casillas: 32 por 32
L_8BD7:
	ld a,(hl)			;8bd7
	cp e			;8bd8
	jr nz,L_8BDD		;8bd9
	ld (hl),000h		;8bdb   ; Se deja vacia
L_8BDD:
	inc hl			;8bdd   ; Byte siguiente del tablero
	dec bc			;8bde   ; Y una casilla menos de las 1024
	ld a,b			;8bdf
	or c			;8be0
	jr nz,L_8BD7		;8be1
	ret			;8be3
MUEVE_LA_UNIDAD_A_MANO:		; Cuarta entrada del despachador: el jugador lleva una unidad casilla a casilla
	ld hl,00000h		;8be4   ; Operando automodificado en 0x8B8D y 0x8CA6: donde esta la unidad
	ld a,(00000h)		;8be7   ; Operando automodificado en 0x8B77: 0xBE00 + la unidad
	call PON_LA_UNIDAD_EN_EL_TABLERO		;8bea
	push af			;8bed
	ld a,021h		;8bee   ; 0x21 = ld hl: se arma el interruptor de opcode de 0x8A68
	ld (08a68h),a		;8bf0
	pop af			;8bf3
	and 040h		;8bf4   ; Bit 6: si la unidad ha entrado en contacto, se acaba el manejo a mano
	jr nz,DEJA_DE_LLEVARLA_A_MANO		;8bf6
	xor a			;8bf8
	ld (00000h),a		;8bf9   ; Operando automodificado en 0x8C9B: la casilla que ocupa, que se vacia
	push hl			;8bfc
	call 0066dh		;8bfd
	pop hl			;8c00
	bit 5,a		;8c01   ; Bit 5, la tecla 1: se suelta la unidad
	jr z,L_8C0B		;8c03
	ld a,(08c63h)		;8c05
	jp VUELVE_A_SU_CASILLA		;8c08
L_8C0B:
	rra			;8c0b   ; Bit 0 del mando: una diagonal, con codigo 0x80
	jr nc,L_8C15		;8c0c
	ld c,080h		;8c0e
	ld de,0ff01h		;8c10
	jr L_8C31		;8c13
L_8C15:
	rra			;8c15   ; Bit 1: la contraria, codigo 0x02
	jr nc,L_8C1F		;8c16
	ld c,002h		;8c18
	ld de,001ffh		;8c1a
	jr L_8C31		;8c1d
L_8C1F:
	rra			;8c1f   ; Bit 2: codigo 0x00
	jr nc,L_8C29		;8c20
	ld c,000h		;8c22
	ld de,0ffffh		;8c24
	jr L_8C31		;8c27
L_8C29:
	rra			;8c29   ; Bit 3: codigo 0x82
	jr nc,NO_SE_MUEVE		;8c2a
	ld c,082h		;8c2c
	ld de,00101h		;8c2e
L_8C31:
	ld a,c			;8c31
	ld (08cc1h),a		;8c32   ; 0x8CC1 es el operando del or nn de 0x8CC0: el codigo de direccion
	push hl			;8c35
	ld a,h			;8c36
	add a,d			;8c37   ; Se suma el desplazamiento a la coordenada ...
	jp m,MIRA_LA_CASILLA_DE_DESTINO		;8c38
	cp 020h		;8c3b   ; ... y se comprueba que no se sale del tablero de 32x32
	jr nc,MIRA_LA_CASILLA_DE_DESTINO		;8c3d
	ld h,a			;8c3f
	ld a,l			;8c40
	add a,e			;8c41
	jp m,MIRA_LA_CASILLA_DE_DESTINO		;8c42
	cp 020h		;8c45
	jr nc,MIRA_LA_CASILLA_DE_DESTINO		;8c47
	ld l,a			;8c49
	ex (sp),hl			;8c4a   ; La casilla nueva queda en la pila
MIRA_LA_CASILLA_DE_DESTINO:		; Vacia se anda, ocupada por un enemigo se ataca, y por un amigo no se pasa
	pop hl			;8c4b
	push hl			;8c4c
	call COORDENADAS_A_CASILLA		;8c4d   ; De coordenadas a casilla del tablero
	ld a,(hl)			;8c50
	or a			;8c51   ; Vacia: se puede andar
	jr z,ANDA_A_LA_CASILLA		;8c52
	inc a			;8c54   ; Obstaculo: tampoco se anda, pero no se ataca
	jr z,ANDA_A_LA_CASILLA		;8c55
	pop hl			;8c57
	dec a			;8c58   ; Dos dec: del contenido de la casilla al numero de unidad menos uno
	dec a			;8c59
	cp 000h		;8c5a   ; Operando en 0x8C5B: la raya entre bandos, que pone 0x90E7
	jr nc,NO_SE_MUEVE		;8c5c   ; De la raya arriba es de tu bando: no se le ataca
	ld l,a			;8c5e
	ld c,a			;8c5f
	ld h,0c7h		;8c60
	ld a,000h		;8c62   ; Operando automodificado en 0x8B98: la unidad que lleva el jugador
	ld (hl),a			;8c64   ; 0xC700 del enemigo apunta a la unidad ...
	ld l,a			;8c65
	ld (hl),c			;8c66   ; ... y 0xC700 de la unidad apunta al enemigo: se enganchan
VUELVE_A_SU_CASILLA:		; Repone la unidad en el tablero
	ld hl,(08bfah)		;8c67   ; Operando automodificado en 0x8C9B: la casilla que ocupaba
	inc a			;8c6a
	ld (hl),a			;8c6b
DEJA_DE_LLEVARLA_A_MANO:		; Devuelve el manejo normal del cursor y el despachador a su sitio
	ld a,021h		;8c6c   ; 0x21 = ld hl: 0x8E0D vuelve a ser la rutina del cursor
	ld (MUEVE_EL_CURSOR_DE_BATALLA),a		;8c6e
	ld (08a68h),a		;8c71   ; Y el interruptor de opcode de 0x8A68 tambien
	ld de,095a8h		;8c74   ; 0x95A8: el dibujo de ficha 3 de siempre
	ld (08851h),de		;8c77
	ld a,001h		;8c7b
	ld (09190h),a		;8c7d   ; Aviso 1: "La Batalla ha comenzado."
	ld hl,NO_HACE_NADA		;8c80
	ld (094bdh),hl		;8c83   ; La cuarta palabra del despachador vuelve a 0x8F19
	xor a			;8c86
	ld (08b23h),a		;8c87   ; Y ya no hay unidad elegida
	jp PON_LA_UNIDAD_EN_EL_TABLERO		;8c8a
NO_SE_MUEVE:		; La casilla de destino no vale: la unidad se queda donde estaba
	ld a,(08c63h)		;8c8d
	inc a			;8c90
	ld hl,(08bfah)		;8c91   ; Operando automodificado en 0x8C9B: su casilla de siempre
	ld (hl),a			;8c94
	ret			;8c95
ANDA_A_LA_CASILLA:		; Ocupa la casilla nueva, mueve con ella el centro de la pantalla y cambia el fotograma
	ld a,(08c63h)		;8c96
	inc a			;8c99
	ld (hl),a			;8c9a   ; La unidad ocupa la casilla nueva
	ld (08bfah),hl		;8c9b   ; 0x8BFA y 0x8C68 se quedan con la casilla ocupada
	pop hl			;8c9e
	ld (MUEVE_EL_CURSOR_DE_BATALLA+1),hl		;8c9f   ; 0x8E0E: el centro de la pantalla sigue a la unidad
	ld bc,(MUEVE_LA_UNIDAD_A_MANO+1)		;8ca2   ; Las coordenadas viejas ...
	ld (MUEVE_LA_UNIDAD_A_MANO+1),hl		;8ca6   ; ... y las nuevas al operando de 0x8BE4
	ld e,h			;8ca9
	ld d,l			;8caa
	push de			;8cab
	dec a			;8cac
	ld e,a			;8cad
	ld d,0beh		;8cae
	ex de,hl			;8cb0
	ld a,(hl)			;8cb1
	and 0e0h		;8cb2   ; En 0xBE00+n solo cambian los cinco bits bajos
	or d			;8cb4
	ld (hl),a			;8cb5
	inc h			;8cb6
	ld (hl),e			;8cb7   ; 0xBF00+n se lleva la otra coordenada
	pop de			;8cb8
	ld h,0c8h		;8cb9
	ld a,(hl)			;8cbb
	xor 001h		;8cbc   ; Bit 0 de 0xC800+n: el fotograma de andar
	and 001h		;8cbe
	or 000h		;8cc0   ; Operando automodificado en 0x8C32: el codigo de direccion
	ld (hl),a			;8cc2
	ret			;8cc3
APUNTA_HACIA_DONDE_MIRA:		; B,C = donde esta, D,E = adonde mira: deja el codigo de direccion en (hl), que es 0xC800+n
	push bc			;8cc4
	ld a,b			;8cc5
	cp d			;8cc6   ; Compara las dos coordenadas ...
	ld a,c			;8cc7
	jr c,L_8CD3		;8cc8
	ld b,080h		;8cca   ; ... y con las dos sale una de las cuatro diagonales
	cp e			;8ccc
	jr c,L_8CDA		;8ccd
	ld b,000h		;8ccf
	jr L_8CDA		;8cd1
L_8CD3:
	ld b,082h		;8cd3
	cp e			;8cd5
	jr c,L_8CDA		;8cd6
	ld b,002h		;8cd8
L_8CDA:
	ld a,(hl)			;8cda
	and 001h		;8cdb   ; Del byte viejo solo se conserva el bit 0, el del fotograma
	or b			;8cdd
	ld (hl),a			;8cde
	pop bc			;8cdf
	ret			;8ce0
PREPARA_UN_EJERCITO:		; 0xBD00+n: si entra en la batalla, calcula sus numeros y suelta sus figuras en el tablero
	bit 5,(hl)		;8ce1   ; Bit 5 de 0xBD00+n: si no esta puesto, este ejercito no entra
	ret z			;8ce3
	bit 4,(hl)		;8ce4   ; Bit 4: es el ejercito que sigue el jugador
	jr z,NUMEROS_DE_LA_FIGURA		;8ce6
	ld a,001h		;8ce8
	ld (09120h),a		;8cea   ; 0x9120 es el operando de 0x911F
	ld a,l			;8ced
	ld (09273h),a		;8cee   ; 0x9273 es el operando de 0x9272: el numero de ese ejercito
	ld a,(08d7ch)		;8cf1   ; 0x8D7C lleva la cuenta de figuras ya puestas en el tablero
	ld (092d9h),a		;8cf4
NUMEROS_DE_LA_FIGURA:		; Del tipo de tropa salen los operandos que 0x8D5D copiara en cada figura
	push hl			;8cf7
	ld a,(hl)			;8cf8   ; Nibble bajo de 0xBD00+n: el tipo de tropa
	and 00fh		;8cf9
	cp 009h		;8cfb   ; De 9 arriba, todos valen como el tipo 2
	jr c,L_8D01		;8cfd
	ld a,002h		;8cff
L_8D01:
	cp 001h		;8d01
	jr z,L_8D08		;8d03
	ld (09125h),a		;8d05   ; 0x9125 es el operando del xor de 0x9124
L_8D08:
	cp 007h		;8d08   ; El tipo 7 dibuja como el 1 ...
	jr nz,L_8D0E		;8d0a
	ld a,001h		;8d0c
L_8D0E:
	cp 008h		;8d0e   ; ... y el 8 como el 4
	jr nz,DIBUJO_Y_FUERZA		;8d10
	ld a,004h		;8d12
DIBUJO_Y_FUERZA:		; Deja en los operandos de 0x8D5D el dibujo, la vida, el golpe y el resto de numeros de la figura
	add a,a			;8d14
	ld (08d8bh),a		;8d15   ; 0x8D8B es el operando de 0x8D8A: lo que va a 0xC400+n, el dibujo
	call CUATRO_SI_ES_TIPO_0_1_O_7		;8d18
	ld a,c			;8d1b
	ld (08d9eh),a		;8d1c   ; 0x8D9E es el operando de 0x8D9D: lo que va a 0xE600+n
	ld a,l			;8d1f
	ld (08da2h),a		;8d20   ; 0x8DA2 es el operando de 0x8DA1: lo que va a 0xC600+n, el ejercito de origen
	ld h,0c1h		;8d23   ; Nibble bajo de 0xC100+n
	ld a,(hl)			;8d25
	and 00fh		;8d26
	ld c,a			;8d28
	call MULTIPLICA		;8d29   ; 0x8DB5 multiplica: DE = A por C
	ld (08d98h),a		;8d2c   ; 0x8D98 es el operando de 0x8D97: lo que va a 0xE400+n, el acierto
	call NIBBLE_ALTO_DE_HL		;8d2f   ; Devuelve el nibble ALTO de (hl)
	ld (08d9bh),a		;8d32   ; 0x8D9B es el operando de 0x8D9A: lo que va a 0xE500+n, el golpe
	ld h,0c2h		;8d35   ; 0xC200+n
	ld a,(hl)			;8d37
	ld (08d45h),a		;8d38   ; 0x8D45 es el operando del ld c,nn de 0x8D44
	push hl			;8d3b
	call FUERZA_DE_LA_TROPA		;8d3c
	pop hl			;8d3f
	ld a,0ffh		;8d40   ; 0xFF menos lo que sale de 0x8DE4 ...
	sub c			;8d42
	sub d			;8d43
	ld c,000h		;8d44
	call MULTIPLICA		;8d46
	ld a,d			;8d49
	or 001h		;8d4a
	ld (08d94h),a		;8d4c   ; ... y con el bit 0 forzado va a 0xE300+n, la vida
	ld h,0c5h		;8d4f   ; 0xC500+n: cuantas figuras pone este ejercito, minimo una
	ld a,(hl)			;8d51
	or a			;8d52
	jr nz,L_8D56		;8d53
	inc a			;8d55
L_8D56:
	ld b,a			;8d56
	call SIGUIENTE_AL_AZAR		;8d57
	ld (08da8h),a		;8d5a   ; 0x8DA8 es el operando de 0x8DA7: el fotograma de arranque
UNA_FIGURA_MAS:		; Cada vuelta suelta una figura del ejercito en el tablero
	push bc			;8d5d
BUSCA_CASILLA_LIBRE:		; Sortea coordenadas hasta dar con una casilla vacia y de la paridad buena
	call SIGUIENTE_AL_AZAR		;8d5e
	ld h,003h		;8d61   ; 0x0300 + el azar: la tabla de tramos de 0x908D, que carga el sorteo hacia un borde del tablero
	ld a,(hl)			;8d63
	ld b,a			;8d64
	and 001h		;8d65   ; Paridad de la primera coordenada ...
	ld c,a			;8d67
	call SIGUIENTE_AL_AZAR		;8d68
	and 01fh		;8d6b
	ld l,a			;8d6d
	and 001h		;8d6e   ; ... que tiene que ser la misma que la de la segunda: es un tablero de damas
	cp c			;8d70
	jr nz,BUSCA_CASILLA_LIBRE		;8d71
	ld c,l			;8d73
	call CASILLA_DEL_TABLERO		;8d74   ; De coordenadas a casilla del tablero
	ld a,(hl)			;8d77
	or a			;8d78   ; Si no esta vacia, se vuelve a sortear
	jr nz,BUSCA_CASILLA_LIBRE		;8d79
	ld a,000h		;8d7b   ; Operando en 0x8D7C: cuantas figuras hay ya en el tablero
	cp 0feh		;8d7d   ; 0xFE figuras es el tope
	jr z,SIGUIENTE_FIGURA		;8d7f
	inc a			;8d81
	ld (hl),a			;8d82   ; La casilla se queda con el numero de figura mas uno
	ld (08d7ch),a		;8d83   ; Y la cuenta sube en uno
	dec a			;8d86
	ld l,a			;8d87
	ld h,0c4h		;8d88   ; 0xC400+n: el dibujo, del operando de 0x8D8A
	ld (hl),000h		;8d8a
	ld h,0beh		;8d8c   ; 0xBE00+n: la coordenada X
	ld (hl),c			;8d8e
	inc h			;8d8f
	ld (hl),b			;8d90   ; 0xBF00+n: la coordenada Y
	ld h,0e3h		;8d91   ; 0xE300+n: los puntos de vida
	ld (hl),000h		;8d93
	ld h,0e4h		;8d95   ; 0xE400+n: la probabilidad de acertar
	ld (hl),000h		;8d97
	inc h			;8d99   ; 0xE500+n: lo que quita cada golpe
	ld (hl),000h		;8d9a
	inc h			;8d9c   ; 0xE600+n: cuantas veces se levanta
	ld (hl),000h		;8d9d
	ld h,0c6h		;8d9f   ; 0xC600+n: el ejercito del mapa al que pertenece
	ld (hl),000h		;8da1
	inc h			;8da3   ; 0xC700+n a 0xFF: aun no persigue a nadie
	ld (hl),0ffh		;8da4
	inc h			;8da6   ; 0xC800+n: el fotograma
	ld a,000h		;8da7
	ld (hl),a			;8da9
	inc a			;8daa
	and 003h		;8dab   ; Los fotogramas de arranque van rotando 0, 1, 2, 3
	ld (08da8h),a		;8dad
SIGUIENTE_FIGURA:		; Hasta agotar las figuras de este ejercito
	pop bc			;8db0
	djnz UNA_FIGURA_MAS		;8db1
	pop hl			;8db3
	ret			;8db4
MULTIPLICA:		; DE = A por C, sumando C veces
	ld e,a			;8db5
	xor a			;8db6
	ld d,a			;8db7
L_8DB8:
	add a,e			;8db8
	jr nc,L_8DBC		;8db9   ; El acarreo se lleva al byte alto
	inc d			;8dbb
L_8DBC:
	dec c			;8dbc
	jr nz,L_8DB8		;8dbd
	ret			;8dbf
CUATRO_SI_ES_TIPO_0_1_O_7:		; C = 4 para los tipos por debajo de 2 y para el 7; 0 para los demas
	ld c,000h		;8dc0
	cp 002h		;8dc2
	jr c,L_8DC9		;8dc4
	cp 007h		;8dc6
	ret nz			;8dc8
L_8DC9:
	ld c,004h		;8dc9
	ret			;8dcb
VENTAJA_DEL_TERRENO:		; D = 100 en los terrenos 7, 8 y 9, 50 en el 11 y 0 en el resto
	ld a,000h		;8dcc   ; Operando en 0x8DCD, que escribe 0x902A: el byte de terreno
	ld e,a			;8dce
	and 00fh		;8dcf   ; Nibble bajo: el tipo de terreno
	ld d,000h		;8dd1
	cp 007h		;8dd3   ; Por debajo del 7 no hay ventaja ...
	ret c			;8dd5
	cp 00ch		;8dd6   ; ... ni del 12 arriba ...
	ret nc			;8dd8
	cp 00ah		;8dd9   ; ... ni en el 10
	ret z			;8ddb
	ld d,032h		;8ddc   ; El terreno 11 da 50
	cp 00bh		;8dde
	ret z			;8de0
	ld d,064h		;8de1   ; Y los terrenos 7, 8 y 9 dan 100
	ret			;8de3
FUERZA_DE_LA_TROPA:		; A = tipo; lee la tabla de 0x6D47 y le suma la ventaja del terreno
	add a,a			;8de4
	add a,a			;8de5
	add a,a			;8de6
	add a,047h		;8de7   ; 0x6D47: la tabla de tropas del bloque de textos
	or 000h		;8de9   ; Operando en 0x8DEA, que escribe 0x902F
	ld l,a			;8deb
	adc a,06dh		;8dec
	sub l			;8dee
	ld h,a			;8def
	ld a,(hl)			;8df0
	add a,a			;8df1   ; Lo de la tabla, por ocho
	add a,a			;8df2
	add a,a			;8df3
	ld c,a			;8df4
	call VENTAJA_DEL_TERRENO		;8df5   ; Y la ventaja que da el terreno
	bit 4,e		;8df8   ; Bit 4 del byte de terreno
SIN_VENTAJA:		; OPCODE interruptor: 0x90B9 le mete 0xC8 (ret z) y 0x90D0 0xC0 (ret nz), uno por bando
	ret nz			;8dfa
	ld d,000h		;8dfb
	ret			;8dfd
CASILLA_DEL_TABLERO:		; B = coordenada Y, C = X; devuelve HL = 0x5E00 + Y*32 + X
	ld a,b			;8dfe   ; La coordenada Y, que entra en B
CASILLA_DEL_TABLERO_CON_A:		; Igual pero con la coordenada Y ya en A
	add a,a			;8dff   ; Tres add a,a y dos add hl,hl: la fila por 32
	add a,a			;8e00
	add a,a			;8e01
	ld h,000h		;8e02
	ld l,a			;8e04
	add hl,hl			;8e05
	add hl,hl			;8e06
	ld a,b			;8e07
	ld b,05eh		;8e08   ; 0x5E00: el tablero, encima del codigo del menu
	add hl,bc			;8e0a   ; Y la columna, que venia en C
	ld b,a			;8e0b
	ret			;8e0c

; ----------------------------------------------------------------------
; El cursor de la batalla: lo mueve el jugador y de el sale lo que se pulsa
; ----------------------------------------------------------------------
MUEVE_EL_CURSOR_DE_BATALLA:		; Lee el mando y corre el centro de la pantalla en diagonal. 0x8B7E le mete un ret para desconectarla
	ld hl,00000h		;8e0d   ; OPCODE interruptor (0xC9 apaga, 0x21 enciende) y operando 0x8E0E con la casilla del centro
	call 0066dh		;8e10
	bit 4,a		;8e13   ; Bit 4: el disparo
	push hl			;8e15
	call nz,PULSA_EN_LA_BATALLA		;8e16   ; Lo pulsado se resuelve en 0x8B18
	pop hl			;8e19
	ld b,a			;8e1a
	ld de,00000h		;8e1b   ; Sin ninguna direccion, DE no mueve nada
	rra			;8e1e   ; Bit 0: una diagonal
	jr nc,L_8E24		;8e1f
	ld de,0ff01h		;8e21
L_8E24:
	rra			;8e24   ; Bit 1: la contraria
	jr nc,L_8E2A		;8e25
	ld de,001ffh		;8e27
L_8E2A:
	rra			;8e2a   ; Bit 2
	jr nc,L_8E30		;8e2b
	ld de,0ffffh		;8e2d
L_8E30:
	rra			;8e30   ; Bit 3
	jr nc,MIRA_LA_TECLA_1_8E36		;8e31
	ld de,00101h		;8e33
MIRA_LA_TECLA_1_8E36:		; Bit 5 del mando: se olvida la unidad elegida
	rra			;8e36   ; Dos rra: se salta el bit del disparo
	rra			;8e37
	jr nc,MUEVE_SI_CABE		;8e38
	xor a			;8e3a
	ld (08b23h),a		;8e3b   ; 0x8B23 a cero: ya no hay unidad elegida
	inc a			;8e3e
	ld (09190h),a		;8e3f   ; Aviso 1: "La Batalla ha comenzado."
	ld bc,095a8h		;8e42   ; 0x95A8: el dibujo de ficha 3 de siempre
	ld (08851h),bc		;8e45
MUEVE_SI_CABE:		; Suma el desplazamiento a las dos coordenadas si no se sale del tablero
	push hl			;8e49
	ld a,h			;8e4a
	add a,d			;8e4b
	jp m,GUARDA_EL_CURSOR		;8e4c   ; Negativo: fuera del tablero
	cp 020h		;8e4f   ; Y de 0x20 arriba, tambien
	jr nc,GUARDA_EL_CURSOR		;8e51
	ld h,a			;8e53
	ld a,l			;8e54
	add a,e			;8e55
	jp m,GUARDA_EL_CURSOR		;8e56
	cp 020h		;8e59
	jr nc,GUARDA_EL_CURSOR		;8e5b
	ld l,a			;8e5d
	ex (sp),hl			;8e5e
GUARDA_EL_CURSOR:		; Apunta la casilla nueva y lee lo que hay en ella
	pop hl			;8e5f
	ld (MUEVE_EL_CURSOR_DE_BATALLA+1),hl		;8e60   ; 0x8E0E: el centro de la pantalla
	call COORDENADAS_A_CASILLA		;8e63   ; De coordenadas a casilla del tablero
	ld (08b91h),hl		;8e66   ; 0x8B91 es el operando del ld hl de 0x8B90: la casilla del cursor
	ld a,(hl)			;8e69
	ld (PULSA_EN_LA_BATALLA+1),a		;8e6a   ; 0x8B19 es el operando de 0x8B18: lo que hay en esa casilla
	ret			;8e6d
COORDENADAS_A_CASILLA:		; H = X, L = Y; devuelve HL = 0x5E00 + Y*32 + X. De paso vacia las casillas de la paridad prohibida
	push af			;8e6e
	push bc			;8e6f
	push hl			;8e70
	ld e,h			;8e71   ; E guarda la X mientras se calcula
	ld a,l			;8e72
	add a,a			;8e73   ; Tres add a,a y dos add hl,hl: la Y por 32
	add a,a			;8e74
	add a,a			;8e75
	ld h,000h		;8e76
	ld l,a			;8e78
	add hl,hl			;8e79
	add hl,hl			;8e7a
	ld a,l			;8e7b
	or e			;8e7c   ; La X entra por or: los cinco bits bajos estaban libres
	ld l,a			;8e7d
	ld a,h			;8e7e
	add a,05eh		;8e7f   ; 0x5E00: el tablero
	ld h,a			;8e81
	pop bc			;8e82
	ld a,b			;8e83   ; Si las dos coordenadas tienen distinta paridad ...
	xor c			;8e84
	and 001h		;8e85
	jr z,SALE_DE_LA_CASILLA		;8e87
	ld a,(hl)			;8e89   ; ... y en la casilla no hay ni vacio ni obstaculo ...
	or a			;8e8a
	jr z,SALE_DE_LA_CASILLA		;8e8b
	inc a			;8e8d
	jr z,SALE_DE_LA_CASILLA		;8e8e
	ld (hl),000h		;8e90   ; ... se vacia: en esas casillas no puede haber nadie
SALE_DE_LA_CASILLA:		; Devuelve HL apuntando a la casilla
	pop bc			;8e92
	pop af			;8e93
	ret			;8e94

; ----------------------------------------------------------------------
; El combate cuerpo a cuerpo: la primera entrada del despachador de 0x94B7
; ----------------------------------------------------------------------
RESUELVE_LOS_COMBATES:		; Recorre las figuras y, a las que estan en contacto, les hace tirar
	ld hl,0be00h		;8e95   ; Operando en 0x8E96, que pone 0x9118: por que figura se empieza
UNA_FIGURA_EN_COMBATE:		; Solo pelean las que estan puestas y con el bit 6 de contacto
	bit 5,(hl)		;8e98   ; Bit 5: la figura ya no esta
	jp nz,BAJA_UN_INDICE		;8e9a
	bit 6,(hl)		;8e9d   ; Bit 6: no esta en contacto con nadie
	jp z,BAJA_UN_INDICE		;8e9f
	push hl			;8ea2
	ld a,(hl)			;8ea3   ; Bits 0-4 de 0xBE00+n: la coordenada X
	and 01fh		;8ea4
	ld b,a			;8ea6
	inc h			;8ea7
	ld c,(hl)			;8ea8   ; 0xBF00+n: la Y
	push bc			;8ea9
	push hl			;8eaa
	ld e,l			;8eab
	inc e			;8eac
	ld a,c			;8ead
	ld c,b			;8eae
	call CASILLA_DEL_TABLERO_CON_A		;8eaf   ; La figura se vuelve a poner en su casilla del tablero
	ld (hl),e			;8eb2
	pop hl			;8eb3
	pop bc			;8eb4
	ld e,l			;8eb5
	ld h,0c7h		;8eb6   ; 0xC700+n: contra quien pelea
	ld l,(hl)			;8eb8
	ld (hl),e			;8eb9   ; Y el otro queda apuntando a esta: se enganchan
	ld h,0beh		;8eba
	ld a,(hl)			;8ebc   ; Las coordenadas del contrario ...
	and 01fh		;8ebd
	ld d,a			;8ebf
	inc h			;8ec0
	ld e,(hl)			;8ec1
	pop hl			;8ec2
	push hl			;8ec3
	ld h,0c8h		;8ec4
	call APUNTA_HACIA_DONDE_MIRA		;8ec6   ; ... para girarse hacia el
	ld c,l			;8ec9
	ld a,(hl)			;8eca
	xor 001h		;8ecb   ; Bit 0 de 0xC800+n: el fotograma de pelear
	ld (hl),a			;8ecd
	dec h			;8ece
	ld b,(hl)			;8ecf   ; B se queda con el numero del contrario
	call SIGUIENTE_AL_AZAR		;8ed0   ; Un byte al azar ...
	ld l,c			;8ed3
	ld h,0e4h		;8ed4   ; ... contra 0xE400+n, que es lo que acierta esta figura
	cp (hl)			;8ed6
	jr c,GOLPE_DADO		;8ed7   ; Menor: golpe dado
	bit 3,a		;8ed9   ; Los dos caminos van al mismo sitio: el bit 3 no decide nada
	jp nz,SIGUIENTE_EN_COMBATE		;8edb
	jp SIGUIENTE_EN_COMBATE		;8ede
GOLPE_DADO:		; Le quita al contrario los puntos de 0xE500+n
	inc h			;8ee1
	ld a,(hl)			;8ee2   ; 0xE500+n: lo que quita este golpe
	ld (08eebh),a		;8ee3   ; 0x8EEB es el operando del sub de 0x8EEA
	ld l,b			;8ee6
	ld h,0e3h		;8ee7   ; 0xE300 del contrario: sus puntos de vida
	ld a,(hl)			;8ee9
	sub 000h		;8eea
	ld (hl),a			;8eec   ; Se le restan
	jr nc,SIGUIENTE_EN_COMBATE		;8eed   ; Mientras no baje de cero, sigue en pie
	ld h,0e6h		;8eef   ; 0xE600 del contrario: cuantas veces le queda levantarse
	ld a,(hl)			;8ef1
	or a			;8ef2
	jr z,FIGURA_ABATIDA		;8ef3
	dec a			;8ef5   ; Se le gasta una ...
	ld (hl),a			;8ef6
	ld h,0e3h		;8ef7
	ld (hl),0ffh		;8ef9   ; ... y vuelve a 0xFF puntos de vida
	jr SIGUIENTE_EN_COMBATE		;8efb
FIGURA_ABATIDA:		; La figura cae: si era la ultima de su ejercito, el ejercito desaparece
	call QUITA_LA_FIGURA		;8efd   ; Quita la figura del tablero y de la lista
	ld l,b			;8f00
	ld h,0c6h		;8f01   ; 0xC600 del contrario: a que ejercito pertenecia
	ld l,(hl)			;8f03
	ld h,0c5h		;8f04   ; 0xC500 de ese ejercito: cuantas figuras le quedaban
	ld a,(hl)			;8f06
	and a			;8f07
	jr z,EJERCITO_DESHECHO		;8f08
	dec (hl)			;8f0a   ; Una menos; si aun quedan, se acabo
	jr nz,SIGUIENTE_EN_COMBATE		;8f0b
EJERCITO_DESHECHO:		; Sin figuras: el ejercito se borra del mapa
	call BORRA_EL_EJERCITO_DEL_MAPA		;8f0d
SIGUIENTE_EN_COMBATE:		; Recupera el puntero de la lista de 0xBE00
	pop hl			;8f10
	ld h,0beh		;8f11
BAJA_UN_INDICE:		; Baja una figura; al pasar del 0 se acaba la ronda
	ld a,l			;8f13
	dec l			;8f14
	or a			;8f15
	jp nz,UNA_FIGURA_EN_COMBATE		;8f16
NO_HACE_NADA:		; Un ret suelto: es la segunda y la cuarta entrada del despachador de 0x94B7
	ret			;8f19
BORRA_EL_EJERCITO_DEL_MAPA:		; Pone a cero las coordenadas del ejercito en el mapa y reparte sus efectos
	ld h,0b9h		;8f1a   ; 0xB900+n a cero ...
	ld (hl),000h		;8f1c
	inc h			;8f1e   ; ... y 0xBA00+n tambien: fuera del mapa
	ld (hl),000h		;8f1f
	ld c,l			;8f21
	ld h,0bdh		;8f22   ; Nibble bajo de 0xBD00+n: el tipo de ejercito
	ld a,(hl)			;8f24
	and 00fh		;8f25
	cp 005h		;8f27   ; El tipo 5 tiene su propio final, en 0x930D
	jp z,EJERCITO_TIPO_5_DESHECHO		;8f29
	xor a			;8f2c
REPASA_LOS_EJERCITOS:		; Para cada ejercito sin destino, copia sus coordenadas a 0xBB00 y 0xBC00
	push af			;8f2d
	call BUSCA_EL_DESTINO		;8f2e
	ld a,d			;8f31   ; Si 0x6956 devuelve algo, este ejercito se salta
	or e			;8f32
	jr nz,SIGUIENTE_EJERCITO		;8f33
	pop af			;8f35
	push af			;8f36
	ld l,a			;8f37
	ld h,0b9h		;8f38   ; 0xB900+a: su coordenada X ...
	ld e,a			;8f3a
	ld d,0bbh		;8f3b   ; ... que se copia a 0xBB00+a, sin el bit 7
	ld a,(hl)			;8f3d
	and 07fh		;8f3e
	ld (de),a			;8f40
	inc hl			;8f41
	inc de			;8f42
	ld a,(hl)			;8f43   ; Y 0xBA00+a a 0xBC00+a
	and 07fh		;8f44
	ld (de),a			;8f46
SIGUIENTE_EJERCITO:		; Los 256 indices
	pop af			;8f47
	inc a			;8f48
	jr nz,REPASA_LOS_EJERCITOS		;8f49
	ret			;8f4b
QUITA_LA_FIGURA:		; La figura cae: se marca, se borra su casilla y se suelta a quien la perseguia
	push bc			;8f4c
	ld h,0bfh		;8f4d   ; 0xBF00+n: su coordenada Y
	ld b,(hl)			;8f4f
	dec h			;8f50
	ld a,(hl)			;8f51
	set 5,(hl)		;8f52   ; Bit 5 de 0xBE00+n: esta figura ya no esta
	and 01fh		;8f54
	ld c,a			;8f56
	call CASILLA_DEL_TABLERO		;8f57   ; Su casilla del tablero ...
	ld (hl),000h		;8f5a   ; ... se queda vacia
	pop bc			;8f5c
	ld hl,0c700h		;8f5d   ; Y ahora un repaso a los 256 perseguidores
SUELTA_A_QUIEN_LA_PERSEGUIA:		; Quien apuntase a esta figura se queda sin objetivo y sin contacto
	ld a,(hl)			;8f60
	cp b			;8f61   ; Este perseguia a la que acaba de caer
	jr nz,SIGUIENTE_PERSEGUIDOR		;8f62
	ld (hl),0ffh		;8f64   ; 0xC700 a 0xFF: ya no persigue a nadie
	ld h,0beh		;8f66
	res 6,(hl)		;8f68   ; Y bit 6 abajo: deja de estar en contacto
	ld h,0c7h		;8f6a
SIGUIENTE_PERSEGUIDOR:		; Los 256 indices
	inc l			;8f6c
	jr nz,SUELTA_A_QUIEN_LA_PERSEGUIA		;8f6d
	ret			;8f6f

; ----------------------------------------------------------------------
; Antes de la batalla: repartir cuantas unidades de cada bando entran. Se llega desde 0x67AA
; ----------------------------------------------------------------------
REPARTE_LOS_QUE_ENTRAN:		; Suma la fuerza de cada bando en la casilla de la batalla y marca con el bit 5 de 0xBD00 a los que pelean
	ld hl,00000h		;8f70
	ld de,00000h		;8f73
	exx			;8f76   ; A partir de aqui L y E del juego alternativo son los dos totales
	ld de,00000h		;8f77   ; 0x8F78 es el operando: la casilla del mapa donde se pelea, que escribe 0x67A5
	ld hl,0b900h		;8f7a   ; 0xB900: la tira de coordenadas X
SUMA_UNA_UNIDAD:		; Si esta en la casilla de la batalla, su fuerza va a uno de los dos totales
	call FUERZA_EN_ESTA_CASILLA		;8f7d   ; Devuelve Z y la fuerza si esta unidad esta en esa casilla
	jr nz,SIGUIENTE_DE_LA_CASILLA		;8f80
	ld c,a			;8f82
	ld a,l			;8f83
	cp 078h		;8f84   ; De 0x78 arriba, al otro total ...
	jr nc,SUMA_AL_OTRO_BANDO		;8f86
	cp 016h		;8f88   ; ... y las unidades 0x16 y 0x17, tambien
	jr z,SUMA_AL_OTRO_BANDO		;8f8a
	cp 017h		;8f8c
	jr z,SUMA_AL_OTRO_BANDO		;8f8e
	ld a,c			;8f90
	exx			;8f91
	add a,l			;8f92   ; Total del primer bando, en L del juego alternativo
	ld l,a			;8f93
	jr nc,L_8FA2		;8f94
	ld l,0ffh		;8f96   ; Se satura en 255
	jr L_8FA2		;8f98
SUMA_AL_OTRO_BANDO:		; La fuerza va al total de E
	ld a,c			;8f9a
	exx			;8f9b
	add a,e			;8f9c   ; Total del segundo bando, en E
	ld e,a			;8f9d
	jr nc,L_8FA2		;8f9e
	ld e,0ffh		;8fa0
L_8FA2:
	exx			;8fa2
	ld h,0b9h		;8fa3
SIGUIENTE_DE_LA_CASILLA:		; Los 256 indices de la tira
	inc l			;8fa5
	jr nz,SUMA_UNA_UNIDAD		;8fa6
	exx			;8fa8
	ld a,l			;8fa9   ; Sin nadie de un bando no hay batalla
	or a			;8faa
	ret z			;8fab
	ld a,e			;8fac
	or a			;8fad
	ret z			;8fae
	ld a,l			;8faf
	add a,e			;8fb0   ; Los dos totales juntos ...
	jr c,REDUCE_LOS_TOTALES		;8fb1
	cp 0fbh		;8fb3   ; ... si no pasan de 0xFA, valen tal cual
	jr c,MARCA_A_LOS_QUE_PELEAN		;8fb5
REDUCE_LOS_TOTALES:		; Los dos juntos pasan de 0xFA: se recortan para que quepan
	ld a,l			;8fb7
	cp 05bh		;8fb8   ; Por debajo de 0x5B, el primero se queda y el otro se recorta
	jr nc,RECORTA_EL_PRIMERO		;8fba
	ld a,0fah		;8fbc
	sub l			;8fbe
	ld e,a			;8fbf
	jr MARCA_A_LOS_QUE_PELEAN		;8fc0
RECORTA_EL_PRIMERO:		; Si los dos son grandes, se dejan en 0x5A y 0xA0
	ld a,e			;8fc2
	cp 0a1h		;8fc3   ; De 0xA1 arriba los dos: 0x5A y 0xA0 fijos
	jr c,RECORTA_EL_SEGUNDO		;8fc5
	ld l,05ah		;8fc7
	ld e,0a0h		;8fc9
	jr MARCA_A_LOS_QUE_PELEAN		;8fcb
RECORTA_EL_SEGUNDO:		; El primero se saca de 0xFA menos el segundo
	ld a,0fah		;8fcd
	sub e			;8fcf
	ld l,a			;8fd0
MARCA_A_LOS_QUE_PELEAN:		; Con los dos cupos ya hechos, va marcando unidades hasta llenarlos
	ld a,l			;8fd1
	inc a			;8fd2
	ld (08ffdh),a		;8fd3   ; 0x8FFD es el operando del cp de 0x8FFC: el cupo del primer bando
	ld a,e			;8fd6
	inc a			;8fd7
	ld (0900eh),a		;8fd8   ; 0x900E es el operando del cp de 0x900D: el del segundo
	ld hl,00000h		;8fdb
	exx			;8fde
	ld hl,0b900h		;8fdf   ; Otra vez la tira de coordenadas
	ld de,(08f78h)		;8fe2   ; Y la casilla donde se pelea
CUMPLE_EL_CUPO:		; Va sumando fuerzas hasta pasarse del cupo; a la que se pasa, se le pone el bit 5
	call FUERZA_EN_ESTA_CASILLA		;8fe6
	jr nz,SIGUIENTE_A_MARCAR		;8fe9
	ld c,a			;8feb
	ld a,l			;8fec
	cp 016h		;8fed   ; Las unidades 0x16 y 0x17 ...
	jr z,MIRA_EL_OTRO_CUPO		;8fef
	cp 017h		;8ff1
	jr z,MIRA_EL_OTRO_CUPO		;8ff3
	cp 078h		;8ff5   ; ... y las de 0x78 arriba van por el otro cupo
	jr nc,MIRA_EL_OTRO_CUPO		;8ff7
	ld a,c			;8ff9
	exx			;8ffa
	add a,l			;8ffb
	cp 000h		;8ffc   ; Operando automodificado en 0x8FD3: el cupo
	jr nc,VUELVE_DEL_ALTERNATIVO		;8ffe   ; Aun no se ha llenado: sigue sumando
	ld l,a			;9000
	exx			;9001
	ld h,0bdh		;9002
	set 5,(hl)		;9004   ; Bit 5 de 0xBD00+n: esta unidad entra en la batalla
	ld h,0b9h		;9006
	jr SIGUIENTE_A_MARCAR		;9008
MIRA_EL_OTRO_CUPO:		; Lo mismo para el segundo bando, con el total en H
	ld a,c			;900a
	exx			;900b
	add a,h			;900c
	cp 000h		;900d   ; Operando automodificado en 0x8FD8: el otro cupo
	jr nc,VUELVE_DEL_ALTERNATIVO		;900f
	exx			;9011
	ld h,0bdh		;9012
	set 5,(hl)		;9014   ; Bit 5 de 0xBD00+n: tambien entra
	ld h,0b9h		;9016
	exx			;9018
	ld h,a			;9019
VUELVE_DEL_ALTERNATIVO:		; Devuelve los registros a su juego
	exx			;901a
SIGUIENTE_A_MARCAR:		; Los 256 indices
	inc l			;901b
	jr nz,CUMPLE_EL_CUPO		;901c
	ld hl,(08f78h)		;901e   ; La casilla de la batalla
	call PANTALLA_DE_BATALLA		;9021
	ld hl,(08f78h)		;9024   ; Y otra vez, ahora para leer el terreno
	call CELDA_DEL_MAPA		;9027   ; De la casilla sale su byte de mapa
	ld (VENTAJA_DEL_TERRENO+1),a		;902a   ; 0x8DCD: el terreno donde se pelea, que da la ventaja
	and 00fh		;902d   ; Su nibble bajo ...
	ld (08deah),a		;902f   ; ... al operando de 0x8DE9
	call COMPRIME_EL_MAPA		;9032   ; El mapa se comprime para dejar sitio a la batalla
	ld b,040h		;9035   ; 0x40 atributos: las dos primeras filas de la pantalla
	ld hl,05800h		;9037
	ld a,046h		;903a   ; Atributo 0x46 arriba, que es tambien el de los textos de la batalla
	ld (082f6h),a		;903c   ; 0x82F6 es el operando de 0x82F5: con que atributo se escribe
PINTA_LA_FRANJA_DE_ARRIBA:		; Las dos primeras filas con el atributo 0x46
	ld (hl),a			;903f
	inc hl			;9040
	djnz PINTA_LA_FRANJA_DE_ARRIBA		;9041
	ld hl,05a40h		;9043   ; 0x5A40: las seis ultimas filas de atributos
	xor a			;9046
	ld b,0c0h		;9047   ; 0xC0 = 192 atributos
PINTA_LA_FRANJA_DE_ABAJO:		; Las seis ultimas filas, en negro
	ld (hl),a			;9049
	inc hl			;904a
	djnz PINTA_LA_FRANJA_DE_ABAJO		;904b
	ld hl,05e00h		;904d   ; El tablero de la batalla: 0x500 bytes desde 0x5E00, encima del menu
	ld de,05e01h		;9050
	ld bc,004ffh		;9053
	ld (hl),000h		;9056
	ldir		;9058
	ld hl,0c700h		;905a   ; 0xC700 entera a 0xFF: nadie persigue a nadie
	ld c,0ffh		;905d
	ld de,0c701h		;905f
	ld (hl),c			;9062
	ldir		;9063
	ld c,0ffh		;9065
	ld hl,0be00h		;9067   ; Y 0xBE00 entera a 0xFF: ninguna figura puesta
	ld de,0be01h		;906a
	ld (hl),c			;906d
	ldir		;906e
	ld b,00fh		;9070   ; Quince obstaculos
PONE_UN_OBSTACULO:		; Sortea una casilla y le mete un 0xFF, pero solo en las de paridad distinta
	push bc			;9072
	call SIGUIENTE_AL_AZAR		;9073   ; Coordenada al azar ...
	and 01fh		;9076   ; ... de cinco bits
	ld c,a			;9078
	and 001h		;9079
	ld l,a			;907b   ; Paridad de una ...
	ld a,h			;907c
	and 01fh		;907d
	ld b,a			;907f
	and 001h		;9080
	cp l			;9082   ; ... contra la de la otra: si coinciden, no se pone nada
	jr z,OBSTACULO_SIGUIENTE		;9083
	call CASILLA_DEL_TABLERO		;9085
	ld (hl),0ffh		;9088   ; 0xFF en la casilla: obstaculo
OBSTACULO_SIGUIENTE:		; Los quince
	pop bc			;908a
	djnz PONE_UN_OBSTACULO		;908b
	ld hl,00300h		;908d   ; 0x0300: la tabla de tramos con la que se sortean las posiciones de salida
	ld a,020h		;9090   ; El primer tramo mide 32 bytes ...
	ld e,01fh		;9092   ; ... y lleva el valor 0x1F
CUATRO_TRAMOS:		; Cuatro tramos de la misma anchura, con valores que van bajando
	ld d,004h		;9094
UN_TRAMO:		; B bytes seguidos con el mismo valor
	ld b,a			;9096
RELLENA_EL_TRAMO:		; Escribe el valor hasta agotar el tramo o la pagina
	ld (hl),e			;9097
	inc l			;9098
	jr z,ARMA_LOS_DOS_BANDOS		;9099   ; Al dar la vuelta L, la pagina esta llena
	djnz RELLENA_EL_TRAMO		;909b
	dec e			;909d   ; Cada tramo, un valor menos
	dec d			;909e
	jr nz,UN_TRAMO		;909f
	inc a			;90a1
	srl a		;90a2   ; Y cada cuatro tramos, la mitad de anchos: asi los valores altos salen mas
	jr CUATRO_TRAMOS		;90a4
ARMA_LOS_DOS_BANDOS:		; Prepara las figuras de cada ejercito que entra en la batalla
	call 00604h		;90a6   ; Los atributos de la pantalla, al VDP
	xor a			;90a9
	ld (08d7ch),a		;90aa   ; La cuenta de figuras del tablero, a cero
	ld (09120h),a		;90ad
	ld de,095a8h		;90b0   ; 0x95A8: el dibujo de ficha 3 de siempre
	ld (08851h),de		;90b3
	ld a,0c8h		;90b7   ; 0xC8 = ret z: el interruptor de 0x8DFA para el primer bando
	ld (SIN_VENTAJA),a		;90b9
	ld hl,0bd16h		;90bc   ; Los ejercitos 0x16 y 0x17 primero ...
	call PREPARA_UN_EJERCITO		;90bf
	inc l			;90c2
	call PREPARA_UN_EJERCITO		;90c3
	ld l,078h		;90c6   ; ... y luego de 0x78 en adelante
EJERCITOS_DEL_PRIMER_BANDO:		; De 0x78 a 0xFF, cada uno suelta sus figuras
	call PREPARA_UN_EJERCITO		;90c8
	inc l			;90cb
	jr nz,EJERCITOS_DEL_PRIMER_BANDO		;90cc
	ld a,0c0h		;90ce   ; 0xC0 = ret nz: el interruptor de 0x8DFA cambia de bando
	ld (SIN_VENTAJA),a		;90d0
	ld a,(08d7ch)		;90d3   ; Cuantas figuras ha puesto el primer bando: esa es la raya que los separa
	inc a			;90d6
	ld (SI_ES_ENEMIGO_LO_APUNTA+1),a		;90d7   ; 0x8AF2: el filtro de amigo o enemigo
	ld (08b5eh),a		;90da   ; 0x8B5E y 0x898E, la misma raya mas uno
	ld (0898eh),a		;90dd
	dec a			;90e0
	ld (08a9ch),a		;90e1   ; 0x8A9C, 0x8A88, 0x8C5B y 0x8B30 se llevan la raya justa
	ld (08a88h),a		;90e4
	ld (08c5bh),a		;90e7
	ld (08b30h),a		;90ea
	dec a			;90ed
	ld (091c1h),a		;90ee   ; 0x91C1 y 0x91A9 se llevan la raya menos uno
	ld (QUEDA_ALGUIEN_DEL_PRIMER_BANDO+1),a		;90f1
	ld hl,00300h		;90f4   ; 0x0300 otra vez
DA_LA_VUELTA_A_LOS_TRAMOS:		; 0x1F menos cada byte: ahora el sorteo tira al otro borde del tablero
	ld a,01fh		;90f7   ; 0x1F menos lo que hubiera: el sorteo se va al lado contrario
	sub (hl)			;90f9
	ld (hl),a			;90fa
	inc l			;90fb
	jr nz,DA_LA_VUELTA_A_LOS_TRAMOS		;90fc
	ld hl,0bd77h		;90fe   ; 0xBD77: el ultimo ejercito del segundo bando
EJERCITOS_DEL_SEGUNDO_BANDO:		; De 0x77 hacia abajo, saltandose los 0x16 y 0x17 que ya estan
	call PREPARA_UN_EJERCITO		;9101
	dec l			;9104
	jp m,ARRANCA_LA_BATALLA		;9105   ; Al pasar de 0 se acaba
	ld a,l			;9108
	cp 017h		;9109   ; El 0x17 y el 0x16 ya se pusieron arriba: se salta al 0x15
	jr nz,EJERCITOS_DEL_SEGUNDO_BANDO		;910b
	ld l,015h		;910d
	jp EJERCITOS_DEL_SEGUNDO_BANDO		;910f
ARRANCA_LA_BATALLA:		; Reparte la raya entre bandos, monta la tabla de bytes invertidos y entra en el bucle
	ld a,(08d7ch)		;9112   ; La raya entre bandos otra vez
	ld (0897eh),a		;9115   ; 0x897E: por que figura empieza la ronda de la maquina
	ld (08e96h),a		;9118   ; 0x8E96: y por cual la de los combates
	inc a			;911b
	ld (08ab8h),a		;911c   ; 0x8AB8: hasta donde busca enemigo 0x8A9E
	ld a,000h		;911f
	ld (TECLA_R_EN_LA_BATALLA+1),a		;9121   ; 0x926F es el operando de 0x926E
	xor 000h		;9124
	ld (09282h),a		;9126   ; 0x9282 es el operando de 0x9281
	ld hl,00300h		;9129   ; 0x0300 pasa a ser la tabla de bytes invertidos, la de reflejar dibujos
	xor a			;912c
UN_BYTE_INVERTIDO:		; Da la vuelta a los ocho bits de A y lo deja en 0x0300+A
	ld b,080h		;912d
ROTA_LOS_OCHO_BITS:		; Lo que sale por arriba de A entra por abajo de B
	rlca			;912f
	rr b		;9130
	jr nc,ROTA_LOS_OCHO_BITS		;9132   ; Cuando el 0x80 de arranque sale de B, el byte esta dado la vuelta
	ld (hl),b			;9134
	inc a			;9135
	inc l			;9136
	jr nz,UN_BYTE_INVERTIDO		;9137
	ld a,001h		;9139
	ld (09190h),a		;913b   ; 0x9190: el aviso 1, "La Batalla ha comenzado."
	ld hl,01010h		;913e   ; La pantalla arranca centrada en la casilla 16,16 ...
	ld (MUEVE_EL_CURSOR_DE_BATALLA+1),hl		;9141   ; ... que es el operando de 0x8E0D
	ld hl,06010h		;9144   ; 0x6010, el byte que sigue a las teclas definidas
	ld a,(hl)			;9147
	ld (PULSA_EN_LA_BATALLA+1),a		;9148   ; 0x8B19: con que empieza el byte de la casilla pulsada
	call DEJA_DE_LLEVARLA_A_MANO		;914b
BUCLE_DE_LA_BATALLA:		; Cada vuelta: limpia coordenadas, mira el mando, redibuja, mueve un bando y mira si queda alguien
	ld hl,0bf00h		;914e
LIMPIA_LAS_COORDENADAS:		; Deja en cinco bits los 256 bytes de 0xBF00
	ld a,01fh		;9151   ; De 0xBF00 solo valen los cinco bits bajos
	and (hl)			;9153
	ld (hl),a			;9154
	inc l			;9155
	jr nz,LIMPIA_LAS_COORDENADAS		;9156
	ld a,(06511h)		;9158   ; El byte del mando
	bit 6,a		;915b   ; Bit 6: la tecla R
	call nz,TECLA_R_EN_LA_BATALLA		;915d
	call MONTA_LA_PANTALLA_DE_BATALLA		;9160   ; Monta y dibuja la pantalla de batalla
	ld a,000h		;9163   ; Operando en 0x9164: por que entrada del despachador va la ronda
	inc a			;9165
	and 003h		;9166   ; Cuatro entradas, en rueda
	ld (09164h),a		;9168   ; Y la siguiente queda apuntada
	add a,a			;916b
	add a,0b7h		;916c   ; 0x94B7: la tabla de cuatro palabras del despachador
	ld l,a			;916e
	adc a,094h		;916f
	sub l			;9171
	ld h,a			;9172
	ld a,(hl)			;9173
	inc hl			;9174
	ld h,(hl)			;9175
	ld l,a			;9176
	ld (LLAMA_AL_DESPACHADOR+1),hl		;9177   ; 0x917B es el operando del call de 0x917A
LLAMA_AL_DESPACHADOR:		; Operando automodificado en 0x9177: una de las cuatro rutinas de la rueda
	call LLAMA_AL_DESPACHADOR		;917a
	call MUEVE_EL_CURSOR_DE_BATALLA		;917d   ; El cursor del jugador
	ld hl,093e5h		;9180   ; Operando en 0x9181: el aviso que se pinta abajo
	ld de,04000h		;9183   ; 0x4000: la primera linea de la pantalla
	call ESCRIBE_TEXTO		;9186
	ld hl,09402h		;9189   ; 0x9402 es solo el 0x00 de cierre: a partir de ahora no se escribe nada
	ld (09181h),hl		;918c
	ld a,000h		;918f   ; Operando en 0x9190: el numero de aviso que haya pedido alguien
	or a			;9191
	jr z,QUEDA_ALGUIEN_DEL_PRIMER_BANDO		;9192   ; Cero: no hay aviso nuevo
	dec a			;9194
	add a,a			;9195
	add a,0d9h		;9196   ; 0x93D9 + (n-1)*2: la tabla de seis punteros a los mensajes
	ld l,a			;9198
	adc a,093h		;9199
	sub l			;919b
	ld h,a			;919c
	ld e,(hl)			;919d
	inc hl			;919e
	ld d,(hl)			;919f
	ld (09181h),de		;91a0   ; El mensaje elegido pasa al operando de 0x9180
	xor a			;91a4
	ld (09190h),a		;91a5   ; Y el aviso se da por servido
QUEDA_ALGUIEN_DEL_PRIMER_BANDO:		; Recorre de la raya menos uno hacia abajo buscando una figura viva
	ld hl,0be00h		;91a8   ; Operando en 0x91A9: la raya entre bandos menos uno
MIRA_SI_VIVE:		; Bit 5 abajo quiere decir que esa figura sigue en pie
	bit 5,(hl)		;91ab   ; Bit 5: si esta abajo, aun queda alguien de este bando
	jr z,QUEDA_ALGUIEN_DEL_SEGUNDO_BANDO		;91ad
	ld a,l			;91af
	dec l			;91b0
	or a			;91b1
	jr nz,MIRA_SI_VIVE		;91b2
	ld hl,NO_HACE_NADA		;91b4   ; Nadie: gana el otro bando
	ld de,BORRA_EL_EJERCITO_DEL_MAPA		;91b7
	jr SE_ACABO_LA_BATALLA		;91ba
QUEDA_ALGUIEN_DEL_SEGUNDO_BANDO:		; Lo mismo con las figuras que van de la raya al final
	ld a,(0897eh)		;91bc   ; 0x897E: el ultimo indice de figuras
	ld l,a			;91bf
	ld a,000h		;91c0   ; Operando en 0x91C1: la raya menos uno
MIRA_SI_VIVE_EL_OTRO:		; Con que quede una viva, la batalla sigue
	bit 5,(hl)		;91c2
	jp z,BUCLE_DE_LA_BATALLA		;91c4   ; Aun queda alguien: otra vuelta del bucle
	dec l			;91c7
	cp l			;91c8
	jr nz,MIRA_SI_VIVE_EL_OTRO		;91c9
	ld de,NO_HACE_NADA		;91cb
	ld hl,BORRA_EL_EJERCITO_DEL_MAPA		;91ce
SE_ACABO_LA_BATALLA:		; Deja en los dos call de abajo quien gana y quien pierde, y se lo aplica a cada ejercito
	ld (091eeh),hl		;91d1   ; 0x91EE es el operando del call de 0x91ED
	ld (EL_OTRO_BANDO+1),de		;91d4   ; 0x91F3 es el operando del call de 0x91F2
	ld hl,0bd00h		;91d8   ; 0xBD00: la lista de ejercitos del mapa
APLICA_EL_RESULTADO:		; A cada ejercito que entro en la batalla se le llama al bando que le toca
	bit 5,(hl)		;91db   ; Bit 5: este ejercito estuvo en la batalla
	jr z,CIERRA_LA_BATALLA		;91dd
	push hl			;91df
	ld a,l			;91e0
	cp 016h		;91e1   ; Los ejercitos 0x16 y 0x17 ...
	jr z,EL_OTRO_BANDO		;91e3
	cp 017h		;91e5
	jr z,EL_OTRO_BANDO		;91e7
	cp 078h		;91e9   ; ... y los de 0x78 arriba van por el otro camino
	jr nc,EL_OTRO_BANDO		;91eb
	call 00000h		;91ed   ; BIOS CHKRAM - Tests RAM and sets RAM slot for the system  [alias: STARTUP, RESET, BOOT] | No es la BIOS: el operando lo acaba de escribir 0x91D1
	jr SIGUIENTE_EJERCITO_DEL_RESULTADO		;91f0
EL_OTRO_BANDO:		; No es la BIOS: el operando lo escribe 0x91D4
	call 00000h		;91f2   ; BIOS CHKRAM - Tests RAM and sets RAM slot for the system  [alias: STARTUP, RESET, BOOT] | No es la BIOS: el operando lo escribe 0x91D4
SIGUIENTE_EJERCITO_DEL_RESULTADO:		; Recupera el puntero de la lista
	pop hl			;91f5
CIERRA_LA_BATALLA:		; Avisa del final, devuelve el mapa a su sitio y decide si se sigue jugando
	inc l			;91f6
	jr nz,APLICA_EL_RESULTADO		;91f7
	call DESPUES_DE_LA_BATALLA		;91f9   ; El cartel de "La Batalla ha finalizado."
	call DESCOMPRIME_EL_MAPA		;91fc   ; El mapa se descomprime otra vez
	ld hl,0b916h		;91ff   ; 0xB916 y 0xBA16: las coordenadas del ejercito 0x16
	ld a,(hl)			;9202
	inc h			;9203
	or (hl)			;9204
	jr nz,L_920A		;9205   ; Si tiene alguna, se le deja donde esta
	call PON_EL_EJERCITO_16_EN_SU_SITIO		;9207
L_920A:
	call BORRA_PANTALLA_NEGRA		;920a   ; Pantalla en negro
	call MIRA_QUIEN_ESTA_EN_LA_CASILLA_56_3F		;920d
	call BUSCA_AL_PORTADOR		;9210   ; El primer indice de 0xBD00 con el bit 4: el ejercito que sigue el jugador
	ld h,0b9h		;9213   ; Sus dos coordenadas ...
	ld a,(hl)			;9215
	inc h			;9216
	or (hl)			;9217
	jr z,A_LA_DERROTA		;9218   ; ... las dos a cero es que ya no esta: DERROTA
	call BORRA_PANTALLA_NEGRA		;921a
	ld sp,05bffh		;921d   ; La pila, a donde la dejo 0x5E01
	ld hl,07fach		;9220   ; Se apila 0x7FAC como direccion de vuelta ...
	push hl			;9223
	ld bc,(08f78h)		;9224   ; ... y BC se lleva la casilla de la batalla, que es el argumento de 0x7FAC
	ret			;9228   ; El ret no vuelve de ningun sitio: salta a la 0x7FAC recien apilada
A_LA_DERROTA:		; La pantalla de Sauron
	jp DERROTA		;9229
PON_EL_EJERCITO_16_EN_SU_SITIO:		; Deja el 0x16 en la casilla 0x6F,0x40 del mapa y su 0xC200 a 0xFF
	ld (hl),040h		;922c   ; 0xBA16 = 0x40
	dec h			;922e
	ld (hl),06fh		;922f   ; 0xB916 = 0x6F
	ld h,0c2h		;9231   ; Y 0xC216 = 0xFF
	ld (hl),0ffh		;9233
	ret			;9235
DESPUES_DE_LA_BATALLA:		; Repinta, reparte 0x18 a los que pelearon y espera a que se pulse disparo
	call MONTA_LA_PANTALLA_DE_BATALLA		;9236
	ld hl,0c600h		;9239   ; 0xC600-0xC6FE a cero
	ld de,0c601h		;923c
	ld bc,000feh		;923f
	ld (hl),000h		;9242
	ldir		;9244
	ld hl,0bd00h		;9246   ; 0xBD00: los ejercitos
REPARTE_A_LOS_QUE_PELEARON:		; A cada ejercito con el bit 5 le pone 0x18 en 0xC600 y le baja el bit
	bit 5,(hl)		;9249   ; Bit 5: este estuvo en la batalla
	jr z,SIGUIENTE_DEL_REPARTO		;924b
	ld h,0c6h		;924d
	ld (hl),018h		;924f   ; 0xC600+n = 0x18
	ld h,0bdh		;9251
	res 5,(hl)		;9253   ; Y se le baja el bit 5
SIGUIENTE_DEL_REPARTO:		; Los 256 indices
	inc l			;9255
	jr nz,REPARTE_A_LOS_QUE_PELEARON		;9256
	call ESPERA_A_SOLTAR_FUEGO		;9258
	ld hl,09403h		;925b   ; 0x9403: "La Batalla ha finalizado."
	ld de,04000h		;925e
	call ESCRIBE_TEXTO		;9261
ESPERA_EL_DISPARO:		; No sigue hasta que se pulsa
	call 0066dh		;9264
	bit 4,a		;9267
	jr z,ESPERA_EL_DISPARO		;9269
	jp ESPERA_A_SOLTAR_FUEGO		;926b
TECLA_R_EN_LA_BATALLA:		; Gasta un uso de 0xC000 y, si queda alguno, mueve al ejercito del jugador
	ld a,000h		;926e   ; Operando en 0x926F, que ponen 0x9121 y 0x92D5
	or a			;9270
	ret z			;9271
	ld hl,0c000h		;9272   ; Operando en 0x9273, que pone 0x8CEE: el ejercito que sigue el jugador
	ld a,(hl)			;9275
	and 0f0h		;9276   ; Nibble alto de 0xC000+n, que se conserva
	ld b,a			;9278
	ld a,(hl)			;9279
	and 00fh		;927a   ; El nibble bajo es la cuenta de usos ...
	dec a			;927c   ; ... y a cero, DERROTA
	jr z,A_LA_DERROTA		;927d
	or b			;927f
	ld (hl),a			;9280
	ld a,000h		;9281   ; Operando en 0x9282, que pone 0x9126
	or a			;9283
	ret z			;9284
	push hl			;9285
	ld hl,(08f78h)		;9286   ; La casilla de la batalla
	call CELDA_DEL_MAPA		;9289
	pop hl			;928c
	ld h,0bdh		;928d   ; Nibble bajo de 0xBD00+n: el tipo de ejercito
	ld a,(hl)			;928f
	and 00fh		;9290
	add a,a			;9292
	add a,a			;9293
	add a,a			;9294
	add a,a			;9295
	add a,047h		;9296   ; 0x6D47 + tipo*16: su ficha en la tabla de tropas
	defb 0fdh,06fh	;ld iyl,a		;9298
	adc a,06dh		;929a
	defb 0fdh,095h	;sub iyl		;929c
	defb 0fdh,067h	;ld iyh,a		;929e
	push hl			;92a0
	ld de,06b34h		;92a1   ; 0x6B34 y 0x6B13: las dos tablas del bloque de textos
	ld hl,06b13h		;92a4
	ld b,007h		;92a7   ; Siete entradas
BUSCA_LA_SALIDA:		; Recorre las siete entradas hasta dar con una que valga
	ld a,(de)			;92a9
	ld (092afh),a		;92aa   ; 0x92AF es el operando de un ld que 0x92A9 va cambiando
	ld a,(ix+000h)		;92ad
	and 00fh		;92b0
	ld (092b7h),a		;92b2   ; 0x92B7 es el operando del cp de 0x92B6
	ld a,(iy+000h)		;92b5
	or a			;92b8   ; Bit 7: esta entrada vale
	jp p,SE_LARGA_DE_LA_BATALLA		;92b9
	inc de			;92bc
	inc hl			;92bd
	inc hl			;92be
	djnz BUSCA_LA_SALIDA		;92bf
	pop hl			;92c1
	ret			;92c2
SE_LARGA_DE_LA_BATALLA:		; Le suma a las coordenadas del ejercito el salto que dice la tabla de 0x6B13
	ld c,(hl)			;92c3
	inc hl			;92c4
	ld b,(hl)			;92c5
	pop hl			;92c6
	ld h,0b9h		;92c7   ; 0xB900+n: la coordenada X, sin el bit de "hay alguien"
	ld a,(hl)			;92c9
	and 07fh		;92ca
	add a,c			;92cc   ; Se le suma el salto
	ld (hl),a			;92cd
	inc h			;92ce   ; Y lo mismo con 0xBA00+n
	ld a,(hl)			;92cf
	and 07fh		;92d0
	add a,b			;92d2
	ld (hl),a			;92d3
	xor a			;92d4
	ld (TECLA_R_EN_LA_BATALLA+1),a		;92d5   ; 0x926F: la tecla R se apaga hasta que la vuelvan a encender
	ld l,000h		;92d8
	ld b,l			;92da
	jp QUITA_LA_FIGURA		;92db   ; Y la figura se quita del tablero
MIRA_QUIEN_ESTA_EN_LA_CASILLA_56_3F:		; Cuenta unidades en (0x56, 0x3F); si solo hay de las otras, DERROTA
	ld hl,0b900h		;92de   ; 0xB900: las coordenadas X
	ld bc,00000h		;92e1
UNA_UNIDAD_EN_LA_CASILLA:		; Compara las dos coordenadas con 0x56 y 0x3F
	ld a,(hl)			;92e4
	cp 056h		;92e5   ; 0x56 en la X ...
	jr nz,SIGUIENTE_DE_LA_VIGILANCIA		;92e7
	inc h			;92e9
	ld a,(hl)			;92ea
	dec h			;92eb
	cp 03fh		;92ec   ; ... y 0x3F en la Y: la casilla que se vigila
	jr nz,SIGUIENTE_DE_LA_VIGILANCIA		;92ee
	ld a,l			;92f0
	cp 016h		;92f1   ; Las unidades 0x16 y 0x17 ...
	jr z,CUENTA_EN_C		;92f3
	cp 017h		;92f5
	jr z,CUENTA_EN_C		;92f7
	cp 078h		;92f9   ; ... y las de 0x78 arriba cuentan en C
	jr nc,CUENTA_EN_C		;92fb
	inc b			;92fd   ; Las demas, en B
	jr SIGUIENTE_DE_LA_VIGILANCIA		;92fe
CUENTA_EN_C:		; Suma una al otro contador
	inc c			;9300
SIGUIENTE_DE_LA_VIGILANCIA:		; Los 256 indices
	inc l			;9301
	jr nz,UNA_UNIDAD_EN_LA_CASILLA		;9302
	ld a,b			;9304
	or a			;9305   ; Con una sola de las primeras, no pasa nada
	ret nz			;9306
	ld a,c			;9307
	or a			;9308
	jp nz,A_LA_DERROTA		;9309   ; Ninguna de las primeras y alguna de las otras: DERROTA
	ret			;930c
EJERCITO_TIPO_5_DESHECHO:		; El ejercito de tipo 5 no desaparece: se le pasa lo que llevaba a otro
	push bc			;930d
	ld h,0bah		;930e   ; 0xBA00+n
	call PON_EL_EJERCITO_16_EN_SU_SITIO		;9310   ; Se coloca el ejercito 0x16 en 0x6F,0x40
	ld b,000h		;9313
	ld hl,0bd00h		;9315   ; 0xBD00: la lista de ejercitos
	ld a,l			;9318
BUSCA_QUIEN_LO_HEREDA:		; Busca un ejercito puesto y con el bit 5, saltandose el 0x16, el 0x17 y los de 0x78 arriba
	inc b			;9319
	jr z,SIN_HEREDERO		;931a   ; Al dar la vuelta B se acaba la busqueda
	inc a			;931c
	cp 016h		;931d   ; Ni el 0x16 ...
	jr z,BUSCA_QUIEN_LO_HEREDA		;931f
	cp 017h		;9321   ; ... ni el 0x17 ...
	jr z,BUSCA_QUIEN_LO_HEREDA		;9323
	cp 078h		;9325   ; ... ni de 0x78 arriba
	jr nc,BUSCA_QUIEN_LO_HEREDA		;9327
	ld l,a			;9329
	bit 5,(hl)		;932a   ; Bit 5: tiene que haber estado en la batalla
	jr z,BUSCA_QUIEN_LO_HEREDA		;932c
	ld h,0b9h		;932e   ; Sus coordenadas: si son cero, tampoco vale
	ld a,(hl)			;9330
	inc h			;9331
	or (hl)			;9332
	ld h,0bdh		;9333
	jr z,BUSCA_QUIEN_LO_HEREDA		;9335
	ld a,l			;9337
	ld (09316h),a		;9338   ; 0x9316 es el byte bajo del ld hl de 0x9315
DEJA_LA_HERENCIA:		; 0xBB00+c apunta al heredero, 0xBC00+c a 0xFF y 0xC500+c a 0x1F
	ld h,0bbh		;933b   ; 0xBB00+c se queda con el heredero
	ld l,c			;933d
	ld (hl),a			;933e
	inc h			;933f
	ld (hl),0ffh		;9340   ; 0xBC00+c a 0xFF
	ld h,0c5h		;9342   ; Y 0xC500+c a 0x1F figuras
	ld (hl),01fh		;9344
	pop bc			;9346
	ret			;9347
SIN_HEREDERO:		; Si no se encuentra a nadie, hereda el ejercito que sigue el jugador
	push hl			;9348
	call BUSCA_AL_PORTADOR		;9349
	pop hl			;934c
	jr DEJA_LA_HERENCIA		;934d
FUERZA_EN_ESTA_CASILLA:		; Devuelve Z y en A las figuras de 0xC500+n si la unidad esta en la casilla D,E
	ld a,(hl)			;934f   ; 0xB900+n sin el bit de "hay alguien" ...
	and 07fh		;9350
	cp e			;9352   ; ... contra E
	ret nz			;9353
	inc h			;9354   ; Y 0xBA00+n ...
	ld a,(hl)			;9355
	dec h			;9356
	and 07fh		;9357
	cp d			;9359   ; ... contra D
	ret nz			;935a
	ld h,0c5h		;935b   ; 0xC500+n: cuantas figuras pone, minimo una
	ld a,(hl)			;935d
	or a			;935e
	jr nz,L_9362		;935f
	inc a			;9361
L_9362:
	cp a			;9362   ; cp a deja el cero puesto sin tocar A
	ld h,0b9h		;9363
	ret			;9365

; ----------------------------------------------------------------------
; El mapa se guarda COMPRIMIDO: 0x9394 lo empaqueta antes de la batalla y 0x9366 lo devuelve entero
; ----------------------------------------------------------------------
DESCOMPRIME_EL_MAPA:		; De 0x16ED bytes de parejas cuenta/valor salen los 0x33CD del mapa. La llaman 0x5E28 al arrancar y 0x91FC al salir de la batalla
	ld a,009h		;9366   ; Atributo 9 en toda la pantalla mientras se trabaja
	call PINTA_TODOS_LOS_ATRIBUTOS		;9368
	ld hl,0cc00h		;936b   ; El mapa comprimido, tal como esta en RAM
	ld de,04000h		;936e   ; Se pasa a 0x4000, la pantalla, que aqui hace de sitio de paso
	ld bc,016edh		;9371   ; 0x16ED bytes es lo que ocupa comprimido
	push hl			;9374
	push de			;9375
	ldir		;9376
	ld bc,033cdh		;9378   ; 0x33CD es lo que mide entero
	pop hl			;937b
	pop de			;937c
	push bc			;937d
	exx			;937e   ; El contador de lo que falta va en HL del juego alternativo
	pop hl			;937f
	exx			;9380
UNA_PAREJA:		; B = cuantas veces, A = el byte que se repite
	ld b,(hl)			;9381
	inc hl			;9382
	ld a,(hl)			;9383
	inc hl			;9384
REPITE_EL_BYTE:		; Lo escribe y descuenta; al llegar a cero, se acabo
	ld (de),a			;9385
	inc de			;9386   ; Un byte del mapa ya descomprimido
	exx			;9387
	ex af,af'			;9388
	dec hl			;9389   ; Una casilla menos de las 0x33CD
	ld a,h			;938a
	or l			;938b
	ret z			;938c   ; Cuando no falta nada, se sale desde dentro del bucle
	ex af,af'			;938d
	exx			;938e
	djnz REPITE_EL_BYTE		;938f   ; Hasta agotar la cuenta de esta pareja
	jp UNA_PAREJA		;9391
COMPRIME_EL_MAPA:		; Recorre los 0x33CC bytes del mapa y los deja en parejas cuenta/valor: 0x16EC bytes, y el resto queda libre para la batalla
	ld a,009h		;9394   ; Atributo 9 mientras se trabaja
	call PINTA_TODOS_LOS_ATRIBUTOS		;9396
	ld hl,0cc00h		;9399   ; El mapa entero
	ld de,04000h		;939c   ; A 0x4000, que hace de sitio de paso
	ld bc,033cch		;939f   ; Los 0x33CC bytes del mapa
	push hl			;93a2
	push de			;93a3
	call EMPAQUETA		;93a4   ; Se comprime de HL a DE
	ld bc,016ech		;93a7   ; 0x16EC bytes es lo que ocupa comprimido ...
	pop hl			;93aa
	pop de			;93ab
	ldir		;93ac   ; ... y vuelven a 0xCC00: de ahi arriba queda libre para la batalla
	ld a,020h		;93ae   ; Atributo 0x20 y pantalla en negro
	jp BORRA_PANTALLA		;93b0
EMPAQUETA:		; Va contando cuantas veces seguidas se repite cada byte
	push bc			;93b3
	exx			;93b4   ; Lo que queda por leer, en HL del juego alternativo
	pop hl			;93b5
	exx			;93b6
EMPIEZA_UNA_TIRA:		; Se apunta el byte y la cuenta arranca a cero
	ld c,(hl)			;93b7
	ld b,000h		;93b8
	jr CUENTA_UNO_MAS		;93ba
SIGUE_LA_TIRA:		; Mientras el byte se repita, la cuenta sube
	ld a,c			;93bc
	cp (hl)			;93bd
	jr nz,CIERRA_Y_SIGUE		;93be
CUENTA_UNO_MAS:		; Sube la cuenta; si da la vuelta, se cierra la pareja
	inc hl			;93c0
	inc b			;93c1
	jr z,CIERRA_Y_SIGUE		;93c2   ; La cuenta no pasa de 256
	exx			;93c4
	dec hl			;93c5
	ld a,h			;93c6
	or l			;93c7
	exx			;93c8
	jr z,ESCRIBE_LA_PAREJA		;93c9   ; Se acabo el mapa: se cierra la ultima pareja
	jr SIGUE_LA_TIRA		;93cb
CIERRA_Y_SIGUE:		; Escribe la pareja y empieza otra
	call ESCRIBE_LA_PAREJA		;93cd
	jr EMPIEZA_UNA_TIRA		;93d0
ESCRIBE_LA_PAREJA:		; Deja la cuenta y detras el byte
	ld a,b			;93d2
	ld (de),a			;93d3   ; Primero cuantas veces ...
	inc de			;93d4
	ld a,c			;93d5
	ld (de),a			;93d6   ; ... y detras el byte que se repite
	inc de			;93d7
	ret			;93d8

; ----------------------------------------------------------------------
; DATOS punteros_de_los_mensajes: Seis punteros a los mensajes de abajo
;   (0x9180, 0x9189, 0x925B)
;   0x93d9..0x93e5  (12 bytes)
DATA_punteros_de_los_mensajes:
	defw 093e5h	; 93d9  -> DATA_mensajes_de_abajo
	defw 09421h	; 93db
	defw 0943fh	; 93dd
	defw 0945dh	; 93df
	defw 0947bh	; 93e1
	defw 09499h	; 93e3

; ----------------------------------------------------------------------
; DATOS mensajes_de_abajo: Mensajes: "La Batalla ha comenzado/finalizado",
;   "Elige el enemigo a atacar", "No puedes atacar a un amigo", "No pertenece
;   a tu Alianza", "Nuevo destino elegido", "Aqui no hay nadie"
;   0x93e5..0x94b7  (210 bytes)
DATA_mensajes_de_abajo:
	defb 04ch,061h,020h,042h,061h,074h,061h,06ch,06ch,061h,020h,068h,061h,020h,063h,06fh	; 93e5  La Batalla ha co
	defb 06dh,065h,06eh,07ah,061h,064h,06fh,02eh,020h,020h,020h,020h,020h,000h,04ch,061h	; 93f5  menzado.     .La
	defb 020h,042h,061h,074h,061h,06ch,06ch,061h,020h,068h,061h,020h,066h,069h,06eh,061h	; 9405   Batalla ha fina
	defb 06ch,069h,07ah,061h,064h,06fh,02eh,020h,020h,020h,020h,000h,045h,06ch,069h,067h	; 9415  lizado.    .Elig
	defb 065h,020h,065h,06ch,020h,065h,06eh,065h,06dh,069h,067h,06fh,020h,061h,020h,061h	; 9425  e el enemigo a a
	defb 074h,061h,063h,061h,072h,02eh,020h,020h,020h,000h,04eh,06fh,020h,070h,075h,065h	; 9435  tacar.   .No pue
	defb 064h,065h,073h,020h,061h,074h,061h,063h,061h,072h,020h,061h,020h,075h,06eh,020h	; 9445  des atacar a un 
	defb 061h,06dh,069h,067h,06fh,02eh,020h,000h,04eh,06fh,020h,070h,065h,072h,074h,065h	; 9455  amigo. .No perte
	defb 06eh,065h,063h,065h,020h,061h,020h,074h,075h,020h,041h,06ch,069h,061h,06eh,07ah	; 9465  nece a tu Alianz
	defb 061h,02eh,020h,020h,020h,000h,04eh,075h,065h,076h,06fh,020h,064h,065h,073h,074h	; 9475  a.   .Nuevo dest
	defb 069h,06eh,06fh,020h,065h,06ch,065h,067h,069h,064h,06fh,02eh,020h,020h,020h,020h	; 9485  ino elegido.    
	defb 020h,020h,020h,000h,041h,071h,075h,069h,020h,06eh,06fh,020h,068h,061h,079h,020h	; 9495     .Aqui no hay 
	defb 06eh,061h,064h,069h,065h,02eh,020h,020h,020h,020h,020h,020h,020h,020h,020h,020h	; 94a5  nadie.          
	defb 020h,000h	; 94b5

; ----------------------------------------------------------------------
; DATOS tabla_del_despachador_9163: Tabla de 4 palabras del despachador de
;   0x9163 (la CUARTA, 0x94BD, es una variable: 0x8BA1 mete 0x8BE4 y 0x8C83
;   devuelve 0x8F19)
;   0x94b7..0x94bf  (8 bytes)
DATA_tabla_del_despachador_9163:
	defw 08e95h	; 94b7  -> RESUELVE_LOS_COMBATES
	defw 08f19h	; 94b9  -> NO_HACE_NADA
	defw 0897dh	; 94bb  -> MUEVE_LAS_UNIDADES
	defw 08f19h	; 94bd  -> NO_HACE_NADA

; ----------------------------------------------------------------------
; DATOS tabla_del_despachador_8A11: Tabla de 4 palabras que 0x8A11-0x8A1E
;   indexa con A&3
;   0x94bf..0x94c7  (8 bytes)
DATA_tabla_del_despachador_8A11:
	defw 0894dh	; 94bf  -> DIAGONAL_C_MAS_B_MENOS
	defw 0895ch	; 94c1  -> DIAGONAL_LAS_DOS_MENOS
	defw 0896bh	; 94c3  -> DIAGONAL_LAS_DOS_MAS
	defw 0893eh	; 94c5  -> DIAGONAL_B_MAS_C_MENOS

; ----------------------------------------------------------------------
; DATOS tablas_de_caracteres_y_datos: Tablas de codigos de caracter/tile y
;   datos (0x95A8 lo apuntan 0x8850, 0x8B3B, 0x8C74, 0x8E42, 0x90B0; formato
;   pendiente)
;   0x94c7..0x9627  (352 bytes)
DATA_tablas_de_caracteres_y_datos:
	defb 02fh,02eh,02dh,02ch,033h,032h,031h,030h,027h,026h,025h,024h,02bh,02ah,029h,028h	; 94c7  /.-,3210'&%$+*)(
	defb 04fh,04eh,04dh,04ch,053h,052h,051h,050h,047h,046h,045h,044h,04bh,04ah,049h,048h	; 94d7  ONMLSRQPGFEDKJIH
	defb 03fh,03eh,03dh,03ch,043h,042h,041h,040h,037h,036h,035h,034h,03bh,03ah,039h,038h	; 94e7  ?>=<CBA@7654;:98
	defb 01fh,01eh,01dh,01ch,023h,022h,021h,020h,017h,016h,015h,014h,01bh,01ah,019h,018h	; 94f7  ....#"! ........
	defb 05ch,05bh,05ah,000h,05fh,05eh,05dh,000h,056h,055h,054h,000h,059h,058h,057h,000h	; 9507  \[Z._^].VUT.YXW.
	defb 00fh,00eh,00dh,00ch,013h,012h,011h,010h,007h,006h,005h,004h,00bh,00ah,009h,008h	; 9517  ................
	defb 068h,067h,066h,000h,06bh,06ah,069h,000h,062h,061h,060h,000h,065h,064h,063h,000h	; 9527  hgf.kji.ba`.edc.
	defb 000h,000h,08bh,08ah,08fh,08eh,08dh,08ch,000h,085h,084h,000h,089h,088h,087h,086h	; 9537  ................
	defb 000h,000h,09fh,000h,0a3h,0a2h,0a1h,0a0h,000h,000h,09ah,000h,09eh,09dh,09ch,09bh	; 9547  ................
	defb 000h,000h,095h,000h,099h,098h,097h,096h,000h,000h,090h,000h,094h,093h,092h,091h	; 9557  ................
	defb 000h,000h,07fh,000h,083h,082h,081h,080h,000h,07ah,079h,000h,07eh,07dh,07ch,07bh	; 9567  .........zy.~}|{
	defb 000h,000h,000h,000h,0ach,0abh,0aah,000h,000h,0a6h,0a5h,0a4h,0a9h,0a8h,0a7h,000h	; 9577  ................
	defb 000h,000h,074h,073h,078h,077h,076h,075h,000h,06eh,06dh,06ch,072h,071h,070h,06fh	; 9587  ..tsxwvu.nmlrqpo
	defb 000h,000h,000h,000h,0b3h,0b2h,0b1h,000h,000h,000h,0adh,000h,0b0h,0afh,0aeh,000h	; 9597  ................
	defb 0e0h,01fh,007h,0f8h,0f9h,006h,09fh,060h,07fh,080h,0feh,001h,0feh,001h,07fh,080h	; 95a7  .......`........
	defb 07fh,080h,0feh,001h,0feh,001h,07fh,080h,09fh,060h,0f9h,006h,007h,0f8h,0e0h,01fh	; 95b7  .........`......
	defb 003h,0fch,0c0h,03fh,0f1h,00eh,08fh,070h,0d3h,02ch,0cbh,034h,03fh,0c0h,0fch,003h	; 95c7  ...?...p.,.4?...
	defb 0fch,003h,03fh,0c0h,0cbh,034h,0d3h,02ch,08fh,070h,0f1h,00eh,0c0h,03fh,003h,0fch	; 95d7  ..?..4.,.p...?..
	defb 0e0h,01fh,007h,0f8h,051h,0aeh,095h,06ah,02ah,0d5h,0aah,055h,054h,0abh,055h,0aah	; 95e7  ....Q..j*..UT.U.
	defb 02ah,0d5h,0aah,055h,054h,0abh,055h,0aah,08ah,075h,0a9h,056h,007h,0f8h,0e0h,01fh	; 95f7  *..UT.U..u.V....
	defb 0ffh,000h,0ffh,000h,0ffh,000h,0ffh,000h,0bfh,040h,0ffh,000h,0ffh,000h,05bh,0a4h	; 9607  .........@....[.
	defb 0d5h,02ah,0cfh,030h,0b7h,048h,0feh,001h,0f8h,007h,07fh,080h,0ffh,000h,0f6h,009h	; 9617  .*.0.H..........

; ======================================================================
; CODIGO 0x9627..0x9687  (96 bytes)
; ======================================================================


CARGA_LA_PARTIDA:		; Lee de la cinta 0x1000 bytes a 0xB900 con bandera 0xFC. La llama 0x802A
	call PIDE_LA_CINTA		;9627   ; Primero el aviso de poner la cinta; con la tecla 1 se cancela
	ret c			;962a
	ld hl,09687h		;962b   ; 0x9687: "Cargando Posiciones"
	call ESCRIBE_TEXTO		;962e
	ld ix,0b900h		;9631   ; 0xB900: ahi empiezan las tiras de unidades
	ld de,01000h		;9635   ; 0x1000 bytes: de 0xB900 a 0xC8FF
	ld a,0fch		;9638   ; Bandera 0xFC, la misma con que se graba
REINTENTA_LA_CARGA:		; Si la carga falla, se vuelve a intentar sin salir
	push ix		;963a
	push de			;963c
	push af			;963d
	scf			;963e   ; El acarreo pide leer, no verificar
	call 007f9h		;963f   ; El cargador de cinta del bloque bajo
	jr c,CARGA_HECHA		;9642   ; Con acarreo ha ido bien
	pop af			;9644
	pop de			;9645
	pop ix		;9646
	jr REINTENTA_LA_CARGA		;9648
CARGA_HECHA:		; Recupera los registros apilados
	pop af			;964a
	pop de			;964b
	pop ix		;964c
DEJA_LA_CINTA:		; Borde negro y se reabren las interrupciones
	xor a			;964e
	call 00467h		;964f   ; Borde en negro otra vez
	ei			;9652
	ret			;9653
SALVA_LA_PARTIDA:		; Graba en cinta los 0x1000 bytes de 0xB900 con bandera 0xFC. La llama 0x802A
	call PIDE_LA_CINTA		;9654
	ret c			;9657
	ld hl,096aah		;9658   ; 0x96AA: "Salvando Posiciones del juego"
	call ESCRIBE_TEXTO		;965b
	ld ix,0b900h		;965e
	ld de,01000h		;9662
	ld a,0fch		;9665
	call 008b2h		;9667   ; La grabadora del bloque bajo
	jr DEJA_LA_CINTA		;966a
PIDE_LA_CINTA:		; Escribe "Pon el cassette y pulsa Fuego" y espera; con la tecla 1 se cancela
	ld hl,096cdh		;966c   ; 0x96CD: "Pon el cassette y pulsa Fuego"
	call ESCRIBE_TEXTO		;966f
	call ESPERA_A_SOLTAR_FUEGO		;9672
ESPERA_FUEGO_O_TECLA_1:		; Bit 5 cancela, bit 4 sigue
	call 0066dh		;9675
	bit 5,a		;9678   ; Bit 5, la tecla 1: se deja
	jr nz,CANCELADO		;967a
	bit 4,a		;967c   ; Bit 4: el disparo
	jr z,ESPERA_FUEGO_O_TECLA_1		;967e
	call ESPERA_A_SOLTAR_FUEGO		;9680
	or a			;9683   ; Sin acarreo: adelante
	ret			;9684
CANCELADO:		; Con acarreo: el jugador se ha echado atras
	scf			;9685
	ret			;9686

; ----------------------------------------------------------------------
; DATOS rotulos_de_cinta: Rotulos "Cargando Posiciones" y compania para
;   cargar/salvar la partida en cinta (0x962B, 0x9658, 0x966C)
;   0x9687..0x96f0  (105 bytes)
DATA_rotulos_de_cinta:
	defb 0d0h,0e0h,020h,020h,020h,020h,020h,020h,020h,043h,061h,072h,067h,061h,06eh,064h	; 9687  ..       Cargand
	defb 06fh,020h,050h,06fh,073h,069h,063h,069h,06fh,06eh,065h,073h,020h,020h,020h,020h	; 9697  o Posiciones    
	defb 020h,020h,000h,0d0h,0e0h,020h,020h,053h,061h,06ch,076h,061h,06eh,064h,06fh,020h	; 96a7    ...  Salvando 
	defb 050h,06fh,073h,069h,063h,069h,06fh,06eh,065h,073h,020h,064h,065h,06ch,020h,06ah	; 96b7  Posiciones del j
	defb 075h,065h,067h,06fh,020h,000h,0d0h,0e0h,020h,020h,050h,06fh,06eh,020h,065h,06ch	; 96c7  uego ...  Pon el
	defb 020h,063h,061h,073h,073h,065h,074h,074h,065h,020h,079h,020h,070h,075h,06ch,073h	; 96d7   cassette y puls
	defb 061h,020h,046h,075h,065h,067h,06fh,020h,000h	; 96e7  a Fuego .

; ----------------------------------------------------------------------
; DATOS modo_de_control: Variable: modo de control (0 joystick, 1 cursores, 3
;   teclado); la lee 0x5E31 y 0x0698, la escribe 0x5E61
;   0x96f0..0x96f1  (1 bytes)
DATA_modo_de_control:
	defb 000h	; 96f0
