# The cartridge

The game shipped on cassette and takes **six and a half minutes** to load. This
turns it into a cartridge that boots in **nine seconds**, without changing a
single byte of the game.

**There is no ROM here either.** You build it from your own tape:

    make rom          # war.rom, from the original tape
    make rom_parche   # war_parche.rom, from the patched one

Both come out at 64 KB, **ASCII16** type, and neither is distributed: they are
the whole game in a different case (see the [legal notice](https://github.com/antxiko/WarinMiddleEarth-MSX-Patch/blob/main/LEGAL-NOTICE.md)).

    openmsx -machine Philips_VG_8020 -carta war.rom -romtype ascii16

## The idea: do not touch the game, imitate its loader

The cartridge is not a conversion, it is a **loader**. It leaves RAM exactly as
the tape loader leaves it and jumps to the same place, `0x0190`, where the game
itself relocates its blocks the way it always does.

| what it leaves | where |
|---|---|
| low block | `0x0190` |
| middle block | `0x3F4F` |
| high block | `0x88B8` |
| POKE mailbox | `0x012C`, zeroed |
| stack | `SP = 0xFDE8` |

That is what makes it checkable: if RAM is the same, the game cannot tell how
it got there.

## How it is built

**77 bytes of boot code** in the ROM (`src/cartucho/cargador_rom.asm`): the `AB`
header, bank 0, copy the rest into RAM and jump to it.

**A 977-byte stub** running at `0xD800` (`src/cartucho/cargador_ram.asm`): it
looks for RAM in pages 2, 1 and 0 and interprets a **plan of 52 operations** of
eight bytes each. The plan is not written by hand: `tools/haz_rom.py` generates
it from the ROM's real layout and also writes it to `work/plan.json`, so the
checks never have to assume anything.

The data runs from `0x0800` to `0xF727`. **2,264 bytes** are left over.

## The two hard parts

**Page 1 is the ROM while loading.** With the cartridge in,
`0x4000`-`0x7FFF` is the cartridge, and **14,400 bytes** of the middle block
land there (`0x4000`-`0x783F`). There is nowhere to put them — except **VRAM**,
which is free during loading: they are copied there, the cartridge is switched
out of page 1, and they come back. The buffer reaches `0x383F` and **overwrites
the name table and the sprite tables**, so those get written twice, before and
after.

**The game inherits its screen from BASIC.** It only ever writes VDP register 7
and **never** the name table: it relies on the `COLOR 1,1,1:SCREEN 2` in the two
lines of BASIC the tape runs before loading anything. A cartridge boots without
that BASIC, so it has to be reproduced. This was not deduced, it was
**measured** on the tape with `tools/omsx_estado_cinta.tcl`.

    VDP R0-R7   02 E0 06 FF 03 36 07 01
    PSG         R7 reads back 0x3F, R11 = 0x0B
    VRAM        identity name table, 32 sprites at Y=209

## The slots

The BIOS has `ENASLT` to change what sits in a page, and it works for pages 2
and 1 as long as page 0 is still the BIOS. Page 0 and everything after it need
a clone of our own, with one precaution: it **must not flip page 3**, which is
where the stub lives. It writes `0xFFFF` only when the destination's primary
slot is the same as page 3's.

Tested with RAM in an **expanded slot** (Philips NMS 8250, 3-2), which is the
case that breaks loaders that get this wrong.

## What is verified

`tools/omsx_verifica_rom.tcl` boots the machine with the cartridge in and dumps
exactly what was dumped when loading the tape, at the same two instants;
`tools/coteja_rom.py` compares them byte for byte.

| instant | what is compared |
|---|---|
| at `0x0190` | the blocks as they fall off the tape, before relocation |
| at `0x5E00` | the three blocks relocated, all 16 KB of VRAM, VDP R0-R7 and PSG R0-R13 |

Result: **everything required matches**, with `war.rom` on a Philips VG-8020, a
Philips NMS 8250, C-BIOS MSX1 and C-BIOS MSX2, and with `war_parche.rom` on the
VG-8020 against the patched tape's dumps.

On MSX2, register 1 reads back `0x60`: the V9938 has no 4K/16K bit of the
TMS9918. That is accepted, and said out loud.

Eight more checks live in `tests/test_cartucho.py`. The strong one is an
**interpreter of the plan, written separately in Python**, tracking RAM, VRAM
and what sits in page 1 at every step: if the plan ever tried to write to
`0x4000`-`0x7FFF` with the cartridge in, it shows up there without an emulator.

## What is not verified

**Nobody has played a whole game from the cartridge.** It has been seen to
boot, the menu, and the map after pressing `0`. That is all.

And the cartridge has **no music**: the game is silent on tape and stays silent
here. That is the obvious extension, and it is written down in
[open questions](OPEN-QUESTIONS.html).
