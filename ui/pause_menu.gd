class_name PauseMenu
extends Control
## Пауза. Игру останавливает не этот экран, а main.gd через get_tree().paused —
## здесь только кнопки.

signal resume_requested
signal settings_requested
signal menu_requested
signal quit_requested

@onready var _info: Label = %Info
@onready var _resume_btn: Button = %ResumeBtn
@onready var _settings_btn: Button = %SettingsBtn
@onready var _menu_btn: Button = %MenuBtn
@onready var _quit_btn: Button = %QuitBtn


func _ready() -> void:
	_resume_btn.pressed.connect(func() -> void: resume_requested.emit())
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())
	_menu_btn.pressed.connect(func() -> void: menu_requested.emit())
	_quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	visibility_changed.connect(_on_visibility_changed)


func show_run(sim: Sim) -> void:
	_info.text = "%s   ·   уровень %d   ·   счёт %d" % [
		sim.preset["label"], sim.level, sim.score,
	]


func _on_visibility_changed() -> void:
	if visible:
		_resume_btn.grab_focus()
