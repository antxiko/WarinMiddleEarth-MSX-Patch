#!/usr/bin/env python3
"""Coteja POR PIXEL la vista de cerca de dos ROMs: la de la tabla de nombres y la de antes.

Los volcados los hace tools/omsx_coteja_vista.tcl en los mismos instantes del
juego para las dos ROMs. Lo que se exige, instante a instante:

  - que la pantalla de caracteres (0x5E00) sea la misma en las dos: si no, el
    juego no estaba en el mismo estado y comparar no diria nada;
  - en los instantes de la VISTA, que lo que el VDP ensena -dibujado con
    tools/render_vram.py de la VRAM y los registros- sea identico pixel a
    pixel. Y que las dos VRAM NO sean iguales: la nueva tiene que llevar en
    0x1800 la pantalla de caracteres y la de referencia la identidad, que si
    no el cotejo seria trivial;
  - en los instantes de BITMAP -el menu y el mapa-, que la VRAM entera sea
    identica byte a byte: es la prueba de que el guardian devolvio la tabla de
    nombres a la identidad antes de que nadie pintara.

Con --encendida se mira ademas la pasada con la pantalla ENCENDIDA de la ROM
nueva: la tabla de nombres tiene que ser la pantalla de caracteres y los
patrones y colores los que salen de la cinta, sin un byte perdido.

Los PNG se escriben en el directorio que se diga, para MIRARLOS.

Uso: coteja_vista.py <dir nueva> <dir referencia> <dir png>
                     [--roms <nueva.rom> <referencia.rom>]
                     [--encendida <dir> --work <dir>]
Sale con 1 si algo de lo exigido no cuadra.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_vram                                          # noqa: E402

VISTAS = ("vista_a", "vista_b", "vista_c", "vista_d")
BITMAPS = ("menu_r", "menu_ordenes", "mapa")
PANTALLA = 0x5E00 - 0x4000      # donde cae 0x5E00 en el .ram, que empieza en 0x4000
NOMBRES = slice(0x1800, 0x1B00)
VISIBLE = slice(0x0000, 0x3800)  # patrones, nombres, sprites y colores: todo lo que se ve


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def volcado(d, nombre):
    vram = lee(os.path.join(d, nombre + ".vram"))
    with open(os.path.join(d, nombre + ".regs")) as f:
        regs = [int(x, 16) for x in f.read().split()][:8]
    ram = lee(os.path.join(d, nombre + ".ram"))
    return vram, regs, ram


def pantalla_de_caracteres(ram):
    return ram[PANTALLA:PANTALLA + 850]


def filas_de_nombres(ram):
    p = pantalla_de_caracteres(ram)
    return b"".join(p[f * 34:f * 34 + 32] for f in range(24))


def identidad():
    return bytes(range(256)) * 3


def pixeles(vram, regs):
    _w, _h, filas = render_vram.pinta(vram, regs, escala=1)
    return filas


def guarda_png(vram, regs, ruta):
    w, h, filas = render_vram.pinta(vram, regs, escala=2)
    render_vram.png(w, h, filas, ruta)


def diferencia(a, b, ruta_diff):
    """Cuantos pixeles cambian; y un PNG con los que cambian en rojo sobre la
    imagen A en gris, para ver DONDE."""
    n = 0
    filas = []
    for fa, fb in zip(a, b):
        fila = []
        for i in range(0, len(fa), 3):
            if fa[i:i + 3] != fb[i:i + 3]:
                n += 1
                fila.extend((255, 0, 0) * 2)
            else:
                g = (fa[i] + fa[i + 1] + fa[i + 2]) // 6 + 64
                fila.extend((g, g, g) * 2)
        filas.append(fila)
        filas.append(fila)
    if n:
        render_vram.png(512, 384, filas, ruta_diff)
    return n


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    nueva, ref, pngs = argv[1:4]
    roms = encendida = work = None
    i = 4
    while i < len(argv):
        if argv[i] == "--roms":
            roms = (argv[i + 1], argv[i + 2]); i += 3
        elif argv[i] == "--encendida":
            encendida = argv[i + 1]; i += 2
        elif argv[i] == "--work":
            work = argv[i + 1]; i += 2
        else:
            print("argumento desconocido:", argv[i]); return 2
    os.makedirs(pngs, exist_ok=True)
    fallos = 0

    def falla(que):
        nonlocal fallos
        fallos += 1
        print("  FALLO: " + que)

    # La trampa del cotejo trivial: dos ficheros distintos de verdad.
    if roms:
        a, b = (lee(r) for r in roms)
        if a == b:
            falla("las dos ROMs son IDENTICAS: no hay nada que cotejar")
        else:
            print("  las dos ROMs difieren en %d bytes: hay cotejo" % sum(x != y for x, y in zip(a, b)))

    instantes = 0
    for inst in VISTAS + BITMAPS:
        en_nueva = os.path.exists(os.path.join(nueva, inst + ".vram"))
        en_ref = os.path.exists(os.path.join(ref, inst + ".vram"))
        if not en_nueva and not en_ref:
            continue
        if en_nueva != en_ref:
            falla("%s: solo lo volco una de las dos ROMs; no siguieron el mismo camino" % inst)
            continue
        instantes += 1
        vn, rn, ramn = volcado(nueva, inst)
        vr, rr, ramr = volcado(ref, inst)
        if pantalla_de_caracteres(ramn) != pantalla_de_caracteres(ramr):
            falla("%s: la pantalla de caracteres de 0x5E00 no es la misma en las dos ROMs" % inst)
        pn, pr = pixeles(vn, rn), pixeles(vr, rr)
        guarda_png(vn, rn, os.path.join(pngs, inst + "_nueva.png"))
        guarda_png(vr, rr, os.path.join(pngs, inst + "_referencia.png"))
        d = diferencia(pn, pr, os.path.join(pngs, inst + "_DIFERENCIA.png"))
        print("  %-13s pixel a pixel: %s" % (inst, "IDENTICAS" if d == 0 else "%d pixeles distintos" % d))
        if d:
            falla("%s: las dos imagenes no son iguales (ver %s_DIFERENCIA.png)" % (inst, inst))
        if inst in VISTAS:
            if vn[NOMBRES] != filas_de_nombres(ramn):
                falla("%s: la ROM nueva no lleva en 0x1800 la pantalla de caracteres" % inst)
            if vr[NOMBRES] != identidad():
                falla("%s: la ROM de referencia no lleva la tabla de nombres identidad" % inst)
            if vn[VISIBLE] == vr[VISIBLE]:
                falla("%s: las dos VRAM son iguales byte a byte: el cotejo seria trivial" % inst)
            else:
                print("  %-13s las VRAM difieren en %d bytes y la imagen no: es lo que se buscaba"
                      % ("", sum(x != y for x, y in zip(vn[VISIBLE], vr[VISIBLE]))))
        else:
            if vn[VISIBLE] != vr[VISIBLE]:
                primero = next(i for i in range(0x3800) if vn[i] != vr[i])
                falla("%s: en modo bitmap la VRAM tiene que ser identica byte a byte; difiere desde 0x%04X"
                      % (inst, primero))
            else:
                print("  %-13s VRAM identica byte a byte (bitmap, con la identidad devuelta)" % "")
            if vn[NOMBRES] != identidad():
                falla("%s: la ROM nueva no ha devuelto la tabla de nombres a la identidad" % inst)
    if instantes < 4:
        falla("solo hay %d instantes cotejados; se esperaban al menos vista_a, vista_b, menu_r y vista_c" % instantes)

    if encendida:
        if not work:
            falla("--encendida necesita --work para saber que patrones esperar")
        else:
            import corre_nombres
            bajo = lee(os.path.join(work, "bajo.raw"))
            alto = lee(os.path.join(work, "alto.raw"))
            ram = bytearray(0x10000)
            ram[corre_nombres.ORG_ALTO:corre_nombres.ORG_ALTO + len(alto)] = alto
            ram[corre_nombres.TABLA_COLOR:corre_nombres.TABLA_COLOR + 256] = corre_nombres.tabla_de_color(bajo)
            esperado_p = corre_nombres.patrones_esperados(ram)
            esperado_c = corre_nombres.colores_esperados(ram)
            vistos = 0
            for inst in VISTAS:
                if not os.path.exists(os.path.join(encendida, inst + ".vram")):
                    continue
                vistos += 1
                v, regs, r = volcado(encendida, inst)
                if regs[1] & 0x40 == 0:
                    falla("%s (encendida): la pantalla estaba apagada, R1 = 0x%02X" % (inst, regs[1]))
                perdidos = (sum(x != y for x, y in zip(v[NOMBRES], filas_de_nombres(r)))
                            + sum(x != y for x, y in zip(v[:0x1800], esperado_p))
                            + sum(x != y for x, y in zip(v[0x2000:0x3800], esperado_c)))
                print("  %-13s con la pantalla ENCENDIDA: %s"
                      % (inst, "ni un byte perdido" if perdidos == 0 else "%d bytes perdidos" % perdidos))
                if perdidos:
                    falla("%s: con la pantalla encendida se pierden bytes" % inst)
                guarda_png(v, regs, os.path.join(pngs, inst + "_encendida.png"))
            if not vistos:
                falla("la pasada con la pantalla encendida no volco ninguna vista")

    if fallos:
        print("  %d fallos" % fallos)
        return 1
    print("  todo lo exigido coincide: la vista por tabla de nombres ensena lo mismo que antes")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
