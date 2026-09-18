# War in Middle Earth (MSX) — Araubi's patch

> ## Playable, and not finished
>
> Everything below is in place and measured in openMSX, but **nobody has played
> a whole game with the patch on**. What is known to be missing is listed at the
> bottom. Read it before you judge a screenshot.

A byte patch for the MSX cassette of **War in Middle Earth** (Melbourne House /
Dro Soft, 1989), built on top of the
[commented disassembly](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly).
It does the three things **Araubi** asked for on the forum: make enemy units
visible, show the numeric value of each of a unit's attributes, and surface how
long the Ring-bearer has left. Plus a fourth: the enemy now has an icon of its
own, so you can tell the two sides apart. And a fifth: the **map names and the
race names finish their translation into Spanish**.

[README en español](README.es.md) · Full write-up: [INVESTIGACION.md](INVESTIGACION.md)

## The tape is not here

No cassette image is distributed, only the patch work (see
[LEGAL-NOTICE.md](LEGAL-NOTICE.md)). You supply your own `war.tsx` (sha256
`13c63632…b1d81208`), and:

    make extract     # pulls the block bodies out of your tape into work/
    make parche      # applies the table and writes war_parche.tsx
    make ips         # and war_parche.ips, the patch on its own
    make test        # the checks
    make rom         # war.rom, the game as a cartridge (not distributed either)
    make rom_parche  # war_parche.rom, the cartridge with the patch

**`war_parche.ips` is in this repository**: it carries only the bytes that
change — our own code and the drawing of the Eye — so you can apply it to your
own cassette with any IPS tool, or with `python3 tools/ips.py --aplica war.tsx
war_parche.ips war_parche.tsx`.

`war_parche.tsx` is the patched cassette, the same size as the original, ready
for a real MSX1 (`openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx`).

## What it changes

It lands in the game's middle block (which runs at `0x5E00`) and in the map's
tile table in the high block: **1,578 bytes across 195 table entries**. Of those,
**29 are written by hand** — 568 bytes of code, pointers and text — and **166
fall out of the canvases**, 1,010 bytes of repainted drawings. Each one is checked
against the bytes it expects before writing — nothing shifts, and `make parche`
fails if a single byte changes outside the table (`tools/parchea.py`).

**1 · Enemy units become visible.** The map keeps a "someone is here" bit for
each cell, and `RECENTRA_EL_MAPA` (0x7FAC) re-plants it unit by unit — but its
loop stops at unit `0x78`, exactly where the enemy side begins, so the enemy is
never planted and never drawn. Changing the loop's limit from `0x78` to `0x00`
(**one byte, at 0x7FD1**) makes it walk all 256 units. Verified: **136 enemy
units get planted where zero did before.**

| without the patch | with it |
|---|---|
| ![](docs/imagenes/mapa_sin_parche.png) | ![](docs/imagenes/mapa_con_parche.png) |

**2 · Every attribute shows its number.** A unit's sheet lists six qualities —
Valioso, Habil, Duro, Bravo, Energico, Decidido — as adverb + adjective ("very
brave"), never as a number. A new routine (`MUESTRA_LOS_VALORES`, 76 bytes),
written over the **ZX Spectrum beeper engine at 0x6600 that nothing in this port
ever calls**, reads the six values (from `0xC000`/`0xC100`/`0xC200`/`0xC300`) and
prints them as digits in the sheet. It is hooked by a three-byte trampoline at
`0x708A`. Verified against the real values: all six match.

**3 · The Ring-bearer's deadline, next to the ring.** The game's clock counts
ticks, days and months; every month it decrements the operand at **0x8333** — set
to 255 when the game starts — prints *"El Anillo corrompe al que lo usa"*, and
`jp z,DERROTA`. That operand is literally how long you have left, and the game
never shows it. `MARCA_AL_PORTADOR` draws the ring character at 0x7C46, the last
column of the sheet's second row; the three columns to its left were free, and
that is where the number now goes.

![](docs/imagenes/plazo_del_anillo.png)

**4 · The enemy gets the Eye of Sauron.** With change 1 the enemy showed up
wearing *your* helmet, which is half a fix. The drawing routine only ever looks
at the map byte, so it cannot know which side a unit belongs to — but **bit 5 of
that byte was free** (measured: zero uses across all 13,260 cells). It now marks
"this one is theirs", and four new tiles at the tail of the 0x9E00 table (111 to
114, which were all zeros) hold the icon.

| enemies with your helmet | enemies with the Eye |
|---|---|
| ![](docs/imagenes/enemigas_con_casco.png) | ![](docs/imagenes/ojo_de_sauron.png) |

**5 · The text finishes its translation.** Animagic's conversion left the map's
place names in English and several race names truncated. Thirteen entries
change: ten place names (`Bywater` → `Delagua`, `Michel Delving` →
`Cavada Grande`, `Dale` → `Valle`…), the races (`Brujo` → `Mago`, `Elf` →
`Elfo`, `Hum` → `Hombre`, `Orc` → `Orco` and `Orcs` → `Orcos`), the sheet's four
adjectives (`Habil` → `Firme`, `Valioso` → `Virtuoso`, `Duro` → `Valiente`,
`Bravo` → `Fuerte`) and its last line (`Aliado a la Sociedad` →
`Aliado a la Comunidad`).

Character names are **left alone**: `Brand III` — Bard the Bowman's grandson,
king of Dale — is spelled the same in Spanish, and an earlier patch mistranslated
it.

Not one byte moves. A place-name record carries the **size of its signpost**
(`ancho<<4 | filas`) and the text fills it exactly, so a new name has to measure
the same: `Cavada ` + `Grande ` fills the 7×2 sign that held `Michel `/`Delving`.
The race names live in two lists walked by counting terminator bits, so inside a
list a string *may* change length — and that is what pays for the longer words:
`Brujo ` → `Mago` frees two bytes twice per list, which is exactly the four that
`Elf` → `Elfo` and `Hum` → `Hombre` need.

Same cell, same unit, original tape and patched one:

| without the patch | with it |
|---|---|
| ![](docs/imagenes/textos_sin_parche.png) | ![](docs/imagenes/textos_con_parche.png) |

The two-row signpost, the one that could have broken, holds `Cavada `/`Grande `
in the same 7×2 box:

| without the patch | with it |
|---|---|
| ![](docs/imagenes/cartel_sin_parche.png) | ![](docs/imagenes/cartel_con_parche.png) |

**6 · The map, repainted.** The map's 128 8×8 tiles are exported to a PNG at
full size, repainted in any image editor and read back in: **122 of the 128** go
into the patch on their own, as 103 entries of the `graficos` group. And with
them came the finding that **the canvas was lying**: the tile carries a ZX
attribute, but `ATRIBUTO_A_COLOR` (`0x049F`) translates it into an MSX colour
before it is drawn, with two tables of eight, so only **twelve of the MSX's
fifteen colours** can be asked for. The text now sits on the frames' khaki, which
is one byte at `0x763F`.

| the cassette's tiles | repainted |
|---|---|
| ![](docs/imagenes/tiles-del-mapa.png) | ![](docs/imagenes/tiles-repintados.png) |

**7 · Gollum is a hobbit.** A unit's race is the low nibble of `0xBD00+n`, and
Gollum — unit 21 — had type 8, which was his and nobody else's (measured: the
only one of the 256). And type 8 was not just a name: in battle `0x8CF7` takes
the figure, the health and the hit from the type, and `0x8D0E` has type 8 drawn
**as type 4**, so Gollum turned up wearing the dwarf's figure. With type 6 he is
a hobbit in everything — name, figure, strength and terrain costs — just like
Sam, Merry and Pippin. **One byte.**

**8 · Two more heroes: Tom Bombadil and Radagast.** Cartridge only, and for a
measured reason: all 256 unit slots are taken, and the list of 24 names
(`0x6B46`) is **exactly 181 bytes**, with the road network starting at `0x6BFB`
right behind it. Not one byte to spare, so the whole list is **relocated** into
the free RAM the cartridge carries — five pointers and two per-unit-number
limits — and grows to 26 names. The tape cannot do this: there is no dependable
RAM to put it in, and an IPS can only write where the tape loads.

The two slots come from **0x18 and 0x19**, two dwarf platoons both standing on
(22,12); **their 39 men are redistributed** among the four formations on
(23,15), so not a single soldier is lost. Bombadil takes **type 8** — the one
Gollum vacated when he became a hobbit, renamed here to **"Eterno"** — and
lives in the Old Forest at (50,28), east of Buckland; Radagast is **type 0**
(Wizard), Gandalf's own type, and lives at Rhosgobel, (83,30), between the
Anduin and Mirkwood. **Bombadil carries Gandalf's own six values**, copied from
his slot when the ROM is built rather than written out by hand, and Radagast's
sit **two points below**.
The one thing they cannot do is bear the Ring: the delivery menu cuts the list
short before Gollum.

The byte "Eterno" needs in each of the two race tables comes out of **entry 7**,
which is dead text: type 7 is Sauron and Saruman and nobody else, and both have
names, so their race is never read. Each table's total stays put, which is the
one thing that cannot change. Note that a race only shows on the record card of
an *unnamed* unit, so "Eterno" never actually reaches the screen — the same
thing that happens to Gollum with "Hobbit" — and in battle type 8 is still drawn
with the dwarf's figure, because it has none of its own (`0x8D0E`).

None of the images above are screen captures: the game re-uploads the screen to
the VDP constantly, so two photographs of the *same* state, three seconds apart,
already differ in 37 % of their pixels. They are drawn from the ZX screen buffer
the game keeps in RAM, dumped at a fixed instant. Full evidence, addresses and
the openMSX output are in [INVESTIGACION.md](INVESTIGACION.md).

## From tape to cartridge

The game itself is untouched: `make rom` builds from your tape **`war.rom`, a
64 KB ASCII16 MegaROM** with a 77-byte boot and a 1,105-byte stub that leave RAM
exactly as the tape loader leaves it and jump to the same place (0x0190). From
the patched tape, `make rom_parche` builds `war_parche.rom`. Neither is
distributed. The game only ever writes VDP register 7 and inherits everything
else from BASIC's `SCREEN 2`, so the cartridge reproduces what was measured on
the tape; and since page 1 is the ROM while loading, the 14,400 bytes of the
middle block that land there go through VRAM. Checked byte for byte — RAM, VRAM,
VDP and PSG — on four machines (`make verifica_rom`, `make verifica_rom_parche`):
all identical to the tape. Details in [INVESTIGACION.md](INVESTIGACION.md).

The cartridge **uses ZX0**, by Einar Saukas, for the images: 26,112 bytes of
screens in 12,600. Its licence asks that you say so, and it is said here and in
[LEGAL-NOTICE.md](LEGAL-NOTICE.md); the compressor itself is not distributed.

And **the close-up view goes through the name table, with the cursor as a
sprite and a fixed window**: instead of expanding the character screen into a
bitmap and pushing 12,288 bytes to VRAM on every loop, it pushes the 768 bytes
of the name table, because each cell's byte already is the pattern index; and
the map chunk is only redrawn when the cursor (two 16x16 sprites, editable in
`src/cartucho/cursor.png` with `tools/editor_sprites.html`, which opens in the
browser and shows the drawing over the actual screen) moves: the cursor stays in the centre and the map moves, as in the
original. Measured on an NMS 8250: from 3.2 to 43.2 loops per second at rest,
with the cursor at five cells per second and the picture checked against the
old one (`make verifica_vista_parche`). One thing the faster loop broke and is
fixed: in the menu that cycles through the units sharing a cell, up and down act on the key press, not while the key is held.
And another one found later: **the battle cursor** moves one cell per loop, so
once the board only uploaded what changed it became ungovernable; it now follows
the clock and not the loop, one cell every sixteen frames. Measured in a real
battle: **3.00 cells per second with the limit and 4.00 without it**, with the
loop at 7 turns per second — which without a limit is 7 cells.

The **sprites are editable** with `tools/editor_sprites.html`, which opens in
the browser and shows them over a piece of the screen they live on: the map's
gauntlet was yellow and black over a yellow and black map — you could not see it
— and is now blue, and the three cursors stopped being an opaque 16x16 block and
are down to the stroke and its outline, with the terrain showing around them.

And **the overview map is no longer drawn: it is decompressed**. Walking its
23,500 cells stamping pixels took 3.9 seconds, and you paid it every time you
came back from the close-up view. But that drawing never changes -it depends
only on the low nibble of the map byte, and units are attributes, not pixels-
so the cartridge carries it ready-made, compressed with ZX0 (6,144 bytes into
3,034), and unpacks it in place: **from 3.9 to 0.7 seconds**. It is drawn by
`tools/mapa_general.py`, a transcription of the game's own routines checked
byte for byte against the emulator; that the terrain does not change while you
play is measured on Araubi's recorded game (`make verifica_terreno`), not
assumed. That check also turned up a 1988 bug: an `inc b` clobbers the flag
that picks the terrain drawing, so one of the five 8x8 drawings is never used.

And **the map's pointing hand is a real sprite**. It used to be a software
sprite stamped into the canvas, with its 24 background bytes saved and a 4x3
cell box pushed to VRAM on every loop; now it is two hardware sprites, editable
in `src/cartucho/guante.png`. The game loop goes from 51.9 to 59.5 loops per
second, and what you see is identical pixel for pixel (`make verifica_mapa`).

And **the File/Memo/Time panel takes the close-up view's colour**. On the
patched tape the view's text is light yellow and the map's panel stayed white;
now they match. It is not one byte but four, because the panel's attribute is
how the game recognises it -to tell whether a click lands on it, and to spare
it when clearing- and because that yellow was the unit marker's: the two
attributes swap, so units turn white and stand out far better against the map.

And **every unit on the map now carries a drawing, not just a colour**. On the
tape a unit is not a drawing at all: `REPINTA_LOS_EJERCITOS` changes the
ATTRIBUTE of its cell and nothing else, so two units in neighbouring cells
blur into one smear you cannot count. That cell now also gets an 8x8 drawing
-out of the box the **One Ring**: the eight bytes of character 0x5F of the
game's own font, the one the patch draws on the Ring-bearer's card-, and it is
repainted in `src/cartucho/marca.png` with `tools/editor_marcas.html`, which
also lets you pick the cell's two colours.

No copy of the map was needed to rub the drawing out when a unit moves, which
is what it looked like: **that copy already exists**. The game keeps its
emulated Spectrum screen at 0x4000 -page 1, which is RAM throughout the game-,
so the drawing is stamped **into VRAM only** and erasing it means sending back
up the eight bytes the canvas already holds. Two bytes per marker instead of
6,144. Checked on the emulator with the screen ON, which is how it is played
(`make verifica_marcas`): every marked cell carries the drawing exactly, no
other cell does -that is the erase working- and the canvas stays clean. The
check calls itself USELESS if no cell lost its marker between the two
repaints, so it cannot pass without having proved anything.

And **the battle's background takes the colour of the terrain** it is fought
on, instead of the same green every time: plain dark green, forest light green,
river light blue, road dark yellow and mountain dark red -the closest thing to
brown an MSX1 can give, having none-. It comes out of a single byte, because
the game already stores the terrain at 0x8DEA when setting the battle up, three
instructions before the colour is chosen.

And the **broken figures** got fixed along the way: 1,544 bytes out of 4,096
were not reaching VRAM, because the two routines that upload the board run at
22 cycles per byte and the TMS9918 will not take two accesses closer than about
29. The battle patch did not cause it, it exposed it: the board used to be
re-uploaded whole every turn, so whatever fell got fixed on the next one.
Uploading at 37 cycles -1.3 % of a turn- takes the check from 1,544 bytes to
**zero** (`make verifica_batalla`).

The ROM to play is `war_unificada.rom` (`make rom_unificada`): the patched tape
with everything. Details in [INVESTIGACION.md](INVESTIGACION.md).

## What is still missing

- **Nobody has played a full game** with the map repainted. Araubi did play one with the September build, and that is where the big bug turned up.
- **The cartridge has only been seen to boot** (the menu and the map); nobody
  has played a full game from it.
- The unit sheet has been seen for a formation leader (Gandalf) and for the
  Ring-bearer (Frodo); **not every unit type has been checked** for the number
  colliding with a long label.
- **The deadline only shows inside the bearer's sheet.** A permanent counter on
  the play screen would mean hooking the game loop (0x7F57) and writing every
  frame: new code, more risk, left as an extension.
- **Units 0x16 and 0x17 stay invisible.** The planting loop skips them on
  purpose (`cp 016h` / `cp 017h` at 0x7FB3) and we have not worked out why. Nine
  of the ten occupied enemy cells get planted; the tenth holds only unit 0x16.

## Licence

The tools, the write-up and the IPS patch are released under [LICENSE](LICENSE).
**The game is not**, and no cassette image is distributed here — see
[LEGAL-NOTICE.md](LEGAL-NOTICE.md).
