; El area de trabajo del reproductor, en la RAM libre de 0x5C00 (pagina 1,
; 512 B medidos libres en todas las fases). Sale de PT3-RAM.ASM de
; msx-msxlib, que alli se ensambla en RAM; aqui, como el codigo vive en la
; ROM del cartucho, cada variable es un `equ` a su direccion.

PT3_SETUP        equ 05C00h
PT3_MODADDR      equ 05C01h
PT3_CrPsPtr      equ 05C03h
PT3_SAMPTRS      equ 05C05h
PT3_OrnPtrs      equ 05C07h
PT3_PDSP         equ 05C09h
PT3_CSP          equ 05C0Bh
PT3_PSP          equ 05C0Dh
PT3_PrNote       equ 05C0Fh
PT3_PrSlide      equ 05C10h
PT3_AdInPtA      equ 05C12h
PT3_AdInPtB      equ 05C14h
PT3_AdInPtC      equ 05C16h
PT3_LPosPtr      equ 05C18h
PT3_PatsPtr      equ 05C1Ah
PT3_Delay        equ 05C1Ch
PT3_AddToEn      equ 05C1Dh
PT3_Env_Del      equ 05C1Eh
PT3_ESldAdd      equ 05C1Fh
VARS             equ 05C21h
ChanA            equ 05C21h
ChanB            equ 05C3Eh
ChanC            equ 05C5Bh
DelyCnt          equ 05C78h
CurESld          equ 05C79h
CurEDel          equ 05C7Bh
Ns_Base_AddToNs  equ 05C7Ch
Ns_Base          equ 05C7Ch
AddToNs          equ 05C7Dh
AYREGS           equ 05C7Eh
VT_              equ 05C7Eh
EnvBase          equ 05C8Ch
VAR0END          equ 05C8Eh
