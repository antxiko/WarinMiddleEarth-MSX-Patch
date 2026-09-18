"""El tablero de la batalla, subido ENTERO y sin perder un byte.

Las figuras salian rotas jugando. Medido cotejando el bufer del juego contra la
VRAM en una batalla de verdad: 1.544 bytes de 4.096 no llegaban. La causa eran
las dos rutinas del juego que suben el tablero -BITMAP_A_VRAM (0x05BD) y
RECUADRO_A_VRAM (0x0702)-, que van a 22 ciclos por byte cuando el TMS9918 no
admite dos accesos a menos de unos 29 con la pantalla encendida.

Aqui se EJECUTA la rutina que las sustituye, con el interprete de Z80 de
corre_finales.py y su VDP de pega, y se exige que la VRAM quede exactamente
como el bufer subido. Es el test que habria cazado el fallo que se colo al
escribirla: OCHO_LINEAS usa B de contador y lo deja a cero, asi que el `djnz`
del bucle de celdas no contaba y solo subia el primer tercio. En pantalla eso
era la mitad de abajo del tablero sin dibujar.
"""
import json
import os
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

from corre_finales import CENTINELA                         # noqa: E402
import corre_nombres                                        # noqa: E402

WORK = os.path.join(RAIZ, "work", "unificada")
ROM = os.path.join(RAIZ, "war_unificada.rom")
LIENZO = 0x4000
TAM = 0x1800


def zx_a_vram(lienzo):
    """El bufer del ZX tal y como hay que subirlo a la tabla de patrones."""
    fuera = bytearray(TAM)
    for fila in range(24):
        for linea in range(8):
            for col in range(32):
                zx = ((fila // 8) << 11) | (linea << 8) | ((fila % 8) << 5) | col
                fuera[(fila // 8) * 2048 + (fila % 8) * 256 + col * 8 + linea] = lienzo[zx]
    return bytes(fuera)


class ElTablero(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.listo = (os.path.exists(ROM)
                     and os.path.exists(os.path.join(WORK, "plan.json"))
                     and os.path.exists(os.path.join(WORK, "nombres.sym")))
        if not cls.listo:
            return
        cls.plan = json.load(open(os.path.join(WORK, "plan.json")))
        with open(ROM, "rb") as f:
            cls.rom = f.read()
        with open(os.path.join(WORK, "nombres.sym")) as f:
            cls.sim = dict((l.split()[0], int(l.split()[2].rstrip("Hh"), 16))
                           for l in f if "EQU" in l)

    def setUp(self):
        if not self.listo:
            self.skipTest("hace falta make rom_unificada")

    def maquina(self):
        """La RAM con la rutina en su sitio. El bloque bajo hace falta porque
        la rutina llama a DIRECCION_VRAM, que es del parche, pero el resto del
        tablero no se toca."""
        work = os.path.join(RAIZ, "work")
        with open(os.path.join(work, "bajo.raw"), "rb") as f:
            bajo = f.read()
        with open(os.path.join(work, "alto.raw"), "rb") as f:
            alto = f.read()
        return corre_nombres.monta(self.rom, self.plan, bajo, alto)

    def corre(self, m, desde, sp=0x5BFF):
        z = corre_nombres.Z80(m, corre_nombres.Vdp(), desde, sp, {})
        z.push(CENTINELA)
        z.corre()
        return z

    def test_sube_el_tablero_entero_y_clavado(self):
        """Un bufer con un byte distinto en CADA uno de los 6.144 sitios: si la
        rutina se saltara uno, o subiera dos veces el mismo, se veria."""
        m = self.maquina()
        patron = bytes(((i * 7 + (i >> 8) * 13) & 0xFF) for i in range(TAM))
        m.ram[LIENZO:LIENZO + TAM] = patron
        z = self.corre(m, self.sim["TABLERO_A_VRAM"])
        self.assertEqual(bytes(z.vdp.vram[:TAM]), zx_a_vram(patron),
                         "lo que llega a la VRAM no es el bufer subido")

    def test_no_se_queda_a_medias(self):
        """El fallo que hubo: solo subia el primer tercio. Se mira tercio a
        tercio para que el mensaje diga CUAL falta, que es lo que costo verlo
        en pantalla (era la mitad de abajo)."""
        m = self.maquina()
        patron = bytes(((i * 5 + 1) & 0xFF) for i in range(TAM))
        m.ram[LIENZO:LIENZO + TAM] = patron
        z = self.corre(m, self.sim["TABLERO_A_VRAM"])
        esperado = zx_a_vram(patron)
        for t in range(3):
            a, b = t * 2048, (t + 1) * 2048
            self.assertEqual(bytes(z.vdp.vram[a:b]), esperado[a:b],
                             "el tercio %d (filas %d a %d) no se subio entero"
                             % (t, t * 8, t * 8 + 7))

    def test_no_pisa_nada_mas_de_la_vram(self):
        """Solo la tabla de patrones: ni los nombres (0x1800) ni el color."""
        m = self.maquina()
        m.ram[LIENZO:LIENZO + TAM] = bytes(TAM)
        z = self.corre(m, self.sim["TABLERO_A_VRAM"])
        self.assertEqual(bytes(z.vdp.vram[TAM:0x4000]), bytes(0x4000 - TAM),
                         "la rutina escribe fuera de la tabla de patrones")


class ElRitmo(unittest.TestCase):
    """Y que nadie vuelva a subir el tablero por las rutinas rapidas."""

    def test_el_parche_no_llama_a_las_de_22_ciclos(self):
        asm = os.path.join(RAIZ, "src", "cartucho", "nombres.asm")
        with open(asm, encoding="utf-8") as f:
            texto = f.read()
        for rutina, direccion in (("BITMAP_A_VRAM", "005BDh"),
                                  ("RECUADRO_A_VRAM", "00702h")):
            cuerpo = texto[texto.index("MI_SUBE_TABLERO:"):]
            self.assertNotIn("call %s" % rutina, cuerpo,
                             "%s (0x%s) va a 22 ciclos por byte y el VDP pierde "
                             "bytes: no se puede usar para subir el tablero"
                             % (rutina, direccion))
            self.assertNotIn("jp %s" % rutina, cuerpo,
                             "%s (0x%s) va a 22 ciclos por byte" % (rutina, direccion))

    def test_el_bucle_guarda_el_contador(self):
        """OCHO_LINEAS usa B y lo deja a cero: quien la llame en un bucle con
        `djnz` tiene que guardarlo. Sin esto solo se subia un tercio."""
        asm = os.path.join(RAIZ, "src", "cartucho", "nombres.asm")
        with open(asm, encoding="utf-8") as f:
            texto = f.read()
        i = texto.index("UN_TERCIO:")
        cuerpo = texto[i:texto.index("djnz UT_CELDA", i)]
        self.assertIn("push bc", cuerpo, "el bucle del tercio no guarda B")
        self.assertIn("pop bc", cuerpo, "el bucle del tercio no recupera B")


if __name__ == "__main__":
    unittest.main()
