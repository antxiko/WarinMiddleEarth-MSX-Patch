# How it works

The six things, one by one, with an address behind every claim.

## A unit's map

The engine keeps **256 unit slots**, in parallel 256-byte arrays indexed by unit
number:

| address | what it holds |
|---|---|
| `0xB900+n` | column (X) on the map |
| `0xBA00+n` | row (Y) |
| `0xBD00+n` | type, side and flags; **bit 4 = carries the Ring** |
| `0xC000+n` | low nibble *Valioso*, high nibble *Hábil* |
| `0xC100+n` | low nibble *Duro*, high nibble *Bravo* |
| `0xC200+n` | *Enérgico* (spent by walking) |
| `0xC300+n` | *Decidido* (goes up one every month) |

Yours are slots `0x00`-`0x77` except `0x16` and `0x17`; the other side's are
those two and everything from `0x78` up. The **Ring-bearer** is the first slot
with bit 4 of `0xBD00` set: in a new game, **Frodo, unit 0x05**.

And the map lives from `0xCC00`, **column by column**: its `0x33CC` bytes are
130 columns of `0x66`, so cell (x, y) sits at `0xCC00 + (x+1)*102 + (y+1)`.

---

## 1 · Enemy units become visible

In each map cell, **bit 7** means "someone is here", and it is what makes the
game draw the 2×2 silhouette. `RECENTRA_EL_MAPA` (`0x7FAC`) sets it: it clears
bit 7 across the whole map and re-plants it unit by unit. But the loop stops at
0x78:

```
7FB0  ld c,000h        ; starts at unit 0
7FB2  ...              ; plants bit 7 in unit C's cell
7FCC  set 7,(hl)       ; "someone is here"
7FCE  inc c
7FCF  ld a,c
7FD0  cp 078h          ; <- stops exactly where the enemy begins
7FD2  jr nz,0x7FB2
```

**One byte at `0x7FD1`**, from `0x78` to `0x00`, and the loop walks all 256
slots. `0x7FC7` already skips the ones sitting at (0,0), so empty slots do no
harm. Measured: **136 enemy units planted** where zero were before.

> **Note.** The opcode switch at `0x8982`/`0x8993` over `0x8AF3` — writing
> `0xD0` = `ret nc` or `0xD8` = `ret c` — does **not** decide this: it is the
> battle's side filter. That was checked before ruling it out.

---

## 2 · Every attribute shows its number

The sheet is assembled in a buffer at `0x7C17`, 24 columns by 10 rows, and
painted afterwards. Column 20 of each line has room for three digits.

The new routine lives at `0x6600` and a **three-byte trampoline** at `0x708A`
hooks it: where `ARMA_LA_FICHA` used to do `ld hl,0x5FBD` right before painting,
it now does `call 0x6600`. The routine writes the six numbers and **ends by
redoing that same `ld hl,0x5FBD`**, so the render is unchanged.

The values come from `0xC000`-`0xC300` for whichever unit the operand at
`0x6EAD` names, and the digits are written by `ESCRIBE_A_EN_TRES_CIFRAS`
(`0x7113`), which is the game's own.

---

## 3 · The Ring's deadline

The clock (`0x831B`) counts ticks, days and months. Going from day 60 to 61:

```
8332  ld a,000h      ; the operand at 0x8333 is the COUNTDOWN of months
8334  dec a          ; 0x7F4F sets it to 255 when the game starts
8335  ld (08333h),a  ; one month less
8338  jp z,DERROTA   ; at zero, Sauron's screen
8340  ld hl,0853ah   ; "El Anillo corrompe al que lo usa."
```

That operand **is** what you have left before losing, and the game ties it to
the Ring with its own message. There are other roads to `DERROTA` — losing the
bearer, running the `0xC000` uses down in battle, handing the Ring to a unit
with none — but that is the only one that is a **deadline**.

`MARCA_AL_PORTADOR` (`0x6F6E`) checks bit 4 of `0xBD00` and, if that unit
carries the Ring, writes character `0x5F` at `0x7C46`, the last column of the
sheet's second row. To its left, `0x7C43`, three columns were free.

That `ld a,05fh` + `ld (07c46h),a` is now a `call ANILLO_CON_PLAZO` (`0x666E`),
which places the ring the same way and also writes `0x8333` at `0x7C43`.

**And it saves BC, DE and HL.** What follows in the sheet is
`call DESCRIBE_EL_DESTINO` (`0x6F7C`), which relies on the HL it was handed:
`0x7C27`, where the `ESCRIBE_A_EN_TRES_CIFRAS` at `0x6F6B` left it. Without
saving it the sheet gets written somewhere else, with half the Fellowship's
names on top of it. Tried, and you can see it.

---

## 4 · The Eye of Sauron

The game picks a cell's artwork by looking at **its map byte and nothing else**:

```
PINTA_LA_UNIDAD (0x7708):   or a          ; without bit 7 there is nothing
                            ret p
                            bit 6,a       ; cell with an order under way -> 0x11
                            ld a,011h
                            jr nz,ESTAMPA
                            ld a,015h     ; otherwise, the usual artwork
```

So when it draws it **cannot know which side a unit belongs to**. That has to go
into the map byte itself, and for that we need a free bit. **Bit 5** was free:
zero uses across all 13,260 cells.

- `SIEMBRA_CON_BANDO` (`0x664C`) replaces the `call CELDA_DEL_MAPA` +
  `set 7,(hl)` at `0x7FC9`: it sets bit 7 as always and, if the unit is `0x78`
  or higher, bit 5 too.
- `DIBUJO_SEGUN_BANDO` (`0x6658`) replaces the body of `PINTA_LA_UNIDAD` from
  `0x770A` and looks at that bit 5 before anything else.

The icon is **four new tiles** at indices 111 to 114 of the `0x9E00` table,
which were all zeros. Each tile is nine bytes: eight of artwork and a **ZX
Spectrum attribute** glued behind.

**The ZX's colour is per 8×8 cell, not per pixel**, so the Eye gets two colours
per quadrant. It uses them: it was repainted in **dark red on the map's cream** —
attribute `0x3A`, and `0x17` in the top-left quadrant, which runs the other way
round — and the friendly icon became a **blue shield**. Both used to carry the
same `0x38`, black on white, and at a glance they looked too much alike.

## 5 · The text finishes its translation

Animagic's conversion translated the game half way: the map's place names stayed
in English and three race names came across truncated. Nineteen strings change,
and **not one byte moves**. What makes that possible is that the game keeps its
text in four different shapes, and each one allows something different.

**The place table, `0x7A5E`.** `BUSCA_EL_SITIO` (`0x6E50`) walks it. Each record
is

```
[x][y][2 + width*rows][width<<4 | rows][text]
```

with no terminator: the length comes out of the third byte, which is also what
you add to reach the next record. The fourth byte is the **size of the signpost**
`VENTANA_DEL_SITIO` (`0x6E2D`) draws, and the text fills it whole, row by row —
that is why `Minas Tirith` is twelve letters in 6×2 and `Monte   Gundabad`
sixteen in 8×2, with the spaces put in by hand. A new name has to measure
**exactly width × rows**:

| address | was | is | fits because |
|---|---|---|---|
| `0x7B34` | Bywater | **Delagua** | 7×1, seven letters exactly |
| `0x7B28` | Buckland | **LosGamos** | 8×1 |
| `0x7B5D` | Far Downs | **Quebradas** | 9×1 |
| `0x7B4B` | Michel Delving | **Cavada Grande** | 7×2: `Cavada ` + `Grande ` |
| `0x7BC7` | Grey  Havens | **Ptos  Grises** | 6×2: `Ptos  ` + `Grises` |
| `0x7AA5` | Rivendell | **Rivendel** | 9×1 to **8×1**: one letter to spare |
| `0x7AB2` | Isenmouthe | **Ga. Hierro** | 10×1 |
| `0x7A79` | Morannon | **Puerta N** | 8×1 |
| `0x7B0D` | Dale | **Valle** | 4×1 to **5×1**, with the byte Rivendel lends it |
| `0x7B7F` | HelmsDeep | **AbismHelm** | 5×2: `Abism` + `Helm ` |

**The lists of packed strings**, each ending with **bit 7 set on its last
letter**. String N is reached by counting terminators from a base
(`SALTA_B_TEXTOS`, `0x6E98`). There are four: races in the plural (`0x7D06`), in
the singular (`0x7D39`), the side labels (`0x7D6A`) and the adverbs (`0x7D9A`).
Inside a list a string **may** change length as long as the total does not — and
that is what pays for the longer words. `Hum` → `Hombre` is three bytes more and
`Elf` → `Elfo` one more; there is no room behind, because `0x7D6A` is a fixed
address in the code. But `Brujo ` → `Mago` is two bytes less, and `Brujo`
appears **twice in each list** (races 0 and 7 are two kinds of wizard):

```
singular (0x7D3A, 44 bytes, races 0..8)
  Brujo 6  Nazgul 6  Hum 3     Elf 3   Enano 5  Orc 3  Hobbit 6  Brujo 6  Gollum 6  = 44
  Mago 4   Nazgul 6  Hombre 6  Elfo 4  Enano 5  Orc 3  Hobbit 6  Mago 4   Gollum 6  = 44

plural (0x7D07, 45 bytes, races 0..7)
  Brujos 7  Nazgul 6  Hum 3      Elfos 5  Enanos 7  Orcs 4  Hobbits 7  Brujo 6  = 45
  Magos 5   Nazgul 6  Hombres 7  Elfos 5  Enanos 7  Orcs 4  Hobbits 7  Mago 4   = 45
```

`Gollum` closes both lists and is not touched: its last byte **is** the base of
the next list.

The three race changes were asked for in the singular, but `Brujo` and `Hum` sit
in **both** tables — leaving the plural alone would have left the game saying
"Formacion de 005 Hum". It was changed too, **in the plural** (`Magos`,
`Hombres`), which is what that place wants: its neighbours are `Enanos`, `Orcs`
and `Hobbits`. `Elfos` was already right. Race 7 of the plural table was written
by the game in the singular (`Brujo `), and that is respected: it reads `Mago`.

**The list of 24 proper names, `0x6B46`**, separated by `0xB7` and copied up to
that separator (`0x6E23`, `0x6F38`). `Brand III` → **`Bardo III`**, nine letters
for nine.

**And the sheet's six adjectives, which are in no list at all.** Each one is
loaded by its own absolute `ld hl` — `0x704B`, `0x7061`, `0x7006`, `0x6FEF`,
`0x701E` and `0x7035` — so unlike everything above they *can* grow: move the
string and change the pointer. Four of them do:

| pointer | was | is | where it lives now |
|---|---|---|---|
| `0x7006` | Habil | **Firme** | `0x7DE6`, its own slot: five letters for five |
| `0x6FEF` | Valioso | **Virtuoso** | `0x6689`, in the dead beeper engine |
| `0x701E` | Duro | **Valiente** | `0x6692` |
| `0x7035` | Bravo | **Fuerte** | `0x669B` |

The three that moved take 25 bytes and their three pointers six more. `Enérgico`
and `Decidido` stay as they were, and so do the three abandoned strings at
`0x7DF0`-`0x7DFF`: nobody reads them any more, and a check makes sure they are
left untouched.

The **last line** of the sheet was a template plus a word from the list at
`0x7D6A`, which is how it read `Aliado a la Sociedad`. `Comunidad` is one letter
longer, so the whole list moved to `0x66A2` with each entry carrying the complete
phrase, and the write starts at column 0 (`0x7CEF`) instead of column 10. That
way the other three entries read exactly as they read before.

The font settles which letters are available: `0xC800` holds 128 characters of
eight bytes, and everything from `0x21` to `0x7F` is drawn (only `0x20`, the
space, is blank). Codes with bit 7 set are not letters — they are artwork from
the `0x9E00` table — so **there are no accents**, and `Nazgul` keeps going
without its circumflex.

---

## 6 · The map, repainted

The map is drawn with **128 tiles of 8 × 8** at `0x9E00`, nine bytes each: eight
of bitmap and a **ZX Spectrum attribute** behind. `tools/lienzos.py` exports the
lot to a PNG of 128 × 64 at 1:1 — sixteen tiles per row — and reads it back;
`make parche` compares the canvas against the cassette and turns every drawing
that changed into an entry. **122 of the 128** changed.

The thing worth knowing is what colours can be asked for, because the attribute
is the Spectrum's but **the colour is the MSX's**:

```
ATRIBUTO_A_COLOR (0x049F):  ld hl,004ceh   ; the table without bright
                            bit 6,a
                            jr z,+3
                            ld hl,004d6h   ; and the one with it
                            ...            ; ink -> high nibble, paper -> low
```

Two tables of eight bytes, read out of the tape:

| | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| `0x04CE`, no bright | 1 | 4 | 6 | 13 | 12 | 7 | 10 | 15 |
| `0x04D6`, bright | 1 | 5 | 9 | 13 | 3 | 7 | 11 | 15 |

Sixteen slots, **twelve distinct MSX colours**: nothing produces the medium red
(8), the medium green (2) or the grey (14). And only four of the eight — blue,
red, green and yellow — actually change with the bright bit, so the Spectrum's
"both of the same brightness" rule only binds for those. The tool knows all of
this: it draws the canvas in MSX colours, refuses a cell with three of them, and
if an unreachable colour gets in it takes the nearest one and says so.

**And one byte more, for the paper.** `UN_CARACTER_NORMAL` (`0x7616`) paints
every character of the font with one fixed attribute, the `ld a,078h` at
`0x763E`. Its operand — `0x763F` — goes from `0x78` to `0x70`: paper 6 with
bright, which the `0x04D6` table sends to MSX colour 11, the same khaki the
frames are painted in. It takes the **spaces** with it, which is what fills the
inside of a signpost, so the box comes out khaki all through instead of leaving
a halo behind each letter. It is global: menu, labels, sheet and battle.

What could **not** be done, and why, is in [Findings](FINDINGS.md).
