# War in Middle Earth (MSX) — el parche de Araubi

> ## ⚠️ TRABAJO EN CURSO — este parche **no esta terminado**
>
> Las tres cosas que hace estan puestas y verificadas en un MSX real con
> openMSX, pero se publica como trabajo en curso a proposito: nadie ha jugado
> una partida entera con el puesto, la ficha se ha visto en el jefe de una
> formacion pero no en todos los tipos de unidad, y el medidor del Anillo
> siempre a la vista esta sin hacer. La lista completa esta al final. Leela
> antes de juzgar una captura.

Un parche de bytes para la cinta MSX de **War in Middle Earth** (Melbourne House
/ Dro Soft, 1989), montado encima del
[desensamblado comentado](https://github.com/antxiko/WarinMiddleEarth-MSX-disassembly).
Hace las tres cosas que **Araubi** pidio en el foro: hacer visibles las unidades
enemigas, ensenar el valor numerico de cada apartado de una unidad, y sacar a la
luz el contador de corrupcion del Anillo.

[README in English](README.md) · Investigacion completa: [INVESTIGACION.md](INVESTIGACION.md)

## La cinta no esta aqui

No se distribuye ninguna imagen de cinta, solo el trabajo del parche (ver
[AVISO-LEGAL.md](AVISO-LEGAL.md)). Pones tu propia `war.tsx` (sha256
`13c63632…b1d81208`) y:

    make extract     # saca los cuerpos de los bloques de tu cinta a work/
    make parche      # aplica la tabla y escribe war_parche.tsx
    make test        # las comprobaciones

`war_parche.tsx` es la cinta parcheada, del mismo tamano que la original, lista
para un MSX1 real (`openmsx -machine Philips_VG_8020 -cassetteplayer war_parche.tsx`).

## Que cambia

Todo cae en el bloque medio del juego (corre en `0x5E00`), **80 bytes en tres
cambios**, cada uno comprobando los bytes que espera antes de escribir — nada se
desplaza, y `make parche` falla si cambia un solo byte fuera de la tabla
(`tools/parchea.py`).

**1 · Las unidades enemigas se ven.** El mapa guarda un bit de "aqui hay
alguien" por casilla, y `RECENTRA_EL_MAPA` (0x7FAC) lo vuelve a sembrar unidad a
unidad — pero su bucle para en la unidad `0x78`, justo donde empieza el bando
enemigo, asi que al enemigo nunca se le siembra ni se le dibuja. Cambiar el tope
del bucle de `0x78` a `0x00` (**un byte, en 0x7FD1**) hace que recorra las 256
unidades. Verificado: **se siembran 136 unidades enemigas donde antes cero**.

**2 · Cada apartado ensena su numero.** La ficha de una unidad lista seis
cualidades —Valioso, Habil, Duro, Bravo, Energico, Decidido— como adverbio +
adjetivo ("Muy Bravo"), nunca como numero. Una rutina nueva
(`MUESTRA_LOS_VALORES`, 76 bytes), escrita encima del **motor del altavoz del ZX
Spectrum de 0x6600 que en esta conversion no llama nadie**, lee los seis valores
(de `0xC000`/`0xC100`/`0xC200`/`0xC300`) y los escribe en cifras en la ficha. La
engancha un trampolin de tres bytes en `0x708A`. Verificado contra los valores
reales: los seis coinciden.

**3 · El contador de corrupcion del Anillo se ve.** `0xC300+n` es el contador
que el mensaje mensual "El Anillo corrompe al que lo usa" sube a cada unidad;
para el portador (Frodo) es su corrupcion. Con el cambio 2 ya sale como numero
en su ficha (Frodo empieza cerca de **176 de 255**). En el binario no hay una
variable de "resistencia" aparte — el Anillo es ese contador y ese mensaje.

Toda la evidencia, las direcciones y la salida de openMSX estan en
[INVESTIGACION.md](INVESTIGACION.md).

## Lo que falta

- **Nadie ha jugado una partida entera** con el parche puesto.
- La ficha se ha visto en el jefe de una formacion (Gandalf) y forzada en el
  portador (Frodo); **no se ha comprobado en todos los tipos de unidad** que el
  numero no choque con un rotulo largo.
- **El medidor del Anillo siempre a la vista no esta hecho.** Ahora el numero
  esta en la ficha; un "Anillo: NNN" fijo en la pantalla de partida queda como
  ampliacion (el gancho esta localizado: `0x733E` da el portador, `0xC300+portador`
  el valor).
- Las siluetas enemigas se dibujan igual que las amigas (sin color que las
  distinga); sembrar tambien para el enemigo el atributo con brillo es una
  opcion documentada.

## Licencia

Las herramientas y la investigacion se publican bajo [LICENSE](LICENSE). **El
juego no**, y la cinta no se distribuye aqui — ver [AVISO-LEGAL.md](AVISO-LEGAL.md).
