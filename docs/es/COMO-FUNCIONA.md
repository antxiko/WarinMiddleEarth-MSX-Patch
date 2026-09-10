# Cómo funciona

Las seis cosas, una a una, con la dirección de cada afirmación.

## El mapa de una unidad

El motor lleva **256 ranuras** de unidad, en arrays paralelos de 256 bytes
indexados por el número de unidad:

| dirección | qué guarda |
|---|---|
| `0xB900+n` | columna (X) en el mapa |
| `0xBA00+n` | fila (Y) |
| `0xBD00+n` | tipo, bando y banderas; **bit 4 = lleva el Anillo** |
| `0xC000+n` | nibble bajo *Valioso*, nibble alto *Hábil* |
| `0xC100+n` | nibble bajo *Duro*, nibble alto *Bravo* |
| `0xC200+n` | *Enérgico* (baja al andar) |
| `0xC300+n` | *Decidido* (sube un mes sí y otro también) |

Las tuyas son las ranuras `0x00`-`0x77` salvo la `0x16` y la `0x17`; las del
otro bando son esas dos y de la `0x78` en adelante. El **portador del Anillo**
es la primera ranura con el bit 4 de `0xBD00` puesto: en una partida nueva,
**Frodo, la unidad 0x05**.

Y el mapa vive desde `0xCC00`, **por columnas**: `0x33CC` bytes son 130 columnas
de `0x66`, así que la casilla (x, y) está en `0xCC00 + (x+1)*102 + (y+1)`.

---

## 1 · Las unidades enemigas se ven

En cada casilla del mapa, el **bit 7** significa «aquí hay alguien», y es lo que
hace que el juego dibuje la silueta de 2×2. Ese bit lo pone
`RECENTRA_EL_MAPA` (`0x7FAC`): borra el bit 7 de todo el mapa y lo vuelve a
sembrar unidad a unidad. Pero el bucle para en la 0x78:

```
7FB0  ld c,000h        ; empieza en la unidad 0
7FB2  ...              ; siembra el bit 7 de la casilla de la unidad C
7FCC  set 7,(hl)       ; "aqui hay alguien"
7FCE  inc c
7FCF  ld a,c
7FD0  cp 078h          ; <- se para justo donde empieza el enemigo
7FD2  jr nz,0x7FB2
```

**Un byte en `0x7FD1`**, de `0x78` a `0x00`, y el bucle recorre las 256 ranuras.
`0x7FC7` ya se salta las que están en (0,0), así que las vacías no molestan.
Medido: **136 unidades enemigas sembradas** donde antes cero.

> **Aviso.** El interruptor por opcode de `0x8982`/`0x8993` sobre `0x8AF3` —que
> mete `0xD0` = `ret nc` o `0xD8` = `ret c`— **no** decide esto: es el filtro de
> bando de la batalla. Se comprobó antes de descartarlo.

---

## 2 · Cada apartado enseña su número

La ficha se arma en un búfer de `0x7C17`, 24 columnas por 10 filas, y se pinta
después. En la columna 20 de cada línea hay sitio para tres cifras.

La rutina nueva vive en `0x6600` y la engancha un **trampolín de tres bytes** en
`0x708A`: donde `ARMA_LA_FICHA` hacía `ld hl,0x5FBD` justo antes de pintar,
ahora hace `call 0x6600`. La rutina escribe los seis números y **termina
rehaciendo ese mismo `ld hl,0x5FBD`**, de modo que el render sigue igual.

Los valores salen de `0xC000`-`0xC300` con la unidad que diga el operando de
`0x6EAD`, y las cifras las escribe `ESCRIBE_A_EN_TRES_CIFRAS` (`0x7113`), que es
del propio juego.

---

## 3 · El plazo del Anillo

El reloj (`0x831B`) cuenta tics, días y meses. Al pasar del día 60 al 61:

```
8332  ld a,000h      ; el operando de 0x8333 es la CUENTA ATRAS de meses
8334  dec a          ; 0x7F4F la deja en 255 al empezar la partida
8335  ld (08333h),a  ; un mes menos de plazo
8338  jp z,DERROTA   ; a cero, la pantalla de Sauron
8340  ld hl,0853ah   ; "El Anillo corrompe al que lo usa."
```

Ese operando **es** lo que queda antes de perder, y el juego lo ata al Anillo
con su propio mensaje. Hay más caminos a `DERROTA` —quedarse sin portador,
agotar los usos de `0xC000` en la batalla, entregar el Anillo a una unidad sin
usos—, pero ése es el único que es un **plazo**.

`MARCA_AL_PORTADOR` (`0x6F6E`) mira el bit 4 de `0xBD00` y, si esa unidad lleva
el Anillo, escribe el carácter `0x5F` en `0x7C46`, la última columna de la
segunda fila de la ficha. A su izquierda, `0x7C43`, había tres columnas libres.

Ahora ese `ld a,05fh` + `ld (07c46h),a` es un `call ANILLO_CON_PLAZO`
(`0x666E`), que pone el anillo igual y además escribe el `0x8333` en `0x7C43`.

**Y guarda BC, DE y HL.** Lo que va detrás en la ficha es
`call DESCRIBE_EL_DESTINO` (`0x6F7C`), que se aprovecha del HL que traía de
antes: `0x7C27`, donde lo dejó el `ESCRIBE_A_EN_TRES_CIFRAS` de `0x6F6B`. Sin
guardarlo, la ficha sale escrita en otro sitio, con los nombres de media
Comunidad encima. Probado, y se ve.

---

## 4 · El Ojo de Sauron

El juego elige el dibujo de una casilla mirando **sólo su byte de mapa**:

```
PINTA_LA_UNIDAD (0x7708):   or a          ; sin el bit 7 no hay nada
                            ret p
                            bit 6,a       ; casilla con una orden en marcha -> 0x11
                            ld a,011h
                            jr nz,ESTAMPA
                            ld a,015h     ; si no, el dibujo de siempre
```

O sea que al dibujar **no sabe de qué bando es la unidad**. Hay que metérselo en
el propio byte, y para eso hace falta un bit libre. El **bit 5** lo estaba: cero
usos en las 13.260 casillas.

- `SIEMBRA_CON_BANDO` (`0x664C`) sustituye al `call CELDA_DEL_MAPA` +
  `set 7,(hl)` de `0x7FC9`: pone el bit 7 como siempre y, si la unidad es la
  `0x78` o mayor, también el bit 5.
- `DIBUJO_SEGUN_BANDO` (`0x6658`) sustituye al cuerpo de `PINTA_LA_UNIDAD` desde
  `0x770A` y mira ese bit 5 antes que nada.

El icono son **cuatro tiles nuevos** en los índices 111 a 114 de la tabla de
`0x9E00`, que estaban a cero. Cada tile son nueve bytes: ocho de dibujo y el
**atributo del ZX Spectrum** pegado detrás.

**El color del ZX va por celda de 8×8, no por píxel**, así que el Ojo sólo puede
tener dos colores por cuadrante. Los tiene: se repintó en **rojo oscuro sobre el
crema del mapa** —atributo `0x3A`, y `0x17` en el cuadrante de arriba a la
izquierda, que va al revés—, y el icono aliado pasó a ser un **escudo azul**.
Antes los dos llevaban el mismo `0x38`, negro sobre blanco, y a distancia se
parecían demasiado.

## 5 · El texto termina de traducirse

La conversión de Animagic tradujo el juego a medias: los topónimos del mapa se
quedaron en inglés y tres nombres de raza salen truncados. Cambian diecinueve
cadenas, y **no se mueve un byte**. Lo que lo hace posible es que el juego
guarda su texto de cuatro maneras distintas, y cada una permite una cosa.

**La tabla de sitios, `0x7A5E`.** La recorre `BUSCA_EL_SITIO` (`0x6E50`). Cada
registro es

```
[x][y][2 + ancho*filas][ancho<<4 | filas][texto]
```

sin terminador: el largo sale del tercer byte, que además es lo que hay que
sumar para llegar al registro siguiente. El cuarto byte es el **tamaño del
cartel** que dibuja `VENTANA_DEL_SITIO` (`0x6E2D`), y el texto lo rellena
entero, fila a fila —por eso «Minas Tirith» son doce letras en 6×2 y
«Monte   Gundabad» dieciséis en 8×2, con los espacios puestos a mano—. Un
nombre nuevo tiene que medir **exactamente ancho × filas**:

| dirección | estaba | queda | cabe porque |
|---|---|---|---|
| `0x7B34` | Bywater | **Delagua** | 7×1, siete letras justas |
| `0x7B28` | Buckland | **LosGamos** | 8×1 |
| `0x7B5D` | Far Downs | **Quebradas** | 9×1 |
| `0x7B4B` | Michel Delving | **Cavada Grande** | 7×2: `Cavada ` + `Grande ` |
| `0x7BC7` | Grey  Havens | **Ptos  Grises** | 6×2: `Ptos  ` + `Grises` |
| `0x7AA5` | Rivendell | **Rivendel** | de 9×1 a **8×1**: le sobra una letra |
| `0x7AB2` | Isenmouthe | **Ga. Hierro** | 10×1 |
| `0x7A79` | Morannon | **Puerta N** | 8×1 |
| `0x7B0D` | Dale | **Valle** | de 4×1 a **5×1**, con el byte que le presta Rivendel |
| `0x7B7F` | HelmsDeep | **AbismHelm** | 5×2: `Abism` + `Helm ` |

**Las listas de cadenas pegadas**, cada una con el **bit 7 en su última
letra**. Se llega a la cadena N contando terminadores desde una base
(`SALTA_B_TEXTOS`, `0x6E98`). Hay cuatro: razas en plural (`0x7D06`), en
singular (`0x7D39`), carteles de bando (`0x7D6A`) y adverbios (`0x7D9A`).
**Dentro** de una lista una cadena sí puede cambiar de largo mientras el total
no cambie, y eso es lo que paga las palabras largas. «Hum» → «Hombre» son tres
bytes más y «Elf» → «Elfo» uno más; detrás no hay sitio, porque `0x7D6A` es
una dirección fija del código. Pero «Brujo » → «Mago» son dos bytes menos, y
«Brujo» sale **dos veces en cada lista** (las razas 0 y 7 son dos clases de
mago):

```
singular (0x7D3A, 44 bytes, razas 0..8)
  Brujo 6  Nazgul 6  Hum 3     Elf 3   Enano 5  Orc 3  Hobbit 6  Brujo 6  Gollum 6  = 44
  Mago 4   Nazgul 6  Hombre 6  Elfo 4  Enano 5  Orc 3  Hobbit 6  Mago 4   Gollum 6  = 44

plural (0x7D07, 45 bytes, razas 0..7)
  Brujos 7  Nazgul 6  Hum 3      Elfos 5  Enanos 7  Orcs 4  Hobbits 7  Brujo 6  = 45
  Magos 5   Nazgul 6  Hombres 7  Elfos 5  Enanos 7  Orcs 4  Hobbits 7  Mago 4   = 45
```

«Gollum» cierra las dos listas y no se toca: su último byte **es** la base de la
lista siguiente.

Los tres cambios de raza se pidieron en singular, pero «Brujo» y «Hum» están en
**las dos** tablas: dejar la de plural hubiera dejado el juego diciendo
«Formacion de 005 Hum». Se ha cambiado también, **con la forma plural**
(«Magos», «Hombres»), que es lo que ese sitio pide: sus vecinas son «Enanos»,
«Orcs» y «Hobbits». «Elfos» ya estaba bien. La raza 7 de la tabla de plurales
la escribió el juego en singular («Brujo »), y se respeta: queda «Mago».

**La lista de los 24 nombres propios, `0x6B46`**, separados por `0xB7` y
copiados hasta ese separador (`0x6E23`, `0x6F38`). `Brand III` → **`Bardo III`**,
nueve letras por nueve.

**Y los seis adjetivos de la ficha, que no están en ninguna lista.** A cada uno
lo carga su propio `ld hl` absoluto —`0x704B`, `0x7061`, `0x7006`, `0x6FEF`,
`0x701E` y `0x7035`—, así que, al revés que todo lo anterior, sí pueden crecer:
se mueve la cadena y se cambia el puntero. Cuatro lo hacen:

| puntero | era | es | dónde vive ahora |
|---|---|---|---|
| `0x7006` | Habil | **Firme** | `0x7DE6`, su propio hueco: cinco letras por cinco |
| `0x6FEF` | Valioso | **Virtuoso** | `0x6689`, en el motor de altavoz muerto |
| `0x701E` | Duro | **Valiente** | `0x6692` |
| `0x7035` | Bravo | **Fuerte** | `0x669B` |

Los tres que se mudan ocupan 25 bytes y sus tres punteros otros seis. `Enérgico`
y `Decidido` se quedan como estaban, y también se quedan intactas las tres
cadenas abandonadas de `0x7DF0`-`0x7DFF`: ya no las lee nadie, y hay una prueba
que comprueba que no se tocan.

La **última línea** de la ficha era una plantilla más una palabra de la lista de
`0x7D6A`, y por eso decía `Aliado a la Sociedad`. `Comunidad` tiene una letra
más, así que la lista entera se mudó a `0x66A2` con la frase completa en cada
entrada, y la escritura empieza en la columna 0 (`0x7CEF`) en vez de en la 10.
Así las otras tres se leen exactamente igual que antes.

La fuente decide qué letras hay: `0xC800` lleva 128 caracteres de ocho bytes, y
del `0x21` al `0x7F` están todos dibujados (sólo el `0x20`, el espacio, está en
blanco). Los códigos con el bit 7 puesto no son letras —son dibujos de la tabla
de `0x9E00`—, así que **no hay acentos**, y «Nazgul» sigue sin su circunflejo.

---

## 6 · El mapa, repintado

El mapa se dibuja con **128 tiles de 8 × 8** en `0x9E00`, de nueve bytes cada
uno: ocho de dibujo y un **atributo del ZX Spectrum** detrás.
`tools/lienzos.py` los saca todos a un PNG de 128 × 64 a tamaño real —dieciséis
tiles por fila— y los vuelve a leer; `make parche` compara el lienzo con la
cinta y convierte en entrada cada dibujo que haya cambiado. Han cambiado
**122 de los 128**.

Lo que hay que saber es qué colores se pueden pedir, porque el atributo es del
Spectrum pero **el color es del MSX**:

```
ATRIBUTO_A_COLOR (0x049F):  ld hl,004ceh   ; la tabla sin brillo
                            bit 6,a
                            jr z,+3
                            ld hl,004d6h   ; y la que lo lleva
                            ...            ; tinta -> nibble alto, papel -> bajo
```

Dos tablas de ocho bytes, leídas de la cinta:

| | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| `0x04CE`, sin brillo | 1 | 4 | 6 | 13 | 12 | 7 | 10 | 15 |
| `0x04D6`, con brillo | 1 | 5 | 9 | 13 | 3 | 7 | 11 | 15 |

Dieciséis huecos, **doce colores distintos del MSX**: no hay forma de sacar el
rojo medio (8), el verde medio (2) ni el gris (14). Y sólo cuatro de los ocho
—azul, rojo, verde y amarillo— cambian de verdad con el bit de brillo, así que
la regla del Spectrum de «los dos del mismo brillo» sólo obliga en ésos. La
herramienta sabe todo esto: dibuja el lienzo con los colores del MSX, rechaza
una casilla con tres, y si entra un color imposible coge el más parecido y lo
dice.

**Y un byte más, el del papel.** `UN_CARACTER_NORMAL` (`0x7616`) pinta todos los
caracteres de la fuente con un atributo fijo, el `ld a,078h` de `0x763E`. Su
operando —`0x763F`— pasa de `0x78` a `0x70`: papel 6 con brillo, que la tabla de
`0x04D6` manda al color 11 del MSX, el mismo khaki con el que están pintados los
marcos. Se lleva por delante también los **espacios**, que son los que rellenan
el interior de un cartel, así que la caja sale de khaki entero en vez de dejar
un halo detrás de cada letra. Es global: menú, rótulos, ficha y batalla.

Lo que **no** se pudo hacer, y por qué, está en [Hallazgos](HALLAZGOS.md).
