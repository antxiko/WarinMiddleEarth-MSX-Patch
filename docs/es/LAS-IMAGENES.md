# Las imágenes

Ninguna de las imágenes de esta web es una captura de pantalla, y **no puede
serlo**. Esta página cuenta por qué y qué se hace en su lugar, porque el método
vale para cualquier juego que se comporte igual.

## El problema: la pantalla nunca está quieta

La primera pareja «sin parche / con parche» que se hizo salió con el **33 % de
los píxeles distintos**, y eso para un cambio que sólo añade tres siluetas. Antes
de dar por bueno ese número hacía falta un control, y el control lo tumbó:

| medida | píxeles distintos |
|---|---|
| dos pasadas del **mismo** estado, foto contra foto | **0,0 %** |
| dos fotos del mismo estado separadas **3 s** | **37 %** |
| sin parche contra con parche | 33 % |

O sea: la emulación es determinista —dos pasadas idénticas dan la misma foto al
píxel—, pero **el juego resube la pantalla al VDP sin parar** y la captura pilla
el volcado a medias. Comparar fotos, aquí, no demuestra nada.

## La salida: el búfer del Spectrum

Esta conversión no dibuja en la VRAM del MSX: dibuja en **una pantalla de ZX
Spectrum montada en RAM**, en las mismas direcciones que tendría un Spectrum, y
la sube entera de vez en cuando.

- `0x4000`-`0x57FF`: los 6.144 bytes de bitmap, con el enredo del Spectrum
  (tercio, línea de píxel, fila de celda).
- `0x5800`-`0x5AFF`: los 768 atributos, uno por celda de 8×8.
- `PANTALLA_A_VRAM` (`0x05BD`) los sube desenredando el orden, y
  `ATRIBUTOS_A_VRAM` (`0x0604`) traduce cada atributo del ZX al byte de color
  del MSX con **la tabla de `0x0200`**, que el propio juego rellena al arrancar.

Así que lo que se vuelca es ese búfer, en un instante fijo, y lo dibuja
`tools/render_zx.py` **con la tabla de color del cartucho**, no con una paleta
inventada.

## Que el búfer sí está quieto, medido

Dos volcados del mismo estado separados **quince segundos emulados**:

    32 bytes distintos de 6.912

y los 32 son las columnas 14 y 15, filas de píxel 81 a 88: **el parpadeo del
cursor**. Todo lo demás, idéntico.

## Cómo se hace una pareja

`tools/omsx_zx.tcl` parte de un estado guardado en el menú, escribe la posición
del cursor, fuerza un disparo —que es lo que dispara `RECENTRA_EL_MAPA`— y
vuelca el búfer. Se corre dos veces, una con la cinta original y otra con la
parcheada, **con los mismos parámetros**, y se dibujan los dos volcados.

Con eso, lo que cambia entre las dos imágenes lo cambia el parche.

## Tres trampas del emulador que salieron por el camino

**Un `return` dentro del cuerpo de un breakpoint de openMSX lo mata**, y en
silencio: deja de saltar y nadie protesta. Y **dos breakpoints en la misma
dirección** tampoco valen: el segundo no se registra, el primero sigue
funcionando, y parece que ese código no se ejecuta.

**No se le puede escribir una variable del juego «para sólo mirar».** Para ver
la ficha de otra unidad de la casilla se intentó escribirle el selector
`0x6EAD` desde el depurador, de tres formas distintas, y las tres acabaron con
el juego actuando sobre esa unidad y montando otra pantalla encima del código
parcheado. Se nota porque los bytes del parche dejan de estar donde se
pusieron —por eso el volcado los relee y los deja apuntados en el log—.

Lo que sí funciona es **darle al juego la entrada que le daría el jugador**: un
punto de ruptura donde lee el mando, y forzar ahí el bit de la tecla. El camino
está en el propio listado: disparo sobre la casilla (`0x7229`) para entrar en
`ELIGE_ENTRE_LAS_DE_LA_CASILLA`, y luego «siguiente» (`0x775B`) hasta llegar a
la unidad que se quiere ver.

## Las herramientas

| herramienta | qué hace |
|---|---|
| `tools/omsx_zx.tcl` | vuelca el búfer ZX, la tabla de color y el mapa |
| `tools/render_zx.py` | lo dibuja a PNG con los colores del cartucho |
| `tools/omsx_mapa.tcl` | vuelca sólo el mapa de `0xCC00`, para contar casillas |
| `tools/omsx_censo.tcl` | vuelca las 256 ranuras de unidad al empezar |
| `tools/render_icono.py` | dibuja un cuadro de 2×2 de la tabla de `0x77B5` |
| `tools/icono_a_tiles.py` | pasa un PNG de 16×16 a los cuatro tiles de 9 bytes |
| `tools/lienzos.py` | saca los tiles, los sprites y la fuente a tres PNG editables a tamaño real, y los vuelve a meter |
| `tools/previo_repinta.py` | repinta una pantalla ya volcada, casilla a casilla, con los tiles del lienzo |
| `tools/cuerpo_parcheado.py` | el cuerpo de un bloque con el parche aplicado, para dibujar las láminas del «después» |
| `tools/render_mapa_completo.py` | el mapa entero en un PNG, sacado de la cinta |

## El mapa entero, en una sola imagen

El juego no te enseña nunca más de dieciséis casillas por trece. El mapa es de
**128 × 100**, y a los dos caracteres por casilla con que se dibuja son 2048 ×
1600 píxeles: cabe en un PNG.

**No es un mosaico de pantallazos.** El mapa se dibuja repitiendo lo que hace el
motor del propio juego, leído del desensamblado:
`DIBUJA_EL_TROZO_DE_MAPA` (`0x7643`) da **tres pasadas** sobre las casillas
—el terreno, lo que va encima y las unidades— y la del terreno mira a los
vecinos: `VECINOS_IGUALES` (`0x7366`) devuelve un bit por cada vecino del
terreno que se le pregunte, y `ELIGE_EL_DIBUJO` (`0x73CA`) recorre una tabla de
entradas `[umbral][dos bytes de máscara][índices…]` para estampar un **cuadro de
4 × 4 caracteres** alrededor de la casilla. Por eso las tres pasadas van
enteras, una detrás de otra: el dibujo de una casilla se mete en las de al lado.

El formato de esas tablas estaba **sin resolver** en el desensamblado, donde el
bloque de datos de `0x77A0` dice «formato pendiente». Sacar la imagen del mapa es
lo que lo ha cerrado.

**Y el mapa sale de la cinta**, así que nada de esto necesita el emulador: está
comprimido en `0xCC00`, `0x16ED` bytes de **parejas cuenta/valor** —la cuenta
primero, y un cero cuenta 256, que es como se comporta el `djnz`— que
`DESCOMPRIME_EL_MAPA` (`0x9366`) desempaqueta en `0x33CD` bytes nada más
arrancar.

Dos comprobaciones, las dos medidas:

- el mapa descomprimido de la cinta contra un volcado de `0xCC00` sacado del
  emulador en marcha: **19 bytes distintos de 13.260**, y los diecinueve son el
  bit 7 —las unidades que el juego siembra al empezar la partida—;
- la misma ventana de dieciséis por trece que estaba enseñando el juego,
  dibujada aquí y comparada contra el volcado de la pantalla de verdad: **52 de
  las 768 celdas de carácter cambian**, y esas 52 son el panel de «Posición» que
  el juego pinta encima del mapa y esta herramienta no dibuja.

## Ver un repintado antes de tocar la cinta

Repintar 128 tiles y enterarse después de que el mapa no se lee es una forma cara
de trabajar. `tools/previo_repinta.py` se la salta: coge una pantalla ya volcada
del juego, **identifica cada una de sus 768 casillas** contra los tiles y la
fuente de la cinta —los ocho bytes del dibujo, y los dos colores que daría su
atributo— y la vuelve a dibujar con los tiles del lienzo. Lo que no identifica lo
deja como está y lo cuenta, para no inventarse nada. En las cuatro pantallas que
se usaron aquí, **768 de 768 casillas identificadas** en cada una.

Además acepta el atributo de la fuente como argumento, que es como se miró el
papel khaki antes de gastar un byte en él.

Y luego se comprobó contra lo de verdad. La misma pantalla, volcada de la cinta
parcheada corriendo en el emulador, contra el previo:

    0 píxeles distintos de 196.608

El previo no es una ilustración: es lo que la máquina acaba dibujando.
