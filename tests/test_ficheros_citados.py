"""Que el fichero que nombra una pagina exista de verdad.

El aviso legal de SIETE repositorios de la serie decia que el desensamblado
esta en `src/tennis.asm`, que es el listado de Konami's Tennis: el fichero vino
copiado de aquel repositorio y el nombre se quedo dentro. Y en otros cuatro, la
frase que explica que las imagenes se dibujan desde el cartucho nombraba un
`tools/graficos.py` que aqui no existe.

El test de "no se nombra otro juego de la serie" no podia cazarlo: en Ping Pong
la palabra tennis es legitima -es tenis de mesa-, y ademas ese test solo mira
docs/, no los ficheros de la raiz, que es justo donde vive el aviso legal.

Asi que esta comprobacion no mira el NOMBRE, mira el FICHERO: toda ruta de este
repositorio que se cite en un .md de la raiz o en cualquier pagina de docs/
tiene que existir. Caza el copia y pega de un nombre de fichero venga de donde
venga, y tambien el fichero que se borro o se renombro y dejo la frase atras.

Este fichero es el mismo en todos los repositorios de la serie: si se arregla
aqui, hay que llevarlo a los demas.
"""

import os
import re
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(RAIZ, "docs")

# Rutas que se citan a proposito aunque no existan en este repositorio, cada
# una con su motivo. Lo normal es que esto este vacio: si hay que anadir algo,
# que se lea por que.
EXCEPCIONES = {}

# Una ruta citada va entre comillas invertidas en el .md, pero en el .html que
# sale de ahi va dentro de un <code>, o sea entre '>' y '<'. Si el delimitador
# de cierre no se acepta, el test pasa sobre el .md arreglado y se calla sobre
# el .html que sigue publicando el nombre viejo. Paso justo eso en Baseball.
CITA = re.compile(r"""[`"'>]((?:src|tools|tests)/[A-Za-z0-9_.-]+)[`"'<]""")


def paginas():
    """Los .md de la raiz y todo lo publicable de docs/, por su nombre."""
    encontradas = {}
    for f in sorted(os.listdir(RAIZ)):
        if f.endswith(".md"):
            encontradas[f] = os.path.join(RAIZ, f)
    for base, _, ficheros in os.walk(DOCS):
        for f in sorted(ficheros):
            if f.endswith((".md", ".html")):
                ruta = os.path.join(base, f)
                encontradas[os.path.relpath(ruta, RAIZ)] = ruta
    return encontradas


class TestFicherosCitados(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.textos = {}
        for nombre, ruta in paginas().items():
            with open(ruta, encoding="utf-8", errors="replace") as f:
                cls.textos[nombre] = f.read()

    def test_toda_ruta_citada_existe(self):
        malas = []
        for pagina, texto in sorted(self.textos.items()):
            for cita in sorted(set(CITA.findall(texto))):
                if cita in EXCEPCIONES:
                    continue
                if not os.path.exists(os.path.join(RAIZ, cita)):
                    malas.append("%s nombra %s, que no existe" % (pagina, cita))
        self.assertEqual(malas, [], "; ".join(malas))

    def test_las_excepciones_siguen_haciendo_falta(self):
        """Una excepcion que ya no hace falta es una mentira dormida."""
        sobran = [c for c in EXCEPCIONES
                  if os.path.exists(os.path.join(RAIZ, c))]
        self.assertEqual(sobran, [], "ya existen, quitalas de EXCEPCIONES: %s"
                                     % ", ".join(sobran))


if __name__ == "__main__":
    unittest.main()
