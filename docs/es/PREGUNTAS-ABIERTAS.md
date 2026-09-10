# Preguntas abiertas

Lo que no está hecho, lo que no se sabe, y lo que hace falta para cerrarlo.

## Araubi jugó, y encontró el fallo gordo (cerrada)

Esta página empezaba pidiendo que alguien jugara una partida entera, porque el
parche estaba medido instante a instante en el emulador pero nadie se había
sentado a jugarlo. **Araubi lo hizo y mandó la grabación**: a los ocho minutos
las etiquetas de la ficha salían en basura y poco después la máquina se colgaba.

Era del parche: el gancho del Anillo apuntaba un byte antes del principio de su
rutina y colaba un `ld (hl),a` que se comía los separadores de la lista de
nombres, uno por cada ficha pintada. Está contado en
[Hallazgos](HALLAZGOS.md), y arreglado con un byte.

Una partida grabada valió más que todas las comprobaciones automáticas juntas.
Lo que sigue faltando por ver jugando:

- si el número de la ficha **se come alguna letra** en algún tipo de unidad;
- si el plazo del Anillo **baja como debe** al pasar los meses;
- si en alguna pantalla aparece un Ojo **donde no hay nadie**;
- si el mapa repintado se sigue leyendo bien tras una hora de partida, y si
  aparece alguno de los ocho tiles que se han quedado en blanco;
- y si el juego se comporta raro en la batalla, que es la parte que este parche
  no toca pero comparte memoria con lo que sí.

Y una que dejó abierta la grabación: el cuelgue venía después del panel roto y
lo más probable es que fuera su consecuencia —sin separador, la copia de un
nombre no encuentra dónde parar—, pero **eso no está demostrado**. Con la cinta
corregida la partida llega viva a los diez minutos y no se cuelga; una partida
larga de verdad lo cerraría.

## La ficha, en todos los tipos de unidad

Se ha visto en **Gandalf** (Brujo) y en **Frodo** (Hobbit), y en las dos cabe.
Pero las etiquetas de la ficha son de longitud variable —«Es muy Decidido ,» es
larga— y los números van en la columna 20. Falta comprobar los demás tipos.

## Dos unidades enemigas siguen invisibles

El bucle de siembra se salta a propósito las ranuras `0x16` y `0x17`, y las dos
son enemigas. De las diez casillas con enemigos dentro se siembran nueve.

**Lo que no se sabe: por qué.** El juego las trata distinto en más sitios —el
bucle que colorea las casillas de unidad (`0x6AE3`) también las salta, y hay una
rutina, `PON_EL_EJERCITO_16_EN_SU_SITIO` (`0x922C`), dedicada a recolocar la
`0x16`—, así que parece que son algo especial y no un descuido. Hacerlas
visibles sin saber qué son es pedir un problema.

## El plazo sólo se ve abriendo la ficha del portador

Hoy el número sale en la ficha, que es donde el juego dibuja el anillo. Un
contador **siempre en pantalla** pediría enganchar el bucle de partida
(`0x7F57`) y escribir en la pantalla ZX cada cuadro: es código nuevo, con más
riesgo, y sin forma de comprobarlo sin jugar un rato.

El gancho está localizado: `0x733E` da el portador, `0x8333` el valor y `0x7113`
sabe pintar el número.

## El Ojo, en rojo (cerrada)

Estaba aquí pedido y hecho está: al repintar el mapa, el Ojo pasó a **rojo
oscuro** sobre el crema del terreno y el icono aliado a un **escudo azul**.
Antes los dos llevaban el mismo atributo `0x38`, negro sobre blanco, y a
distancia se parecían demasiado. El rojo oscuro es uno de los doce colores que
el atributo del Spectrum sí puede pedir en esta conversión; el rojo vivo, no.

## Ocho tiles se quedan en blanco a propósito

En el repintado, los tiles **85 a 88** y **93 a 96** vienen vacíos, y en la
cinta tenían dibujo. Son exactamente los cuatro cuadrantes de los cuadros `0x16`
y `0x18` de la tabla de dos por dos de `0x77B5`.

**Lo que no se sabe: si alguien los pide.** Buscando quién usa cada índice de esa
tabla aparecieron dueños para el `0x00`-`0x0F` (`PINTA_LO_DE_ENCIMA`, por el
nibble del terreno), el `0x11` y el `0x15` (`PINTA_LA_UNIDAD`) y el `0x13`/`0x14`
(terreno 4). Para el `0x10`, el `0x12`, el `0x16`, el `0x17` y el `0x18` **no se
ha encontrado llamador**, que no es lo mismo que demostrar que están muertos. Si
alguno se pinta en una partida larga, ahí saldría un hueco. Se arregla
repintándolos: son ocho dibujos del lienzo.

## El texto, en todas las pantallas

Las diecinueve cadenas se han leído de la RAM del emulador y se han visto en
pantalla en el cartel del mapa, en la ficha de una unidad con nombre y en la de
una formación sin nombre. Lo que **no** está comprobado:

- los topónimos que se han dejado siguen en inglés o con la grafía de Tolkien
  (`Orthanc`, `Barad-Dur`, `Minas Tirith`...), que era lo pedido;
- `Ga. Hierro` y `Puerta N` son abreviaturas que obliga el ancho del cartel
  (10x1 y 8x1). Nada más largo cabe sin rehacer el cartel;
- y de las razas se han visto `Mago`, `Hombre` y `Hombres`. `Elfo`, `Elfos` y
  las dos casillas de `Mago` se leen bien de la RAM, pero no se ha cazado cada
  una en pantalla.

Los cuatro adjetivos nuevos **sí** se han cazado en pantalla, volcados de la
cinta parcheada: `Firme`, `Virtuoso`, `Valiente` y `Fuerte` en la ficha de
Gandalf y en la de Frodo, con `Aliado a la Comunidad` cerrando las dos.

## Nadie ha jugado una partida desde el cartucho

El [cartucho](EL-CARTUCHO.html) deja la RAM, la VRAM, el VDP y el PSG igual que
la cinta —cotejado byte a byte en cuatro máquinas—, y eso demuestra que el
juego arranca en las mismas condiciones. **No demuestra que se pueda terminar
una partida.** Se ha visto el menú y el mapa; nada más.

Lo que haría falta es lo de siempre: que alguien juegue. Si aparece algo, sería
un cargador que deja bien la RAM y mal alguna otra cosa, y el sitio donde
mirar sería lo que el cotejo **no** compara: los puertos que no son VDP ni PSG,
y el estado de las ranuras a partir del salto.

## El cartucho no tiene música

El juego es mudo en cinta y sigue mudo en cartucho. Pero un cartucho tiene
sitio: la ROM puede crecer a 128 KB sin tocar el cargador, y el gancho por
cuadro que el juego deja vacío está identificado. Lo que falta es el
reproductor y la música, y decidir dónde vive su área de trabajo: la RAM libre
en todas las fases son **unos 2,9 KB**, más **13.824 bytes reclamables** en
`0x094F`-`0x3F4E` (las dos pantallas finales del ZX, que se leen una sola vez).

Es una ampliación, no una duda: no hay nada que averiguar, hay que hacerlo.

## Lo que este parche no toca

- **La batalla.** El tablero se monta encima del código del menú y tiene sus
  propias rutinas de bando; nada de lo de aquí entra ahí.
- **El equilibrio del juego.** No se ha cambiado ni un valor de unidad, ni el
  plazo, ni la corrupción. Sólo se enseña lo que ya había.
- **El sonido.** Sigue mudo. El motor del altavoz que la conversión trajo está,
  ahora, ocupado por este parche en **226 de sus 276 bytes**: 137 de código y 89
  de texto. Quedan 50 libres.
