#!/usr/bin/env python3
"""EL MAPA GENERAL, DIBUJADO AQUI: los 6.144 bytes del lienzo, sin emulador.

DIBUJA_EL_MAPA (0x8166) cuesta 13.696.000 ciclos -3,83 segundos- y el 89 % de
eso es recorrer 126 x 93 y 127 x 96 casillas estampando pixeles de dos en dos.
Y es un dibujo que NO cambia en toda la partida: el nibble bajo del byte de
mapa es lo unico que se mira, y lo que se mueve -las unidades- no son pixeles
sino ATRIBUTOS (REPINTA_LOS_EJERCITOS, 0x6AAF, solo toca 0x5800-0x5AFF).

Asi que el cartucho lo lleva ya dibujado, comprimido con ZX0, y lo descomprime
en su sitio. Para eso hay que saber dibujarlo aqui, y esto es la TRANSCRIPCION
de las rutinas del juego, instruccion a instruccion, no una version libre:

    PINTA_TERRENO_BAJO   0x8044   tipos 1..9: un pixel doble y los puentes a
                                  las casillas vecinas que sean del mismo tipo
    PINTA_TERRENO_ALTO   0x80BD   tipos 10..15: una cruz de cinco pixeles
                                  dobles recortada de un dibujo de 8x8
    PUNTO_A_DIRECCION    0x7E4F   fila y columna en pixeles -> direccion de
                                  pantalla del ZX y mascara del pixel doble
    PINTA_EL_PUNTO       0x7E86   el pixel doble, con el dibujo de 8x8
    PINTA_SIN_MOVER      0x7EF5   el pixel doble, con el relleno de 0x7E76
    ELIGE_EL_RELLENO     0x7E7A   uno de los cuatro de 0x83F8

Lo que garantiza que la transcripcion es fiel no es leerla: es que el resultado
se coteja BYTE A BYTE con el volcado del emulador en 0x81C1, que es donde el
juego acaba de dibujarlo (tools/omsx_mapa.tcl / `make verifica_mapa`).

El mapa sale de la cinta y de nada mas: viaja comprimido en el bloque alto y lo
desempaqueta DESCOMPRIME_EL_MAPA (0x9366); aqui se usa el mismo descompresor
que tools/render_mapa_completo.py.

Uso:
    mapa_general.py <work> <lienzo.bin>            los 6.144 bytes
    mapa_general.py <work> <lienzo.png> --png      para mirarlo
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lienzos                                              # noqa: E402
import render_mapa_completo                                 # noqa: E402

ORG_MEDIO = 0x5E00
LIENZO = 0x4000                 # la pantalla del ZX emulada: 6.144 B de bitmap
TAM_LIENZO = 0x1800
MAPA = 0xCC00                   # 130 columnas de 102 bytes
RELLENOS = 0x83F8               # los cuatro rellenos de ELIGE_EL_RELLENO
TRAMAS = 0x83FC                 # las cuatro de PINTA_EL_PUNTO (que las lee y no las usa)
TABLA = 0x8030                  # las diez palabras que despachan por tipo de terreno
# Los dibujos de 8x8 de PINTA_TERRENO_ALTO, por tipo menos 10. Y OJO, que aqui
# hay una ERRATA DEL JUEGO: el bucle de 0x8188 hace `sub 00ah / inc b / call
# nc`, y el `inc b` PISA EL FLAG Z. PINTA_TERRENO_ALTO lo guarda con `push af`
# y lo recupera con `pop af` creyendo que trae el del `sub`, asi que su primer
# `jr z` -el que elegiria el dibujo de 0x848F para el tipo 10- prueba en
# realidad si B+1 vale cero, cosa que no pasa nunca (B va de 93 a 1). El
# resultado: el dibujo de 0x848F NO SE USA JAMAS y el tipo 10 acaba en el
# `ld hl,08477h` del final, el mismo que los tipos 14 y 15. Los tres `dec a`
# de despues si ponen el Z, y por eso los tipos 11, 12 y 13 aciertan.
# Esto lo destapo el cotejo byte a byte con el emulador, no la lectura.
DIBUJOS_ALTOS = {1: 0x847F, 2: 0x8487, 3: 0x846F}
DIBUJO_ALTO_RESTO = 0x8477      # los tipos 10, 14 y 15
DIBUJO_MUERTO = 0x848F          # el que la errata deja sin usar
# Y a donde van las diez palabras de la tabla, que se comprueban
DESPACHO = {0x8071: "unida", 0x8062: "terreno_2", 0x8068: "terreno_3_y_4",
            0x805C: "terreno_5", 0x80AE: "terreno_6", 0x80AD: "no_se_pinta"}
# Los colores del MSX con los que el juego pinta el mapa: atributo 0x30 en las
# 768 celdas (0x81C4), o sea tinta 0 sobre papel 6
ATRIBUTO_MAPA = 0x30


def rrca(a):
    return ((a >> 1) | ((a & 1) << 7)) & 0xFF, bool(a & 1)


def rlca(a):
    return ((a << 1) | (a >> 7)) & 0xFF, bool(a & 0x80)


def rrc(a):
    return rrca(a)


class Dibujante:
    """El motor del mapa general, con los registros que las rutinas se pasan
    en globales, como en el juego: `relleno` es el operando de 0x7E75 y
    `dibujo` los de 0x7E97/0x7E9A."""

    def __init__(self, medio, mapa):
        self.medio = medio
        self.ram = bytearray(0x10000)
        self.ram[MAPA:MAPA + len(mapa)] = mapa
        self.relleno = 0
        self.dibujo = 0
        # la pantalla y la mascara del pixel doble, que las rutinas se pasan
        # en HL y en BC
        self.h = self.l = 0
        self.b = self.c = 0

    def med(self, dire, n=1):
        o = dire - ORG_MEDIO
        return self.medio[o:o + n]

    # ------------------------------------------------------------ el lienzo
    def lienzo(self):
        return bytes(self.ram[LIENZO:LIENZO + TAM_LIENZO])

    # -------------------------------------------------- 0x7E7A y 0x7E4F
    def elige_el_relleno(self, a):
        """ELIGE_EL_RELLENO (0x7E7A): uno de los cuatro de 0x83F8 segun A y 3."""
        self.relleno = self.med(RELLENOS + (a & 3))[0]

    def punto_a_direccion(self, b, c):
        """PUNTO_A_DIRECCION (0x7E4F): B = fila y C = columna EN PIXELES.
        Deja la direccion en HL y, en B y C, la mascara y el relleno ya
        recortado al hueco de dos pixeles."""
        a = b & 0xC0
        a = (a >> 1) & 0xFF                     # rra con el acarreo a cero (lo dejo el `and`)
        a = ((a >> 1) | 0x80) & 0xFF            # scf / rra
        a, _ = rrca(a)
        a ^= b
        a &= 0xF8
        a ^= b
        self.h = a
        a = c
        for _ in range(3):
            a, _ = rlca(a)
        a ^= b
        a &= 0xC7
        a ^= b
        for _ in range(2):
            a, _ = rlca(a)
        self.l = a
        a = c
        a, _ = rrca(a)
        a &= 3
        cuantos = (a + 1) & 0xFF
        a = 0xFC                                # los seis unos que dejan el hueco de dos pixeles
        for _ in range(cuantos):
            a, _ = rrca(a)
            a, _ = rrca(a)
        self.b = a
        self.c = self.relleno & (~a & 0xFF)

    # -------------------------------------------- el lapiz: 0x7EAE .. 0x7EF9
    def escribe(self, d, v):
        assert LIENZO <= d < LIENZO + TAM_LIENZO, \
            "el dibujo se sale del lienzo: 0x%04X" % d
        self.ram[d] = v

    def pinta_sin_mover(self):
        """PINTA_SIN_MOVER (0x7EF5)."""
        d = (self.h << 8) | self.l
        self.escribe(d, (self.ram[d] & self.b) | self.c)

    def pinta_el_punto(self):
        """PINTA_EL_PUNTO (0x7E86): como el anterior pero con la linea que toque
        del dibujo de 8x8 en vez del relleno. El `ld a,(de)` de la trama de
        0x83FC esta y se pisa sin usarse: se deja por fidelidad."""
        self.med(TRAMAS + ((rrca(self.l)[0]) & 3))          # la trama que se lee y no se usa
        linea = self.med(self.dibujo + (self.h & 7))[0]
        d = (self.h << 8) | self.l
        c = linea & (~self.b & 0xFF)
        self.escribe(d, (self.ram[d] & self.b) | c)

    def baja_una_linea(self):
        """BAJA_UNA_LINEA (0x7EAE)."""
        self.h = (self.h + 1) & 0xFF
        if self.h & 7:
            return
        self.h = (self.h - 8) & 0xFF
        a = self.l + 0x20
        self.l = a & 0xFF
        if a > 0xFF:
            self.h = (self.h + 8) & 0xFF

    def sube_una_linea(self):
        """SUBE_UNA_LINEA (0x7EC4)."""
        self.h = (self.h - 1) & 0xFF
        if (self.h & 7) != 7:
            return
        self.h = (self.h + 8) & 0xFF
        a = self.l - 0x20
        self.l = a & 0xFF
        if a < 0:
            self.h = (self.h - 8) & 0xFF

    def corre_a_la_derecha(self):
        """CORRE_A_LA_DERECHA (0x7EDC): dos rotaciones; si el hueco da la
        vuelta, al byte siguiente."""
        self.c, _ = rrc(self.c)
        self.c, _ = rrc(self.c)
        self.b, _ = rrc(self.b)
        self.b, cy = rrc(self.b)
        if not cy:
            self.l = (self.l + 1) & 0xFF
            if self.l == 0:
                self.h = (self.h + 1) & 0xFF

    def corre_a_la_izquierda(self):
        """CORRE_A_LA_IZQUIERDA (0x7EEA)."""
        self.c, _ = rlca(self.c)
        self.c, _ = rlca(self.c)
        self.b, _ = rlca(self.b)
        self.b, cy = rlca(self.b)
        if not cy:
            self.l = (self.l - 1) & 0xFF
            if self.l == 0xFF:
                self.h = (self.h - 1) & 0xFF

    # ----------------------------------------------- los tipos 1..9: 0x8044
    def pinta_terreno_bajo(self, a, b, c, iy):
        """PINTA_TERRENO_BAJO (0x8044): A = tipo 1..9, B = fila, C = columna,
        IY = la casilla. Despacha por la tabla de 0x8030."""
        if a == 0:
            return
        self.elige_el_relleno(a)
        e = a
        t = self.med(TABLA + (a - 1) * 2, 2)
        destino = t[0] | (t[1] << 8)
        cual = DESPACHO.get(destino)
        assert cual, "la tabla de 0x8030 manda a 0x%04X, que no es ninguna de las conocidas" % destino
        if cual == "terreno_5":
            self.elige_el_relleno(1)            # trama llena, pero se une con el terreno 1
            e = 1
            self.pinta_casilla_unida(b, c, e, iy)
        elif cual == "terreno_2":
            self.elige_el_relleno(2)
            e = 2
            self.pinta_casilla_unida(b, c, e, iy)
        elif cual == "terreno_3_y_4":
            self.elige_el_relleno(1)            # los dos, llenos, y unidos con el 3
            e = 3
            self.pinta_casilla_unida(b, c, e, iy)
        elif cual == "unida":
            self.pinta_casilla_unida(b, c, e, iy)
        elif cual == "terreno_6":
            self.punto_a_direccion((b << 1) & 0xFF, (c << 1) & 0xFF)
            self.pinta_sin_mover()
        # no_se_pinta: los tipos 7, 8 y 9 no dibujan nada

    def pinta_casilla_unida(self, b, c, e, iy):
        """PINTA_CASILLA_UNIDA (0x8071): el pixel de la casilla y los puentes a
        las cuatro vecinas que sean del tipo E."""
        self.punto_a_direccion((b << 1) & 0xFF, (c << 1) & 0xFF)
        self.pinta_sin_mover()
        self.corre_a_la_derecha()
        if self.ram[(iy + 0x66) & 0xFFFF] & 0x0F == e:
            self.pinta_sin_mover()
        self.baja_una_linea()
        if self.ram[(iy + 0x67) & 0xFFFF] & 0x0F == e:
            self.pinta_sin_mover()
        self.corre_a_la_izquierda()
        if self.ram[(iy + 1) & 0xFFFF] & 0x0F == e:
            self.pinta_sin_mover()
        self.corre_a_la_izquierda()
        if self.ram[(iy - 0x65) & 0xFFFF] & 0x0F == e:
            self.pinta_sin_mover()

    # -------------------------------------------- los tipos 10..15: 0x80BD
    def pinta_terreno_alto(self, a, b, c):
        """PINTA_TERRENO_ALTO (0x80BD): A = tipo menos 10, B = fila, C =
        columna. Cinco pixeles dobles en cruz, recortados de un dibujo de 8x8."""
        if b >= 0x61:                           # de la fila 0x61 para abajo no se pinta
            return
        self.dibujo = DIBUJOS_ALTOS.get(a, DIBUJO_ALTO_RESTO)
        self.punto_a_direccion((b << 1) & 0xFF, (c << 1) & 0xFF)
        self.pinta_el_punto()
        self.corre_a_la_derecha()
        self.pinta_el_punto()
        self.baja_una_linea()
        self.corre_a_la_izquierda()
        self.pinta_el_punto()
        self.sube_una_linea()
        self.corre_a_la_izquierda()
        self.pinta_el_punto()
        self.corre_a_la_derecha()
        self.sube_una_linea()
        self.pinta_el_punto()

    # ------------------------------------------------ las dos pasadas: 0x8166
    def dibuja(self):
        """Lo que hace 0x817B-0x81C0: la trama de arranque y las dos pasadas,
        en el mismo orden y con los mismos recorridos."""
        self.elige_el_relleno(3)                # trama 3 y 3 = 3: 0x55, la de arranque
        iy = 0xFF60                             # la ultima casilla; de ahi hacia atras
        c = 0x7E                                # 126 columnas
        while True:
            b = 0x5D                            # 93 filas
            while True:
                a = self.ram[iy] & 0x0F
                a -= 10                         # sin acarreo son los tipos 10..15
                if a >= 0:
                    self.pinta_terreno_alto(a, (b + 1) & 0xFF, c)
                iy = (iy - 1) & 0xFFFF
                b = (b - 1) & 0xFF
                if b == 0:
                    break
            iy = (iy + 0xFFF7) & 0xFFFF         # -9: con las 93 filas, los 0x66 de una columna
            c -= 1
            if c == 0:
                break
        iy = 0xFF62                             # segunda pasada, dos casillas mas alla
        c = 0x7E
        while True:
            b = 0x5F                            # 95 filas, y el bucle llega hasta B = 0
            while True:
                a = self.ram[iy] & 0x0F
                if a < 0x0A:
                    self.pinta_terreno_bajo(a, b, c, iy)
                iy = (iy - 1) & 0xFFFF
                b = (b - 1) & 0xFF
                if b & 0x80:                    # `jp p`: se sale al pasar de cero
                    break
            iy = (iy + 0xFFFA) & 0xFFFF         # -6: con las 95 filas, los 0x66 de la columna
            c = (c - 1) & 0xFF
            if c & 0x80:
                break


def dibuja_el_mapa(work, medio=None, alto=None):
    """Los 6.144 bytes que el juego deja en 0x4000 al acabar las dos pasadas."""
    if alto is None:
        with open(os.path.join(work, "alto.raw"), "rb") as f:
            alto = f.read()
    if medio is None:
        with open(os.path.join(work, "medio.raw"), "rb") as f:
            medio = f.read()
    d = Dibujante(medio, render_mapa_completo.descomprime_el_mapa(alto))
    d.dibuja()
    return d.lienzo()


def a_png(lienzo, ruta):
    """El lienzo, con los colores del atributo 0x30 que 0x81C4 pone en las 768
    celdas: tinta 0 sobre papel 6."""
    t = lienzos.TABLA_SIN
    tinta, papel = t[ATRIBUTO_MAPA & 7], t[(ATRIBUTO_MAPA >> 3) & 7]
    filas = []
    for y in range(192):
        d = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        filas.append([tinta if lienzo[d + (x >> 3)] & (0x80 >> (x & 7)) else papel
                      for x in range(256)])
    lienzos.escribe_png(ruta, 256, 192, filas, lienzos.MSX)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    work, salida = argv[1], argv[2]
    lienzo = dibuja_el_mapa(work)
    if "--png" in argv:
        a_png(lienzo, salida)
        print("%s: el mapa general, 256 x 192" % salida)
    else:
        with open(salida, "wb") as f:
            f.write(lienzo)
        print("%s: %d bytes de lienzo (%d encendidos)"
              % (salida, len(lienzo), sum(bin(b).count("1") for b in lienzo)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
