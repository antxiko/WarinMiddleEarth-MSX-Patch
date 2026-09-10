; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LA CABECERA Y EL ARRANQUE
; ==========================================================================
; Esto es lo unico que corre desde la ROM. La BIOS llama a INIT con el
; cartucho en la pagina 1 (y, siendo un MegaROM, tambien en la 2): aqui solo
; se fija el banco 0 en la ventana, se averigua en que ranura esta el propio
; cartucho, se copia el stub a 0xD800 y se salta a el. Todo lo demas -buscar
; RAM, mover los bloques, dejar el VDP y el PSG como los deja la cinta- lo
; hace el stub desde la RAM, porque tiene que quitar el cartucho de la
; pagina 1 para escribir en ella.
;
; Se ensambla con STUB_LEN = tamano del stub ya ensamblado (lo pasa
; tools/haz_rom.py con --equ); el propio haz_rom.py pega el stub justo
; detras, en STUB_ROM.
; ==========================================================================

        include "direcciones.inc"
        org     04000h

        defb    "AB"
        defw    INIT
        defw    0                       ; STATEMENT
        defw    0                       ; DEVICE
        defw    0                       ; TEXT (BASIC)
        defs    6,0

INIT:
        di
        xor     a
        ld      (BANCO_VENTANA),a       ; banco 0 en 0x4000-0x7FFF
        ld      (07000h),a              ; y en la segunda ventana, por dejarla en algo conocido

        ; El identificador del cartucho, tal como lo quiere ENASLT: la
        ; primaria de la pagina 1 sale del puerto A8 (RSLREG); si EXPTBL dice
        ; que esta expandida, la secundaria sale de SLTTBL, que es lo ultimo
        ; que la BIOS escribio en el registro 0xFFFF de esa primaria.
        call    RSLREG
        rrca
        rrca
        and     003h
        ld      c,a                     ; C = primaria
        ld      b,0
        ld      hl,EXPTBL
        add     hl,bc
        ld      a,(hl)
        bit     7,a
        ld      a,c
        jr      z,ID_LISTO
        ld      hl,SLTTBL
        add     hl,bc
        ld      a,(hl)
        rrca                            ; bits 3-2 de SLTTBL: la secundaria de la pagina 1
        rrca
        and     003h
        rlca
        rlca
        or      c
        or      080h
ID_LISTO:
        push    af                      ; el ldir no toca AF: el identificador viaja en la pila
        ld      hl,STUB_ROM
        ld      de,STUB
        ld      bc,STUB_LEN
        ldir
        pop     af
        ld      (ID_CART),a
        jp      STUB

STUB_ROM:                               ; aqui pega haz_rom.py el stub ensamblado
