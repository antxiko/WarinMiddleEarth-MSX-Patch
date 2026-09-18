"""El editor de marcas (tools/editor_marcas.html) contra los datos del juego.

El editor deja elegir los dos colores de la celda de una unidad, y eso solo
vale si las tablas con las que decide son LAS DEL JUEGO: el atributo del ZX no
llega a la pantalla, lo traduce antes ATRIBUTO_A_COLOR (0x049F) con dos tablas
de ocho colores del MSX. Si el editor llevara otras, ofreceria colores que la
maquina no puede dar -o tacharia los que si-.

Y el anillo que trae de fabrica no es un dibujo inventado: es el caracter 0x5F
de la fuente del juego, el que el parche pinta en la ficha del Portador del
Anillo. Si alguien repinta la fuente, esto lo dice.
"""
import os
import re
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

import lienzos                                              # noqa: E402

HTML = os.path.join(RAIZ, "tools", "editor_marcas.html")
FUENTE = 0xC800
ORG_ALTO = 0x9E00
ANILLO = 0x5F           # el caracter que MARCA_AL_PORTADOR (0x6F77) escribe en la ficha


def js(nombre):
    """Una lista de numeros declarada en el HTML: const <nombre> = [...]."""
    with open(HTML, encoding="utf-8") as f:
        html = f.read()
    m = re.search(r"const %s = \[([0-9,\s]*)\];" % nombre, html)
    if not m:
        raise AssertionError("no encuentro %s en %s" % (nombre, HTML))
    return [int(v) for v in m.group(1).replace("\n", "").split(",") if v.strip()]


def de_fabrica():
    with open(HTML, encoding="utf-8") as f:
        html = f.read()
    tabla = re.search(r"const DE_FABRICA = \{(.*?)\n\};", html, re.S).group(1)
    return {n: (bytes.fromhex(d), int(t), int(p))
            for n, d, t, p in re.findall(r'(\w+):\s*\["([0-9a-fA-F]+)",\s*(\d+),\s*(\d+)\]', tabla)}


class EditorDeMarcas(unittest.TestCase):
    def test_las_tablas_de_color_son_las_del_juego(self):
        self.assertEqual(js("TABLA_SIN"), list(lienzos.TABLA_SIN))
        self.assertEqual(js("TABLA_CON"), list(lienzos.TABLA_CON))

    def test_el_anillo_es_el_caracter_del_juego(self):
        """Los ocho bytes que trae, contra la fuente de la cinta PARCHEADA."""
        alto = os.path.join(RAIZ, "work", "cuerpos_parche", "alto.raw")
        if not os.path.exists(alto):
            self.skipTest("falta work/cuerpos_parche (haz `make rom_parche`)")
        with open(alto, "rb") as f:
            datos = f.read()
        o = FUENTE - ORG_ALTO + ANILLO * 8
        self.assertEqual(de_fabrica()["anillo"][0], datos[o:o + 8],
                         "el anillo del editor no es el caracter 0x%02X de la fuente" % ANILLO)

    def test_las_marcas_arrancan_con_los_colores_de_ahora(self):
        """Negro sobre blanco, que es el atributo 0x78 que el juego pone hoy en
        la celda de una unidad (0x6AE0 con el parche del panel)."""
        for nombre, (dibujo, tinta, papel) in de_fabrica().items():
            self.assertEqual(len(dibujo), 8, "%s: una marca son ocho bytes" % nombre)
            self.assertEqual((tinta, papel), (1, 15), "%s: negro sobre blanco" % nombre)
            self.assertEqual(self.atributo(tinta, papel), 0x78)

    @staticmethod
    def atributo(tinta, papel):
        # con brillo primero: negro sobre blanco lo dan 0x38 y 0x78, y el que el
        # juego usa es el segundo
        for brillo, t in ((1, lienzos.TABLA_CON), (0, lienzos.TABLA_SIN)):
            if tinta in t and papel in t:
                return (brillo << 6) | (t.index(papel) << 3) | t.index(tinta)
        return None

    def test_no_se_ofrece_ningun_color_que_el_juego_no_pueda_dar(self):
        """Doce de los quince del MSX: el verde medio, el rojo medio y el gris
        no salen de ninguna de las dos tablas."""
        alcanzables = set(lienzos.TABLA_SIN) | set(lienzos.TABLA_CON)
        self.assertEqual(len(alcanzables), 12)
        for imposible in (2, 8, 14):        # verde medio, rojo medio, gris
            self.assertNotIn(imposible, alcanzables)
        # y las parejas: las que comparten tabla, y solo esas
        parejas = {(t, p) for tabla in (lienzos.TABLA_SIN, lienzos.TABLA_CON)
                   for t in tabla for p in tabla if t != p}
        self.assertEqual(len(parejas), 100)
        self.assertIsNotNone(self.atributo(1, 15), "negro sobre blanco tiene que poder")
        self.assertIsNone(self.atributo(3, 4), "verde claro sobre azul oscuro no cabe: distinto brillo")


if __name__ == "__main__":
    unittest.main()
