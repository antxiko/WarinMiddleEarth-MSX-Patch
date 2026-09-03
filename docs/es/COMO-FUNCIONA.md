# Cómo funciona

Las cuatro cosas, una a una, con la dirección de cada afirmación.

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
(`0x666D`), que pone el anillo igual y además escribe el `0x8333` en `0x7C43`.

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
**atributo del ZX Spectrum** pegado detrás. Se les ha puesto `0x38` —tinta
negra sobre papel blanco—, el mismo que llevan los tiles del icono aliado, así
que el Ojo tapa el fondo igual que el casco.

**El color del ZX va por celda de 8×8, no por píxel.** Darle tinta roja al Ojo
sería un byte por cuadrante; se ha dejado en negro sobre blanco, como se dibujó.

Lo que **no** se pudo hacer, y por qué, está en [Hallazgos](HALLAZGOS.md).
