#!/usr/bin/env python3
"""Escribe el cuerpo de un bloque de la cinta CON EL PARCHE YA APLICADO.

Para que: las laminas de la web se dibujan con tools/render_graficos.py, que
lee un cuerpo tal cual sale de la cinta. Para ensenar los tiles REPINTADOS hace
falta el mismo bloque pero con la tabla de tools/parchea.py encima, y eso es lo
que deja aqui.

No monta ninguna cinta ni toca los ficheros de work/: solo aplica la tabla en
memoria y escribe la copia que se le pide.

    python3 tools/cuerpo_parcheado.py <bloque> <salida.raw> [work]

<bloque> es uno de los nombres de BLOQUES_SPECTRUM: pantalla, bajo, medio, alto.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parchea                                                  # noqa: E402


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    bloque, salida = argv[1], argv[2]
    work = argv[3] if len(argv) > 3 else os.path.join(parchea.RAIZ, "work")
    if bloque not in parchea.BLOQUES_SPECTRUM:
        raise SystemExit("bloque desconocido: %s (hay %s)"
                         % (bloque, ", ".join(parchea.BLOQUES_SPECTRUM)))

    cuerpos = {}
    for n in parchea.BLOQUES_SPECTRUM:
        ruta = os.path.join(work, n + ".raw")
        if not os.path.exists(ruta):
            raise SystemExit("no hay %s; ejecuta antes `make extract`" % ruta)
        cuerpos[n] = bytearray(open(ruta, "rb").read())

    # aplica() comprueba entrada por entrada que los bytes originales son los
    # que la tabla espera, asi que si la cinta no es la buena se para aqui.
    rangos = parchea.aplica(cuerpos)
    with open(salida, "wb") as f:
        f.write(bytes(cuerpos[bloque]))
    print("%s: %d bytes, %d entradas del bloque %s aplicadas"
          % (salida, len(cuerpos[bloque]), len(rangos.get(bloque, [])), bloque))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
