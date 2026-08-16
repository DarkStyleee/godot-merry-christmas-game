class_name ResultsScreen
extends Control
## Итоги забега — общий экран для поражения и победы: меняются заголовок,
## подпись и наличие кнопки «Продолжить». Строки статистики одни и те же,
## чтобы забеги можно было сравнивать глазами.

signal again_requested
signal continue_requested
signal menu_requested

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _record_line: Label = %RecordLine
@onready var _stats: GridContainer = %Stats
@onready var _continue_btn: Button = %ContinueBtn
@onready var _again_btn: Button = %AgainBtn
@onready var _menu_btn: Button = %MenuBtn


func _ready() -> void:
	_continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	_again_btn.pressed.connect(func() -> void: again_requested.emit())
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	visibility_changed.connect(_on_visibility_changed)


func show_stats(stats: Dictionary, is_record: bool) -> void:
	var victory: bool = stats["victory"]
	var label: String = CFG.preset(stats["diff"])["label"]

	_title.text = "СТО УРОВНЕЙ" if victory else "ВСЕ УПАЛИ"
	_title.add_theme_color_override("font_color", Ink.GOLD if victory else Ink.RED)
	_subtitle.text = ("Ночь выстояна до последнего уровня. Дальше — только счёт." if victory
			else "Остановились на уровне %d из %d" % [stats["level"], CFG.LEVEL_MAX])

	var best := Profile.best_score(stats["diff"])
	if is_record:
		_record_line.text = "НОВЫЙ РЕКОРД"
		_record_line.add_theme_color_override("font_color", Ink.GREEN)
	elif best > 0:
		_record_line.text = "рекорд на «%s» — %d" % [label, best]
		_record_line.add_theme_color_override("font_color", Ink.GOLD)
	else:
		_record_line.text = ""

	_continue_btn.visible = victory
	_fill(stats)


func _fill(stats: Dictionary) -> void:
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()

	var bounces: int = stats["bounces"]
	var sweet_share := 0 if bounces == 0 else roundi(100.0 * float(stats["sweet_hits"]) / bounces)
	_row("сложность", str(CFG.preset(stats["diff"])["label"]), Ink.DIM)
	_row("счёт", str(stats["score"]), Ink.GOLD)
	_row("уровень", "%d из %d" % [stats["level"], CFG.LEVEL_MAX], Ink.TEXT)
	_row("отрезвлено", str(stats["sobered"]), Ink.TEXT)
	_row("ударов", "%d   ·   бантом %d%%" % [bounces, sweet_share], Ink.TEXT)
	_row("лучшая серия", str(stats["streak"]), Ink.TEXT)
	_row("упало мимо палки", str(stats["misses"]), Ink.DIM)
	_row("подобрано хорошего", "%d   ·   плохого %d" % [stats["items_good"], stats["items_bad"]], Ink.DIM)
	_row("продержались", Ink.mmss(stats["time"]), Ink.DIM)


func _row(name: String, value: String, color: Color) -> void:
	var l := Label.new()
	l.text = name
	l.custom_minimum_size = Vector2(210, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Ink.MUTED)
	_stats.add_child(l)

	var v := Label.new()
	v.text = value
	v.custom_minimum_size = Vector2(210, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 15)
	v.add_theme_color_override("font_color", color)
	_stats.add_child(v)


func _on_visibility_changed() -> void:
	if not visible:
		return
	if _continue_btn.visible:
		_continue_btn.grab_focus()
	else:
		_again_btn.grab_focus()
