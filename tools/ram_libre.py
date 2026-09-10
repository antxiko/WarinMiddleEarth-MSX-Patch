#!/usr/bin/env python3
"""Junta lo que midio tools/omsx_ram_libre.tcl con lo que dice el listado, y saca
la tabla de RAM LIBRE: tramos que nadie leyo ni escribio en toda la partida.

Entra el fichero .bandas de una pasada (cada linea: banda, ini, fin, primer
toque de lectura y de escritura, o '-' si no hubo), y sale:

  - los tramos intocados, fundidos, con su tamano;
  - los tramos SOLO LEIDOS (nadie escribe: datos que podrian ir en ROM);
  - y por cada tramo, que dice de el la cinta (dentro de que bloque cae).

Uso:
    python3 tools/ram_libre.py work/ram/fino.bandas [work/ram/grueso.bandas ...]

Con varios ficheros, un byte cuenta como tocado si lo toco CUALQUIERA de las
pasadas: lo que se quiere es lo que queda libre en TODAS.
"""
import sys

# Lo que trae la cinta, por bloques, tal como lo carga y recoloca el arranque.
CINTA = [(0x0190, 0x3F4F, "bloque bajo"),
         (0x5E00, 0x96F1, "bloque medio"),
         (0x9E00, 0xE678, "bloque alto")]
# Y lo que el juego monta encima al arrancar, que no viene en la cinta.
MONTADO = [(0x0000, 0x0190, "cabecera: 0x0038 = jp 0x0400; 0x012C, los POKEs del cargador"),
           (0x4000, 0x5B00, "pantalla del ZX emulada (bitmap + atributos)"),
           (0x5B00, 0x5C00, "pila, desde 0x5BFF hacia abajo"),
           (0xCC00, 0xFFCD, "el mapa descomprimido (0x33CD bytes desde 0xCC00)"),
           (0xE800, 0xF400, "batalla: las capas de fichas y sus copias")]


def lee(ruta):
    toc = {}
    for lin in open(ruta, encoding="utf-8"):
        if lin.startswith("#") or not lin.strip():
            continue
        p = lin.split()
        ini, fin = int(p[1], 16), int(p[2], 16)
        toc[(ini, fin)] = (p[3] != "-", p[4] != "-", p[3], p[4])
    return toc


def donde(a):
    for ini, fin, que in CINTA + MONTADO:
        if ini <= a < fin:
            return que
    return "fuera de la cinta"


def funde(tramos):
    out = []
    for ini, fin in sorted(tramos):
        if out and out[-1][1] + 1 == ini:
            out[-1][1] = fin
        else:
            out.append([ini, fin])
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    leido, escrito = {}, {}
    banda = None
    for ruta in argv[1:]:
        for (ini, fin), (r, w, pr, pw) in lee(ruta).items():
            banda = fin - ini + 1 if banda is None else min(banda, fin - ini + 1)
            # con bandas de distinto tamano, se reparte al grano mas fino
            for a in range(ini, fin + 1, 16):
                leido[a] = leido.get(a, False) or r
                escrito[a] = escrito.get(a, False) or w
    granos = sorted(leido)
    libres = [(a, a + 15) for a in granos if not leido[a] and not escrito[a]]
    solo_lee = [(a, a + 15) for a in granos if leido[a] and not escrito[a]]

    total = 0
    print("== RAM que nadie leyo ni escribio en la partida ==")
    print("   %-13s %6s  %s" % ("tramo", "bytes", "que hay ahi segun la cinta"))
    for ini, fin in funde(libres):
        n = fin - ini + 1
        total += n
        print("   %04X-%04X  %6d  %s" % (ini, fin, n, donde(ini)))
    print("   %-13s %6d" % ("TOTAL", total))

    total = 0
    print("\n== Solo LEIDO (nadie escribe): podria vivir en ROM ==")
    for ini, fin in funde(solo_lee):
        n = fin - ini + 1
        total += n
        print("   %04X-%04X  %6d  %s" % (ini, fin, n, donde(ini)))
    print("   %-13s %6d" % ("TOTAL", total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
