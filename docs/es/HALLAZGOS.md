# Hallazgos

Lo que apareció al hacer el parche, incluido lo que salió mal.

## El bit 5 del byte de mapa estaba libre

Cada casilla del mapa es un byte: el nibble bajo es el terreno, el **bit 7** es
«aquí hay alguien» y el **bit 6** es «casilla con una orden en marcha». Del bit
5 no se sabía nada, así que se contó sobre las **13.260 casillas** de una
partida recién empezada:

    bit 0: 1340   bit 4:   10
    bit 1: 6683   bit 5:    0   <- libre
    bit 2: 1957   bit 6:    0
    bit 3: 2148   bit 7:   28

Cero usos. Ahí cabe la marca de bando sin quitarle nada al juego. El bit 6
también sale a cero en ese instante, pero **ese tiene dueño**: lo usa
`PINTA_LA_UNIDAD` para el dibujo de «orden en marcha».

## Los huecos a cero de una tabla no son huecos libres

La tabla de cuadros de dos por dos de `0x77B5` tiene seis entradas enteramente a
cero —`0x00`, `0x01`, `0x03`, `0x04`, `0x05` y `0x06`— y parecían sitio de
sobra para el icono nuevo.

**No lo eran.** `PINTA_LO_DE_ENCIMA` (`0x7714`) elige entrada con un
`and 00fh` sobre el nibble bajo del terreno, así que los índices `0x00`-`0x0F`
ya tienen dueño aunque estén vacíos: un cero en esa tabla no significa «libre»,
significa **«esta casilla no dibuja nada encima»**.

Poner el Ojo en el hueco `0x03` se lo puso a las **447 casillas de terreno de
tipo 3** del mapa. Se vio a la primera pasada y se tiró.

La salida fue no usar índice: apuntar HL a una lista propia de cuatro códigos y
entrar en `ESTAMPA_DOS_POR_DOS` **pasada su aritmética**, en `0x7720`, que es
justo donde esa rutina hace su primer `ld a,(hl)`. El estampado sigue siendo el
del juego; sólo la lista es nuestra.

## Dos unidades enemigas no se pueden hacer visibles

El bucle de siembra se salta **a propósito** las ranuras `0x16` y `0x17`:

```
7FB2  ld a,c
7FB3  cp 016h      ; la 0x16 no se marca
7FB5  jr z,L_7FCE
7FB7  cp 017h      ; la 0x17 tampoco
7FB9  jr z,L_7FCE
```

Y las dos son del bando enemigo. Al empezar la partida hay **diez casillas** con
enemigos dentro y el parche siembra **nueve**: la (111,64), donde sólo está la
`0x16`, sigue sin dibujarse. La `0x17` sí sale, pero porque comparte casilla
—la (65,54)— con otras treinta y seis.

Por qué el juego las aparta es una [pregunta abierta](PREGUNTAS-ABIERTAS.md).

## La petición del Anillo estaba mal leída

La primera versión de este trabajo dio por bueno que «la corrupción **es** el
contador `0xC300` del portador». Es verdad que ese contador sube un punto al mes
—lo hace `SUMA_UN_MES_A_LOS_CONTADORES` (`0x834A`), a los 256 a la vez—, pero
**no es lo que mata**: nadie más lo lee con un umbral.

Lo que mata es la **cuenta atrás de meses** del operando de `0x8333`, que
empieza en 255, baja uno cada mes y a cero salta a `DERROTA`. Y el mensaje que
el juego saca ese mismo mes es *«El Anillo corrompe al que lo usa.»*, así que es
él quien ata las dos cosas.

Buscar quién *escribe* una variable no basta: hay que ver **quién decide con
ella**.

## El juego es mudo, y su silencio es el sitio del parche

La conversión trajo el motor del altavoz del Spectrum entero, en `0x6600`, con
cinco efectos de veintiún bytes detrás. **No lo llama nadie**: ni una
instrucción de los cinco listados apunta ahí, y los cuatro sitios que piden un
efecto llaman a `0x65FF`, que es un `ret` pelado. Del PSG del MSX sólo se
escriben los registros 7 y 14, los dos para leer el joystick.

Los 137 bytes de código nuevo de este parche viven ahí dentro.

## Al escribir en la ficha hay que guardar los registros

`ANILLO_CON_PLAZO` llama a `ESCRIBE_A_EN_TRES_CIFRAS`, que deja HL tres bytes
más allá. Lo que va detrás en la ficha, `DESCRIBE_EL_DESTINO` (`0x6F7C`), **se
aprovecha del HL que traía de antes**. Sin guardarlo, la ficha sale escrita en
otro sitio: con los nombres de media Comunidad encima.

No es una suposición: se probó sin guardar y la ficha salió rota.

## Un byte de menos en un `call`, y el panel se deshacía a los ocho minutos

Araubi jugó una partida entera y mandó la grabación. A partir del **minuto
ocho** las etiquetas de la ficha salían en basura —los números y `Destino:`
seguían bien— y poco después la máquina se colgaba.

Los textos en RAM **no estaban tocados**: 1.536 bytes comparados contra la
cinta, cero diferencias. Lo que se rompía era el **separador**. Los 24 nombres
propios de `0x6B46` van pegados con un `0xB7` en medio, y las rutinas que los
copian leen hasta ese byte. Comparando la RAM en dos instantes:

    t=430   todos los separadores en su sitio
    t=470   uno convertido en 0x10
    t=500   quedaban 6 de los 25 bytes 0xB7 de 0x6B45..0x6BFA

Uno menos por cada ficha que se pintaba. Un punto de observación de escritura
sobre la tabla lo cazó a la primera:

    t=471,686   escribe 10 en 6B75   PC=666D  HL=6B75  A=10
    t=474,471   escribe 10 en 6B7B   PC=666D  HL=6B7B  A=10
    ...dieciocho veces hasta t=492,173

`0x666D` es de este parche. Y es un byte antes de donde tenía que ser:
`ANILLO_CON_PLAZO` empieza en **`0x666E`** —lo dice el fichero de símbolos que
saca pasmo—. En `0x666D` está el `0x77` con que acaba el `jp 07717h` de la
línea de arriba, y ese byte suelto se lee como **`ld (hl),a`**.

O sea que cada vez que se pintaba la ficha del portador, antes de entrar en la
rutina se ejecutaba un `ld (hl),a` de propina, con el HL y el A que traía
`MARCA_AL_PORTADOR`: `HL` en la tabla de nombres y `A` valiendo `0x10`. El
parche se comía sus propios separadores, uno a uno, hasta que la copia de un
nombre ya no encontraba dónde parar.

El arreglo es **un byte**: `cd 6d 66` → `cd 6e 66`. Medido sobre la misma
grabación, con la cinta corregida y reproduciendo desde el principio: la rutina
se llama **29 veces** en el tramo donde antes se rompía, hay **cero** escrituras
en la tabla de nombres, los separadores siguen enteros y la ficha se lee bien a
los diez minutos.

Lo que dolió es que **había un test para esto** y daba verde: comprobaba que el
gancho apuntaba a `base + 33` bytes, contados a mano igual de mal que en el
parche. Ahora las direcciones las saca del fichero de símbolos del ensamblador,
que es el único que sabe de verdad dónde empieza cada rutina.


## El lienzo mentía: el atributo es del ZX, el color es del MSX

Los tiles salían al PNG pintados con los colores del **ZX Spectrum**, que es lo
que dice el atributo pegado detrás de cada uno. En pantalla no se ven así nunca.
Esta conversión no manda el atributo al VDP: lo traduce antes
`ATRIBUTO_A_COLOR` (`0x049F`) con dos tablas de ocho colores —`0x04CE` sin
brillo y `0x04D6` con él— y lo que sale es un byte de color del **MSX**. El
lienzo enseñaba el gris del ZX donde el juego pone blanco.

De ahí salen dos cosas, y las dos cambian lo que se puede dibujar:

- **Sólo se pueden pedir doce de los quince colores del MSX.** Los dieciséis
  huecos de las dos tablas guardan doce valores distintos. No hay atributo que
  dé el rojo medio, el verde medio ni el gris. Medido sobre el repintado que
  llegó: **349 píxeles de rojo medio en 16 tiles**, 47 de verde medio en 4, y 3
  de gris en uno. Cada uno se cambia ahora por el alcanzable más parecido, y la
  herramienta dice cuál era, cuántos píxeles y en qué se ha convertido.
- **La regla de «los dos del mismo brillo» aprieta menos de lo que parecía.**
  Sólo cuatro de los ocho colores cambian entre las dos tablas: azul, rojo, verde
  y amarillo. El negro, el magenta, el cian y el blanco dan el mismo color del
  MSX con brillo y sin él, así que no obligan a nada. La comprobación rechazaba
  casillas que se podían dibujar perfectamente.

La lección no es de este juego: **un lienzo que enseña colores distintos de los
que va a enseñar la máquina es un lienzo que miente**, y la forma de
comprobarlo es dibujarlo con la traducción del propio juego, no con la paleta de
la máquina de la que se convirtió.
