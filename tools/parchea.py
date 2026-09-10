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

LOS GRAFICOS NO SE ESCRIBEN EN LA TABLA: SE DIBUJAN. Los TRES juegos de dibujos
del bloque alto viven en sendos PNG dentro de src/parche/, a tamano real y sin
separacion:

    tiles_del_mapa.png      128 tiles de 8x8   (0x9E00)   128x64
    sprites_de_batalla.png  176 sprites 16x8   (0xA2E8)   176x128
    fuente.png              128 caracteres 8x8 (0xC800)   128x64

Se editan con cualquier editor de imagenes; al hacer `make parche` se comparan
con lo que trae la cinta y cada dibujo repintado sale solo como una entrada mas
de la tabla, del grupo "graficos". Si los lienzos no se tocan, no aparece ni una
entrada de mas. Las reglas del ZX que hay que respetar al pintar un tile -dos
colores por casilla y los dos del mismo brillo- y la ida y vuelta exacta estan
explicadas en tools/lienzos.py.

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
import lienzos  # noqa: E402
import tsx_build  # noqa: E402

# LOS LIENZOS. Los graficos del bloque alto -los 128 tiles del mapa, los 176
# sprites de batalla y los 128 caracteres de la fuente- puestos en tres PNG a
# tamano real, sin escalar y sin separacion: un pixel del PNG es un pixel del
# juego. Se editan con cualquier editor y de ahi salen, solas, las entradas del
# grupo "graficos" de la tabla (ver parches_de_graficos y tools/lienzos.py).
CARPETA_LIENZOS = os.path.join(RAIZ, "src", "parche")

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
# atributo del ZX detras. El Ojo esta REPINTADO desde el 2026-09-10: ya no es
# negro sobre blanco, es el ojo en llamas en rojo oscuro -atributo 0x3A, tinta
# roja sobre papel blanco, y 0x17 en el tile 111, donde el rojo es mayoria y se
# queda de papel-. En pantalla ese rojo del Spectrum sale como el color 6 del
# MSX, que es el rojo oscuro: ver la nota de las dos tablas en tools/lienzos.py.
#
# ESTO YA NO SE ESCRIBE DESDE AQUI. El dibujo vive en src/parche/tiles_del_mapa.png
# y las entradas del parche salen de compararlo con la cinta. Este hexadecimal se
# queda como CONTROL: es lo que el lienzo tiene que seguir dando, y el test
# test_el_lienzo_sigue_trayendo_el_ojo lo comprueba. Si alguien rehace el lienzo
# desde la cinta y se lleva el Ojo por delante, el test se pone rojo.
TILES_OJO = bytes.fromhex(
    "e6cccb861694dc4c1760b8742018ae9d983a7363390d583f0d003a988c363d78d830003a")

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
    # NO va aqui: sale del lienzo, como el resto de los graficos del bloque
    # alto. Ver parches_de_graficos.

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
    # ---- (5) EL PAPEL DEL TEXTO, DEL BLANCO AL KHAKI DEL MARCO -----------
    # UN_CARACTER_NORMAL (0x7616) pinta TODOS los caracteres de la fuente con el
    # mismo atributo fijo, `ld a,078h` en 0x763E: tinta 0 (negra), papel 7
    # (blanco) y el bit 6, el BRIGHT del Spectrum. En el MSX ese atributo lo
    # traduce ATRIBUTO_A_COLOR (0x049F) a negro sobre blanco.
    #
    # Con 0x70 el papel pasa a ser el 6 (amarillo) CON brillo, que la tabla de
    # 0x04D6 manda al color 11 del MSX: el amarillo claro. Es EXACTAMENTE el
    # mismo color con el que estan pintados los marcos en el lienzo nuevo, asi
    # que el texto y su caja dejan de ser dos cosas distintas.
    #
    # OJO, ES GLOBAL: por aqui pasa todo el texto del juego -el menu, los
    # rotulos, la ficha y los mensajes de batalla-, no solo los paneles. Y se
    # lleva por delante tambien los ESPACIOS, que es lo que rellena el interior
    # de los carteles: por eso la caja queda de un khaki entero y no un halo
    # detras de cada letra.
    dict(grupo="papel", bloque="medio", dir=0x763F, orig="78", nuevo="70",
         motivo="atributo del texto: papel blanco -> papel amarillo con brillo "
                "(color 11 del MSX), el mismo de los marcos"),

    # ---- (6) LOS ADJETIVOS DE LA FICHA -----------------------------------
    # Los seis atributos se pintan como <adverbio><adjetivo>"," en su fila del
    # buffer de la ficha (0x7C17, 24 columnas), y cada adjetivo lo carga el
    # codigo con su PROPIO `ld hl` absoluto: 0x704B, 0x7061, 0x7006, 0x6FEF,
    # 0x701E y 0x7035. Eso es lo que permite alargarlos: no van por una lista
    # que haya que recorrer, asi que basta con moverlos y cambiar el puntero.
    #
    # EL LIMITE ES LA PANTALLA, no la cinta. El adverbio mas largo de la lista
    # de 0x7D9A es " No es muy " (11 caracteres) y MUESTRA_LOS_VALORES escribe
    # el numero en la columna 20, asi que del adverbio al numero quedan nueve
    # columnas. Un adjetivo de ocho letras (nueve con su espacio de delante)
    # deja la coma justo en la columna 20 y el numero se la come: es lo que ya
    # le pasa hoy a "Energico", asi que ninguno de estos lo empeora.
    #
    # "Firme" cabe en el hueco de "Habil" -las dos son de cinco letras y el
    # hueco trae tres espacios de relleno-, asi que ese se cambia en su sitio.
    dict(grupo="adjetivos", bloque="medio", dir=0x7DE6,
         orig="20486162696c2020a0", nuevo="204669726d652020a0",
         motivo="adjetivo 3: 'Habil' -> 'Firme', en su hueco de nueve bytes"),

    # Los otros tres crecen seis bytes en total y no caben donde estaban, asi
    # que se llevan al motor de sonido del Spectrum, que esta muerto (0x6600 -
    # 0x6713, no lo llama nadie) y del que el parche ya gasta hasta 0x6688.
    # Quedan 139 bytes libres; estos ocupan 25, de 0x6689 a 0x66A1.
    dict(grupo="adjetivos", bloque="medio", dir=0x6689,
         orig="286d110000ed5219381a0e002a8066ed5b83663effaa573eff",
         nuevo="2056697274756f73ef2056616c69656e74e5204675657274e5",
         motivo="las tres cadenas nuevas: ' Virtuoso', ' Valiente' y ' Fuerte'"),
    # Y sus tres punteros. Cada uno es el operando de un `ld hl`, dos bytes.
    dict(grupo="adjetivos", bloque="medio", dir=0x6FF0, orig="ef7d", nuevo="8966",
         motivo="adjetivo 4 (0x6FEF): 'Valioso' -> 'Virtuoso' en 0x6689"),
    dict(grupo="adjetivos", bloque="medio", dir=0x701F, orig="f77d", nuevo="9266",
         motivo="adjetivo 5 (0x701E): 'Duro' -> 'Valiente' en 0x6692"),
    dict(grupo="adjetivos", bloque="medio", dir=0x7036, orig="fc7d", nuevo="9b66",
         motivo="adjetivo 6 (0x7035): 'Bravo' -> 'Fuerte' en 0x669B"),

    # ---- (7) LA ULTIMA LINEA DE LA FICHA: "Aliado Comunidad" -------------
    # La fila 9 del buffer (0x7CEF, 24 columnas) trae de la cinta la plantilla
    # "Forma una alianza" y el codigo le escribe encima, en la COLUMNA 10, una
    # de cuatro palabras de la lista de 0x7D6B (`and 003h` en 0x7070 elige
    # cual), rellenando de espacios lo que sobre. De ahi salen hoy
    # "Forma una  Sociedad", "Forma una -" y dos veces "Forma una  union".
    #
    # Para poner "Aliado Comunidad" no basta con cambiar la palabra: "Forma una"
    # esta en la plantilla y se veria delante. Y no vale cambiar la plantilla,
    # porque las otras tres opciones la comparten y quedarian en "Aliado union".
    #
    # La salida es mover la lista ENTERA a la zona muerta y que cada entrada
    # traiga LA FRASE COMPLETA, escribiendola desde la columna 0. Asi la primera
    # dice lo que se quiere y las otras tres se dejan EXACTAMENTE como se ven
    # hoy, con sus dos espacios y todo. Son dos punteros de dos bytes.
    dict(grupo="textos", bloque="medio", dir=0x66A2,
         orig="ab5f13ed538366793287661100007caa677dab6f228066210000110000193e00"
              "b72840110000ed52381a0e002aba66ed5bbd663effaa573effab5f13ed53bd66",
         nuevo="416c6961646f2061206c6120436f6d756e696461e4466f726d6120756e6120ad"
               "466f726d6120756e612020756e696fee466f726d6120756e612020756e696fee",
         motivo="las cuatro frases enteras de la fila 9: 'Aliado a la Comunidad' y "
                "las otras tres tal y como se ven hoy"),
    dict(grupo="textos", bloque="medio", dir=0x7074, orig="6a7d", nuevo="a266",
         codigo=True,
         motivo="0x7073: la lista de la fila 9 pasa de 0x7D6A a 0x66A2"),
    dict(grupo="textos", bloque="medio", dir=0x707A, orig="f97c", nuevo="ef7c",
         codigo=True,
         motivo="0x7079: se escribe desde la columna 0 (0x7CEF), no desde la 10"),

    #
    # (5a) La tabla de sitios de 0x7A5E. Cada registro es
    #      [x][y][2+ancho*filas][ancho<<4 | filas][texto], y el texto se pinta en
    #      un cartel de ancho x filas: el largo del texto TIENE que seguir siendo
    #      ancho*filas, asi que las cadenas cortas se rellenan con espacios y las
    #      de dos filas se reparten fila a fila.
    dict(grupo="textos", bloque="medio", dir=0x7A79,
         orig="4d6f72616e6e6f6e", nuevo="507565727461204e",
         motivo="sitio 8x1: 'Morannon' -> 'Puerta N'"),
    # "Dale" -> "Valle" cuesta un byte que en su registro no hay: el sitio es
    # 4x1 y son cinco letras. El byte se lo presta "Rivendel ", que llevaba un
    # espacio de relleno de cuando el parche acorto "Rivendell" para que
    # cupieran nueve; ahora es un cartel de 8x1 y ese espacio sobra.
    #
    # Los registros van pegados y el juego los recorre sumando su largo, asi que
    # encoger uno CORRE todos los de detras. Por eso esto no son dos parches
    # sueltos sino UNO que reescribe el tramo entero de Rivendel a Dale -nueve
    # registros, 112 bytes antes y 112 despues-, con los siete de en medio tal y
    # como estaban. Los parches de "Rivendell" y de "Isenmouthe" se han metido
    # aqui dentro por la misma razon: sus direcciones se movian.
    #
    # SIN COMPROBAR en pantalla: el cartel de Valle pasa de cuatro columnas a
    # cinco y el de Rivendel de nueve a ocho, y no se ha mirado si el [x][y] del
    # registro es la esquina del cartel o su centro.
    dict(grupo="textos", bloque="medio", dir=0x7AA1, registros=True,
         orig="45170b91526976656e64656c6c643a0ca14973656e6d6f757468656f400b9142"
              "617261642d44757263410e62436972697468556e676f6c20613c0a8144757274"
              "68616e6754270e62446f6c20202047756c64757244630751556d626172141e09"
              "714861726c6f6e64640f064144616c65",
         nuevo="45170a81526976656e64656c643a0ca147612e2048696572726f6f400b914261"
               "7261642d44757263410e62436972697468556e676f6c20613c0a814475727468"
               "616e6754270e62446f6c20202047756c64757244630751556d626172141e0971"
               "4861726c6f6e64640f075156616c6c65",
         motivo="el tramo de nueve sitios: 'Rivendell'->'Rivendel' (8x1), "
                "'Isenmouthe'->'Ga. Hierro' y 'Dale'->'Valle' (5x1)"),

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


def parches_de_graficos(cuerpo_alto, carpeta=CARPETA_LIENZOS, avisos=None):
    """Las entradas del grupo "graficos", de comparar los lienzos con la cinta.

    AQUI SE EDITAN TODOS LOS GRAFICOS DEL BLOQUE ALTO, no solo los cuatro tiles
    del Ojo: los 128 tiles del mapa, los 176 sprites de batalla y los 128
    caracteres de la fuente. Cada lienzo lleva su tabla entera dibujada a tamano
    real; se compara dibujo por dibujo con lo que trae la cinta y cada trozo que
    no coincide sale como una entrada mas de la tabla, con su `orig` y su
    `nuevo` de la misma longitud, igual que las escritas a mano.

    Un dibujo que se vea exactamente igual que el de la cinta devuelve SUS
    BYTES de siempre, asi que si no se tocan los lienzos no aparece ni una
    entrada de mas. Hoy solo salen los 36 bytes del Ojo de Sauron.
    """
    fuera = []
    for hoja in lienzos.HOJAS:
        png = os.path.join(carpeta, hoja.png)
        if not os.path.exists(png):
            continue
        tabla = lienzos.tabla_del_bloque(cuerpo_alto, hoja)
        nueva, avs = lienzos.lee_lienzo(png, tabla, hoja)
        if avisos is not None:
            avisos.extend(avs)
        for off, viejo, nuevo in lienzos.tramos(tabla, nueva):
            primero = off // hoja.paso
            ultimo = (off + len(nuevo) - 1) // hoja.paso
            fuera.append(dict(
                grupo="graficos", bloque="alto", dir=hoja.ini + off,
                orig=viejo.hex(), nuevo=nuevo.hex(),
                motivo="%s, %s en src/parche/%s"
                       % (hoja.como_se_llaman(primero, ultimo),
                          "dibujado" if primero == ultimo else "dibujados",
                          hoja.png)))
    return fuera


def tabla_de_parches(cuerpo_alto, carpeta=CARPETA_LIENZOS, avisos=None):
    """La tabla entera: lo escrito a mano mas lo que sale de los lienzos."""
    return PARCHES + parches_de_graficos(cuerpo_alto, carpeta, avisos)


def aplica(cuerpos):
    """Aplica la tabla sobre un dict {nombre: bytearray}. Devuelve rangos tocados.

    Los graficos se leen de los lienzos ANTES de escribir nada, con el cuerpo
    alto todavia tal cual vino de la cinta: es la referencia contra la que se
    decide que dibujos han cambiado.
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
    # El orden en que se cuentan los grupos. Si aparece uno que no esta aqui se
    # PARA: antes se saltaba en silencio, y una entrada nueva se aplicaba a la
    # cinta pero no salia en el informe ni entraba en el total.
    orden = ("visibilidad", "valores", "icono", "anillo", "papel", "adjetivos",
             "graficos", "textos")
    sueltos = sorted({p["grupo"] for p in tabla} - set(orden))
    if sueltos:
        raise SystemExit("grupos sin sitio en el informe: %s" % ", ".join(sueltos))
    for grupo in orden:
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
