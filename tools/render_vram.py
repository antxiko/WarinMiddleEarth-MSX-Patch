#!/usr/bin/env python3
"""Dibuja un volcado de VRAM tal como lo ensena el VDP en SCREEN 2.

    python3 tools/render_vram.py <vram.bin> <salida.png> [escala] [--regs "02 E0 06 FF 03 36 07 01"]

No adivina la disposicion: la saca de los registros del VDP, que son los que
mandan. En modo grafico 2, R3 y R4 NO son una direccion sino base y mascara
(ver la nota de la serie sobre esto), asi que:

    nombres   = R2 * 0x400
    patrones  = (R4 & 0x04) * 0x800      con mascara (R4 & 0x03) sobre el tercio
    colores   = (R3 & 0x80) * 0x40       con mascara (R3 & 0x7F)
    sprites   = R5 * 0x80 (atributos), R6 * 0x800 (patrones)

Los valores por defecto son los que este juego deja puestos (02 E0 06 FF 03 36
07 01). Con --regs se le pasan otros, en hexadecimal y separados por espacios,
copiados tal cual de la linea "VDP:" que escribe tools/omsx_mira_mapa.tcl.
"""
import struct
import sys
import zlib

# La paleta del TMS9918, en RGB de 8 bits.
PALETA = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def png(w, h, pix, fn):
    raw = b"".join(b"\x00" + bytes(fila) for fila in pix)
    def chunk(t, d):
        return (struct.pack(">I", len(d)) + t + d
                + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff))
    cab = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    with open(fn, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", cab)
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def pinta(vram, regs, escala=2, con_sprites=True):
    r2, r3, r4, r5, r6, r7 = regs[2], regs[3], regs[4], regs[5], regs[6], regs[7]
    nombres = r2 * 0x400
    pat_base, pat_masc = (r4 & 0x04) * 0x800, ((r4 & 0x03) << 8) | 0xFF
    col_base, col_masc = (r3 & 0x80) * 0x40, ((r3 & 0x7F) << 3) | 0x07
    spr_atr, spr_pat = r5 * 0x80, r6 * 0x800
    fondo = r7 & 0x0F

    lienzo = [[fondo] * 256 for _ in range(192)]
    for fila in range(24):
        tercio = (fila // 8) << 8
        for col in range(32):
            car = vram[nombres + fila * 32 + col]
            idx = tercio | car
            for y in range(8):
                b = vram[pat_base + ((idx & pat_masc) << 3) + y]
                c = vram[col_base + ((idx & col_masc) << 3) + y]
                tinta, papel = c >> 4, c & 0x0F
                for x in range(8):
                    v = tinta if (b << x) & 0x80 else papel
                    lienzo[fila * 8 + y][col * 8 + x] = v if v else fondo

    if con_sprites:
        grandes = bool(regs[1] & 0x02)
        lado = 16 if grandes else 8
        for s in range(32):
            a = spr_atr + s * 4
            sy = vram[a]
            if sy == 208:          # 0xD0: aqui se acaban los sprites
                break
            sy = (sy + 1) & 0xFF
            if sy > 192:
                sy -= 256
            sx, patron, ec = vram[a + 1], vram[a + 2], vram[a + 3]
            color = ec & 0x0F
            if ec & 0x80:
                sx -= 32
            if not color:
                continue
            base = spr_pat + ((patron & (0xFC if grandes else 0xFF)) << 3)
            # Un sprite de 16x16 son 32 bytes en CUATRO cuadrantes de 8, y el
            # orden del TMS9918 es por COLUMNAS: arriba a la izquierda (0-7),
            # abajo a la izquierda (8-15), arriba a la derecha (16-23) y abajo
            # a la derecha (24-31). Estaba al reves -filas primero- y nadie lo
            # vio porque este juego no ensenaba ningun sprite hasta el cursor.
            for y in range(lado):
                for x in range(lado):
                    o = base + (y & 7) + (8 if y >= 8 else 0) + (16 if x >= 8 else 0)
                    if not (vram[o] << (x & 7)) & 0x80:
                        continue
                    py, px = sy + y, sx + x
                    if 0 <= py < 192 and 0 <= px < 256:
                        lienzo[py][px] = color

    filas = []
    for y in range(192):
        fila = []
        for x in range(256):
            fila.extend(PALETA[lienzo[y][x]] * escala)
        filas.extend([fila] * escala)
    return 256 * escala, 192 * escala, filas


def main():
    args = sys.argv[1:]
    regs = [0x02, 0xE0, 0x06, 0xFF, 0x03, 0x36, 0x07, 0x01]
    if "--regs" in args:
        i = args.index("--regs")
        regs = [int(v, 16) for v in args[i + 1].split()][:8]
        del args[i:i + 2]
    vram = open(args[0], "rb").read()
    salida = args[1]
    escala = int(args[2]) if len(args) > 2 else 2
    w, h, filas = pinta(vram, regs, escala)
    png(w, h, filas, salida)
    print(f"{salida}: {w}x{h}, nombres 0x{regs[2] * 0x400:04X}, "
          f"patrones 0x{(regs[4] & 4) * 0x800:04X}, colores 0x{(regs[3] & 0x80) * 0x40:04X}")


if __name__ == "__main__":
    main()
