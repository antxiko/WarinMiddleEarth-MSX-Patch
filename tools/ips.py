#!/usr/bin/env python3
"""Saca un parche IPS de la diferencia entre dos ficheros del mismo tamano.

Aqui sirve para repartir el parche SIN repartir el juego: el .ips lleva solo los
bytes que cambian -codigo nuestro y el dibujo del Ojo de Sauron-, y cada cual lo
aplica sobre SU copia de la cinta.

    python3 tools/ips.py <original.tsx> <parcheado.tsx> <salida.ips>
    python3 tools/ips.py --aplica <original.tsx> <parche.ips> <salida.tsx>

El formato IPS es de 1990 y cabe en un parrafo: la cabecera "PATCH", luego los
registros -tres bytes de posicion y dos de longitud, en big endian, seguidos de
los datos- y al final "EOF". Un registro con longitud cero es la variante RLE,
que aqui no se usa: los tramos son cortos y no compensa.

Dos limites del formato que aqui no molestan pero conviene tener escritos:
la posicion no pasa de 0xFFFFFF (16 MB) y no puede valer 0x454F46, que es "EOF"
y cortaria el parche a la mitad.
"""
import sys

CABECERA = b"PATCH"
FINAL = b"EOF"
MAX_TRAMO = 0xFFFF
POSICION_PROHIBIDA = 0x454F46   # "EOF" leido como numero


def tramos(a, b, hueco=6):
    """Los tramos que cambian, uniendo los que esten a `hueco` bytes o menos.

    Unirlos sale a cuenta: cada registro cuesta cinco bytes de cabecera, asi que
    arrastrar cuatro o cinco bytes iguales es mas barato que abrir otro.
    """
    fuera = []
    n = len(a)
    i = 0
    while i < n:
        if a[i] == b[i]:
            i += 1
            continue
        fin = i + 1                    # el ultimo byte distinto visto, +1
        iguales = 0
        j = i + 1
        while j < n:
            if a[j] != b[j]:
                fin = j + 1
                iguales = 0
            else:
                iguales += 1
                if iguales > hueco:
                    break
            j += 1
        fuera.append((i, fin))
        i = fin
    return fuera


def crea(original, parcheado):
    a = open(original, "rb").read()
    b = open(parcheado, "rb").read()
    if len(a) != len(b):
        raise SystemExit("los dos ficheros tienen que medir igual: %d y %d"
                         % (len(a), len(b)))
    salida = bytearray(CABECERA)
    total = 0
    for ini, fin in tramos(a, b):
        while ini < fin:
            trozo = min(fin - ini, MAX_TRAMO)
            if ini > 0xFFFFFF:
                raise SystemExit("posicion 0x%X fuera del alcance del IPS" % ini)
            if ini == POSICION_PROHIBIDA:
                ini -= 1        # un byte de mas, y el "EOF" deja de ser posicion
                trozo += 1
            salida += ini.to_bytes(3, "big") + trozo.to_bytes(2, "big")
            salida += b[ini:ini + trozo]
            total += trozo
            ini += trozo
    salida += FINAL
    return bytes(salida), total


def aplica(original, parche):
    datos = bytearray(open(original, "rb").read())
    p = open(parche, "rb").read()
    if p[:5] != CABECERA:
        raise SystemExit("%s no es un IPS" % parche)
    i = 5
    while p[i:i + 3] != FINAL:
        pos = int.from_bytes(p[i:i + 3], "big")
        largo = int.from_bytes(p[i + 3:i + 5], "big")
        i += 5
        if largo:
            datos[pos:pos + largo] = p[i:i + largo]
            i += largo
        else:                                   # variante RLE
            veces = int.from_bytes(p[i:i + 2], "big")
            datos[pos:pos + veces] = bytes([p[i + 2]]) * veces
            i += 3
    return bytes(datos)


def main(argv):
    if len(argv) > 1 and argv[1] == "--aplica":
        if len(argv) != 5:
            raise SystemExit(__doc__)
        open(argv[4], "wb").write(aplica(argv[2], argv[3]))
        print("%s = %s + %s" % (argv[4], argv[2], argv[3]))
        return 0
    if len(argv) != 4:
        raise SystemExit(__doc__)
    ips, total = crea(argv[1], argv[2])
    open(argv[3], "wb").write(ips)
    registros = 0
    i = 5
    while ips[i:i + 3] != FINAL:
        largo = int.from_bytes(ips[i + 3:i + 5], "big")
        registros += 1
        i += 5 + largo
    print("%s: %d bytes, %d registros, %d bytes de datos"
          % (argv[3], len(ips), registros, total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
