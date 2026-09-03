# Findings

What turned up while making the patch, including what went wrong.

## Bit 5 of the map byte was free

Each map cell is one byte: the low nibble is the terrain, **bit 7** is "someone
is here" and **bit 6** is "cell with an order under way". Nothing was known
about bit 5, so it was counted across the **13,260 cells** of a freshly started
game:

    bit 0: 1340   bit 4:   10
    bit 1: 6683   bit 5:    0   <- free
    bit 2: 1957   bit 6:    0
    bit 3: 2148   bit 7:   28

Zero uses. The side marker fits there without taking anything away from the game.
Bit 6 also reads zero at that instant, but **that one has an owner**:
`PINTA_LA_UNIDAD` uses it for the "order under way" artwork.

## Zeroed slots in a table are not free slots

The two-by-two artwork table at `0x77B5` has six entirely zeroed entries —
`0x00`, `0x01`, `0x03`, `0x04`, `0x05` and `0x06` — and they looked like plenty
of room for the new icon.

**They were not.** `PINTA_LO_DE_ENCIMA` (`0x7714`) picks its entry with an
`and 00fh` over the terrain's low nibble, so indices `0x00`-`0x0F` already have
an owner even when empty: a zero in that table does not mean "free", it means
**"this cell draws nothing on top"**.

Putting the Eye in slot `0x03` gave it to all **447 cells of terrain type 3** on
the map. It showed up on the first run and was thrown away.

The way out was not to use an index at all: point HL at our own list of four
codes and enter `ESTAMPA_DOS_POR_DOS` **past its arithmetic**, at `0x7720`,
which is exactly where that routine does its first `ld a,(hl)`. The stamping is
still the game's; only the list is ours.

## Two enemy units cannot be made visible

The planting loop skips slots `0x16` and `0x17` **on purpose**:

```
7FB2  ld a,c
7FB3  cp 016h      ; 0x16 is not marked
7FB5  jr z,L_7FCE
7FB7  cp 017h      ; nor is 0x17
7FB9  jr z,L_7FCE
```

And both belong to the enemy side. At the start of a game there are **ten cells**
with enemies in them and the patch plants **nine**: (111,64), where only `0x16`
sits, still goes undrawn. `0x17` does appear, but only because it shares a cell
— (65,54) — with thirty-six others.

Why the game holds them apart is an [open question](OPEN-QUESTIONS.md).

## The Ring request had been misread

The first version of this work took it as read that "the corruption **is** the
bearer's `0xC300` counter". That counter does go up one every month —
`SUMA_UN_MES_A_LOS_CONTADORES` (`0x834A`) raises all 256 at once — but **it is
not what kills you**: nobody else reads it against a threshold.

What kills you is the **countdown of months** in the operand at `0x8333`, which
starts at 255, drops by one each month and jumps to `DERROTA` at zero. And the
message the game prints that same month is *"El Anillo corrompe al que lo usa."*,
so it is the game itself that ties the two together.

Finding who *writes* a variable is not enough: you have to find **who decides
with it**.

## The game is silent, and its silence is where the patch lives

The conversion brought the Spectrum's whole beeper engine across, at `0x6600`,
with five twenty-one-byte effects behind it. **Nothing ever calls it**: not one
instruction in the five listings points there, and the four places that ask for
an effect call `0x65FF`, a bare `ret`. Of the MSX's PSG only registers 7 and 14
are ever written, both to read the joystick.

This patch's 137 bytes of new code live inside that.

## Writing into the sheet means saving the registers

`ANILLO_CON_PLAZO` calls `ESCRIBE_A_EN_TRES_CIFRAS`, which leaves HL three bytes
further on. What follows in the sheet, `DESCRIBE_EL_DESTINO` (`0x6F7C`), **relies
on the HL it was handed**. Without saving it the sheet gets written somewhere
else: with half the Fellowship's names on top of it.

That is not a guess: it was tried without saving, and the sheet came out broken.
