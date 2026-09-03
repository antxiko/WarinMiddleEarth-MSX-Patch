# Empezar

Esto es un **parche de jugabilidad** para la cinta MSX de *War in Middle Earth*
(Melbourne House / Dro Soft, 1989). No es el juego: es lo que se le cambia.

**Aquí no hay ninguna imagen de cinta.** Se reparte el parche y cada cual lo
aplica sobre su copia.

## La vía rápida: el IPS

En el repositorio hay un **`war_parche.ips`** de 249 bytes. Lleva sólo los bytes
que cambian —código nuestro y el dibujo del Ojo de Sauron— y se aplica sobre tu
propia cinta con cualquier herramienta de IPS, o con la que viene aquí:

    python3 tools/ips.py --aplica war.tsx war_parche.ips war_parche.tsx

Tu cinta tiene que ser la misma que se usó para sacarlo. Su huella es
`sha256 13c63632…b1d81208`; si la tuya es otra, el parche se aplicará igual pero
nadie garantiza el resultado.

## La vía larga: montarlo tú

Necesitas Python 3 y `make`. Pon tu `war.tsx` en la raíz y:

    make extract     # saca los cuerpos de los bloques de tu cinta a work/
    make parche      # aplica la tabla y escribe war_parche.tsx
    make ips         # y war_parche.ips, el parche a secas
    make test        # las 23 comprobaciones

`make parche` no escribe a ciegas: **cada cambio comprueba antes que los bytes
originales son los que espera**, y si al terminar hay un solo byte distinto
fuera de la tabla, aborta. Por eso es seguro dejarlo correr sobre tu copia.

## Jugarlo

    openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx

y en el MSX, `RUN"CAS:"`. La carga entera son unos seis minutos y medio de
tiempo emulado; con el acelerador del emulador, mucho menos.

## Qué vas a ver distinto

- **Las unidades enemigas se dibujan en el mapa**, con el Ojo de Sauron, para
  no confundirlas con las tuyas.
- **La ficha de cada unidad enseña el número** de sus seis apartados, no sólo
  «es muy hábil».
- **En la ficha del portador del Anillo**, a la izquierda del anillo, salen los
  **meses que quedan** antes de sucumbir.

Para llegar a la ficha de Frodo: pon el cursor sobre la casilla de la Comunidad,
dispara, y con arriba y abajo vas pasando de una unidad a otra hasta llegar a
él. El número del anillo sólo sale en la ficha del portador, que es donde el
juego dibuja el anillo.

## Antes de juzgarlo

**Nadie ha jugado una partida entera con el parche puesto.** Lo que se sabe que
falta está en [Preguntas abiertas](PREGUNTAS-ABIERTAS.md), y se agradece que lo
juegues y lo cuentes.

## De dónde sale

De un [desensamblado comentado](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly)
de la cinta entera, que es **otro repositorio y otra web**. Todas las direcciones
que se citan aquí salen de aquel listado, no de probar a ver qué pasa.
