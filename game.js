/* ============================================================================
   Merry Christmas — аркада-жонглирование Дедами Морозами.
   Все числа живут в config.js. Здесь только логика и отрисовка.
   ========================================================================== */
(function () {
'use strict';

const A = CONFIG.arena, P = CONFIG.paddle, S = CONFIG.santa, IT = CONFIG.items;
const PADDLE_TOP = P.y - P.height / 2;
const PLANE = PADDLE_TOP - S.radius;      // Y центра Деда в момент касания

const cv = document.getElementById('game');
const ctx = cv.getContext('2d');
ctx.imageSmoothingQuality = 'high';

// ------------------------------------------------------------- ассеты ----
const IMG = {};
const SPRITES = ['santa_c1', 'santa_c2', 'santa_c3', 'santa_c4', 'santa_fly',
  'santa_c1_sheet', 'santa_c2_sheet', 'santa_c3_sheet', 'santa_c4_sheet',
  'paddle', 'item_brine', 'item_snack', 'item_wide', 'item_high', 'item_slow',
  'item_coal', 'item_bottle', 'bg'];
const ANIM_FRAMES = 6, ANIM_FPS = 8;
SPRITES.forEach((n) => {
  const im = new Image();
  im.src = 'assets/' + n + '.png';
  im.onerror = () => { im.broken = true; };
  IMG[n] = im;
});
const ready = (im) => im && im.complete && !im.broken && im.naturalWidth > 0;

// доля высоты спрайта палки, на которой лежит сама планка (замерено по альфе)
const PADDLE_BAR = 0.2796, PADDLE_ASPECT = 152 / 384;

// -------------------------------------------------------------- звук ----
let muted = false;
function pool(file, n, vol) {
  const arr = [];
  for (let i = 0; i < n; i++) { const a = new Audio('assets/audio/' + file); a.volume = vol; arr.push(a); }
  let k = 0;
  return (rate) => {
    if (muted) return;
    const a = arr[k++ % n];
    try { a.playbackRate = rate || 1; a.currentTime = 0; a.play().catch(() => {}); } catch (e) {}
  };
}
const SFX = {
  hit:    pool('hit.wav', 6, 0.55),
  sober:  pool('sober.wav', 3, 0.5),
  miss:   pool('miss.wav', 3, 0.7),
  bonus:  pool('bonus.wav', 3, 0.5),
  hazard: pool('hazard.wav', 3, 0.6),
};
const music = new Audio('assets/audio/music.ogg');
music.loop = true; music.volume = 0.28;

// ------------------------------------------------------------ утилиты ----
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const rnd = (a, b) => a + Math.random() * (b - a);

function bounceH(d) {
  for (const seg of S.bounce) {
    if (d <= seg.d1) {
      const k = seg.d1 === seg.d0 ? 0 : (d - seg.d0) / (seg.d1 - seg.d0);
      return seg.h0 + (seg.h1 - seg.h0) * k;
    }
  }
  return S.bounce[S.bounce.length - 1].h1;
}

function foldX(x) {
  const span = A.w - 2 * S.radius;
  let u = ((x - S.radius) % (2 * span) + 2 * span) % (2 * span);
  if (u > span) u = 2 * span - u;
  return u + S.radius;
}

// снос метелью за интервал [t0, t0+T] — точный интеграл, не приближение
function driftShift(phase, t0, T) {
  const w = S.drift.freq;
  return (S.drift.amp / w) * (Math.cos(w * t0 + phase) - Math.cos(w * (t0 + T) + phase));
}

// предсказание точки и времени касания плоскости палки
function predict(s, g) {
  const disc = s.vy * s.vy + 2 * g * (PLANE - s.y);
  if (disc < 0) return null;
  const t = (-s.vy + Math.sqrt(disc)) / g;
  if (t < 0) return null;
  return { t, x: foldX(s.x + s.vx * t + driftShift(s.phase, G.t, t)) };
}

// ----------------------------------------------------------- рекорды ----
// Два хранилища сразу. localStorage — чтобы ничего не терялось само по себе
// между запусками. records.js рядом с index.html — чтобы рекорды переезжали
// вместе с папкой игры: страница с file:// не может писать на диск, но может
// подгрузить соседний скрипт, а файл для него отдаётся кнопкой в меню.
const RECORD_KEY = 'merry-christmas-records';
const RECORDS = {};

function mergeRecords(src) {
  if (!src || typeof src !== 'object') return;
  for (const k of Object.keys(CONFIG.difficulty)) {
    const b = src[k];
    if (!b || typeof b.score !== 'number' || !isFinite(b.score)) continue;
    const a = RECORDS[k];
    if (!a || b.score > a.score) {
      RECORDS[k] = { score: b.score | 0, streak: b.streak | 0, time: Math.round(+b.time || 0) };
    }
  }
}

function persistRecords() {
  try { localStorage.setItem(RECORD_KEY, JSON.stringify(RECORDS)); } catch (e) {}
}

function saveRecord(diff, score, streak, time) {
  const cur = RECORDS[diff];
  if (cur && cur.score >= score) return false;
  RECORDS[diff] = { score, streak, time: Math.round(time) };
  persistRecords();
  syncToFile();
  return true;
}

// Записать файл рядом с index.html страница с file:// не может — это запрет
// браузера, а не недоработка. Поэтому при запуске через start.bat игра едет с
// локального сервера, и запись в records.js делает он. При обычном двойном
// клике остаётся только localStorage, и это ожидаемо.
const SERVED = location.protocol === 'http:' || location.protocol === 'https:';
let syncFailed = false;

function syncToFile() {
  if (!SERVED) return;
  fetch('records', { method: 'POST', headers: { 'Content-Type': 'application/json' },
                     body: JSON.stringify(RECORDS) })
    .then((r) => { syncFailed = !r.ok; })
    .catch(() => { syncFailed = true; });
}

mergeRecords(window.RECORDS);
try { mergeRecords(JSON.parse(localStorage.getItem(RECORD_KEY) || 'null')); } catch (e) {}

// --------------------------------------------------------------- игра ----
const G = {
  state: 'menu',          // menu | play | pause | over
  diff: 'normal',
  newRecord: false,
};

function reset(diffKey) {
  const D = CONFIG.difficulty[diffKey];
  Object.assign(G, {
    state: 'play', diff: diffKey, D,
    t: 0, hp: D.hpStart, score: 0, mult: 1, streak: 0, maxStreak: 0,
    santas: [], items: [], puffs: [], pops: [],
    px: A.w / 2, pv: 0, pvHist: [], squash: 0,
    nextSanta: 0, nextBonus: D.bonusEvery, nextBrine: D.brineEvery,
    nextHazard: D.hazardFrom,
    wideUntil: -1, highUntil: -1, slowUntil: -1, snack: 0, graceUntil: -1,
    shake: 0, flash: 0, uid: 0,
  });
}

const gravityNow = () => {
  const c = G.D.gravity;
  const g = c.gMax - (c.gMax - c.g0) * Math.exp(-G.t / c.tau);
  return G.t < G.slowUntil ? g * IT.slowFactor : g;
};
const halfWNow = () => (P.width * (G.t < G.wideUntil ? IT.wideFactor : 1)) / 2;

// Честный спавн: если новое тело приземлится одновременно с уже летящим,
// ставим его рядом, а не на другом конце арены — иначе игрок не успевает.
function spawnX(g) {
  const lo = S.spawnMargin, hi = A.w - S.spawnMargin;
  const fallT = Math.sqrt((2 * (PLANE + S.radius)) / g);
  const clash = [];
  for (const s of G.santas) {
    const q = predict(s, g);
    if (q && Math.abs(q.t - fallT) < S.fairSpawn.window) clash.push(q.x);
  }
  if (!clash.length) return rnd(lo, hi);
  const c = clash[(Math.random() * clash.length) | 0];
  return clamp(c + rnd(-S.fairSpawn.reach, S.fairSpawn.reach), lo, hi);
}

// Предметы падают в ту треть арены, где сейчас меньше всего Дедов Морозов —
// чтобы бонус приходилось выбирать, а не получать даром.
function itemX() {
  const c = [0, 0, 0];
  for (const s of G.santas) c[clamp((s.x / A.w * 3) | 0, 0, 2)]++;
  let best = 0;
  for (let i = 1; i < 3; i++) if (c[i] < c[best]) best = i;
  return rnd(best * A.w / 3 + 40, (best + 1) * A.w / 3 - 40);
}

const BONUS_KINDS = ['wide', 'high', 'slow', 'snack'];

function addPop(x, y, text, color) {
  G.pops.push({ x, y, text, color, life: 0.9 });
}
function addPuff(x, y, n, color) {
  for (let i = 0; i < n; i++) {
    G.puffs.push({
      x, y, vx: rnd(-140, 140), vy: rnd(-190, -40),
      life: rnd(0.35, 0.8), r: rnd(2, 5), color,
    });
  }
}

function loseHp(x, y) {
  if (G.t < G.graceUntil) return;
  G.hp--; G.graceUntil = G.t + CONFIG.hp.graceAfterLoss;
  G.shake = 0.35; G.flash = 0.5;
  if (G.hp <= 0) {
    G.state = 'over';
    G.newRecord = saveRecord(G.diff, G.score, G.maxStreak, G.t);
    music.pause();
  }
}

// ------------------------------------------------------------- физика ----
function step(dt) {
  G.t += dt;
  const g = gravityNow();
  const halfW = halfWNow();

  // ---- спавн
  if (G.t >= G.nextSanta) {
    if (G.santas.length < S.maxOnField) {
      G.santas.push({
        id: G.uid++, x: spawnX(g), y: -S.radius, vx: 0, vy: 0,
        sober: 0, phase: Math.random() * Math.PI * 2,
        rot: rnd(-0.4, 0.4), spin: rnd(-1.4, 1.4), flip: Math.random() < 0.5,
        animOffset: (Math.random() * 6) | 0, escaping: false,
      });
    }
    const sp = G.D.spawn;
    G.nextSanta = G.t + sp.sMin + (sp.s0 - sp.sMin) * Math.exp(-G.t / sp.tau);
  }
  if (G.t >= G.nextBonus) {
    G.items.push({ kind: BONUS_KINDS[(Math.random() * 4) | 0], x: itemX(), y: -IT.radius, bad: false });
    G.nextBonus = G.t + G.D.bonusEvery;
  }
  if (G.t >= G.nextBrine) {
    G.items.push({ kind: 'brine', x: itemX(), y: -IT.radius, bad: false });
    G.nextBrine = G.t + G.D.brineEvery;
  }
  if (G.t >= G.D.hazardFrom && G.t >= G.nextHazard) {
    G.items.push({
      kind: Math.random() < 0.5 ? 'coal' : 'bottle',
      x: itemX(), y: -IT.radius, bad: true,
    });
    G.nextHazard = G.t + G.D.hazardEvery;
  }

  // ---- палка следует за курсором без сглаживания
  const prevPx = G.px;
  G.px = clamp(G.aimX !== undefined ? G.aimX : G.px, halfW, A.w - halfW);
  G.pvHist.push((G.px - prevPx) / dt);
  if (G.pvHist.length > P.speedSamples) G.pvHist.shift();
  G.pv = clamp(G.pvHist.reduce((a, b) => a + b, 0) / G.pvHist.length,
               -P.speedClamp, P.speedClamp);

  // ---- Деды Морозы
  for (let i = G.santas.length - 1; i >= 0; i--) {
    const s = G.santas[i];

    if (s.escaping) {                     // протрезвел — улетает вверх
      s.y -= S.escapeSpeed * dt;
      s.rot *= 0.85;
      if (s.y < -120) G.santas.splice(i, 1);
      continue;
    }

    const prevY = s.y;
    s.vy += g * dt;
    s.x += (s.vx + S.drift.amp * Math.sin(G.t * S.drift.freq + s.phase)) * dt;
    s.y += s.vy * dt;
    s.rot += s.spin * dt;

    if (s.x < S.radius) { s.x = S.radius; s.vx = -s.vx * S.wallDamp; s.spin = -s.spin; }
    if (s.x > A.w - S.radius) { s.x = A.w - S.radius; s.vx = -s.vx * S.wallDamp; s.spin = -s.spin; }
    if (s.y < S.radius && s.vy < 0) { s.y = S.radius; s.vy = -s.vy * S.wallDamp; }

    // касание верхней грани палки
    if (s.vy > 0 && prevY <= PLANE && s.y >= PLANE && Math.abs(s.x - G.px) <= halfW) {
      const off = s.x - G.px;
      const d = Math.min(1, Math.abs(off) / halfW);
      let h = bounceH(d);
      if (G.t < G.highUntil) h *= IT.highFactor;
      h = Math.min(h, S.hCap);

      s.y = PLANE;
      s.vy = -Math.sqrt(2 * g * h * A.h);
      s.vx = clamp(Math.sign(off) * S.vxBase * d + G.pv * S.vxFromPaddle,
                   -S.vxMax, S.vxMax);
      s.spin = clamp(s.vx / 90, -3.2, 3.2);

      const sweet = d <= P.sweetZone;
      let gain = sweet ? S.sober.gainSweet : S.sober.gainNormal;
      if (G.snack > 0) { gain *= 2; G.snack--; }
      s.sober += gain;

      G.streak++;
      G.maxStreak = Math.max(G.maxStreak, G.streak);
      G.mult = Math.min(CONFIG.score.maxMult, 1 + ((G.streak / CONFIG.score.comboStep) | 0));
      G.score += CONFIG.score.bounce * G.mult;

      G.squash = 1;
      addPuff(s.x, PLANE + S.radius, sweet ? 12 : 7, sweet ? '#ffe08a' : '#dbe9ff');
      // икота: чем трезвее, тем выше тон и тише
      SFX.hit(0.8 + 0.16 * s.sober);

      if (s.sober >= S.sober.threshold) {
        s.escaping = true;
        s.vx = 0; s.vy = 0;
        G.score += CONFIG.score.sober * G.mult;
        addPop(s.x, s.y - 40, '+' + CONFIG.score.sober * G.mult, '#8ef2a4');
        addPuff(s.x, s.y, 16, '#8ef2a4');
        SFX.sober();
      }
      continue;
    }

    // пол
    if (s.y - S.radius > A.h) {
      G.santas.splice(i, 1);
      G.streak = 0; G.mult = 1;
      addPuff(s.x, A.h - 6, 14, '#ff8080');
      SFX.miss();
      loseHp(s.x, A.h);
    }
  }

  // ---- предметы
  for (let i = G.items.length - 1; i >= 0; i--) {
    const it = G.items[i];
    it.y += IT.fallSpeed * dt;

    const hitPaddle = it.y + IT.radius >= PADDLE_TOP && it.y - IT.radius <= P.y + P.height / 2 &&
                      Math.abs(it.x - G.px) <= halfW + IT.radius * 0.4;
    if (hitPaddle) {
      G.items.splice(i, 1);
      applyItem(it);
      continue;
    }
    if (it.y - IT.radius > A.h) G.items.splice(i, 1);
  }

  // ---- эффекты
  for (let i = G.puffs.length - 1; i >= 0; i--) {
    const p = G.puffs[i];
    p.life -= dt;
    if (p.life <= 0) { G.puffs.splice(i, 1); continue; }
    p.vy += 420 * dt; p.x += p.vx * dt; p.y += p.vy * dt;
  }
  for (let i = G.pops.length - 1; i >= 0; i--) {
    const p = G.pops[i];
    p.life -= dt; p.y -= 34 * dt;
    if (p.life <= 0) G.pops.splice(i, 1);
  }
  G.squash = Math.max(0, G.squash - dt * 6);
  G.shake = Math.max(0, G.shake - dt);
  G.flash = Math.max(0, G.flash - dt * 1.6);
}

function applyItem(it) {
  if (it.bad) {
    G.streak = 0; G.mult = 1;
    SFX.hazard();
    addPuff(it.x, P.y, 18, '#ff9a5c');
    if (it.kind === 'bottle') {
      for (const s of G.santas) {
        if (s.escaping) continue;
        if (Math.hypot(s.x - it.x, s.y - P.y) <= IT.bottleRadius) {
          s.sober = Math.max(0, s.sober - IT.bottleSoberLoss);
        }
      }
      addPop(it.x, P.y - 40, 'по кругу!', '#ff9a5c');
    } else {
      addPop(it.x, P.y - 40, 'уголь', '#ff9a5c');
    }
    loseHp(it.x, P.y);
    return;
  }

  SFX.bonus();
  addPuff(it.x, P.y, 12, '#9ad8ff');
  if (it.kind === 'brine') {
    if (G.hp < G.D.hpMax) { G.hp++; addPop(it.x, P.y - 40, '+1 HP', '#8ef2a4'); }
    else addPop(it.x, P.y - 40, 'и так хорошо', '#9ad8ff');
  } else if (it.kind === 'wide') {
    G.wideUntil = G.t + IT.wideDuration; addPop(it.x, P.y - 40, 'шире', '#9ad8ff');
  } else if (it.kind === 'high') {
    G.highUntil = G.t + IT.highDuration; addPop(it.x, P.y - 40, 'выше', '#9ad8ff');
  } else if (it.kind === 'slow') {
    G.slowUntil = G.t + IT.slowDuration; addPop(it.x, P.y - 40, 'медленнее', '#9ad8ff');
  } else {
    G.snack = IT.snackBounces; addPop(it.x, P.y - 40, 'закуска ×2', '#9ad8ff');
  }
}

// ---------------------------------------------------------- отрисовка ----
const ITEM_IMG = { brine: 'item_brine', snack: 'item_snack', wide: 'item_wide',
  high: 'item_high', slow: 'item_slow', coal: 'item_coal', bottle: 'item_bottle' };
const ITEM_COLOR = { brine: '#8ef2a4', snack: '#f2d98e', wide: '#57d07a',
  high: '#5aa8f2', slow: '#a97cf2', coal: '#3a3f4a', bottle: '#2f6b3a' };

// снег на фоне
const flakes = [];
for (let i = 0; i < 70; i++) {
  flakes.push({ x: Math.random() * A.w, y: Math.random() * A.h,
    r: rnd(0.8, 2.4), v: rnd(12, 40), d: rnd(-14, 14), p: Math.random() * 6.3 });
}

function noseTier(sober) {
  if (sober <= 1) return 'c1';
  if (sober <= 3) return 'c2';
  if (sober <= 5) return 'c3';
  return 'c4';
}
function noseColor(sober) {
  for (const t of S.noseTiers) if (sober <= t.upTo) return t.color;
  return S.noseTiers[S.noseTiers.length - 1].color;
}

function drawSanta(s) {
  const tier = noseTier(s.sober);
  const sheet = s.escaping ? null : IMG[('santa_' + tier + '_sheet')];
  const im = s.escaping ? IMG.santa_fly : IMG['santa_' + tier];
  const col = noseColor(s.sober);

  // Свечение под телом — тот же цвет, что у носа. Нос на 60 px нечитаем, а
  // цветное пятно ловится боковым зрением даже когда тел на поле десяток.
  const rr = S.radius * 1.9;
  const gl = ctx.createRadialGradient(s.x, s.y, S.radius * 0.35, s.x, s.y, rr);
  gl.addColorStop(0, col);
  gl.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.globalAlpha = s.escaping ? 0.22 : 0.42;
  ctx.fillStyle = gl;
  ctx.beginPath(); ctx.arc(s.x, s.y, rr, 0, 6.283); ctx.fill();
  ctx.globalAlpha = 1;

  ctx.save();
  ctx.translate(s.x, s.y);
  ctx.rotate(s.rot);
  if (s.flip) ctx.scale(-1, 1);
  if (ready(sheet)) {                       // анимированный лист: 6 кадров в ряд
    const cell = sheet.naturalHeight;
    const f = ((G.t * ANIM_FPS + s.animOffset) | 0) % ANIM_FRAMES;
    const h = S.radius * 3.4;
    ctx.drawImage(sheet, f * cell, 0, cell, cell, -h / 2, -h / 2, h, h);
  } else if (ready(im)) {
    const h = S.radius * 3.1;
    const w = h * (im.naturalWidth / im.naturalHeight);
    ctx.drawImage(im, -w / 2, -h / 2, w, h);
  } else {                                  // запасной вариант без спрайтов
    ctx.fillStyle = '#d33';
    ctx.beginPath(); ctx.arc(0, 0, S.radius, 0, 6.283); ctx.fill();
    ctx.fillStyle = col;
    ctx.beginPath(); ctx.arc(0, -4, 6, 0, 6.283); ctx.fill();
  }
  ctx.restore();
}

function drawMarkers(g) {
  for (const s of G.santas) {
    if (s.escaping) continue;
    const p = predict(s, g);
    if (!p) continue;
    const a = clamp(1.15 - p.t / 2.4, 0.12, 0.9);

    // маркер приземления на линии палки
    ctx.save();
    ctx.globalAlpha = a;
    ctx.strokeStyle = noseColor(s.sober);
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 5]);
    ctx.beginPath(); ctx.arc(p.x, P.y, S.radius + 2, 0, 6.283); ctx.stroke();
    ctx.setLineDash([]);
    // вертикальная нить от тела к маркеру
    ctx.globalAlpha = a * 0.28;
    ctx.beginPath(); ctx.moveTo(p.x, P.y - S.radius); ctx.lineTo(p.x, Math.max(0, s.y)); ctx.stroke();
    ctx.restore();

    // тело ещё за верхней границей — рисуем предупреждение
    if (s.y < 0) {
      ctx.save();
      ctx.globalAlpha = 0.9;
      ctx.fillStyle = '#ffd166';
      ctx.beginPath();
      ctx.moveTo(s.x - 10, 6); ctx.lineTo(s.x + 10, 6); ctx.lineTo(s.x, 22);
      ctx.closePath(); ctx.fill();
      ctx.restore();
    }
  }
}

function drawPaddle() {
  const halfW = halfWNow();
  const w = halfW * 2;
  const squash = 1 - G.squash * 0.35;
  ctx.save();
  ctx.translate(G.px, P.y);
  ctx.scale(1, squash);
  if (ready(IMG.paddle)) {
    const h = w * PADDLE_ASPECT;
    ctx.drawImage(IMG.paddle, -w / 2, -PADDLE_BAR * h, w, h);
  } else {
    ctx.fillStyle = '#c9a227';
    ctx.fillRect(-halfW, -P.height / 2, w, P.height);
    ctx.fillStyle = '#e8433f';
    ctx.fillRect(-halfW * P.sweetZone, -P.height / 2 - 3, w * P.sweetZone, P.height + 6);
  }
  ctx.restore();

  if (G.t < G.wideUntil) {                 // подсветка активного бонуса ширины
    ctx.strokeStyle = '#57d07a';
    ctx.globalAlpha = 0.5; ctx.lineWidth = 2;
    ctx.strokeRect(G.px - halfW, P.y - 12, w, 24);
    ctx.globalAlpha = 1;
  }
}

function drawItem(it) {
  const im = IMG[ITEM_IMG[it.kind]];
  if (ready(im)) {
    const h = IT.radius * 2.4;
    const w = h * (im.naturalWidth / im.naturalHeight);
    ctx.drawImage(im, it.x - w / 2, it.y - h / 2, w, h);
  } else if (it.bad) {                     // острый силуэт — вред
    ctx.fillStyle = ITEM_COLOR[it.kind];
    ctx.strokeStyle = '#000'; ctx.lineWidth = 3;
    ctx.beginPath();
    for (let i = 0; i < 7; i++) {
      const a = (i / 7) * 6.283, r = i % 2 ? IT.radius * 0.55 : IT.radius;
      ctx[i ? 'lineTo' : 'moveTo'](it.x + Math.cos(a) * r, it.y + Math.sin(a) * r);
    }
    ctx.closePath(); ctx.fill(); ctx.stroke();
  } else {                                 // круглый силуэт — бонус
    ctx.fillStyle = ITEM_COLOR[it.kind];
    ctx.strokeStyle = '#000'; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(it.x, it.y, IT.radius, 0, 6.283);
    ctx.fill(); ctx.stroke();
  }
}

function drawHud() {
  ctx.save();
  ctx.font = 'bold 20px "Segoe UI", sans-serif';
  ctx.textBaseline = 'top';

  ctx.fillStyle = '#eaf1ff';
  ctx.fillText(String(G.score), 16, 14);
  ctx.font = 'bold 15px "Segoe UI", sans-serif';
  ctx.fillStyle = G.mult > 1 ? '#ffd166' : '#7d8aa3';
  ctx.fillText('×' + G.mult + '   серия ' + G.streak, 16, 40);

  // HP шапками
  for (let i = 0; i < G.D.hpMax; i++) {
    const x = A.w - 26 - i * 26, on = i < G.hp;
    ctx.globalAlpha = on ? 1 : 0.2;
    ctx.fillStyle = '#e8433f';
    ctx.beginPath();
    ctx.moveTo(x - 9, 26); ctx.lineTo(x + 9, 26); ctx.lineTo(x, 10);
    ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.fillRect(x - 10, 26, 20, 5);
    ctx.globalAlpha = 1;
  }

  ctx.font = '14px "Segoe UI", sans-serif';
  ctx.fillStyle = '#7d8aa3';
  ctx.textAlign = 'center';
  ctx.fillText(G.D.label + '   ·   в воздухе ' + G.santas.filter((s) => !s.escaping).length +
               '   ·   ' + G.t.toFixed(0) + ' c', A.w / 2, 16);
  ctx.textAlign = 'left';

  // активные эффекты
  let ex = 16, ey = 64;
  const badge = (text, color, until) => {
    const left = until - G.t;
    if (left <= 0) return;
    ctx.fillStyle = color; ctx.globalAlpha = 0.85;
    ctx.font = 'bold 13px "Segoe UI", sans-serif';
    ctx.fillText(text + ' ' + left.toFixed(1) + 'c', ex, ey);
    ctx.globalAlpha = 1; ey += 18;
  };
  badge('шире', '#57d07a', G.wideUntil);
  badge('выше', '#5aa8f2', G.highUntil);
  badge('медленнее', '#a97cf2', G.slowUntil);
  if (G.snack > 0) {
    ctx.fillStyle = '#f2d98e'; ctx.globalAlpha = 0.85;
    ctx.font = 'bold 13px "Segoe UI", sans-serif';
    ctx.fillText('закуска ×2: ' + G.snack, ex, ey); ctx.globalAlpha = 1;
  }

  // кнопка звука
  ctx.fillStyle = muted ? '#5b6478' : '#9ad8ff';
  ctx.font = '18px "Segoe UI", sans-serif';
  ctx.textAlign = 'right';
  ctx.fillText(muted ? 'звук выкл' : 'звук вкл', A.w - 16, A.h - 28);
  ctx.textAlign = 'left';
  ctx.restore();
}

function drawBackdrop(dt) {
  if (ready(IMG.bg)) ctx.drawImage(IMG.bg, 0, 0, A.w, A.h);
  else { ctx.fillStyle = '#0b1020'; ctx.fillRect(0, 0, A.w, A.h); }

  ctx.fillStyle = '#ffffff';
  for (const f of flakes) {
    f.y += f.v * dt; f.x += Math.sin(G.t !== undefined ? G.t + f.p : f.p) * f.d * dt;
    if (f.y > A.h) { f.y = -4; f.x = Math.random() * A.w; }
    ctx.globalAlpha = 0.35;
    ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, 6.283); ctx.fill();
  }
  ctx.globalAlpha = 1;

  // линия пола
  ctx.strokeStyle = '#2a3550'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(0, A.h - 1); ctx.lineTo(A.w, A.h - 1); ctx.stroke();
}

function drawEffects() {
  for (const p of G.puffs) {
    ctx.globalAlpha = clamp(p.life * 1.6, 0, 1);
    ctx.fillStyle = p.color;
    ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, 6.283); ctx.fill();
  }
  ctx.globalAlpha = 1;
  ctx.font = 'bold 17px "Segoe UI", sans-serif';
  ctx.textAlign = 'center';
  for (const p of G.pops) {
    ctx.globalAlpha = clamp(p.life * 1.3, 0, 1);
    ctx.fillStyle = p.color;
    ctx.fillText(p.text, p.x, p.y);
  }
  ctx.globalAlpha = 1;
  ctx.textAlign = 'left';
}

// ------------------------------------------------------------- экраны ----
const BTN = [];
function button(x, y, w, h, label, action, hot) {
  BTN.push({ x, y, w, h, action });
  ctx.fillStyle = hot ? '#e8433f' : '#182238';
  ctx.strokeStyle = hot ? '#ffd166' : '#31415f';
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.roundRect(x, y, w, h, 10); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#eaf1ff';
  ctx.font = 'bold 18px "Segoe UI", sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(label, x + w / 2, y + h / 2);
  ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
}

const mmss = (s) => ((s / 60) | 0) + ':' + String(Math.round(s % 60)).padStart(2, '0');

function drawMenu() {
  ctx.fillStyle = 'rgba(7,11,20,0.82)';
  ctx.fillRect(0, 0, A.w, A.h);
  ctx.textAlign = 'center';
  ctx.fillStyle = '#eaf1ff';
  ctx.font = 'bold 46px "Segoe UI", sans-serif';
  ctx.fillText('MERRY CHRISTMAS', A.w / 2, 82);
  ctx.font = '18px "Segoe UI", sans-serif';
  ctx.fillStyle = '#9fb0cc';
  ctx.fillText('Двигайте палку мышью и не давайте пьяным Дедам Морозам упасть.', A.w / 2, 122);
  ctx.fillText('Шесть единиц трезвости — и он улетает. Бант в центре даёт две за удар.', A.w / 2, 148);
  ctx.textAlign = 'left';

  const keys = Object.keys(CONFIG.difficulty);
  keys.forEach((k, i) => {
    const D = CONFIG.difficulty[k];
    const x = A.w / 2 - 330 + i * 230;
    button(x, 182, 200, 62, D.label, () => { reset(k); startMusic(); }, G.diff === k);
    ctx.fillStyle = '#7d8aa3';
    ctx.font = '13px "Segoe UI", sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(D.hpStart + ' HP', x + 100, 262);
    ctx.textAlign = 'left';
  });

  // таблица рекордов
  ctx.textAlign = 'center';
  ctx.fillStyle = '#5b6478';
  ctx.font = 'bold 13px "Segoe UI", sans-serif';
  ctx.fillText('РЕКОРДЫ', A.w / 2, 306);
  ctx.textAlign = 'left';
  keys.forEach((k, i) => {
    const D = CONFIG.difficulty[k], r = RECORDS[k], y = 334 + i * 24;
    ctx.font = '15px "Segoe UI", sans-serif';
    ctx.fillStyle = '#9fb0cc';
    ctx.fillText(D.label, 300, y);
    ctx.textAlign = 'right';
    if (r) {
      ctx.fillStyle = '#ffd166';
      ctx.font = 'bold 15px "Segoe UI", sans-serif';
      ctx.fillText(String(r.score), 470, y);
      ctx.fillStyle = '#7d8aa3';
      ctx.font = '14px "Segoe UI", sans-serif';
      ctx.fillText('серия ' + r.streak, 560, y);
      ctx.fillText(mmss(r.time), 620, y);
    } else {
      ctx.fillStyle = '#4a5468';
      ctx.fillText('пока пусто', 470, y);
    }
    ctx.textAlign = 'left';
  });

  ctx.textAlign = 'center';
  ctx.font = '13px "Segoe UI", sans-serif';
  if (syncFailed) {
    ctx.fillStyle = '#e8433f';
    ctx.fillText('Сервер не принимает запись — рекорды пока только в браузере.', A.w / 2, 442);
  } else if (SERVED) {
    ctx.fillStyle = '#57d07a';
    ctx.fillText('Автосохранение в records.js рядом с игрой', A.w / 2, 442);
  } else {
    ctx.fillStyle = '#4a5468';
    ctx.fillText('Рекорды сохраняются в браузере автоматически.', A.w / 2, 436);
    ctx.fillText('Чтобы они переезжали вместе с папкой — запускайте через start.bat.', A.w / 2, 456);
  }

  ctx.fillStyle = '#5b6478';
  ctx.font = '14px "Segoe UI", sans-serif';
  ctx.fillText('пробел — пауза · Esc — меню · M — звук', A.w / 2, 508);
  ctx.textAlign = 'left';
}

function drawPause() {
  ctx.fillStyle = 'rgba(7,11,20,0.72)';
  ctx.fillRect(0, 0, A.w, A.h);
  ctx.textAlign = 'center'; ctx.fillStyle = '#eaf1ff';
  ctx.font = 'bold 44px "Segoe UI", sans-serif';
  ctx.fillText('ПАУЗА', A.w / 2, A.h / 2 - 10);
  ctx.font = '17px "Segoe UI", sans-serif'; ctx.fillStyle = '#9fb0cc';
  ctx.fillText('пробел — продолжить', A.w / 2, A.h / 2 + 26);
  ctx.textAlign = 'left';
}

function drawOver() {
  ctx.fillStyle = 'rgba(7,11,20,0.85)';
  ctx.fillRect(0, 0, A.w, A.h);
  ctx.textAlign = 'center';
  ctx.fillStyle = '#e8433f';
  ctx.font = 'bold 48px "Segoe UI", sans-serif';
  ctx.fillText('ВСЕ УПАЛИ', A.w / 2, 170);
  ctx.fillStyle = '#eaf1ff';
  ctx.font = 'bold 30px "Segoe UI", sans-serif';
  ctx.fillText('счёт ' + G.score, A.w / 2, 232);
  ctx.font = '18px "Segoe UI", sans-serif';
  ctx.fillStyle = '#9fb0cc';
  ctx.fillText('максимальная серия ' + G.maxStreak + '   ·   продержались ' + G.t.toFixed(0) + ' c',
               A.w / 2, 268);
  const r = RECORDS[G.diff];
  if (G.newRecord) {
    ctx.fillStyle = '#8ef2a4';
    ctx.font = 'bold 20px "Segoe UI", sans-serif';
    ctx.fillText('НОВЫЙ РЕКОРД · ' + G.D.label, A.w / 2, 302);
  } else if (r) {
    ctx.fillStyle = '#ffd166';
    ctx.fillText('рекорд на «' + G.D.label + '» — ' + r.score, A.w / 2, 300);
  }
  ctx.textAlign = 'left';
  button(A.w / 2 - 210, 340, 200, 56, 'Ещё раз (R)', () => { reset(G.diff); startMusic(); }, true);
  button(A.w / 2 + 10, 340, 200, 56, 'В меню', () => { G.state = 'menu'; }, false);
}

// --------------------------------------------------------------- цикл ----
let last = performance.now(), acc = 0;
const FIXED = 1 / 120;

function render(dt) {
  BTN.length = 0;
  ctx.save();
  if (G.shake > 0) {
    const k = G.shake * 14;
    ctx.translate(rnd(-k, k), rnd(-k, k));
  }
  drawBackdrop(dt);

  if (G.state !== 'menu') {
    const g = gravityNow();
    drawMarkers(g);
    for (const it of G.items) drawItem(it);
    for (const s of G.santas) drawSanta(s);
    drawPaddle();
    drawEffects();
    drawHud();
  }
  ctx.restore();

  if (G.flash > 0) {
    const grd = ctx.createRadialGradient(A.w / 2, A.h / 2, A.h * 0.35, A.w / 2, A.h / 2, A.w * 0.7);
    grd.addColorStop(0, 'rgba(255,40,40,0)');
    grd.addColorStop(1, 'rgba(255,40,40,' + (G.flash * 0.6).toFixed(3) + ')');
    ctx.fillStyle = grd; ctx.fillRect(0, 0, A.w, A.h);
  }

  if (G.state === 'menu') drawMenu();
  else if (G.state === 'pause') drawPause();
  else if (G.state === 'over') drawOver();

  // системный курсор мешает только в игре — в меню им целятся в кнопки
  cv.style.cursor = G.state === 'play' ? 'none' : 'default';
}

function frame(now) {
  let dt = (now - last) / 1000;
  last = now;
  if (dt > 0.25) dt = 0.25;               // вкладка была в фоне

  if (G.state === 'play') {
    acc += dt;
    while (acc >= FIXED) { step(FIXED); acc -= FIXED; if (G.state !== 'play') break; }
  }
  render(dt);
  requestAnimationFrame(frame);
}

// --------------------------------------------------------------- ввод ----
function toLogical(ev) {
  const r = cv.getBoundingClientRect();
  return { x: (ev.clientX - r.left) * (A.w / r.width),
           y: (ev.clientY - r.top) * (A.h / r.height) };
}
cv.addEventListener('mousemove', (ev) => { G.aimX = toLogical(ev).x; });
cv.addEventListener('mousedown', (ev) => {
  const p = toLogical(ev);
  if (p.x > A.w - 120 && p.y > A.h - 44) { toggleMute(); return; }
  for (const b of BTN) {
    if (p.x >= b.x && p.x <= b.x + b.w && p.y >= b.y && p.y <= b.y + b.h) { b.action(); return; }
  }
});
addEventListener('keydown', (ev) => {
  if (ev.code === 'Space') {
    ev.preventDefault();
    if (G.state === 'play') { G.state = 'pause'; music.pause(); }
    else if (G.state === 'pause') { G.state = 'play'; last = performance.now(); startMusic(); }
  }
  if (ev.code === 'Escape') {
    if (G.state !== 'menu') { G.state = 'menu'; music.pause(); }
  }
  if (ev.key === 'r' || ev.key === 'R' || ev.key === 'к' || ev.key === 'К') {
    if (G.state === 'over') { reset(G.diff); startMusic(); }
  }
  if (ev.key === 'm' || ev.key === 'M' || ev.key === 'ь' || ev.key === 'Ь') toggleMute();
});

function toggleMute() {
  muted = !muted;
  if (muted) music.pause(); else startMusic();
}
function startMusic() {
  if (muted) return;
  music.play().catch(() => {});
}

// стартовое состояние: показываем меню поверх пустой арены
reset('normal');
G.state = 'menu';

// Отладочный хук для снятия скриншотов и дымового теста:
// index.html?demo=normal&ff=45 — стартует забег и прокручивает 45 секунд,
// подставляя вместо игрока простейшего бота. В обычной игре не участвует.
(function demoHook() {
  const q = new URLSearchParams(location.search);
  const d = q.get('demo');
  if (!d || !CONFIG.difficulty[d]) return;
  muted = true;
  reset(d);
  const ff = Number(q.get('ff') || 30);
  const dt = 1 / 120;
  for (let i = 0; i < ff / dt && G.state === 'play'; i++) {
    let best = null, bt = Infinity;
    const g = gravityNow();
    for (const s of G.santas) {
      if (s.escaping) continue;
      const p = predict(s, g);
      if (p && p.t < bt) { bt = p.t; best = p; }
    }
    if (best) G.aimX = best.x;
    step(dt);
  }
})();

// Замер под критерий приёмки: 15 объектов на поле, кадр не должен стоить
// дороже 18.2 мс (55 fps). Цикл синхронный — так измерение не зависит от
// планировщика rAF. index.html?perf=1, результат уходит в document.title.
(function perfHook() {
  if (!new URLSearchParams(location.search).has('perf')) return;
  muted = true;
  reset('normal');
  const g = gravityNow();
  for (let i = 0; i < 12; i++) {
    G.santas.push({
      id: G.uid++, x: 60 + i * 65, y: 120 + (i % 5) * 70,
      vx: rnd(-200, 200), vy: rnd(-500, 300), sober: i % 6,
      phase: Math.random() * 6.283, rot: rnd(-3, 3), spin: rnd(-2, 2),
      flip: i % 2 === 0, escaping: false,
    });
  }
  for (let i = 0; i < 3; i++) {
    G.items.push({ kind: BONUS_KINDS[i], x: 200 + i * 250, y: 100 + i * 90, bad: false });
  }
  const spawn12 = () => {
    while (G.santas.length < 12) {
      const i = G.santas.length;
      G.santas.push({
        id: G.uid++, x: 60 + i * 65, y: 120 + (i % 5) * 70,
        vx: rnd(-200, 200), vy: rnd(-500, 300), sober: i % 6,
        phase: Math.random() * 6.283, rot: rnd(-3, 3), spin: rnd(-2, 2),
        flip: i % 2 === 0, animOffset: i % 6, escaping: false,
      });
    }
    while (G.items.length < 3) {
      G.items.push({ kind: BONUS_KINDS[G.items.length], x: 200 + G.items.length * 250, y: 40, bad: false });
    }
  };
  const N = 240;
  const t0 = performance.now();
  for (let i = 0; i < N; i++) {
    G.hp = 99; spawn12();
    step(FIXED); step(FIXED); render(FIXED * 2);
  }
  const ms = (performance.now() - t0) / N;
  document.title = 'PERF objects=' + (G.santas.length + G.items.length) +
                   ' ms=' + ms.toFixed(2) + ' fps=' + (1000 / ms).toFixed(0);
})();

// Проверка попадания по кнопкам без живой мыши: index.html?click=450,303
// шлёт синтетический mousedown в логическую точку и пишет итог в document.title.
(function clickHook() {
  const q = new URLSearchParams(location.search);
  const click = q.get('click'), key = q.get('key');
  if (!click && !key) return;
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const before = G.state;
    if (click) {
      const [lx, ly] = click.split(',').map(Number);
      const r = cv.getBoundingClientRect();
      cv.dispatchEvent(new MouseEvent('mousedown', {
        clientX: r.left + (lx * r.width) / A.w,
        clientY: r.top + (ly * r.height) / A.h,
        bubbles: true,
      }));
    }
    if (key) dispatchEvent(new KeyboardEvent('keydown', { code: key, key, bubbles: true }));
    document.title = 'HOOK buttons=' + BTN.length + ' state=' + before + '->' + G.state;
  }));
})();

requestAnimationFrame(frame);

})();
