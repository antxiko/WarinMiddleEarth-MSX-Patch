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
ahora icono propio, para poder distinguir los dos bandos. Y una quinta: **los
nombres del mapa y los de las razas terminan de traducirse al castellano**.

[README in English](README.md) · Investigacion completa: [INVESTIGACION.md](INVESTIGACION.md)

## La cinta no esta aqui

No se distribuye ninguna imagen de cinta, solo el trabajo del parche (ver
[AVISO-LEGAL.md](AVISO-LEGAL.md)). Pones tu propia `war.tsx` (sha256
`13c63632…b1d81208`) y:

    make extract     # saca los cuerpos de los bloques de tu cinta a work/
    make parche      # aplica la tabla y escribe war_parche.tsx
    make test        # las comprobaciones
    make rom         # war.rom, el juego como cartucho (tampoco se distribuye)
    make rom_parche  # war_parche.rom, el cartucho con el parche

`war_parche.tsx` es la cinta parcheada, del mismo tamano que la original, lista
para un MSX1 real (`openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx`).

## Que cambia

Cae en el bloque medio del juego (el que corre desde `0x5E00`) y en la tabla de
tiles del mapa del bloque alto: **1.578 bytes en 195 entradas de la tabla**. De
ellas, **29 estan escritas a mano** -568 bytes de codigo, punteros y texto- y
**166 salen solas de los lienzos**, 1.010 bytes de dibujos repintados. Cada una
comprueba antes de escribir que los bytes originales son los que espera; nada se
desplaza, y `make parche` avisa si cambia un solo byte fuera de la tabla
(`tools/parchea.py`).

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

**5 · El texto termina de traducirse.** La conversion de Animagic dejo los
toponimos del mapa en ingles y varios nombres de raza truncados. Cambian trece
entradas: diez sitios del mapa (`Bywater` -> `Delagua`, `Michel Delving` ->
`Cavada Grande`, `Dale` -> `Valle`...), las razas (`Brujo` -> `Mago`, `Elf` ->
`Elfo`, `Hum` -> `Hombre`, `Orc` -> `Orco` y `Orcs` -> `Orcos`), los cuatro
adjetivos de la ficha (`Habil` -> `Firme`, `Valioso` -> `Virtuoso`, `Duro` ->
`Valiente`, `Bravo` -> `Fuerte`) y su ultima linea (`Aliado a la Sociedad` ->
`Aliado a la Comunidad`).

Los nombres de los personajes **no se tocan**: `Brand III` -el nieto de Bardo el
Arquero, rey de Valle- se llama igual en las dos lenguas, y hubo un parche que
lo traducia por error.

Y no se mueve un byte. El registro de un sitio lleva **el tamano de su cartel**
(`ancho<<4 | filas`) y el texto lo rellena entero, asi que el nombre nuevo tiene
que medir lo mismo: `Cavada ` + `Grande ` llena el cartel de 7x2 donde iba
`Michel `/`Delving`. Los nombres de raza viven en dos listas que se recorren
contando bits de fin, asi que **dentro** de una lista una cadena si puede cambiar
de largo: eso es lo que paga las palabras mas largas. `Brujo ` -> `Mago` libera
dos bytes, y sale dos veces en cada lista: los cuatro justos que necesitan
`Elf` -> `Elfo` y `Hum` -> `Hombre`. El byte de `Orcos` sale del espacio de
relleno que ya traia `Enanos `, y el de `Orco` de la entrada que era de Gollum,
que desde el cambio 7 no la lee nadie.

La misma casilla y la misma unidad, con la cinta original y con la parcheada:

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/textos_sin_parche.png) | ![](docs/imagenes/textos_con_parche.png) |

El cartel de dos filas, que era el que podia romperse, lleva
`Cavada `/`Grande ` en la misma caja de 7x2:

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/cartel_sin_parche.png) | ![](docs/imagenes/cartel_con_parche.png) |

**6 · El mapa, repintado.** Los 128 tiles de 8x8 del mapa se sacan a un PNG a
tamano real, se repintan con cualquier editor y se vuelven a leer: **122 de los
128** entran solos en el parche, como 103 entradas del grupo `graficos`. Y con
ellos salio que **el lienzo mentia**: el tile lleva un atributo del ZX, pero
`ATRIBUTO_A_COLOR` (`0x049F`) lo traduce a un color del MSX antes de pintarlo,
con dos tablas de ocho, asi que solo se pueden pedir **doce de los quince
colores** del MSX. El texto va ahora sobre el khaki de los marcos, que es un byte
en `0x763F`.

| los tiles de la cinta | repintados |
|---|---|
| ![](docs/imagenes/tiles-del-mapa.png) | ![](docs/imagenes/tiles-repintados.png) |

**7 · Gollum es un hobbit.** La raza de cada unidad es el nibble bajo de
`0xBD00+n`, y Gollum -la unidad 21- tenia el tipo 8, que era suyo y de nadie mas
(medido: la unica de las 256). Y con el 8 no era solo el nombre: en la batalla
`0x8CF7` saca del tipo la figura, la vida y el golpe, y `0x8D0E` manda dibujar el
tipo 8 **como el 4**, asi que Gollum salia con la figura del enano. Con el 6 es
un hobbit en todo -nombre, figura, fuerza y costes de terreno-, igual que Sam,
Merry y Pippin. **Un byte.**

**8 · Dos heroes mas: Tom Bombadil y Radagast.** Solo en el cartucho, y por una
razon medida: las 256 ranuras de unidad estan TODAS ocupadas y la lista de los
24 nombres (`0x6B46`) ocupa **181 bytes clavados**, con la red de caminos
empezando en `0x6BFB` justo detras. No cabe ni un byte, asi que la lista se
**muda entera** a la RAM libre que lleva el cartucho -cinco punteros y dos topes
por numero de unidad- y crece a 26 nombres. En la cinta eso no se puede hacer:
no hay RAM de fiar donde ponerla, y el IPS solo escribe donde la cinta carga.

Las dos ranuras salen de la **0x18 y la 0x19**, dos pelotones de enanos
plantados los dos en (22,12); **sus 39 hombres se reparten** entre las cuatro
formaciones de (23,15), asi que no se pierde ni un soldado. Bombadil ocupa el
**tipo 8** -el que dejo libre Gollum al pasar a hobbit, y que aqui se rebautiza
**"Eterno"**- y vive en el Bosque Viejo, en (50,28), al este de Los Gamos;
Radagast es del **tipo 0** (Mago), el de Gandalf, y vive en Rhosgobel, en
(83,30), entre el Anduin y el Bosque Negro. Los seis valores de Radagast van
**dos puntos por debajo de los de Gandalf**. Lo unico que no pueden es llevar el
Anillo: el menu de entrega corta la lista antes de Gollum.

El byte que le falta a "Eterno" en cada una de las dos tablas de raza sale de la
**entrada 7**, que es texto muerto: el tipo 7 son Sauron y Saruman y los dos
tienen nombre, asi que su raza no la lee nadie. El total de cada tabla no se
mueve, que es lo unico que no puede cambiar. Ojo: la raza solo se ve en la ficha
de una unidad SIN nombre, asi que "Eterno" no llega a salir en pantalla -lo
mismo que le pasa a Gollum con "Hobbit"-, y en la batalla el tipo 8 se sigue
dibujando con la figura del enano, porque no tiene una propia (`0x8D0E`).

Ninguna de estas imagenes es una captura de pantalla: el juego resube la
pantalla al VDP sin parar, asi que dos fotos del *mismo* estado separadas tres
segundos ya salen con el 37 % de los pixels distintos. Estan dibujadas desde el
bufer de pantalla del ZX que el juego lleva en RAM, volcado en un instante fijo.
Las direcciones, las medidas y la salida de openMSX estan en
[INVESTIGACION.md](INVESTIGACION.md).

## De cinta a cartucho

El juego no se toca: `make rom` monta de tu cinta **`war.rom`, una MegaROM
ASCII16 de 64 KB** con un cargador de 77 bytes y un stub de 1.105 que dejan la RAM
exactamente como la deja el cargador de la cinta y saltan al mismo sitio
(0x0190). Con la cinta parcheada, `make rom_parche` saca `war_parche.rom`.
Tampoco se distribuyen. El juego solo escribe el registro 7 del VDP y hereda
todo lo demas del `SCREEN 2` del BASIC, asi que el cartucho reproduce lo medido
en la cinta; y como la pagina 1 es la ROM mientras se carga, los 14.400 bytes
del bloque medio que caen ahi pasan por la VRAM. Comprobado byte a byte -RAM,
VRAM, VDP y PSG- en cuatro maquinas (`make verifica_rom`,
`make verifica_rom_parche`): todo igual que la cinta. Detalle en
[INVESTIGACION.md](INVESTIGACION.md).

El cartucho **usa ZX0**, de Einar Saukas, para las imagenes: 26.112 bytes de
pantallas en 12.600. Su licencia pide que se diga, y queda dicho aqui y en
[AVISO-LEGAL.md](AVISO-LEGAL.md); el compresor no se distribuye.

Y **la vista de cerca va por tabla de nombres, con el cursor como sprite y la
ventana quieta**: en vez de expandir la pantalla de caracteres a bitmap y
subir 12.288 bytes a la VRAM en cada vuelta, sube los 768 de la tabla de
nombres, porque el byte de cada celda ya es el indice de patron; y el trozo de
mapa solo se repinta cuando el cursor -dos sprites de 16x16, editables en
`src/cartucho/cursor.png` con `tools/editor_sprites.html`, que se abre en el
navegador y ensena el dibujo sobre la pantalla de verdad- se mueve: el cursor se queda en el centro y lo que se mueve es el
mapa, como en el original. Medido en un NMS 8250: de 3,2 a 43,2 vueltas por
segundo en reposo, con el cursor a cinco casillas por segundo y la imagen
cotejada contra la de antes (`make verifica_vista_parche`). Una cosa que la
vuelta rapida rompio y esta arreglada: en el menu que pasa de una unidad a
otra de la misma casilla, arriba y abajo van por toque, no mientras se
mantiene la tecla. Y otra que se vio despues: **el cursor de la batalla** se
corre una casilla por vuelta del bucle, asi que al subir al VDP solo lo que
cambia se volvio ingobernable; ahora va al reloj y no al bucle, una casilla cada
dieciseis cuadros. Medido en una batalla de verdad: **3,00 casillas por segundo
con el limite y 4,00 sin el**, con el bucle a 7 vueltas por segundo -que sin
limite son 7 casillas-.

Los **sprites se editan** con `tools/editor_sprites.html`, que se abre en el
navegador y los ensena sobre un trozo de la pantalla donde viven: el guante del
mapa era amarillo y negro sobre un mapa amarillo y negro -no se veia- y va ahora
en azul, y los tres cursores dejaron de ser un bloque opaco de 16x16 para
quedarse en el trazo y su borde, con el terreno viendose alrededor.

Y **el mapa general ya no se dibuja: se descomprime**. Recorrer sus 23.500
casillas estampando pixeles costaba 3,9 segundos, y se pagaban cada vez que se
volvia de la vista de cerca. Pero ese dibujo no cambia nunca -depende solo del
nibble bajo del byte de mapa, y las unidades son atributos, no pixeles-, asi
que el cartucho lo lleva ya dibujado, comprimido con ZX0 (6.144 bytes en
3.034), y lo descomprime en su sitio: **de 3,9 a 0,7 segundos**. Lo dibuja
`tools/mapa_general.py`, que transcribe las rutinas del juego y se coteja byte
a byte con el emulador; que el terreno no cambia mientras se juega esta medido
sobre la partida grabada de Araubi (`make verifica_terreno`), no supuesto. De
paso, ese cotejo destapo una errata del juego de 1988: un `inc b` pisa el flag
que elige el dibujo del terreno, y por eso uno de los cinco dibujos de 8x8 no
se usa nunca.

Y **el guante del mapa es un sprite de verdad**. Era un sprite por software
estampado en el lienzo, con sus 24 bytes de fondo guardados y un recuadro de
4x3 celdas subido a la VRAM en cada vuelta; ahora son dos sprites de hardware,
editables en `src/cartucho/guante.png`. La vuelta del bucle de partida pasa de
51,9 a 59,5 por segundo, y lo que se ve es identico pixel a pixel
(`make verifica_mapa`).

Y **el panel File/Memo/Time toma el color de la vista**. En la cinta parcheada
el texto de la vista de cerca va en amarillo claro y el panel del mapa se
quedaba en blanco; ahora los dos son el mismo. No es un byte sino cuatro,
porque el atributo del panel es como el juego lo reconoce -para saber si el
disparo cae ahi y para respetarlo al limpiar- y porque ese amarillo era el de
la marca de unidad: los dos atributos se intercambian, asi que las unidades
pasan a blanco y se ven mucho mejor sobre el amarillo del mapa.

La ROM que se juega es `war_unificada.rom` (`make rom_unificada`): la cinta
parcheada con todo. Detalle en [INVESTIGACION.md](INVESTIGACION.md).

## Lo que falta

- **Nadie ha jugado una partida entera** con el mapa repintado. Araubi si jugo una con la version de septiembre, y de ahi salio el fallo gordo.
- **El cartucho solo se ha visto arrancar** (el menu y el mapa); nadie ha jugado
  una partida entera desde el.
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
