#!/usr/bin/env python3
"""Los lienzos: de la cinta a unos PNG editables y de vuelta.

PARA QUE. Lo pidio theNestruo: poder EDITAR los graficos del parche sin tocar un
solo byte a mano. El parche escribia los cuatro tiles del Ojo de Sauron como un
chorro de hexadecimal en la tabla de tools/parchea.py; ahora TODOS los graficos
del bloque alto viven en tres PNG que se abren con cualquier editor.

LAS TRES HOJAS, con la direccion que las acota en src/alto.notes. Son las mismas
tres que dibuja tools/render_graficos.py para la web; aqui salen a tamano real,
pegadas y sin escalar -un pixel del PNG es un pixel del juego- y ademas se
vuelven a leer.

  tiles     0x9E00-0xA280  LOS 128 TILES DEL MAPA, de 8x8. Nueve bytes cada uno:
                           ocho de dibujo y detras el atributo del ZX Spectrum,
                           que es de donde sale el color. 16 columnas: 128x64.
                           SE DIBUJAN CON LOS COLORES DEL MSX, que es lo que se
                           ve jugando; ver mas abajo.

  sprites   0xA2E8-0xB8E8  LOS 176 SPRITES DE BATALLA, de 16x8 CON MASCARA. 32
                           bytes: parejas [mascara][dibujo] en el zigzag que
                           recorre 0x887B. Donde la mascara vale 1 el sprite es
                           transparente y se ve lo que hubiera debajo. Van de dos
                           en dos, que es como encajan en figuras de 16x16 (ver
                           mas abajo). 11 columnas de figuras: 176x128.

  fuente    0xC800-0xCC00  LOS 128 CARACTERES, de 8x8 y un byte por linea, sin
                           atributo: un bit es un pixel. En los codigos bajos
                           estan las texturas del terreno y despues los marcos,
                           las flechas, los digitos y las letras. 16 columnas:
                           128x64.

EL ATRIBUTO DEL ZX, que solo gastan los tiles: bits 0-2 la TINTA (el color de
los bits a 1), 3-5 el PAPEL (el de los bits a 0), 6 el BRILLO -que vale para los
dos colores a la vez- y 7 el parpadeo, que el juego no usa y aqui se conserva
tal cual.

PERO EL COLOR QUE SE VE NO ES EL DEL SPECTRUM. Esta conversion es de MSX: el
atributo no llega a la pantalla, lo traduce antes ATRIBUTO_A_COLOR (0x049F) con
dos tablas de ocho colores del MSX -0x04CE para el atributo sin brillo y 0x04D6
para el que lo lleva-. Asi que el lienzo de los tiles se pinta y se relee con
LOS COLORES DEL MSX, los que ve quien juega, y no con los del Spectrum. De ahi
salen las TRES REGLAS que hay que respetar al pintar un tile, que son las de la
maquina y no un capricho de esta herramienta:

    1. DOS COLORES POR CASILLA de 8x8, no mas. Es el famoso "attribute clash".
    2. LOS DOS DEL MISMO BRILLO. El bit de brillo es uno para toda la casilla, y
       cambia a la vez el azul, el rojo, el verde y el amarillo: no se puede
       tener azul oscuro y rojo claro juntos. Los otros cuatro -el negro, el
       magenta, el cian y el blanco- se ven IGUAL con brillo y sin el, porque
       las dos tablas les dan el mismo color, asi que esos no obligan a nada.
    3. SOLO DOCE DE LOS QUINCE COLORES DEL MSX. De las dos tablas no salen el
       verde medio (2), el rojo medio (8) ni el gris (14): no hay atributo del
       Spectrum capaz de producirlos, por mucho que se pinten. Un pixel de esos
       se cambia por el mas parecido de los doce y se avisa.

Si una casilla se salta la primera o la segunda, la herramienta PARA y dice cual
es, en vez de elegir por su cuenta. Los sprites y la fuente no tienen atributo, asi
que no tienen esa limitacion: los sprites gastan tres estados -transparente,
negro y blanco- y la fuente dos. En el lienzo de los sprites el transparente va
con el FONDO de las laminas de la web, #18181C, y declarado transparente en el
propio PNG; no hay ningun color-clave inventado.

LOS SPRITES VAN DE DOS EN DOS EN EL LIENZO. MEDIDO es que cada sprite son 32
bytes y 16x8: los dos caminos que los pintan lo dicen igual (0x87E9 calcula
0xA2E8 + (tipo-4)*32 y pinta ocho filas; 0x87B4 hace la misma cuenta con un
`inc hl` delante y pinta otras ocho). OBSERVADO, y solo observado, es que las
entradas consecutivas encajan de dos en dos en figuras de 16x16. No se ha
encontrado la rutina que lo haga. El lienzo las apila asi porque es como se ven
las figuras enteras y por tanto como se pueden dibujar, pero eso no demuestra
nada sobre el juego: cada sprite sigue yendo a SU direccion, calculada aparte.

LO QUE NO SE TOCA. Una casilla cuyo dibujo salga exactamente igual que el que
traia la cinta se devuelve con SUS BYTES ORIGINALES, sin recodificar. Esto no es
un adorno: hay tiles que no se pueden reconstruir mirando la imagen -el 85 lleva
tinta blanca sobre papel blanco y un dibujo escondido debajo, y los 111 al 127
son negro sobre negro-, asi que sin esta regla abrir y guardar el PNG sin
cambiar nada ya moveria bytes. Con ella, la ida y vuelta es exacta.

COMO SE ELIGE QUIEN ES TINTA Y QUIEN PAPEL en un tile repintado. Da igual para
lo que se ve -intercambiarlos con el dibujo invertido pinta lo mismo-, pero los
bytes salen distintos, asi que hace falta una regla fija:

    a. si los dos colores son los mismos que traia la casilla, cada uno conserva
       su papel de antes (asi redibujar sin cambiar de color no mueve el atributo)
    b. si no, el PAPEL es el color mas abundante de la casilla; a igualdad, el
       del pixel de arriba a la izquierda
    c. una casilla de un solo color se guarda con los ocho bytes a cero y ese
       color de papel

Uso:
    python3 tools/lienzos.py saca <work/alto.raw> [directorio] [hoja] [--rehaz]
    python3 tools/lienzos.py mete <work/alto.raw> [directorio] [hoja]

El directorio por defecto es src/parche. `saca` dibuja los lienzos con los
graficos tal y como vienen en la cinta; OJO: los del repositorio ya traen encima
los dibujos del parche, asi que se niega a pisarlos si existen y hay que
insistirle con --rehaz. `mete` lee los lienzos y dice que cambia respecto a la
cinta, que es lo que hace tools/parchea.py para armar el parche.
"""
import os
import struct
import sys
import zlib

ORG = 0x9E00                      # el org del bloque alto


class ErrorDeLienzo(Exception):
    """Algo del PNG no se puede convertir a graficos del juego."""


# ===========================================================================
# Las paletas
# ===========================================================================
# La del ZX Spectrum en el orden del atributo: negro, azul, rojo, magenta,
# verde, cian, amarillo y blanco; primero los ocho normales y detras los ocho
# con brillo. Es la misma tabla que usa tools/render_graficos.py para las
# laminas de la web, para que los dos dibujen igual.
ZX = [(0, 0, 0), (0, 0, 215), (215, 0, 0), (215, 0, 215),
      (0, 215, 0), (0, 215, 215), (215, 215, 0), (215, 215, 215),
      (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
      (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]

NOMBRE_COLOR = ["negro", "azul", "rojo", "magenta",
                "verde", "cian", "amarillo", "blanco"]

# ---------------------------------------------------------------------------
# PERO LOS TILES NO SE VEN CON LOS COLORES DEL ZX. Esta conversion es de MSX y
# los atributos del Spectrum no llegan a la pantalla tal cual: ATRIBUTO_A_COLOR
# (0x049F) traduce cada uno a un byte de color de SCREEN 2 con dos tablas de
# ocho, una para el atributo sin brillo y otra para el que lo lleva. Estan en la
# cinta, en 0x04CE y 0x04D6, declaradas en src/bajo.notes, y son estas.
TABLA_SIN = [1, 4, 6, 13, 12, 7, 10, 15]      # 0x04CE
TABLA_CON = [1, 5, 9, 13, 3, 7, 11, 15]       # 0x04D6

# Los quince colores del MSX1 (TMS9918), numerados como los numera el VDP. Son
# los valores de la paleta MSX1 que reparten Aseprite y Lospec, que es con la
# que se pintan los lienzos.
MSX = [
    (0, 0, 0),                                            # 0 transparente
    (0x00, 0x00, 0x00), (0x3E, 0xB8, 0x49), (0x74, 0xD0, 0x7D),
    (0x59, 0x55, 0xE0), (0x80, 0x76, 0xF1), (0xB9, 0x5E, 0x51),
    (0x65, 0xDB, 0xEF), (0xDB, 0x65, 0x59), (0xFF, 0x89, 0x7D),
    (0xCC, 0xC3, 0x5E), (0xDE, 0xD0, 0x87), (0x3A, 0xA2, 0x41),
    (0xB7, 0x66, 0xB5), (0xCC, 0xCC, 0xCC), (0xFF, 0xFF, 0xFF),
]

NOMBRE_MSX = ["transparente", "negro", "verde medio", "verde claro",
              "azul oscuro", "azul claro", "rojo oscuro", "cian",
              "rojo medio", "rojo claro", "amarillo oscuro", "amarillo claro",
              "verde oscuro", "magenta", "gris", "blanco"]

# La paleta con la que se dibuja y se relee el lienzo de los tiles: el indice
# sigue siendo el del atributo del ZX -color 0-7 y el bit 3, el brillo-, pero el
# COLOR que se ve es el que el juego acaba poniendo en la pantalla del MSX. Asi
# el lienzo enseña lo que se ve jugando y no lo que se veria en un Spectrum.
ZX_EN_MSX = [MSX[(TABLA_CON if i & 8 else TABLA_SIN)[i & 7]] for i in range(16)]

# TRES DE LOS QUINCE COLORES DEL MSX NO SALEN DE ESAS DOS TABLAS: el verde medio
# (2), el rojo medio (8) y el gris (14). No hay atributo del Spectrum que los
# produzca, asi que un tile no los puede llevar por mucho que se pinten.
MSX_ALCANZABLES = sorted(set(TABLA_SIN) | set(TABLA_CON))

# Y CUATRO DE LOS OCHO COLORES DEL ZX SE VEN IGUAL con brillo y sin el, porque
# las dos tablas les dan el mismo color del MSX: el negro, el magenta, el cian y
# el blanco. Esos cuatro no obligan a nada al brillo de su casilla; los otros
# cuatro -azul, rojo, verde y amarillo- si.
EXIGE_BRILLO = {i for i in range(8) if TABLA_SIN[i] != TABLA_CON[i]}

# La de los sprites: TRES estados, y los tres hacen falta. No es una eleccion:
# la rutina que los pinta (0x887B) hace `and` con la mascara y `or` con el
# dibujo, asi que un pixel puede dejar el fondo como estaba (mascara 1), o
# escribirlo a papel (mascara 0, dibujo 0) o a tinta (mascara 0, dibujo 1). Los
# dos primeros SE VEN IGUAL cuando debajo hay papel, pero son bytes distintos y
# los dos aparecen: 12.489 pixels transparentes y 2.892 negros escritos, en 153
# de los 176 sprites. Con dos colores no se podrian distinguir.
#
# El transparente NO se marca con un color inventado tipo chroma-key: se marca
# con el FONDO que ya usan las laminas publicadas de la web
# (tools/render_graficos.py), #18181C, y ademas se declara transparente de
# verdad en el PNG, para que el editor lo enseñe como tal. Al leer valen las dos
# cosas: el pixel con alfa a cero -la goma- y el pixel de ese color, que es lo
# que queda si se aplana la imagen.
TRANSPARENTE, NEGRO, BLANCO = 0, 1, 2
FONDO = (24, 24, 28)                 # el mismo de tools/render_graficos.py
SPRITE = [FONDO, (0, 0, 0), (255, 255, 255)]
NOMBRE_SPRITE = ["transparente", "negro", "blanco"]

# La de la fuente: un bit, un pixel. El indice ES el bit -0 papel, 1 tinta-, o
# sea que MONO[0] es el papel y MONO[1] la tinta.
#
# Y SE PINTA COMO SE VE JUGANDO, igual que el de los tiles, no como el mapa de
# bits en crudo. El parche pone el atributo del texto (0x763F) en 0x70 -papel 6
# con brillo-, que ATRIBUTO_A_COLOR manda al color 11 del MSX: el amarillo claro
# de los marcos. Asi que el papel es ese amarillo y la tinta es negra. Antes era
# al reves -tinta blanca sobre papel negro-, que es el crudo y no se parecia a
# nada de lo que sale en pantalla.
MONO = [MSX[11], (0, 0, 0)]
NOMBRE_MONO = ["amarillo claro", "negro"]


def canon_zx(indice):
    """El indice del ZX, con el brillo quitado a quien no lo luce.

    Cuatro de los ocho colores dan el MISMO color del MSX con brillo y sin el
    (EXIGE_BRILLO): el negro, el magenta, el cian y el blanco. Mirando la imagen
    no hay forma de distinguir sus dos versiones, asi que aqui se cuentan como
    el mismo color y se quedan con el indice bajo. Sin esto, un tile de negro
    brillante sobre blanco brillante -los hay, el 103 y el 105- no se
    reconoceria al releerlo y volveria con la tinta y el papel del reves.
    """
    return indice if (indice & 7) in EXIGE_BRILLO else indice & 7


def sin_canon(indice):
    return indice


def nombra_zx(indice):
    """Como se llama el color que se VE, que es el del MSX, y de donde sale."""
    msx = (TABLA_CON if indice & 8 else TABLA_SIN)[indice & 7]
    return "%s (MSX %d, atributo %s%s)" % (
        NOMBRE_MSX[msx], msx, NOMBRE_COLOR[indice & 7],
        " con brillo" if indice & 8 else "")


# ===========================================================================
# PNG: escribir y leer, sin dependencias (aqui no hay PIL)
# ===========================================================================
def _trozo(tipo, datos):
    return (struct.pack(">I", len(datos)) + tipo + datos
            + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))


def escribe_png(ruta, ancho, alto, indices, paleta, transparente=None):
    """PNG indexado de 8 bits. La paleta va dentro, asi que el editor la ofrece
    hecha y no hay manera de pintar un color que el juego no sepa dar.

    `transparente` es el indice que ademas se declara transparente (tRNS), para
    que el editor enseñe como tal lo que en el juego deja pasar el fondo. Su
    color sigue estando en la paleta, asi que aplanar la imagen no lo pierde.
    """
    crudo = b"".join(b"\x00" + bytes(f) for f in indices)
    plte = b"".join(bytes(c) for c in paleta)
    trns = b""
    if transparente is not None:
        trns = _trozo(b"tRNS", bytes([255] * transparente + [0]))
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + _trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 3, 0, 0, 0))
                + _trozo(b"PLTE", plte) + trns
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
    """Devuelve (ancho, alto, filas, opacos).

    filas[y][x] = (r, g, b) y opacos[y][x] = si el pixel es opaco. Traga lo que
    escupen los editores de verdad: indexado, gris, RGB y RGBA, a 1, 2, 4, 8 o
    16 bits. Lo unico que no acepta es el entrelazado Adam7, y lo dice claro en
    vez de sacar ruido.
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
    filas, opacos = [], []
    for linea in lineas:
        if prof < 8:
            valores = _bits(linea, ancho * canales, prof)
        elif prof == 8:
            valores = list(linea)
        else:                                   # 16 bits: nos quedamos el alto
            valores = [linea[i] for i in range(0, len(linea), 2)]
        fila, opaca = [], []
        for x in range(ancho):
            v = valores[x * canales:(x + 1) * canales]
            op = True
            if color == 3:
                if paleta is None or v[0] >= len(paleta):
                    raise ErrorDeLienzo("el PNG indexado apunta fuera de su paleta")
                if trns and v[0] < len(trns) and trns[v[0]] < 128:
                    op = False
                rgb = paleta[v[0]]
            elif color == 0:
                g = v[0] if prof >= 8 else v[0] * 255 // maximo
                rgb = (g, g, g)
            elif color == 4:
                op = v[1] >= 128
                rgb = (v[0], v[0], v[0])
            elif color == 2:
                rgb = (v[0], v[1], v[2])
            else:                               # RGBA
                op = v[3] >= 128
                rgb = (v[0], v[1], v[2])
            fila.append(rgb)
            opaca.append(op)
        filas.append(fila)
        opacos.append(opaca)
    return ancho, alto, filas, opacos


# ===========================================================================
# Los tres codecs: de los bytes al dibujo y del dibujo a los bytes
# ===========================================================================
def dibuja_tile(nueve):
    """Los nueve bytes de un tile, como 8x8 indices de la paleta del ZX."""
    attr = nueve[8]
    brillo = 8 if attr & 0x40 else 0
    tinta = canon_zx((attr & 0x07) + brillo)
    papel = canon_zx(((attr >> 3) & 0x07) + brillo)
    return [[tinta if nueve[y] & (0x80 >> x) else papel for x in range(8)]
            for y in range(8)]


def codifica_tile(celda, referencia, numero):
    """Una casilla de 8x8 (indices del ZX) -> los nueve bytes del tile.

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
            "la casilla %d usa %d colores (%s) y el Spectrum solo da DOS por "
            "casilla de 8x8: una tinta y un papel"
            % (numero, len(colores), ", ".join(nombra_zx(c) for c in colores)))

    # El brillo es de la casilla entera. Los cuatro colores que se ven igual con
    # brillo y sin el no obligan a nada; los otros cuatro si.
    exigen = [c for c in colores if (c & 7) in EXIGE_BRILLO]
    brillos = {c >> 3 for c in exigen}
    if len(brillos) > 1:
        raise ErrorDeLienzo(
            "la casilla %d mezcla %s: el bit de brillo es UNO para toda la "
            "casilla, asi que sus dos colores tienen que salir los dos de la "
            "misma tabla (el negro, el magenta, el cian y el blanco valen para "
            "las dos)" % (numero, " y ".join(nombra_zx(c) for c in exigen)))
    brillo = brillos.pop() if brillos else (1 if referencia[8] & 0x40 else 0)

    if len(colores) == 1:
        papel = tinta = colores[0] & 7
        dibujo = [0] * 8
    else:
        ref = dibuja_tile(referencia)
        antes = set()
        for y in range(8):
            antes.update(ref[y])
        tinta_ref = canon_zx((referencia[8] & 0x07)
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


# El recorrido de 0x887B, que es de donde sale el orden de los 32 bytes. Por
# cada byte de pantalla hace `ld a,(de) / and (hl) / inc hl / or (hl) / inc hl /
# ld (de),a`, o sea que van en PAREJAS -primero la mascara, que se cruza con lo
# que ya hay, y detras el dibujo, que se suma- y HL avanza de dos en dos. Y las
# parejas van en zigzag porque la rutina escribe la izquierda, `inc e` a la
# derecha, `inc d` para bajar una linea y `dec e` para volver a la izquierda:
# asi se ahorra recolocar DE.
ORDEN_SPRITE = []
for _f in range(0, 8, 2):
    ORDEN_SPRITE += [(_f, 0), (_f, 1), (_f + 1, 1), (_f + 1, 0)]


def dibuja_sprite(treintaydos):
    """Los 32 bytes de un sprite, como 8 filas de 16 indices (transp/negro/blanco).

    La mascara tiene el sentido de siempre: donde vale 1 se conserva el fondo,
    asi que ahi el sprite es transparente.
    """
    dib = [[TRANSPARENTE] * 16 for _ in range(8)]
    for n, (fila, col) in enumerate(ORDEN_SPRITE):
        m, b = treintaydos[n * 2], treintaydos[n * 2 + 1]
        for bit in range(8):
            if m & (0x80 >> bit):
                continue                        # transparente: manda el fondo
            dib[fila][col * 8 + bit] = BLANCO if b & (0x80 >> bit) else NEGRO
    return dib


def codifica_sprite(celda, referencia, numero):
    """8x16 indices -> los 32 bytes, en el mismo zigzag.

    No hace falta ninguna regla de desempate: los tres estados caben sin
    ambiguedad en los dos bits. Lo unico que se pierde son los bits de dibujo
    que hubiera DEBAJO de la mascara, que no se ven; en esta cinta no hay
    ninguno encendido (medido: 0 de 12.489 pixels transparentes).
    """
    fuera = bytearray(32)
    for n, (fila, col) in enumerate(ORDEN_SPRITE):
        m = b = 0
        for bit in range(8):
            v = celda[fila][col * 8 + bit]
            if v == TRANSPARENTE:
                m |= 0x80 >> bit
            elif v == BLANCO:
                b |= 0x80 >> bit
        fuera[n * 2], fuera[n * 2 + 1] = m, b
    return bytes(fuera)


def dibuja_caracter(ocho):
    """Los ocho bytes de un caracter, como 8x8 indices (negro/blanco)."""
    return [[1 if ocho[y] & (0x80 >> x) else 0 for x in range(8)]
            for y in range(8)]


def codifica_caracter(celda, referencia, numero):
    """8x8 indices -> los ocho bytes. Un bit, un pixel: no hay nada que decidir."""
    fuera = []
    for y in range(8):
        v = 0
        for x in range(8):
            if celda[y][x]:
                v |= 0x80 >> x
        fuera.append(v)
    return bytes(fuera)


# ===========================================================================
# Las tres hojas
# ===========================================================================
class Hoja:
    """Un tramo del bloque alto y como se dibuja y se relee.

    `agrupa` son las entradas que se apilan en vertical dentro de una figura del
    lienzo: 1 para los tiles y la fuente, 2 para los sprites, que encajan de dos
    en dos en figuras de 16x16.
    """

    def __init__(self, nombre, png, que_es, plural, ini, fin, paso, ancho, alto,
                 cols, agrupa, paleta, dibuja, codifica, opacidad, canon=sin_canon):
        self.nombre, self.png = nombre, png
        self.que_es, self.plural = que_es, plural
        self.ini, self.fin, self.paso = ini, fin, paso
        self.ancho, self.alto, self.cols, self.agrupa = ancho, alto, cols, agrupa
        self.paleta, self.dibuja, self.codifica = paleta, dibuja, codifica
        self.opacidad, self.canon = opacidad, canon
        self.cuantos = (fin - ini) // paso
        figuras = (self.cuantos + agrupa - 1) // agrupa
        filas = (figuras + cols - 1) // cols
        self.px_ancho = cols * ancho
        self.px_alto = filas * alto * agrupa

    def sitio(self, n):
        """Donde cae la entrada n dentro del lienzo: (x, y) de su esquina."""
        figura, dentro = divmod(n, self.agrupa)
        return ((figura % self.cols) * self.ancho,
                (figura // self.cols) * self.alto * self.agrupa + dentro * self.alto)

    def bytes_de(self, tabla, n):
        return tabla[n * self.paso:(n + 1) * self.paso]

    def como_se_llaman(self, primero, ultimo):
        """"el tile 85", "los sprites 12-13", "el caracter 65 ('A')"."""
        if primero != ultimo:
            return "los %s %d-%d" % (self.plural, primero, ultimo)
        if self.nombre == "fuente" and 0x20 <= primero < 0x7F:
            return "el caracter %d ('%s')" % (primero, chr(primero))
        return "el %s %d" % (self.que_es, primero)


HOJAS = [
    Hoja("tiles", "tiles_del_mapa.png", "tile", "tiles",
         0x9E00, 0xA280, 9, 8, 8, 16, 1, ZX_EN_MSX,
         dibuja_tile, codifica_tile, "prohibida", canon_zx),
    Hoja("sprites", "sprites_de_batalla.png", "sprite", "sprites",
         0xA2E8, 0xB8E8, 32, 16, 8, 11, 2, SPRITE,
         dibuja_sprite, codifica_sprite, "transparente"),
    Hoja("fuente", "fuente.png", "caracter", "caracteres",
         0xC800, 0xCC00, 8, 8, 8, 16, 1, MONO,
         dibuja_caracter, codifica_caracter, "prohibida"),
]
POR_NOMBRE = {h.nombre: h for h in HOJAS}


def tabla_del_bloque(alto_raw, hoja):
    """Los bytes de esa hoja dentro del cuerpo del bloque alto."""
    return bytes(alto_raw[hoja.ini - ORG:hoja.fin - ORG])


# ===========================================================================
# De los bytes al lienzo
# ===========================================================================
def a_indices(tabla, hoja):
    """La tabla de la hoja -> las filas de indices del lienzo."""
    if len(tabla) != hoja.cuantos * hoja.paso:
        raise ErrorDeLienzo("la tabla de %s mide %d bytes y tiene que medir %d"
                            % (hoja.nombre, len(tabla), hoja.cuantos * hoja.paso))
    lienzo = [[0] * hoja.px_ancho for _ in range(hoja.px_alto)]
    for n in range(hoja.cuantos):
        dib = hoja.dibuja(hoja.bytes_de(tabla, n))
        ox, oy = hoja.sitio(n)
        for y in range(hoja.alto):
            for x in range(hoja.ancho):
                lienzo[oy + y][ox + x] = dib[y][x]
    return lienzo


def saca_lienzo(tabla, hoja, ruta):
    escribe_png(ruta, hoja.px_ancho, hoja.px_alto, a_indices(tabla, hoja), hoja.paleta,
                TRANSPARENTE if hoja.opacidad == "transparente" else None)


# ===========================================================================
# Del lienzo a los bytes
# ===========================================================================
def _indice_del_color(rgb, hoja):
    """El indice de la paleta de la hoja, y si el color era exacto o el mas cercano."""
    if rgb in hoja.paleta:
        return hoja.canon(hoja.paleta.index(rgb)), True
    mejor, dist = 0, None
    for i, c in enumerate(hoja.paleta):
        d = sum((a - b) ** 2 for a, b in zip(rgb, c))
        if dist is None or d < dist:
            mejor, dist = i, d
    return hoja.canon(mejor), False


def _nombra(indice, hoja):
    if hoja.paleta is ZX_EN_MSX:
        return nombra_zx(indice)
    if hoja.paleta is SPRITE:
        return NOMBRE_SPRITE[indice]
    return NOMBRE_MONO[indice]


def lee_lienzo(ruta, referencia, hoja):
    """El PNG editado -> los bytes de la hoja. Devuelve (tabla, avisos).

    `referencia` es la tabla tal y como viene en la cinta. Toda entrada que se
    vea EXACTAMENTE igual que la suya se devuelve con sus bytes de siempre: es
    lo que hace que abrir y guardar el PNG sin tocar nada no mueva un solo byte.
    """
    ancho, alto, filas, opacos = lee_png(ruta)
    if (ancho, alto) != (hoja.px_ancho, hoja.px_alto):
        raise ErrorDeLienzo(
            "el lienzo de %s tiene que medir %dx%d (%d de %dx%d en %d columnas%s) "
            "y mide %dx%d. No lo escales: un pixel del PNG es un pixel del juego."
            % (hoja.nombre, hoja.px_ancho, hoja.px_alto, hoja.cuantos, hoja.ancho,
               hoja.alto, hoja.cols, ", de dos en dos" if hoja.agrupa > 1 else "",
               ancho, alto))

    indices, sustituidos, transparentes = [], {}, 0
    for y in range(alto):
        fila = []
        for x in range(ancho):
            if not opacos[y][x]:
                if hoja.opacidad == "transparente":
                    fila.append(TRANSPARENTE)     # la goma tambien vale
                    continue
                transparentes += 1
            i, exacto = _indice_del_color(filas[y][x], hoja)
            if not exacto:
                visto = sustituidos.get(filas[y][x], (i, 0))
                sustituidos[filas[y][x]] = (i, visto[1] + 1)
            fila.append(i)
        indices.append(fila)
    if transparentes:
        raise ErrorDeLienzo(
            "el lienzo de %s tiene %d pixels transparentes y ahi no hay "
            "transparencia: todo pixel es un color. Aplana la imagen antes de "
            "guardarla." % (hoja.nombre, transparentes))
    avisos = []
    for rgb, (i, n) in sorted(sustituidos.items()):
        avisos.append("  %s: el color #%02X%02X%02X (%d pixels) no esta en la "
                      "paleta; se toma el mas parecido, %s"
                      % (hoja.nombre, rgb[0], rgb[1], rgb[2], n, _nombra(i, hoja)))

    fuera = bytearray()
    for n in range(hoja.cuantos):
        ox, oy = hoja.sitio(n)
        celda = [[indices[oy + y][ox + x] for x in range(hoja.ancho)]
                 for y in range(hoja.alto)]
        ref = hoja.bytes_de(referencia, n)
        if celda == hoja.dibuja(ref):
            fuera += ref                       # sin tocar: los bytes de la cinta
        else:
            fuera += hoja.codifica(celda, ref, n)
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


def tocados(antes, ahora, hoja):
    """Los numeros de entrada que cambian, para poder contarlos y nombrarlos."""
    return [n for n in range(hoja.cuantos)
            if hoja.bytes_de(antes, n) != hoja.bytes_de(ahora, n)]


# ===========================================================================
def main(argv):
    if len(argv) < 3 or argv[1] not in ("saca", "mete"):
        print(__doc__)
        return 2
    orden, raw = argv[1], argv[2]
    sueltos = [a for a in argv[3:] if not a.startswith("-")]
    carpeta = sueltos[0] if sueltos else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src", "parche")
    cuales = [POR_NOMBRE[n] for n in sueltos[1:]] if len(sueltos) > 1 else HOJAS
    if not os.path.exists(raw):
        print("  falta %s: hazlo antes con `make extract`" % raw)
        return 2
    crudo = open(raw, "rb").read()

    if orden == "saca":
        os.makedirs(carpeta, exist_ok=True)
        malo = 0
        for h in cuales:
            ruta = os.path.join(carpeta, h.png)
            if os.path.exists(ruta) and "--rehaz" not in argv:
                print("  %s ya existe. Los lienzos del repositorio llevan ENCIMA\n"
                      "  los dibujos del parche, y esto los dejaria como vienen en\n"
                      "  la cinta. Si es lo que quieres, pasa --rehaz." % ruta)
                malo = 1
                continue
            saca_lienzo(tabla_del_bloque(crudo, h), h, ruta)
            print("  %-28s %3d %s de %dx%d, %dx%d pixels, sin escalar"
                  % (ruta, h.cuantos, h.nombre, h.ancho, h.alto,
                     h.px_ancho, h.px_alto))
        return malo

    total = 0
    for h in cuales:
        ruta = os.path.join(carpeta, h.png)
        if not os.path.exists(ruta):
            print("  %s: no hay lienzo" % h.nombre)
            continue
        tabla = tabla_del_bloque(crudo, h)
        try:
            nueva, avisos = lee_lienzo(ruta, tabla, h)
        except ErrorDeLienzo as e:
            print("  %s" % e)
            return 1
        for a in avisos:
            print(a)
        cambia = tocados(tabla, nueva, h)
        if not cambia:
            print("  %-8s no cambia ni un byte de 0x%04X" % (h.nombre, h.ini))
            continue
        print("  %-8s %d cambiados: %s"
              % (h.nombre, len(cambia), ", ".join(map(str, cambia))))
        for off, viejo, nuevo in tramos(tabla, nueva):
            total += len(nuevo)
            print("    0x%04X  %3d B  %s -> %s"
                  % (h.ini + off, len(viejo), viejo.hex(), nuevo.hex()))
    if total:
        print("  %d bytes de graficos" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
