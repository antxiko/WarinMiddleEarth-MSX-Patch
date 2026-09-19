#!/usr/bin/env python3
"""EL MAPA DE LA RAM: que hay en cada tramo de los 64 KB cuando el juego corre.

No hay nada escrito a mano aqui: los bloques salen de donde los deja el
cargador (comprobado contra los volcados de la cinta), lo que el juego monta
encima sale del listado (src/*.notes), los tramos LIBRES salen de la medicion
con openMSX (tools/omsx_ram_libre.tcl -> tools/ram_libre.py), lo que ocupa el
cartucho sale del plan.json y los huecos que el juego deja con los parches
puestos los declara el propio plan (haz_rom.py: HUECOS_DEL_JUEGO).

El juego corre con las CUATRO paginas en RAM y sin BIOS, asi que estos 64 KB
son todo lo que hay.

OJO CON LA MEDICION: la partida grabada que mide lo libre es la de Araubi en
cinta, que NO llega a ninguna batalla. Lo que la batalla usa y nadie mas toca
-sus sprites, su codigo, su tabla de bits invertidos- saldria como libre; se
descuenta con la lista BATALLA, que sale del listado y de las partidas del
cartucho con batallas (2026-09-19). Y lo que ocupa el cartucho en la pagina 2
no se puede medir en una partida del cartucho: las lecturas de esa pagina se
mezclan con la ROM asomada por la ventana de 0x8000.

Uso:  mapa_ram.py [work] [plan.json]
      (por defecto ./work y, de ahi, unificada/plan.json si existe o si no
      musica/plan.json: la ROM que se juega es la unificada)
"""
import json
import os
import re
import sys

# Lo que trae la cinta, tal como lo recoloca el arranque (mismos datos que
# tools/ram_libre.py, que es quien los cotejo contra los volcados).
CINTA = [(0x0190, 0x3F4F, "bloque bajo: la capa MSX, los graficos y las dos pantallas finales"),
         (0x5E00, 0x96F1, "bloque medio: EL JUEGO (menu, mapa, batalla, textos)"),
         (0x9E00, 0xE678, "bloque alto: graficos, mapa comprimido y tablas")]

# Y lo que el juego monta encima, que no viene en la cinta.
MONTADO = [(0x0000, 0x0190, "vectores y buzon de POKEs: 0x0038 = jp 0x0400"),
           (0x4000, 0x5B00, "la pantalla del ZX emulada: bitmap y atributos"),
           (0x5B00, 0x5C00, "la pila, desde 0x5BFF hacia abajo (medido: nunca bajo de 0x5BC0)"),
           (0x5DDE, 0x5E00, "la vista escribe aqui la fila de ENCIMA de su pantalla (ld (iy-022h),a en 0x7411): 34 B pisados"),
           (0xCC00, 0xFFCD, "el mapa descomprimido (0x33CD bytes); en batalla, empaquetado en 0xCC00-0xE2EB"),
           (0xE300, 0xF400, "batalla: las tiras de figuras y las capas de fichas, dentro del mapa empaquetado")]

# Lo que SOLO usa la batalla, y por eso una partida sin batalla lo deja como
# si estuviera libre. Del listado (src/medio.notes, src/alto.notes, bajo) y de
# las partidas del cartucho con batallas: los sprites los leen 0x880B-0x8903.
BATALLA = [(0x0300, 0x0400, "tabla de bits invertidos: la monta 0x9129 al empezar cada batalla"),
           (0x8572, 0x9366, "el codigo de la batalla"),
           (0x93D9, 0x9627, "mensajes, despachadores y tablas de fichas de la batalla"),
           (0xA2E8, 0xB8E8, "los 176 sprites de la batalla, 32 B cada uno; solo lectura")]

# Las dos pantallas finales, que son la cola del bloque bajo.
FINALES = [(0x094F, 0x244F, "pantalla final: VICTORIA (Gandalf), 6912 B"),
           (0x244F, 0x3F4F, "pantalla final: DERROTA (Sauron), 6912 B")]

TRABAJO_INC = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "src", "cartucho", "wyz_trabajo.inc")


def area_de_trabajo():
    """De donde a donde llegan las variables del reproductor, leidas del .inc
    que las reparte. La primera etiqueta y WYZ_TRABAJO_FIN."""
    dirs = []
    with open(TRABAJO_INC) as f:
        for linea in f:
            m = re.match(r"\s*\S+\s+equ\s+0([0-9A-Fa-f]{4})h", linea)
            if m:
                dirs.append(int(m.group(1), 16))
    assert dirs, "%s no trae ni una direccion" % TRABAJO_INC
    return dirs[0], dirs[-1]


def lee_libres(work):
    """Los tramos que nadie leyo ni escribio, tal y como los funde
    tools/ram_libre.py. Se le pregunta a EL en vez de repetir aqui la cuenta:
    los .bandas vienen en dos granularidades -16 y 256 bytes- y mezclarlas a
    mano daba miles de tramos solapados."""
    import glob
    import subprocess
    bandas = sorted(glob.glob(os.path.join(work, "ram", "*.bandas")))
    if not bandas:
        return []
    r = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                     "ram_libre.py")] + bandas,
                       capture_output=True, text=True)
    tramos, dentro = [], False
    for linea in r.stdout.splitlines():
        if "nadie leyo ni escribio" in linea:
            dentro = True
            continue
        if linea.startswith("==") or "Solo LEIDO" in linea:
            dentro = False
        if not dentro:
            continue
        campos = linea.split()
        if len(campos) >= 2 and "-" in campos[0]:
            a, b = campos[0].split("-")
            try:
                tramos.append((int(a, 16), int(b, 16) + 1))
            except ValueError:
                pass
    return tramos


def quita(tramos, ocupados):
    """Los `tramos` menos lo que caiga en `ocupados`: lo que la medicion da por
    libre pero el listado dice que la batalla usa."""
    fuera = []
    for ini, fin in tramos:
        trozos = [(ini, fin)]
        for a, b, _q in ocupados:
            nuevos = []
            for i, f in trozos:
                if b <= i or f <= a:
                    nuevos.append((i, f))
                else:
                    if i < a:
                        nuevos.append((i, a))
                    if b < f:
                        nuevos.append((b, f))
            trozos = nuevos
        fuera += trozos
    return fuera


def elige_plan(work, ruta=None):
    if ruta:
        return ruta
    for cual in ("unificada", "musica"):
        r = os.path.join(work, cual, "plan.json")
        if os.path.exists(r):
            return r
    return None


def lee_plan(ruta):
    if not ruta or not os.path.exists(ruta):
        return {}
    with open(ruta) as f:
        return json.load(f)


def lee_finales(d):
    """Si la ROM se monto con --finales-rom, las dos pantallas ya no viajan a
    la RAM: se quedan en el cartucho y se descomprimen a 0x4000 al acabar la
    partida. Entonces su tramo deja de ser 'cola del bloque bajo' y pasa a ser
    RAM libre AJENA A LA CINTA, que es la unica de fiar."""
    f_ = d.get("finales")
    if not f_:
        return None
    return [(q["dir"], q["dir"] + q["crudo"]) for q in f_["pantallas"]]


def lee_cartucho(d):
    """Lo que el cartucho tiene puesto en RAM con el juego corriendo."""
    m = d.get("datos", {}).get("musica")
    if not m:
        return []
    p = m["puente"]
    # Lo que ocupa el area de trabajo del reproductor NO se escribe aqui: sale
    # del .inc que genera tools/convierte_wyz.py, que es quien reparte las
    # variables. A mano se quedaria vieja en cuanto el reproductor cambie.
    trabajo = area_de_trabajo()
    ocupa = [(p["ram"], p["ram"] + p["bytes"], "EL PUENTE de la musica (%d B)" % p["bytes"]),
             (trabajo[0], trabajo[1],
              "area de trabajo del reproductor WYZ (%d B)" % (trabajo[1] - trabajo[0]))]
    f_ = d.get("finales")
    if f_:
        ocupa.append((f_["ram"], f_["ram"] + f_["bytes"],
                      "LA RUTINA de las pantallas finales y el mapa general (%d B); descomprime EN EL SITIO, sin bufer" % f_["bytes"]))
    v = d.get("vista")
    if v:
        ocupa.append((v["ram"], v["ram"] + v["bytes"],
                      "LA RUTINA de la vista, los sprites, las marcas y la batalla (%d B)" % v["bytes"]))
    return ocupa


def lee_bufers(d):
    """Los dos bufers de ZX0. Solo se usan MIENTRAS CARGA -despues de saltar a
    0x0190 esa RAM esta libre-, pero hay que contarlos: quien quiera meter algo
    ahi tiene que saber que el cargador pasa por encima antes de arrancar."""
    z = d.get("zona_libre")
    if not z:
        return []
    return [(z[cual]["ram"], z[cual]["ram"] + z[cual]["bytes"],
             "bufer de ZX0, SOLO durante la carga: %s" % z[cual]["que"])
            for cual in ("bufer_z", "bufer_d")]


def lee_tiles(d):
    """Los dibujos del mapa: si la vista los lee de la ROM, su copia en la RAM
    es libre desde que arranca el juego."""
    t = d.get("vista", {}).get("tiles")
    if not t:
        return []
    return [(t["ram"], t["ram"] + t["bytes"], "los 128 dibujos del mapa: la vista los lee de la ROM; esta copia no la mira nadie")]


def lee_huecos(d):
    """Los huecos que el juego deja con los parches del cartucho, tal como los
    declara el plan (y los vigilan los tests)."""
    return [(h["ini"], h["fin"], "hueco del juego (%s): %s" % (h["prueba"], h["que"]))
            for h in d.get("huecos", [])]


def main(argv):
    work = argv[1] if len(argv) > 1 else "work"
    plan = elige_plan(work, argv[2] if len(argv) > 2 else None)
    d = lee_plan(plan)
    medidos = lee_libres(work)
    libres = quita(medidos, BATALLA)
    cartucho = lee_cartucho(d)
    en_la_rom = lee_finales(d)
    bufers = lee_bufers(d)
    tiles = lee_tiles(d)
    huecos = lee_huecos(d)

    # Lo que la CINTA deja en la RAM. Si las dos pantallas finales se quedan en
    # el cartucho, el bloque bajo se acorta hasta donde empezaban: de ahi salen
    # los 13.824 bytes que ese cambio libera.
    cinta = list(CINTA)
    if en_la_rom:
        ini_finales = min(a for a, _b in en_la_rom)
        cinta[0] = (cinta[0][0], ini_finales,
                    "bloque bajo: la capa MSX y los graficos (las finales se quedan en la ROM)")

    print("=" * 78)
    print(" LA RAM DE WAR IN MIDDLE EARTH, 64 KB, con el juego corriendo")
    print(" (las cuatro paginas en RAM: no hay BIOS ni cartucho a la vista)")
    if plan:
        print(" plan: %s" % plan)
    print("=" * 78)
    print()

    filas = []
    for ini, fin, que in cinta:
        filas.append((ini, fin, "CINTA", que))
    for ini, fin, que in FINALES:
        if en_la_rom:
            filas.append((ini, fin, "EN ROM", que + ", ya NO en la RAM"))
        else:
            filas.append((ini, fin, "IMAGEN", que))
    for ini, fin, que in MONTADO:
        filas.append((ini, fin, "JUEGO", que))
    for ini, fin, que in BATALLA:
        filas.append((ini, fin, "BATALLA", que))
    for ini, fin, que in cartucho:
        filas.append((ini, fin, "CARTUCHO", que))
    for ini, fin, que in bufers:
        filas.append((ini, fin, "CARGA", que))
    for ini, fin, que in tiles:
        filas.append((ini, fin, "HUECO", que))
    for ini, fin, que in huecos:
        filas.append((ini, fin, "HUECO", que))
    for ini, fin in libres:
        filas.append((ini, fin, "libre", "nadie lo leyo ni lo escribio en toda la partida"))

    ancho = 44
    for ini, fin, tipo, que in sorted(filas):
        tam = fin - ini
        barra = ("#" if tipo in ("CINTA", "JUEGO", "BATALLA")
                 else "*" if tipo in ("IMAGEN", "CARTUCHO")
                 else "-" if tipo == "EN ROM"
                 else "o" if tipo == "CARGA"
                 else "+" if tipo == "HUECO" else ".")
        n = max(1, min(ancho, round(tam / 65536 * ancho * 6)))
        print("  %04X-%04X %6d B  %-8s %-8s %s"
              % (ini, fin - 1, tam, tipo, barra * min(n, 8), que))

    print()
    print("  Los tramos se SOLAPAN a proposito: lo que la cinta trae y lo que el")
    print("  juego monta encima conviven en las mismas direcciones segun el momento.")
    print()
    total_libre = sum(f - i for i, f in libres)
    print("  RAM que nadie toca en toda la partida (descontada la batalla): %d B" % total_libre)
    print("  De ella, AJENA A LA CINTA -la unica de fiar para meter cosas-:")
    # No es una lista de direcciones escrita a mano: es lo LIBRE menos lo que la
    # cinta deja ocupado. Asi, en cuanto las finales se quedan en la ROM, su
    # tramo aparece aqui solo.
    de_la_cinta = set()
    for ini, fin, _que in cinta:
        de_la_cinta.update(range(ini, fin))
    ajena = []
    for ini, fin in libres:
        tramo = None
        for x in range(ini, fin):
            if x in de_la_cinta:
                if tramo:
                    ajena.append(tramo)
                    tramo = None
            elif tramo:
                tramo[1] = x + 1
            else:
                tramo = [x, x + 1]
        if tramo:
            ajena.append(tramo)
    ajena = [t for t in ajena if t[1] - t[0] >= 64]
    for ini, fin in sorted(ajena):
        print("      %04X-%04X  %6d B" % (ini, fin - 1, fin - ini))
    total_ajena = sum(f - i for i, f in ajena)
    print("      %-11s %6d B  EN TOTAL" % ("", total_ajena))
    usa = 0
    if cartucho:
        print("  Y de esa, ya hay puesto:")
        for i, f, que in sorted(cartucho):
            print("      %04X-%04X  %6d B  %s" % (i, f - 1, f - i, que))
            usa += f - i
    # Lo que la vista pisa por debajo de 0x5E00 tampoco vale, aunque la
    # medicion lo diera por libre: la partida de Araubi no llevo la vista al
    # borde de arriba del mapa.
    pisado = [(a, b) for a, b, _q in MONTADO if a == 0x5DDE]
    for a, b in pisado:
        usa += b - a
        print("      %04X-%04X  %6d B  pisado por la vista (la fila de encima de su pantalla)" % (a, b - 1, b - a))
    queda_ajena = total_ajena - usa
    print("  Queda de la RAM ajena a la cinta: %d B." % queda_ajena)
    # Los huecos que caen dentro de lo ya contado como ajeno (el buzon de
    # POKEs, en 0x012C) no se suman dos veces.
    ya_contado = set()
    for ini, fin in ajena:
        ya_contado.update(range(ini, fin))

    def nuevos(tramos):
        return sum(1 for i, f, _q in tramos for x in range(i, f) if x not in ya_contado)

    total_huecos, total_tiles = nuevos(huecos), nuevos(tiles)
    if huecos or tiles:
        print()
        print("  MAS LOS HUECOS QUE EL JUEGO DEJA CON LOS PARCHES PUESTOS (los declara el plan):")
        for i, f, que in sorted(huecos + tiles):
            print("      %04X-%04X  %6d B  %s" % (i, f - 1, f - i, que))
        print("      %-11s %6d B  EN TOTAL: %d de huecos del juego y %d de los dibujos del mapa"
              % ("", total_huecos + total_tiles, sum(f - i for i, f, _q in huecos), total_tiles))
        if total_huecos != sum(f - i for i, f, _q in huecos):
            print("      (%d B de los huecos ya estaban contados arriba, en la RAM ajena a la cinta)"
                  % (sum(f - i for i, f, _q in huecos) - total_huecos))
    print()
    print("  QUEDA PARA LO QUE VENGA: %d B (%d ajenos a la cinta + %d de huecos y dibujos)."
          % (queda_ajena + total_huecos + total_tiles, queda_ajena, total_huecos + total_tiles))
    if bufers:
        print()
        print("  Y ojo con esto: MIENTRAS CARGA, el cargador usa ademas")
        for i, f, que in bufers:
            print("      %04X-%04X  %6d B  %s" % (i, f - 1, f - i, que.split(": ", 1)[-1]))
        print("  Despues de saltar a 0x0190 esa RAM queda libre, pero lo que se")
        print("  deje ahi antes de arrancar el juego no sobrevive.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
