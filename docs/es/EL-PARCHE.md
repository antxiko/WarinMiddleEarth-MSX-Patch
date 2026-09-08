# El parche

Veintidós entradas, **393 bytes**, ninguna fuera de la tabla y ninguna
desplazada: cada parche mide exactamente lo mismo que lo que sustituye, así que
ninguna dirección del juego se mueve.

## La tabla

| dirección | bloque | bytes | qué |
|---|---|---|---|
| `0x7FD1` | medio | 1 | el tope del bucle de siembra, `0x78` → `0x00` |
| `0x708A` | medio | 3 | trampolín a la rutina de los valores |
| `0x6600` | medio | 76 | `MUESTRA_LOS_VALORES` |
| `0x664C` | medio | 61 | la siembra por bando, el dibujo por bando y el plazo |
| `0x7FC9` | medio | 5 | gancho de la siembra |
| `0x770A` | medio | 10 | gancho del dibujo |
| `0x6F77` | medio | 5 | gancho del anillo |
| `0xA1E7` | alto | 36 | los cuatro tiles del Ojo de Sauron, dibujados en el lienzo |
| `0x7A79`…`0x7BC7` | medio | 91 | los diez toponimos del mapa |
| `0x6BA5` | medio | 9 | `Brand III` → `Bardo III` |
| `0x7DF0` | medio | 7 | `Valioso` → `Integro` |
| `0x7D07` | medio | 45 | las razas en plural |
| `0x7D3A` | medio | 44 | las razas en singular |

Las direcciones son de **ejecución**. El bloque «medio» corre desde `0x5E00` y
el «alto» desde `0x9E00`. Los diez toponimos son diez entradas sueltas: `0x7A79`,
`0x7AA5`, `0x7AB2`, `0x7B0D`, `0x7B28`, `0x7B34`, `0x7B4B`, `0x7B5D`, `0x7B7F` y
`0x7BC7`.

## Los tres formatos de texto

Nada se desplaza, así que el sitio de cada cadena manda. Y aprieta distinto
según dónde viva:

- **La tabla de sitios (`0x7A5E`).** Cada registro es
  `[x][y][2+ancho*filas][ancho<<4|filas][texto]`, sin terminador. El cuarto byte
  es el **tamaño del cartel** que se dibuja, y el texto lo rellena entero, fila a
  fila: un nombre nuevo tiene que medir **exactamente ancho × filas**. Por eso
  `Cavada ` + `Grande ` llena el cartel de 7×2 donde iba `Michel `/`Delving`.
- **Las cuatro listas de cadenas pegadas**, con el **bit 7 en la última letra**
  (razas en plural `0x7D06`, en singular `0x7D39`, carteles de bando `0x7D6A` y
  adverbios `0x7D9A`). Se llega a la cadena N contando terminadores, así que
  **dentro** de una lista una cadena sí puede cambiar de largo mientras el total
  no cambie. Eso es lo que paga las palabras largas: `Brujo ` → `Mago` libera dos
  bytes y sale dos veces en cada lista, los cuatro justos que necesitan
  `Elf` → `Elfo` y `Hum` → `Hombre`.
- **La lista de los 24 nombres propios (`0x6B46`)**, separados por `0xB7`.

## Cómo se aplica

El desensamblado no se toca. Se parte de los **cuerpos** que `make extract` saca
de tu cinta (`work/*.raw`, los mismos bytes sin la envoltura del formato
Spectrum), se les aplica la tabla de `tools/parchea.py` y se vuelve a montar la
cinta reenvolviendo cada bloque con su bandera delante y su XOR detrás.

Cada entrada de la tabla lleva **los bytes que espera encontrar**. Si no están,
`make parche` aborta: no es esa cinta. Y al terminar se comprueba que, fuera de
los rangos de la tabla, el cuerpo es idéntico al original.

## Dónde vive el código nuevo

Los 137 bytes de código nuevo —76 de la rutina de los valores y 61 de la segunda
tanda— están escritos **encima del motor del altavoz del ZX Spectrum**, en
`0x6600`-`0x6688`.

Ese motor lo trajo la conversión entero y **no lo llama nadie**: ni una
instrucción de los cinco listados apunta a `0x6600`, y los cuatro sitios que
piden un efecto de sonido llaman a `0x65FF`, que es un `ret` pelado. Del PSG del
MSX sólo se escriben dos registros, el 7 y el 14, y los dos son para leer el
joystick. Este juego es mudo, y su silencio nos deja 276 bytes de sitio.

## Los gráficos, en tres PNG

**Todos** los dibujos del bloque alto se editan con un editor de imágenes. Están
en `src/parche/`, a tamaño real y **sin separación**: un píxel del PNG es un
píxel del juego.

| lienzo | qué lleva | dónde vive | tamaño |
|---|---|---|---|
| `tiles_del_mapa.png` | los **128 tiles** del mapa, de 8 × 8 | `0x9E00` | 128 × 64 |
| `sprites_de_batalla.png` | los **176 sprites** de batalla, de 16 × 8 con máscara | `0xA2E8` | 176 × 128 |
| `fuente.png` | los **128 caracteres**, de 8 × 8 | `0xC800` | 128 × 64 |

Se repinta lo que se quiera y `make parche` hace el resto: compara los lienzos
con la cinta y cada dibujo que haya cambiado sale solo como una entrada más de
la tabla, del grupo `graficos`, con su `orig` y su `nuevo` de la misma longitud,
igual que las escritas a mano. Si no se tocan, no aparece ni una entrada de más.
Hoy la única que sale es el Ojo de Sauron, y da **exactamente** los mismos 36
bytes que cuando estaban escritos a mano en el código.

| orden | qué hace |
|---|---|
| `make graficos` | dice qué dibujos cambian respecto a la cinta, sin montar nada |
| `make parche` | los convierte en entradas del parche y arma la cinta |
| `make lienzos` | **rehace** los PNG desde la cinta, o sea que se lleva por delante lo que esté dibujado encima; hay que insistirle con `--rehaz` |

### Cómo se pinta cada hoja

- **Los tiles** llevan **atributo del ZX** detrás del dibujo (bits 0‑2 la tinta,
  3‑5 el papel, 6 el brillo y 7 el parpadeo), y de ahí salen las dos reglas del
  Spectrum: **dos colores por casilla** de 8 × 8 —el famoso *attribute clash*— y
  **los dos del mismo brillo**, porque el bit de brillo es uno solo para los dos.
  El negro es la excepción: es `#000000` con brillo y sin él. Si una casilla se
  salta alguna, la herramienta **para y dice cuál es y por qué**, en vez de
  elegir por su cuenta.
- **Los sprites** no llevan atributo: llevan **máscara**. Tienen tres estados
  —**transparente**, negro y blanco— y el transparente se pinta de **magenta**,
  para que se vea y no se pierda al aplanar la imagen; borrar con la goma
  también vale. Van **apilados de dos en dos**, que es como encajan en figuras
  de 16 × 16 (eso último es una lectura de la imagen, no una rutina encontrada:
  cada sprite sigue yendo a su dirección, calculada aparte).
- **La fuente** es lo más simple: un bit, un píxel, blanco sobre negro. El
  índice **es** el código del carácter, así que la `A` está en el 65.

### Lo que no se toca

Un dibujo que se vea *exactamente* igual que el de la cinta se devuelve con
**sus bytes de siempre**, sin recodificar. Por eso abrir un PNG y guardarlo sin
cambiar nada no mueve un solo byte, ni siquiera en los que no se pueden
reconstruir mirando la imagen: el tile **85** lleva tinta blanca sobre papel
blanco, con ocho bytes de dibujo escondidos debajo, y del **111 al 127** son
negro sobre negro. Sin esa regla, cada ida y vuelta ensuciaría el parche con
cambios que nadie ha pedido.

La paleta de cada hoja va **dentro** del PNG, así que un editor en modo indexado
la ofrece hecha. Si aun así entra un color de fuera —por trabajar en color
verdadero, por ejemplo—, se toma el más parecido y se avisa por pantalla de cuál
era, cuántos píxeles y por qué color se ha cambiado.

## El IPS

`make ips` saca **`war_parche.ips`**: 487 bytes en dieciocho registros, con sólo
lo que cambia. Comprobado en el sitio —y en las pruebas— que **aplicado sobre
`war.tsx` devuelve la cinta parcheada byte a byte**.

Se reparte eso, no el juego.

## Las comprobaciones

`make test` son 66, y no son de adorno. Entre ellas:

- que **`orig` y `nuevo` miden igual** en las veintidós entradas, o sea que nada
  se desplaza;
- que cada entrada **cae dentro de su bloque**;
- que los bytes de la tabla son **exactamente** lo que sale de ensamblar
  `src/parche/ficha_valores.asm` y `src/parche/icono_enemigo.asm` con pasmo;
- que los tres ganchos de la segunda tanda **apuntan donde toca** dentro de la
  rutina nueva;
- que el parche **no escribe en la tabla de cuadros de `0x77B5`**, que es la
  trampa que se cuenta en [Hallazgos](HALLAZGOS.md);
- que los cuatro tiles del Ojo van al hueco que estaba a cero y **con el mismo
  atributo de color que el icono aliado**, y que el lienzo los sigue dando
  **byte a byte** como cuando estaban escritos a mano;
- que sacar cada lienzo desde la cinta y volver a leerlo devuelve **los bytes
  intactos**, y que hoy no cambia **ningún otro dibujo** de los 432 que hay entre
  las tres hojas;
- que los tres códecs dibujan **píxel a píxel** lo mismo que
  `tools/render_graficos.py`, que es el que hace las láminas de la web: si aquí
  se leyera el zigzag de los sprites o el atributo de los tiles de otra manera,
  los dibujos no coincidirían;
- que una casilla con **tres colores** o que **mezcle brillos** se rechaza con el
  número de casilla y el motivo, que los sprites y la fuente **no** cargan con
  esa limitación, y que el lector de PNG traga lo que sale de un editor de
  verdad —indexado, gris, RGB, RGBA, de 1 a 16 bits y los cinco filtros—;
- que el sitio de cada dibujo dentro de un lienzo **no se solapa con ningún
  otro**, o repintar uno estropearía a su vecino;
- que los parches de texto **no cambian el número de cadenas** de una lista (si
  metieran o quitaran una, todas las de detrás se correrían de índice y el juego
  diría «Orcs» donde pone «Enanos»);
- que **ninguna base absoluta** —las catorce que el código usa para entrar en los
  textos— cae dentro de un parche;
- que, aplicada la tabla, **los 29 carteles del mapa siguen midiendo ancho ×
  filas** y las cuatro listas de cadenas se siguen leyendo enteras, incluidas las
  que el parche no toca;
- y que el IPS del repositorio **reconstruye la cinta parcheada**.
