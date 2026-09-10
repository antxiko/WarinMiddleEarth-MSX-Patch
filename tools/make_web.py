#!/usr/bin/env python3
"""Genera la portada de la web del PARCHE, en los dos idiomas.

Esta web es la del PARCHE, no la del desensamblado: son dos repositorios
distintos y dos webs distintas, como el par del Mahjong Dojo. El desensamblado
explica el juego; esto explica los 1.396 bytes que se le cambian y por que.

El diseno es el compartido por la serie (tools/estilo_web.py) y la pagina sale
autocontenida, con las imagenes embebidas como data URI.

LAS IMAGENES NO SON CAPTURAS DE PANTALLA, y no pueden serlo: el juego resube la
pantalla al VDP sin parar, asi que dos fotos del MISMO estado separadas tres
segundos ya salen con el 37 % de los pixels distintos. Se vuelca el bufer de
pantalla del ZX que el juego lleva en RAM (0x4000 y 0x5800) en un instante fijo
y lo dibuja tools/render_zx.py con la tabla de color del propio cartucho.

Uso: make_web.py <docs/imagenes> <salida.html> <idioma>
"""
import base64
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from estilo_web import ESTILO                                   # noqa: E402

# Las cifras salen de las herramientas, no de escribirlas aqui a ojo:
#   `make parche` -> 1396 bytes cambiados en 130 entradas, 0 fuera de la tabla
#                    (27 escritas a mano, 548 B; 103 de los lienzos, 848 B)
#   `make ips`    -> war_parche.ips, 1718 bytes en 39 registros
#   `make test`   -> 73 comprobaciones
#   pasmo src/parche/*.asm -> 76 + 61 = 137 bytes de codigo nuevo
BYTES = 1396
CAMBIOS = 130
IPS_BYTES = 1718
IPS_REGISTROS = 39
TESTS = 73
#   los 1396 bytes, repartidos: 137 de codigo, 376 de texto, 10 de punteros,
#   848 de tiles repintados, 23 de ganchos y trampolines y 2 sueltos (el tope
#   de la siembra y el papel del texto)
CODIGO_NUEVO = 137
TEXTO = 376
CADENAS = 19
TILES = 122
CASILLAS_MAPA = 13260

REPO = "https://github.com/antxiko/WarinMiddleEarth-MSX-Patch"
REPO_DIS = "https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly"


def mil(n, idioma):
    return f"{n:,}".replace(",", "." if idioma == "es" else ",")


TXT = {
    "es": dict(
        titulo="War in Middle Earth — el parche de Araubi",
        aviso="<b>Aquí no hay ni una captura de pantalla.</b> No pueden "
              "haberla: el juego resube la pantalla al VDP sin parar, y dos "
              "fotos del <b>mismo</b> estado separadas tres segundos ya salen "
              "con el <b>37 % de los píxeles distintos</b>. Lo que se ve está "
              "dibujado desde el <b>búfer de pantalla del ZX Spectrum que el "
              "juego lleva en RAM</b>, volcado en un instante fijo y pintado "
              "con la tabla de color del propio cartucho. El control: dos "
              "pasadas del mismo estado dan una imagen idéntica al píxel, así "
              "que lo que cambia entre «sin» y «con» lo cambia el parche.",
        claim="Araubi pidió tres cosas en el foro y salieron seis. "
              f"<b>{mil(BYTES, 'es')} bytes en {CAMBIOS} sitios</b>, cada uno "
              "comprobado contra los bytes que espera antes de escribir: nada "
              "se desplaza, y el montaje falla si cambia un solo byte fuera de "
              "la tabla. El código nuevo vive dentro del <b>motor de altavoz "
              "del ZX que esta conversión trajo entero y no llama nadie</b>, "
              f"las <b>{CADENAS} cadenas</b> que terminan de traducir el juego "
              "caben sin mover una sola letra de sitio, y el mapa entero viene "
              f"<b>repintado</b>: {TILES} de los 128 dibujos de 8×8, hechos en "
              "un PNG y convertidos en parche por la propia herramienta.",
        ficha=["Melbourne House / Dro Soft · <b>1989</b>",
               "Cinta MSX1 · <b>62.261 bytes</b>",
               f"<b>{mil(BYTES, 'es')} bytes</b> cambiados, <b>0</b> desplazados",
               "Parche <b>IPS</b>, extraoficial"],
        nav=[("#numbers", "Las cifras"), ("#findings", "Lo que cambia"),
             ("#screens", "Antes y después")],
        docnav=[("EMPEZAR.html", "Empezar"), ("EL-PARCHE.html", "El parche"),
                ("COMO-FUNCIONA.html", "Cómo funciona"),
                ("LAS-IMAGENES.html", "Las imágenes"),
                ("HALLAZGOS.html", "Hallazgos"),
                ("PREGUNTAS-ABIERTAS.html", "Preguntas abiertas")],
        otro=("../", "In English"),
        h_num="El parche en cifras",
        h_find="Las seis cosas que hace",
        h_scr="La misma casilla, sin el parche y con él",
        cifras=[(mil(BYTES, "es"), "bytes cambiados"),
                (str(CAMBIOS), "sitios tocados"),
                ("0", "bytes desplazados"),
                ("0", "bytes fuera de la tabla"),
                (str(CODIGO_NUEVO), "bytes de código nuevo"),
                (str(TEXTO), "bytes de texto nuevo"),
                (f"{TILES}/128", "tiles del mapa repintados"),
                (mil(IPS_BYTES, "es"), "bytes de parche IPS"),
                (str(TESTS), "comprobaciones en verde")],
        nota_scr="Cada pareja es la misma partida, la misma casilla y el mismo "
                 "instante, cargando la cinta original y cargando la parcheada. "
                 "Las de «ahora» están volcadas de la cinta parcheada de hoy, "
                 "con el mapa ya repintado.",
        pie_leg="Esto es un parche de jugabilidad, extraoficial y sin ánimo de "
                "lucro. El juego sigue siendo de sus autores y aquí "
                "<b>no se distribuye ninguna imagen de cinta</b>: se reparte el "
                "parche, y cada cual lo aplica sobre su copia. Sale del "
                f'<a href="{REPO_DIS}">desensamblado comentado</a>, que es otro '
                "repositorio y otra web.",
    ),
    "en": dict(
        titulo="War in Middle Earth — Araubi's patch",
        aviso="<b>There is not a single screenshot here.</b> There cannot be: "
              "the game re-uploads the screen to the VDP constantly, and two "
              "photographs of the <b>same</b> state three seconds apart already "
              "differ in <b>37 % of their pixels</b>. What you see is drawn "
              "from the <b>ZX Spectrum screen buffer the game keeps in RAM</b>, "
              "dumped at a fixed instant and painted with the cartridge's own "
              "colour table. The control: two runs of the same state give a "
              "pixel-identical image, so whatever changes between «without» and "
              "«with» is the patch and nothing else.",
        claim="Araubi asked for three things on the forum and six came out. "
              f"<b>{mil(BYTES, 'en')} bytes across {CAMBIOS} places</b>, each "
              "one checked against the bytes it expects before writing: nothing "
              "shifts, and the build fails if a single byte changes outside the "
              "table. The new code lives inside the <b>ZX beeper engine this "
              "port brought across whole and never calls</b>, the "
              f"<b>{CADENAS} strings</b> that finish translating the game fit "
              "without moving a single letter, and the whole map comes "
              f"<b>repainted</b>: {TILES} of the 128 8×8 drawings, done in a "
              "PNG and turned into patch entries by the tool itself.",
        ficha=["Melbourne House / Dro Soft · <b>1989</b>",
               "MSX1 cassette · <b>62,261 bytes</b>",
               f"<b>{mil(BYTES, 'en')} bytes</b> changed, <b>0</b> shifted",
               "<b>IPS</b> patch, unofficial"],
        nav=[("#numbers", "The numbers"), ("#findings", "What it changes"),
             ("#screens", "Before and after")],
        docnav=[("GETTING-STARTED.html", "Getting started"),
                ("THE-PATCH.html", "The patch"),
                ("HOW-IT-WORKS.html", "How it works"),
                ("THE-PICTURES.html", "The pictures"),
                ("FINDINGS.html", "Findings"),
                ("OPEN-QUESTIONS.html", "Open questions")],
        otro=("es/", "En castellano"),
        h_num="The patch in numbers",
        h_find="The six things it does",
        h_scr="The same cell, without the patch and with it",
        cifras=[(mil(BYTES, "en"), "bytes changed"),
                (str(CAMBIOS), "places touched"),
                ("0", "bytes shifted"),
                ("0", "bytes outside the table"),
                (str(CODIGO_NUEVO), "bytes of new code"),
                (str(TEXTO), "bytes of new text"),
                (f"{TILES}/128", "map tiles repainted"),
                (mil(IPS_BYTES, "en"), "bytes of IPS patch"),
                (str(TESTS), "checks passing")],
        nota_scr="Each pair is the same game, the same cell and the same "
                 "instant, loading the original cassette and the patched one. "
                 "The “now” ones are dumped from today's patched cassette, with "
                 "the map already repainted.",
        pie_leg="This is an unofficial, non-commercial gameplay patch. The game "
                "still belongs to its authors and <b>no cassette image is "
                "distributed here</b>: the patch is what gets shared, and you "
                "apply it to your own copy. It comes out of the "
                f'<a href="{REPO_DIS}">commented disassembly</a>, which is a '
                "separate repository and a separate site.",
    ),
}

HALLAZGOS = {
    "es": [
        ("1 · Las unidades enemigas se ven",
         "<p>El mapa guarda un bit de «aquí hay alguien» por casilla, y "
         "<code>RECENTRA_EL_MAPA</code> (<code>0x7FAC</code>) lo vuelve a "
         "sembrar unidad a unidad. Pero su bucle <b>para en la unidad "
         "0x78</b>, que es justo donde empieza el bando enemigo: las enemigas "
         "no se siembran, y por eso no se dibujan. Esa era la niebla de guerra "
         "del juego, y era un descuido con forma de <code>cp 078h</code>.</p>"
         "<p><b>Un byte, en <code>0x7FD1</code>:</b> el tope pasa a "
         "<code>0x00</code> y el bucle recorre las 256 ranuras. Medido: "
         "<b>136 unidades enemigas</b> se siembran donde antes se sembraban "
         "cero.</p>"),
        ("2 · Cada apartado enseña su número",
         "<p>La ficha lista seis cualidades —Valioso, Hábil, Duro, Bravo, "
         "Enérgico y Decidido— como adverbio más adjetivo («es muy bravo»), "
         "nunca como cifra, y con eso no se pueden comparar dos unidades.</p>"
         "<p>Una rutina nueva de 76 bytes lee los seis valores de "
         "<code>0xC000</code>-<code>0xC300</code> y los escribe en la columna "
         "20 de cada línea. La engancha un trampolín de tres bytes en "
         "<code>0x708A</code>, donde la ficha hacía <code>ld hl,0x5FBD</code> "
         "justo antes de pintarse. Comprobado contra la RAM: <b>coinciden los "
         "seis</b>.</p>"),
        ("3 · El plazo del Anillo, al lado del anillo",
         "<p>Esta petición estaba mal leída la primera vez. No es el contador "
         "<code>0xC300</code> del portador: <b>es una cuenta atrás de "
         "meses</b>. El reloj del juego baja uno el operando de "
         "<code>0x8333</code> —que <code>0x7F4F</code> deja en <b>255</b> al "
         "empezar—, saca el mensaje «El Anillo corrompe al que lo usa.» y "
         "hace <code>jp z,DERROTA</code>.</p>"
         "<p>Ese número es, literalmente, lo que te queda, y el juego no lo "
         "enseña en ningún sitio. El anillo de la ficha es el carácter "
         "<code>0x5F</code> en <code>0x7C46</code>; las tres columnas de su "
         "izquierda estaban libres, y ahí va ahora.</p>"),
        ("4 · Las enemigas llevan el Ojo de Sauron",
         "<p>Con el cambio 1 las enemigas salían… <b>con tu casco</b>, que es "
         "media solución: las ves, pero no sabes cuáles son. Y la rutina que "
         "dibuja sólo mira el byte del mapa, así que no puede saber de qué "
         "bando es una unidad.</p>"
         "<p>El <b>bit 5</b> de ese byte estaba libre —medido: cero usos en las "
         f"{mil(CASILLAS_MAPA, 'es')} casillas—, y ahí va ahora la marca de "
         "bando. El icono son <b>cuatro tiles nuevos</b> al final de la tabla "
         "de <code>0x9E00</code>, en los índices 111 a 114, que estaban a "
         "cero.</p>"),
        ("5 · El texto termina de traducirse",
         "<p>La conversión de Animagic dejó <b>los topónimos del mapa en "
         "inglés</b> y tres nombres de raza truncados: «Brujo», «Elf» y «Hum». "
         f"Cambian <b>{CADENAS} cadenas</b> —diez sitios del mapa, un nombre de "
         "unidad, las tres razas, los cuatro adjetivos de la ficha y su última "
         "línea— y no se mueve un byte.</p>"
         "<p>El registro de un sitio lleva <b>el tamaño de su cartel</b> "
         "(<code>ancho&lt;&lt;4 | filas</code>) y el texto lo rellena entero, "
         "así que el nombre nuevo tiene que medir lo mismo: "
         "<code>Cavada </code> + <code>Grande </code> llena el cartel de 7×2 "
         "donde iba <code>Michel </code>/<code>Delving</code>. Los nombres de "
         "raza viven en dos listas que se recorren <b>contando bits de fin</b>, "
         "así que dentro de una lista una cadena sí puede cambiar de largo: "
         "«Brujo » → «Mago» libera dos bytes y sale <b>dos veces en cada "
         "lista</b>, los cuatro justos que necesitan «Elf» → «Elfo» y "
         "«Hum» → «Hombre».</p>"),
        ("6 · El mapa, repintado entero",
         "<p>Los 128 dibujos de 8×8 del mapa se sacan a un PNG a tamaño real, "
         f"se repintan con un editor cualquiera y <b>{TILES} de los 128</b> "
         "vuelven a la cinta convertidos en entradas del parche, con su "
         "<code>orig</code> y su <code>nuevo</code> del mismo largo, igual que "
         "las escritas a mano. Los seis que no cambian es porque el dibujo que "
         "vuelve es idéntico al que había.</p>"
         "<p>Y ahí salió que <b>el lienzo mentía</b>: cada tile lleva pegado un "
         "atributo del <b>Spectrum</b>, pero el juego no lo manda a la "
         "pantalla, lo traduce antes <code>ATRIBUTO_A_COLOR</code> "
         "(<code>0x049F</code>) con dos tablas de ocho colores del MSX. Así que "
         "sólo se pueden pintar <b>doce de los quince colores</b> del MSX, y la "
         "herramienta avisa y sustituye si se cuela uno imposible. El texto va "
         "ahora sobre el mismo khaki de los marcos: <b>un byte</b> en "
         "<code>0x763F</code>.</p>"),
        ("Y una trampa que costó una pasada entera",
         "<p>La tabla de cuadros de dos por dos de <code>0x77B5</code> tiene "
         "seis entradas a cero y parecen sitio de sobra. <b>No lo son:</b> "
         "<code>PINTA_LO_DE_ENCIMA</code> elige entrada con un "
         "<code>and 00fh</code> sobre el nibble bajo del terreno, así que los "
         "índices 0x00-0x0F ya tienen dueño.</p>"
         "<p>Poner el Ojo en el hueco 0x03 se lo puso a las <b>447 casillas de "
         "terreno de tipo 3</b>. La salida fue no usar índice: apuntar HL a una "
         "lista propia de cuatro códigos y entrar en el estampador ya pasada su "
         "aritmética, en <code>0x7720</code>.</p>"),
    ],
    "en": [
        ("1 · Enemy units become visible",
         "<p>The map keeps a “someone is here” bit per cell, and "
         "<code>RECENTRA_EL_MAPA</code> (<code>0x7FAC</code>) re-plants it unit "
         "by unit. But its loop <b>stops at unit 0x78</b>, exactly where the "
         "enemy side begins: the enemy never gets planted, and so never gets "
         "drawn. That was the game's fog of war, and it was an oversight shaped "
         "like a <code>cp 078h</code>.</p>"
         "<p><b>One byte, at <code>0x7FD1</code>:</b> the limit becomes "
         "<code>0x00</code> and the loop walks all 256 slots. Measured: "
         "<b>136 enemy units</b> get planted where zero did before.</p>"),
        ("2 · Every attribute shows its number",
         "<p>A unit's sheet lists six qualities — Valioso, Hábil, Duro, Bravo, "
         "Enérgico, Decidido — as adverb plus adjective (“very brave”), never "
         "as a number, and you cannot compare two units with that.</p>"
         "<p>A new 76-byte routine reads the six values from "
         "<code>0xC000</code>-<code>0xC300</code> and writes them at column 20 "
         "of each line. A three-byte trampoline at <code>0x708A</code> hooks "
         "it, where the sheet used to do <code>ld hl,0x5FBD</code> right before "
         "painting itself. Checked against RAM: <b>all six match</b>.</p>"),
        ("3 · The Ring's deadline, next to the ring",
         "<p>This request was misread the first time. It is not the bearer's "
         "<code>0xC300</code> counter: <b>it is a countdown of months</b>. The "
         "game's clock decrements the operand at <code>0x8333</code> — which "
         "<code>0x7F4F</code> sets to <b>255</b> at the start — prints “El "
         "Anillo corrompe al que lo usa.” and does "
         "<code>jp z,DERROTA</code>.</p>"
         "<p>That number is literally how long you have left, and the game "
         "shows it nowhere. The ring in the sheet is character "
         "<code>0x5F</code> at <code>0x7C46</code>; the three columns to its "
         "left were free, and that is where it goes now.</p>"),
        ("4 · The enemy gets the Eye of Sauron",
         "<p>With change 1 the enemy showed up… <b>wearing your helmet</b>, "
         "which is half a fix: you see them, but you cannot tell which is "
         "which. And the drawing routine only ever looks at the map byte, so it "
         "cannot know which side a unit belongs to.</p>"
         "<p><b>Bit 5</b> of that byte was free — measured: zero uses across "
         f"all {mil(CASILLAS_MAPA, 'en')} cells — and that is now the side "
         "marker. The icon is <b>four new tiles</b> at the tail of the "
         "<code>0x9E00</code> table, indices 111 to 114, which were all "
         "zeros.</p>"),
        ("5 · The text finishes its translation",
         "<p>Animagic's conversion left <b>the map's place names in English</b> "
         "and three race names truncated: “Brujo”, “Elf” and “Hum”. "
         f"<b>{CADENAS} strings</b> change — ten place names, one unit name, "
         "the three races, the sheet's four adjectives and its last line — and "
         "not a byte moves.</p>"
         "<p>A place record carries <b>the size of its signpost</b> "
         "(<code>width&lt;&lt;4 | rows</code>) and the text fills it whole, so "
         "the new name has to measure the same: <code>Cavada </code> + "
         "<code>Grande </code> fills the 7×2 sign that held "
         "<code>Michel </code>/<code>Delving</code>. The race names live in two "
         "lists walked by <b>counting terminator bits</b>, so inside a list a "
         "string <i>may</i> change length: “Brujo ” → “Mago” frees two bytes and "
         "appears <b>twice in each list</b> — exactly the four that "
         "“Elf” → “Elfo” and “Hum” → “Hombre” need.</p>"),
        ("6 · The map, repainted whole",
         "<p>The map's 128 8×8 drawings are exported to a PNG at full size, "
         f"repainted in any image editor, and <b>{TILES} of the 128</b> go back "
         "into the cassette as patch entries, with <code>orig</code> and "
         "<code>nuevo</code> the same length, exactly like the hand-written "
         "ones. The six that do not change are the ones whose drawing comes "
         "back identical to what was there.</p>"
         "<p>And that is where it turned out that <b>the canvas was lying</b>: "
         "each tile carries a <b>Spectrum</b> attribute glued behind it, but "
         "the game never sends it to the screen — "
         "<code>ATRIBUTO_A_COLOR</code> (<code>0x049F</code>) translates it "
         "first, with two eight-colour MSX tables. So only <b>twelve of the "
         "MSX's fifteen colours</b> can be painted, and the tool says so and "
         "substitutes if an impossible one gets in. The text now sits on the "
         "same khaki as the frames: <b>one byte</b> at "
         "<code>0x763F</code>.</p>"),
        ("And one trap that cost a whole run",
         "<p>The two-by-two artwork table at <code>0x77B5</code> has six "
         "all-zero entries and they look like plenty of room. <b>They are "
         "not:</b> <code>PINTA_LO_DE_ENCIMA</code> picks its entry with an "
         "<code>and 00fh</code> over the terrain's low nibble, so indices "
         "0x00-0x0F already have an owner.</p>"
         "<p>Putting the Eye in slot 0x03 gave it to all <b>447 cells of "
         "terrain type 3</b>. The way out was not to use an index at all: point "
         "HL at our own list of four codes and enter the stamper past its "
         "arithmetic, at <code>0x7720</code>.</p>"),
    ],
}

# Las parejas de la galeria: fichero, pie en castellano, pie en ingles.
GALERIA = [
    ("mapa_sin_parche.png",
     "SIN PARCHE, casilla 036N/096E — tres huestes de Sauron estan ahi mismo y "
     "no se dibuja ninguna. Esa era la niebla de guerra",
     "WITHOUT THE PATCH, cell 036N/096E — three of Sauron's hosts are right "
     "there and not one is drawn. That was the fog of war"),
    ("enemigas_con_casco.png",
     "EL PRIMER PARCHE — las enemigas ya salian, pero con el casco de las "
     "tuyas. Se ven y no se distinguen. Doce celdas de caracter cambian, y ni "
     "un atributo de color",
     "THE FIRST PATCH — the enemy did show up, but wearing your own helmet. "
     "You see them and cannot tell them apart. Twelve character cells change, "
     "and not one colour attribute"),
    ("ojo_de_sauron.png",
     "EL OJO DE SAURON — las tres huestes lo llevan y los dos aliados de la "
     "esquina siguen con su casco. Todavia con los dibujos de la cinta",
     "THE EYE OF SAURON — the three hosts wear it and the two friendly units "
     "in the corner keep their helmet. Still with the cassette's own artwork"),
    ("mapa_con_parche.png",
     "AHORA — la misma casilla y el mismo instante, con el mapa repintado. "
     "Frente a la cinta original cambian 735 de las 768 celdas de caracter y "
     "560 atributos: el mapa es otro",
     "NOW — the same cell, the same instant, with the map repainted. Against "
     "the original cassette 735 of the 768 character cells change, and 560 "
     "attributes: the map is another map"),
    ("ficha_sin_valores.png",
     "SIN PARCHE — la ficha de Gandalf: \"Es muy Habil\". Muy... cuanto",
     "WITHOUT THE PATCH — Gandalf's sheet: \"Es muy Habil\". Very... how much"),
    ("ficha_con_valores.png",
     "CON PARCHE — la misma ficha con su numero en cada linea: Energico 158, Decidido "
     "192, Firme 010, Virtuoso 008, Valiente 010, Fuerte 006. Y la ultima "
     "linea, entera: \"Aliado a la Comunidad\"",
     "WITH THE PATCH — the same sheet with a number on every line: Energico 158, "
     "Decidido 192, Firme 010, Virtuoso 008, Valiente 010, Fuerte 006. And the "
     "last line, whole: \"Aliado a la Comunidad\""),
    ("ficha_frodo_sin_parche.png",
     "SIN PARCHE — la ficha de Frodo, el portador. El anillo dice quien lo "
     "lleva, y nada mas",
     "WITHOUT THE PATCH — Frodo's sheet, the Ring-bearer. The ring says who "
     "carries it, and nothing else"),
    ("plazo_del_anillo.png",
     "CON PARCHE — 255, pegado al anillo: los meses que quedan antes de "
     "sucumbir. Cada mes baja uno; a cero, la pantalla de Sauron",
     "WITH THE PATCH — 255, right beside the ring: the months left before you "
     "succumb. One less every month; at zero, Sauron's screen"),
    ("icono_aliado.png",
     "EL ICONO ALIADO, ampliado y leido de la cinta ya parcheada: los tiles 81 "
     "a 84 de la tabla de 0x9E00, repintados como un escudo",
     "THE FRIENDLY ICON, enlarged and read off the already patched tape: tiles "
     "81 to 84 of the 0x9E00 table, repainted as a shield"),
    ("icono_ojo_de_sauron.png",
     "EL OJO, tambien de la cinta parcheada: los tiles 111 a 114, que estaban "
     "a cero. Ahora en rojo oscuro, que es un color que el atributo del "
     "Spectrum si puede pedir",
     "THE EYE, also off the patched tape: tiles 111 to 114, which were all "
     "zeros. Now in dark red, which is a colour the Spectrum attribute can "
     "actually ask for"),
    ("textos_sin_parche.png",
     "SIN PARCHE — el cartel dice \"Dale\" y la ficha \"Formacion de 005 Hum\", "
     "\"Hum:caracter:\" y \"No Valioso\". La conversion se quedo a medias",
     "WITHOUT THE PATCH — the sign says \"Dale\" and the sheet \"Formacion de "
     "005 Hum\", \"Hum:caracter:\" and \"No Valioso\". The conversion stopped "
     "half way"),
    ("textos_con_parche.png",
     "CON PARCHE, la misma casilla y la misma unidad — \"Valle\", \"Formacion "
     "de 005 Hombres\", \"Hombre:caracter:\" y \"No Virtuoso\". Y el texto sobre "
     "el khaki de los marcos, que es un solo byte",
     "WITH THE PATCH, same cell, same unit — \"Valle\", \"Formacion de 005 "
     "Hombres\", \"Hombre:caracter:\" and \"No Virtuoso\". And the text on the "
     "frames' khaki, which is a single byte"),
    ("cartel_sin_parche.png",
     "SIN PARCHE — el cartel de dos filas: \"Michel\" arriba, \"Delving\" "
     "abajo, siete columnas por dos filas",
     "WITHOUT THE PATCH — the two-row signpost: \"Michel\" on top, \"Delving\" "
     "below, seven columns by two rows"),
    ("cartel_con_parche.png",
     "CON PARCHE — \"Cavada\" y \"Grande\" en el mismo cartel de 7x2, que es "
     "lo que obliga a rellenar con espacios. Y la Comarca repintada debajo",
     "WITH THE PATCH — \"Cavada\" and \"Grande\" in the same 7x2 sign, which is "
     "what forces the padding with spaces. And the Shire repainted underneath"),
    ("tiles-del-mapa.png",
     "LOS 128 TILES DEL MAPA tal y como vienen en la cinta, dibujados byte a "
     "byte y con los colores del MSX -que no son los del Spectrum, aunque el "
     "atributo si lo sea-",
     "THE MAP'S 128 TILES as they come on the cassette, drawn byte by byte and "
     "with the MSX's colours — which are not the Spectrum's, even though the "
     "attribute is"),
    ("tiles-repintados.png",
     "LOS MISMOS, REPINTADOS: 122 de los 128 entran en el parche. El magenta "
     "es hueco vacio",
     "THE SAME ONES, REPAINTED: 122 of the 128 make it into the patch. Magenta "
     "is empty space"),
]


def img64(ruta):
    with open(ruta, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    imgdir, salida, idioma = argv[1:4]
    t = TXT[idioma]

    logo = os.path.join(imgdir, "carga.png")
    cabecera = (f'<img src="{img64(logo)}" alt="War in Middle Earth">'
                if os.path.exists(logo) else "<h1>War in Middle Earth</h1>")

    nav = "".join(f'<a href="{h}">{x}</a>' for h, x in t["nav"])
    nav += "".join(f'<a href="{h}">{x}</a>' for h, x in t["docnav"])
    nav += (f'<a href="{t["otro"][0]}" style="margin-left:auto;color:var(--oro)">'
            f'{t["otro"][1]}</a>')

    cifras = "".join(f'<div class="cifra"><b>{v}</b><span>{e}</span></div>'
                     for v, e in t["cifras"])
    halls = "".join(f'<div class="hall"><h3>{tit}</h3>{cuerpo}</div>'
                    for tit, cuerpo in HALLAZGOS[idioma])
    imgs = ""
    faltan = []
    for fich, es, en in GALERIA:
        ruta = os.path.join(imgdir, fich)
        if not os.path.exists(ruta):
            faltan.append(fich)
            continue
        pie = es if idioma == "es" else en
        imgs += (f'<figure><img src="{img64(ruta)}" alt="{pie}">'
                 f'<figcaption>{pie}</figcaption></figure>')
    if faltan:
        print("  (faltan %d imagenes: %s)" % (len(faltan), " ".join(faltan)))

    html = f"""<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{t['titulo']}</title>
<style>{ESTILO}</style>
<header class="top">
  {cabecera}
  <p class="claim">{t['claim']}</p>
  <p class="ficha">{' · '.join(t['ficha'])}</p>
</header>
<p class="ficha" style="border:1px solid var(--oro);padding:.8em 1em;margin:1.5em 0">
{t['aviso']}</p>
<nav>{nav}</nav>
<section id="numbers">
  <h2>{t['h_num']}</h2>
  <div class="cifras">{cifras}</div>
</section>
<section id="findings"><h2>{t['h_find']}</h2>{halls}</section>
<section id="screens">
  <h2>{t['h_scr']}</h2>
  <p class="n">{t['nota_scr']}</p>
  <div class="galeria">{imgs}</div>
</section>
<footer><p>{t['pie_leg']}</p></footer>
"""
    with open(salida, "w", encoding="utf-8") as f:
        f.write(html)
    print("  %s: %d KB (%s)" % (salida, len(html) // 1024, idioma))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
