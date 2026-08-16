/* ============================================================================
   Развёртка кривых уровня под целевую глубину забега.

   Цель задана в TARGETS: до какого уровня доходит «средний» игрок. Скрипт
   перебирает кривые (разгон гравитации, разгон спавна, рост лимита тел),
   гоняет симулятор и печатает лучшие комбинации.

   Запуск:  node tools/tune.js [runs]
   ========================================================================== */

const CONFIG = require('./config.js');
const { run } = require('./sim.js');

// lvl — целевая медиана уровня для скилла average
// span — во сколько раз pro должен уходить дальше novice (скилл должен решать)
const TARGETS = {
  casual:   { lvl: 17, span: 1.8 },
  normal:   { lvl: 12, span: 1.7 },
  hardcore: { lvl: 6,  span: 1.8 },
};

// Крутим то, что реально двигает глубину: скорость разгона гравитации, скорость
// разгона спавна и то, как быстро растёт лимит тел на поле. Сами потолки (gMax,
// sMin) заданы физикой — см. BALANCE.md §8, ниже цикла в 1.3 с человек не живёт.
const GRID = {
  gTau: [14, 18, 22, 26],
  sTau: [16, 22, 28],
  fieldStep: [4, 6, 8],
};

const RUNS = Number(process.argv[2] || 40);
const median = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];

for (const diff of Object.keys(TARGETS)) {
  const T = TARGETS[diff];
  const base = CONFIG.difficulty[diff];
  const g0 = base.gravity.g0, gMax = base.gravity.gMax;
  const s0 = base.spawn.s0, sMin = base.spawn.sMin;
  const n0 = base.field.n0;
  const results = [];

  for (const gTau of GRID.gTau) {
    for (const sTau of GRID.sTau) {
      for (const fieldStep of GRID.fieldStep) {
        base.gravity = { g0, gMax, tau: gTau };
        base.spawn = { s0, sMin, tau: sTau };
        base.field = { n0, step: fieldStep };

        const lvl = {};
        for (const skill of ['novice', 'average', 'pro']) {
          const rs = [];
          for (let i = 0; i < RUNS; i++) rs.push(run(diff, skill, i * 7919 + 13));
          lvl[skill] = median(rs.map((r) => r.level));
        }
        const span = lvl.pro / Math.max(1, lvl.novice);
        const err = Math.abs(lvl.average - T.lvl) / T.lvl +
                    0.5 * Math.abs(span - T.span) / T.span;
        results.push({ gTau, sTau, fieldStep, lvl, span, err });
      }
    }
  }

  results.sort((a, b) => a.err - b.err);
  console.log(`\n=== ${diff}  (цель: средний до ${T.lvl}-го, разброс ×${T.span}) ===`);
  console.log('  gTau  sTau  тел/шаг   novice  average  pro   разброс  ошибка');
  for (const r of results.slice(0, 6)) {
    console.log(
      String(r.gTau).padStart(6) + String(r.sTau).padStart(6) +
      String(r.fieldStep).padStart(9) +
      String(r.lvl.novice).padStart(9) + String(r.lvl.average).padStart(9) +
      String(r.lvl.pro).padStart(5) +
      r.span.toFixed(2).padStart(9) + r.err.toFixed(3).padStart(9));
  }
}
