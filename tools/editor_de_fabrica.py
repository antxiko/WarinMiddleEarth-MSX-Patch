#!/usr/bin/env python3
"""Lleva los sprites de src/cartucho/*.png a la tabla DE_FABRICA del editor.

tools/editor_sprites.html trae los cuatro sprites DENTRO, para que al abrirlo
se vean sin buscar ningun fichero y para que el boton "volver al original"
tenga a que volver. Eso es una copia, y una copia se queda vieja: si alguien
repinta los PNG y no toca el HTML, el editor abre el dibujo de antes y
guardarlo desharia el cambio en silencio.

Asi que la copia NO se edita a mano, se regenera:

    python3 tools/editor_de_fabrica.py

Que este al dia lo exige tests/test_editor_sprites.py, que corre el codigo del
editor y compara pixel a pixel con los PNG.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))

import cursor                                               # noqa: E402
import guante                                               # noqa: E402

HTML = os.path.join(RAIZ, "tools", "editor_sprites.html")


def lineas():
    """Las lineas de la tabla, en el orden en que las lee el editor."""
    fuera = []
    patrones, colores, _av = cursor.planos_del_png(os.path.join(RAIZ, "src/cartucho/cursor.png"))
    for n, (_modo, nombre) in enumerate(cursor.MODOS):
        trozos = []
        for p in range(2):
            i = (n * 2 + p) * cursor.BYTES_POR_PLANO
            trozos.append((colores[n * 2 + p], patrones[i:i + cursor.BYTES_POR_PLANO].hex()))
        fuera.append((nombre, trozos))
    patrones, colores, _av = guante.planos_del_png(os.path.join(RAIZ, "src/cartucho/guante.png"))
    fuera.append(("guante", [(colores[p], patrones[p * 32:(p + 1) * 32].hex())
                             for p in range(2)]))
    return fuera


def tabla():
    out = ["const DE_FABRICA = {"]
    for nombre, trozos in lineas():
        (ca, pa), (cb, pb) = trozos
        out.append('  %-8s [%2d,"%s",' % (nombre + ":", ca, pa))
        out.append('           %2d,"%s"],' % (cb, pb))
    out.append("};")
    return "\n".join(out)


def main():
    with open(HTML, encoding="utf-8") as f:
        html = f.read()
    nueva = tabla()
    html2, n = re.subn(r"const DE_FABRICA = \{.*?\n\};", nueva.replace("\\", "\\\\"),
                       html, flags=re.S)
    if n != 1:
        raise SystemExit("no encuentro la tabla DE_FABRICA en %s" % HTML)
    if html2 == html:
        print("el editor ya tenia los sprites de src/cartucho/")
        return 0
    with open(HTML, "w", encoding="utf-8") as f:
        f.write(html2)
    print("%s: tabla DE_FABRICA al dia con src/cartucho/cursor.png y guante.png" % HTML)
    for nombre, trozos in lineas():
        print("  %-8s %s + %s" % (nombre, *(("color %d" % c) for c, _ in trozos)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
