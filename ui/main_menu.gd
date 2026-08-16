class_name MainMenu
extends Control
## Главное меню: корневой экран, выбор режима и выбор сложности на нём же.
##
## Карточки и таблица рекордов собираются кодом из CFG.MODE_ORDER и
## CFG.DIFF_ORDER — добавить режим или пресет в config.gd достаточно, меню
## подхватит.

signal start_requested(mode_key: String, diff_key: String)
signal settings_requested
signal quit_requested

const CARD_WIDTH := 236.0
const MODE_CARD_WIDTH := 300.0

@onready var _root_box: VBoxContainer = %RootBox
@onready var _mode_box: VBoxContainer = %ModeBox
@onready var _diff_box: VBoxContainer = %DiffBox
@onready var _mode_cards: HBoxContainer = %ModeCards
@onready var _cards: HBoxContainer = %Cards
@onready var _diff_title: Label = %DiffTitle
@onready var _records: GridContainer = %Records
@onready var _play_btn: Button = %PlayBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _quit_btn: Button = %QuitBtn
@onready var _mode_back_btn: Button = %ModeBackBtn
@onready var _back_btn: Button = %BackBtn
@onready var _version: Label = %Version

var _mode := "santa"                   ## режим, выбранный на предыдущем шаге
var _card_notes: Dictionary = {}       ## diff -> Label с рекордом на карточке


func _ready() -> void:
	_play_btn.pressed.connect(show_modes)
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())
	_quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	_mode_back_btn.pressed.connect(show_root)
	_back_btn.pressed.connect(show_modes)
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "1.0")
	_build_mode_cards()
	_build_cards()
	_refresh()                         # первый показ сигнала видимости не даёт
	visibility_changed.connect(_on_visibility_changed)


func show_root() -> void:
	_root_box.visible = true
	_mode_box.visible = false
	_diff_box.visible = false
	_play_btn.grab_focus()


func show_modes() -> void:
	_root_box.visible = false
	_mode_box.visible = true
	_diff_box.visible = false
	_focus_first(_mode_cards)


func show_difficulty(mode_key := "") -> void:
	if not mode_key.is_empty():
		_mode = mode_key
	_root_box.visible = false
	_mode_box.visible = false
	_diff_box.visible = true
	_diff_title.text = "ВЫБЕРИТЕ СЛОЖНОСТЬ   ·   %s" % str(CFG.mode(_mode)["label"]).to_upper()
	_refresh()                         # рекорды на карточках — уже этого режима
	_focus_first(_cards)


## Esc и кнопка «назад» — один и тот же путь на шаг назад.
func back() -> void:
	if _diff_box.visible:
		show_modes()
	else:
		show_root()


func _on_visibility_changed() -> void:
	if not visible:
		return
	_refresh()
	show_root()


func _focus_first(box: HBoxContainer) -> void:
	var first := box.get_child(0)
	if first != null and first.get_child_count() > 0:
		(first.get_child(0) as Button).grab_focus()


func _refresh() -> void:
	_build_records()
	for key: String in _card_notes:
		var rec := Profile.record_for(CFG.record_key(_mode, key))
		var note: Label = _card_notes[key]
		note.text = "%d HP   ·   %s" % [
			int(CFG.preset(key)["hp_start"]),
			"лучший уровень %d" % int(rec["best_level"]) if rec.has("best_level") else "ещё не играли",
		]


func _build_mode_cards() -> void:
	for key: String in CFG.MODE_ORDER:
		var info := CFG.mode(key)
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(MODE_CARD_WIDTH, 0)
		card.add_theme_constant_override("separation", 8)

		var btn := Button.new()
		btn.text = str(info["label"])
		btn.custom_minimum_size = Vector2(MODE_CARD_WIDTH, 64)
		btn.pressed.connect(show_difficulty.bind(key))
		card.add_child(btn)

		var hint := Label.new()
		hint.text = str(info["hint"])
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.custom_minimum_size = Vector2(MODE_CARD_WIDTH, 46)
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Ink.MUTED)
		card.add_child(hint)

		_mode_cards.add_child(card)


func _build_cards() -> void:
	for key: String in CFG.DIFF_ORDER:
		var preset := CFG.preset(key)
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		card.add_theme_constant_override("separation", 8)

		var btn := Button.new()
		btn.text = str(preset["label"])
		btn.custom_minimum_size = Vector2(CARD_WIDTH, 56)
		btn.pressed.connect(func() -> void: start_requested.emit(_mode, key))
		card.add_child(btn)

		var hint := Label.new()
		hint.text = str(preset["hint"])
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.custom_minimum_size = Vector2(CARD_WIDTH, 46)
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", Ink.MUTED)
		card.add_child(hint)

		var note := Label.new()
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Ink.FAINT)
		card.add_child(note)
		_card_notes[key] = note

		_cards.add_child(card)


## Строк в таблице шесть — режимы на сложности. Пустые не показываем: пока
## сыграно два забега, таблица из шести «пока пусто» только мешает читать.
func _build_records() -> void:
	for child in _records.get_children():
		_records.remove_child(child)
		child.queue_free()

	var shown := 0
	for mode_key: String in CFG.MODE_ORDER:
		for diff_key: String in CFG.DIFF_ORDER:
			var rec := Profile.record_for(CFG.record_key(mode_key, diff_key))
			if rec.is_empty():
				continue
			shown += 1
			_cell("%s · %s" % [CFG.mode(mode_key)["short"], CFG.preset(diff_key)["label"]],
					Ink.DIM, HORIZONTAL_ALIGNMENT_LEFT, 170.0)
			_cell(str(rec["score"]), Ink.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 90.0)
			_cell("уровень %d" % int(rec["best_level"]), Ink.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 110.0)
			_cell("серия %d" % int(rec["streak"]), Ink.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)

	if shown == 0:
		_cell("пока пусто", Ink.FAINT, HORIZONTAL_ALIGNMENT_CENTER, 170.0)


func _cell(text: String, color: Color, align: HorizontalAlignment, width: float) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	_records.add_child(l)
