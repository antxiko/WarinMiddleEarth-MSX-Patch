#!/usr/bin/env python3
"""¿Llega a la VRAM todo lo que el juego dibuja en el tablero de la batalla?

El juego es un port del Spectrum: dibuja en su pantalla emulada de 0x4000 y
luego la sube a la tabla de patrones del SCREEN 2. Asi que hay dos versiones de
lo mismo, y tienen que ser identicas:

    el bufer de 0x4000    lo que el juego CREE que hay
    la VRAM 0x0000        lo que el VDP tiene de verdad, y lo que se ve

Si no lo son, es que alguna escritura se cayo: con la pantalla encendida el
TMS9918 no admite dos accesos a la VRAM a menos de unos 29 ciclos, y al que va
mas rapido se le comen bytes. Eso es lo que hacia que las figuras salieran
rotas -lo vio el usuario jugando-: las dos rutinas del juego que suben el
tablero, BITMAP_A_VRAM (0x05BD) y RECUADRO_A_VRAM (0x0702), van a 22.

Se mira SOLO el tablero (las filas 2 a 17): la franja de arriba lleva el texto
-que se escribe por otro camino- y la de abajo esta en negro.

Uso:
    coteja_batalla.py <dir> [--tope N]

`--tope` es cuantos bytes distintos se toleran; por defecto 0. Con la ROM sin
arreglar salen unos 1.500 de 6.144.
"""
import os
import sys

FILA_PRIMERA, FILA_ULTIMA = 2, 17       # el tablero; fuera van el texto y el negro
TAM = 0x1800


def zx_a_vram(lienzo):
    """El bufer del ZX tal y como lo sube el juego a la tabla de patrones: en
    el ZX la linea de pixel manda sobre la fila de caracteres y en el MSX es al
    reves."""
    fuera = bytearray(TAM)
    for fila in range(24):
        for linea in range(8):
            for col in range(32):
                zx = ((fila // 8) << 11) | (linea << 8) | ((fila % 8) << 5) | col
                fuera[(fila // 8) * 2048 + (fila % 8) * 256 + col * 8 + linea] = lienzo[zx]
    return bytes(fuera)


def lee(dire, nombre):
    with open(os.path.join(dire, nombre), "rb") as f:
        return f.read()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    dire = argv[1]
    tope = 0
    if "--tope" in argv:
        tope = int(argv[argv.index("--tope") + 1])

    falta = [n for n in ("bitmap.bin", "patrones.bin")
             if not os.path.exists(os.path.join(dire, n))]
    if falta:
        print("faltan %s: ¿corrio tools/omsx_fondo_batalla.tcl?" % ", ".join(falta),
              file=sys.stderr)
        return 1

    subido = zx_a_vram(lee(dire, "bitmap.bin"))
    vram = lee(dire, "patrones.bin")

    malos, celdas = [], set()
    for celda in range(768):
        fila = celda // 32
        if not (FILA_PRIMERA <= fila <= FILA_ULTIMA):
            continue
        d = (fila // 8) * 2048 + (fila % 8) * 256 + (celda % 32) * 8
        for i in range(d, d + 8):
            if subido[i] != vram[i]:
                malos.append(i)
                celdas.add(celda)

    total = (FILA_ULTIMA - FILA_PRIMERA + 1) * 32 * 8
    print("el tablero son %d bytes (filas %d a %d)" % (total, FILA_PRIMERA, FILA_ULTIMA))
    print("bytes que NO llegaron a la VRAM: %d (%.1f %%), en %d celdas de %d"
          % (len(malos), 100.0 * len(malos) / total, len(celdas), total // 8))
    if len(malos) > tope:
        print("FALLO: se toleraban %d y se han caido %d. El tablero se sube mas "
              "rapido de lo que el VDP admite." % (tope, len(malos)), file=sys.stderr)
        return 1
    print("EN VERDE: lo que el juego dibuja es exactamente lo que se ve")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
