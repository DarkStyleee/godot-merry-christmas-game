class_name SelfCheck
extends RefCounted
## Самопроверка: формулы отскока, кривые уровней и живой прогон ботом.
##
##   godot --headless --path . -- --check [--curve]
##
## Этим же прогоном начинается сборка (tools/build.ps1): падает проверка —
## exe не собирается. Проверка гоняет ту же Sim, что и игра, без единой ноды.

## Фора шару при выборе цели, с. Ронять его дороже, чем упустить Деда Мороза,
## поэтому бот идёт к нему, даже когда тело приземляется чуть раньше.
const BALL_BIAS := 0.25

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

	var pb := sim.predict_ball(g)
	if pb != Vector2.INF:
		best_t = pb.x - BALL_BIAS
		sim.aim_x = pb.y

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
	check_ball()
	check_save()
	check_one_ending()
	for key: String in CFG.DIFF_ORDER:
		if with_curve:
			print(curve_table(key))
		for mode_key: String in CFG.MODE_ORDER:
			print(bot_report(mode_key, key, 180.0))


static func bot_report(mode_key: String, diff_key: String, seconds: float) -> String:
	var sim := Sim.new()
	sim.start(mode_key, diff_key)
	play(sim, seconds)
	return "CHECK %-5s %-9s t=%5.1f level=%-3d score=%-6d hp=%d sobered=%-3d misses=%-3d balls=%d" % [
		mode_key, diff_key, sim.t, sim.level, sim.score, sim.hp, sim.sobered_total,
		sim.misses, sim.balls_lost,
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


## Режим «Новогодний шар» держится на двух правилах, и оба ломаются тихо:
## упавший Дед Мороз перестаёт быть бесплатным, а шар начинает проваливаться
## сквозь палку. Проверяем оба.
static func check_ball() -> void:
	var sim := Sim.new()
	sim.start("ball", "normal")
	var hp_before := sim.hp

	var s := Sim.Santa.new()
	s.x = 100.0
	s.y = CFG.ARENA_H + CFG.SANTA_RADIUS * 2.0
	sim.santas.append(s)
	sim.step(1.0 / 120.0)
	assert(sim.misses == 1, "упавшее тело не засчиталось")
	assert(sim.hp == hp_before, "в режиме шара упавший Дед Мороз отнял HP")

	# То же тело в основном режиме обязано стоить HP — иначе правило потерялось.
	var santa_sim := Sim.new()
	santa_sim.start("santa", "normal")
	var s2 := Sim.Santa.new()
	s2.x = 100.0
	s2.y = CFG.ARENA_H + CFG.SANTA_RADIUS * 2.0
	santa_sim.santas.append(s2)
	santa_sim.step(1.0 / 120.0)
	assert(santa_sim.hp == int(santa_sim.preset["hp_start"]) - 1,
			"в основном режиме упавший Дед Мороз перестал стоить HP")

	# Палка всегда точно под шаром: при таком ведении он не теряется ни разу.
	var perfect := Sim.new()
	perfect.start("ball", "casual")
	var dt := 1.0 / 120.0
	for i in int(120.0 / dt):
		if perfect.ball != null:
			perfect.aim_x = perfect.ball.x
		perfect.step(dt)
	assert(perfect.balls_lost == 0, "шар проваливается сквозь палку")
	assert(perfect.running, "идеальное ведение шара всё равно кончилось поражением")
	assert(perfect.ball != null, "шар не вернулся после падения")


## Сохранение ломается тихо: забыли поле в to_dict() — после «Продолжить» оно
## молча берётся из start(). Поэтому снимок гоняется через JSON туда и обратно
## и сравнивается целиком, в обоих режимах и посреди живого поля. Плюс то, что
## испорченный файл не поднимает забег, а не поднимает его наполовину.
static func check_save() -> void:
	for mode_key: String in CFG.MODE_ORDER:
		var sim := Sim.new()
		sim.start(mode_key, "normal")
		play(sim, 40.0)
		# Снимок нужен посреди живого поля, а бот в половине прогонов успевает его
		# очистить к сороковой секунде: доигрываем, пока кто-нибудь не появится.
		for i in 100:
			if not sim.santas.is_empty():
				break
			play(sim, 0.1)
		assert(sim.running, "%s: бот не дожил до снимка" % mode_key)
		var text := JSON.stringify(sim.to_dict(), "", false, true)

		var back := Sim.new()
		assert(back.restore(JSON.parse_string(text)), "%s: снимок не поднялся" % mode_key)
		assert(same_snapshot(sim.to_dict(), back.to_dict()),
				"%s: снимок поднялся не таким, каким был записан" % mode_key)
		assert(back.running and back.quota_need == sim.quota_need)
		assert(back.santas.size() == sim.santas.size() and not back.santas.is_empty(),
				"%s: поле потеряло тела (%d -> %d)" % [mode_key, sim.santas.size(), back.santas.size()])
		play(back, 1.0)                              # поднятый забег живёт дальше
		assert(back.t > sim.t, "%s: поднятый забег стоит" % mode_key)

	# Выигранный забег поднимается выигранным, а не живым на сотом уровне: иначе
	# «Продолжить» из меню потребовало бы взять сотый уровень ещё раз.
	var won := Sim.new()
	won.start("santa", "casual")
	force_victory(won)
	assert(won.outcome == Sim.Outcome.VICTORY, "сотый уровень не дал победы")
	var won_back := Sim.from_dict(JSON.parse_string(JSON.stringify(won.to_dict(), "", false, true)))
	assert(won_back != null, "выигранный забег не поднялся")
	assert(won_back.outcome == Sim.Outcome.VICTORY and not won_back.running
			and won_back.level == CFG.LEVEL_MAX, "выигранный забег поднялся не выигранным")
	assert(same_snapshot(won.to_dict(), won_back.to_dict()),
			"выигранный забег поднялся не таким, каким был записан")
	won_back.continue_endless()
	assert(won_back.running and won_back.endless and won_back.level == CFG.LEVEL_MAX + 1,
			"выигранный забег не продолжается игрой без конца")

	var good := Sim.new()
	good.start("santa", "normal")
	var snap := good.to_dict()
	var broken: Array[Dictionary] = [
		{}, {"version": 999}, {"mode": "chess"}, {"diff": "nightmare"},
		{"hp": 0}, {"level": 0}, {"level": CFG.LEVEL_MAX + 1},
		# победа бывает только на сотом уровне и только до игры без конца
		{"victory": true, "level": 50},
		{"victory": true, "level": CFG.LEVEL_MAX, "endless": true},
	]
	for patch in broken:
		var d: Dictionary = snap.duplicate(true) if not patch.is_empty() else {}
		d.merge(patch, true)
		var probe := Sim.new()
		probe.start("ball", "casual")
		assert(not probe.restore(d), "поднялся испорченный снимок %s" % patch)
		assert(probe.mode == "ball" and probe.diff == "casual",
				"отвергнутый снимок всё-таки переписал забег")

	# Обновление баланса может урезать запас шапок: забег из прошлой версии не
	# пропадает, а продолжается с тем запасом, что разрешён теперь.
	var more_hp := snap.duplicate(true)
	more_hp["hp"] = 99
	var trimmed := Sim.from_dict(more_hp)
	assert(trimmed != null and trimmed.hp == int(trimmed.preset["hp_max"]),
			"шапок больше нынешнего запаса — и забег не поднялся")

	# Мусор в полях не роняет загрузку, а зажимается.
	var junk := snap.duplicate(true)
	junk["score"] = "много"
	junk["t"] = INF
	junk["santas"] = [{"x": -5000.0, "vx": 1e9, "sober": 100}, "не тело"]
	junk["items"] = [{"kind": "bomb"}, {"kind": "brine", "x": 450.0}]
	junk["victory"] = "да"
	var probe := Sim.new()
	assert(probe.restore(junk), "мусор в полях сорвал загрузку")
	assert(probe.running, "строка в поле победы засчиталась победой")
	assert(probe.score == 0 and probe.t == 0.0)
	assert(probe.santas.size() == 1 and probe.santas[0].x == 0.0
			and probe.santas[0].vx == CFG.VX_MAX and probe.santas[0].sober == CFG.SOBER_THRESHOLD * 2)
	assert(probe.items.size() == 1 and probe.items[0].kind == "brine")


## Снимки равны поле в поле. Дробные — с допуском: JSON-парсер Godot теряет
## последний бит у семнадцатизначных чисел, и строки до цифры не сходятся.
static func same_snapshot(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key: Variant in a:
			if not (b as Dictionary).has(key) or not same_snapshot(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same_snapshot(a[i], b[i]):
				return false
		return true
	if a is float or b is float:
		return (a is float or a is int) and (b is float or b is int) and is_equal_approx(a, b)
	return typeof(a) == typeof(b) and a == b


static func check_math() -> void:
	var sim := Sim.new()
	sim.start("santa", "normal")

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
## Забег кончается первым же концом за шаг. Если в одном шаге взят сотый
## уровень и разбился последний, второй конец не случается: иначе итоги
## показываются дважды, а выигранный забег сохраняется без шапок или
## стирается как проигранный. Тела шаг обходит с конца списка.
static func check_one_ending() -> void:
	for victory_first: bool in [true, false]:
		var sim := Sim.new()
		sim.start("santa", "casual")
		sim.level = CFG.LEVEL_MAX
		sim.quota_need = CFG.quota_for(sim.preset, CFG.LEVEL_MAX)
		sim.quota_done = sim.quota_need - 1
		sim.hp = 1
		sim.next_santa = INF
		sim.aim_x = CFG.ARENA_W / 2.0

		var hit := Sim.Santa.new()                  # трезвеет и закрывает сотый уровень
		hit.x = sim.aim_x
		hit.y = Sim.PLANE - 0.5
		hit.vy = 200.0
		hit.sober = CFG.SOBER_THRESHOLD - CFG.SOBER_GAIN_SWEET
		var miss := Sim.Santa.new()                 # разбивается и забирает последнюю шапку
		miss.x = 60.0
		miss.y = CFG.ARENA_H + CFG.SANTA_RADIUS + 1.0
		miss.vy = 100.0
		sim.santas.append(miss if victory_first else hit)
		sim.santas.append(hit if victory_first else miss)

		var endings: Array[bool] = []
		sim.finished.connect(func(victory: bool) -> void: endings.append(victory))
		sim.step(1.0 / 120.0)
		var what := "победа, потом падение" if victory_first else "падение, потом победа"
		assert(endings.size() == 1 and endings[0] == victory_first,
				"%s: концов забега за шаг %s" % [what, endings])
		if victory_first:
			assert(sim.outcome == Sim.Outcome.VICTORY and sim.hp == 1,
					"%s: победу перебило падение после неё" % what)
		else:
			assert(sim.outcome == Sim.Outcome.DEFEAT and sim.quota_done == sim.quota_need - 1,
					"%s: проигранный забег после конца ещё и выиграл" % what)


## Переносит забег на сотый уровень и закрывает его квоту — то есть выигрывает.
static func force_victory(sim: Sim) -> void:
	sim.level = CFG.LEVEL_MAX
	sim.quota_need = CFG.quota_for(sim.preset, CFG.LEVEL_MAX)
	for i in sim.quota_need:
		force_sober(sim)


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
