class_name SelfCheck
extends RefCounted
## Самопроверка: формулы отскока, кривые уровней и живой прогон ботом.
##
##   godot --headless --path . -- --check [--curve]
##
## Этим же прогоном начинается сборка (tools/build.ps1): падает проверка —
## exe не собирается. Проверка гоняет ту же Sim, что и игра, без единой ноды.

## Простейший бот: целится в тело, которое приземлится первым. Живого игрока не
## изображает (для этого есть tools/sim.js с моделью моторики) — его дело
## показать, что забег вообще живёт и физика не уходит в NaN.
static func play(sim: Sim, seconds: float) -> void:
	var dt := 1.0 / 120.0
	for i in int(seconds / dt):
		if not sim.running:
			return
		aim(sim)
		sim.step(dt)
		assert(is_finite(sim.paddle_x) and is_finite(sim.t), "физика ушла в NaN")


static func aim(sim: Sim) -> void:
	var g := sim.gravity_now()
	var best_t := INF
	for s in sim.santas:
		if s.escaping:
			continue
		var p := sim.predict(s, g)
		if p != Vector2.INF and p.x < best_t:
			best_t = p.x
			sim.aim_x = p.y


## Проверка потока экранов живёт в main.gd: она про его машину состояний, и
## ссылка отсюда на Main замкнула бы файлы в кольцо, которое GDScript не разбирает.
static func run_all(with_curve := false) -> void:
	check_math()
	check_levels()
	for key: String in CFG.DIFF_ORDER:
		if with_curve:
			print(curve_table(key))
		print(bot_report(key, 180.0))


static func bot_report(diff_key: String, seconds: float) -> String:
	var sim := Sim.new()
	sim.start(diff_key)
	play(sim, seconds)
	return "CHECK %-9s t=%5.1f level=%-3d score=%-6d hp=%d sobered=%-3d misses=%d" % [
		diff_key, sim.t, sim.level, sim.score, sim.hp, sim.sobered_total, sim.misses,
	]


static func curve_table(diff_key: String) -> String:
	var p := CFG.preset(diff_key)
	var out := "CURVE %s   уровень:  g  /  спавн  /  тел  /  квота  /  цикл\n" % diff_key
	for level in [1, 3, 5, 10, 20, 40, 70, CFG.LEVEL_MAX]:
		var g := CFG.gravity_for(p, level)
		out += "  %3d   %6.0f   %5.2fс   %2d   %2d   %.2fс\n" % [
			level, g, CFG.spawn_interval_for(p, level), CFG.field_cap_for(p, level),
			CFG.quota_for(p, level), cycle_time(g),
		]
	return out


## Время полного цикла отскока от центра палки — сколько у игрока есть на одно
## тело. Ниже ~1.3 с человек перестаёт успевать (BALANCE.md §1.1).
static func cycle_time(g: float) -> float:
	return 2.0 * sqrt(2.0 * CFG.BOUNCE[0][2] * CFG.ARENA_H / g)


static func check_math() -> void:
	var sim := Sim.new()
	sim.start("normal")

	assert(is_equal_approx(sim.bounce_height(0.0), 0.80))
	assert(is_equal_approx(sim.bounce_height(0.15), 0.80))
	assert(is_equal_approx(sim.bounce_height(1.0), 0.25))
	assert(is_equal_approx(sim.bounce_height(0.375), 0.60))      # середина второго сегмента

	assert(is_equal_approx(sim.fold_x(450.0), 450.0))            # внутри арены — без изменений
	assert(is_equal_approx(sim.fold_x(900.0), 856.0))            # отражение от правой стены
	assert(is_equal_approx(sim.fold_x(-22.0), 66.0))             # отражение от левой
	assert(sim.fold_x(5000.0) >= CFG.SANTA_RADIUS
			and sim.fold_x(5000.0) <= CFG.ARENA_W - CFG.SANTA_RADIUS)

	# свободное падение с нулевой скоростью: t = sqrt(2h/g)
	var s := Sim.Santa.new()
	s.x = 300.0
	s.y = 0.0
	var p := sim.predict(s, 1000.0)
	assert(is_equal_approx(p.x, sqrt(2.0 * Sim.PLANE / 1000.0)))

	# тело под плоскостью, подпрыгнет на 5 px и не дотянется — приземления нет
	s.y = Sim.PLANE + 50.0
	s.vy = -100.0
	assert(sim.predict(s, 1000.0) == Vector2.INF)

	# оттуда же, но с запасом скорости: вернётся и пересечёт плоскость сверху
	s.vy = -600.0
	assert(is_equal_approx(sim.predict(s, 1000.0).x, (600.0 + sqrt(260000.0)) / 1000.0))

	assert(Ink.mmss(59.7) == "1:00")                             # не «0:60»
	assert(Ink.mmss(125.0) == "2:05")


## Отрезвляет одно тело руками — быстрее, чем ждать, пока это сделает бот.
static func force_sober(sim: Sim) -> void:
	var s := Sim.Santa.new()
	s.x = sim.paddle_x
	s.y = Sim.PLANE
	s.sober = CFG.SOBER_THRESHOLD - CFG.SOBER_GAIN_SWEET
	sim.santas.append(s)
	sim._bounce(s, sim.gravity_now(), sim.half_width_now())


## Кривые уровней: каждый следующий уровень обязан быть не легче предыдущего, а
## сотый — всё ещё отбиваемым руками. Обе стороны легко сломать одной правкой
## пресета, поэтому они проверяются, а не остаются на честном слове.
static func check_levels() -> void:
	for key: String in CFG.DIFF_ORDER:
		var p := CFG.preset(key)
		var prev_g := 0.0
		var prev_spawn := INF
		var prev_field := 0
		var prev_quota := 0

		for level in range(1, CFG.LEVEL_MAX + 1):
			var g := CFG.gravity_for(p, level)
			var spawn := CFG.spawn_interval_for(p, level)
			var field := CFG.field_cap_for(p, level)
			var quota := CFG.quota_for(p, level)

			assert(g >= prev_g, "%s: гравитация упала на уровне %d" % [key, level])
			assert(spawn <= prev_spawn, "%s: спавн замедлился на уровне %d" % [key, level])
			assert(field >= prev_field, "%s: тел стало меньше на уровне %d" % [key, level])
			assert(quota >= prev_quota, "%s: квота упала на уровне %d" % [key, level])
			assert(field <= CFG.MAX_ON_FIELD, "%s: лимит тел выше потолка" % key)
			assert(quota >= 1, "%s: пустая квота на уровне %d" % [key, level])

			prev_g = g
			prev_spawn = spawn
			prev_field = field
			prev_quota = quota

		var first_g := CFG.gravity_for(p, 1)
		assert(prev_g > first_g * 1.5, "%s: сотый уровень почти не тяжелее первого" % key)
		assert(cycle_time(prev_g) > 1.3, "%s: на сотом уровне цикл короче реакции" % key)
		assert(prev_spawn > 0.5, "%s: спавн на сотом уровне быстрее падения" % key)
		assert(CFG.quota_for(p, 1) <= 3, "%s: первый уровень начинается с марафона" % key)
