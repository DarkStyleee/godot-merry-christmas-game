/* ============================================================================
   Развёртка параметров спавна под целевую кривую сложности.

   Цели заданы в TARGETS: медиана длительности забега для «среднего» игрока
   и желаемое число тел на поле в эндгейме. Скрипт перебирает (s0, sMin, tau,
   hp), гоняет симулятор и печатает лучшие комбинации.

   Запуск:  node tools/tune.js [runs]
   ========================================================================== */

const CONFIG = require('../config.js');
const { run } = require('./sim.js');

// tMid — целевая медиана забега для скилла average, с
// nEnd — целевое число тел на поле в последние 20 с перед проигрышем
const TARGETS = {
  casual:   { tMid: 165, nEnd: 2.5 },
  normal:   { tMid: 115, nEnd: 3.0 },
  hardcore: { tMid: 72,  nEnd: 3.5 },
};

// Спавн уже упёрся в потолок пропускной способности, поэтому крутим то, что
// реально двигает сложность: запас HP и кривую разгона гравитации.
const GRID = {
  gMax: [900, 1150, 1400],
  gTau: [70, 110, 150],
  sMin: [1.4, 2.0],
};
const HP_GRID = { casual: [7, 8, 9], normal: [5, 6, 7], hardcore: [4, 5, 6] };

const RUNS = Number(process.argv[2] || 60);
const median = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];
const tail = (s, n) => s.slice(Math.max(0, s.length - n));
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);

for (const diff of Object.keys(TARGETS)) {
  const T = TARGETS[diff];
  const base = CONFIG.difficulty[diff];
  const results = [];

  const s0 = base.spawn.s0, sTau = base.spawn.tau, g0 = base.gravity.g0;

  for (const hp of HP_GRID[diff]) {
    for (const gMax of GRID.gMax) {
      for (const gTau of GRID.gTau) {
        for (const sMin of GRID.sMin) {
          base.hpStart = hp; base.hpMax = hp;
          base.spawn = { s0, sMin, tau: sTau };
          base.gravity = { g0, gMax, tau: gTau };

          const rs = [];
          for (let i = 0; i < RUNS; i++) rs.push(run(diff, 'average', i * 7919 + 13));
          const med = median(rs.map((r) => r.survived));
          const nEnd = mean(rs.map((r) => mean(tail(r.nSamples, 20))));
          const err = Math.abs(med - T.tMid) / T.tMid +
                      0.5 * Math.abs(nEnd - T.nEnd) / T.nEnd;
          results.push({ hp, gMax, gTau, sMin, med, nEnd, err });
        }
      }
    }
  }

  results.sort((a, b) => a.err - b.err);
  console.log(`\n=== ${diff}  (цель: медиана ${T.tMid} c, тел на поле ${T.nEnd}) ===`);
  console.log('  hp  gMax  gTau  sMin   медиана   тел   ошибка');
  for (const r of results.slice(0, 6)) {
    console.log(
      String(r.hp).padStart(4) + String(r.gMax).padStart(6) +
      String(r.gTau).padStart(6) + r.sMin.toFixed(1).padStart(6) +
      r.med.toFixed(1).padStart(10) + 'с' + r.nEnd.toFixed(1).padStart(6) +
      r.err.toFixed(3).padStart(9));
  }
}
