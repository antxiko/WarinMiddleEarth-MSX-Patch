# How it works

The four things, one by one, with an address behind every claim.

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

That `ld a,05fh` + `ld (07c46h),a` is now a `call ANILLO_CON_PLAZO` (`0x666D`),
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
Spectrum attribute** glued behind. They carry `0x38` — black ink on white paper
— the same as the friendly icon's tiles, so the Eye covers the ground exactly
as the helmet does.

**The ZX's colour is per 8×8 cell, not per pixel.** Giving the Eye red ink would
be one byte per quadrant; it was left black on white, as it was drawn.

What could **not** be done, and why, is in [Findings](FINDINGS.md).
