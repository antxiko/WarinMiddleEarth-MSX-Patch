# Aviso legal y atribución

*(Also available [in English](LEGAL-NOTICE.md).)*

## De quién es cada cosa

**El juego no es nuestro.** *War in Middle Earth* se publico para MSX en cinta. **El binario no lleva ni un credito dentro** -ni editor, ni ano, ni nombres-, asi que aqui no se afirma quien lo hizo: lo unico que se puede decir leyendo la cinta es lo que hace el codigo. Todos los derechos sobre el juego siguen siendo de
sus titulares.

**Lo que sí es nuestro** son las herramientas de este repositorio, los
comentarios del listado, el análisis y la documentación. Eso se publica con la
licencia de `LICENSE`.

## Qué hay en este repositorio

Los ficheros de `src/` son el desensamblado de los cinco modulos de la cinta. Se
publica para la **preservación, el estudio y la documentación** de un título que es parte de la historia del software del MSX.

La imagen de la cinta **no** se distribuye aquí. Quien quiera volver
a montar el listado tiene que poner la suya, y el `Makefile` comprueba su
sha256 antes de hacer nada.

Las imágenes que produce `tools/render_graficos.py` no son ilustraciones traídas de
fuera: son la memoria de vídeo del propio juego, reconstruida repitiendo las
copias que hace el cartucho —las mismas direcciones y el mismo orden que están
en el listado— y dibujada tal cual. Son parte de la prueba de que la lectura
del binario es correcta: si estuviera mal, saldría ruido.

## En qué se apoya

En nada de nadie. Todo lo que se afirma aquí sale de leer este binario, y cada
afirmación lleva su evidencia al lado: la instrucción que lee un dato, la tabla
que cierra exactamente donde tiene que cerrar, o la cuenta que sale sola. Lo
que no está cerrado se dice que no lo está.

## Si eres uno de los autores

Si trabajaste en *War in Middle Earth* o tienes derechos sobre el juego, y
preferirías que este material no estuviera publicado, **dilo y se retira, sin
discusión**. La intención de este trabajo es justo la contraria de
perjudicarte: es dejar constancia de cómo se hizo.
