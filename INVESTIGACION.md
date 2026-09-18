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
| 8 · Gollum, hobbit | hecho, verificado | un byte (0xBD15): era la unica unidad de tipo 8 de las 256, y ese tipo se dibujaba como el enano; en el juego corriendo, tipo 6 como Sam, Merry y Pippin |
| 9 · el cursor de la batalla | hecho, verificado | 3,00 casillas/s con el limite y 4,00 sin el, con el bucle a 7 vueltas/s (tools/omsx_cursor_batalla.tcl, VG-8020) |
| 10 · los sprites repintados | hecho, verificado | el guante en azul y los cursores sin el bloque opaco; el cotejo del mapa da 85 pixels distintos, los mismos que enciende guante.png, y 0 fuera |
| 11 · dos heroes mas | hecho, verificado | Tom Bombadil (tipo 8, "Eterno") y Radagast (tipo 0) en las ranuras 0x18 y 0x19; sus fichas y 0xBD18 = 8 leidos con el juego corriendo |

**1.578 bytes en 195 entradas de la tabla, ninguna fuera de ella y ninguna
desplazada**: 29 escritas a mano (568 bytes de codigo, punteros y texto) y 166
sacadas de los lienzos (1.010 de dibujos repintados). `make test` = 193 en
verde: 92 del cartucho, 33 del parche, 32 de los lienzos, 10 del cursor, 9 de
los listados, 6 del mapa, 8 de los dos editores y 3 mas.

## Como se reparte

`make ips` saca **`war_parche.ips`**, que lleva solo los bytes que cambian -1.830
en 50 registros, 2.088 bytes de fichero- y se aplica sobre tu propia cinta.
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

**La sombra, medida y descartada.** El plan traia una sombra de 768 bytes para
subir solo las filas que cambian, y la intuicion dice que en reposo solo
cambian las dos filas del cursor. Se monto como variante de ensamblado
(`--vista-sombra`, `make mide_sombra MAQUINA=Philips_NMS_8250`; el codigo sigue
en `nombres.asm` bajo `IF SOMBRA`) y se midio en el NMS 8250, con la ROM
pintando lo mismo pixel a pixel:

    ciclos por vuelta        sin sombra    con sombra
    en reposo                   363.884       363.968
    moviendo el cursor          623.715       645.979

No gana en reposo y pierde un 3,6 % moviendo. La razon es de reloj: comparar
una celda con la sombra son 31 ciclos (`ld a,(de) / cp (hl) / jr nz / inc de /
inc l`) y subirla 37, porque el VDP no admite dos bytes a menos de ~29 ciclos
con la pantalla encendida. Ahorrar la subida cuesta lo mismo que hacerla. Donde
SI paga "no pintar lo que no cambia" es en el trozo: ver abajo.

De paso, una cosa del juego original que el cotejo puso delante: al cerrar el
menu de la R eligiendo a quien ya lleva el Anillo, `MENU_DE_ENTREGA` vuelve con
el numero de ese personaje en A y 0x7224 se lo pasa a `MUEVE_POR_EL_MAPA` como
si fuera el mando. Con Frodo, que es el 5 (bits 0 y 2: arriba e izquierda), el
cursor sube una casilla y va otra a la izquierda. Sale igual en la ROM sin el
cambio, que ahi corre el codigo de la cinta tal cual.

### El cursor como sprite y la ventana fija — HECHO y VERIFICADO

Con la tabla de nombres, de los 363.884 ciclos de una vuelta 330.031 eran
`DIBUJA_EL_TROZO_DE_MAPA` (0x7643): repintar las 16 x 13 celdas del trozo en
cada vuelta aunque el cursor no se moviera. Se repintaba porque el cursor iba
dentro de la pantalla de caracteres -cuatro caracteres de 0x77B5 + modo*4
escritos encima del centro- y la ventana se desplazaba con el. La idea del
usuario: *siendo un sprite no pintariamos el mapa*.

Ahora el cursor son **dos sprites de 16x16 solapados**, uno por color (el
dibujo y el bloque de detras), **siempre en el centro**: lo que se mueve es el
mapa, como en el original. El trozo solo se vuelve a dibujar cuando cambia la
posicion del cursor o el modo; la pantalla de caracteres limpia se guarda en
una cache de 850 bytes y en las vueltas sin repintado -el reposo, que es donde
se iba el 91 % del tiempo- se restaura con un `ldir`; las ventanas de
posicion, ficha y sitio se dibujan encima como siempre. El cursor ya no
parpadea. (Hubo una version intermedia con la ventana del trozo quieta y el
cursor moviendose dentro, con un margen de tres celdas; se cuenta mas abajo, y
se quito.)

Tres decisiones del usuario: el cursor fijo en el centro, el cursor **editable**
-`src/cartucho/cursor.png`, 48 x 16, los tres cursores (mirar, elegir
destino, batalla) con hasta dos colores mas el transparente; `tools/cursor.py`
lo saca de los tiles de la cinta parcheada y lo vuelve a leer como planos de
sprite; `tools/editor_sprites.html` es un editor de los dos planos que se abre
en el navegador, ensena el dibujo sobre un trozo de la pantalla de verdad y
guarda ese PNG (tambien el del guante del mapa general)- y **una casilla cada diez cuadros** con la tecla pulsada: con la vuelta
a mas de cuarenta por segundo el cursor, que avanza una casilla por vuelta,
iba a 25 casillas por segundo. Ahora `MI_MUEVE` deja pasar un paso cada diez
cuadros -cinco por segundo a 50 Hz-, y una pulsacion suelta mueve al instante.
Los cuadros los cuenta el gancho de la interrupcion: cuando la musica calla, el
puente lo deja apuntando a `CUENTA_CUADROS` (cuatro bytes) en vez de al `ret`
vacio.

Son **cinco parches del juego, dieciseis bytes**: los siete de la vista, tres
en 0x71A4 (`push hl / push hl / exx` por un `jp MI_PINTA`), tres en 0x7225 (el
`call MUEVE_POR_EL_MAPA` de la vuelta por `call MI_MUEVE`) y tres en 0x7758
(el `call LEE_LOS_MANDOS` del menu de la casilla por `call MI_ELECCION`, ver
mas abajo). En 0x71C6 NO se
puede poner un salto, porque 0x752E escribe en 0x71C7 (el operando del
parpadeo): MI_PINTA replica 0x71A7-0x71C5 llamando a las mismas rutinas
(`CELDA_DEL_MAPA` con la fila mas uno, la esquina 720 bytes atras,
`DIBUJA_EL_TROZO_DE_MAPA`, `TAPA_LOS_BORDES`). Lo que se leyo del listado y
manda en el diseno: la esquina del trozo es (H-5, L-7) y el cursor cae en la
celda (7, 5) de la ventana; el reloj del juego no corre en la vista (solo lo
mueve `BUCLE_DE_PARTIDA`), y el trozo cambia sin moverse el cursor solo por la
marca de bit 6 de una orden -que llega tras un menu de bitmap, o sea tras el
guardian- y al quitarla, que cambia el modo: la cache vale mientras no cambien
la esquina ni el modo ni pase el guardian, que ademas esconde los sprites
(Y=209, como los dejo el cargador). El tamano 16x16 lo pone el plan en R1
(0xE2): el juego nunca escribe R1.

Dos cosas que solo se vieron al cotejar. **`tools/render_vram.py` tenia los
cuadrantes del sprite de 16x16 al reves** (van por columnas: 0-7 arriba a la
izquierda, 8-15 abajo a la izquierda, 16-23 y 24-31 la derecha) y nadie lo
habia visto porque este juego no ensenaba ningun sprite. Y **el atributo del
texto no se puede copiar**: el parche de Araubi lo cambia de 0x78 a 0x70 (el
amarillo claro de los marcos), asi que la rutina lo lee del operando de
0x763E; con la constante, en la cinta parcheada el cartel de Posicion salia
con los colores de la cinta original.

**Medido en el NMS 8250** (`tools/omsx_vista.tcl`, `war_unificada.rom`):

    en reposo                363.884 ->  82.772 ciclos por vuelta    9,8 -> 43,2 vueltas por segundo
    moviendo sin soltar      623.715 -> 367.761 de media             5,7 ->  9,7: la mitad de las vueltas repintan
                                                                     (658.702 de media, y crece con el terreno:
                                                                     de 404.144 a 684.378 entrando en las montanas)
                                                                     y la otra mitad viene de la cache (82.757)

Y el paso del cursor (`tools/omsx_paso_cursor.tcl`, dos segundos con la derecha
pulsada, VG-8020): 10 casillas, cinco por segundo; la ROM sin la vista, tres.

**Verificado** (`make verifica_vista` y `make verifica_vista_parche`, exit 0 en
la VG-8020, y la parcheada tambien en el NMS 8250). Como la nueva no repinta
el trozo en todas las vueltas, `tools/coteja_vista.py` lleva un **modelo de
la cache** y la sonda vuelca el trozo puro de cada vuelta: se exige que la
nueva pinte el trozo exactamente en las vueltas que dice el modelo (20 de 60:
al entrar, tras cada menu y en cada paso del cursor, mientras la vieja lo
pinta en las 60), que caracter a caracter el trozo sea el que la vieja pinto
en el ultimo repintado y las ventanas las de cada vuelta, que los atributos y
patrones de los sprites sean los que tocan, y, en todos los instantes,
**pixel a pixel con la vieja**: en `vista_k`, con el cursor
de la vieja encendido, las dos imagenes son identicas, sprite incluido. En los
instantes de bitmap la VRAM entera es identica byte a byte, sprites escondidos
incluidos. Sin emulador, `tools/corre_nombres.py` ejecuta MI_PINTA y MI_MUEVE
con trampas en las tres rutinas del juego (152 tests). Y como los PNG del
cotejo los dibuja la propia herramienta, `make captura_vista` saca tres
capturas del emulador de verdad, con el renderer encendido.

**La ROM que se juega es `war_unificada.rom`** (`make rom_unificada`):
la cinta parcheada de Araubi con la musica, ZX0, las finales en la ROM y la
vista con el cursor. `cursor.png` sale de sus cuerpos (`make cursor`) porque
el parche repinta el cursor de batalla.

### Dos fallos vistos jugando, y la vuelta del cursor al centro

Los dos salieron el 2026-09-13 con la ROM en la mano, y los dos eran hijos de
la misma cosa: la vuelta iba cuatro veces mas rapida y el cursor ya no estaba
siempre en el centro.

**El cursor se metia debajo de la ficha.** En el original el cursor se
escribia en la pantalla de caracteres ANTES de las ventanas, asi que una
ventana lo tapaba; y en la practica no pasaba nunca, porque el cursor estaba
siempre en la celda (7, 5) y la ficha -24 x 10 con marco, desde la fila 13 de
caracteres (0x5FBD)- queda por debajo. El sprite, en cambio, va por delante de
todo, y con la ventana quieta el cursor bajaba hasta la fila 9: se veia encima
del texto de la ficha. Se arreglo primero escondiendo el sprite cuando una
ventana tapaba sus cuatro celdas (comparandolas con la cache) y recentrando en
la vuelta siguiente; y con eso a la vista el usuario decidio **volver a que el
cursor este en el centro y no se mueva nunca: solo se mueve el mapa**, como en
el original, y quitar el paginado de diez columnas y siete filas. Asi que la
ventana quieta, el margen y aquel arreglo se retiraron: MI_PINTA repinta el
trozo cuando cambia la posicion o el modo y lo saca de la cache en las demas
vueltas, y los dos sprites llevan siempre Y = 79 y X = 112. En el centro no
lo tapa ninguna ventana: la ficha va de la fila 13 para abajo (en los modos
0x12 y 0x17, en la 20) y los carteles de posicion, destino y sitio no pasan
de la fila 3. El precio, que el usuario acepto: moviendo el cursor cada paso
repinta, como antes; y como MI_MUEVE lo limita a cinco casillas por segundo,
la sensacion es la de siempre.

**Cambiar de unidad en el menu de la casilla iba disparado.** Con fuego sobre
una casilla con varias unidades, `ELIGE_ENTRE_LAS_DE_LA_CASILLA` (0x7751)
entra en un bucle en el que arriba y abajo pasan de una unidad a otra y cada
paso repinta la vista; en el original cada vuelta de ese bucle costaba un
repintado entero (tres por segundo), y con la cache -la posicion no cambia- va
a mas de cuarenta: con la tecla pulsada era imposible parar en la que se
queria. Decision del usuario: *que solo reaccione al primer toque, y hasta que
no se deje de pulsar y se vuelva a pulsar la tecla, no vuelva a reaccionar*.
`MI_ELECCION` sustituye al `call LEE_LOS_MANDOS` (0x066D) de 0x7758 y solo deja
pasar arriba y abajo en la vuelta en que se pulsan (guarda el mando de la
vuelta anterior y pasa lo pulsado ahora y no entonces); fuego y la tecla 1, que
son las dos salidas del bucle, pasan tal cual y borran lo apuntado, asi que la
proxima entrada empieza de cero. Tres bytes mas del juego.

**Verificado.** El recorrido de la sonda (`tools/omsx_coteja_vista.tcl`) se
alargo de 50 a 60 vueltas: en la 49 el cursor se *teleporta* (`reg HL`, igual
en las dos ROMs) a la casilla de encima de las cuatro unidades de (fila 15,
columna 23), las mas cercanas a la entrada, baja una casilla sobre ellas -la
ficha debajo, el cursor en el centro- y entra en el menu de la casilla, donde
se pulsa arriba cinco vueltas seguidas, se suelta y se vuelve a pulsar una.
Resultado (`make verifica_vista_parche`, exit 0 en la VG-8020 y en el NMS
8250; `make verifica_vista`, exit 0): la nueva pinta el trozo 20 veces en 60
vueltas -al entrar, tras cada menu y en cada paso-, todos los instantes con el
mismo encuadre que la vieja, y en el menu de la casilla los dos toques son **2
cambios de unidad en la nueva y 6 en la referencia** (una por vuelta con la
tecla pulsada). Como en esa casilla hay cuatro unidades, 6 y 2 dejan elegida
la misma, y las fichas de despues -`vista_o`, `vista_d`- salen identicas pixel
a pixel. Sin emulador, `tools/corre_nombres.py` ejecuta tambien `MI_ELECCION`
(diez combinaciones de mando y estado) y comprueba que cualquier paso repinta
y que los sprites no se mueven de (7, 5). Y `tools/omsx_paso_cursor.tcl`: 10
casillas en 2 s con la derecha pulsada, en las dos maquinas.

Y la medida (`make mide_vista`): la vuelta en reposo pasa de 83.037 a 83.544
ciclos, 42,8 vueltas por segundo.


### El mapa general, dibujado al montar la ROM — HECHO y VERIFICADO

`DIBUJA_EL_MAPA` (0x8166) tarda **13.950.631 ciclos, 3,9 segundos**, y no se
paga una vez: se paga **cada vez que se vuelve al mapa**, o sea cada vez que se
sale de la vista de cerca. Medido por tramos, el 89 % es recorrer casillas
estampando pixeles de dos en dos:

    borrado del lienzo (0x4000-0x5AFF)   1.013.827    7 %
    pasada de terreno alto (126 x 93)    5.217.626   38 %
    pasada de terreno bajo (127 x 96)    6.927.925   51 %
    sube el bitmap al VDP (0x05BD)         172.270   1,3 %
    atributos (PINTA_TODOS_LOS_ATRIBUTOS)  364.348   2,7 %

O sea que cambiar el FORMATO de la subida no arreglaria nada: subir la pantalla
es el 1,3 %. Y **a tiles el mapa ocuparia MAS**, no menos: contadas sobre el
volcado, las 768 celdas usan 455 patrones distintos (188/169/128 por tercio,
que caben en los 256 de cada uno, o sea que seria posible), y son 3.880 B de
patrones + 3.880 de color + 768 de nombres = **8.528 B frente a los 6.144 del
bitmap**. En la vista de cerca la tabla de nombres ganaba porque la pantalla de
caracteres YA existia en la RAM; aqui el mapa es un dibujo a media resolucion
con tramas y casi ninguna celda se repite.

Lo que si quita los 3,9 segundos es no dibujarlo: **llevarlo ya dibujado en la
ROM**.

#### Por que se puede

El dibujo del terreno depende SOLO del nibble bajo del byte de mapa: las dos
pasadas hacen `and 00fh` y los vecinos de `PINTA_CASILLA_UNIDA` tambien. Y lo
que se mueve durante la partida -las unidades- no son pixeles sino ATRIBUTOS:
`REPINTA_LOS_EJERCITOS` (0x6AAF) solo toca 0x5800-0x5AFF.

Asi que la pregunta es si el nibble bajo cambia mientras se juega. **Medido, no
supuesto** (`make verifica_terreno`): se reproduce la partida grabada de Araubi
sobre la cinta, se vuelca el mapa (0xCC00, 13.260 bytes) al entrar en el bucle
de partida y otra vez al final, y se comparan. Resultado: **ni un nibble bajo
cambia** -ni entre el principio y el final, ni contra el mapa tal y como sale
de la cinta-; cambian 28 casillas y solo en los bits 0x80 y 0x20, que son las
banderas de unidad. Y del watchpoint: mientras se juega, en el mapa solo
escribe el bucle de 0x7FF0, el que baja el bit 7.

#### Quien lo dibuja: `tools/mapa_general.py`

Los 6.144 bytes no se capturan del emulador: se DIBUJAN, transcribiendo las
rutinas del juego instruccion a instruccion -`PINTA_TERRENO_ALTO` (0x80BD),
`PINTA_TERRENO_BAJO` (0x8044), `PUNTO_A_DIRECCION` (0x7E4F), `PINTA_EL_PUNTO`
(0x7E86), `PINTA_SIN_MOVER` (0x7EF5), `ELIGE_EL_RELLENO` (0x7E7A)- sobre el
mapa que sale de la cinta. Lo que garantiza que la transcripcion es fiel no es
leerla: es que el resultado se coteja **byte a byte con el volcado del emulador
en 0x81C1**, que es donde el juego acaba de dibujarlo.

**Y ahi aparecio una errata del juego.** La primera version daba 497 bytes
distintos, todos en casillas de terreno 10. La causa: el bucle de 0x8188 hace

    sub 00ah / inc b / call nc,PINTA_TERRENO_ALTO

y el `inc b` **pisa el flag Z**. `PINTA_TERRENO_ALTO` lo guarda con `push af` y
lo recupera con `pop af` creyendo que trae el del `sub`, asi que su primer
`jr z` -el que elegiria el dibujo de 0x848F para el tipo 10- prueba en realidad
si B+1 vale cero, cosa que no pasa nunca (B va de 93 a 1). Resultado: **el
dibujo de 0x848F no se usa jamas** y el terreno 10 se pinta con el de 0x8477,
el mismo que los tipos 14 y 15. Los tres `dec a` de despues si ponen el Z, y
por eso los tipos 11, 12 y 13 aciertan. El acarreo, que es lo que mira el
`call nc`, sobrevive al `inc b`: por eso el fallo solo se ve en el dibujo.

#### Como se hace en el cartucho

El lienzo viaja comprimido con ZX0 -**6.144 -> 3.034 bytes**- y lo descomprime
la misma rutina que las pantallas finales (`src/cartucho/finales.asm`), que
ahora tiene dos entradas y un cuerpo comun: traer el bloque de la ROM a un
bufer de RAM cruzando de banco, y llamar a ZX0 con las cuatro paginas en RAM.

El parche del juego son **tres bytes en 0x816B**: el `ld hl,04000h` del `ldir`
que ponia el lienzo a cero, por un `jp MAPA`. `MAPA` hace lo unico de
0x816B-0x81C0 que se nota fuera -`BORRA_PANTALLA` con atributo 0 y la trama de
arranque en el operando de 0x7E75-, descomprime y sigue en 0x81C1, que es donde
el juego sube el lienzo al VDP. El `ldir` sobraba: `BORRA_PANTALLA`, dos
instrucciones mas alla, borra ese mismo tramo.

    DIBUJA_EL_MAPA   13.950.631 -> 2.496.488 ciclos   (3,897 s -> 0,697 s)

y de esos 2,5 millones, la mitad es el borrado de la pantalla que ya estaba:

    BORRA_PANTALLA     853.964      la VRAM y el lienzo a cero, como antes
    copia del banco    236.944      los 3.034 bytes de la ROM al bufer
    dzx0               591.874      los 6.144 del lienzo
    0x81C1 a 0x81E7    813.525      subir el bitmap, los atributos y los paneles

#### Verificado

- `tools/mapa_general.py` == el volcado del emulador en 0x81C1, **byte a byte**,
  y la ROM nueva deja ese mismo lienzo (`make verifica_mapa`, exit 0 en la
  VG-8020 y en el NMS 8250; `make verifica_mapa_parche`, exit 0).
- Sin emulador: `tools/corre_finales.py` EJECUTA la rutina del cartucho -con su
  mapper, sus ranuras y su ZX0- y lo que deja en 0x4000 es el lienzo dibujado,
  con el cartucho en cualquiera de las cuatro ranuras primarias, sin tocar
  nunca la pila con el cartucho puesto y sin pasarse de los 6.144 bytes.
- El bloque de la ROM, descomprimido con la otra implementacion de ZX0, da
  exactamente ese lienzo (`test_cada_bloque_de_la_rom_devuelve_lo_que_traia_la_cinta`).
- Las dos cintas -la original y la de Araubi- dibujan el MISMO mapa: el parche
  cambia textos, tiles y la ficha, pero no el terreno.

### El guante del mapa, como sprite — HECHO y VERIFICADO

En el mapa general el cursor es un guante que senala, y en la cinta es un
**sprite por software**: ocho lineas de dos bytes de dibujo (0x6345) con su
mascara (0x6355), desplazadas al pixel y estampadas en el lienzo de 0x4000,
guardando antes los 24 bytes de fondo que tapan (0x62FF) para devolverlos al
moverse. Y por eso el bucle de partida subia un recuadro de 4x3 celdas a la
VRAM **en cada vuelta** (`REFRESCA_EL_CURSOR`, 0x07C3). Medido en un NMS 8250:

    REFRESCA_EL_CURSOR        3.935 ciclos, en TODAS las vueltas
    estampar el guante        6.375 ciclos, en las vueltas en que se mueve

Ahora son **dos sprites de hardware**, uno por color, con su dibujo en un PNG
que cualquiera puede repintar (`src/cartucho/guante.png`, `tools/guante.py`),
igual que el cursor de la vista de cerca. Son los sprites 2 y 3, detras de los
dos de la vista, y sus patrones van detras de los seis de aquel.

Dos parches del juego, cuatro bytes en total:

- **0x7F57**, la primera linea del bucle de partida: el `call REFRESCA_EL_CURSOR`
  pasa a llamar a `MI_GUANTE`, que sube ocho bytes de atributos de sprite -Y =
  fila menos 1, porque el VDP pinta el sprite una linea por debajo de su Y- y,
  la primera vez despues de cada escondida, los 64 de patrones.
- **0x6575**, dentro de `MUEVE_EL_CURSOR`: el `push hl` con el que empezaba el
  estampado pasa a ser un `ret`. Lo de antes se queda -la cuenta de la direccion
  de pantalla, que 0x7F8B lee de 0x64DA para saber si el disparo cae en un
  panel-; lo que se va es meter el dibujo en el lienzo, guardar el fondo y armar
  el borrado de 0x64D9, que asi se queda en `ret` para siempre.

**El guante no se queda flotando sobre lo que venga.** Cualquiera que vaya a
pintar pasa por `VRAM_A_ESCRIBIR` (0x044B), que ya lleva el guardian de la
vista: ahi se aparca el guante en Y = 209 y se apunta que hay que volver a
subirlo. La vuelta siguiente del bucle de partida lo vuelve a poner, asi que en
el mapa esta siempre y fuera de el no esta nunca.

Lo unico que cambia de aspecto: el sprite lleva SU color y ya no el de la celda
que tapa, asi que sobre los paneles -atributo 0x78, papel blanco- el guante se
ve amarillo y no blanco. Sobre el mapa, que es atributo 0x30 en las 768 celdas,
no se distingue: el cotejo pixel a pixel da CERO diferencias.

    una vuelta del bucle de partida   69.009 -> 60.156 ciclos
                                      51,9 -> 59,5 vueltas por segundo

#### Verificado

- `make verifica_mapa` (exit 0): en tres instantes del bucle de partida, el
  lienzo de la ROM nueva es el de la vieja **con el guante borrado** -lo que
  haria `BORRA_EL_CURSOR` con los 24 bytes de 0x62FF-, los sprites 2 y 3 estan
  donde dice el cursor, sus patrones son los de `guante.png`, y **lo que se ve
  en pantalla es identico pixel a pixel**, compuesto como lo compone el VDP.
- De paso, lo que nadie mira: la VRAM de cada ROM es exactamente su lienzo
  subido. Con la pantalla encendida NO lo es, ni en una ni en otra: el
  `call 005bdh` del juego va mas rapido de lo que el TMS9918 admite y pierde
  bytes, con cartucho y sin el. Por eso la sonda apaga la pantalla.
- Sin emulador, `tools/corre_nombres.py` ejecuta `MI_GUANTE` y el guardian: la
  primera vez sube 64 + 8 bytes y despues solo 8; la fila 0 da Y = 255, que el
  TMS9918 entiende como -1; y el guardian lo aparca y apunta que hay que volver
  a ponerlo, sin pisar BC, DE ni HL.


### El panel File/Memo/Time, con el color de la vista — HECHO y VERIFICADO

En la cinta parcheada de Araubi el texto de la vista de cerca se escribe con el
atributo **0x70** -negro sobre amarillo claro, el operando de 0x763E- y el panel
del mapa general se quedaba en el **0x78** de la cinta original, negro sobre
blanco. Dos pantallas del mismo juego con dos colores de panel.

Ahora el panel toma el de la vista, leido de 0x763F: en la cinta original los
dos ya son 0x78 y no cambia nada; en la parcheada son cuatro bytes.

**Y son cuatro, no uno, porque el atributo del panel es como el juego lo
reconoce:**

    0x8167   el operando del `ld a,078h` de 0x8166: con el se escriben los textos
    0x7F9A   el del `cp 078h` de 0x7F99 (PULSA_EN_EL_PANEL): si el disparo cae en
             una celda con ese atributo, es un panel. Sin esto los paneles dejan
             de responder
    0x6AB6   el del `ld a,078h` de 0x6AB5 (REPINTA_LOS_EJERCITOS): el UNICO
             atributo que se respeta al limpiar; todo lo demas vuelve a 0x30.
             Sin esto el panel pierde el color en el primer repintado
    0x6AE1   el del `ld a,070h` de 0x6AE0: la marca de unidad

El cuarto es una **colision**: 0x70, el atributo de la vista, es tambien con el
que se marca donde hay una unidad. Si el panel se lo queda, la marca tiene que
irse a otro, y el que se queda libre es justamente el del panel, 0x78. O sea
que los dos atributos se INTERCAMBIAN: el panel pasa a amarillo claro, como la
vista, y las unidades a blanco. Y ganan: antes eran amarillo claro sobre el
amarillo oscuro del mapa y apenas se distinguian.

#### Verificado

`make verifica_mapa_parche` (exit 0): las dos pantallas siguen siendo IDENTICAS
pixel a pixel despues de aplicarle a la ROM vieja esa permutacion de dos
atributos -y solo esa- sobre los atributos de la RAM y sobre la tabla de color
de la VRAM. O sea que el cambio es exactamente el intercambio y nada mas.
`make verifica_mapa` (la cinta original, donde no cambia nada) tambien exit 0.
Y siete tests, sobre las DOS cintas: que el atributo sale de 0x763F y no de una
constante, que la marca se aparta solo si choca, y que los cuatro sitios van
juntos y caen sobre lo que la cinta trae.

## 8) Gollum, los orcos y el cursor de la batalla — HECHO y VERIFICADO

Cuatro cosas que pidio el usuario el 2026-09-18, con la ROM unificada ya
jugandose.

### Gollum es un hobbit: un byte

La raza de una unidad es el **nibble bajo de `0xBD00+n`**, en el bloque alto, o
sea que viaja en la cinta. Gollum es la unidad **21** y tenia el tipo **8**.

Lo que no estaba a la vista: el tipo 8 **no tiene figura propia**. En
`NUMEROS_DE_LA_FIGURA` (0x8CF7), al montar la batalla, del tipo salen el dibujo,
la vida y el golpe de la figura; y ahi mismo, en **0x8D0E**, hay un
`cp 008h / ld a,004h`: el tipo 8 se dibuja **como el 4**, el enano. Asi que
Gollum peleaba con la figura del enano y con su propia linea en la tabla de
nombres.

Con el tipo **6** es un hobbit en todo -nombre, figura, fuerza (`0x6D47` +
tipo*16) y costes de terreno (`0x6D37`)-, igual que Sam, Merry y Pippin.

**Y el 8 se queda sin nadie**, lo cual es medible: de las 256 unidades de
`0xBD00`, la 21 era la unica de ese tipo. Comprobado tambien con el juego
corriendo (`tools/omsx_ficha_gollum.tcl`): `0xBD15` = 6, los mismos que las
unidades 6, 7 y 8, y su ficha se sigue pintando con su nombre.

### `Orc` -> `Orco` y `Orcs` -> `Orcos`, sin mover un byte

Las dos tablas de razas se recorren contando bits de fin desde su base, asi que
una cadena puede cambiar de largo **mientras el total no cambie**: detras de
cada tabla empieza otra cosa. Cada plural necesitaba un byte mas, y cada uno
salio de un sitio distinto:

- **plural**: del **espacio de relleno de `Enanos `**, que ya venia en la cinta
  porque el ingles era `Dwarves` (7 letras) y `Enanos` son 6;
- **singular**: de la **entrada 8**, la que decia `Gollum`. Desde el cambio de
  arriba no la lee nadie, asi que se queda en `Enano`, que es lo que ese tipo
  dibujaba de todas formas. (Eso es **en la cinta**, donde el tipo 8 se queda
  vacio para siempre. En el CARTUCHO lo ocupa Tom Bombadil y esa entrada pasa a
  decir `Eterno`: apartado 9.)

Y de paso se quito el parche que traducia `Brand III` por `Bardo III`: Brand,
nieto de Bardo el Arquero y rey de Valle, se llama igual en las dos lenguas. Es
un ejemplo de lo de siempre: **deshacer es quitar la entrada, no cambiarla por
otra**. Ahora un test exige que el parche no toque ni un byte de esa lista.

### El cursor de la batalla va al reloj, no al bucle

`MUEVE_EL_CURSOR_DE_BATALLA` (0x8E0D) corre el cursor **una casilla por vuelta**
del bucle de batalla, asi que su velocidad es la del bucle. Al hacer que el
tablero subiera al VDP solo lo que cambia, la vuelta paso de 0,3170 a 0,1068 s
-de 3,2 a 9,4 casillas por segundo- y el cursor se volvio ingobernable. Es el
mismo problema que arreglo `MI_MUEVE` en el mapa, y se arregla igual:
**`MI_CURSOR_BATALLA`** sustituye su `call LEE_LOS_MANDOS` de **0x8E10** y deja
pasar las cuatro direcciones una vez cada **16 cuadros**; el disparo y la tecla 1
pasan siempre, que ya tienen su espera a soltar en `PULSA_EN_LA_BATALLA`.

Medido en una batalla de verdad, en la MISMA batalla y la misma partida -se
deshace el parche escribiendo los tres bytes originales en la RAM, que un cotejo
entre dos ROMs no valdria porque las batallas no son iguales-, con
`tools/omsx_cursor_batalla.tcl` en un VG-8020:

    con MI_CURSOR_BATALLA    3,00 casillas/s   (el bucle a 7,0 vueltas/s)
    como en la cinta         4,00 casillas/s   (el bucle a 4,0 vueltas/s)

Lo que importa no es la resta: es que **la velocidad deja de depender de lo
rapido que vaya la batalla**. En esa misma pasada, sin el limite el cursor
habria ido a 7 casillas por segundo.

**Y costo una medida tirada a la basura**: la primera version plantaba el cursor
en (2,2) nada mas empezar la batalla y contaba cuanto avanzaba. Daba 18 casillas
CON el parche y 9 sin el, o sea que el parche "aceleraba" el cursor. Un punto de
observacion sobre 0x8E0E enseno por que: **0x9141, dentro del montaje de la
batalla, recoloca el cursor en el centro (16,16)** despues de que la sonda lo
plantara. Se contaba desde donde no estaba. La sonda espera ahora a 0x9141 y
ademas cuenta los pasos con el punto de observacion, que no depende de donde
empiece ni de si topa con el borde.

### Los sprites, repintados y editables

`tools/editor_sprites.html` (que sustituye a `editor_cursor.html`) edita los
**cuatro** sprites de hardware del cartucho -los tres cursores y el guante-, con
los dibujos dentro y **un trozo real de la pantalla donde vive cada uno** debajo:
el mapa general para el guante y la vista de cerca para los cursores. En el
lienzo el fondo va apagado con un velo y entero en la previa, porque el guante
era amarillo y negro sobre un mapa amarillo y negro y el dibujo se perdia dentro
del terreno.

Dos cambios de aspecto:

- **el guante, azul**: relleno azul claro y contorno blanco, en vez de amarillo
  oscuro y negro, que eran los colores del propio mapa;
- **los cursores, casi transparentes**: el plano de detras era un **bloque opaco
  de 16x16** que tapaba el terreno; ahora es el contorno del trazo -sus ocho
  vecinos-, asi que se ve el mapa alrededor y el cursor se sigue leyendo sobre
  cualquier fondo. De 208 pixels de bloque a 128 de halo en el de mirar.

El cotejo del mapa (`make verifica_mapa_parche`) tuvo que ajustarse, y el ajuste
es mas fuerte que lo que habia: antes exigia las dos pantallas identicas pixel a
pixel; ahora exige **cero diferencias fuera del guante** y que las de dentro
sean **exactamente los pixels que enciende `guante.png`**. Si el guante se
moviera de sitio, se comiera una fila o dejara de pintar algo, se ve. Da 38
comprobaciones y 0 fallos, con 85 pixels distintos y 0 fuera.

## 9) Dos heroes mas: Tom Bombadil y Radagast — HECHO y VERIFICADO

Lo pidio el usuario el 2026-09-18: Tom Bombadil de clase enano y Radagast como
Gandalf pero un par de puntos por debajo. Antes de tocar nada se midio si cabia,
y lo que salio fue que **cabe, pero no donde uno esperaria**.

### Lo que el binario dice: no hay sitio en ninguno de los dos lados

**Las 256 ranuras de unidad estan TODAS ocupadas.** Censados los siete arrays
paralelos del bloque alto (0xB900 columna, 0xBA00 fila, 0xBB00/0xBC00 destino,
0xBD00 tipo y bando, 0xC000-0xC300 los seis valores, 0xC500 efectivos): cero
ranuras en (0,0) -que es como el juego dice "esta no esta en el mapa"- y
ninguna de las 96 formaciones aliadas con 0 efectivos. No hay ranura de regalo.

**Y la lista de nombres esta encajonada.** Los 24 nombres de `BUSCA_EL_NOMBRE`
(0x6981) viven en 0x6B46 y ocupan **181 bytes clavados**. Delante lleva la
cabecera del menu de entrega del Anillo -0x6B3D, renglones y columnas- con
"Vuelve" detras; y **en 0x6BFB justo** empieza la red de caminos de 64 puntos
que lee 0x69C6. Los 22 bytes que piden los dos nombres nuevos no caben.

### Lo que si se puede: mudarla

Solo **cinco sitios** miran esa lista, y eso es lo que la hace mudable:

| donde | que es |
|-------|--------|
| 0x6982 | el puntero de `BUSCA_EL_NOMBRE` |
| 0x6985 | el largo, que es el tope del `cpir` que cuenta separadores 0xB7 |
| 0x7302 | el puntero a la cabecera, en `MENU_DE_ENTREGA` (0x72F5) |
| 0x72F8 y 0x7309 | las dos escrituras del byte de CORTE, el 0xB7 de "Faramir" |

Mas dos topes por numero de unidad, que suben de 0x17 y 0x18 a **0x1A**:
0x6E19 (a quien persigue) y 0x6F2D (la ficha). Barridos todos los `cp` por
numero de unidad del listado, el resto son el filtro de bando (0x16, 0x17 y
0x78), que no tiene nada que ver.

La lista mudada -cabecera, "Vuelve" y 26 nombres- vive en
`src/cartucho/nombres.asm` y viaja con el resto del codigo nuevo.

### Por que esto es del CARTUCHO y no de la cinta

Porque en la cinta **no hay donde meterla**. El mapa de RAM
(`tools/mapa_ram.py`) deja claro que la unica RAM de fiar es la **ajena a la
cinta**, y un IPS solo puede escribir donde la cinta carga. Los huecos que se
ven dentro de los bloques son bytes que la cinta trae y que nadie leyo *en la
partida medida*, que no es lo mismo que "nadie los lee nunca". Asi que los dos
heroes son cosa del cartucho, como la musica, el mapa dibujado, la vista de
cerca y los sprites. **El IPS de la cinta no se toca**: sigue en 2.088 bytes y
50 registros.

### De donde salen las dos ranuras

De la **0x18 y la 0x19**, que eran dos pelotones de enanos plantados los dos en
(22,12). Van pegadas detras de Saruman (0x17), que es lo que deja la lista de
nombres contigua y el numero de nombre igual al numero de unidad.

**Y no se pierde ni un enano**: sus 31 + 8 hombres se reparten entre las cuatro
formaciones de (23,15) -0x1A a 0x1D-, que pasan de 12, 4, 19 y 24 a 22, 14, 29
y 33. Un test lo exige sumando los efectivos de todas las formaciones de tipo 4
antes y despues.

### Los dos tipos ya existian

No hubo que inventar figura ni fuerza. La raza es el nibble bajo de 0xBD00+n:

- **Tom Bombadil es del tipo 8**, el que dejo libre Gollum al pasar a hobbit y
  que aqui se rebautiza **"Eterno"** (ver mas abajo). El dibujo, la vida y el
  golpe salen de `NUMEROS_DE_LA_FIGURA` (0x8CF7), la fuerza de 0x6D47 + tipo*16
  y los costes de terreno de 0x6D37.
- **Radagast es del tipo 0**, Mago, el de Gandalf, con el mismo trato de figura
  fuerte que le da `CUATRO_SI_ES_TIPO_0_1_O_7` (0x8DC0).

Y lo de "un par de puntos menos" sale gratis, porque los seis valores son **por
ranura**. Medida la escala sobre los 22 heroes de la cinta, va de 1 a 10 y
Gandalf es el techo: Valioso 8, Habil 10, Duro 10, Bravo 6, Energico 158,
Decidido 192.

**Tom Bombadil lleva los seis valores de Gandalf, clavados**, y no escritos a
mano: se copian de la ranura 0 al montar la ROM, asi que no pueden separarse si
algun dia cambia Gandalf. En pantalla las dos fichas salen con los mismos
numeros -192, 010, "Es muy", "Virtuoso"-; lo unico que cambia es el nombre.
**Radagast va dos puntos por debajo en los cuatro** (6, 8, 8, 4) y tambien en
Energico y Decidido. Los dos tests comprueban la RELACION -igualdad en uno,
resta en el otro-, no una constante escrita al lado.

Y la escala de la ficha, medida sobre `REPARTE_EN_OCHO` (0x6E88), que parte el
valor en ocho tramos de dos y elige adverbio en 0x7D9A:

| valor | adverbio |
|-------|----------|
| 0-1 | `No es muy` |
| 2-3 | `No` |
| 4-5 | `No muy` |
| 6-7 | `Es algo` |
| 8-9 | (sin adverbio) |
| 10-11 | `Es muy` |
| 12-13 | `Muy` |
| 14-15 | `Realmente` |

Los dos tramos de arriba **no los alcanza nadie en la cinta**, porque ningun
valor pasa de 10; con los nibbles solo se llega ahi poniendolos a 12 o mas.
Queda apuntado por si algun dia se quiere a alguien fuera de la escala. (Y no
hay riesgo de desbordar el contador de Decidido: `SUMA_UN_MES_A_LOS_CONTADORES`
(0x834A) **satura en 255**.)

### Donde caen

Medido sobre la tabla de sitios (0x7A5E) y el mapa descomprimido
-`0xCC00 + (x+1)*102 + (y+1)`-, con los costes de 0x6D47 por delante: los
terrenos 1 y 2 no los pisa nadie.

| heroe | casilla | terreno | por que ahi |
|-------|---------|---------|-------------|
| Tom Bombadil | (50,28) | 10 | el Bosque Viejo: al este de Los Gamos (48,27) y al oeste de Bree (53,25) |
| Radagast | (83,30) | 0 | Rhosgobel: al este del Anduin (la columna de terreno 3 en x=80), al oeste del Bosque Negro (los 13 empiezan en x=86) y al norte de Dol Guldur (84,39) |

### El tipo 8 pasa a llamarse "Eterno"

Gollum dejo el tipo 8 vacio al pasar a hobbit, y de las 256 unidades no se
quedo ninguna ahi (medido). Ahora lo ocupa Bombadil, que de enano no tiene
nada, y el tipo se rebautiza en las dos tablas de raza.

**De donde sale el byte.** Las dos tablas se recorren contando terminadores
-bit 7 en la ultima letra- desde su base, y detras de cada una empieza otra
cosa: el singular arranca justo donde acaba el plural, y detras del singular
esta "Mujer". O sea que **una entrada puede cambiar de largo mientras el total
no cambie**. "Eternos" pide un byte mas que "Gollum" y "Eterno" uno mas que
"Enano", y los dos salen del mismo sitio: **la entrada 7**, que es texto
muerto. El tipo 7 son **Sauron y Saruman y nadie mas** (medido sobre las 256), y
los dos TIENEN NOMBRE, asi que su raza no la lee nadie: las dos unicas rutinas
que miran estas tablas -`FORMACION_SIN_NOMBRE` (0x6F57) y `NOMBRE_DEL_TIPO`
(0x6DF6)- solo entran con unidades SIN nombre. Es la misma jugada que dejo el
byte de "Orco", y por la misma razon.

| tabla | entradas 7 y 8, antes | despues | total |
|-------|----------------------|---------|-------|
| plural (0x7D30) | `Mago` + `Gollum` | `Mag` + `Eternos` | 10 = 10 |
| singular (0x7D5D) | `Mago` + `Enano` | `Mag` + `Eterno` | 9 = 9 |

**Y va en el cartucho, no en el IPS**, porque el tipo 8 solo esta habitado en el
cartucho: en la cinta sigue vacio desde que Gollum es hobbit.

### Lo que el cambio de tipo NO hace, y lo que si

**"Eterno" no se ve en pantalla.** La raza solo sale en la ficha de una unidad
SIN nombre -`ARMA_LA_FICHA` mira `cp 01Ah` en 0x6F2C y, si la tiene, copia el
nombre- y Bombadil es la 0x18, que tiene el suyo. Es exactamente lo que le pasa
a Gollum con "Hobbit" desde que es del tipo 6, y ya estaba apuntado en la
cabecera de `tools/omsx_ficha_gollum.tcl`. El rebautizo es de coherencia.

**En la batalla se sigue dibujando como enano.** `0x8D0E` lleva un
`cp 008h / ld a,004h`: el tipo 8 no tiene figura propia y se pinta con la del 4.
Es lo mismo que le pasaba a Gollum antes de ser hobbit.

**Lo unico que cambia de verdad son dos de los dieciseis terrenos.** La fila de
0x6D47 + tipo*16 -que es a la vez el coste de andar y, desde `MI_FUERZA`, la
fuerza en el terreno donde se pelea- solo se diferencia de la del enano en el
14 y el 15, los de montana: el enano paga **3 y 2** y el Eterno **15 y 3**. Todo
lo demas, identico. Esa fila esta libre y se puede ajustar si algun dia se
quiere que el Eterno ande a su manera.

### Lo que NO hacen: llevar el Anillo

`MENU_DE_ENTREGA` corta la lista antes de Gollum -mete un 0 en el 0xB7 de
"Faramir" y se lo devuelve al salir-, y los dos nuevos van detras de Saruman.
Asi que **no salen en el menu de entrega**. Es una decision del usuario, no un
descuido: mover el corte metaria tambien a Gollum, a Sauron y a Saruman, y
ademas el menu es de 9 columnas y "Tom Bombadil" son 12 letras.

### La opcion `--heroes`, y por que va aparte de `--vista`

Las dos ranuras se parchean con `--heroes` y los nombres con `--vista`, que es
donde viaja `nombres.asm`. **No es capricho**: la ROM de referencia con la que
se cotejan el mapa general y la vista de cerca
(`work/war_parche_sin_vista.rom`) se monta sin `--vista`, y si no llevara las
mismas unidades los cotejos compararian **dos partidas distintas**. Con las dos
ROMs jugando la misma partida, la unica diferencia vuelve a ser lo que el
cotejo quiere medir.

Se vio en el sitio: la primera version metia todo junto y el cotejo del mapa
canto 87 pixels distintos fuera del guante, y el de la vista 12 fallos y 44
celdas. No eran un fallo del parche -eran las marcas de los dos heroes nuevos y
los numeros de las formaciones de enanos, que la sonda de la vista mira a
proposito-, pero un cotejo que no puede distinguir eso no sirve.

### Lo comprobado

- **En el emulador, con el juego corriendo** (`tools/omsx_ficha_gollum.tcl`,
  VG-8020): el cursor a su casilla, fuego, y el buffer de texto de la ficha
  (0x7C17) leido. Sale **"Tom Bombadil"** en la unidad 24 y **"Radagast"** en la
  25. Y la regresion, que es lo que de verdad prueba que la mudanza no rompio
  nada: **Gandalf, Gollum y Brand III** siguen saliendo con su nombre.
- **El cotejo del mapa general** pasa de 38 a **50 comprobaciones, 0 fallos**, y
  las doce nuevas exigen que las dos ROMs marquen la celda que le toca a cada
  heroe por su casilla -columna `x >> 2`, fila `(y - 4) >> 2`, como lo calcula
  `MARCA_UNA_UNIDAD` (0x6AC5)-. Esa es la prueba de que un heroe nuevo SE VE en
  el mapa general.
- **El cotejo de la vista de cerca** (`make verifica_vista_parche`), en verde.
- **Nueve tests nuevos** (`TestLosDosHeroesNuevos`), sobre la RAM que deja el
  interprete del plan, no sobre lo que el codigo dice que hace. Y las
  direcciones salen del plan, no escritas a mano.
- **Y muerden**: puesto Radagast en una casilla de mar, el test del terreno
  canta; cambiada UNA letra de "Gimli" en la lista, cantan tres.
- **El kit sin Python** monta la ROM identica byte a byte.

## 10) La marca de las unidades: un dibujo, no un color

### Lo que habia

En el mapa general una unidad **no es un dibujo**. `REPINTA_LOS_EJERCITOS`
(0x6AAF) devuelve los 768 atributos de la pantalla del Spectrum al 0x30 del
fondo -respetando solo el del panel, que es como el juego lo reconoce- y le
escribe **UN BYTE** al atributo de la celda de cada unidad (0x6AE0). Luego los
sube todos con `ATRIBUTOS_A_VRAM` (0x0604).

O sea que una unidad es **una celda de otro color**, y de ahi el problema que
se ve jugando: dos unidades en celdas vecinas se funden en una mancha en la
que no se puede contar cuantas hay.

### Lo que hay ahora

`MI_MARCAS` (nombres.asm) le estampa ademas un **dibujo de 8x8** a esa celda.
De fabrica es el **Anillo**: los ocho bytes del caracter 0x5F de la fuente del
juego, el mismo que el parche pinta en la ficha del Portador. No esta
inventado, y se puede repintar en `src/cartucho/marca.png`.

### POR QUE NO HACE FALTA GUARDAR UNA COPIA DEL MAPA

Estampar pixeles obliga a saber **borrarlos** cuando la unidad se mueve, y de
ahi salio la idea de guardar una copia limpia del lienzo -6.144 bytes- en la
RAM libre. **No hace falta: esa copia ya existe.**

El juego es un port del Spectrum y mantiene su pantalla emulada en 0x4000, en
la **pagina 1, que es RAM durante toda la partida** (el puente conmuta la
pagina 2, no esta). Asi que basta con estampar **solo en la VRAM** y no tocar
el lienzo: borrar una marca es volver a subir a la VRAM los ocho bytes que el
lienzo ya tiene. Cuesta **2 bytes por marca** -la fila y la columna- en vez de
6.144, y es correcto por construccion: el lienzo es la verdad y la VRAM su
copia, asi que restaurar desde el lienzo siempre devuelve lo que el juego cree
que hay en pantalla.

### El ritmo, que es donde estaba la trampa

Los dos bucles van a **39 y 37 ciclos por byte**. Con la pantalla encendida el
TMS9918 no admite dos accesos a la VRAM a menos de unos 29 y se le caen bytes:
le pasa a `PANTALLA_A_VRAM` (0x05BD) y a `RECUADRO_A_VRAM` (0x0702), que van a
**22** y pierden casi 4.000 bytes de los 6.144 (ver mas arriba). Por eso
ninguna de las dos se reutiliza aqui, aunque las dos hacian justo lo que hacia
falta: **una marca con un byte caido se quedaria sucia hasta el repintado
siguiente**, que son 256 vueltas mas tarde.

### Lo que cuesta

`REPINTA_LOS_EJERCITOS` **no corre por fotograma**: el bucle de partida mueve
UNA unidad por vuelta (0x6719) y solo la llama cuando el contador da la
vuelta, o sea **una vez cada 256**. Y lo que ya se pagaba ahi son los 597.698
ciclos de `ATRIBUTOS_A_VRAM`. Esto anade unos 110.000: un 18 % sobre una
rutina que corre una vez cada 256 vueltas.

### EL JUEGO NO MUEVE NADA HASTA QUE SE ARRANCA LA PARTIDA

Medido al montar la sonda, y explica por que la primera no volcaba nada:
**729.052 vueltas del bucle de partida y un unico repintado**, el de la
entrada. Al entrar al mapa, 0x81DE-0x81E4 desvia al retardo de 0x8274 los dos
`call` del bucle -el de mover la unidad siguiente (0x7F65) y el del reloj
(0x7F6B)-, asi que mientras el jugador no pulsa abajo del todo no se mueve una
sola unidad ni avanza el calendario. `PULSA_ABAJO_DEL_TODO` (0x81EA) se los
devuelve.

## 11) El fondo de la batalla, segun el terreno

Todas las batallas se peleaban sobre el mismo **verde**, se diera el encuentro
en un llano, en la montana o cruzando un rio. Y el color salia de **un unico
byte**: el `ld a,020h` con el que `COMPRIME_EL_MAPA` (0x9394) remata antes de
saltar a `BORRA_PANTALLA`.

Medido antes de tocar nada (`tools/omsx_fondo_batalla.tcl`): un punto de
observacion sobre los atributos del tablero durante una batalla entera da **UN
SOLO escritor**, el `lddr` de 0x7F37, o sea ese mismo camino. El atributo del
centro del tablero sale 0x20: tinta negra sobre papel verde oscuro.

**Y sale barato porque el juego ya sabe donde se pelea.** Al montar la batalla,
0x9024-0x902F lee la casilla y guarda su nibble bajo -la clase de terreno- en
**0x8DEA**, y la llamada a `COMPRIME_EL_MAPA` esta **tres instrucciones
despues**. `MI_FONDO` solo tiene que leer ese byte y buscar el color en una
tabla de dieciseis.

### Los grupos de terreno, medidos

El terreno es el nibble bajo del byte de mapa, de 0 a 15; **15 de las 16 clases
aparecen** en el mapa (la 5 no se usa nunca). Y un SOLO byte por (raza,
terreno) en la tabla de 0x6D47 hace dos cosas: el coste de moverse
(`COSTE_DEL_TERRENO`, 0x68AB; negativo = intransitable) y la fuerza en combate
(`FUERZA_DE_LA_TROPA`, 0x8DE4). Agrupando las columnas identicas salen **nueve
grupos**:

| terrenos | efecto | % del mapa | color |
|---|---|---|---|
| 0, 4, 5, 8, 9, 10, 11 | cuesta 3 a todos | 47,1 % | verde oscuro |
| 1, 2 | **intransitable**: no hay batalla | 34,8 % | (azul) |
| 14 | 3 a Enano y Orco, 15 al resto | 7,8 % | rojo oscuro |
| 13 | 3 a Mago, Elfo y Hobbit | 4,0 % | verde claro |
| 3 | 3 a Mago y Elfo (el Hobbit no) | 3,4 % | azul claro |
| 6 | cuesta 2 a todos | 2,6 % | amarillo oscuro |
| 15 | 2 a Enano y Orco | 0,2 % | verde oscuro |
| 12 | 15 a todos | 0,1 % | verde oscuro |
| 7 | 3 solo al Orco | 1 casilla | verde oscuro |

**El MSX1 no tiene marron**: este motor alcanza 12 de los 15 colores -el
atributo del ZX pasa por `ATRIBUTO_A_COLOR` (0x049F) con dos tablas de ocho- y
se quedan fuera el verde medio, el rojo medio y el gris. Para la montana se
eligio el rojo oscuro (#B95E51), que es lo que mas se le parece.

## 12) LAS FIGURAS ROTAS: el VDP se comia una cuarta parte del tablero

Lo vio el usuario jugando -*"los ejercitos se rompen"*- y se midio cotejando el
bufer del juego contra la VRAM en una batalla de verdad:

    1.544 bytes de 4.096 no llegaban a la VRAM   (37,7 % del tablero)
    245 celdas de 512, todas en las filas 2..17

La causa es la de siempre: con la pantalla encendida el TMS9918 no admite dos
accesos a la VRAM a menos de unos 29 ciclos, y **las dos rutinas del juego que
suben el tablero van a 22**: `BITMAP_A_VRAM` (0x05BD), el tablero entero, y
`RECUADRO_A_VRAM` (0x0702), cada ficha que cambia.

**El parche de la batalla no causo el fallo: lo DESTAPO.** En la cinta el
tablero se resubia entero en cada vuelta, asi que lo que se caia se arreglaba
solo a la siguiente (y se caia otra cosa). Al subir solo lo que cambia, cada
ficha se sube UNA vez y el byte que se cae se queda roto. De hecho, la ROM
**sin** el parche sale mucho peor: el tablero aparece casi vacio y hasta el
texto de arriba sale corrupto.

Arreglado subiendo a 37 ciclos por byte, como el resto del parche. Cuesta
227.000 ciclos una vez por batalla y unos 5.900 por vuelta -un **1,3 %** sobre
los 462.251 que cuesta una vuelta-. Cotejo despues: **0 bytes de 4.096**.

### La trampa: un contador pisado

La primera version bajaba de 1.544 a 791 y ahi se atascaba. Lo que lo delato no
fue el numero sino **como** fallaba: la mitad de las celdas estaban distintas
ENTERAS (8 bytes de 8, o sea nunca subidas), iban **en parejas** -una ficha son
dos celdas- y **todas en las filas 8 a 17**, la mitad de abajo.

Era un fallo de la rutina nueva: `OCHO_LINEAS` usa B de contador y lo deja a
cero, asi que el `djnz` del bucle de celdas no contaba y solo se subia el primer
tercio. **Un byte perdido por el VDP y una celda sin subir se ven igual en
pantalla, pero no en el cotejo**: la pista fue que fallaran los ocho bytes.

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
