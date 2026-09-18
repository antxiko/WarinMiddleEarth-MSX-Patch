# War in Middle Earth (Melbourne House / Dro Soft, 1989, MSX1) - desensamblado
#
# `make` extrae los bloques de la cinta, los traza y comprueba que al rehacer
# los listados sale EXACTAMENTE el original, byte a byte.
#
# Lo que hace raro a este juego: es una conversion del ZX Spectrum (Melbourne
# House, 1988; la conversion es de Animagic) y se trajeron el sistema de cinta
# entero. Los bloques no son KCS del MSX sino bloques del Spectrum (TZX 0x10)
# con su `[bandera][datos][XOR]`, y el cargador es una reimplementacion de
# LD-BYTES de la ROM del Spectrum. El juego corre con las CUATRO paginas en RAM,
# sin BIOS, en tres bloques que el arranque recoloca; por eso se traza sobre una
# imagen de 64K (work/juego64.bin) y luego se parte en tres listados, cada uno
# con el org donde de verdad se ejecuta.

TSX  := war.tsx
TSX_SHA := 13c636328d1714d5e00419141ca1a7ac9c7a3a04d7ec2b26545212aab1d81208
SYMS := work/msx.sym

.PHONY: all verify clean extract cuerpos trazado listados sanity test cinta imagenes web parche verifica_parche lienzos graficos

all: verify

# ---------------------------------------------------------------- extraccion
cinta:
	@if [ ! -f "$(TSX)" ]; then \
	  echo ""; \
	  echo "  Falta la imagen de cinta: $(TSX)"; \
	  echo ""; \
	  echo "  No se distribuye con este repositorio, solo el trabajo de"; \
	  echo "  documentacion (ver AVISO-LEGAL.md). Para reconstruirlo todo hace"; \
	  echo "  falta tu propia copia del TSX de War in Middle Earth, con ese"; \
	  echo "  nombre y en la raiz del proyecto. Debe dar este sha256:"; \
	  echo "      $(TSX_SHA)"; \
	  echo ""; \
	  exit 1; \
	fi
	@echo "$(TSX_SHA)  $(TSX)" | shasum -a 256 -c - >/dev/null 2>&1 \
	  || { echo "  AVISO: $(TSX) no da el sha256 esperado; los listados pueden no cuadrar."; }

extract: extracted/.stamp
extracted/.stamp: tools/tsx_parse.py tools/cuerpos.py | cinta
	@mkdir -p work
	python3 tools/tsx_parse.py "$(TSX)" extracted >/dev/null
	python3 tools/cuerpos.py extracted work
	@touch $@

cuerpos: extract

# ------------------------------------------------------------------ trazado
# El juego se traza ENTERO sobre la imagen de 64K, porque los tres bloques se
# llaman entre si; los huecos entre bloques van declarados como datos en
# src/juego.nocode para que una llamada perdida no se trague ceros como codigo.
# Los puntos de entrada que el trazador no puede deducir -retornos empujados,
# tablas de saltos, operandos automodificados- van en src/juego.entries, cada
# uno con la instruccion que lo justifica.
work/juego.trace.json: tools/z80trace.py src/juego.entries src/juego.nocode extracted/.stamp
	python3 tools/z80trace.py work/juego64.bin 0x0000 src/juego.entries work/juego src/juego.nocode

# Y se parte en los tres bloques de la cinta, cada uno con su org de ejecucion.
work/bajo.trace.json work/medio.trace.json work/alto.trace.json: work/juego.trace.json tools/split_trace.py
	python3 tools/split_trace.py work/juego64.bin work/juego.trace.json work

work/loader.trace.json: tools/z80trace.py src/loader.entries extracted/.stamp
	python3 tools/z80trace.py work/loader.raw 0xD6D8 src/loader.entries work/loader

work/pantalla.trace.json: tools/z80trace.py src/pantalla.entries src/pantalla.nocode extracted/.stamp
	python3 tools/z80trace.py work/pantalla.raw 0x88B8 src/pantalla.entries work/pantalla src/pantalla.nocode

trazado: work/bajo.trace.json work/loader.trace.json work/pantalla.trace.json

# ----------------------------------------------------------------- listados
listados: src/war_loader.asm src/war_pantalla.asm src/war_bajo.asm src/war_medio.asm src/war_alto.asm

src/war_loader.asm: work/loader.trace.json src/loader.notes tools/mkasm.py
	python3 tools/mkasm.py work/loader.raw 0xD6D8 work/loader.trace.json \
	  src/loader.notes $(SYMS) $@ "WAR IN MIDDLE EARTH - MSX - el cargador"

src/war_pantalla.asm: work/pantalla.trace.json src/pantalla.notes tools/mkasm.py
	python3 tools/mkasm.py work/pantalla.raw 0x88B8 work/pantalla.trace.json \
	  src/pantalla.notes $(SYMS) $@ "WAR IN MIDDLE EARTH - MSX - la pantalla de carga"

src/war_bajo.asm: work/bajo.trace.json src/bajo.notes tools/mkasm.py
	python3 tools/mkasm.py work/bajo.raw 0x0190 work/bajo.trace.json \
	  src/bajo.notes $(SYMS) $@ "WAR IN MIDDLE EARTH - MSX - bloque bajo (0x0190): la capa MSX y los graficos"

src/war_medio.asm: work/medio.trace.json src/medio.notes tools/mkasm.py
	python3 tools/mkasm.py work/medio.raw 0x5E00 work/medio.trace.json \
	  src/medio.notes $(SYMS) $@ "WAR IN MIDDLE EARTH - MSX - bloque medio (0x5E00): el juego"

src/war_alto.asm: work/alto.trace.json src/alto.notes tools/mkasm.py
	python3 tools/mkasm.py work/alto.raw 0x9E00 work/alto.trace.json \
	  src/alto.notes $(SYMS) $@ "WAR IN MIDDLE EARTH - MSX - bloque alto (0x9E00): graficos, mapa y tablas"

sanity: work/juego.trace.json work/loader.trace.json work/pantalla.trace.json
	@echo "=================================================================="
	@echo " Coherencia: ningun punto de entrada dentro de una zona de datos"
	@echo "=================================================================="
	@python3 tools/check_entradas.py src/juego.entries src/bajo.notes src/juego.nocode
	@python3 tools/check_entradas.py src/juego.entries src/medio.notes src/juego.nocode
	@python3 tools/check_entradas.py src/juego.entries src/alto.notes src/juego.nocode
	@python3 tools/check_entradas.py src/loader.entries src/loader.notes
	@python3 tools/check_entradas.py src/pantalla.entries src/pantalla.notes src/pantalla.nocode
	@echo ""
	@echo "=================================================================="
	@echo " Sanidad del trazado: las zonas de datos no pueden salir como codigo"
	@echo "=================================================================="
	python3 tools/check_trace.py work/juego.trace.json src/juego.nocode
	python3 tools/check_trace.py work/pantalla.trace.json src/pantalla.nocode
	@echo ""
	@echo "=================================================================="
	@echo " Y el cruce COMPLETO: TODAS las zonas D contra lo que el trazador cree"
	@echo "=================================================================="
	python3 tools/check_datos_como_codigo.py work src
	@echo ""
	@echo "=================================================================="
	@echo " Presupuesto de la cinta: no deben quedar bytes sin explicar"
	@echo "=================================================================="
	@python3 tools/presupuesto.py work src

# Las imagenes NO son capturas: se dibujan con los bytes de la cinta,
# repitiendo lo que hace el propio cargador. Si el reparto estuviera mal,
# saldria ruido en vez de un dibujo.
imagenes: extracted/.stamp
	@mkdir -p docs/imagenes work/laminas_parche
	@python3 tools/render_carga.py work/pantalla.raw docs/imagenes/carga.png
	@python3 tools/render_graficos.py work/alto.raw docs/imagenes
	@# Y la misma lamina de tiles, pero del bloque alto YA PARCHEADO: es la
	@# unica forma de ensenar los 128 dibujos repintados sin capturar nada.
	@python3 tools/cuerpo_parcheado.py alto work/alto_parcheado.raw
	@python3 tools/render_graficos.py work/alto_parcheado.raw work/laminas_parche
	@cp work/laminas_parche/tiles-del-mapa.png docs/imagenes/tiles-repintados.png
	@# Y lo mismo con la fuente, repintada desde el 2026-09-11. Sin esto la web
	@# ensena solo la de la cinta: regenerar las imagenes no cambiaba un byte
	@# porque ninguna lamina salia del bloque parcheado.
	@cp work/laminas_parche/fuente.png docs/imagenes/fuente-repintada.png
	@# EL MAPA ENTERO, las dos veces. El mapa viene comprimido en la propia
	@# cinta (0x16ED bytes de parejas cuenta/valor en 0xCC00), asi que esto no
	@# necesita el emulador para nada.
	@python3 tools/cuerpo_parcheado.py medio work/medio_parcheado.raw
	@python3 tools/render_mapa_completo.py work/alto.raw work/medio.raw 	   docs/imagenes/mapa-completo-original.png
	@python3 tools/render_mapa_completo.py work/alto_parcheado.raw 	   work/medio_parcheado.raw docs/imagenes/mapa-completo.png

# ------------------------------------------------------------------ el parche
# EL PARCHE DE ARAUBI. Aplica la tabla de tools/parchea.py sobre los cuerpos de
# la cinta (work/*.raw, que salen de `make extract`, o sea de TU cinta) y arma
# la cinta parcheada war_parche.tsx: enemigas visibles y con el Ojo de Sauron,
# los valores numericos en la ficha y el plazo del Anillo. Ver INVESTIGACION.md.
parche: extract src/parche/ficha_valores.asm src/parche/icono_enemigo.asm
	python3 tools/parchea.py work war_parche.tsx

# LOS GRAFICOS, EN TRES PNG. Todos los dibujos del bloque alto viven en
# src/parche/, a tamano real y sin separacion -un pixel del PNG es un pixel del
# juego-: tiles_del_mapa.png (128 tiles de 8x8, 128x64), sprites_de_batalla.png
# (176 sprites de 16x8 con mascara, apilados de dos en dos, 176x128) y fuente.png
# (128 caracteres de 8x8, 128x64). Se editan con cualquier editor de imagenes y
# `make parche` los convierte solos en entradas del parche. `make graficos` dice
# que dibujos cambian respecto a la cinta sin llegar a montar nada.
#
# `make lienzos` REHACE los PNG desde la cinta, o sea que se lleva por delante lo
# que este dibujado encima (hoy, el Ojo de Sauron). Por eso la herramienta se
# niega si el fichero ya existe y hay que insistirle con --rehaz.
graficos: extract
	python3 tools/lienzos.py mete work/alto.raw src/parche

lienzos: extract
	python3 tools/lienzos.py saca work/alto.raw src/parche

# El parche a secas, para repartirlo SIN repartir el juego: solo los bytes que
# cambian, para aplicar sobre tu propia cinta. Se comprueba en el sitio que,
# aplicado, devuelve exactamente la cinta parcheada.
ips: parche
	python3 tools/ips.py war.tsx war_parche.tsx war_parche.ips
	@python3 tools/ips.py --aplica war.tsx war_parche.ips work/ips_comprobacion.tsx
	@cmp war_parche.tsx work/ips_comprobacion.tsx && 	 echo "el IPS aplicado sobre war.tsx da war_parche.tsx byte a byte" 

# Verificacion en openMSX (necesita el estado guardado; ver INVESTIGACION.md):
#   make verifica_parche
verifica_parche: parche
	@python3 tools/parchea.py work war_parche.tsx >/dev/null
	@echo "cinta parcheada lista: war_parche.tsx"
	@echo "para verla: openmsx -machine Philips_VG_8020 -ext cassetteplayer -cassetteplayer war_parche.tsx"

verify: listados sanity
	@echo "=================================================================="
	@echo " Reproducibilidad: ensamblar debe dar el binario exacto"
	@echo "=================================================================="
	@sh tools/verify_build.sh src/war_loader.asm   work/loader.raw   0xD6D8
	@sh tools/verify_build.sh src/war_pantalla.asm work/pantalla.raw 0x88B8
	@sh tools/verify_build.sh src/war_bajo.asm     work/bajo.raw     0x0190
	@sh tools/verify_build.sh src/war_medio.asm    work/medio.raw    0x5E00
	@sh tools/verify_build.sh src/war_alto.asm     work/alto.raw     0x9E00

test:
	@echo "=================================================================="
	@echo " Tests"
	@echo "=================================================================="
	@python3 -m unittest discover -s tests -v

web: imagenes
	python3 tools/md2html.py docs en
	python3 tools/md2html.py docs/es es
	python3 tools/make_web.py docs/imagenes docs/index.html en
	python3 tools/make_web.py docs/imagenes docs/es/index.html es
	@touch docs/.nojekyll
	@python3 tools/check_enlaces.py docs

clean:
	rm -rf extracted build work/*.raw work/*.bin work/*.json work/*.blocks

# ------------------------------------------------------------- el cartucho
# DE CINTA A CARTUCHO. El juego no se toca: war.rom es una MegaROM ASCII16 de
# 64 KB con un cargador (src/cartucho/) que deja la RAM exactamente como la
# deja el cargador de la cinta y salta al mismo sitio (0x0190). Se monta de
# los cuerpos de TU cinta; con la cinta parcheada sale war_parche.rom. Ninguna
# de las dos se distribuye (ver AVISO-LEGAL.md). Detalle en INVESTIGACION.md.
OPENMSX  := /c/Program\ Files/openMSX/openmsx.exe
MAQUINA  := Philips_VG_8020
ESPERA   := 150

# LA MUSICA. El .pt3 NO va en el repositorio: es de su autor, y war_musica.rom
# tampoco se distribuye. Por defecto se coge el de RUN23, de KNM
# (twitter.com/DGrijando), que viaja en msx-msxlib (BSD 3-Clause, de Nestor
# Sancho); con otro modulo basta cambiar esta variable:
#   make verifica_musica MUSICA=/ruta/a/lo_que_sea.pt3
# (la ruta va relativa al repositorio y no por $(HOME), que en el make de msys
# es /home/usuario y no el del usuario de Windows)
MUSICA   := ../../msx-msxlib/games/examples/pt3music/RUN23_ShuffleOne.pt3
# El reproductor TAMPOCO va en el repositorio, por lo mismo que no va la cinta:
# es de sus autores -Bulba / Dioniso / msxKun / SapphiRe- y viaja en msx-msxlib
# sin una licencia escrita, solo un "hope you find useful this code". Aqui va la
# herramienta que lo traduce de asMSX a pasmo; el fuente lo pone cada cual.
PT3SRC   := ../../msx-msxlib/libext/pt3/PT3-ROM.ASM
# EL COMPRESOR. Las imagenes del cartucho van comprimidas con ZX0, de Einar
# Saukas. El descompresor SI esta aqui (src/cartucho/dzx0.asm, 68 bytes: su
# licencia lo permite a cambio de decir que se usa ZX0, y esta dicho en el
# README y en AVISO-LEGAL.md); el compresor no, que viaja en MSXgl:
#   make rom_musica ZX0EXE=/ruta/a/zx0.exe
ZX0EXE   := C:/Users/Antxiko/Documents/MSXonLIVE/MSXgl/tools/compress/ZX0/zx0.exe
export ZX0EXE

CARTUCHO := src/cartucho/cargador_rom.asm src/cartucho/cargador_ram.asm src/cartucho/direcciones.inc src/cartucho/dzx0.asm

.PHONY: rom rom_parche rom_musica estado_cinta verifica_rom verifica_rom_parche verifica_musica verifica_comprimido verifica_finales captura_rom

rom: war.rom
war.rom: extract $(CARTUCHO) tools/haz_rom.py
	python3 tools/haz_rom.py work $@ --espera $(ESPERA)

# La misma ROM con el reproductor PT3 y un modulo metidos en el hueco que queda
# al final del ultimo banco, sonando en el MENU, y con las dos pantallas
# finales quedandose en la ROM en vez de ocupar 13.824 bytes de RAM toda la
# partida. Cambia trece bytes del bloque medio -el gancho por cuadro, la
# lectura del nivel y el `ldir` de 0x83E7-, y por eso es un fichero aparte:
# war.rom se queda intacta y cotejada.
rom_musica: war_musica.rom
war_musica.rom: extract $(CARTUCHO) tools/haz_rom.py tools/cursor.py tools/guante.py tools/mapa_general.py src/cartucho/musica.asm src/cartucho/puente.asm src/cartucho/pt3_player.asm src/cartucho/pt3_trabajo.inc src/cartucho/finales.asm src/cartucho/nombres.asm src/cartucho/cursor.png src/cartucho/guante.png
	@test -f "$(MUSICA)" || { echo "no encuentro el modulo: $(MUSICA)"; echo "pasa otro con: make $@ MUSICA=/ruta/al.pt3"; exit 1; }
	python3 tools/haz_rom.py work $@ --espera $(ESPERA) --comprime --musica "$(MUSICA)" --finales-rom --vista --mapa --panel

# La misma ROM SIN la vista por tabla de nombres: es la referencia contra la
# que se coteja y se mide. Va a work/sin_vista para no pisar el plan de la otra.
work/war_sin_vista.rom: extract $(CARTUCHO) tools/haz_rom.py src/cartucho/musica.asm src/cartucho/puente.asm src/cartucho/pt3_player.asm src/cartucho/pt3_trabajo.inc src/cartucho/finales.asm
	python3 tools/haz_rom.py work $@ --espera $(ESPERA) --comprime --musica "$(MUSICA)" --finales-rom --salidas work/sin_vista

# El reproductor, traducido de la sintaxis de asMSX a la de pasmo. La traduccion
# es mecanica -241 corchetes de indireccion, 46 desplazamientos de IX que hay que
# calcular, un modulo que pasmo no entiende- y por eso la hace una herramienta:
# lo que la comprueba no es leerla, es que pasmo la ensamble.
src/cartucho/pt3_player.asm: tools/convierte_pt3.py
	@test -f "$(PT3SRC)" || { echo ""; \
	  echo "  Falta el reproductor PT3: $(PT3SRC)"; \
	  echo ""; \
	  echo "  No se distribuye aqui (ver AVISO-LEGAL.md): es de Bulba, Dioniso,"; \
	  echo "  msxKun y SapphiRe, y viaja en msx-msxlib, de Nestor Sancho:"; \
	  echo "      https://github.com/theNestruo/msx-msxlib"; \
	  echo "  Pon la ruta con: make $@ PT3SRC=/ruta/a/PT3-ROM.ASM"; \
	  echo ""; exit 1; }
	python3 tools/convierte_pt3.py "$(PT3SRC)" $@

# Los cuerpos de la cinta parcheada salen de war_parche.tsx con las mismas dos
# herramientas que los de la original: asi la ROM parcheada se monta de la
# cinta que se reparte, no de una copia intermedia.
rom_parche: war_parche.rom
war_parche.rom: parche src/cartucho/cargador_rom.asm src/cartucho/cargador_ram.asm src/cartucho/direcciones.inc tools/haz_rom.py
	@mkdir -p work/cuerpos_parche
	python3 tools/tsx_parse.py war_parche.tsx work/cuerpos_parche/extracted >/dev/null
	python3 tools/cuerpos.py work/cuerpos_parche/extracted work/cuerpos_parche >/dev/null
	python3 tools/haz_rom.py work/cuerpos_parche $@ --espera $(ESPERA)

# LA ROM UNIFICADA: TODO en un solo fichero. Es el cartucho que se juega, y
# lleva las dos mitades del trabajo.
#
# De la cinta de Araubi (war_parche.tsx):
#   textos en espanol, la ficha con sus valores en cifras, el plazo del Anillo
#   al lado del anillo, el Ojo de Sauron para las unidades enemigas, el papel
#   khaki del texto, la fuente y los tiles del mapa repintados, y el arreglo
#   del mapa comprimido (que el bit 5 del Ojo desbordaba el paquete y se comia
#   el mapa por la derecha).
#
# Del cartucho (tools/haz_rom.py):
#   musica PT3 en el menu, las tres imagenes y el mapa general comprimidos con
#   ZX0, las dos pantallas finales quedandose en la ROM en vez de comer 13.824
#   bytes de RAM, el mapa general ya dibujado, la vista de cerca por tabla de
#   nombres con el cursor y el guante como sprites de hardware, el panel con el
#   color de la vista, y la fuerza de la tropa en batalla arreglada.
#
# Los seis sitios que el cartucho parchea son identicos en las dos cintas
# (comprobado), y cursor.png sale de los cuerpos PARCHEADOS, que el parche
# repinta el cursor de batalla.
rom_unificada: war_unificada.rom
war_unificada.rom: war_parche.rom tools/haz_rom.py tools/cursor.py tools/guante.py tools/mapa_general.py src/cartucho/musica.asm src/cartucho/puente.asm src/cartucho/pt3_player.asm src/cartucho/pt3_trabajo.inc src/cartucho/finales.asm src/cartucho/nombres.asm src/cartucho/cursor.png src/cartucho/guante.png
	@test -f "$(MUSICA)" || { echo "no encuentro el modulo: $(MUSICA)"; echo "pasa otro con: make $@ MUSICA=/ruta/al.pt3"; exit 1; }
	python3 tools/haz_rom.py work/cuerpos_parche $@ --espera $(ESPERA) --comprime --musica "$(MUSICA)" --finales-rom --vista --mapa --panel --heroes --salidas work/unificada --kit work/kit

# EL KIT PARA COMPILAR EL PARCHE SIN PYTHON. Lo deja `--kit` de ahi arriba, al
# montar la ROM: los intermedios ya cocidos, src/nombres.asm -que es lo unico
# editable- y un war_cart.asm que lo pega todo con solo pasmo. Que la ROM del
# kit sale IDENTICA a la de aqui se comprueba compilandola.
kit: war_unificada.rom
	cd work/kit && sh hazlo.sh
	cmp work/kit/WAR_UNIFICADA.ROM war_unificada.rom && echo "el kit monta la misma ROM, byte a byte"

kit_zip: kit
	rm -f work/WarInMiddleEarth-kit.zip
	rm -f work/kit/WAR_UNIFICADA.ROM work/kit/nombres.bin work/kit/nombres.sym
	cd work && python3 -m zipfile -c WarInMiddleEarth-kit.zip kit
	@echo "work/WarInMiddleEarth-kit.zip listo"

# Su referencia SIN la vista, para el cotejo y la medida.
work/war_parche_sin_vista.rom: war_parche.rom tools/haz_rom.py src/cartucho/musica.asm src/cartucho/puente.asm src/cartucho/pt3_player.asm src/cartucho/pt3_trabajo.inc src/cartucho/finales.asm
	python3 tools/haz_rom.py work/cuerpos_parche $@ --espera $(ESPERA) --comprime --musica "$(MUSICA)" --finales-rom --heroes --salidas work/parche_sin_vista

# El cursor de fabrica, de los tiles de la cinta PARCHEADA. Se niega a pisar
# el PNG si ya existe (puede llevar cambios de alguien): con REHAZ=1 lo pisa.
.PHONY: cursor
cursor: war_parche.rom
	python3 tools/cursor.py saca work/cuerpos_parche src/cartucho/cursor.png $(if $(REHAZ),--rehaz)

# Y el guante del mapa general, de los 32 bytes de dibujo y mascara de la
# cinta (0x6345 y 0x6355), que son los mismos en las dos. Igual: no pisa.
.PHONY: guante
guante:
	python3 tools/guante.py saca work src/cartucho/guante.png $(if $(REHAZ),--rehaz)

# Lo que deja la cinta al llegar a 0x5E00 (VRAM, VDP, PSG), del estado que
# guarda omsx_arranque.tcl: es lo que el cartucho tiene que reproducir.
estado_cinta: work/estado_cinta/vram_5e00.bin
work/estado_cinta/vram_5e00.bin: tools/omsx_estado_cinta.tcl work/omsx_orig/war_5e00.oms
	WAR_STATE="$(abspath work/omsx_orig/war_5e00.oms)" WAR_OUT="$(abspath work/estado_cinta)" \
	  $(OPENMSX) -script tools/omsx_estado_cinta.tcl

# openMSX arranca con el cartucho y vuelca lo mismo que se volco con la cinta,
# en los mismos dos instantes; coteja_rom.py lo compara byte a byte.
#   make verifica_rom MAQUINA=Philips_NMS_8250     (otra maquina)
verifica_rom: war.rom estado_cinta
	@rm -rf work/rom_$(MAQUINA)
	WAR_ROM="$(abspath war.rom)" WAR_OUT="$(abspath work/rom_$(MAQUINA))" \
	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war.rom)" -romtype ascii16 -script tools/omsx_verifica_rom.tcl
	@grep -v volcado work/rom_$(MAQUINA)/verifica_rom.log
	python3 tools/coteja_rom.py work/rom_$(MAQUINA) work/omsx_orig work/estado_cinta

verifica_rom_parche: war_parche.rom estado_cinta
	@rm -rf work/rom_parche_$(MAQUINA)
	WAR_ROM="$(abspath war_parche.rom)" WAR_OUT="$(abspath work/rom_parche_$(MAQUINA))" \
	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_parche.rom)" -romtype ascii16 -script tools/omsx_verifica_rom.tcl
	@grep -v volcado work/rom_parche_$(MAQUINA)/verifica_rom.log
	python3 tools/coteja_rom.py work/rom_parche_$(MAQUINA) work/omsx_v4 work/estado_cinta

# LA COMPRESION, SOLA: la misma ROM pero con las imagenes comprimidas con ZX0 y
# sin musica, para que el cotejo contra la cinta diga si la ida y vuelta pierde
# algo. Comprimir implica dejar las dos pantallas finales en la ROM -los bufers
# de ZX0 caen justo en la RAM que ellas liberan-, asi que ese tramo se excluye
# del cotejo y lo cubre `make verifica_finales`, que las fuerza y las compara.
verifica_comprimido: estado_cinta
	python3 tools/haz_rom.py work work/war_z.rom --espera $(ESPERA) --comprime --salidas work/z
	@rm -rf work/rom_z
	WAR_ROM="$(abspath work/war_z.rom)" WAR_OUT="$(abspath work/rom_z)" 	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_z.rom)" -romtype ascii16 -script tools/omsx_verifica_rom.tcl
	@grep -v volcado work/rom_z/verifica_rom.log
	python3 tools/coteja_rom.py work/rom_z work/omsx_orig work/estado_cinta --sin-finales work/z/plan.json

# ¿SUENA? El emulador arranca la ROM con musica, comprueba las cuatro cosas que
# tienen que cumplirse -gancho, puente, ejecucion y PSG en movimiento-, mide el
# coste por cuadro, pulsa 0 y comprueba que calla. Sale distinto de cero si
# alguna falla: mirar un log no es verificar.
verifica_musica: war_musica.rom
	@rm -rf work/musica_$(MAQUINA)
	WAR_ROM="$(abspath war_musica.rom)" WAR_OUT="$(abspath work/musica_$(MAQUINA))" \
	  WAR_DIRS="$(abspath work/musica/musica.tcl)" \
	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_musica.tcl
	@cat work/musica_$(MAQUINA)/musica.log

# LAS DOS PANTALLAS FINALES. Para ver una hay que terminarse el juego, asi que
# la sonda fuerza el PC en 0x83E7 -donde los cuatro finales convergen- con HL en
# cada pantalla, y vuelca los 6.912 bytes que quedan en 0x4000 y la VRAM ya
# pintada. Se monta ademas la ROM de ANTES del cambio -SIN --comprime, con las
# dos pantallas en la RAM y el `ldir` original de 0x83E7 intacto- y se hace lo
# mismo, para comparar las dos.
#
# OJO CON LA REFERENCIA: tiene que ser una ROM DISTINTA de verdad. Cuando
# --comprime paso a implicar --finales-rom, la de referencia salio identica a la
# nueva y el cotejo de VRAM se estaba comparando consigo mismo: en verde y sin
# comprobar nada.
#
# El cotejo que decide es el primero: los 6.912 bytes contra los de la cinta.
# El de la VRAM cierra el circulo, pero un cotejo entre dos ROMs no diria nada
# si las dos estuvieran mal igual.
verifica_finales: war_musica.rom
	python3 tools/haz_rom.py work work/war_ref.rom --espera $(ESPERA) --musica "$(MUSICA)" --salidas work/ref
	@rm -rf work/finales_ref work/finales_$(MAQUINA)
	WAR_ROM="$(abspath work/war_ref.rom)" WAR_OUT="$(abspath work/finales_ref)" 	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_ref.rom)" -romtype ascii16 -script tools/omsx_finales.tcl
	WAR_ROM="$(abspath war_musica.rom)" WAR_OUT="$(abspath work/finales_$(MAQUINA))" 	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_finales.tcl
	@cat work/finales_$(MAQUINA)/finales.log
	python3 tools/coteja_finales.py work/finales_$(MAQUINA) work work/finales_ref

# LA VISTA DE CERCA POR TABLA DE NOMBRES, CON EL CURSOR COMO SPRITE. La VRAM
# de la ROM nueva ya no se parece a la de antes -una lleva nombres y la otra
# bitmap- y, con la ventana del trozo fija, ni siquiera ensena lo mismo en
# cuanto el cursor se mueve. Las dos ROMs se llevan a los mismos instantes de
# la vista (contados por vueltas del bucle, no por reloj: van a distinta
# velocidad), la sonda vuelca el trozo puro de CADA vuelta y el estado entero
# en los instantes elegidos, y tools/coteja_vista.py reconstruye con un MODELO
# del paginado lo que la nueva tiene que ensenar: caracter a caracter en todas
# las vueltas, pixel a pixel (tools/render_vram.py) donde el encuadre coincide,
# y en los instantes de bitmap -el menu y el mapa- la VRAM entera identica byte
# a byte, sprites escondidos incluidos. Los PNG quedan en work/vista_png para
# mirarlos, que un hash no lo hace; y tools/omsx_captura_vista.tcl saca
# capturas del emulador de verdad (make captura_vista).
#
# Se hace con la pantalla APAGADA en las dos: encendida, el VDP pierde bytes.
# Una tercera pasada, con la pantalla encendida y solo la ROM nueva, comprueba
# que a la rutina nueva NO se le cae ninguno: sus bucles van al ritmo que el
# VDP admite.
#
# OJO CON LA REFERENCIA: se comprueba antes que las dos ROMs son distintas.
.PHONY: verifica_vista verifica_vista_parche mide_vista captura_vista
# Capturas del emulador de verdad, con la ROM que se diga (por defecto la
# parcheada con todo): make captura_vista ROM=war_musica.rom
captura_vista: $(ROM)
	@rm -rf work/captura_vista
	WAR_OUT="$(abspath work/captura_vista)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath $(ROM))" -romtype ascii16 -script tools/omsx_captura_vista.tcl
	@cat work/captura_vista/captura_vista.log

# Lo mismo que verifica_vista pero con la cinta PARCHEADA: la que se juega.
verifica_vista_parche: war_unificada.rom work/war_parche_sin_vista.rom
	@cmp -s war_unificada.rom work/war_parche_sin_vista.rom && { echo "la ROM de referencia es IDENTICA a la nueva: el cotejo no diria nada"; exit 1; } || true
	@rm -rf work/vistap_ref work/vistap_nueva work/vistap_encendida work/vistap_png
	WAR_OUT="$(abspath work/vistap_ref)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_parche_sin_vista.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	WAR_OUT="$(abspath work/vistap_nueva)" WAR_DIRS="$(abspath work/unificada/vista.tcl)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_unificada.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	WAR_OUT="$(abspath work/vistap_encendida)" WAR_DIRS="$(abspath work/unificada/vista.tcl)" WAR_PANTALLA=encendida $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_unificada.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	@cat work/vistap_nueva/coteja_vista.log
	python3 tools/coteja_vista.py work/vistap_nueva work/vistap_ref work/vistap_png --plan work/unificada/plan.json --work work/cuerpos_parche --roms war_unificada.rom work/war_parche_sin_vista.rom --encendida work/vistap_encendida
verifica_vista: war_musica.rom work/war_sin_vista.rom
	@cmp -s war_musica.rom work/war_sin_vista.rom && { echo "la ROM de referencia es IDENTICA a la nueva: el cotejo no diria nada"; exit 1; } || true
	@rm -rf work/vista_ref work/vista_nueva work/vista_encendida work/vista_png
	WAR_OUT="$(abspath work/vista_ref)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sin_vista.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	WAR_OUT="$(abspath work/vista_nueva)" WAR_DIRS="$(abspath work/musica/vista.tcl)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	WAR_OUT="$(abspath work/vista_encendida)" WAR_DIRS="$(abspath work/musica/vista.tcl)" WAR_PANTALLA=encendida $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	@cat work/vista_nueva/coteja_vista.log
	python3 tools/coteja_vista.py work/vista_nueva work/vista_ref work/vista_png --plan work/musica/plan.json --work work --roms war_musica.rom work/war_sin_vista.rom --encendida work/vista_encendida

# EL MAPA GENERAL Y EL GUANTE. Los dos cambios que se ven en la otra pantalla:
# el lienzo ya dibujado -que la ROM descomprime en vez de recorrer 23.500
# casillas- y el guante, que era un sprite por software estampado en ese mismo
# lienzo y ahora son dos sprites de verdad.
#
# Las dos ROMs se llevan a los mismos instantes del bucle de partida (contados
# por VUELTAS, que van a distinta velocidad) y se vuelca el lienzo, la VRAM
# entera y el estado del guante. tools/coteja_mapa.py exige TRES cosas: que el
# lienzo de la vieja sea el que dibuja tools/mapa_general.py, que el que
# descomprime la nueva sea el mismo byte a byte, y que lo que se ve en pantalla
# -compuesto como lo compone el VDP, sprites incluidos- sea identico pixel a
# pixel. De paso comprueba que la VRAM de cada una es su lienzo subido, que es
# lo que cazaria un byte perdido por el VDP.
#
# El corte es 0x7F5A y no 0x7F57: ahi la vieja ya ha subido su recuadro y la
# nueva ya ha puesto sus sprites, asi que las dos se miran en el mismo punto.
.PHONY: verifica_mapa verifica_mapa_parche
verifica_mapa: war_musica.rom work/war_sin_vista.rom
	@cmp -s war_musica.rom work/war_sin_vista.rom && { echo "la ROM de referencia es IDENTICA a la nueva: el cotejo no diria nada"; exit 1; } || true
	@rm -rf work/lienzo_ref work/lienzo_nuevo work/lienzo_png
	WAR_OUT="$(abspath work/lienzo_ref)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sin_vista.rom)" -romtype ascii16 -script tools/omsx_lienzo.tcl
	WAR_OUT="$(abspath work/lienzo_nuevo)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_lienzo.tcl
	@echo "ANTES, recorriendo las casillas ($(MAQUINA)):"
	@grep -E "DIBUJA_EL_MAPA|vuelta del bucle" work/lienzo_ref/lienzo.log
	@echo "DESPUES, descomprimiendo el lienzo:"
	@grep -E "DIBUJA_EL_MAPA|vuelta del bucle" work/lienzo_nuevo/lienzo.log
	python3 tools/coteja_mapa.py work/lienzo_nuevo work/lienzo_ref work/lienzo_png --plan work/musica/plan.json --work work

# ¿CAMBIA EL TERRENO MIENTRAS SE JUEGA? Es lo que sostiene que el mapa pueda
# viajar dibujado. Se reproduce la partida grabada de Araubi -sobre la CINTA,
# que la pregunta es del juego y no del cartucho-, se vuelca el mapa al empezar
# y al acabar, y se comparan los nibbles bajos, que es lo unico que se dibuja.
# El log dice ademas quien escribe en el mapa mientras se juega.
.PHONY: verifica_terreno
verifica_terreno: work/replay/war_replay.omr
	@rm -rf work/terreno_quieto
	WAR_REPLAY="$(abspath work/replay/war_replay.omr)" WAR_OUT="$(abspath work/terreno_quieto)" 	  $(OPENMSX) -machine $(MAQUINA) -script tools/omsx_terreno_quieto.tcl
	@grep -v loadreplay work/terreno_quieto/terreno_quieto.log
	python3 tools/coteja_terreno.py work/terreno_quieto work

work/replay/war_replay.omr: WarInMiddleEarth.omr war.tsx tools/prepara_replay.py
	@mkdir -p work/replay
	python3 tools/prepara_replay.py WarInMiddleEarth.omr war.tsx $@

# Lo mismo con la cinta PARCHEADA, que es la que se juega.
verifica_mapa_parche: war_unificada.rom work/war_parche_sin_vista.rom
	@cmp -s war_unificada.rom work/war_parche_sin_vista.rom && { echo "la ROM de referencia es IDENTICA a la nueva"; exit 1; } || true
	@rm -rf work/lienzop_ref work/lienzop_nuevo work/lienzop_png
	WAR_OUT="$(abspath work/lienzop_ref)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_parche_sin_vista.rom)" -romtype ascii16 -script tools/omsx_lienzo.tcl
	WAR_OUT="$(abspath work/lienzop_nuevo)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_unificada.rom)" -romtype ascii16 -script tools/omsx_lienzo.tcl
	@grep -E "DIBUJA_EL_MAPA|vuelta del bucle" work/lienzop_ref/lienzo.log work/lienzop_nuevo/lienzo.log
	python3 tools/coteja_mapa.py work/lienzop_nuevo work/lienzop_ref work/lienzop_png --plan work/unificada/plan.json --work work/cuerpos_parche

# LA MARCA DE LAS UNIDADES: que el dibujo se pone donde toca y, sobre todo,
# que se BORRA al moverse la unidad. Se deja correr el bucle hasta el quinto
# repintado del mapa -uno cada 256 vueltas- y se cotejan dos de ellos con la
# pantalla ENCENDIDA, que es como se juega: asi el cotejo mide tambien el
# ritmo del VDP. El cotejo se declara INUTIL si entre los dos repintados no se
# movio ninguna unidad.
.PHONY: verifica_marcas
verifica_marcas: war_unificada.rom
	@rm -rf work/marcas
	WAR_OUT="$(abspath work/marcas)" \
	  WAR_MARCAS_N="0x$$(grep -E '^MARCAS_N' work/unificada/nombres.sym | sed -E 's/.*EQU 0*([0-9A-Fa-f]+)H/\1/')" \
	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_unificada.rom)" -romtype ascii16 -script tools/omsx_marcas.tcl
	@grep -E "repintado|MARCAS_N" work/marcas/marcas.log
	python3 tools/coteja_marcas.py work/marcas src/cartucho/marca.png

# Y LA MEDIDA: ciclos por vuelta de la vista y vueltas por segundo, antes y
# despues, con la misma sonda. Un numero, no una impresion.
mide_vista: war_musica.rom work/war_sin_vista.rom
	@rm -rf work/vista_antes work/vista_despues
	WAR_OUT="$(abspath work/vista_antes)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sin_vista.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	WAR_OUT="$(abspath work/vista_despues)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	@echo "ANTES, sin la tabla de nombres ($(MAQUINA)):"
	@grep -E "ciclos|vueltas por segundo" work/vista_antes/vista.log
	@echo "DESPUES, con ella:"
	@grep -E "ciclos|vueltas por segundo" work/vista_despues/vista.log

# LA SOMBRA, MEDIDA. La misma ROM con la sombra de 768 B (solo se suben las
# filas que cambian) contra la que sube las 768 celdas siempre, en REPOSO -solo
# parpadea el cursor- y MOVIENDO el cursor -cambia el trozo entero-. Y el cotejo
# por pixel de la de sombra contra la referencia, que ahorrar no vale si pinta
# otra cosa.
work/war_sombra.rom: extract $(CARTUCHO) tools/haz_rom.py tools/cursor.py tools/guante.py tools/mapa_general.py src/cartucho/musica.asm src/cartucho/puente.asm src/cartucho/pt3_player.asm src/cartucho/pt3_trabajo.inc src/cartucho/finales.asm src/cartucho/nombres.asm src/cartucho/cursor.png src/cartucho/guante.png
	python3 tools/haz_rom.py work $@ --espera $(ESPERA) --comprime --musica "$(MUSICA)" --finales-rom --vista-sombra --salidas work/sombra

.PHONY: mide_sombra
mide_sombra: war_musica.rom work/war_sombra.rom work/war_sin_vista.rom
	@cmp -s war_musica.rom work/war_sombra.rom && { echo "la ROM con sombra es IDENTICA a la de sin sombra"; exit 1; } || true
	@rm -rf work/sombra_reposo work/sombra_mueve work/sinsombra_reposo work/sinsombra_mueve work/vista_sombra work/vista_ref_sombra work/sombra_png
	WAR_OUT="$(abspath work/sinsombra_reposo)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	WAR_OUT="$(abspath work/sombra_reposo)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sombra.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	WAR_OUT="$(abspath work/sinsombra_mueve)" WAR_MUEVE=1 $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	WAR_OUT="$(abspath work/sombra_mueve)" WAR_MUEVE=1 $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sombra.rom)" -romtype ascii16 -script tools/omsx_vista.tcl
	WAR_OUT="$(abspath work/vista_ref_sombra)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sin_vista.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	WAR_OUT="$(abspath work/vista_sombra)" WAR_DIRS="$(abspath work/sombra/vista.tcl)" $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath work/war_sombra.rom)" -romtype ascii16 -script tools/omsx_coteja_vista.tcl
	python3 tools/coteja_vista.py work/vista_sombra work/vista_ref_sombra work/sombra_png --plan work/sombra/plan.json --work work --roms work/war_sombra.rom work/war_sin_vista.rom
	@for d in sinsombra_reposo sombra_reposo sinsombra_mueve sombra_mueve; do echo "--- $$d ($(MAQUINA)):"; grep -E "VUELTA|vueltas por segundo" work/$$d/vista.log; done

# PARA MIRARLO TU. Arranca la ROM con musica en el emulador, sin scripts ni
# volcados, y te deja jugar:
#   make juega
#   make juega ROM=war.rom            (la conversion fiel, sin musica)
#
# Y las dos pantallas finales, que de otro modo habria que ganarse o perderse la
# partida entera para verlas. Salen de la ROM, descomprimidas con ZX0:
#   make ve_final
#   make ve_final PANTALLA=derrota
ROM      := war_unificada.rom
PANTALLA := victoria

.PHONY: juega ve_final

juega: $(ROM)
	$(OPENMSX) -machine $(MAQUINA) -carta "$(abspath $(ROM))" -romtype ascii16

ve_final: war_musica.rom
	WAR_PANTALLA=$(PANTALLA) $(OPENMSX) -machine $(MAQUINA) 	  -carta "$(abspath war_musica.rom)" -romtype ascii16 -script tools/omsx_ve_final.tcl

# Ver el juego corriendo desde el cartucho: el menu y, tras pulsar 0, el mapa.
captura_rom: war.rom
	@rm -rf work/captura
	WAR_ROM="$(abspath war.rom)" WAR_OUT="$(abspath work/captura)" WAR_CAPTURA=1 \
	  $(OPENMSX) -machine $(MAQUINA) -carta "$(abspath war.rom)" -romtype ascii16 -script tools/omsx_verifica_rom.tcl
	@grep -v volcado work/captura/verifica_rom.log
