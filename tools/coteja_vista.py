#!/usr/bin/env python3
"""Coteja la vista de cerca de dos ROMs: la de la tabla de nombres con el cursor como sprite, y la de antes.

Los volcados los hace tools/omsx_coteja_vista.tcl en los mismos instantes del
juego para las dos ROMs: en cada vuelta del bucle, el trozo PURO (0x5E00 recien
pintado, antes de las ventanas) con la posicion del cursor, el modo y si se
ejecuto DIBUJA_EL_TROZO_DE_MAPA; y en los instantes elegidos, el estado
entero (VRAM, registros, RAM).

La ROM nueva ya no ensena lo mismo que la vieja en cuanto el cursor se mueve:
la ventana del trozo se queda quieta hasta que el cursor se acerca al borde.
Asi que aqui va un MODELO de esa regla (la misma que MI_PINTA: margen 3 en
una ventana de 16 x 13 con el cursor en la celda (7, 5) al recentrar; se
repinta al cambiar de modo y tras un menu) y lo que se exige es:

  1. que las dos ROMs siguieran el mismo camino: la misma posicion y el
     mismo modo en cada vuelta;
  2. que la nueva pinte el trozo EXACTAMENTE en las vueltas que dice el
     modelo, y la vieja en todas;
  3. caracter a caracter, en cada vuelta: el trozo puro de la nueva es el
     trozo puro que la vieja pinto en la vuelta del ultimo repintado (salvo
     las cuatro celdas donde la vieja lleva su cursor, que se cotejan con
     otra vuelta en la que esa casilla se ve); y en los instantes volcados,
     la pantalla final es ese trozo con las ventanas de la vieja encima;
  4. en la VRAM de la nueva: la tabla de nombres es la pantalla de
     caracteres, los dos sprites del cursor llevan la Y, la X, el patron y el
     color que tocan, sus patrones son los de cursor.png y R1 lleva el
     tamano 16x16;
  5. pixel a pixel, donde el encuadre coincide (recien entrado, tras un menu
     y tras cada recentrado): lo que ensena la nueva SIN el sprite es lo que
     ensena la vieja fuera del cursor; con el sprite, es la vieja con el
     cursor de cursor.png encima; y si cursor.png es el de fabrica, IDENTICAS
     cuando la vieja tiene el cursor encendido;
  6. en los instantes de BITMAP -menus y mapa-, VRAM identica byte a byte,
     sprites escondidos incluidos: el guardian lo devolvio todo.

Con --encendida se mira ademas la pasada con la pantalla ENCENDIDA de la ROM
nueva: nombres, patrones, colores y los dos sprites, sin un byte perdido.

Los PNG se escriben en el directorio que se diga, para MIRARLOS.

Uso: coteja_vista.py <dir nueva> <dir referencia> <dir png> --plan <plan.json> --work <dir>
                     [--roms <nueva.rom> <referencia.rom>] [--encendida <dir>]
Sale con 1 si algo de lo exigido no cuadra.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cursor                                               # noqa: E402
import render_vram                                          # noqa: E402

VISTAS = tuple("vista_" + c for c in "abckdefghij")
BITMAPS = ("menu_r", "menu_ordenes", "mapa")
PANTALLA = 0x5E00
NOMBRES = slice(0x1800, 0x1B00)
VISIBLE = slice(0x0000, 0x3800)  # patrones, nombres, sprites y colores: todo lo que se ve
SPRITES = 0x1B00
SPRITES_PAT = 0x3800
ORG_MEDIO = 0x5E00
TABLA_CURSORES = 0x77B5
CENTRO = (0x162, 0x163, 0x184, 0x185)   # las cuatro celdas del cursor de la vieja: fila 10, columna 14
ESCONDIDOS = bytes([209, 0, 0, 1, 209, 0, 1, 1])


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def volcado(d, nombre):
    vram = lee(os.path.join(d, nombre + ".vram"))
    with open(os.path.join(d, nombre + ".regs")) as f:
        regs = [int(x, 16) for x in f.read().split()][:8]
    ram = lee(os.path.join(d, nombre + ".ram"))
    return vram, regs, ram


def lee_vueltas(d):
    """Los sucesos de vueltas.txt, en orden."""
    sucesos = []
    with open(os.path.join(d, "vueltas.txt")) as f:
        for linea in f:
            p = linea.split()
            if not p:
                continue
            if p[0] == "vuelta":
                s = dict(tipo="vuelta", k=int(p[1]), hl=int(p[3], 16), modo=int(p[5], 16),
                         dibujado=int(p[7]))
                if "esquina" in p:
                    s["esquina"] = int(p[p.index("esquina") + 1], 16)
                    s["valida"] = int(p[p.index("valida") + 1])
                sucesos.append(s)
            elif p[0] == "estado":
                sucesos.append(dict(tipo="estado", nombre=p[1], k=int(p[2])))
            elif p[0] == "menu":
                sucesos.append(dict(tipo="menu"))
    return sucesos


def trozo(d, k):
    return lee(os.path.join(d, "trozo_%d.bin" % k))


def pantalla_de(ram):
    return ram[PANTALLA:PANTALLA + 850]


def filas_de_nombres(p):
    return b"".join(p[f * 34:f * 34 + 32] for f in range(24))


def identidad():
    return bytes(range(256)) * 3


def modelo(sucesos, ventana):
    """Por vuelta: la esquina que la nueva tiene que llevar, si repinta, en
    que vuelta repinto por ultima vez y donde cae el cursor en la ventana."""
    ancho, alto = ventana["ancho"], ventana["alto"]
    ccol, cfila, margen = ventana["cursor_col"], ventana["cursor_fila"], ventana["margen"]
    valida, h0, l0, modo0, k0 = False, None, None, None, None
    por_vuelta = {}
    for s in sucesos:
        if s["tipo"] == "menu":
            valida = False
        elif s["tipo"] == "vuelta":
            h, l = (s["hl"] >> 8) & 0x7F, s["hl"] & 0x7F
            repinta = (not valida or s["modo"] != modo0
                       or not (margen <= l - l0 + ccol <= ancho - 1 - margen)
                       or not (margen <= h - h0 + cfila <= alto - 1 - margen))
            if repinta:
                h0, l0, modo0, valida, k0 = h, l, s["modo"], True, s["k"]
            por_vuelta[s["k"]] = dict(h0=h0, l0=l0, repinta=repinta, k0=k0,
                                      ci=l - l0 + ccol, ri=h - h0 + cfila, modo=s["modo"],
                                      h=h, l=l)
    return por_vuelta


def pixeles(vram, regs, con_sprites=True):
    _w, _h, filas = render_vram.pinta(vram, regs, escala=1, con_sprites=con_sprites)
    return filas


def guarda_png(vram, regs, ruta):
    w, h, filas = render_vram.pinta(vram, regs, escala=2)
    render_vram.png(w, h, filas, ruta)


def diferencia(a, b, ruta_diff, salvo=None):
    """Cuantos pixeles cambian fuera del recuadro `salvo` (x, y, lado); y un
    PNG con los que cambian en rojo sobre la imagen A en gris, para ver DONDE."""
    n = 0
    filas = []
    for y, (fa, fb) in enumerate(zip(a, b)):
        fila = []
        for x in range(0, len(fa) // 3):
            i = x * 3
            dentro = salvo and salvo[0] <= x < salvo[0] + salvo[2] and salvo[1] <= y < salvo[1] + salvo[2]
            if fa[i:i + 3] != fb[i:i + 3] and not dentro:
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


def con_el_cursor_encima(img, dib, x0, y0):
    """La imagen con el cursor de cursor.png pintado en (x0, y0)."""
    fuera = [list(f) for f in img]
    for dy in range(16):
        for dx in range(16):
            c = dib[dy][dx]
            if c is None:
                continue
            x, y = x0 + dx, y0 + dy
            if 0 <= x < 256 and 0 <= y < 192:
                fuera[y][x * 3:x * 3 + 3] = render_vram.PALETA[c]
    return fuera


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    nueva, ref, pngs = argv[1:4]
    roms = encendida = work = plan_ruta = None
    i = 4
    while i < len(argv):
        if argv[i] == "--roms":
            roms = (argv[i + 1], argv[i + 2]); i += 3
        elif argv[i] == "--encendida":
            encendida = argv[i + 1]; i += 2
        elif argv[i] == "--work":
            work = argv[i + 1]; i += 2
        elif argv[i] == "--plan":
            plan_ruta = argv[i + 1]; i += 2
        else:
            print("argumento desconocido:", argv[i]); return 2
    if not plan_ruta or not work:
        print("hacen falta --plan <plan.json> y --work <dir>")
        return 2
    os.makedirs(pngs, exist_ok=True)
    with open(plan_ruta) as f:
        plan = json.load(f)
    c = plan["vista"]["cursor"]
    planos = bytes.fromhex(c["planos"])
    colores = bytes(c["planos_colores"])
    ventana = c["ventana"]
    modos = {int(k, 16): v for k, v in c["modos"].items()}
    medio = lee(os.path.join(work, "medio.raw"))
    de_fabrica = (planos, colores) == cursor.planos_de_fabrica(work)
    print("  el cursor es %s" % ("el de fabrica: el del juego" if de_fabrica else "OTRO (cursor.png esta editado)"))

    fallos = 0

    def falla(que):
        nonlocal fallos
        fallos += 1
        print("  FALLO: " + que)

    def codigos_del_cursor(modo):
        return medio[TABLA_CURSORES - ORG_MEDIO + modo * 4:][:4]

    # La trampa del cotejo trivial: dos ficheros distintos de verdad.
    if roms:
        a, b = (lee(r) for r in roms)
        if a == b:
            falla("las dos ROMs son IDENTICAS: no hay nada que cotejar")
        else:
            print("  las dos ROMs difieren en %d bytes: hay cotejo" % sum(x != y for x, y in zip(a, b)))

    # ------------------------------------------------- 1 y 2: el camino y los repintados
    sn, sr = lee_vueltas(nueva), lee_vueltas(ref)
    vn = [s for s in sn if s["tipo"] == "vuelta"]
    vr = [s for s in sr if s["tipo"] == "vuelta"]
    camino_n = [(s["k"], s["hl"], s["modo"]) for s in vn]
    camino_r = [(s["k"], s["hl"], s["modo"]) for s in vr]
    if camino_n != camino_r:
        falla("las dos ROMs no siguieron el mismo camino (posicion o modo distintos en alguna vuelta)")
        for a, b in zip(camino_n, camino_r):
            if a != b:
                print("     vuelta %d: nueva HL=%04X modo %02X, referencia HL=%04X modo %02X" % (a[0], a[1], a[2], b[1], b[2]))
                break
        return 1
    if [s["tipo"] for s in sn] != [s["tipo"] for s in sr]:
        falla("los sucesos (vueltas, menus, volcados) no van en el mismo orden en las dos ROMs")
    m = modelo(sn, ventana)
    if any(s["dibujado"] != 1 for s in vr):
        falla("la ROM de referencia no pinta el trozo en todas las vueltas: la sonda no ve 0x7643")
    pintadas = [s["k"] for s in vn if s["dibujado"]]
    esperadas = [k for k in sorted(m) if m[k]["repinta"]]
    if pintadas != esperadas:
        falla("la nueva pinta el trozo en las vueltas %s y el modelo dice %s" % (pintadas, esperadas))
    else:
        print("  la nueva pinta el trozo %d veces en %d vueltas (%s); la referencia, %d veces"
              % (len(pintadas), len(vn), ", ".join(str(k) for k in pintadas), len(vr)))
    for s in vn:
        if "esquina" in s:
            q = m[s["k"]]
            if s["esquina"] != (q["h0"] << 8 | q["l0"]) or s["valida"] != 1:
                falla("vuelta %d: la nueva lleva esquina %04X y cache %d, y el modelo dice %02X%02X"
                      % (s["k"], s["esquina"], s["valida"], q["h0"], q["l0"]))

    # --------------------------------------------- 3: el trozo puro, caracter a caracter
    hl_ref = {s["k"]: s["hl"] for s in vr}
    celdas_mal = 0
    sin_comprobar = 0
    for s in vn:
        k, q = s["k"], m[s["k"]]
        tn, tr = trozo(nueva, k), trozo(ref, q["k0"])
        # la referencia lleva el cursor escrito en el centro cuando esta encendido
        cursor_ref = tr[CENTRO[0]:CENTRO[0] + 2] + tr[CENTRO[2]:CENTRO[2] + 2] == codigos_del_cursor(q["modo"])
        for o in range(850):
            if o in CENTRO and cursor_ref:
                continue
            if tn[o] != tr[o]:
                celdas_mal += 1
                if celdas_mal <= 3:
                    print("     vuelta %d: la celda %d (fila %d, columna %d) es %02X y la referencia (vuelta %d) tiene %02X"
                          % (k, o, o // 34, o % 34, tn[o], q["k0"], tr[o]))
        if cursor_ref:
            # las cuatro celdas de debajo del cursor de la referencia: la casilla
            # (h0, l0) se ve en cualquier otra vuelta en la que el cursor este en
            # otro sitio, desplazada dos celdas por casilla
            visto = False
            for k2, hl2 in hl_ref.items():
                h2, l2 = (hl2 >> 8) & 0x7F, hl2 & 0x7F
                if (h2, l2) == (q["h0"], q["l0"]):
                    continue
                fila, col = 10 + 2 * (q["h0"] - h2), 14 + 2 * (q["l0"] - l2)
                if 0 <= fila < 23 and 0 <= col < 31:
                    t2 = trozo(ref, k2)
                    esperado = bytes([t2[fila * 34 + col], t2[fila * 34 + col + 1],
                                      t2[(fila + 1) * 34 + col], t2[(fila + 1) * 34 + col + 1]])
                    visto = True
                    if bytes(tn[o] for o in CENTRO) != esperado:
                        celdas_mal += 1
                        print("     vuelta %d: bajo el cursor de la referencia la nueva tiene %s y la vuelta %d ensena %s"
                              % (k, bytes(tn[o] for o in CENTRO).hex(), k2, esperado.hex()))
                    break
            if not visto:
                sin_comprobar += 1
    if celdas_mal:
        falla("el trozo puro de la nueva no es el de la referencia: %d celdas distintas" % celdas_mal)
    else:
        print("  el trozo puro de la nueva es el que la referencia pinto en el ultimo repintado, en las %d vueltas" % len(vn))
    if sin_comprobar:
        print("  aviso: en %d repintados no se pudo cotejar lo que hay bajo el cursor de la referencia" % sin_comprobar)

    # ---------------------------------- y en los instantes volcados, la pantalla con las ventanas
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
        vram_n, regs_n, ram_n = volcado(nueva, inst)
        vram_r, regs_r, ram_r = volcado(ref, inst)
        guarda_png(vram_n, regs_n, os.path.join(pngs, inst + "_nueva.png"))
        guarda_png(vram_r, regs_r, os.path.join(pngs, inst + "_referencia.png"))
        if inst in BITMAPS:
            # (la pantalla de caracteres de 0x5E00 ya NO es la misma en las
            # dos: la nueva lleva la ventana fija y no escribe el cursor en
            # ella; lo que tiene que ser identico es lo que se ve)
            pn, pr = pixeles(vram_n, regs_n), pixeles(vram_r, regs_r)
            d = diferencia(pn, pr, os.path.join(pngs, inst + "_DIFERENCIA.png"))
            if d:
                falla("%s: las dos imagenes no son iguales: %d pixeles (ver %s_DIFERENCIA.png)" % (inst, d, inst))
            if vram_n[VISIBLE] != vram_r[VISIBLE]:
                primero = next(j for j in range(0x3800) if vram_n[j] != vram_r[j])
                falla("%s: en modo bitmap la VRAM tiene que ser identica byte a byte; difiere desde 0x%04X"
                      % (inst, primero))
            else:
                print("  %-13s bitmap: VRAM identica byte a byte, sprites escondidos incluidos" % inst)
            if vram_n[NOMBRES] != identidad():
                falla("%s: la ROM nueva no ha devuelto la tabla de nombres a la identidad" % inst)
            if vram_n[SPRITES:SPRITES + 8] != ESCONDIDOS:
                falla("%s: el guardian no ha dejado los dos sprites como los dejo el cargador" % inst)
            continue

        # un instante de la vista: la vuelta en la que se volco
        k = next(s["k"] for s in sn if s["tipo"] == "estado" and s["nombre"] == inst)
        q = m[k]
        pan_n, pan_r = pantalla_de(ram_n), pantalla_de(ram_r)
        puro_n, puro_r = trozo(nueva, k), trozo(ref, k)
        mal = 0
        for f in range(24):
            for col in range(32):
                o = f * 34 + col
                if pan_r[o] != puro_r[o]:                  # una ventana de la referencia
                    ok = pan_n[o] == pan_r[o]
                else:                                       # el trozo, o una ventana que coincide con el
                    ok = pan_n[o] == puro_n[o] or pan_n[o] == pan_r[o]
                if not ok:
                    mal += 1
        if mal:
            falla("%s: la pantalla final de la nueva no es su trozo con las ventanas de la referencia: %d celdas" % (inst, mal))

        # 4: la VRAM de la nueva
        if vram_n[NOMBRES] != filas_de_nombres(pan_n):
            falla("%s: la ROM nueva no lleva en 0x1800 la pantalla de caracteres" % inst)
        if vram_r[NOMBRES] != identidad():
            falla("%s: la ROM de referencia no lleva la tabla de nombres identidad" % inst)
        if not regs_n[1] & 0x02:
            falla("%s: R1 = 0x%02X, sin el bit de sprites de 16x16" % (inst, regs_n[1]))
        mi = modos[q["modo"]]
        y, x = (16 * q["ri"] - 1) & 0xFF, 16 * q["ci"]
        esperados = bytes([y, x, mi * 8, colores[mi * 2], y, x, mi * 8 + 4, colores[mi * 2 + 1]])
        if vram_n[SPRITES:SPRITES + 8] != esperados:
            falla("%s: los atributos de los sprites son %s y tenian que ser %s (celda %d,%d de la ventana)"
                  % (inst, vram_n[SPRITES:SPRITES + 8].hex(), esperados.hex(), q["ci"], q["ri"]))
        if vram_n[SPRITES + 8:SPRITES + 128] != b"".join(bytes([209, 0, n, 1]) for n in range(2, 32)):
            falla("%s: los otros 30 sprites no estan como los dejo el cargador" % inst)
        if vram_n[SPRITES_PAT:SPRITES_PAT + len(planos)] != planos:
            falla("%s: los patrones de los sprites no son los de cursor.png" % inst)

        # 5: pixel a pixel
        img_r = pixeles(vram_r, regs_r)
        img_n_sin = pixeles(vram_n, regs_n, con_sprites=False)
        img_n = pixeles(vram_n, regs_n)
        recuadro = (x, (y + 1) & 0xFF, 16)
        esperada = con_el_cursor_encima(img_n_sin, cursor.dibuja(planos, colores, mi), recuadro[0], recuadro[1])
        if img_n != esperada:
            falla("%s: el sprite no se ve como dice cursor.png en (%d, %d)" % (inst, recuadro[0], recuadro[1]))
        coincide = (q["h"], q["l"]) == (q["h0"], q["l0"])
        if coincide:
            cursor_ref = pan_r[CENTRO[0]:CENTRO[0] + 2] + pan_r[CENTRO[2]:CENTRO[2] + 2] == codigos_del_cursor(q["modo"])
            d = diferencia(img_n_sin, img_r, os.path.join(pngs, inst + "_DIFERENCIA.png"), salvo=recuadro)
            if d:
                falla("%s: fuera del cursor, la nueva sin sprite no es la referencia: %d pixeles (ver %s_DIFERENCIA.png)"
                      % (inst, d, inst))
            if cursor_ref:
                if de_fabrica:
                    d2 = diferencia(img_n, img_r, os.path.join(pngs, inst + "_DIFERENCIA.png"))
                    if d2:
                        falla("%s: con el cursor de fabrica la imagen tenia que ser IDENTICA a la referencia: %d pixeles"
                              % (inst, d2))
                    else:
                        print("  %-13s encuadre igual y cursor encendido en la referencia: IDENTICAS pixel a pixel, sprite incluido" % inst)
                else:
                    print("  %-13s encuadre igual: identicas fuera del cursor (el cursor esta editado)" % inst)
            else:
                d2 = diferencia(img_n_sin, img_r, os.path.join(pngs, inst + "_DIFERENCIA.png"))
                if d2:
                    falla("%s: la referencia tiene el cursor apagado y la nueva sin sprite no es identica: %d pixeles" % (inst, d2))
                else:
                    print("  %-13s encuadre igual y cursor apagado en la referencia: IDENTICAS sin el sprite, y el sprite encima" % inst)
        else:
            print("  %-13s encuadre distinto (cursor en la celda %d,%d de la ventana fija): trozo, ventanas y sprite comprobados"
                  % (inst, q["ci"], q["ri"]))
        if vram_n[VISIBLE] == vram_r[VISIBLE]:
            falla("%s: las dos VRAM son iguales byte a byte: el cotejo seria trivial" % inst)
    if instantes < 6:
        falla("solo hay %d instantes cotejados; se esperaban al menos vista_a, vista_b, menu_r, vista_c, vista_e y vista_f" % instantes)

    if encendida:
        import corre_nombres
        bajo = lee(os.path.join(work, "bajo.raw"))
        alto = lee(os.path.join(work, "alto.raw"))
        ram = bytearray(0x10000)
        ram[corre_nombres.ORG_ALTO:corre_nombres.ORG_ALTO + len(alto)] = alto
        ram[corre_nombres.ORG_MEDIO:corre_nombres.ORG_MEDIO + len(medio)] = medio   # el atributo del texto, 0x763F
        ram[corre_nombres.TABLA_COLOR:corre_nombres.TABLA_COLOR + 256] = corre_nombres.tabla_de_color(bajo)
        esperado_p = corre_nombres.patrones_esperados(ram)
        esperado_c = corre_nombres.colores_esperados(ram)
        se = lee_vueltas(encendida)
        me = modelo(se, ventana)
        vistos = 0
        for inst in VISTAS:
            if not os.path.exists(os.path.join(encendida, inst + ".vram")):
                continue
            vistos += 1
            v, regs, r = volcado(encendida, inst)
            if regs[1] & 0x40 == 0:
                falla("%s (encendida): la pantalla estaba apagada, R1 = 0x%02X" % (inst, regs[1]))
            k = next(s["k"] for s in se if s["tipo"] == "estado" and s["nombre"] == inst)
            q = me[k]
            mi = modos[q["modo"]]
            y, x = (16 * q["ri"] - 1) & 0xFF, 16 * q["ci"]
            atributos = bytes([y, x, mi * 8, colores[mi * 2], y, x, mi * 8 + 4, colores[mi * 2 + 1]])
            perdidos = (sum(a != b for a, b in zip(v[NOMBRES], filas_de_nombres(pantalla_de(r))))
                        + sum(a != b for a, b in zip(v[:0x1800], esperado_p))
                        + sum(a != b for a, b in zip(v[0x2000:0x3800], esperado_c))
                        + sum(a != b for a, b in zip(v[SPRITES:SPRITES + 8], atributos))
                        + sum(a != b for a, b in zip(v[SPRITES_PAT:SPRITES_PAT + len(planos)], planos)))
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
    print("  todo lo exigido coincide: la ventana fija con el cursor como sprite ensena lo que tiene que ensenar")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
