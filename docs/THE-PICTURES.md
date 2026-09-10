# The pictures

Not one picture on this site is a screenshot, and **it cannot be**. This page
explains why and what is done instead, because the method works for any game
that behaves the same way.

## The problem: the screen is never still

The first "without / with" pair came out with **33 % of its pixels different**,
and that for a change which only adds three silhouettes. Before trusting that
number it needed a control, and the control demolished it:

| measurement | pixels differing |
|---|---|
| two runs of the **same** state, photo against photo | **0.0 %** |
| two photos of the same state **3 s** apart | **37 %** |
| without the patch against with it | 33 % |

So: the emulation is deterministic — two identical runs give the same picture to
the pixel — but **the game re-uploads the screen to the VDP constantly** and the
capture catches the upload half done. Comparing photographs, here, proves
nothing.

## The way out: the Spectrum's buffer

This conversion does not draw into the MSX's VRAM: it draws into **a ZX Spectrum
screen assembled in RAM**, at the same addresses a Spectrum would use, and
uploads the lot every so often.

- `0x4000`-`0x57FF`: the 6,144 bytes of bitmap, with the Spectrum's tangle
  (third, pixel line, character row).
- `0x5800`-`0x5AFF`: the 768 attributes, one per 8×8 cell.
- `PANTALLA_A_VRAM` (`0x05BD`) uploads them untangling the order, and
  `ATRIBUTOS_A_VRAM` (`0x0604`) translates each ZX attribute into the MSX's
  colour byte using **the table at `0x0200`**, which the game itself fills in at
  boot.

So what gets dumped is that buffer, at a fixed instant, and `tools/render_zx.py`
draws it **with the cartridge's own colour table**, not with an invented palette.

## That the buffer *is* still, measured

Two dumps of the same state **fifteen emulated seconds** apart:

    32 bytes differing out of 6,912

and all 32 are columns 14 and 15, pixel rows 81 to 88: **the cursor blinking**.
Everything else identical.

## How a pair is made

`tools/omsx_zx.tcl` starts from a saved state at the menu, writes the cursor
position, forces a fire — which is what triggers `RECENTRA_EL_MAPA` — and dumps
the buffer. It is run twice, once with the original cassette and once with the
patched one, **with the same parameters**, and both dumps are drawn.

With that, whatever differs between the two pictures is the patch.

## Three emulator traps that turned up on the way

**A `return` inside an openMSX breakpoint body kills it**, silently: it stops
firing and nothing complains. And **two breakpoints at the same address** are no
good either: the second is never registered, the first keeps working, and it
looks as if that code never runs.

**You cannot write a game variable "just to look".** To see another unit's sheet
we tried writing the `0x6EAD` selector from the debugger, three different ways,
and all three ended with the game acting on that unit and building another
screen on top of the patched code. You can tell because the patch's bytes stop
being where they were put — which is why the dump re-reads them and logs them.

What does work is **handing the game the input a player would give it**: a
breakpoint where it reads the controls, and forcing the key's bit there. The path
is in the listing itself: fire over the cell (`0x7229`) to enter
`ELIGE_ENTRE_LAS_DE_LA_CASILLA`, then "next" (`0x775B`) until you reach the unit
you want to see.

## The tools

| tool | what it does |
|---|---|
| `tools/omsx_zx.tcl` | dumps the ZX buffer, the colour table and the map |
| `tools/render_zx.py` | draws it to PNG with the cartridge's colours |
| `tools/omsx_mapa.tcl` | dumps just the `0xCC00` map, for counting cells |
| `tools/omsx_censo.tcl` | dumps all 256 unit slots at the start of a game |
| `tools/render_icono.py` | draws one 2×2 entry of the `0x77B5` table |
| `tools/icono_a_tiles.py` | turns a 16×16 PNG into the four nine-byte tiles |
| `tools/lienzos.py` | exports the tiles, the sprites and the font to three editable 1:1 PNGs, and reads them back |
| `tools/previo_repinta.py` | repaints an existing screen, cell by cell, with the canvas's tiles |
| `tools/cuerpo_parcheado.py` | the same block body with the patch applied, for drawing the "after" plates |

## Seeing a repaint before touching the cassette

Repainting 128 tiles and finding out afterwards that the map does not read is an
expensive way to work. `tools/previo_repinta.py` avoids it: it takes a screen
already dumped from the game and **identifies each of its 768 cells** against the
cassette's tiles and font — the eight bytes of the drawing, and the two colours
the attribute would give — and draws it again with the canvas's tiles. What it
cannot identify it leaves alone and reports, so nothing gets invented. Across the
four screens used here, **768 of 768 cells were identified in each**.

It also takes the font's attribute as an argument, which is how the khaki paper
was looked at before spending a byte on it.

And then it was checked against the real thing. The same screen, dumped from the
patched cassette running in the emulator, against the preview:

    0 pixels differing out of 196,608

The preview is not an illustration: it is what the machine ends up drawing.
