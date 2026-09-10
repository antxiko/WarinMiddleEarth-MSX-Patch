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
- whether the repainted map still reads after an hour of play — and whether any
  of the eight blanked tiles turns up;
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

## The Eye, in red (closed)

It was asked for here and it is done: with the map repaint the Eye became **dark
red** over the terrain's cream, and the friendly icon a **blue shield**. Both
used to carry the same `0x38`, black on white, and at a glance they looked too
much alike. Dark red is one of the twelve colours the Spectrum attribute can
actually ask for in this port; bright red is not.

## Eight tiles are left blank on purpose

In the repaint, tiles **85 to 88** and **93 to 96** come back empty, and on the
cassette they had artwork. They are exactly the four quadrants of drawings `0x16`
and `0x18` in the two-by-two table at `0x77B5`.

**What is not known is whether anything asks for them.** Hunting for who uses
each index of that table turned up owners for `0x00`-`0x0F`
(`PINTA_LO_DE_ENCIMA`, through the terrain's nibble), `0x11` and `0x15`
(`PINTA_LA_UNIDAD`) and `0x13`/`0x14` (terrain 4). For `0x10`, `0x12`, `0x16`,
`0x17` and `0x18` **no caller was found**, which is not the same as proving them
dead. If one of them ever gets drawn in a long game, a hole would show up there.
The fix is to repaint them: eight drawings on the canvas.

## The text, on every screen

The nineteen strings have been read out of the emulator's RAM and seen on screen
on the map sign, on a named unit's sheet and on a nameless formation's. What is
**not** checked:

- the ten place names that were left alone are still in English or in Tolkien's
  own spelling (`Orthanc`, `Barad-Dur`, `Minas Tirith`...), which was the ask;
- `Ga. Hierro` and `Puerta N` are abbreviations forced by the signpost's width
  (10x1 and 8x1). Nothing longer fits without redrawing the sign;
- and the races are seen for `Mago`, `Hombre` and `Hombres`. `Elfo`, `Elfos` and
  the two `Mago` slots read correctly out of RAM but have not each been caught
  on screen.

The four new adjectives **have** been caught on screen, dumped from the patched
cassette: `Firme`, `Virtuoso`, `Valiente` and `Fuerte` on Gandalf's sheet and on
Frodo's, with `Aliado a la Comunidad` closing both.

## What this patch does not touch

- **Battle.** The board is built on top of the menu's code and has its own
  side-filtering routines; nothing here reaches into it.
- **Game balance.** Not one unit value has been changed, nor the deadline, nor
  the corruption. It only shows what was already there.
- **Sound.** Still silent. The beeper engine the conversion brought across now
  has **226 of its 276 bytes** taken by this patch: 137 of code and 89 of text.
  Fifty are left.
