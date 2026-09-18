// Comprueba que tools/editor_marcas.html NO ESTA ROTO: corre su guion entero
// con un DOM de pega -incluido el `pinta()` del final, que dibuja el lienzo,
// las paletas y la previa- y comprueba la unica cuenta que tiene, la del
// atributo del ZX.
//
// Hace falta porque los tests de Python leen el HTML con expresiones regulares
// y eso NO ve un error de sintaxis: el 2026-09-18 una sustitucion mal cortada
// dejo un `}` huerfano y setenta lineas duplicadas, los cuatro tests de
// tests/test_editor_marcas.py siguieron en verde y el editor se abria EN BLANCO.
//
//     node tools/prueba_editor_marcas.js
//
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const raiz = path.dirname(__dirname);
const html = fs.readFileSync(path.join(raiz, "tools/editor_marcas.html"), "utf8");
const guion = html.match(/<script>([\s\S]*)<\/script>/)[1];

const nodo = () => ({
  textContent: "", innerHTML: "", className: "", style: {}, title: "", checked: true,
  classList: { toggle() {}, add() {} }, addEventListener() {},
  appendChild() {}, querySelectorAll: () => [], onclick: null, onchange: null,
  getContext: () => new Proxy({}, { get: () => () => ({ data: [] }) }),
  getBoundingClientRect: () => ({ left: 0, top: 0 }),
});
global.document = { getElementById: nodo, createElement: nodo, querySelectorAll: () => [] };
global.window = { addEventListener() {} };
global.Image = class { set src(_v) {} get complete() { return false; } get width() { return 0; } };

let api;
try {
  api = vm.runInThisContext(guion + "\n;({atributoDe, estado, MARCAS, ALCANZABLES});");
} catch (e) {
  console.log("el guion del editor NO corre: " + e.message);
  console.log(e.stack.split("\n").slice(0, 4).join("\n"));
  process.exit(1);
}
const { atributoDe, estado, MARCAS, ALCANZABLES } = api;

let fallos = 0;
function exige(ok, que) {
  if (!ok) { console.log("  MAL  " + que); fallos++; } else { console.log("  ok   " + que); }
}

exige(MARCAS.length >= 2 && MARCAS.includes("anillo") && MARCAS.includes("escudo"),
      "estan el anillo y el escudo");
for (const m of MARCAS) {
  const e = estado[m];
  exige(e && e.p && e.p.length === 8 && e.p[0].length === 8, `${m}: el dibujo es de 8x8`);
  exige(atributoDe(e.tinta, e.papel) !== null, `${m}: sus dos colores caben en un atributo`);
}
exige(ALCANZABLES.length === 12, "se ofrecen doce colores, los que el juego puede dar");
// negro sobre blanco: lo dan 0x38 y 0x78, y tiene que salir el que el juego usa
exige(atributoDe(1, 15) === 0x78, "negro sobre blanco da 0x78, el atributo que el juego ya pone");
exige(atributoDe(15, 1) === 0x47, "blanco sobre negro da 0x47");
// verde claro solo esta en la tabla CON brillo y el azul oscuro en la de SIN
exige(atributoDe(3, 4) === null, "verde claro sobre azul oscuro no cabe: distinto brillo");
exige(atributoDe(1, 7) !== null, "negro sobre cian si, que el cian esta en las dos tablas");

console.log(fallos ? `${fallos} fallos` : "el editor de marcas corre y sus cuentas cuadran");
process.exit(fallos ? 1 : 0);
