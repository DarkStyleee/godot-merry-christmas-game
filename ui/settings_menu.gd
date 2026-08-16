class_name SettingsMenu
extends Control
## Настройки: громкости, экран, удобство, сброс рекордов.
##
## Экран — тонкий слой над Profile: любое изменение сразу пишется в профиль и
## сразу слышно, никаких «Применить». Громкости уезжают в шины AudioServer
## через Audio.apply_volumes(), подписанный на Profile.settings_changed.

signal closed

@onready var _master: HSlider = %Master
@onready var _music: HSlider = %Music
@onready var _sfx: HSlider = %Sfx
@onready var _master_value: Label = %MasterValue
@onready var _music_value: Label = %MusicValue
@onready var _sfx_value: Label = %SfxValue
@onready var _mute: CheckButton = %Mute
@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _shake: CheckButton = %Shake
@onready var _markers: CheckButton = %Markers
@onready var _reset_btn: Button = %ResetBtn
@onready var _back_btn: Button = %BackBtn
@onready var _confirm: ConfirmationDialog = %Confirm

var _loading := false


func _ready() -> void:
	_master.value_changed.connect(func(v: float) -> void: _on_volume(&"master", v))
	_music.value_changed.connect(func(v: float) -> void: _on_volume(&"music", v))
	_sfx.value_changed.connect(func(v: float) -> void: _on_volume(&"sfx", v))
	# Пример громкости — по концу перетаскивания, а не на каждый шаг ползунка:
	# иначе за один драг «бонус» проигрывается двадцать раз.
	_master.drag_ended.connect(_beep)
	_sfx.drag_ended.connect(_beep)
	_mute.toggled.connect(func(on: bool) -> void: _on_flag(&"muted", on))
	_fullscreen.toggled.connect(_on_fullscreen)
	_shake.toggled.connect(func(on: bool) -> void: _on_flag(&"screen_shake", on))
	_markers.toggled.connect(func(on: bool) -> void: _on_flag(&"landing_markers", on))
	_reset_btn.pressed.connect(_confirm.popup_centered)
	_confirm.confirmed.connect(_on_reset_confirmed)
	_back_btn.pressed.connect(func() -> void: closed.emit())
	visibility_changed.connect(_on_visibility_changed)
	# F11 и M работают и с открытыми настройками, переключатели должны это видеть
	Profile.settings_changed.connect(_on_profile_changed)


func _on_visibility_changed() -> void:
	if not visible:
		return
	_pull()
	_back_btn.grab_focus()


func _on_profile_changed() -> void:
	if visible:
		_pull()


## Профиль -> виджеты. Флаг гасит обратную запись, иначе загрузка выглядит
## как семь действий пользователя подряд.
func _pull() -> void:
	_loading = true
	_master.value = Profile.master_volume
	_music.value = Profile.music_volume
	_sfx.value = Profile.sfx_volume
	_mute.button_pressed = Profile.muted
	_fullscreen.button_pressed = Profile.fullscreen
	_shake.button_pressed = Profile.screen_shake
	_markers.button_pressed = Profile.landing_markers
	_loading = false
	_show_values()


func _show_values() -> void:
	_master_value.text = "%d%%" % roundi(_master.value * 100.0)
	_music_value.text = "%d%%" % roundi(_music.value * 100.0)
	_sfx_value.text = "%d%%" % roundi(_sfx.value * 100.0)


func _on_volume(which: StringName, v: float) -> void:
	_show_values()
	if _loading:
		return
	match which:
		&"master": Profile.master_volume = v
		&"music": Profile.music_volume = v
		&"sfx": Profile.sfx_volume = v
	Profile.changed()


func _beep(_changed: bool) -> void:
	Audio.play("bonus")


func _on_flag(which: StringName, on: bool) -> void:
	if _loading:
		return
	match which:
		&"muted": Profile.muted = on
		&"screen_shake": Profile.screen_shake = on
		&"landing_markers": Profile.landing_markers = on
	Profile.changed()


func _on_fullscreen(on: bool) -> void:
	if _loading or on == Profile.fullscreen:
		return
	Profile.toggle_fullscreen()


func _on_reset_confirmed() -> void:
	Profile.reset_records()
