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
import cursor                                               # noqa: E402
import lienzos                                              # noqa: E402
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


def color_msx(atributo):
    """Atributo ZX -> byte de color del MSX, por las dos tablas del juego."""
    t = lienzos.TABLA_CON if atributo & 0x40 else lienzos.TABLA_SIN
    return (t[atributo & 7] << 4) | t[(atributo >> 3) & 7]


def traduce_el_panel(plan):
    """Las dos traducciones que hay que aplicarle a la ROM VIEJA para poder
    compararla con la nueva cuando el panel cambia de color: una para los
    atributos ZX de la copia en RAM y otra para los bytes de color de la VRAM.

    El cambio es una PERMUTACION de dos atributos: el panel se queda con el de
    la vista y la marca de unidad se va al que el panel deja libre. Sin
    --panel las dos traducciones son la identidad."""
    at = list(range(256))
    col = list(range(256))
    q = plan.get("panel")
    if q:
        for viejo, nuevo in ((q["orig"], q["atributo"]), (q["marca_orig"], q["marca"])):
            at[viejo] = nuevo
            col[color_msx(viejo)] = color_msx(nuevo)
    return bytes(at), bytes(col)


LIMPIO = 0x30       # papel amarillo sin brillo: el fondo del mapa (0x6ABA)
MARCA_SIN_PANEL = 0x70      # y la marca de unidad de la cinta (0x6AE0)


def heroes_nuevos(plan):
    """Las casillas de los heroes que el cartucho anade y la ROM vieja no
    tiene. Salen de los parches que el plan DECLARA sobre 0xB900 (columna) y
    0xBA00 (fila) del bloque alto, no de una lista escrita aqui."""
    p = {q["dir"]: int(q["nuevo"], 16) for q in plan.get("heroes", {}).get("parches", [])
         if q.get("bloque") == "alto" and len(q["nuevo"]) == 2}
    return [(p[0xB900 + n], p[0xBA00 + n])
            for n in sorted(d - 0xB900 for d in p if 0xB900 <= d < 0xBA00)]


def celda_de_la_marca(x, y):
    """Donde cae la marca de una unidad en los 768 atributos, tal y como lo
    calcula MARCA_UNA_UNIDAD (0x6AC5): la columna de caracter es x >> 2 -hay
    cuatro casillas de mapa por columna- y la fila es (y - 4) >> 2, porque las
    cuatro primeras filas del mapa no se ven."""
    return (x >> 2) & 0x1F, ((y & 0x7F) - 4) >> 2


def celda_en_la_vram(col, fila):
    """Los ocho bytes de color de esa celda, en la tabla de 0x2000."""
    o = (fila // 8) * 2048 + (fila % 8) * 256 + col * 8
    return range(0x2000 + o, 0x2000 + o + 8)


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
    tr_at, tr_col = traduce_el_panel(plan)
    nuevos = heroes_nuevos(plan)
    marca = plan["panel"]["marca"] if plan.get("panel") and plan["panel"]["parches"] else MARCA_SIN_PANEL
    # El dibujo de 8x8 que lleva la celda de cada unidad, si esta ROM lo trae.
    # Sale del plan, no escrito a mano.
    m = plan["vista"].get("marcas") if plan.get("vista") else None
    dibujo = bytes.fromhex(m["bytes"]) if m else None
    if m:
        print("  (cada unidad lleva ademas el dibujo de %s: %s)"
              % (m["png"], " ".join("%02X" % b for b in dibujo)))
    if nuevos:
        print("  (la ROM nueva anade %d heroes; a la vieja se le ponen sus marcas en %s"
              " para poder comparar los lienzos)"
              % (len(nuevos), ", ".join("(%d,%d)" % celda_de_la_marca(x, y) for x, y in nuevos)))
    if plan.get("panel") and plan["panel"]["parches"]:
        q = plan["panel"]
        print("  (el panel pasa de 0x%02X a 0x%02X y la marca de unidad de 0x%02X a 0x%02X:"
              " la ROM vieja se traduce antes de compararla)"
              % (q["orig"], q["atributo"], q["marca_orig"], q["marca"]))
    for n in vueltas:
        ln = lee(os.path.join(nuevo, "%d.ram" % n))
        lv = lee(os.path.join(viejo, "%d.ram" % n))
        vn = lee(os.path.join(nuevo, "%d.vram" % n))
        vv = lee(os.path.join(viejo, "%d.vram" % n))
        # la ROM vieja, con el panel y la marca traducidos: es lo unico que
        # cambia entre las dos aparte del guante
        lv = lv[:TAM_BITMAP] + bytes(tr_at[b] for b in lv[TAM_BITMAP:TAM_LIENZO])
        vv = (bytes(vv[:0x2000]) + bytes(tr_col[b] for b in vv[0x2000:0x3800])
              + bytes(vv[0x3800:]))
        # Los heroes que anade el cartucho van en las DOS ROMs -la de
        # referencia se monta con --heroes a proposito, para que el cotejo no
        # compare dos partidas distintas-, asi que aqui no hay nada que
        # traducir: lo que se exige es que los dos los marquen en la misma
        # celda, la que les toca por su casilla del mapa. Es lo que prueba, con
        # el juego corriendo, que un heroe nuevo SE VE en el mapa general.
        for x, y in nuevos:
            c, f = celda_de_la_marca(x, y)
            o = TAM_BITMAP + f * 32 + c
            exige(ln[o] == marca,
                  "vuelta %d: la ROM nueva marca la celda (%d,%d), donde esta el heroe nuevo" % (n, c, f))
            exige(lv[o] == marca,
                  "vuelta %d: y la vieja tambien: las dos llevan las mismas unidades" % n)
        en, ev = estado(nuevo, n), estado(viejo, n)
        col, fila = int(en["col"]), int(en["fila"])
        exige((col, fila) == (int(ev["col"]), int(ev["fila"])),
              "vuelta %d: las dos ROMs tienen el cursor en el mismo sitio (%d,%d)" % (n, col, fila))

        # LAS CELDAS DE UNIDAD de la ROM nueva: las que llevan el atributo de
        # marca. Ahi el dibujo de 8x8 esta SOLO en la VRAM y no en el lienzo,
        # que es justo lo que permite borrarlo; asi que el lienzo de las dos
        # ROMs sigue siendo el mismo y lo que cambia es lo que se ve.
        marcadas = [(f, c) for f in range(24) for c in range(32)
                    if ln[TAM_BITMAP + f * 32 + c] == marca] if dibujo else []

        # la VRAM de cada una es su lienzo, subido -y en la nueva, con el
        # dibujo de la marca encima de las celdas de unidad-
        for cual, lienzo, vram in (("nueva", ln, vn), ("vieja", lv, vv)):
            subido = bytearray(zx_a_vram(lienzo))
            if cual == "nueva":
                for f, c in marcadas:
                    o = f * 0x100 + c * 8
                    subido[o:o + 8] = dibujo
            exige(vram[:TAM_BITMAP] == bytes(subido),
                  "vuelta %d: la VRAM de la ROM %s es su lienzo subido, sin perder un byte%s"
                  % (n, cual,
                     (", con el dibujo de %s en las %d celdas de unidad"
                      % (os.path.basename(m["png"]), len(marcadas)))
                     if cual == "nueva" and marcadas else ""))

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
        # Y las celdas de unidad, que en la nueva llevan el dibujo de la marca
        # y en la vieja no: es una diferencia QUERIDA, igual que el guante.
        de_marcas = set((c * 8 + x, f * 8 + y)
                        for f, c in marcadas for y in range(8) for x in range(8))
        fuera = [p for p in distintos if p not in caja and p not in de_marcas]
        exige(not fuera,
              "vuelta %d: las dos pantallas son IGUALES pixel a pixel fuera del guante "
              "y de las %d celdas de unidad (%d distintos, %d fuera)"
              % (n, len(marcadas), len(distintos), len(fuera)))
        # Y DENTRO del guante lo que se exige es la SILUETA, no el color: el
        # guante es editable (src/cartucho/guante.png) y desde el 2026-09-18 va
        # en azul y blanco, porque amarillo y negro sobre un mapa amarillo y
        # negro no se veia. Lo que no puede cambiar es QUE pixeles pinta: los
        # distintos tienen que ser exactamente los que el PNG enciende en sus
        # dos planos, ni uno mas. Si el guante se moviera de sitio, se comiera
        # una fila o dejara de pintar algo, aqui se ve.
        silueta = set()
        for p in range(2):
            plano = cursor.bytes_a_plano(patrones_png[p * 32:(p + 1) * 32])
            for y in range(16):
                for x in range(16):
                    if plano[y][x]:
                        silueta.add((col + x, fila + y))
        exige(set(distintos) - de_marcas == silueta,
              "vuelta %d: fuera de las celdas de unidad, lo unico que cambia es el "
              "color del guante: %d pixels, los mismos que enciende %s"
              % (n, len(silueta), g["png"]))
        # Y DENTRO de las celdas de unidad tiene que haber cambiado algo: si el
        # dibujo no se viera, esto pasaria solo por estar en la lista de
        # excluidos. Lo que se exige es que cada celda marcada se vea DISTINTA
        # de como la ve la ROM vieja, que es la que no lleva marca.
        if marcadas:
            mudas = [(f, c) for f, c in marcadas
                     if not any((c * 8 + x, f * 8 + y) in set(distintos)
                                for y in range(8) for x in range(8))]
            exige(not mudas,
                  "vuelta %d: las %d celdas de unidad se ven distintas de la ROM sin "
                  "marca%s" % (n, len(marcadas),
                               "" if not mudas else " (%d iguales: %s)"
                               % (len(mudas), mudas[:6])))
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
