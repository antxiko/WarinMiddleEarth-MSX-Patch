"""El fondo de la batalla, segun el terreno donde se pelea.

Todas las batallas se peleaban sobre el mismo verde. Ahora el color sale del
terreno, leyendo 0x8DEA -que el juego ya guarda al montar la batalla- en una
tabla de dieciseis.

Lo que se comprueba aqui es que la tabla que viaja EN LA ROM da los colores que
se acordaron, traducidos con las tablas del propio juego; que la tinta se queda
en negro, que es lo que hace que las figuras se vean; y que el parche se
engancha en el byte que de verdad elige el color, no en otro parecido.
"""
import json
import os
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

import lienzos                                              # noqa: E402

WORK = os.path.join(RAIZ, "work", "unificada")
ORG_MEDIO = 0x5E00

# Lo que el usuario eligio, mirando los candidatos sobre una batalla de verdad.
# El nombre del color es el del MSX; el atributo, el del ZX que lo produce.
ACORDADO = {
    0:  ("verde oscuro", 0x20),     # llano, y el resto de su grupo
    1:  ("azul claro", 0x48),       # agua: intransitable, no hay batalla
    2:  ("azul claro", 0x48),
    3:  ("azul claro", 0x48),       # rio
    4:  ("verde oscuro", 0x20),
    5:  ("verde oscuro", 0x20),
    6:  ("amarillo oscuro", 0x30),  # camino
    7:  ("verde oscuro", 0x20),
    8:  ("verde oscuro", 0x20),
    9:  ("verde oscuro", 0x20),
    10: ("verde oscuro", 0x20),
    11: ("verde oscuro", 0x20),
    12: ("verde oscuro", 0x20),
    13: ("verde claro", 0x60),      # bosque
    14: ("rojo oscuro", 0x10),      # montana: lo mas marron que da la maquina
    15: ("verde oscuro", 0x20),
}
LLANO = [0, 4, 5, 7, 8, 9, 10, 11, 12, 15]


def simbolos():
    sym = os.path.join(WORK, "nombres.sym")
    if not os.path.exists(sym):
        return None
    with open(sym) as f:
        return dict((l.split()[0], int(l.split()[2].rstrip("Hh"), 16))
                    for l in f if "EQU" in l)


def color_msx(atributo):
    """El atributo ZX -> byte de color del MSX, por las dos tablas del juego
    (0x04CE sin brillo y 0x04D6 con el). Tinta arriba, papel abajo."""
    t = lienzos.TABLA_CON if atributo & 0x40 else lienzos.TABLA_SIN
    return t[(atributo >> 3) & 7], t[atributo & 7]      # papel, tinta


class LaTablaDeLaRom(unittest.TestCase):
    """La tabla tal como viaja en el binario, no como esta escrita en el .asm."""

    @classmethod
    def setUpClass(cls):
        cls.sim = simbolos()
        binario = os.path.join(WORK, "nombres.bin")
        if cls.sim is None or not os.path.exists(binario):
            cls.tabla = None
            return
        plan = json.load(open(os.path.join(WORK, "plan.json")))
        org = plan["vista"]["ram"]
        with open(binario, "rb") as f:
            datos = f.read()
        d = cls.sim["FONDO_POR_TERRENO"] - org
        cls.tabla = datos[d:d + 16]

    def setUp(self):
        if self.tabla is None:
            self.skipTest("hace falta make rom_unificada")

    def test_son_dieciseis(self):
        self.assertEqual(len(self.tabla), 16)

    def test_cada_terreno_lleva_el_color_acordado(self):
        for t, (nombre, atributo) in ACORDADO.items():
            self.assertEqual(self.tabla[t], atributo,
                             "el terreno %d deberia ser %s (0x%02X) y lleva 0x%02X"
                             % (t, nombre, atributo, self.tabla[t]))

    def test_el_color_que_sale_es_el_que_se_penso(self):
        """Y que traducido por las tablas del juego da ESE color del MSX: un
        atributo correcto en el papel equivocado no serviria de nada."""
        for t, (nombre, atributo) in ACORDADO.items():
            papel, _tinta = color_msx(self.tabla[t])
            self.assertEqual(lienzos.NOMBRE_MSX[papel], nombre,
                             "el terreno %d sale %s y se queria %s"
                             % (t, lienzos.NOMBRE_MSX[papel], nombre))

    def test_la_tinta_se_queda_en_negro(self):
        """Las figuras se dibujan con la TINTA de la celda. Si algun fondo se
        llevara la tinta por delante, las tropas se volverian invisibles."""
        for t in range(16):
            _papel, tinta = color_msx(self.tabla[t])
            self.assertEqual(lienzos.NOMBRE_MSX[tinta], "negro",
                             "el terreno %d deja la tinta en %s: las figuras no se verian"
                             % (t, lienzos.NOMBRE_MSX[tinta]))

    def test_el_grupo_del_llano_va_junto(self):
        """Los terrenos que se comportan igual en el juego llevan el mismo
        color: si alguno se descolgara, el color dejaria de significar algo."""
        colores = set(self.tabla[t] for t in LLANO)
        self.assertEqual(len(colores), 1,
                         "el grupo del llano lleva mas de un color: %s"
                         % sorted("0x%02X" % c for c in colores))

    def test_los_cinco_se_distinguen(self):
        """Y el que muerde de verdad: llano, rio, camino, bosque y montana
        tienen que salir de CINCO colores distintos. Con la tabla puesta toda
        a verde, todo lo de arriba pasaria menos esto."""
        cinco = [self.tabla[t] for t in (0, 3, 6, 13, 14)]
        self.assertEqual(len(set(cinco)), 5,
                         "los cinco terrenos con color propio no se distinguen: %s"
                         % ["0x%02X" % c for c in cinco])


class ElParche(unittest.TestCase):
    def test_se_engancha_donde_se_elige_el_color(self):
        import haz_rom
        self.assertEqual(haz_rom.FONDO_DE_LA_BATALLA, 0x93AE)
        self.assertEqual(haz_rom.FONDO_DE_LA_BATALLA_ORIG,
                         bytes.fromhex("3e20c3127f"))

    def test_el_listado_dice_que_ahi_estaba_el_color(self):
        """0x93AE tiene que ser el `ld a,020h` y 0x93B0 el `jp BORRA_PANTALLA`:
        si el listado cambia, el parche estaria pisando otra cosa."""
        asm = os.path.join(RAIZ, "src", "war_medio.asm")
        with open(asm, encoding="utf-8", errors="replace") as f:
            lineas = f.readlines()
        de = dict()
        for l in lineas:
            for marca in (";93ae", ";93b0"):
                if marca in l:
                    de[marca] = l.strip()
        self.assertIn("020h", de.get(";93ae", ""), de.get(";93ae", "falta 0x93AE"))
        self.assertIn("BORRA_PANTALLA", de.get(";93b0", ""),
                      de.get(";93b0", "falta 0x93B0"))

    def test_el_terreno_se_lee_de_donde_lo_deja_el_juego(self):
        """0x8DEA lo escribe 0x902F al montar la batalla, TRES instrucciones
        antes de la llamada en la que se elige el color. Si la rutina mirara
        otro sitio, el color no tendria nada que ver con el terreno."""
        asm = os.path.join(RAIZ, "src", "cartucho", "nombres.asm")
        with open(asm, encoding="utf-8") as f:
            texto = f.read()
        self.assertIn("TERRENO_DE_LA_BATALLA:  equ 08deah", texto)
        i = texto.index("MI_FONDO:")
        self.assertIn("ld a,(TERRENO_DE_LA_BATALLA)", texto[i:i + 400])


if __name__ == "__main__":
    unittest.main()
