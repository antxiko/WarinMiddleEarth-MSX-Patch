#!/usr/bin/env python3
"""Ejecuta la rutina de la vista por tabla de nombres (src/cartucho/nombres.asm), en Python.

Hermano de corre_finales.py y montado sobre su interprete: le anade el VDP -los
puertos 0x98 y 0x99, con la VRAM detras- y las pocas instrucciones que
nombres.asm usa y finales.asm no. Lo que se comprueba sin arrancar nada:

  1. que CARACTERES_A_NOMBRES deja en la tabla de nombres (0x1800) los 32
     primeros bytes de cada una de las 24 filas de 0x5E00, y nada mas;
  2. que la primera vez -MODO_NOMBRES a 0- sube antes los 256 patrones y sus
     colores, replicados en los tres tercios, y que son los que salen de la
     fuente de 0xC800, de los dibujos de 0x9E00 y de la tabla de 0x0200. Lo
     esperado se calcula aqui, aparte, de los cuerpos de la cinta;
  3. que el GUARDIAN, metido en 0x044B, devuelve la tabla de nombres a la
     identidad cuando toca, no escribe nada cuando no toca, y deja la
     direccion de VRAM que le pidieron con BC, DE y HL intactos.

Como corre_finales, el interprete solo conoce las instrucciones que la rutina
usa, a proposito: si alguien le anade una, el test se para.

Uso:  corre_nombres.py <rom> <plan.json> <work>      con informe
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corre_finales                                        # noqa: E402
from corre_finales import CENTINELA, Maquina                # noqa: E402

CARGA_BAJO = 0x0190
ORG_ALTO = 0x9E00           # el bloque alto, ya recolocado por 0x0190
FUENTE = 0xC800
DIBUJOS = 0x9E00
TABLA_COLOR = 0x0200
PANTALLA = 0x5E00
ATRIBUTO_TEXTO = 0x763F     # el operando del `ld a,078h` de 0x763E: 0x78 en la cinta, 0x70 con el parche
# Las dos tablas de ocho colores de ATRIBUTO_A_COLOR (0x049F): sin brillo en
# 0x04CE y con brillo en 0x04D6. Son del bloque bajo.
COLORES_ZX = (0x04CE, 0x04D6)


class Vdp:
    """Los dos puertos del TMS9918: 0x99 recibe la direccion en dos bytes -el
    bajo y luego el alto, con el bit 6 puesto para escribir- y 0x98 los datos,
    que van subiendo la direccion solos."""

    def __init__(self):
        self.vram = bytearray(0x4000)
        self.primero = None         # el byte bajo de la direccion, a la espera del alto
        self.dir = 0
        self.escritura = False
        self.escritos = 0           # cuantos bytes han entrado por 0x98
        self.direcciones = []       # cada puntero que se puso, en orden

    def out99(self, v):
        if self.primero is None:
            self.primero = v
            return
        assert not (v & 0x80), "se escribe un registro del VDP (0x%02X): la rutina no deberia" % v
        self.dir = ((v & 0x3F) << 8) | self.primero
        self.escritura = bool(v & 0x40)
        self.direcciones.append((self.dir, self.escritura))
        self.primero = None

    def out98(self, v):
        assert self.escritura, "se escribe en la VRAM con el puntero puesto para LEER"
        self.vram[self.dir] = v & 0xFF
        self.dir = (self.dir + 1) & 0x3FFF
        self.escritos += 1


class Z80(corre_finales.Z80):
    """Las instrucciones de nombres.asm que finales.asm no usa, el VDP, IX y
    las TRAMPAS: direcciones del juego que MI_PINTA llama (CELDA_DEL_MAPA,
    DIBUJA_EL_TROZO_DE_MAPA, TAPA_LOS_BORDES) y que aqui no se ejecutan sino
    que se sustituyen por una funcion de Python que apunta con que la
    llamaron. Asi se comprueba lo que MI_PINTA hace ALREDEDOR de ellas sin
    interpretar medio bloque medio."""

    def __init__(self, maquina, vdp, pc, sp, trampas=None):
        super().__init__(maquina, pc, sp)
        self.vdp = vdp
        self.ix = 0
        self.trampas = trampas or {}
        self.llamadas = []          # (direccion de la trampa, lo que apunto)

    def paso(self):
        if self.pc in self.trampas:
            self.llamadas.append((self.pc, self.trampas[self.pc](self)))
            self.pc = self.pop()
            return
        op = self.m.lee(self.pc)
        if op == 0xDD:                                  # el prefijo de IX
            self.n()
            sub = self.n()
            if sub == 0x19:                             # add ix,de
                self.ix = (self.ix + self.de) & 0xFFFF
            else:
                raise NotImplementedError("DD %02X en 0x%04X" % (sub, self.pc - 2))
        elif op == 0xC6:                                # add a,n
            self.n(); v = self.a + self.n(); self.cy = v > 255; self.a = v & 0xFF; self.z = self.a == 0
        elif op == 0x85:                                # add a,l
            self.n(); v = self.a + self.l; self.cy = v > 255; self.a = v & 0xFF; self.z = self.a == 0
        elif op == 0x8C:                                # adc a,h
            self.n(); v = self.a + self.h + (1 if self.cy else 0); self.cy = v > 255; self.a = v & 0xFF; self.z = self.a == 0
        elif op == 0x91:                                # sub c
            self.n(); v = self.a - self.c; self.cy = v < 0; self.a = v & 0xFF; self.z = self.a == 0
        elif op == 0xB8:                                # cp b
            self.n(); self.z = self.a == self.b; self.cy = self.a < self.b
        elif op == 0xD6:                                # sub n
            self.n(); v = self.a - self.n(); self.cy = v < 0; self.a = v & 0xFF; self.z = self.a == 0
        elif op == 0x3D:                                # dec a
            self.n(); self.a = (self.a - 1) & 0xFF; self.z = self.a == 0
        elif op == 0x4F:                                # ld c,a
            self.n(); self.c = self.a
        elif op == 0x67:                                # ld h,a
            self.n(); self.h = self.a
        elif op == 0x36:                                # ld (hl),n
            self.n(); self.m.escribe(self.hl, self.n())
        elif op == 0xD3:                                # out (n),a
            self.n()
            puerto = self.n()
            if puerto == 0x98:
                self.vdp.out98(self.a)
            elif puerto == 0x99:
                self.vdp.out99(self.a)
            else:
                raise AssertionError("out (0x%02X): la rutina solo escribe 0x98 y 0x99" % puerto)
        elif op == 0x06:                                # ld b,n
            self.n(); self.b = self.n()
        elif op == 0x0D:                                # dec c (toca Z, no C)
            self.n(); self.c = (self.c - 1) & 0xFF; self.z = self.c == 0
        elif op == 0x1B:                                # dec de (no toca flags)
            self.n(); self.de = (self.de - 1) & 0xFFFF
        elif op == 0x6F:                                # ld l,a
            self.n(); self.l = self.a
        elif op == 0x7D:                                # ld a,l
            self.n(); self.a = self.l
        elif op == 0xAF:                                # xor a
            self.n(); self.a = 0; self.z = True; self.cy = False
        elif op == 0xCC:                                # call z,nn
            self.n()
            destino = self.nn()
            if self.z:
                self.push(self.pc)
                self.pc = destino
        elif op == 0xD5:                                # push de
            self.n(); self.push(self.de)
        elif op == 0xD1:                                # pop de
            self.n(); self.de = self.pop()
        # --- y las de la variante CON SOMBRA (`--vista-sombra`)
        elif op == 0x1A:                                # ld a,(de)
            self.n(); self.a = self.m.lee(self.de)
        elif op == 0x77:                                # ld (hl),a
            self.n(); self.m.escribe(self.hl, self.a)
        elif op == 0xBE:                                # cp (hl)
            self.n()
            v = self.m.lee(self.hl); self.z = self.a == v; self.cy = self.a < v
        elif op == 0x2C:                                # inc l (toca Z, no C)
            self.n(); self.l = (self.l + 1) & 0xFF; self.z = self.l == 0
        elif op == 0x24:                                # inc h
            self.n(); self.h = (self.h + 1) & 0xFF; self.z = self.h == 0
        elif op == 0xC3:                                # jp nn
            self.n(); self.pc = self.nn()
        else:
            super().paso()


# ------------------------------------------------------------ lo esperado
def tabla_de_color(bajo):
    """Los 256 bytes de 0x0200: atributo ZX -> byte de color del MSX, como los
    calcula 0x049F y los deja 0x5E15. Bits 0-2 la tinta, 3-5 el papel, 6 el
    brillo, que elige la tabla; el 7 (FLASH) no cuenta."""
    sin, con = (bajo[d - CARGA_BAJO:d - CARGA_BAJO + 8] for d in COLORES_ZX)
    tabla = bytearray(256)
    for a in range(256):
        t = con if a & 0x40 else sin
        tabla[a] = (t[a & 7] << 4) | t[(a >> 3) & 7]
    return bytes(tabla)


def patrones_esperados(ram):
    """Un tercio: la fuente tal cual y los 128 dibujos sin su noveno byte. Tres."""
    fuente = bytes(ram[FUENTE:FUENTE + 1024])
    dibujos = b"".join(bytes(ram[DIBUJOS + i * 9:DIBUJOS + i * 9 + 8]) for i in range(128))
    return (fuente + dibujos) * 3


def colores_esperados(ram):
    """Un tercio: el color del atributo 0x78 para los 128 caracteres, y el del
    noveno byte de cada dibujo, ocho veces cada uno. Tres."""
    t = ram[TABLA_COLOR:TABLA_COLOR + 256]
    texto = bytes([t[ram[ATRIBUTO_TEXTO]]]) * 1024
    dibujos = b"".join(bytes([t[ram[DIBUJOS + i * 9 + 8]]]) * 8 for i in range(128))
    return (texto + dibujos) * 3


def filas_de_nombres(pantalla):
    """Los 32 primeros bytes de cada una de las 24 filas de 34."""
    return b"".join(pantalla[f * 34:f * 34 + 32] for f in range(24))


# ------------------------------------------------------------- la maquina
def monta(rom, plan, bajo, alto, ranura_cart=1, ranura_ram=3, medio=None):
    """La maquina como la deja el juego al entrar en la vista: las cuatro
    paginas en RAM, el bloque bajo en 0x0190 con el parche del guardian, el
    alto recolocado en 0x9E00 -de ahi salen los dibujos y la fuente-, la tabla
    de color de 0x0200 y la rutina en su sitio. Con `medio`, tambien el bloque
    medio recolocado en 0x5E00 (con el parche de 0x71A4), para entrar en
    MI_PINTA por donde entra el juego."""
    v = plan["vista"]
    m = Maquina(rom, ranura_cart, ranura_ram)
    m.ram[CARGA_BAJO:CARGA_BAJO + len(bajo)] = bajo
    m.ram[ORG_ALTO:ORG_ALTO + len(alto)] = alto
    if medio is not None:
        m.ram[ORG_MEDIO:ORG_MEDIO + len(medio)] = medio
    m.ram[TABLA_COLOR:TABLA_COLOR + 256] = tabla_de_color(bajo)
    m.ram[v["ram"]:v["ram"] + v["bytes"]] = rom[v["rom"]:v["rom"] + v["bytes"]]
    for q in v["parches"]:
        nuevo = bytes.fromhex(q["nuevo"])
        m.ram[q["dir"]:q["dir"] + len(nuevo)] = nuevo
    return m


# ------------------------------------------------- MI_PINTA y sus trampas
ORG_MEDIO = 0x5E00
PINTA_LA_VISTA = 0x71A4
MODO_DE_LA_VISTA = 0x71CF
CELDA_DEL_MAPA = 0x8108
DIBUJA_EL_TROZO = 0x7643
TAPA_LOS_BORDES = 0x7129
MAPA = 0xCC00 + 0x67            # donde CELDA_DEL_MAPA empieza a contar: 0xCC00 mas 0x67 de margen
ANCHO_MAPA = 102                # bytes por columna del mapa


def celda_del_mapa(h, l):
    """Lo que CELDA_DEL_MAPA (0x8108) devuelve en IX para (H, L), sin las banderas."""
    return (MAPA + ANCHO_MAPA * (l & 0x7F) + (h & 0x7F)) & 0xFFFF


def trampas_del_juego(relleno=None):
    """Las tres rutinas del juego que MI_PINTA llama, sustituidas: CELDA_DEL_MAPA
    calcula IX como la de verdad; DIBUJA_EL_TROZO_DE_MAPA apunta la esquina que
    le dan y rellena la pantalla de caracteres con algo que dependa de ella
    -asi se ve que lo que se guarda en la cache es lo que se pinto-; y
    TAPA_LOS_BORDES apunta el HL con el que la llaman."""
    def celda(z):
        z.ix = celda_del_mapa(z.h, z.l)
        z.a = z.m.lee(z.ix)
        return ("hl", z.hl)

    def dibuja(z):
        for o in range(850):
            v = relleno(z.ix, o) if relleno else ((z.ix + o * 7) & 0x7F) | 0x80
            if v is not None:                   # None: esa celda se deja como estaba
                z.m.escribe(PANTALLA + o, v)
        return ("ix", z.ix)

    def tapa(z):
        return ("hl", z.hl)

    return {CELDA_DEL_MAPA: celda, DIBUJA_EL_TROZO: dibuja, TAPA_LOS_BORDES: tapa}


def corre_pinta(m, plan, hl, modo, cache_valida=0, esquina=(0, 0), ultimo_modo=0,
                cache=None, sp=0x5BFF, desde=None):
    """MI_PINTA con el cursor en HL y el modo en 0x71CF, con el estado de la
    rutina que se diga: si la cache vale, la esquina del ultimo repintado, el
    modo de entonces y los 850 bytes de la cache. Entra por 0x71A4 -el `jp`
    del parche- si el bloque medio esta en RAM, o directo a MI_PINTA.
    Devuelve la CPU, con las llamadas a las trampas apuntadas."""
    c = plan["vista"]["cursor"]
    m.ram[MODO_DE_LA_VISTA] = modo
    m.ram[c["cache_valida"]] = cache_valida
    m.ram[c["esquina_h"]], m.ram[c["esquina_l"]] = esquina
    m.ram[c["ultimo_modo"]] = ultimo_modo
    if cache is not None:
        m.ram[c["cache"]:c["cache"] + 850] = cache
    if desde is None:
        desde = PINTA_LA_VISTA if m.ram[PINTA_LA_VISTA] == 0xC3 else c["pinta"]
    z = Z80(m, Vdp(), desde, sp, trampas_del_juego())
    z.hl = hl
    z.push(CENTINELA)
    z.corre()
    return z


MUEVE_POR_EL_MAPA = 0x734B


def corre_mueve(m, plan, hl, mando, cuadros, ultimo, sp=0x5BFF):
    """MI_MUEVE con el mando en A y la posicion en HL, con el contador de
    cuadros y el cuadro del ultimo paso que se digan. MUEVE_POR_EL_MAPA va
    con una trampa que apunta con que A y HL la llaman."""
    c = plan["vista"]["cursor"]
    m.ram[c["cuadros"]] = cuadros
    m.ram[c["ultimo_paso"]] = ultimo

    def mueve(z):
        return ("a_hl", (z.a, z.hl))

    z = Z80(m, Vdp(), c["mueve"], sp, {MUEVE_POR_EL_MAPA: mueve})
    z.a, z.hl = mando, hl
    z.push(CENTINELA)
    z.corre()
    return z


def atributos_esperados(plan, ci, ri, modo):
    """Los ocho bytes de ATRIBUTOS para el cursor en la celda (ci, ri) de la
    ventana y ese modo: Y una linea por encima, X, el patron y el color."""
    c = plan["vista"]["cursor"]
    mi = c["modos"]["0x%02x" % modo] if ("0x%02x" % modo) in c["modos"] else c["modos"]["0x%02X" % modo]
    colores = c["planos_colores"]
    y, x = (16 * ri - 1) & 0xFF, (16 * ci) & 0xFF
    return bytes([y, x, mi * 8, colores[mi * 2], y, x, mi * 8 + 4, colores[mi * 2 + 1]])


def corre_vista(m, plan, pantalla, modo, sp=0x5BFF, vdp=None):
    """CARACTERES_A_NOMBRES con esa pantalla de caracteres en 0x5E00 y ese
    MODO_NOMBRES. Devuelve el VDP y la CPU al volver. Con `vdp` se sigue sobre
    la VRAM de una llamada anterior -lo que necesita la variante con sombra-,
    con la cuenta de escrituras a cero."""
    v = plan["vista"]
    m.ram[PANTALLA:PANTALLA + len(pantalla)] = pantalla
    m.ram[v["modo"]] = modo
    if vdp is None:
        vdp = Vdp()
    vdp.escritos, vdp.direcciones = 0, []
    z = Z80(m, vdp, v["entrada"], sp)
    z.push(CENTINELA)
    z.corre()
    return vdp, z


def corre_guardian(m, plan, hl, modo, sp=0x5BFF):
    """VRAM_A_ESCRIBIR (0x044B), ya parcheado, como lo llama el juego: con la
    direccion en HL. BC y DE llevan valores conocidos para ver si salen igual."""
    v = plan["vista"]
    m.ram[v["modo"]] = modo
    vdp = Vdp()
    z = Z80(m, vdp, 0x044B, sp)
    z.hl, z.bc, z.de = hl, 0x1234, 0x5678
    z.push(CENTINELA)
    z.corre()
    return vdp, z


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    with open(argv[1], "rb") as fh:
        rom = fh.read()
    with open(argv[2]) as fh:
        plan = json.load(fh)
    if "vista" not in plan:
        print("ese plan no lleva la vista por tabla de nombres (--vista)")
        return 2
    with open(os.path.join(argv[3], "bajo.raw"), "rb") as fh:
        bajo = fh.read()
    with open(os.path.join(argv[3], "alto.raw"), "rb") as fh:
        alto = fh.read()
    pantalla = bytes((i * 7 + 3) & 0xFF for i in range(850))
    for modo in (0, 1):
        m = monta(rom, plan, bajo, alto)
        vdp, z = corre_vista(m, plan, pantalla, modo)
        nombres_ok = bytes(vdp.vram[0x1800:0x1B00]) == filas_de_nombres(pantalla)
        print("CARACTERES_A_NOMBRES con MODO_NOMBRES=%d: %d instrucciones, %d bytes a la VRAM; nombres %s"
              % (modo, z.pasos, vdp.escritos, "OK" if nombres_ok else "MAL"))
        if modo == 0:
            print("   patrones %s, colores %s, modo queda en %d"
                  % ("OK" if bytes(vdp.vram[:0x1800]) == patrones_esperados(m.ram) else "MAL",
                     "OK" if bytes(vdp.vram[0x2000:0x3800]) == colores_esperados(m.ram) else "MAL",
                     m.ram[plan["vista"]["modo"]]))
    for modo in (1, 0):
        m = monta(rom, plan, bajo, alto)
        vdp, z = corre_guardian(m, plan, 0x2345, modo)
        print("GUARDIAN con MODO_NOMBRES=%d: %d bytes a la VRAM, identidad %s, modo queda en %d, direccion %s"
              % (modo, vdp.escritos,
                 "OK" if bytes(vdp.vram[0x1800:0x1B00]) == bytes(range(256)) * 3 else "no",
                 m.ram[plan["vista"]["modo"]], vdp.direcciones[-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
