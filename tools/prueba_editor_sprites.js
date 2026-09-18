// Comprueba el editor de sprites SIN navegador: corre su propio codigo con un
// DOM de pega y exige dos cosas.
//
//   1. la ida y vuelta del formato: los 32 bytes por cuadrantes que el editor
//      lee al arrancar vuelven a salir identicos de bytesDe()
//   2. lo que el editor GUARDARIA -el color del MSX de cada pixel, o
//      transparente- es exactamente lo que hay en src/cartucho/*.png
//
// Lo segundo lo cierra tests/test_editor_sprites.py, que compara el JSON que
// deja esto con lo que leen tools/cursor.py y tools/guante.py. Correrlo:
//
//     node tools/prueba_editor_sprites.js work/editor_sprites.json
//
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const raiz = path.dirname(__dirname);
const html = fs.readFileSync(path.join(raiz, "tools/editor_sprites.html"), "utf8");
const guion = html.match(/<script>([\s\S]*)<\/script>/)[1];

// El DOM justo para que el guion arranque: nada de esto dibuja.
const nodo = () => ({
  textContent: "", className: "", style: {}, title: "", checked: true,
  classList: { toggle() {}, add() {} }, addEventListener() {},
  appendChild() {}, querySelectorAll: () => [], onclick: null, onchange: null,
  getContext: () => new Proxy({}, { get: () => () => ({ data: [] }) }),
  getBoundingClientRect: () => ({ left: 0, top: 0 }),
});
global.document = {
  getElementById: nodo, createElement: nodo, querySelectorAll: () => [],
};
global.window = { addEventListener() {} };
global.Image = class { set src(_v) {} get complete() { return false; } get width() { return 0; } };

const api = vm.runInThisContext(guion + "\n;({SPRITES, estado, DE_FABRICA, colorDe, bytesDe, MSX});");
const { SPRITES, estado, DE_FABRICA, colorDe, bytesDe, MSX } = api;

let fallos = 0;
const hex = b => b.map(v => v.toString(16).padStart(2, "0")).join("");

// 1. ida y vuelta de los 32 bytes por cuadrantes
for (const s of SPRITES) {
  const e = estado[s.id], d = DE_FABRICA[s.id];
  for (let p = 0; p < 2; p++) {
    const salen = hex(bytesDe(e.planos[p]));
    if (salen !== d[p * 2 + 1]) {
      console.log(`FALLA ${s.id} plano ${"AB"[p]}:\n  esperaba ${d[p * 2 + 1]}\n  y sale   ${salen}`);
      fallos++;
    }
    if (e.colores[p] !== d[p * 2]) {
      console.log(`FALLA ${s.id} color ${"AB"[p]}: esperaba ${d[p * 2]} y hay ${e.colores[p]}`);
      fallos++;
    }
  }
}

// 2. lo que se guardaria, pixel a pixel: indice de la paleta del MSX o 0
const fuera = {};
for (const s of SPRITES) {
  const filas = [];
  for (let y = 0; y < 16; y++) {
    const fila = [];
    for (let x = 0; x < 16; x++) {
      const c = colorDe(s.id, x, y);
      fila.push(c ? MSX.findIndex(m => m && m[0] === c[0] && m[1] === c[1] && m[2] === c[2]) : 0);
    }
    filas.push(fila);
  }
  fuera[s.id] = { png: s.png, hueco: s.hueco, indices: filas };
}

const salida = process.argv[2] || path.join(raiz, "work/editor_sprites.json");
fs.mkdirSync(path.dirname(salida), { recursive: true });
fs.writeFileSync(salida, JSON.stringify(fuera, null, 1));
console.log(fallos ? `${fallos} fallos` : "el editor lee y escribe los cuatro sprites igual que el repositorio");
console.log(`${salida}: lo que el editor guardaria, para tests/test_editor_sprites.py`);
process.exit(fallos ? 1 : 0);
