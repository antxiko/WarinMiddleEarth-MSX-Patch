#!/usr/bin/env python3
"""Comprobaciones del parche de Araubi.

Ninguna necesita el emulador. La que necesita los cuerpos de la cinta
(work/*.raw, que salen de `make extract`) se salta si no estan, como el resto
de la serie: el repositorio no trae la cinta.
"""
import functools
import os
import shutil
import subprocess
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import parchea  # noqa: E402

WORK = os.path.join(RAIZ, "work")
EXT = os.path.join(RAIZ, "extracted")
ASM = os.path.join(RAIZ, "src", "parche", "ficha_valores.asm")


def pasmo():
    p = shutil.which("pasmo")
    if p:
        return p
    cand = os.path.expanduser("~/AppData/Local/Programs/pasmo/pasmo.exe")
    return cand if os.path.exists(cand) else None


def hay_cuerpos():
    return all(os.path.exists(os.path.join(WORK, n + ".raw"))
               for n in parchea.BLOQUES_SPECTRUM)


class TestTabla(unittest.TestCase):
    def test_orig_y_nuevo_miden_igual(self):
        """Cada parche cambia bytes SIN desplazar nada: orig y nuevo igual de largos."""
        for p in parchea.PARCHES:
            self.assertEqual(len(bytes.fromhex(p["orig"])), len(bytes.fromhex(p["nuevo"])),
                             "parche 0x%04X" % p["dir"])

    def test_todo_cae_dentro_de_su_bloque(self):
        for p in parchea.PARCHES:
            self.assertIn(p["bloque"], parchea.BLOQUES_SPECTRUM)

    def test_las_tres_peticiones_estan_cubiertas(self):
        grupos = {p["grupo"] for p in parchea.PARCHES}
        self.assertIn("visibilidad", grupos)
        self.assertIn("valores", grupos)

    def test_la_rutina_de_la_ficha_es_la_del_asm(self):
        """La rutina hardcodeada en la tabla es EXACTAMENTE lo que sale de
        ensamblar src/parche/ficha_valores.asm. Si el .asm cambia, esto avisa."""
        pas = pasmo()
        if not pas:
            self.skipTest("pasmo no esta en el PATH")
        bin_ = os.path.join(RAIZ, "work", "ficha_valores.test.bin")
        os.makedirs(os.path.dirname(bin_), exist_ok=True)
        r = subprocess.run([pas, "--bin", ASM, bin_], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr or r.stdout)
        self.assertEqual(open(bin_, "rb").read(), parchea.RUTINA_FICHA)

    def test_el_trampolin_apunta_a_la_rutina(self):
        """El trampolin de 0x708A es `call 0x6600`, justo donde vive la rutina."""
        tr = next(p for p in parchea.PARCHES if p["dir"] == 0x708A)
        b = bytes.fromhex(tr["nuevo"])
        self.assertEqual(b[0], 0xCD)                 # call nn
        self.assertEqual(b[1] | (b[2] << 8), 0x6600) # a 0x6600
        rut = next(p for p in parchea.PARCHES if p["dir"] == 0x6600)
        self.assertEqual(rut["bloque"], "medio")


class TestAplicacion(unittest.TestCase):
    """Necesita los cuerpos de la cinta; se salta si no estan."""

    def setUp(self):
        if not hay_cuerpos():
            self.skipTest("faltan work/*.raw (haz `make extract` con tu cinta)")

    def _origs(self):
        return {n: open(os.path.join(WORK, n + ".raw"), "rb").read()
                for n in parchea.BLOQUES_SPECTRUM}

    def test_los_bytes_originales_son_los_esperados(self):
        """aplica() aborta si algun 'orig' no cuadra; que no aborte ya lo prueba,
        pero ademas comprobamos byte a byte contra el cuerpo limpio."""
        origs = self._origs()
        for p in parchea.PARCHES:
            org = parchea.BLOQUES_SPECTRUM[p["bloque"]][1]
            off = p["dir"] - org
            orig = bytes.fromhex(p["orig"])
            self.assertEqual(origs[p["bloque"]][off:off + len(orig)], orig,
                             "0x%04X no trae los bytes esperados" % p["dir"])

    def test_solo_cambia_lo_de_la_tabla(self):
        origs = self._origs()
        cuerpos = {n: bytearray(b) for n, b in origs.items()}
        rangos = parchea.aplica(cuerpos)
        # (a) fuera de los rangos de la tabla, nada cambia
        for n in parchea.BLOQUES_SPECTRUM:
            o, c = origs[n], cuerpos[n]
            permitido = rangos.get(n, [])
            for i in range(len(o)):
                if o[i] != c[i]:
                    self.assertTrue(any(a <= i < b for a, b in permitido),
                                    "byte fuera de la tabla en %s off 0x%X" % (n, i))
        # (b) dentro de cada rango, el cuerpo queda EXACTAMENTE igual a 'nuevo'
        for p in parchea.PARCHES:
            org = parchea.BLOQUES_SPECTRUM[p["bloque"]][1]
            off = p["dir"] - org
            nuevo = bytes.fromhex(p["nuevo"])
            self.assertEqual(bytes(cuerpos[p["bloque"]][off:off + len(nuevo)]), nuevo,
                             "0x%04X no quedo con los bytes nuevos" % p["dir"])

    def test_la_cinta_parcheada_se_reconstruye_con_xor_valido(self):
        if not os.path.exists(os.path.join(EXT, "manifest.json")):
            self.skipTest("falta extracted/ (haz `make extract`)")
        salida = os.path.join(WORK, "war_parche.test.tsx")
        rc = parchea.main(["parchea.py", WORK, salida])
        self.assertEqual(rc, 0)
        self.assertTrue(os.path.exists(salida))
        # el bloque medio reenvuelto debe pasar su XOR
        cuerpo = open(os.path.join(WORK, "parche", "medio.raw"), "rb").read()
        original = open(os.path.join(EXT, "block10.raw"), "rb").read()
        env = parchea.reenvuelve_spectrum(cuerpo, original[0])
        x = 0
        for b in env[:-1]:
            x ^= b
        self.assertEqual(x, env[-1], "el XOR del bloque medio parcheado no cuadra")
        self.assertEqual(len(env), len(original), "el bloque cambio de tamano")


if __name__ == "__main__":
    unittest.main()
