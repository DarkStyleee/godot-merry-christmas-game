class_name Main
extends Node
## Корень игры: держит арену и экраны интерфейса, переключает их, ставит паузу.
##
## Разделение ответственности простое: Sim считает, Arena рисует, экраны просят
## («сигнал вверх»), а решает, что делать, только этот скрипт («вызов вниз»).
## Паузу держит движок: get_tree().paused, арена помечена PROCESS_MODE_PAUSABLE,
## а корень и слой интерфейса — PROCESS_MODE_ALWAYS, поэтому меню на паузе живо.

enum Screen { MENU, PLAY, PAUSE, SETTINGS, RESULTS }

const AUTOSAVE_EVERY := 5.0           ## секунд игрового времени между записями забега

@onready var _arena: Arena = %Arena
@onready var _menu: MainMenu = %MainMenu
@onready var _pause: PauseMenu = %PauseMenu
@onready var _settings: SettingsMenu = %SettingsMenu
@onready var _results: ResultsScreen = %Results

var _screen := Screen.MENU
var _settings_from := Screen.MENU
var _saved_at := 0.0                  ## время забега (Sim.t) последней записи


func _ready() -> void:
	# Песочницу поднимаем до окна и до всего остального: отладочный прогон не
	# должен ни писать в профиль, ни разворачиваться на весь экран, если игрок
	# держит там полноэкранный режим.
	var args := OS.get_cmdline_user_args()
	Profile.sandbox = args.has("--check") or not _arg(args, "--shot").is_empty()
	Profile.apply_window()
	_menu.show_root()

	_menu.start_requested.connect(start_run)
	_menu.continue_requested.connect(continue_saved)
	_menu.settings_requested.connect(open_settings)
	_menu.quit_requested.connect(_quit)

	_pause.resume_requested.connect(_resume)
	_pause.settings_requested.connect(open_settings)
	_pause.menu_requested.connect(_to_menu)
	_pause.quit_requested.connect(_quit)

	_settings.closed.connect(_close_settings)

	_results.again_requested.connect(_restart)
	_results.continue_requested.connect(_continue_endless)
	_results.menu_requested.connect(_to_menu)

	_arena.run_finished.connect(_on_run_finished)
	# Отложенно: сигнал приходит посреди шага, когда новый уровень ещё не
	# начался, а к концу кадра забег снова целый.
	_arena.sim.level_cleared.connect(func(_level: int, _healed: bool) -> void:
			_save_run.call_deferred())

	_set_screen(Screen.MENU)
	_handle_cmdline()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fullscreen"):
		Profile.toggle_fullscreen()
	elif event.is_action_pressed(&"mute"):
		Audio.toggle_mute()
	elif event.is_action_pressed(&"restart") and _screen == Screen.RESULTS:
		_restart()
	elif event.is_action_pressed(&"ui_cancel"):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_autosave()


## Свернули окно или ушли из него (Alt+Tab, Win, клик мимо) — пауза: иначе
## забег без игрока идёт дальше и может проиграться сам. Обратно с паузы
## снимает только игрок.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_before_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _screen == Screen.PLAY:
		_pause_run()


func _before_quit() -> void:
	_save_run()
	Profile.save()
	Audio.stop_music()


## Забег пишется на диск при каждой остановке: пауза, выход в меню, закрытие
## окна, победа — и на каждом взятом уровне. Стирается, когда забег проигран
## или начат новый.
func _save_run() -> void:
	if _arena.active and _arena.sim.can_continue():
		Profile.save_run(_arena.sim.to_dict())
		_saved_at = _arena.sim.t


## А посреди игры — раз в AUTOSAVE_EVERY секунд её времени: выключение Windows
## Godot 4.7 не ловит (WM_ENDSESSION не обрабатывается, закрытия окна не будет),
## и снятый процесс тоже никого не спрашивает.
func _autosave() -> void:
	if _screen == Screen.PLAY and _arena.sim.t - _saved_at >= AUTOSAVE_EVERY:
		_save_run()


# ============================================================== экраны ====

func _set_screen(next: Screen) -> void:
	_screen = next
	_menu.visible = next == Screen.MENU
	_pause.visible = next == Screen.PAUSE
	_settings.visible = next == Screen.SETTINGS
	_results.visible = next == Screen.RESULTS
	# На паузе замирает и арена, и снег за меню — но только если пауза настоящая.
	# Настройки из главного меню игру не останавливают: останавливать нечего.
	get_tree().paused = (next == Screen.PAUSE
			or (next == Screen.SETTINGS and _settings_from == Screen.PAUSE))
	Input.mouse_mode = (Input.MOUSE_MODE_HIDDEN if next == Screen.PLAY
			else Input.MOUSE_MODE_VISIBLE)


func current_screen() -> Screen:
	return _screen


## Esc и кнопка «назад» — один и тот же путь.
func cancel() -> void:
	match _screen:
		Screen.PLAY: _pause_run()
		Screen.PAUSE: _resume()
		Screen.SETTINGS: _close_settings()
		Screen.RESULTS: _to_menu()
		Screen.MENU: _menu.back()


func start_run(mode_key: String, diff_key: String) -> void:
	_abandon_saved()
	_arena.start_run(mode_key, diff_key)
	_saved_at = _arena.sim.t
	_set_screen(Screen.PLAY)


## Новый забег заканчивает сохранённый, и тот уходит в рекорды как доигранный:
## счёт заработан честно, бросить забег не значит потерять рекорд. Снимок,
## который не поднимается, засчитать нечем — он просто стирается.
func _abandon_saved() -> void:
	var saved := Sim.from_dict(Profile.load_run())
	if saved != null:
		Profile.submit_run(saved.stats())
	Profile.clear_run()


## Сохранённый забег открывается на паузе: игрок сначала видит поле, потом
## жмёт «Продолжить» — а не получает падающего Деда Мороза в первую секунду.
func continue_saved() -> void:
	if not _arena.restore_run(Profile.load_run()):
		Profile.clear_run()
		_menu.show_root()
		return
	# Итоги победы игрок уже видел — выигранный забег сразу идёт дальше.
	if _arena.sim.outcome == Sim.Outcome.VICTORY:
		_arena.resume_endless()
	_pause_run()


func open_settings() -> void:
	_settings_from = _screen
	_set_screen(Screen.SETTINGS)


func _restart() -> void:
	start_run(_arena.sim.mode, _arena.sim.diff)


func _continue_endless() -> void:
	_arena.resume_endless()
	_set_screen(Screen.PLAY)


func _pause_run() -> void:
	_save_run()
	_pause.show_run(_arena.sim)
	_set_screen(Screen.PAUSE)


func _resume() -> void:
	_set_screen(Screen.PLAY)


func _close_settings() -> void:
	_set_screen(_settings_from)


func _to_menu() -> void:
	_save_run()
	_arena.stop_run()
	_set_screen(Screen.MENU)


func _quit() -> void:
	_before_quit()
	get_tree().quit()


## Выигранный забег остаётся сохранённым: игру без конца можно начать и потом,
## из меню, а не только с экрана итогов. Проигранный продолжать нечего.
func _on_run_finished(stats: Dictionary) -> void:
	if stats["victory"]:
		_save_run()
	else:
		Profile.clear_run()
	var is_record := Profile.submit_run(stats)
	_results.show_stats(stats, is_record)
	_set_screen(Screen.RESULTS)


# ========================================================= отладка ====

## Режимы для сборки и разработки, в обычной игре не участвуют:
##   godot --headless -- --check              формулы, кривые уровней, бот
##   godot -- --shot out.png --screen menu|mode|difficulty|settings|play|pause|continue|confirm|over|win
##                           [--mode santa|ball] [--diff normal] [--ff 45] [--fx]
func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()

	if args.has("--check"):
		SelfCheck.run_all(args.has("--curve"))
		_check_flow()
		get_tree().quit()
		return

	var shot := _arg(args, "--shot")
	if shot.is_empty():
		return

	Profile.muted = true
	var diff := _arg(args, "--diff")
	if not CFG.DIFFICULTY.has(diff):
		diff = "normal"
	var mode := _arg(args, "--mode")
	if not CFG.MODES.has(mode):
		mode = "santa"
	var ff := _arg(args, "--ff")
	var seconds := float(ff) if ff.is_valid_float() else 30.0
	var fx := args.has("--fx")

	match _arg(args, "--screen"):
		"mode":
			_menu.show_modes()
		"difficulty":
			_menu.show_difficulty(mode)
		"settings":
			open_settings()
		"play":
			_fast_forward(mode, diff, seconds, fx)
		"pause":
			_fast_forward(mode, diff, seconds, fx)
			_pause_run()
		"continue":
			_fast_forward(mode, diff, seconds, fx)
			_to_menu()
		"confirm":
			_fast_forward(mode, diff, seconds, fx)
			_to_menu()
			_menu.show_difficulty(mode)
			_menu.pick_difficulty(diff)
		"over":
			_fast_forward(mode, diff, seconds, fx)
			while _arena.sim.running:
				_arena.sim.grace_until = -1.0
				_arena.sim.lose_hp()
		"win":
			_fast_forward(mode, diff, seconds, fx)
			var stats := _arena.sim.stats()
			stats["level"] = CFG.LEVEL_MAX
			stats["victory"] = true
			_arena.stop_run()
			_results.show_stats(stats, true)
			_set_screen(Screen.RESULTS)
		_:
			pass

	await _shoot(shot)


## Отматывает забег ботом до нужного места. Частицы и цифры за отмотанную минуту
## копятся все разом, поэтому по умолчанию они стираются. С --fx бот доигрывает
## ещё полсекунды после очистки: тогда в кадр попадают только свежие эффекты, а
## иначе их вообще не снять.
func _fast_forward(mode: String, diff: String, seconds: float, fx: bool) -> void:
	start_run(mode, diff)
	SelfCheck.play(_arena.sim, seconds)
	_arena.clear_effects()
	if fx:
		SelfCheck.play(_arena.sim, 0.5)


## Поток экранов целиком, тем же путём, каким по ним ходит игрок: Esc из забега
## в паузу, из паузы в настройки и обратно, смерть — итоги — меню. Ломается это
## тихо (кнопка ведёт не туда, пауза не останавливает мир), поэтому проверяется
## машинно, а не глазами.
func _check_flow() -> void:
	var tree := get_tree()
	assert(_screen == Screen.MENU, "старт не с меню")
	assert(not tree.paused)
	assert(get_viewport().gui_get_focus_owner() != null,
			"при запуске ни одна кнопка меню не в фокусе: Enter ничего не делает")

	start_run("santa", "normal")
	assert(_screen == Screen.PLAY)
	assert(_arena.active and _arena.sim.running and _arena.sim.level == 1)
	assert(not tree.paused, "забег начался на паузе")

	cancel()
	assert(_screen == Screen.PAUSE)
	assert(tree.paused, "пауза не останавливает мир")

	open_settings()
	assert(_screen == Screen.SETTINGS)
	assert(tree.paused, "настройки из паузы сняли паузу")

	cancel()
	assert(_screen == Screen.PAUSE, "из настроек не вернулись в паузу")

	cancel()
	assert(_screen == Screen.PLAY)
	assert(not tree.paused, "мир не отмёрз после паузы")

	# уровень берётся квотой, а не временем
	var before := _arena.sim.level
	for i in _arena.sim.quota_need:
		SelfCheck.force_sober(_arena.sim)
	assert(_arena.sim.level == before + 1, "квота выполнена, а уровень не сменился")

	while _arena.sim.running:                     # добиваем забег
		_arena.sim.grace_until = -1.0
		_arena.sim.lose_hp()
	assert(_screen == Screen.RESULTS, "смерть не привела к итогам")
	assert(not Profile.record_for("normal").is_empty(), "забег не попал в таблицу")

	cancel()
	assert(_screen == Screen.MENU)
	assert(not _arena.active, "вышли в меню, а арена жива")
	assert(Profile.load_run().is_empty(), "законченный забег остался в сохранении")
	assert(not _menu.has_saved_run(), "меню предлагает продолжить законченный забег")

	# Недоигранный забег переживает выход в меню и поднимается тем же, каким был.
	start_run("santa", "normal")
	SelfCheck.play(_arena.sim, 20.0)
	assert(_arena.sim.running, "бот не дожил до сохранения")
	cancel()
	var saved := _arena.sim.to_dict()
	_to_menu()
	assert(_menu.has_saved_run(), "в меню нет «Продолжить»")
	continue_saved()
	assert(_screen == Screen.PAUSE and tree.paused, "сохранённый забег открылся не на паузе")
	assert(_arena.active and _arena.sim.running)
	assert(SelfCheck.same_snapshot(_arena.sim.to_dict(), saved),
			"после «Продолжить» забег не тот, что ушёл в меню")
	cancel()
	assert(_screen == Screen.PLAY and not tree.paused)
	while _arena.sim.running:
		_arena.sim.grace_until = -1.0
		_arena.sim.lose_hp()
	assert(Profile.load_run().is_empty(), "проигранный забег остался в сохранении")
	cancel()

	# Новый забег поверх сохранённого сохранение стирает.
	start_run("santa", "casual")
	cancel()
	_to_menu()
	assert(_menu.has_saved_run())
	start_run("santa", "normal")
	assert(Profile.load_run().is_empty(), "новый забег не стёр старое сохранение")
	_to_menu()
	Profile.clear_run()

	# Выигранный забег переживает экран итогов: из меню он продолжается игрой
	# без конца, на паузе, а не теряется вместе с итогами.
	start_run("santa", "normal")
	SelfCheck.force_victory(_arena.sim)
	assert(_screen == Screen.RESULTS, "победа не привела к итогам")
	assert(not Profile.load_run().is_empty(), "выигранный забег не сохранился")
	_to_menu()
	assert(_menu.has_saved_run(), "в меню нет «Продолжить» для выигранного забега")
	continue_saved()
	assert(_screen == Screen.PAUSE and tree.paused, "выигранный забег открылся не на паузе")
	assert(_arena.sim.running and _arena.sim.endless and _arena.sim.level == CFG.LEVEL_MAX + 1,
			"«Продолжить» после победы не повело в игру без конца")
	_to_menu()
	Profile.clear_run()

	# Посреди игры снимок пишется сам раз в пять секунд: выключенный компьютер
	# или снятый процесс теряют не больше. Отсчёт у каждого забега свой.
	start_run("santa", "normal")
	SelfCheck.play(_arena.sim, 3.0)
	_autosave()
	assert(Profile.load_run().is_empty(), "снимок пишется чаще, чем раз в пять секунд")
	SelfCheck.play(_arena.sim, 3.0)
	_autosave()
	assert(not Profile.load_run().is_empty(), "забег идёт шесть секунд, а снимка нет")
	start_run("santa", "normal")
	SelfCheck.play(_arena.sim, 6.0)
	_autosave()
	assert(not Profile.load_run().is_empty(), "отсчёт записи перенёсся из прошлого забега")
	_to_menu()
	Profile.clear_run()

	# Ушёл из окна — игра встаёт на паузу и пишет снимок; вернулся — пауза
	# остаётся, пока игрок сам не продолжит. Уведомление идёт тем же путём, что
	# от движка: от корня дерева.
	start_run("santa", "normal")
	SelfCheck.play(_arena.sim, 1.0)
	tree.root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(_screen == Screen.PAUSE and tree.paused, "потеря фокуса не поставила паузу")
	assert(SelfCheck.same_snapshot(Profile.load_run(), _arena.sim.to_dict()),
			"потеря фокуса не записала снимок")
	tree.root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(_screen == Screen.PAUSE and tree.paused, "возврат в окно сам снял паузу")
	_to_menu()
	Profile.clear_run()

	# Новый забег засчитывает брошенный в рекорды: счёт заработан, и бросить
	# забег не значит потерять рекорд. Нечитаемый снимок засчитать нечем.
	start_run("santa", "casual")
	SelfCheck.play(_arena.sim, 2.0)
	_arena.sim.score = 987_654_321
	_to_menu()
	start_run("santa", "normal")
	assert(Profile.best_score(CFG.record_key("santa", "casual")) == 987_654_321,
			"брошенный забег не попал в рекорды")
	_to_menu()
	Profile.save_run({"version": 999, "mode": "santa", "diff": "hardcore", "score": 5, "level": 3})
	start_run("santa", "normal")
	assert(Profile.record_for(CFG.record_key("santa", "hardcore")).is_empty(),
			"нечитаемый снимок попал в рекорды")
	_to_menu()
	Profile.clear_run()

	# При сохранённом забеге выбор сложности сперва спрашивает: новый забег не
	# начинается и старый не стирается, пока игрок не подтвердит. Esc — отмена.
	start_run("santa", "casual")
	_to_menu()
	_menu.show_difficulty("santa")
	_menu.pick_difficulty("normal")
	assert(_screen == Screen.MENU and _menu.is_confirming(), "новый забег начался без вопроса")
	assert(not Profile.load_run().is_empty(), "сохранённый забег стёрт до подтверждения")
	cancel()
	assert(_screen == Screen.MENU and not _menu.is_confirming(), "Esc не отменил вопрос")
	_menu.pick_difficulty("normal")
	_menu.confirm_new()
	assert(_screen == Screen.PLAY and _arena.sim.diff == "normal", "подтверждение не начало забег")
	_to_menu()
	Profile.clear_run()
	_menu.show_root()
	_menu.show_difficulty("santa")
	_menu.pick_difficulty("normal")
	assert(_screen == Screen.PLAY, "без сохранённого забега выбор сложности не начал забег")
	_to_menu()
	Profile.clear_run()

	# Второй режим доходит до арены своим ключом рекорда и своей ареной с шаром.
	start_run("ball", "normal")
	assert(_arena.sim.mode == "ball")
	while _arena.sim.running:
		_arena.sim.grace_until = -1.0
		_arena.sim.lose_hp()
	assert(Profile.records.has("normal") and Profile.records.has("ball:normal"),
			"режимы пишут рекорд в одну строку")
	cancel()
	print("CHECK flow ok")


func _arg(args: PackedStringArray, name: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s %s" % [path, "ok" if err == OK else error_string(err)])
	Audio.stop_music()
	get_tree().quit()
