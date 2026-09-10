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
import lienzos  # noqa: E402
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


@functools.lru_cache(maxsize=1)
def simbolos_del_icono(pas):
    """{etiqueta: direccion} de src/parche/icono_enemigo.asm, tal como los
    escribe pasmo (`NOMBRE EQU 0666EH`). Es la unica autoridad sobre donde
    empieza cada rutina del parche."""
    os.makedirs(WORK, exist_ok=True)
    binario = os.path.join(WORK, "icono_enemigo.sym.bin")
    sym = os.path.join(WORK, "icono_enemigo.sym")
    r = subprocess.run([pas, "--bin", ASM_ICONO, binario, sym],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr or r.stdout)
    tabla = {}
    for linea in open(sym):
        partes = linea.split()
        if len(partes) == 3 and partes[1].upper() == "EQU":
            tabla[partes[0]] = int(partes[2].rstrip("Hh"), 16)
    return tabla


def hay_cuerpos():
    return all(os.path.exists(os.path.join(WORK, n + ".raw"))
               for n in parchea.BLOQUES_SPECTRUM)


# El motor del altavoz del ZX Spectrum, 0x6600-0x6713: codigo huerfano al que no
# llama nadie, y de donde el parche saca el sitio que le falta.
MOTOR_MUERTO = (0x6600, 0x6713)


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

    def test_los_textos_no_cambian_el_numero_de_cadenas(self):
        """En las listas de cadenas pegadas se llega a la numero N contando bits
        7 (SALTA_B_TEXTOS, 0x6E98). Si el parche metiera o quitara una cadena,
        todas las de detras se correrian de indice: el juego diria 'Orcs' donde
        pone 'Enanos'. Cada cadena tiene que seguir en su sitio."""
        for p in parchea.PARCHES:
            if p["grupo"] != "textos":
                continue
            if p.get("codigo"):
                # Marcada como codigo: es el operando de un `ld`, no una lista
                # de cadenas, y contarle bits 7 no significa nada.
                continue
            if MOTOR_MUERTO[0] <= p["dir"] <= MOTOR_MUERTO[1]:
                # Esta no EDITA una lista: escribe una nueva encima del motor de
                # sonido del ZX, que es codigo muerto. Contar los bits 7 de su
                # `orig` no dice nada, porque ahi hay instrucciones. Lo que si
                # se puede exigir es cuantas cadenas deja.
                nuevo = bytes.fromhex(p["nuevo"])
                self.assertEqual(sum(1 for b in nuevo if b & 0x80), 4,
                                 "la lista nueva de 0x%04X no deja cuatro "
                                 "cadenas" % p["dir"])
                continue
            orig = bytes.fromhex(p["orig"])
            nuevo = bytes.fromhex(p["nuevo"])
            self.assertEqual(sum(1 for b in orig if b & 0x80),
                             sum(1 for b in nuevo if b & 0x80),
                             "0x%04X cambia el numero de cadenas de la lista" % p["dir"])

    def test_los_textos_son_imprimibles(self):
        """La fuente de 0xC800 solo trae dibujo de 0x21 a 0x7F (el 0x20 esta a
        cero y es el espacio); cualquier otro codigo saldria como un borron."""
        for p in parchea.PARCHES:
            if p["grupo"] != "textos" or p.get("codigo") or p.get("registros"):
                # `codigo`: es el operando de un `ld`. `registros`: son registros
                # enteros de la tabla de sitios, con sus cabeceras [x][y][salto]
                # [ancho<<4|filas] por delante de cada texto. En los dos casos
                # hay bytes que no son letras, y a esos este test no les aplica;
                # el texto de los registros lo mira
                # test_los_carteles_del_mapa_siguen_cuadrando, que los recorre.
                continue
            for b in bytes.fromhex(p["nuevo"]):
                self.assertTrue(0x20 <= (b & 0x7F) < 0x80,
                                "0x%04X escribe el codigo 0x%02X" % (p["dir"], b))

    def test_ninguna_base_absoluta_queda_dentro_de_un_parche_de_texto(self):
        """El codigo entra en las listas por direcciones fijas. Un parche puede
        reordenar los bytes DE DENTRO de una lista, pero no puede empezar ni
        acabar a mitad: ninguna de estas bases puede caer dentro de un rango."""
        bases = (0x7A5E,  # la tabla de sitios
                 0x7D06,  # razas en plural
                 0x7D39,  # razas en singular
                 0x7D6A,  # los cuatro carteles de bando
                 0x7D84,  # "Formacion de"
                 0x7D90,  # ":caracter:"
                 0x7D9A,  # los siete adverbios
                 0x7DD3, 0x7DDC, 0x7DE6, 0x7DEF, 0x7DF7, 0x7DFC,  # los seis adjetivos
                 0x6B46)  # los 24 nombres
        for p in parchea.PARCHES:
            if p["grupo"] != "textos":
                continue
            a = p["dir"]
            b = a + len(bytes.fromhex(p["nuevo"]))
            for base in bases:
                self.assertFalse(a < base < b,
                                 "el parche de 0x%04X se traga la base 0x%04X" % (a, base))

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
        """Los tres ganchos de la segunda tanda entran en la rutina nueva: la
        siembra por `call`, el dibujo por `jp` y el anillo por `call`.

        Las direcciones se sacan del fichero de SIMBOLOS que escribe pasmo, no
        de sumar bytes a mano. La primera version las contaba a mano y le puso
        al anillo 0x666D en vez de 0x666E: el test repetia la misma cuenta
        equivocada, asi que confirmaba el fallo en vez de cazarlo."""
        pas = pasmo()
        if not pas:
            self.skipTest("pasmo no esta en el PATH")
        simbolos = simbolos_del_icono(pas)
        rut = next(p for p in parchea.PARCHES if p["dir"] == 0x664C)
        self.assertEqual(len(bytes.fromhex(rut["nuevo"])), len(parchea.RUTINA_ICONO))
        for direccion, opcode, etiqueta in ((0x7FC9, 0xCD, "SIEMBRA_CON_BANDO"),
                                            (0x770A, 0xC3, "DIBUJO_SEGUN_BANDO"),
                                            (0x6F77, 0xCD, "ANILLO_CON_PLAZO")):
            g = bytes.fromhex(next(p for p in parchea.PARCHES
                                   if p["dir"] == direccion)["nuevo"])
            self.assertEqual(g[0], opcode, hex(direccion))
            self.assertEqual(g[1] | (g[2] << 8), simbolos[etiqueta],
                             "el gancho de 0x%04X no entra en %s" % (direccion, etiqueta))

    def test_el_gancho_del_anillo_cae_en_la_primera_instruccion(self):
        """Sin pasmo tambien: el byte al que salta el gancho del anillo tiene
        que ser el `ld a,05fh` con que empieza ANILLO_CON_PLAZO. Si el destino
        se corre un byte cae en el 0x77 con que acaba el `jp 07717h` anterior,
        que es un `ld (hl),a` que escribe donde le pille -el bug de Araubi-."""
        g = bytes.fromhex(next(p for p in parchea.PARCHES
                               if p["dir"] == 0x6F77)["nuevo"])
        destino = g[1] | (g[2] << 8)
        cuerpo = parchea.RUTINA_ICONO[destino - 0x664C:]
        self.assertEqual(cuerpo[:5], bytes.fromhex("3e5f32467c"),
                         "0x%04X no es el `ld a,05fh` / `ld (07c46h),a` del anillo" % destino)

    def test_el_ojo_no_usa_un_hueco_de_la_tabla_de_cuadros(self):
        """Los huecos a cero de la tabla de 0x77B5 NO estan libres: los indices
        0x00-0x0F los elige PINTA_LO_DE_ENCIMA con un `and 00fh` sobre el
        terreno. El parche no puede tocar esa tabla."""
        self.assertFalse([p for p in parchea.PARCHES if 0x77B5 <= p["dir"] < 0x7845],
                         "el parche escribe en la tabla de cuadros de 0x77B5")

    def test_ninguna_entrada_escrita_a_mano_toca_los_graficos(self):
        """Las tres tablas de graficos las llevan los lienzos y solo ellos: si
        alguien vuelve a escribir dibujos a mano en PARCHES, las dos fuentes se
        pisarian y el `orig` de una de ellas dejaria de cuadrar."""
        for p in parchea.PARCHES:
            if p["bloque"] != "alto":
                continue
            a = p["dir"]
            b = a + len(bytes.fromhex(p["nuevo"]))
            for hoja in lienzos.HOJAS:
                self.assertTrue(b <= hoja.ini or a >= hoja.fin,
                                "0x%04X escribe dentro de la hoja de %s"
                                % (a, hoja.nombre))

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

    # ---- los graficos, que ahora salen del lienzo -------------------------
    def test_el_lienzo_sigue_trayendo_el_ojo(self):
        """El Ojo de Sauron ya no se escribe a mano en la tabla: se dibuja en
        src/parche/tiles_del_mapa.png, y de ahi salen sus 36 bytes. Este test
        es el control: el lienzo tiene que seguir dando EXACTAMENTE los mismos
        bytes que cuando eran un hexadecimal en el codigo. Si alguien rehace el
        lienzo desde la cinta y se lleva el Ojo por delante, esto se pone rojo.

        Los cuatro tiles son los indices 111 a 114, que en la cinta venian a
        cero, y llevan el atributo 0x38 -tinta negra sobre papel blanco-, el
        mismo que usan las unidades aliadas."""
        self.assertEqual(0xA1E7, 0x9E00 + 111 * 9)
        g = parchea.parches_de_graficos(self._origs()["alto"])
        # Ya no es una entrada suelta: el mapa entero esta repintado, asi que el
        # Ojo cae dentro de un tramo mas largo. Se recompone el bloque alto con
        # todas las entradas y se miran esos 36 bytes.
        alto = bytearray(self._origs()["alto"])
        for p in g:
            self.assertEqual(p["bloque"], "alto", p)
            i = p["dir"] - 0x9E00
            self.assertEqual(bytes(alto[i:i + len(p["orig"]) // 2]),
                             bytes.fromhex(p["orig"]), p)
            alto[i:i + len(p["nuevo"]) // 2] = bytes.fromhex(p["nuevo"])
        i = 0xA1E7 - 0x9E00
        b = bytes(alto[i:i + 36])
        self.assertEqual(bytes(self._origs()["alto"][i:i + 36]), bytes(36),
                         "en la cinta los tiles 111-114 no venian a cero")
        self.assertEqual(b, parchea.TILES_OJO, "el lienzo ya no dibuja el Ojo")
        for i in range(4):
            self.assertIn(b[i * 9 + 8] & 0x3F, (0x3A, 0x17),
                          "el tile %d no es rojo y blanco" % (111 + i))

    # ---- los adjetivos de la ficha, siguiendo los punteros de verdad -----
    def _medio_parcheado(self):
        """El bloque medio con la tabla aplicada encima, y comprobando de paso
        que cada `orig` es lo que la cinta trae de verdad en esa direccion."""
        d = bytearray(self._origs()["medio"])
        for p in parchea.PARCHES:
            if p["bloque"] != "medio":
                continue
            i = p["dir"] - 0x5E00
            orig = bytes.fromhex(p["orig"])
            self.assertEqual(bytes(d[i:i + len(orig)]), orig,
                             "el orig de 0x%04X no es lo que trae la cinta" % p["dir"])
            d[i:i + len(bytes.fromhex(p["nuevo"]))] = bytes.fromhex(p["nuevo"])
        return bytes(d)

    @staticmethod
    def _texto(d, a):
        """COPIA_TEXTO (0x6E78): letras hasta la que lleva el bit 7, incluida."""
        s = ""
        while True:
            b = d[a - 0x5E00]
            s += chr(b & 0x7F)
            if b & 0x80:
                return s
            a += 1

    def test_los_seis_adjetivos_salen_de_sus_punteros(self):
        """Tres de los seis adjetivos viven fuera de su sitio de siempre, en el
        motor de sonido muerto, y solo se llega a ellos por el operando de un
        `ld hl`. Este test NO repite la aritmetica del parche: lee el puntero de
        la cinta parcheada y va a ver que hay alli. Si alguien mueve una cadena
        y se olvida del puntero, o al reves, aqui se ve."""
        d = self._medio_parcheado()
        espera = {0x704B: " Energico", 0x7061: " Decidido ", 0x7006: " Firme   ",
                  0x6FEF: " Virtuoso", 0x701E: " Valiente", 0x7035: " Fuerte"}
        for ld, texto in espera.items():
            self.assertEqual(d[ld - 0x5E00], 0x21,
                             "en 0x%04X tendria que haber un `ld hl,nn`" % ld)
            destino = d[ld + 1 - 0x5E00] | (d[ld + 2 - 0x5E00] << 8)
            self.assertEqual(self._texto(d, destino), texto,
                             "el `ld hl` de 0x%04X" % ld)

    def test_los_adjetivos_nuevos_caben_en_la_linea_de_la_ficha(self):
        """La ficha son 24 columnas y MUESTRA_LOS_VALORES escribe el numero en
        la 20, asi que <adverbio><adjetivo> no puede pasar de ahi. El adverbio
        mas largo es el peor caso, y lo que se exige es que NINGUN adjetivo
        nuevo empeore lo que ya hacia el mas largo de la cinta original."""
        d = self._medio_parcheado()
        orig = self._origs()["medio"]
        a, adverbios = 0x7D9A, []
        for _ in range(8):
            s = self._texto(d, a)
            adverbios.append(s)
            a += len(s)
        peor = max(len(s) for s in adverbios)
        antes = max(len(self._texto(orig, orig[ld + 1 - 0x5E00]
                                    | (orig[ld + 2 - 0x5E00] << 8)))
                    for ld in (0x704B, 0x7061, 0x7006, 0x6FEF, 0x701E, 0x7035))
        for ld in (0x704B, 0x7061, 0x7006, 0x6FEF, 0x701E, 0x7035):
            destino = d[ld + 1 - 0x5E00] | (d[ld + 2 - 0x5E00] << 8)
            largo = len(self._texto(d, destino))
            self.assertLessEqual(largo, antes,
                                 "el adjetivo de 0x%04X mide %d y el mas largo "
                                 "de la cinta media %d" % (ld, largo, antes))
            self.assertLessEqual(peor + largo, 24,
                                 "el adjetivo de 0x%04X se sale de la ficha" % ld)

    def test_la_ultima_linea_de_la_ficha_sale_entera_y_cabe(self):
        """La fila 9 ya no se compone de plantilla + palabra: la lista mudada
        trae LA FRASE ENTERA y se escribe desde la columna 0. Se sigue el
        puntero de la cinta parcheada, se leen las cuatro y se comprueba que
        ninguna se sale de las 24 columnas de la ficha."""
        d = self._medio_parcheado()
        fila9 = 0x7C17 + 9 * 24
        self.assertEqual(d[0x7073 - 0x5E00], 0x21)     # ld hl,nn
        self.assertEqual(d[0x7079 - 0x5E00], 0x11)     # ld de,nn
        destino = d[0x707A - 0x5E00] | (d[0x707B - 0x5E00] << 8)
        self.assertEqual(destino, fila9,
                         "la frase ya no se escribe desde la columna 0")
        a = d[0x7074 - 0x5E00] | (d[0x7075 - 0x5E00] << 8)
        frases = []
        for _ in range(4):                             # `and 003h` en 0x7070
            s = self._texto(d, a)
            frases.append(s)
            a += len(s)
        self.assertEqual(frases[0], "Aliado a la Comunidad")
        for s in frases:
            self.assertLessEqual(len(s), 24,
                                 "%r se sale de la fila de la ficha" % s)

    def test_las_cadenas_nuevas_caen_en_el_motor_de_sonido_muerto(self):
        """El sitio prestado es 0x6600-0x6713, el motor del altavoz del ZX, que
        no llama nadie. Ninguna entrada del parche puede salirse de ahi ni
        pisarse con otra."""
        usados = []
        for p in parchea.PARCHES:
            if p["bloque"] != "medio" or not 0x6600 <= p["dir"] <= 0x6713:
                continue
            n = len(bytes.fromhex(p["nuevo"]))
            self.assertLessEqual(p["dir"] + n - 1, 0x6713,
                                 "0x%04X se sale del motor muerto" % p["dir"])
            usados.append((p["dir"], p["dir"] + n - 1))
        usados.sort()
        for (_, fin), (ini, _) in zip(usados, usados[1:]):
            self.assertLess(fin, ini, "dos entradas se pisan en 0x%04X" % ini)

    def test_los_lienzos_solo_tocan_los_tiles(self):
        """El parche repinta los 128 tiles del mapa, pero NO los 176 sprites de
        batalla ni los 128 caracteres de la fuente: esos tienen que salir de sus
        lienzos con los bytes de la cinta, sin recodificar. Si aparece una
        entrada fuera del tramo de los tiles, algun lienzo se ha ensuciado por el
        camino (lo tipico: guardarlo escalado, o con el color retocado)."""
        g = parchea.parches_de_graficos(self._origs()["alto"])
        self.assertEqual({p["grupo"] for p in g}, {"graficos"})
        for p in g:
            fin = p["dir"] + len(p["orig"]) // 2
            self.assertTrue(0x9E00 <= p["dir"] and fin <= 0xA280,
                            "la entrada de 0x%04X se sale de los tiles" % p["dir"])

    def test_sin_lienzos_el_parche_se_queda_sin_graficos(self):
        """Si los PNG no estan, no hay entradas de graficos y el resto del
        parche sigue funcionando: los lienzos son una pieza suelta, no un
        requisito."""
        g = parchea.parches_de_graficos(self._origs()["alto"],
                                        carpeta=os.path.join(WORK, "no_existe"))
        self.assertEqual(g, [])

    # ---- los textos, leidos como los lee el propio Z80 --------------------
    @staticmethod
    def _lista(cuerpo, base, cuantas):
        """SALTA_B_TEXTOS (0x6E98) + COPIA_TEXTO (0x6E78): las cadenas van
        pegadas y acaban en la letra que lleva el bit 7."""
        i = base - 0x5E00 + 1
        salida = []
        for _ in range(cuantas):
            s = ""
            while True:
                b = cuerpo[i]
                i += 1
                s += chr(b & 0x7F)
                if b & 0x80:
                    break
            salida.append(s)
        return salida

    @staticmethod
    def _sitios(cuerpo):
        """BUSCA_EL_SITIO (0x6E50): [x][y][salto][ancho<<4|filas][texto], hasta
        que el byte de salto es cero."""
        i = 0x7A5E - 0x5E00
        salida = []
        while cuerpo[i + 2]:
            salto, forma = cuerpo[i + 2], cuerpo[i + 3]
            texto = cuerpo[i + 4:i + 2 + salto].decode("latin-1")
            salida.append((cuerpo[i], cuerpo[i + 1], forma >> 4, forma & 0x0F, texto))
            i += 2 + salto
        return salida

    def test_los_carteles_del_mapa_siguen_cuadrando(self):
        """El cartel de un sitio mide ancho x filas y el texto lo rellena
        entero: si un toponimo nuevo midiera otra cosa, el cartel saldria con
        basura o se comeria el registro siguiente."""
        cuerpos = {n: bytearray(b) for n, b in self._origs().items()}
        antes = self._sitios(cuerpos["medio"])
        parchea.aplica(cuerpos)
        despues = self._sitios(cuerpos["medio"])
        self.assertEqual(len(antes), len(despues), "cambio el numero de sitios")
        # La tabla va pegada y el juego la recorre sumando saltos, asi que lo
        # que de verdad no puede moverse es su LARGO TOTAL: si creciera o
        # menguara se comeria lo que hay detras.
        self.assertEqual(sum(4 + w * r for _, _, w, r, _ in antes),
                         sum(4 + w * r for _, _, w, r, _ in despues),
                         "la tabla de sitios cambia de largo")
        # DOS carteles cambian de ancho a proposito: "Valle" necesita una
        # columna mas que "Dale" y se la presta "Rivendel", que perdio el
        # espacio de relleno. Ningun otro puede moverse.
        cambian = {(100, 15): (5, 1), (69, 23): (8, 1)}
        for (xa, ya, wa, ra, _), (xd, yd, wd, rd, td) in zip(antes, despues):
            self.assertEqual((xa, ya), (xd, yd), "un cartel cambia de sitio")
            self.assertEqual((wd, rd), cambian.get((xa, ya), (wa, ra)),
                             "el cartel de %r cambia de tamano sin permiso" % td)
            self.assertEqual(len(td), wd * rd, "el cartel de %r no mide %dx%d"
                             % (td, wd, rd))
        nombres = [t for _, _, _, _, t in despues]
        for esperado in ("Puerta N", "Rivendel", "Ga. Hierro", "Valle", "LosGamos",
                         "Delagua", "Cavada Grande ", "Quebradas", "AbismHelm ",
                         "Ptos  Grises"):
            self.assertIn(esperado, nombres)
        for ingles in ("Morannon", "Rivendell", "Isenmouthe", "Dale", "Buckland",
                       "Bywater", "Michel Delving", "Far Downs", "HelmsDeep ",
                       "Grey  Havens"):
            self.assertNotIn(ingles, nombres)

    def test_las_dos_listas_de_razas_quedan_en_su_sitio(self):
        """Las nueve razas en plural y las diez en singular, leidas contando
        bits 7 desde 0x7D06 y 0x7D39. Que la ultima de cada lista siga siendo la
        que era prueba que ninguna cadena se ha corrido de indice."""
        cuerpos = {n: bytearray(b) for n, b in self._origs().items()}
        parchea.aplica(cuerpos)
        medio = cuerpos["medio"]
        self.assertEqual(
            self._lista(medio, 0x7D06, 9),
            ["Magos", "Nazgul", "Hombres", "Elfos", "Enanos ", "Orcs", "Hobbits",
             "Mago", "Gollum"])
        self.assertEqual(
            self._lista(medio, 0x7D39, 10),
            ["Mago", "Nazgul", "Hombre", "Elfo", "Enano", "Orc", "Hobbit", "Mago",
             "Gollum", "Mujer"])
        # y las dos listas de detras, que el parche no toca, tienen que seguir
        # leyendose bien: es la prueba de que nada se ha desplazado
        self.assertEqual(self._lista(medio, 0x7D6A, 4),
                         [" Sociedad  ", "-", " union ", " union"])
        self.assertEqual(self._lista(medio, 0x7D9A, 7),
                         ["Realmente ", " Muy ", " Es muy", " ", " Es algo ",
                          " No muy  ", " No "])

    def test_las_cadenas_abandonadas_se_quedan_como_estaban(self):
        """Tres adjetivos se han mudado al motor de sonido muerto, asi que sus
        direcciones de siempre -0x7DEF 'Valioso', 0x7DF7 'Duro' y 0x7DFC
        'Bravo'- ya no las lee nadie. Tienen que quedarse EXACTAMENTE como
        vienen en la cinta: media cadena editada ahi seria un cabo suelto, y
        ademas es la senal de que no se ha desplazado nada alrededor."""
        cuerpos = {n: bytearray(b) for n, b in self._origs().items()}
        antes = bytes(cuerpos["medio"])
        parchea.aplica(cuerpos)
        i, j = 0x7DEF - 0x5E00, 0x7E02 - 0x5E00
        self.assertEqual(bytes(cuerpos["medio"][i:j]), antes[i:j])
        for base, esperado in ((0x7DEF - 1, " Valioso"), (0x7DF7 - 1, " Duro"),
                               (0x7DFC - 1, " Bravo")):
            self.assertEqual(self._lista(cuerpos["medio"], base, 1), [esperado])

    def test_los_24_nombres_siguen_siendo_24(self):
        """La lista de 0x6B46 va separada por 0xB7; 'Brand III' y 'Bardo III'
        miden lo mismo, asi que ni el numero de nombres ni sus posiciones
        cambian."""
        cuerpos = {n: bytearray(b) for n, b in self._origs().items()}
        antes = bytes(cuerpos["medio"])
        parchea.aplica(cuerpos)
        despues = bytes(cuerpos["medio"])
        i, j = 0x6B46 - 0x5E00, 0x6BF3 - 0x5E00
        self.assertEqual(antes[i:j].count(0xB7), despues[i:j].count(0xB7))
        nombres = despues[i:j].decode("latin-1").split("\xb7")
        self.assertIn("Bardo III", nombres)
        self.assertNotIn("Brand III", nombres)

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
