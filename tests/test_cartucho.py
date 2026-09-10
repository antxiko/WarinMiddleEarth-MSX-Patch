"""Lo que tiene que cumplir el CARTUCHO (src/cartucho/), sin arrancar ningun emulador.

La ROM (war.rom) y su plan (work/plan.json) salen de `make rom`. Si no estan,
los tests que los necesitan se saltan diciendolo: no hay cinta que montar.

La prueba fuerte es `test_el_plan_deja_la_ram_como_la_cinta`: un interprete
del plan escrito aparte, en Python, que lleva la cuenta de la RAM, la VRAM y
de que hay en la pagina 1 en cada paso. Si el plan intentara escribir en
0x4000-0x7FFF con el cartucho puesto, o leer la ROM con el cartucho quitado,
aqui se ve sin necesidad de openMSX. Y al final la RAM y la VRAM tienen que
ser las de la cinta.

Los cotejos contra los volcados del emulador (`make verifica`) tambien se
comprueban si existen (`make verifica_rom` y `make verifica_rom_parche`).
"""
import json
import os
import re
import subprocess
import sys
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

ROM = os.path.join(RAIZ, "war.rom")
WORK = os.path.join(RAIZ, "work")
PLAN = os.path.join(WORK, "plan.json")


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def hace_falta(*rutas):
    for r in rutas:
        if not os.path.exists(r):
            raise unittest.SkipTest("falta %s: hace falta `make rom` o `make verifica_rom` con tu cinta" % os.path.relpath(r, RAIZ))


class TestLaRom(unittest.TestCase):

    def setUp(self):
        hace_falta(ROM, PLAN)
        self.rom = lee(ROM)
        with open(PLAN) as f:
            self.plan = json.load(f)

    def test_cabecera_ab_y_tamano(self):
        self.assertEqual(len(self.rom), 0x10000)
        self.assertEqual(self.rom[:2], b"AB")
        init = self.rom[2] | (self.rom[3] << 8)
        self.assertTrue(0x4010 <= init < 0x4800, "INIT fuera del banco 0: 0x%04X" % init)
        self.assertEqual(self.rom[4:16], bytes(12), "STATEMENT, DEVICE y TEXT tienen que ir a cero")

    def test_arranque_y_stub_caben_y_el_resto_es_relleno(self):
        cabeza = self.plan["arranque"] + self.plan["stub"]
        self.assertLessEqual(cabeza, 0x800)
        self.assertEqual(set(self.rom[cabeza:0x800]), {0xFF}, "entre el stub y los datos solo puede haber 0xFF")
        with open(os.path.join(WORK, "cargador_ram.bin"), "rb") as f:
            stub = f.read()
        self.assertEqual(self.rom[self.plan["arranque"]:cabeza], stub, "el stub de la ROM no es el ensamblado")

    def test_los_cuerpos_de_la_cinta_estan_en_la_rom(self):
        pantalla = lee(os.path.join(WORK, "pantalla.raw"))
        esperado = dict(patrones=pantalla[100:100 + 6144], colores=pantalla[100 + 6144:100 + 12288],
                        bajo=lee(os.path.join(WORK, "bajo.raw")), medio=lee(os.path.join(WORK, "medio.raw")),
                        alto=lee(os.path.join(WORK, "alto.raw")))
        for nombre, d in self.plan["datos"].items():
            self.assertEqual(self.rom[d["rom"]:d["rom"] + d["bytes"]], esperado[nombre], nombre)
        fin = max(d["rom"] + d["bytes"] for d in self.plan["datos"].values())
        self.assertEqual(fin, self.plan["fin_datos"])
        self.assertEqual(set(self.rom[fin:]), {0xFF})

    def test_las_variables_del_stub_estan_donde_dice_direcciones_inc(self):
        simbolos = {}
        for fichero in ("cargador_ram.sym", "cargador_rom.sym"):
            with open(os.path.join(WORK, fichero)) as f:
                for linea in f:
                    m = re.match(r"(\w+)\s+EQU\s+0?([0-9A-F]+)H", linea.strip())
                    if m:
                        simbolos[m.group(1)] = int(m.group(2), 16)
        self.assertEqual(simbolos["STUB"], self.plan["stub_ram"])
        self.assertEqual(simbolos["ID_CART"], simbolos["STUB"] + 3)
        self.assertEqual(simbolos["BIOS_OK"], simbolos["STUB"] + 7)
        # el arranque pega el stub justo detras de si mismo
        self.assertEqual(simbolos["STUB_ROM"], 0x4000 + self.plan["arranque"])
        # y lo que copia es el stub entero, con el plan dentro
        self.assertEqual(simbolos["FIN_STUB"] - simbolos["STUB"], self.plan["stub"])

    def test_el_plan_deja_la_ram_como_la_cinta(self):
        """Interprete del plan aparte del stub: RAM, VRAM y quien esta en la pagina 1."""
        ram = bytearray(b"\x00" * 0x10000)
        vram = bytearray(b"\x00" * 0x4000)
        vdp = [None] * 8
        psg = [None] * 14
        pagina1 = "cart"
        salto = None
        escribe_pagina1_con_cart = []
        lee_rom_sin_cart = []

        def escribe_ram(dst, datos):
            if pagina1 == "cart" and any(0x4000 <= dst + i <= 0x7FFF for i in (0, len(datos) - 1)):
                escribe_pagina1_con_cart.append((dst, len(datos)))
            ram[dst:dst + len(datos)] = datos

        def lee_rom(op):
            if pagina1 != "cart":
                lee_rom_sin_cart.append(op)
            self.assertTrue(0x4000 <= op["src"] and op["src"] + op["len"] <= 0x8000, "una copia cruza el banco")
            base = op["b"] * 0x4000 + op["src"] - 0x4000
            return self.rom[base:base + op["len"]]

        for op in self.plan["plan"]:
            nombre = op["op"]
            if nombre == "ROM_RAM":
                escribe_ram(op["dst"], lee_rom(op))
            elif nombre == "ROM_VRAM":
                vram[op["dst"]:op["dst"] + op["len"]] = lee_rom(op)
            elif nombre == "VRAM_RAM":
                escribe_ram(op["dst"], vram[op["src"]:op["src"] + op["len"]])
            elif nombre == "LLENA_RAM":
                escribe_ram(op["dst"], bytes([op["b"]]) * op["len"])
            elif nombre == "LLENA_VRAM":
                vram[op["dst"]:op["dst"] + op["len"]] = bytes([op["b"]]) * op["len"]
            elif nombre == "IDENT_VRAM":
                vram[op["dst"]:op["dst"] + op["len"]] = bytes(i & 0xFF for i in range(op["len"]))
            elif nombre == "SPRITES_VRAM":
                vram[op["dst"]:op["dst"] + 128] = b"".join(bytes([209, 0, n, 1]) for n in range(32))
            elif nombre == "PAG1_RAM":
                pagina1 = "ram"
            elif nombre == "PAG1_CART":
                pagina1 = "cart"
            elif nombre == "VDP_REG":
                vdp[op["b"]] = op["src"] & 0xFF
            elif nombre == "PSG_REG":
                psg[op["b"]] = op["src"] & 0xFF
            elif nombre == "ESPERA":
                self.assertGreater(op["b"], 0)
            elif nombre == "SALTA":
                salto = (op["src"], op["dst"], pagina1)
                break
            else:
                self.fail("op desconocida en el plan: %s" % nombre)

        self.assertEqual(escribe_pagina1_con_cart, [], "el plan escribe en la pagina 1 con el cartucho puesto")
        self.assertEqual(lee_rom_sin_cart, [], "el plan lee la ROM con el cartucho quitado")
        self.assertEqual(salto, (0xFDE8, 0x0190, "ram"), "hay que saltar a 0x0190 con SP=0xFDE8 y las cuatro paginas en RAM")

        # la RAM: como la deja el cargador de la cinta en 0xD741
        bajo, medio, alto = (lee(os.path.join(WORK, n + ".raw")) for n in ("bajo", "medio", "alto"))
        self.assertEqual(ram[0x0190:0x0190 + len(bajo)], bajo)
        self.assertEqual(ram[0x3F4F:0x3F4F + len(medio)], medio)
        self.assertEqual(ram[0x88B8:0x88B8 + len(alto)], alto)
        self.assertEqual(ram[0x012C:0x0190], bytes(100), "el buzon de POKEs tiene que ir a cero")
        # la VRAM: la imagen de carga y lo que deja el SCREEN 2 del BASIC
        pantalla = lee(os.path.join(WORK, "pantalla.raw"))
        self.assertEqual(vram[0x0000:0x1800], pantalla[100:100 + 6144])
        self.assertEqual(vram[0x2000:0x3800], pantalla[100 + 6144:100 + 12288])
        self.assertEqual(vram[0x1800:0x1B00], bytes(range(256)) * 3)
        self.assertEqual(vram[0x1B00:0x1B80], b"".join(bytes([209, 0, n, 1]) for n in range(32)))
        self.assertEqual(set(vram[0x1B80:0x2000]) | set(vram[0x3800:0x4000]), {0})
        # y los registros, los medidos en la cinta
        self.assertEqual(vdp, self.plan["vdp_regs"])
        self.assertEqual(psg, self.plan["psg_regs"])
        self.assertEqual(vdp[1], 0xE0, "hay que dejar la pantalla encendida")

    def test_lo_medido_en_la_cinta_es_lo_que_escribe_el_plan(self):
        estado = os.path.join(WORK, "estado_cinta")
        hace_falta(os.path.join(estado, "vdpregs_5e00.bin"), os.path.join(estado, "psgregs_5e00.bin"))
        self.assertEqual(list(lee(os.path.join(estado, "vdpregs_5e00.bin"))[:8]), self.plan["vdp_regs"])
        psg = list(lee(os.path.join(estado, "psgregs_5e00.bin"))[:14])
        psg[7] |= 0x80  # el puerto B del PSG es de salida en el MSX
        self.assertEqual(psg, self.plan["psg_regs"])


class TestElCotejoConLaCinta(unittest.TestCase):
    """Los volcados de openMSX, si estan hechos (`make verifica`)."""

    def coteja(self, volcados, cinta):
        estado = os.path.join(WORK, "estado_cinta")
        hace_falta(os.path.join(volcados, "ram_5e00.bin"), os.path.join(cinta, "full_5e00.bin"),
                   os.path.join(estado, "vram_5e00.bin"))
        import coteja_rom
        r = subprocess.run([sys.executable, coteja_rom.__file__, volcados, cinta, estado],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("todo lo exigido coincide", r.stdout)

    def test_la_rom_original_en_la_vg8020(self):
        self.coteja(os.path.join(WORK, "rom_Philips_VG_8020"), os.path.join(WORK, "omsx_orig"))

    def test_la_rom_parcheada_en_la_vg8020(self):
        self.coteja(os.path.join(WORK, "rom_parche_Philips_VG_8020"), os.path.join(WORK, "omsx_v4"))


if __name__ == "__main__":
    unittest.main()
