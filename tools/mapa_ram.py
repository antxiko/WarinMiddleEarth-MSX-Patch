#!/usr/bin/env python3
"""EL MAPA DE LA RAM: que hay en cada tramo de los 64 KB cuando el juego corre.

No hay nada escrito a mano aqui: los bloques salen de donde los deja el
cargador (comprobado contra los volcados de la cinta), lo que el juego monta
encima sale del listado, los tramos LIBRES salen de la medicion con openMSX
(tools/omsx_ram_libre.tcl -> tools/ram_libre.py) y lo que ocupa la musica sale
del plan.json del cartucho.

El juego corre con las CUATRO paginas en RAM y sin BIOS, asi que estos 64 KB
son todo lo que hay.

Uso:  mapa_ram.py [work]            (por defecto, ./work)
"""
import json
import os
import sys

# Lo que trae la cinta, tal como lo recoloca el arranque (mismos datos que
# tools/ram_libre.py, que es quien los cotejo contra los volcados).
CINTA = [(0x0190, 0x3F4F, "bloque bajo: la capa MSX, los graficos y las dos pantallas finales"),
         (0x5E00, 0x96F1, "bloque medio: EL JUEGO (menu, mapa, batalla, textos)"),
         (0x9E00, 0xE678, "bloque alto: graficos, mapa comprimido y tablas")]

# Y lo que el juego monta encima, que no viene en la cinta.
MONTADO = [(0x0000, 0x0190, "vectores y buzon de POKEs: 0x0038 = jp 0x0400"),
           (0x4000, 0x5B00, "la pantalla del ZX emulada: bitmap y atributos"),
           (0x5B00, 0x5C00, "la pila, desde 0x5BFF hacia abajo"),
           (0xCC00, 0xFFCD, "el mapa descomprimido (0x33CD bytes)"),
           (0xE800, 0xF400, "batalla: las capas de fichas y sus copias")]

# Las dos pantallas finales, que son la cola del bloque bajo.
FINALES = [(0x094F, 0x244F, "pantalla final: VICTORIA (Gandalf), 6912 B"),
           (0x244F, 0x3F4F, "pantalla final: DERROTA (Sauron), 6912 B")]


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


def lee_finales(work):
    """Si la ROM con musica se monto con --finales-rom, las dos pantallas ya no
    viajan a la RAM: se quedan en el cartucho y se descomprimen a 0x4000 al
    acabar la partida. Entonces su tramo deja de ser 'cola del bloque bajo' y
    pasa a ser RAM libre AJENA A LA CINTA, que es la unica de fiar."""
    ruta = os.path.join(work, "musica", "plan.json")
    if not os.path.exists(ruta):
        return None
    with open(ruta) as f:
        d = json.load(f)
    f_ = d.get("finales")
    if not f_:
        return None
    return [(q["dir"], q["dir"] + q["crudo"]) for q in f_["pantallas"]]


def lee_musica(work):
    """Lo que la musica ocupa en RAM, si la ROM con musica esta montada."""
    ruta = os.path.join(work, "musica", "plan.json")
    if not os.path.exists(ruta):
        return []
    with open(ruta) as f:
        d = json.load(f)
    m = d["datos"].get("musica")
    if not m:
        return []
    p = m["puente"]
    ocupa = [(p["ram"], p["ram"] + p["bytes"], "EL PUENTE de la musica (%d B)" % p["bytes"]),
             (0x5C00, 0x5C00 + 382, "area de trabajo del reproductor PT3 (382 B)")]
    # La rutina de las pantallas finales vive justo detras del puente, en la
    # misma tierra de nadie de la pagina 0.
    f_ = d.get("finales")
    if f_:
        ocupa.append((f_["ram"], f_["ram"] + f_["bytes"],
                      "LA RUTINA de las pantallas finales (%d B)" % f_["bytes"]))
    return ocupa


def lee_bufers(work):
    """Los dos bufers de ZX0. Solo se usan MIENTRAS CARGA -despues de saltar a
    0x0190 esa RAM esta libre-, pero hay que contarlos: quien quiera meter algo
    ahi tiene que saber que el cargador pasa por encima antes de arrancar."""
    ruta = os.path.join(work, "musica", "plan.json")
    if not os.path.exists(ruta):
        return []
    with open(ruta) as f:
        d = json.load(f)
    z = d.get("zona_libre")
    if not z:
        return []
    return [(z[cual]["ram"], z[cual]["ram"] + z[cual]["bytes"],
             "bufer de ZX0, SOLO durante la carga: %s" % z[cual]["que"])
            for cual in ("bufer_z", "bufer_d")]


def main(argv):
    work = argv[1] if len(argv) > 1 else "work"
    libres = lee_libres(work)
    musica = lee_musica(work)
    en_la_rom = lee_finales(work)
    bufers = lee_bufers(work)

    # Lo que la CINTA deja en la RAM. Si las dos pantallas finales se quedan en
    # el cartucho, el bloque bajo se acorta hasta donde empezaban: de ahi salen
    # los 13.824 bytes que este cambio libera.
    cinta = list(CINTA)
    if en_la_rom:
        ini_finales = min(a for a, _b in en_la_rom)
        cinta[0] = (cinta[0][0], ini_finales,
                    "bloque bajo: la capa MSX y los graficos (las finales se quedan en la ROM)")

    print("=" * 78)
    print(" LA RAM DE WAR IN MIDDLE EARTH, 64 KB, con el juego corriendo")
    print(" (las cuatro paginas en RAM: no hay BIOS ni cartucho a la vista)")
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
    for ini, fin, que in musica:
        filas.append((ini, fin, "MUSICA", que))
    for ini, fin, que in bufers:
        filas.append((ini, fin, "CARGA", que))
    for ini, fin in libres:
        filas.append((ini, fin, "libre", "nadie lo leyo ni lo escribio en toda la partida"))

    ancho = 44
    for ini, fin, tipo, que in sorted(filas):
        tam = fin - ini
        barra = ("#" if tipo in ("CINTA", "JUEGO")
                 else "*" if tipo in ("IMAGEN", "MUSICA")
                 else "-" if tipo == "EN ROM"
                 else "o" if tipo == "CARGA" else ".")
        n = max(1, min(ancho, round(tam / 65536 * ancho * 6)))
        print("  %04X-%04X %6d B  %-6s %-8s %s"
              % (ini, fin - 1, tam, tipo, barra * min(n, 8), que))

    print()
    print("  Los tramos se SOLAPAN a proposito: lo que la cinta trae y lo que el")
    print("  juego monta encima conviven en las mismas direcciones segun el momento.")
    print()
    total_libre = sum(f - i for i, f in libres)
    print("  RAM que nadie toca en toda la partida: %d B" % total_libre)
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
        for d in range(ini, fin):
            if d in de_la_cinta:
                if tramo:
                    ajena.append(tramo)
                    tramo = None
            elif tramo:
                tramo[1] = d + 1
            else:
                tramo = [d, d + 1]
        if tramo:
            ajena.append(tramo)
    ajena = [t for t in ajena if t[1] - t[0] >= 64]
    for ini, fin in sorted(ajena):
        print("      %04X-%04X  %6d B" % (ini, fin - 1, fin - ini))
    print("      %-11s %6d B  EN TOTAL" % ("", sum(f - i for i, f in ajena)))
    if musica:
        print("  Y de esa, ya hay puesto:")
        usa = 0
        for i, f, que in sorted(musica):
            print("      %04X-%04X  %6d B  %s" % (i, f - 1, f - i, que))
            usa += f - i
        print("  Queda para lo que venga: %d B." % (sum(f - i for i, f in ajena) - usa))
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
