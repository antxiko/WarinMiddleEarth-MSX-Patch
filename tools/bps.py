#!/usr/bin/env python3
"""El parche BPS: de TU cinta (war.tsx) a la ROM del cartucho (war_unificada.rom).

Por que BPS y no IPS: un IPS solo escribe bytes en su sitio, y la ROM no se
parece en nada a la cinta en su sitio (2.817 de 65.536 bytes coinciden), asi
que un IPS llevaria la ROM entera dentro, juego incluido. Un BPS puede COPIAR
trozos de la cinta a cualquier sitio: lo que ya esta en tu cinta no viaja en el
parche, solo lo nuevo. Lo aplican RomPatcher.js, Floating IPS (flips) y beat.

El formato (la especificacion de byuu, "beat patch format"):
    "BPS1"  varint(tam origen)  varint(tam destino)  varint(tam meta) meta
    acciones: varint(((largo-1) << 2) | accion)
        0 SourceRead  copia del origen en la MISMA posicion de salida
        1 TargetRead  los bytes vienen a continuacion
        2 SourceCopy  copia del origen desde un desplazamiento relativo
        3 TargetCopy  copia de lo ya escrito en la salida (sirve para rachas)
    crc32(origen) crc32(destino) crc32(todo lo anterior del parche), en LE.

    python tools/bps.py hace   <origen> <destino> <parche.bps>
    python tools/bps.py aplica <origen> <parche.bps> <salida>
"""
import sys
import zlib

MINIMO = 6          # una copia mas corta que esto sale mas cara que los literales


def _varint(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def _desplazamiento(d):
    return _varint((abs(d) << 1) | (1 if d < 0 else 0))


def _indice(datos, k=MINIMO):
    idx = {}
    for i in range(len(datos) - k + 1):
        idx.setdefault(datos[i:i + k], []).append(i)
    return idx


def hace(origen, destino):
    out = bytearray(b"BPS1")
    out += _varint(len(origen)) + _varint(len(destino)) + _varint(0)
    idx_o = _indice(origen)
    idx_d = {}                      # lo ya escrito, para TargetCopy
    rel_o = rel_d = 0
    literal = bytearray()

    def suelta_literal():
        nonlocal literal
        if literal:
            out.extend(_varint(((len(literal) - 1) << 2) | 1))
            out.extend(literal)
            literal = bytearray()

    def apunta(desde, hasta):
        for j in range(max(0, desde - MINIMO + 1), hasta - MINIMO + 1):
            idx_d.setdefault(destino[j:j + MINIMO], []).append(j)

    i = 0
    while i < len(destino):
        clave = destino[i:i + MINIMO]
        mejor, accion, donde = 0, None, 0
        # SourceRead: el mismo sitio del origen, sin desplazamiento que pagar
        n = 0
        while i + n < len(destino) and i + n < len(origen) and destino[i + n] == origen[i + n]:
            n += 1
        if n >= MINIMO:
            mejor, accion = n, 0
        for p in idx_o.get(clave, [])[-256:]:
            n = 0
            while i + n < len(destino) and p + n < len(origen) and destino[i + n] == origen[p + n]:
                n += 1
            if n > mejor + 2:
                mejor, accion, donde = n, 2, p
        for p in idx_d.get(clave, [])[-256:]:
            n = 0
            while i + n < len(destino) and destino[i + n] == destino[p + n]:
                n += 1                       # p < i: puede solaparse (rachas)
            if n > mejor + 2:
                mejor, accion, donde = n, 3, p
        if accion is None:
            literal.append(destino[i])
            apunta(i, i + 1)
            i += 1
            continue
        suelta_literal()
        out += _varint(((mejor - 1) << 2) | accion)
        if accion == 2:
            out += _desplazamiento(donde - rel_o)
            rel_o = donde + mejor
        elif accion == 3:
            out += _desplazamiento(donde - rel_d)
            rel_d = donde + mejor
        apunta(i, i + mejor)
        i += mejor
    suelta_literal()
    out += zlib.crc32(origen).to_bytes(4, "little")
    out += zlib.crc32(destino).to_bytes(4, "little")
    out += zlib.crc32(bytes(out)).to_bytes(4, "little")
    return bytes(out)


def aplica(origen, parche):
    """Escrito aparte del codificador, segun la especificacion: es la prueba."""
    if parche[:4] != b"BPS1":
        raise ValueError("no es un BPS")
    if zlib.crc32(parche[:-4]) != int.from_bytes(parche[-4:], "little"):
        raise ValueError("el parche esta danado")
    pos = 4

    def lee():
        nonlocal pos
        n, sh = 0, 1
        while True:
            x = parche[pos]
            pos += 1
            n += (x & 0x7F) * sh
            if x & 0x80:
                return n
            sh <<= 7
            n += sh

    t_o, t_d, t_m = lee(), lee(), lee()
    pos += t_m
    if len(origen) != t_o or zlib.crc32(origen) != int.from_bytes(parche[-12:-8], "little"):
        raise ValueError("este no es el fichero de origen del parche")
    out = bytearray()
    rel_o = rel_d = 0
    while pos < len(parche) - 12:
        dato = lee()
        accion, largo = dato & 3, (dato >> 2) + 1
        if accion == 0:
            out += origen[len(out):len(out) + largo]
        elif accion == 1:
            out += parche[pos:pos + largo]
            pos += largo
        else:
            d = lee()
            d = -(d >> 1) if d & 1 else d >> 1
            if accion == 2:
                rel_o += d
                out += origen[rel_o:rel_o + largo]
                rel_o += largo
            else:
                rel_d += d
                for _ in range(largo):
                    out.append(out[rel_d])
                    rel_d += 1
    if len(out) != t_d or zlib.crc32(out) != int.from_bytes(parche[-8:-4], "little"):
        raise ValueError("la salida no es la esperada")
    return bytes(out)


def main(argv):
    if len(argv) == 5 and argv[1] == "hace":
        o, d = open(argv[2], "rb").read(), open(argv[3], "rb").read()
        p = hace(o, d)
        assert aplica(o, p) == d
        open(argv[4], "wb").write(p)
        print(f"{argv[4]}: {len(p)} bytes; aplicado sobre {argv[2]} da {argv[3]} byte a byte")
    elif len(argv) == 5 and argv[1] == "aplica":
        o, p = open(argv[2], "rb").read(), open(argv[3], "rb").read()
        open(argv[4], "wb").write(aplica(o, p))
        print(f"{argv[4]}")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
