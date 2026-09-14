; ==========================================================================
; War in Middle Earth (MSX) - PARCHE de Araubi
; Tercera tanda: QUE EL MAPA NO SE BORRE POR LA DERECHA.
;
; Vive en 0x66E2, el ULTIMO hueco de la zona muerta: el motor del altavoz del
; ZX Spectrum (0x6600-0x6713), que en esta conversion no lo llama nadie. Lo de
; delante ya esta cogido -0x6600 los valores de la ficha, 0x664C el Ojo de
; Sauron, 0x6689 los adjetivos y 0x66A2 los textos-, asi que aqui quedan 50
; bytes y esto ocupa 25. Ese reparto no se cuenta a mano: sale de la tabla de
; tools/parchea.py.
;
; --------------------------------------------------------------------------
; EL FALLO, MEDIDO
;
; Ruben lo conto asi: "segun avanza el juego va desapareciendo el mapa por la
; derecha". Pasa en el mapa grande y en la vista de cerca, y va a mas.
;
; El mapa vive en 0xCC00 POR COLUMNAS -130 de 0x66 bytes, hasta 0xFFCB-, asi
; que la DERECHA del mapa es la COLA del buffer. Y esa cola se pierde en cada
; batalla:
;
;   COMPRIME_EL_MAPA (0x9394) empaqueta los 0x33CC bytes del mapa en parejas
;   cuenta/valor, para dejarle a la batalla el sitio de 0xE800 arriba. Pero la
;   longitud de lo empaquetado esta CLAVADA en el codigo:
;
;       93A4  call EMPAQUETA     ; comprime de 0xCC00 a 0x4000
;       93A7  ld bc,016ech       ; <- y de vuelta SIEMPRE 0x16EC bytes
;       93AC  ldir
;
;   y DESCOMPRIME_EL_MAPA (0x9366) lee esos mismos 0x16ED al salir.
;
; El mapa limpio empaqueta en 0x16EE (5870 B, medido: DE al llegar a 0x93A7).
; O sea que al original ya le sobran DOS bytes, y pierde con ellos la ultima
; pareja: la cola de la ultima columna, que es borde y no se ve. Ese es el
; margen con el que lleva funcionando desde 1988, y no hay mas.
;
; Y el parche mete carga ahi: SIEMBRA_CON_BANDO (0x6655) marca con el BIT 5
; las casillas del enemigo, y el barrido que limpia el mapa (0x7FE8) usa
; mascara 0x7F, o sea que baja el bit 7 y DEJA EL BIT 5 PUESTO PARA SIEMPRE.
; Cada marca parte una tira y suma dos bytes al paquete.
;
; Medido sobre la partida de Ruben (WarInMiddleEarthNivelMordor.omr, 5,6 h):
; las marcas van de 9 a 1382 y TODAS las compresiones se pasan. Lo que sobra
; no se copia, y al volver de la batalla el desempaquetado se queda sin con
; que rehacer el final del mapa: la cola se va a 0x00 -que es terreno "nada"-
; y esas columnas desaparecen. Una batalla, un mordisco: 85 celdas (columnas
; 119-122), 186 (115-122), 289 (112-122), 311 (111-122).
;
; Y con su mapa metido a mano en el emulador (tools/omsx_cabe_el_mapa.tcl),
; su terreno de la primera hora con las 1048 marcas que tenia al final:
;
;     ROM del 10 de septiembre   6562 B empaquetados   pierde 652 celdas,
;                                                      columnas 111-128
;     con esto                   5870 B               pierde lo mismo que
;                                                      el original: nada que
;                                                      se vea
;
; --------------------------------------------------------------------------
; EL ARREGLO
;
; Quitar el bit 5 JUSTO ANTES de empaquetar. Asi el paquete vuelve a medir lo
; que media en la cinta y entra en su presupuesto, y las marcas las vuelve a
; sembrar RECENTRA_EL_MAPA en cuanto se recentra el mapa.
;
; NO vale hacerlo en el barrido de 0x7FEB cambiando la mascara a 0x5F: ese
; barrido corre JUSTO DESPUES de sembrar -medido: entra con bit7=28 y sale con
; bit7=0-, y el Ojo de Sauron vive precisamente de que el bit 5 sobreviva al
; barrido. Con mascara 0x5F el Ojo no se dibujaria nunca.
;
; Y se toca SOLO el bit 5. Los bits 6 y 7 tambien parten tiras, pero el juego
; ya los trae a cero en este punto -medido en las 30 compresiones de la
; partida: bit6=0 bit7=0 en todas-, que es justo la razon de que al original
; le cuadrara la cuenta.
; ==========================================================================

MAPA     equ 0CC00h        ; el mapa descomprimido, 130 columnas de 0x66
LARGO    equ 033CCh        ; 0x33CC = 13260 bytes
SIN_BIT5 equ 0DFh          ; todo menos el bit 5, el que siembra el parche
EMPAQUETA equ 093B3h       ; la rutina de siempre: HL origen, DE destino, BC cuenta

         org 066E2h

; --------------------------------------------------------------------------
; Limpia las marcas del parche y empaqueta.
; Sustituye al `call EMPAQUETA` de 0x93A4, con HL = 0xCC00, DE = 0x4000 y
; BC = 0x33CC tal como los deja COMPRIME_EL_MAPA, que hay que devolverle
; intactos.
; --------------------------------------------------------------------------
LIMPIA_Y_EMPAQUETA:
         push hl
         push de
         push bc
         ld   hl,MAPA
         ld   bc,LARGO
UNA_CASILLA:
         ld   a,(hl)
         and  SIN_BIT5     ; fuera la marca del enemigo, que no se comprime bien
         ld   (hl),a
         inc  hl
         dec  bc           ; el mismo recuento que el barrido de 0x7FF0
         ld   a,b
         or   c
         jr   nz,UNA_CASILLA
         pop  bc
         pop  de
         pop  hl
         jp   EMPAQUETA    ; y su `ret` devuelve a 0x93A7

         end
