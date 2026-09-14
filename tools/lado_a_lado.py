#!/usr/bin/env python3
"""Dos pantallas del juego, una al lado de la otra, con su rotulo.

    lado_a_lado.py <salida.png> <izq.png> "<rotulo>" <der.png> "<rotulo>"
"""
import sys
from PIL import Image, ImageDraw


def main(argv):
    if len(argv) != 6:
        print(__doc__)
        return 2
    salida, ai, ti, ad, td = argv[1:]
    a = Image.open(ai).convert("RGB")
    b = Image.open(ad).convert("RGB")
    if a.size != b.size:
        b = b.resize(a.size, Image.NEAREST)
    w, h = a.size
    alto_rotulo = 22
    out = Image.new("RGB", (w * 2 + 12, h + alto_rotulo), (24, 24, 24))
    out.paste(a, (0, alto_rotulo))
    out.paste(b, (w + 12, alto_rotulo))
    d = ImageDraw.Draw(out)
    d.text((4, 6), ti, fill=(255, 255, 255))
    d.text((w + 16, 6), td, fill=(255, 255, 255))
    out.save(salida)
    print("%s: %dx%d" % (salida, out.size[0], out.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
