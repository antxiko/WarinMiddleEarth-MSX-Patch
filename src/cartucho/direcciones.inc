; ==========================================================================
; WAR IN MIDDLEEARTH - de cinta a cartucho: las direcciones que comparten
; el trozo que corre desde la ROM (cargador_rom.asm) y el que corre desde la
; RAM (cargador_ram.asm), y los codigos de operacion del plan de carga que
; genera tools/haz_rom.py.
; ==========================================================================

; Donde vive el stub en RAM. La cinta cargaba su cargador en 0xD6D8-0xD981 y
; el bloque alto, tal como cae de la cinta, acaba en 0xD12F: 0xD800 queda por
; encima de todo lo que se copia y por debajo del area de trabajo de la BIOS
; (0xF380), que hace falta intacta mientras se llama a ENASLT.
STUB            equ 0D800h
PILA            equ 0F380h      ; la pila del stub, justo debajo del area de la BIOS

; Las variables van al principio del stub, detras de un jp, para que el trozo
; de ROM pueda escribirlas sin depender de la tabla de simbolos.
ID_CART         equ STUB+3      ; identificador de ranura del cartucho (formato ENASLT)
ID_RAM0         equ STUB+4      ; ranura con RAM en la pagina 0
ID_RAM1         equ STUB+5      ; ... en la pagina 1
ID_RAM2         equ STUB+6      ; ... en la pagina 2
BIOS_OK         equ STUB+7      ; 1 mientras la pagina 0 siga siendo la BIOS

; BIOS
ENASLT          equ 00024h
RSLREG          equ 00138h
EXPTBL          equ 0FCC1h
SLTTBL          equ 0FCC5h

; Los dos registros del mapper ASCII16. Cada uno manda en una ventana, y son
; ventanas DISTINTAS: 0x6000 elige lo que se ve en 0x4000-0x7FFF -que es por
; donde el plan copia los datos- y 0x7000 lo que se ve en 0x8000-0xBFFF, que
; es por donde se asoma la musica. Los dos registros viven en la pagina 1, asi
; que solo se pueden escribir mientras el cartucho este puesto ahi; medido en
; una VG-8020, el banco elegido SOBREVIVE luego a conmutar la ranura.
BANCO_VENTANA   equ 06000h
BANCO_VENTANA_2 equ 07000h

; Cada entrada del plan son 8 bytes:
;   +0 op   +1 b (banco, valor o registro)   +2 src   +4 dst   +6 len
OP_FIN          equ 0
OP_ROM_RAM      equ 1   ; banco b: copia len bytes de ROM src (0x4000-0x7FFF) a RAM dst
OP_ROM_VRAM     equ 2   ; banco b: copia len bytes de ROM src a VRAM dst
OP_VRAM_RAM     equ 3   ; copia len bytes de VRAM src a RAM dst
OP_LLENA_RAM    equ 4   ; escribe len veces el valor b en RAM dst
OP_LLENA_VRAM   equ 5   ; escribe len veces el valor b en VRAM dst
OP_IDENT_VRAM   equ 6   ; escribe 0,1,2..255,0,1.. len bytes en VRAM dst (tabla de nombres)
OP_SPRITES_VRAM equ 7   ; 32 atributos de sprite Y=209 X=0 patron=n color=1 en VRAM dst
OP_PAG1_RAM     equ 8   ; pagina 1 a la ranura con RAM
OP_PAG1_CART    equ 9   ; pagina 1 al cartucho
OP_VDP_REG      equ 10  ; registro b del VDP = byte bajo de src
OP_PSG_REG      equ 11  ; registro b del PSG = byte bajo de src
OP_ESPERA       equ 12  ; espera b cuadros (barridos del VDP)
OP_SALTA        equ 13  ; SP = src, jp dst
OP_BANCO_8000   equ 14  ; deja el banco b puesto en la ventana de 0x8000
OP_RANURA_PAG2  equ 15  ; escribe en dst los bits de 0xA8 que ponen la pagina 2 en el cartucho
OP_ROM_RAM_RLE  equ 16  ; banco b: descomprime de ROM src a RAM dst, con la marca en len
OP_ROM_VRAM_RLE equ 17  ; banco b: descomprime de ROM src a VRAM dst, con la marca en len

; El ultimo codigo que existe. El interprete rechaza todo lo que pase de aqui y
; se planta con el borde rojo, asi que esto hay que subirlo al anadir una
; operacion: cuando se anadieron las dos de la musica se quedo sin tocar y el
; cargador se colgaba antes de la primera copia, con el sintoma de que el stub
; arrancaba y no se llegaba a 0x0190.
OP_ULTIMA       equ OP_ROM_VRAM_RLE
