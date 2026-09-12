#!/usr/bin/env python3
"""EL MAPA DE LA ROM: que hay en cada tramo de los 64 KB del cartucho.

Hermano de tools/mapa_ram.py, y como el, sin una sola cifra escrita a mano:
todo sale del plan.json que genera tools/haz_rom.py de la disposicion real.

La ROM es una MegaROM ASCII16 de cuatro bancos de 16 KB. Solo se ve un banco
cada vez por cada una de las dos ventanas -0x4000 la manda el registro de
0x6000 y 0x8000 la de 0x7000-, asi que aqui se dibuja la ROM ENTERA, de
0x00000 a 0x0FFFF, que es como esta en el fichero.

Uso:  mapa_rom.py [plan.json]        (por defecto, work/musica/plan.json)
"""
import json
import os
import sys

TAM_BANCO = 0x4000


def filas_de(plan):
    """Cada tramo con nombre, en orden, tal y como lo dice el plan."""
    filas = [(0, plan["arranque"], "ARRANQUE", "cabecera AB y el salto al stub"),
             (plan["arranque"], plan["arranque"] + plan["stub"], "STUB",
              "el cargador que corre en 0x%04X, con el plan de %d operaciones dentro"
              % (plan["stub_ram"], len(plan["plan"])))]
    cabeza = plan["arranque"] + plan["stub"]
    datos = min(d["rom"] for d in plan["datos"].values())
    if datos > cabeza:
        filas.append((cabeza, datos, "relleno", "0xFF hasta donde empiezan los datos"))
    for nombre, d in sorted(plan["datos"].items(), key=lambda kv: kv[1]["rom"]):
        if nombre == "musica":
            m = d
            fin_repro = d["rom"] + d["reproductor"]
            filas.append((d["rom"], fin_repro, "MUSICA",
                          "reproductor PT3 y el modulo %s" % d["pt3"]))
            p = d["puente"]
            filas.append((p["rom"], p["rom"] + p["bytes"], "MUSICA",
                          "el puente, que viaja aqui y corre en 0x%04X" % p["ram"]))
            continue
        que = d.get("que", nombre)
        if d.get("zx0"):
            que = "%s  [%d B -> %d con ZX0, -%d]" % (que, d["crudo"], d["bytes"],
                                                     d["crudo"] - d["bytes"])
        filas.append((d["rom"], d["rom"] + d["bytes"], "DATOS", que))
    f = plan.get("finales")
    if f:
        filas.append((f["rom"], f["rom"] + f["bytes"], "FINALES",
                      "la rutina de las pantallas finales, que corre en 0x%04X" % f["ram"]))
    return sorted(filas)


def main(argv):
    ruta = argv[1] if len(argv) > 1 else os.path.join("work", "musica", "plan.json")
    if not os.path.exists(ruta):
        print("no encuentro %s: hace falta `make rom_musica` con tu cinta" % ruta)
        return 2
    with open(ruta) as f:
        plan = json.load(f)

    print("=" * 78)
    print(" LA ROM DE WAR IN MIDDLE EARTH: %s, %d KB, mapper %s"
          % (plan["rom"], plan["bytes"] // 1024, plan["mapper"]))
    print(" (cuatro bancos de 16 KB; por cada ventana se ve uno cada vez)")
    print("=" * 78)
    print()

    filas = filas_de(plan)
    banco = -1
    for ini, fin, tipo, que in filas:
        if ini // TAM_BANCO != banco:
            banco = ini // TAM_BANCO
            print("  --- banco %d (0x%05X-0x%05X) %s"
                  % (banco, banco * TAM_BANCO, (banco + 1) * TAM_BANCO - 1, "-" * 28))
        barra = {"ARRANQUE": "#", "STUB": "#", "DATOS": "*", "MUSICA": "+",
                 "FINALES": "+", "relleno": "."}[tipo]
        tam = fin - ini
        n = max(1, min(8, round(tam / 2048)))
        print("  %05X-%05X %6d B  %-8s %-8s %s"
              % (ini, fin - 1, tam, tipo, barra * n, que))

    ocupado = max(f[1] for f in filas)
    libre = plan["bytes"] - ocupado
    print()
    print("  %05X-%05X %6d B  LIBRE    %s  el hueco, hasta el final de la ROM"
          % (ocupado, plan["bytes"] - 1, libre, " " * 8))
    print()
    # Lo que se gano comprimiendo, sumado de lo que el propio plan declara.
    crudo = sum(d["crudo"] for d in plan["datos"].values() if d.get("zx0"))
    comp = sum(d["bytes"] for d in plan["datos"].values() if d.get("zx0"))
    if crudo:
        print("  Comprimido con ZX0: %d B de imagenes en %d (-%d, el %.0f %%)."
              % (crudo, comp, crudo - comp, 100.0 * (crudo - comp) / crudo))
    print("  Hueco libre: %d bytes." % libre)
    if libre and "musica" in plan["datos"]:
        print("  Un modulo PT3 mas grande cabe mientras no pase de ahi;"
              " el de ahora ocupa %d B." % plan["datos"]["musica"]["bytes"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
