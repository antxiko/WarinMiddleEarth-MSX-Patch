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
CUERPOS_PARCHE = os.path.join(WORK, "cuerpos_parche")


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
        la musica, el de las pantallas finales, los siete de la vista y el del
        mapa ya dibujado. Vienen del plan, no de una lista escrita aqui, para
        que no puedan quedarse viejos."""
        todos = list((self.musica or {}).get("parches", []))
        if self.plan.get("finales"):
            todos.append(self.plan["finales"]["parche"])
        if self.plan.get("mapa"):
            todos.append(self.plan["mapa"]["parche"])
        todos += self.plan.get("panel", {}).get("parches", [])
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

        if "mapa" in self.plan["datos"]:
            # El mapa general no viene de la cinta hecho: se dibuja al montar
            # la ROM con las rutinas del juego transcritas, y lo que se exige
            # es que al descomprimirlo salga EXACTAMENTE eso.
            import mapa_general
            esperado["mapa"] = mapa_general.dibuja_el_mapa(self.CUERPOS)
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
    """Y otra vez sobre war_unificada.rom: la cinta PARCHEADA de Araubi
    con la musica, ZX0, las finales en la ROM y la vista con el cursor como
    sprite. Es el cartucho que se juega, asi que tiene que cumplir lo mismo,
    con los cuerpos de la cinta parcheada (work/cuerpos_parche)."""
    ROM = os.path.join(RAIZ, "war_unificada.rom")
    DERIVADOS = os.path.join(WORK, "unificada")
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
        if self.plan.get("mapa"):
            todos.append(self.plan["mapa"]["parche"])
        todos += self.plan.get("panel", {}).get("parches", [])
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
        mapa = self.plan.get("mapa")
        if mapa:
            # El mapa ya dibujado no viaja a la RAM: se descomprime cuando el
            # juego lo pide. Lo unico que cambia son los tres bytes del parche.
            q = mapa["parche"]
            self.assertEqual(len(bytes.fromhex(q["nuevo"])), 3,
                             "el parche del mapa son los tres bytes del `ld hl,04000h` de 0x816B")
            permitidos.update(range(q["carga"], q["carga"] + 3))
        panel = self.plan.get("panel")
        if panel:
            # El color del panel son bytes sueltos del bloque medio, uno por
            # sitio. En la cinta original no hay ninguno: el panel ya lleva el
            # atributo de la vista.
            for q in panel["parches"]:
                self.assertEqual(len(bytes.fromhex(q["nuevo"])), 1,
                                 "los parches del panel son de un byte")
                permitidos.add(q["carga"])
        vista = self.plan.get("vista")
        if vista:
            # La rutina de la vista, en la misma zona liberada, y sus QUINCE
            # parches: cincuenta y cuatro bytes, cincuenta del bloque medio y
            # cuatro del bajo. Los dos del guante del mapa general; el de
            # 0x8DE4 -la fuerza de la tropa- que se lleva trece el solo, porque
            # sustituye el calculo entero por un salto y un `call MI_FUERZA`; y
            # los SIETE de la batalla (0x8828, 0x8849, 0x884C, 0x90A6, 0x914B,
            # 0x9160 y 0x8E10), tres bytes cada uno, que le quitan a cada vuelta
            # la subida de la pantalla entera, arreglan al infiltrado del
            # centro, ponen la tecla F y atan el cursor al reloj.
            permitidos.update(range(vista["ram"], vista["ram"] + vista["bytes"]))
            de_la_vista = set()
            for q in vista["parches"]:
                de_la_vista.update(range(q["carga"], q["carga"] + len(bytes.fromhex(q["nuevo"]))))
            self.assertEqual(len(de_la_vista), 54,
                             "los parches de la vista tienen que ser cincuenta y cuatro bytes")
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


class TestElMapaGeneral(unittest.TestCase):
    """El mapa general ya dibujado (--mapa): tools/mapa_general.py lo dibuja al
    montar la ROM y finales.asm lo descomprime cuando el juego lo pide.

    Lo fuerte, como en las finales, es que la rutina se EJECUTA: lo que se
    compara no es "el bloque comprimido es el que se metio" sino que al
    DESCOMPRIMIRLO con el descompresor del propio cartucho sale exactamente el
    lienzo que sale de transcribir las rutinas del juego. Y ese lienzo, a su
    vez, esta cotejado byte a byte con el del emulador (`make verifica_mapa`).
    """

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)
        if "mapa" not in self.plan:
            raise unittest.SkipTest("esta ROM no lleva el mapa ya dibujado (--mapa)")
        self.q = self.plan["mapa"]
        self.medio = lee(os.path.join(WORK, "medio.raw"))

    def dibujado(self):
        import mapa_general
        return mapa_general.dibuja_el_mapa(WORK)

    def corre(self, **kw):
        import corre_finales
        return corre_finales.descomprime_el_mapa(self.rom, self.plan, **kw)

    def test_el_parche_es_el_ld_hl_del_ldir_que_borraba_el_lienzo(self):
        """Tres bytes en 0x816B, y ni uno mas del juego. El `ldir` que ponia
        0x4000-0x5AFF a cero sobraba: BORRA_PANTALLA, dos instrucciones mas
        alla, borra ese mismo tramo."""
        q = self.q["parche"]
        self.assertEqual(q["dir"], 0x816B)
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("210040"),
                         "0x816B tiene que ser el `ld hl,04000h` del `ldir`")
        nuevo = bytes.fromhex(q["nuevo"])
        self.assertEqual(len(nuevo), 3)
        self.assertEqual(nuevo[0], 0xC3, "el parche no es un `jp`")
        self.assertEqual(nuevo[1] | (nuevo[2] << 8), self.q["entrada"],
                         "el `jp` no apunta a la entrada de la rutina")
        self.assertEqual(self.medio[q["dir"] - 0x5E00:][:3], bytes.fromhex(q["orig"]),
                         "en la cinta, 0x816B no es lo que el parche dice sustituir")
        self.assertEqual(self.rom[q["rom"]:q["rom"] + 3], nuevo)

    def test_el_lienzo_que_descomprime_es_el_que_se_dibujo(self):
        """EL TEST QUE DECIDE. Se ejecuta la rutina del cartucho y lo que deja
        en 0x4000 -que es de donde 0x05BD sube el bitmap al VDP- tiene que ser,
        byte a byte, lo que sale de transcribir PINTA_TERRENO_ALTO y
        PINTA_TERRENO_BAJO sobre el mapa de la cinta."""
        m, _z = self.corre()
        self.assertEqual(bytes(m.ram[0x4000:0x5800]), self.dibujado(),
                         "el lienzo que sale de la ROM no es el que se dibujo")

    def test_no_se_pasa_del_lienzo(self):
        """6.144 bytes y ni uno mas: encima estan los 768 atributos y, detras,
        la pila del juego en 0x5BFF."""
        m, z = self.corre()
        self.assertEqual(z.de, 0x4000 + 0x1800,
                         "la rutina deja DE en 0x%04X: ha escrito %d bytes y no 6144"
                         % (z.de, z.de - 0x4000))
        self.assertEqual(set(m.ram[0x5800:0x5BF0]), {0},
                         "la rutina se mete en los atributos o mas alla")

    def test_nunca_toca_la_pila_con_el_cartucho_en_la_pagina_1(self):
        """Lo mismo que con las finales, y por lo mismo: la pila vive en
        0x5BFF, en la pagina que hay que conmutar para escribir el registro del
        mapper. Ahora las dos entradas comparten esa rutina."""
        m, _z = self.corre()
        self.assertEqual(m.pila_con_cartucho, [])
        self.assertEqual(m.escrituras_perdidas, [])

    def test_devuelve_las_paginas_y_el_banco_como_estaban(self):
        m, z = self.corre()
        self.assertEqual(m.a8, m.ranura_ram * 0b01010101,
                         "las paginas no quedan como estaban: 0xA8 = 0x%02X" % m.a8)
        self.assertEqual(m.banco_8000, self.plan["finales"]["banco_vuelve"])
        self.assertIs(z.di, False, "la rutina se deja las interrupciones cerradas")

    def test_vale_este_el_cartucho_en_la_ranura_que_este(self):
        esperado = self.dibujado()
        for cart in range(4):
            for ram in range(4):
                if cart == ram:
                    continue
                m, _z = self.corre(ranura_cart=cart, ranura_ram=ram)
                self.assertEqual(bytes(m.ram[0x4000:0x5800]), esperado,
                                 "con el cartucho en la ranura %d y la RAM en la %d sale otra cosa"
                                 % (cart, ram))
                self.assertEqual(m.pila_con_cartucho, [])

    def test_encoge_y_no_viaja_a_la_ram(self):
        """Lo que justifica el cambio: 6.144 bytes que ya no se recorren, y de
        ROM cuesta menos de la mitad. Y no ocupa ni un byte de RAM mientras no
        se pide: se descomprime encima del lienzo, que es su sitio."""
        self.assertEqual(self.q["crudo"], 6144)
        self.assertTrue(self.q["zx0"])
        self.assertLess(self.q["bytes"], self.q["crudo"] // 2)
        self.assertEqual(self.q["destino"], 0x4000)
        for o in self.plan["plan"]:
            self.assertNotEqual(o.get("src"), self.q["src"],
                                "el plan de carga copia el mapa a la RAM, y no hace falta")

    def test_las_dos_cintas_dibujan_el_mismo_mapa(self):
        """El parche de Araubi cambia textos, tiles y la ficha, pero no el mapa:
        las dos cintas tienen que dar el mismo lienzo. Si algun dia lo tocara,
        esto lo diria en vez de que la ROM parcheada llevara un mapa viejo."""
        import mapa_general
        if not os.path.isdir(CUERPOS_PARCHE):
            raise unittest.SkipTest("no estan los cuerpos de la cinta parcheada")
        self.assertEqual(mapa_general.dibuja_el_mapa(CUERPOS_PARCHE), self.dibujado())


class TestElPanelDelMapa(unittest.TestCase):
    """El panel File/Memo/Time con el color de la vista (--panel).

    No es un byte: son TRES, porque el atributo del panel es lo que el juego
    usa para reconocerlo -0x7F99 para saber si el disparo cae ahi y 0x6AB5 para
    respetarlo al limpiar los atributos-, y un CUARTO porque el atributo de la
    vista en la cinta parcheada (0x70) es el mismo con el que se marca donde
    hay una unidad. Se prueba sobre las DOS cintas: en la original el panel ya
    lleva el atributo de la vista y no se cambia nada."""

    ROM = ROM_MUSICA
    DERIVADOS = WORK_MUSICA
    CUERPOS = WORK

    def setUp(self):
        plan = os.path.join(self.DERIVADOS, "plan.json")
        hace_falta(self.ROM, plan)
        self.rom = lee(self.ROM)
        with open(plan) as f:
            self.plan = json.load(f)
        if "panel" not in self.plan:
            raise unittest.SkipTest("esta ROM no lleva el color del panel (--panel)")
        self.q = self.plan["panel"]
        self.medio = lee(os.path.join(self.CUERPOS, "medio.raw"))

    def test_el_atributo_sale_de_la_vista_y_no_de_una_constante(self):
        """Si se escribiera a mano, en una de las dos cintas estaria mal."""
        self.assertEqual(self.q["de_donde"], 0x763F)
        self.assertEqual(self.q["atributo"], self.medio[0x763F - 0x5E00],
                         "el atributo del panel no es el del texto de la vista")

    def test_la_marca_de_unidad_se_aparta_solo_si_choca(self):
        """0x70 es el atributo de la marca de unidad. Si el panel se lo queda,
        la marca tiene que irse al que el panel deja libre; si no, quedarse."""
        if self.q["atributo"] == self.q["marca_orig"]:
            self.assertEqual(self.q["marca"], self.q["orig"],
                             "el panel se queda el 0x70 y la marca no se aparta: se pisarian")
        else:
            self.assertEqual(self.q["marca"], self.q["marca_orig"],
                             "sin colision, la marca de unidad no tiene por que moverse")
        self.assertNotEqual(self.q["marca"], self.q["atributo"],
                            "el panel y la marca de unidad no pueden llevar el mismo atributo")
        self.assertNotEqual(self.q["atributo"], 0x30,
                            "el panel no puede llevar el atributo del fondo del mapa")

    def test_los_tres_sitios_del_panel_van_juntos(self):
        """El que lo escribe, el que lo reconoce y el que lo respeta. Si uno se
        quedara atras, los paneles dejarian de responder o perderian el color
        en el primer repintado."""
        porque = {q["dir"]: q for q in self.q["parches"]}
        if not porque:
            self.assertEqual(self.q["atributo"], self.q["orig"],
                             "sin parches, el panel tenia que llevar ya el atributo de la vista")
            return
        self.assertEqual(sorted(porque), [0x6AB6, 0x6AE1, 0x7F9A, 0x8167])
        for dir_ in (0x8167, 0x7F9A, 0x6AB6):
            q = porque[dir_]
            self.assertEqual(bytes.fromhex(q["orig"]), bytes([self.q["orig"]]),
                             "en 0x%04X no estaba el atributo viejo del panel" % dir_)
            self.assertEqual(bytes.fromhex(q["nuevo"]), bytes([self.q["atributo"]]))
        q = porque[0x6AE1]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes([self.q["marca_orig"]]))
        self.assertEqual(bytes.fromhex(q["nuevo"]), bytes([self.q["marca"]]))
        # y caen sobre lo que la cinta trae, y llegan a la ROM
        for dir_, q in porque.items():
            self.assertEqual(self.medio[dir_ - 0x5E00:dir_ - 0x5E00 + 1], bytes.fromhex(q["orig"]),
                             "en la cinta, 0x%04X no es lo que el parche dice sustituir" % dir_)
            self.assertEqual(self.rom[q["rom"]:q["rom"] + 1], bytes.fromhex(q["nuevo"]))


class TestElPanelDelMapaParche(TestElPanelDelMapa):
    """Y sobre la cinta PARCHEADA, que es donde el cambio se nota: ahi la vista
    va en 0x70 y el panel estaba en 0x78."""

    ROM = os.path.join(RAIZ, "war_unificada.rom")
    DERIVADOS = os.path.join(WORK, "unificada")
    CUERPOS = CUERPOS_PARCHE

    def test_en_esta_cinta_si_cambia(self):
        self.assertEqual(self.q["atributo"], 0x70, "la cinta parcheada escribe la vista en 0x70")
        self.assertEqual(len(self.q["parches"]), 4, "en esta cinta son cuatro bytes")


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

    def test_los_quince_parches_son_los_que_dice(self):
        """Tres bytes en 0x75A5, tres en 0x71A4, tres en 0x7225, tres en
        0x7758, tres en 0x7F57, uno en 0x6575 y trece en 0x8DE4 (bloque medio)
        y cuatro en 0x044B (bloque bajo); y los SIETE DE LA BATALLA, tres cada
        uno: 0x8828 (cada ficha que cambia se sube sola), 0x8849 (el tablero
        entero, solo la primera vuelta), 0x884C (fuera los atributos de cada
        vuelta), 0x90A6 (al montarla se apunta que esta sin subir), 0x914B (el
        infiltrado del centro), 0x9160 (la tecla F) y 0x8E10 (el cursor, al
        paso del reloj). Los quince caen sobre lo que la cinta trae."""
        porque = {q["dir"]: q for q in self.v["parches"]}
        self.assertEqual(sorted(porque),
                         [0x044B, 0x6575, 0x71A4, 0x7225, 0x75A5, 0x7758, 0x7F57,
                          0x8828, 0x8849, 0x884C, 0x8DE4, 0x8E10, 0x90A6, 0x914B, 0x9160])
        # EL CURSOR DE LA BATALLA: su `call LEE_LOS_MANDOS`, por MI_CURSOR_BATALLA.
        q = porque[0x8E10]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("cd6d06"),
                         "0x8E10 tiene que ser `call LEE_LOS_MANDOS` (0x066D)")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xCD]) + self.v["cursor"]["batalla"].to_bytes(2, "little"))
        self.assertEqual(self.medio[0x8E10 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
        # LA BATALLA. Los tres `call` y el `ld hl,(nn)` que se sustituyen, y el
        # de los atributos que se va a nops.
        for d, orig in ((0x8828, "2adc87"), (0x8849, "cdbd05"),
                        (0x884C, "cd0406"), (0x90A6, "cd0406")):
            self.assertEqual(bytes.fromhex(porque[d]["orig"]), bytes.fromhex(orig),
                             "0x%04X no es lo que la cinta trae" % d)
        self.assertEqual(bytes.fromhex(porque[0x884C]["nuevo"]), bytes(3),
                         "los atributos de cada vuelta se quitan con tres nops")
        for d in (0x8828, 0x8849, 0x90A6):
            self.assertEqual(bytes.fromhex(porque[d]["nuevo"])[0], 0xCD,
                             "0x%04X tiene que quedar en un call" % d)
        # LA FUERZA DE LA TROPA. El calculo roto de 0x8DE4 pasa a ser un `jr`
        # que se salta los ocho bytes donde vive el operando del terreno -que no
        # puede ejecutarse- y un `call MI_FUERZA` en los tres ultimos.
        q = porque[0x8DE4]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("878787c647f6006fce6d95677e"),
                         "0x8DE4 tiene que ser el calculo original de FUERZA_DE_LA_TROPA")
        nuevo = bytes.fromhex(q["nuevo"])
        self.assertEqual(len(nuevo), 13)
        self.assertEqual(nuevo[:2], bytes([0x18, 0x08]),
                         "el parche empieza con un `jr` que salta ocho bytes")
        self.assertEqual(nuevo[2:10], bytes(8),
                         "los ocho bytes saltados van a cero: ahi escribe 0x902F el terreno")
        self.assertEqual(nuevo[10], 0xCD, "y los tres ultimos son un `call`")
        destino = int.from_bytes(nuevo[11:13], "little")
        self.assertTrue(self.v["ram"] <= destino < self.v["ram"] + self.v["bytes"],
                        "MI_FUERZA tiene que caer dentro de la rutina de la vista")
        self.assertEqual(self.medio[0x8DE4 - 0x5E00:][:13], bytes.fromhex(q["orig"]))
        # EL GUANTE. El bucle de partida llama a MI_GUANTE en vez de subir un
        # recuadro de 4x3 celdas, y MUEVE_EL_CURSOR deja de estamparlo.
        g = self.v["guante"]
        q = porque[0x7F57]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("cdc307"),
                         "0x7F57 tiene que ser `call REFRESCA_EL_CURSOR` (0x07C3)")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xCD]) + g["entrada"].to_bytes(2, "little"))
        self.assertEqual(self.medio[0x7F57 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
        q = porque[0x6575]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("e5"),
                         "0x6575 tiene que ser el `push hl` con el que empieza el estampado")
        self.assertEqual(bytes.fromhex(q["nuevo"]), bytes([0xC9]), "0x6575 tiene que pasar a ser un `ret`")
        self.assertEqual(self.medio[0x6575 - 0x5E00:][:1], bytes.fromhex(q["orig"]))
        q = porque[0x7758]
        self.assertEqual(bytes.fromhex(q["orig"]), bytes.fromhex("cd6d06"),
                         "0x7758 tiene que ser `call LEE_LOS_MANDOS` (0x066D)")
        self.assertEqual(bytes.fromhex(q["nuevo"]),
                         bytes([0xCD]) + self.v["cursor"]["eleccion"].to_bytes(2, "little"))
        self.assertEqual(self.medio[0x7758 - 0x5E00:][:3], bytes.fromhex(q["orig"]))
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
        self.assertEqual(vdp.escritos, 3 * 2048 + 3 * 2048 + 192 + 768 + 8,
                         "patrones y colores en tres tercios, los 192 de patrones del cursor, los 768 nombres y los 8 atributos")
        self.assertEqual(bytes(vdp.vram[0x1800:0x1B00]), corre_nombres.filas_de_nombres(bytes(pantalla)))
        # la misma pantalla otra vez, sobre la MISMA VRAM: ni un byte
        vdp, _z = corre_nombres.corre_vista(m, plan, bytes(pantalla), modo=1, vdp=vdp)
        self.assertEqual(vdp.escritos, 8, "con la pantalla igual la sombra solo sube los 8 atributos del cursor")
        # el cursor: cuatro celdas en las filas 10 y 11 (0x5F62 y 0x5F62+0x22)
        for o in (0x162, 0x163, 0x184, 0x185):
            pantalla[o] ^= 0x55
        vdp, _z = corre_nombres.corre_vista(m, plan, bytes(pantalla), modo=1, vdp=vdp)
        self.assertEqual(vdp.escritos, 64 + 8, "cuatro celdas en dos filas son dos filas de 32, y los 8 atributos")
        self.assertEqual(sorted(d for d, _e in vdp.direcciones), [0x1800 + 10 * 32, 0x1800 + 11 * 32, 0x1B00])
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

    # ------------------------------------------ EL GUANTE DEL MAPA GENERAL
    def test_el_guante_sale_del_png_y_conserva_la_silueta_de_la_cinta(self):
        """Los dos planos que van en la ROM son los del PNG, y el PNG ensena la
        misma SILUETA que la cinta estampa: relleno donde el dibujo no tiene bit
        y la mascara tampoco, trazo donde el dibujo tiene bit, y nada donde la
        mascara deja ver el fondo.

        El COLOR no se exige, que para eso el PNG es editable: el guante era
        amarillo y negro sobre un mapa amarillo y negro -no se veia-, y el
        usuario lo mando poner azul el 2026-09-18. Lo que no puede cambiar sin
        enterarse nadie es la forma."""
        import guante
        import lienzos
        g = self.v["guante"]
        patrones, colores, _avisos = guante.planos_del_png(
            os.path.join(RAIZ, g["png"]))
        self.assertEqual(patrones.hex(), g["planos"])
        self.assertEqual(list(colores), g["planos_colores"])
        # los dos colores de hoy, para que un repintado accidental se vea
        self.assertEqual([lienzos.NOMBRE_MSX[c] for c in colores],
                         ["azul claro", "blanco"])
        # y la silueta, contra los 32 bytes de la cinta: A es el relleno (el
        # papel) y B el trazo (la tinta), que es como los reparte cursor.py
        # -el plano A es el color con menos pixels-
        dib = self.medio[0x6345 - 0x5E00:][:16]
        mas = self.medio[0x6355 - 0x5E00:][:16]
        relleno, trazo = colores[0], colores[1]
        visto = guante.dibuja(patrones, colores)
        for y in range(16):
            for x in range(16):
                if y >= 8:
                    esperado = None
                else:
                    bit = 0x8000 >> x
                    d = (dib[y * 2] << 8) | dib[y * 2 + 1]
                    m = (mas[y * 2] << 8) | mas[y * 2 + 1]
                    esperado = trazo if d & bit else (None if m & bit else relleno)
                self.assertEqual(visto[y][x], esperado,
                                 "el pixel (%d, %d) del guante no tiene la silueta de la cinta" % (x, y))

    def test_mi_guante_sube_los_patrones_una_vez_y_los_atributos_siempre(self):
        """La primera vez despues de cada escondida sube los 64 bytes de los
        dos planos; despues, solo los ocho atributos. Y el sitio es el que dice
        el cursor del mapa, con la Y una linea por encima."""
        import corre_nombres
        g = self.v["guante"]
        m = self.monta()
        self.assertEqual(m.ram[g["puesto"]], 0, "el guante viaja en la ROM sin poner")
        vdp, _z = corre_nombres.corre_guante(m, self.plan, col=0x50, fila=0x30)
        self.assertEqual(vdp.escritos, 64 + 8)
        self.assertEqual(bytes(vdp.vram[g["vram_patrones"]:g["vram_patrones"] + 64]),
                         bytes.fromhex(g["planos"]), "los patrones del guante no son los del PNG")
        self.assertEqual(m.ram[g["puesto"]], 1)
        # los sprites 0 y 1 -el cursor de la vista- no se tocan
        self.assertEqual(set(vdp.vram[0x1B00:0x1B08]), {0})
        for col, fila in ((0x51, 0x31), (0xE8, 0xB8), (0, 0)):
            vdp, _z = corre_nombres.corre_guante(m, self.plan, col, fila, vdp=vdp)
            self.assertEqual(vdp.escritos, 8, "con los patrones puestos solo suben los ocho atributos")
            self.assertEqual(vdp.direcciones, [(g["vram_atributos"], True)])
            self.assertEqual(bytes(vdp.vram[g["vram_atributos"]:g["vram_atributos"] + 8]),
                             corre_nombres.guante_esperado(self.plan, col, fila))
        # la fila 0 da Y = 255, que el TMS9918 entiende como -1 y pinta desde
        # la linea 0: es lo que hace falta para que el guante llegue arriba
        self.assertEqual(vdp.vram[g["vram_atributos"]], 255)

    def test_el_guardian_esconde_el_guante(self):
        """Cualquiera que vaya a pintar pasa por 0x044B, y un sprite se
        quedaria por delante de lo que venga: un menu, la ficha, la vista o una
        pantalla final. El guardian lo aparca en Y = 209 y apunta que ya no
        esta puesto, para que la vuelta siguiente del bucle de partida vuelva a
        subir patrones y atributos."""
        import corre_nombres
        g = self.v["guante"]
        m = self.monta()
        vdp, z = corre_nombres.corre_guardian(m, self.plan, hl=0x2345, modo=0, puesto=1)
        self.assertEqual(vdp.escritos, 8, "esconder el guante son ocho bytes y nada mas")
        self.assertEqual(bytes(vdp.vram[g["vram_atributos"]:g["vram_atributos"] + 8]),
                         bytes([209, 0, g["patron_a"], g["planos_colores"][0],
                                209, 0, g["patron_b"], g["planos_colores"][1]]))
        self.assertEqual(m.ram[g["puesto"]], 0)
        self.assertEqual(vdp.direcciones[-1], (0x2345, True),
                         "0x044B no deja puesta la direccion que le pidieron")
        self.assertEqual((z.bc, z.de, z.hl), (0x1234, 0x5678, 0x2345),
                         "esconder el guante pisa BC, DE o HL")
        # y sin guante puesto no escribe nada
        m = self.monta()
        vdp, _z = corre_nombres.corre_guardian(m, self.plan, hl=0x2345, modo=0, puesto=0)
        self.assertEqual(vdp.escritos, 0)

    # ------------------------------------- MI_PINTA: la cache del trozo y el cursor fijo
    # Las tres rutinas del juego que MI_PINTA llama (CELDA_DEL_MAPA,
    # DIBUJA_EL_TROZO_DE_MAPA, TAPA_LOS_BORDES) van sustituidas por trampas que
    # apuntan con que se las llamo: lo que se comprueba es lo que MI_PINTA hace
    # alrededor de ellas, que es lo nuevo.
    POSICION = (32, 29)         # donde entra el cursor en la partida de la sonda

    def pinta(self, hl, modo=0x10, **estado):
        import corre_nombres
        m = corre_nombres.monta(self.rom, self.plan, self.bajo, self.alto, medio=self.medio)
        z = corre_nombres.corre_pinta(m, self.plan, hl, modo, **estado)
        return m, z

    def cache_de_prueba(self):
        return bytes((i * 11 + 1) & 0xFF for i in range(850))

    def con_cache(self, hl, modo=0x10, posicion=POSICION, ultimo_modo=0x10):
        return self.pinta(hl, modo, cache_valida=1, posicion=posicion, ultimo_modo=ultimo_modo,
                          cache=self.cache_de_prueba())

    def test_sin_cache_repinta_como_el_original_y_la_guarda(self):
        """Entra por el `jp` de 0x71A4. Sin cache valida hace lo que hacia
        0x71A7-0x71C5: la pantalla a 0x80, CELDA_DEL_MAPA con la fila mas
        uno, la esquina 720 bytes atras, el trozo, los bordes con el HL de
        verdad; y ademas guarda la pantalla en la cache y apunta la posicion."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.POSICION
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
        self.assertEqual((m.ram[c["posicion_h"]], m.ram[c["posicion_l"]]), (h, l))
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
        h, l = self.POSICION
        m, z = self.con_cache((h << 8) | l)
        self.assertEqual(z.llamadas, [], "con la cache valida y el cursor quieto no se llama a nadie")
        self.assertEqual(bytes(m.ram[0x5E00:0x5E00 + 850]), self.cache_de_prueba(), "la pantalla no es la cache")
        self.assertEqual((m.ram[c["posicion_h"]], m.ram[c["posicion_l"]]), (h, l), "la posicion no cambia")
        self.assertEqual(z.hl, (h << 8) | l)
        self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                         corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10))

    def test_cualquier_paso_repinta_y_el_cursor_sigue_en_el_centro(self):
        """El cursor no se mueve nunca: lo que se mueve es el mapa. Una casilla
        en cualquier direccion repinta el trozo (las tres rutinas del juego),
        la posicion apuntada pasa a ser la nueva y los sprites siguen en (7, 5)."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.POSICION
        for dh, dl in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-2, 3)):
            hl = ((h + dh) << 8) | (l + dl)
            m, z = self.con_cache(hl)
            self.assertEqual([d for d, _ in z.llamadas],
                             [corre_nombres.CELDA_DEL_MAPA, corre_nombres.DIBUJA_EL_TROZO, corre_nombres.TAPA_LOS_BORDES],
                             "con el cursor en (%+d, %+d) tenia que repintar" % (dh, dl))
            self.assertEqual((m.ram[c["posicion_h"]], m.ram[c["posicion_l"]]), (h + dh, l + dl))
            self.assertEqual(bytes(m.ram[c["atributos"]:c["atributos"] + 8]),
                             corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10))
            self.assertEqual(z.hl, hl, "MI_PINTA tiene que devolver HL intacto")

    def test_repinta_si_cambia_el_modo_o_la_cache_no_vale(self):
        h, l = self.POSICION
        hl = (h << 8) | l
        _m, z = self.con_cache(hl, modo=0x12, ultimo_modo=0x10)
        self.assertEqual(len(z.llamadas), 3, "al cambiar de modo hay que repintar: el trozo lleva la marca de la orden")
        _m, z = self.pinta(hl, cache_valida=0, posicion=self.POSICION, ultimo_modo=0x10, cache=self.cache_de_prueba())
        self.assertEqual(len(z.llamadas), 3, "con la cache invalidada (el guardian) hay que repintar")

    def test_las_banderas_del_bit_7_no_cuentan(self):
        import corre_nombres
        h, l = self.POSICION
        m, z = self.con_cache(((h | 0x80) << 8) | (l | 0x80))
        self.assertEqual(z.llamadas, [], "el bit 7 de H y L son banderas: no mueven el cursor")
        self.assertEqual(bytes(m.ram[self.v["cursor"]["atributos"]:][:8]),
                         corre_nombres.atributos_esperados(self.plan, 7, 5, 0x10))

    def test_el_patron_y_el_color_van_con_el_modo(self):
        """0x10 mirar, 0x12 destino y 0x17 batalla: dos planos de 16x16 cada
        uno (patrones 0/4, 8/12 y 16/20) con los colores de cursor.png."""
        import corre_nombres
        c = self.v["cursor"]
        h, l = self.POSICION
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

    # ------------------------------------------- el menu de la casilla, por toque
    def test_en_el_menu_de_la_casilla_arriba_y_abajo_van_por_toque(self):
        """MI_ELECCION: arriba y abajo solo pasan en la vuelta en que se pulsan;
        fuego y la tecla 1 pasan siempre y borran lo apuntado; el resto de bits
        va tal cual; y BC, DE y HL salen intactos, como de LEE_LOS_MANDOS."""
        import corre_nombres
        c = self.v["cursor"]
        casos = [   # (lo apuntado, el mando, lo que ve el bucle, lo que queda apuntado)
            (0x00, 0x01, 0x01, 0x01),       # un toque de arriba: pasa
            (0x01, 0x01, 0x00, 0x01),       # sigue pulsada: no pasa
            (0x01, 0x00, 0x00, 0x00),       # soltada
            (0x00, 0x02, 0x02, 0x02),       # un toque de abajo
            (0x01, 0x02, 0x02, 0x02),       # abajo con arriba aun pulsada: pasa abajo
            (0x03, 0x03, 0x00, 0x03),       # las dos seguidas: nada
            (0x01, 0x09, 0x08, 0x09),       # arriba seguida y derecha: la derecha tal cual, arriba no
            (0x03, 0x11, 0x11, 0x00),       # fuego con arriba seguida: pasa entero y se olvida
            (0x01, 0x21, 0x21, 0x00),       # la tecla 1, lo mismo
            (0x00, 0x10, 0x10, 0x00),       # fuego solo
        ]
        for ultima, mando, visto, queda in casos:
            m = self.monta()
            z = corre_nombres.corre_eleccion(m, self.plan, mando, ultima)
            self.assertEqual(z.llamadas, [(corre_nombres.LEE_LOS_MANDOS, ("a", mando))])
            self.assertEqual(z.a, visto, "apuntado %02X y mando %02X: el bucle ve %02X y tenia que ver %02X"
                             % (ultima, mando, z.a, visto))
            self.assertEqual(m.ram[c["ultima_eleccion"]], queda, "apuntado %02X y mando %02X: queda %02X y tenia que quedar %02X"
                             % (ultima, mando, m.ram[c["ultima_eleccion"]], queda))
            self.assertEqual((z.bc, z.de, z.hl), (0x1234, 0x5678, 0x9ABC), "MI_ELECCION tiene que dejar BC, DE y HL como LEE_LOS_MANDOS")

    # ------------------------------------------- el cursor de la batalla
    def test_el_cursor_de_la_batalla_va_al_paso_del_reloj(self):
        """MI_CURSOR_BATALLA: las cuatro direcciones solo pasan una vez cada
        PASO_EN_LA_BATALLA cuadros, asi que la velocidad del cursor deja de ser
        la del bucle de batalla; el disparo y la tecla 1 pasan siempre, que ya
        tienen su espera a soltar en PULSA_EN_LA_BATALLA."""
        import corre_nombres
        c = self.v["cursor"]
        paso = c["paso_batalla"]
        self.assertEqual(paso, 16)
        casos = [   # (mando, cuadros, ultimo paso, lo que ve el cursor, lo que queda apuntado)
            (0x08, 100, 100 - paso, 0x08, 100),         # justo a los PASO cuadros: pasa
            (0x08, 100, 100 - paso + 1, 0x00, 100 - paso + 1),   # a uno de cumplirlos: no
            (0x04, 100, 100, 0x00, 100),                # recien dado un paso: no
            (0x00, 100, 50, 0x00, (100 - paso) & 0xFF),  # sin direccion, el contador queda listo
            (0x10, 100, 100, 0x10, 100 - paso),         # el disparo pasa, y sin direccion el contador queda listo
            (0x18, 100, 100, 0x10, 100),                # y con direccion, pasa solo el disparo
            (0x28, 100, 100 - paso, 0x28, 100),         # la tecla 1 y una direccion, en su cuadro
            (0x01, 4, (4 - paso) & 0xFF, 0x01, 4),      # el contador da la vuelta
        ]
        for mando, cuadros, ultimo, visto, queda in casos:
            m = self.monta()
            z = corre_nombres.corre_cursor_batalla(m, self.plan, mando, cuadros, ultimo)
            self.assertEqual(z.llamadas, [(corre_nombres.LEE_LOS_MANDOS, ("a", mando))])
            self.assertEqual(z.a, visto,
                             "mando %02X a %d cuadros del ultimo paso: ve %02X y tenia que ver %02X"
                             % (mando, (cuadros - ultimo) & 0xFF, z.a, visto))
            self.assertEqual(m.ram[c["ultimo_paso_batalla"]], queda,
                             "mando %02X: queda %d y tenia que quedar %d"
                             % (mando, m.ram[c["ultimo_paso_batalla"]], queda))
            self.assertEqual((z.bc, z.de, z.hl), (0x1234, 0x5678, 0x9ABC),
                             "MI_CURSOR_BATALLA tiene que dejar BC, DE y HL como LEE_LOS_MANDOS")

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
        for nombre in ("pinta", "cache", "cache_valida", "ultimo_modo", "posicion_h", "posicion_l",
                       "atributos", "patrones", "colores", "mueve", "ultimo_paso", "eleccion",
                       "ultima_eleccion", "batalla", "ultimo_paso_batalla"):
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
        import mapa_general
        esperado = {"patrones": pantalla[100:100 + 6144],
                    "colores": pantalla[100 + 6144:100 + 12288],
                    "final0": bajo[0x094F - 0x0190:][:6912],
                    "final1": bajo[0x244F - 0x0190:][:6912],
                    "mapa": mapa_general.dibuja_el_mapa(WORK)}
        comprimidos = [n for n, d in self.plan["datos"].items() if d.get("zx0")]
        self.assertEqual(sorted(comprimidos), sorted(esperado),
                         "no estan comprimidos los cinco bloques que se esperaba")
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
