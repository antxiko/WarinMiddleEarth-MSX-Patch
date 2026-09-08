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
