; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LA MUSICA
;
; Este es el bloque que va en el hueco libre del final del banco 3 de la ROM.
; Ese banco se asoma por la ventana de 0x8000 del mapper ASCII16, asi que todo
; lo de aqui se ensambla en
;
;       0x8000 + (donde empieza el hueco - 0xC000)
;
; que hoy son 2264 bytes desde 0xF728, o sea 0xB728. Ese numero NO se escribe
; aqui a mano: lo calcula tools/haz_rom.py de la disposicion real de la ROM y
; lo pasa como MUSICA_ORG, para que no pueda quedarse viejo si lo que va
; delante cambia de tamano.
;
; y solo se ve mientras la pagina 2 este conmutada a la ranura del cartucho.
; El juego corre con las cuatro paginas en RAM -el bloque alto vive en 0x88B8,
; dentro de esa misma pagina-, de modo que la ROM se asoma UNICAMENTE durante
; la interrupcion: el puente de 0x003B la pone, llama aqui y la devuelve.
;
; Dentro van dos cosas:
;
;   - el reproductor PT3, que es `libext/pt3/PT3-ROM.ASM` de msx-msxlib
;     (Bulba / Dioniso / msxKun / SapphiRe), traducido de la sintaxis de asMSX
;     a la de pasmo por tools/convierte_pt3.py. Su area de trabajo -382 bytes-
;     no esta aqui sino en la RAM libre de 0x5C00: ver pt3_trabajo.inc.
;
;   - el modulo .pt3, SIN sus 100 primeros bytes, que son la cabecera de texto
;     con el titulo y el autor. Por eso a PT3_INIT se le pasa MODULO-100, que
;     es lo mismo que hace msx-msxlib cuando compila con CFG_PT3_HEADERLESS.
;
; El fichero del modulo lo deja tools/haz_rom.py en el directorio de trabajo
; como `modulo.bin`, ya recortado, y lo pasa por -I. La musica NO va en el
; repositorio: es del autor que se elija y se acredita aparte.
; ==========================================================================

                include "pt3_trabajo.inc"

                org MUSICA_ORG

; --------------------------------------------------------------------------
; El reproductor. Deja publicas PT3_INIT, PT3_PLAY, PT3_ROUT y PT3_MUTE, que
; son las cuatro que llama el puente; sus direcciones salen del .sym.
; --------------------------------------------------------------------------
MUSICA_PRINCIPIO:
                include "pt3_player.asm"
MUSICA_REPRODUCTOR_FIN:

; --------------------------------------------------------------------------
; El modulo, ya sin cabecera.
; --------------------------------------------------------------------------
MODULO:
                incbin "modulo.bin"
MODULO_FIN:

MUSICA_FIN:
