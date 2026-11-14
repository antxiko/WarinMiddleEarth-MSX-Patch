; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: EL REPRODUCTOR DE LAS TRES
; CANCIONES (haz_rom.py --canciones)
;
; Como musica.asm, en el hueco del ultimo banco y ensamblado en MUSICA_ORG,
; pero aqui va SOLO el reproductor y su tabla de canciones: las tres canciones
; de Ruben (niebla, taberna y batalla) y sus instrumentos van a la RAM de la
; pagina 0 (canciones.asm), comprimidos en la ROM con ZX0, porque en el hueco
; no caben enteros detras de las tres pantallas nuevas.
;
; Las direcciones que el reproductor necesita de alli -TABLA_PAUTAS,
; TABLA_SONIDOS, DATOS_NOTAS y las tres canciones- las pasa tools/haz_rom.py
; leidas del .sym de canciones.asm, que se ensambla antes.
; ==========================================================================

                include "wyz_trabajo.inc"

                org MUSICA_ORG

MUSICA_PRINCIPIO:
                include "wyz_player.asm"
MUSICA_REPRODUCTOR_FIN:

; WYZ_CARGA_CANCION busca aqui la numero A: el puente se la pide por numero.
TABLA_SONG:     defw CANCION_0, CANCION_1, CANCION_2

; El puente se ensambla con un MODULO, que aqui no hay: es la primera.
MODULO          equ CANCION_0
MODULO_FIN:

MUSICA_FIN:
