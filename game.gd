extends Node2D
## Merry Christmas — аркада-жонглирование Дедами Морозами.
##
## Вся игра в одном скрипте: физика, отрисовка, ввод, рекорды. Отрисовка
## иммедиатная (_draw каждый кадр) — так же, как было в браузерной версии,
## откуда игра портирована. Ноды под тела не заводятся: их до 12 штук, и
## рисовать их напрямую дешевле, чем держать дерево.
##
## Все числа — в config.gd.

const PADDLE_TOP := CFG.PADDLE_Y - CFG.PADDLE_HEIGHT / 2.0
const PLANE := PADDLE_TOP - CFG.SANTA_RADIUS       # Y центра Деда в момент касания

# доля высоты спрайта палки, на которой лежит сама планка (замерено по альфе)
const PADDLE_BAR := 0.2796
const PADDLE_ASPECT := 152.0 / 384.0

const ANIM_FRAMES := 6
const ANIM_FPS := 8.0

const SAVE_PATH := "user://records.json"
const SAVE_VERSION := 1

const TEX := {
	"santa_c1": preload("res://assets/santa_c1.png"),
	"santa_c2": preload("res://assets/santa_c2.png"),
	"santa_c3": preload("res://assets/santa_c3.png"),
	"santa_c4": preload("res://assets/santa_c4.png"),
	"santa_fly": preload("res://assets/santa_fly.png"),
	"santa_c1_sheet": preload("res://assets/santa_c1_sheet.png"),
	"santa_c2_sheet": preload("res://assets/santa_c2_sheet.png"),
	"santa_c3_sheet": preload("res://assets/santa_c3_sheet.png"),
	"santa_c4_sheet": preload("res://assets/santa_c4_sheet.png"),
	"paddle": preload("res://assets/paddle.png"),
	"bg": preload("res://assets/bg.png"),
	"item_brine": preload("res://assets/item_brine.png"),
	"item_snack": preload("res://assets/item_snack.png"),
	"item_wide": preload("res://assets/item_wide.png"),
	"item_high": preload("res://assets/item_high.png"),
	"item_slow": preload("res://assets/item_slow.png"),
	"item_coal": preload("res://assets/item_coal.png"),
	"item_bottle": preload("res://assets/item_bottle.png"),
}

const SFX_FILES := {
	"hit": [preload("res://assets/audio/hit.wav"), 0.55],
	"sober": [preload("res://assets/audio/sober.wav"), 0.5],
	"miss": [preload("res://assets/audio/miss.wav"), 0.7],
	"bonus": [preload("res://assets/audio/bonus.wav"), 0.5],
	"hazard": [preload("res://assets/audio/hazard.wav"), 0.6],
}
const MUSIC := preload("res://assets/audio/music.ogg")

const BONUS_KINDS := ["wide", "high", "slow", "snack"]
const ITEM_TEX := {
	"brine": "item_brine", "snack": "item_snack", "wide": "item_wide",
	"high": "item_high", "slow": "item_slow", "coal": "item_coal",
	"bottle": "item_bottle",
}

# палитра интерфейса
const C_TEXT := Color("eaf1ff")
const C_DIM := Color("9fb0cc")
const C_MUTED := Color("7d8aa3")
const C_FAINT := Color("5b6478")
const C_GOLD := Color("ffd166")
const C_GREEN := Color("8ef2a4")
const C_RED := Color("e8433f")
const C_BLUE := Color("9ad8ff")

enum State { MENU, PLAY, PAUSE, OVER }


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


class Puff:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var r := 0.0
	var color := Color.WHITE


class Pop:
	var pos := Vector2.ZERO
	var text := ""
	var color := Color.WHITE
	var life := 0.0


class Flake:
	var pos := Vector2.ZERO
	var r := 0.0
	var v := 0.0
	var d := 0.0
	var phase := 0.0


class ClickZone:
	var rect := Rect2()
	var action := Callable()

# ---- состояние забега ----
var state := State.MENU
var diff := "normal"
var d_preset: Dictionary = CFG.DIFFICULTY["normal"]
var t := 0.0
var hp := 0
var score := 0
var mult := 1
var streak := 0
var max_streak := 0
var new_record := false

var santas: Array[Santa] = []
var items: Array[Item] = []
var puffs: Array[Puff] = []
var pops: Array[Pop] = []

var px := CFG.ARENA_W / 2.0
var pv := 0.0
var aim_x := CFG.ARENA_W / 2.0
var squash := 0.0
var shake := 0.0
var flash := 0.0

var next_santa := 0.0
var next_bonus := 0.0
var next_brine := 0.0
var next_hazard := 0.0
var wide_until := -1.0
var high_until := -1.0
var slow_until := -1.0
var snack := 0
var grace_until := -1.0

var muted := false

var _pv_hist: Array[float] = []
var _flakes: Array[Flake] = []
var _records: Dictionary = {}
var _buttons: Array[ClickZone] = []
var _sfx: Dictionary = {}
var _music: AudioStreamPlayer
var _font: Font
var _glow: GradientTexture2D
var _vignette: GradientTexture2D
var _btn_normal: StyleBoxFlat
var _btn_hot: StyleBoxFlat
var _headless := false
var _sandbox := false      # отладочный прогон: файл рекордов не трогаем


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build_audio()
	_build_styles()
	_load_records()

	for i in 70:
		var f := Flake.new()
		f.pos = Vector2(randf() * CFG.ARENA_W, randf() * CFG.ARENA_H)
		f.r = randf_range(0.8, 2.4)
		f.v = randf_range(12.0, 40.0)
		f.d = randf_range(-14.0, 14.0)
		f.phase = randf() * TAU
		_flakes.append(f)

	reset("normal")
	state = State.MENU
	_handle_cmdline()


func _process(delta: float) -> void:
	if _headless:
		return
	for f in _flakes:
		f.pos.y += f.v * delta
		f.pos.x += sin(t + f.phase) * f.d * delta
		if f.pos.y > CFG.ARENA_H:
			f.pos.y = -4.0
			f.pos.x = randf() * CFG.ARENA_W
	var want := Input.MOUSE_MODE_HIDDEN if state == State.PLAY else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state != State.PLAY:
		return
	if not _headless:
		aim_x = get_local_mouse_position().x
	step(delta)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var p := get_local_mouse_position()
		if p.x > CFG.ARENA_W - 120.0 and p.y > CFG.ARENA_H - 44.0:
			toggle_mute()
			return
		for b in _buttons:
			if b.rect.has_point(p):
				b.action.call()
				return
		return

	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	# physical_keycode, а не keycode: игра с русской раскладкой должна слушаться
	# тех же клавиш, что с английской
	match key.physical_keycode:
		KEY_SPACE:
			if state == State.PLAY:
				state = State.PAUSE
				_music.stream_paused = true
			elif state == State.PAUSE:
				state = State.PLAY
				_music.stream_paused = false
		KEY_ESCAPE:
			if state != State.MENU:
				state = State.MENU
				_music.stop()
		KEY_R:
			if state == State.OVER:
				reset(diff)
				start_music()
		KEY_M:
			toggle_mute()
		KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_records()


# ============================================================== физика ====

func reset(diff_key: String) -> void:
	diff = diff_key
	d_preset = CFG.DIFFICULTY[diff_key]
	state = State.PLAY
	t = 0.0
	hp = d_preset["hp_start"]
	score = 0
	mult = 1
	streak = 0
	max_streak = 0
	santas.clear()
	items.clear()
	puffs.clear()
	pops.clear()
	px = CFG.ARENA_W / 2.0
	aim_x = px
	pv = 0.0
	_pv_hist.clear()
	squash = 0.0
	shake = 0.0
	flash = 0.0
	next_santa = 0.0
	next_bonus = d_preset["bonus_every"]
	next_brine = d_preset["brine_every"]
	next_hazard = d_preset["hazard_from"]
	wide_until = -1.0
	high_until = -1.0
	slow_until = -1.0
	snack = 0
	grace_until = -1.0


func gravity_now() -> float:
	var g_max: float = d_preset["g_max"]
	var g: float = g_max - (g_max - d_preset["g0"]) * exp(-t / d_preset["g_tau"])
	return g * CFG.SLOW_FACTOR if t < slow_until else g


func half_width_now() -> float:
	return CFG.PADDLE_WIDTH * (CFG.WIDE_FACTOR if t < wide_until else 1.0) / 2.0


func step(dt: float) -> void:
	t += dt
	var g := gravity_now()
	var half_w := half_width_now()

	_spawn(g)

	# палка следует за курсором без сглаживания
	var prev_px := px
	px = clampf(aim_x, half_w, CFG.ARENA_W - half_w)
	_pv_hist.append((px - prev_px) / dt)
	if _pv_hist.size() > CFG.SPEED_SAMPLES:
		_pv_hist.remove_at(0)
	var sum := 0.0
	for v in _pv_hist:
		sum += v
	pv = clampf(sum / _pv_hist.size(), -CFG.SPEED_CLAMP, CFG.SPEED_CLAMP)

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
		if s.vy > 0.0 and prev_y <= PLANE and s.y >= PLANE and absf(s.x - px) <= half_w:
			_bounce(s, g, half_w)
			continue

		# пол
		if s.y - CFG.SANTA_RADIUS > CFG.ARENA_H:
			santas.remove_at(i)
			streak = 0
			mult = 1
			add_puff(Vector2(s.x, CFG.ARENA_H - 6.0), 14, Color("ff8080"))
			play_sfx("miss")
			lose_hp()

	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		it.y += CFG.ITEM_FALL_SPEED * dt
		var hit_paddle := (it.y + CFG.ITEM_RADIUS >= PADDLE_TOP
				and it.y - CFG.ITEM_RADIUS <= CFG.PADDLE_Y + CFG.PADDLE_HEIGHT / 2.0
				and absf(it.x - px) <= half_w + CFG.ITEM_RADIUS * 0.4)
		if hit_paddle:
			items.remove_at(i)
			apply_item(it)
		elif it.y - CFG.ITEM_RADIUS > CFG.ARENA_H:
			items.remove_at(i)

	for i in range(puffs.size() - 1, -1, -1):
		var p := puffs[i]
		p.life -= dt
		if p.life <= 0.0:
			puffs.remove_at(i)
			continue
		p.vel.y += 420.0 * dt
		p.pos += p.vel * dt

	for i in range(pops.size() - 1, -1, -1):
		var p := pops[i]
		p.life -= dt
		p.pos.y -= 34.0 * dt
		if p.life <= 0.0:
			pops.remove_at(i)

	squash = maxf(0.0, squash - dt * 6.0)
	shake = maxf(0.0, shake - dt)
	flash = maxf(0.0, flash - dt * 1.6)


func _spawn(g: float) -> void:
	if t >= next_santa:
		if santas.size() < CFG.MAX_ON_FIELD:
			var s := Santa.new()
			s.x = spawn_x(g)
			s.y = -CFG.SANTA_RADIUS
			s.phase = randf() * TAU
			s.rot = randf_range(-0.4, 0.4)
			s.spin = randf_range(-1.4, 1.4)
			s.flip = randf() < 0.5
			s.anim_offset = randi() % ANIM_FRAMES
			santas.append(s)
		var s_min: float = d_preset["spawn_min"]
		next_santa = t + s_min + (d_preset["spawn_s0"] - s_min) * exp(-t / d_preset["spawn_tau"])

	if t >= next_bonus:
		_add_item(BONUS_KINDS[randi() % BONUS_KINDS.size()], false)
		next_bonus = t + d_preset["bonus_every"]

	if t >= next_brine:
		_add_item("brine", false)
		next_brine = t + d_preset["brine_every"]

	if t >= d_preset["hazard_from"] and t >= next_hazard:
		_add_item("coal" if randf() < 0.5 else "bottle", true)
		next_hazard = t + d_preset["hazard_every"]


func _add_item(kind: String, bad: bool) -> void:
	var it := Item.new()
	it.kind = kind
	it.x = item_x()
	it.y = -CFG.ITEM_RADIUS
	it.bad = bad
	items.append(it)


func _bounce(s: Santa, g: float, half_w: float) -> void:
	var off := s.x - px
	var d := minf(1.0, absf(off) / half_w)
	var h := bounce_height(d)
	if t < high_until:
		h *= CFG.HIGH_FACTOR
	h = minf(h, CFG.H_CAP)

	s.y = PLANE
	s.vy = -sqrt(2.0 * g * h * CFG.ARENA_H)
	s.vx = clampf(signf(off) * CFG.VX_BASE * d + pv * CFG.VX_FROM_PADDLE, -CFG.VX_MAX, CFG.VX_MAX)
	s.spin = clampf(s.vx / 90.0, -3.2, 3.2)

	var sweet := d <= CFG.SWEET_ZONE
	var gain := CFG.SOBER_GAIN_SWEET if sweet else CFG.SOBER_GAIN_NORMAL
	if snack > 0:
		gain *= 2
		snack -= 1
	s.sober += gain

	streak += 1
	max_streak = maxi(max_streak, streak)
	mult = mini(CFG.MAX_MULT, 1 + streak / CFG.COMBO_STEP)
	score += CFG.SCORE_BOUNCE * mult

	squash = 1.0
	add_puff(Vector2(s.x, PLANE + CFG.SANTA_RADIUS), 12 if sweet else 7,
			Color("ffe08a") if sweet else Color("dbe9ff"))
	play_sfx("hit", 0.8 + 0.16 * s.sober)          # икота: чем трезвее, тем выше тон

	if s.sober >= CFG.SOBER_THRESHOLD:
		s.escaping = true
		s.vx = 0.0
		s.vy = 0.0
		score += CFG.SCORE_SOBER * mult
		add_pop(Vector2(s.x, s.y - 40.0), "+%d" % (CFG.SCORE_SOBER * mult), C_GREEN)
		add_puff(Vector2(s.x, s.y), 16, C_GREEN)
		play_sfx("sober")


func apply_item(it: Item) -> void:
	if it.bad:
		streak = 0
		mult = 1
		play_sfx("hazard")
		add_puff(Vector2(it.x, CFG.PADDLE_Y), 18, Color("ff9a5c"))
		if it.kind == "bottle":
			for s in santas:
				if s.escaping:
					continue
				if Vector2(s.x - it.x, s.y - CFG.PADDLE_Y).length() <= CFG.BOTTLE_RADIUS:
					s.sober = maxi(0, s.sober - CFG.BOTTLE_SOBER_LOSS)
			add_pop(Vector2(it.x, CFG.PADDLE_Y - 40.0), "по кругу!", Color("ff9a5c"))
		else:
			add_pop(Vector2(it.x, CFG.PADDLE_Y - 40.0), "уголь", Color("ff9a5c"))
		lose_hp()
		return

	play_sfx("bonus")
	add_puff(Vector2(it.x, CFG.PADDLE_Y), 12, C_BLUE)
	var at := Vector2(it.x, CFG.PADDLE_Y - 40.0)
	match it.kind:
		"brine":
			if hp < d_preset["hp_max"]:
				hp += 1
				add_pop(at, "+1 HP", C_GREEN)
			else:
				add_pop(at, "и так хорошо", C_BLUE)
		"wide":
			wide_until = t + CFG.WIDE_DURATION
			add_pop(at, "шире", C_BLUE)
		"high":
			high_until = t + CFG.HIGH_DURATION
			add_pop(at, "выше", C_BLUE)
		"slow":
			slow_until = t + CFG.SLOW_DURATION
			add_pop(at, "медленнее", C_BLUE)
		_:
			snack = CFG.SNACK_BOUNCES
			add_pop(at, "закуска ×2", C_BLUE)


func lose_hp() -> void:
	if t < grace_until:
		return
	hp -= 1
	grace_until = t + CFG.GRACE_AFTER_LOSS
	shake = 0.35
	flash = 0.5
	if hp <= 0:
		state = State.OVER
		new_record = save_record(diff, score, max_streak, t)
		_music.stop()


func add_pop(pos: Vector2, text: String, color: Color) -> void:
	var p := Pop.new()
	p.pos = pos
	p.text = text
	p.color = color
	p.life = 0.9
	pops.append(p)


func add_puff(pos: Vector2, n: int, color: Color) -> void:
	for i in n:
		var p := Puff.new()
		p.pos = pos
		p.vel = Vector2(randf_range(-140.0, 140.0), randf_range(-190.0, -40.0))
		p.life = randf_range(0.35, 0.8)
		p.r = randf_range(2.0, 5.0)
		p.color = color
		puffs.append(p)


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


# =========================================================== отрисовка ====

func _draw() -> void:
	_buttons.clear()
	var off := Vector2.ZERO
	if shake > 0.0:
		var k := shake * 14.0
		off = Vector2(randf_range(-k, k), randf_range(-k, k))
	draw_set_transform(off)

	_draw_backdrop()
	if state != State.MENU:
		var g := gravity_now()
		_draw_markers(g)
		for it in items:
			_draw_item(it)
		for s in santas:
			_draw_santa(s, off)
		_draw_paddle(off)
		_draw_effects()
		_draw_hud()

	draw_set_transform(Vector2.ZERO)

	if flash > 0.0:
		draw_texture_rect(_vignette, Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), false,
				Color(1.0, 0.16, 0.16, flash * 0.6))

	match state:
		State.MENU: _draw_menu()
		State.PAUSE: _draw_pause()
		State.OVER: _draw_over()
		_: pass


func _draw_backdrop() -> void:
	draw_texture_rect(TEX["bg"], Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), false)
	for f in _flakes:
		draw_circle(f.pos, f.r, Color(1, 1, 1, 0.35))
	draw_line(Vector2(0, CFG.ARENA_H - 1), Vector2(CFG.ARENA_W, CFG.ARENA_H - 1),
			Color("2a3550"), 2.0)


func _draw_markers(g: float) -> void:
	for s in santas:
		if s.escaping:
			continue
		var p := predict(s, g)
		if p == Vector2.INF:
			continue
		var a := clampf(1.15 - p.x / 2.4, 0.12, 0.9)
		var col := nose_color(s.sober)

		# пунктирная окружность на линии палки: 13 штрихов через пропуск
		var center := Vector2(p.y, CFG.PADDLE_Y)
		var r := CFG.SANTA_RADIUS + 2.0
		var seg := TAU / 13.0
		for i in 13:
			draw_arc(center, r, i * seg, i * seg + seg * 0.55, 4, Color(col, a), 2.0)

		# вертикальная нить от тела к маркеру
		draw_line(Vector2(p.y, CFG.PADDLE_Y - CFG.SANTA_RADIUS), Vector2(p.y, maxf(0.0, s.y)),
				Color(col, a * 0.28), 2.0)

		# тело ещё за верхней границей — рисуем предупреждение
		if s.y < 0.0:
			draw_colored_polygon(PackedVector2Array([
				Vector2(s.x - 10.0, 6.0), Vector2(s.x + 10.0, 6.0), Vector2(s.x, 22.0),
			]), Color(C_GOLD, 0.9))


func _draw_santa(s: Santa, off: Vector2) -> void:
	var col := nose_color(s.sober)

	# Свечение под телом — тот же цвет, что у носа. Нос на 60 px нечитаем, а
	# цветное пятно ловится боковым зрением даже когда тел на поле десяток.
	var rr := CFG.SANTA_RADIUS * 1.9
	draw_texture_rect(_glow, Rect2(s.x - rr, s.y - rr, rr * 2.0, rr * 2.0), false,
			Color(col, 0.22 if s.escaping else 0.42))

	var scale := Vector2(-1.0, 1.0) if s.flip else Vector2.ONE
	draw_set_transform(Vector2(s.x, s.y) + off, s.rot, scale)
	if s.escaping:
		var h := CFG.SANTA_RADIUS * 3.1
		var tex: Texture2D = TEX["santa_fly"]
		var w := h * tex.get_width() / float(tex.get_height())
		draw_texture_rect(tex, Rect2(-w / 2.0, -h / 2.0, w, h), false)
	else:
		var sheet: Texture2D = TEX["santa_%s_sheet" % nose_tier(s.sober)]
		var cell := sheet.get_height()
		var f := int(t * ANIM_FPS + s.anim_offset) % ANIM_FRAMES
		var h := CFG.SANTA_RADIUS * 3.4
		draw_texture_rect_region(sheet, Rect2(-h / 2.0, -h / 2.0, h, h),
				Rect2(f * cell, 0, cell, cell))
	draw_set_transform(off)


func _draw_paddle(off: Vector2) -> void:
	var half_w := half_width_now()
	var w := half_w * 2.0
	draw_set_transform(Vector2(px, CFG.PADDLE_Y) + off, 0.0, Vector2(1.0, 1.0 - squash * 0.35))
	var h := w * PADDLE_ASPECT
	draw_texture_rect(TEX["paddle"], Rect2(-w / 2.0, -PADDLE_BAR * h, w, h), false)
	draw_set_transform(off)

	if t < wide_until:                              # подсветка активного бонуса ширины
		draw_rect(Rect2(px - half_w, CFG.PADDLE_Y - 12.0, w, 24.0),
				Color("57d07a", 0.5), false, 2.0)


func _draw_item(it: Item) -> void:
	var tex: Texture2D = TEX[ITEM_TEX[it.kind]]
	var h := CFG.ITEM_RADIUS * 2.4
	var w := h * tex.get_width() / float(tex.get_height())
	draw_texture_rect(tex, Rect2(it.x - w / 2.0, it.y - h / 2.0, w, h), false)


func _draw_effects() -> void:
	for p in puffs:
		draw_circle(p.pos, p.r, Color(p.color, clampf(p.life * 1.6, 0.0, 1.0)))
	for p in pops:
		_text(p.pos, p.text, 17, Color(p.color, clampf(p.life * 1.3, 0.0, 1.0)),
				HORIZONTAL_ALIGNMENT_CENTER, true)


func _draw_hud() -> void:
	_text(Vector2(16, 14), str(score), 20, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	_text(Vector2(16, 40), "×%d   серия %d" % [mult, streak], 15,
			C_GOLD if mult > 1 else C_MUTED, HORIZONTAL_ALIGNMENT_LEFT, true, true)

	for i in int(d_preset["hp_max"]):               # HP шапками
		var x := CFG.ARENA_W - 26.0 - i * 26.0
		var a := 1.0 if i < hp else 0.2
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 9.0, 26.0), Vector2(x + 9.0, 26.0), Vector2(x, 10.0),
		]), Color(C_RED, a))
		draw_rect(Rect2(x - 10.0, 26.0, 20.0, 5.0), Color(1, 1, 1, a))

	var airborne := 0
	for s in santas:
		if not s.escaping:
			airborne += 1
	_text(Vector2(CFG.ARENA_W / 2.0, 16), "%s   ·   в воздухе %d   ·   %d с" %
			[d_preset["label"], airborne, int(t)], 14, C_MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, false, true)

	var ey := 64.0
	ey = _badge("шире", Color("57d07a"), wide_until, ey)
	ey = _badge("выше", Color("5aa8f2"), high_until, ey)
	ey = _badge("медленнее", Color("a97cf2"), slow_until, ey)
	if snack > 0:
		_text(Vector2(16, ey), "закуска ×2 · осталось %d" % snack, 13, Color("f2d98e", 0.85),
				HORIZONTAL_ALIGNMENT_LEFT, true, true)

	_text(Vector2(CFG.ARENA_W - 16.0, CFG.ARENA_H - 28.0),
			"звук выкл" if muted else "звук вкл", 18,
			C_FAINT if muted else C_BLUE, HORIZONTAL_ALIGNMENT_RIGHT, false, true)


func _badge(label: String, color: Color, until: float, y: float) -> float:
	var left := until - t
	if left <= 0.0:
		return y
	_text(Vector2(16, y), "%s %.1fc" % [label, left], 13, Color(color, 0.85),
			HORIZONTAL_ALIGNMENT_LEFT, true, true)
	return y + 18.0


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), Color(0.027, 0.043, 0.078, 0.82))
	var cx := CFG.ARENA_W / 2.0
	_text(Vector2(cx, 82), "MERRY CHRISTMAS", 46, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(Vector2(cx, 122), "Двигайте палку мышью и не давайте пьяным Дедам Морозам упасть.",
			18, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(cx, 148), "Шесть ударов отрезвляют Деда Мороза, и он улетает. Удар бантом считается за два.",
			18, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)

	for i in CFG.DIFF_ORDER.size():
		var key: String = CFG.DIFF_ORDER[i]
		var preset: Dictionary = CFG.DIFFICULTY[key]
		var x := cx - 330.0 + i * 230.0
		_button(Rect2(x, 182, 200, 62), preset["label"], _start.bind(key), diff == key)
		_text(Vector2(x + 100.0, 262), "%d HP" % preset["hp_start"], 13, C_MUTED,
				HORIZONTAL_ALIGNMENT_CENTER)

	_text(Vector2(cx, 306), "РЕКОРДЫ", 13, C_FAINT, HORIZONTAL_ALIGNMENT_CENTER, true)
	for i in CFG.DIFF_ORDER.size():
		var key: String = CFG.DIFF_ORDER[i]
		var y := 334.0 + i * 24.0
		_text(Vector2(270, y), CFG.DIFFICULTY[key]["label"], 15, C_DIM)
		if _records.has(key):
			var r: Dictionary = _records[key]
			_text(Vector2(510, y), str(r["score"]), 15, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
			_text(Vector2(610, y), "серия %d" % r["streak"], 14, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
			_text(Vector2(680, y), mmss(r["time"]), 14, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			_text(Vector2(510, y), "пока пусто", 15, Color("4a5468"), HORIZONTAL_ALIGNMENT_RIGHT)

	_text(Vector2(cx, 442), "Рекорды сохраняются сами.", 13, Color("4a5468"),
			HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(cx, 508), "пробел — пауза · Esc — меню · M — звук · F11 — весь экран",
			14, C_FAINT, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), Color(0.027, 0.043, 0.078, 0.72))
	var cx := CFG.ARENA_W / 2.0
	_text(Vector2(cx, CFG.ARENA_H / 2.0 - 10.0), "ПАУЗА", 44, C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(Vector2(cx, CFG.ARENA_H / 2.0 + 26.0), "пробел — продолжить", 17, C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)


func _draw_over() -> void:
	draw_rect(Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), Color(0.027, 0.043, 0.078, 0.85))
	var cx := CFG.ARENA_W / 2.0
	_text(Vector2(cx, 170), "ВСЕ УПАЛИ", 48, C_RED, HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(Vector2(cx, 232), "счёт %d" % score, 30, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	_text(Vector2(cx, 268), "лучшая серия %d   ·   продержались %d с" % [max_streak, int(t)],
			18, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)

	if new_record:
		_text(Vector2(cx, 302), "НОВЫЙ РЕКОРД · %s" % d_preset["label"], 20, C_GREEN,
				HORIZONTAL_ALIGNMENT_CENTER, true)
	elif _records.has(diff):
		_text(Vector2(cx, 300), "рекорд на «%s» — %d" % [d_preset["label"], _records[diff]["score"]],
				18, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)

	_button(Rect2(cx - 210.0, 340, 200, 56), "Ещё раз (R)", _start.bind(diff), true)
	_button(Rect2(cx + 10.0, 340, 200, 56), "В меню", _to_menu, false)


func _button(rect: Rect2, label: String, action: Callable, hot: bool) -> void:
	var b := ClickZone.new()
	b.rect = rect
	b.action = action
	_buttons.append(b)
	draw_style_box(_btn_hot if hot else _btn_normal, rect)
	var y := rect.position.y + rect.size.y / 2.0 + _font.get_ascent(18) / 2.0 - 2.0
	_text(Vector2(rect.position.x + rect.size.x / 2.0, y), label, 18, C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, true)


## Рисует строку. from_top=true — Y задаёт верх строки, а не базовую линию
## (как было в canvas с textBaseline='top').
func _text(pos: Vector2, s: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, bold := false, from_top := false) -> void:
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0
	if from_top:
		p.y += _font.get_ascent(size)
	# Жирного начертания у встроенного шрифта нет — обводка в тот же цвет
	# даёт нужный вес, не таща в проект второй файл шрифта.
	if bold:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 1, color)
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func nose_tier(sober: int) -> String:
	if sober <= 1: return "c1"
	if sober <= 3: return "c2"
	if sober <= 5: return "c3"
	return "c4"


func nose_color(sober: int) -> Color:
	for tier in CFG.NOSE_TIERS:
		if sober <= tier[0]:
			return tier[1]
	return CFG.NOSE_TIERS[-1][1]


func mmss(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(round(fmod(seconds, 60.0)))]


# ================================================================ ввод ====

func _start(key: String) -> void:
	reset(key)
	start_music()


func _to_menu() -> void:
	state = State.MENU
	_music.stop()


func toggle_mute() -> void:
	muted = not muted
	if muted:
		_music.stop()
	elif state == State.PLAY:
		start_music()
	_save_records()


func start_music() -> void:
	if muted:
		return
	_music.stream_paused = false
	if not _music.playing:
		_music.play()


func play_sfx(name: String, pitch := 1.0) -> void:
	if muted or _headless:
		return
	var p: AudioStreamPlayer = _sfx[name]
	p.pitch_scale = pitch
	p.play()


# ============================================================ рекорды ====

func save_record(diff_key: String, new_score: int, new_streak: int, time_s: float) -> bool:
	var cur: Dictionary = _records.get(diff_key, {})
	if not cur.is_empty() and int(cur["score"]) >= new_score:
		return false
	_records[diff_key] = {"score": new_score, "streak": new_streak, "time": int(round(time_s))}
	_save_records()
	return true


func _load_records() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("Рекорды не читаются: %s" % error_string(FileAccess.get_open_error()))
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Файл рекордов испорчен, начинаем с пустой таблицы")
		return
	muted = bool(data.get("muted", false))
	var recs: Variant = data.get("records", {})
	if typeof(recs) != TYPE_DICTIONARY:
		return
	# Читаем только известные ключи и только разумные числа: файл лежит в
	# пользовательской папке, руками его поправить может кто угодно.
	for key: String in CFG.DIFFICULTY:
		var r: Variant = recs.get(key)
		if typeof(r) != TYPE_DICTIONARY:
			continue
		_records[key] = {
			"score": clampi(int(r.get("score", 0)), 0, 1_000_000_000),
			"streak": clampi(int(r.get("streak", 0)), 0, 1_000_000),
			"time": clampi(int(r.get("time", 0)), 0, 1_000_000),
		}


func _save_records() -> void:
	if _sandbox:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Рекорды не сохранились: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"muted": muted,
		"records": _records,
	}, "  "))
	f.close()


# =========================================================== заготовки ====

func _build_audio() -> void:
	for name: String in SFX_FILES:
		var p := AudioStreamPlayer.new()
		p.stream = SFX_FILES[name][0]
		p.volume_db = linear_to_db(SFX_FILES[name][1])
		# один плеер на звук вместо пула нод: полифония даёт те же
		# перекрывающиеся голоса без ручной ротации
		p.max_polyphony = 6
		add_child(p)
		_sfx[name] = p

	_music = AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = MUSIC
	stream.loop = true
	_music.stream = stream
	_music.volume_db = linear_to_db(0.28)
	add_child(_music)


func _build_styles() -> void:
	_btn_normal = StyleBoxFlat.new()
	_btn_normal.bg_color = Color("182238")
	_btn_normal.border_color = Color("31415f")
	_btn_normal.set_border_width_all(2)
	_btn_normal.set_corner_radius_all(10)
	_btn_hot = _btn_normal.duplicate()
	_btn_hot.bg_color = C_RED
	_btn_hot.border_color = C_GOLD

	# Свечение под телом: белый круг с мягким краем, цвет задаётся модуляцией.
	# Плотное ядро до 0.18 — чтобы под спрайтом было пятно, а не дымка.
	_glow = _radial(_gradient([
		[0.0, Color.WHITE], [0.18, Color.WHITE], [1.0, Color(1, 1, 1, 0)],
	]), 128, 128)

	# Виньетка потери HP: прозрачный центр, крашеные края.
	_vignette = _radial(_gradient([
		[0.47, Color(1, 1, 1, 0)], [1.0, Color.WHITE],
	]), 256, 171)


## Gradient из пар [смещение, цвет]. Поточечно, а не присваиванием offsets и
## colors: массивы разной длины молча обрезаются до исходных двух точек, и
## градиент выходит ступенькой.
func _gradient(points: Array) -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, points[0][0])
	g.set_color(0, points[0][1])
	g.set_offset(1, points[-1][0])
	g.set_color(1, points[-1][1])
	for i in range(1, points.size() - 1):
		g.add_point(points[i][0], points[i][1])
	return g


func _radial(g: Gradient, w: int, h: int) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = w
	tex.height = h
	return tex


# ======================================================== самопроверка ====

## Отладочные режимы, в обычной игре не участвуют:
##   godot --headless -- --check              физика ботом + проверка формул
##   godot -- --shot out.png [--demo normal] [--ff 45]   снимок кадра
func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()

	if args.has("--check"):
		_headless = true
		_sandbox = true
		set_process(false)
		_check_math()
		print(_run_bot("normal", 90.0))
		get_tree().quit()
		return

	var shot := _arg(args, "--shot")
	if shot.is_empty():
		return
	_sandbox = true
	var demo := _arg(args, "--demo")
	if not demo.is_empty() and CFG.DIFFICULTY.has(demo):
		muted = true
		var ff := _arg(args, "--ff")
		_run_bot(demo, float(ff) if ff.is_valid_float() else 30.0)
		if args.has("--over"):                       # добить забег, чтобы снять экран проигрыша
			while state == State.PLAY:
				grace_until = -1.0
				lose_hp()
	_shoot(shot)


func _arg(args: PackedStringArray, name: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s %s" % [path, "ok" if err == OK else error_string(err)])
	get_tree().quit()


func _check_math() -> void:
	assert(is_equal_approx(bounce_height(0.0), 0.80))
	assert(is_equal_approx(bounce_height(0.15), 0.80))
	assert(is_equal_approx(bounce_height(1.0), 0.25))
	assert(is_equal_approx(bounce_height(0.375), 0.60))          # середина второго сегмента

	assert(is_equal_approx(fold_x(450.0), 450.0))                # внутри арены — без изменений
	assert(is_equal_approx(fold_x(900.0), 856.0))                # отражение от правой стены
	assert(is_equal_approx(fold_x(-22.0), 66.0))                 # отражение от левой
	assert(fold_x(5000.0) >= CFG.SANTA_RADIUS and fold_x(5000.0) <= CFG.ARENA_W - CFG.SANTA_RADIUS)

	# свободное падение с нулевой скоростью: t = sqrt(2h/g)
	var s := Santa.new()
	s.x = 300.0
	s.y = 0.0
	var p := predict(s, 1000.0)
	assert(is_equal_approx(p.x, sqrt(2.0 * PLANE / 1000.0)))

	# тело под плоскостью, подпрыгнет на 5 px и не дотянется — приземления нет
	s.y = PLANE + 50.0
	s.vy = -100.0
	assert(predict(s, 1000.0) == Vector2.INF)

	# оттуда же, но с запасом скорости: вернётся и пересечёт плоскость сверху
	s.vy = -600.0
	assert(is_equal_approx(predict(s, 1000.0).x, (600.0 + sqrt(260000.0)) / 1000.0))


## Простейший бот: целится в тело, которое приземлится первым. Для проверки
## того, что забег вообще живёт, этого достаточно.
func _run_bot(diff_key: String, seconds: float) -> String:
	reset(diff_key)
	var dt := 1.0 / 120.0
	var steps := int(seconds / dt)
	for i in steps:
		if state != State.PLAY:
			break
		var g := gravity_now()
		var best_t := INF
		for s in santas:
			if s.escaping:
				continue
			var p := predict(s, g)
			if p != Vector2.INF and p.x < best_t:
				best_t = p.x
				aim_x = p.y
		step(dt)
		assert(is_finite(px) and is_finite(t), "физика ушла в NaN на шаге %d" % i)
	return "CHECK diff=%s t=%.1f score=%d streak=%d hp=%d santas=%d state=%d" % [
		diff_key, t, score, max_streak, hp, santas.size(), state]
