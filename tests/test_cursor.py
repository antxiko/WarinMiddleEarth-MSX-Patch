#!/usr/bin/env python3
"""El cursor de la vista de cerca como sprite: tools/cursor.py y el dibujo de sprites de tools/render_vram.py.

Ninguno necesita el emulador. Los que necesitan los cuerpos de la cinta
(work/cuerpos_parche/*.raw, que salen de `make rom_parche`) se saltan si no
estan, como el resto de la serie: el repositorio no trae la cinta.
"""
import os
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import cursor                                               # noqa: E402
import lienzos                                              # noqa: E402
import render_vram                                          # noqa: E402

WORK = os.path.join(RAIZ, "work")
CUERPOS = os.path.join(WORK, "cuerpos_parche")
PNG = os.path.join(RAIZ, "src", "cartucho", "cursor.png")


def hace_falta(*rutas):
    for r in rutas:
        if not os.path.exists(r):
            raise unittest.SkipTest("falta %s: hace falta `make rom_parche` con tu cinta" % os.path.relpath(r, RAIZ))


def lienzo_vacio():
    return [[cursor.TRANSPARENTE] * cursor.ANCHO_PNG for _ in range(cursor.ALTO_PNG)]


class TestLosPlanos(unittest.TestCase):

    def test_los_cuadrantes_van_por_columnas_como_manda_el_tms9918(self):
        """Arriba a la izquierda 0-7, abajo a la izquierda 8-15, arriba a la
        derecha 16-23 y abajo a la derecha 24-31; el bit 7 es el pixel de la
        izquierda de cada byte."""
        for (x, y), (byte, bit) in (((0, 0), (0, 0x80)), ((7, 0), (0, 0x01)), ((0, 8), (8, 0x80)),
                                    ((8, 0), (16, 0x80)), ((15, 15), (31, 0x01)), ((9, 3), (19, 0x40))):
            plano = [[(px, py) == (x, y) for px in range(16)] for py in range(16)]
            octetos = cursor.plano_a_bytes(plano)
            esperado = bytearray(32)
            esperado[byte] = bit
            self.assertEqual(octetos, bytes(esperado), "el pixel (%d, %d) tenia que ir al byte %d" % (x, y, byte))
            self.assertEqual(cursor.bytes_a_plano(octetos), plano)

    def test_render_vram_dibuja_el_sprite_donde_dice_cursor_py(self):
        """La misma disposicion en los dos sitios: un sprite de 16x16 en la
        VRAM se ve, dibujado por render_vram.py, igual que lo que cursor.py
        dice que es. Es lo que hace que el cotejo por pixel valga."""
        plano = [[(px * 3 + py) % 5 == 0 for px in range(16)] for py in range(16)]     # asimetrico a proposito
        vram = bytearray(0x4000)
        vram[0x3800:0x3800 + 32] = cursor.plano_a_bytes(plano)
        for n in range(32):
            vram[0x1B00 + n * 4:0x1B00 + n * 4 + 4] = bytes([209, 0, n, 1])
        vram[0x1B00:0x1B04] = bytes([47, 40, 0, 6])                     # Y=47 -> linea 48, X=40, patron 0, color 6
        regs = [0x02, 0xE2, 0x06, 0xFF, 0x03, 0x36, 0x07, 0x01]
        _w, _h, filas = render_vram.pinta(bytes(vram), regs, escala=1)
        fondo = render_vram.PALETA[1]
        for y in range(192):
            for x in range(256):
                pixel = tuple(filas[y][x * 3:x * 3 + 3])
                dentro = 40 <= x < 56 and 48 <= y < 64
                encendido = dentro and plano[y - 48][x - 40]
                self.assertEqual(pixel, render_vram.PALETA[6] if encendido else fondo, "pixel (%d, %d)" % (x, y))

    def test_dos_colores_son_dos_planos_y_el_dibujo_va_delante(self):
        dib = [[1 if x == y else 15 for x in range(16)] for y in range(16)]     # una diagonal negra sobre blanco
        (a, ca), (b, cb) = cursor.planos_de_un_cursor(dib, "prueba")
        self.assertEqual((ca, cb), (1, 15), "el color con menos pixels es el plano A")
        self.assertEqual(cursor.bytes_a_plano(a), [[x == y for x in range(16)] for y in range(16)])
        self.assertEqual(cursor.bytes_a_plano(b), [[x != y for x in range(16)] for y in range(16)])
        visto = cursor.dibuja(a + b, bytes([ca, cb]), 0)
        self.assertEqual(visto, dib)

    def test_un_solo_color_deja_el_plano_b_vacio(self):
        dib = [[4 if (x + y) % 2 else cursor.TRANSPARENTE for x in range(16)] for y in range(16)]
        (a, ca), (b, cb) = cursor.planos_de_un_cursor(dib, "prueba")
        self.assertEqual((ca, cb), (4, 0))
        self.assertEqual(b, bytes(32))
        visto = cursor.dibuja(a + b, bytes([ca, cb]), 0)
        self.assertEqual(visto, [[4 if (x + y) % 2 else None for x in range(16)] for y in range(16)])

    def test_tres_colores_se_rechazan_nombrando_el_cursor(self):
        indices = lienzo_vacio()
        indices[0][16 + 0], indices[0][16 + 1], indices[0][16 + 2] = 1, 2, 3     # en el segundo cursor
        with self.assertRaises(cursor.ErrorDeCursor) as e:
            cursor.planos(indices)
        self.assertIn("destino", str(e.exception))
        self.assertIn("3 colores", str(e.exception))

    def test_el_png_va_y_vuelve_y_un_color_de_fuera_se_avisa(self):
        indices = lienzo_vacio()
        for y in range(16):
            for x in range(16):
                indices[y][32 + x] = 9 if x < 8 else 12                     # el tercero, con dos colores
        with tempfile.TemporaryDirectory() as d:
            ruta = os.path.join(d, "c.png")
            cursor.escribe_png(ruta, indices)
            leidos, avisos = cursor.lee_png(ruta)
            self.assertEqual(leidos, indices)
            self.assertEqual(avisos, [])
            # un PNG RGB de un editor cualquiera, con un color que no es del MSX
            filas = [[(255, 0, 0) if (x < 16 and y < 16) else lienzos.FONDO for x in range(48)] for y in range(16)]
            render_vram.png(48, 16, [sum(f, ()) for f in filas], ruta)
            leidos, avisos = cursor.lee_png(ruta)
            self.assertEqual(len(avisos), 1)
            self.assertIn("no esta en la paleta", avisos[0])
            self.assertTrue(all(leidos[y][x] == 8 for y in range(16) for x in range(16)), "el rojo puro tenia que caer en el rojo medio")
            self.assertTrue(all(leidos[y][x] == 0 for y in range(16) for x in range(16, 48)), "el fondo es transparente")

    def test_el_tamano_se_exige(self):
        with tempfile.TemporaryDirectory() as d:
            ruta = os.path.join(d, "c.png")
            lienzos.escribe_png(ruta, 16, 16, [[0] * 16 for _ in range(16)], cursor.PALETA, 0)
            with self.assertRaises(cursor.ErrorDeCursor) as e:
                cursor.lee_png(ruta)
            self.assertIn("48x16", str(e.exception))


class TestElDeFabrica(unittest.TestCase):

    def setUp(self):
        hace_falta(os.path.join(CUERPOS, "medio.raw"), os.path.join(CUERPOS, "alto.raw"))

    def test_saca_y_mete_devuelven_lo_mismo(self):
        """El PNG de fabrica, escrito y vuelto a leer, da los mismos planos que
        calcularlos de los tiles: la ida y vuelta es exacta."""
        with open(os.path.join(CUERPOS, "medio.raw"), "rb") as f:
            medio = f.read()
        with open(os.path.join(CUERPOS, "alto.raw"), "rb") as f:
            alto = f.read()
        indices = cursor.indices_de_fabrica(medio, alto)
        with tempfile.TemporaryDirectory() as d:
            ruta = os.path.join(d, "c.png")
            cursor.escribe_png(ruta, indices)
            patrones, colores, avisos = cursor.planos_del_png(ruta)
        self.assertEqual(avisos, [])
        self.assertEqual((patrones, colores), cursor.planos_de_fabrica(CUERPOS))
        self.assertEqual(len(patrones), 192)
        self.assertEqual(colores, bytes([1, 15] * 3), "los tres cursores del juego son tinta negra sobre papel blanco")

    def test_el_de_fabrica_es_el_de_los_cuatro_caracteres_del_juego(self):
        """Cada cursor son los cuatro caracteres de 0x77B5 + modo*4, dos
        arriba y dos abajo, como los escribe 0x71D0-0x71ED."""
        with open(os.path.join(CUERPOS, "medio.raw"), "rb") as f:
            medio = f.read()
        with open(os.path.join(CUERPOS, "alto.raw"), "rb") as f:
            alto = f.read()
        for modo, _nombre in cursor.MODOS:
            dib = cursor.cursor_de_fabrica(medio, alto, modo)
            codigos = medio[0x77B5 - 0x5E00 + modo * 4:][:4]
            for n, cod in enumerate(codigos):
                patron, atributo = cursor.caracter(alto, cod)
                tinta, papel = cursor.color_msx(atributo)
                oy, ox = (n // 2) * 8, (n % 2) * 8
                for y in range(8):
                    for x in range(8):
                        self.assertEqual(dib[oy + y][ox + x], tinta if patron[y] & (0x80 >> x) else papel)

    def test_el_png_del_repositorio_es_valido_y_mide_lo_que_debe(self):
        patrones, colores, avisos = cursor.planos_del_png(PNG)
        self.assertEqual(avisos, [])
        self.assertEqual(len(patrones), 192)
        self.assertEqual(len(colores), 6)
        self.assertTrue(all(c for c in colores[::2]), "todo cursor lleva al menos un color")


if __name__ == "__main__":
    unittest.main()
