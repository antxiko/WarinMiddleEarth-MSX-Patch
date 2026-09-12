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

LA MUSICA (--musica <fichero.pt3>)

Detras de los datos queda un hueco hasta el final de la ROM -hoy 2264 bytes-,
y cae entero en el ultimo banco. Ahi van el reproductor PT3, el modulo y el
puente, y ese banco se deja FIJADO en la ventana de 0x8000 antes de saltar al
juego, mientras el registro del mapper todavia se puede escribir. Luego el
juego corre con las cuatro paginas en RAM y la ROM se asoma solo durante la
interrupcion, que es lo que hace el puente de 0x003B. Ademas cambia dos sitios
del bloque medio: el gancho por cuadro y la lectura del nivel del menu, para
que la musica arranque con el menu y calle al empezar la partida.

LAS PANTALLAS FINALES EN LA ROM (--finales-rom)

Las dos pantallas del final -victoria y derrota, 6.912 bytes cada una- ocupan
13.824 bytes de RAM desde el arranque para usarse una sola vez al acabar la
partida. Con esta opcion dejan de viajar a la RAM: se quedan en la ROM, donde
ya estaban comprimidas, y una rutina de la pagina 0 (src/cartucho/finales.asm)
las descomprime a 0x4000 cuando el juego las pide. Son ocho bytes mas del
bloque medio, los de 0x83E7, donde los cuatro finales convergen.

Uso: haz_rom.py <work> <salida.rom> [--espera N] [--sin-pantalla]
                                    [--comprime] [--finales-rom]
                                    [--musica <fichero.pt3>] [--salidas <dir>]

`--salidas` manda donde van los derivados (plan, stub, .sym, plan.json). Hace
falta para montar DOS ROMs parecidas sin que la segunda le pise el plan a la
primera: los tests cargarian entonces una ROM con el plan de la otra y
fallarian sin que nada estuviera roto.

`work` es el directorio con los cuerpos: el `work/` del parche para la cinta
original, o `work/cuerpos_parche/` para la parcheada (los saca el Makefile de
war_parche.tsx con las mismas dos herramientas). El plan, los binarios del
cargador y plan.json se escriben en ese mismo directorio, y en `work/musica/`
cuando se pide musica: las dos ROMs salen de los mismos cuerpos, asi que
compartiendo directorio la segunda pisaria el plan y el stub de la primera.
"""
import json
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comprime import comprime           # noqa: E402

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
          PSG_REG=11, ESPERA=12, SALTA=13, BANCO_8000=14)

# LA MUSICA (opcional, --musica). El reproductor y el modulo van en el hueco
# que queda detras de los datos, que cae en el ultimo banco; ese banco se deja
# FIJADO en la ventana de 0x8000 antes de saltar al juego, mientras el registro
# del mapper todavia se puede escribir. Medido en una VG-8020: el banco
# sobrevive a conmutar la ranura de la pagina 2, que es lo que permite que el
# juego corra con las cuatro paginas en RAM y la ROM se asome solo durante la
# interrupcion.
VENTANA_8000 = 0x8000       # donde se ve el banco elegido con el registro 0x7000
CABECERA_PT3 = 100          # los 100 bytes de texto (titulo y autor) no se meten
PUENTE_RAM = 0x003B         # detras del `jp 0x0400` de 0x0038, en tierra de nadie
# El gancho por cuadro que el juego deja vacio: 0x5E0F es `ld hl,00428h` y
# 0x5E12 lo guarda en 0x0415. Cambiando su operando -dos bytes del bloque
# medio- la interrupcion pasa a llamar al puente en vez de a un `ret`.
GANCHO_RAM = 0x0415         # el operando del `call` de 0x0414, en la INTERRUPCION
GANCHO_OPERANDO = 0x5E10    # y el `ld hl,nn` del bloque medio que lo rellena
GANCHO_VACIO = 0x0428
ORG_MEDIO = 0x5E00          # donde corre el bloque medio, ya recolocado
# Y donde calla: MENU_TECLA_0 ya ha comprobado que la tecla es el '0' de
# empezar la partida, y lo primero que hace es recoger el nivel elegido. Ese
# `ld a,(MENU_NIVEL)` se cambia por un `call` al trozo que avisa al puente y
# hace luego la carga que se llevo por delante.
MENU_LEE_NIVEL = 0x5E86     # `3A 70 5E`, tres bytes
MENU_NIVEL = 0x5E70         # el operando del `ld a,nn` de 0x5E6F, que guarda el nivel

# LAS TRES IMAGENES (--comprime). Son lo unico del juego que se puede encoger
# de verdad, y no se pierde ninguna: viajan comprimidas y el cargador las
# descomprime en su sitio, asi que el juego encuentra exactamente lo mismo.
#
#   la intro    los 12.288 B de la pantalla de carga, que van a la VRAM
#   la victoria 6.912 B en 0x094F, dentro del bloque bajo (Gandalf)
#   la derrota  6.912 B en 0x244F, la cola del bloque bajo (Sauron)
#
# Las dos finales son pantallas del ZX enteras -bitmap y atributos- y ocupan
# TODA la cola del bloque bajo, que por eso se parte en dos: el codigo se copia
# crudo y ellas se descomprimen detras.
FINALES = ((0x094F, 6912, "victoria: Gandalf y THE FORCES OF EVIL HAVE BEEN DESTROYED"),
           (0x244F, 6912, "derrota: Sauron y May the Forces of Evil Never be Defeated"))

# Y con --finales-rom ni siquiera viajan a la RAM. PINTA_LA_PANTALLA_FINAL es
# donde los cuatro finales del juego convergen, y sus ocho primeros bytes son
# el `ld de,04000h / ld bc,01b00h / ldir` que copiaba la pantalla desde la RAM:
# se cambian por una llamada a la rutina, que hace lo mismo leyendo de la ROM.
# HL llega con 0x094F o 0x244F, asi que no hay que tocar VICTORIA ni DERROTA.
PINTA_LA_FINAL = 0x83E7
PINTA_LA_FINAL_ORIG = bytes.fromhex("110040 01001b edb0")


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

    # Un bloque comprimido: basta el banco donde EMPIEZA, porque el
    # descompresor cruza al siguiente solo. La marca viaja en el campo `len`,
    # que en estas dos operaciones no hace falta para nada mas.
    def rle(self, a_vram, d, dst, nota):
        banco = d["rom"] // TAM_BANCO
        self.op("ROM_VRAM_RLE" if a_vram else "ROM_RAM_RLE", banco,
                0x4000 + d["rom"] % TAM_BANCO, dst, d["marca"], nota)

    def inc(self):
        lineas = []
        for nombre, b, src, dst, n, nota in self.ops:
            lineas.append("        defb OP_%s,%d\n        defw 0%04Xh,0%04Xh,0%04Xh   ; %s"
                          % (nombre, b, src, dst, n, nota))
        return "\n".join(lineas) + "\n"

    def json(self):
        return [dict(op=nombre, b=b, src=src, dst=dst, len=n, nota=nota)
                for nombre, b, src, dst, n, nota in self.ops]


def lee_simbolos(ruta):
    """Los `ETIQUETA EQU 1234H` que escribe pasmo. Las direcciones de las
    rutinas salen de aqui y no de contarlas a mano: asi no pueden quedarse
    viejas cuando el fuente cambia."""
    simbolos = {}
    with open(ruta) as f:
        for linea in f:
            partes = linea.split()
            if len(partes) == 3 and partes[1].upper() == "EQU":
                simbolos[partes[0]] = int(partes[2].rstrip("Hh"), 16)
    return simbolos


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
    musica = None
    comprimir = False
    finales_rom = False
    salidas_pedidas = None
    i = 3
    while i < len(argv):
        if argv[i] == "--espera":
            espera = int(argv[i + 1]); i += 2
        elif argv[i] == "--sin-pantalla":
            con_pantalla = False; i += 1
        elif argv[i] == "--musica":
            musica = argv[i + 1]; i += 2
        elif argv[i] == "--comprime":
            comprimir = True; i += 1
        elif argv[i] == "--finales-rom":
            finales_rom = True; i += 1
        elif argv[i] == "--salidas":
            salidas_pedidas = argv[i + 1]; i += 2
        else:
            print("argumento desconocido:", argv[i]); return 2
    assert 0 < espera < 256
    # La rutina de las finales lleva un descompresor y nada mas: si los bloques
    # viajaran crudos no sabria copiarlos.
    assert not finales_rom or comprimir, "--finales-rom necesita --comprime"

    # Los cuerpos se leen de `work`, pero lo que se GENERA -el plan, el stub
    # ensamblado, los .sym- va aparte cuando hay musica: las dos ROMs salen de
    # los mismos cuerpos y, compartiendo directorio, la segunda pisaba el plan y
    # el stub de la primera. Los tests cargaban entonces war.rom con el plan de
    # war_musica.rom y fallaban sin que nada estuviera realmente roto.
    if salidas_pedidas:
        salidas = salidas_pedidas
    elif musica:
        salidas = os.path.join(work, "musica")
    elif finales_rom:
        salidas = os.path.join(work, "finales")
    elif comprimir:
        salidas = os.path.join(work, "comprimido")
    else:
        salidas = work
    os.makedirs(salidas, exist_ok=True)

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

    def mete(nombre, cuerpo, **extra):
        nonlocal pos
        disposicion[nombre] = dict(rom=pos, bytes=len(cuerpo), **extra)
        datos.append(cuerpo)
        pos += len(cuerpo)

    def mete_z(nombre, cuerpo, que):
        """Comprimido, con su marca y el tamano original apuntados: el plan los
        necesita y el test los usa para comprobar la ida y vuelta. Si el
        resultado fuera mas grande que el original -puede pasar, comprimir no
        siempre encoge- se mete crudo y se dice."""
        z, marca = comprime(cuerpo)
        if len(z) >= len(cuerpo):
            mete(nombre, cuerpo, crudo=len(cuerpo), rle=False, que=que)
            return False
        mete(nombre, z, crudo=len(cuerpo), rle=True, marca=marca, que=que)
        return True

    if comprimir:
        # Las tres imagenes comprimidas, y el bloque bajo partido: primero su
        # codigo, crudo, y detras las dos pantallas finales.
        mete_z("patrones", patrones, "intro: los patrones de la pantalla de carga")
        mete_z("colores", colores, "intro: los colores de la pantalla de carga")
        corte = FINALES[0][0] - CARGA_BAJO
        assert FINALES[0][0] + FINALES[0][1] == FINALES[1][0], "las dos finales no van seguidas"
        assert FINALES[1][0] + FINALES[1][1] - CARGA_BAJO == len(bajo), \
            "las dos pantallas finales no acaban donde acaba el bloque bajo"
        mete("bajo", bajo[:corte], crudo=corte, rle=False,
             que="bloque bajo: el codigo, hasta donde empiezan las pantallas finales")
        for n, (dir_, tam, que) in enumerate(FINALES):
            o = dir_ - CARGA_BAJO
            mete_z("final%d" % n, bajo[o:o + tam], que)
    else:
        mete("patrones", patrones, crudo=len(patrones), rle=False)
        mete("colores", colores, crudo=len(colores), rle=False)
        mete("bajo", bajo, crudo=len(bajo), rle=False)
    mete("medio", medio, crudo=len(medio), rle=False)
    mete("alto", alto, crudo=len(alto), rle=False)
    assert pos <= TAM_ROM, "no cabe: %d bytes" % pos

    # ---------------------------------------------------------------- musica
    # El hueco que queda detras de los datos, hasta el final de la ROM. Como va
    # pegado al final, cae entero dentro del ultimo banco, que es el que se deja
    # puesto en la ventana de 0x8000. La direccion de ensamblado sale de aqui y
    # se le pasa a pasmo: asi no puede quedarse vieja si los datos crecen.
    hueco, libre_hueco = pos, TAM_ROM - pos
    banco_musica = hueco // TAM_BANCO
    musica_org = VENTANA_8000 + hueco - banco_musica * TAM_BANCO
    bloque_musica = None
    if musica:
        assert banco_musica == (TAM_ROM - 1) // TAM_BANCO, \
            "el hueco empieza en el banco %d y no en el ultimo" % banco_musica
        with open(musica, "rb") as f:
            pt3 = f.read()
        assert len(pt3) > CABECERA_PT3, "%s no llega ni a la cabecera" % musica
        # PT3_INIT quiere la direccion del modulo MENOS 100, que es justo lo que
        # queda al quitarle la cabecera de texto: la misma cuenta que hace
        # msx-msxlib con CFG_PT3_HEADERLESS.
        with open(os.path.join(salidas, "modulo.bin"), "wb") as f:
            f.write(pt3[CABECERA_PT3:])
        bloque_musica = pasmo(os.path.join(SRC, "musica.asm"),
                              os.path.join(salidas, "musica.bin"),
                              os.path.join(salidas, "musica.sym"),
                              equs=[("MUSICA_ORG", musica_org)])
        sim = lee_simbolos(os.path.join(salidas, "musica.sym"))
        # Y el puente, que corre en la RAM de la pagina 0 pero VIAJA en la ROM,
        # detras del reproductor, para que el plan lo copie a su sitio. Se
        # ensambla aparte porque su `org` es otro, y las direcciones de las
        # rutinas se las damos leidas del .sym de lo que acabamos de ensamblar.
        puente = pasmo(os.path.join(SRC, "puente.asm"),
                       os.path.join(salidas, "puente.bin"), os.path.join(salidas, "puente.sym"),
                       equs=[("PUENTE_ORG", PUENTE_RAM), ("GANCHO_VACIO", GANCHO_VACIO), ("GANCHO", GANCHO_RAM),
                             ("MENU_NIVEL", MENU_NIVEL)]
                             + [(k, sim[k]) for k in ("PT3_INIT", "PT3_PLAY", "PT3_ROUT",
                                                      "PT3_MUTE", "MODULO")])
        sim_puente = lee_simbolos(os.path.join(salidas, "puente.sym"))
        puente_rom = hueco + len(bloque_musica)
        bloque_musica += puente
        assert len(bloque_musica) <= libre_hueco, \
            "la musica ocupa %d B y en el hueco caben %d" % (len(bloque_musica), libre_hueco)
        assert PUENTE_RAM + len(puente) <= BUZON_POKES[0], \
            "el puente llega a 0x%04X y pisaria el buzon de POKEs" % (PUENTE_RAM + len(puente))

    # LAS PANTALLAS FINALES. La rutina corre en la RAM de la pagina 0, detras
    # del puente si lo hay, pero VIAJA en la ROM como el: en el hueco, detras
    # de la musica. De donde lee cada pantalla -banco, direccion dentro de la
    # ventana de 0x8000 y marca del RLE- se lo damos ya calculado, que es lo
    # que hay en la disposicion y aqui no hay que volver a deducirlo.
    bloque_finales = None
    finales_ram = PUENTE_RAM + (len(puente) if musica else 0)
    if finales_rom:
        equs = [("FINALES_ORG", finales_ram),
                ("BANCO_VUELVE", banco_musica if musica else 0)]
        for n, (dir_, _tam, _que) in enumerate(FINALES):
            d = disposicion["final%d" % n]
            assert d.get("rle"), "la pantalla final %d no esta comprimida" % n
            equs += [("F%d_DIR" % n, dir_),
                     ("F%d_BANCO" % n, d["rom"] // TAM_BANCO),
                     ("F%d_SRC" % n, VENTANA_8000 + d["rom"] % TAM_BANCO),
                     ("F%d_MARCA" % n, d["marca"])]
        bloque_finales = pasmo(os.path.join(SRC, "finales.asm"),
                               os.path.join(salidas, "finales.bin"),
                               os.path.join(salidas, "finales.sym"), equs=equs)
        sim_finales = lee_simbolos(os.path.join(salidas, "finales.sym"))
        finales_rom_pos = hueco + (len(bloque_musica) if bloque_musica else 0)
        bloque_musica = (bloque_musica or b"") + bloque_finales
        assert len(bloque_musica) <= libre_hueco, \
            "la musica y las finales ocupan %d B y en el hueco caben %d" % (len(bloque_musica), libre_hueco)
        assert finales_ram + len(bloque_finales) <= BUZON_POKES[0], \
            "la rutina de las finales llega a 0x%04X y pisaria el buzon de POKEs" \
            % (finales_ram + len(bloque_finales))

    # El bloque medio, cargado en 0x3F4F, cruza a la pagina 1 en 0x4000
    en_pagina0 = 0x4000 - CARGA_MEDIO                  # 177 bytes
    en_pagina1 = len(medio) - en_pagina0               # 14400 bytes
    assert en_pagina1 <= 0x4000, "el tramo de la pagina 1 no cabe en la VRAM"
    assert CARGA_ALTO + len(alto) - 1 < STUB, "el bloque alto pisaria el stub"

    # ------------------------------------------------------------------ plan
    def bloque(nombre, dst, a_vram=False, nota=None):
        """Mete el bloque `nombre` en el plan, comprimido o crudo segun como se
        haya guardado. Asi el plan no repite la decision que ya se tomo arriba."""
        d = disposicion[nombre]
        texto = nota or d.get("que", nombre)
        if d.get("rle"):
            p.rle(a_vram, d, dst, "%s (%d B -> %d, RLE)" % (texto, d["crudo"], d["bytes"]))
        else:
            p.copia_rom("ROM_VRAM" if a_vram else "ROM_RAM", d["rom"], dst, d["bytes"], texto)

    p = Plan()
    if musica:
        # Lo primero de todo, que es cuando la pagina 1 es el cartucho con toda
        # seguridad y el registro del mapper se puede escribir. Una vez puesto,
        # el banco se queda: ni las copias -que mueven la OTRA ventana, la de
        # 0x4000- ni el conmutar la ranura mas adelante lo tocan.
        p.op("BANCO_8000", banco_musica,
             nota="banco %d fijado en la ventana de 0x8000: la musica" % banco_musica)
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
        bloque("patrones", 0x0000, a_vram=True, nota="pantalla de carga: patrones")
        bloque("colores", 0x2000, a_vram=True, nota="pantalla de carga: colores")
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
    bloque("bajo", CARGA_BAJO, nota="bloque bajo a 0x0190, donde corre")
    # Con --finales-rom estas dos NO viajan a la RAM: se quedan donde estan y
    # la rutina de la pagina 0 las descomprime a 0x4000 al acabar la partida.
    # Son los 13.824 bytes de RAM que libera el cambio.
    if not finales_rom:
        for n, (dir_, _tam, _que) in enumerate(FINALES):
            if ("final%d" % n) in disposicion:
                bloque("final%d" % n, dir_)
    p.copia_rom("ROM_RAM", disposicion["medio"]["rom"], CARGA_MEDIO, en_pagina0, "bloque medio 0x3F4F-0x3FFF")
    p.op("LLENA_RAM", 0, 0, BUZON_POKES[0], BUZON_POKES[1], "buzon de POKEs de 0x012C a cero: sin POKEs")
    if musica:
        # El puente a su sitio, y dentro de el la ranura donde ha resultado
        # estar el cartucho, que hasta ahora no se sabia.
        p.copia_rom("ROM_RAM", puente_rom, PUENTE_RAM, len(puente),
                    "el puente de la musica a 0x%04X, donde lo llama el gancho" % PUENTE_RAM)
        p.op("RANURA_PAG2", 0, 0, sim_puente["PUENTE_RANURA"] + 1, 0,
             "y la ranura del cartucho en el `or` de 0x%04X" % (sim_puente["PUENTE_RANURA"] + 1))
    if finales_rom:
        # La rutina de las finales, a su sitio, y sus DOS `or`: conmuta la
        # pagina 2 para leer la ROM y la 1 un momento para el registro del
        # mapper, asi que necesita los bits de las dos.
        p.copia_rom("ROM_RAM", finales_rom_pos, finales_ram, len(bloque_finales),
                    "la rutina de las pantallas finales a 0x%04X" % finales_ram)
        p.op("RANURA_PAG2", 0, 0, sim_finales["F_RANURA2"] + 1, 0,
             "la ranura del cartucho para la pagina 2 de las finales")
        p.op("RANURA_PAG1", 0, 0, sim_finales["F_RANURA1"] + 1, 0,
             "... y para la pagina 1, que conmuta al escribir el registro")
    p.copia_rom("ROM_RAM", disposicion["alto"]["rom"], CARGA_ALTO, len(alto), "bloque alto a 0x88B8, como cae de la cinta")
    # y la pagina 1
    p.op("PAG1_RAM", nota="fuera el cartucho de la pagina 1")
    p.op("VRAM_RAM", 0, 0x0000, 0x4000, en_pagina1, "el tramo vuelve de la VRAM a 0x4000-0x783F")
    if con_pantalla:
        p.op("PAG1_CART", nota="el cartucho otra vez, para repintar la imagen")
        bloque("patrones", 0x0000, a_vram=True, nota="imagen de carga otra vez: patrones")
        bloque("colores", 0x2000, a_vram=True, nota="imagen de carga otra vez: colores")
        tablas_del_screen_2(" (otra vez: el bufer las piso)")
        p.op("PAG1_RAM", nota="y fuera del todo: el juego quiere las cuatro paginas en RAM")
    else:
        tablas_del_screen_2(" (otra vez: el bufer las piso)")
    for r, v in enumerate(PSG_REGS):
        p.op("PSG_REG", r, v, nota="PSG R%d como lo deja la cinta" % r)
    p.op("VDP_REG", 1, VDP_REGS[1], nota="pantalla encendida, como la deja la cinta")
    p.op("SALTA", 0, PILA, SALTO, nota="SP=0x%04X y a 0x%04X, como el cargador de la cinta" % (PILA, SALTO))
    p.op("FIN")

    with open(os.path.join(salidas, "plan.inc"), "w") as f:
        f.write("; generado por tools/haz_rom.py: no editar\n")
        f.write(p.inc())

    # ------------------------------------------------------------ ensamblar
    stub = pasmo(os.path.join(SRC, "cargador_ram.asm"),
                 os.path.join(salidas, "cargador_ram.bin"), os.path.join(salidas, "cargador_ram.sym"))
    arranque = pasmo(os.path.join(SRC, "cargador_rom.asm"),
                     os.path.join(salidas, "cargador_rom.bin"), os.path.join(salidas, "cargador_rom.sym"),
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
    assert pos == hueco, "la disposicion no ha salido donde se calculo"
    # Los unicos bytes del juego que estas ROMs cambian, y la razon de que la
    # musica y las finales vayan en un fichero aparte: en war.rom el gancho
    # sigue siendo el `ret` de siempre, el menu no llama a nadie y las
    # pantallas finales se copian de la RAM con su `ldir`.
    base = disposicion["medio"]["rom"] - ORG_MEDIO
    parches = []
    parches_musica = []

    def parchea(dir_, viejo, nuevo, que):
        o = base + dir_
        assert rom[o:o + len(viejo)] == viejo, \
            "en 0x%04X no esta %s sino %s" % (dir_, viejo.hex(), bytes(rom[o:o + len(viejo)]).hex())
        assert len(nuevo) == len(viejo), "un parche del juego no puede cambiar de tamano"
        rom[o:o + len(nuevo)] = nuevo
        # `dir` es donde el juego lo EJECUTA (0x5E00 y arriba) y `carga`
        # donde cae al cargarlo, antes de que 0x0190 recoloque el bloque.
        # Los tests que miran la RAM recien cargada necesitan la segunda.
        q = dict(dir=dir_, carga=CARGA_MEDIO + dir_ - ORG_MEDIO,
                 rom=o, orig=viejo.hex(), nuevo=nuevo.hex(), que=que)
        parches.append(q)
        return q

    if bloque_musica:
        rom[hueco:hueco + len(bloque_musica)] = bloque_musica
    if musica:
        parches_musica.append(parchea(
            GANCHO_OPERANDO, GANCHO_VACIO.to_bytes(2, "little"),
            PUENTE_RAM.to_bytes(2, "little"),
            "el gancho por cuadro pasa del `ret` de 0x%04X al puente" % GANCHO_VACIO))
        parches_musica.append(parchea(
            MENU_LEE_NIVEL, bytes([0x3A]) + MENU_NIVEL.to_bytes(2, "little"),
            bytes([0xCD]) + sim_puente["PARA_LA_MUSICA"].to_bytes(2, "little"),
            "al pulsar 0 el menu avisa al puente antes de leer el nivel"))
    parche_finales = None
    if finales_rom:
        # El `ld de,04000h / ld bc,01b00h / ldir` de PINTA_LA_PANTALLA_FINAL,
        # por la llamada. Los cinco bytes que sobran van a cero: el `call`
        # vuelve y los atraviesa como NOPs hasta el `call 005bdh` de 0x83EF.
        parche_finales = parchea(
            PINTA_LA_FINAL, PINTA_LA_FINAL_ORIG,
            bytes([0xCD]) + sim_finales["FINALES"].to_bytes(2, "little") + bytes(5),
            "los cuatro finales llaman a la rutina en vez de copiar de la RAM")
    with open(salida, "wb") as f:
        f.write(rom)

    if musica:
        # `bytes` es lo que ocupa la MUSICA: el reproductor, el modulo y el
        # puente. Si ademas van las finales, su rutina viaja detras y se cuenta
        # aparte, en resumen["finales"].
        musica_bytes = len(bloque_musica) - (len(bloque_finales) if bloque_finales else 0)
        disposicion["musica"] = dict(rom=hueco, bytes=musica_bytes,
                                     banco=banco_musica, org=musica_org,
                                     pt3=os.path.basename(musica),
                                     reproductor=musica_bytes - len(puente),
                                     modulo=sim["MODULO"], init=sim["PT3_INIT"],
                                     play=sim["PT3_PLAY"], rout=sim["PT3_ROUT"],
                                     mute=sim["PT3_MUTE"],
                                     puente=dict(rom=puente_rom, ram=PUENTE_RAM,
                                                 bytes=len(puente),
                                                 para=sim_puente["PARA_LA_MUSICA"]),
                                     parches=parches_musica)

    resumen = dict(rom=os.path.basename(salida), bytes=TAM_ROM, mapper="ASCII16",
                   arranque=len(arranque), stub=len(stub), stub_ram=STUB, plan_entradas=len(p.ops),
                   datos=disposicion, fin_datos=pos,
                   libre=TAM_ROM - pos - (len(bloque_musica) if bloque_musica else 0),
                   carga=dict(bajo=CARGA_BAJO, medio=CARGA_MEDIO, alto=CARGA_ALTO, salto=SALTO, pila=PILA),
                   pantalla_de_carga=con_pantalla, espera_cuadros=espera,
                   vdp_regs=VDP_REGS, psg_regs=PSG_REGS, plan=p.json())
    if finales_rom:
        # Lo que hace falta para comprobar esto sin arrancar nada: donde viaja
        # la rutina, donde corre, de donde lee cada pantalla y el parche que la
        # pone en marcha. Las direcciones salen del .sym, no de contarlas.
        resumen["finales"] = dict(
            rom=finales_rom_pos, ram=finales_ram, bytes=len(bloque_finales),
            entrada=sim_finales["FINALES"], parche=parche_finales,
            banco_vuelve=banco_musica if musica else 0,
            ranuras=dict(pag1=sim_finales["F_RANURA1"] + 1, pag2=sim_finales["F_RANURA2"] + 1),
            pantallas=[dict(dir=dir_, crudo=tam, que=que,
                            rom=disposicion["final%d" % n]["rom"],
                            bytes=disposicion["final%d" % n]["bytes"],
                            banco=disposicion["final%d" % n]["rom"] // TAM_BANCO,
                            src=VENTANA_8000 + disposicion["final%d" % n]["rom"] % TAM_BANCO,
                            marca=disposicion["final%d" % n]["marca"])
                       for n, (dir_, tam, que) in enumerate(FINALES)])
    with open(os.path.join(salidas, "plan.json"), "w") as f:
        json.dump(resumen, f, indent=1)

    # Las direcciones para las sondas de openMSX, en un fichero que se hace
    # `source`. Escritas a mano se quedan viejas en cuanto el puente cambia de
    # tamano: PUENTE_SONANDO se movio de 0x006E a 0x007C al anadirle el parar,
    # y la sonda siguio leyendo la vieja y dando un valor que no era.
    if musica:
        with open(os.path.join(salidas, "musica.tcl"), "w") as f:
            f.write("# generado por tools/haz_rom.py: no editar\n")
            for k, v in (("PUENTE", PUENTE_RAM), ("PUENTE_FIN", PUENTE_RAM + len(puente) - 1),
                         ("PUENTE_SONANDO", sim_puente["PUENTE_SONANDO"]),
                         ("PUENTE_RANURA", sim_puente["PUENTE_RANURA"] + 1),
                         ("PARA_LA_MUSICA", sim_puente["PARA_LA_MUSICA"]),
                         ("GANCHO", GANCHO_RAM), ("GANCHO_VACIO", GANCHO_VACIO),
                         ("PT3_SETUP", sim_puente["PT3_SETUP"]),
                         ("AYREGS", sim_puente["AYREGS"])):
                f.write("set ::%-15s 0x%04X\n" % (k, v))

    print("%s: %d bytes, %s" % (salida, TAM_ROM, resumen["mapper"]))
    print("  arranque %d B + stub %d B (plan de %d entradas) en 0x0000; datos de 0x%04X a 0x%04X; libres %d B"
          % (len(arranque), len(stub), len(p.ops), INICIO_DATOS, pos - 1, resumen["libre"]))
    for nombre, d in disposicion.items():
        print("  %-9s ROM 0x%05X  %5d B" % (nombre, d["rom"], d["bytes"]))
    if musica:
        m = disposicion["musica"]
        print("  la musica es %s: banco %d, se ve en 0x%04X-0x%04X por la ventana de 0x8000"
              % (m["pt3"], m["banco"], m["org"], m["org"] + m["bytes"] - 1))
        print("     PT3_INIT 0x%04X  PT3_PLAY 0x%04X  PT3_ROUT 0x%04X  modulo 0x%04X (a INIT se le pasa 0x%04X)"
              % (m["init"], m["play"], m["rout"], m["modulo"], m["modulo"] - CABECERA_PT3))
        print("     el puente: %d B de ROM 0x%05X a RAM 0x%04X; PARA_LA_MUSICA en 0x%04X"
              % (m["puente"]["bytes"], m["puente"]["rom"], m["puente"]["ram"], m["puente"]["para"]))
        for q in m["parches"]:
            print("     0x%04X del bloque medio: %s -> %s, %s"
                  % (q["dir"], q["orig"], q["nuevo"], q["que"]))
    if finales_rom:
        f = resumen["finales"]
        print("  las pantallas finales se quedan en la ROM: %d B de rutina de ROM 0x%05X a RAM 0x%04X"
              % (f["bytes"], f["rom"], f["ram"]))
        for q in f["pantallas"]:
            print("     0x%04X (%d B crudos) desde el banco %d, 0x%04X, marca 0x%02X: %s"
                  % (q["dir"], q["crudo"], q["banco"], q["src"], q["marca"], q["que"]))
        q = f["parche"]
        print("     0x%04X del bloque medio: %s -> %s, %s"
              % (q["dir"], q["orig"], q["nuevo"], q["que"]))
        print("     RAM liberada: %d bytes" % sum(q["crudo"] for q in f["pantallas"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
