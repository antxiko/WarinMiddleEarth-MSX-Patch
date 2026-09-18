"""El editor de sprites (tools/editor_sprites.html) contra los PNG del repositorio.

El editor lleva los cuatro sprites DENTRO, en su tabla DE_FABRICA, para que al
abrirlo se vean sin buscar ningun fichero y para que el boton "volver al
original" tenga a que volver. Eso es una copia, y una copia se queda vieja: si
alguien repinta src/cartucho/cursor.png y no toca el HTML, el editor abriria el
dibujo de antes y guardarlo desharia el cambio en silencio. Por eso la copia no
se edita a mano -la escribe tools/editor_de_fabrica.py- y por eso esta esto.

Aqui se lee la tabla del HTML tal cual, se decodifican sus planos con la misma
regla del TMS9918 que usa tools/cursor.py -32 bytes por cuadrantes y columnas- y
se exige que sean EXACTAMENTE los que salen de los PNG.

Lo que esto NO comprueba es el codigo del editor: para eso esta
tools/prueba_editor_sprites.js, que lo ejecuta de verdad con un DOM de pega y
corre en el gate antes de cada commit. Aqui no se usa node, para que `make test`
no dependa de el ni se salte nada.
"""
import os
import re
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

import cursor                                               # noqa: E402
import guante                                               # noqa: E402

HTML = os.path.join(RAIZ, "tools", "editor_sprites.html")
NOMBRES = ["mirar", "destino", "batalla", "guante"]


def del_html():
    """{nombre: [(color, bytes), (color, bytes)]}, leido de la tabla DE_FABRICA."""
    with open(HTML, encoding="utf-8") as f:
        html = f.read()
    tabla = re.search(r"const DE_FABRICA = \{(.*?)\n\};", html, re.S)
    if not tabla:
        raise AssertionError("no encuentro la tabla DE_FABRICA en %s" % HTML)
    fuera = {}
    for nombre, cuerpo in re.findall(r"(\w+):\s*\[(.*?)\],", tabla.group(1), re.S):
        trozos = re.findall(r'(\d+)\s*,\s*"([0-9a-fA-F]*)"', cuerpo)
        fuera[nombre] = [(int(c), bytes.fromhex(p)) for c, p in trozos]
    return fuera


class EditorDeSprites(unittest.TestCase):
    def setUp(self):
        self.editor = del_html()

    def test_estan_los_cuatro_sprites(self):
        self.assertEqual(sorted(self.editor), sorted(NOMBRES))
        for nombre, planos in self.editor.items():
            self.assertEqual(len(planos), 2, "%s tiene que llevar dos planos" % nombre)
            for color, octetos in planos:
                self.assertEqual(len(octetos), cursor.BYTES_POR_PLANO,
                                 "%s: un plano son 32 bytes" % nombre)
                self.assertTrue(0 <= color <= 15, "%s: color fuera de la paleta" % nombre)

    def test_los_planos_son_los_de_los_png(self):
        """Los mismos bytes y los mismos colores que van a la ROM."""
        patrones, colores, _av = cursor.planos_del_png(
            os.path.join(RAIZ, "src/cartucho/cursor.png"))
        del_png = {}
        for n, (_modo, nombre) in enumerate(cursor.MODOS):
            del_png[nombre] = [(colores[n * 2 + p],
                                patrones[(n * 2 + p) * 32:(n * 2 + p + 1) * 32])
                               for p in range(2)]
        patrones, colores, _av = guante.planos_del_png(
            os.path.join(RAIZ, "src/cartucho/guante.png"))
        del_png["guante"] = [(colores[p], patrones[p * 32:(p + 1) * 32]) for p in range(2)]

        for nombre in NOMBRES:
            self.assertEqual(
                self.editor[nombre], del_png[nombre],
                "el editor tiene otro dibujo de '%s' que src/cartucho/: "
                "corre python3 tools/editor_de_fabrica.py" % nombre)

    def test_el_dibujo_se_ve_igual_pixel_a_pixel(self):
        """Y no solo los bytes: lo que el editor ensena de cada sprite, celda a
        celda, es lo que hay en el PNG. Los 32 bytes van por cuadrantes
        (arriba-izq 0-7, abajo-izq 8-15, arriba-der 16-23, abajo-der 24-31): si
        alguien se equivocara de orden, los bytes podrian cuadrar y el dibujo
        salir espejado."""
        cur, _ = cursor.lee_png(os.path.join(RAIZ, "src/cartucho/cursor.png"))
        gua, _ = guante.lee_png(os.path.join(RAIZ, "src/cartucho/guante.png"))
        for n, nombre in enumerate(NOMBRES):
            png = ([fila[n * 16:(n + 1) * 16] for fila in cur] if nombre != "guante" else gua)
            (ca, pa), (cb, pb) = self.editor[nombre]
            a, b = cursor.bytes_a_plano(pa), cursor.bytes_a_plano(pb)
            for y in range(16):
                for x in range(16):
                    visto = ca if a[y][x] else (cb if b[y][x] else 0)
                    self.assertEqual(visto, png[y][x],
                                     "%s: el pixel (%d, %d) del editor no es el del PNG"
                                     % (nombre, x, y))

    def test_los_dos_fondos_viajan_dentro(self):
        """Los trozos de pantalla de la previa van embebidos: el HTML tiene que
        poder abrirse solo, sin la carpeta work/ al lado."""
        with open(HTML, encoding="utf-8") as f:
            html = f.read()
        for clave in ("mapa", "vista"):
            hay = re.findall(r'%s:\s*"data:image/png;base64,([A-Za-z0-9+/=]*)"' % clave, html)
            self.assertEqual(len(hay), 1, "falta el fondo embebido de '%s'" % clave)
            self.assertGreater(len(hay[0]), 100, "el fondo de '%s' esta vacio" % clave)


if __name__ == "__main__":
    unittest.main()
