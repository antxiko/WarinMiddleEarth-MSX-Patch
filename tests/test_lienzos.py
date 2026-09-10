#!/usr/bin/env python3
"""Comprobaciones de los lienzos: tiles del mapa, sprites de batalla y fuente.

Casi ninguna necesita la cinta: se fabrican tablas a mano, se sacan al PNG y se
vuelven a leer. Lo que se comprueba es que la IDA Y VUELTA es exacta en las tres
hojas, que el lector de PNG traga lo que escupen los editores de verdad, y que
las dos reglas del ZX -dos colores por casilla y los dos del mismo brillo- se
cazan con un mensaje que dice que casilla y por que, en vez de elegir por su
cuenta.

Las que SI necesitan la cinta (work/alto.raw) se saltan si no esta, como el
resto de la serie: el repositorio no trae la cinta.
"""
import os
import struct
import sys
import tempfile
import unittest
import zlib

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import lienzos as L  # noqa: E402

PARCHE = os.path.join(RAIZ, "src", "parche")
ALTO = os.path.join(RAIZ, "work", "alto.raw")


def tabla_de_muestra(hoja):
    """Una tabla inventada para esa hoja, con los casos raros dentro.

    No vale con dibujos bonitos: hacen falta los que NO se pueden reconstruir
    mirando la imagen, que son los que justifican la regla de "si se ve igual,
    devuelve los bytes de siempre".
    """
    if hoja.nombre == "tiles":
        fuera = bytearray()
        for t in range(hoja.cuantos):
            if t == 0:                   # tinta y papel iguales, con dibujo debajo
                fuera += bytes([0x10, 0x41, 0x62, 0x5C, 0x40, 0x40, 0x40, 0x40, 0x7F])
            elif t == 1:                 # todo a cero: negro sobre negro
                fuera += bytes(9)
            elif t == 2:                 # negro brillante sobre blanco brillante
                fuera += bytes([0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81, 0x78])
            elif t == 3:                 # con el bit de parpadeo puesto
                fuera += bytes([0xFF, 0x00, 0xFF, 0x00, 0xF0, 0x0F, 0xF0, 0x0F, 0xB8])
            else:
                fuera += bytes([(t * 7 + y * 31) & 0xFF for y in range(8)]) \
                    + bytes([(t * 5) & 0x7F])
        return bytes(fuera)
    if hoja.nombre == "sprites":
        fuera = bytearray()
        for s in range(hoja.cuantos):
            for i in range(16):
                m = (s * 3 + i * 17) & 0xFF
                b = (s * 11 + i * 7) & 0xFF
                fuera += bytes([m, b & ~m & 0xFF])   # nada de dibujo bajo la mascara
            if s == 0:
                fuera[0:32] = bytes([0xFF, 0x00] * 16)   # entero transparente
        return bytes(fuera)
    return bytes([(c * 13 + y * 29) & 0xFF for c in range(hoja.cuantos)
                  for y in range(8)])


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


def indices_de(png, hoja):
    """Vuelve a leer un lienzo como indices, para poder repintarlo en un test."""
    _, _, filas, _ = L.lee_png(png)
    return [[L._indice_del_color(p, hoja)[0] for p in f] for f in filas]


class TestIdaYVuelta(unittest.TestCase):
    """La propiedad que lo sostiene todo, en las tres hojas."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.dir.cleanup()

    def png(self, hoja):
        return os.path.join(self.dir.name, hoja.png)

    def test_sacar_y_meter_no_mueve_un_byte(self):
        """Abrir un lienzo y guardarlo sin tocar nada tiene que devolver
        EXACTAMENTE los mismos bytes. Sin esto, cada vuelta ensuciaria el parche
        con cambios que nadie ha pedido."""
        for hoja in L.HOJAS:
            tabla = tabla_de_muestra(hoja)
            L.saca_lienzo(tabla, hoja, self.png(hoja))
            vuelta, avisos = L.lee_lienzo(self.png(hoja), tabla, hoja)
            self.assertEqual(vuelta, tabla, hoja.nombre)
            self.assertEqual(avisos, [], hoja.nombre)
            self.assertEqual(L.tocados(tabla, vuelta, hoja), [], hoja.nombre)

    def test_cada_lienzo_mide_lo_que_dice_su_hoja(self):
        esperado = {"tiles": (128, 64), "sprites": (176, 128), "fuente": (128, 64)}
        for hoja in L.HOJAS:
            L.saca_lienzo(tabla_de_muestra(hoja), hoja, self.png(hoja))
            ancho, alto, _, _ = L.lee_png(self.png(hoja))
            self.assertEqual((ancho, alto), (hoja.px_ancho, hoja.px_alto))
            self.assertEqual((ancho, alto), esperado[hoja.nombre], hoja.nombre)

    def test_cada_dibujo_cae_en_su_sitio_y_solo_en_el_suyo(self):
        """El sitio de la entrada n en el lienzo no puede solaparse con el de
        ninguna otra, o repintar una estropearia a su vecina."""
        for hoja in L.HOJAS:
            visto = {}
            for n in range(hoja.cuantos):
                ox, oy = hoja.sitio(n)
                self.assertLessEqual(ox + hoja.ancho, hoja.px_ancho)
                self.assertLessEqual(oy + hoja.alto, hoja.px_alto)
                for y in range(hoja.alto):
                    for x in range(hoja.ancho):
                        p = (ox + x, oy + y)
                        self.assertNotIn(p, visto, "%s: %d pisa a %s"
                                         % (hoja.nombre, n, visto.get(p)))
                        visto[p] = n
            self.assertEqual(len(visto), hoja.px_ancho * hoja.px_alto, hoja.nombre)

    def test_los_dibujos_que_no_se_pueden_reconstruir_se_respetan(self):
        """El tile 0 de la muestra lleva tinta blanca sobre papel blanco: se ve
        un cuadrado liso y el dibujo esta debajo, invisible. El 1 es negro sobre
        negro, y el sprite 0 es transparente entero. Si se recodificaran mirando
        la imagen, esos bytes se perderian."""
        for hoja, cuales in ((L.POR_NOMBRE["tiles"], (0, 1, 2, 3)),
                             (L.POR_NOMBRE["sprites"], (0,))):
            tabla = tabla_de_muestra(hoja)
            L.saca_lienzo(tabla, hoja, self.png(hoja))
            vuelta, _ = L.lee_lienzo(self.png(hoja), tabla, hoja)
            for n in cuales:
                self.assertEqual(hoja.bytes_de(vuelta, n), hoja.bytes_de(tabla, n),
                                 "%s %d no volvio como estaba" % (hoja.nombre, n))

    def test_repintar_uno_solo_cambia_ese(self):
        """Lo que se pinta en un dibujo no puede salpicar a los de al lado."""
        for hoja, cual in ((L.POR_NOMBRE["tiles"], 20),
                           (L.POR_NOMBRE["sprites"], 33),
                           (L.POR_NOMBRE["fuente"], 65)):
            tabla = tabla_de_muestra(hoja)
            L.saca_lienzo(tabla, hoja, self.png(hoja))
            ind = indices_de(self.png(hoja), hoja)
            ox, oy = hoja.sitio(cual)
            for y in range(hoja.alto):
                for x in range(hoja.ancho):
                    ind[oy + y][ox + x] = (len(hoja.paleta) - 1) if y % 2 else 0
            L.escribe_png(self.png(hoja), hoja.px_ancho, hoja.px_alto, ind, hoja.paleta)
            vuelta, _ = L.lee_lienzo(self.png(hoja), tabla, hoja)
            self.assertEqual(L.tocados(tabla, vuelta, hoja), [cual], hoja.nombre)

    def test_el_dibujo_que_vuelve_se_ve_igual_que_el_que_se_pinto(self):
        """La prueba de verdad no son los bytes sino el dibujo: sea cual sea el
        reparto interno, lo que se vuelve a dibujar con los bytes nuevos tiene
        que ser pixel a pixel lo que habia en el PNG."""
        for hoja in L.HOJAS:
            tabla = tabla_de_muestra(hoja)
            L.saca_lienzo(tabla, hoja, self.png(hoja))
            ind = indices_de(self.png(hoja), hoja)
            for n in (7, 40, 99):
                ox, oy = hoja.sitio(n)
                for y in range(hoja.alto):
                    for x in range(hoja.ancho):
                        v = (x * y + n) % len(hoja.paleta)
                        if hoja.paleta is L.ZX_EN_MSX:   # sin saltarse las reglas
                            v = 15 if (x * y + n) % 3 else 9
                        ind[oy + y][ox + x] = v
            L.escribe_png(self.png(hoja), hoja.px_ancho, hoja.px_alto, ind, hoja.paleta)
            vuelta, _ = L.lee_lienzo(self.png(hoja), tabla, hoja)
            # Se comparan los COLORES, no los indices: dos indices distintos
            # pueden ser el mismo color -el blanco del ZX con brillo y sin el
            # acaban los dos en el blanco del MSX- y lo que se prueba aqui es
            # que el dibujo que vuelve se VE igual que el que se pinto.
            def colores(rejilla):
                return [[hoja.paleta[i] for i in f] for f in rejilla]
            self.assertEqual(colores(L.a_indices(vuelta, hoja)),
                             colores(ind), hoja.nombre)

    def test_el_parpadeo_se_conserva_al_repintar(self):
        """El bit 7 del atributo no se ve en el PNG, asi que se hereda del tile
        que habia. Repintar no puede encender ni apagar el parpadeo."""
        hoja = L.POR_NOMBRE["tiles"]
        tabla = tabla_de_muestra(hoja)
        self.assertTrue(tabla[3 * 9 + 8] & 0x80, "el tile 3 tenia que parpadear")
        L.saca_lienzo(tabla, hoja, self.png(hoja))
        ind = indices_de(self.png(hoja), hoja)
        ox, oy = hoja.sitio(3)
        for y in range(8):
            for x in range(8):
                ind[oy + y][ox + x] = 4 if (x + y) % 2 else 0    # verde y negro
        L.escribe_png(self.png(hoja), hoja.px_ancho, hoja.px_alto, ind, hoja.paleta)
        vuelta, _ = L.lee_lienzo(self.png(hoja), tabla, hoja)
        self.assertNotEqual(hoja.bytes_de(vuelta, 3), hoja.bytes_de(tabla, 3))
        self.assertTrue(vuelta[3 * 9 + 8] & 0x80, "se perdio el parpadeo del tile 3")

    def test_la_goma_del_editor_vale_como_transparente_en_los_sprites(self):
        """El lienzo de los sprites declara su transparencia de verdad (tRNS),
        asi que el editor la enseña como tal; si la devuelve como pixel con alfa
        a cero -borrado con la goma-, tambien cuenta. Y si se aplana, el color
        del fondo que queda debajo sigue valiendo, que es la otra mitad."""
        hoja = L.POR_NOMBRE["sprites"]
        tabla = tabla_de_muestra(hoja)
        L.saca_lienzo(tabla, hoja, self.png(hoja))
        ind = indices_de(self.png(hoja), hoja)
        # se reescribe como RGBA con los transparentes en alfa 0
        lineas = []
        for y in range(hoja.px_alto):
            fila = bytearray()
            for x in range(hoja.px_ancho):
                if ind[y][x] == L.TRANSPARENTE:
                    fila += bytes([0, 0, 0, 0])
                else:
                    fila += bytes(L.SPRITE[ind[y][x]]) + b"\xff"
            lineas.append(bytes(fila))
        rgba = os.path.join(self.dir.name, "rgba.png")
        escribe_png_crudo(rgba, hoja.px_ancho, hoja.px_alto, 8, 6, lineas)
        vuelta, avisos = L.lee_lienzo(rgba, tabla, hoja)
        self.assertEqual(vuelta, tabla)
        self.assertEqual(avisos, [])


class TestLasReglasDelSpectrum(unittest.TestCase):
    """Las dos que no se pueden saltar, cazadas con nombre y apellidos."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.hoja = L.POR_NOMBRE["tiles"]
        self.png = os.path.join(self.dir.name, "tiles.png")
        self.tabla = tabla_de_muestra(self.hoja)

    def tearDown(self):
        self.dir.cleanup()

    def _pinta(self, tile, colores):
        L.saca_lienzo(self.tabla, self.hoja, self.png)
        ind = indices_de(self.png, self.hoja)
        ox, oy = self.hoja.sitio(tile)
        for y in range(8):
            for x in range(8):
                ind[oy + y][ox + x] = colores[(y * 8 + x) % len(colores)]
        L.escribe_png(self.png, self.hoja.px_ancho, self.hoja.px_alto, ind,
                     self.hoja.paleta)

    def test_tres_colores_en_una_casilla_no_cuelan(self):
        self._pinta(33, [0, 2, 4])
        with self.assertRaises(L.ErrorDeLienzo) as e:
            L.lee_lienzo(self.png, self.tabla, self.hoja)
        self.assertIn("casilla 33", str(e.exception))
        self.assertIn("DOS", str(e.exception))

    def test_mezclar_brillante_y_normal_no_cuela(self):
        """Rojo oscuro (atributo rojo sin brillo) y verde claro (verde CON
        brillo) en la misma casilla: el bit de brillo es uno solo para los dos
        colores, asi que no hay atributo que pueda decir eso."""
        self._pinta(50, [2, 12])
        with self.assertRaises(L.ErrorDeLienzo) as e:
            L.lee_lienzo(self.png, self.tabla, self.hoja)
        self.assertIn("casilla 50", str(e.exception))
        self.assertIn("brillo", str(e.exception))

    def test_los_cuatro_colores_ciegos_al_brillo_no_obligan_a_nada(self):
        """El negro, el magenta, el cian y el blanco salen con el MISMO color
        del MSX lleven brillo o no -las dos tablas de 0x04CE y 0x04D6 les dan lo
        mismo-, asi que ninguno de los cuatro le impone brillo a su casilla y se
        llevan bien con cualquier compañero."""
        self.assertEqual(L.EXIGE_BRILLO, {1, 2, 4, 6})
        for tile, otro in ((51, 0), (52, 3), (53, 5), (54, 7)):
            for pareja in (2, 12):        # rojo sin brillo y verde con brillo
                self._pinta(tile, [otro, pareja])
                vuelta, _ = L.lee_lienzo(self.png, self.tabla, self.hoja)
                attr = vuelta[tile * 9 + 8]
                brillo = 8 if attr & 0x40 else 0
                visto = {L.ZX_EN_MSX[(attr & 7) + brillo],
                         L.ZX_EN_MSX[((attr >> 3) & 7) + brillo]}
                self.assertEqual(visto, {L.ZX_EN_MSX[otro], L.ZX_EN_MSX[pareja]},
                                 "tile %d con el color %d" % (tile, otro))

    def test_los_sprites_y_la_fuente_no_tienen_esa_limitacion(self):
        """No llevan atributo, asi que ni hay dos colores por casilla ni brillo
        compartido: cualquier reparto de sus estados vale."""
        for nombre in ("sprites", "fuente"):
            hoja = L.POR_NOMBRE[nombre]
            tabla = tabla_de_muestra(hoja)
            png = os.path.join(self.dir.name, hoja.png)
            L.saca_lienzo(tabla, hoja, png)
            ind = indices_de(png, hoja)
            ox, oy = hoja.sitio(9)
            for y in range(hoja.alto):
                for x in range(hoja.ancho):
                    ind[oy + y][ox + x] = (x + y) % len(hoja.paleta)
            L.escribe_png(png, hoja.px_ancho, hoja.px_alto, ind, hoja.paleta)
            vuelta, _ = L.lee_lienzo(png, tabla, hoja)      # no levanta nada
            self.assertEqual(L.tocados(tabla, vuelta, hoja), [9], nombre)

    def test_un_lienzo_de_otro_tamano_se_rechaza(self):
        escribe_png_crudo(self.png, 64, 64, 8, 2, [bytes(64 * 3)] * 64)
        with self.assertRaises(L.ErrorDeLienzo) as e:
            L.lee_lienzo(self.png, self.tabla, self.hoja)
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
        self.assertEqual(L.lee_png(self.png)[2],
                         [[(1, 2, 3), (4, 5, 6)], [(7, 8, 9), (10, 11, 12)]])

    def test_rgba_de_8_bits(self):
        filas = [bytes([1, 2, 3, 255, 4, 5, 6, 0])]
        escribe_png_crudo(self.png, 2, 1, 8, 6, filas)
        ancho, alto, filas, opacos = L.lee_png(self.png)
        self.assertEqual(filas, [[(1, 2, 3), (4, 5, 6)]])
        self.assertEqual(opacos, [[True, False]])

    def test_rgb_de_16_bits(self):
        """GIMP guarda a 16 bits sin avisar; nos quedamos con el byte alto."""
        filas = [struct.pack(">6H", 0x1122, 0x3344, 0x5566, 0x7788, 0x99AA, 0xBBCC)]
        escribe_png_crudo(self.png, 2, 1, 16, 2, filas)
        self.assertEqual(L.lee_png(self.png)[2], [[(0x11, 0x33, 0x55),
                                                   (0x77, 0x99, 0xBB)]])

    def test_gris_de_8_bits(self):
        escribe_png_crudo(self.png, 2, 1, 8, 0, [bytes([0, 255])])
        self.assertEqual(L.lee_png(self.png)[2], [[(0, 0, 0), (255, 255, 255)]])

    def test_gris_de_1_bit(self):
        escribe_png_crudo(self.png, 8, 1, 1, 0, [bytes([0b10100000])])
        fila = L.lee_png(self.png)[2][0]
        self.assertEqual([p[0] for p in fila], [255, 0, 255, 0, 0, 0, 0, 0])

    def test_indexado_de_4_bits(self):
        paleta = [(10, 20, 30), (40, 50, 60), (70, 80, 90)]
        escribe_png_crudo(self.png, 4, 1, 4, 3, [bytes([0x01, 0x20])], paleta)
        self.assertEqual(L.lee_png(self.png)[2],
                         [[(10, 20, 30), (40, 50, 60), (70, 80, 90), (10, 20, 30)]])

    def test_los_cinco_filtros(self):
        """Un PNG escrito por otro programa llega con los filtros puestos; hay
        que deshacerlos bien o sale un revoltijo."""
        ancho, alto = 32, 32
        original = [[((x * 7 + y * 13) % 256, (x * 3) % 256, (y * 5) % 256)
                     for x in range(ancho)] for y in range(alto)]
        previa, crudo = bytearray(ancho * 3), b""
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
                    salida[x] = (linea[x] - L._paeth(izq, arr, dia)) & 0xFF
            crudo += bytes([filtro]) + bytes(salida)
            previa = linea

        def trozo(tipo, datos):
            return (struct.pack(">I", len(datos)) + tipo + datos
                    + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))

        open(self.png, "wb").write(
            b"\x89PNG\r\n\x1a\n"
            + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0))
            + trozo(b"IDAT", zlib.compress(crudo, 9)) + trozo(b"IEND", b""))
        self.assertEqual(L.lee_png(self.png)[2], original)

    def test_el_entrelazado_se_rechaza_con_su_nombre(self):
        """Adam7 no se lee. Lo importante es que lo diga, porque leerlo como si
        no lo fuera sacaria un revoltijo con pinta de dibujo."""
        escribe_png_crudo(self.png, 2, 1, 8, 2, [bytes(6)])
        d = bytearray(open(self.png, "rb").read())
        d[8 + 8 + 12] = 1                      # el byte de entrelazado del IHDR
        d[8 + 8 + 13:8 + 8 + 17] = struct.pack(
            ">I", zlib.crc32(bytes(d[8 + 4:8 + 8 + 13])) & 0xFFFFFFFF)
        open(self.png, "wb").write(bytes(d))
        with self.assertRaises(L.ErrorDeLienzo) as e:
            L.lee_png(self.png)
        self.assertIn("entrelazado", str(e.exception))

    def test_la_transparencia_se_rechaza_donde_no_la_hay(self):
        """En los tiles y en la fuente un pixel transparente no es ningun color:
        no hay forma de saber que queria. Mejor parar que inventarse un negro.
        (En los sprites SI vale: alli el transparente es un estado.)"""
        hoja = L.POR_NOMBRE["fuente"]
        lineas = [bytes([0, 0, 0, 0] * hoja.px_ancho) for _ in range(hoja.px_alto)]
        escribe_png_crudo(self.png, hoja.px_ancho, hoja.px_alto, 8, 6, lineas)
        with self.assertRaises(L.ErrorDeLienzo) as e:
            L.lee_lienzo(self.png, tabla_de_muestra(hoja), hoja)
        self.assertIn("transparent", str(e.exception))

    def test_un_color_de_fuera_de_la_paleta_se_acerca_y_se_avisa(self):
        """Si el editor mete un color de fuera no se para el parche, pero
        tampoco se hace en silencio: se coge el mas parecido y se dice cual,
        cuantos pixels y por que color se cambia."""
        hoja = L.POR_NOMBRE["tiles"]
        tabla = tabla_de_muestra(hoja)
        L.saca_lienzo(tabla, hoja, self.png)
        ind = indices_de(self.png, hoja)
        paleta = list(hoja.paleta)
        paleta[4] = (10, 200, 10)              # un verde que no es del MSX
        ox, oy = hoja.sitio(60)
        for y in range(8):
            for x in range(8):
                ind[oy + y][ox + x] = 4 if x % 2 else 0
        L.escribe_png(self.png, hoja.px_ancho, hoja.px_alto, ind, paleta)
        vuelta, avisos = L.lee_lienzo(self.png, tabla, hoja)
        self.assertEqual(len(avisos), 1)
        self.assertIn("#0AC80A", avisos[0])
        self.assertIn("verde", avisos[0])
        self.assertEqual(vuelta[60 * 9 + 8] & 0x07, 4)


class TestLosLienzosDelRepositorio(unittest.TestCase):
    """Los tres PNG que se reparten, mirados sin necesidad de la cinta."""

    def test_el_fondo_de_los_sprites_es_el_de_la_web(self):
        """En el lienzo de los sprites NO hay color-clave inventado: el
        transparente lleva el mismo FONDO que las laminas ya publicadas
        (tools/render_graficos.py), y ademas va declarado transparente en el
        propio PNG para que el editor lo enseñe como tal."""
        import render_graficos
        self.assertEqual(L.SPRITE[L.TRANSPARENTE], render_graficos.FONDO)
        hoja = L.POR_NOMBRE["sprites"]
        raw = open(os.path.join(PARCHE, hoja.png), "rb").read()
        self.assertIn(b"tRNS", raw, "al lienzo de sprites le falta la transparencia")
        _, _, filas, opacos = L.lee_png(os.path.join(PARCHE, hoja.png))
        self.assertEqual(sum(1 for f in opacos for o in f if not o), 12489)
        self.assertFalse([p for f in filas for p in f if p == (255, 0, 255)],
                         "ha vuelto el magenta de chroma-key")

    def test_los_sprites_necesitan_los_tres_estados(self):
        """Que no se caiga en la tentacion de quitar uno: los tres se usan. Un
        pixel negro OPACO -mascara 0, dibujo 0- escribe papel encima de lo que
        hubiera, y uno transparente lo deja pasar. Se ven igual sobre papel,
        pero son bytes distintos, y los dos estan en el lienzo."""
        hoja = L.POR_NOMBRE["sprites"]
        ind = indices_de(os.path.join(PARCHE, hoja.png), hoja)
        cuenta = {L.TRANSPARENTE: 0, L.NEGRO: 0, L.BLANCO: 0}
        for f in ind:
            for v in f:
                cuenta[v] += 1
        self.assertEqual(cuenta[L.TRANSPARENTE], 12489)
        self.assertEqual(cuenta[L.NEGRO], 2892)
        self.assertEqual(cuenta[L.BLANCO], 7147)

    def test_existen_y_miden_lo_que_tienen_que_medir(self):
        for hoja in L.HOJAS:
            ruta = os.path.join(PARCHE, hoja.png)
            self.assertTrue(os.path.exists(ruta), "falta %s" % ruta)
            ancho, alto, _, _ = L.lee_png(ruta)
            self.assertEqual((ancho, alto), (hoja.px_ancho, hoja.px_alto), hoja.nombre)

    def test_solo_gastan_colores_de_su_paleta(self):
        """Un color de fuera se acercaria al mas parecido y el dibujo saldria
        distinto del que se ve. Los lienzos que se reparten no traen ni uno."""
        for hoja in L.HOJAS:
            _, _, filas, _ = L.lee_png(os.path.join(PARCHE, hoja.png))
            fuera = {p for f in filas for p in f if p not in hoja.paleta}
            self.assertEqual(fuera, set(), "%s: %s" % (hoja.nombre, fuera))

    def test_ningun_tile_se_salta_las_reglas(self):
        """Los 128, uno a uno, contra las dos reglas del Spectrum. Se usa una
        referencia en blanco para que ninguno se libre por parecerse a la cinta:
        aqui se codifican todos."""
        hoja = L.POR_NOMBRE["tiles"]
        ind = indices_de(os.path.join(PARCHE, hoja.png), hoja)
        for n in range(hoja.cuantos):
            ox, oy = hoja.sitio(n)
            celda = [[ind[oy + y][ox + x] for x in range(8)] for y in range(8)]
            hoja.codifica(celda, bytes(9), n)   # levanta ErrorDeLienzo si no cuadra


class TestContraLaCinta(unittest.TestCase):
    """Las que necesitan work/alto.raw; se saltan si no esta."""

    def setUp(self):
        if not os.path.exists(ALTO):
            self.skipTest("falta work/alto.raw (haz `make extract` con tu cinta)")
        self.alto = open(ALTO, "rb").read()

    def test_los_tres_codecs_dibujan_igual_que_la_web(self):
        """El cotejo mas duro que hay a mano: tools/render_graficos.py ya dibuja
        estas tres hojas para la web, revisado y publicado. Si los codecs de
        aqui leyeran los bytes de otra manera -el zigzag de los sprites, el
        atributo de los tiles-, los dibujos no coincidirian. Se comparan PIXEL A
        PIXEL, no de lejos."""
        import render_graficos as R
        for hoja, saca, color in (
                (L.POR_NOMBRE["tiles"], R.tiles_del_mapa,
                 lambda i: L.ZX_EN_MSX[i]),
                (L.POR_NOMBRE["sprites"], R.sprites_de_batalla,
                 lambda i: None if i == L.TRANSPARENTE
                 else ((255, 255, 255) if i == L.BLANCO else (0, 0, 0))),
                (L.POR_NOMBRE["fuente"], R.fuente,
                 lambda i: (255, 255, 255) if i else (0, 0, 0))):
            ref = saca(self.alto)
            tabla = L.tabla_del_bloque(self.alto, hoja)
            self.assertEqual(len(ref), hoja.cuantos, hoja.nombre)
            for n in range(hoja.cuantos):
                mio = hoja.dibuja(hoja.bytes_de(tabla, n))
                for y in range(hoja.alto):
                    for x in range(hoja.ancho):
                        self.assertEqual(color(mio[y][x]), ref[n][y][x],
                                         "%s %d, pixel (%d,%d)" % (hoja.nombre, n, x, y))

    def test_la_cinta_va_y_vuelve_entera(self):
        """Las tres hojas de la cinta de verdad, no de una tabla inventada."""
        with tempfile.TemporaryDirectory() as d:
            for hoja in L.HOJAS:
                tabla = L.tabla_del_bloque(self.alto, hoja)
                png = os.path.join(d, hoja.png)
                L.saca_lienzo(tabla, hoja, png)
                vuelta, avisos = L.lee_lienzo(png, tabla, hoja)
                self.assertEqual(vuelta, tabla, hoja.nombre)
                self.assertEqual(avisos, [], hoja.nombre)

    # Los 122 tiles que el lienzo del repositorio repinta: TODOS menos los seis
    # del 97 al 102, que se quedaron con los bytes de la cinta. No es casualidad
    # ni descuido: de esos seis solo cambio el fondo, y el fondo era ya el mismo
    # color -el blanco del ZX y el blanco del MSX son el mismo color 15-, asi
    # que el dibujo que vuelve es identico al de la cinta y la regla de "lo que
    # no se toca" les devuelve sus bytes de siempre.
    TILES_REPINTADOS = [n for n in range(128) if not 97 <= n <= 102]

    def test_los_lienzos_del_repositorio_solo_repintan_tiles(self):
        """El mapa entero esta repintado desde el 2026-09-10, pero los SPRITES y
        la FUENTE tienen que seguir saliendo con los bytes de la cinta, sin
        recodificar. Si aparece uno de esos, algun lienzo se ha ensuciado por el
        camino (lo tipico: guardarlo escalado o con el color retocado)."""
        for hoja in L.HOJAS:
            tabla = L.tabla_del_bloque(self.alto, hoja)
            vuelta, avisos = L.lee_lienzo(os.path.join(PARCHE, hoja.png), tabla, hoja)
            esperado = self.TILES_REPINTADOS if hoja.nombre == "tiles" else []
            self.assertEqual(L.tocados(tabla, vuelta, hoja), esperado, hoja.nombre)
            self.assertEqual(avisos, [], hoja.nombre)

    def test_el_lienzo_de_los_tiles_no_pide_colores_imposibles(self):
        """Ni un solo pixel de un color que el juego no sepa poner en pantalla.
        Son doce de los quince del MSX: los otros tres -el verde medio, el rojo
        medio y el gris- no salen de las tablas de 0x04CE y 0x04D6, asi que no
        hay atributo del Spectrum capaz de producirlos."""
        hoja = L.POR_NOMBRE["tiles"]
        self.assertEqual(L.MSX_ALCANZABLES, [1, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 15])
        buenos = {L.MSX[c] for c in L.MSX_ALCANZABLES}
        _, _, filas, _ = L.lee_png(os.path.join(PARCHE, hoja.png))
        malos = {p for f in filas for p in f} - buenos
        self.assertEqual(malos, set(), "colores que el juego no puede dar: %s" % malos)


if __name__ == "__main__":
    unittest.main()
