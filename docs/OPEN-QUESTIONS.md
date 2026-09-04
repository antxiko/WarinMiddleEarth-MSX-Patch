# Open questions

What is not done, what is not known, and what it would take to close it.

## Araubi played it, and found the big one (closed)

This page used to open by asking someone to play a full game, because the patch
was measured instant by instant in the emulator but nobody had sat down and
played it. **Araubi did, and sent the recording**: eight minutes in, the sheet's
labels came out as garbage, and shortly after that the machine hung.

It was the patch's fault: the Ring hook pointed one byte before the start of its
routine and slipped in an `ld (hl),a` that ate the separators of the name list,
one per sheet drawn. It is written up in [Findings](FINDINGS.md), and fixed with
a single byte.

One recorded game was worth more than every automated check put together. What
still needs playing to be seen:

- whether the number in the sheet **eats a letter** on some unit type;
- whether the Ring's deadline **counts down as it should** as the months pass;
- whether an Eye shows up **where nobody is**;
- and whether the game misbehaves in battle, which this patch does not touch but
  which shares memory with what it does.

And one the recording left open: the hang came after the broken panel and was
most likely its consequence —with no separator, copying a name never finds where
to stop— but **that is not proven**. With the corrected tape the game is still
alive ten minutes in and does not hang; a genuinely long game would close it.

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
