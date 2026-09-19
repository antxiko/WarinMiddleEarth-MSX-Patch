#!/usr/bin/env python3
"""Traduce el WYZ PSG proPLAYER de msx-msxlib de sintaxis tniASM a la de pasmo.

Son dos ficheros y salen dos:

    wyzplayer-ROM.tniasm.asm  ->  src/cartucho/wyz_player.asm
    wyzplayer-RAM.tniasm.asm  ->  src/cartucho/wyz_trabajo.inc

El de RAM no es codigo: es la lista de variables del reproductor, en un orden
que el propio fichero declara FIJO porque el reproductor las recorre con IX
desde PUNTERO_A. Alli se reservan con `rb`/`rw`; aqui, como el codigo vive en
la ROM del cartucho, cada una es un `equ` a su direccion. Se generan en vez de
escribirse a mano por lo de siempre: a mano se quedan viejas en cuanto alguien
anade una variable, y los desplazamientos de IX del reproductor -que son
restas entre dos de ellas- darian todos un byte de mas. Ver la memoria
`no-contar-desplazamientos-a-mano`.

La traduccion es MECANICA, y por eso la hace una herramienta y no unas manos:
son 315 corchetes, 33 numeros binarios, 15 con `$` y 32 desplazamientos de IX
que hay que calcular. Lo que la comprueba no es leerla: es que pasmo la
ensamble y que el reproductor suene en el emulador.

Reglas:
  [expr]      -> (expr)      indireccion; tniASM usa corchetes
  $XXXX       -> 0XXXXh      y si empieza por letra, 0 delante
  00110110B   -> 036h        pasmo no lleva el sufijo B de tniASM
  IX+A-B      -> IX+n        pasmo evalua la resta en 16 bits SIN signo y la
                             rechaza con "Offset out of range" aunque quepa
  ADC E       -> ADC A,E     tniASM se come el acumulador; pasmo lo exige
  IFDEF X     ->             se resuelve aqui: lo que no se pide, no sale

No se toca nada mas: ni el orden, ni las instrucciones, ni los comentarios.

Uso:
  convierte_wyz.py <wyzplayer-ROM.asm> <wyzplayer-RAM.asm> <salida.asm> <salida.inc> --ram 0x5C00
  convierte_wyz.py --cancion <cancion.mus.asm> <salida.asm>
"""
import argparse
import re
import sys

# Lo que NO se pide. El cartucho solo tiene que tocar la musica del menu:
# sin fundido, sin tempos hibridos y sin efectos de sonido externos. Cada uno
# que se quiera se anade aqui y entra su codigo.
DEFINIDOS = set()

# Un `$` seguido de digitos hexadecimales, pero NO dentro de una palabra.
HEX = re.compile(r"(?<![A-Za-z0-9_])\$([0-9A-Fa-f]+)")
# Un numero binario de tniASM: digitos 0/1 y una B al final. El `(?<![\w$.])`
# es para no morder ni el final de una etiqueta (CANAL_B) ni un hexadecimal.
BIN = re.compile(r"(?<![\w$.])([01]{2,8})B(?![\w])")
# Los desplazamientos de IX/IY escritos como resta entre dos variables:
# `IX+PUNTERO_DECA-PUNTERO_A+1`. Con numeros sueltos -IX+0- no se toca nada.
DESP = re.compile(r"\b(I[XY])\+([A-Za-z_][A-Za-z0-9_]*(?:\s*[-+]\s*[A-Za-z_][A-Za-z0-9_]*|\s*[-+]\s*\d+)*)")
# `ADC E` por `ADC A,E`. tniASM da por sabido el acumulador en las tres que lo
# llevan implicito; pasmo lo exige escrito. Las demas -AND, OR, XOR, CP, SUB-
# son de un operando de verdad y no se tocan. Con coma dentro no hay nada que
# hacer: `ADD HL,DE` ya esta completa.
ACUMULADOR = re.compile(r"^(\s*(?:[A-Za-z_][A-Za-z0-9_]*:)?\s*)(ADC|ADD|SBC)(\s+)([^,\s][^,]*?)(\s*)$", re.I)


def hex_pasmo(m):
    v = m.group(1)
    return ("0" + v + "h") if v[0].isalpha() else (v + "h")


def bin_pasmo(m):
    return "0%02Xh" % int(m.group(1), 2)


def sin_comentario(linea):
    """El comentario se deja intacto: puede llevar corchetes que son prosa."""
    codigo, punto_coma, comentario = linea.partition(";")
    return codigo, punto_coma + comentario


def resuelve_ifdef(lineas, fichero):
    """Quita los bloques IFDEF/IFNDEF cuyo simbolo no se ha pedido.

    tniASM no tiene ELSE aqui, pero se lleva la cuenta con una pila por si
    alguna version lo trae: si aparece uno, esto se para en vez de tragarselo.
    """
    salida, pila, quitadas = [], [], 0
    for n, linea in enumerate(lineas, 1):
        codigo, _ = sin_comentario(linea)
        m = re.match(r"\s*(IFDEF|IFNDEF|ELSE|ENDIF)\b\s*(\S*)", codigo)
        if m:
            que, simbolo = m.group(1), m.group(2)
            if que == "IFDEF":
                pila.append(simbolo in DEFINIDOS)
            elif que == "IFNDEF":
                pila.append(simbolo not in DEFINIDOS)
            elif que == "ELSE":
                raise SystemExit("%s:%d: ELSE en un IFDEF, y esto no lo sabe hacer" % (fichero, n))
            else:
                if not pila:
                    raise SystemExit("%s:%d: ENDIF sin IFDEF" % (fichero, n))
                pila.pop()
            quitadas += 1
            continue
        if all(pila):
            salida.append(linea)
        else:
            quitadas += 1
    if pila:
        raise SystemExit("%s: se acaba el fichero con un IFDEF sin cerrar" % fichero)
    return salida, quitadas


def lee_variables(fichero):
    """Las variables del fichero de RAM, EN ORDEN, con lo que ocupa cada una.

    `rb n` son n bytes y `rw n` son n palabras. El orden importa: el
    reproductor llega a las de los canales B y C sumandole a IX la distancia
    que hay desde las del canal A.
    """
    lineas, _ = resuelve_ifdef(open(fichero, encoding="latin-1").read().splitlines(), fichero)
    variables = []
    for linea in lineas:
        codigo, _ = sin_comentario(linea)
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:?\s+(rb|rw)\s+(\S+)", codigo)
        if not m:
            continue
        nombre, que, cuantos = m.group(1), m.group(2), m.group(3)
        n = int(cuantos[1:], 16) if cuantos.startswith("$") else int(cuantos)
        variables.append((nombre, n * (1 if que == "rb" else 2)))
    return variables


def escribe_inc(variables, base, destino, origen):
    """El .inc: cada variable, un `equ` a su direccion."""
    ancho = max(len(n) for n, _ in variables)
    with open(destino, "w", encoding="latin-1", newline="\n") as f:
        f.write("; El area de trabajo del reproductor WYZ, en la RAM libre de 0x%04X.\n"
                "; GENERADO por tools/convierte_wyz.py a partir de\n"
                "; %s: no editar a mano.\n"
                ";\n"
                "; Alli se reservan con rb/rw y aqui, como el codigo vive en la ROM del\n"
                "; cartucho, cada variable es un `equ` a su direccion. EL ORDEN ES FIJO: el\n"
                "; reproductor recorre los tres canales sumandole a IX la distancia entre\n"
                "; las variables del canal A y las del B.\n\n" % (base, origen))
        dir_ = base
        for nombre, n in variables:
            f.write("%-*s equ 0%04Xh%s\n" % (ancho, nombre, dir_,
                                             "" if n == 1 else "   ; %d bytes" % n))
            dir_ += n
        f.write("\nWYZ_TRABAJO_FIN  equ 0%04Xh   ; %d bytes en total\n" % (dir_, dir_ - base))
    return dir_ - base


def traduce(lineas, constantes, fichero):
    """Las cuatro reglas de sintaxis, linea a linea."""
    salida = []
    cuenta = dict(corchetes=0, hex=0, binarios=0, desplazamientos=0, acumulador=0)

    def desplazamiento(m):
        reg, expr = m.group(1), m.group(2)
        try:
            valor = eval(expr, {"__builtins__": {}}, dict(constantes))
        except Exception as e:
            raise SystemExit("%s: no se puede evaluar %s+%s: %s" % (fichero, reg, expr, e))
        if not -128 <= valor <= 127:
            raise SystemExit("%s: %s+%s = %d, que no cabe en un desplazamiento"
                             % (fichero, reg, expr, valor))
        cuenta["desplazamientos"] += 1
        return "%s%+d" % (reg, valor)

    for linea in lineas:
        codigo, comentario = sin_comentario(linea)

        cuenta["corchetes"] += codigo.count("[")
        codigo = codigo.replace("[", "(").replace("]", ")")

        cuenta["hex"] += len(HEX.findall(codigo))
        codigo = HEX.sub(hex_pasmo, codigo)

        cuenta["binarios"] += len(BIN.findall(codigo))
        codigo = BIN.sub(bin_pasmo, codigo)

        codigo = DESP.sub(desplazamiento, codigo)

        m = ACUMULADOR.match(codigo)
        if m:
            cuenta["acumulador"] += 1
            codigo = "%s%s%sA,%s%s" % (m.group(1), m.group(2), m.group(3),
                                       m.group(4), m.group(5))

        salida.append(codigo + comentario)
    return salida, cuenta


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("ficheros", nargs="+")
    p.add_argument("--ram", default="0x5C00",
                   help="donde empieza el area de trabajo (por defecto 0x5C00)")
    p.add_argument("--con", default="",
                   help="opciones del reproductor, separadas por comas: fade, sfx, hybrid")
    p.add_argument("--cancion", action="store_true",
                   help="traduce el .mus.asm de una cancion (pautas, efectos y notas)")
    a = p.parse_args()

    for o in filter(None, a.con.split(",")):
        DEFINIDOS.add("CFG_WYZ_" + o.strip().upper())

    if a.cancion:
        if len(a.ficheros) != 2:
            p.error("--cancion quiere <cancion.mus.asm> <salida.asm>")
        origen, destino = a.ficheros
        lineas = open(origen, encoding="latin-1").read().splitlines()
        salida, cuenta = traduce(lineas, {}, origen)
        with open(destino, "w", encoding="latin-1", newline="\n") as f:
            f.write("\n".join(salida) + "\n")
        print("traducida la cancion %s -> %s" % (origen, destino))
        return

    if len(a.ficheros) != 4:
        p.error("quiere <ROM.asm> <RAM.asm> <salida.asm> <salida.inc>")
    rom, ram, destino_asm, destino_inc = a.ficheros
    base = int(a.ram, 0)

    # 1. Las variables, que ademas son las constantes con las que se calculan
    #    los desplazamientos de IX del reproductor.
    variables = lee_variables(ram)
    constantes, dir_ = {}, base
    for nombre, n in variables:
        constantes[nombre] = dir_
        dir_ += n
    ocupa = escribe_inc(variables, base, destino_inc, ram)

    # 2. El reproductor. A las constantes se les suman sus propios `equ`, que
    #    son los cuatro bits de WYZ_FLAGS.
    lineas = open(rom, encoding="latin-1").read().splitlines()
    for linea in lineas:
        codigo, _ = sin_comentario(linea)
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:?\s+equ\s+(-?\d+)\s*$", codigo, re.I)
        if m:
            constantes[m.group(1)] = int(m.group(2))
    lineas, quitadas = resuelve_ifdef(lineas, rom)
    salida, cuenta = traduce(lineas, constantes, rom)
    with open(destino_asm, "w", encoding="latin-1", newline="\n") as f:
        f.write("\n".join(salida) + "\n")

    print("traducido %s -> %s" % (rom, destino_asm))
    print("  corchetes de indireccion: %d" % cuenta["corchetes"])
    print("  numeros con $:            %d" % cuenta["hex"])
    print("  numeros binarios:         %d" % cuenta["binarios"])
    print("  desplazamientos IX/IY:    %d" % cuenta["desplazamientos"])
    print("  ADC/ADD/SBC sin A:        %d" % cuenta["acumulador"])
    print("  lineas quitadas por IFDEF: %d  (definidos: %s)"
          % (quitadas, ", ".join(sorted(DEFINIDOS)) or "ninguno"))
    print("traducido %s -> %s" % (ram, destino_inc))
    print("  %d variables, %d bytes de 0x%04X a 0x%04X"
          % (len(variables), ocupa, base, base + ocupa - 1))


if __name__ == "__main__":
    sys.exit(main())
