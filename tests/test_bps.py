"""El parche BPS (cinta -> ROM del cartucho): el formato, y que da la ROM.

Sin la cinta y la ROM, solo se prueba el formato con datos inventados: copias
del origen en su sitio y fuera de el, rachas copiadas de la propia salida y
literales, y que un origen equivocado se rechaza.
"""
import hashlib
import os
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import bps  # noqa: E402

# La ROM que sale de aplicar war_cartucho.bps a la cinta: builds/WIME09.ROM
SHA256_ROM = "0286382242f442be4dd32ceed7bdae1df8fc29a91af8ba5ae7f52e88f31e2fed"


def leer(f):
    with open(os.path.join(RAIZ, f), "rb") as fh:
        return fh.read()


def hace_falta(test, *ficheros):
    for f in ficheros:
        if not os.path.exists(os.path.join(RAIZ, f)):
            test.skipTest(f"sin {f}")


class TestFormato(unittest.TestCase):
    def test_ida_y_vuelta(self):
        origen = bytes(range(256)) * 8 + b"WAR IN MIDDLE EARTH" * 20
        destino = (origen[100:900] + b"\xff" * 3000 + b"nuevo" + origen[:100]
                   + origen[1500:2000] + bytes(range(7, 200, 3)))
        p = bps.hace(origen, destino)
        self.assertEqual(p[:4], b"BPS1")
        self.assertEqual(bps.aplica(origen, p), destino)
        # la racha de 0xFF va como copia de la salida, no como 3.000 literales
        self.assertLess(len(p), 600)

    def test_rechaza_otro_origen(self):
        origen = bytes(range(256)) * 4
        p = bps.hace(origen, origen[::-1])
        with self.assertRaises(ValueError):
            bps.aplica(origen[:-1] + b"\x00", p)


class TestElParchePublicado(unittest.TestCase):
    def test_da_la_rom_del_cartucho(self):
        hace_falta(self, "war.tsx", "war_cartucho.bps")
        cinta = leer("war.tsx")
        p = leer("war_cartucho.bps")
        rom = bps.aplica(cinta, p)
        self.assertEqual(len(rom), 65536)
        self.assertEqual(hashlib.sha256(rom).hexdigest(), SHA256_ROM)

    def test_no_lleva_la_cinta_dentro(self):
        """Lo que viaja en el parche es lo nuevo: ni un tramo de 64 bytes
        seguidos de la cinta va como literal."""
        hace_falta(self, "war.tsx", "war_cartucho.bps")
        cinta = leer("war.tsx")
        p = leer("war_cartucho.bps")
        trozos = {cinta[i:i + 64] for i in range(0, len(cinta) - 64)}
        dentro = sum(1 for i in range(len(p) - 64) if p[i:i + 64] in trozos)
        self.assertEqual(dentro, 0)


if __name__ == "__main__":
    unittest.main()
