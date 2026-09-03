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
import parchea
import ips  # noqa: E402

WORK = os.path.join(RAIZ, "work")
EXT = os.path.join(RAIZ, "extracted")
ASM = os.path.join(RAIZ, "src", "parche", "ficha_valores.asm")
ASM_ICONO = os.path.join(RAIZ, "src", "parche", "icono_enemigo.asm")


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

    def test_la_rutina_del_icono_es_la_del_asm(self):
        """Lo mismo para la segunda tanda: el Ojo de Sauron y el plazo del
        Anillo salen de ensamblar src/parche/icono_enemigo.asm."""
        pas = pasmo()
        if not pas:
            self.skipTest("pasmo no esta en el PATH")
        bin_ = os.path.join(RAIZ, "work", "icono_enemigo.test.bin")
        os.makedirs(os.path.dirname(bin_), exist_ok=True)
        r = subprocess.run([pas, "--bin", ASM_ICONO, bin_], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr or r.stdout)
        self.assertEqual(open(bin_, "rb").read(), parchea.RUTINA_ICONO)

    def test_los_ganchos_del_icono_apuntan_donde_toca(self):
        """Los tres ganchos de la segunda tanda entran en la rutina nueva:
        la siembra por `call`, el dibujo por `jp` y el anillo por `call`."""
        rut = next(p for p in parchea.PARCHES if p["dir"] == 0x664C)
        base = 0x664C
        self.assertEqual(len(bytes.fromhex(rut["nuevo"])), len(parchea.RUTINA_ICONO))
        for direccion, opcode, destino in ((0x7FC9, 0xCD, base),          # SIEMBRA_CON_BANDO
                                           (0x770A, 0xC3, base + 12),     # DIBUJO_SEGUN_BANDO
                                           (0x6F77, 0xCD, base + 33)):    # ANILLO_CON_PLAZO
            g = bytes.fromhex(next(p for p in parchea.PARCHES
                                   if p["dir"] == direccion)["nuevo"])
            self.assertEqual(g[0], opcode, hex(direccion))
            self.assertEqual(g[1] | (g[2] << 8), destino, hex(direccion))

    def test_el_ojo_no_usa_un_hueco_de_la_tabla_de_cuadros(self):
        """Los huecos a cero de la tabla de 0x77B5 NO estan libres: los indices
        0x00-0x0F los elige PINTA_LO_DE_ENCIMA con un `and 00fh` sobre el
        terreno. El parche no puede tocar esa tabla."""
        self.assertFalse([p for p in parchea.PARCHES if 0x77B5 <= p["dir"] < 0x7845],
                         "el parche escribe en la tabla de cuadros de 0x77B5")

    def test_los_tiles_del_ojo_caben_donde_no_habia_nada(self):
        """Los cuatro tiles nuevos son de nueve bytes y van a los indices
        111-114 de la tabla de 0x9E00, que venian a cero."""
        t = next(p for p in parchea.PARCHES if p["dir"] == 0xA1E7)
        self.assertEqual(t["bloque"], "alto")
        self.assertEqual(bytes.fromhex(t["orig"]), bytes(36))
        b = bytes.fromhex(t["nuevo"])
        self.assertEqual(len(b), 36)
        self.assertEqual(0xA1E7, 0x9E00 + 111 * 9)
        for i in range(4):
            self.assertEqual(b[i * 9 + 8], 0x38,
                             "el atributo del tile %d no es el del aliado" % (111 + i))

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


class TestIPS(unittest.TestCase):
    """El parche que se reparte: solo los bytes que cambian."""

    def test_ida_y_vuelta(self):
        """Un IPS sacado de dos ficheros, aplicado al primero, da el segundo."""
        a = bytes(range(256)) * 8
        b = bytearray(a)
        for pos, val in ((3, 0xFF), (4, 0xFE), (100, 0x01), (900, 0x02), (901, 0x03)):
            b[pos] = val
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            fa = os.path.join(d, "a.bin")
            fb = os.path.join(d, "b.bin")
            fp = os.path.join(d, "p.ips")
            open(fa, "wb").write(a)
            open(fb, "wb").write(bytes(b))
            parche, total = ips.crea(fa, fb)
            open(fp, "wb").write(parche)
            self.assertEqual(parche[:5], b"PATCH")
            self.assertEqual(parche[-3:], b"EOF")
            self.assertEqual(ips.aplica(fa, fp), bytes(b))
            self.assertLessEqual(total, 20, "no deberia arrastrar medio fichero")

    def test_el_ips_del_repositorio_reconstruye_la_cinta(self):
        """Si estan las dos cintas, el war_parche.ips que se reparte tiene que
        dar la parcheada byte a byte."""
        orig = os.path.join(RAIZ, "war.tsx")
        parcheada = os.path.join(RAIZ, "war_parche.tsx")
        parche = os.path.join(RAIZ, "war_parche.ips")
        if not (os.path.exists(orig) and os.path.exists(parcheada)):
            self.skipTest("faltan las cintas (cada cual pone la suya)")
        self.assertTrue(os.path.exists(parche), "falta war_parche.ips; haz `make ips`")
        self.assertEqual(ips.aplica(orig, parche), open(parcheada, "rb").read())
