#!/usr/bin/env python3
"""Comprobaciones del lienzo de los tiles del mapa.

Ninguna necesita la cinta: se fabrican tablas de tiles a mano, se sacan al PNG y
se vuelven a leer. Lo que se comprueba es que la IDA Y VUELTA es exacta, que el
lector de PNG traga lo que escupen los editores de verdad y que las dos reglas
del ZX -dos colores por casilla y los dos del mismo brillo- se cazan con un
mensaje que dice que casilla y por que, en vez de elegir por su cuenta.
"""
import os
import struct
import sys
import tempfile
import unittest
import zlib

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import tiles_del_mapa as T  # noqa: E402

LIENZO = os.path.join(RAIZ, "src", "parche", "tiles_del_mapa.png")


def tabla_de_muestra():
    """Una tabla de 128 tiles inventada, con los casos raros dentro.

    No vale con tiles bonitos: hacen falta los que NO se pueden reconstruir
    mirando la imagen, que son los que justifican la regla de "si se ve igual,
    devuelve los bytes de siempre".
    """
    fuera = bytearray()
    for t in range(T.TILES):
        if t == 0:                       # tinta y papel iguales, con dibujo debajo
            fuera += bytes([0x10, 0x41, 0x62, 0x5C, 0x40, 0x40, 0x40, 0x40, 0x7F])
        elif t == 1:                     # todo a cero: negro sobre negro
            fuera += bytes(9)
        elif t == 2:                     # negro brillante sobre blanco brillante
            fuera += bytes([0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81, 0x78])
        elif t == 3:                     # con el bit de parpadeo puesto
            fuera += bytes([0xFF, 0x00, 0xFF, 0x00, 0xF0, 0x0F, 0xF0, 0x0F, 0xB8])
        else:
            fuera += bytes([(t * 7 + y * 31) & 0xFF for y in range(8)]) \
                + bytes([(t * 5) & 0x7F])
    return bytes(fuera)


def escribe_png_crudo(ruta, ancho, alto, prof, color, lineas, paleta=None):
    """Un PNG con los parametros que se le pidan, para probar el lector.

    `lineas` son los bytes de cada fila YA empaquetados, sin el byte de filtro.
    """
    def trozo(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))

    crudo = b"".join(b"\x00" + bytes(l) for l in lineas)
    d = (b"\x89PNG\r\n\x1a\n"
         + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, prof, color, 0, 0, 0)))
    if paleta is not None:
        d += trozo(b"PLTE", b"".join(bytes(c) for c in paleta))
    d += trozo(b"IDAT", zlib.compress(crudo, 9)) + trozo(b"IEND", b"")
    open(ruta, "wb").write(d)


class TestIdaYVuelta(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.png = os.path.join(self.dir.name, "lienzo.png")

    def tearDown(self):
        self.dir.cleanup()

    def test_sacar_y_meter_no_mueve_un_byte(self):
        """Abrir el lienzo y guardarlo sin tocar nada tiene que devolver
        EXACTAMENTE los mismos 1152 bytes. Es la propiedad que lo sostiene
        todo: sin ella, cada vuelta ensuciaria el parche con cambios que nadie
        ha pedido."""
        tabla = tabla_de_muestra()
        T.saca_lienzo(tabla, self.png)
        vuelta, avisos = T.lee_lienzo(self.png, tabla)
        self.assertEqual(vuelta, tabla)
        self.assertEqual(avisos, [])
        self.assertEqual(T.tiles_tocados(tabla, vuelta), [])

    def test_los_tiles_que_no_se_pueden_reconstruir_se_respetan(self):
        """El tile 0 lleva tinta blanca sobre papel blanco: se ve un cuadrado
        liso y el dibujo esta debajo, invisible. El 1 es negro sobre negro. Si
        se recodificaran mirando la imagen, esos ocho bytes se perderian."""
        tabla = tabla_de_muestra()
        T.saca_lienzo(tabla, self.png)
        vuelta, _ = T.lee_lienzo(self.png, tabla)
        for t in (0, 1, 2, 3):
            self.assertEqual(vuelta[t * 9:(t + 1) * 9], tabla[t * 9:(t + 1) * 9],
                             "el tile %d no volvio como estaba" % t)

    def test_el_parpadeo_se_conserva_al_repintar(self):
        """El bit 7 del atributo no se ve en el PNG, asi que se hereda del tile
        que habia. Repintar un tile no puede encender ni apagar el parpadeo."""
        tabla = bytearray(tabla_de_muestra())
        self.assertTrue(tabla[3 * 9 + 8] & 0x80, "el tile 3 tenia que parpadear")
        T.saca_lienzo(bytes(tabla), self.png)
        # se repinta el tile 3 entero de un color que no tenia
        ancho, alto, filas = T.lee_png(self.png)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        for y in range(8):
            for x in range(8):
                indices[y][24 + x] = 4 if (x + y) % 2 else 0    # verde y negro
        T.escribe_png(self.png, ancho, alto, indices, T.ZX)
        vuelta, _ = T.lee_lienzo(self.png, bytes(tabla))
        self.assertNotEqual(vuelta[3 * 9:4 * 9], bytes(tabla[3 * 9:4 * 9]))
        self.assertTrue(vuelta[3 * 9 + 8] & 0x80, "se perdio el parpadeo del tile 3")

    def test_repintar_un_tile_solo_cambia_ese_tile(self):
        """Lo que se pinta en una casilla no puede salpicar a las de al lado."""
        tabla = tabla_de_muestra()
        T.saca_lienzo(tabla, self.png)
        ancho, alto, filas = T.lee_png(self.png)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        # el tile 20 (columna 4, fila 1) a rayas rojas sobre negro
        ox, oy = (20 % T.COLS) * 8, (20 // T.COLS) * 8
        for y in range(8):
            for x in range(8):
                indices[oy + y][ox + x] = 2 if y % 2 else 0
        T.escribe_png(self.png, ancho, alto, indices, T.ZX)
        vuelta, _ = T.lee_lienzo(self.png, tabla)
        self.assertEqual(T.tiles_tocados(tabla, vuelta), [20])
        nueve = vuelta[20 * 9:21 * 9]
        self.assertEqual(nueve[:8], bytes([0, 0xFF, 0, 0xFF, 0, 0xFF, 0, 0xFF]))
        self.assertEqual(nueve[8] & 0x07, 2, "la tinta tenia que ser roja")
        self.assertEqual((nueve[8] >> 3) & 0x07, 0, "el papel tenia que ser negro")
        self.assertEqual(nueve[8] & 0x40, 0, "no habia colores brillantes")

    def test_el_dibujo_que_vuelve_se_ve_igual_que_el_que_se_pinto(self):
        """La prueba de verdad no son los bytes sino el dibujo: sea cual sea el
        reparto de tinta y papel, lo que se vuelve a dibujar con los bytes
        nuevos tiene que ser pixel a pixel lo que habia en el PNG."""
        tabla = tabla_de_muestra()
        T.saca_lienzo(tabla, self.png)
        ancho, alto, filas = T.lee_png(self.png)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        for t in (7, 40, 99):                       # tres casillas cualesquiera
            ox, oy = (t % T.COLS) * 8, (t // T.COLS) * 8
            for y in range(8):
                for x in range(8):
                    indices[oy + y][ox + x] = 15 if (x * y + t) % 3 else 9
        T.escribe_png(self.png, ancho, alto, indices, T.ZX)
        vuelta, _ = T.lee_lienzo(self.png, tabla)
        self.assertEqual(T.tabla_a_indices(vuelta), indices)


class TestLasReglasDelSpectrum(unittest.TestCase):
    """Las dos que no se pueden saltar, cazadas con nombre y apellidos."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.png = os.path.join(self.dir.name, "lienzo.png")
        self.tabla = tabla_de_muestra()

    def tearDown(self):
        self.dir.cleanup()

    def _pinta(self, tile, colores):
        T.saca_lienzo(self.tabla, self.png)
        ancho, alto, filas = T.lee_png(self.png)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        ox, oy = (tile % T.COLS) * 8, (tile // T.COLS) * 8
        for y in range(8):
            for x in range(8):
                indices[oy + y][ox + x] = colores[(y * 8 + x) % len(colores)]
        T.escribe_png(self.png, ancho, alto, indices, T.ZX)

    def test_tres_colores_en_una_casilla_no_cuelan(self):
        self._pinta(33, [0, 2, 4])
        with self.assertRaises(T.ErrorDeLienzo) as e:
            T.lee_lienzo(self.png, self.tabla)
        self.assertIn("casilla 33", str(e.exception))
        self.assertIn("DOS", str(e.exception))

    def test_mezclar_brillante_y_normal_no_cuela(self):
        """Rojo normal y blanco brillante en la misma casilla: el bit de brillo
        es uno solo para los dos colores, asi que no hay atributo que lo diga."""
        self._pinta(50, [2, 15])
        with self.assertRaises(T.ErrorDeLienzo) as e:
            T.lee_lienzo(self.png, self.tabla)
        self.assertIn("casilla 50", str(e.exception))
        self.assertIn("brillante", str(e.exception))

    def test_el_negro_se_lleva_bien_con_los_dos_brillos(self):
        """El negro es #000000 con brillo y sin el, asi que no obliga a nada:
        negro con blanco brillante es una casilla legal."""
        self._pinta(51, [0, 15])
        vuelta, _ = T.lee_lienzo(self.png, self.tabla)
        self.assertEqual(vuelta[51 * 9 + 8] & 0x40, 0x40)

    def test_un_lienzo_de_otro_tamano_se_rechaza(self):
        escribe_png_crudo(self.png, 64, 64, 8, 2, [bytes(64 * 3)] * 64)
        with self.assertRaises(T.ErrorDeLienzo) as e:
            T.lee_lienzo(self.png, self.tabla)
        self.assertIn("128x64", str(e.exception))
        self.assertIn("No lo escales", str(e.exception))


class TestElLectorDePng(unittest.TestCase):
    """El lienzo vuelve del editor que le toque, no del que lo escribio."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.png = os.path.join(self.dir.name, "x.png")

    def tearDown(self):
        self.dir.cleanup()

    def test_rgb_de_8_bits(self):
        filas = [bytes([1, 2, 3, 4, 5, 6]), bytes([7, 8, 9, 10, 11, 12])]
        escribe_png_crudo(self.png, 2, 2, 8, 2, filas)
        self.assertEqual(T.lee_png(self.png)[2],
                         [[(1, 2, 3), (4, 5, 6)], [(7, 8, 9), (10, 11, 12)]])

    def test_rgba_de_8_bits(self):
        filas = [bytes([1, 2, 3, 255, 4, 5, 6, 255])]
        escribe_png_crudo(self.png, 2, 1, 8, 6, filas)
        self.assertEqual(T.lee_png(self.png)[2], [[(1, 2, 3), (4, 5, 6)]])

    def test_rgb_de_16_bits(self):
        """GIMP guarda a 16 bits sin avisar; nos quedamos con el byte alto."""
        filas = [struct.pack(">6H", 0x1122, 0x3344, 0x5566, 0x7788, 0x99AA, 0xBBCC)]
        escribe_png_crudo(self.png, 2, 1, 16, 2, filas)
        self.assertEqual(T.lee_png(self.png)[2], [[(0x11, 0x33, 0x55),
                                                   (0x77, 0x99, 0xBB)]])

    def test_gris_de_8_bits(self):
        escribe_png_crudo(self.png, 2, 1, 8, 0, [bytes([0, 255])])
        self.assertEqual(T.lee_png(self.png)[2], [[(0, 0, 0), (255, 255, 255)]])

    def test_gris_de_1_bit(self):
        escribe_png_crudo(self.png, 8, 1, 1, 0, [bytes([0b10100000])])
        fila = T.lee_png(self.png)[2][0]
        self.assertEqual([p[0] for p in fila], [255, 0, 255, 0, 0, 0, 0, 0])

    def test_indexado_de_4_bits(self):
        paleta = [(10, 20, 30), (40, 50, 60), (70, 80, 90)]
        escribe_png_crudo(self.png, 4, 1, 4, 3, [bytes([0x01, 0x20])], paleta)
        self.assertEqual(T.lee_png(self.png)[2],
                         [[(10, 20, 30), (40, 50, 60), (70, 80, 90), (10, 20, 30)]])

    def test_los_cinco_filtros(self):
        """Un PNG escrito por otro programa llega con los filtros puestos; hay
        que deshacerlos bien o sale un revoltijo. Se comprueba con el escritor
        del propio zlib a maxima compresion, que los usa todos."""
        ancho, alto = 32, 32
        original = [[((x * 7 + y * 13) % 256, (x * 3) % 256, (y * 5) % 256)
                     for x in range(ancho)] for y in range(alto)]
        # se escribe a pelo probando CADA filtro en una linea distinta
        lineas, previa = [], bytearray(ancho * 3)
        crudo = b""
        for y in range(alto):
            linea = bytearray()
            for p in original[y]:
                linea += bytes(p)
            filtro = y % 5
            salida = bytearray(linea)
            for x in range(len(linea) - 1, -1, -1):
                izq = linea[x - 3] if x >= 3 else 0
                arr = previa[x]
                dia = previa[x - 3] if x >= 3 else 0
                if filtro == 1:
                    salida[x] = (linea[x] - izq) & 0xFF
                elif filtro == 2:
                    salida[x] = (linea[x] - arr) & 0xFF
                elif filtro == 3:
                    salida[x] = (linea[x] - ((izq + arr) >> 1)) & 0xFF
                elif filtro == 4:
                    salida[x] = (linea[x] - T._paeth(izq, arr, dia)) & 0xFF
            crudo += bytes([filtro]) + bytes(salida)
            previa = linea
            lineas.append(linea)

        def trozo(tipo, datos):
            return (struct.pack(">I", len(datos)) + tipo + datos
                    + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))

        open(self.png, "wb").write(
            b"\x89PNG\r\n\x1a\n"
            + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0))
            + trozo(b"IDAT", zlib.compress(crudo, 9)) + trozo(b"IEND", b""))
        self.assertEqual(T.lee_png(self.png)[2], original)

    def test_el_entrelazado_se_rechaza_con_su_nombre(self):
        """Adam7 no se lee. Lo importante es que lo diga, porque leerlo como si
        no lo fuera sacaria un revoltijo con pinta de dibujo."""
        escribe_png_crudo(self.png, 2, 1, 8, 2, [bytes(6)])
        d = bytearray(open(self.png, "rb").read())
        d[8 + 8 + 12] = 1                      # el byte de entrelazado del IHDR
        d[8 + 8 + 13:8 + 8 + 17] = struct.pack(
            ">I", zlib.crc32(bytes(d[8 + 4:8 + 8 + 13])) & 0xFFFFFFFF)
        open(self.png, "wb").write(bytes(d))
        with self.assertRaises(T.ErrorDeLienzo) as e:
            T.lee_png(self.png)
        self.assertIn("entrelazado", str(e.exception))

    def test_la_transparencia_se_rechaza_con_su_nombre(self):
        """Un pixel transparente no es tinta ni papel: no hay forma de saber que
        color queria. Mejor parar que inventarse un negro."""
        escribe_png_crudo(self.png, 2, 1, 8, 6, [bytes([1, 2, 3, 0, 4, 5, 6, 255])])
        with self.assertRaises(T.ErrorDeLienzo) as e:
            T.lee_png(self.png)
        self.assertIn("transparent", str(e.exception))

    def test_un_color_que_no_es_del_zx_se_acerca_y_se_avisa(self):
        """Si el editor mete un color de fuera de la paleta no se para el
        parche, pero tampoco se hace en silencio: se coge el mas parecido y se
        dice cual, cuantos pixels y por que color se cambia."""
        tabla = tabla_de_muestra()
        T.saca_lienzo(tabla, self.png)
        ancho, alto, filas = T.lee_png(self.png)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        paleta = list(T.ZX)
        paleta[4] = (10, 200, 10)              # un verde que no es el del ZX
        ox, oy = (60 % T.COLS) * 8, (60 // T.COLS) * 8
        for y in range(8):
            for x in range(8):
                indices[oy + y][ox + x] = 4 if x % 2 else 0
        T.escribe_png(self.png, ancho, alto, indices, paleta)
        vuelta, avisos = T.lee_lienzo(self.png, tabla)
        self.assertEqual(len(avisos), 1)
        self.assertIn("#0AC80A", avisos[0])
        self.assertIn("verde", avisos[0])
        self.assertEqual(vuelta[60 * 9 + 8] & 0x07, 4)


class TestElLienzoDelRepositorio(unittest.TestCase):
    """El PNG que se reparte, mirado sin necesidad de la cinta."""

    def test_existe_y_mide_lo_que_tiene_que_medir(self):
        self.assertTrue(os.path.exists(LIENZO), "falta %s" % LIENZO)
        ancho, alto, _ = T.lee_png(LIENZO)
        self.assertEqual((ancho, alto), (T.ANCHO, T.ALTO))
        self.assertEqual((ancho, alto), (128, 64))

    def test_solo_gasta_colores_del_zx(self):
        """Un color de fuera de la paleta se acercaria al mas parecido y el
        dibujo saldria distinto del que se ve. El lienzo que se reparte no
        puede traer ni uno."""
        _, _, filas = T.lee_png(LIENZO)
        fuera = {p for f in filas for p in f if p not in T.ZX}
        self.assertEqual(fuera, set(), "colores que no son del ZX: %s" % fuera)

    def test_ninguna_casilla_se_salta_las_reglas(self):
        """Las 128, uno por uno, contra las dos reglas del Spectrum. Se usa una
        referencia en blanco para que ninguna se libre por parecerse a la cinta:
        aqui se codifican todas."""
        _, _, filas = T.lee_png(LIENZO)
        indices = [[T.canon(T._indice_del_color(p)[0]) for p in f] for f in filas]
        for t in range(T.TILES):
            ox, oy = (t % T.COLS) * 8, (t // T.COLS) * 8
            celda = [[indices[oy + y][ox + x] for x in range(8)] for y in range(8)]
            T._codifica(celda, bytes(9), t)     # levanta ErrorDeLienzo si no cuadra


if __name__ == "__main__":
    unittest.main()
