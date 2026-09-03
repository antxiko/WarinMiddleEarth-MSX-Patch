#!/usr/bin/env python3
"""Dibuja la pantalla ZX emulada del juego (volcada por tools/omsx_zx.tcl) tal
como la ve un MSX, traduciendo cada atributo del Spectrum con la tabla de
0x0200 que el propio juego rellena.

    python3 tools/render_zx.py <zx.bin> <tabla_color.bin> <salida.png> [escala]

El volcado son 0x1B00 bytes desde 0x4000: 6144 de bitmap con el enredo del
Spectrum (tercio, linea de pixel, fila de celda) y 768 de atributos desde
0x5800. El byte que sale de la tabla es el de color de la VRAM del MSX:
nibble alto = tinta, nibble bajo = papel.
"""
import struct
import sys
import zlib

# Paleta del TMS9918 (los 16 colores del MSX1), en RGB de 8 bits
PALETA = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def png(w, h, filas, fn):
    raw = b"".join(b"\x00" + bytes(f) for f in filas)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    open(fn, "wb").write(b"\x89PNG\r\n\x1a\n"
                         + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(raw, 9))
                         + chunk(b"IEND", b""))


def direccion_zx(y, xb):
    """Byte (xb, y) de la pantalla del Spectrum dentro del bitmap."""
    return ((y & 0xC0) << 5) | ((y & 0x07) << 8) | ((y & 0x38) << 2) | xb


def main():
    zx = open(sys.argv[1], "rb").read()
    tabla = open(sys.argv[2], "rb").read()
    salida = sys.argv[3]
    esc = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    assert len(zx) >= 0x1B00, f"volcado corto: {len(zx)}"
    assert len(tabla) >= 256, f"tabla corta: {len(tabla)}"

    filas = []
    for y in range(192):
        fila = []
        for xb in range(32):
            byte = zx[direccion_zx(y, xb)]
            color = tabla[zx[0x1800 + (y >> 3) * 32 + xb]]
            tinta = PALETA[(color >> 4) & 15]
            papel = PALETA[color & 15]
            for bit in range(8):
                rgb = tinta if (byte >> (7 - bit)) & 1 else papel
                fila += list(rgb) * esc
        for _ in range(esc):
            filas.append(fila)
    png(256 * esc, 192 * esc, filas, salida)
    print(f"{salida}: 256x192 x{esc}")


if __name__ == "__main__":
    main()
