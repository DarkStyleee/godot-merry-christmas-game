extends Node
## Звук: шины, громкости, музыка и эффекты. Автозагрузка.
##
## Шины Music и SFX собираются в рантайме, а не лежат отдельным файлом
## default_bus_layout.tres: их две, они тривиальны, и в текстовом виде их
## видно прямо здесь. Громкости берутся из Profile и применяются к шинам —
## поэтому ползунок в настройках знать о плеерах не обязан.

## имя -> [поток, базовая громкость 0..1]
const SFX_FILES := {
	"hit": [preload("res://assets/audio/hit.wav"), 0.55],
	"sober": [preload("res://assets/audio/sober.wav"), 0.5],
	"miss": [preload("res://assets/audio/miss.wav"), 0.7],
	"bonus": [preload("res://assets/audio/bonus.wav"), 0.5],
	"hazard": [preload("res://assets/audio/hazard.wav"), 0.6],
}
const MUSIC := preload("res://assets/audio/music.ogg")
const MUSIC_GAIN := 0.5            ## потолок музыки при ползунке на максимуме

var _sfx: Dictionary = {}
var _music: AudioStreamPlayer

## Headless — самопроверка и экспорт: звуковой драйвер пустышка, а движок выходит
## через долю секунды и считает недоигранные потоки утечкой. Играть нечему и незачем.
var _silent := false


func _ready() -> void:
	_ensure_bus(&"SFX")
	_ensure_bus(&"Music")

	for key: String in SFX_FILES:
		var p := AudioStreamPlayer.new()
		p.stream = SFX_FILES[key][0]
		p.volume_db = linear_to_db(SFX_FILES[key][1])
		p.bus = &"SFX"
		# один плеер на звук вместо пула нод: полифония даёт те же
		# перекрывающиеся голоса без ручной ротации
		p.max_polyphony = 6
		add_child(p)
		_sfx[key] = p

	_music = AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = MUSIC
	stream.loop = true
	_music.stream = stream
	_music.volume_db = linear_to_db(MUSIC_GAIN)
	_music.bus = &"Music"
	add_child(_music)

	# Плеера два, а не четыре: и в меню, и в забеге играет одна дорожка, поэтому
	# музыку не надо гасить и заводить на каждом переходе между экранами.
	Profile.settings_changed.connect(apply_volumes)
	apply_volumes()

	_silent = DisplayServer.get_name() == "headless"
	if not _silent:
		_music.play()


func apply_volumes() -> void:
	_set_bus(&"Master", Profile.master_volume, Profile.muted)
	_set_bus(&"Music", Profile.music_volume, false)
	_set_bus(&"SFX", Profile.sfx_volume, false)


func toggle_mute() -> void:
	Profile.muted = not Profile.muted
	Profile.changed()


## Перед выходом: движок жалуется на поток, оборванный на полуслове.
func stop_music() -> void:
	_music.stop()


func play(sound: String, pitch := 1.0) -> void:
	if Profile.muted or _silent:
		return
	var p: AudioStreamPlayer = _sfx[sound]
	p.pitch_scale = pitch
	p.play()


func _set_bus(bus_name: StringName, volume: float, mute: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(idx, mute or volume <= 0.005)


func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	return idx
