# El cartucho

El juego venía en cinta y tarda **seis minutos y medio** en cargar. Esto lo
convierte en un cartucho que arranca en **nueve segundos** sin cambiarle un
solo byte al juego.

**Aquí tampoco hay ninguna ROM.** Se monta de tu propia cinta:

    make rom          # war.rom, de la cinta original
    make rom_parche   # war_parche.rom, de la cinta ya parcheada

Las dos salen de 64 KB, del tipo **ASCII16**, y ninguna se reparte: son el
juego entero en otro envase (ver el [aviso legal](https://github.com/antxiko/WarinMiddleEarth-MSX-Patch/blob/main/AVISO-LEGAL.md)).

    openmsx -machine Philips_VG_8020 -carta war.rom -romtype ascii16

## La idea: no tocar el juego, imitar al cargador

El cartucho no es una conversión: es un **cargador**. Deja la RAM exactamente
como la deja el cargador de la cinta y salta al mismo sitio, `0x0190`, donde el
propio juego recoloca sus bloques como hace siempre.

| lo que deja | dónde |
|---|---|
| bloque bajo | `0x0190` |
| bloque medio | `0x3F4F` |
| bloque alto | `0x88B8` |
| buzón de POKEs | `0x012C`, a cero |
| pila | `SP = 0xFDE8` |

Eso es lo que permite comprobarlo: si la RAM es la misma, el juego no puede
notar por dónde entró.

## Cómo está hecho

**77 bytes de arranque** en la ROM (`src/cartucho/cargador_rom.asm`): la
cabecera `AB`, el banco 0, copiar el resto a RAM y saltar.

**Un stub de 977 bytes** que corre en `0xD800`
(`src/cartucho/cargador_ram.asm`): busca RAM en las páginas 2, 1 y 0 e
interpreta un **plan de 52 operaciones** de ocho bytes. El plan no está escrito
a mano: lo genera `tools/haz_rom.py` de la disposición real de la ROM y lo deja
también en `work/plan.json`, para que las comprobaciones no tengan que suponer
nada.

Los datos van de `0x0800` a `0xF727`. Sobran **2.264 bytes**.

## Las dos cosas que costaron

**La página 1 es la ROM mientras se carga.** Con el cartucho puesto,
`0x4000`-`0x7FFF` es el cartucho, y ahí caen **14.400 bytes** del bloque medio
(`0x4000`-`0x783F`). No hay dónde ponerlos... salvo en la **VRAM**, que durante
la carga está libre: se copian allí, se quita el cartucho de la página 1 y
vuelven. El búfer llega hasta `0x383F` y **pisa la tabla de nombres y las de
sprites**, así que ésas se escriben dos veces, antes y después.

**El juego hereda la pantalla del BASIC.** Sólo escribe el registro 7 del VDP y
**nunca** la tabla de nombres: cuenta con el `COLOR 1,1,1:SCREEN 2` de las dos
líneas de BASIC que la cinta ejecuta antes de cargar nada. Un cartucho arranca
sin ese BASIC, así que hay que reproducirlo. No se dedujo: se **midió** en la
cinta con `tools/omsx_estado_cinta.tcl`.

    VDP R0-R7   02 E0 06 FF 03 36 07 01
    PSG         R7 se lee 0x3F, R11 = 0x0B
    VRAM        tabla de nombres identidad, 32 sprites en Y=209

## Las ranuras

La BIOS trae `ENASLT` para cambiar lo que hay en una página, y sirve para las
páginas 2 y 1 mientras la página 0 siga siendo la BIOS. Para la página 0 y a
partir de ahí hace falta un clon propio, y con un cuidado: **no puede voltear
la página 3**, que es donde vive el stub. Escribe `0xFFFF` sólo si la primaria
de destino es la misma de la página 3.

Probado con la RAM en **ranura expandida** (Philips NMS 8250, 3-2), que es el
caso que rompe los cargadores mal hechos.

## Qué está comprobado

`tools/omsx_verifica_rom.tcl` arranca la máquina con el cartucho y vuelca lo
mismo que se volcó cargando la cinta, en los mismos dos instantes;
`tools/coteja_rom.py` lo compara byte a byte.

| instante | lo que se compara |
|---|---|
| en `0x0190` | los bloques como caen de la cinta, antes de recolocar |
| en `0x5E00` | los tres bloques recolocados, la VRAM entera (16 KB), VDP R0-R7 y PSG R0-R13 |

Resultado: **todo lo exigido coincide**, con `war.rom` en Philips VG-8020,
Philips NMS 8250, C-BIOS MSX1 y C-BIOS MSX2, y con `war_parche.rom` en la
VG-8020 contra los volcados de la cinta parcheada.

En MSX2 el registro 1 se lee `0x60`: el V9938 no tiene el bit de 4K/16K del
TMS9918. Se acepta, y se dice.

Ocho comprobaciones más en `tests/test_cartucho.py`. La fuerte es un
**intérprete del plan escrito aparte, en Python**, que lleva la cuenta de la
RAM, de la VRAM y de qué hay en la página 1 en cada paso: si el plan intentara
escribir en `0x4000`-`0x7FFF` con el cartucho puesto, salta ahí sin necesidad
de emulador.

## Qué no está comprobado

**Nadie ha jugado una partida entera desde el cartucho.** Se ha visto arrancar,
el menú y, tras pulsar `0`, el mapa. Eso es todo.

Y el cartucho **no tiene música**: el juego es mudo en cinta y sigue siéndolo
aquí. Es la ampliación evidente y está apuntada en
[preguntas abiertas](PREGUNTAS-ABIERTAS.html).
