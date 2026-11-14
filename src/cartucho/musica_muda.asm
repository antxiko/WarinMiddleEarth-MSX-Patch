; LA MUSICA, QUITADA (2026-11-14, a peticion del autor): en vez del reproductor WYZ y
; su cancion van cuatro `ret` con los mismos nombres, sin modulo. El puente
; (puente.asm) se queda TAL CUAL, porque ademas de la musica cuenta los cuadros con
; los que la vista de cerca mueve el cursor: sigue el mismo camino -arranca al
; encender, "suena" en el menu y al pulsar 0 pasa a solo contar cuadros-, pero cada
; llamada al reproductor vuelve sin hacer nada y el PSG se queda como lo dejo el
; arranque (R7 = 0x3F: mudo). Lo monta `haz_rom.py --musica muda`.
                org MUSICA_ORG
MUSICA_PRINCIPIO:
WYZ_PLAYER_INIT:
WYZ_CARGA_CANCION_HL:
WYZ_REPRODUCE_FRAME:
WYZ_PLAYER_OFF:
                ret
MUSICA_REPRODUCTOR_FIN:
TABLA_SONG:     defw MODULO
MODULO:
MODULO_FIN:
MUSICA_FIN:
