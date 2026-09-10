# Getting started

This is a **gameplay patch** for the MSX cassette of *War in Middle Earth*
(Melbourne House / Dro Soft, 1989). It is not the game: it is what gets changed
in it.

**No cassette image is distributed here.** The patch is what gets shared, and
you apply it to your own copy.

## The quick way: the IPS

The repository carries a **`war_parche.ips`** of 1,718 bytes. It holds only the
bytes that change — our own code, the map's 122 repainted tiles and the new
text — and it
applies to your own tape with any IPS tool, or with the one included here:

    python3 tools/ips.py --aplica war.tsx war_parche.ips war_parche.tsx

Your tape has to be the one it was made from. Its fingerprint is
`sha256 13c63632…b1d81208`; if yours differs the patch will still apply, but
nobody can vouch for the result.

## The long way: build it yourself

You need Python 3 and `make`. Put your `war.tsx` in the root and:

    make extract     # pulls the block bodies out of your tape into work/
    make parche      # applies the table and writes war_parche.tsx
    make ips         # and war_parche.ips, the patch on its own
    make test        # the 79 checks

`make parche` does not write blind: **each change first checks that the original
bytes are the ones it expects**, and if a single byte outside the table differs
when it finishes, it aborts. That is why it is safe to let it run on your copy.

## Playing it

    openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx

then, on the MSX, `RUN"CAS:"`. The whole load is about six and a half minutes of
emulated time; with the emulator's throttle off, far less.

## What you will see differently

- **The whole map is repainted**: 122 of the 128 8 × 8 drawings. It is the first
  thing you notice, because it changes the entire screen.
- **Enemy units are drawn on the map**, wearing the Eye of Sauron so you do not
  mistake them for your own.
- **Each unit's sheet shows the number** for its six attributes, not just "very
  skilled".
- **In the Ring-bearer's sheet**, to the left of the ring, the **months left**
  before he succumbs.
- **The text sits on the frames' own khaki** instead of on white.
- And the sheet reads **Firme, Virtuoso, Valiente and Fuerte** where it read
  Hábil, Valioso, Duro and Bravo, with its last line whole: "Aliado a la
  Comunidad".

To reach Frodo's sheet: put the cursor on the Fellowship's cell, fire, and use
up and down to step through the units until you get to him. The ring number only
shows in the bearer's sheet, which is where the game draws the ring.

## Before you judge it

Araubi played a full game with the September build, and that is where the big
bug turned up — it is written up in [Findings](FINDINGS.md). **Nobody has played
one with the map repainted.** What is known to be missing is in
[Open questions](OPEN-QUESTIONS.md), and playing it and reporting back is the
most useful thing you can do.

## Where it comes from

From a [commented disassembly](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly)
of the whole tape, which is a **separate repository and a separate site**. Every
address quoted here comes out of that listing, not out of trial and error.
