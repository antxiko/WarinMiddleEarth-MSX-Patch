#!/usr/bin/env python3
"""LA IDA Y VUELTA DEL MAPA COMPRIMIDO, celda a celda.

Transcripcion de las dos rutinas del juego, tal como estan en el listado:

  EMPAQUETA (0x93B3)          0x33CC bytes -> parejas cuenta/valor
  COMPRIME_EL_MAPA (0x93A4)   y copia de vuelta 0x16EC, mida lo que mida
  DESCOMPRIME_EL_MAPA (0x9366) lee 0x16ED y expande hasta llenar 0x33CD

Lo que se quiere ver es cuantas celdas NO vuelven, y en que columnas. El mapa
va por columnas de 0x66, asi que la cola del buffer es la derecha del mapa.

OJO CON EL TAMANO ABSOLUTO. Por cada tira de 256 el contador de EMPAQUETA se
queda uno por detras -el `inc b` que da la vuelta sale por CIERRA_Y_SIGUE sin
descontar-, asi que el empaquetador de verdad SE SALE del mapa y sigue leyendo
lo que haya detras de 0xFFCB. Aqui se para en el mapa, y por eso sale 4 bytes
corto: el mapa limpio da 5866 aqui y 5870 medido en el emulador (DE al llegar
a 0x93A7). Para la cuenta exacta, el emulador; esto es para ver QUE se pierde.

Uso:  ronda_del_mapa.py <mapa.bin> [<mapa.bin> ...]
"""
import sys

LARGO = 0x33CC      # lo que empaqueta COMPRIME
VUELTA = 0x16EC     # lo que copia de vuelta, clavado en 0x93A7
LEE = 0x16ED        # lo que lee DESCOMPRIME, clavado en 0x9371
EXPANDE = 0x33CD    # y hasta donde llena, clavado en 0x9378


def empaqueta(mapa):
    """0x93B3. La cuenta va en B y no pasa de 256 (`inc b` / `jr z`); el que
    manda es el contador de 0x33CC que vive en el HL del juego alternativo."""
    out = bytearray()
    hl = 0
    cont = LARGO
    while True:
        c = mapa[hl]                  # EMPIEZA_UNA_TIRA
        b = 0
        while True:                   # entra por CUENTA_UNO_MAS
            hl += 1
            b = (b + 1) & 0xFF
            if b == 0:                # 256: se cierra la pareja
                break                 # OJO: por aqui NO se descuenta el contador
            if hl >= LARGO:           # el contador va uno por detras por cada
                out += bytes([b, c])  # tira de 256, asi que el mapa se acaba
                return bytes(out)     # antes que la cuenta
            cont -= 1
            if cont == 0:             # se acabo el mapa
                out += bytes([b, c])
                return bytes(out)
            if mapa[hl] != c:         # SIGUE_LA_TIRA
                break
        out += bytes([b, c])


def descomprime(paquete):
    """0x9366. Lee parejas y repite; B = 0 son 256 (djnz). Para cuando el
    contador de 0x33CD llega a cero, desde DENTRO del bucle."""
    out = bytearray()
    hl = 0
    cont = EXPANDE
    while True:
        if hl + 1 >= len(paquete):
            return bytes(out), False      # se quedo sin de donde leer
        b = paquete[hl]; hl += 1
        a = paquete[hl]; hl += 1
        n = b if b else 256
        for _ in range(n):
            out.append(a)
            cont -= 1
            if cont == 0:
                return bytes(out), True


def ronda(mapa):
    paquete = empaqueta(mapa)
    # COMPRIME copia de vuelta SIEMPRE 0x16EC bytes, y DESCOMPRIME lee 0x16ED:
    # el byte de mas sale de lo que hubiera ahi antes, que aqui se rellena con
    # ceros porque lo que importa es a partir de donde se rompe.
    recortado = paquete[:VUELTA] + b"\x00" * max(0, LEE - VUELTA)
    vuelto, entero = descomprime(recortado)
    return paquete, vuelto, entero


def informa(nombre, mapa):
    paquete, vuelto, entero = ronda(mapa)
    marcas = sum(1 for x in mapa if x & 0x20)
    perdidas = 0
    colmin, colmax = 999, -1
    for i in range(LARGO):
        v = vuelto[i] if i < len(vuelto) else None
        if v != mapa[i]:
            perdidas += 1
            c = i // 102 - 1
            colmin = min(colmin, c)
            colmax = max(colmax, c)
    print("%-28s marcas=%5d  empaquetado=%5d B (%+d sobre %d)  celdas que NO vuelven=%5d %s"
          % (nombre, marcas, len(paquete), len(paquete) - VUELTA, VUELTA, perdidas,
             "" if not perdidas else "(columnas %d..%d)" % (colmin, colmax)))


if __name__ == "__main__":
    for f in sys.argv[1:]:
        d = open(f, "rb").read()
        informa(f + "  tal cual", d)
        informa(f + "  sin el bit 5", bytes(x & 0xDF for x in d))
