; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: LAS TRES CANCIONES DE RUBEN
;
; Lo que el cargador descomprime en la RAM de la pagina 0 (CANCIONES_ORG, al
; final de la zona que liberaron las pantallas finales) y el reproductor lee
; desde la interrupcion: las tres canciones tal cual salen del tracker -el
; primer byte de cada una es el tempo y el reproductor lo quiere- y, detras,
; los instrumentos, los efectos de ritmo y la tabla de notas, que son UNOS para
; las tres (medieval.mus.asm, traducido a pasmo por tools/convierte_wyz.py).
;
;   0  niebla   el menu
;   1  taberna  la partida: el mapa general y la vista de cerca
;   2  batalla  la batalla
; ==========================================================================

                org CANCIONES_ORG

CANCION_0:      incbin "niebla.mus"
CANCION_1:      incbin "taberna.mus"
CANCION_2:      incbin "batalla.mus"
                include "cancion.asm"
CANCIONES_FIN:
