# The patch

Seven changes, **197 bytes**, none outside the table and none shifted: every
patch is exactly as long as what it replaces, so no address in the game moves.

## The table

| address | block | bytes | what |
|---|---|---|---|
| `0x7FD1` | middle | 1 | the planting loop's limit, `0x78` → `0x00` |
| `0x708A` | middle | 3 | trampoline to the attribute routine |
| `0x6600` | middle | 76 | `MUESTRA_LOS_VALORES` |
| `0x664C` | middle | 61 | planting by side, drawing by side, and the deadline |
| `0x7FC9` | middle | 5 | planting hook |
| `0x770A` | middle | 10 | drawing hook |
| `0x6F77` | middle | 5 | ring hook |
| `0xA1E7` | high | 36 | the four tiles of the Eye of Sauron |

The addresses are **execution** addresses. The "middle" block runs from
`0x5E00` and the "high" one from `0x9E00`.

## How it is applied

The disassembly is never touched. It starts from the **block bodies** that
`make extract` pulls out of your tape (`work/*.raw`, the same bytes without the
Spectrum format's wrapper), applies the table in `tools/parchea.py`, and rebuilds
the cassette by re-wrapping each block with its flag in front and its XOR behind.

Every entry in the table carries **the bytes it expects to find**. If they are
not there, `make parche` aborts: wrong tape. And when it finishes it checks that,
outside the table's ranges, the body is identical to the original.

## Where the new code lives

The 137 bytes of new code — 76 for the attribute routine and 61 for the second
round — are written **over the ZX Spectrum's beeper engine**, at
`0x6600`-`0x6688`.

The conversion brought that engine across whole and **nothing ever calls it**:
not one instruction in the five listings points at `0x6600`, and the four places
that ask for a sound effect call `0x65FF`, which is a bare `ret`. Of the MSX's
PSG only two registers are ever written, 7 and 14, and both are for reading the
joystick. This game is silent, and its silence gives us 276 bytes of room.

## The IPS

`make ips` produces **`war_parche.ips`**: 249 bytes in eight records, holding
only what changes. Verified on the spot — and in the tests — that **applied to
`war.tsx` it gives back the patched cassette byte for byte**.

That is what gets shared. Not the game.

## The checks

`make test` is 23 of them, and they are not decoration. Among others:

- that **`orig` and `nuevo` are the same length** in all seven entries, i.e.
  nothing shifts;
- that every entry **falls inside its block**;
- that the table's bytes are **exactly** what comes out of assembling
  `src/parche/ficha_valores.asm` and `src/parche/icono_enemigo.asm` with pasmo;
- that the second round's three hooks **point where they should** inside the new
  routine;
- that the patch **never writes into the artwork table at `0x77B5`**, which is
  the trap described in [Findings](FINDINGS.md);
- that the four tiles of the Eye go into the slot that was all zeros and **with
  the same colour attribute as the friendly icon**;
- and that the repository's IPS **rebuilds the patched cassette**.
