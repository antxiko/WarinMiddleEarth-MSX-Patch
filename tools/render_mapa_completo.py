#!/usr/bin/env python3
"""Dibuja EL MAPA ENTERO del juego en un solo PNG, sin capturar pantalla.

NO es un pantallazo pegado con otros: aqui se repite lo que hace el motor de
dibujo del juego, leido del desensamblado, sobre las 128 x 100 casillas del mapa.
Si el reparto estuviera mal, saldria ruido en vez de la Tierra Media.

COMO DIBUJA EL JUEGO UNA CASILLA. `DIBUJA_EL_TROZO_DE_MAPA` (0x7643) da TRES
pasadas sobre las celdas, y cada una escribe en una pantalla de caracteres cuya
fila mide **34** (0x5E00, rellena antes con 0x80):

  1. EL TERRENO. `DESPACHA_POR_TERRENO` (0x7687) mira el nibble bajo del byte de
     mapa y salta por una tabla de dieciseis palabras en 0x7697. Solo cuatro
     clases tienen rutina -la 1, la 3, la 4 y la 6-; las demas no pintan nada
     aqui. Las tres primeras miran a los VECINOS y estampan un cuadro de 4 x 4
     caracteres, o sea que el dibujo de una casilla se mete en las de al lado:
     por eso las tres pasadas van enteras, una detras de otra, y no casilla a
     casilla.
  2. LO DE ENCIMA. `PINTA_LO_DE_ENCIMA` (0x7714): el nibble bajo elige un cuadro
     de 2 x 2 en la tabla de 0x77B5, y los ceros dejan ver lo que ya habia.
  3. LAS UNIDADES. `PINTA_LA_UNIDAD` (0x7708): con el bit 7 puesto se estampa el
     cuadro 0x15, o el 0x11 si ademas esta el bit 6. Con el parche puesto, el
     bit 5 saca el Ojo de Sauron.

LOS VECINOS. `VECINOS_IGUALES` (0x7366) devuelve un bit por vecino del terreno
que se le pida, en el orden arriba-izquierda (bit 7), arriba, arriba-derecha,
izquierda, derecha, abajo-izquierda, abajo y abajo-derecha (bit 0). En el mapa
una columna son 102 bytes y una fila un byte.

LA TABLA DE DIBUJOS. `ELIGE_EL_DIBUJO` (0x73CA) recorre entradas de la forma
`[umbral][mascara alta][mascara baja][indices...]`: si la combinacion de vecinos
es MENOR que el umbral se rinde (`SIN_DIBUJO`), si es IGUAL pinta, y si es mayor
salta tantos bytes como bits puestos traigan las dos mascaras y sigue. Cada bit
puesto es una de las dieciseis casillas del cuadro de 4 x 4, y el byte que le
toca es un INDICE sobre una base de caracteres.

    terreno 1  ->  tabla 0x797D, base 0x7819
    terreno 3  ->  tabla 0x784D, base 0x782D
    terreno 6  ->  tabla 0x784D, base 0x783D
    terreno 4  ->  sin tabla: el cuadro 0x14 si la casilla de arriba es del
                   terreno 6, y el 0x13 si no

`SIN_DIBUJO` (0x73B3) se queda con los cuatro vecinos en cruz (`and 0x5A`) y
vuelve a probar; si ni asi cambia nada, las cuatro casillas quedan a 0x81.

**El formato de esas tablas estaba SIN RESOLVER en el desensamblado**, donde el
bloque de 0x77A0 dice "formato pendiente". Esto lo cierra.

EL MAPA. 130 columnas de 102 bytes desde 0xCC00: la casilla (x, y) esta en
0xCC00 + (x+1)*102 + (y+1), asi que el terreno jugable es 128 x 100 y queda un
borde de una casilla alrededor, que es el que miran los vecinos.

Y NO HACE FALTA EL EMULADOR PARA TENERLO: el mapa viene en la cinta comprimido
en ese mismo sitio, y lo desempaqueta `DESCOMPRIME_EL_MAPA` (0x9366) nada mas
arrancar. Son 0x16ED bytes de **parejas cuenta/valor** -la cuenta va primero, y
un cero cuenta 256, que es como se comporta el `djnz`- de los que salen los
0x33CD del mapa. Asi que la imagen se saca de la cinta y de nada mas.

Uso:
    python3 tools/render_mapa_completo.py <alto.raw> <medio.raw> <salida.png>
        [--mapa <volcado.bin>] [--escala N] [--sin-unidades] [--ventana X,Y]

Sin `--mapa` se descomprime el de la cinta, que es el mapa recien empezada la
partida y **sin ninguna unidad sembrada**. Con `--mapa` se usa un volcado de los
0x33CC bytes de 0xCC00 (los saca tools/omsx_zx.tcl), que ademas trae las
unidades de esa partida.

`--ventana X,Y` dibuja solo el trozo de 16 x 13 celdas que el juego ensena con
el cursor en esa casilla, que es como se comprueba contra un volcado de verdad.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lienzos import MSX, ZX_EN_MSX, escribe_png                 # noqa: E402

ORG_MEDIO = 0x5E00
ORG_ALTO = 0x9E00

COLUMNAS, FILAS = 130, 102          # el array entero, con su borde
ANCHO, ALTO = 128, 100              # lo jugable

POOL = 0x77B5                       # los cuadros de dos por dos
TABLA_DESPACHO = 0x7697             # dieciseis palabras, una por clase de terreno
ATRIBUTO_TEXTO = 0x763F             # el operando del `ld a,078h` de 0x763E

# Los dieciseis desplazamientos del cuadro de 4 x 4, en (columna, fila) desde la
# esquina de la celda. Salen de PINTA_LAS_16_CASILLAS (0x73F0), donde una fila
# de la pantalla de caracteres mide 0x22 = 34.
CUADRO_16 = [(-1, -1), (0, -1), (1, -1), (2, -1),
             (-1, 0), (0, 0), (1, 0), (2, 0),
             (-1, 1), (0, 1), (1, 1), (2, 1),
             (-1, 2), (0, 2), (1, 2), (2, 2)]

# Los ocho vecinos de VECINOS_IGUALES, del bit 7 al bit 0.
VECINOS = [(-1, -1, 7), (0, -1, 6), (1, -1, 5), (-1, 0, 4),
           (1, 0, 3), (-1, 1, 2), (0, 1, 1), (1, 1, 0)]

MARGEN = 2                          # casillas de sobra para el desborde del 4x4

MAPA_EN_LA_CINTA = 0xCC00           # ahi esta comprimido, y ahi se desempaqueta
COMPRIMIDO = 0x16ED                 # lo que ocupa empaquetado
DESCOMPRIMIDO = 0x33CD              # y lo que mide entero


def descomprime_el_mapa(alto):
    """DESCOMPRIME_EL_MAPA (0x9366): parejas [cuenta][valor], y la cuenta a
    cero son 256 -el bucle es un `djnz`-. Para al completar 0x33CD bytes,
    incluso a mitad de una pareja."""
    ini = MAPA_EN_LA_CINTA - ORG_ALTO
    src = alto[ini:ini + COMPRIMIDO]
    fuera = bytearray()
    i = 0
    while len(fuera) < DESCOMPRIMIDO:
        if i + 1 >= len(src):
            raise SystemExit("el mapa comprimido se acaba antes de tiempo")
        cuenta, valor = src[i] or 256, src[i + 1]
        i += 2
        fuera += bytes([valor]) * min(cuenta, DESCOMPRIMIDO - len(fuera))
    return bytes(fuera[:COLUMNAS * FILAS])


class Mapa:
    """El motor de dibujo del juego, sobre una pantalla de caracteres tan ancha
    como haga falta en vez de las 34 de la de verdad."""

    def __init__(self, mapa, medio, alto, con_parche=None):
        if len(mapa) != COLUMNAS * FILAS:
            raise SystemExit("el mapa mide %d bytes y tienen que ser %d"
                             % (len(mapa), COLUMNAS * FILAS))
        self.mapa = mapa
        self.medio = medio
        self.alto = alto
        # Con el parche, PINTA_LA_UNIDAD (0x770A) es un `jp` a la rutina nueva.
        if con_parche is None:
            con_parche = self.med(0x770A) == 0xC3
        self.con_parche = con_parche
        self.ancho_car = (ANCHO + 2 * MARGEN) * 2
        self.alto_car = (ALTO + 2 * MARGEN) * 2
        # 0x80 es el relleno con que PINTA_LA_VISTA_DE_CERCA (0x71A7) borra
        self.car = [[0x80] * self.ancho_car for _ in range(self.alto_car)]

    # ---------------------------------------------------------------- memoria
    def med(self, dire):
        return self.medio[dire - ORG_MEDIO]

    def celda(self, x, y):
        """El byte de mapa de la casilla, con su borde de una."""
        if not (-1 <= x <= ANCHO and -1 <= y <= ALTO):
            return 0
        return self.mapa[(x + 1) * FILAS + (y + 1)]

    # ---------------------------------------------------- la pantalla de chars
    def pon(self, x, y, dc, df, codigo):
        cx = (x + MARGEN) * 2 + dc
        cy = (y + MARGEN) * 2 + df
        if 0 <= cx < self.ancho_car and 0 <= cy < self.alto_car:
            self.car[cy][cx] = codigo

    def estampa_2x2(self, x, y, indice):
        """ESTAMPA_DOS_POR_DOS (0x7717): cuatro codigos, y los ceros no pintan."""
        p = POOL + indice * 4
        for i, (dc, df) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
            c = self.med(p + i)
            if c:
                self.pon(x, y, dc, df, c)

    def estampa_lista(self, x, y, codigos):
        for i, (dc, df) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
            if codigos[i]:
                self.pon(x, y, dc, df, codigos[i])

    # ------------------------------------------------------------- los vecinos
    def vecinos(self, x, y, terreno, c=0):
        for dx, dy, bit in VECINOS:
            if (self.celda(x + dx, y + dy) & 0x0F) == terreno:
                c |= 1 << bit
        return c

    # ------------------------------------------------ ELIGE_EL_DIBUJO (0x73CA)
    def elige_el_dibujo(self, x, y, c, tabla, base):
        a = c
        while True:
            hl = tabla
            while True:
                umbral = self.med(hl)
                if a < umbral:                       # jr c,SIN_DIBUJO
                    a2 = a & 0x5A                    # los cuatro vecinos en cruz
                    if a2 == c:
                        for dc, df in ((0, 0), (1, 0), (0, 1), (1, 1)):
                            self.pon(x, y, dc, df, 0x81)
                        return
                    a = c = a2                       # ld c,a y otra vuelta
                    break
                d, e = self.med(hl + 1), self.med(hl + 2)
                hl += 3
                if a == umbral:                      # jr z,PINTA_LAS_16_CASILLAS
                    self.pinta_16(x, y, d, e, hl, base)
                    return
                hl += bin(d).count("1") + bin(e).count("1")

    def pinta_16(self, x, y, d, e, hl, base):
        mascara = (d << 8) | e
        for i, (dc, df) in enumerate(CUADRO_16):
            if mascara & (0x8000 >> i):
                indice = self.med(hl)
                hl += 1
                self.pon(x, y, dc, df, self.med(base + indice))

    # ------------------------------------------- las cuatro clases con rutina
    def terreno_1(self, x, y):
        """TERRENO_2 (0x76B7): los vecinos del terreno 2, AL REVES."""
        c = (~self.vecinos(x, y, 2)) & 0xFF
        self.elige_el_dibujo(x, y, c, 0x797D, 0x7819)

    def terreno_3(self, x, y):
        """TERRENO_3 (0x76C7): tambien cuentan los vecinos del 2, del 4 y del 5."""
        c = self.vecinos(x, y, 3)
        for t in (2, 4, 5):
            c = self.vecinos(x, y, t, c)
        self.elige_el_dibujo(x, y, c, 0x784D, 0x782D)

    def terreno_4(self, x, y):
        """TERRENO_CON_VECINO_6 (0x76E4): mira la casilla de arriba, entera."""
        self.estampa_2x2(x, y, 0x14 if self.celda(x, y - 1) == 6 else 0x13)

    def terreno_6(self, x, y):
        """TERRENO_6 (0x76F0): pegado al 4 y al 5."""
        c = self.vecinos(x, y, 6)
        for t in (4, 5):
            c = self.vecinos(x, y, t, c)
        self.elige_el_dibujo(x, y, c, 0x784D, 0x783D)

    # ----------------------------------------------------------- las 3 pasadas
    def pasada_terreno(self, x, y):
        n = self.celda(x, y) & 0x0F
        if n == 1:
            self.terreno_1(x, y)
        elif n == 3:
            self.terreno_3(x, y)
        elif n == 4:
            self.terreno_4(x, y)
        elif n == 6:
            self.terreno_6(x, y)

    def pasada_encima(self, x, y):
        n = self.celda(x, y) & 0x0F
        if n:
            self.estampa_2x2(x, y, n)

    def pasada_unidades(self, x, y):
        a = self.celda(x, y)
        if not (a & 0x80):
            return
        if self.con_parche and (a & 0x20):
            # DIBUJO_SEGUN_BANDO: el Ojo son los tiles 111 a 114
            self.estampa_lista(x, y, [0xEF, 0xF0, 0xF1, 0xF2])
        elif a & 0x40:
            self.estampa_2x2(x, y, 0x11)
        else:
            self.estampa_2x2(x, y, 0x15)

    def dibuja(self, celdas, unidades=True):
        for pasada in (self.pasada_terreno, self.pasada_encima,
                       self.pasada_unidades):
            if pasada is self.pasada_unidades and not unidades:
                continue
            for x, y in celdas:
                pasada(x, y)

    # ------------------------------------------------------------- a pixeles
    def a_pixeles(self, x0, y0, ancho_celdas, alto_celdas, escala=1):
        """Cada codigo con el bit 7 es un tile de nueve bytes de 0x9E00; los
        demas son caracteres de la fuente de 0xC800, que UN_CARACTER_NORMAL
        (0x7616) pinta todos con el mismo atributo."""
        attr_texto = self.med(ATRIBUTO_TEXTO)
        w = ancho_celdas * 2 * 8 * escala
        filas = []
        for cy in range(alto_celdas * 2):
            lineas = [[] for _ in range(8)]
            for cx in range(ancho_celdas * 2):
                codigo = self.car[(y0 + MARGEN) * 2 + cy][(x0 + MARGEN) * 2 + cx]
                if codigo & 0x80:
                    p = (codigo & 0x7F) * 9
                    dibujo, attr = self.alto[p:p + 8], self.alto[p + 8]
                else:
                    p = 0xC800 - ORG_ALTO + codigo * 8
                    dibujo, attr = self.alto[p:p + 8], attr_texto
                brillo = 8 if attr & 0x40 else 0
                tinta = ZX_EN_MSX[(attr & 7) | brillo]
                papel = ZX_EN_MSX[((attr >> 3) & 7) | brillo]
                for li in range(8):
                    b = dibujo[li]
                    for bit in range(8):
                        c = tinta if b & (0x80 >> bit) else papel
                        lineas[li] += [MSX.index(c)] * escala
            for li in lineas:
                for _ in range(escala):
                    filas.append(bytes(li))
        return w, len(filas), filas


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    ruta_alto, ruta_medio, salida = argv[1:4]
    escala = 1
    unidades = True
    ventana = None
    ruta_mapa = None
    resto = argv[4:]
    while resto:
        o = resto.pop(0)
        if o == "--escala":
            escala = int(resto.pop(0))
        elif o == "--sin-unidades":
            unidades = False
        elif o == "--mapa":
            ruta_mapa = resto.pop(0)
        elif o == "--ventana":
            ventana = tuple(int(v) for v in resto.pop(0).split(","))
        else:
            raise SystemExit("opcion desconocida: %s" % o)

    alto = open(ruta_alto, "rb").read()
    mapa = (open(ruta_mapa, "rb").read() if ruta_mapa
            else descomprime_el_mapa(alto))
    m = Mapa(mapa, open(ruta_medio, "rb").read(), alto)

    if ventana:
        # El trozo que ensena el juego: la esquina es (cursor - 7, cursor - 5),
        # por el `inc h` de 0x71B5 y el -720 de 0x71B9.
        x0, y0 = ventana[0] - 7, ventana[1] - 5
        # EXACTAMENTE las 16 x 13 celdas que recorre UNA_PASADA (0x7656), ni
        # una mas: el juego no dibuja las de fuera, asi que su cuadro de 4 x 4
        # tampoco se mete en el borde de la pantalla.
        celdas = [(x, y) for y in range(y0, y0 + 13)
                  for x in range(x0, x0 + 16)]
        m.dibuja(celdas, unidades)
        w, h, filas = m.a_pixeles(x0, y0, 16, 12, escala)
    else:
        celdas = [(x, y) for y in range(ALTO) for x in range(ANCHO)]
        m.dibuja(celdas, unidades)
        w, h, filas = m.a_pixeles(0, 0, ANCHO, ALTO, escala)

    escribe_png(salida, w, h, filas, MSX)
    print("%s: %d x %d px%s%s" % (salida, w, h, "" if escala == 1 else
                                  " (escala %d)" % escala,
                                  "" if unidades else ", sin unidades"))
    print("  parche detectado: %s   mapa: %s"
          % ("si" if m.con_parche else "no",
             ruta_mapa if ruta_mapa else "descomprimido de la cinta"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
