#!/usr/bin/env python3
"""Repinta una captura del juego con los tiles del lienzo, casilla a casilla.

PARA QUE. Ver como quedan unos tiles nuevos en una pantalla DE VERDAD sin tener
que volver a conducir el emulador hasta ella. Una captura del mapa ya es la
pantalla que vio el jugador; aqui se identifica cada casilla de 8x8 contra los
tiles y la fuente de la cinta y se vuelve a dibujar con los del lienzo.

COMO SE IDENTIFICA UNA CASILLA. La pantalla es de 32x24 casillas y cada una
tiene como mucho dos colores, asi que de sus 64 pixels sale un dibujo de ocho
bytes -que color es tinta y cual papel se prueba de las dos maneras-. Ese dibujo
se busca:

  1. entre los 128 tiles de 0x9E00, y ademas se exige que los DOS COLORES que
     se ven sean los que da su atributo. Sin esa segunda condicion hay dibujos
     que aparecen en varios tiles con colores distintos y se elegiria mal.
  2. si no, entre los 128 caracteres de la fuente de 0xC800, que el juego pinta
     todos con el atributo 0x78 -negro sobre blanco-.

Lo que no cae en ninguno de los dos se deja tal cual y se cuenta aparte, para no
inventarse nada: una casilla sin identificar sale en el informe.

LO QUE ESTO **NO** ENSEÑA, y hay que tenerlo presente al mirar el resultado: LAS
LETRAS SON LAS DE LA CAPTURA. Aqui se repintan los tiles y, si se pide, el papel
de la fuente, pero el TEXTO no se vuelve a componer: sale el que hubiera en
pantalla el dia que se hizo el pantallazo. Las capturas de work/PARA_ARAUBI son
del 2026-09-03, o sea de ANTES de traducir los toponimos y las razas, asi que en
ellas todavia se lee "Brujo" y "Rivendell". Para ver el texto de verdad hay que
leerlo de la cinta parcheada siguiendo sus punteros, que es lo que hacen los
tests test_los_seis_adjetivos_salen_de_sus_punteros y
test_la_ultima_linea_de_la_ficha_sale_entera_y_cabe.

EL COLOR. La captura viene con la paleta del TMS9918 tal y como la saca openMSX,
que no es la misma tabla de valores RGB que usan los lienzos (esos van con la
paleta MSX1 de Aseprite/Lospec). Aqui se trabaja con el NUMERO de color del VDP
y se dibuja con la paleta de openMSX, para que el previo se vea como un pantallazo.

Uso:
    python3 tools/previo_repinta.py <captura.png> <lienzo.png> <salida.png> [attr]

`attr` es el atributo con que repintar los caracteres de la fuente; por defecto
el 0x78 que el juego lleva en 0x763F. Poniendole otro se ve como quedaria
cambiar ese byte sin tocar la cinta: 0x70, por ejemplo, es tinta negra sobre
papel amarillo CON brillo, que en el MSX es el mismo khaki de los marcos.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lienzos as L                                            # noqa: E402

ALTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "work", "alto.raw")

# La paleta del TMS9918 como la pinta openMSX, que es la de las capturas. Es la
# misma tabla que tools/render_zx.py.
OPENMSX = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]
ATRIBUTO_DE_LA_FUENTE = 0x78          # el que 0x7616 le pone a todo caracter

# EL OJO DE SAURON DE LA CAPTURA. Las capturas del repositorio estan tomadas con
# el parche puesto, asi que sus tres Ojos son los tiles 111-114 del parche VIEJO
# -negro sobre blanco-, y en la cinta esos cuatro tiles vienen a cero. Sin esto
# las doce casillas de los Ojos no se identificarian y se quedarian sin repintar.
OJO_VIEJO = bytes.fromhex(
    "011608502041418138806014888482c2c138814140215108060938c1c282040a14609038")


def color_msx(rgb):
    """El numero de color del VDP mas cercano a ese RGB de la captura."""
    return min(range(1, 16), key=lambda i: sum((a - b) ** 2
                                               for a, b in zip(rgb, OPENMSX[i])))


def del_atributo(attr):
    """(tinta, papel) en numeros de color del MSX, como los da 0x049F."""
    tabla = L.TABLA_CON if attr & 0x40 else L.TABLA_SIN
    return tabla[attr & 0x07], tabla[(attr >> 3) & 0x07]


def indice(tabla, n):
    return tabla[n * 9:(n + 1) * 9]


def repinta(captura, lienzo, salida, attr_fuente=ATRIBUTO_DE_LA_FUENTE):
    alto_raw = open(ALTO, "rb").read()
    hoja = L.POR_NOMBRE["tiles"]
    cinta = bytearray(L.tabla_del_bloque(alto_raw, hoja))
    cinta[111 * 9:111 * 9 + 36] = OJO_VIEJO
    cinta = bytes(cinta)
    nuevos, avisos = L.lee_lienzo(lienzo, cinta, hoja)
    if avisos:
        for a in avisos:
            print(a)
    fuente = alto_raw[0xC800 - L.ORG:0xCC00 - L.ORG]

    ancho, alto, filas, _ = L.lee_png(captura)
    escala = ancho // 256
    if (ancho, alto) != (256 * escala, 192 * escala):
        raise SystemExit("la captura mide %dx%d y se esperaba un multiplo de 256x192"
                         % (ancho, alto))

    # Los indices de la cinta, por dibujo: el mismo dibujo puede estar en varios
    # tiles con atributos distintos, asi que se guardan todos.
    por_dibujo = {}
    for n in range(128):
        por_dibujo.setdefault(bytes(indice(cinta, n)[:8]), []).append(n)
    caracteres = {}
    for n in range(128):
        caracteres.setdefault(bytes(fuente[n * 8:(n + 1) * 8]), n)

    cuenta = {"tile": 0, "fuente": 0, "sin identificar": 0, "lisa": 0}
    salida_px = [[(0, 0, 0)] * ancho for _ in range(alto)]
    for cy in range(24):
        for cx in range(32):
            celda = [[color_msx(filas[(cy * 8 + y) * escala][(cx * 8 + x) * escala])
                      for x in range(8)] for y in range(8)]
            vistos = sorted({c for f in celda for c in f})
            elegido = None
            if len(vistos) == 1 and vistos[0] == del_atributo(ATRIBUTO_DE_LA_FUENTE)[1]:
                # Una casilla de un solo color y justo el papel de la fuente es
                # un ESPACIO, y hay que contarla como tal: son las que rellenan
                # el interior de los paneles, y con otro atributo cambian igual
                # que las letras. Hay una sola ambiguedad y esta medida: el
                # unico tile que sale blanco liso es el 85 (atributo 0x7F, tinta
                # y papel blancos), asi que el riesgo se limita a el.
                elegido = ("fuente", 32)
            elif len(vistos) == 2:
                for tinta, papel in ((vistos[0], vistos[1]), (vistos[1], vistos[0])):
                    dib = bytes(sum(0x80 >> x for x in range(8) if celda[y][x] == tinta)
                                for y in range(8))
                    for n in por_dibujo.get(dib, ()):
                        if del_atributo(indice(cinta, n)[8]) == (tinta, papel):
                            elegido = ("tile", n)
                            break
                    if elegido:
                        break
                    if (tinta, papel) == del_atributo(ATRIBUTO_DE_LA_FUENTE) \
                            and dib in caracteres:
                        elegido = ("fuente", caracteres[dib])
                        break
            if elegido and elegido[0] == "tile":
                cuenta["tile"] += 1
                nueve = indice(nuevos, elegido[1])
                tinta, papel = del_atributo(nueve[8])
                pintado = [[OPENMSX[tinta] if nueve[y] & (0x80 >> x) else OPENMSX[papel]
                            for x in range(8)] for y in range(8)]
            elif elegido:
                cuenta["fuente"] += 1
                # El caracter se vuelve a pintar con el atributo que se pida,
                # que es lo que permite ver como quedaria cambiar el 0x78 de
                # 0x763F por otro sin tocar la cinta.
                ocho = fuente[elegido[1] * 8:(elegido[1] + 1) * 8]
                tinta, papel = del_atributo(attr_fuente)
                pintado = [[OPENMSX[tinta] if ocho[y] & (0x80 >> x) else OPENMSX[papel]
                            for x in range(8)] for y in range(8)]
            else:
                cuenta["lisa" if len(vistos) < 2 else "sin identificar"] += 1
                pintado = [[OPENMSX[celda[y][x]] for x in range(8)] for y in range(8)]
            for y in range(8):
                for x in range(8):
                    for sy in range(escala):
                        for sx in range(escala):
                            salida_px[(cy * 8 + y) * escala + sy][
                                (cx * 8 + x) * escala + sx] = pintado[y][x]

    cols, pal = {}, []
    rejilla = []
    for f in salida_px:
        fila = []
        for p in f:
            if p not in cols:
                cols[p] = len(pal)
                pal.append(p)
            fila.append(cols[p])
        rejilla.append(fila)
    L.escribe_png(salida, ancho, alto, rejilla, pal)
    print("%s: %d casillas de tile repintadas, %d de fuente, %d lisas, "
          "%d SIN IDENTIFICAR" % (salida, cuenta["tile"], cuenta["fuente"],
                                  cuenta["lisa"], cuenta["sin identificar"]))
    return cuenta


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5):
        raise SystemExit(__doc__)
    attr = int(sys.argv[4], 0) if len(sys.argv) == 5 else ATRIBUTO_DE_LA_FUENTE
    repinta(sys.argv[1], sys.argv[2], sys.argv[3], attr)
