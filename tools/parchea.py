#!/usr/bin/env python3
"""Aplica el parche de Araubi a War in Middle Earth y reconstruye la cinta.

COMO FUNCIONA. El desensamblado no se toca: se parte de los CUERPOS que saca
`make extract` a work/*.raw (los mismos bytes de la cinta, sin la envoltura del
formato Spectrum). Cada cambio es una entrada de la TABLA de mas abajo:

    bloque   en cual de los cuerpos cae (aqui todo es 'medio', 0x5E00)
    dir      la direccion de EJECUCION del primer byte que cambia
    orig     los bytes que DEBE haber ahi (si no, se aborta: no es esta cinta)
    nuevo    los bytes que se escriben (SIEMPRE la misma longitud que orig)
    motivo   por que

La longitud de orig y nuevo es igual byte a byte: nada se desplaza. Antes de
escribir se comprueba que orig es lo que hay; despues se comprueba que, fuera de
los rangos de la tabla, el cuerpo es identico al original. Asi el parche no
puede tocar nada por accidente.

LOS GRAFICOS NO SE ESCRIBEN EN LA TABLA: SE DIBUJAN. Los 128 tiles del mapa
-toda la tabla de 0x9E00, no solo los del Ojo de Sauron- viven en un PNG de
128x64, src/parche/tiles_del_mapa.png, con cada tile de 8x8 a tamano real y sin
separacion. Se edita con cualquier editor de imagenes; al hacer `make parche` se
compara con lo que trae la cinta y cada casilla repintada sale sola como una
entrada mas de la tabla, del grupo "graficos". Si el lienzo no se toca, no
aparece ni una entrada de mas. Las reglas del ZX que hay que respetar al pintar
-dos colores por casilla y los dos del mismo brillo- y la ida y vuelta exacta
estan explicadas en tools/tiles_del_mapa.py.

Con los cuerpos ya parcheados se vuelve a montar la cinta: cada bloque del ZX
Spectrum se reenvuelve con su bandera delante y su XOR detras (la unica
verificacion de integridad que trae la cinta), y tools/tsx_build.py arma el TSX.

LOS TRES FORMATOS DE TEXTO del juego, que es lo que manda en el grupo "textos":

  1. La tabla de SITIOS del mapa (0x7A5E, la recorre BUSCA_EL_SITIO en 0x6E50).
     Cada registro es [x][y][2+ancho*filas][ancho<<4 | filas][texto], sin
     terminador: el largo sale del cuarto byte, que ademas es el tamano del
     cartel que dibuja VENTANA_DEL_SITIO. Por eso un toponimo nuevo tiene que
     medir EXACTAMENTE ancho*filas, y los de dos filas se reparten fila a fila
     ("Cavada " + "Grande " se lee "Cavada Grande" en un cartel de 7x2).

  2. Las LISTAS de cadenas pegadas con el bit 7 en su ultima letra: las razas en
     plural (0x7D06) y en singular (0x7D39), los carteles de bando (0x7D6A) y
     los adverbios (0x7D9A). Se llega a la cadena N contando bits 7 desde la
     base (SALTA_B_TEXTOS, 0x6E98), asi que DENTRO de una lista las cadenas
     pueden cambiar de largo mientras el total no cambie; el total si es
     intocable, porque la base de la lista siguiente es una direccion absoluta
     del codigo.

  3. Los NOMBRES de las 24 unidades con nombre propio (0x6B46), separados por
     0xB7 y copiados hasta ese separador (0x6E23, 0x6F38).

Uso:  parchea.py [work] [salida.tsx]
"""
import os
import shutil
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import tiles_del_mapa  # noqa: E402
import tsx_build  # noqa: E402

# EL LIENZO DE LOS GRAFICOS. Los 128 tiles del mapa, de 8x8, puestos en un PNG
# de 128x64 sin escalar y sin separacion: un pixel del PNG es un pixel del
# juego. Se edita con cualquier editor y de ahi salen, solas, las entradas del
# grupo "graficos" de la tabla (ver parches_de_graficos y tools/tiles_del_mapa.py).
PNG_TILES = os.path.join(RAIZ, "src", "parche", "tiles_del_mapa.png")

# Los cuatro bloques del ZX Spectrum: nombre del cuerpo -> (fichero de bloque en
# el manifiesto, direccion de ejecucion). El cuerpo va envuelto [bandera][cuerpo][XOR].
BLOQUES_SPECTRUM = {
    "pantalla": ("block08.raw", 0x88B8),
    "bajo":     ("block09.raw", 0x0190),
    "medio":    ("block10.raw", 0x5E00),
    "alto":     ("block11.raw", 0x9E00),
}

# La rutina nueva "MUESTRA LOS VALORES" (src/parche/ficha_valores.asm), ensamblada
# con pasmo a org 0x6600. Se guarda aqui para que la tabla sea autocontenida y el
# test pueda reensamblar el .asm y comprobar que sigue dando exactamente esto.
RUTINA_FICHA = bytes.fromhex(
    "c5d53aad6e5f16c21a21737ccd137116c31a218b7ccd137116c01acd967021a37c"
    "cd137116c01ae60f21bb7ccd137116c11ae60f21d37ccd137116c11acd967021eb"
    "7ccd1371d1c121bd5fc9")

# Los 76 bytes originales de 0x6600: el arranque del motor del altavoz del ZX,
# codigo muerto (nadie lo llama; los efectos acaban en el ret de 0x65FF).
ORIG_FICHA = bytes.fromhex(
    "87c6656fce6395677e23666fcd1467ed538066cd1467ed53ba66cd1467ed53ae66"
    "cd1467ed53e766cd1467ed538366cd1467ed53bd66cd1467ed53c666cd1467ed53"
    "0667cd1467ed538c66cd")

# La segunda tanda (src/parche/icono_enemigo.asm), ensamblada a org 0x664C:
# el Ojo de Sauron para las enemigas y el plazo del Anillo. Va justo detras de
# la rutina de los valores, en la misma zona muerta del motor del altavoz.
RUTINA_ICONO = bytes.fromhex(
    "cd0881cbfe79fe78d8cbeec9cb6f2806218566c32077cb773e11c217773e15c317773e"
    "5f32467cc5d5e53a338321437ccd1371e1d1c13e5fc9eff0f1f2")

# Los 61 bytes originales de 0x664C: mas motor de altavoz, igual de muerto.
ORIG_ICONO = bytes.fromhex(
    "1467ed53f9667ef52a80667cb52824ed4bba6678b1281c227a66af0808d3feee10082b"
    "7db4c26e660b79b02806210000c36866210000110000193e00b7")

# Los cuatro tiles del Ojo de Sauron. Nueve bytes cada uno: ocho de dibujo y el
# atributo del ZX detras, 0x38 = tinta negra sobre papel blanco, el mismo que
# usan las unidades aliadas.
#
# ESTO YA NO SE ESCRIBE DESDE AQUI. El dibujo vive en el lienzo, PNG_TILES, y
# las entradas del parche salen de compararlo con la cinta. Este hexadecimal se
# queda como CONTROL: es lo que el lienzo tiene que seguir dando, y el test
# test_el_lienzo_sigue_trayendo_el_ojo lo comprueba. Si alguien rehace el lienzo
# desde la cinta y se lleva el Ojo por delante, el test se pone rojo.
TILES_OJO = bytes.fromhex(
    "011608502041418138806014888482c2c138814140215108060938c1c282040a14609038")

# ==========================================================================
# LA TABLA DE PARCHES
# ==========================================================================
PARCHES = [
    # ---- (1) UNIDADES ENEMIGAS VISIBLES ----------------------------------
    # RECENTRA_EL_MAPA (0x7FAC) borra el bit 7 ("aqui hay alguien") de todo el
    # mapa y lo vuelve a poner unidad a unidad, PERO el bucle para en la unidad
    # 0x78 (cp 078h en 0x7FD0): las 0x78-0xFF, que son del otro bando, nunca se
    # siembran, y por eso no se dibujan. Cambiando el tope 0x78 -> 0x00 el bucle
    # recorre las 256 unidades y siembra tambien las enemigas.
    dict(grupo="visibilidad", bloque="medio", dir=0x7FD1, orig="78", nuevo="00",
         motivo="siembra bit7: el bucle de MARCA_UNA_UNIDAD_7FB2 llega a 0xFF, no a 0x78"),

    # ---- (2) VALORES NUMERICOS DE LA UNIDAD (y con ellos, el del Anillo) ---
    # Trampolin en ARMA_LA_FICHA: donde hacia `ld hl,0x5FBD` (21 BD 5F) justo
    # antes de pintar la ficha, ahora llama a la rutina nueva de 0x6600, que
    # escribe los seis atributos en numeros y termina rehaciendo ese ld hl.
    dict(grupo="valores", bloque="medio", dir=0x708A, orig="21bd5f", nuevo="cd0066",
         motivo="trampolin: call MUESTRA_LOS_VALORES (0x6600) antes de PINTA_LA_VENTANA"),
    # La rutina, escrita sobre el motor de sonido muerto de 0x6600.
    dict(grupo="valores", bloque="medio", dir=0x6600, orig=ORIG_FICHA.hex(),
         nuevo=RUTINA_FICHA.hex(),
         motivo="MUESTRA_LOS_VALORES: 0xC000/0xC100/0xC200/0xC300 en cifras en la ficha"),
    # ---- (3) EL OJO DE SAURON PARA LAS ENEMIGAS --------------------------
    # El juego elige el dibujo de una casilla mirando SOLO su byte de mapa, asi
    # que al dibujar no sabe de que bando es. El bit 5 de ese byte esta libre
    # (medido: cero usos en las 13.260 casillas), y ahi va la marca de bando.
    dict(grupo="icono", bloque="medio", dir=0x664C, orig=ORIG_ICONO.hex(),
         nuevo=RUTINA_ICONO.hex(),
         motivo="siembra con bando, dibujo con bando y el plazo del Anillo"),
    # La siembra: donde hacia `call CELDA_DEL_MAPA` + `set 7,(hl)`, ahora llama
    # a SIEMBRA_CON_BANDO, que ademas pone el bit 5 si la unidad es >= 0x78.
    dict(grupo="icono", bloque="medio", dir=0x7FC9, orig="cd0881cbfe", nuevo="cd4c660000",
         motivo="call SIEMBRA_CON_BANDO (0x664C): bit 7 siempre, bit 5 si es enemiga"),
    # El dibujo: el cuerpo de PINTA_LA_UNIDAD desde 0x770A se va a la rutina
    # nueva, que mira el bit 5 antes que el 6. El `or a` / `ret p` de 0x7708 se
    # queda donde estaba.
    dict(grupo="icono", bloque="medio", dir=0x770A, orig="cb773e1120073e151803",
         nuevo="c3586600000000000000",
         motivo="jp DIBUJO_SEGUN_BANDO (0x6658): el Ojo de Sauron si la casilla es enemiga"),
    # Y el dibujo del Ojo -los tiles 111 a 114, que en la cinta estaban a cero-
    # NO va aqui: sale del lienzo, como los otros 124. Ver parches_de_graficos.

    # ---- (4) EL PLAZO QUE QUEDA, AL LADO DEL ANILLO ----------------------
    # El reloj baja un mes el operando de 0x8333 (255 al empezar) y a cero salta
    # a DERROTA, con el mensaje "El Anillo corrompe al que lo usa.". Donde
    # MARCA_AL_PORTADOR escribia solo el anillo en 0x7C46, ahora llama a
    # ANILLO_CON_PLAZO, que escribe tambien ese numero en las tres columnas de
    # su izquierda (0x7C43).
    #
    # OJO CON LA DIRECCION. ANILLO_CON_PLAZO empieza en 0x666E, no en 0x666D:
    # 0x664C + 12 (SIEMBRA_CON_BANDO) + 10 + 12 (las dos mitades de
    # DIBUJO_SEGUN_BANDO) = 34 bytes. La primera version puso 0x666D, un byte
    # antes, que es el 0x77 con que acaba el `jp 07717h` de la linea anterior:
    # o sea un `ld (hl),a` de propina antes de entrar en la rutina. Con el HL
    # que traia MARCA_AL_PORTADOR -la tabla de nombres de 0x6B46- eso escribia
    # el A del momento (0x10) encima del separador 0xB7 de un nombre, uno por
    # cada ficha pintada, hasta que el panel entero salia en basura. Es el bug
    # que reporto Araubi. El test lo comprueba ahora contra los simbolos que
    # saca pasmo, no contra un numero escrito a mano.
    dict(grupo="anillo", bloque="medio", dir=0x6F77, orig="3e5f32467c", nuevo="cd6e660000",
         motivo="call ANILLO_CON_PLAZO (0x666E): el anillo y los meses que quedan"),

    # ---- (5) LOS TEXTOS EN ESPANOL ---------------------------------------
    # La conversion dejo los toponimos del mapa en ingles y tres nombres de raza
    # a medio traducir. Aqui van con los nombres de la traduccion de Tolkien al
    # castellano. NINGUNA cadena cambia de longitud, que es lo que permite que
    # nada se desplace. Ver "Los tres formatos de texto" arriba.
    #
    # (5a) La tabla de sitios de 0x7A5E. Cada registro es
    #      [x][y][2+ancho*filas][ancho<<4 | filas][texto], y el texto se pinta en
    #      un cartel de ancho x filas: el largo del texto TIENE que seguir siendo
    #      ancho*filas, asi que las cadenas cortas se rellenan con espacios y las
    #      de dos filas se reparten fila a fila.
    dict(grupo="textos", bloque="medio", dir=0x7A79,
         orig="4d6f72616e6e6f6e", nuevo="507565727461204e",
         motivo="sitio 8x1: 'Morannon' -> 'Puerta N'"),
    dict(grupo="textos", bloque="medio", dir=0x7AA5,
         orig="526976656e64656c6c", nuevo="526976656e64656c20",
         motivo="sitio 9x1: 'Rivendell' -> 'Rivendel ' (8 letras + un espacio)"),
    dict(grupo="textos", bloque="medio", dir=0x7AB2,
         orig="4973656e6d6f75746865", nuevo="47612e2048696572726f",
         motivo="sitio 10x1: 'Isenmouthe' -> 'Ga. Hierro'"),
    dict(grupo="textos", bloque="medio", dir=0x7B0D,
         orig="44616c65", nuevo="56616c65",
         motivo="sitio 4x1: 'Dale' -> 'Vale'"),
    dict(grupo="textos", bloque="medio", dir=0x7B28,
         orig="4275636b6c616e64", nuevo="4c6f7347616d6f73",
         motivo="sitio 8x1: 'Buckland' -> 'LosGamos'"),
    dict(grupo="textos", bloque="medio", dir=0x7B34,
         orig="42797761746572", nuevo="44656c61677561",
         motivo="sitio 7x1: 'Bywater' -> 'Delagua'"),
    dict(grupo="textos", bloque="medio", dir=0x7B4B,
         orig="4d696368656c2044656c76696e67", nuevo="436176616461204772616e646520",
         motivo="sitio 7x2: 'Michel '/'Delving' -> 'Cavada '/'Grande '"),
    dict(grupo="textos", bloque="medio", dir=0x7B5D,
         orig="46617220446f776e73", nuevo="517565627261646173",
         motivo="sitio 9x1: 'Far Downs' -> 'Quebradas'"),
    dict(grupo="textos", bloque="medio", dir=0x7B7F,
         orig="48656c6d734465657020", nuevo="416269736d48656c6d20",
         motivo="sitio 5x2: 'Helms'/'Deep ' -> 'Abism'/'Helm '"),
    dict(grupo="textos", bloque="medio", dir=0x7BC7,
         orig="477265792020486176656e73", nuevo="50746f732020477269736573",
         motivo="sitio 6x2: 'Grey  '/'Havens' -> 'Ptos  '/'Grises'"),
    # (5b) La lista de los 24 nombres de 0x6B46, separados por 0xB7.
    dict(grupo="textos", bloque="medio", dir=0x6BA5,
         orig="4272616e6420494949", nuevo="426172646f20494949",
         motivo="nombre 9 letras: 'Brand III' -> 'Bardo III'"),
    # (5c) El cuarto adjetivo de la ficha, al que apunta 0x6FEF (0x7DEF, con su
    #      espacio delante); acaba con el bit 7 en la ultima letra.
    dict(grupo="textos", bloque="medio", dir=0x7DF0,
         orig="56616c696f73ef", nuevo="496e74656772ef",
         motivo="adjetivo de la ficha: 'Valioso' -> 'Integro'"),
    # (5d) Las dos tablas de razas. Se escriben ENTERAS de una vez porque las
    #      cadenas van pegadas y se llega a cada una contando bits 7 desde la
    #      base (SALTA_B_TEXTOS, 0x6E98): dentro de la tabla las cadenas pueden
    #      cambiar de largo mientras el TOTAL no cambie, y ese total no puede
    #      cambiar porque justo detras empieza la tabla siguiente.
    #      Plural (base 0x7D06, la lee FORMACION_SIN_NOMBRE en 0x6F57), entradas
    #      0..7; la 8 ('Gollum') no se toca y cierra en 0x7D39, que es la base de
    #      la tabla en singular. 45 bytes antes y 45 despues:
    #      7+6+3+5+7+4+7+6 = 45   ->   5+6+7+5+7+4+7+4 = 45
    dict(grupo="textos", bloque="medio", dir=0x7D07,
         orig="4272756a6f73a04e617a6775ec4875ed456c666ff3456e616e6f73a04f7263f3"
              "486f62626974f34272756a6fa0",
         nuevo="4d61676ff34e617a6775ec486f6d627265f3456c666ff3456e616e6f73a04f7263f3"
               "486f62626974f34d6167ef",
         motivo="razas en plural: 'Brujos'->'Magos', 'Hum'->'Hombres', 'Brujo'->'Mago'"),
    #      Singular (base 0x7D39, la lee NOMBRE_DEL_TIPO en 0x6DF6), entradas
    #      0..8; la 9 ('Mujer') no se toca y cierra en 0x7D6A, que es la base de
    #      los carteles de bando. 44 bytes antes y 44 despues:
    #      6+6+3+3+5+3+6+6+6 = 44   ->   4+6+6+4+5+3+6+4+6 = 44
    dict(grupo="textos", bloque="medio", dir=0x7D3A,
         orig="4272756a6fa04e617a6775ec4875ed456ce6456e616eef4f72e3486f626269f4"
              "4272756a6fa0476f6c6c75ed",
         nuevo="4d6167ef4e617a6775ec486f6d6272e5456c66ef456e616eef4f72e3486f626269f4"
               "4d6167ef476f6c6c75ed",
         motivo="razas en singular: 'Brujo'->'Mago', 'Hum'->'Hombre', 'Elf'->'Elfo'"),
]


def parches_de_graficos(cuerpo_alto, png=PNG_TILES, avisos=None):
    """Las entradas del grupo "graficos", sacadas de comparar el lienzo con la cinta.

    LOS 128 TILES DEL MAPA SE EDITAN AQUI, no solo los cuatro del Ojo. El lienzo
    PNG_TILES lleva la tabla entera de 0x9E00 dibujada a tamano real; se compara
    casilla por casilla con lo que trae la cinta y cada trozo que no coincide
    sale como una entrada mas de la tabla, con su `orig` y su `nuevo` de la
    misma longitud, igual que las escritas a mano.

    Una casilla que se vea exactamente igual que la de la cinta devuelve SUS
    BYTES de siempre, asi que si no se toca el lienzo no aparece ni una entrada
    de mas. Hoy solo salen los 36 bytes del Ojo de Sauron.
    """
    if not os.path.exists(png):
        return []
    tabla = tiles_del_mapa.tabla_del_bloque(cuerpo_alto)
    nueva, avs = tiles_del_mapa.lee_lienzo(png, tabla)
    if avisos is not None:
        avisos.extend(avs)
    fuera = []
    for off, viejo, nuevo in tiles_del_mapa.tramos(tabla, nueva):
        primero = off // tiles_del_mapa.PASO
        ultimo = (off + len(nuevo) - 1) // tiles_del_mapa.PASO
        cual = ("el tile %d" % primero if primero == ultimo
                else "los tiles %d-%d" % (primero, ultimo))
        fuera.append(dict(
            grupo="graficos", bloque="alto",
            dir=tiles_del_mapa.TABLA_INI + off,
            orig=viejo.hex(), nuevo=nuevo.hex(),
            motivo="%s del mapa, dibujados en src/parche/tiles_del_mapa.png" % cual))
    return fuera


def tabla_de_parches(cuerpo_alto, png=PNG_TILES, avisos=None):
    """La tabla entera: lo escrito a mano mas lo que sale del lienzo."""
    return PARCHES + parches_de_graficos(cuerpo_alto, png, avisos)


def aplica(cuerpos):
    """Aplica la tabla sobre un dict {nombre: bytearray}. Devuelve rangos tocados.

    Los graficos se leen del lienzo ANTES de escribir nada, con el cuerpo alto
    todavia tal cual vino de la cinta: es la referencia contra la que se decide
    que casillas han cambiado.
    """
    rangos = {}
    for p in tabla_de_parches(cuerpos["alto"]):
        nombre = p["bloque"]
        org = BLOQUES_SPECTRUM[nombre][1]
        cuerpo = cuerpos[nombre]
        orig = bytes.fromhex(p["orig"])
        nuevo = bytes.fromhex(p["nuevo"])
        if len(orig) != len(nuevo):
            raise SystemExit("parche 0x%04X: orig(%d) y nuevo(%d) miden distinto"
                             % (p["dir"], len(orig), len(nuevo)))
        off = p["dir"] - org
        if off < 0 or off + len(orig) > len(cuerpo):
            raise SystemExit("parche 0x%04X: se sale del bloque %s" % (p["dir"], nombre))
        hay = bytes(cuerpo[off:off + len(orig)])
        if hay != orig:
            raise SystemExit(
                "parche 0x%04X (%s): esperaba %s pero hay %s. No es esta cinta."
                % (p["dir"], nombre, orig.hex(), hay.hex()))
        cuerpo[off:off + len(nuevo)] = nuevo
        rangos.setdefault(nombre, []).append((off, off + len(nuevo)))
    return rangos


def reenvuelve_spectrum(cuerpo, bandera):
    """[bandera] + cuerpo + [XOR de todo lo anterior]."""
    x = bandera
    for c in cuerpo:
        x ^= c
    return bytes([bandera]) + bytes(cuerpo) + bytes([x])


def main(argv):
    work = argv[1] if len(argv) > 1 else os.path.join(RAIZ, "work")
    salida = argv[2] if len(argv) > 2 else os.path.join(RAIZ, "war_parche.tsx")
    ext = os.path.join(RAIZ, "extracted")
    if not os.path.exists(os.path.join(work, "medio.raw")):
        raise SystemExit("no hay %s/medio.raw; ejecuta antes `make extract`" % work)

    # 1. Cargar los cuerpos originales y aplicar la tabla sobre una copia.
    origs = {n: open(os.path.join(work, n + ".raw"), "rb").read()
             for n in BLOQUES_SPECTRUM}
    cuerpos = {n: bytearray(b) for n, b in origs.items()}
    rangos = aplica(cuerpos)

    # 2. Comprobar que SOLO ha cambiado lo de la tabla.
    print("== parches aplicados ==")
    avisos = []
    tabla = tabla_de_parches(origs["alto"], avisos=avisos)
    for a in avisos:
        print(a)
    total = 0
    for grupo in ("visibilidad", "valores", "icono", "anillo", "graficos", "textos"):
        gp = [p for p in tabla if p["grupo"] == grupo]
        if not gp:
            continue
        print("  [%s]" % grupo)
        for p in gp:
            print("    0x%04X  %-6s %2d B  %s -> %s  %s"
                  % (p["dir"], p["bloque"], len(bytes.fromhex(p["orig"])),
                     p["orig"], p["nuevo"], p["motivo"]))
            total += len(bytes.fromhex(p["nuevo"]))
    fuera = 0
    for n in BLOQUES_SPECTRUM:
        o, c = origs[n], cuerpos[n]
        permitido = rangos.get(n, [])
        for i in range(len(o)):
            if o[i] == c[i]:
                continue
            if not any(a <= i < b for a, b in permitido):
                fuera += 1
    if fuera:
        raise SystemExit("FALLO: %d bytes cambiados FUERA de la tabla" % fuera)
    print("  %d bytes cambiados, 0 fuera de la tabla" % total)

    # 3. Escribir los cuerpos parcheados.
    pdir = os.path.join(work, "parche")
    os.makedirs(pdir, exist_ok=True)
    for n, c in cuerpos.items():
        open(os.path.join(pdir, n + ".raw"), "wb").write(c)

    # 4. Reconstruir la cinta: reenvolver los bloques Spectrum y montar el TSX.
    tape = os.path.join(pdir, "tape")
    os.makedirs(tape, exist_ok=True)
    for f in os.listdir(ext):
        if f.startswith("block") and f.endswith(".raw"):
            shutil.copy(os.path.join(ext, f), os.path.join(tape, f))
    for n, (fichero, _org) in BLOQUES_SPECTRUM.items():
        original = open(os.path.join(ext, fichero), "rb").read()
        bandera = original[0]
        nuevo = reenvuelve_spectrum(cuerpos[n], bandera)
        assert len(nuevo) == len(original), "%s cambio de tamano" % n
        open(os.path.join(tape, fichero), "wb").write(nuevo)
    tsx_build.build(os.path.join(ext, "manifest.json"), salida, tape)
    print("cinta parcheada -> %s" % salida)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
