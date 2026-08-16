const TRACE = !!process.env.TRACE;
/* ============================================================================
   Headless-симулятор баланса «Merry Christmas».
   Физика идентична игровой; игрок заменён ботом с человеческой моторикой
   (реакция + разгон/потолок скорости мыши + ошибка прицела).

   Запуск:  node tools/sim.js [runs]
   ========================================================================== */

const CONFIG = require('./config.js');

// ---------------------------------------------------------------- ГПСЧ ----
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
// нормаль через Бокса—Мюллера
function gauss(rnd) {
  let u = 0, v = 0;
  while (u === 0) u = rnd();
  while (v === 0) v = rnd();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

// ------------------------------------------------------- модель игрока ----
// react — время простой реакции на смену цели, с (лит.: ~250 мс средний
//         взрослый, 180–200 мс тренированный игрок)
// vmax  — пиковая скорость курсора, px/s
// accel — разгон курсора, px/s^2 (связка accel+vmax воспроизводит закон
//         Фиттса a=0.23 c, b=0.166 c/бит на дистанциях 150–900 px)
// k     — коэффициент моторного шума по закону Шмидта: SD = k * D / T
//         (Schmidt et al. 1979, типичное k ~0.075 для баллистических бросков)
//
// Чистый Шмидт применим только к движению без зрительного контроля. Если у
// игрока остаётся запас времени, он успевает сделать корректирующие досылки,
// каждая режет остаточную ошибку примерно вдвое. Отсюда двухчастная модель
// ниже: при запасе — почти точное попадание, в цейтноте — баллистический
// разброс. Промахи возникают ровно там, где поток перестаёт помещаться.
// Время реакции платится только за неожиданное — за появление нового тела.
// Переключение между телами, которые игрок уже ведёт глазами, стоит лишь
// саккады и запуска движения. Без этого различия бот теряет по 0.2-0.3 с на
// каждой ловле и оказывается вдвое слабее живого жонглёра.
const ANTICIPATED_COST = 0.06;   // с
const TRACKED_AFTER = 0.5;       // с в полёте, после которых тело «ведётся»
const SIGMA_FLOOR = 6;      // тремор, px
const CORR_TIME = 0.22;     // время одной корректирующей досылки, с
const CORR_GAIN = 0.45;     // во сколько раз досылка режет ошибку
const CORR_MAX = 2;         // больше двух досылок человек не успевает
// plan  — насколько игрок планирует удар. Смещение от центра палки задаёт и
//         знак vx, и высоту отскока, то есть куда тело улетит и когда вернётся.
//         Это главная глубина игры: сгонять тела к центру и разводить их по
//         времени, чтобы они не падали одновременно в разные углы. Новичок
//         бьёт «в лоб» и сам себя растаскивает.
const SKILLS = {
  novice:  { react: 0.34, vmax: 1500, accel: 7000,  k: 0.095, plan: 0.20, grabBonus: 0.25, avoidHazard: 0.40 },
  average: { react: 0.26, vmax: 2200, accel: 10000, k: 0.075, plan: 0.50, grabBonus: 0.45, avoidHazard: 0.65 },
  good:    { react: 0.20, vmax: 2800, accel: 14000, k: 0.058, plan: 0.80, grabBonus: 0.60, avoidHazard: 0.80 },
  pro:     { react: 0.16, vmax: 3400, accel: 18000, k: 0.045, plan: 1.00, grabBonus: 0.70, avoidHazard: 0.90 },
};

// складываем координату с отражениями от стен
function foldX(x) {
  const span = A.w - 2 * S.radius;
  let u = ((x - S.radius) % (2 * span) + 2 * span) % (2 * span);
  if (u > span) u = 2 * span - u;
  return u + S.radius;
}

// Выбор точки удара по палке. Считается один раз в момент захвата цели —
// живой игрок тоже решает, куда бить, когда начинает движение.
const D_GRID = [0, 0.15, 0.35, 0.6, 0.85];
const CONFLICT_WINDOW = 0.5;   // с, ближе этого приземления считаем конфликтом
function chooseOffset(p, santas, tgtId, K, halfW, g, t, highOn) {
  const others = [];
  for (const s of santas) {
    if (s.id === tgtId) continue;
    const q = predict(s, g, t);
    if (q) others.push({ t: t + q.t, x: q.x });
  }
  let bestOff = 0, bestScore = -Infinity;
  for (const d of D_GRID) {
    for (const sgn of d === 0 ? [1] : [1, -1]) {
      let h = bounceH(d);
      if (highOn) h *= CONFIG.items.highFactor;
      h = Math.min(h, S.hCap);
      const vy = Math.sqrt(2 * g * h * A.h);
      const tNext = (2 * vy) / g;
      const vx = Math.max(-S.vxMax, Math.min(S.vxMax, sgn * S.vxBase * d));
      const xNext = foldX(p.x + vx * tNext);
      const landAt = t + p.t + tNext;

      let plan = 0;
      for (const o of others) {                       // штраф за конфликт
        const dtime = Math.abs(o.t - landAt);
        if (dtime < CONFLICT_WINDOW) {
          plan -= (CONFLICT_WINDOW - dtime) * Math.min(Math.abs(o.x - xNext), 600) * 0.02;
        }
      }
      plan -= Math.abs(A.w / 2 - xNext) * 0.01;       // тянем к центру

      const score = K.plan * plan +
        (d <= P.sweetZone ? 6 : 3) +                  // трезвость за удар
        tNext * 2;                                    // время в воздухе
      if (score > bestScore) { bestScore = score; bestOff = sgn * d * halfW; }
    }
  }
  return bestOff;
}

// СКО ошибки прицела: баллистический разброс, ослабленный досылками
function aimSigma(K, dist, timeLeft) {
  const tReq = travelTime(dist, K.vmax, K.accel);
  const slack = Math.max(0, timeLeft - tReq);
  const corrections = Math.min(CORR_MAX, slack / CORR_TIME);
  const ballistic = K.k * Math.abs(dist) / Math.max(0.15, timeLeft);
  return Math.max(SIGMA_FLOOR, ballistic * Math.pow(CORR_GAIN, corrections));
}

// время перемещения курсора на расстояние d при трапецеидальном профиле
function travelTime(d, vmax, accel) {
  d = Math.abs(d);
  const dAccel = (vmax * vmax) / accel;         // путь на разгон+торможение
  if (d <= dAccel) return 2 * Math.sqrt(d / accel);
  return 2 * (vmax / accel) + (d - dAccel) / vmax;
}

// ------------------------------------------------------------- физика ----
const A = CONFIG.arena, P = CONFIG.paddle, S = CONFIG.santa;
const PADDLE_TOP = P.y - P.height / 2;
const PLANE = PADDLE_TOP - S.radius;            // Y центра Деда в момент удара

function bounceH(d) {
  for (const seg of S.bounce) {
    if (d <= seg.d1) {
      const k = seg.d1 === seg.d0 ? 0 : (d - seg.d0) / (seg.d1 - seg.d0);
      return seg.h0 + (seg.h1 - seg.h0) * k;
    }
  }
  return S.bounce[S.bounce.length - 1].h1;
}

// снос метелью за интервал [t0, t0+T] — точный интеграл
function driftShift(phase, t0, T) {
  const w = S.drift.freq;
  return (S.drift.amp / w) * (Math.cos(w * t0 + phase) - Math.cos(w * (t0 + T) + phase));
}

// предсказание точки и времени касания плоскости палки
function predict(s, g, now) {
  const disc = s.vy * s.vy + 2 * g * (PLANE - s.y);
  if (disc < 0) return null;                    // не долетит (уже вверх и мимо)
  const t = (-s.vy + Math.sqrt(disc)) / g;
  if (t < 0) return null;
  return { t, x: foldX(s.x + s.vx * t + driftShift(s.phase, now || 0, t)) };
}

// Честный спавн: если новое тело приземлится одновременно с уже летящим,
// ставим его рядом — в пределах одного броска руки, а не на другом конце.
function pickSpawnX(santas, g, rnd, t) {
  const lo = S.spawnMargin, hi = A.w - S.spawnMargin;
  const fallT = Math.sqrt((2 * (PLANE + S.radius)) / g);
  const clash = [];
  for (const s of santas) {
    const q = predict(s, g, t);
    if (q && Math.abs(q.t - fallT) < S.fairSpawn.window) clash.push(q.x);
  }
  if (!clash.length) return lo + rnd() * (hi - lo);
  const c = clash[Math.floor(rnd() * clash.length)];
  const near = c + (rnd() * 2 - 1) * S.fairSpawn.reach;
  return Math.max(lo, Math.min(hi, near));
}

// -------------------------------------------------------------- прогон ----
function run(diffKey, skillKey, seed, maxTime = 600) {
  const D = CONFIG.difficulty[diffKey];
  const K = SKILLS[skillKey];
  const rnd = mulberry32(seed);

  let t = 0, hp = D.hpStart, score = 0, mult = 1, streak = 0, maxStreak = 0;
  let bounces = 0, misses = 0, sobered = 0, graceUntil = -1;
  let firstMiss = null;
  const santas = [], items = [];
  const nSamples = [];                          // N раз в секунду
  let nextSample = 0;

  // таймеры спавна
  let nextSanta = 0, nextBonus = D.bonusEvery, nextBrine = D.brineEvery,
      nextHazard = D.hazardFrom;

  // состояние палки
  let px = A.w / 2, pv = 0, aimX = A.w / 2, aimBias = 0, shotOffset = 0,
      targetId = -1, switchAt = -1, pendingId = -1;
  let widthMul = 1, wideUntil = -1, highUntil = -1, slowUntil = -1, snack = 0;
  let uid = 0;

  const dt = 1 / 120;

  while (t < maxTime && hp > 0) {
    const gc = D.gravity;
    let g = gc.gMax - (gc.gMax - gc.g0) * Math.exp(-t / gc.tau);
    if (t < slowUntil) g *= CONFIG.items.slowFactor;
    const halfW = (P.width * (t < wideUntil ? CONFIG.items.wideFactor : 1)) / 2;

    // ---- спавн ------------------------------------------------------------
    if (t >= nextSanta) {
      if (santas.length < S.maxOnField) {
        santas.push({
          id: uid++,
          x: pickSpawnX(santas, g, rnd, t),
          y: -S.radius, vx: 0, vy: 0, sober: 0, phase: rnd() * Math.PI * 2,
          bornAt: t,
        });
        if (TRACE) console.log(`  спавн id=${uid - 1} t=${t.toFixed(2)} x=${santas[santas.length - 1].x.toFixed(0)} N=${santas.length}`);
      }
      const sp = D.spawn;
      nextSanta = t + sp.sMin + (sp.s0 - sp.sMin) * Math.exp(-t / sp.tau);
    }
    if (t >= nextBonus) { items.push({ kind: 'bonus', y: -20 }); nextBonus = t + D.bonusEvery; }
    if (t >= nextBrine) { items.push({ kind: 'brine', y: -20 }); nextBrine = t + D.brineEvery; }
    if (t >= D.hazardFrom && t >= nextHazard) { items.push({ kind: 'hazard', y: -20 }); nextHazard = t + D.hazardEvery; }

    // ---- бот: выбор цели --------------------------------------------------
    let best = null, bestT = Infinity;
    for (const s of santas) {
      const p = predict(s, g, t);
      if (!p) continue;
      // недостижимые цели бросаем — живой игрок делает так же
      if (travelTime(p.x - px, K.vmax, K.accel) > p.t + 0.12) continue;
      if (p.t < bestT) { bestT = p.t; best = { s, p }; }
    }
    if (best && best.s.id !== targetId) {
      if (best.s.id !== pendingId) {
        pendingId = best.s.id;
        const tracked = t - best.s.bornAt > TRACKED_AFTER;
        switchAt = t + (tracked ? ANTICIPATED_COST : K.react);
      }
      if (t >= switchAt) {
        if (TRACE) console.log(`  цель -> id=${best.s.id} t=${t.toFixed(2)} tland=${best.p.t.toFixed(2)} x=${best.p.x.toFixed(0)} px=${px.toFixed(0)}`);
        targetId = best.s.id;
        shotOffset = chooseOffset(best.p, santas, best.s.id, K, halfW, g, t, t < highUntil);
        const want = best.p.x - shotOffset;
        aimBias = gauss(rnd) * aimSigma(K, want - px, best.p.t);
      }
    }
    if (targetId !== -1) {
      const cur = santas.find((s) => s.id === targetId);
      const p = cur && predict(cur, g, t);
      if (p) aimX = p.x - shotOffset + aimBias;
      else targetId = -1;
    }

    // ---- движение палки ---------------------------------------------------
    {
      const lo = halfW, hi = A.w - halfW;
      const want = Math.max(lo, Math.min(hi, aimX));
      const d = want - px;
      const stopDist = (pv * pv) / (2 * K.accel);
      const dir = Math.sign(d);
      if (Math.abs(d) <= stopDist && Math.sign(pv) === dir) {
        pv -= dir * K.accel * dt;                // торможение
      } else {
        pv += dir * K.accel * dt;
      }
      pv = Math.max(-K.vmax, Math.min(K.vmax, pv));
      px += pv * dt;
      if (px < lo) { px = lo; pv = 0; }
      if (px > hi) { px = hi; pv = 0; }
    }
    const paddleSpeed = Math.max(-P.speedClamp, Math.min(P.speedClamp, pv));

    // ---- физика Дедов Морозов --------------------------------------------
    for (let i = santas.length - 1; i >= 0; i--) {
      const s = santas[i];
      const prevY = s.y;
      s.vy += g * dt;
      s.x += (s.vx + S.drift.amp * Math.sin(t * S.drift.freq + s.phase)) * dt;
      s.y += s.vy * dt;

      if (s.x < S.radius) { s.x = S.radius; s.vx = -s.vx * S.wallDamp; }
      if (s.x > A.w - S.radius) { s.x = A.w - S.radius; s.vx = -s.vx * S.wallDamp; }
      if (s.y < S.radius && s.vy < 0) { s.y = S.radius; s.vy = -s.vy * S.wallDamp; }

      // касание палки
      if (s.vy > 0 && prevY <= PLANE && s.y >= PLANE && Math.abs(s.x - px) > halfW && TRACE) {
        console.log(`  МИМО id=${s.id} t=${t.toFixed(2)} sx=${s.x.toFixed(0)} px=${px.toFixed(0)} dx=${(s.x - px).toFixed(0)} target=${targetId} aim=${aimX.toFixed(0)}`);
      }
      if (s.vy > 0 && prevY <= PLANE && s.y >= PLANE && Math.abs(s.x - px) <= halfW) {
        const off = s.x - px;
        const d = Math.min(1, Math.abs(off) / halfW);
        let h = bounceH(d);
        if (t < highUntil) h *= CONFIG.items.highFactor;
        h = Math.min(h, S.hCap);
        s.y = PLANE;
        s.vy = -Math.sqrt(2 * g * h * A.h);
        s.vx = Math.max(-S.vxMax, Math.min(S.vxMax,
          Math.sign(off) * S.vxBase * d + paddleSpeed * S.vxFromPaddle));

        let gain = d <= P.sweetZone ? S.sober.gainSweet : S.sober.gainNormal;
        if (snack > 0) { gain *= 2; snack--; }
        s.sober += gain;

        bounces++; streak++; maxStreak = Math.max(maxStreak, streak);
        mult = Math.min(CONFIG.score.maxMult, 1 + Math.floor(streak / CONFIG.score.comboStep));
        score += CONFIG.score.bounce * mult;

        if (s.sober >= S.sober.threshold) {
          sobered++; score += CONFIG.score.sober * mult;
          santas.splice(i, 1);
          if (targetId === s.id) targetId = -1;
          continue;
        }
      }

      // пол
      if (s.y - S.radius > A.h) {
        santas.splice(i, 1);
        if (targetId === s.id) targetId = -1;
        misses++; streak = 0; mult = 1;
        if (TRACE) console.log(
          `  промах t=${t.toFixed(2)} N=${santas.length + 1} id=${s.id} ` +
          `sx=${s.x.toFixed(0)} px=${px.toFixed(0)} |dx|=${Math.abs(s.x - px).toFixed(0)} ` +
          `svx=${s.vx.toFixed(0)} target=${targetId} aim=${aimX.toFixed(0)}`);
        if (firstMiss === null) firstMiss = t;
        if (t >= graceUntil) { hp--; graceUntil = t + CONFIG.hp.graceAfterLoss; }
      }
    }

    // ---- предметы (статистическая модель подбора) -------------------------
    for (let i = items.length - 1; i >= 0; i--) {
      const it = items[i];
      it.y += CONFIG.items.fallSpeed * dt;
      if (it.y < P.y) continue;
      items.splice(i, 1);
      if (it.kind === 'brine') {
        if (rnd() < K.grabBonus) hp = Math.min(D.hpMax, hp + 1);
      } else if (it.kind === 'bonus') {
        if (rnd() < K.grabBonus) {
          const r = rnd();
          if (r < 0.25) { wideUntil = t + CONFIG.items.wideDuration; }
          else if (r < 0.5) { highUntil = t + CONFIG.items.highDuration; }
          else if (r < 0.75) { slowUntil = t + CONFIG.items.slowDuration; }
          else { snack = CONFIG.items.snackBounces; }
        }
      } else {
        if (rnd() > K.avoidHazard) {
          streak = 0; mult = 1;
          if (t >= graceUntil) { hp--; graceUntil = t + CONFIG.hp.graceAfterLoss; }
        }
      }
    }

    if (t >= nextSample) { nSamples.push(santas.length); nextSample += 1; }
    t += dt;
  }

  return { survived: t, hp, score, bounces, misses, sobered, maxStreak, firstMiss, nSamples };
}

module.exports = { run, SKILLS };
if (require.main !== module) return;

// ------------------------------------------------------------- отчёты ----
const pct = (arr, p) => {
  const a = [...arr].sort((x, y) => x - y);
  return a[Math.min(a.length - 1, Math.floor(a.length * p))];
};
const avgAt = (runs, sec) => {
  const v = runs.map((r) => r.nSamples[sec]).filter((x) => x !== undefined);
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : NaN;
};
const f = (x, n = 1) => (Number.isFinite(x) ? x.toFixed(n) : ' — ');
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN);

const RUNS = Number(process.argv[2] || 200);

console.log(`\nvxBase=${S.vxBase}  vxMax=${S.vxMax}  порог=${S.sober.threshold}  прогонов=${RUNS}\n`);
console.log('сложность  скилл    выжил(med)   p25/p75    1-й пром.  N@30  N@60  N@90  N@120  N@180  уд/с  очки(med)');
console.log('-'.repeat(112));

const ONLY_DIFF = process.env.DIFF, ONLY_SKILL = process.env.SKILL;
for (const diff of Object.keys(CONFIG.difficulty)) {
  if (ONLY_DIFF && diff !== ONLY_DIFF) continue;
  for (const skill of Object.keys(SKILLS)) {
    if (ONLY_SKILL && skill !== ONLY_SKILL) continue;
    const runs = [];
    for (let i = 0; i < RUNS; i++) runs.push(run(diff, skill, i * 7919 + 13));
    const surv = runs.map((r) => r.survived);
    const fm = runs.map((r) => (r.firstMiss === null ? 999 : r.firstMiss));
    console.log(
      diff.padEnd(10) + skill.padEnd(9) +
      f(pct(surv, 0.5)).padStart(8) + 'с' +
      (f(pct(surv, 0.25)) + '/' + f(pct(surv, 0.75))).padStart(13) +
      f(pct(fm, 0.5)).padStart(11) + 'с' +
      f(avgAt(runs, 30)).padStart(6) + f(avgAt(runs, 60)).padStart(6) +
      f(avgAt(runs, 90)).padStart(6) + f(avgAt(runs, 120)).padStart(7) +
      f(avgAt(runs, 180)).padStart(7) +
      f(mean(runs.map((r) => r.bounces / r.survived)), 2).padStart(6) +
      String(pct(runs.map((r) => r.score), 0.5)).padStart(11)
    );
  }
  console.log('-'.repeat(114));
}
