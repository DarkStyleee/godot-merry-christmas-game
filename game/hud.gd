class_name Hud
extends Node2D
## Показания забега поверх арены: счёт, множитель, рекорд, уровень с квотой,
## HP, активные бонусы и баннер взятого уровня.
##
## Тоже иммедиатная отрисовка, а не Control-ноды: HUD ничего не принимает от
## мыши и живёт в той же системе координат, что арена. Control-ноды нужны там,
## где есть фокус и клики, — это меню.

const BANNER_TIME := 2.0
const QUOTA_BAR := Vector2(230.0, 6.0)

var sim: Sim

var _record := 0
var _banner_level := 0
var _banner_life := 0.0


func reset() -> void:
	_record = Profile.best_score(CFG.record_key(sim.mode, sim.diff))
	_banner_level = 0
	_banner_life = 0.0


func show_banner(level: int) -> void:
	_banner_level = level
	_banner_life = BANNER_TIME


func _process(delta: float) -> void:
	if _banner_life > 0.0:
		_banner_life -= delta
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	_draw_score()
	_draw_level()
	_draw_hp()
	_draw_buffs()
	# На паузе баннер не рисуем: время для него стоит, и он висел бы над меню
	# паузы всё время, пока игрок думает.
	if _banner_life > 0.0 and not get_tree().paused:
		_draw_banner()


func _draw_score() -> void:
	Ink.text(self, Vector2(16, 14), str(sim.score), 20, Ink.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true, true)
	Ink.text(self, Vector2(16, 40), "×%d   серия %d" % [sim.mult, sim.streak], 15,
			Ink.GOLD if sim.mult > 1 else Ink.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true, true)

	if _record <= 0:
		Ink.text(self, Vector2(16, 60), "рекорда ещё нет", 13, Ink.FAINT,
				HORIZONTAL_ALIGNMENT_LEFT, false, true)
	elif sim.score > _record:
		Ink.text(self, Vector2(16, 60), "рекорд побит", 13, Ink.GREEN,
				HORIZONTAL_ALIGNMENT_LEFT, true, true)
	else:
		Ink.text(self, Vector2(16, 60), "рекорд %d" % _record, 13, Ink.FAINT,
				HORIZONTAL_ALIGNMENT_LEFT, false, true)


func _draw_level() -> void:
	var cx := CFG.ARENA_W / 2.0
	var title := "УРОВЕНЬ %d" % sim.level
	if sim.endless:
		title += " · без конца"
	Ink.text(self, Vector2(cx, 12), title, 16, Ink.TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, true)

	var bar := Rect2(cx - QUOTA_BAR.x / 2.0, 36.0, QUOTA_BAR.x, QUOTA_BAR.y)
	draw_rect(bar, Color(1, 1, 1, 0.10))
	var k := clampf(float(sim.quota_done) / maxf(1.0, float(sim.quota_need)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(Ink.GREEN, 0.85))

	var airborne := 0
	for s in sim.santas:
		if not s.escaping:
			airborne += 1
	Ink.text(self, Vector2(cx, 48), "отрезвлено %d / %d   ·   в воздухе %d   ·   %s" %
			[sim.quota_done, sim.quota_need, airborne, Ink.mmss(sim.t)], 13, Ink.MUTED,
			HORIZONTAL_ALIGNMENT_CENTER, false, true)


func _draw_hp() -> void:
	for i in int(sim.preset["hp_max"]):              # HP шапками
		var x := CFG.ARENA_W - 26.0 - i * 26.0
		var a := 1.0 if i < sim.hp else 0.2
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 9.0, 26.0), Vector2(x + 9.0, 26.0), Vector2(x, 10.0),
		]), Color(Ink.RED, a))
		draw_rect(Rect2(x - 10.0, 26.0, 20.0, 5.0), Color(1, 1, 1, a))


func _draw_buffs() -> void:
	var y := 86.0
	# Шар пропал не навсегда — без этой строки пауза перед его возвращением
	# читается как поломка.
	if sim.mode == "ball" and sim.ball == null:
		Ink.text(self, Vector2(16, y), "шар вернётся через %.1fc" % maxf(sim.ball_wait, 0.0), 13,
				Color(Ink.BLUE, 0.9), HORIZONTAL_ALIGNMENT_LEFT, true, true)
		y += 18.0
	y = _badge("шире", Color("57d07a"), sim.wide_until, y)
	y = _badge("выше", Color("5aa8f2"), sim.high_until, y)
	y = _badge("медленнее", Color("a97cf2"), sim.slow_until, y)
	if sim.snack > 0:
		Ink.text(self, Vector2(16, y), "закуска ×2 · осталось %d" % sim.snack, 13,
				Color("f2d98e", 0.85), HORIZONTAL_ALIGNMENT_LEFT, true, true)
		y += 18.0
	if Profile.muted:
		Ink.text(self, Vector2(CFG.ARENA_W - 16.0, CFG.ARENA_H - 26.0), "звук выкл", 14,
				Ink.FAINT, HORIZONTAL_ALIGNMENT_RIGHT, false, true)


func _badge(label: String, color: Color, until: float, y: float) -> float:
	var left := until - sim.t
	if left <= 0.0:
		return y
	Ink.text(self, Vector2(16, y), "%s %.1fc" % [label, left], 13, Color(color, 0.85),
			HORIZONTAL_ALIGNMENT_LEFT, true, true)
	return y + 18.0


func _draw_banner() -> void:
	var a := clampf(_banner_life / (BANNER_TIME * 0.5), 0.0, 1.0)
	var cx := CFG.ARENA_W / 2.0
	var rise := (BANNER_TIME - _banner_life) * 14.0
	Ink.text(self, Vector2(cx, 190.0 - rise), "УРОВЕНЬ %d" % _banner_level, 46,
			Color(Ink.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, true)
	Ink.text(self, Vector2(cx, 220.0 - rise), "отрезвить %d" % sim.quota_need, 18,
			Color(Ink.DIM, a), HORIZONTAL_ALIGNMENT_CENTER)
