#!/usr/bin/env python3
"""El lienzo de los tiles del mapa: de la cinta a un PNG editable y de vuelta.

PARA QUE. Lo pidio theNestruo: poder EDITAR los graficos del parche sin tocar un
solo byte a mano. El parche escribia los cuatro tiles del Ojo de Sauron como un
chorro de hexadecimal en la tabla de tools/parchea.py; ahora esos cuatro tiles
-y los otros 124- viven en un PNG que se abre con cualquier editor.

EL LIENZO. src/parche/tiles_del_mapa.png, de 128x64 pixels: los 128 tiles de la
tabla de 0x9E00 puestos en 16 columnas por 8 filas, cada uno de 8x8, PEGADOS y
SIN escalar. Un pixel del PNG es un pixel del juego. No lleva separacion ni
marco: cualquier pixel que se pinte es un pixel que acaba en la cinta.

QUE ES CADA TILE. Nueve bytes: ocho de dibujo -una fila por byte, el bit 7 a la
izquierda- y detras el atributo del ZX Spectrum, que es de donde sale el color:

    bits 0-2  la TINTA  (el color de los bits a 1)
    bits 3-5  el PAPEL  (el color de los bits a 0)
    bit  6    el BRILLO (vale para los dos colores a la vez)
    bit  7    el parpadeo (el juego no lo usa; se conserva tal cual)

De ahi salen las DOS REGLAS que hay que respetar al pintar, que son las del
Spectrum y no un capricho de esta herramienta:

    1. DOS COLORES POR CASILLA de 8x8, no mas. Es el famoso "attribute clash".
    2. LOS DOS DEL MISMO BRILLO. Los ocho colores normales y los ocho brillantes
       no se mezclan dentro de una casilla. El negro es la excepcion, porque es
       el mismo con brillo y sin el.

Si una casilla se salta alguna de las dos, la herramienta PARA y dice cual es,
en vez de elegir por su cuenta.

LO QUE NO SE TOCA. Una casilla cuyo dibujo salga exactamente igual que el que
traia la cinta se devuelve con SUS BYTES ORIGINALES, sin recodificar. Esto no es
un adorno: hay tiles que no se pueden reconstruir mirando la imagen -el 85 lleva
tinta blanca sobre papel blanco y un dibujo escondido debajo, y los 111 al 127
son negro sobre negro-, asi que sin esta regla abrir y guardar el PNG sin
cambiar nada ya moveria bytes. Con ella, la ida y vuelta es exacta.

COMO SE ELIGE QUIEN ES TINTA Y QUIEN PAPEL en una casilla repintada. Da igual
para lo que se ve -intercambiarlos con el dibujo invertido pinta lo mismo-, pero
los bytes salen distintos, asi que hace falta una regla fija:

    a. si los dos colores son los mismos que traia la casilla, cada uno conserva
       su papel de antes (asi redibujar sin cambiar de color no mueve el atributo)
    b. si no, el PAPEL es el color mas abundante de la casilla; a igualdad, el
       del pixel de arriba a la izquierda
    c. una casilla de un solo color se guarda con los ocho bytes a cero y ese
       color de papel

Uso:
    python3 tools/tiles_del_mapa.py saca <work/alto.raw> <lienzo.png>
    python3 tools/tiles_del_mapa.py mete <work/alto.raw> <lienzo.png>

`saca` dibuja el lienzo con los tiles tal y como vienen en la cinta. OJO: el
lienzo del repositorio ya trae encima los dibujos del parche, asi que `saca` se
niega a pisarlo si existe (hay que pasarle --rehaz para hacerlo a proposito).

`mete` lee el lienzo y dice, casilla por casilla, que cambia respecto a la
cinta. Es lo que hace tools/parchea.py para convertirlo en entradas del parche.
"""
import os
import struct
import sys
import zlib

ORG = 0x9E00                      # el org del bloque alto
TABLA_INI, TABLA_FIN, PASO = 0x9E00, 0xA280, 9
TILES = (TABLA_FIN - TABLA_INI) // PASO      # 128
COLS = 16                         # el lienzo, en columnas de tiles
FILAS = (TILES + COLS - 1) // COLS
ANCHO, ALTO = COLS * 8, FILAS * 8            # 128 x 64

# La paleta del ZX Spectrum en el orden del atributo: negro, azul, rojo,
# magenta, verde, cian, amarillo y blanco; primero los ocho normales y detras
# los ocho con brillo. Es la misma tabla que usa tools/render_graficos.py para
# las laminas de la web, para que los dos dibujen igual.
ZX = [(0, 0, 0), (0, 0, 215), (215, 0, 0), (215, 0, 215),
      (0, 215, 0), (0, 215, 215), (215, 215, 0), (215, 215, 215),
      (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
      (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]

NOMBRE_COLOR = ["negro", "azul", "rojo", "magenta",
                "verde", "cian", "amarillo", "blanco"]


def nombra(indice):
    return "%s%s" % (NOMBRE_COLOR[indice & 7], " brillante" if indice & 8 else "")


class ErrorDeLienzo(Exception):
    """Algo del PNG no se puede convertir a tiles del Spectrum."""


# ===========================================================================
# PNG: escribir y leer, sin dependencias (aqui no hay PIL)
# ===========================================================================
def _trozo(tipo, datos):
    return (struct.pack(">I", len(datos)) + tipo + datos
            + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))


def escribe_png(ruta, ancho, alto, indices, paleta):
    """PNG indexado de 8 bits. La paleta va dentro, asi que el editor la ofrece
    hecha y no hay manera de pintar un color que el ZX no sepa dar."""
    crudo = b"".join(b"\x00" + bytes(f) for f in indices)
    plte = b"".join(bytes(c) for c in paleta)
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + _trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 3, 0, 0, 0))
                + _trozo(b"PLTE", plte)
                + _trozo(b"IDAT", zlib.compress(crudo, 9))
                + _trozo(b"IEND", b""))


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _desfiltra(crudo, alto, ancho_linea, bpp):
    """Deshace los cinco filtros del PNG, linea a linea."""
    fuera = []
    previa = bytearray(ancho_linea)
    i = 0
    for _ in range(alto):
        if i >= len(crudo):
            raise ErrorDeLienzo("el PNG se corta a mitad de la imagen")
        filtro = crudo[i]
        i += 1
        linea = bytearray(crudo[i:i + ancho_linea])
        if len(linea) != ancho_linea:
            raise ErrorDeLienzo("el PNG se corta a mitad de una linea")
        i += ancho_linea
        if filtro == 1:
            for x in range(bpp, ancho_linea):
                linea[x] = (linea[x] + linea[x - bpp]) & 0xFF
        elif filtro == 2:
            for x in range(ancho_linea):
                linea[x] = (linea[x] + previa[x]) & 0xFF
        elif filtro == 3:
            for x in range(ancho_linea):
                izq = linea[x - bpp] if x >= bpp else 0
                linea[x] = (linea[x] + ((izq + previa[x]) >> 1)) & 0xFF
        elif filtro == 4:
            for x in range(ancho_linea):
                izq = linea[x - bpp] if x >= bpp else 0
                arr = previa[x]
                dia = previa[x - bpp] if x >= bpp else 0
                linea[x] = (linea[x] + _paeth(izq, arr, dia)) & 0xFF
        elif filtro != 0:
            raise ErrorDeLienzo("filtro de PNG desconocido: %d" % filtro)
        fuera.append(bytes(linea))
        previa = linea
    return fuera


def _bits(linea, cuantos, profundidad):
    """Saca `cuantos` valores de una linea empaquetada a 1, 2 o 4 bits."""
    porbyte = 8 // profundidad
    mascara = (1 << profundidad) - 1
    fuera = []
    for i in range(cuantos):
        b = linea[i // porbyte]
        desp = 8 - profundidad * (i % porbyte + 1)
        fuera.append((b >> desp) & mascara)
    return fuera


def lee_png(ruta):
    """Devuelve (ancho, alto, filas) con filas[y][x] = (r, g, b).

    Traga lo que escupen los editores de verdad: indexado, gris, RGB y RGBA, a
    1, 2, 4, 8 o 16 bits. Lo unico que no acepta es el entrelazado Adam7, y lo
    dice claro en vez de sacar ruido.
    """
    d = open(ruta, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ErrorDeLienzo("%s no es un PNG" % ruta)
    pos, idat, paleta, ihdr, trns = 8, [], None, None, None
    while pos + 8 <= len(d):
        largo = struct.unpack(">I", d[pos:pos + 4])[0]
        tipo = d[pos + 4:pos + 8]
        cuerpo = d[pos + 8:pos + 8 + largo]
        pos += 12 + largo
        if tipo == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", cuerpo)
        elif tipo == b"PLTE":
            paleta = [tuple(cuerpo[i:i + 3]) for i in range(0, len(cuerpo), 3)]
        elif tipo == b"tRNS":
            trns = cuerpo
        elif tipo == b"IDAT":
            idat.append(cuerpo)
        elif tipo == b"IEND":
            break
    if not ihdr:
        raise ErrorDeLienzo("al PNG le falta la cabecera IHDR")
    ancho, alto, prof, color, _comp, _filtro, entrelazado = ihdr
    if entrelazado:
        raise ErrorDeLienzo("el PNG esta entrelazado (Adam7) y esto no lo lee: "
                            "guardalo sin entrelazar")
    canales = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
    if canales is None:
        raise ErrorDeLienzo("tipo de color de PNG desconocido: %d" % color)
    bpp = max(1, canales * prof // 8)
    ancho_linea = (ancho * canales * prof + 7) // 8
    lineas = _desfiltra(zlib.decompress(b"".join(idat)), alto, ancho_linea, bpp)

    maximo = (1 << prof) - 1
    filas, transparentes = [], 0
    for linea in lineas:
        if prof < 8:
            valores = _bits(linea, ancho * canales, prof)
        elif prof == 8:
            valores = list(linea)
        else:                                   # 16 bits: nos quedamos el alto
            valores = [linea[i] for i in range(0, len(linea), 2)]
        fila = []
        for x in range(ancho):
            v = valores[x * canales:(x + 1) * canales]
            if color == 3:
                if paleta is None or v[0] >= len(paleta):
                    raise ErrorDeLienzo("el PNG indexado apunta fuera de su paleta")
                if trns and v[0] < len(trns) and trns[v[0]] < 128:
                    transparentes += 1
                rgb = paleta[v[0]]
            elif color == 0:
                g = v[0] if prof >= 8 else v[0] * 255 // maximo
                rgb = (g, g, g)
            elif color == 4:
                if v[1] < 128:
                    transparentes += 1
                rgb = (v[0], v[0], v[0])
            elif color == 2:
                rgb = (v[0], v[1], v[2])
            else:                               # RGBA
                if v[3] < 128:
                    transparentes += 1
                rgb = (v[0], v[1], v[2])
            fila.append(rgb)
        filas.append(fila)
    if transparentes:
        raise ErrorDeLienzo(
            "el lienzo tiene %d pixels transparentes y aqui no hay transparencia: "
            "todo pixel es tinta o papel. Aplana la imagen antes de guardarla."
            % transparentes)
    return ancho, alto, filas


# ===========================================================================
# De los bytes al lienzo
# ===========================================================================
def canon(indice):
    """El indice, con el negro SIEMPRE en el 0.

    La paleta del ZX trae el negro dos veces, en el 0 y en el 8, porque el
    brillo no le hace nada: los dos son #000000. Mirando la imagen no hay forma
    de distinguirlos, asi que aqui se cuentan como el mismo color. Sin esto, un
    tile de negro brillante sobre blanco brillante -los hay, el 103 y el 105-
    no se reconoceria al releerlo y volveria con la tinta y el papel del reves.
    """
    return 0 if (indice & 7) == 0 else indice


def dibuja_tile(nueve):
    """Los nueve bytes de un tile, como 8x8 indices de la paleta del ZX."""
    attr = nueve[8]
    brillo = 8 if attr & 0x40 else 0
    tinta = canon((attr & 0x07) + brillo)
    papel = canon(((attr >> 3) & 0x07) + brillo)
    return [[tinta if nueve[y] & (0x80 >> x) else papel for x in range(8)]
            for y in range(8)]


def tabla_a_indices(tabla):
    """La tabla de 1152 bytes -> las 64 filas de 128 indices del lienzo."""
    if len(tabla) != TILES * PASO:
        raise ErrorDeLienzo("la tabla mide %d bytes y tiene que medir %d"
                            % (len(tabla), TILES * PASO))
    lienzo = [[0] * ANCHO for _ in range(ALTO)]
    for t in range(TILES):
        dib = dibuja_tile(tabla[t * PASO:(t + 1) * PASO])
        ox, oy = (t % COLS) * 8, (t // COLS) * 8
        for y in range(8):
            for x in range(8):
                lienzo[oy + y][ox + x] = dib[y][x]
    return lienzo


def saca_lienzo(tabla, ruta):
    escribe_png(ruta, ANCHO, ALTO, tabla_a_indices(tabla), ZX)


# ===========================================================================
# Del lienzo a los bytes
# ===========================================================================
def _indice_del_color(rgb):
    """El indice de la paleta del ZX, y si el color era exacto o el mas cercano."""
    if rgb in ZX:
        return canon(ZX.index(rgb)), True
    mejor, dist = 0, None
    for i, c in enumerate(ZX):
        d = sum((a - b) ** 2 for a, b in zip(rgb, c))
        if dist is None or d < dist:
            mejor, dist = i, d
    return canon(mejor), False


def _codifica(celda, referencia, numero):
    """Una casilla de 8x8 (indices de la paleta) -> los nueve bytes del tile.

    `referencia` son los nueve bytes que traia la cinta, que se usan para dos
    cosas: conservar el parpadeo y decidir quien es tinta y quien papel cuando
    la casilla se repinta con los mismos dos colores.
    """
    cuenta = {}
    for y in range(8):
        for x in range(8):
            cuenta[celda[y][x]] = cuenta.get(celda[y][x], 0) + 1
    colores = list(cuenta)
    if len(colores) > 2:
        raise ErrorDeLienzo(
            "la casilla %d (columna %d, fila %d) usa %d colores (%s) y el "
            "Spectrum solo da DOS por casilla de 8x8: una tinta y un papel"
            % (numero, numero % COLS, numero // COLS, len(colores),
               ", ".join(nombra(c) for c in colores)))

    # El brillo es de la casilla entera. El negro vale para las dos mitades de
    # la paleta, asi que no obliga a nada; cualquier otro color si.
    exigen = [c for c in colores if (c & 7) != 0]
    brillos = {c >> 3 for c in exigen}
    if len(brillos) > 1:
        raise ErrorDeLienzo(
            "la casilla %d mezcla %s: en una casilla los dos colores tienen que "
            "ser los dos brillantes o los dos normales (el negro vale para ambos)"
            % (numero, " y ".join(nombra(c) for c in exigen)))
    brillo = brillos.pop() if brillos else (1 if referencia[8] & 0x40 else 0)

    if len(colores) == 1:
        papel = tinta = colores[0] & 7
        dibujo = [0] * 8
    else:
        ref = dibuja_tile(referencia)
        antes = set()
        for y in range(8):
            antes.update(ref[y])
        tinta_ref = canon((referencia[8] & 0x07)
                          + (8 if referencia[8] & 0x40 else 0))
        if set(colores) == antes and tinta_ref in colores:
            tinta_i = tinta_ref                      # (a) cada uno en su papel
        else:                                        # (b) papel = el mas abundante
            a, b = colores
            if cuenta[a] != cuenta[b]:
                tinta_i = a if cuenta[a] < cuenta[b] else b
            else:
                tinta_i = b if celda[0][0] == a else a
        tinta = tinta_i & 7
        papel = [c for c in colores if c != tinta_i][0] & 7
        dibujo = []
        for y in range(8):
            v = 0
            for x in range(8):
                if celda[y][x] == tinta_i:
                    v |= 0x80 >> x
            dibujo.append(v)
    attr = tinta | (papel << 3) | (brillo << 6) | (referencia[8] & 0x80)
    return bytes(dibujo + [attr])


def lee_lienzo(ruta, referencia):
    """El PNG editado -> la tabla de 1152 bytes. Devuelve (tabla, avisos).

    `referencia` es la tabla tal y como viene en la cinta. Toda casilla que se
    vea EXACTAMENTE igual que la suya se devuelve con sus bytes de siempre: es
    lo que hace que abrir y guardar el PNG sin tocar nada no mueva un solo byte.
    """
    ancho, alto, filas = lee_png(ruta)
    if (ancho, alto) != (ANCHO, ALTO):
        raise ErrorDeLienzo(
            "el lienzo tiene que medir %dx%d (los %d tiles de 8x8 en %d columnas) "
            "y mide %dx%d. No lo escales: un pixel del PNG es un pixel del juego."
            % (ANCHO, ALTO, TILES, COLS, ancho, alto))

    # Los colores, uno a uno, contra la paleta del ZX.
    indices, sustituidos = [], {}
    for y in range(alto):
        fila = []
        for x in range(ancho):
            i, exacto = _indice_del_color(filas[y][x])
            if not exacto:
                visto = sustituidos.get(filas[y][x], (i, 0))
                sustituidos[filas[y][x]] = (i, visto[1] + 1)
            fila.append(i)
        indices.append(fila)
    avisos = []
    for rgb, (i, n) in sorted(sustituidos.items()):
        avisos.append("  el color #%02X%02X%02X (%d pixels) no es del ZX: se toma "
                      "el mas parecido, %s" % (rgb[0], rgb[1], rgb[2], n, nombra(i)))

    fuera = bytearray()
    for t in range(TILES):
        ox, oy = (t % COLS) * 8, (t // COLS) * 8
        celda = [[indices[oy + y][ox + x] for x in range(8)] for y in range(8)]
        ref = referencia[t * PASO:(t + 1) * PASO]
        if celda == dibuja_tile(ref):
            fuera += ref                       # sin tocar: los bytes de la cinta
        else:
            fuera += _codifica(celda, ref, t)
    return bytes(fuera), avisos


def tramos(antes, ahora):
    """Los trozos que cambian, pegando los bytes seguidos: [(off, viejo, nuevo)]."""
    fuera, i = [], 0
    while i < len(antes):
        if antes[i] == ahora[i]:
            i += 1
            continue
        j = i
        while j < len(antes) and antes[j] != ahora[j]:
            j += 1
        fuera.append((i, bytes(antes[i:j]), bytes(ahora[i:j])))
        i = j
    return fuera


def tiles_tocados(antes, ahora):
    """Los numeros de tile que cambian, para poder contarlos y nombrarlos."""
    return [t for t in range(TILES)
            if antes[t * PASO:(t + 1) * PASO] != ahora[t * PASO:(t + 1) * PASO]]


def tabla_del_bloque(alto_raw):
    """Los 1152 bytes de la tabla dentro del cuerpo del bloque alto."""
    return bytes(alto_raw[TABLA_INI - ORG:TABLA_FIN - ORG])


# ===========================================================================
def main(argv):
    if len(argv) < 4 or argv[1] not in ("saca", "mete"):
        print(__doc__)
        return 2
    orden, raw, png = argv[1], argv[2], argv[3]
    if not os.path.exists(raw):
        print("  falta %s: hazlo antes con `make extract`" % raw)
        return 2
    tabla = tabla_del_bloque(open(raw, "rb").read())

    if orden == "saca":
        if os.path.exists(png) and "--rehaz" not in argv:
            print("  %s ya existe. El lienzo del repositorio lleva ENCIMA los\n"
                  "  dibujos del parche (el Ojo de Sauron), y esto lo dejaria como\n"
                  "  viene la cinta. Si es lo que quieres, pasa --rehaz." % png)
            return 1
        os.makedirs(os.path.dirname(os.path.abspath(png)), exist_ok=True)
        saca_lienzo(tabla, png)
        print("  %s: %d tiles de 8x8 en %d columnas, %dx%d pixels, sin escalar"
              % (png, TILES, COLS, ANCHO, ALTO))
        return 0

    try:
        nueva, avisos = lee_lienzo(png, tabla)
    except ErrorDeLienzo as e:
        print("  %s" % e)
        return 1
    for a in avisos:
        print(a)
    tocados = tiles_tocados(tabla, nueva)
    if not tocados:
        print("  %s no cambia ni un byte de la tabla de 0x%04X" % (png, TABLA_INI))
        return 0
    print("  %d tiles cambiados: %s" % (len(tocados), ", ".join(map(str, tocados))))
    for off, viejo, nuevo in tramos(tabla, nueva):
        print("    0x%04X  %2d B  %s -> %s"
              % (TABLA_INI + off, len(viejo), viejo.hex(), nuevo.hex()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
