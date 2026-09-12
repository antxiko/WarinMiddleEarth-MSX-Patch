#!/usr/bin/env python3
"""ZX0 para el cartucho: comprimir con el compresor de verdad y comprobarlo
descomprimiendo con el descompresor de verdad.

POR QUE ZX0 Y NO EL RLE DE MARCA

El RLE de marca (tools/comprime.py) solo gasta bytes en las rachas, que en una
pantalla del ZX son pocas. ZX0 es LZ: encuentra repeticiones a cualquier
distancia. Medido sobre los cuatro bloques de este cartucho:

    intro patrones   6.144 -> 5.236 (RLE) -> 3.663 (ZX0)
    intro colores    6.144 -> 2.511       -> 1.030
    victoria         6.912 -> 5.519       -> 3.847
    derrota          6.912 -> 5.763       -> 4.060
                                            ------
    6.429 bytes de ROM, a cambio de 68 de descompresor.

EL COMPRESOR NO ESTA AQUI

Es el `zx0.exe` de Einar Saukas, que viaja en MSXgl. Su codigo esta bajo BSD-3
y no se copia a este repositorio: se le pasa la ruta, como al reproductor PT3.
El DESCOMPRESOR si esta (src/cartucho/dzx0.asm): su licencia lo permite
explicitamente a cambio de decir en la documentacion que se usa ZX0, y esta
dicho en el README, en AVISO-LEGAL.md y en el propio fichero.

COMO SE COMPRUEBA QUE LA IDA Y VUELTA NO PIERDE NADA

`descomprime()` no reimplementa el formato: **ejecuta el dzx0.asm que va en la
ROM** dentro del interprete de Z80 de tools/corre_finales.py. Asi lo que se
comprueba es el codigo que va a correr en el MSX, no una traduccion de el, y
la pareja es de verdad independiente: el compresor es el C de Einar Saukas y
el descompresor su ensamblador, pasando por dos implementaciones distintas.

Uso:  zx0.py <fichero> [<fichero>...]     mide y comprueba la ida y vuelta
"""
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
SRC = os.path.join(RAIZ, "src", "cartucho")

sys.path.insert(0, AQUI)

# El compresor. Se puede cambiar con la variable de entorno ZX0EXE o pasandolo
# como argumento; por defecto, donde suele estar en MSXgl.
ZX0EXE = os.environ.get(
    "ZX0EXE",
    "C:/Users/Antxiko/Documents/MSXonLIVE/MSXgl/tools/compress/ZX0/zx0.exe")

# Donde se monta todo para descomprimir en el interprete. Cuatro tramos que no
# se pisan, y en este orden porque a `descomprime()` se le suele dar el resto de
# la ROM entero -no se sabe donde acaba el bloque hasta descomprimirlo-, asi que
# el origen tiene que tener sitio de sobra por delante.
_DZX0_ORG = 0x0000      # el descompresor, 68 B
_ORIGEN = 0x0100        # el flujo comprimido, hasta donde empieza el destino
_DESTINO = 0xC000       # lo mayor que se descomprime son 6.912 B: hasta 0xDB00
_PILA = 0xFF00          # por encima del destino: ZX0 usa la pila a fondo


def falta_el_compresor(exe=None):
    """El mensaje que hay que dar cuando no esta, con la ruta que se probo."""
    exe = exe or ZX0EXE
    return ("\n  Falta el compresor ZX0: %s\n\n"
            "  No se distribuye aqui (ver AVISO-LEGAL.md): es de Einar Saukas y\n"
            "  viaja en MSXgl, de Guillaume 'Aoineko' Blanchard:\n"
            "      https://github.com/aoineko-fr/MSXgl\n"
            "      https://github.com/einar-saukas/ZX0\n"
            "  Pon la ruta con ZX0EXE=/ruta/a/zx0.exe o con: make ... ZX0EXE=...\n" % exe)


def comprime(datos, exe=None):
    """Los bytes comprimidos. El compresor trabaja con ficheros, asi que pasa
    por dos temporales; a cambio es EL compresor, con su parsing optimo, y no
    una aproximacion escrita aqui."""
    exe = exe or ZX0EXE
    if not os.path.exists(exe):
        raise FileNotFoundError(falta_el_compresor(exe))
    with tempfile.TemporaryDirectory() as tmp:
        entrada = os.path.join(tmp, "bloque.bin")
        salida = entrada + ".zx0"
        with open(entrada, "wb") as f:
            f.write(datos)
        # -f para que sobreescriba sin preguntar; el formato por defecto es el
        # que entiende dzx0_standard (ni -c clasico, ni -b hacia atras).
        r = subprocess.run([exe, "-f", entrada, salida], capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(salida):
            raise RuntimeError("zx0 ha fallado:\n%s%s" % (r.stdout, r.stderr))
        with open(salida, "rb") as f:
            return f.read()


_dzx0_cache = {}


def dzx0_binario(org=None):
    """El descompresor, ensamblado en `org`.

    Hace falta decir el org porque dzx0 NO es codigo reubicable: sus dos
    `call dzx0s_elias` llevan la direccion absoluta dentro, asi que los 68 bytes
    son distintos segun donde se ensamble. Por eso el stub y la rutina de las
    pantallas finales llevan cada uno su copia y no se parecen byte a byte."""
    org = _DZX0_ORG if org is None else org
    if org in _dzx0_cache:
        return _dzx0_cache[org]
    with tempfile.TemporaryDirectory() as tmp:
        fuente = os.path.join(tmp, "solo_dzx0.asm")
        with open(fuente, "w") as f:
            f.write("        org 0%04Xh\n        include \"dzx0.asm\"\n" % org)
        binario = os.path.join(tmp, "dzx0.bin")
        r = subprocess.run(["pasmo", "--bin", "-I", SRC, fuente, binario,
                            os.path.join(tmp, "dzx0.sym")],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("pasmo ha fallado con dzx0.asm:\n%s%s" % (r.stdout, r.stderr))
        with open(binario, "rb") as f:
            _dzx0_cache[org] = f.read()
    return _dzx0_cache[org]


def descomprime(comprimido):
    """Lo que saca el descompresor DE VERDAD, ejecutado paso a paso.

    Devuelve los bytes que deja en el destino, que son los que el registro DE
    dice que ha escrito: ZX0 no lleva el tamano original dentro, lo marca
    terminando."""
    from corre_finales import Maquina, Z80, CENTINELA
    dzx0 = dzx0_binario()
    # Una maquina con las cuatro paginas en RAM: aqui no hay cartucho que valga.
    m = Maquina(b"", ranura_cart=1, ranura_ram=0)
    m.a8 = 0
    m.ram[_DZX0_ORG:_DZX0_ORG + len(dzx0)] = dzx0
    # Se recorta a lo que cabe: el que llama no sabe donde acaba el bloque -ZX0
    # no lleva el tamano dentro, lo marca terminando- y suele pasar de mas.
    comprimido = comprimido[:_DESTINO - _ORIGEN]
    m.ram[_ORIGEN:_ORIGEN + len(comprimido)] = comprimido
    z = Z80(m, _DZX0_ORG, _PILA)
    z.hl = _ORIGEN
    z.de = _DESTINO
    z.push(CENTINELA)
    z.corre()
    return bytes(m.ram[_DESTINO:z.de])


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    print("%-28s %8s %8s %8s %7s" % ("fichero", "crudo", "ZX0", "ahorro", "ida y vuelta"))
    fallos = 0
    for ruta in argv[1:]:
        with open(ruta, "rb") as f:
            datos = f.read()
        z = comprime(datos)
        vuelta = descomprime(z)
        bien = vuelta == datos
        fallos += not bien
        print("%-28s %8d %8d %+8d   %s"
              % (os.path.basename(ruta), len(datos), len(z), len(datos) - len(z),
                 "OK" if bien else "NO DEVUELVE LO MISMO (%d bytes)" % len(vuelta)))
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
