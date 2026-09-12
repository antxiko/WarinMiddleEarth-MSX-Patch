# Legal notice and attribution

*(También disponible [en castellano](AVISO-LEGAL.md).)*

## Who owns what

**The game is not ours.** *War in Middle Earth* was published for the MSX on tape. **The binary carries no credits at all** — no publisher, no year, no names — so this repository makes no claim about who made it: all the tape can tell us is what the code does. All rights over the game remain with their
holders.

**What is ours** are this repository's tools, the comments in the listing, the
analysis and the documentation. That is published under the licence in
`LICENSE`.

## What is in this repository

The file The files in `src/` are the disassembly of the five modules on the tape. It
is published for the **preservation, study and documentation** of a title
that is part of MSX software history.

The tape image is **not** distributed here. Anyone who wants to
rebuild the listing has to supply their own, and the `Makefile` checks its
sha256 before doing anything. Nor are the cartridge ROMs (`war.rom`,
`war_parche.rom`, `war_musica.rom`) that `make rom` builds from it: they are the
same game in a different case, and everyone builds them from their own tape.

## Other people's code that the cartridge uses

**This cartridge uses ZX0.** The format and the compressor are by **Einar
Saukas** ([github.com/einar-saukas/ZX0](https://github.com/einar-saukas/ZX0)),
with contributions from Urusergi and introspec. Its licence allows the
decompressor to be used freely inside your own programs, even commercial ones,
in exchange for one thing only: **saying so in your documentation**. It is said
here, in the `README`, and in `src/cartucho/dzx0.asm` itself, which carries the
translation of his assembly to pasmo syntax and nothing else. **The compressor
is not copied here**: it is the `zx0.exe` that ships with
[MSXgl](https://github.com/aoineko-fr/MSXgl), and you pass its path.

**The music replayer is not ours either.** `PT3-ROM.ASM` is by Bulba, Dioniso,
msxKun and SapphiRe, ships inside [msx-msxlib](https://github.com/theNestruo/msx-msxlib)
by Néstor Sancho and **carries no written licence**: only a *"hope you find
useful this code"*. So all that lives here is `tools/convierte_pt3.py`, which
translates it from asMSX to pasmo, and everyone supplies their own copy. **The
`.pt3` module is not distributed either**: it belongs to its author.

The images produced by `tools/render_graficos.py` are not illustrations brought in
from outside: they are the game's own video memory, rebuilt by replaying the
copies the cartridge makes —the same addresses and the same order that are in
the listing— and drawn as they come. They are part of the proof that the
reading of the binary is right: if it were wrong, they would come out as noise.

## What it rests on

Nobody else's work. Everything stated here comes from reading this binary, and
each claim carries its evidence next to it: the instruction that reads a datum,
the table that ends exactly where it has to end, or the arithmetic that works
out. What is not settled is said not to be.

## If you are one of the authors

If you worked on *War in Middle Earth* or hold rights over the game, and you would
rather this material were not published, **say so and it comes down, no
argument**. The intent of this work is the opposite of harming you: it is to
put on record how it was made.
