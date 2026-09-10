#!/usr/bin/env python3
"""Dibuja los graficos de War in Middle Earth desde los bytes de la cinta.

Ninguna de estas imagenes es una captura: no hay emulador por medio. Se leen
los bytes del bloque alto (org 0x9E00) en los rangos que el listado tiene
acotados y se revelan como los revela el juego. Si un rango estuviera mal
etiquetado, saldria ruido; que salga un dibujo es la comprobacion.

LAS TRES PIEZAS, con la direccion que las acota en src/alto.notes:

  0x9E00-0xA280  LOS TILES DEL MAPA. Hasta 128 tiles de NUEVE bytes: ocho
                 lineas de bitmap y, detras, un atributo del ZX Spectrum. Los
                 lee 0x75C7-0x75EB cuando el codigo de la rejilla lleva el
                 bit 7. Que sean nueve y no ocho es lo que delata la
                 conversion: el atributo del Spectrum viaja pegado al dibujo.

  0xA2E8-0xB8E8  LOS SPRITES DE BATALLA. 176 sprites de 16x8 con mascara, 32
                 bytes cada uno: ocho filas de dos bytes de dibujo y ocho de
                 dos bytes de mascara. La direccion de cada uno sale de
                 0xA2E8 + (tipo-4)*32, que es lo que calcula 0x87B4-0x87C4.

  0xC800-0xCC00  LA FUENTE. 128 caracteres de ocho bytes: en los codigos bajos
                 estan las texturas del terreno, y despues los marcos, las
                 flechas, los digitos y las letras. La leen 0x7620-0x763C y el
                 volcado a VRAM de 0x043F.

EL ATRIBUTO DEL SPECTRUM, que es lo que da el color de los tiles: bits 0-2 la
tinta, 3-5 el papel, 6 el brillo y 7 el parpadeo. Aqui se usa la paleta del ZX
porque es la que describe el byte; lo que el MSX acabe pintando lo decide la
conversion de 0x049F, que es otra cosa y esta en el listado del bloque bajo.

Uso: render_graficos.py <work/alto.raw> <directorio_salida>
"""
import os
import struct
import sys
import zlib

ORG = 0x9E00

TILES = (0x9E00, 0xA280, 9)          # 128 tiles de 8 lineas + 1 atributo
SPRITES = (0xA2E8, 0xB8E8, 32)       # 176 sprites de 16x8 con mascara
FUENTE = (0xC800, 0xCC00, 8)         # 128 caracteres de 8 bytes

# EL ATRIBUTO ES DEL SPECTRUM, PERO EL COLOR QUE SE VE ES DEL MSX. Esta
# conversion no manda el atributo a la pantalla: ATRIBUTO_A_COLOR (0x049F) lo
# traduce antes a un byte de color de SCREEN 2 con dos tablas de ocho, la de
# 0x04CE para el atributo sin brillo y la de 0x04D6 para el que lo lleva. Asi
# que aqui se dibuja con los colores del MSX, que son los que ve quien juega, y
# no con los del Spectrum. Las tablas y la paleta salen de tools/lienzos.py,
# para que las laminas de la web y los lienzos editables dibujen igual.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lienzos import ZX_EN_MSX as ZX          # noqa: E402
FONDO = (24, 24, 28)                 # el hueco entre dibujos, para verlos


def png(path, w, h, filas):
    """Un PNG de color verdadero, sin dependencias."""
    raw = b"".join(b"\x00" + bytes(v for p in f for v in p) for f in filas)

    def chunk(t, d):
        return (struct.pack(">I", len(d)) + t + d
                + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


def hoja(dibujos, ancho_px, alto_px, cols, escala, sep=2):
    """Pone los dibujos en una rejilla. dibujos[n][y][x] = (r,g,b) o None."""
    filas = (len(dibujos) + cols - 1) // cols
    w = cols * (ancho_px * escala + sep) + sep
    h = filas * (alto_px * escala + sep) + sep
    lienzo = [[FONDO] * w for _ in range(h)]
    for n, d in enumerate(dibujos):
        ox = sep + (n % cols) * (ancho_px * escala + sep)
        oy = sep + (n // cols) * (alto_px * escala + sep)
        for y in range(alto_px):
            for x in range(ancho_px):
                rgb = d[y][x]
                if rgb is None:
                    continue
                for dy in range(escala):
                    for dx in range(escala):
                        lienzo[oy + y * escala + dy][ox + x * escala + dx] = rgb
    return w, h, lienzo


def tiles_del_mapa(d):
    """Ocho lineas de bitmap y un atributo del Spectrum detras."""
    ini, fin, paso = TILES
    fuera = []
    for a in range(ini - ORG, fin - ORG, paso):
        attr = d[a + 8]
        brillo = 8 if attr & 0x40 else 0
        tinta = ZX[(attr & 0x07) + brillo]
        papel = ZX[((attr >> 3) & 0x07) + brillo]
        dib = []
        for y in range(8):
            b = d[a + y]
            dib.append([tinta if b & (0x80 >> x) else papel for x in range(8)])
        fuera.append(dib)
    return fuera


def sprites_de_batalla(d):
    """Dieciseis parejas (mascara, dibujo), en el orden en que las gasta el juego.

    NO es "los 16 bytes del dibujo y luego los 16 de la mascara". El orden sale
    de leer la rutina que los pinta, 0x887B, que por cada byte de pantalla hace:

        ld a,(de) / and (hl) / inc hl / or (hl) / inc hl / ld (de),a

    o sea que los bytes van en PAREJAS -primero la mascara, que se cruza con lo
    que ya hay, y detras el dibujo, que se suma-, y HL avanza de dos en dos.

    Y las parejas no van en zigzag por casualidad: la rutina escribe la
    izquierda, `inc e` a la derecha, `inc d` para bajar una linea, y `dec e`
    para volver a la izquierda. Asi se ahorra recolocar DE. De ahi este orden,
    que es el que hay que respetar para no sacar ruido:

        fila 0: izquierda, derecha      fila 1: derecha, izquierda
        fila 2: izquierda, derecha      fila 3: derecha, izquierda   ...

    Cuatro llamadas a 0x887B -tres desde 0x8801 y la cuarta escrita a mano en
    0x880A- hacen las ocho filas: 16 bytes de pantalla, 32 con las mascaras.

    La mascara tiene el sentido de siempre: donde vale 1 se conserva el fondo,
    asi que ahi el sprite es transparente y aqui se deja ver la hoja.
    """
    ini, fin, paso = SPRITES
    # el recorrido de 0x887B, dos filas por vuelta
    orden = []
    for fila in range(0, 8, 2):
        orden += [(fila, 0), (fila, 1), (fila + 1, 1), (fila + 1, 0)]
    fuera = []
    for a in range(ini - ORG, fin - ORG, paso):
        dib = [[None] * 16 for _ in range(8)]
        for n, (fila, col) in enumerate(orden):
            m, b = d[a + n * 2], d[a + n * 2 + 1]
            for bit in range(8):
                if m & (0x80 >> bit):
                    continue                      # transparente: manda el fondo
                dib[fila][col * 8 + bit] = ((255, 255, 255)
                                            if b & (0x80 >> bit) else (0, 0, 0))
        fuera.append(dib)
    return fuera


def fuente(d):
    """Ciento veintiocho caracteres de ocho bytes, en blanco sobre negro."""
    ini, fin, paso = FUENTE
    fuera = []
    for a in range(ini - ORG, fin - ORG, paso):
        dib = []
        for y in range(8):
            b = d[a + y]
            dib.append([(255, 255, 255) if b & (0x80 >> x) else (0, 0, 0)
                        for x in range(8)])
        fuera.append(dib)
    return fuera


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    ruta, salida = argv[1], argv[2]
    if not os.path.exists(ruta):
        print("  falta %s: hazlo antes con `make extract`" % ruta)
        return 2
    d = open(ruta, "rb").read()
    if len(d) < FUENTE[1] - ORG:
        print("  el bloque son %d bytes y la fuente acaba en %d: no cabe"
              % (len(d), FUENTE[1] - ORG))
        return 1
    os.makedirs(salida, exist_ok=True)

    sprites = sprites_de_batalla(d)
    trabajos = [
        ("tiles-del-mapa.png", tiles_del_mapa(d), 8, 8, 16, 4, TILES),
        ("sprites-de-batalla.png", sprites, 16, 8, 11, 3, SPRITES),
        ("fuente.png", fuente(d), 8, 8, 16, 4, FUENTE),
    ]
    for nombre, dibujos, aw, ah, cols, esc, rango in trabajos:
        w, h, lienzo = hoja(dibujos, aw, ah, cols, esc)
        fn = os.path.join(salida, nombre)
        png(fn, w, h, lienzo)
        print("  %-24s 0x%04X-0x%04X  %3d dibujos de %dx%d  %s"
              % (nombre, rango[0], rango[1], len(dibujos), aw, ah, fn))

    # Y la misma hoja de dos en dos. OJO CON LO QUE ESTO ES Y LO QUE NO:
    # MEDIDO es que cada sprite son 32 bytes y 16x8. Los dos caminos que los
    # dibujan lo dicen igual: 0x87E9 calcula 0xA2E8 + (tipo-4)*32 y pinta ocho
    # filas, y 0x87B4 hace la misma cuenta con un `inc hl` delante -o sea,
    # empezando por el dibujo en vez de por la mascara- y pinta otras ocho.
    # OBSERVADO, y solo observado, es que las entradas consecutivas encajan de
    # dos en dos en figuras de 16x16: sueltas se ven medias figuras y apiladas
    # se ven guerreros y jinetes enteros. No se ha encontrado la rutina que lo
    # haga, asi que va dicho como lo que es: una lectura de la imagen.
    grupos = [sprites[i] + sprites[i + 1] for i in range(0, len(sprites) - 1, 2)]
    w, h, lienzo = hoja(grupos, 16, 16, 11, 3)
    fn = os.path.join(salida, "sprites-de-dos-en-dos.png")
    png(fn, w, h, lienzo)
    print("  %-24s los mismos bytes, apilados de dos en dos: %d figuras de 16x16  %s"
          % ("sprites-de-dos-en-dos.png", len(grupos), fn))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
