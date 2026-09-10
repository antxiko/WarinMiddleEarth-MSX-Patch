#!/usr/bin/env python3
"""Monta el cartucho de War in Middle Earth a partir de los cuerpos de la cinta.

Entrada: el directorio `work` con bajo.raw, medio.raw, alto.raw y pantalla.raw
(los saca tools/cuerpos.py de la cinta, como para el resto del parche).
Salida: una MegaROM ASCII16 de 64 KB y un plan.json con la disposicion, para
que los tests y el cotejo no tengan que suponer nada.

COMO ESTA HECHA LA ROM

    banco 0, 0x0000   cabecera AB + arranque (cargador_rom.asm), y detras el
                      stub que corre en RAM (cargador_ram.asm), con el plan
    0x0800..          los datos, seguidos: los patrones y los colores de la
                      pantalla de carga, el bloque bajo, el medio y el alto

El cargador de la cinta deja los bloques en 0x0190 (bajo), 0x3F4F (medio) y
0x88B8 (alto) y salta a 0x0190, que los recoloca. El cartucho deja EXACTAMENTE
lo mismo y salta al mismo sitio: asi la RAM se puede cotejar byte a byte con
los volcados de la cinta en dos instantes, 0x0190 y 0x5E00.

EL PLAN

Una lista de operaciones de 8 bytes (op, b, src, dst, len) que interpreta el
stub. Se genera aqui, de la disposicion real de la ROM, y va dentro del propio
stub (work/plan.inc). Lo que hace, en orden:

  1. VDP como lo deja `COLOR 1,1,1:SCREEN 2`, medido en la cinta: registros
     0-7, tabla de nombres identidad, 32 sprites en Y=209, resto a cero.
  2. La pantalla de carga a la VRAM, pantalla encendida, y una espera.
  3. Pantalla apagada. El tramo del bloque medio que cae en la pagina 1
     (0x4000-0x783F) va a la VRAM, que hace de bufer.
  4. Las copias que no tocan la pagina 1: bajo a 0x0190, la cola del medio a
     0x3F4F, el buzon de POKEs de 0x012C a cero, alto a 0x88B8.
  5. Pagina 1 a RAM; el tramo vuelve de la VRAM a 0x4000. Cartucho otra vez
     en la pagina 1 para repintar la imagen de carga y las tablas del
     SCREEN 2, que el bufer piso (llega hasta 0x383F); pagina 1 a RAM.
  6. PSG como lo deja la cinta, pantalla encendida, SP=0xFDE8 y jp 0x0190.

Uso: haz_rom.py <work> <salida.rom> [--espera N] [--sin-pantalla]

`work` es el directorio con los cuerpos: el `work/` del parche para la cinta
original, o `work/cuerpos_parche/` para la parcheada (los saca el Makefile de
war_parche.tsx con las mismas dos herramientas). El plan, los binarios del
cargador y plan.json se escriben en ese mismo directorio.
"""
import json
import os
import struct
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
SRC = os.path.join(RAIZ, "src", "cartucho")

TAM_ROM = 0x10000           # 64 KB: cuatro bancos ASCII16
TAM_BANCO = 0x4000
INICIO_DATOS = 0x0800       # lo que se reserva para arranque + stub + plan
STUB = 0xD800

# Lo que deja el cargador de la cinta (leido de src/war_loader.asm del
# desensamblado y comprobado contra work/omsx_orig/full_crudo.bin):
CARGA_BAJO = 0x0190
CARGA_MEDIO = 0x3F4F
CARGA_ALTO = 0x88B8
BUZON_POKES = (0x012C, 100)  # 0x012C-0x018F: 0x0190 solo lo lee si empieza por tres 0xC9
SALTO = 0x0190
PILA = 0xFDE8               # la pila del cargador de la cinta (0xD6D9)

# Lo que deja `COLOR 1,1,1:SCREEN 2`, medido con openMSX al llegar a 0x5E00
# (tools/omsx_estado_cinta.tcl, work/estado_cinta/): R0-R7 y el PSG.
VDP_REGS = [0x02, 0xE0, 0x06, 0xFF, 0x03, 0x36, 0x07, 0x01]
# El registro 7 del PSG se leyo 0x3F; se escribe con el bit 7 puesto, que en el
# MSX es obligatorio (el puerto B del PSG es de salida). El juego, en su primera
# lectura del joystick, le hace `or 0xC0` de todas formas.
PSG_REGS = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xBF,
            0x00, 0x00, 0x00, 0x0B, 0x00, 0x00]

# Codigos de operacion, los mismos de src/direcciones.inc
OP = dict(FIN=0, ROM_RAM=1, ROM_VRAM=2, VRAM_RAM=3, LLENA_RAM=4, LLENA_VRAM=5,
          IDENT_VRAM=6, SPRITES_VRAM=7, PAG1_RAM=8, PAG1_CART=9, VDP_REG=10,
          PSG_REG=11, ESPERA=12, SALTA=13)


class Plan:
    def __init__(self):
        self.ops = []

    def op(self, nombre, b=0, src=0, dst=0, n=0, nota=""):
        assert 0 <= b < 256 and 0 <= src < 0x10000 and 0 <= dst < 0x10000 and 0 <= n < 0x10000
        self.ops.append((nombre, b, src, dst, n, nota))

    # copias que pueden cruzar bancos: se parten en trozos de un banco
    def copia_rom(self, nombre, origen_rom, dst, n, nota):
        while n:
            banco = origen_rom >> 14
            dentro = origen_rom & (TAM_BANCO - 1)
            trozo = min(n, TAM_BANCO - dentro)
            self.op(nombre, banco, 0x4000 + dentro, dst, trozo, nota)
            origen_rom += trozo
            dst += trozo
            n -= trozo

    def inc(self):
        lineas = []
        for nombre, b, src, dst, n, nota in self.ops:
            lineas.append("        defb OP_%s,%d\n        defw 0%04Xh,0%04Xh,0%04Xh   ; %s"
                          % (nombre, b, src, dst, n, nota))
        return "\n".join(lineas) + "\n"

    def json(self):
        return [dict(op=nombre, b=b, src=src, dst=dst, len=n, nota=nota)
                for nombre, b, src, dst, n, nota in self.ops]


def pasmo(fuente, salida, simbolos, equs=()):
    orden = ["pasmo", "--bin"]
    for k, v in equs:
        orden += ["--equ", "%s=%d" % (k, v)]
    orden += ["-I", SRC, "-I", os.path.dirname(salida), fuente, salida, simbolos]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write("pasmo ha fallado con %s:\n%s%s\n" % (fuente, r.stdout, r.stderr))
        sys.exit(1)
    with open(salida, "rb") as f:
        return f.read()


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    work, salida = argv[1], argv[2]
    espera = 150
    con_pantalla = True
    i = 3
    while i < len(argv):
        if argv[i] == "--espera":
            espera = int(argv[i + 1]); i += 2
        elif argv[i] == "--sin-pantalla":
            con_pantalla = False; i += 1
        else:
            print("argumento desconocido:", argv[i]); return 2
    assert 0 < espera < 256

    cuerpos = {}
    for nombre in ("bajo", "medio", "alto", "pantalla"):
        with open(os.path.join(work, nombre + ".raw"), "rb") as f:
            cuerpos[nombre] = f.read()
    bajo, medio, alto, pantalla = (cuerpos[k] for k in ("bajo", "medio", "alto", "pantalla"))
    assert len(bajo) == 15807 and len(medio) == 14577 and len(alto) == 18552 and len(pantalla) == 12388, \
        "los cuerpos no tienen el tamano de la cinta: %s" % {k: len(v) for k, v in cuerpos.items()}
    # La pantalla de carga: 100 bytes de codigo y luego 6144 de patrones y
    # 6144 de colores (src/war_pantalla.asm). El codigo no hace falta.
    patrones = pantalla[100:100 + 6144]
    colores = pantalla[100 + 6144:100 + 12288]

    # ------------------------------------------------------------ disposicion
    datos = []
    disposicion = {}
    pos = INICIO_DATOS

    def mete(nombre, cuerpo):
        nonlocal pos
        disposicion[nombre] = dict(rom=pos, bytes=len(cuerpo))
        datos.append(cuerpo)
        pos += len(cuerpo)

    mete("patrones", patrones)
    mete("colores", colores)
    mete("bajo", bajo)
    mete("medio", medio)
    mete("alto", alto)
    assert pos <= TAM_ROM, "no cabe: %d bytes" % pos

    # El bloque medio, cargado en 0x3F4F, cruza a la pagina 1 en 0x4000
    en_pagina0 = 0x4000 - CARGA_MEDIO                  # 177 bytes
    en_pagina1 = len(medio) - en_pagina0               # 14400 bytes
    assert en_pagina1 <= 0x4000, "el tramo de la pagina 1 no cabe en la VRAM"
    assert CARGA_ALTO + len(alto) - 1 < STUB, "el bloque alto pisaria el stub"

    # ------------------------------------------------------------------ plan
    p = Plan()
    p.op("VDP_REG", 1, 0xA0, nota="pantalla apagada mientras se prepara la VRAM")
    for r, v in enumerate(VDP_REGS):
        if r != 1:
            p.op("VDP_REG", r, v, nota="R%d como lo deja el SCREEN 2 del BASIC" % r)
    # Las tablas del SCREEN 2 se escriben DOS veces: ahora, para que la imagen
    # de carga se vea, y otra vez al final, porque el tramo que pasa por la VRAM
    # (0x0000-0x383F) las pisa.
    def tablas_del_screen_2(cuando):
        p.op("IDENT_VRAM", 0, 0, 0x1800, 768, "tabla de nombres: 0..255 tres veces" + cuando)
        p.op("SPRITES_VRAM", 0, 0, 0x1B00, 128, "32 atributos de sprite: Y=209, color 1" + cuando)
        p.op("LLENA_VRAM", 0, 0, 0x1B80, 0x2000 - 0x1B80, "resto de la tabla de sprites a cero" + cuando)
        p.op("LLENA_VRAM", 0, 0, 0x3800, 0x0800, "patrones de sprites a cero" + cuando)
    tablas_del_screen_2("")
    if con_pantalla:
        p.copia_rom("ROM_VRAM", disposicion["patrones"]["rom"], 0x0000, 6144, "pantalla de carga: patrones")
        p.copia_rom("ROM_VRAM", disposicion["colores"]["rom"], 0x2000, 6144, "pantalla de carga: colores")
        p.op("VDP_REG", 1, 0xE0, nota="pantalla encendida: se ve la imagen de carga")
        p.op("ESPERA", espera, nota="%d cuadros mirando la imagen" % espera)
        p.op("VDP_REG", 1, 0xA0, nota="pantalla apagada: la VRAM va a hacer de bufer")
    else:
        p.op("LLENA_VRAM", 0, 0, 0x0000, 0x1800, "sin pantalla de carga: patrones a cero")
        p.op("LLENA_VRAM", 0, 0, 0x2000, 0x1800, "sin pantalla de carga: colores a cero")
    # el tramo de la pagina 1, a la VRAM
    p.copia_rom("ROM_VRAM", disposicion["medio"]["rom"] + en_pagina0, 0x0000, en_pagina1,
                "bloque medio 0x4000-0x783F, de momento a la VRAM")
    # lo que no toca la pagina 1
    p.copia_rom("ROM_RAM", disposicion["bajo"]["rom"], CARGA_BAJO, len(bajo), "bloque bajo a 0x0190, donde corre")
    p.copia_rom("ROM_RAM", disposicion["medio"]["rom"], CARGA_MEDIO, en_pagina0, "bloque medio 0x3F4F-0x3FFF")
    p.op("LLENA_RAM", 0, 0, BUZON_POKES[0], BUZON_POKES[1], "buzon de POKEs de 0x012C a cero: sin POKEs")
    p.copia_rom("ROM_RAM", disposicion["alto"]["rom"], CARGA_ALTO, len(alto), "bloque alto a 0x88B8, como cae de la cinta")
    # y la pagina 1
    p.op("PAG1_RAM", nota="fuera el cartucho de la pagina 1")
    p.op("VRAM_RAM", 0, 0x0000, 0x4000, en_pagina1, "el tramo vuelve de la VRAM a 0x4000-0x783F")
    if con_pantalla:
        p.op("PAG1_CART", nota="el cartucho otra vez, para repintar la imagen")
        p.copia_rom("ROM_VRAM", disposicion["patrones"]["rom"], 0x0000, 6144, "imagen de carga otra vez: patrones")
        p.copia_rom("ROM_VRAM", disposicion["colores"]["rom"], 0x2000, 6144, "imagen de carga otra vez: colores")
        tablas_del_screen_2(" (otra vez: el bufer las piso)")
        p.op("PAG1_RAM", nota="y fuera del todo: el juego quiere las cuatro paginas en RAM")
    else:
        tablas_del_screen_2(" (otra vez: el bufer las piso)")
    for r, v in enumerate(PSG_REGS):
        p.op("PSG_REG", r, v, nota="PSG R%d como lo deja la cinta" % r)
    p.op("VDP_REG", 1, VDP_REGS[1], nota="pantalla encendida, como la deja la cinta")
    p.op("SALTA", 0, PILA, SALTO, nota="SP=0x%04X y a 0x%04X, como el cargador de la cinta" % (PILA, SALTO))
    p.op("FIN")

    os.makedirs(work, exist_ok=True)
    with open(os.path.join(work, "plan.inc"), "w") as f:
        f.write("; generado por tools/haz_rom.py: no editar\n")
        f.write(p.inc())

    # ------------------------------------------------------------ ensamblar
    stub = pasmo(os.path.join(SRC, "cargador_ram.asm"),
                 os.path.join(work, "cargador_ram.bin"), os.path.join(work, "cargador_ram.sym"))
    arranque = pasmo(os.path.join(SRC, "cargador_rom.asm"),
                     os.path.join(work, "cargador_rom.bin"), os.path.join(work, "cargador_rom.sym"),
                     equs=[("STUB_LEN", len(stub))])
    assert arranque[:2] == b"AB"
    cabeza = arranque + stub
    assert len(cabeza) <= INICIO_DATOS, "arranque + stub + plan ocupan %d, mas de %d" % (len(cabeza), INICIO_DATOS)

    rom = bytearray(b"\xFF" * TAM_ROM)
    rom[0:len(cabeza)] = cabeza
    pos = INICIO_DATOS
    for cuerpo in datos:
        rom[pos:pos + len(cuerpo)] = cuerpo
        pos += len(cuerpo)
    with open(salida, "wb") as f:
        f.write(rom)

    resumen = dict(rom=os.path.basename(salida), bytes=TAM_ROM, mapper="ASCII16",
                   arranque=len(arranque), stub=len(stub), stub_ram=STUB, plan_entradas=len(p.ops),
                   datos=disposicion, fin_datos=pos, libre=TAM_ROM - pos,
                   carga=dict(bajo=CARGA_BAJO, medio=CARGA_MEDIO, alto=CARGA_ALTO, salto=SALTO, pila=PILA),
                   pantalla_de_carga=con_pantalla, espera_cuadros=espera,
                   vdp_regs=VDP_REGS, psg_regs=PSG_REGS, plan=p.json())
    with open(os.path.join(work, "plan.json"), "w") as f:
        json.dump(resumen, f, indent=1)

    print("%s: %d bytes, %s" % (salida, TAM_ROM, resumen["mapper"]))
    print("  arranque %d B + stub %d B (plan de %d entradas) en 0x0000; datos de 0x%04X a 0x%04X; libres %d B"
          % (len(arranque), len(stub), len(p.ops), INICIO_DATOS, pos - 1, TAM_ROM - pos))
    for nombre, d in disposicion.items():
        print("  %-9s ROM 0x%05X  %5d B" % (nombre, d["rom"], d["bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
