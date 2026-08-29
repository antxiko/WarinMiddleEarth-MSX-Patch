; ==========================================================================
; War in Middle Earth (MSX) - PARCHE de Araubi
; Rutina "MUESTRA LOS VALORES": escribe los SEIS atributos numericos de la
; unidad en su ficha, en la columna 20 de cada fila (0..255 en tres cifras).
;
; Vive en 0x6600-0x6713, el motor del altavoz del ZX Spectrum, que en esta
; conversion no lo llama NADIE (los cuatro sitios que piden efecto acaban en
; el ret pelado de 0x65FF). O sea, zona muerta reutilizable.
;
; La engancha el trampolin de 0x708A: donde ARMA_LA_FICHA hacia `ld hl,0x5FBD`
; justo antes de pintar la ventana, ahora hace `call 0x6600`; esta rutina
; escribe los numeros en el buffer de la ficha (0x7C17) y termina rehaciendo
; ese mismo `ld hl,0x5FBD`, de modo que el render sigue igual.
;
; La unidad de la ficha es el operando de MIRA_UNA_UNIDAD (0x6EAD).
; Atributos (arrays paralelos de 256 bytes, indexados por unidad):
;   0xC000 nibble bajo = Valioso   nibble alto = Habil
;   0xC100 nibble bajo = Duro      nibble alto = Bravo
;   0xC200 byte entero = Energico  (gasta al andar)
;   0xC300 byte entero = Decidido  (sube un mes si y otro tambien: la
;                                   corrupcion del Anillo del que lo lleva)
; Filas del buffer de la ficha (0x7C17, 24 columnas por fila):
;   fila 3 = 0x7C5F Energico   fila 4 = 0x7C77 Decidido
;   fila 5 = 0x7C8F Habil      fila 6 = 0x7CA7 Valioso
;   fila 7 = 0x7CBF Duro       fila 8 = 0x7CD7 Bravo
; Columna 20 de cada fila = base + 0x14.
; ==========================================================================

CIFRAS   equ 07113h        ; ESCRIBE_A_EN_TRES_CIFRAS: A=valor, HL=destino
NIBALTO  equ 07096h        ; NIBBLE_ALTO: A -> nibble alto de A
UNIDAD   equ 06eadh        ; operando de MIRA_UNA_UNIDAD: la unidad de la ficha

	org 06600h
MUESTRA_LOS_VALORES:
	push bc
	push de
	ld a,(UNIDAD)
	ld e,a               ; E = numero de unidad (fijo durante toda la rutina)

	ld d,0c2h            ; Energico = 0xC200+n  -> fila 3, col 20 = 0x7C73
	ld a,(de)
	ld hl,07c73h
	call CIFRAS

	ld d,0c3h            ; Decidido = 0xC300+n  -> fila 4, col 20 = 0x7C8B
	ld a,(de)
	ld hl,07c8bh
	call CIFRAS

	ld d,0c0h            ; Habil = 0xC000+n nibble alto -> fila 5, col 20 = 0x7CA3
	ld a,(de)
	call NIBALTO
	ld hl,07ca3h
	call CIFRAS

	ld d,0c0h            ; Valioso = 0xC000+n nibble bajo -> fila 6, col 20 = 0x7CBB
	ld a,(de)
	and 00fh
	ld hl,07cbbh
	call CIFRAS

	ld d,0c1h            ; Duro = 0xC100+n nibble bajo -> fila 7, col 20 = 0x7CD3
	ld a,(de)
	and 00fh
	ld hl,07cd3h
	call CIFRAS

	ld d,0c1h            ; Bravo = 0xC100+n nibble alto -> fila 8, col 20 = 0x7CEB
	ld a,(de)
	call NIBALTO
	ld hl,07cebh
	call CIFRAS

	pop de
	pop bc
	ld hl,05fbdh         ; lo que hacia el ld hl,0x5FBD que reemplaza el trampolin
	ret
