#!/usr/bin/env python3
"""El guante del mapa general como SPRITE: del PNG a los dos planos y vuelta.

En el mapa general el cursor es un guante que senala, y en la cinta es un
sprite POR SOFTWARE: ocho lineas de dos bytes de dibujo (0x6345) con su
mascara (0x6355), desplazadas al pixel y estampadas en el lienzo de 0x4000,
guardando antes los 24 bytes de fondo que tapan (0x62FF) para devolverlos al
moverse. Y por eso el bucle de partida subia un recuadro de 4x3 celdas a la
VRAM en cada vuelta (REFRESCA_EL_CURSOR, 0x07C3).

En el cartucho pasa a ser un sprite de verdad, y como un sprite del MSX1 es de
UN color, son DOS solapados: un plano por color, igual que el cursor de la
vista de cerca (tools/cursor.py). El dibujo va en un PNG que cualquiera puede
repintar:

    src/cartucho/guante.png      16 x 16, sin escalar

El de fabrica es el de la cinta, que solo ocupa las ocho lineas de arriba: la
mitad de abajo queda transparente y ahi se puede dibujar. Los tres estados de
cada pixel salen de como estampa el juego -`pantalla AND mascara OR dibujo`-:

    dibujo 1                 la TINTA de la celda (atributo 0x30: negro)
    dibujo 0 y mascara 0     el PAPEL de la celda (amarillo oscuro)
    dibujo 0 y mascara 1     transparente: se ve el mapa de debajo

La diferencia con el original: el sprite lleva SU color y ya no el de la celda
que tapa, asi que sobre los paneles -atributo 0x78, papel blanco- el guante se
ve amarillo y no blanco. Quien quiera otra cosa, que repinte el PNG.

Uso:
    guante.py saca <work> <guante.png> [--rehaz]   el de la cinta
    guante.py mete <guante.png> <guante.inc>       el include para nombres.asm
    guante.py mira <guante.png>                    que lleva
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cursor                                               # noqa: E402
import lienzos                                              # noqa: E402

ORG_MEDIO = 0x5E00
DIBUJO = 0x6345                 # ocho lineas de dos bytes
MASCARA = 0x6355                # y su mascara, 16 bytes mas alla
LINEAS = 8
ATRIBUTO_MAPA = 0x30            # papel 6 y tinta 0: con lo que 0x81C4 pinta el mapa entero
LADO = cursor.LADO
ANCHO_PNG = ALTO_PNG = LADO
TRANSPARENTE = cursor.TRANSPARENTE
BYTES_POR_PLANO = cursor.BYTES_POR_PLANO
PLANOS = 2


class ErrorDeGuante(Exception):
    pass


# ------------------------------------------------------------ el de fabrica
def indices_de_fabrica(medio):
    """16x16 indices de la paleta del MSX, de los 32 bytes de la cinta."""
    dib = medio[DIBUJO - ORG_MEDIO:][:LINEAS * 2]
    mas = medio[MASCARA - ORG_MEDIO:][:LINEAS * 2]
    tinta, papel = cursor.color_msx(ATRIBUTO_MAPA)
    filas = [[TRANSPARENTE] * LADO for _ in range(LADO)]
    for y in range(LINEAS):
        d = (dib[y * 2] << 8) | dib[y * 2 + 1]
        m = (mas[y * 2] << 8) | mas[y * 2 + 1]
        for x in range(LADO):
            bit = 0x8000 >> x
            if d & bit:
                filas[y][x] = tinta
            elif not m & bit:
                filas[y][x] = papel
    return filas


# ------------------------------------------------------ de indices a planos
def planos(indices):
    """16x16 indices -> (patrones: 64 bytes, colores: 2 bytes)."""
    patrones, colores = bytearray(), bytearray()
    for octetos, color in cursor.planos_de_un_cursor(indices, "el guante"):
        patrones += octetos
        colores.append(color)
    return bytes(patrones), bytes(colores)


def dibuja(patrones, colores):
    """Lo que ensenan los dos sprites: 16x16 con el color del MSX de cada
    pixel, o None donde es transparente."""
    return cursor.dibuja(patrones, colores, 0)


# ------------------------------------------------------------------ el PNG
def escribe_png(ruta, indices):
    lienzos.escribe_png(ruta, ANCHO_PNG, ALTO_PNG, indices, cursor.PALETA, TRANSPARENTE)


def lee_png(ruta):
    return cursor.lee_png(ruta, ANCHO_PNG, ALTO_PNG, "un sprite de 16x16")


def planos_del_png(ruta):
    """(patrones, colores, avisos) del PNG: lo que va a la ROM."""
    indices, avisos = lee_png(ruta)
    patrones, colores = planos(indices)
    return patrones, colores, avisos


def escribe_inc(png, ruta_inc):
    """El include de nombres.asm: los dos planos y sus dos colores."""
    patrones, colores, avisos = planos_del_png(png)
    with open(ruta_inc, "w") as f:
        f.write("; generado por tools/guante.py de %s: no editar\n" % os.path.basename(png))
        f.write("; dos planos de 32 bytes, el A y el B, y el color de cada uno\n")
        f.write("GUANTE_PATRONES:\n")
        for n in range(PLANOS):
            trozo = patrones[n * BYTES_POR_PLANO:(n + 1) * BYTES_POR_PLANO]
            for i in range(0, BYTES_POR_PLANO, 16):
                f.write("                defb " + ",".join("0%02Xh" % b for b in trozo[i:i + 16]) + "\n")
        f.write("; y el color de cada plano, como equ: nombres.asm los mete en los atributos\n")
        for n, c in enumerate(colores):
            f.write("GUANTE_COLOR_%s  equ %d\n" % ("AB"[n], c))
    return patrones, colores, avisos


def describe(patrones, colores):
    partes = []
    for p in range(PLANOS):
        c = colores[p]
        octetos = patrones[p * BYTES_POR_PLANO:(p + 1) * BYTES_POR_PLANO]
        encendidos = sum(bin(b).count("1") for b in octetos)
        partes.append("plano %s: %s, %d pixels" % ("AB"[p], lienzos.NOMBRE_MSX[c] if c else "vacio", encendidos))
    return "  guante   " + "; ".join(partes)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    orden = argv[1]
    if orden == "saca":
        work, png = argv[2], argv[3]
        if os.path.exists(png) and "--rehaz" not in argv:
            print("%s ya existe y puede llevar cambios de alguien: para pisarlo, --rehaz" % png)
            return 1
        with open(os.path.join(work, "medio.raw"), "rb") as f:
            medio = f.read()
        indices = indices_de_fabrica(medio)
        escribe_png(png, indices)
        patrones, colores = planos(indices)
        print("%s: el guante del juego, %dx%d" % (png, ANCHO_PNG, ALTO_PNG))
        print(describe(patrones, colores))
        return 0
    if orden == "mete":
        png, inc = argv[2], argv[3]
        patrones, colores, avisos = escribe_inc(png, inc)
        for a in avisos:
            print(a)
        print("%s: %d bytes de patrones y %d colores" % (inc, len(patrones), len(colores)))
        print(describe(patrones, colores))
        return 0
    if orden == "mira":
        patrones, colores, avisos = planos_del_png(argv[2])
        for a in avisos:
            print(a)
        print(describe(patrones, colores))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (ErrorDeGuante, cursor.ErrorDeCursor, lienzos.ErrorDeLienzo) as e:
        print("guante.py: %s" % e)
        sys.exit(1)
