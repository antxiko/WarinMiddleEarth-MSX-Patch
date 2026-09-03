#!/usr/bin/env python3
"""Pasa un icono de 16x16 en blanco y negro a los CUATRO tiles de 8x8 con que
el juego estampa un cuadro de dos por dos.

Cada tile de la tabla de 0x9E00 mide NUEVE bytes: ocho de dibujo (una fila de
pixels por byte, el bit 7 a la izquierda) y detras el atributo del ZX Spectrum
de esa celda (bits 0-2 tinta, 3-5 papel, 6 brillo). Un pixel negro es tinta.

El orden es el que espera ESTAMPA_DOS_POR_DOS (0x7717): arriba-izquierda,
arriba-derecha, abajo-izquierda y abajo-derecha.

    python3 tools/icono_a_tiles.py <icono.png> [atributo]

Escribe por pantalla los 36 bytes en hexadecimal, listos para la tabla de
tools/parchea.py, y dibuja el icono en texto para poder cotejarlo.
"""
import sys

from PIL import Image

ATRIBUTO_POR_DEFECTO = 0x38   # tinta 0 (negro) sobre papel 7 (blanco): el aliado


def tiles(ruta, atributo):
    im = Image.open(ruta).convert("L")
    if im.size != (16, 16):
        raise SystemExit("el icono tiene que ser de 16x16, y es de %dx%d" % im.size)
    pix = im.load()
    salida = []
    for cy in (0, 8):
        for cx in (0, 8):
            if (cy, cx) == (0, 8):
                pass
            tile = []
            for y in range(8):
                b = 0
                for x in range(8):
                    if pix[cx + x, cy + y] < 128:      # negro = tinta
                        b |= 0x80 >> x
                tile.append(b)
            tile.append(atributo)
            salida.append(bytes(tile))
    # ESTAMPA los quiere en orden TL, TR, BL, BR, que es justo como salen del
    # doble bucle de arriba (cy externo, cx interno).
    return salida


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    atributo = int(sys.argv[2], 0) if len(sys.argv) > 2 else ATRIBUTO_POR_DEFECTO
    cuatro = tiles(sys.argv[1], atributo)

    im = Image.open(sys.argv[1]).convert("L")
    pix = im.load()
    print("el icono, para cotejarlo:")
    for y in range(16):
        print("   " + "".join("#" if pix[x, y] < 128 else "." for x in range(16)))

    print("\nlos cuatro tiles (ocho bytes de dibujo + el atributo 0x%02X):" % atributo)
    for nombre, t in zip(("arriba-izq", "arriba-der", "abajo-izq", "abajo-der"), cuatro):
        print("   %-11s %s" % (nombre, " ".join("%02X" % v for v in t)))
    print("\nlos 36 bytes seguidos, para la tabla del parche:")
    print(b"".join(cuatro).hex())


if __name__ == "__main__":
    main()
