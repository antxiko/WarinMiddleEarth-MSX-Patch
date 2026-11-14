#!/usr/bin/env python3
"""Coteja lo que deja tools/omsx_ruben.tcl contra los ficheros de Ruben.

    coteja_ruben.py <dir de la sonda> <asses> [<dir de los png>]

- La VRAM de la portada y de las dos finales tiene que llevar, byte a byte, los
  patrones (0x0000) y los colores (0x2000) de PORTADA, VICTORIA y DERROTA.SC2,
  y la tabla de nombres 0..255 tres veces; en las finales, ademas, el primer
  sprite con Y=208 (ninguno a la vista).
- El log tiene que decir BIEN en las cuatro fases (menu, partida, batalla y
  despues de la batalla), CERO intrusos en la RAM de las canciones y en el area
  del WYZ, y las dos finales paradas con el gancho en 0x0428 y el PSG mudo.

Con un tercer argumento pinta las tres pantallas TAL COMO ESTAN EN LA VRAM, en
PNG, para mirarlas (paleta del TMS9918).
"""
import os
import re
import struct
import sys
import zlib

PALETA = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120), (84, 85, 237), (125, 118, 252),
          (212, 82, 77), (66, 235, 245), (252, 85, 84), (255, 121, 120), (212, 193, 84),
          (230, 206, 128), (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]


def png(ruta, ancho, alto, pixeles):
    filas = b"".join(b"\x00" + bytes(c for p in pixeles[y * ancho:(y + 1) * ancho] for c in PALETA[p])
                     for y in range(alto))

    def trozo(tipo, datos):
        return (struct.pack(">I", len(datos)) + tipo + datos
                + struct.pack(">I", zlib.crc32(tipo + datos) & 0xFFFFFFFF))
    with open(ruta, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0))
                + trozo(b"IDAT", zlib.compress(filas, 9)) + trozo(b"IEND", b""))


def pinta(vram, ruta):
    pix = [0] * (256 * 192)
    for celda in range(768):
        tercio, n = celda // 256, vram[0x1800 + celda]
        cx, cy = celda % 32, celda // 32
        for linea in range(8):
            o = tercio * 2048 + n * 8 + linea
            pat, col = vram[o], vram[0x2000 + o]
            for bit in range(8):
                pix[(cy * 8 + linea) * 256 + cx * 8 + bit] = (col >> 4) if pat & (0x80 >> bit) else (col & 15)
    png(ruta, 256, 192, pix)


def main(argv):
    sonda, asses = argv[1], argv[2]
    dir_png = argv[3] if len(argv) > 3 else None
    fallos = 0
    for nombre, fichero, final in (("portada", "PORTADA", False), ("victoria", "VICTORIA", True),
                                   ("derrota", "DERROTA", True)):
        with open(os.path.join(sonda, "vram_%s.bin" % nombre), "rb") as f:
            vram = f.read()
        with open(os.path.join(asses, fichero + ".SC2"), "rb") as f:
            v = f.read()[7:]
        malos = [(que, sum(1 for i in range(0x1800) if vram[base + i] != v[base + i]))
                 for que, base in (("patrones", 0x0000), ("colores", 0x2000))]
        nombres_bien = vram[0x1800:0x1B00] == bytes(range(256)) * 3
        texto = ", ".join("%s %d distintos" % m for m in malos) + ", nombres %s" % ("0..255" if nombres_bien else "MAL")
        mal = any(n for _q, n in malos) or not nombres_bien
        if final:
            texto += ", primer sprite Y=%d" % vram[0x1B00]
            mal = mal or vram[0x1B00] != 0xD0
        print("%-9s %s -> %s" % (nombre, texto, "MAL" if mal else "BIEN"))
        fallos += mal
        if dir_png:
            os.makedirs(dir_png, exist_ok=True)
            pinta(vram, os.path.join(dir_png, "%s.png" % nombre))

    with open(os.path.join(sonda, "ruben.log"), encoding="utf-8") as f:
        log = f.read()
    fases = re.findall(r"FASE (.+?): .* -> (BIEN|MAL)", log)
    for que, v in fases:
        print("fase %-22s %s" % (que, v))
    if len(fases) != 5 or any(v != "BIEN" for _q, v in fases):
        print("las cinco fases no estan BIEN (%d vistas)" % len(fases))
        fallos += 1
    m = re.search(r"MUDA con la M: .* -> (BIEN|MAL)", log)
    print("la M calla la musica: %s" % (m.group(1) if m else "NO SE VIO"))
    fallos += not m or m.group(1) != "BIEN"
    for que in ("canciones", "el area del WYZ"):
        m = re.search(r"intrusos en (?:la RAM de las )?%s: (\d+)" % que, log)
        n = int(m.group(1)) if m else -1
        print("intrusos en %s: %d" % (que, n))
        fallos += n != 0
    paradas = re.findall(r"parada: gancho (0x[0-9A-F]+), volumenes (\d+) (\d+) (\d+)", log)
    for g, *vol in paradas:
        bien = g == "0x0428" and vol == ["0", "0", "0"]
        print("final parada: gancho %s, volumenes %s -> %s" % (g, " ".join(vol), "BIEN" if bien else "MAL"))
        fallos += not bien
    if len(paradas) != 2:
        print("no se pararon las dos finales (%d)" % len(paradas))
        fallos += 1
    print("TODO BIEN" if not fallos else "%d FALLOS" % fallos)
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
