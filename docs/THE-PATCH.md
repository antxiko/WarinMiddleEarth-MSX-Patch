# The patch

A hundred and thirty entries, **1,396 bytes**, none outside the table and none
shifted: every patch is exactly as long as what it replaces, so no address in
the game moves.

They come from two places: **27 entries written by hand** — 548 bytes of code,
pointers and text — and **103 that fall out of the canvases** — 848 bytes, the
122 repainted map tiles. Byte by byte: 848 of tiles, 376 of text, 137 of new
code, 23 of hooks and trampolines, 10 of pointers and 2 loose ones — the
planting loop's limit and the text's paper. The tool draws no distinction
between them: every one carries the bytes it expects to find, and every one is
as long as what it replaces.

## The table

| address | block | bytes | what |
|---|---|---|---|
| `0x7FD1` | middle | 1 | the planting loop's limit, `0x78` → `0x00` |
| `0x708A` | middle | 3 | trampoline to the attribute routine |
| `0x6600` | middle | 76 | `MUESTRA_LOS_VALORES` |
| `0x664C` | middle | 61 | planting by side, drawing by side, and the deadline |
| `0x7FC9` | middle | 5 | planting hook |
| `0x770A` | middle | 10 | drawing hook |
| `0x6F77` | middle | 5 | ring hook |
| `0x763F` | middle | 1 | the text's paper, `0x78` → `0x70` |
| `0x7DE6` | middle | 9 | `Habil` → `Firme`, in its own slot |
| `0x6689` | middle | 25 | ` Virtuoso`, ` Valiente` and ` Fuerte` |
| `0x6FF0`, `0x701F`, `0x7036` | middle | 2 each | those three adjectives' pointers |
| `0x66A2` | middle | 64 | the four whole phrases of the sheet's last line |
| `0x7074`, `0x707A` | middle | 2 each | that list's pointer and its column |
| `0x7A79`…`0x7BC7` | middle | 180 | the ten place names on the map |
| `0x6BA5` | middle | 9 | `Brand III` → `Bardo III` |
| `0x7D07` | middle | 45 | the race names in the plural |
| `0x7D3A` | middle | 44 | the race names in the singular |
| `0x9E02`…`0xA280` | high | 848 | the 122 repainted tiles, in 103 entries |

The addresses are **execution** addresses. The "middle" block runs from
`0x5E00` and the "high" one from `0x9E00`. The ten place names come in eight
entries: seven on their own — `0x7A79`, `0x7B28`, `0x7B34`, `0x7B4B`, `0x7B5D`,
`0x7B7F` and `0x7BC7` — and one of 112 bytes that rewrites in one go the stretch
of nine records starting at `0x7AA1`, because there `Rivendell` gives up a letter
to lend it to `Dale`, and shrinking one record **shifts every record behind
it**.

## The four text formats

Nothing shifts, so where a string lives is what decides whether it can change.
And each format squeezes differently:

- **The place table (`0x7A5E`).** Every record is
  `[x][y][2+width*rows][width<<4|rows][text]`, with no terminator. The fourth
  byte is the **size of the signpost** that gets drawn, and the text fills it
  whole, row by row: a new name has to measure **exactly width × rows**. That is
  why `Cavada ` + `Grande ` fills the 7×2 sign that held `Michel `/`Delving`.
- **The four lists of strings packed back to back**, each ending with **bit 7 set
  on its last letter** (races in the plural `0x7D06`, in the singular `0x7D39`,
  the side labels `0x7D6A` and the adverbs `0x7D9A`). String N is reached by
  counting terminators, so **inside** a list a string *may* change length as long
  as the total does not. That is what pays for the longer words: `Brujo ` →
  `Mago` frees two bytes and appears twice in each list — exactly the four that
  `Elf` → `Elfo` and `Hum` → `Hombre` need.
- **The list of the 24 proper names (`0x6B46`)**, separated by `0xB7`.
- **The sheet's six adjectives, each with its own `ld hl`.** These sit in no
  list to be walked: `0x704B`, `0x7061`, `0x7006`, `0x6FEF`, `0x701E` and
  `0x7035` each load their own absolute address. That is why these *can* grow —
  move them elsewhere and change the pointer — and why `Valioso` fits as
  `Virtuoso`. Here the limit **is not the cassette, it is the screen**: the
  sheet is 24 columns wide and the patch's number goes in column 20, so with the
  longest adverb (` No es muy `, eleven) an eight-letter adjective leaves the
  comma right under the number. That already happened to `Energico` before this
  patch, and there is a check demanding that none of the new ones make it
  worse.

The fourth list, the one for the sheet's **last line** (`0x7D6A`), moved whole
to `0x66A2`. That line used to be composed from a template plus the list's word,
and now each entry carries **the complete phrase**, written from column 0: it
was the only way to turn `Aliado a la Sociedad` into `Aliado a la Comunidad`
without touching the other three.

## How it is applied

The disassembly is never touched. It starts from the **block bodies** that
`make extract` pulls out of your tape (`work/*.raw`, the same bytes without the
Spectrum format's wrapper), applies the table in `tools/parchea.py`, and rebuilds
the cassette by re-wrapping each block with its flag in front and its XOR behind.

Every entry in the table carries **the bytes it expects to find**. If they are
not there, `make parche` aborts: wrong tape. And when it finishes it checks that,
outside the table's ranges, the body is identical to the original.

## Where the new code lives

The 137 bytes of new code — 76 for the attribute routine and 61 for the second
round — are written **over the ZX Spectrum's beeper engine**, at
`0x6600`-`0x6688`. Behind them go 89 more bytes that are no longer code but
**text**: the three long adjectives (`0x6689`-`0x66A1`) and the four phrases of
the sheet's last line (`0x66A2`-`0x66E1`).

The conversion brought that engine across whole and **nothing ever calls it**:
not one instruction in the five listings points at `0x6600`, and the four places
that ask for a sound effect call `0x65FF`, which is a bare `ret`. Of the MSX's
PSG only two registers are ever written, 7 and 14, and both are for reading the
joystick. This game is silent, and its silence gives us 276 bytes of room, of
which the patch spends **226** and leaves 50 free. A check makes sure no entry
runs past that stretch or steps on another.

## The graphics, in three PNGs

**All** the artwork in the high block is edited with an image editor. It lives
in `src/parche/`, at full size and **with no gaps**: one pixel of the PNG is one
pixel of the game.

| canvas | what it holds | where it lives | size |
|---|---|---|---|
| `tiles_del_mapa.png` | the **128 map tiles**, 8 × 8 | `0x9E00` | 128 × 64 |
| `sprites_de_batalla.png` | the **176 battle sprites**, 16 × 8 with a mask | `0xA2E8` | 176 × 128 |
| `fuente.png` | the **128 characters**, 8 × 8 | `0xC800` | 128 × 64 |

Repaint whatever you like and `make parche` does the rest: it compares the
canvases with the cassette and every drawing that changed comes out on its own
as one more entry in the table, in the `graficos` group, with its `orig` and its
`nuevo` the same length, exactly like the hand-written ones. Leave them alone
and not a single extra entry appears.

Today **122 of the 128 tiles** come out of there, repainted: 103 entries and 848
bytes, more than half the patch. The six that do not move are 97 to 102, where
only the background changed — the ZX's white and the MSX's are the same colour
15, so the drawing that comes back is byte for byte the one that was there. The
Eye of Sauron is in that group now too: it used to be 36 hand-written bytes and
it is drawn on the canvas like everything else.

| command | what it does |
|---|---|
| `make graficos` | says which drawings differ from the cassette, without building anything |
| `make parche` | turns them into patch entries and builds the cassette |
| `make lienzos` | **redraws** the PNGs from the cassette, wiping whatever was painted on top; it has to be forced with `--rehaz` |

### How each sheet is painted

- **The tiles** carry a **ZX attribute** behind the bitmap (bits 0-2 the ink, 3-5
  the paper, 6 the bright, 7 the flash), and that is where the Spectrum's two
  rules come from: **two colours per 8 × 8 cell** — the famous *attribute clash* —
  and **both of the same brightness**, because there is a single bright bit for
  the two of them. If a cell breaks either rule the tool **stops and says which
  one and why**, instead of deciding on its own.
  **But the colour you see is the MSX's, not the Spectrum's.** This port never
  sends the attribute to the screen: `ATRIBUTO_A_COLOR` (`0x049F`) translates it
  first, with two eight-colour tables the game fills in at boot — `0x04CE` for an
  attribute without bright, `0x04D6` for one with it. So the canvas is drawn and
  read back **in MSX colours**, and only **twelve of the fifteen** can be asked
  for: no attribute yields the medium red, the medium green or the grey. If one
  of those gets in, the tool takes the nearest reachable colour and reports which
  it was, how many pixels and what it became. The brightness rule loosens too:
  only the four colours whose two entries differ — blue, red, green and yellow —
  force anything.
- **The sprites** carry no attribute: they carry a **mask**. The routine that
  draws them (`0x887B`) does `and` with the mask and `or` with the bitmap, so a
  pixel can **leave the background as it was**, write it to **paper**, or write
  it to **ink**. Three states, and all three are used: 12,489 transparent
  pixels, **2,892 written blacks** - in 153 of the 176 - and 7,147 whites. The
  first two look alike over paper but are different bytes, so the canvas needs
  three colours. There is **no invented colour key** here: the transparent one
  carries the same background as the web's plates (`#18181C`) and is also
  **declared transparent in the PNG itself**, so the editor shows it as such;
  erasing with the eraser works too, and if the image is flattened that colour
  still does the job. They are **stacked in pairs**, which is how they fit into
  16 × 16 figures (that last part is a reading of the picture, not a routine we
  found: each sprite still goes to its own address, worked out separately).
- **The font** is the simplest of the three: one bit, one pixel, white on black.
  The index **is** the character code, so `A` sits at 65.

### What is left alone

A drawing that looks *exactly* like the one on the cassette is handed back with
**its original bytes**, not re-encoded. That is why opening a PNG and saving it
unchanged does not move a single byte, not even in the ones that cannot be
rebuilt from the picture: a tile with white ink on white paper hides eight bytes
of bitmap underneath, and so does one that is black on black. Without that rule
every round trip would dirty the patch with changes nobody asked for — and it is
what leaves tiles 97 to 102 out of the patch today.

Each sheet's palette travels **inside** its PNG, so an editor in indexed mode
offers it ready-made. If a colour from outside still gets in - by working in
true colour, say - the nearest one is taken and the screen reports which it was,
how many pixels, and what it was changed to.

## The IPS

`make ips` produces **`war_parche.ips`**: 1,718 bytes in 39 records, holding
only what changes. Verified on the spot — and in the tests — that **applied to
`war.tsx` it gives back the patched cassette byte for byte**.

That is what gets shared. Not the game.

## The checks

`make test` is 73 of them, and they are not decoration. Among others:

- that **`orig` and `nuevo` are the same length** in all 130 entries, i.e.
  nothing shifts;
- that every entry **falls inside its block**;
- that the table's bytes are **exactly** what comes out of assembling
  `src/parche/ficha_valores.asm` and `src/parche/icono_enemigo.asm` with pasmo;
- that the second round's three hooks **point where they should** inside the new
  routine;
- that the patch **never writes into the artwork table at `0x77B5`**, which is
  the trap described in [Findings](FINDINGS.md);
- that the four tiles of the Eye go into the slot that was all zeros and **with
  the same colour attribute as the friendly icon**, and that the canvas still
  yields them **byte for byte** as when they were hand-written;
- that exporting each canvas from the cassette and reading it back returns
  **every byte untouched**, and that today **no other drawing** changes among the
  432 across the three sheets;
- that the three codecs draw **pixel for pixel** what `tools/render_graficos.py`
  draws — the tool that makes the web's plates: if the sprites' zigzag or the
  tiles' attribute were read differently here, the drawings would not match;
- that a cell with **three colours**, or one that **mixes brightnesses**, is
  rejected with the cell number and the reason, that the sprites and the font do
  **not** carry that limitation, and that the PNG reader swallows what a real
  editor puts out - indexed, greyscale, RGB, RGBA, 1 to 16 bits and all five
  filters;
- that each drawing's slot inside a canvas **overlaps no other**, or repainting
  one would ruin its neighbour;
- that the text patches **do not change how many strings a list holds** (adding
  or removing one would shift every string behind it by an index, and the game
  would say "Orcs" where it says "Enanos");
- that **no absolute base** — the fourteen the code uses to enter the text — falls
  inside a patch;
- that, once the table is applied, **the 29 map signs still measure width × rows**
  and the four string lists still read whole, including the ones the patch does
  not touch;
- and that the repository's IPS **rebuilds the patched cassette**.
