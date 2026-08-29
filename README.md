# War in Middle Earth (MSX) — Araubi's patch

> ## ⚠️ WORK IN PROGRESS — this patch is **not finished**
>
> The three things it does are in place and have been verified on a real MSX in
> openMSX, but it is published as work in progress on purpose: nobody has played
> a whole game with it on, the unit sheet has been seen for a formation's leader
> but not for every unit type, and the always-on ring meter is not built yet.
> The full list is at the bottom. Read it before you judge a screenshot.

A byte patch for the MSX cassette of **War in Middle Earth** (Melbourne House /
Dro Soft, 1989), built on top of the
[commented disassembly](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly).
It does the three things **Araubi** asked for on the forum: make enemy units
visible, show the numeric value of each of a unit's attributes, and surface the
ring-corruption counter.

[README en español](README.es.md) · Full write-up: [INVESTIGACION.md](INVESTIGACION.md)

## The tape is not here

No cassette image is distributed, only the patch work (see
[LEGAL-NOTICE.md](LEGAL-NOTICE.md)). You supply your own `war.tsx` (sha256
`13c63632…b1d81208`), and:

    make extract     # pulls the block bodies out of your tape into work/
    make parche      # applies the table and writes war_parche.tsx
    make test        # the checks

`war_parche.tsx` is the patched cassette, the same size as the original, ready
for a real MSX1 (`openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx`).

## What it changes

Everything is in the game's middle block (runs at `0x5E00`), **80 bytes across
three edits**, each one checked against the bytes it expects before writing —
nothing shifts, and `make parche` fails if a single byte changes outside the
table (`tools/parchea.py`).

**1 · Enemy units become visible.** The map keeps a "someone is here" bit for
each cell, and `RECENTRA_EL_MAPA` (0x7FAC) re-plants it unit by unit — but its
loop stops at unit `0x78`, exactly where the enemy side begins, so the enemy is
never planted and never drawn. Changing the loop's limit from `0x78` to `0x00`
(**one byte, at 0x7FD1**) makes it walk all 256 units. Verified: **136 enemy
units get planted where zero did before.**

**2 · Every attribute shows its number.** A unit's sheet lists six qualities —
Valioso, Habil, Duro, Bravo, Energico, Decidido — as adverb + adjective ("very
brave"), never as a number. A new routine (`MUESTRA_LOS_VALORES`, 76 bytes),
written over the **ZX Spectrum beeper engine at 0x6600 that nothing in this port
ever calls**, reads the six values (from `0xC000`/`0xC100`/`0xC200`/`0xC300`) and
prints them as digits in the sheet. It is hooked by a three-byte trampoline at
`0x708A`. Verified against the real values: all six match.

**3 · The ring-corruption counter is visible.** `0xC300+n` is the counter the
monthly "the Ring corrupts its bearer" message raises for every unit; for the
Ring-bearer (Frodo) that is his corruption. With change 2 it now shows as a
number in his sheet (Frodo starts around **176 of 255**). There is no separate
"resistance" variable in the binary — the Ring is that counter and that message.

Full evidence, addresses and the openMSX output are in
[INVESTIGACION.md](INVESTIGACION.md).

## What is still missing

- **Nobody has played a full game** with the patch on.
- The unit sheet has been seen for a formation leader (Gandalf) and forced for
  the Ring-bearer (Frodo); **not every unit type has been checked** for the
  number colliding with a long label.
- **The always-on ring meter is not built.** Right now the number is in the
  sheet; a permanent "Ring: NNN" on the play screen is left as an extension (the
  hook is located: `0x733E` gives the bearer, `0xC300+bearer` the value).
- Enemy silhouettes are drawn the same as friendly ones (no colour telling them
  apart); planting the bright attribute for the enemy too is a documented option.

## Licence

The tools and the write-up are released under [LICENSE](LICENSE). **The game is
not**, and the tape is not distributed here — see [LEGAL-NOTICE.md](LEGAL-NOTICE.md).
