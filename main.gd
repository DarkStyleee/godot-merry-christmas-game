class_name Main
extends Node
## Корень игры: держит арену и экраны интерфейса, переключает их, ставит паузу.
##
## Разделение ответственности простое: Sim считает, Arena рисует, экраны просят
## («сигнал вверх»), а решает, что делать, только этот скрипт («вызов вниз»).
## Паузу держит движок: get_tree().paused, арена помечена PROCESS_MODE_PAUSABLE,
## а корень и слой интерфейса — PROCESS_MODE_ALWAYS, поэтому меню на паузе живо.

enum Screen { MENU, PLAY, PAUSE, SETTINGS, RESULTS }

@onready var _arena: Arena = %Arena
@onready var _menu: MainMenu = %MainMenu
@onready var _pause: PauseMenu = %PauseMenu
@onready var _settings: SettingsMenu = %SettingsMenu
@onready var _results: ResultsScreen = %Results

var _screen := Screen.MENU
var _settings_from := Screen.MENU


func _ready() -> void:
	# Песочницу поднимаем до окна и до всего остального: отладочный прогон не
	# должен ни писать в профиль, ни разворачиваться на весь экран, если игрок
	# держит там полноэкранный режим.
	var args := OS.get_cmdline_user_args()
	Profile.sandbox = args.has("--check") or not _arg(args, "--shot").is_empty()
	Profile.apply_window()

	_menu.start_requested.connect(start_run)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_before_quit()


func _before_quit() -> void:
	Profile.save()
	Audio.stop_music()


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
		Screen.MENU: _menu.show_root()


func start_run(diff_key: String) -> void:
	_arena.start_run(diff_key)
	_set_screen(Screen.PLAY)


func open_settings() -> void:
	_settings_from = _screen
	_set_screen(Screen.SETTINGS)


func _restart() -> void:
	start_run(_arena.sim.diff)


func _continue_endless() -> void:
	_arena.resume_endless()
	_set_screen(Screen.PLAY)


func _pause_run() -> void:
	_pause.show_run(_arena.sim)
	_set_screen(Screen.PAUSE)


func _resume() -> void:
	_set_screen(Screen.PLAY)


func _close_settings() -> void:
	_set_screen(_settings_from)


func _to_menu() -> void:
	_arena.stop_run()
	_set_screen(Screen.MENU)


func _quit() -> void:
	_before_quit()
	get_tree().quit()


func _on_run_finished(stats: Dictionary) -> void:
	var is_record := Profile.submit_run(stats)
	_results.show_stats(stats, is_record)
	_set_screen(Screen.RESULTS)


# ========================================================= отладка ====

## Режимы для сборки и разработки, в обычной игре не участвуют:
##   godot --headless -- --check              формулы, кривые уровней, бот
##   godot -- --shot out.png --screen menu|difficulty|settings|play|pause|over|win
##                           [--diff normal] [--ff 45]
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
	var ff := _arg(args, "--ff")
	var seconds := float(ff) if ff.is_valid_float() else 30.0

	match _arg(args, "--screen"):
		"difficulty":
			_menu.show_difficulty()
		"settings":
			open_settings()
		"play":
			start_run(diff)
			SelfCheck.play(_arena.sim, seconds)
			_arena.clear_effects()
		"pause":
			start_run(diff)
			SelfCheck.play(_arena.sim, seconds)
			_arena.clear_effects()
			_pause_run()
		"over":
			start_run(diff)
			SelfCheck.play(_arena.sim, seconds)
			_arena.clear_effects()
			while _arena.sim.running:
				_arena.sim.grace_until = -1.0
				_arena.sim.lose_hp()
		"win":
			start_run(diff)
			SelfCheck.play(_arena.sim, seconds)
			_arena.clear_effects()
			var stats := _arena.sim.stats()
			stats["level"] = CFG.LEVEL_MAX
			stats["victory"] = true
			_arena.stop_run()
			_results.show_stats(stats, true)
			_set_screen(Screen.RESULTS)
		_:
			pass

	await _shoot(shot)


## Поток экранов целиком, тем же путём, каким по ним ходит игрок: Esc из забега
## в паузу, из паузы в настройки и обратно, смерть — итоги — меню. Ломается это
## тихо (кнопка ведёт не туда, пауза не останавливает мир), поэтому проверяется
## машинно, а не глазами.
func _check_flow() -> void:
	var tree := get_tree()
	assert(_screen == Screen.MENU, "старт не с меню")
	assert(not tree.paused)

	start_run("normal")
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
