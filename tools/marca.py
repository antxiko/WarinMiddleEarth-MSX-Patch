#!/usr/bin/env python3
"""La marca de las unidades en el mapa general: del PNG a los ocho bytes.

En el mapa general una unidad no es un dibujo: REPINTA_LOS_EJERCITOS (0x6AAF)
le cambia el ATRIBUTO a su celda y nada mas, asi que dos unidades juntas se
funden en una mancha en la que no se puede contar cuantas hay. MI_MARCAS
(src/cartucho/nombres.asm) le estampa ademas un dibujo de 8x8 a esa celda, y
el dibujo va en un PNG que cualquiera puede repintar:

    src/cartucho/marca.png       8 x 8, sin escalar

El de fabrica NO esta inventado: son los ocho bytes del caracter 0x5F de la
fuente del juego, el Anillo que el parche pinta en la ficha del Portador.

UN BIT, UN PIXEL. El color no sale de aqui: lo pone el atributo de la celda
(0x6AE1), que con el parche del panel es 0x78, papel blanco y tinta negra. Por
eso el PNG solo dice QUE PIXELS SE ENCIENDEN:

    negro       el pixel se enciende: se ve con la TINTA de la celda
    blanco      apagado: se ve el PAPEL de la celda

Y por eso tampoco hay transparencia que valga: los ocho bytes sustituyen a los
del mapa en esa celda, no se mezclan con ellos.

Uso:
    marca.py saca <work> <marca.png> [--rehaz]   el Anillo de la fuente
    marca.py mete <marca.png> <marca.inc>        el include para nombres.asm
    marca.py mira <marca.png>                    que lleva
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lienzos                                              # noqa: E402

FUENTE = 0xC800                 # los 128 caracteres, 8 bytes cada uno
CARACTER_ANILLO = 0x5F          # el que el parche pinta en la ficha del Portador
LADO = 8
BYTES = 8
# Lo que se ve hoy con el atributo 0x78: papel blanco y tinta negra. El PNG
# lleva la paleta dentro para que el editor la ofrezca hecha.
APAGADO, ENCENDIDO = 0, 1
PALETA = [lienzos.MSX[15], lienzos.MSX[1]]
NOMBRES = ["el papel de la celda", "la tinta de la celda"]


class ErrorDeMarca(Exception):
    pass


# ------------------------------------------------------------ el de fabrica
def de_fabrica(work):
    """Los ocho bytes del Anillo, sacados de la fuente del bloque alto."""
    ruta = os.path.join(work, "alto_parcheado.raw")
    if not os.path.exists(ruta):
        ruta = os.path.join(work, "alto.raw")
    with open(ruta, "rb") as f:
        alto = f.read()
    base = FUENTE - lienzos.ORG + CARACTER_ANILLO * BYTES
    ocho = alto[base:base + BYTES]
    if len(ocho) != BYTES:
        raise ErrorDeMarca("%s no llega hasta la fuente: %d bytes" % (ruta, len(alto)))
    return bytes(ocho)


def saca(work, ruta_png, rehaz=False):
    if os.path.exists(ruta_png) and not rehaz:
        raise ErrorDeMarca("%s ya existe; --rehaz para pisarlo" % ruta_png)
    indices = lienzos.dibuja_caracter(de_fabrica(work))
    lienzos.escribe_png(ruta_png, LADO, LADO, indices, PALETA)
    return indices


# ------------------------------------------------------------------- el PNG
def lee_png(ruta):
    """El PNG -> los ocho bytes. Todo pixel que no sea el papel, se enciende."""
    ancho, alto, filas, opacos = lienzos.lee_png(ruta)
    if (ancho, alto) != (LADO, LADO):
        raise ErrorDeMarca("el dibujo tiene que medir %dx%d y mide %dx%d. "
                           "No lo escales: un pixel del PNG es un pixel del juego."
                           % (LADO, LADO, ancho, alto))
    indices = []
    for y in range(alto):
        fila = []
        for x in range(ancho):
            # Un bit por pixel: o esta al color del papel (o transparente), o
            # se enciende. Cualquier otro color es "encendido": no hay tercera.
            apagado = not opacos[y][x] or filas[y][x] == PALETA[APAGADO]
            fila.append(APAGADO if apagado else ENCENDIDO)
        indices.append(fila)
    return bytes(lienzos.codifica_caracter(indices, None, 0))


def escribe_inc(png, ruta_inc):
    """El include de nombres.asm: los ocho bytes del dibujo."""
    ocho = lee_png(png)
    with open(ruta_inc, "w") as f:
        f.write("; generado por tools/marca.py de %s: no editar\n"
                % os.path.basename(png))
        f.write("; los ocho bytes de la marca de unidad, un bit por pixel\n")
        f.write("                defb " + ",".join("0%02Xh" % b for b in ocho) + "\n")
    return ocho


def describe(ocho):
    lineas = ["  " + "".join("#" if b & (0x80 >> x) else "." for x in range(8))
              for b in ocho]
    encendidos = sum(bin(b).count("1") for b in ocho)
    return lineas + ["  %d pixels encendidos de 64; los ocho bytes: %s"
                     % (encendidos, " ".join("%02X" % b for b in ocho))]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    orden = argv[1]
    try:
        if orden == "saca" and len(argv) >= 4:
            indices = saca(argv[2], argv[3], "--rehaz" in argv)
            print("%s: el Anillo de la fuente (caracter 0x%02X)"
                  % (argv[3], CARACTER_ANILLO))
            for f in indices:
                print("  " + "".join("#" if p else "." for p in f))
            return 0
        if orden == "mete" and len(argv) >= 4:
            ocho = escribe_inc(argv[2], argv[3])
            print("%s: %s" % (argv[3], " ".join("%02X" % b for b in ocho)))
            return 0
        if orden == "mira" and len(argv) >= 3:
            for linea in describe(lee_png(argv[2])):
                print(linea)
            return 0
    except (ErrorDeMarca, lienzos.ErrorDeLienzo) as e:
        print("marca.py: %s" % e, file=sys.stderr)
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
