#!/usr/bin/env python3
"""Dibuja uno de los cuadros de dos por dos de la tabla de 0x77B5, sacando cada
caracter de la tabla de tiles del mapa (0x9E00, nueve bytes por tile: ocho de
dibujo y el atributo del ZX detras).

    python3 tools/render_icono.py <imagen64k.bin> <dibujo> <salida.png> [escala]
"""
import struct
import sys
import zlib

PALETA = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
          (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
          (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
          (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]
# El atributo del ZX: bits 0-2 tinta, 3-5 papel, 6 brillo. Se pinta con la
# paleta del MSX equivalente, que es como acaba en pantalla.
ZX = [(0, 0, 0), (0, 0, 200), (200, 0, 0), (200, 0, 200),
      (0, 200, 0), (0, 200, 200), (200, 200, 0), (200, 200, 200)]
ZXB = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
       (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]


def png(w, h, filas, fn):
    raw = b"".join(b"\x00" + bytes(f) for f in filas)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    open(fn, "wb").write(b"\x89PNG\r\n\x1a\n"
                         + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    m = open(sys.argv[1], "rb").read()
    dib = int(sys.argv[2], 0)
    out = sys.argv[3]
    esc = int(sys.argv[4]) if len(sys.argv) > 4 else 12
    codigos = m[0x77B5 + dib * 4: 0x77B5 + dib * 4 + 4]
    print(f"dibujo 0x{dib:02X}: caracteres {' '.join(f'{c:02X}' for c in codigos)}")

    cuad = []
    for c in codigos:
        if c < 0x80:
            cuad.append((bytes(8), 0x38))          # fuente normal: aqui no toca
            continue
        a = 0x9E00 + (c & 0x7F) * 9
        cuad.append((m[a:a + 8], m[a + 8]))
        print(f"   tile {c & 0x7F:3d} @0x{a:04X}  atributo 0x{m[a + 8]:02X}")

    filas = []
    for y in range(16):
        fila = []
        for x in range(16):
            i = (y // 8) * 2 + (x // 8)
            dibujo, atr = cuad[i]
            bit = (dibujo[y % 8] >> (7 - (x % 8))) & 1
            pal = ZXB if atr & 0x40 else ZX
            fila += list(pal[atr & 7] if bit else pal[(atr >> 3) & 7]) * esc
        for _ in range(esc):
            filas.append(fila)
    png(16 * esc, 16 * esc, filas, out)
    print(f"{out}: 16x16 x{esc}")


if __name__ == "__main__":
    main()
