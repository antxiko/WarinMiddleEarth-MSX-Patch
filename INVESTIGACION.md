# War in Middle Earth (MSX) — el parche de Araubi

Araubi, en el foro, pidio tres cosas:

> Lo que mas interesante me parece seria poder hacer visibles a las unidades
> enemigas con algun parche, y un medidor de resistencia al anillo, mas poder
> ver los valores en cada apartado de las unidades.

Este repositorio sale del clon del desensamblado
(`antxiko/WarinMiddleEarth-MSX-disassembly`) y hereda sus herramientas. El
parche no toca los listados: parte de los cuerpos que `make extract` saca de la
cinta (`work/*.raw`), les aplica la tabla de `tools/parchea.py` y vuelve a
montar la cinta (`war_parche.tsx`). Cada cambio comprueba primero que los bytes
originales son los que espera; nada se desplaza (cada parche mide igual antes y
despues) y `make parche` avisa si algo cambia fuera de la tabla.

Todas las direcciones son de EJECUCION del bloque medio del juego (0x5E00, el
que corre desde 0x5E00) y estan tomadas del listado del desensamblado, no
supuestas. Las medidas en openMSX son sobre una Philips VG-8020 cargando la
cinta parcheada.

## Las imagenes de este documento NO son capturas de pantalla

Y no pueden serlo: el juego resube la pantalla al VDP sin parar, asi que **dos
fotos del MISMO estado separadas tres segundos ya salen con el 37 % de los
pixels distintos**. Comparar capturas, aqui, no demuestra nada.

Lo que se dibuja es el **bufer de pantalla del ZX Spectrum que el juego lleva en
RAM** -6.144 bytes de bitmap desde 0x4000 y 768 atributos desde 0x5800-, volcado
en un instante fijo y pintado despues con los colores que el propio cartucho le
asigna a cada atributo, su tabla de 0x0200. Ese bufer si esta quieto: dos
volcados separados quince segundos emulados salen iguales salvo 32 bytes, que
son el parpadeo del cursor.

Y el control que hacia falta: **dos pasadas del mismo estado dan una imagen
identica al pixel**, asi que lo que cambia entre "sin" y "con" lo cambia el
parche y nada mas. Vuelca `tools/omsx_zx.tcl`, dibuja `tools/render_zx.py`.

## El mapa de una unidad

El motor lleva **256 ranuras** de unidad, en arrays paralelos de 256 bytes
indexados por el numero de unidad (documentado en el desensamblado):

| direccion | que guarda |
|-----------|------------|
| `0xB900+n` | columna (X) en el mapa |
| `0xBA00+n` | fila (Y) en el mapa |
| `0xBB00+n`, `0xBC00+n` | el destino |
| `0xBD00+n` | tipo (nibble bajo), **bando (dos bits altos)** y banderas; **bit 4 = lleva el Anillo** |
| `0xC000+n` | nibble bajo = *Valioso*, nibble alto = *Habil* |
| `0xC100+n` | nibble bajo = *Duro*, nibble alto = *Bravo* |
| `0xC200+n` | *Energico* (byte entero; baja al andar) |
| `0xC300+n` | *Decidido* (byte entero; sube un mes si y otro tambien) |
| `0xC600+n` | estado · `0xC700+n` | pasos que quedan |

Las **tuyas** son las ranuras 0x00-0x77 salvo la 0x16 y la 0x17; las del
**otro bando** son la 0x16, la 0x17 y de la **0x78 en adelante** (`0x74EE
BUSCA_UNA_TUYA`, `0x7508 SIGUIENTE_DEL_ENEMIGO`). El **portador del Anillo** es
la primera ranura con el bit 4 de `0xBD00` puesto (`0x733E BUSCA_AL_PORTADOR`);
en una partida nueva es **Frodo, la unidad 0x05**.

---

## 1) Unidades enemigas visibles — HECHO y VERIFICADO

### Como esta hoy
El mapa vive en RAM desde `0xCC00`; en cada casilla, el **bit 7** del byte de
mapa significa "aqui hay alguien" y es lo que hace que `0x7708 PINTA_LA_UNIDAD`
dibuje la silueta de 2x2. Ese bit lo pone `RECENTRA_EL_MAPA` (0x7FAC): borra el
bit 7 de todo el mapa (`0x7FED`) y lo vuelve a sembrar unidad a unidad con el
bucle de `0x7FB2`. **Pero el bucle para en la unidad 0x78:**

```
0x7FB0  ld c,000h        ; empieza en la unidad 0
0x7FB2  ...              ; siembra el bit 7 de la casilla de la unidad C
0x7FCC  set 7,(hl)       ; "aqui hay alguien"
0x7FCE  inc c
0x7FCF  ld a,c
0x7FD0  cp 078h          ; <-- se para en 0x78
0x7FD2  jr nz,0x7FB2
```

Como las enemigas son de la 0x78 para arriba, **nunca se siembran, y por eso no
se dibujan**. Esa es la niebla de guerra del juego.

> **Aviso.** El interruptor por opcode de `0x8982`/`0x8993` sobre `0x8AF3` (mete
> `0xD0`=`ret nc` o `0xD8`=`ret c`) **no** decide la visibilidad del mapa: es el
> filtro de bando de `0x8AF1 SI_ES_ENEMIGO_LO_APUNTA`, que en la BATALLA busca
> un enemigo pegado en diagonal para atacarlo. Se comprobo antes de descartarlo.

### El cambio
Un solo byte: el tope del bucle, `0x78` -> `0x00`, en **0x7FD1**. Con `cp 000h`
el bucle recorre las 256 ranuras (0x00-0xFF) y siembra tambien las enemigas.
`0x7FC7` ya se salta las que estan en (0,0), asi que las ranuras vacias no
molestan.

### Verificado (openMSX, `tools/omsx_verifica.tcl`)
Arrancada una partida y forzado un disparo sobre el mapa (que dispara
`RECENTRA_EL_MAPA`), instrumentando `0x7FCC`:

```
sembradas en la ultima pasada = 254  (amigas<0x78 = 118, enemigas>=0x78 = 136)  indice maximo = 255
unidades enemigas (0x78-0xFF) con coordenadas en el mapa = 136
```

**136 unidades enemigas se siembran** donde antes se sembraban cero.

La misma casilla (036N/096E), sin el parche y con el:

| sin parche | con el primer parche |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/enemigas_con_casco.png) |

Tres huestes de Sauron estan ahi mismo y no se dibujaba ninguna; con el parche
aparecen las tres siluetas, que son 34 unidades enemigas. Contado sobre el mapa
en RAM: **de 19 casillas con unidad se pasa a 28**, y en la pantalla cambian
**doce celdas de caracter**, o sea tres dibujos de dos por dos y nada mas.

Esa medida de doce celdas es de aquella pareja, la del primer parche, y por eso
se conserva aqui: aisla el cambio de la siembra y nada mas. Contra la cinta de
hoy no se puede medir asi, porque el mapa viene repintado entero -735 de las 768
celdas y 560 atributos cambian- y la cuenta ya no separaria una cosa de la otra.

| sin parche | la cinta de hoy |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/mapa_con_parche.png) |

### El limite: dos enemigas se quedan fuera

El bucle se salta **a proposito** las unidades 0x16 y 0x17 (`cp 016h` y
`cp 017h` en 0x7FB3), y eso el parche no lo toca. Al empezar la partida hay
**diez casillas** con enemigos dentro y el parche siembra **nueve**: la
(111,64), donde solo esta la 0x16, sigue sin dibujarse. La 0x17 si sale, pero
porque comparte casilla -la (65,54)- con otras treinta y seis.

---

## 2) Los valores de cada apartado de la unidad — HECHO y VERIFICADO

### Como esta hoy
Al mirar una unidad, `0x6F0B FICHA_DE_LA_UNIDAD` arma su ficha en el buffer
`0x7C17` (24 columnas x 10 filas) y la pinta. `0x6FDC LAS_SEIS_CUALIDADES`
escribe seis apartados, cada uno como **adverbio + adjetivo** ("Muy Valioso",
"Es algo Bravo"...), eligiendo el adverbio por tramos con `0x6E88`. El numero
que hay debajo **no se ve**:

| apartado | fuente | rango |
|----------|--------|-------|
| Valioso  | `0xC000+n` nibble bajo | 0-15 |
| Habil    | `0xC000+n` nibble alto | 0-15 |
| Duro     | `0xC100+n` nibble bajo | 0-15 |
| Bravo    | `0xC100+n` nibble alto | 0-15 |
| Energico | `0xC200+n` byte | 0-255 |
| Decidido | `0xC300+n` byte | 0-255 |

### El cambio
El juego ya trae `0x7113 ESCRIBE_A_EN_TRES_CIFRAS` (A -> tres digitos en (HL)).
El parche anade una rutina, **`MUESTRA_LOS_VALORES`** (`src/parche/ficha_valores.asm`,
76 bytes), que lee los seis valores de la unidad de la ficha y los escribe en
cifras en la **columna 20** de cada fila del buffer. Vive en **0x6600**, encima
del **motor del altavoz del ZX Spectrum, que en esta conversion no lo llama
nadie** (los efectos acaban en el `ret` de 0x65FF): zona muerta reutilizable.

La engancha un **trampolin** en `0x708A`: donde `ARMA_LA_FICHA` hacia
`ld hl,0x5FBD` justo antes de pintar, ahora hace `call 0x6600`; la rutina
escribe los numeros y termina rehaciendo ese `ld hl,0x5FBD`, de modo que el
render sigue igual.

### Verificado (openMSX, `tools/omsx_ficha.tcl`)
Forzando la ficha de Frodo (unidad 0x05) y comparando los digitos escritos con
los valores reales:

```
valores reales de la unidad 0x05:
  Valioso=10  Habil=7  Duro=7  Bravo=2  Energico=126  Decidido/Anillo=176
Energico -> digitos en la ficha: '126'  (esperado 126)
Decidido -> digitos en la ficha: '176'  (esperado 176)
Habil    -> digitos en la ficha: '007'  (esperado 007)
Valioso  -> digitos en la ficha: '010'  (esperado 010)
Duro     -> digitos en la ficha: '007'  (esperado 007)
Bravo    -> digitos en la ficha: '002'  (esperado 002)
```

Los seis coinciden. Por el camino normal del juego (cursor sobre una unidad) la
ficha sale con sus numeros: `docs/imagenes/ficha_con_valores.png` (Gandalf,
"Energico 198, Muy Decidido 192, Es algo Bravo 006"...).

---

## 3) El plazo del Anillo — HECHO y VERIFICADO

### Lo que se entendio mal la primera vez

La primera version de este documento decia que "la corrupcion **es** el contador
0xC300 del portador, y con el parche 2 ya se ve". Es verdad que 0xC300 sube un
punto al mes, pero **no es lo que mata**, y no era lo que se pedia. Lo que se
pedia es ver **cuanto le queda al portador antes de sucumbir**.

### Lo que dice el binario

El reloj del juego (0x831B) cuenta tics, dias y meses. Al pasar del dia 60 al 61:

```
8332  ld a,000h      ; el operando de 0x8333 es la CUENTA ATRAS de meses
8334  dec a          ; 0x7F4F la deja en 255 al empezar la partida
8335  ld (08333h),a  ; un mes menos de plazo
8338  jp z,DERROTA   ; a cero, la pantalla de Sauron
833b  ...
8340  ld hl,0853ah   ; y el mensaje de ese mes: "El Anillo corrompe al que lo usa."
```

O sea: **el operando de 0x8333 es, literalmente, los meses que quedan antes de
perder la partida**, y el juego lo ata al Anillo con su propio mensaje. Empieza
en 255 y no se ensena en ningun sitio.

Hay mas caminos a `DERROTA` -quedarse sin portador, agotar los usos de 0xC000 en
la batalla, entregar el Anillo a una unidad sin usos-, pero ese es el unico que
es un **plazo**.

### El cambio

`MARCA_AL_PORTADOR` (0x6F6E) mira el bit 4 de 0xBD00 y, si esa unidad lleva el
Anillo, escribe el caracter 0x5F -el anillo- en **0x7C46**, la ultima columna de
la segunda fila de la ficha. A su izquierda, 0x7C43, hay tres columnas libres:
justo tres cifras.

Donde el juego hacia `ld a,05fh` + `ld (07c46h),a`, ahora llama a
**ANILLO_CON_PLAZO (0x666E)**, que pone el anillo igual y ademas escribe el
0x8333 en 0x7C43 con `ESCRIBE_A_EN_TRES_CIFRAS` (0x7113), la misma rutina que la
ficha ya usaba dos lineas antes.

**Y guarda BC, DE y HL.** Lo que va detras en la ficha es
`call DESCRIBE_EL_DESTINO` (0x6F7C), que se aprovecha del HL que traia de antes
-0x7C27, donde lo dejo el `ESCRIBE_A_EN_TRES_CIFRAS` de 0x6F6B-. Llamar a esa
misma rutina aqui sin guardarlo deja la ficha escrita en otro sitio: sale con
los nombres de media Comunidad encima. Probado, y se ve.

### Verificado (openMSX)

La ficha de **Frodo**, el portador, con el parche:

![](docs/imagenes/plazo_del_anillo.png)

```
Frodo
Hobbit                255o     <- el plazo, pegado al anillo
Destino: Rivendell
  Es algo Energico,     126
  Es muy Decidido ,     176
  ...
```

`0x8333` en RAM vale 255 en ese instante, y 255 es lo que sale escrito. Sin
parche, esa misma ficha (`docs/imagenes/ficha_frodo_sin_parche.png`) solo dice
"Es muy Decidido," y el anillo, sin numero ninguno.

Solo aparece en la ficha del portador, que es donde el juego dibuja el anillo.

---

## 4) El Ojo de Sauron para las enemigas — HECHO y VERIFICADO

Con el parche 1 las enemigas ya salian... **con el casco de las tuyas**, que es
media solucion: las ves, pero no sabes cuales son. El icono nuevo -el Ojo de
Sauron, 16x16 en blanco y negro- lo dibujo Antxiko, y aqui esta metido en el
cartucho.

### Por que no era inmediato

El juego elige el dibujo de una casilla mirando **solo el byte del mapa**:

```
PINTA_LA_UNIDAD (0x7708):   or a          ; sin el bit 7 no hay nada
                            ret p
                            bit 6,a       ; casilla con una orden en marcha -> 0x11
                            ld a,011h
                            jr nz,ESTAMPA
                            ld a,015h     ; si no, el dibujo de siempre
```

Al dibujar no sabe de que bando es la unidad. Hay que metrselo en el propio byte
de mapa, y para eso hace falta un bit libre.

### Los tres huecos que si estaban libres

- **El bit 5 del byte de mapa.** Medido sobre las 13.260 casillas: **cero usos**.
  (El bit 6 lo usa el juego para "casilla con una orden en marcha" y el 7 es
  "aqui hay alguien".)
- **Los tiles 111 a 127 de la tabla de 0x9E00**, que estan a cero. Cada tile son
  nueve bytes: ocho de dibujo y el atributo del ZX detras. Se usan cuatro.
- **La zona muerta de 0x664C**, detras de la rutina de los valores: mas motor de
  altavoz que no llama nadie.

### El hueco que NO estaba libre, aunque lo pareciera

La tabla de cuadros de dos por dos de **0x77B5** tiene seis entradas a cero
(0x00, 0x01, 0x03, 0x04, 0x05 y 0x06) y parecen sitio de sobra. **No lo son:**
`PINTA_LO_DE_ENCIMA` (0x7714) elige entrada con un `and 00fh` sobre el nibble
bajo del terreno, asi que los indices 0x00-0x0F ya tienen dueno. Poner el Ojo en
el hueco 0x03 se lo puso a las **447 casillas de terreno de tipo 3**. Se probo,
se vio, y se tiro.

La salida: no usar indice. `DIBUJO_SEGUN_BANDO` pone HL en una lista propia de
cuatro codigos y entra en `ESTAMPA_DOS_POR_DOS` **pasada su aritmetica**, en
0x7720, que es justo donde esa rutina hace el primer `ld a,(hl)`.

### El cambio

| donde | que |
|---|---|
| 0x7FC9 | `call CELDA_DEL_MAPA` + `set 7,(hl)` pasa a ser `call SIEMBRA_CON_BANDO` |
| 0x770A | el cuerpo de `PINTA_LA_UNIDAD` pasa a ser `jp DIBUJO_SEGUN_BANDO` |
| 0x664C | las tres rutinas nuevas, 61 bytes (`src/parche/icono_enemigo.asm`) |
| 0xA1E7 | los cuatro tiles del Ojo, 36 bytes, en los indices 111 a 114 |

`SIEMBRA_CON_BANDO` pone el bit 7 como siempre y, si la unidad es la 0x78 o
mayor, tambien el bit 5. `DIBUJO_SEGUN_BANDO` mira ese bit 5 antes que nada.

### Verificado (openMSX)

| el primer parche: enemigas con casco | ahora: el Ojo de Sauron |
|---|---|
| ![](docs/imagenes/enemigas_con_casco.png) | ![](docs/imagenes/ojo_de_sauron.png) |

- **nueve casillas** llevan el bit 5, y son las nueve que tienen enemigos
  dentro; **cero** casillas amigas lo llevan;
- en la pantalla cambian **doce celdas de caracter** -las tres huestes- y **cero
  atributos de color**: el Ojo tapaba el fondo igual que el casco, con la misma
  tinta negra sobre papel blanco (asi era entonces; al repintar el mapa cada uno
  se llevo su color, y por eso los dos dibujos de mas abajo ya no son estos);
- los dos aliados de la esquina siguen con su casco.

El icono, ampliado y releido de la cinta ya parcheada:

| la unidad aliada (tiles 81-84) | la enemiga (tiles 111-114) |
|---|---|
| ![](docs/imagenes/icono_aliado.png) | ![](docs/imagenes/icono_ojo_de_sauron.png) |

**El color del ZX va por celda de 8x8, no por pixel**, asi que el Ojo solo puede
tener dos colores por cuadrante. Al repintar el mapa se le dieron: **rojo oscuro
sobre el crema del terreno** -atributo 0x3A, y 0x17 en el cuadrante de arriba a
la izquierda, que va al reves-, y el icono aliado paso a ser un **escudo azul**.
Antes los dos llevaban el mismo 0x38, negro sobre blanco, y a distancia se
parecian demasiado. Las dos imagenes de arriba son ya las de la cinta de hoy.

---

## 5) Los textos en espanol — HECHO y VERIFICADO

La conversion de Animagic tradujo el juego a medias: los **toponimos del mapa**
se quedaron en ingles y **tres nombres de raza** salen truncados. Aqui van los
diecinueve cambios, con los nombres de la traduccion de Tolkien al castellano.

### Los cuatro formatos de texto del juego

Esto es lo que decide que se puede cambiar y que no. Ninguna cadena puede
cambiar el numero de bytes que ocupa (el parche no desplaza nada), pero cada
formato aprieta de una manera distinta:

**a) La tabla de SITIOS, 0x7A5E.** La recorre `BUSCA_EL_SITIO` (0x6E50). Cada
registro es

```
[x][y][2 + ancho*filas][ancho<<4 | filas][texto]
```

sin terminador: el largo sale del tercer byte, que ademas es lo que hay que
sumar para llegar al registro siguiente. El cuarto byte es el **tamano del
cartel** que dibuja `VENTANA_DEL_SITIO` (0x6E2D), y el texto lo rellena entero,
fila a fila. Por eso "Minas Tirith" son doce letras en 6x2 y "Monte   Gundabad"
dieciseis en 8x2, con los espacios puestos a mano. Un toponimo nuevo tiene que
medir **exactamente ancho x filas**.

**b) Las LISTAS de cadenas pegadas**, con el **bit 7 en la ultima letra**. Se
llega a la cadena numero N contando terminadores desde la base
(`SALTA_B_TEXTOS`, 0x6E98). Hay cuatro: razas en plural (0x7D06), razas en
singular (0x7D39), carteles de bando (0x7D6A) y adverbios (0x7D9A). Dentro de
una lista **las cadenas si pueden cambiar de largo**, mientras el total no
cambie: es lo que permite pagar "Hombre" con lo que sobra de "Brujo". El total
es intocable porque la base de la lista siguiente es una direccion fija del
codigo.

**c) La lista de los 24 NOMBRES propios, 0x6B46**, separados por `0xB7` y
copiados hasta ese separador (0x6E23 y 0x6F38).

**d) Los SEIS ADJETIVOS de la ficha, cada uno con su `ld hl`.** Estos no estan
en ninguna lista que haya que recorrer: 0x704B, 0x7061, 0x7006, 0x6FEF, 0x701E y
0x7035 cargan cada uno su direccion absoluta. Son los unicos que **si pueden
crecer**, moviendolos a otro sitio y cambiando el puntero. El limite aqui no es
la cinta sino la pantalla: la ficha son 24 columnas, el numero del parche va en
la 20 y el adverbio mas largo (" No es muy ") mide once, asi que un adjetivo de
ocho letras deja la coma justo debajo del numero -es lo que ya le pasaba a
"Energico"-. Lo mismo vale para la lista de la fila 9 (0x7D6A), que se ha mudado
entera a 0x66A2 con la frase completa en cada entrada.

### Los diecinueve cambios

| # | direccion | como estaba | como queda | cabe porque |
|---|-----------|-------------|------------|-------------|
| 1 | `0x7B34` | Bywater | **Delagua** | 7x1, siete letras justas |
| 2 | `0x7B28` | Buckland | **LosGamos** | 8x1, ocho justas |
| 3 | `0x7B5D` | Far Downs | **Quebradas** | 9x1, nueve justas |
| 4 | `0x7B4B` | Michel Delving | **Cavada Grande** | 7x2: `Cavada ` + `Grande ` |
| 5 | `0x7BC7` | Grey  Havens | **Ptos  Grises** | 6x2: `Ptos  ` + `Grises` |
| 6 | `0x7AA5` | Rivendell | **Rivendel** | de 9x1 a 8x1: le sobra una letra |
| 7 | `0x7AB2` | Isenmouthe | **Ga. Hierro** | 10x1, diez justas |
| 8 | `0x7A79` | Morannon | **Puerta N** | 8x1, ocho justas |
| 9 | `0x7B0D` | Dale | **Valle** | de 4x1 a 5x1, con el byte que le presta Rivendel |
| 10 | `0x7B7F` | HelmsDeep | **AbismHelm** | 5x2: `Abism` + `Helm ` |
| 11 | `0x6BA5` | Brand III | **Bardo III** | nueve letras entre dos `0xB7` |
| 12 | `0x7D3A`, `0x7D07` | Brujo / Brujos | **Mago / Magos** | ver abajo |
| 13 | `0x7D3A` | Elf | **Elfo** | ver abajo |
| 14 | `0x7D3A`, `0x7D07` | Hum | **Hombre / Hombres** | ver abajo |
| 15 | `0x7DE6` | Habil | **Firme** | cinco letras por cinco, en su hueco |
| 16 | `0x6689` | Valioso | **Virtuoso** | se muda al motor de altavoz muerto |
| 17 | `0x6692` | Duro | **Valiente** | idem |
| 18 | `0x669B` | Bravo | **Fuerte** | idem |
| 19 | `0x66A2` | Aliado a la Sociedad | **Aliado a la Comunidad** | la lista de la fila 9, mudada entera; el puntero cae en 0x66A1, el byte de delante |

Los diez primeros son la tabla de sitios; el 11 es la lista de los 24 nombres
propios (es el numero 13, entre `Thranduil` y `Theodred`); del 15 al 18 son
adjetivos de la ficha, que no van en ninguna lista -a cada uno lo carga su
propio `ld hl` absoluto: 0x704B, 0x7061, 0x7006, 0x6FEF, 0x701E y 0x7035-, y por
eso pueden crecer moviendolos y cambiando el puntero. El 19 es la ultima linea
de la ficha, que se componia con una plantilla mas una palabra: ahora cada
entrada de la lista trae la frase entera y se escribe desde la columna 0.

### Las dos tablas de razas: la cuenta que las hace caber

"Hum" -> "Hombre" son **tres bytes mas** y "Elf" -> "Elfo" **uno mas**. No hay
sitio detras: en 0x7D6A empieza la lista de carteles de bando y el codigo entra
ahi por direccion fija. Pero **"Brujo " -> "Mago" son dos bytes menos, y "Brujo"
sale dos veces en cada lista** (las razas 0 y 7 son dos clases de mago). La
cuenta sale exacta, sin tocar un solo byte fuera:

```
singular (0x7D3A, 44 bytes, razas 0..8)
  Brujo·6 Nazgul·6 Hum·3 Elf·3 Enano·5 Orc·3 Hobbit·6 Brujo·6 Gollum·6  = 44
  Mago·4  Nazgul·6 Hombre·6 Elfo·4 Enano·5 Orc·3 Hobbit·6 Mago·4 Gollum·6 = 44

plural (0x7D07, 45 bytes, razas 0..7)
  Brujos·7 Nazgul·6 Hum·3 Elfos·5 Enanos·7 Orcs·4 Hobbits·7 Brujo·6 = 45
  Magos·5  Nazgul·6 Hombres·7 Elfos·5 Enanos·7 Orcs·4 Hobbits·7 Mago·4 = 45
```

`Gollum` cierra las dos listas y no se toca, porque su ultimo byte **es** la base
de la lista siguiente.

> **Lo que va mas alla de la lista literal.** Los tres cambios de raza se pidieron
> en singular ("Brujo -> Mago", "Elf -> Elfo", "Hum -> Hombre"), pero `Brujo` y
> `Hum` estan **en las dos tablas**: dejar solo la de singular hubiera dejado el
> juego diciendo "Formacion de 005 Hum". Se ha cambiado tambien la de plural,
> **con la forma plural** (`Magos`, `Hombres`), que es lo que ese sitio pide:
> sus vecinas son `Enanos`, `Orcs` y `Hobbits`. `Elfos` ya estaba bien y no se
> toca. La raza 7 de la tabla de plurales la escribio el juego en singular
> (`Brujo `), y se respeta: queda `Mago`.

### Que no se ha tocado

- **`Orthanc`, `Orodruin`, `Barad-Dur`, `Umbar`, `Edoras`, `Linhir`,
  `Pelargir`, `Minas Tirith`, `Minas Morgul`, `Dol Guldur`, `Dol Amroth`,
  `Cirith Ungol`, `Durthang`, `Monte Gundabad`, `Harlond`, `Bree`, `Fornost`,
  `Hobbiton`, `Tharbad`**: no estaban en la lista, y ademas se escriben igual (o
  casi) en castellano.
- **Los otros cinco adjetivos** de la ficha (Energico, Decidido, Habil, Duro,
  Bravo) y los siete adverbios.
- **`Nazgul`**, que ya estaba bien (sin el circunflejo, que la fuente no tiene).

### Verificado (openMSX)

La cinta parcheada se carga entera en una Philips VG-8020
(`tools/omsx_arranque.tcl`) y se leen las tablas **de la RAM de la maquina**,
recorriendolas como las recorre el Z80. Los **29 registros de sitio siguen
midiendo ancho x filas**, y las listas de detras de las tocadas se siguen
leyendo enteras, que es la prueba de que nada se ha desplazado:

```
RAZAS EN PLURAL   (0x7D06): Magos, Nazgul, Hombres, Elfos, Enanos, Orcs, Hobbits, Mago, Gollum
RAZAS EN SINGULAR (0x7D39): Mago, Nazgul, Hombre, Elfo, Enano, Orc, Hobbit, Mago, Gollum, Mujer
FILA 9 DE LA FICHA (0x66A1): Aliado a la Comunidad, Forma una -, Forma una  union, Forma una  union
ADVERBIOS         (0x7D9A): Realmente ,  Muy ,  Es muy,  ,  Es algo ,  No muy  ,  No
ADJETIVOS (por sus seis ld hl): Energico, Decidido, Firme, Virtuoso, Valiente, Fuerte
NOMBRES (0x6B46): ... Thranduil, Bardo III, Theodred ...
```

**La A que se comia el juego (arreglado el 2026-09-10).** Esa lectura estaba
bien y la pantalla no: la ficha ensenaba `liado a la Comunidad`, y asi salio en
las tres imagenes de la ficha publicadas el 3 de septiembre, hasta que el
usuario lo vio jugando. `SALTA_B_TEXTOS` (0x6E98) hace `inc hl` ANTES de mirar
nada, porque espera que el puntero caiga en el byte ANTERIOR a la lista: en la
cinta, 0x7D6A es la ultima letra de `Gollum` y la lista de bando empieza en
0x7D6B. El parche apuntaba a 0x66A2, que es la A misma, y el juego se la
saltaba. Ahora apunta a 0x66A1 -la ultima letra de ` Fuerte`, con su bit 7-, y
el test de la fila 9 recorre la lista como el Z80, con el salto, en vez de
leerla desde el puntero tal cual: con el puntero viejo falla y dice
`liado a la Comunidad`. Entre la cinta parcheada de antes y la de ahora cambia
**un byte** (y su copia sin recolocar, 0x51C3, en el volcado de 0x0190).

Y en pantalla, la **misma casilla y la misma unidad** con la cinta original y con
la parcheada -la formacion 0x39, cinco Hombres en Valle-:

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/textos_sin_parche.png) | ![](docs/imagenes/textos_con_parche.png) |

De un tiron: el cartel `Dale` -> `Valle`, `Formacion de 005 Hum` ->
`005 Hombres`, `Hum:caracter:` -> `Hombre:caracter:`, `Destino: Dale` ->
`Destino: Valle` y `No Valioso` -> `No Virtuoso`. La de la derecha es la cinta de
hoy, asi que trae ademas el mapa repintado y el papel khaki: contra la original
cambian **547 de las 768 celdas**, y ya no tiene sentido contarlas para medir el
texto.

Y el cartel de dos filas, que era el que podia romperse:

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/cartel_sin_parche.png) | ![](docs/imagenes/cartel_con_parche.png) |

`Michel`/`Delving` pasa a `Cavada`/`Grande` en el mismo cartel de 7x2. Cuando se
midio contra la cinta de septiembre eran **13 celdas de caracter, todas dentro
del cartel**, y ningun atributo; la de hoy trae tambien el mapa repintado
debajo.

Las imagenes son las de siempre: el bufer de pantalla del ZX volcado de la RAM
en un instante fijo y dibujado con `tools/render_zx.py`, no capturas.

---

## 6) El mapa repintado — HECHO y VERIFICADO

El mapa se dibuja con **128 tiles de 8x8** en 0x9E00, de nueve bytes cada uno:
ocho de dibujo y un **atributo del ZX Spectrum** detras. `tools/lienzos.py` los
saca a un PNG de 128x64 a tamano real -dieciseis por fila- y los vuelve a leer;
`make parche` compara el lienzo con la cinta y convierte en entrada cada dibujo
que haya cambiado. **122 de los 128** han cambiado: 103 entradas y 848 bytes.

### El lienzo mentia: el atributo es del ZX, el color es del MSX

Los tiles salian al PNG con los colores del **Spectrum**, que es lo que dice el
atributo. En pantalla no se ven asi nunca: esta conversion no manda el atributo
al VDP, lo traduce antes `ATRIBUTO_A_COLOR` (0x049F), leido de la cinta:

```
049F  push hl / push de / push bc / push af
04A3  ld hl,004CEh        ; la tabla SIN brillo
04A6  bit 6,a             ; el BRIGHT del atributo
04A8  jr z,+3
04AA  ld hl,004D6h        ; la tabla CON brillo
...                       ; tinta -> nibble alto, papel -> nibble bajo
```

| | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| `0x04CE`, sin brillo | 1 | 4 | 6 | 13 | 12 | 7 | 10 | 15 |
| `0x04D6`, con brillo | 1 | 5 | 9 | 13 | 3 | 7 | 11 | 15 |

Dieciseis huecos y **doce colores distintos del MSX**: no hay atributo que de el
rojo medio (8), el verde medio (2) ni el gris (14). Medido sobre el repintado que
llego: 349 pixeles de rojo medio en 16 tiles, 47 de verde medio en 4 y 3 de gris
en uno; cada uno se cambia por el alcanzable mas parecido y la herramienta lo
dice. Y solo cuatro de los ocho colores cambian con el bit de brillo -azul,
rojo, verde y amarillo-, asi que la regla de "los dos del mismo brillo" solo
obliga en esos.

### El papel del texto, del blanco al khaki

`UN_CARACTER_NORMAL` (0x7616) pinta **todos** los caracteres de la fuente con un
atributo fijo, el `ld a,078h` de 0x763E. Su operando -0x763F- pasa de 0x78 a
0x70: papel 6 con brillo, que la tabla de 0x04D6 manda al color 11 del MSX, el
mismo khaki de los marcos. Se lleva tambien los **espacios**, que son los que
rellenan el interior de un cartel. Es global: menu, rotulos, ficha y batalla.

### Verificado (openMSX)

La cinta parcheada cargada de cero en un Philips VG-8020, volcado el bufer de
pantalla del ZX en la misma casilla de siempre (036N/096E):

- los bytes del parche siguen en su sitio en el mismo volcado (0x7FD1=00,
  0x708A=CD, 0x664C=CD), que es el control de que el juego esta donde se cree;
- contra la cinta original cambian **735 de las 768 celdas** de caracter y 560
  atributos;
- y el previo que `tools/previo_repinta.py` habia dibujado ANTES de tocar la
  cinta sale **identico al pixel**: 0 de 196.608 distintos.

| sin parche | con el mapa repintado |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/mapa_con_parche.png) |

Los 128 tiles, como vienen en la cinta y como quedan:

| la cinta | repintados |
|---|---|
| ![](docs/imagenes/tiles-del-mapa.png) | ![](docs/imagenes/tiles-repintados.png) |

**Ocho tiles se quedan en blanco a proposito**: el 85 al 88 y el 93 al 96, que
son los cuatro cuadrantes de los cuadros 0x16 y 0x18 de la tabla de 0x77B5. De
esa tabla tienen dueno conocido el 0x00-0x0F (`PINTA_LO_DE_ENCIMA`, por el
nibble del terreno), el 0x11 y el 0x15 (`PINTA_LA_UNIDAD`) y el 0x13/0x14
(terreno 4); para el 0x10, el 0x12, el 0x16, el 0x17 y el 0x18 **no se ha
encontrado llamador**, que no es lo mismo que demostrar que estan muertos.

## Estado

| peticion | estado | evidencia |
|----------|--------|-----------|
| 1 · enemigos visibles | hecho, verificado | 136 enemigas sembradas; 9 casillas de 10 (la 0x16 y la 0x17 las salta el juego) |
| 2 · valores de la unidad | hecho, verificado | los seis numeros coinciden con la RAM |
| 3 · plazo del Anillo | hecho, verificado | el 0x8333 -255 meses- escrito al lado del anillo |
| 4 · el Ojo de Sauron | hecho, verificado | 9 casillas marcadas, 12 celdas cambian, 0 atributos tocados |
| 5 · los textos en espanol | hecho, verificado | leidos de la RAM del emulador: 29 carteles cuadran, las cuatro listas se siguen leyendo |
| 6 · el mapa repintado | hecho, verificado | 122 de 128 tiles; volcado de la cinta parcheada = previo, 0 pixeles distintos de 196.608 |
| 7 · de cinta a cartucho | hecho, verificado | RAM, VRAM, VDP y PSG iguales a los de la cinta en cuatro maquinas; nadie ha jugado una partida entera desde el |

**1.396 bytes en 130 entradas de la tabla, ninguna fuera de ella y ninguna
desplazada**: 27 escritas a mano (548 bytes de codigo, punteros y texto) y 103
sacadas de los lienzos (848 de tiles repintados). `make test` = 114 en verde: 79 del parche y 35 del cartucho.

## Como se reparte

`make ips` saca **`war_parche.ips`**, que lleva solo los bytes que cambian -1.515
en 39 registros, 1.718 bytes de fichero- y se aplica sobre tu propia cinta.
Comprobado: aplicado sobre `war.tsx` da un fichero identico byte a byte al que
saca `make parche`.

## De cinta a cartucho — HECHO y VERIFICADO

El juego no se toca: `war.rom` es una **MegaROM ASCII16 de 64 KB** que lleva
dentro los cuerpos de los bloques de la cinta y un cargador que deja la RAM
**exactamente como la deja el cargador de la cinta** antes de saltar a 0x0190:
el bloque bajo en 0x0190, el medio en 0x3F4F, el alto en 0x88B8, el buzon de
POKEs de 0x012C a cero y SP=0xFDE8. Luego salta al mismo 0x0190, y el propio
juego recoloca los bloques a 0x5E00 y 0x9E00 como hace siempre. Con la cinta
parcheada sale `war_parche.rom`. **Ninguna de las dos se distribuye**: se
montan de tu cinta con `make rom` y `make rom_parche` (ver
[AVISO-LEGAL.md](AVISO-LEGAL.md)).

### Como esta hecha

- **77 bytes de arranque** en la ROM (`src/cartucho/cargador_rom.asm`): la
  cabecera `AB`, el banco 0, copiar el stub a RAM y saltar a el.
- **Un stub de 1.105 bytes** que corre en 0xD800 (`src/cartucho/cargador_ram.asm`):
  busca RAM en las paginas 2, 1 y 0 e interpreta un **plan de 52 operaciones
  de 8 bytes** que `tools/haz_rom.py` genera de la disposicion real de la ROM
  y deja en `work/plan.json`, para que los tests no supongan nada.
- Los datos van de 0x0800 a 0xF727: quedan 2.264 bytes libres. (En
  `war_musica.rom`, que ademas comprime las imagenes con ZX0, el hueco es de
  13.627 bytes.)
- **El tramo de la pagina 1 pasa por la VRAM.** Con el cartucho puesto la
  pagina 1 (0x4000-0x7FFF) es la ROM, y ahi caen 14.400 bytes del bloque medio
  (0x4000-0x783F). Se copian primero a la VRAM, que esta libre durante la
  carga; se quita el cartucho de la pagina 1, y vuelven. El bufer llega hasta
  0x383F y pisa la tabla de nombres y las de sprites de SCREEN 2, asi que esas
  se escriben dos veces.
- **Lo que el juego hereda del BASIC.** El juego solo escribe el registro 7 del
  VDP y nunca la tabla de nombres: cuenta con el `COLOR 1,1,1:SCREEN 2` de las
  dos lineas de BASIC de la cinta. El cartucho reproduce lo MEDIDO en la cinta
  al llegar a 0x5E00 (`tools/omsx_estado_cinta.tcl`): VDP R0-R7 =
  `02 E0 06 FF 03 36 07 01`, tabla de nombres identidad, 32 sprites en Y=209,
  PSG con R7=0x3F leido y R11=0x0B.
- Ranuras: ENASLT de la BIOS para las paginas 2 y 1 mientras la pagina 0 sigue
  siendo la BIOS, y un clon propio para la pagina 0 y despues, que no voltea la
  pagina 3 porque el stub vive ahi. Probado con la RAM en ranura expandida
  (Philips NMS 8250).
- La pantalla de carga se ensena 150 cuadros (`--espera N`; `--sin-pantalla` la
  quita).

### Verificado (openMSX, `make verifica_rom` y `make verifica_rom_parche`)

`tools/omsx_verifica_rom.tcl` arranca la maquina con el cartucho y vuelca lo
mismo que se volco con la cinta, en los mismos dos instantes;
`tools/coteja_rom.py` lo compara byte a byte:

- en 0x0190, contra `full_crudo.bin`: bajo + medio (0x0190-0x783F) y alto
  (0x88B8-0xD12F) tal como caen de la cinta;
- en 0x5E00, contra `full_5e00.bin`: los tres bloques recolocados
  (0x0190-0x3F4E, 0x5E00-0x96F0, 0x9E00-0xE677), **la VRAM entera**, los
  registros 0-7 del VDP y los 0-13 del PSG.

Exit 0 con `war.rom` en Philips VG-8020, Philips NMS 8250, C-BIOS MSX1 y C-BIOS
MSX2, y con `war_parche.rom` en la VG-8020 contra los volcados de la cinta
parcheada. En MSX2 el R1 se lee 0x60 porque el V9938 no tiene el bit 4K/16K del
TMS9918; se acepta con aviso. `make captura_rom` ensena el menu y, tras pulsar
0, el mapa (PC=0x6A47). Los tests del cartucho estan en
`tests/test_cartucho.py`; el fuerte es un interprete del plan en Python que
lleva la cuenta de la RAM, la VRAM y de que hay en la pagina 1 en cada paso, y
falla si el plan escribiera en 0x4000-0x7FFF con el cartucho puesto.

Lo que NO se ha hecho: jugar una partida entera desde el cartucho. Se ha visto
arrancar, el menu y el mapa.

### Las dos pantallas finales, a la ROM: 13.824 bytes de RAM

`war_musica.rom` se monta ademas con `--finales-rom`, y eso es lo que mas RAM
libera de todo el cartucho.

**El problema.** Las dos pantallas del final -la victoria en 0x094F y la
derrota en 0x244F, 6.912 bytes cada una- ocupaban 13.824 bytes de RAM desde que
arrancaba el cartucho hasta el final de la partida, y se usan UNA VEZ, en los
ultimos segundos. Estaban ahi por herencia: la cinta las cargaba asi y el
cartucho se limitaba a reproducir lo que dejaba la cinta.

**Por que se puede.** `PINTA_LA_PANTALLA_FINAL` (0x83E7) es donde convergen los
cuatro finales del juego -0x6A73, 0x7F7D, 0x8338 y 0x9229 saltan a VICTORIA
(0x83D9) o a DERROTA (0x83E1), y las dos caen ahi-. Y lo que hacia eran ocho
bytes:

    83E7:  ld de,04000h / ld bc,01b00h / ldir      11 00 40 01 00 1B ED B0

O sea que **las pantallas no se usan donde estan**: se copian a 0x4000 y se
pintan desde ahi, asi que da igual de donde vengan los bytes. Detras viene un
`di` y un bucle cerrado sobre si mismo: el juego se acaba y no hay que dejar
nada recuperable.

**Que se ha hecho.** Esos ocho bytes pasan a ser `call` a
`src/cartucho/finales.asm` mas cinco ceros. HL llega con 0x094F o con 0x244F,
asi que la rutina sabe cual le piden sin tocar VICTORIA ni DERROTA. Los bloques
se quedan en la ROM, donde ya viajaban comprimidos, y la rutina los descomprime
a 0x4000. **Son 200 bytes** que viven en la pagina 0, en la RAM que ellos mismos
liberan (0x0950), y llevan su propio descompresor ZX0.

**Las dos conmutaciones, que es lo delicado.** El registro que manda en la
ventana de 0x8000 -por donde se lee el bloque- vive en 0x7000, o sea en la
PAGINA 1, que en tiempo de juego es RAM. Para elegir banco hay que poner un
momento el cartucho ahi, escribir el registro y devolver la RAM. Y **en ese
tramo no se puede tocar la pila**: la del juego esta en 0x5BFF, pagina 1, y
cualquier push, pop, call o ret leeria o escribiria la ROM. Por eso el bucle de
copia no la toca. Ademas corre con `di`, porque mientras dura la pagina 2 es la
ROM y la interrupcion del juego usa datos que viven ahi.

**Y por eso va en dos pasos.** Primero se COPIA el bloque comprimido a un bufer
en RAM -ahi si se cruza de banco- y despues se llama a ZX0, ya con las cuatro
paginas en RAM. ZX0 usa la pila a fondo (`push bc`, `ex (sp),hl`) y lee el
origen de corrido, asi que no puede correr ni con la pagina de la pila
conmutada ni a caballo de dos bancos.

**La RAM, antes y despues** (`tools/mapa_ram.py`, que la calcula del plan y de
lo medido con openMSX, sin cifras escritas a mano):

    ajena a la cinta, antes .... 2.304 B
    ajena a la cinta, ahora ... 16.449 B
    menos el puente (75), la rutina (200) y el area del PT3 (382)
    LIBRE ..................... 15.792 B

**Quien mas usaba ese tramo: nadie.** Barrido de los cinco listados buscando el
rango 0x094F-0x3F4E: 41 apariciones, y todas son constantes -tamanos, contadores
y direcciones de VRAM- salvo dos, que son `ld hl,0094fh` (0x83DC) y
`ld hl,0244fh` (0x83E4). Justo las dos que este cambio sustituye. Encaja con lo
medido antes con la partida grabada: leidas una sola vez, por el `ldir` de
0x83ED.

#### Verificado: `make verifica_finales`, exit 0

Para ver una pantalla final hay que terminarse el juego, asi que
`tools/omsx_finales.tcl` lo fuerza: arranca la ROM, llega al menu, pulsa 0 y
pone el PC en 0x83E7 con HL en cada pantalla. Dos cotejos, y el primero es el
que decide:

1. **Los 6.912 bytes que quedan en 0x4000, contra los de la CINTA.** Es una
   verdad absoluta y no una comparacion entre dos ROMs: de ahi es de donde
   0x05BD y 0x0604 sacan lo que suben al VDP. Las dos pantallas, OK.
2. **La VRAM ya pintada, contra la de la ROM de antes del cambio.** Las dos, OK.

Y sin emulador, `tools/corre_finales.py` **ejecuta la rutina** en un interprete
del Z80 con las ranuras y el mapper modelados: comprueba que lo que deja en
0x4000 es la pantalla de la cinta, que nunca toca la pila con el cartucho en la
pagina 1, que no escribe un solo byte en la ROM, que devuelve las paginas y el
banco como estaban y que no se pasa de 6.912 bytes. Lo repite con el cartucho
en las cuatro ranuras primarias posibles, porque una mascara mal puesta solo se
nota en algunas combinaciones. El interprete solo conoce las instrucciones que
la rutina usa: si alguien le anade una, el test se para en vez de pasarla por
alto.

### ZX0 en vez del RLE de marca: 6.429 bytes mas de ROM

Las imagenes viajaban comprimidas con un **RLE de marca** escrito aqui: byte
literal salvo tras una marca, que es el byte menos frecuente del bloque. Tiene
la virtud de que descomprime **en streaming**, escribiendo directo al puerto
0x98 del VDP sin pasar por RAM, y la pega de que en una pantalla del ZX hay
pocas rachas y por tanto poco que encoger.

**Este cartucho usa ZX0**, de Einar Saukas. Medido con su compresor, no
estimado:

| bloque | crudo | RLE de marca | ZX0 |
|---|---|---|---|
| intro: patrones | 6.144 | 5.236 | **3.663** |
| intro: colores | 6.144 | 2.511 | **1.030** |
| victoria | 6.912 | 5.519 | **3.847** |
| derrota | 6.912 | 5.763 | **4.060** |
| **total** | 26.112 | 19.029 | **12.600** |

    hueco de la ROM: 7.253 -> 13.627 bytes

El descompresor son **68 bytes** (`src/cartucho/dzx0.asm`, la version
"Standard"), y va **dos veces** en la ROM: una en el stub, que descomprime al
cargar, y otra dentro de la rutina de las pantallas finales, que no puede
llamar al stub porque en tiempo de juego 0xD800 puede estar pisado.

#### Lo que ZX0 obliga a cambiar, y por que hace falta un bufer

ZX0 es LZ: la mayor parte de lo que escribe son **copias de lo que ya escribio**
(`add hl,de` sobre el destino y `ldir`). De ahi tres consecuencias que el RLE no
tenia:

1. **El destino tiene que ser RAM legible.** Contra la VRAM no se puede, asi que
   lo que va a la pantalla ya no se descomprime en un paso: se trae el bloque
   comprimido a un bufer, se descomprime a otro y se vuelca de corrido
   (`ROM_RAM`, `ZX0_RAM`, `RAM_VRAM`).
2. **Usa la pila a fondo** (`push bc`, `ex (sp),hl`), asi que no puede correr
   con la pagina de la pila conmutada al cartucho.
3. **Lee el origen de corrido** y no sabe cruzar de banco.

Los dos bufers piden ~9.800 bytes contiguos justo cuando se repinta la imagen de
carga, y **eso solo cabe desde que las pantallas finales dejaron de viajar a la
RAM**: van en 0x0A50-0x324F, dentro de los 13.824 que ellas liberaron. Los dos
cambios se sostienen el uno al otro.

Y una cosa que NO se ha hecho: **comprimir el modulo `.pt3`**. ZX0 lo dejaria en
220 bytes en vez de 426, pero habria que tenerlo descomprimido en RAM y tocar el
puente. Cambiar 206 bytes de ROM por 426 de RAM no sale a cuenta cuando lo que
sobra es ROM.

#### De paso: EL JUEGO PIERDE BYTES AL ESCRIBIR LA VRAM

Cotejando la VRAM salian casi 4.000 bytes de diferencia entre dos ROMs cuyos
6.912 bytes de 0x4000 eran identicos. No era el cambio: `UN_TERCIO_A_VRAM`
(0x05D6) hace `ld a,(hl) / out (098h),a / inc h` en bucle apretado, y con la
pantalla ENCENDIDA el VDP no tiene ranuras de acceso para tanto y se le caen
bytes. Cuales se caen depende de en que punto del barrido se empiece, asi que
dos ROMs que tardan distinto en cargar pintan bitmaps distintos.

Medido: 3.996 bytes de diferencia en la victoria y 4.603 en la derrota con la
pantalla encendida, y **CERO en cuanto se apaga**. La misma ROM dos veces da
siempre lo mismo, asi que es reproducible, no aleatorio. O sea: **la pantalla
final del juego original ya sale con bytes perdidos, y no siempre los mismos.**
Por eso la sonda apaga la pantalla antes de pintar: para que el cotejo compare
lo que el juego ESCRIBE, que es lo unico que este cambio podria alterar.

### La vista de cerca, por tabla de nombres — HECHO y VERIFICADO

La vista de cerca (`BUCLE_DE_LA_VISTA`, 0x71F9) es lo que mas se repinta del
juego, y lo hacia a lo bruto: `PANTALLA_DE_CARACTERES_A_LA_ZX` (0x75A5)
expandia las 768 celdas de la pantalla de caracteres de 0x5E00 a 6.144 bytes de
bitmap y 768 de atributos en RAM, y subia los 12.288 bytes a la VRAM **en cada
vuelta del bucle**. Medido en un NMS 8250 (`tools/omsx_vista.tcl`): 800.857
ciclos de los 1.132.000 de una vuelta.

Y no hacia falta, porque **esa pantalla ya es una tabla de nombres**: un byte
por celda; con el bit 7 a 1 es uno de los 128 dibujos de 0x9E00 y con el bit 7
a 0 uno de los 128 caracteres de la fuente de 0xC800, siempre con el atributo
0x78. 128 + 128 = 256 patrones justos, y el color es funcion del codigo. O sea:
el byte de 0x5E00 ES el indice de patron del SCREEN 2, sin traducir.

`src/cartucho/nombres.asm` (218 bytes en 0x3250, detras de los bufers de ZX0)
hace tres cosas:

- **`CARACTERES_A_NOMBRES`** sustituye a 0x75A5 entera -sus tres primeros bytes
  pasan a ser un `jp`, y asi cubre a sus tres llamadores- y sube a 0x1800 los
  32 primeros bytes de cada una de las 24 filas de 34: **768 bytes por vuelta en
  vez de 12.288**, y ni un byte de RAM que expandir. Sin sombra de lo ya subido:
  comparar una celda cuesta lo mismo que subirla.
- **`PONE_LOS_PATRONES`**, la primera vez tras un pintado en bitmap, sube los 256
  patrones y sus colores **replicados en los tres tercios** (0x0000/0x0800/0x1000
  y 0x2000/0x2800/0x3000). Asi no se toca ni R3 ni R4 y cualquier tercio con el
  nombre *n* ensena el mismo dibujo. Cuesta una vuelta de las de antes, una vez.
- **El guardian**, en `VRAM_A_ESCRIBIR` (0x044B, bloque bajo): es la UNICA
  rutina del juego que pone una direccion de VRAM (las `out (099h)` de 0x044D y
  0x0454; los bloques medio y alto no tocan el puerto), y por ahi pasan el mapa,
  los menus de `LISTA_*` -que se abren DESDE la vista-, la batalla y los finales.
  Sus cuatro primeros bytes pasan a `call GUARDIAN / nop`, y si la tabla de
  nombres es la de la vista, la devuelve a la identidad antes de dejar escribir.
  Asi no hay que enumerar caminos. Medido antes con `tools/omsx_fronteras.tcl`:
  en la vista solo escribe la VRAM 0x074E desde 0x7610, y nadie mas lee ni
  escribe 0x4000-0x5AFF.

Son siete bytes mas del juego: veinte en total con los de la musica y los de
las finales.

**Medido, antes y despues, en el NMS 8250** (`make mide_vista MAQUINA=Philips_NMS_8250`):

    antes     1.132.000 ciclos por vuelta    3,2 vueltas por segundo
    despues     363.884 ciclos por vuelta    9,8 vueltas por segundo

Lo que queda son los 330.031 ciclos de `DIBUJA_EL_TROZO_DE_MAPA`, que es el
siguiente objetivo.

**Verificado** (`make verifica_vista`, exit 0 en la VG-8020 y en el NMS 8250):
la VRAM ya no se parece byte a byte a la de antes, asi que el cotejo es **por
pixel**. Las dos ROMs -la nueva y la misma sin `--vista`, que difieren en 353
bytes- se llevan a los mismos instantes de la vista, contados **por vueltas del
bucle** y no por reloj (van a distinta velocidad y el cursor parpadea por
vuelta), y se dibuja lo que el VDP ensena con `tools/render_vram.py`: cinco
instantes -tres de la vista, el menu de la R y el mapa al salir- **identicos
pixel a pixel**, y en los dos de bitmap la VRAM entera identica byte a byte, que
es la prueba del guardian. Con la pantalla encendida, que es cuando el VDP
pierde bytes, a la rutina nueva no se le cae ninguno: sus bucles van a 36 ciclos
por byte o mas. Y sin emulador, `tools/corre_nombres.py` ejecuta la rutina en el
interprete de Z80 con el VDP modelado: los patrones, los colores y los nombres
son los que salen de la cinta, y el guardian deja BC, DE y HL como entraron.

De paso, una cosa del juego original que el cotejo puso delante: al cerrar el
menu de la R eligiendo a quien ya lleva el Anillo, `MENU_DE_ENTREGA` vuelve con
el numero de ese personaje en A y 0x7224 se lo pasa a `MUEVE_POR_EL_MAPA` como
si fuera el mando. Con Frodo, que es el 5 (bits 0 y 2: arriba e izquierda), el
cursor sube una casilla y va otra a la izquierda. Sale igual en la ROM sin el
cambio, que ahi corre el codigo de la cinta tal cual.

## Lo que queda abierto

- **Nadie ha jugado una partida entera** con el mapa repintado; Araubi si jugo
  una con la version de septiembre, y de ahi salio el fallo del gancho del
  Anillo. La ficha se ha visto en Gandalf y en Frodo, no en todos los tipos de
  unidad.
- **Ocho tiles se quedan en blanco**: el 85 al 88 y el 93 al 96, que son los
  cuadros 0x16 y 0x18 de la tabla de 0x77B5. No se les ha encontrado llamador,
  que no es lo mismo que demostrar que estan muertos.
- **El plazo solo se ve abriendo la ficha del portador.** Un medidor siempre en
  pantalla pide enganchar el bucle de partida (0x7F57) y escribir cada cuadro:
  es codigo nuevo con mas riesgo, y queda apuntado como ampliacion.
- **Las unidades 0x16 y 0x17 siguen invisibles**, porque el bucle de siembra las
  salta a proposito y no se ha averiguado por que.
- **El cartucho solo se ha visto arrancar**: el cotejo dice que la RAM, la VRAM,
  el VDP y el PSG son los de la cinta al arrancar, y se han visto el menu y el
  mapa; nadie ha jugado una partida entera desde el.
