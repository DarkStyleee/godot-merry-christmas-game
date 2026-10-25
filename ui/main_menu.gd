class_name MainMenu
extends Control
## Главное меню: корневой экран, выбор режима и выбор сложности на нём же.
##
## Карточки и таблица рекордов собираются кодом из CFG.MODE_ORDER и
## CFG.DIFF_ORDER — добавить режим или пресет в config.gd достаточно, меню
## подхватит.

signal start_requested(mode_key: String, diff_key: String)
signal continue_requested
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
@onready var _continue_btn: Button = %ContinueBtn
@onready var _continue_note: Label = %ContinueNote
@onready var _play_btn: Button = %PlayBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _quit_btn: Button = %QuitBtn
@onready var _mode_back_btn: Button = %ModeBackBtn
@onready var _back_btn: Button = %BackBtn
@onready var _confirm_box: VBoxContainer = %ConfirmBox
@onready var _confirm_note: Label = %ConfirmNote
@onready var _confirm_btn: Button = %ConfirmBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _version: Label = %Version

var _mode := "santa"                   ## режим, выбранный на предыдущем шаге
var _card_notes: Dictionary = {}       ## diff -> Label с рекордом на карточке
var _saved_note := ""                  ## «режим · сложность · уровень · счёт» сохранённого забега
var _picked_diff := ""                 ## сложность, которая ждёт подтверждения


func _ready() -> void:
	_continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	_play_btn.pressed.connect(show_modes)
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())
	_quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	_mode_back_btn.pressed.connect(show_root)
	_back_btn.pressed.connect(show_modes)
	_confirm_btn.pressed.connect(confirm_new)
	_cancel_btn.pressed.connect(show_difficulty)
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "1.0")
	_build_mode_cards()
	_build_cards()
	_refresh()                         # первый показ сигнала видимости не даёт
	visibility_changed.connect(_on_visibility_changed)


func show_root() -> void:
	_show_box(_root_box)
	_refresh_continue()
	(_continue_btn if _continue_btn.visible else _play_btn).grab_focus()


func has_saved_run() -> bool:
	return _continue_btn.visible


## Кнопка есть, только если снимок поднимается: проверяет его тот же
## Sim.restore(), что потом и продолжит забег, — иначе меню обещало бы забег,
## которого не будет. Подпись — чтобы было видно, что потеряет «Начать игру».
## Первый show_root() зовёт main.gd: в _ready меню ещё не знает, песочница ли это.
func _refresh_continue() -> void:
	var sim := Sim.from_dict(Profile.load_run())
	var ok := sim != null
	_continue_btn.visible = ok
	_continue_note.visible = ok
	if ok:
		_saved_note = "%s · %s · %s · счёт %d" % [
			CFG.mode(sim.mode)["short"], sim.preset["label"],
			"победа" if sim.outcome == Sim.Outcome.VICTORY else "уровень %d" % sim.level,
			sim.score,
		]
		_continue_note.text = _saved_note


func show_modes() -> void:
	_show_box(_mode_box)
	_focus_first(_mode_cards)


func show_difficulty(mode_key := "") -> void:
	if not mode_key.is_empty():
		_mode = mode_key
	_show_box(_diff_box)
	_diff_title.text = "ВЫБЕРИТЕ СЛОЖНОСТЬ   ·   %s" % str(CFG.mode(_mode)["label"]).to_upper()
	_refresh()                         # рекорды на карточках — уже этого режима
	_focus_first(_cards)


## Карточка сложности. При сохранённом забеге сперва спрашиваем: новый забег
## закончит его. Фокус на «Отмене» — Enter по инерции не должен стереть часы игры.
func pick_difficulty(diff_key: String) -> void:
	if not has_saved_run():
		start_requested.emit(_mode, diff_key)
		return
	_picked_diff = diff_key
	_confirm_note.text = "Сохранённый забег закончится, его счёт уйдёт в рекорды:\n%s" % _saved_note
	_show_box(_confirm_box)
	_cancel_btn.grab_focus()


func is_confirming() -> bool:
	return _confirm_box.visible


func confirm_new() -> void:
	start_requested.emit(_mode, _picked_diff)


## Esc и кнопка «назад» — один и тот же путь на шаг назад.
func back() -> void:
	if _confirm_box.visible:
		show_difficulty()
	elif _diff_box.visible:
		show_modes()
	else:
		show_root()


func _show_box(box: Control) -> void:
	for b: Control in [_root_box, _mode_box, _diff_box, _confirm_box]:
		b.visible = b == box


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
		btn.pressed.connect(pick_difficulty.bind(key))
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
