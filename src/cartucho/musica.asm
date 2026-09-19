; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LA MUSICA
;
; Este es el bloque que va en el hueco libre del final del banco 3 de la ROM.
; Ese banco se asoma por la ventana de 0x8000 del mapper ASCII16, asi que todo
; lo de aqui se ensambla en
;
;       0x8000 + (donde empieza el hueco - 0xC000)
;
; Ese numero NO se escribe aqui a mano: lo calcula tools/haz_rom.py de la
; disposicion real de la ROM y lo pasa como MUSICA_ORG, para que no pueda
; quedarse viejo si lo que va delante cambia de tamano.
;
; y solo se ve mientras la pagina 2 este conmutada a la ranura del cartucho.
; El juego corre con las cuatro paginas en RAM -el bloque alto vive en 0x88B8,
; dentro de esa misma pagina-, de modo que la ROM se asoma UNICAMENTE durante
; la interrupcion: el puente de 0x003B la pone, llama aqui y la devuelve.
;
; Dentro van dos cosas:
;
;   - el reproductor, que es el WYZ PSG proPLAYER v0.47d de Wyz, tal como lo
;     trae msx-msxlib en `libext/wyzplayer047d/` ya partido en dos: el codigo
;     en `wyzplayer-ROM.tniasm.asm` y sus variables en `wyzplayer-RAM...`.
;     Esa particion es la que permite que el reproductor viva en la ROM de un
;     cartucho. tools/convierte_wyz.py lo traduce de tniASM a pasmo y saca de
;     paso el `wyz_trabajo.inc` con las variables, que aqui no ocupan sitio:
;     son 233 bytes de la RAM libre de 0x5C00.
;
;   - la cancion, que son DOS ficheros y no uno: el `.mus` con las notas, tal
;     cual, y su `.mus.asm` con los instrumentos, los efectos de ritmo y la
;     tabla de frecuencias de las notas. Los dos los deja tools/haz_rom.py en
;     el directorio de trabajo como `cancion.bin` y `cancion.asm`.
;
; Ni el reproductor ni la cancion van en el repositorio: son de sus autores y
; se acreditan aparte. Aqui viaja lo que los enchufa, que es esto.
; ==========================================================================

                include "wyz_trabajo.inc"

                org MUSICA_ORG

; --------------------------------------------------------------------------
; El reproductor. Deja publicas las cuatro rutinas que llama el puente:
; WYZ_PLAYER_INIT, WYZ_CARGA_CANCION_HL, WYZ_REPRODUCE_FRAME y WYZ_PLAYER_OFF.
; Sus direcciones salen del .sym, no de aqui.
; --------------------------------------------------------------------------
MUSICA_PRINCIPIO:
                include "wyz_player.asm"
MUSICA_REPRODUCTOR_FIN:

; --------------------------------------------------------------------------
; La tabla de canciones. El reproductor trae dos maneras de arrancar una:
; WYZ_CARGA_CANCION, que busca la numero A en esta tabla, y
; WYZ_CARGA_CANCION_HL, que se la come de HL. El puente usa la segunda -aqui
; solo hay una cancion-, pero la tabla se queda porque la primera sigue
; estando en el binario y la nombra.
; --------------------------------------------------------------------------
TABLA_SONG:     defw MODULO

; --------------------------------------------------------------------------
; La cancion: las notas y, detras, sus instrumentos y la tabla de frecuencias.
; Va entera, sin quitarle nada: el primer byte del .mus es el tempo y el
; reproductor lo quiere.
; --------------------------------------------------------------------------
MODULO:         incbin "cancion.bin"
MODULO_FIN:
                include "cancion.asm"

MUSICA_FIN:
