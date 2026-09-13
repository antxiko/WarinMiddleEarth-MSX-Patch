#!/usr/bin/env python3
"""Coteja el MAPA GENERAL de la ROM nueva con el de la vieja, y el guante.

Dos cambios se ven en esta pantalla y los dos se comprueban aqui:

  EL MAPA YA DIBUJADO. La ROM nueva no recorre las 23.500 casillas: descomprime
  el lienzo de la ROM. Lo que se exige es que los 6.144 bytes que quedan en
  0x4000 en 0x81C1 sean LOS MISMOS que deja la ROM vieja recorriendolas, y que
  ademas sean los que dibuja tools/mapa_general.py, que es de donde salen. Tres
  caminos distintos al mismo byte.

  EL GUANTE COMO SPRITE. La ROM vieja lo ESTAMPA en el lienzo -y guarda en
  0x62FF los 24 bytes de fondo que tapa-; la nueva no lo toca y lo pone en los
  sprites 2 y 3. Asi que el lienzo de la nueva tiene que ser el de la vieja CON
  EL GUANTE BORRADO, que es lo que haria BORRA_EL_CURSOR (0x64DC) con esos 24
  bytes. Y lo que se ve en pantalla, igual: las dos imagenes, compuestas como
  las compone el VDP -sprites incluidos-, pixel a pixel.

De paso se comprueba lo que nadie mira y estropea cualquier cotejo: que la VRAM
de cada una es EXACTAMENTE su lienzo subido (si el VDP hubiera perdido un byte,
aqui se veria) y que los sprites de la vieja siguen todos aparcados en Y = 209.

Uso:
    coteja_mapa.py <dir nuevo> <dir viejo> <dir png> --plan <plan.json> --work <work>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mapa_general                                         # noqa: E402
import render_vram                                          # noqa: E402

LIENZO = 0x4000
TAM_BITMAP = 0x1800
TAM_LIENZO = 0x1B00             # bitmap y los 768 atributos
VRAM_SPRITES = 0x1B00
VRAM_PATRONES_SPRITE = 0x3800


class Mal(Exception):
    pass


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def estado(d, n):
    """El <n>.txt de la sonda: cursor, fondo guardado y direccion de pantalla."""
    fuera = {}
    with open(os.path.join(d, "%s.txt" % n)) as f:
        for linea in f:
            k, v = linea.split(None, 1)
            fuera[k] = v.strip()
    return fuera


def zx_a_vram(lienzo):
    """El lienzo del ZX (0x4000), tal y como lo sube 0x05BD a la tabla de
    patrones del SCREEN 2. Las dos disposiciones son distintas: en el ZX la
    linea de pixel manda sobre la fila de caracteres y en el MSX es al reves."""
    fuera = bytearray(TAM_BITMAP)
    for fila in range(24):
        for linea in range(8):
            for col in range(32):
                zx = ((fila // 8) << 11) | (linea << 8) | ((fila % 8) << 5) | col
                fuera[(fila // 8) * 2048 + (fila % 8) * 256 + col * 8 + linea] = lienzo[zx]
    return bytes(fuera)


def borra_el_guante(lienzo, fondo, direccion):
    """BORRA_EL_CURSOR (0x64DC): devuelve al lienzo los 24 bytes que el sprite
    por software guardo antes de taparlos. Tres por linea, ocho lineas, bajando
    a la manera del ZX y parando si se pasa de 0x5800."""
    fuera = bytearray(lienzo)
    h, l = direccion >> 8, direccion & 0xFF
    i = 0
    for _ in range(8):
        if h >= 0x58:
            break
        for b in range(3):
            fuera[((h << 8) | l) - LIENZO + b] = fondo[i]
            i += 1
        h = (h + 1) & 0xFF              # baja una linea de pixel
        if not h & 7:
            h = (h - 8) & 0xFF
            l += 0x20
            if l > 0xFF:
                l &= 0xFF
                h = (h + 8) & 0xFF
    return bytes(fuera)


def atributos_del_guante(plan, col, fila):
    g = plan["vista"]["guante"]
    y = (fila - 1) & 0xFF
    c = g["planos_colores"]
    return bytes([y, col, g["patron_a"], c[0], y, col, g["patron_b"], c[1]])


def caja_del_guante(col, fila):
    """Los 16x16 pixeles que el sprite puede tocar."""
    return [(x, y) for y in range(fila, fila + 16) for x in range(col, col + 16)]


def cotejo(nuevo, viejo, png, plan, work):
    fallos = []
    hechos = []

    def exige(ok, que):
        (hechos if ok else fallos).append(que)

    # ---------------------------------------------------- 1. el lienzo del mapa
    dibujado = mapa_general.dibuja_el_mapa(work)
    t_viejo = lee(os.path.join(viejo, "terreno.bin"))
    t_nuevo = lee(os.path.join(nuevo, "terreno.bin"))
    exige(t_viejo == dibujado,
          "el lienzo que deja la ROM VIEJA recorriendo el mapa es el que dibuja mapa_general.py")
    exige(t_nuevo == t_viejo,
          "el lienzo que descomprime la ROM NUEVA es el mismo, byte a byte")

    # ---------------------------------------------- 2. cada vuelta que se volco
    vueltas = sorted(int(f[:-4]) for f in os.listdir(nuevo) if f.endswith(".ram"))
    g = plan["vista"]["guante"]
    patrones_png = bytes.fromhex(g["planos"])
    for n in vueltas:
        ln = lee(os.path.join(nuevo, "%d.ram" % n))
        lv = lee(os.path.join(viejo, "%d.ram" % n))
        vn = lee(os.path.join(nuevo, "%d.vram" % n))
        vv = lee(os.path.join(viejo, "%d.vram" % n))
        en, ev = estado(nuevo, n), estado(viejo, n)
        col, fila = int(en["col"]), int(en["fila"])
        exige((col, fila) == (int(ev["col"]), int(ev["fila"])),
              "vuelta %d: las dos ROMs tienen el cursor en el mismo sitio (%d,%d)" % (n, col, fila))

        # la VRAM de cada una es su lienzo, subido
        for cual, lienzo, vram in (("nueva", ln, vn), ("vieja", lv, vv)):
            exige(vram[:TAM_BITMAP] == zx_a_vram(lienzo),
                  "vuelta %d: la VRAM de la ROM %s es su lienzo subido, sin perder un byte" % (n, cual))

        # el lienzo de la nueva es el de la vieja con el guante borrado
        exige(int(ev["borrado"]) == 0x21,
              "vuelta %d: en la ROM vieja el guante esta estampado (0x64D9 es un `ld hl,nn`)" % n)
        exige(int(en["borrado"]) == 0xC9,
              "vuelta %d: en la ROM nueva no hay nada que borrar: 0x64D9 se queda en `ret`" % n)
        d = int(ev["direccion"][2:4] + ev["direccion"][0:2], 16)
        limpio = borra_el_guante(lv, bytes.fromhex(ev["fondo"]), d)
        exige(ln[:TAM_LIENZO] == limpio[:TAM_LIENZO],
              "vuelta %d: el lienzo de la nueva es el de la vieja con el guante borrado" % n)

        # los sprites
        exige(vv[VRAM_SPRITES:VRAM_SPRITES + 128]
              == b"".join(bytes([209, 0, s, 1]) for s in range(32)),
              "vuelta %d: la ROM vieja no ensena ningun sprite" % n)
        exige(vn[VRAM_SPRITES + 8:VRAM_SPRITES + 16] == atributos_del_guante(plan, col, fila),
              "vuelta %d: los sprites 2 y 3 de la nueva estan en (%d,%d)" % (n, col, fila))
        exige(vn[VRAM_SPRITES:VRAM_SPRITES + 8] == bytes([209, 0, 0, 1, 209, 0, 1, 1]),
              "vuelta %d: los sprites 0 y 1 -el cursor de la vista- siguen aparcados" % n)
        o = g["vram_patrones"]
        exige(vn[o:o + 64] == patrones_png,
              "vuelta %d: los patrones del guante son los de %s" % (n, g["png"]))

        # y lo que se ve: pixel a pixel, con los sprites compuestos
        regs_n = [int(en["regs"][i * 2:i * 2 + 2], 16) for i in range(8)]
        regs_v = [int(ev["regs"][i * 2:i * 2 + 2], 16) for i in range(8)]
        w, h, fn = render_vram.pinta(vn, regs_n, escala=1)
        _w, _h, fv = render_vram.pinta(vv, regs_v, escala=1)
        distintos = [(x, y) for y in range(192) for x in range(256)
                     if fn[y][x * 3:x * 3 + 3] != fv[y][x * 3:x * 3 + 3]]
        caja = set(caja_del_guante(col, fila))
        fuera = [p for p in distintos if p not in caja]
        exige(not distintos,
              "vuelta %d: las dos pantallas son IGUALES pixel a pixel (%d distintos, %d fuera del guante)"
              % (n, len(distintos), len(fuera)))
        if png:
            os.makedirs(png, exist_ok=True)
            render_vram.png(w, h, fn, os.path.join(png, "%d_nueva.png" % n))
            render_vram.png(_w, _h, fv, os.path.join(png, "%d_vieja.png" % n))

    for q in hechos:
        print("  OK   %s" % q)
    for q in fallos:
        print("  MAL  %s" % q)
    print("%d comprobaciones, %d fallos" % (len(hechos) + len(fallos), len(fallos)))
    return 1 if fallos else 0


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    nuevo, viejo, png = argv[1], argv[2], argv[3]
    plan_ruta, work = None, "work"
    resto = argv[4:]
    while resto:
        o = resto.pop(0)
        if o == "--plan":
            plan_ruta = resto.pop(0)
        elif o == "--work":
            work = resto.pop(0)
        else:
            raise SystemExit("opcion desconocida: %s" % o)
    with open(plan_ruta) as f:
        plan = json.load(f)
    assert "mapa" in plan and "vista" in plan, "ese plan no lleva el mapa ni el guante"
    return cotejo(nuevo, viejo, png, plan, work)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
