#!/usr/bin/env python3
"""Traduce el PT3-ROM.ASM de msx-msxlib de sintaxis asMSX a la de pasmo.

La traduccion es MECANICA y por eso se hace con una herramienta y no a mano:
son 244 corchetes, 34 `.equ`, 25 `.dw`/`.db` y 16 numeros con `$`. Lo que la
comprueba no es leerla, es que pasmo la ensamble y que salgan los **1528
bytes** que la cabecera del original dice que ocupa.

Reglas:
  [expr]      -> (expr)      indireccion; asMSX usa corchetes
  .equ        -> equ
  .dw / .db   -> defw / defb
  $XXXX       -> 0XXXXh      y si empieza por letra, 0 delante
  % 65536     -> pasmo ya trunca a 16 bits; el modulo se queda igual

No se toca nada mas: ni el orden, ni las instrucciones, ni los comentarios.

Uso: convierte.py <PT3-ROM.ASM> <salida.asm>
"""
import re
import sys

ORIGEN, DESTINO = sys.argv[1], sys.argv[2]

# Un `$` seguido de digitos hexadecimales, pero NO dentro de una palabra
# (por si hay etiquetas con $, que no las hay, pero mas vale atarlo).
HEX = re.compile(r"(?<![A-Za-z0-9_])\$([0-9A-Fa-f]+)")


def hex_pasmo(m):
    v = m.group(1)
    return ("0" + v + "h") if v[0].isalpha() else (v + "h")


# Los desplazamientos de IX/IY: `IX+(CHNPRM_X-12)`.
#
# pasmo evalua `0-12` en 16 bits SIN signo -65524- y lo rechaza con "Offset out
# of range", aunque el desplazamiento real sea -12 y quepa de sobra. asMSX no se
# quejaba. Asi que aqui se calculan y se escriben ya con su signo: `IX-12`.
# Comprobado: `ld (ix+(CERO-12)),a` falla y `ld (ix-12),a` ensambla.
CONSTANTES = {}
for l in open(ORIGEN, encoding="latin-1"):
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s+\.equ\s+(-?\d+)", l)
    if m:
        CONSTANTES[m.group(1)] = int(m.group(2))

DESP = re.compile(r"(I[XY])\+\(([^()]*)\)")


def desplazamiento(m):
    global n_desp
    reg, expr = m.group(1), m.group(2)
    try:
        valor = eval(expr, {"__builtins__": {}}, dict(CONSTANTES))
    except Exception as e:
        print("  NO EVALUA %r: %s" % (expr, e)); return m.group(0)                    # no se sabe: se deja como estaba
    if not -128 <= valor <= 127:
        raise SystemExit("%s+(%s) = %d, que no cabe en un desplazamiento"
                         % (reg, expr, valor))
    n_desp += 1
    return "%s%+d" % (reg, valor)


salida = []
n_corchetes = n_equ = n_datos = n_hex = n_desp = n_modulo = 0
for linea in open(ORIGEN, encoding="latin-1"):
    # El comentario se deja intacto: puede llevar corchetes que son prosa.
    codigo, punto_coma, comentario = linea.partition(";")

    n_corchetes += codigo.count("[")
    codigo = codigo.replace("[", "(").replace("]", ")")

    if ".equ" in codigo:
        n_equ += 1
        codigo = codigo.replace(".equ", "equ")

    for viejo, nuevo in ((".dw", "defw"), (".db", "defb")):
        if viejo in codigo:
            n_datos += 1
            codigo = codigo.replace(viejo, nuevo)

    n_hex += len(HEX.findall(codigo))
    codigo = HEX.sub(hex_pasmo, codigo)

    codigo = DESP.sub(desplazamiento, codigo)

    # El unico modulo del fichero. En asMSX el % trunca a 16 bits; pasmo no lo
    # entiende y responde "Division by zero". Ademas los parentesis de fuera eran
    # AGRUPACION -en asMSX la indireccion son corchetes-, asi que dejarlos seria
    # peor que el error: pasmo leeria una carga DESDE MEMORIA en vez de un valor.
    # Se quitan los dos, y el truncamiento a 16 bits lo hace pasmo solo.
    if "% 65536" in codigo:
        codigo = codigo.replace("((SPCCOMS+0DF20h) % 65536)", "SPCCOMS+0DF20h")
        n_modulo += 1

    salida.append(codigo + punto_coma + comentario)

with open(DESTINO, "w", encoding="latin-1", newline="\n") as f:
    f.writelines(salida)

print("traducido %s -> %s" % (ORIGEN, DESTINO))
print("  corchetes de indireccion: %d" % n_corchetes)
print("  .equ:                     %d" % n_equ)
print("  lineas de datos .dw/.db:  %d" % n_datos)
print("  numeros con $:            %d" % n_hex)
print("  desplazamientos IX/IY:    %d" % n_desp)
print("  modulos %% 65536:          %d" % n_modulo)
