#!/usr/bin/env python3
"""Dibuja el mapa general A PARTIR DE UN VOLCADO de 0xCC00.

tools/mapa_general.py dibuja SIEMPRE el mapa que viene comprimido en la cinta.
Esto hace lo mismo -la misma transcripcion de PINTA_TERRENO_ALTO y
PINTA_TERRENO_BAJO- pero con el mapa que haya en un volcado, que es lo que
hace falta para ver como estaba el mapa en un momento de una partida.

    dibuja_el_mapa_de.py <mapa.bin de 0x33CC bytes> <salida.png> [work]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapa_general                                          # noqa: E402


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    volcado, salida = argv[1], argv[2]
    work = argv[3] if len(argv) > 3 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "work")
    with open(os.path.join(work, "medio.raw"), "rb") as f:
        medio = f.read()
    with open(volcado, "rb") as f:
        mapa = f.read()
    # El motor lee 0x33CD: uno mas de los 0x33CC que ocupa el mapa.
    if len(mapa) < 0x33CD:
        mapa = mapa + b"\x00" * (0x33CD - len(mapa))
    d = mapa_general.Dibujante(medio, mapa)
    d.dibuja()
    mapa_general.a_png(d.lienzo(), salida)
    print("%s: el mapa de %s, 256 x 192" % (salida, volcado))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
