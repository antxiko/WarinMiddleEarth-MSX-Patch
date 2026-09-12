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


def descomprime_desde(rom, ini, marca):
    """El RLE de marca de tools/comprime.py, leido de la ROM tal y como lo lee
    el descompresor del stub: hasta el `marca 0` que cierra el bloque. Escrito
    aparte a proposito, para que un fallo del compresor no se cuele por usar su
    propia funcion en los dos lados."""
    out = bytearray()
    i = ini
    while True:
        b = rom[i]
        i += 1
        if b != marca:
            out.append(b)
            continue
        n = rom[i]
        i += 1
        if n == 0:
            return bytes(out)
        out += bytes([rom[i]]) * n
        i += 1


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
        elif nombre in ("ROM_RAM_RLE", "ROM_VRAM_RLE"):
            # El descompresor cruza de banco solo, y en la ROM los bancos
            # van seguidos, asi que aqui basta con leer de corrido desde
            # donde empieza. La marca viaja en el campo `len`.
            if pagina1 != "cart":
                lee_rom_sin_cart.append(op)
            ini = op["b"] * 0x4000 + op["src"] - 0x4000
            salido = descomprime_desde(rom, ini, op["len"] & 0xFF)
            if nombre == "ROM_RAM_RLE":
                escribe_ram(op["dst"], salido)
            else:
                vram[op["dst"]:op["dst"] + len(salido)] = salido
        elif nombre == "RANURA_PAG2":
            escribe_ram(op["dst"], b"\x00")   # un byte, el operando del `or` del puente
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

    def setUp(self):
        plan = os.path.join(self.DERIVADOS, "plan.json")
        hace_falta(self.ROM, plan)
        self.rom = lee(self.ROM)
        with open(plan) as f:
            self.plan = json.load(f)
        self.musica = self.plan["datos"].get("musica")

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
        pantalla = lee(os.path.join(WORK, "pantalla.raw"))
        esperado = dict(patrones=pantalla[100:100 + 6144], colores=pantalla[100 + 6144:100 + 12288],
                        bajo=lee(os.path.join(WORK, "bajo.raw")), medio=lee(os.path.join(WORK, "medio.raw")),
                        alto=lee(os.path.join(WORK, "alto.raw")))
        # Con musica, el bloque medio lleva los parches del gancho y del menu:
        # se aplican sobre lo esperado, que para eso el plan dice cuales son.
        for q in (self.musica or {}).get("parches", []):
            o = q["dir"] - 0x5E00
            viejo, nuevo = bytes.fromhex(q["orig"]), bytes.fromhex(q["nuevo"])
            self.assertEqual(esperado["medio"][o:o + len(viejo)], viejo,
                             "el parche de 0x%04X no cae sobre lo que dice" % q["dir"])
            esperado["medio"] = esperado["medio"][:o] + nuevo + esperado["medio"][o + len(nuevo):]
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
            if d.get("rle"):
                # Lo que cuenta no es lo que hay en la ROM sino lo que sale al
                # descomprimirlo: es la unica forma de que este test siga
                # comprobando la cinta y no el formato.
                salido = descomprime_desde(self.rom, d["rom"], d["marca"])
                self.assertEqual(salido, esperado[nombre], "%s, descomprimido" % nombre)
                self.assertEqual(len(salido), d["crudo"], nombre)
                self.assertLess(d["bytes"], d["crudo"], "%s no encoge" % nombre)
            else:
                self.assertEqual(en_rom, esperado[nombre], nombre)
        fin = max(d["rom"] + d["bytes"] for n, d in self.plan["datos"].items() if n != "musica")
        self.assertEqual(fin, self.plan["fin_datos"])
        relleno = self.rom[fin + (self.musica["bytes"] if self.musica else 0):]
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
        bajo, medio, alto = (lee(os.path.join(WORK, n + '.raw')) for n in ('bajo', 'medio', 'alto'))
        # la RAM: como la deja el cargador de la cinta en 0xD741
        for q in (self.musica or {}).get("parches", []):
            o = q["dir"] - 0x5E00
            nuevo = bytes.fromhex(q["nuevo"])
            medio = medio[:o] + nuevo + medio[o + len(nuevo):]
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


class TestLaMusica(unittest.TestCase):
    """Lo que solo tiene sentido con musica: donde cae, que cambia y que no."""

    def setUp(self):
        plan = os.path.join(WORK_MUSICA, "plan.json")
        hace_falta(ROM_MUSICA, plan)
        self.rom = lee(ROM_MUSICA)
        with open(plan) as f:
            self.plan = json.load(f)
        self.m = self.plan["datos"]["musica"]

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
        ranura = [o for o in self.plan["plan"] if o["op"] == "RANURA_PAG2"]
        self.assertEqual(len(ranura), 1, "nadie rellena la ranura del puente, o la rellenan dos veces")
        self.assertTrue(p["ram"] <= ranura[0]["dst"] < p["ram"] + p["bytes"],
                        "la ranura se escribe fuera del puente")

    def test_la_musica_solo_cambia_cinco_bytes_del_juego(self):
        """La prueba de que la musica no toca el juego.

        No se comparan las dos ROMs byte a byte: desde que las imagenes viajan
        comprimidas, la de musica no se PARECE a la otra -otra disposicion, otro
        stub, otros tamanos- y ese diff no diria nada. Lo que tiene que
        coincidir es lo que acaba en la RAM, que es lo unico que el juego ve.

        Se permite exactamente: los bytes que el plan declara como parches, y
        el puente, que vive en tierra de nadie y no le quita el sitio a nadie.
        """
        hace_falta(ROM, PLAN)
        with open(PLAN) as f:
            plan_sin = json.load(f)
        ram_sin = ejecuta_plan(self, lee(ROM), plan_sin)[0]
        ram_con = ejecuta_plan(self, self.rom, self.plan)[0]

        permitidos = set()
        for q in self.m["parches"]:
            permitidos.update(range(q["carga"], q["carga"] + len(bytes.fromhex(q["nuevo"]))))
        self.assertEqual(len(permitidos), 5, "los parches del juego tienen que ser cinco bytes")
        p = self.m["puente"]
        permitidos.update(range(p["ram"], p["ram"] + p["bytes"]))

        fuera = [i for i in range(0x10000) if ram_sin[i] != ram_con[i] and i not in permitidos]
        self.assertEqual(fuera, [], "la musica cambia la RAM fuera de lo que declara")
        # Y los cinco se cambian de verdad: si el parche no se aplicara, la
        # comprobacion de arriba pasaria igual.
        for q in self.m["parches"]:
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
