# Preguntas abiertas

Lo que no está hecho, lo que no se sabe, y lo que hace falta para cerrarlo.

## Nadie ha jugado una partida entera

Es lo más importante de esta página. El parche está medido instante a instante
en el emulador, pero **nadie se ha sentado a jugar una partida completa con él
puesto**. Todo lo que sigue son cosas que sólo se ven jugando.

Si lo juegas, lo que interesa saber:

- si el número de la ficha **se come alguna letra** en algún tipo de unidad;
- si el plazo del Anillo **baja como debe** al pasar los meses;
- si en alguna pantalla aparece un Ojo **donde no hay nadie**;
- y si el juego se comporta raro en la batalla, que es la parte que este parche
  no toca pero comparte memoria con lo que sí.

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

## El Ojo, en rojo

El atributo de los cuatro tiles es `0x38` —tinta negra sobre papel blanco—, el
mismo que el del icono aliado. Ponerlo en **tinta roja** sería un byte por
cuadrante, cuatro en total.

No se ha hecho porque el color del ZX va por celda de 8×8 y habría que ver en
pantalla si el rojo sobre el tramado del mapa se lee bien o ensucia. Es una
prueba, no un problema.

## El texto, en todas las pantallas

Las quince cadenas se han leído de la RAM del emulador y se han visto en
pantalla en el cartel del mapa, en la ficha de una unidad con nombre y en la de
una formación sin nombre. Lo que **no** está comprobado:

- los topónimos que se han dejado siguen en inglés o con la grafía de Tolkien
  (`Orthanc`, `Barad-Dur`, `Minas Tirith`...), que era lo pedido;
- `Ga. Hierro` y `Puerta N` son abreviaturas que obliga el ancho del cartel
  (10x1 y 8x1). Nada más largo cabe sin rehacer el cartel;
- y de las razas se han visto `Mago`, `Hombre` y `Hombres`. `Elfo`, `Elfos` y
  las dos casillas de `Mago` se leen bien de la RAM, pero no se ha cazado cada
  una en pantalla.

## Lo que este parche no toca

- **La batalla.** El tablero se monta encima del código del menú y tiene sus
  propias rutinas de bando; nada de lo de aquí entra ahí.
- **El equilibrio del juego.** No se ha cambiado ni un valor de unidad, ni el
  plazo, ni la corrupción. Sólo se enseña lo que ya había.
- **El sonido.** Sigue mudo. El motor del altavoz que la conversión trajo está,
  ahora, medio ocupado por este parche.
