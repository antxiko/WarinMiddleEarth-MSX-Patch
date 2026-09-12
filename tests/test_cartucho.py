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
ROM_MUSICA = os.path.join(RAIZ, "war_musica.rom")
WORK_MUSICA = os.path.join(WORK, "musica")


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def descomprime_desde(rom, ini):
    """Lo que sale de descomprimir el bloque que empieza en `ini`.

    No reimplementa el formato: ejecuta el descompresor DE VERDAD
    (src/cartucho/dzx0.asm) en el interprete de Z80 de tools/corre_finales.py.
    Asi lo que se comprueba es el codigo que va a correr en el MSX, y la pareja
    sigue siendo independiente: el compresor es el C de Einar Saukas y esto su
    ensamblador, que son dos implementaciones distintas del mismo formato."""
    import zx0
    return zx0.descomprime(rom[ini:])


def hace_falta(*rutas):
    for r in rutas:
        if not os.path.exists(r):
            raise unittest.SkipTest("falta %s: hace falta `make rom` o `make verifica_rom` con tu cinta" % os.path.relpath(r, RAIZ))




def ejecuta_plan(test, rom, plan):
    """El plan, interpretado aparte del stub: lleva la cuenta de la RAM, la
    VRAM, los registros y de quien esta en la pagina 1 en cada paso. Sirve para
    cualquier ROM del proyecto, que es lo que permite ejecutar las dos y
    comparar la RAM que dejan."""
    self = test
    ram = bytearray(b"\x00" * 0x10000)
    vram = bytearray(b"\x00" * 0x4000)
    vdp = [None] * 8
    psg = [None] * 14
    pagina1 = "cart"
    ventana_8000 = None
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
        return rom[base:base + op["len"]]

    for op in plan["plan"]:
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
        elif nombre == "BANCO_8000":
            # El registro vive en 0x7000, o sea en la pagina 1: solo se
            # puede escribir con el cartucho puesto ahi.
            self.assertEqual(pagina1, "cart",
                             "la ventana de 0x8000 se fija sin el cartucho en la pagina 1")
            ventana_8000 = op["b"]
        elif nombre == "ZX0_RAM":
            # ZX0 lee de la RAM y escribe en la RAM: ni toca la ROM ni el banco.
            # El bloque comprimido lo trajo un ROM_RAM antes.
            escribe_ram(op["dst"], descomprime_desde(bytes(ram), op["src"]))
        elif nombre == "RAM_VRAM":
            vram[op["dst"]:op["dst"] + op["len"]] = ram[op["src"]:op["src"] + op["len"]]
        elif nombre in ("RANURA_PAG1", "RANURA_PAG2"):
            # un byte: el operando del `or` que lleva la ranura del cartucho
            escribe_ram(op["dst"], b"\x00")
        elif nombre == "SALTA":
            salto = (op["src"], op["dst"], pagina1)
            break
        else:
            self.fail("op desconocida en el plan: %s" % nombre)

    if "musica" in plan["datos"]:
        self.assertEqual(ventana_8000, plan["datos"]["musica"]["banco"],
                         "la ventana de 0x8000 no se queda en el banco de la musica")
    self.assertEqual(escribe_pagina1_con_cart, [], "el plan escribe en la pagina 1 con el cartucho puesto")
    self.assertEqual(lee_rom_sin_cart, [], "el plan lee la ROM con el cartucho quitado")
    self.assertEqual(salto, (0xFDE8, 0x0190, "ram"), "hay que saltar a 0x0190 con SP=0xFDE8 y las cuatro paginas en RAM")

    return ram, vram, vdp, psg, salto

class TestLaRom(unittest.TestCase):

    # Los mismos requisitos valen para war.rom y para war_musica.rom; lo unico
    # que cambia es de donde salen. Los derivados de la ROM con musica van a
    # work/musica/ para que las dos no se pisen el plan ni el stub.
    ROM = ROM
    DERIVADOS = WORK
    CUERPOS = WORK          # de que cinta salen los cuerpos: la original o la parcheada

    def setUp(self):
        plan = os.path.join(self.DERIVADOS, "plan.json")
        hace_falta(self.ROM, plan)
        self.rom = lee(self.ROM)
        with open(plan) as f:
            self.plan = json.load(f)
        self.musica = self.plan["datos"].get("musica")

    def parches(self):
        """Todos los bytes del juego que esta ROM declara cambiar: los dos de
        la musica, el de las pantallas finales y los dos de la vista. Vienen
        del plan, no de una lista escrita aqui, para que no puedan quedarse
        viejos."""
        todos = list((self.musica or {}).get("parches", []))
        if self.plan.get("finales"):
            todos.append(self.plan["finales"]["parche"])
        todos += self.plan.get("vista", {}).get("parches", [])
        return todos

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
        with open(os.path.join(self.DERIVADOS, "cargador_ram.bin"), "rb") as f:
            stub = f.read()
        self.assertEqual(self.rom[self.plan["arranque"]:cabeza], stub, "el stub de la ROM no es el ensamblado")

    def test_los_cuerpos_de_la_cinta_estan_en_la_rom(self):
        pantalla = lee(os.path.join(self.CUERPOS, "pantalla.raw"))
        esperado = dict(patrones=pantalla[100:100 + 6144], colores=pantalla[100 + 6144:100 + 12288],
                        bajo=lee(os.path.join(self.CUERPOS, "bajo.raw")), medio=lee(os.path.join(self.CUERPOS, "medio.raw")),
                        alto=lee(os.path.join(self.CUERPOS, "alto.raw")))
        # Con musica, con las finales en la ROM y con la vista, los bloques
        # llevan sus parches -el medio, y el bajo desde la vista-: se aplican
        # sobre lo esperado, que para eso el plan dice cuales son y donde caen.
        for q in self.parches():
            bloque = q.get("bloque", "medio")
            o = q["dir"] - {"medio": 0x5E00, "bajo": 0x0190}[bloque]
            viejo, nuevo = bytes.fromhex(q["orig"]), bytes.fromhex(q["nuevo"])
            self.assertEqual(esperado[bloque][o:o + len(viejo)], viejo,
                             "el parche de 0x%04X no cae sobre lo que dice" % q["dir"])
            esperado[bloque] = esperado[bloque][:o] + nuevo + esperado[bloque][o + len(nuevo):]
        # Con --comprime, el bloque bajo se parte: su codigo crudo y detras las
        # dos pantallas finales comprimidas, cada una en su entrada.
        corte = len(esperado["bajo"])
        for n, (dir_, tam) in enumerate(((0x094F, 6912), (0x244F, 6912))):
            if ("final%d" % n) in self.plan["datos"]:
                o = dir_ - 0x0190
                esperado["final%d" % n] = esperado["bajo"][o:o + tam]
                corte = min(corte, o)
        esperado["bajo"] = esperado["bajo"][:corte]

        for nombre, d in self.plan["datos"].items():
            if nombre == "musica":
                continue        # no sale de la cinta; tiene sus propios tests
            en_rom = self.rom[d["rom"]:d["rom"] + d["bytes"]]
            if d.get("zx0"):
                # Lo que cuenta no es lo que hay en la ROM sino lo que sale al
                # descomprimirlo: es la unica forma de que este test siga
                # comprobando la cinta y no el formato.
                salido = descomprime_desde(self.rom, d["rom"])
                self.assertEqual(salido, esperado[nombre], "%s, descomprimido" % nombre)
                self.assertEqual(len(salido), d["crudo"], nombre)
                self.assertLess(d["bytes"], d["crudo"], "%s no encoge" % nombre)
            else:
                self.assertEqual(en_rom, esperado[nombre], nombre)
        fin = max(d["rom"] + d["bytes"] for n, d in self.plan["datos"].items() if n != "musica")
        self.assertEqual(fin, self.plan["fin_datos"])
        extra = (self.musica["bytes"] if self.musica else 0)
        if self.plan.get("finales"):
            extra += self.plan["finales"]["bytes"]
        if self.plan.get("vista"):
            extra += self.plan["vista"]["bytes"]
        relleno = self.rom[fin + extra:]
        self.assertEqual(set(relleno), {0xFF})

    def test_las_variables_del_stub_estan_donde_dice_direcciones_inc(self):
        simbolos = {}
        for fichero in ("cargador_ram.sym", "cargador_rom.sym"):
            with open(os.path.join(self.DERIVADOS, fichero)) as f:
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
        ram, vram, vdp, psg, salto = ejecuta_plan(self, self.rom, self.plan)
        self._comprueba_la_ram(ram, vram, vdp, psg, salto)

    def _comprueba_la_ram(self, ram, vram, vdp, psg, salto):
        """Lo que el cargador tiene que dejar, venga de la ROM que venga."""
        bajo, medio, alto = (lee(os.path.join(self.CUERPOS, n + '.raw')) for n in ('bajo', 'medio', 'alto'))
        # la RAM: como la deja el cargador de la cinta en 0xD741, con los
        # parches que el plan declara puestos en su bloque: el medio (que aqui
        # aun esta en 0x3F4F, sin recolocar) o el bajo (0x044B, la vista).
        for q in self.parches():
            nuevo = bytes.fromhex(q["nuevo"])
            if q.get("bloque", "medio") == "medio":
                o = q["dir"] - 0x5E00
                medio = medio[:o] + nuevo + medio[o + len(nuevo):]
            else:
                o = q["dir"] - 0x0190
                bajo = bajo[:o] + nuevo + bajo[o + len(nuevo):]
        # Con las finales en la ROM, del bloque bajo solo viaja el codigo: las
        # dos pantallas se quedan donde estan y se descomprimen al acabar la
        # partida. Esos 13.824 bytes de RAM tienen que quedar SIN TOCAR, que es
        # justamente lo que libera el cambio.
        finales = self.plan.get("finales")
        if finales:
            corte = min(q["dir"] for q in finales["pantallas"]) - 0x0190
            self.assertEqual(ram[0x0190:0x0190 + corte], bajo[:corte])
            # Ya no se puede exigir que ese tramo quede a CERO: los dos bufers
            # de ZX0 viven ahi y dejan restos de la imagen de carga. Lo que se
            # exige es lo que de verdad importa: que la pantalla final no este.
            for q in finales["pantallas"]:
                o = q["dir"] - 0x0190
                self.assertNotEqual(bytes(ram[q["dir"]:q["dir"] + q["crudo"]]),
                                    bajo[o:o + q["crudo"]],
                                    "la pantalla de 0x%04X sigue viajando a la RAM" % q["dir"])
        else:
            self.assertEqual(ram[0x0190:0x0190 + len(bajo)], bajo)
        self.assertEqual(ram[0x3F4F:0x3F4F + len(medio)], medio)
        self.assertEqual(ram[0x88B8:0x88B8 + len(alto)], alto)
        self.assertEqual(ram[0x012C:0x0190], bytes(100), "el buzon de POKEs tiene que ir a cero")
        # la VRAM: la imagen de carga y lo que deja el SCREEN 2 del BASIC
        pantalla = lee(os.path.join(self.CUERPOS, "pantalla.raw"))
        self.assertEqual(vram[0x0000:0x1800], pantalla[100:100 + 6144])
        self.assertEqual(vram[0x2000:0x3800], pantalla[100 + 6144:100 + 12288])
        self.assertEqual(vram[0x1800:0x1B00], bytes(range(256)) * 3)
        self.assertEqual(vram[0x1B00:0x1B80], b"".join(bytes([209, 0, n, 1]) for n in range(32)))
        self.assertEqual(set(vram[0x1B80:0x2000]) | set(vram[0x3800:0x4000]), {0})
        # y los registros, los medidos en la cinta; con la vista, R1 lleva
        # ademas el bit 1: el cursor es un sprite de 16x16
        self.assertEqual(vdp, self.plan["vdp_regs"])
        self.assertEqual(psg, self.plan["psg_regs"])
        self.assertEqual(vdp[1], 0xE2 if self.plan.get("vista") else 0xE0,
                         "hay que dejar la pantalla encendida (y los sprites de 16x16 con la vista)")


    def test_lo_medido_en_la_cinta_es_lo_que_escribe_el_plan(self):
        estado = os.path.join(WORK, "estado_cinta")
        hace_falta(os.path.join(estado, "vdpregs_5e00.bin"), os.path.join(estado, "psgregs_5e00.bin"))
        medidos = list(lee(os.path.join(estado, "vdpregs_5e00.bin"))[:8])
        del_plan = list(self.plan["vdp_regs"])
        if self.plan.get("vista"):
            # el unico bit que el plan anade a lo medido es el tamano de sprite
            self.assertEqual(del_plan[1], medidos[1] | 0x02)
            del_plan[1] &= ~0x02
        self.assertEqual(medidos, del_plan)
        psg = list(lee(os.path.join(estado, "psgregs_5e00.bin"))[:14])
        psg[7] |= 0x80  # el puerto B del PSG es de salida en el MSX
        self.assertEqual(psg, self.plan["psg_regs"])


class TestLaRomConMusica(TestLaRom):
    """Los MISMOS requisitos de siempre, pero sobre war_musica.rom.

    Heredar en vez de copiar es lo que da valor: la ROM con musica tiene que
    seguir dejando la RAM y la VRAM como la cinta, saltar a 0x0190 con las
    cuatro paginas en RAM y no escribir en la pagina 1 con el cartucho puesto.
    Lo unico que se le permite de mas son los parches que el propio plan
    declara, y el hueco del final ocupado.
    """
    ROM = ROM_MUSICA
    DERIVADOS = WORK_MUSICA


class TestLaRomParcheConMusica(TestLaRom):
    """Y otra vez sobre war_parche_musica.rom: la cinta PARCHEADA de Araubi
    con la musica, ZX0, las finales en la ROM y la vista con el cursor como
    sprite. Es el cartucho que se juega, asi que tiene que cumplir lo mismo,
    con los cuerpos de la cinta parcheada (work/cuerpos_parche)."""
    ROM = os.path.join(RAIZ, "war_parche_musica.rom")
    DERIVADOS = os.path.join(WORK, "parche_musica")
    CUERPOS = os.path.join(WORK, "cuerpos_parche")


class TestLaMusica(unittest.TestCase):
    """Lo que solo tiene sentido con musica: donde cae, que cambia y que no."""

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)
        self.m = self.plan["datos"]["musica"]

    def parches_declarados(self):
        todos = list(self.m["parches"])
        if self.plan.get("finales"):
            todos.append(self.plan["finales"]["parche"])
        todos += self.plan.get("vista", {}).get("parches", [])
        return todos

    def test_cabe_en_el_hueco_y_no_se_sale_del_ultimo_banco(self):
        ini = self.m["rom"]
        self.assertEqual(ini, self.plan["fin_datos"], "la musica no empieza donde acaban los datos")
        self.assertEqual(ini // 0x4000, self.m["banco"])
        fin = ini + self.m["bytes"]
        self.assertLessEqual(fin, len(self.rom), "la musica se sale de la ROM")
        self.assertEqual(fin // 0x4000, self.m["banco"] if fin % 0x4000 else self.m["banco"] + 1,
                         "la musica cruza a otro banco y por la ventana no se veria entera")
        self.assertGreaterEqual(self.plan["libre"], 0)

    def test_lo_que_se_ve_por_la_ventana_de_0x8000_es_lo_que_hay_en_la_rom(self):
        """El reproductor se ensambla con un `org` que NO es donde vive en la
        ROM, sino donde se vera al poner su banco en la ventana de 0x8000. Si
        esa cuenta estuviera mal, cada `call` del reproductor saltaria a otro
        sitio. Aqui se comprueba la correspondencia y que las direcciones que
        el plan publica caen dentro de la ventana."""
        self.assertEqual(self.m["org"], 0x8000 + self.m["rom"] - self.m["banco"] * 0x4000)
        for rutina in ("init", "play", "rout", "mute", "modulo"):
            d = self.m[rutina]
            self.assertTrue(self.m["org"] <= d < self.m["org"] + self.m["bytes"],
                            "%s cae en 0x%04X, fuera del bloque" % (rutina, d))
        with open(os.path.join(WORK_MUSICA, "musica.bin"), "rb") as f:
            bloque = f.read()
        self.assertEqual(self.rom[self.m["rom"]:self.m["rom"] + len(bloque)], bloque,
                         "lo que hay en la ROM no es el reproductor ensamblado")

    def test_el_modulo_va_sin_sus_cien_bytes_de_cabecera(self):
        """A PT3_INIT se le pasa MODULO-100 porque el modulo viaja sin la
        cabecera de texto. Si se metiera entero, el reproductor leeria el
        titulo como si fueran punteros."""
        with open(os.path.join(WORK_MUSICA, "modulo.bin"), "rb") as f:
            modulo = f.read()
        ini = self.m["rom"] + self.m["modulo"] - self.m["org"]
        self.assertEqual(self.rom[ini:ini + len(modulo)], modulo)
        # El byte 0 del modulo recortado es el que el reproductor lee como
        # Delay, o sea el byte 100 del fichero: si alguien quitara el recorte,
        # aqui saldria una letra del titulo.
        self.assertLess(modulo[0], 0x20, "el primer byte no parece el Delay del PT3 sino texto")

    def test_el_puente_cabe_donde_dice_y_no_pisa_el_buzon_de_pokes(self):
        p = self.m["puente"]
        self.assertEqual(p["ram"], 0x003B, "el puente tiene que ir detras del `jp 0x0400` de 0x0038")
        self.assertLessEqual(p["ram"] + p["bytes"], 0x012C,
                             "el puente llega al buzon de POKEs de 0x012C")
        self.assertTrue(p["ram"] <= p["para"] < p["ram"] + p["bytes"],
                        "PARA_LA_MUSICA cae fuera del puente")
        with open(os.path.join(WORK_MUSICA, "puente.bin"), "rb") as f:
            puente = f.read()
        self.assertEqual(len(puente), p["bytes"])
        self.assertEqual(self.rom[p["rom"]:p["rom"] + len(puente)], puente)

    def test_el_puente_solo_conmuta_la_pagina_2(self):
        """LO QUE NO PUEDE PASAR NUNCA: que el puente toque la pagina de la
        pila.

        La pila del juego esta en 0x5BFF y el area de trabajo del reproductor en
        0x5C00, las dos en la pagina 1; el propio puente y el gancho que lo llama
        estan en la 0, y la pila del sistema y el mapa en la 3. Si al asomar la
        ROM se cambiara cualquiera de esas tres, el `ret` de vuelta leeria de
        una pagina distinta de la que empujo la llamada y la maquina se iria.

        En 0xA8 cada pagina son dos bits: 0-1 la pagina 0, 2-3 la 1, 4-5 la 2 y
        6-7 la 3. La mascara 0xCF -11001111- borra SOLO los bits de la pagina 2
        y conserva las otras tres tal y como estaban, que es justo lo exigido.
        """
        with open(os.path.join(WORK_MUSICA, "puente.bin"), "rb") as f:
            puente = f.read()
        escrituras = [i for i in range(len(puente) - 1) if puente[i:i + 2] == b"\xD3\xA8"]
        self.assertEqual(len(escrituras), 2,
                         "el puente tiene que escribir 0xA8 dos veces: al asomar la ROM y al devolverla")
        # La primera escritura va precedida de `in a,(0A8h)` (DB A8), el `and`
        # de la mascara y el `or` de la ranura: se parte de lo que HAY, no de un
        # valor inventado, que es lo que hace que las otras tres paginas queden
        # como estuvieran.
        cabeza = puente[:escrituras[0]]
        self.assertIn(b"\xDB\xA8", cabeza, "el puente no lee 0xA8 antes de escribirlo")
        self.assertIn(b"\xE6\xCF", cabeza,
                      "el puente no enmascara con 0xCF: estaria tocando paginas que no son la 2")
        self.assertNotIn(b"\xE6", cabeza[cabeza.index(b"\xE6\xCF") + 2:],
                         "hay un segundo `and` antes de conmutar")
        # Y la segunda devuelve exactamente lo leido, que viajo por la pila.
        self.assertEqual(puente[escrituras[1] - 1], 0xF1, "antes de devolver 0xA8 falta el `pop af`")
        self.assertIn(b"\xF5", puente[:escrituras[0]], "falta el `push af` que guarda como estaba")

    def test_el_plan_copia_el_puente_a_su_sitio_y_le_da_la_ranura(self):
        p = self.m["puente"]
        copias = [o for o in self.plan["plan"] if o["op"] == "ROM_RAM" and o["dst"] == p["ram"]]
        self.assertEqual(len(copias), 1, "el puente no se copia exactamente una vez")
        self.assertEqual(copias[0]["len"], p["bytes"])
        # La rutina de las finales tambien pide su RANURA_PAG2, asi que hay que
        # quedarse con la que cae DENTRO del puente.
        ranura = [o for o in self.plan["plan"] if o["op"] == "RANURA_PAG2"
                  and p["ram"] <= o["dst"] < p["ram"] + p["bytes"]]
        self.assertEqual(len(ranura), 1, "nadie rellena la ranura del puente, o la rellenan dos veces")

    def test_la_rom_con_extras_solo_cambia_la_ram_en_lo_que_declara(self):
        """La prueba de que ni la musica ni las finales tocan el juego.

        No se comparan las dos ROMs byte a byte: desde que las imagenes viajan
        comprimidas, la de musica no se PARECE a la otra -otra disposicion, otro
        stub, otros tamanos- y ese diff no diria nada. Lo que tiene que
        coincidir es lo que acaba en la RAM, que es lo unico que el juego ve.

        Se permite exactamente: los bytes que el plan declara como parches, el
        puente y la rutina de las finales -las dos en tierra de nadie, que no le
        quitan el sitio a nadie- y los 13.824 bytes de las dos pantallas
        finales, que es lo que este cambio LIBERA a proposito.
        """
        hace_falta(ROM, PLAN)
        with open(PLAN) as f:
            plan_sin = json.load(f)
        ram_sin = ejecuta_plan(self, lee(ROM), plan_sin)[0]
        ram_con = ejecuta_plan(self, self.rom, self.plan)[0]

        de_la_musica = set()
        for q in self.m["parches"]:
            de_la_musica.update(range(q["carga"], q["carga"] + len(bytes.fromhex(q["nuevo"]))))
        self.assertEqual(len(de_la_musica), 5, "los parches de la musica tienen que ser cinco bytes")
        permitidos = set(de_la_musica)
        p = self.m["puente"]
        permitidos.update(range(p["ram"], p["ram"] + p["bytes"]))

        finales = self.plan.get("finales")
        if finales:
            q = finales["parche"]
            self.assertEqual(len(bytes.fromhex(q["nuevo"])), 8,
                             "el parche de las finales son los ocho bytes del `ldir`")
            permitidos.update(range(q["carga"], q["carga"] + 8))
            permitidos.update(range(finales["ram"], finales["ram"] + finales["bytes"]))
            for pantalla in finales["pantallas"]:
                permitidos.update(range(pantalla["dir"], pantalla["dir"] + pantalla["crudo"]))
            # y los bufers de ZX0, que viven en ese mismo tramo
            z = self.plan["zona_libre"]
            for cual in ("bufer_z", "bufer_d"):
                permitidos.update(range(z[cual]["ram"], z[cual]["ram"] + z[cual]["bytes"]))
                # Y que la diferencia sea la que se dice: war.rom SI las lleva a
                # la RAM y esta NO. Sin esto, el tramo permitido taparia
                # cualquier cosa que pasara ahi.
                tramo = slice(pantalla["dir"], pantalla["dir"] + pantalla["crudo"])
                self.assertNotEqual(bytes(ram_con[tramo]), bytes(ram_sin[tramo]),
                                    "la pantalla de 0x%04X sigue viajando a la RAM" % pantalla["dir"])
        vista = self.plan.get("vista")
        if vista:
            # La rutina de la vista, en la misma zona liberada, y sus cuatro
            # parches: trece bytes, nueve del bloque medio y cuatro del bajo.
            permitidos.update(range(vista["ram"], vista["ram"] + vista["bytes"]))
            de_la_vista = set()
            for q in vista["parches"]:
                de_la_vista.update(range(q["carga"], q["carga"] + len(bytes.fromhex(q["nuevo"]))))
            self.assertEqual(len(de_la_vista), 13, "los parches de la vista tienen que ser trece bytes")
            permitidos.update(de_la_vista)

        fuera = [i for i in range(0x10000) if ram_sin[i] != ram_con[i] and i not in permitidos]
        self.assertEqual(fuera, [], "la ROM cambia la RAM fuera de lo que declara")
        # Y los parches se aplican de verdad: si no llegaran a la RAM, la
        # comprobacion de arriba pasaria igual.
        for q in self.parches_declarados():
            n = len(bytes.fromhex(q["nuevo"]))
            self.assertEqual(bytes(ram_con[q["carga"]:q["carga"] + n]), bytes.fromhex(q["nuevo"]),
                             "el parche de 0x%04X no llega a la RAM" % q["dir"])
            self.assertEqual(bytes(ram_sin[q["carga"]:q["carga"] + n]), bytes.fromhex(q["orig"]),
                             "en 0x%04X, war.rom no tiene lo que el parche dice sustituir" % q["dir"])

    def test_el_gancho_y_el_menu_quedan_apuntando_al_puente(self):
        p = self.m["puente"]
        porque = {q["dir"]: q for q in self.m["parches"]}
        self.assertEqual(bytes.fromhex(porque[0x5E10]["nuevo"]),
                         p["ram"].to_bytes(2, "little"),
                         "el gancho por cuadro no apunta al puente")
        self.assertEqual(bytes.fromhex(porque[0x5E86]["nuevo"]),
                         bytes([0xCD]) + p["para"].to_bytes(2, "little"),
                         "el menu no llama a PARA_LA_MUSICA")


class TestLasPantallasFinales(unittest.TestCase):
    """Las dos pantallas del final se quedan en la ROM (--finales-rom).

    Lo fuerte de aqui es que la rutina se EJECUTA, en tools/corre_finales.py:
    un interprete del Z80 con las ranuras y el mapper modelados. Es la unica
    forma de comprobar sin emulador las tres cosas que pueden salir mal -el
    banco que se pone en la ventana de 0x8000, el cruce de banco a mitad del
    flujo comprimido y las dos conmutaciones de pagina- y ademas la que
    importa: que lo que queda en 0x4000 es la pantalla de la cinta, byte a byte.
    """

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)
        if "finales" not in self.plan:
            raise unittest.SkipTest("esta ROM no lleva las finales en la ROM (--finales-rom)")
        self.f = self.plan["finales"]
        self.bajo = lee(os.path.join(WORK, "bajo.raw"))

    def de_la_cinta(self, pantalla):
        """Los 6.912 bytes de esa pantalla tal y como vienen de la cinta."""
        o = pantalla["dir"] - 0x0190
        return self.bajo[o:o + pantalla["crudo"]]

    # ---------------------------------------------------------- la colocacion
    def test_la_rutina_y_los_bufers_caben_en_la_zona_que_ella_libera(self):
        """La rutina ya no cabe detras del puente: con el descompresor ZX0
        dentro pasa de los 166 bytes que hay hasta el buzon de POKEs. Vive en la
        RAM que ella misma libera, junto a los dos bufers, y los tres tienen que
        caber ahi sin pisarse ni salirse."""
        f = self.f
        z = self.plan["zona_libre"]
        self.assertEqual(z["rutina"]["ram"], f["ram"])
        self.assertEqual(z["rutina"]["bytes"], f["bytes"])
        # los tres, en orden y sin solaparse
        tramos = [(z["rutina"]["ram"], z["rutina"]["bytes"], "la rutina"),
                  (z["bufer_z"]["ram"], z["bufer_z"]["bytes"], "el bufer del comprimido"),
                  (z["bufer_d"]["ram"], z["bufer_d"]["bytes"], "el bufer del descomprimido")]
        if "nombres" in z:
            # y la vista por tabla de nombres, que va detras de los bufers
            tramos.append((z["nombres"]["ram"], z["nombres"]["bytes"], "la rutina de la vista"))
        anterior = z["ini"]
        for ini, tam, que in tramos:
            self.assertGreaterEqual(ini, anterior, "%s empieza dentro de lo anterior" % que)
            anterior = ini + tam
        self.assertLessEqual(anterior, z["fin"] + 1,
                             "los bufers llegan a 0x%04X y se salen de la zona libre" % anterior)
        # y la zona libre es de verdad lo que las pantallas dejaron
        self.assertGreaterEqual(z["ini"], min(q["dir"] for q in f["pantallas"]))
        self.assertLessEqual(z["fin"], max(q["dir"] + q["crudo"] for q in f["pantallas"]) - 1)
        self.assertTrue(f["ram"] <= f["entrada"] < f["ram"] + f["bytes"])
        with open(os.path.join(WORK_MUSICA, "finales.bin"), "rb") as fh:
            binario = fh.read()
        self.assertEqual(len(binario), f["bytes"])
        self.assertEqual(self.rom[f["rom"]:f["rom"] + len(binario)], binario,
                         "lo que hay en la ROM no es la rutina ensamblada")

    def test_el_plan_copia_la_rutina_y_le_da_las_dos_ranuras(self):
        f = self.f
        copias = [o for o in self.plan["plan"] if o["op"] == "ROM_RAM" and o["dst"] == f["ram"]]
        self.assertEqual(len(copias), 1, "la rutina no se copia exactamente una vez")
        self.assertEqual(copias[0]["len"], f["bytes"])
        # Las dos ranuras: la pagina 2 para leer la ROM y la 1 para el registro
        # del mapper. Si faltara cualquiera, el `or` se quedaria en 0x00 y la
        # rutina conmutaria a la ranura 0.
        for pagina, op in (("pag2", "RANURA_PAG2"), ("pag1", "RANURA_PAG1")):
            dst = f["ranuras"][pagina]
            cuantas = [o for o in self.plan["plan"] if o["op"] == op and o["dst"] == dst]
            self.assertEqual(len(cuantas), 1, "la ranura de la %s no se rellena una sola vez" % pagina)
            self.assertTrue(f["ram"] <= dst < f["ram"] + f["bytes"],
                            "la ranura de la %s se escribe fuera de la rutina" % pagina)

    def test_las_pantallas_ya_no_viajan_a_la_ram(self):
        """Lo que libera los 13.824 bytes: ninguna operacion del plan escribe en
        0x094F-0x3F4E. Es la cuenta de RAM que justifica todo el cambio."""
        ini = min(q["dir"] for q in self.f["pantallas"])
        fin = max(q["dir"] + q["crudo"] for q in self.f["pantallas"])
        self.assertEqual(fin - ini, 13824)
        # En el tramo liberado ahora vive gente: la rutina y los dos bufers de
        # ZX0. Lo que NO puede haber es una pantalla entera.
        z = self.plan["zona_libre"]
        permitido = [(z["rutina"]["ram"], z["rutina"]["bytes"]),
                     (z["bufer_z"]["ram"], z["bufer_z"]["bytes"]),
                     (z["bufer_d"]["ram"], z["bufer_d"]["bytes"])]
        if "nombres" in z:
            permitido.append((z["nombres"]["ram"], z["nombres"]["bytes"]))

        def declarado(dst, n):
            return any(a <= dst and dst + n <= a + t for a, t in permitido)

        for o in self.plan["plan"]:
            if o["op"] in ("ROM_RAM", "LLENA_RAM", "VRAM_RAM", "ZX0_RAM"):
                # ZX0_RAM no dice cuanto escribe: se mira solo donde empieza
                n = 1 if o["op"] == "ZX0_RAM" else o["len"]
                if o["dst"] < fin and o["dst"] + n > ini:
                    self.assertTrue(declarado(o["dst"], n),
                                    "la op %s escribe en el tramo liberado sin declararlo: 0x%04X +%d"
                                    % (o["op"], o["dst"], n))
            if o["op"] == "ZX0_RAM":
                self.assertNotIn(o["dst"], [q["dir"] for q in self.f["pantallas"]],
                                 "una pantalla final sigue descomprimiendose a la RAM en 0x%04X" % o["dst"])

    def test_el_parche_sustituye_exactamente_el_ldir_de_0x83e7(self):
        q = self.f["parche"]
        self.assertEqual(q["dir"], 0x83E7)
        # `ld de,04000h / ld bc,01b00h / ldir`: los ocho bytes que copiaban la
        # pantalla desde la RAM. 0x1B00 = 6912, que es lo que la rutina deja.
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("110040 01001b edb0"))
        nuevo = bytes.fromhex(q["nuevo"])
        self.assertEqual(len(nuevo), 8, "el parche tiene que ocupar lo mismo que el `ldir`")
        self.assertEqual(nuevo[0], 0xCD, "el parche no empieza por un `call`")
        self.assertEqual(nuevo[1] | (nuevo[2] << 8), self.f["entrada"],
                         "el `call` no apunta a la entrada de la rutina")
        self.assertEqual(set(nuevo[3:]), {0}, "los cinco bytes de relleno no van a cero")
        # y llega a la RAM donde el juego lo ejecuta
        o = q["dir"] - 0x5E00
        medio = lee(os.path.join(WORK, "medio.raw"))
        self.assertEqual(medio[o:o + 8], bytes.fromhex(q["orig"]),
                         "en la cinta, 0x83E7 no es el `ldir` que el parche dice sustituir")
        self.assertEqual(self.rom[q["rom"]:q["rom"] + 8], nuevo)

    # ------------------------------------------------ y la rutina, EJECUTADA
    def corre(self, pantalla, **kw):
        import corre_finales
        return corre_finales.pinta(self.rom, self.plan, pantalla, **kw)

    def test_las_dos_pantallas_salen_identicas_a_las_de_la_cinta(self):
        """EL TEST QUE DECIDE. Se ejecuta la rutina y lo que deja en 0x4000 -que
        es de donde 0x05BD sube el bitmap al VDP- tiene que ser, byte a byte, la
        pantalla que el `ldir` copiaba de la RAM."""
        for pantalla in self.f["pantallas"]:
            m, _z = self.corre(pantalla)
            salido = bytes(m.ram[0x4000:0x4000 + pantalla["crudo"]])
            self.assertEqual(salido, self.de_la_cinta(pantalla),
                             "la pantalla de 0x%04X no sale como la de la cinta" % pantalla["dir"])

    def test_la_rutina_nunca_toca_la_pila_con_el_cartucho_en_la_pagina_1(self):
        """LO QUE NO PUEDE PASAR NUNCA.

        La pila del juego esta en 0x5BFF, o sea en la pagina 1, y la rutina
        conmuta esa pagina al cartucho para escribir el registro del mapper de
        0x7000. Un push, un pop, un call o un ret en ese tramo escribiria o
        leeria la ROM: el retorno se perderia y la maquina se iria. Por eso las
        conmutaciones van con instrucciones sueltas y el `push af` de F_LEE
        queda fuera.
        """
        for pantalla in self.f["pantallas"]:
            m, _z = self.corre(pantalla)
            self.assertEqual(m.pila_con_cartucho, [],
                             "con la pantalla de 0x%04X se toca la pila teniendo el cartucho puesto"
                             % pantalla["dir"])
            self.assertEqual(m.escrituras_perdidas, [],
                             "la rutina escribe en la ROM, donde no hay nada que escribir")

    def test_la_rutina_devuelve_las_paginas_y_el_banco_como_estaban(self):
        """Al volver, el juego sigue: las cuatro paginas tienen que ser RAM otra
        vez y la ventana de 0x8000 tiene que apuntar al banco de la musica, que
        es lo que el puente espera encontrar."""
        for pantalla in self.f["pantallas"]:
            m, z = self.corre(pantalla)
            self.assertEqual(m.a8, m.ranura_ram * 0b01010101,
                             "las paginas no quedan como estaban: 0xA8 = 0x%02X" % m.a8)
            self.assertEqual(m.banco_8000, self.f["banco_vuelve"],
                             "la ventana de 0x8000 se queda en el banco %d" % m.banco_8000)
            self.assertIs(z.di, False, "la rutina se deja las interrupciones cerradas")

    def test_vale_este_el_cartucho_en_la_ranura_que_este(self):
        """La ranura no se sabe hasta el arranque: la escribe el cargador en los
        dos `or` de la rutina. Se prueban las cuatro primarias posibles para el
        cartucho, con la RAM en otra, porque una mascara mal puesta solo se nota
        en algunas combinaciones."""
        for cart in range(4):
            for ram in range(4):
                if cart == ram:
                    continue
                pantalla = self.f["pantallas"][0]
                m, _z = self.corre(pantalla, ranura_cart=cart, ranura_ram=ram)
                self.assertEqual(bytes(m.ram[0x4000:0x4000 + pantalla["crudo"]]),
                                 self.de_la_cinta(pantalla),
                                 "con el cartucho en la ranura %d y la RAM en la %d sale otra cosa"
                                 % (cart, ram))
                self.assertEqual(m.pila_con_cartucho, [])

    def test_no_se_pasa_del_sitio_de_la_pantalla(self):
        """6.912 bytes y ni uno mas: 0x4000+6912 = 0x5B00, y justo encima esta la
        pila del juego en 0x5BFF. Si el flujo comprimido no acabara donde debe,
        la rutina se la comeria."""
        for pantalla in self.f["pantallas"]:
            m, z = self.corre(pantalla)
            self.assertEqual(z.de, 0x4000 + pantalla["crudo"],
                             "la rutina deja DE en 0x%04X: ha escrito %d bytes y no %d"
                             % (z.de, z.de - 0x4000, pantalla["crudo"]))
            # de lo que escribe al final de la pantalla hasta la pila, nada
            self.assertEqual(set(m.ram[0x4000 + pantalla["crudo"]:0x5BF0]), {0},
                             "la rutina se ha pasado del sitio de la pantalla")


class TestLaVistaPorNombres(unittest.TestCase):
    """La vista de cerca por tabla de nombres (--vista): src/cartucho/nombres.asm.

    Como con las finales, lo fuerte es que la rutina se EJECUTA, en
    tools/corre_nombres.py: el mismo interprete de Z80 con el VDP modelado
    detras de los puertos 0x98 y 0x99. Asi se comprueba sin emulador lo que de
    otro modo solo se veria mirando una pantalla: que lo que llega a la tabla
    de nombres es la pantalla de caracteres, que los 256 patrones y colores son
    los de la fuente, los dibujos y la tabla del juego -replicados en los tres
    tercios-, y que el guardian devuelve la identidad cuando toca y no toca
    nada cuando no toca. El cotejo por pixel contra la ROM de antes lo hace
    `make verifica_vista`, con openMSX.
    """

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)
        if "vista" not in self.plan:
            raise unittest.SkipTest("esta ROM no lleva la vista por tabla de nombres (--vista)")
        self.v = self.plan["vista"]
        self.bajo = lee(os.path.join(WORK, "bajo.raw"))
        self.medio = lee(os.path.join(WORK, "medio.raw"))
        self.alto = lee(os.path.join(WORK, "alto.raw"))

    def monta(self):
        import corre_nombres
        return corre_nombres.monta(self.rom, self.plan, self.bajo, self.alto, medio=self.medio)

    # ---------------------------------------------------------- la colocacion
    def test_el_bloque_esta_en_la_rom_y_es_el_ensamblado(self):
        v = self.v
        with open(os.path.join(WORK_MUSICA, "nombres.bin"), "rb") as fh:
            binario = fh.read()
        self.assertEqual(len(binario), v["bytes"])
        self.assertEqual(self.rom[v["rom"]:v["rom"] + len(binario)], binario,
                         "lo que hay en la ROM no es la rutina ensamblada")
        for nombre in ("entrada", "patrones", "guardian", "identidad", "modo"):
            self.assertTrue(v["ram"] <= v[nombre] < v["ram"] + v["bytes"],
                            "%s cae en 0x%04X, fuera del bloque" % (nombre, v[nombre]))

    def test_vive_detras_de_los_bufers_de_zx0_y_antes_del_bloque_medio(self):
        """El sitio no se elige a mano: es donde acaba el segundo bufer de ZX0,
        que es lo ultimo que el cargador escribe en la zona liberada. Y tiene
        que acabar antes de 0x3F4F, donde cae el bloque medio."""
        z = self.plan["zona_libre"]
        self.assertIn("nombres", z, "la zona libre no declara la rutina de la vista")
        self.assertEqual(z["nombres"]["ram"], self.v["ram"])
        self.assertEqual(z["nombres"]["bytes"], self.v["bytes"])
        self.assertGreaterEqual(self.v["ram"], z["bufer_d"]["ram"] + z["bufer_d"]["bytes"],
                                "la rutina de la vista se solapa con el bufer de ZX0")
        self.assertLessEqual(self.v["ram"] + self.v["bytes"], self.plan["carga"]["medio"],
                             "la rutina de la vista pisa el bloque medio")
        self.assertLess(self.v["ram"] + self.v["bytes"], 0x4000,
                        "la rutina de la vista tiene que estar entera en la pagina 0")

    def test_el_plan_la_copia_exactamente_una_vez(self):
        copias = [o for o in self.plan["plan"] if o["op"] == "ROM_RAM" and o["dst"] == self.v["ram"]]
        self.assertEqual(len(copias), 1, "la rutina no se copia exactamente una vez")
        self.assertEqual(copias[0]["len"], self.v["bytes"])
        # y despues de nada que la pise: los bufers de ZX0 se usan tambien
        # DESPUES de esa copia (al repintar la imagen de carga) y acaban justo
        # donde ella empieza, asi que lo que se comprueba es que no se solapan
        z = self.plan["zona_libre"]
        for cual in ("bufer_z", "bufer_d"):
            self.assertLessEqual(z[cual]["ram"] + z[cual]["bytes"], self.v["ram"])

    def test_los_cuatro_parches_son_los_que_dice(self):
        """Tres bytes en 0x75A5, tres en 0x71A4 y tres en 0x7225 (bloque medio)
        y cuatro en 0x044B (bloque bajo), y los cuatro caen sobre lo que la
        cinta trae."""
        porque = {q["dir"]: q for q in self.v["parches"]}
        self.assertEqual(sorted(porque), [0x044B, 0x71A4, 0x7225, 0x75A5])
        q = porque[0x7225]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("cd4b73"),
                         "0x7225 tiene que ser `call MUEVE_POR_EL_MAPA`")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xCD]) + self.v["cursor"]["mueve"].to_bytes(2, "little"))
        self.assertEqual(self.medio[0x7225 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
        q = porque[0x71A4]
        self.assertEqual(q["bloque"], "medio")
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("e5e5d9"),
                         "0x71A4 tiene que empezar por `push hl / push hl / exx`")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xC3]) + self.v["cursor"]["pinta"].to_bytes(2, "little"),
                         "el parche de 0x71A4 no es un `jp` a MI_PINTA")
        self.assertEqual(self.medio[0x71A4 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
        q = porque[0x75A5]
        self.assertEqual(q["bloque"], "medio")
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("210040"),
                         "0x75A5 tiene que empezar por `ld hl,04000h`")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xC3]) + self.v["entrada"].to_bytes(2, "little"),
                         "el parche de 0x75A5 no es un `jp` a la entrada")
        self.assertEqual(self.medio[0x75A5 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
        q = porque[0x044B]
        self.assertEqual(q["bloque"], "bajo")
        self.assertEqual(q["carga"], 0x044B, "el bloque bajo corre donde cae")
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("f37dd399"),
                         "0x044B tiene que ser `di / ld a,l / out (099h),a`")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xCD]) + self.v["guardian"].to_bytes(2, "little") + bytes(1),
                         "el parche de 0x044B no es `call GUARDIAN / nop`")
        self.assertEqual(self.bajo[0x044B - 0x0190:][:4], bytes.fromhex(q["orig"]))
        for q in self.v["parches"]:
            self.assertEqual(self.rom[q["rom"]:q["rom"] + len(bytes.fromhex(q["nuevo"]))],
                             bytes.fromhex(q["nuevo"]), "el parche de 0x%04X no esta en la ROM" % q["dir"])

    def test_0x044b_es_la_unica_direccion_de_vram_del_juego(self):
        """La razon de que el guardian valga: en el bloque bajo, las unicas
        `out (099h),a` que escriben una DIRECCION son las dos de 0x044B y las
        dos de VRAM_A_LEER (0x045A), que nadie llama. Las otras dos (0x0467)
        escriben el registro 7. Y los bloques medio y alto no tocan el puerto."""
        outs = [0x0190 + i for i in range(len(self.bajo) - 1) if self.bajo[i:i + 2] == b"\xD3\x99"]
        self.assertEqual(outs, [0x044D, 0x0454, 0x045C, 0x0461, 0x0467, 0x046B])
        for bloque in (self.medio, self.alto):
            self.assertNotIn(b"\xD3\x99", bloque)
            self.assertNotIn(b"\xD3\x98", bloque)

    # ------------------------------------------------ y la rutina, EJECUTADA
    def pantalla_de_prueba(self):
        """25 filas de 34 con los 256 valores repartidos: 850 celdas por un
        numero primo con 256 pasan por todos los codigos."""
        return bytes((i * 7 + 3) & 0xFF for i in range(850))

    def test_la_rutina_deja_la_tabla_de_nombres_y_solo_eso(self):
        import corre_nombres
        m = self.monta()
        pantalla = self.pantalla_de_prueba()
        c = self.v["cursor"]
        atributos = bytes((i * 13 + 5) & 0xFF for i in range(8))
        m.ram[c["atributos"]:c["atributos"] + 8] = atributos
        vdp, z = corre_nombres.corre_vista(m, self.plan, pantalla, modo=1)
        self.assertEqual(vdp.escritos, 768 + 8, "con los patrones ya puestos van los 768 nombres y los 8 atributos del cursor")
        self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), corre_nombres.filas_de_nombres(pantalla),
                         "la tabla de nombres no es la pantalla de caracteres, 32 de cada 34")
        self.assertEqual(bytes(vdp.vram[0x1B00:0x1B08]), atributos,
                         "los dos sprites del cursor no llevan los atributos que dejo MI_PINTA")
        self.assertEqual(set(vdp.vram[:0x1800]) | set(vdp.vram[0x1B08:]), {0},
                         "la rutina ha escrito fuera de la tabla de nombres y los atributos del cursor")
        self.assertEqual(m.ram[self.v["modo"]], 1)
        self.assertIs(z.di, False, "la rutina se deja las interrupciones cerradas")

    def test_la_primera_vez_sube_los_patrones_y_los_colores_replicados(self):
        """MODO_NOMBRES a 0: antes de los nombres van los 256 patrones y sus
        colores, tres veces cada uno. Lo esperado se calcula aparte, en Python,
        de la fuente, los dibujos y la tabla de color de la cinta."""
        import corre_nombres
        m = self.monta()
        pantalla = self.pantalla_de_prueba()
        vdp, _z = corre_nombres.corre_vista(m, self.plan, pantalla, modo=0)
        self.assertEqual(vdp.escritos, 3 * 2048 + 3 * 2048 + 192 + 768 + 8)
        esperado_p = corre_nombres.patrones_esperados(m.ram)
        esperado_c = corre_nombres.colores_esperados(m.ram)
        self.assertEqual(len(esperado_p), 0x1800)
        self.assertEqual(bytes(vdp.vram[:0x1800]), esperado_p, "los patrones no son los de la fuente y los dibujos")
        self.assertEqual(bytes(vdp.vram[0x2000:0x3800]), esperado_c, "los colores no son los de la tabla de 0x0200")
        self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), corre_nombres.filas_de_nombres(pantalla))
        # y los seis planos del cursor, los de cursor.png, en la tabla de patrones de sprites
        planos = bytes.fromhex(self.v["cursor"]["planos"])
        self.assertEqual(len(planos), 192)
        self.assertEqual(bytes(vdp.vram[0x3800:0x3800 + 192]), planos, "los patrones del cursor no son los del PNG")
        self.assertEqual(set(vdp.vram[0x1B08:0x2000]) | set(vdp.vram[0x3800 + 192:]), {0})
        self.assertEqual(m.ram[self.v["modo"]], 1, "la rutina no apunta que los patrones ya estan")
        # y los tres tercios son de verdad iguales: el nombre n ensena lo mismo este donde este
        self.assertEqual(esperado_p[:0x800], esperado_p[0x800:0x1000])
        self.assertEqual(esperado_p[:0x800], esperado_p[0x1000:])
        # y la fuente va en los 128 primeros y los dibujos, sin atributo, en los otros 128
        self.assertEqual(esperado_p[:1024], bytes(m.ram[0xC800:0xCC00]))
        self.assertEqual(esperado_p[1024:1024 + 8], bytes(m.ram[0x9E00:0x9E08]))

    def test_la_variante_con_sombra_sube_solo_las_filas_que_cambian(self):
        """La sombra de 768 B (`--vista-sombra`, work/war_sombra.rom) se monta
        solo para MEDIR -no gana: ver INVESTIGACION.md-, pero si esta montada
        tiene que hacer lo que dice: la segunda vez con la misma pantalla no
        sube nada, y al cambiar cuatro celdas de dos filas sube esas dos filas
        y deja la tabla de nombres bien."""
        import corre_nombres
        rom = os.path.join(WORK, "war_sombra.rom")
        plan = os.path.join(WORK, "sombra", "plan.json")
        if not (os.path.exists(rom) and os.path.exists(plan)):
            raise unittest.SkipTest("la ROM con sombra no esta montada (make work/war_sombra.rom)")
        with open(plan) as f:
            plan = json.load(f)
        self.assertTrue(plan["vista"].get("sombra"), "ese plan no lleva la sombra")
        m = corre_nombres.monta(lee(rom), plan, self.bajo, self.alto)
        pantalla = bytearray(self.pantalla_de_prueba())
        vdp, _z = corre_nombres.corre_vista(m, plan, bytes(pantalla), modo=0)
        self.assertEqual(vdp.escritos, 3 * 2048 + 3 * 2048 + 768)
        self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), corre_nombres.filas_de_nombres(bytes(pantalla)))
        # la misma pantalla otra vez, sobre la MISMA VRAM: ni un byte
        vdp, _z = corre_nombres.corre_vista(m, plan, bytes(pantalla), modo=1, vdp=vdp)
        self.assertEqual(vdp.escritos, 0, "con la pantalla igual la sombra no deberia subir nada")
        # el cursor: cuatro celdas en las filas 10 y 11 (0x5F62 y 0x5F62+0x22)
        for o in (0x162, 0x163, 0x184, 0x185):
            pantalla[o] ^= 0x55
        vdp, _z = corre_nombres.corre_vista(m, plan, bytes(pantalla), modo=1, vdp=vdp)
        self.assertEqual(vdp.escritos, 64, "cuatro celdas en dos filas son dos filas de 32")
        self.assertEqual(sorted(d for d, _e in vdp.direcciones), [0x1800 + 10 * 32, 0x1800 + 11 * 32])
        self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), corre_nombres.filas_de_nombres(bytes(pantalla)))

    def test_el_guardian_devuelve_la_identidad_y_no_toca_nada_mas(self):
        """Lo que hace posible que el resto del juego no se entere. Con
        MODO_NOMBRES a 1, una llamada a 0x044B -la de siempre, con la direccion
        en HL- deja la tabla de nombres identidad, el modo a 0 y la direccion
        que le pidieron; con el modo a 0 no escribe ni un byte. Y en los dos
        casos BC, DE y HL salen como entraron, que sus llamadores cuentan con
        ello."""
        import corre_nombres
        c = self.v["cursor"]
        for modo, escribe in ((1, 768 + 8), (0, 0)):
            m = self.monta()
            m.ram[c["cache_valida"]] = 1
            vdp, z = corre_nombres.corre_guardian(m, self.plan, hl=0x2345, modo=modo)
            self.assertEqual(vdp.escritos, escribe, "con el modo a %d el guardian escribe %d bytes" % (modo, vdp.escritos))
            if modo:
                self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), bytes(range(256)) * 3,
                                 "el guardian no devuelve la identidad")
                # y los dos sprites del cursor, como los dejo el cargador: fuera de la pantalla
                self.assertEqual(bytes(vdp.vram[0x1B00:0x1B08]), bytes([209, 0, 0, 1, 209, 0, 1, 1]),
                                 "el guardian no esconde el cursor")
                self.assertEqual(set(vdp.vram[:0x1800]) | set(vdp.vram[0x1B08:]), {0})
                self.assertEqual(m.ram[c["cache_valida"]], 0, "el guardian tiene que invalidar la cache del trozo")
            else:
                self.assertEqual(m.ram[c["cache_valida"]], 1, "sin nada que devolver, el guardian no toca la cache")
            self.assertEqual(m.ram[self.v["modo"]], 0)
            self.assertEqual(vdp.direcciones[-1], (0x2345, True),
                             "0x044B no deja puesta la direccion de escritura que le pidieron")
            self.assertEqual((z.bc, z.de, z.hl), (0x1234, 0x5678, 0x2345), "el guardian pisa BC, DE o HL")
            self.assertIs(z.di, False, "0x044B tiene que salir con las interrupciones abiertas, como siempre")

    # ------------------------------------- MI_PINTA: la ventana fija y la cache
    # Las tres rutinas del juego que MI_PINTA llama (CELDA_DEL_MAPA,
    # DIBUJA_EL_TROZO_DE_MAPA, TAPA_LOS_BORDES) van sustituidas por trampas que
    # apuntan con que se las llamo: lo que se comprueba es lo que MI_PINTA hace
    # alrededor de ellas, que es lo nuevo.
    ESQUINA = (32, 29)          # donde entra el cursor en la partida de la sonda

    def pinta(self, hl, modo=0x10, **estado):
        import corre_nombres
        m = corre_nombres.monta(self.rom, self.plan, self.bajo, self.alto, medio=self.medio)
        z = corre_nombres.corre_pinta(m, self.plan, hl, modo, **estado)
        return m, z

    def cache_de_prueba(self):
        return bytes((i * 11 + 1) & 0xFF for i in range(850))

    def con_cache(self, hl, modo=0x10, esquina=ESQUINA, ultimo_modo=0x10):
        return self.pinta(hl, modo, cache_valida=1, esquina=esquina, ultimo_modo=ultimo_modo,
                          cache=self.cache_de_prueba())

    def test_sin_cache_repinta_como_el_original_y_la_guarda(self):
        """Entra por el `jp` de 0x71A4. Sin cache valida hace lo que hacia
        0x71A7-0x71C5: la pantalla a 0x80, CELDA_DEL_MAPA con la fila mas
        uno, la esquina 720 bytes atras, el trozo, los bordes con el HL de
        verdad; y ademas guarda la pantalla en la cache y apunta la esquina."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.ESQUINA
        m, z = self.pinta((h << 8) | l)
        self.assertEqual([d for d, _ in z.llamadas],
                         [corre_nombres.CELDA_DEL_MAPA, corre_nombres.DIBUJA_EL_TROZO, corre_nombres.TAPA_LOS_BORDES])
        self.assertEqual(z.llamadas[0][1], ("hl", ((h + 1) << 8) | l), "CELDA_DEL_MAPA va con la fila mas uno, como en 0x71B5")
        self.assertEqual(z.llamadas[1][1], ("ix", (corre_nombres.celda_del_mapa(h + 1, l) - 720) & 0xFFFF),
                         "la esquina del trozo no esta 7 columnas y 6 filas atras")
        self.assertEqual(z.llamadas[2][1], ("hl", (h << 8) | l), "TAPA_LOS_BORDES quiere el HL de verdad")
        self.assertEqual(z.hl, (h << 8) | l, "MI_PINTA tiene que devolver HL intacto")
        pantalla = bytes(m.ram[0x5E00:0x5E00 + 850])
        self.assertEqual(bytes(m.ram[c["cache"]:c["cache"] + 850]), pantalla, "la cache no es la pantalla recien pintada")
        self.assertEqual(m.ram[c["cache_valida"]], 1)
        self.assertEqual((m.ram[c["esquina_h"]], m.ram[c["esquina_l"]]), (h, l))
        self.assertEqual(m.ram[c["ultimo_modo"]], 0x10)
        self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                         corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10),
                         "recien repintado, el cursor cae en la celda (7, 5) de la ventana")

    def test_la_pantalla_se_pone_a_0x80_antes_de_pintar(self):
        """Con una trampa que solo pinta la mitad de las celdas se ve el
        relleno de 0x71A7 en la otra mitad."""
        import corre_nombres
        m = corre_nombres.monta(self.rom, self.plan, self.bajo, self.alto, medio=self.medio)
        trampas = corre_nombres.trampas_del_juego(relleno=lambda ix, o: 0x90 if o % 2 else None)
        m.ram[corre_nombres.MODO_DE_LA_VISTA] = 0x10
        z = corre_nombres.Z80(m, corre_nombres.Vdp(), corre_nombres.PINTA_LA_VISTA, 0x5BFF, trampas)
        z.hl = 0x201D
        z.push(corre_nombres.CENTINELA)
        z.corre()
        pantalla = bytes(m.ram[0x5E00:0x5E00 + 850])
        self.assertEqual(pantalla, bytes(0x90 if o % 2 else 0x80 for o in range(850)))

    def test_con_cache_no_repinta_y_restaura_el_trozo(self):
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.ESQUINA
        m, z = self.con_cache(((h + 1) << 8) | (l + 1))
        self.assertEqual(z.llamadas, [], "con la cache valida y el cursor dentro no se llama a nadie")
        self.assertEqual(bytes(m.ram[0x5E00:0x5E00 + 850]), self.cache_de_prueba(), "la pantalla no es la cache")
        self.assertEqual((m.ram[c["esquina_h"]], m.ram[c["esquina_l"]]), (h, l), "la esquina no se mueve")
        self.assertEqual(z.hl, ((h + 1) << 8) | (l + 1))
        self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                         corre_nombres.atributos_esperados(self.plan, 8, 6, 0x10))

    def test_el_margen_es_de_tres_celdas_por_los_cuatro_lados(self):
        """Ventana de 16 x 13 con el cursor en (7, 5): sin repintar de la
        columna 3 a la 12 y de la fila 3 a la 9. Una mas alla, se repinta y la
        esquina pasa a ser la posicion nueva."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.ESQUINA
        for dh, dl, repinta in ((0, -4, False), (0, -5, True), (0, 5, False), (0, 6, True),
                                (-2, 0, False), (-3, 0, True), (4, 0, False), (5, 0, True),
                                (4, 5, False), (-2, -4, False), (5, 6, True)):
            hl = ((h + dh) << 8) | (l + dl)
            m, z = self.con_cache(hl)
            self.assertEqual(bool(z.llamadas), repinta,
                             "con el cursor en (%+d, %+d) %s" % (dh, dl, "tenia que repintar" if repinta else "no habia que repintar"))
            if repinta:
                self.assertEqual((m.ram[c["esquina_h"]], m.ram[c["esquina_l"]]), (h + dh, l + dl))
                self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                                 corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10))
            else:
                self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                                 corre_nombres.atributos_esperados(self.plan, 7 + dl, 5 + dh, 0x10))

    def test_repinta_si_cambia_el_modo_o_la_cache_no_vale(self):
        h, l = self.ESQUINA
        hl = (h << 8) | l
        _m, z = self.con_cache(hl, modo=0x12, ultimo_modo=0x10)
        self.assertEqual(len(z.llamadas), 3, "al cambiar de modo hay que repintar: el trozo lleva la marca de la orden")
        _m, z = self.pinta(hl, cache_valida=0, esquina=self.ESQUINA, ultimo_modo=0x10, cache=self.cache_de_prueba())
        self.assertEqual(len(z.llamadas), 3, "con la cache invalidada (el guardian) hay que repintar")

    def test_las_banderas_del_bit_7_no_cuentan(self):
        import corre_nombres
        h, l = self.ESQUINA
        m, z = self.con_cache(((h | 0x80) << 8) | (l | 0x80))
        self.assertEqual(z.llamadas, [], "el bit 7 de H y L son banderas: no mueven el cursor")
        self.assertEqual(bytes(m.ram[self.v["cursor"]["atributos"]:][:8]),
                         corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10))

    def test_el_patron_y_el_color_van_con_el_modo(self):
        """0x10 mirar, 0x12 destino y 0x17 batalla: dos planos de 16x16 cada
        uno (patrones 0/4, 8/12 y 16/20) con los colores de cursor.png."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.ESQUINA
        for modo, n in ((0x10, 0), (0x12, 1), (0x17, 2)):
            m, _z = self.con_cache((h << 8) | l, modo=modo, ultimo_modo=modo)
            a = bytes(m.ram[c["atributos"]:c["atributos"] + 8])
            self.assertEqual(a, corre_nombres.atributos_esperados(self.plan, 7, 5, modo))
            self.assertEqual((a[2], a[6]), (n * 8, n * 8 + 4))
            self.assertEqual((a[3], a[7]), tuple(c["planos_colores"][n * 2:n * 2 + 2]))
            self.assertEqual((a[0], a[1]), (79, 112), "la celda (7, 5) son 16 pixels por celda, y Y una linea por encima")

    def test_el_plan_pone_los_sprites_de_16x16(self):
        """El juego nunca escribe R1: lo que deje el cargador se queda."""
        self.assertEqual(self.plan["vdp_regs"][1], 0xE2)
        ultimo_r1 = [o for o in self.plan["plan"] if o["op"] == "VDP_REG" and o["b"] == 1][-1]
        self.assertEqual(ultimo_r1["src"] & 0xFF, 0xE2)
        self.assertEqual(self.v["cursor"]["r1"], 0xE2)

    def test_los_dibujos_de_la_rom_son_los_del_png(self):
        """Lo que viaja en la ROM (CURSOR_PATRONES y CURSOR_COLORES) es lo que
        sale de leer src/cartucho/cursor.png ahora mismo."""
        import cursor
        c = self.v["cursor"]
        patrones, colores, _avisos = cursor.planos_del_png(os.path.join(RAIZ, c["png"]))
        self.assertEqual(bytes.fromhex(c["planos"]), patrones)
        self.assertEqual(bytes(c["planos_colores"]), colores)
        m = self.monta()
        self.assertEqual(bytes(m.ram[c["patrones"]:c["patrones"] + 192]), patrones)
        self.assertEqual(bytes(m.ram[c["colores"]:c["colores"] + 6]), colores)
        self.assertEqual(c["colores"] - c["patrones"], 192)

    def test_el_paso_del_cursor_es_una_casilla_cada_diez_cuadros(self):
        """MI_MUEVE: con una direccion pulsada solo se mueve si han pasado
        PASO cuadros desde el ultimo paso; sin direccion, el contador se deja
        listo para que la siguiente pulsacion mueva al instante."""
        import corre_nombres
        c = self.v["cursor"]
        self.assertEqual(c["paso"], 10)
        m = self.monta()
        z = corre_nombres.corre_mueve(m, self.plan, 0x201D, 0x10, cuadros=100, ultimo=95)
        self.assertEqual(z.llamadas, [], "sin direccion no se mueve")
        self.assertEqual(m.ram[c["ultimo_paso"]], 90, "sin direccion el contador queda a un paso de distancia")
        m = self.monta()
        z = corre_nombres.corre_mueve(m, self.plan, 0x201D, 0x08, cuadros=100, ultimo=91)
        self.assertEqual(z.llamadas, [], "a nueve cuadros del ultimo paso, todavia no")
        self.assertEqual(m.ram[c["ultimo_paso"]], 91)
        m = self.monta()
        z = corre_nombres.corre_mueve(m, self.plan, 0x201D, 0x18, cuadros=100, ultimo=90)
        self.assertEqual(z.llamadas, [(corre_nombres.MUEVE_POR_EL_MAPA, ("a_hl", (0x18, 0x201D)))],
                         "a diez cuadros se mueve, con el mando entero y la posicion")
        self.assertEqual(m.ram[c["ultimo_paso"]], 100)
        m = self.monta()
        z = corre_nombres.corre_mueve(m, self.plan, 0x201D, 0x01, cuadros=4, ultimo=250)
        self.assertEqual(len(z.llamadas), 1, "el contador da la vuelta: de 250 a 4 son diez cuadros")

    def test_el_atributo_del_texto_se_lee_del_juego(self):
        """0x763F es 0x78 en la cinta y 0x70 con el parche de Araubi: los
        colores de la fuente tienen que salir de ahi, no de una constante."""
        import corre_nombres
        for atributo in (0x78, 0x70):
            m = self.monta()
            m.ram[0x763F] = atributo
            vdp, _z = corre_nombres.corre_vista(m, self.plan, self.pantalla_de_prueba(), modo=0)
            color = m.ram[0x0200 + atributo]
            self.assertEqual(set(vdp.vram[0x2000:0x2400]), {color}, "el color de la fuente no es el del atributo 0x%02X" % atributo)
            self.assertEqual(bytes(vdp.vram[0x2000:0x3800]), corre_nombres.colores_esperados(m.ram))

    def test_la_cache_y_las_variables_caben_en_el_bloque(self):
        c = self.v["cursor"]
        for nombre in ("pinta", "cache", "cache_valida", "ultimo_modo", "esquina_h", "esquina_l",
                       "atributos", "patrones", "colores"):
            self.assertTrue(self.v["ram"] <= c[nombre] < self.v["ram"] + self.v["bytes"],
                            "%s cae en 0x%04X, fuera del bloque" % (nombre, c[nombre]))
        self.assertLessEqual(c["cache"] + 850, self.v["ram"] + self.v["bytes"])


class TestZX0(unittest.TestCase):
    """El compresor, que es de donde sale el hueco de la ROM.

    Lo que se comprueba aqui no es el formato -ese es de Einar Saukas y esta
    probado por media escena- sino las dos cosas que SI pueden salir mal aqui:
    que la traduccion de su ensamblador a la sintaxis de pasmo sigue siendo el
    mismo programa, y que cada bloque de la ROM devuelve exactamente lo que
    venia en la cinta.
    """

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)

    def test_el_descompresor_son_los_68_bytes_del_original(self):
        """La version "Standard" de dzx0 son 68 bytes y asi lo dice su cabecera.
        Si la traduccion a pasmo hubiera cambiado una instruccion, esto cantaria
        antes de que nadie tuviera que mirar una pantalla."""
        import zx0
        self.assertEqual(len(zx0.dzx0_binario()), 68)

    def test_cada_bloque_de_la_rom_devuelve_lo_que_traia_la_cinta(self):
        """La ida y vuelta, bloque a bloque, contra los cuerpos de la cinta.

        Comprime el C de Einar Saukas y descomprime su ensamblador, ejecutado en
        el interprete: dos implementaciones distintas del mismo formato, que es
        lo que hace que esto valga como comprobacion y no como tautologia."""
        pantalla = lee(os.path.join(WORK, "pantalla.raw"))
        bajo = lee(os.path.join(WORK, "bajo.raw"))
        esperado = {"patrones": pantalla[100:100 + 6144],
                    "colores": pantalla[100 + 6144:100 + 12288],
                    "final0": bajo[0x094F - 0x0190:][:6912],
                    "final1": bajo[0x244F - 0x0190:][:6912]}
        comprimidos = [n for n, d in self.plan["datos"].items() if d.get("zx0")]
        self.assertEqual(sorted(comprimidos), sorted(esperado),
                         "no estan comprimidos los cuatro bloques que se esperaba")
        for nombre in comprimidos:
            d = self.plan["datos"][nombre]
            salido = descomprime_desde(self.rom, d["rom"])
            self.assertEqual(len(salido), d["crudo"], "%s: sale otro tamano" % nombre)
            self.assertEqual(salido, esperado[nombre], "%s: no devuelve lo de la cinta" % nombre)

    def test_zx0_encoge_mas_que_el_rle_que_habia_antes(self):
        """La razon del cambio, comprobada y no supuesta. Si algun dia dejara de
        ser cierto para algun bloque, aqui se veria: el RLE de marca sigue en
        tools/comprime.py precisamente para poder medirlo."""
        from comprime import comprime as rle
        pantalla = lee(os.path.join(WORK, "pantalla.raw"))
        crudos = {"patrones": pantalla[100:100 + 6144],
                  "colores": pantalla[100 + 6144:100 + 12288]}
        for nombre, datos in crudos.items():
            con_rle = len(rle(datos)[0])
            con_zx0 = self.plan["datos"][nombre]["bytes"]
            self.assertLess(con_zx0, con_rle,
                            "%s: ZX0 da %d y el RLE %d" % (nombre, con_zx0, con_rle))

    def test_el_stub_y_la_rutina_llevan_cada_uno_su_copia_del_descompresor(self):
        """Y tiene que ser asi: el stub de 0xD800 descomprime al cargar, pero en
        tiempo de juego puede estar pisado, asi que la rutina de las finales no
        puede llamarlo y lleva la suya. Son 68 bytes repetidos a proposito."""
        import zx0
        # OJO: dzx0 NO es reubicable -sus dos `call dzx0s_elias` llevan la
        # direccion absoluta dentro-, asi que las dos copias NO son iguales byte
        # a byte. Hay que ensamblarlo en el org de cada una, y ese org sale del
        # .sym, no de contarlo a mano.
        for fichero in ("cargador_ram", "finales"):
            simbolos = {}
            with open(os.path.join(WORK_MUSICA, fichero + ".sym")) as f:
                for linea in f:
                    m = re.match(r"(\w+)\s+EQU\s+0?([0-9A-Fa-f]+)H", linea.strip())
                    if m:
                        simbolos[m.group(1)] = int(m.group(2), 16)
            self.assertIn("dzx0_standard", simbolos,
                          "%s no lleva el descompresor dentro" % fichero)
            copia = zx0.dzx0_binario(simbolos["dzx0_standard"])
            self.assertEqual(len(copia), 68)
            with open(os.path.join(WORK_MUSICA, fichero + ".bin"), "rb") as f:
                binario = f.read()
            self.assertIn(copia, binario,
                          "el descompresor de %s no es el de src/cartucho/dzx0.asm" % fichero)
            self.assertIn(copia, self.rom, "esa copia no ha llegado a la ROM")


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
