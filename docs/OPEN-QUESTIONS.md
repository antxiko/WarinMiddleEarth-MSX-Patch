# Open questions

What is not done, what is not known, and what it would take to close it.

## Nobody has played a full game

This is the most important line on the page. The patch is measured instant by
instant in the emulator, but **nobody has sat down and played a complete game
with it on**. Everything that follows is the kind of thing you only see by
playing.

If you play it, what would help to know:

- whether the number in the sheet **eats a letter** on some unit type;
- whether the Ring's deadline **counts down as it should** as the months pass;
- whether an Eye shows up **where nobody is**;
- and whether the game misbehaves in battle, which this patch does not touch but
  which shares memory with what it does.

## The sheet, on every unit type

It has been seen on **Gandalf** (Brujo) and **Frodo** (Hobbit), and it fits on
both. But the sheet's labels vary in length — "Es muy Decidido ," is a long one
— and the numbers go in column 20. The other types are unchecked.

## Two enemy units are still invisible

The planting loop deliberately skips slots `0x16` and `0x17`, and both are enemy
units. Of the ten cells holding enemies, nine get planted.

**What is not known: why.** The game treats them differently in more places —
the loop that colours unit cells (`0x6AE3`) skips them too, and there is a
routine, `PON_EL_EJERCITO_16_EN_SU_SITIO` (`0x922C`), dedicated to putting `0x16`
back where it belongs — so they look like something special rather than an
oversight. Making them visible without knowing what they are is asking for
trouble.

## The deadline only shows inside the bearer's sheet

Today the number appears in the sheet, which is where the game draws the ring. A
counter **permanently on screen** would mean hooking the play loop (`0x7F57`)
and writing into the ZX screen every frame: new code, more risk, and no way to
check it without playing for a while.

The hook is located: `0x733E` gives the bearer, `0x8333` the value, and `0x7113`
knows how to paint the number.

## The Eye, in red

The four tiles carry attribute `0x38` — black ink on white paper — the same as
the friendly icon. Making it **red ink** would be one byte per quadrant, four in
all.

It has not been done because the ZX's colour is per 8×8 cell and it would need
looking at on screen: whether red over the map's dithering reads well or just
muddies it. That is a test, not a problem.

## The text, on every screen

The fifteen strings have been read out of the emulator's RAM and seen on screen
on the map sign, on a named unit's sheet and on a nameless formation's. What is
**not** checked:

- the ten place names that were left alone are still in English or in Tolkien's
  own spelling (`Orthanc`, `Barad-Dur`, `Minas Tirith`...), which was the ask;
- `Ga. Hierro` and `Puerta N` are abbreviations forced by the signpost's width
  (10x1 and 8x1). Nothing longer fits without redrawing the sign;
- and the races are seen for `Mago`, `Hombre` and `Hombres`. `Elfo`, `Elfos` and
  the two `Mago` slots read correctly out of RAM but have not each been caught
  on screen.

## What this patch does not touch

- **Battle.** The board is built on top of the menu's code and has its own
  side-filtering routines; nothing here reaches into it.
- **Game balance.** Not one unit value has been changed, nor the deadline, nor
  the corruption. It only shows what was already there.
- **Sound.** Still silent. The beeper engine the conversion brought across is
  now half occupied by this patch.
