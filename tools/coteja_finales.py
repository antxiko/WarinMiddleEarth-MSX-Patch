#!/usr/bin/env python3
"""Coteja las dos pantallas finales del cartucho con las de la cinta.

Los volcados los hace tools/omsx_finales.tcl forzando el PC en 0x83E7, que es
donde los cuatro finales del juego convergen.

DOS COTEJOS, Y EL PRIMERO ES EL QUE DECIDE

  1. Los 6.912 bytes que quedan en 0x4000 contra los de la cinta. Es una verdad
     absoluta y no una comparacion entre dos ROMs: ahi es de donde 0x05BD y
     0x0604 sacan lo que suben al VDP, asi que si esos bytes son los de la cinta
     el jugador ve exactamente la misma pantalla.
  2. La VRAM despues de pintarla, contra la de otra ROM si se da. Esto no
     sustituye al primero -las dos podrian estar mal igual- pero cierra el
     circulo: lo que acaba en la pantalla es lo mismo que antes.

Uso: coteja_finales.py <dir volcados> <dir work> [<dir volcados de referencia>]
Sale con 1 si algo de lo exigido no cuadra.
"""
import os
import sys

# Donde vive cada pantalla dentro del bloque bajo, que se carga en 0x0190.
CARGA_BAJO = 0x0190
PANTALLAS = (("victoria", 0x094F, 6912), ("derrota", 0x244F, 6912))


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    volcados, work = argv[1], argv[2]
    referencia = argv[3] if len(argv) > 3 else None
    bajo = lee(os.path.join(work, "bajo.raw"))
    fallos = 0

    for nombre, dir_, tam in PANTALLAS:
        ruta = os.path.join(volcados, "pantalla_%s.bin" % nombre)
        if not os.path.exists(ruta):
            print("  falta %s: la sonda no llego a volcarla" % ruta)
            fallos += 1
            continue
        salido = lee(ruta)[:tam]
        o = dir_ - CARGA_BAJO
        esperado = bajo[o:o + tam]
        d = [i for i in range(tam) if salido[i] != esperado[i]]
        print("  %-8s 0x4000-0x%04X contra la cinta (0x%04X)   %s"
              % (nombre, 0x4000 + tam - 1, dir_,
                 "OK" if not d else "%d bytes distintos, p.ej. +0x%04X" % (len(d), d[0])))
        fallos += len(d)

    if referencia:
        for nombre, _dir, _tam in PANTALLAS:
            a = os.path.join(volcados, "vram_%s.bin" % nombre)
            b = os.path.join(referencia, "vram_%s.bin" % nombre)
            if not (os.path.exists(a) and os.path.exists(b)):
                print("  falta un volcado de VRAM de %s" % nombre)
                fallos += 1
                continue
            va, vb = lee(a)[:0x4000], lee(b)[:0x4000]
            d = [i for i in range(0x4000) if va[i] != vb[i]]
            print("  %-8s VRAM 0x0000-0x3FFF contra %s   %s"
                  % (nombre, os.path.basename(referencia),
                     "OK" if not d else "%d bytes distintos, p.ej. 0x%04X" % (len(d), d[0])))
            fallos += len(d)

    print("RESULTADO: %s" % ("las dos pantallas son las de la cinta" if not fallos
                             else "%d diferencias" % fallos))
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
