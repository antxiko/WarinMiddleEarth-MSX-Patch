#!/usr/bin/env python3
"""Dibuja uno de los cuadros de dos por dos de la tabla de 0x77B5, sacando cada
caracter de la tabla de tiles del mapa (0x9E00, nueve bytes por tile: ocho de
dibujo y el atributo del ZX detras).

    python3 tools/render_icono.py <imagen64k.bin> <dibujo> <salida.png> [escala]
    python3 tools/render_icono.py <imagen64k.bin> 111,112,113,114 <salida.png>
"""
import os
import struct
import sys
import zlib

# EL ATRIBUTO ES DEL SPECTRUM, PERO EL COLOR QUE SE VE ES DEL MSX: el juego no
# manda el atributo a la pantalla, lo traduce antes ATRIBUTO_A_COLOR (0x049F)
# con dos tablas de ocho colores (0x04CE sin brillo, 0x04D6 con el). Aqui se
# dibuja con los del MSX, los que ve quien juega, y salen de tools/lienzos.py
# para que todo lo que dibuja esta serie de herramientas dibuje igual.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lienzos import ZX_EN_MSX                                   # noqa: E402


def png(w, h, filas, fn):
    raw = b"".join(b"\x00" + bytes(f) for f in filas)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    open(fn, "wb").write(b"\x89PNG\r\n\x1a\n"
                         + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    m = open(sys.argv[1], "rb").read()
    out = sys.argv[3]
    esc = int(sys.argv[4]) if len(sys.argv) > 4 else 12

    # El segundo argumento es una entrada de la tabla de 0x77B5 -y entonces los
    # cuatro codigos salen de ella- o los CUATRO TILES a pelo, separados por
    # comas. Lo segundo hace falta para el Ojo de Sauron: el parche no lo mete
    # en esa tabla, DIBUJO_SEGUN_BANDO apunta HL a su propia lista de cuatro.
    if "," in sys.argv[2]:
        codigos = bytes((int(t, 0) & 0x7F) | 0x80 for t in sys.argv[2].split(","))
        print(f"tiles sueltos: {' '.join(f'{c & 0x7F:d}' for c in codigos)}")
    else:
        dib = int(sys.argv[2], 0)
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
            brillo = 8 if atr & 0x40 else 0
            tinta, papel = (atr & 7) | brillo, ((atr >> 3) & 7) | brillo
            fila += list(ZX_EN_MSX[tinta if bit else papel]) * esc
        for _ in range(esc):
            filas.append(fila)
    png(16 * esc, 16 * esc, filas, out)
    print(f"{out}: 16x16 x{esc}")


if __name__ == "__main__":
    main()
