"""La marca de las unidades en el mapa general.

Tres cosas: que el dibujo que viaja en la ROM es el del PNG y el PNG el del
juego, que el parche se engancha donde toca, y -la que de verdad importa- que
el cotejo del emulador CAZA un fallo. Un cotejo que solo se ha visto pasar no
ha demostrado nada: aqui se le dan volcados con una marca sin borrar y con una
celda a medio escribir, y tiene que devolver 1 en los dos casos.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

import lienzos                                              # noqa: E402
import marca                                                # noqa: E402

PNG = os.path.join(RAIZ, "src", "cartucho", "marca.png")
COTEJA = os.path.join(RAIZ, "tools", "coteja_marcas.py")
WORK = os.path.join(RAIZ, "work")
FUENTE = 0xC800
ANILLO = 0x5F           # el caracter que el parche pinta en la ficha del Portador
BITMAP, ATRIBUTOS = 0x4000, 0x5800
FILAS, COLUMNAS = 24, 32
FONDO, MARCA = 0x30, 0x78


class ElDibujo(unittest.TestCase):
    def test_el_png_existe(self):
        self.assertTrue(os.path.exists(PNG),
                        "falta %s: `python3 tools/marca.py saca work %s`" % (PNG, PNG))

    def test_es_el_anillo_del_juego(self):
        """Los ocho bytes del PNG son los del caracter 0x5F de la fuente."""
        ruta = os.path.join(WORK, "alto_parcheado.raw")
        if not os.path.exists(ruta):
            self.skipTest("hace falta work/alto_parcheado.raw (make cuerpos)")
        with open(ruta, "rb") as f:
            alto = f.read()
        base = FUENTE - lienzos.ORG + ANILLO * 8
        self.assertEqual(marca.lee_png(PNG), alto[base:base + 8],
                         "el dibujo de marca.png ya no es el Anillo de la fuente")

    def test_ida_y_vuelta(self):
        """El PNG -> ocho bytes -> PNG no pierde nada."""
        ocho = marca.lee_png(PNG)
        tmp = tempfile.mkdtemp()
        try:
            otro = os.path.join(tmp, "m.png")
            lienzos.escribe_png(otro, 8, 8, lienzos.dibuja_caracter(ocho), marca.PALETA)
            self.assertEqual(marca.lee_png(otro), ocho)
        finally:
            shutil.rmtree(tmp)

    def test_el_inc_lleva_los_ocho_bytes(self):
        tmp = tempfile.mkdtemp()
        try:
            inc = os.path.join(tmp, "marca.inc")
            ocho = marca.escribe_inc(PNG, inc)
            with open(inc) as f:
                texto = f.read()
            self.assertIn("defb", texto)
            for b in ocho:
                self.assertIn("0%02Xh" % b, texto)
        finally:
            shutil.rmtree(tmp)


class ElParche(unittest.TestCase):
    """Donde se engancha: el `call ATRIBUTOS_A_VRAM` con el que acaba
    REPINTA_LOS_EJERCITOS, que es lo ultimo que hace antes del `ret`."""

    def test_se_engancha_en_el_call_de_los_atributos(self):
        sys.path.insert(0, os.path.join(RAIZ, "tools"))
        import haz_rom
        self.assertEqual(haz_rom.DIBUJO_DE_UNIDAD, 0x6AF1)
        self.assertEqual(haz_rom.DIBUJO_DE_UNIDAD_ORIG, bytes.fromhex("cd0406"))

    def test_el_listado_dice_lo_mismo(self):
        """Y que en el listado esa direccion es de verdad ese `call`."""
        asm = os.path.join(RAIZ, "src", "war_medio.asm")
        with open(asm, encoding="utf-8", errors="replace") as f:
            lineas = [l for l in f if ";6af1" in l]
        self.assertTrue(lineas, "0x6AF1 no sale en el listado")
        self.assertIn("00604h", lineas[0],
                      "0x6AF1 ya no es el `call 0x0604`: %s" % lineas[0].strip())

    def test_la_rutina_y_la_tabla_estan_en_el_sym(self):
        sym = os.path.join(WORK, "unificada", "nombres.sym")
        if not os.path.exists(sym):
            self.skipTest("hace falta work/unificada/nombres.sym (make rom_unificada)")
        with open(sym) as f:
            simbolos = dict(
                (l.split()[0], int(l.split()[2].rstrip("Hh"), 16))
                for l in f if "EQU" in l)
        for nombre in ("MI_MARCAS", "MARCAS_N", "MARCAS_TAB", "DIBUJO_MARCA"):
            self.assertIn(nombre, simbolos)
        # La tabla son dos bytes por marca y no puede solaparse con el dibujo.
        self.assertGreaterEqual(simbolos["DIBUJO_MARCA"] - simbolos["MARCAS_TAB"],
                                0, "el dibujo cae dentro de la tabla")


class ElKitLosLleva(unittest.TestCase):
    """Todo `include` de nombres.asm tiene que viajar en el kit sin Python.

    Pagado el 2026-09-18: nombres.asm estreno `include "marca.inc"` y el kit
    seguia copiando solo cursor.inc y guante.inc, asi que `hazlo.sh` moria con
    "File 'marca.inc' not found". Lo canto `make kit`, que ya estaba; este test
    lo canta antes y sin compilar nada."""

    def test_el_kit_copia_todos_los_include(self):
        asm = os.path.join(RAIZ, "src", "cartucho", "nombres.asm")
        with open(asm, encoding="utf-8") as f:
            incluidos = re.findall(r'^\s*include\s+"([^"]+)"', f.read(), re.M)
        self.assertTrue(incluidos, "nombres.asm no incluye nada: ¿cambio el formato?")
        with open(os.path.join(RAIZ, "tools", "haz_rom.py"), encoding="utf-8") as f:
            copiados = re.search(r'for n in \(([^)]*)\):\s*\n\s*shutil\.copy\(os\.path\.join\(salidas, n\)',
                                 f.read())
        self.assertIsNotNone(copiados, "no encuentro la lista de .inc que se copian al kit")
        lista = re.findall(r'"([^"]+)"', copiados.group(1))
        for n in incluidos:
            self.assertIn(n, lista,
                          "nombres.asm incluye %s y el kit no lo copia: hazlo.sh no compilaria" % n)


class ElCotejoCaza(unittest.TestCase):
    """Volcados de pega: uno bueno, y dos con un fallo metido a mano.

    Si el cotejo no distinguiera los tres, no estaria comprobando nada."""

    def setUp(self):
        self.dibujo = marca.lee_png(PNG)
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def monta(self, celdas, dibujadas=None, apuntadas=None, lienzo_sucio=()):
        """Un volcado: `celdas` son las marcadas y `dibujadas` las que llevan
        el dibujo en la VRAM. Por defecto, las mismas."""
        if dibujadas is None:
            dibujadas = celdas
        ram = bytearray(0x1B00)
        vram = bytearray(0x4000)
        for i in range(FILAS * COLUMNAS):
            ram[ATRIBUTOS - BITMAP + i] = FONDO
        for fila, col in celdas:
            ram[ATRIBUTOS - BITMAP + fila * COLUMNAS + col] = MARCA
        for fila, col in dibujadas:
            d = fila * 0x100 + col * 8
            vram[d:d + 8] = self.dibujo
        for fila, col in lienzo_sucio:
            d = ((fila & 0x18) << 8 | (fila & 7) << 5 | col)
            for i in range(8):
                ram[d + 0x100 * i] = self.dibujo[i]
        return ram, vram, len(celdas) if apuntadas is None else apuntadas

    def escribe(self, n, celdas, **kw):
        ram, vram, apuntadas = self.monta(celdas, **kw)
        with open(os.path.join(self.tmp, "%d.ram" % n), "wb") as f:
            f.write(ram)
        with open(os.path.join(self.tmp, "%d.vram" % n), "wb") as f:
            f.write(vram)
        with open(os.path.join(self.tmp, "%d.txt" % n), "w") as f:
            f.write("atributo %d\nmarcas %d\nregs E2\n" % (MARCA, apuntadas))

    def corre(self):
        return subprocess.run([sys.executable, COTEJA, self.tmp, PNG],
                              capture_output=True, text=True)

    def test_en_verde_cuando_esta_bien(self):
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 5), (10, 20)])          # una se movio
        r = self.corre()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("EN VERDE", r.stdout)

    def test_caza_una_marca_sin_borrar(self):
        """El fallo que mas duele: la unidad se movio y el dibujo viejo sigue."""
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 5), (10, 20)], dibujadas=[(3, 4), (3, 5), (10, 20)])
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("no se borraron", r.stderr)

    def test_caza_una_celda_a_medio_escribir(self):
        """Un byte caido por ir mas rapido de lo que el VDP admite."""
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 5), (10, 20)], dibujadas=[(10, 20)])
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("SIN el dibujo clavado", r.stderr)

    def test_caza_el_dibujo_en_el_lienzo(self):
        """Si MI_MARCAS tocara el lienzo, la copia limpia del mapa se perderia."""
        self.escribe(1, [(3, 4)])
        self.escribe(2, [(3, 5)], lienzo_sucio=[(3, 4)])
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("LIENZO", r.stderr)

    def test_caza_una_cuenta_que_no_cuadra(self):
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 5), (10, 20)], apuntadas=9)
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("apunta 9 marcas", r.stderr)

    def test_se_declara_inutil_si_nadie_se_movio(self):
        """Dos repintados identicos no prueban el borrado, y tiene que decirlo."""
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 4), (10, 20)])
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("INUTIL", r.stderr)

    def test_se_declara_inutil_si_solo_aparecen_celdas(self):
        """El fallo de verdad, pagado el 2026-09-18 midiendo en el emulador.

        Se movieron ocho unidades y salio EN VERDE, pero las ocho estaban en la
        MISMA celda y en esa celda quedaban otras: la celda siguio marcada, o
        sea que nada se borro. Una celda de MAS prueba que se estampa; solo una
        celda que se QUEDA VACIA prueba que se borra."""
        self.escribe(1, [(3, 4), (10, 20)])
        self.escribe(2, [(3, 4), (10, 20), (7, 7)])     # una nueva, ninguna vaciada
        r = self.corre()
        self.assertEqual(r.returncode, 1)
        self.assertIn("INUTIL", r.stderr)
        self.assertIn("dejo de estar marcada", r.stderr)


if __name__ == "__main__":
    unittest.main()
