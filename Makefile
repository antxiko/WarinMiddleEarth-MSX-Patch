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

.PHONY: all verify clean extract cuerpos trazado listados sanity test cinta imagenes web parche verifica_parche

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
	@mkdir -p docs/imagenes
	@python3 tools/render_carga.py work/pantalla.raw docs/imagenes/carga.png
	@python3 tools/render_graficos.py work/alto.raw docs/imagenes

# ------------------------------------------------------------------ el parche
# EL PARCHE DE ARAUBI. Aplica la tabla de tools/parchea.py sobre los cuerpos de
# la cinta (work/*.raw, que salen de `make extract`, o sea de TU cinta) y arma
# la cinta parcheada war_parche.tsx: enemigas visibles y con el Ojo de Sauron,
# los valores numericos en la ficha y el plazo del Anillo. Ver INVESTIGACION.md.
parche: extract src/parche/ficha_valores.asm src/parche/icono_enemigo.asm
	python3 tools/parchea.py work war_parche.tsx

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
