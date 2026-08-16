class_name Arena
extends Node2D
## Вид арены: рисует то, что насчитал Sim, и переводит его события в частицы,
## всплывающие цифры, тряску и звук.
##
## Отрисовка иммедиатная (_draw каждый кадр) — так же, как было в браузерной
## версии, откуда игра портирована. Ноды под тела не заводятся: их до 12 штук,
## и рисовать их напрямую дешевле, чем держать дерево.
##
## Фон со снегом рисуется всегда, даже когда забега нет: под меню видно ту же
## арену, а не чёрный прямоугольник.

signal run_finished(stats: Dictionary)

const ANIM_FRAMES := 6
const ANIM_FPS := 8.0

# доля высоты спрайта палки, на которой лежит сама планка (замерено по альфе)
const PADDLE_BAR := 0.2796
const PADDLE_ASPECT := 152.0 / 384.0

const TEX := {
	"santa_c1_sheet": preload("res://assets/santa_c1_sheet.png"),
	"santa_c2_sheet": preload("res://assets/santa_c2_sheet.png"),
	"santa_c3_sheet": preload("res://assets/santa_c3_sheet.png"),
	"santa_c4_sheet": preload("res://assets/santa_c4_sheet.png"),
	"santa_fly": preload("res://assets/santa_fly.png"),
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

const ITEM_TEX := {
	"brine": "item_brine", "snack": "item_snack", "wide": "item_wide",
	"high": "item_high", "slow": "item_slow", "coal": "item_coal",
	"bottle": "item_bottle",
}

## kind -> [подпись, цвет]
const ITEM_POP := {
	"brine": ["+1 HP", Ink.GREEN],
	"wide": ["шире", Ink.BLUE],
	"high": ["выше", Ink.BLUE],
	"slow": ["медленнее", Ink.BLUE],
	"snack": ["закуска ×2", Ink.BLUE],
	"coal": ["уголь", Ink.ORANGE],
	"bottle": ["по кругу!", Ink.ORANGE],
}


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


var sim := Sim.new()
var active := false                ## идёт забег (в том числе на паузе)

var _puffs: Array[Puff] = []
var _pops: Array[Pop] = []
var _flakes: Array[Flake] = []
var _squash := 0.0
var _shake := 0.0
var _flash := 0.0
var _time := 0.0                   ## своё время для анимаций фона и спрайтов

@onready var _hud: Hud = %Hud

var _glow: GradientTexture2D
var _vignette: GradientTexture2D


func _ready() -> void:
	_build_textures()
	for i in 70:
		var f := Flake.new()
		f.pos = Vector2(randf() * CFG.ARENA_W, randf() * CFG.ARENA_H)
		f.r = randf_range(0.8, 2.4)
		f.v = randf_range(12.0, 40.0)
		f.d = randf_range(-14.0, 14.0)
		f.phase = randf() * TAU
		_flakes.append(f)

	sim.bounced.connect(_on_bounced)
	sim.sobered.connect(_on_sobered)
	sim.fell.connect(_on_fell)
	sim.item_applied.connect(_on_item_applied)
	sim.damaged.connect(_on_damaged)
	sim.level_cleared.connect(_on_level_cleared)
	sim.finished.connect(_on_finished)
	_hud.sim = sim


func start_run(diff_key: String) -> void:
	sim.start(diff_key)
	active = true
	_puffs.clear()
	_pops.clear()
	_squash = 0.0
	_shake = 0.0
	_flash = 0.0
	_hud.reset()
	_hud.visible = true


func resume_endless() -> void:
	sim.continue_endless()
	_hud.show_banner(sim.level)


## Нужно режиму скриншотов: бот отматывает минуту симуляции за один кадр, и все
## его частицы с цифрами оказываются на экране разом.
func clear_effects() -> void:
	_puffs.clear()
	_pops.clear()
	_shake = 0.0
	_flash = 0.0


func stop_run() -> void:
	active = false
	sim.running = false
	_hud.visible = false


func _process(delta: float) -> void:
	_time += delta
	for f in _flakes:
		f.pos.y += f.v * delta
		f.pos.x += sin(_time + f.phase) * f.d * delta
		if f.pos.y > CFG.ARENA_H:
			f.pos.y = -4.0
			f.pos.x = randf() * CFG.ARENA_W

	for i in range(_puffs.size() - 1, -1, -1):
		var p := _puffs[i]
		p.life -= delta
		if p.life <= 0.0:
			_puffs.remove_at(i)
			continue
		p.vel.y += 420.0 * delta
		p.pos += p.vel * delta

	for i in range(_pops.size() - 1, -1, -1):
		var p := _pops[i]
		p.life -= delta
		p.pos.y -= 34.0 * delta
		if p.life <= 0.0:
			_pops.remove_at(i)

	_squash = maxf(0.0, _squash - delta * 6.0)
	_shake = maxf(0.0, _shake - delta)
	_flash = maxf(0.0, _flash - delta * 1.6)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not active or not sim.running:
		return
	sim.aim_x = get_local_mouse_position().x
	sim.step(delta)


# =========================================================== отрисовка ====

func _draw() -> void:
	var off := Vector2.ZERO
	if _shake > 0.0 and Profile.screen_shake:
		var k := _shake * 14.0
		off = Vector2(randf_range(-k, k), randf_range(-k, k))
	draw_set_transform(off)

	_draw_backdrop()
	if active:
		var g := sim.gravity_now()
		if Profile.landing_markers:
			_draw_markers(g)
		for it in sim.items:
			_draw_item(it)
		for s in sim.santas:
			_draw_santa(s, off)
		_draw_paddle(off)
		_draw_effects()

	draw_set_transform(Vector2.ZERO)

	if _flash > 0.0:
		draw_texture_rect(_vignette, Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), false,
				Color(1.0, 0.16, 0.16, _flash * 0.6))


func _draw_backdrop() -> void:
	draw_texture_rect(TEX["bg"], Rect2(0, 0, CFG.ARENA_W, CFG.ARENA_H), false)
	for f in _flakes:
		draw_circle(f.pos, f.r, Color(1, 1, 1, 0.35))
	draw_line(Vector2(0, CFG.ARENA_H - 1), Vector2(CFG.ARENA_W, CFG.ARENA_H - 1),
			Color("2a3550"), 2.0)


func _draw_markers(g: float) -> void:
	for s in sim.santas:
		if s.escaping:
			continue
		var p := sim.predict(s, g)
		if p == Vector2.INF:
			continue
		var a := clampf(1.15 - p.x / 2.4, 0.12, 0.9)
		var col := Sim.nose_color(s.sober)

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
			]), Color(Ink.GOLD, 0.9))


func _draw_santa(s: Sim.Santa, off: Vector2) -> void:
	var col := Sim.nose_color(s.sober)

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
		var sheet: Texture2D = TEX["santa_%s_sheet" % Sim.nose_tier(s.sober)]
		var cell := sheet.get_height()
		var f := int(_time * ANIM_FPS + s.anim_offset) % ANIM_FRAMES
		var h := CFG.SANTA_RADIUS * 3.4
		draw_texture_rect_region(sheet, Rect2(-h / 2.0, -h / 2.0, h, h),
				Rect2(f * cell, 0, cell, cell))
	draw_set_transform(off)


func _draw_paddle(off: Vector2) -> void:
	var half_w := sim.half_width_now()
	var w := half_w * 2.0
	draw_set_transform(Vector2(sim.paddle_x, CFG.PADDLE_Y) + off, 0.0,
			Vector2(1.0, 1.0 - _squash * 0.35))
	var h := w * PADDLE_ASPECT
	draw_texture_rect(TEX["paddle"], Rect2(-w / 2.0, -PADDLE_BAR * h, w, h), false)
	draw_set_transform(off)


func _draw_item(it: Sim.Item) -> void:
	var tex: Texture2D = TEX[ITEM_TEX[it.kind]]
	var h := CFG.ITEM_RADIUS * 2.4
	var w := h * tex.get_width() / float(tex.get_height())
	draw_texture_rect(tex, Rect2(it.x - w / 2.0, it.y - h / 2.0, w, h), false)


func _draw_effects() -> void:
	for p in _puffs:
		draw_circle(p.pos, p.r, Color(p.color, clampf(p.life * 1.6, 0.0, 1.0)))
	for p in _pops:
		Ink.text(self, p.pos, p.text, 17, Color(p.color, clampf(p.life * 1.3, 0.0, 1.0)),
				HORIZONTAL_ALIGNMENT_CENTER, true)


# ============================================================= события ====

func _on_bounced(s: Sim.Santa, sweet: bool) -> void:
	_squash = 1.0
	_add_puff(Vector2(s.x, Sim.PLANE + CFG.SANTA_RADIUS), 12 if sweet else 7,
			Color("ffe08a") if sweet else Color("dbe9ff"))
	Audio.play("hit", 0.8 + 0.16 * s.sober)         # икота: чем трезвее, тем выше тон


func _on_sobered(s: Sim.Santa, points: int) -> void:
	_add_pop(Vector2(s.x, s.y - 40.0), "+%d" % points, Ink.GREEN)
	_add_puff(Vector2(s.x, s.y), 16, Ink.GREEN)
	Audio.play("sober")


func _on_fell(x: float) -> void:
	_add_puff(Vector2(x, CFG.ARENA_H - 6.0), 14, Color("ff8080"))
	Audio.play("miss")


func _on_item_applied(kind: String, gained: bool, x: float) -> void:
	var at := Vector2(x, CFG.PADDLE_Y - 40.0)
	var entry: Array = ITEM_POP[kind]
	var label: String = entry[0]
	var color: Color = entry[1]
	if kind == "brine" and not gained:
		label = "и так хорошо"
		color = Ink.BLUE
	_add_pop(at, label, color)

	var bad := kind == "coal" or kind == "bottle"
	_add_puff(Vector2(x, CFG.PADDLE_Y), 18 if bad else 12, Ink.ORANGE if bad else Ink.BLUE)
	Audio.play("hazard" if bad else "bonus")


func _on_damaged(_hp_left: int) -> void:
	_shake = 0.35
	_flash = 0.5


func _on_level_cleared(level: int, healed: bool) -> void:
	_hud.show_banner(level + 1)
	if healed:
		_add_pop(Vector2(CFG.ARENA_W / 2.0, CFG.PADDLE_Y - 90.0), "+1 HP", Ink.GREEN)
	Audio.play("bonus", 1.25)


func _on_finished(_victory: bool) -> void:
	run_finished.emit(sim.stats())


func _add_pop(pos: Vector2, text: String, color: Color) -> void:
	var p := Pop.new()
	p.pos = pos
	p.text = text
	p.color = color
	p.life = 0.9
	_pops.append(p)


func _add_puff(pos: Vector2, n: int, color: Color) -> void:
	for i in n:
		var p := Puff.new()
		p.pos = pos
		p.vel = Vector2(randf_range(-140.0, 140.0), randf_range(-190.0, -40.0))
		p.life = randf_range(0.35, 0.8)
		p.r = randf_range(2.0, 5.0)
		p.color = color
		_puffs.append(p)


func _build_textures() -> void:
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
