#!/usr/bin/env python3
"""RLE de marca: el compresor de las tres imagenes del cartucho.

POR QUE ESTE Y NO OTRO

Se midieron dos. El RLE clasico de parejas cuenta/valor -que es el que el
propio juego usa para su mapa- con los patrones de la pantalla de carga CRECE:
6.144 bytes se convierten en 7.870, porque casi ningun byte se repite y cada
uno pasa a ocupar dos. Comprimir no siempre encoge.

El de marca solo gasta bytes de mas en las rachas, y ademas la marca se ELIGE
midiendo: es el byte MENOS frecuente del bloque, para que haya que escaparlo lo
menos posible. En el peor caso concebible -un bloque donde la marca abunde-
crece; por eso `comprime()` comprueba el resultado y devuelve tambien el
tamano, y quien llama decide.

EL FORMATO

    <b>                 si b != MARCA: un byte literal
    MARCA <n> <v>       n veces el byte v   (1 <= n <= 255)
    MARCA 0             fin del bloque

Un byte igual a la MARCA que aparezca suelto se emite como `MARCA 1 MARCA`,
que ocupa tres. De ahi que la marca sea el byte menos frecuente.

El descompresor en Z80 esta en src/cartucho/cargador_ram.asm (DESCOMPRIME).

Uso:  comprime.py <fichero> [<fichero>...]      mide y ensena la tabla
"""
import sys


def elige_marca(datos):
    """El byte menos frecuente. Si alguno no aparece, ese: entonces no hay que
    escapar nada."""
    cuenta = [0] * 256
    for b in datos:
        cuenta[b] += 1
    return min(range(256), key=lambda b: cuenta[b])


def comprime(datos, marca=None):
    if marca is None:
        marca = elige_marca(datos)
    out = bytearray()
    i, n = 0, len(datos)
    while i < n:
        b = datos[i]
        j = i
        while j < n and datos[j] == b and j - i < 255:
            j += 1
        racha = j - i
        # Una racha compensa a partir de cuatro; y la marca suelta hay que
        # escaparla siempre, cueste lo que cueste.
        if racha >= 4 or b == marca:
            out += bytes([marca, racha, b])
            i = j
        else:
            out += bytes([b]) * racha
            i = j
    out += bytes([marca, 0])
    return bytes(out), marca


def descomprime(datos, marca):
    """El mismo algoritmo que el Z80, en Python: es lo que permite comprobar la
    ida y vuelta sin arrancar nada."""
    out = bytearray()
    i = 0
    while i < len(datos):
        b = datos[i]
        i += 1
        if b != marca:
            out.append(b)
            continue
        n = datos[i]
        i += 1
        if n == 0:
            break
        out += bytes([datos[i]]) * n
        i += 1
    return bytes(out)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    print("%-28s %8s %8s %8s %6s" % ("fichero", "crudo", "comprimido", "ahorro", "marca"))
    for ruta in argv[1:]:
        with open(ruta, "rb") as f:
            datos = f.read()
        salida, marca = comprime(datos)
        assert descomprime(salida, marca) == datos, "%s: la ida y vuelta NO devuelve lo mismo" % ruta
        print("%-28s %8d %8d %+8d   0x%02X"
              % (ruta.split("/")[-1], len(datos), len(salida), len(datos) - len(salida), marca))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
