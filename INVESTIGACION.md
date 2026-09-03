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

| sin parche | con parche |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/mapa_con_parche.png) |

Tres huestes de Sauron estan ahi mismo y no se dibujaba ninguna; con el parche
aparecen las tres siluetas, que son 34 unidades enemigas. Contado sobre el mapa
en RAM: **de 19 casillas con unidad se pasa a 28**, y en la pantalla cambian
**doce celdas de caracter**, o sea tres dibujos de dos por dos y nada mas.

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
**ANILLO_CON_PLAZO (0x666D)**, que pone el anillo igual y ademas escribe el
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
  atributos de color**: el Ojo tapa el fondo igual que el casco, con la misma
  tinta negra sobre papel blanco;
- los dos aliados de la esquina siguen con su casco.

El icono, ampliado y releido de la cinta ya parcheada:

| la unidad aliada (tiles 81-84) | la enemiga (tiles 111-114) |
|---|---|
| ![](docs/imagenes/icono_aliado.png) | ![](docs/imagenes/icono_ojo_de_sauron.png) |

**El color del ZX va por celda de 8x8, no por pixel**, asi que darle tinta roja
al Ojo seria un byte por cuadrante. Se ha dejado en negro sobre blanco, como
pidio quien lo dibujo.

---

## Estado

| peticion | estado | evidencia |
|----------|--------|-----------|
| 1 · enemigos visibles | hecho, verificado | 136 enemigas sembradas; 9 casillas de 10 (la 0x16 y la 0x17 las salta el juego) |
| 2 · valores de la unidad | hecho, verificado | los seis numeros coinciden con la RAM |
| 3 · plazo del Anillo | hecho, verificado | el 0x8333 -255 meses- escrito al lado del anillo |
| 4 · el Ojo de Sauron | hecho, verificado | 9 casillas marcadas, 12 celdas cambian, 0 atributos tocados |

**197 bytes en siete cambios, ninguno fuera de la tabla y ninguno desplazado.**
`make test` = 21 en verde.

## Como se reparte

`make ips` saca **`war_parche.ips`**, que lleva solo los bytes que cambian -194
en ocho registros- y se aplica sobre tu propia cinta. Comprobado: aplicado sobre
`war.tsx` da un fichero identico byte a byte al que saca `make parche`.

## Lo que queda abierto

- **Nadie ha jugado una partida entera** con el parche puesto. La ficha se ha
  visto en Gandalf y en Frodo, no en todos los tipos de unidad.
- **El plazo solo se ve abriendo la ficha del portador.** Un medidor siempre en
  pantalla pide enganchar el bucle de partida (0x7F57) y escribir cada cuadro:
  es codigo nuevo con mas riesgo, y queda apuntado como ampliacion.
- **Las unidades 0x16 y 0x17 siguen invisibles**, porque el bucle de siembra las
  salta a proposito y no se ha averiguado por que.
