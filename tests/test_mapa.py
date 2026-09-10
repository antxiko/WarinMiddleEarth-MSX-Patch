#!/usr/bin/env python3
"""Comprobaciones del dibujo del mapa entero (tools/render_mapa_completo.py).

Ninguna necesita el emulador. Las que necesitan los cuerpos de la cinta
(work/*.raw, que salen de `make extract`) se saltan si no estan, como el resto
de la serie: el repositorio no trae la cinta.

Lo que estas pruebas SI demuestran: que el descompresor y el motor de dibujo
siguen dando lo mismo. Lo que NO demuestran es que sea correcto -eso se midio
contra el emulador, y esta contado en docs/THE-PICTURES.md: 19 bytes de
diferencia de 13.260, todos el bit 7 de las unidades, y 52 celdas de 768 en una
ventana, todas del panel que el juego pinta encima-.
"""
import hashlib
import os
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import render_mapa_completo as R                                # noqa: E402

WORK = os.path.join(RAIZ, "work")

# Del mapa de ESTA cinta, medidos una vez y clavados aqui para que un cambio en
# el descompresor o en el motor de dibujo no pase en silencio.
SHA_MAPA = "622ccfc25a6c53d8688e19c28b5486d29c38b92d0d5e58e58837f6d420f2814f"
SHA_VENTANA = "3748176392b42f0f46ca177ac2d5d6b589e3894a200ba69167ce28282fd8664a"
TERRENOS = {0: 5686, 1: 324, 2: 3837, 3: 447, 4: 13, 6: 344, 7: 1, 8: 9,
            9: 4, 10: 522, 11: 14, 12: 14, 13: 527, 14: 1035, 15: 23}


def cuerpo(nombre):
    ruta = os.path.join(WORK, nombre + ".raw")
    if not os.path.exists(ruta):
        raise unittest.SkipTest("no hay work/%s.raw; ejecuta `make extract`" % nombre)
    with open(ruta, "rb") as f:
        return f.read()


class ElDescompresor(unittest.TestCase):

    def test_una_cuenta_a_cero_son_256(self):
        """El bucle de 0x9385 es un `djnz`, asi que B = 0 da 256 vueltas. Es la
        unica regla del formato que no se ve mirando los bytes."""
        parejas = bytes([0, 0x42])                   # cuenta 0 -> 256 copias
        parejas += bytes([255, 0x00]) * 52           # y relleno hasta el final
        falso = bytearray(0x2E00) + bytearray(parejas)
        falso += bytearray(0x2E00 + R.COMPRIMIDO - len(falso))
        salida = R.descomprime_el_mapa(bytes(falso))
        self.assertEqual(salida[:256], bytes([0x42]) * 256,
                         "una cuenta a cero tiene que dar 256 bytes")
        self.assertEqual(salida[256], 0x00)

    def test_el_mapa_de_la_cinta_mide_lo_que_dice_el_juego(self):
        m = R.descomprime_el_mapa(cuerpo("alto"))
        self.assertEqual(len(m), R.COLUMNAS * R.FILAS)
        self.assertEqual(hashlib.sha256(m).hexdigest(), SHA_MAPA,
                         "el mapa descomprimido ha cambiado")

    def test_los_terrenos_del_mapa_son_los_de_siempre(self):
        """El reparto de clases de terreno de las 12.800 casillas jugables. Si
        el descompresor se desincroniza media pareja, esto se mueve entero."""
        m = R.descomprime_el_mapa(cuerpo("alto"))
        cuenta = {}
        for x in range(R.ANCHO):
            for y in range(R.ALTO):
                n = m[(x + 1) * R.FILAS + (y + 1)] & 0x0F
                cuenta[n] = cuenta.get(n, 0) + 1
        self.assertEqual(cuenta, TERRENOS)
        self.assertEqual(sum(cuenta.values()), R.ANCHO * R.ALTO)


class ElMotorDeDibujo(unittest.TestCase):

    def test_la_ventana_sale_igual_que_siempre(self):
        """Las 16 x 13 casillas que el juego ensena con el cursor en (96,63),
        dibujadas con los graficos DE LA CINTA -no con los lienzos, para que
        repintar no toque esta prueba-."""
        salida = os.path.join(WORK, "test_ventana.png")
        alto, medio = cuerpo("alto"), cuerpo("medio")
        m = R.Mapa(R.descomprime_el_mapa(alto), medio, alto)
        x0, y0 = 96 - 7, 63 - 5
        celdas = [(x, y) for y in range(y0, y0 + 13)
                  for x in range(x0, x0 + 16)]
        m.dibuja(celdas)
        w, h, filas = m.a_pixeles(x0, y0, 16, 12)
        self.assertEqual((w, h), (256, 192), "la ventana es de 32 x 24 caracteres")
        R.escribe_png(salida, w, h, filas, R.MSX)
        with open(salida, "rb") as f:
            self.assertEqual(hashlib.sha256(f.read()).hexdigest(), SHA_VENTANA,
                             "el motor de dibujo ha cambiado de resultado")

    def test_el_mapa_entero_es_de_2048_por_1600(self):
        alto, medio = cuerpo("alto"), cuerpo("medio")
        m = R.Mapa(R.descomprime_el_mapa(alto), medio, alto)
        m.dibuja([(0, 0)])
        w, h, _ = m.a_pixeles(0, 0, R.ANCHO, R.ALTO)
        self.assertEqual((w, h), (2048, 1600))

    def test_sin_unidades_no_se_pinta_ninguna(self):
        """Con el mapa de la cinta no hay ni un bit 7 puesto: el juego siembra
        las unidades al empezar la partida, no vienen en el dato."""
        m = R.descomprime_el_mapa(cuerpo("alto"))
        con_bit7 = [i for i, b in enumerate(m) if b & 0x80]
        self.assertEqual(con_bit7, [], "el mapa de la cinta trae unidades sembradas")


if __name__ == "__main__":
    unittest.main()
