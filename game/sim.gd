class_name Sim
extends RefCounted
## Симуляция забега: физика, спавн, предметы, уровни, очки.
##
## Ничего не рисует, не звучит и не читает ввод — только считает. Вид (arena.gd)
## подписывается на сигналы и превращает события в частицы, звук и тряску, а бот
## самопроверки (selfcheck.gd) гоняет ту же симуляцию без единой ноды.
##
## Единственный вход снаружи — `aim_x` (куда игрок ведёт палку) и `step(dt)`.

signal bounced(santa: Santa, sweet: bool)          ## удар по палке
signal sobered(santa: Santa, points: int)          ## Дед Мороз протрезвел и улетает
signal fell(x: float)                              ## тело ушло за нижнюю грань
signal item_applied(kind: String, gained: bool, x: float)
signal damaged(hp_left: int)                       ## потеряно HP
signal level_cleared(level: int, healed: bool)     ## уровень взят
signal finished(victory: bool)                     ## забег кончился

enum Outcome { NONE, DEFEAT, VICTORY }

const PADDLE_TOP := CFG.PADDLE_Y - CFG.PADDLE_HEIGHT / 2.0
const PLANE := PADDLE_TOP - CFG.SANTA_RADIUS       ## Y центра Деда в момент касания

const BONUS_KINDS := ["wide", "high", "slow", "snack"]


class Santa:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var sober := 0
	var phase := 0.0
	var rot := 0.0
	var spin := 0.0
	var flip := false
	var anim_offset := 0
	var escaping := false


class Item:
	var kind := ""
	var x := 0.0
	var y := 0.0
	var bad := false


# ---- забег ----
var diff := "normal"
var preset: Dictionary = CFG.DIFFICULTY["normal"]
var running := false
var outcome := Outcome.NONE
var endless := false               ## сотый уровень взят, играем дальше ради счёта

var t := 0.0
var level := 1
var hp := 0
var score := 0
var mult := 1
var streak := 0

# ---- поле ----
var santas: Array[Santa] = []
var items: Array[Item] = []

var aim_x := CFG.ARENA_W / 2.0     ## куда игрок ведёт палку; ставится снаружи
var paddle_x := CFG.ARENA_W / 2.0
var paddle_vx := 0.0

# ---- уровень ----
var quota_done := 0
var quota_need := 0

# ---- таймеры ----
var next_santa := 0.0
var next_bonus := 0.0
var next_brine := 0.0
var next_hazard := -1.0
var wide_until := -1.0
var high_until := -1.0
var slow_until := -1.0
var snack := 0
var grace_until := -1.0

# ---- итоги забега ----
var bounces := 0
var sweet_hits := 0
var sobered_total := 0
var misses := 0
var items_good := 0
var items_bad := 0
var max_streak := 0

var _pv_hist: Array[float] = []


func start(diff_key: String) -> void:
	diff = diff_key
	preset = CFG.preset(diff_key)
	running = true
	outcome = Outcome.NONE
	endless = false

	t = 0.0
	level = 1
	hp = int(preset["hp_start"])
	score = 0
	mult = 1
	streak = 0

	santas.clear()
	items.clear()
	paddle_x = CFG.ARENA_W / 2.0
	aim_x = paddle_x
	paddle_vx = 0.0
	_pv_hist.clear()

	quota_done = 0
	quota_need = CFG.quota_for(preset, 1)

	next_santa = 0.0
	next_bonus = float(preset["bonus_every"])
	next_brine = float(preset["brine_every"])
	next_hazard = -1.0
	wide_until = -1.0
	high_until = -1.0
	slow_until = -1.0
	snack = 0
	grace_until = -1.0

	bounces = 0
	sweet_hits = 0
	sobered_total = 0
	misses = 0
	items_good = 0
	items_bad = 0
	max_streak = 0


## Продолжить забег после взятого сотого уровня — уже без потолка.
func continue_endless() -> void:
	if outcome != Outcome.VICTORY:
		return
	endless = true
	running = true
	outcome = Outcome.NONE
	level += 1
	quota_done = 0
	quota_need = CFG.quota_for(preset, level)


func gravity_now() -> float:
	var g := CFG.gravity_for(preset, level)
	return g * CFG.SLOW_FACTOR if t < slow_until else g


func half_width_now() -> float:
	return CFG.PADDLE_WIDTH * (CFG.WIDE_FACTOR if t < wide_until else 1.0) / 2.0


func stats() -> Dictionary:
	return {
		"diff": diff,
		"level": level,
		"score": score,
		"time": t,
		"hp": hp,
		"hp_max": int(preset["hp_max"]),
		"bounces": bounces,
		"sweet_hits": sweet_hits,
		"sobered": sobered_total,
		"misses": misses,
		"items_good": items_good,
		"items_bad": items_bad,
		"streak": max_streak,
		"victory": outcome == Outcome.VICTORY,
	}


# ============================================================== физика ====

func step(dt: float) -> void:
	if not running:
		return
	t += dt
	var g := gravity_now()
	var half_w := half_width_now()

	_spawn(g)

	# палка следует за курсором без сглаживания
	var prev_x := paddle_x
	paddle_x = clampf(aim_x, half_w, CFG.ARENA_W - half_w)
	_pv_hist.append((paddle_x - prev_x) / dt)
	if _pv_hist.size() > CFG.SPEED_SAMPLES:
		_pv_hist.remove_at(0)
	var sum := 0.0
	for v in _pv_hist:
		sum += v
	paddle_vx = clampf(sum / _pv_hist.size(), -CFG.SPEED_CLAMP, CFG.SPEED_CLAMP)

	for i in range(santas.size() - 1, -1, -1):
		var s := santas[i]

		if s.escaping:                                # протрезвел — улетает вверх
			s.y -= CFG.ESCAPE_SPEED * dt
			s.rot *= 0.85
			if s.y < -120.0:
				santas.remove_at(i)
			continue

		var prev_y := s.y
		s.vy += g * dt
		s.x += (s.vx + CFG.DRIFT_AMP * sin(t * CFG.DRIFT_FREQ + s.phase)) * dt
		s.y += s.vy * dt
		s.rot += s.spin * dt

		if s.x < CFG.SANTA_RADIUS:
			s.x = CFG.SANTA_RADIUS
			s.vx = -s.vx * CFG.WALL_DAMP
			s.spin = -s.spin
		if s.x > CFG.ARENA_W - CFG.SANTA_RADIUS:
			s.x = CFG.ARENA_W - CFG.SANTA_RADIUS
			s.vx = -s.vx * CFG.WALL_DAMP
			s.spin = -s.spin
		if s.y < CFG.SANTA_RADIUS and s.vy < 0.0:
			s.y = CFG.SANTA_RADIUS
			s.vy = -s.vy * CFG.WALL_DAMP

		# касание верхней грани палки
		if s.vy > 0.0 and prev_y <= PLANE and s.y >= PLANE and absf(s.x - paddle_x) <= half_w:
			_bounce(s, g, half_w)
			continue

		# пол
		if s.y - CFG.SANTA_RADIUS > CFG.ARENA_H:
			santas.remove_at(i)
			streak = 0
			mult = 1
			misses += 1
			fell.emit(s.x)
			lose_hp()

	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		it.y += CFG.ITEM_FALL_SPEED * dt
		var hit_paddle := (it.y + CFG.ITEM_RADIUS >= PADDLE_TOP
				and it.y - CFG.ITEM_RADIUS <= CFG.PADDLE_Y + CFG.PADDLE_HEIGHT / 2.0
				and absf(it.x - paddle_x) <= half_w + CFG.ITEM_RADIUS * 0.4)
		if hit_paddle:
			items.remove_at(i)
			_apply_item(it)
		elif it.y - CFG.ITEM_RADIUS > CFG.ARENA_H:
			items.remove_at(i)


func _spawn(g: float) -> void:
	if t >= next_santa:
		if santas.size() < CFG.field_cap_for(preset, level):
			var s := Santa.new()
			s.x = spawn_x(g)
			s.y = -CFG.SANTA_RADIUS
			s.phase = randf() * TAU
			s.rot = randf_range(-0.4, 0.4)
			s.spin = randf_range(-1.4, 1.4)
			s.flip = randf() < 0.5
			s.anim_offset = randi()
			santas.append(s)
		next_santa = t + CFG.spawn_interval_for(preset, level)

	if t >= next_bonus:
		_add_item(BONUS_KINDS[randi() % BONUS_KINDS.size()], false)
		next_bonus = t + float(preset["bonus_every"])

	if t >= next_brine:
		_add_item("brine", false)
		next_brine = t + float(preset["brine_every"])

	if level >= int(preset["hazard_level"]):
		var every: float = preset["hazard_every"]
		if next_hazard < 0.0:
			next_hazard = t + every * 0.5           # уровень только начался, дать вдохнуть
		elif t >= next_hazard:
			_add_item("coal" if randf() < 0.5 else "bottle", true)
			next_hazard = t + every


func _add_item(kind: String, bad: bool) -> void:
	var it := Item.new()
	it.kind = kind
	it.x = item_x()
	it.y = -CFG.ITEM_RADIUS
	it.bad = bad
	items.append(it)


func _bounce(s: Santa, g: float, half_w: float) -> void:
	var off := s.x - paddle_x
	var d := minf(1.0, absf(off) / half_w)
	var h := bounce_height(d)
	if t < high_until:
		h *= CFG.HIGH_FACTOR
	h = minf(h, CFG.H_CAP)

	s.y = PLANE
	s.vy = -sqrt(2.0 * g * h * CFG.ARENA_H)
	s.vx = clampf(signf(off) * CFG.VX_BASE * d + paddle_vx * CFG.VX_FROM_PADDLE,
			-CFG.VX_MAX, CFG.VX_MAX)
	s.spin = clampf(s.vx / 90.0, -3.2, 3.2)

	var sweet := d <= CFG.SWEET_ZONE
	var gain := CFG.SOBER_GAIN_SWEET if sweet else CFG.SOBER_GAIN_NORMAL
	if snack > 0:
		gain *= 2
		snack -= 1
	s.sober += gain

	bounces += 1
	if sweet:
		sweet_hits += 1
	streak += 1
	max_streak = maxi(max_streak, streak)
	mult = mini(CFG.MAX_MULT, 1 + streak / CFG.COMBO_STEP)
	score += CFG.SCORE_BOUNCE * mult
	bounced.emit(s, sweet)

	if s.sober >= CFG.SOBER_THRESHOLD:
		s.escaping = true
		s.vx = 0.0
		s.vy = 0.0
		var points := CFG.SCORE_SOBER * mult
		score += points
		sobered_total += 1
		quota_done += 1
		sobered.emit(s, points)
		if quota_done >= quota_need:
			_clear_level()


func _clear_level() -> void:
	score += CFG.SCORE_LEVEL * level

	if level >= CFG.LEVEL_MAX and not endless:
		running = false
		outcome = Outcome.VICTORY
		finished.emit(true)
		return

	var healed := level % CFG.LEVEL_HEAL_EVERY == 0 and hp < int(preset["hp_max"])
	if healed:
		hp += 1
	level_cleared.emit(level, healed)

	level += 1
	quota_done = 0
	quota_need = CFG.quota_for(preset, level)
	next_hazard = -1.0 if level == int(preset["hazard_level"]) else next_hazard


func _apply_item(it: Item) -> void:
	if it.bad:
		streak = 0
		mult = 1
		items_bad += 1
		if it.kind == "bottle":
			for s in santas:
				if s.escaping:
					continue
				if Vector2(s.x - it.x, s.y - CFG.PADDLE_Y).length() <= CFG.BOTTLE_RADIUS:
					s.sober = maxi(0, s.sober - CFG.BOTTLE_SOBER_LOSS)
		item_applied.emit(it.kind, false, it.x)
		lose_hp()
		return

	items_good += 1
	var gained := true
	match it.kind:
		"brine":
			gained = hp < int(preset["hp_max"])
			if gained:
				hp += 1
		"wide":
			wide_until = t + CFG.WIDE_DURATION
		"high":
			high_until = t + CFG.HIGH_DURATION
		"slow":
			slow_until = t + CFG.SLOW_DURATION
		_:
			snack = CFG.SNACK_BOUNCES
	item_applied.emit(it.kind, gained, it.x)


func lose_hp() -> void:
	if t < grace_until:
		return
	hp -= 1
	grace_until = t + CFG.GRACE_AFTER_LOSS
	damaged.emit(hp)
	if hp <= 0:
		running = false
		outcome = Outcome.DEFEAT
		finished.emit(false)


# ---- чистая математика (её же гоняет самопроверка) ----

func bounce_height(d: float) -> float:
	for seg in CFG.BOUNCE:
		if d <= seg[1]:
			var k: float = 0.0 if is_equal_approx(seg[1], seg[0]) else (d - seg[0]) / (seg[1] - seg[0])
			return seg[2] + (seg[3] - seg[2]) * k
	return CFG.BOUNCE[-1][3]


## Складывает X внутрь арены с учётом отражений от стен — как если бы тело
## отскакивало от них по пути.
func fold_x(x: float) -> float:
	var span := CFG.ARENA_W - 2.0 * CFG.SANTA_RADIUS
	var u := fposmod(x - CFG.SANTA_RADIUS, 2.0 * span)
	if u > span:
		u = 2.0 * span - u
	return u + CFG.SANTA_RADIUS


## Снос метелью за интервал [t0, t0+T] — точный интеграл, не приближение.
func drift_shift(phase: float, t0: float, duration: float) -> float:
	var w := CFG.DRIFT_FREQ
	return (CFG.DRIFT_AMP / w) * (cos(w * t0 + phase) - cos(w * (t0 + duration) + phase))


## Предсказание точки и времени касания плоскости палки.
## Возвращает Vector2(время, X) либо Vector2.INF, если тело туда не придёт.
func predict(s: Santa, g: float) -> Vector2:
	var disc := s.vy * s.vy + 2.0 * g * (PLANE - s.y)
	if disc < 0.0:
		return Vector2.INF
	var time := (-s.vy + sqrt(disc)) / g
	if time < 0.0:
		return Vector2.INF
	return Vector2(time, fold_x(s.x + s.vx * time + drift_shift(s.phase, t, time)))


## Честный спавн: если новое тело приземлится одновременно с уже летящим,
## ставим его рядом, а не на другом конце арены — иначе игрок не успевает.
func spawn_x(g: float) -> float:
	var lo := CFG.SPAWN_MARGIN
	var hi := CFG.ARENA_W - CFG.SPAWN_MARGIN
	var fall_t := sqrt((2.0 * (PLANE + CFG.SANTA_RADIUS)) / g)
	var clash: Array[float] = []
	for s in santas:
		var q := predict(s, g)
		if q != Vector2.INF and absf(q.x - fall_t) < CFG.FAIR_SPAWN_WINDOW:
			clash.append(q.y)
	if clash.is_empty():
		return randf_range(lo, hi)
	var c: float = clash[randi() % clash.size()]
	return clampf(c + randf_range(-CFG.FAIR_SPAWN_REACH, CFG.FAIR_SPAWN_REACH), lo, hi)


## Предметы падают в ту треть арены, где сейчас меньше всего Дедов Морозов —
## чтобы бонус приходилось выбирать, а не получать даром.
func item_x() -> float:
	var count := [0, 0, 0]
	for s in santas:
		count[clampi(int(s.x / CFG.ARENA_W * 3.0), 0, 2)] += 1
	var best := 0
	for i in range(1, 3):
		if count[i] < count[best]:
			best = i
	return randf_range(best * CFG.ARENA_W / 3.0 + 40.0, (best + 1) * CFG.ARENA_W / 3.0 - 40.0)


static func nose_tier(sober: int) -> String:
	if sober <= 1: return "c1"
	if sober <= 3: return "c2"
	if sober <= 5: return "c3"
	return "c4"


static func nose_color(sober: int) -> Color:
	for tier in CFG.NOSE_TIERS:
		if sober <= tier[0]:
			return tier[1]
	return CFG.NOSE_TIERS[-1][1]
