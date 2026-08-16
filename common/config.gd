# ============================================================================
# CONFIG — единственное место, где живут числа.
# Значения выведены в BALANCE.md; менять здесь.
# Симулятор баланса (tools/sim.js) держит свою копию в tools/config.js —
# после правки чисел здесь его копию надо обновить руками, иначе он считает
# другую игру.
# ============================================================================
class_name CFG
extends RefCounted

# ---- арена ----
const ARENA_W := 900.0
const ARENA_H := 600.0

# ---- палка ----
const PADDLE_WIDTH := 160.0        # базовая ширина, px
const PADDLE_HEIGHT := 16.0
const PADDLE_Y := 540.0            # Y центра палки
const SWEET_ZONE := 0.15           # доля полуширины: |d| <= 0.15 -> сладкая зона
const SPEED_SAMPLES := 4           # окно скользящего среднего для скорости палки
const SPEED_CLAMP := 1200.0        # px/s, потолок учитываемой скорости палки

# ---- Дед Мороз ----
const SANTA_RADIUS := 22.0
const MAX_ON_FIELD := 12           # абсолютный потолок, уровень до него дорастает
const SPAWN_MARGIN := 60.0         # отступ от стен при спавне

# Честный спавн. Новый Дед Мороз падает до палки ~1.3 с. Если его приземление
# совпадёт по времени с уже летящим телом на другом конце арены, игрок не
# успевает физически — это не сложность, а нечестность. Поэтому при конфликте
# по времени новый спавнится рядом с конфликтующим, в пределах броска руки.
const FAIR_SPAWN_WINDOW := 0.55
const FAIR_SPAWN_REACH := 170.0

# Таблица высоты отскока: [d0, d1, h0, h1], h — доля высоты арены (600 px),
# d — |смещение от центра палки| / (ширина/2), 0..1
const BOUNCE := [
	[0.00, 0.15, 0.80, 0.80],
	[0.15, 0.60, 0.75, 0.45],
	[0.60, 1.00, 0.40, 0.25],
]
const H_CAP := 0.85                # жёсткий потолок высоты отскока с бонусами

const VX_BASE := 220.0             # px/s, вклад смещения от центра
const VX_FROM_PADDLE := 0.20       # доля скорости палки, уходящая в vx
const VX_MAX := 300.0              # px/s, потолок |vx|
const WALL_DAMP := 0.95            # коэффициент при отражении от стен и потолка

# Метель: amp*sin(t*freq + phase) px/s. Нужна, чтобы тела не застывали в
# неподвижных колоннах при аккуратной игре. Снос учитывается в предсказании
# точки приземления точно, интегралом, иначе маркер врёт на десятки пикселей.
const DRIFT_AMP := 30.0
const DRIFT_FREQ := 0.45

const SOBER_THRESHOLD := 6
const SOBER_GAIN_SWEET := 2
const SOBER_GAIN_NORMAL := 1
const ESCAPE_SPEED := 900.0        # px/s, скорость улёта протрезвевшего

# Цвет носа по трезвости — основной канал считывания.
# [порог трезвости включительно, цвет]
const NOSE_TIERS := [
	[1, Color("7d1f1f")],          # багровый
	[3, Color("c0245c")],          # малиновый
	[5, Color("f08bb0")],          # розовый
	[6, Color("f2c9a0")],          # обычный
]

# ---- предметы ----
const ITEM_FALL_SPEED := 180.0     # px/s, постоянная, без гравитации
const ITEM_RADIUS := 18.0
const WIDE_DURATION := 10.0        # стрелка <->
const HIGH_DURATION := 10.0        # стрелка ^
const SLOW_DURATION := 8.0         # стрелка v
const SNACK_BOUNCES := 5           # закуска: сколько отскоков с двойной трезвостью
const WIDE_FACTOR := 1.5
const HIGH_FACTOR := 1.25
const SLOW_FACTOR := 0.7
const BOTTLE_RADIUS := 200.0       # радиус деморализации от бутылки
const BOTTLE_SOBER_LOSS := 2

# ---- шар (режим «Новогодний шар») ----
# Шар живёт по физике тела: тот же радиус, та же кривая отскока, та же
# гравитация уровня. Отдельных чисел ему нужно ровно одно — пауза перед
# возвращением после падения.
const BALL_RESPAWN := 1.2          # с

# ---- прочее ----
const GRACE_AFTER_LOSS := 0.8      # с, окно неуязвимости после потери HP
const SCORE_BOUNCE := 10
const SCORE_SOBER := 100
const SCORE_LEVEL := 50            # за взятый уровень: SCORE_LEVEL * номер
const COMBO_STEP := 10             # отскоков подряд на +1 к множителю
const MAX_MULT := 5

# ---- уровни ---------------------------------------------------------------
# Эскалация привязана к номеру уровня, а не к секундам: внутри уровня числа
# постоянны, шаг слышен на границе — как скорость в тетрисе.
#
#   гравитация  g(L) = g_max - (g_max - g0) * exp(-(L-1) / g_tau)
#   спавн       S(L) = s_min + (s0 - s_min) * exp(-(L-1) / s_tau)
#   лимит тел   N(L) = field0 + (L-1) / field_step,  не выше MAX_ON_FIELD
#   квота       Q(L) = quota0 + (L-1) / quota_step,  не выше quota_cap
#
# Все четыре монотонны по L, так что «каждый уровень тяжелее предыдущего»
# выполняется буквально. Кривые с насыщением: к сороковым уровням гравитация и
# спавн выходят на плато, дальше растёт только квота. Иначе сотый уровень
# физически не отбивается — время цикла отскока T = 2*sqrt(2*h*600/g), и уже
# при g > 2000 требуемый темп уходит за человеческий потолок в ~1 удар/с
# (BALANCE.md §1.1). Плато превращает хвост в испытание выносливости, а не в
# мясорубку с заранее известным исходом.
const LEVEL_MAX := 100
const LEVEL_HEAL_EVERY := 5        # каждые N уровней +1 HP, но не выше hp_max

# ---- Режимы ----
# Общего у них всё, кроме двух правил: кто стоит HP и есть ли на поле шар.
# Уровни, квоты, предметы и кривые сложности одни и те же.
const MODE_ORDER := ["santa", "ball"]
const MODES := {
	"santa": {
		"label": "Пьяный Дед Мороз",
		"short": "деды",
		"hint": "Ни один не должен упасть: уронил — минус шапка",
	},
	"ball": {
		"label": "Новогодний шар",
		"short": "шар",
		"hint": "Шар ронять нельзя, Дедов Морозов — можно. Но они дают очки",
	},
}

# ---- Пресеты сложности ----
const DIFF_ORDER := ["casual", "normal", "hardcore"]
const DIFFICULTY := {
	"casual": {
		"label": "Ёлочка",
		"hint": "Спокойно разобраться, что тут вообще происходит",
		"hp_start": 7, "hp_max": 7,
		"g0": 420.0, "g_max": 1100.0, "g_tau": 22.0,
		"spawn0": 5.0, "spawn_min": 1.5, "spawn_tau": 26.0,
		"field0": 2, "field_step": 8.0,
		"quota0": 2, "quota_step": 5.0, "quota_cap": 8,
		"bonus_every": 12.0, "brine_every": 45.0,
		"hazard_level": 8, "hazard_every": 26.0,
	},
	"normal": {
		"label": "Корпоратив",
		"hint": "Как задумано: руки заняты, голова считает",
		"hp_start": 5, "hp_max": 5,
		"g0": 480.0, "g_max": 1400.0, "g_tau": 18.0,
		"spawn0": 4.2, "spawn_min": 1.35, "spawn_tau": 22.0,
		"field0": 2, "field_step": 6.0,
		"quota0": 2, "quota_step": 4.0, "quota_cap": 8,
		"bonus_every": 15.0, "brine_every": 60.0,
		"hazard_level": 6, "hazard_every": 20.0,
	},
	"hardcore": {
		"label": "Похмелье",
		"hint": "Двадцатый уровень тут дороже сотого на Ёлочке",
		"hp_start": 5, "hp_max": 5,
		"g0": 560.0, "g_max": 1800.0, "g_tau": 14.0,
		"spawn0": 3.6, "spawn_min": 1.05, "spawn_tau": 18.0,
		"field0": 3, "field_step": 5.0,
		"quota0": 3, "quota_step": 4.0, "quota_cap": 10,
		"bonus_every": 18.0, "brine_every": 75.0,
		"hazard_level": 4, "hazard_every": 16.0,
	},
}


static func preset(diff_key: String) -> Dictionary:
	return DIFFICULTY.get(diff_key, DIFFICULTY["normal"])


static func mode(mode_key: String) -> Dictionary:
	return MODES.get(mode_key, MODES["santa"])


## Ключ рекорда в профиле. Основной режим держит старые ключи без префикса —
## иначе таблица рекордов обнулилась бы при обновлении игры.
static func record_key(mode_key: String, diff_key: String) -> String:
	return diff_key if mode_key == "santa" else "%s:%s" % [mode_key, diff_key]


static func gravity_for(p: Dictionary, level: int) -> float:
	var g_max: float = p["g_max"]
	var g0: float = p["g0"]
	var tau: float = p["g_tau"]
	return g_max - (g_max - g0) * exp(-float(level - 1) / tau)


static func spawn_interval_for(p: Dictionary, level: int) -> float:
	var s_min: float = p["spawn_min"]
	var s0: float = p["spawn0"]
	var tau: float = p["spawn_tau"]
	return s_min + (s0 - s_min) * exp(-float(level - 1) / tau)


static func field_cap_for(p: Dictionary, level: int) -> int:
	var step: float = p["field_step"]
	return mini(MAX_ON_FIELD, int(p["field0"]) + int(float(level - 1) / step))


static func quota_for(p: Dictionary, level: int) -> int:
	var step: float = p["quota_step"]
	return mini(int(p["quota_cap"]), int(p["quota0"]) + int(float(level - 1) / step))
