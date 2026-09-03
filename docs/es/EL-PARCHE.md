# El parche

Siete cambios, **197 bytes**, ninguno fuera de la tabla y ninguno desplazado:
cada parche mide exactamente lo mismo que lo que sustituye, así que ninguna
dirección del juego se mueve.

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
| `0xA1E7` | alto | 36 | los cuatro tiles del Ojo de Sauron |

Las direcciones son de **ejecución**. El bloque «medio» corre desde `0x5E00` y
el «alto» desde `0x9E00`.

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

## El IPS

`make ips` saca **`war_parche.ips`**: 249 bytes en ocho registros, con sólo lo
que cambia. Comprobado en el sitio —y en las pruebas— que **aplicado sobre
`war.tsx` devuelve la cinta parcheada byte a byte**.

Se reparte eso, no el juego.

## Las comprobaciones

`make test` son 23, y no son de adorno. Entre ellas:

- que **`orig` y `nuevo` miden igual** en las siete entradas, o sea que nada se
  desplaza;
- que cada entrada **cae dentro de su bloque**;
- que los bytes de la tabla son **exactamente** lo que sale de ensamblar
  `src/parche/ficha_valores.asm` y `src/parche/icono_enemigo.asm` con pasmo;
- que los tres ganchos de la segunda tanda **apuntan donde toca** dentro de la
  rutina nueva;
- que el parche **no escribe en la tabla de cuadros de `0x77B5`**, que es la
  trampa que se cuenta en [Hallazgos](HALLAZGOS.md);
- que los cuatro tiles del Ojo van al hueco que estaba a cero y **con el mismo
  atributo de color que el icono aliado**;
- y que el IPS del repositorio **reconstruye la cinta parcheada**.
