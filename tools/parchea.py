#!/usr/bin/env python3
"""Aplica el parche de Araubi a War in Middle Earth y reconstruye la cinta.

COMO FUNCIONA. El desensamblado no se toca: se parte de los CUERPOS que saca
`make extract` a work/*.raw (los mismos bytes de la cinta, sin la envoltura del
formato Spectrum). Cada cambio es una entrada de la TABLA de mas abajo:

    bloque   en cual de los cuerpos cae (aqui todo es 'medio', 0x5E00)
    dir      la direccion de EJECUCION del primer byte que cambia
    orig     los bytes que DEBE haber ahi (si no, se aborta: no es esta cinta)
    nuevo    los bytes que se escriben (SIEMPRE la misma longitud que orig)
    motivo   por que

La longitud de orig y nuevo es igual byte a byte: nada se desplaza. Antes de
escribir se comprueba que orig es lo que hay; despues se comprueba que, fuera de
los rangos de la tabla, el cuerpo es identico al original. Asi el parche no
puede tocar nada por accidente.

Con los cuerpos ya parcheados se vuelve a montar la cinta: cada bloque del ZX
Spectrum se reenvuelve con su bandera delante y su XOR detras (la unica
verificacion de integridad que trae la cinta), y tools/tsx_build.py arma el TSX.

Uso:  parchea.py [work] [salida.tsx]
"""
import os
import shutil
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import tsx_build  # noqa: E402

# Los cuatro bloques del ZX Spectrum: nombre del cuerpo -> (fichero de bloque en
# el manifiesto, direccion de ejecucion). El cuerpo va envuelto [bandera][cuerpo][XOR].
BLOQUES_SPECTRUM = {
    "pantalla": ("block08.raw", 0x88B8),
    "bajo":     ("block09.raw", 0x0190),
    "medio":    ("block10.raw", 0x5E00),
    "alto":     ("block11.raw", 0x9E00),
}

# La rutina nueva "MUESTRA LOS VALORES" (src/parche/ficha_valores.asm), ensamblada
# con pasmo a org 0x6600. Se guarda aqui para que la tabla sea autocontenida y el
# test pueda reensamblar el .asm y comprobar que sigue dando exactamente esto.
RUTINA_FICHA = bytes.fromhex(
    "c5d53aad6e5f16c21a21737ccd137116c31a218b7ccd137116c01acd967021a37c"
    "cd137116c01ae60f21bb7ccd137116c11ae60f21d37ccd137116c11acd967021eb"
    "7ccd1371d1c121bd5fc9")

# Los 76 bytes originales de 0x6600: el arranque del motor del altavoz del ZX,
# codigo muerto (nadie lo llama; los efectos acaban en el ret de 0x65FF).
ORIG_FICHA = bytes.fromhex(
    "87c6656fce6395677e23666fcd1467ed538066cd1467ed53ba66cd1467ed53ae66"
    "cd1467ed53e766cd1467ed538366cd1467ed53bd66cd1467ed53c666cd1467ed53"
    "0667cd1467ed538c66cd")

# ==========================================================================
# LA TABLA DE PARCHES
# ==========================================================================
PARCHES = [
    # ---- (1) UNIDADES ENEMIGAS VISIBLES ----------------------------------
    # RECENTRA_EL_MAPA (0x7FAC) borra el bit 7 ("aqui hay alguien") de todo el
    # mapa y lo vuelve a poner unidad a unidad, PERO el bucle para en la unidad
    # 0x78 (cp 078h en 0x7FD0): las 0x78-0xFF, que son del otro bando, nunca se
    # siembran, y por eso no se dibujan. Cambiando el tope 0x78 -> 0x00 el bucle
    # recorre las 256 unidades y siembra tambien las enemigas.
    dict(grupo="visibilidad", bloque="medio", dir=0x7FD1, orig="78", nuevo="00",
         motivo="siembra bit7: el bucle de MARCA_UNA_UNIDAD_7FB2 llega a 0xFF, no a 0x78"),

    # ---- (2) VALORES NUMERICOS DE LA UNIDAD (y con ellos, el del Anillo) ---
    # Trampolin en ARMA_LA_FICHA: donde hacia `ld hl,0x5FBD` (21 BD 5F) justo
    # antes de pintar la ficha, ahora llama a la rutina nueva de 0x6600, que
    # escribe los seis atributos en numeros y termina rehaciendo ese ld hl.
    dict(grupo="valores", bloque="medio", dir=0x708A, orig="21bd5f", nuevo="cd0066",
         motivo="trampolin: call MUESTRA_LOS_VALORES (0x6600) antes de PINTA_LA_VENTANA"),
    # La rutina, escrita sobre el motor de sonido muerto de 0x6600.
    dict(grupo="valores", bloque="medio", dir=0x6600, orig=ORIG_FICHA.hex(),
         nuevo=RUTINA_FICHA.hex(),
         motivo="MUESTRA_LOS_VALORES: 0xC000/0xC100/0xC200/0xC300 en cifras en la ficha"),
]


def aplica(cuerpos):
    """Aplica la tabla sobre un dict {nombre: bytearray}. Devuelve rangos tocados."""
    rangos = {}
    for p in PARCHES:
        nombre = p["bloque"]
        org = BLOQUES_SPECTRUM[nombre][1]
        cuerpo = cuerpos[nombre]
        orig = bytes.fromhex(p["orig"])
        nuevo = bytes.fromhex(p["nuevo"])
        if len(orig) != len(nuevo):
            raise SystemExit("parche 0x%04X: orig(%d) y nuevo(%d) miden distinto"
                             % (p["dir"], len(orig), len(nuevo)))
        off = p["dir"] - org
        if off < 0 or off + len(orig) > len(cuerpo):
            raise SystemExit("parche 0x%04X: se sale del bloque %s" % (p["dir"], nombre))
        hay = bytes(cuerpo[off:off + len(orig)])
        if hay != orig:
            raise SystemExit(
                "parche 0x%04X (%s): esperaba %s pero hay %s. No es esta cinta."
                % (p["dir"], nombre, orig.hex(), hay.hex()))
        cuerpo[off:off + len(nuevo)] = nuevo
        rangos.setdefault(nombre, []).append((off, off + len(nuevo)))
    return rangos


def reenvuelve_spectrum(cuerpo, bandera):
    """[bandera] + cuerpo + [XOR de todo lo anterior]."""
    x = bandera
    for c in cuerpo:
        x ^= c
    return bytes([bandera]) + bytes(cuerpo) + bytes([x])


def main(argv):
    work = argv[1] if len(argv) > 1 else os.path.join(RAIZ, "work")
    salida = argv[2] if len(argv) > 2 else os.path.join(RAIZ, "war_parche.tsx")
    ext = os.path.join(RAIZ, "extracted")
    if not os.path.exists(os.path.join(work, "medio.raw")):
        raise SystemExit("no hay %s/medio.raw; ejecuta antes `make extract`" % work)

    # 1. Cargar los cuerpos originales y aplicar la tabla sobre una copia.
    origs = {n: open(os.path.join(work, n + ".raw"), "rb").read()
             for n in BLOQUES_SPECTRUM}
    cuerpos = {n: bytearray(b) for n, b in origs.items()}
    rangos = aplica(cuerpos)

    # 2. Comprobar que SOLO ha cambiado lo de la tabla.
    print("== parches aplicados ==")
    total = 0
    for grupo in ("visibilidad", "valores", "anillo"):
        gp = [p for p in PARCHES if p["grupo"] == grupo]
        if not gp:
            continue
        print("  [%s]" % grupo)
        for p in gp:
            print("    0x%04X  %-6s %2d B  %s -> %s  %s"
                  % (p["dir"], p["bloque"], len(bytes.fromhex(p["orig"])),
                     p["orig"], p["nuevo"], p["motivo"]))
            total += len(bytes.fromhex(p["nuevo"]))
    fuera = 0
    for n in BLOQUES_SPECTRUM:
        o, c = origs[n], cuerpos[n]
        permitido = rangos.get(n, [])
        for i in range(len(o)):
            if o[i] == c[i]:
                continue
            if not any(a <= i < b for a, b in permitido):
                fuera += 1
    if fuera:
        raise SystemExit("FALLO: %d bytes cambiados FUERA de la tabla" % fuera)
    print("  %d bytes cambiados, 0 fuera de la tabla" % total)

    # 3. Escribir los cuerpos parcheados.
    pdir = os.path.join(work, "parche")
    os.makedirs(pdir, exist_ok=True)
    for n, c in cuerpos.items():
        open(os.path.join(pdir, n + ".raw"), "wb").write(c)

    # 4. Reconstruir la cinta: reenvolver los bloques Spectrum y montar el TSX.
    tape = os.path.join(pdir, "tape")
    os.makedirs(tape, exist_ok=True)
    for f in os.listdir(ext):
        if f.startswith("block") and f.endswith(".raw"):
            shutil.copy(os.path.join(ext, f), os.path.join(tape, f))
    for n, (fichero, _org) in BLOQUES_SPECTRUM.items():
        original = open(os.path.join(ext, fichero), "rb").read()
        bandera = original[0]
        nuevo = reenvuelve_spectrum(cuerpos[n], bandera)
        assert len(nuevo) == len(original), "%s cambio de tamano" % n
        open(os.path.join(tape, fichero), "wb").write(nuevo)
    tsx_build.build(os.path.join(ext, "manifest.json"), salida, tape)
    print("cinta parcheada -> %s" % salida)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
