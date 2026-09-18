#!/usr/bin/env python3
"""¿Se pone la marca donde toca, y se BORRA cuando la unidad se mueve?

Come los volcados de tools/omsx_marcas.tcl -dos repintados del mapa general- y
comprueba cuatro cosas sobre cada uno. Las tres primeras son sobre la pantalla
tal como el jugador la ve; la cuarta es la que sostiene todo el diseño.

  1. TODA celda con el atributo de marca lleva el dibujo en la VRAM, clavado.
     Ademas de que se estampa, esto mide el RITMO: el volcado se hace con la
     pantalla encendida, y si el bucle fuera mas rapido de lo que el TMS9918
     admite se le caerian bytes y el dibujo no saldria igual.

  2. NINGUNA otra celda lo lleva. Esto es el borrado: una marca que no se
     hubiera quitado al moverse la unidad seria un dibujo sin su atributo.

  3. El LIENZO de 0x4000 no tiene el dibujo en ninguna parte: MI_MARCAS estampa
     solo en la VRAM y por eso el lienzo sigue siendo la copia limpia del mapa,
     que es de donde se borra.

  4. Y la cuenta que MI_MARCAS lleva apuntada es la de verdad.

Y antes que nada comprueba que el cotejo COMPRUEBA algo: si entre un repintado
y otro no se hubiera movido ninguna unidad, el punto 2 pasaria solo y no diria
nada. Si las celdas marcadas son las mismas, esto se declara INUTIL y falla.

Uso:
    coteja_marcas.py <dir> <dibujo.png>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import marca                                                # noqa: E402

BITMAP = 0x4000                 # el lienzo del Spectrum, en el volcado de RAM
ATRIBUTOS = 0x5800
FILAS, COLUMNAS = 24, 32
FONDO = 0x30                    # con lo que 0x81C4 pinta el mapa entero


def celda_vram(vram, fila, col):
    """Los ocho bytes del patron de esa celda: fila*0x100 + columna*8."""
    d = fila * 0x100 + col * 8
    return vram[d:d + 8]


def celda_lienzo(ram, fila, col):
    """Y los del lienzo, donde las ocho lineas estan a 256 bytes una de otra."""
    d = ((fila & 0x18) << 8 | (fila & 7) << 5 | col)
    return bytes(ram[d + 0x100 * i] for i in range(8))


def lee(dire, n):
    with open(os.path.join(dire, n), "rb") as f:
        return f.read()


def datos(dire, n):
    d = {}
    with open(os.path.join(dire, "%s.txt" % n)) as f:
        for linea in f:
            k, _, v = linea.strip().partition(" ")
            d[k] = v
    return d


def mira(dire, n, dibujo, fallos):
    ram = lee(dire, "%s.ram" % n)
    vram = lee(dire, "%s.vram" % n)
    d = datos(dire, n)
    atributo = int(d["atributo"])
    apuntadas = int(d["marcas"])

    marcadas, con_dibujo, huerfanas, mal_puestas, en_el_lienzo = set(), set(), [], [], []
    for fila in range(FILAS):
        for col in range(COLUMNAS):
            a = ram[ATRIBUTOS - BITMAP + fila * COLUMNAS + col]
            es_marca = a == atributo
            tiene = celda_vram(vram, fila, col) == dibujo
            if es_marca:
                marcadas.add((fila, col))
                if not tiene:
                    mal_puestas.append((fila, col))
            elif tiene:
                huerfanas.append((fila, col))
            if tiene:
                con_dibujo.add((fila, col))
            if celda_lienzo(ram, fila, col) == dibujo:
                en_el_lienzo.append((fila, col))

    print("  repintado %s: atributo 0x%02X, %d celdas marcadas, %d con el dibujo"
          % (n, atributo, len(marcadas), len(con_dibujo)))
    if mal_puestas:
        fallos.append("repintado %s: %d celdas marcadas SIN el dibujo clavado %s"
                      % (n, len(mal_puestas), mal_puestas[:8]))
    if huerfanas:
        fallos.append("repintado %s: %d dibujos SIN atributo de marca -no se borraron- %s"
                      % (n, len(huerfanas), huerfanas[:8]))
    if en_el_lienzo:
        fallos.append("repintado %s: el dibujo esta en el LIENZO de 0x4000 en %s; "
                      "MI_MARCAS solo debe tocar la VRAM" % (n, en_el_lienzo[:8]))
    if apuntadas != len(marcadas):
        fallos.append("repintado %s: MI_MARCAS apunta %d marcas y en la pantalla hay %d"
                      % (n, apuntadas, len(marcadas)))
    return marcadas


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    dire, png = argv[1], argv[2]
    dibujo = marca.lee_png(png)
    print("el dibujo, de %s: %s" % (os.path.basename(png),
                                    " ".join("%02X" % b for b in dibujo)))
    cuales = sorted(int(f.split(".")[0]) for f in os.listdir(dire) if f.endswith(".txt"))
    if len(cuales) < 2:
        print("hacen falta DOS repintados por lo menos y hay %d" % len(cuales),
              file=sys.stderr)
        return 1

    fallos = []
    vistas = [mira(dire, n, dibujo, fallos) for n in cuales]

    # ¿Comprueba algo esto? El borrado solo se ejercita si alguna celda DEJA de
    # estar marcada. Que aparezcan celdas nuevas no vale: eso prueba que se
    # estampa, que es lo otro. Y no basta con que "cambien" celdas, porque un
    # cambio puede ser solo una celda de mas.
    vaciadas = vistas[0] - vistas[-1]
    nuevas = vistas[-1] - vistas[0]
    print("  del primer repintado al ultimo: %d celdas se quedan sin marca y "
          "%d aparecen" % (len(vaciadas), len(nuevas)))
    if not vaciadas:
        print("INUTIL: ninguna celda dejo de estar marcada entre los dos "
              "repintados, asi que el borrado no se ha probado ni una vez",
              file=sys.stderr)
        return 1

    for f in fallos:
        print("FALLO: " + f, file=sys.stderr)
    if fallos:
        return 1
    print("EN VERDE: el dibujo esta en todas las celdas marcadas y en ninguna mas, "
          "el lienzo sigue limpio y la cuenta cuadra")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
