#!/usr/bin/env python3
"""Coteja lo que deja el cartucho con lo que deja la cinta, byte a byte.

Misma RAM = mismo juego. El cartucho no toca el codigo del juego: solo lo
coloca. Asi que la prueba de que el cartucho es la cinta es que, en los dos
instantes que se volcaron con la cinta, la memoria sea la misma:

  en 0x0190  los tres bloques tal como caen de la cinta, sin recolocar
             (0x0190-0x783F y 0x88B8-0xD12F contra full_crudo.bin)
  en 0x5E00  ya recolocados, el juego arrancando (0x0190-0x3F4E,
             0x5E00-0x96F0 y 0x9E00-0xE677 contra full_5e00.bin), y ademas
             la VRAM entera, los registros 0-7 del VDP y los del PSG contra
             lo medido con la cinta (work/estado_cinta)

Fuera de esas regiones la RAM es lo que cada cargador dejo (la pila, el buzon
de POKEs, el propio cargador) y no se exige que coincida; se informa.

Uso: coteja_rom.py <dir volcados del cartucho> <dir volcados de la cinta> <dir estado_cinta>
     [--sin-finales <plan.json>]  si la ROM lleva las pantallas finales en el
                                  cartucho: el tramo y el parche salen de ese plan
Sale con 1 si algo de lo exigido no cuadra.
"""
import os
import sys

REGIONES_0190 = [(0x0190, 0x783F, "bajo + medio, como caen de la cinta"),
                 (0x88B8, 0xD12F, "alto, como cae de la cinta")]
REGIONES_5E00 = [(0x0190, 0x3F4E, "bloque bajo"),
                 (0x5E00, 0x96F0, "bloque medio, recolocado"),
                 (0x9E00, 0xE677, "bloque alto, recolocado")]

# Con --sin-finales, las dos pantallas del final no viajan a la RAM: se quedan
# en la ROM y se descomprimen a 0x4000 al acabar la partida. Su tramo se recorta
# de las regiones exigidas, porque alli ya no hay nada que comparar.
#
# OJO: un cotejo NO VE LO QUE EXCLUYE. Que esas pantallas siguen siendo las de
# la cinta lo dice `make verifica_finales`, que las fuerza y compara los 6.912
# bytes que quedan en 0x4000 con los del bloque bajo. Sin ese, esto seria un
# agujero.


def lo_que_no_se_exige(plan):
    """El tramo de las pantallas y los bytes del parche, LEIDOS DEL PLAN.

    Escritos a mano se quedarian viejos en cuanto la rutina cambie de sitio o el
    parche de tamano, y el cotejo empezaria a exigir una direccion que ya no es
    -o, peor, a perdonar una que si.- El plan lo genera tools/haz_rom.py de la
    disposicion real."""
    f = plan["finales"]
    ini = min(q["dir"] for q in f["pantallas"])
    fin = max(q["dir"] + q["crudo"] for q in f["pantallas"]) - 1
    q = f["parche"]
    n = len(bytes.fromhex(q["nuevo"]))
    # `dir` es donde el juego lo ejecuta (0x5E00 arriba) y `carga` donde cae
    # antes de que 0x0190 recoloque el bloque: hacen falta los dos, uno por
    # cada volcado.
    return (ini, fin), (range(q["carga"], q["carga"] + n), range(q["dir"], q["dir"] + n))


def recorta(regiones, fuera):
    """Las mismas regiones sin el tramo `fuera`, partiendolas si hace falta."""
    ini_f, fin_f = fuera
    out = []
    for ini, fin, que in regiones:
        if fin < ini_f or ini > fin_f:
            out.append((ini, fin, que))
            continue
        if ini < ini_f:
            out.append((ini, ini_f - 1, que + " (hasta las pantallas finales)"))
        if fin > fin_f:
            out.append((fin_f + 1, fin, que + " (desde el final de las pantallas)"))
    return out


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def tramos(diferentes):
    out = []
    for i in diferentes:
        if out and i == out[-1][1] + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def coteja(nombre, a, b, regiones, perdonados=()):
    """Compara a (cartucho) con b (cinta). Devuelve cuantos bytes fallan en lo
    exigido. `perdonados` son los bytes que la ROM declara cambiar a proposito:
    salen del plan, no de una lista escrita aqui."""
    perdonados = set(perdonados)
    malos = 0
    for ini, fin, que in regiones:
        d = [i for i in range(ini, fin + 1) if a[i] != b[i] and i not in perdonados]
        estado = "OK" if not d else "%d bytes distintos, p.ej. 0x%04X" % (len(d), d[0])
        print("  %s 0x%04X-0x%04X %-36s %s" % (nombre, ini, fin, que, estado))
        malos += len(d)
    # y lo demas, solo para saberlo
    exigido = set()
    for ini, fin, _ in regiones:
        exigido.update(range(ini, fin + 1))
    otros = [i for i in range(len(a)) if i not in exigido and a[i] != b[i]]
    if otros:
        t = tramos(otros)
        print("  %s fuera de lo exigido: %d bytes distintos en %d tramos: %s%s"
              % (nombre, len(otros), len(t),
                 ", ".join("0x%04X-0x%04X" % (x, y) for x, y in t[:8]), "..." if len(t) > 8 else ""))
    return malos


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    cart, cinta, estado = argv[1:4]
    regiones_0190, regiones_5e00 = REGIONES_0190, REGIONES_5E00
    perdonados_0190 = perdonados_5e00 = ()
    if "--sin-finales" in argv:
        import json
        ruta = argv[argv.index("--sin-finales") + 1]
        with open(ruta) as f:
            plan = json.load(f)
        fuera, (perdonados_0190, perdonados_5e00) = lo_que_no_se_exige(plan)
        regiones_0190 = recorta(regiones_0190, fuera)
        regiones_5e00 = recorta(regiones_5e00, fuera)
        print("Las dos pantallas finales van en la ROM: 0x%04X-0x%04X no se exige,"
              % fuera)
        print("y el `call` que las pide, %d bytes en 0x%04X, tampoco."
              % (len(perdonados_5e00), perdonados_5e00[0]))
    fallos = 0

    print("En 0x0190 (contra %s/full_crudo.bin):" % cinta)
    fallos += coteja("RAM", lee(os.path.join(cart, "ram_0190.bin")),
                     lee(os.path.join(cinta, "full_crudo.bin")), regiones_0190, perdonados_0190)

    print("En 0x5E00 (contra %s/full_5e00.bin):" % cinta)
    fallos += coteja("RAM", lee(os.path.join(cart, "ram_5e00.bin")),
                     lee(os.path.join(cinta, "full_5e00.bin")), regiones_5e00, perdonados_5e00)

    v_cart = lee(os.path.join(cart, "vram_5e00.bin"))[:0x4000]
    v_cinta = lee(os.path.join(estado, "vram_5e00.bin"))[:0x4000]
    d = [i for i in range(0x4000) if v_cart[i] != v_cinta[i]]
    print("  VRAM 0x0000-0x3FFF (16 KB)                                %s"
          % ("OK" if not d else "%d bytes distintos, p.ej. 0x%04X" % (len(d), d[0])))
    fallos += len(d)

    r_cart = lee(os.path.join(cart, "vdpregs_5e00.bin"))[:8]
    r_cinta = lee(os.path.join(estado, "vdpregs_5e00.bin"))[:8]
    if r_cart == r_cinta:
        veredicto = "OK"
    elif bytes([r_cart[1] | 0x80]) == r_cinta[1:2] and r_cart[:1] + r_cart[2:] == r_cinta[:1] + r_cinta[2:]:
        # El bit 7 de R1 es el selector 4K/16K del TMS9918; el V9938 de las
        # MSX2 no lo tiene y lo devuelve a cero. El cartucho escribe 0xE0 en
        # las dos (plan.json), y en la VG-8020 se lee 0xE0.
        veredicto = "OK (el bit 7 de R1 no existe en el V9938 de las MSX2)"
    else:
        veredicto = "DISTINTOS"
        fallos += 1
    print("  VDP R0-R7 cartucho %s  cinta %s  %s" % (r_cart.hex(" "), r_cinta.hex(" "), veredicto))

    p_cart = bytearray(lee(os.path.join(cart, "psgregs_5e00.bin"))[:14])
    p_cinta = bytearray(lee(os.path.join(estado, "psgregs_5e00.bin"))[:14])
    # el bit 7 del registro 7 es el sentido del puerto B: el juego lo pone el mismo
    p_cart[7] &= 0x3F
    p_cinta[7] &= 0x3F
    print("  PSG R0-R13 cartucho %s  cinta %s  %s"
          % (p_cart.hex(" "), p_cinta.hex(" "), "OK" if p_cart == p_cinta else "DISTINTOS"))
    fallos += p_cart != p_cinta

    print("RESULTADO: %s" % ("todo lo exigido coincide" if not fallos else "%d diferencias" % fallos))
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
