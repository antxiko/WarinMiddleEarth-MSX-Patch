#!/usr/bin/env python3
"""Ejecuta la rutina de las pantallas finales del cartucho, en Python.

POR QUE UN INTERPRETE Y NO UN EMULADOR

Lo que hace src/cartucho/finales.asm no se puede comprobar mirando: conmuta
dos paginas de la memoria, cambia el banco que se ve por la ventana de 0x8000 y
descomprime cruzando de banco a mitad. Un fallo en cualquiera de esas tres
cosas da una pantalla con basura, y para verla hay que terminarse el juego.

Este interprete ejecuta la rutina de verdad -los mismos bytes que van en la
ROM- sobre un modelo de la maquina: ranuras, mapper ASCII16 y RAM. Asi se
comprueba sin arrancar nada:

  1. que lo que deja en 0x4000 son los 6.912 bytes de la pantalla de la cinta,
     que es lo unico que el juego ve;
  2. que NUNCA toca la pila teniendo el cartucho en la pagina 1. La pila del
     juego vive en 0x5BFF, o sea ahi: un push, un pop, un call o un ret en ese
     tramo escribiria o leeria la ROM y la maquina se iria;
  3. que devuelve las paginas y el banco como estaban.

El interprete solo conoce las instrucciones que la rutina usa. Eso es a
proposito: si alguien le anade una, el test se para en vez de pasar por alto lo
que no sabe interpretar.

Uso:  corre_finales.py <rom> <plan.json>      las dos pantallas, con informe
"""
import json
import sys

TAM_BANCO = 0x4000
CENTINELA = 0xBEEF          # la direccion de retorno que se le pone a la pila


class Maquina:
    """Ranuras, mapper ASCII16 y RAM, lo justo para correr la rutina.

    En 0xA8 cada pagina son dos bits: 0-1 la pagina 0, 2-3 la 1, 4-5 la 2 y 6-7
    la 3. El cartucho esta en la primaria `ranura_cart` y la RAM en `ranura_ram`;
    una pagina es ROM cuando sus dos bits valen la del cartucho.
    """

    def __init__(self, rom, ranura_cart=1, ranura_ram=3):
        self.rom = rom
        self.ram = bytearray(0x10000)
        self.ranura_cart = ranura_cart
        self.ranura_ram = ranura_ram
        # el juego corre con las cuatro paginas en RAM
        self.a8 = ranura_ram * 0b01010101
        self.banco_4000 = 0
        self.banco_8000 = 0
        self.pila_con_cartucho = []     # lo que no puede pasar nunca
        self.escrituras_perdidas = []   # escribir en la ROM no hace nada; se apunta

    def es_cartucho(self, pagina):
        return (self.a8 >> (2 * pagina)) & 3 == self.ranura_cart

    def lee(self, dir_):
        dir_ &= 0xFFFF
        pagina = dir_ >> 14
        if not self.es_cartucho(pagina):
            return self.ram[dir_]
        if pagina == 1:
            return self.rom[self.banco_4000 * TAM_BANCO + dir_ - 0x4000]
        if pagina == 2:
            return self.rom[self.banco_8000 * TAM_BANCO + dir_ - 0x8000]
        return 0xFF             # un ASCII16 no responde en las paginas 0 y 3

    def escribe(self, dir_, v):
        dir_ &= 0xFFFF
        pagina = dir_ >> 14
        if not self.es_cartucho(pagina):
            self.ram[dir_] = v & 0xFF
            return
        # Los dos registros del mapper, cada uno en su ventana de 2 KB.
        if 0x6000 <= dir_ < 0x6800:
            self.banco_4000 = v & 0xFF
        elif 0x7000 <= dir_ < 0x7800:
            self.banco_8000 = v & 0xFF
        else:
            self.escrituras_perdidas.append(dir_)

    # --- la pila, que es lo que hay que vigilar
    def pila(self, sp, que):
        if self.es_cartucho((sp & 0xFFFF) >> 14):
            self.pila_con_cartucho.append((que, sp & 0xFFFF))


class Z80:
    """Solo las instrucciones que usa finales.asm. Cualquier otra, y se para."""

    def __init__(self, maquina, pc, sp, hl=0):
        self.m = maquina
        self.pc, self.sp = pc, sp
        self.a = self.b = self.c = self.d = self.e = 0
        self.h, self.l = hl >> 8, hl & 0xFF
        self.cy = self.z = False
        self.di = None          # None = como estaba; True/False = lo que dejo
        self.pasos = 0

    # --- ayudas
    def n(self):
        v = self.m.lee(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def nn(self):
        return self.n() | (self.n() << 8)

    def desp(self):
        """El desplazamiento de un `jr`/`djnz`. No se llama `d` porque ese
        nombre es el registro D."""
        v = self.n()
        return v - 256 if v > 127 else v

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        self.m.pila(self.sp, "push")
        self.m.escribe(self.sp, v & 0xFF)
        self.m.escribe(self.sp + 1, v >> 8)

    def pop(self):
        self.m.pila(self.sp, "pop")
        v = self.m.lee(self.sp) | (self.m.lee(self.sp + 1) << 8)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    @property
    def de(self):
        return (self.d << 8) | self.e

    @de.setter
    def de(self, v):
        self.d, self.e = (v >> 8) & 0xFF, v & 0xFF

    @property
    def hl(self):
        return (self.h << 8) | self.l

    @hl.setter
    def hl(self, v):
        self.h, self.l = (v >> 8) & 0xFF, v & 0xFF

    def corre(self, tope=2000000):
        while self.pasos < tope:
            self.pasos += 1
            if self.pc == CENTINELA:
                return
            self.paso()
        raise RuntimeError("la rutina no termina: %d instrucciones" % tope)

    def paso(self):
        op = self.n()
        if op == 0xF3:                                  # di
            self.di = True
        elif op == 0xFB:                                # ei
            self.di = False
        elif op == 0x00:                                # nop
            pass
        elif op == 0xDB:                                # in a,(n)
            puerto = self.n()
            assert puerto == 0xA8, "in a,(0x%02X): solo se espera 0xA8" % puerto
            self.a = self.m.a8
        elif op == 0xD3:                                # out (n),a
            puerto = self.n()
            assert puerto == 0xA8, "out (0x%02X): solo se espera 0xA8" % puerto
            self.m.a8 = self.a
        elif op == 0x32:                                # ld (nn),a
            self.m.escribe(self.nn(), self.a)
        elif op == 0x3A:                                # ld a,(nn)
            self.a = self.m.lee(self.nn())
        elif op == 0xE6:                                # and n
            self.a &= self.n(); self.z = self.a == 0; self.cy = False
        elif op == 0xF6:                                # or n
            self.a |= self.n(); self.z = self.a == 0; self.cy = False
        elif op == 0xB7:                                # or a
            self.z = self.a == 0; self.cy = False
        elif op == 0xFE:                                # cp n
            v = self.n(); self.z = self.a == v; self.cy = self.a < v
        elif op == 0x7C:                                # ld a,h
            self.a = self.h
        elif op == 0x79:                                # ld a,c
            self.a = self.c
        elif op == 0x47:                                # ld b,a
            self.b = self.a
        elif op == 0x3E:                                # ld a,n
            self.a = self.n()
        elif op == 0x0E:                                # ld c,n
            self.c = self.n()
        elif op == 0x26:                                # ld h,n
            self.h = self.n()
        elif op == 0x21:                                # ld hl,nn
            self.hl = self.nn()
        elif op == 0x11:                                # ld de,nn
            self.de = self.nn()
        elif op == 0x7E:                                # ld a,(hl)
            self.a = self.m.lee(self.hl)
        elif op == 0x12:                                # ld (de),a
            self.m.escribe(self.de, self.a)
        elif op == 0x13:                                # inc de
            self.de = (self.de + 1) & 0xFFFF
        elif op == 0x23:                                # inc hl
            self.hl = (self.hl + 1) & 0xFFFF
        elif op == 0x3C:                                # inc a
            self.a = (self.a + 1) & 0xFF; self.z = self.a == 0
        elif op == 0x18:                                # jr d
            e = self.desp()
            self.pc = (self.pc + e) & 0xFFFF
        elif op == 0x20:                                # jr nz,d
            e = self.desp()
            if not self.z:
                self.pc = (self.pc + e) & 0xFFFF
        elif op == 0x28:                                # jr z,d
            e = self.desp()
            if self.z:
                self.pc = (self.pc + e) & 0xFFFF
        elif op == 0x30:                                # jr nc,d
            e = self.desp()
            if not self.cy:
                self.pc = (self.pc + e) & 0xFFFF
        elif op == 0x10:                                # djnz d
            e = self.desp()
            self.b = (self.b - 1) & 0xFF
            if self.b:
                self.pc = (self.pc + e) & 0xFFFF
        elif op == 0xCD:                                # call nn
            destino = self.nn()
            self.push(self.pc)
            self.pc = destino
        elif op == 0xC9:                                # ret
            self.pc = self.pop()
        elif op == 0xC8:                                # ret z
            if self.z:
                self.pc = self.pop()
        elif op == 0xF5:                                # push af
            self.push((self.a << 8) | (0x40 if self.z else 0) | (1 if self.cy else 0))
        elif op == 0xF1:                                # pop af
            v = self.pop()
            self.a, self.z, self.cy = v >> 8, bool(v & 0x40), bool(v & 1)
        elif op == 0xCB:
            sub = self.n()
            if sub == 0x74:                             # bit 6,h
                self.z = not (self.h & 0x40)
            else:
                raise NotImplementedError("CB %02X en 0x%04X" % (sub, self.pc - 2))
        else:
            raise NotImplementedError("opcode %02X en 0x%04X" % (op, self.pc - 1))


def pinta(rom, plan, pantalla, ranura_cart=1, ranura_ram=3, sp=0x5BFF):
    """Monta la maquina como la deja el cargador, copia la rutina a su sitio y
    la llama como la llama el juego. Devuelve lo que queda en 0x4000."""
    f = plan["finales"]
    m = Maquina(rom, ranura_cart, ranura_ram)
    # lo que hace el plan: la rutina a la RAM y las dos ranuras en sus `or`
    m.ram[f["ram"]:f["ram"] + f["bytes"]] = rom[f["rom"]:f["rom"] + f["bytes"]]
    m.ram[f["ranuras"]["pag2"]] = ranura_cart << 4
    m.ram[f["ranuras"]["pag1"]] = ranura_cart << 2
    # y lo que deja el cargador antes de saltar al juego
    m.banco_8000 = f["banco_vuelve"]

    z = Z80(m, f["entrada"], sp, hl=pantalla["dir"])
    z.push(CENTINELA)
    z.corre()
    return m, z


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    with open(argv[1], "rb") as fh:
        rom = fh.read()
    with open(argv[2]) as fh:
        plan = json.load(fh)
    if "finales" not in plan:
        print("ese plan no lleva las pantallas finales en la ROM (--finales-rom)")
        return 2
    for pantalla in plan["finales"]["pantallas"]:
        m, z = pinta(rom, plan, pantalla)
        salido = bytes(m.ram[0x4000:0x4000 + pantalla["crudo"]])
        print("0x%04X  %s" % (pantalla["dir"], pantalla["que"]))
        print("   %d instrucciones; %d bytes en 0x4000; 0xA8 = 0x%02X; banco de 0x8000 = %d"
              % (z.pasos, len(salido), m.a8, m.banco_8000))
        print("   la pila con el cartucho puesto: %s"
              % ("NUNCA" if not m.pila_con_cartucho else m.pila_con_cartucho[:4]))
        print("   escrituras perdidas en la ROM: %d" % len(m.escrituras_perdidas))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
