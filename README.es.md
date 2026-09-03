# War in Middle Earth (MSX) — el parche de Araubi

> ## Jugable, y sin terminar
>
> Todo lo de aqui abajo esta hecho y medido en openMSX, pero **nadie ha jugado
> una partida entera con el parche puesto**. Lo que se sabe que falta esta al
> final. Leelo antes de juzgar una captura.

Un parche de bytes para la cinta MSX de **War in Middle Earth** (Melbourne House
/ Dro Soft, 1989), montado encima del
[desensamblado comentado](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly).
Hace las tres cosas que **Araubi** pidio en el foro: hacer visibles las unidades
enemigas, ensenar el valor numerico de cada apartado de una unidad, y sacar a la
luz cuanto le queda al portador del Anillo. Y una cuarta: las enemigas llevan
ahora icono propio, para poder distinguir los dos bandos.

[README in English](README.md) · Investigacion completa: [INVESTIGACION.md](INVESTIGACION.md)

## La cinta no esta aqui

No se distribuye ninguna imagen de cinta, solo el trabajo del parche (ver
[AVISO-LEGAL.md](AVISO-LEGAL.md)). Pones tu propia `war.tsx` (sha256
`13c63632…b1d81208`) y:

    make extract     # saca los cuerpos de los bloques de tu cinta a work/
    make parche      # aplica la tabla y escribe war_parche.tsx
    make test        # las comprobaciones

`war_parche.tsx` es la cinta parcheada, del mismo tamano que la original, lista
para un MSX1 real (`openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx`).

## Que cambia

Todo cae en el bloque medio del juego (el que corre desde `0x5E00`) mas cuatro
tiles del bloque alto: **197 bytes en siete cambios**. Cada uno comprueba antes
de escribir que los bytes originales son los que espera; nada se desplaza, y
`make parche` avisa si cambia un solo byte fuera de la tabla (`tools/parchea.py`).

**1 · Las unidades enemigas se ven.** El mapa guarda un bit de "aqui hay
alguien" por casilla, y `RECENTRA_EL_MAPA` (0x7FAC) lo vuelve a sembrar unidad a
unidad; pero su bucle **para en la unidad 0x78**, justo donde empieza el bando
enemigo, asi que las enemigas no se siembran y no se dibujan. Cambiando el tope
de `0x78` a `0x00` -**un byte, en 0x7FD1**- recorre las 256. Comprobado: **136
unidades enemigas se siembran donde antes se sembraban cero.**

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/mapa_con_parche.png) |

**2 · Cada apartado ensena su numero.** La ficha de una unidad lista seis
cualidades -Valioso, Habil, Duro, Bravo, Energico y Decidido- como adverbio mas
adjetivo ("es muy bravo"), nunca como cifra. Una rutina nueva
(`MUESTRA_LOS_VALORES`, 76 bytes), escrita encima del **motor del altavoz del ZX
Spectrum de 0x6600, que en esta conversion no llama nadie**, lee los seis
valores (de `0xC000`/`0xC100`/`0xC200`/`0xC300`) y los escribe en cifras. La
engancha un trampolin de tres bytes en `0x708A`. Comprobado contra los valores
reales: coinciden los seis.

**3 · El plazo del portador, al lado del anillo.** El reloj del juego cuenta
tics, dias y meses; cada mes baja uno el operando de **0x8333** -que 0x7F4F deja
en 255 al empezar-, saca el mensaje *"El Anillo corrompe al que lo usa"* y hace
`jp z,DERROTA`. Ese operando es, literalmente, lo que te queda, y el juego no lo
ensena en ningun sitio. `MARCA_AL_PORTADOR` dibuja el anillo en 0x7C46, la
ultima columna de la segunda fila de la ficha; las tres columnas de su izquierda
estaban libres, y ahi va ahora el numero.

![](docs/imagenes/plazo_del_anillo.png)

**4 · Las enemigas llevan el Ojo de Sauron.** Con el cambio 1 las enemigas
salian... con **tu** casco, que es media solucion. La rutina que dibuja solo
mira el byte del mapa, asi que no puede saber de que bando es una unidad; pero
**el bit 5 de ese byte estaba libre** (medido: cero usos en las 13.260 casillas).
Ahi va ahora la marca de "esta es del otro bando", y el icono son cuatro tiles
nuevos al final de la tabla de 0x9E00 (los 111 a 114, que estaban a cero).

| las enemigas con tu casco | las enemigas con el Ojo |
|---|---|
| ![](docs/imagenes/enemigas_con_casco.png) | ![](docs/imagenes/ojo_de_sauron.png) |

Ninguna de estas imagenes es una captura de pantalla: el juego resube la
pantalla al VDP sin parar, asi que dos fotos del *mismo* estado separadas tres
segundos ya salen con el 37 % de los pixels distintos. Estan dibujadas desde el
bufer de pantalla del ZX que el juego lleva en RAM, volcado en un instante fijo.
Las direcciones, las medidas y la salida de openMSX estan en
[INVESTIGACION.md](INVESTIGACION.md).

## Lo que falta

- **Nadie ha jugado una partida entera** con el parche puesto.
- La ficha se ha visto en el jefe de una formacion (Gandalf) y en el portador
  (Frodo); **no se han comprobado todos los tipos de unidad** por si el numero
  choca con una etiqueta larga.
- **El plazo solo se ve abriendo la ficha del portador.** Un contador siempre en
  pantalla pide enganchar el bucle de partida (0x7F57) y escribir cada cuadro:
  codigo nuevo y mas riesgo, asi que queda como ampliacion.
- **Las unidades 0x16 y 0x17 siguen invisibles.** El bucle de siembra las salta
  a proposito (`cp 016h` / `cp 017h` en 0x7FB3) y no se ha averiguado por que.
  De las diez casillas con enemigos dentro se siembran nueve; en la decima solo
  esta la 0x16.

## Licencia

Las herramientas y la investigacion se publican bajo [LICENSE](LICENSE). **El
juego no**, y la cinta no se distribuye aqui — ver [AVISO-LEGAL.md](AVISO-LEGAL.md).
