#!/usr/bin/env python3
"""El cursor de la vista de cerca como SPRITE: del PNG a los planos y vuelta.

En la ROM con la vista por tabla de nombres el cursor ya no son cuatro
caracteres escritos encima del mapa sino un sprite de 16x16, y como un sprite
del MSX1 es de UN color, cada cursor son hasta DOS sprites solapados: un plano
por color. Los tres cursores -mirar, elegir destino y batalla- van en un PNG
que cualquiera puede repintar:

    src/cartucho/cursor.png      48 x 16: los tres cursores de 16x16 seguidos,
                                 sin separacion y sin escalar

La paleta va dentro del PNG: el fondo transparente de las laminas de la web
(#18181C, declarado transparente de verdad) y los quince colores del MSX1.
Cada cursor puede llevar hasta DOS colores ademas del transparente; con mas se
para y dice cual. Un color que no sea de la paleta se cambia por el mas
parecido, avisando.

Los dos planos de un cursor: el plano A es el color con MENOS pixels -el
dibujo- y el B el que tiene mas -el bloque de detras-; con un solo color el
plano B va vacio (color 0). Como ningun pixel del PNG lleva dos colores, los
planos nunca se solapan y da igual cual de los dos sprites vaya delante.

Por defecto el PNG se saca de los tiles del propio juego: los cuatro
caracteres de 0x77B5 + modo*4 de cada modo, dibujados con el color que
ATRIBUTO_A_COLOR (0x049F) les daria en pantalla. Salen los tres cursores
originales, negro sobre un bloque blanco opaco, que es lo que el juego pinta.

Los 32 bytes de un sprite de 16x16 van por CUADRANTES y por columnas, como
manda el TMS9918: arriba a la izquierda (0-7), abajo a la izquierda (8-15),
arriba a la derecha (16-23) y abajo a la derecha (24-31).

Uso:
    cursor.py saca <work> <cursor.png> [--rehaz]    el PNG por defecto, de los tiles
    cursor.py mete <cursor.png> <cursor.inc>        el include para nombres.asm
    cursor.py mira <cursor.png>                     que lleva cada cursor
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lienzos                                              # noqa: E402

ORG_MEDIO = 0x5E00
ORG_ALTO = 0x9E00
TABLA_CURSORES = 0x77B5         # cuatro caracteres por dibujo, indice = modo (0x71CF)
DIBUJOS = 0x9E00                # 128 tiles de 9 bytes: 8 de patron y el atributo
FUENTE = 0xC800                 # 128 caracteres de 8 bytes, atributo 0x78 fijo
ATRIBUTO_TEXTO = 0x78
LADO = 16
MODOS = ((0x10, "mirar"), (0x12, "destino"), (0x17, "batalla"))
ANCHO_PNG, ALTO_PNG = LADO * len(MODOS), LADO

TRANSPARENTE = 0
FONDO = lienzos.FONDO
PALETA = [FONDO] + lienzos.MSX[1:]        # indice 0 transparente, 1..15 el color del MSX
BYTES_POR_PLANO = 32
PLANOS = 2 * len(MODOS)


class ErrorDeCursor(Exception):
    pass


# ------------------------------------------------------------ el de fabrica
def color_msx(atributo):
    """(tinta, papel) en colores del MSX, por las dos tablas del juego."""
    t = lienzos.TABLA_CON if atributo & 0x40 else lienzos.TABLA_SIN
    return t[atributo & 7], t[(atributo >> 3) & 7]


def caracter(alto, codigo):
    """Los ocho bytes de patron y el atributo del caracter `codigo` de la
    pantalla de caracteres: con el bit 7, un dibujo de 0x9E00; sin el, una
    letra de la fuente con el atributo del texto."""
    if codigo & 0x80:
        o = DIBUJOS - ORG_ALTO + (codigo & 0x7F) * 9
        return alto[o:o + 8], alto[o + 8]
    o = FUENTE - ORG_ALTO + codigo * 8
    return alto[o:o + 8], ATRIBUTO_TEXTO


def cursor_de_fabrica(medio, alto, modo):
    """El cursor del modo, 16x16 indices de PALETA (colores del MSX), tal
    como lo escribe 0x71D0-0x71ED: cuatro caracteres, dos arriba y dos abajo."""
    codigos = medio[TABLA_CURSORES - ORG_MEDIO + modo * 4:][:4]
    dib = [[TRANSPARENTE] * LADO for _ in range(LADO)]
    for n, cod in enumerate(codigos):
        patron, atributo = caracter(alto, cod)
        tinta, papel = color_msx(atributo)
        oy, ox = (n // 2) * 8, (n % 2) * 8
        for y in range(8):
            for x in range(8):
                dib[oy + y][ox + x] = tinta if patron[y] & (0x80 >> x) else papel
    return dib


def indices_de_fabrica(medio, alto):
    filas = [[] for _ in range(ALTO_PNG)]
    for modo, _nombre in MODOS:
        dib = cursor_de_fabrica(medio, alto, modo)
        for y in range(LADO):
            filas[y].extend(dib[y])
    return filas


# ------------------------------------------------------ de indices a planos
def plano_a_bytes(plano):
    """16x16 de verdad/falso -> los 32 bytes del sprite, por cuadrantes."""
    fuera = bytearray(BYTES_POR_PLANO)
    for y in range(LADO):
        for x in range(LADO):
            if plano[y][x]:
                fuera[(16 if x >= 8 else 0) + y] |= 0x80 >> (x & 7)
    return bytes(fuera)


def bytes_a_plano(treintaydos):
    return [[bool(treintaydos[(16 if x >= 8 else 0) + y] & (0x80 >> (x & 7)))
             for x in range(LADO)] for y in range(LADO)]


def planos_de_un_cursor(dib, nombre):
    """16x16 indices -> ((bytes A, color A), (bytes B, color B)).

    A es el color con menos pixels; a igualdad, el de indice mas bajo. Mas de
    dos colores es un error que nombra el cursor."""
    cuenta = {}
    for fila in dib:
        for v in fila:
            if v != TRANSPARENTE:
                cuenta[v] = cuenta.get(v, 0) + 1
    if len(cuenta) > 2:
        raise ErrorDeCursor(
            "el cursor de %s lleva %d colores (%s) y solo caben dos, mas el transparente"
            % (nombre, len(cuenta), ", ".join(lienzos.NOMBRE_MSX[c] for c in sorted(cuenta))))
    orden = sorted(cuenta, key=lambda c: (cuenta[c], c))
    fuera = []
    for i in range(2):
        if i < len(orden):
            c = orden[i]
            fuera.append((plano_a_bytes([[v == c for v in fila] for fila in dib]), c))
        else:
            fuera.append((bytes(BYTES_POR_PLANO), 0))
    return tuple(fuera)


def planos(indices):
    """Las 16 filas de 48 indices -> (patrones: 192 bytes, colores: 6 bytes)."""
    patrones, colores = bytearray(), bytearray()
    for n, (_modo, nombre) in enumerate(MODOS):
        dib = [fila[n * LADO:(n + 1) * LADO] for fila in indices]
        for octetos, color in planos_de_un_cursor(dib, nombre):
            patrones += octetos
            colores.append(color)
    return bytes(patrones), bytes(colores)


def dibuja(patrones, colores, n):
    """Lo que ensenan los dos sprites del cursor n: 16x16 con el color del MSX
    de cada pixel, o None donde es transparente. Con los planos solapados
    manda el A, que es el sprite 0 y va delante."""
    a = bytes_a_plano(patrones[n * 64:n * 64 + 32])
    b = bytes_a_plano(patrones[n * 64 + 32:n * 64 + 64])
    ca, cb = colores[n * 2], colores[n * 2 + 1]
    return [[(ca if a[y][x] and ca else (cb if b[y][x] and cb else None))
             for x in range(LADO)] for y in range(LADO)]


# ------------------------------------------------------------------ el PNG
def escribe_png(ruta, indices):
    lienzos.escribe_png(ruta, ANCHO_PNG, ALTO_PNG, indices, PALETA, TRANSPARENTE)


def _mas_parecido(rgb):
    mejor, dist = 1, None
    for i in range(1, 16):
        c = PALETA[i]
        d = sum((p - q) ** 2 for p, q in zip(rgb, c))
        if dist is None or d < dist:
            mejor, dist = i, d
    return mejor


def lee_png(ruta):
    """El PNG -> (indices 16x48, avisos). Transparente es el pixel con alfa a
    cero o el del color del fondo; cualquier otro, su color del MSX."""
    ancho, alto, filas, opacos = lienzos.lee_png(ruta)
    if (ancho, alto) != (ANCHO_PNG, ALTO_PNG):
        raise ErrorDeCursor("el cursor tiene que medir %dx%d (tres de 16x16 seguidos) y mide %dx%d. "
                            "No lo escales: un pixel del PNG es un pixel del juego."
                            % (ANCHO_PNG, ALTO_PNG, ancho, alto))
    indices, sustituidos = [], {}
    for y in range(alto):
        fila = []
        for x in range(ancho):
            rgb = filas[y][x]
            if not opacos[y][x] or rgb == FONDO:
                fila.append(TRANSPARENTE)
                continue
            if rgb in PALETA:
                i = PALETA.index(rgb)
            else:
                i = _mas_parecido(rgb)
                visto = sustituidos.get(rgb, (i, 0))
                sustituidos[rgb] = (i, visto[1] + 1)
            fila.append(i)
        indices.append(fila)
    avisos = ["  el color #%02X%02X%02X (%d pixels) no esta en la paleta del MSX; se toma el mas parecido, %s"
              % (rgb[0], rgb[1], rgb[2], n, lienzos.NOMBRE_MSX[i])
              for rgb, (i, n) in sorted(sustituidos.items())]
    return indices, avisos


def planos_del_png(ruta):
    """(patrones, colores, avisos) del PNG: lo que va a la ROM."""
    indices, avisos = lee_png(ruta)
    patrones, colores = planos(indices)
    return patrones, colores, avisos


def planos_de_fabrica(work):
    with open(os.path.join(work, "medio.raw"), "rb") as f:
        medio = f.read()
    with open(os.path.join(work, "alto.raw"), "rb") as f:
        alto = f.read()
    return planos(indices_de_fabrica(medio, alto))


def escribe_inc(png, ruta_inc):
    """El include de nombres.asm: los seis planos y sus seis colores."""
    patrones, colores, avisos = planos_del_png(png)
    with open(ruta_inc, "w") as f:
        f.write("; generado por tools/cursor.py de %s: no editar\n" % os.path.basename(png))
        f.write("; seis planos de 32 bytes: por cada modo (mirar, destino, batalla), el plano A y el B\n")
        f.write("CURSOR_PATRONES:\n")
        for n in range(PLANOS):
            trozo = patrones[n * BYTES_POR_PLANO:(n + 1) * BYTES_POR_PLANO]
            for i in range(0, BYTES_POR_PLANO, 16):
                f.write("                defb " + ",".join("0%02Xh" % b for b in trozo[i:i + 16]) + "\n")
        f.write("; el color de cada plano, en el mismo orden; 0 es un plano vacio\n")
        f.write("CURSOR_COLORES: defb " + ",".join(str(c) for c in colores) + "\n")
    return patrones, colores, avisos


def describe(patrones, colores):
    lineas = []
    for n, (_modo, nombre) in enumerate(MODOS):
        partes = []
        for p in range(2):
            c = colores[n * 2 + p]
            octetos = patrones[(n * 2 + p) * BYTES_POR_PLANO:(n * 2 + p + 1) * BYTES_POR_PLANO]
            encendidos = sum(bin(b).count("1") for b in octetos)
            partes.append("plano %s: %s, %d pixels" % ("AB"[p], lienzos.NOMBRE_MSX[c] if c else "vacio", encendidos))
        lineas.append("  %-8s %s" % (nombre, "; ".join(partes)))
    return "\n".join(lineas)


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
        with open(os.path.join(work, "alto.raw"), "rb") as f:
            alto = f.read()
        indices = indices_de_fabrica(medio, alto)
        escribe_png(png, indices)
        patrones, colores = planos(indices)
        print("%s: los tres cursores del juego, %dx%d" % (png, ANCHO_PNG, ALTO_PNG))
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
    except (ErrorDeCursor, lienzos.ErrorDeLienzo) as e:
        print("cursor.py: %s" % e)
        sys.exit(1)
