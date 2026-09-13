#!/usr/bin/env python3
"""¿Cambia el terreno durante la partida? Los dos volcados, comparados.

Es lo que sostiene el mapa general ya dibujado (--mapa): si el nibble bajo de
alguna casilla cambiara mientras se juega, el lienzo que viaja en la ROM
dejaria de ser el que el juego dibujaria, y se veria un mapa viejo.

tools/omsx_terreno_quieto.tcl reproduce la partida grabada de Araubi y vuelca
el mapa (0xCC00, 13.260 bytes) al empezar y al acabar. Aqui se comparan los
NIBBLES BAJOS, que es lo unico que miran las dos pasadas de terreno, y ademas
se comprueba que los dos volcados coinciden con el mapa tal y como sale de la
cinta: asi no vale con que los dos estuvieran mal igual.

Uso:  coteja_terreno.py <dir de los volcados> <work>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_mapa_completo                                 # noqa: E402

MAPA = 0xCC00


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    d, work = argv[1], argv[2]
    antes = lee(os.path.join(d, "mapa_antes.bin"))
    despues = lee(os.path.join(d, "mapa_despues.bin"))
    cinta = render_mapa_completo.descomprime_el_mapa(lee(os.path.join(work, "alto.raw")))
    fallos = 0
    for que, a, b in (("entre el principio y el final de la partida", antes, despues),
                      ("entre la cinta y el principio de la partida", cinta, antes),
                      ("entre la cinta y el final de la partida", cinta, despues)):
        assert len(a) == len(b), "los volcados no miden lo mismo"
        dif = [i for i in range(len(a)) if (a[i] ^ b[i]) & 0x0F]
        if dif:
            fallos += 1
            print("  MAL  %s cambian %d nibbles bajos; el primero, 0x%04X: %02X -> %02X"
                  % (que, len(dif), MAPA + dif[0], a[dif[0]], b[dif[0]]))
        else:
            print("  OK   %s no cambia ni un nibble bajo" % que)
    # y lo que SI cambia, que es lo que se espera: banderas de los bits altos
    banderas = [i for i in range(len(antes)) if antes[i] != despues[i]]
    bits = 0
    for i in banderas:
        bits |= antes[i] ^ despues[i]
    print("  %d casillas cambian durante la partida, y solo en los bits 0x%02X (banderas de unidad)"
          % (len(banderas), bits))
    if bits & 0x0F:
        print("  MAL  alguna bandera cae en el nibble bajo")
        fallos += 1
    print("VERDE" if not fallos else "ROJO")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
