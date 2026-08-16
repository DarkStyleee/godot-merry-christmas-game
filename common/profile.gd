extends Node
## Профиль игрока: настройки и рекорды. Автозагрузка, живёт весь сеанс.
##
## Формат — ConfigFile в user://profile.cfg. Файл лежит в пользовательской
## папке, править его руками может кто угодно, поэтому всё, что прочитано,
## зажимается в разумные пределы.

const PATH := "user://profile.cfg"
const LEGACY_PATH := "user://records.json"    ## формат до появления настроек

signal settings_changed

# ---- звук ----
var master_volume := 0.9
var music_volume := 0.55
var sfx_volume := 0.9
var muted := false

# ---- экран и удобство ----
var fullscreen := false
var screen_shake := true
var landing_markers := true

## CFG.record_key(режим, сложность) -> {score, level, streak, time, best_level}
var records: Dictionary = {}

## Отладочный прогон: на диск не пишем, чужие рекорды не портим.
var sandbox := false


func _ready() -> void:
	_load()


func apply_window() -> void:
	if sandbox or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_window()
	changed()


func changed() -> void:
	settings_changed.emit()
	save()


## Ключ здесь и ниже — из CFG.record_key(режим, сложность), а не голая сложность.
func record_for(key: String) -> Dictionary:
	return records.get(key, {})


func best_score(key: String) -> int:
	return int(record_for(key).get("score", 0))


## Кладёт итоги забега в таблицу. Возвращает true, если счёт стал рекордным.
func submit_run(stats: Dictionary) -> bool:
	var key := CFG.record_key(stats["mode"], stats["diff"])
	var cur: Dictionary = records.get(key, {}).duplicate()
	var is_record := int(stats["score"]) > int(cur.get("score", -1))
	cur["best_level"] = maxi(int(cur.get("best_level", 0)), int(stats["level"]))
	# «или запись неполная» — чтобы в таблице не оказалось строки без счёта,
	# из которой меню потом достаёт несуществующий ключ.
	if is_record or not cur.has("score"):
		cur["score"] = int(stats["score"])
		cur["level"] = int(stats["level"])
		cur["streak"] = int(stats["streak"])
		cur["time"] = int(round(float(stats["time"])))
	records[key] = cur
	save()
	return is_record


func reset_records() -> void:
	records.clear()
	save()


func save() -> void:
	if sandbox:
		return
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "muted", muted)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("game", "landing_markers", landing_markers)
	for key: String in records:
		cf.set_value("records", key, records[key])
	var err := cf.save(PATH)
	if err != OK:
		push_warning("Профиль не сохранился: %s" % error_string(err))


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		_import_legacy()
		return
	master_volume = _unit(cf.get_value("audio", "master", master_volume))
	music_volume = _unit(cf.get_value("audio", "music", music_volume))
	sfx_volume = _unit(cf.get_value("audio", "sfx", sfx_volume))
	muted = bool(cf.get_value("audio", "muted", false))
	fullscreen = bool(cf.get_value("video", "fullscreen", false))
	screen_shake = bool(cf.get_value("game", "screen_shake", true))
	landing_markers = bool(cf.get_value("game", "landing_markers", true))
	for mode_key: String in CFG.MODE_ORDER:
		for diff_key: String in CFG.DIFF_ORDER:
			var key := CFG.record_key(mode_key, diff_key)
			var raw: Variant = cf.get_value("records", key, {})
			if raw is Dictionary and not (raw as Dictionary).is_empty():
				records[key] = _sane_record(raw)


## Рекорды из версии без настроек — чтобы обновление не обнуляло таблицу.
## Только читает: писать здесь нельзя, потому что _load() случается раньше, чем
## отладочный прогон успевает выставить sandbox. Прочитанное ляжет на диск при
## первом же изменении — или при выходе из игры.
func _import_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	var f := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	muted = bool((data as Dictionary).get("muted", false))
	var recs: Variant = (data as Dictionary).get("records", {})
	if not recs is Dictionary:
		return
	for key: String in CFG.DIFFICULTY:
		var r: Variant = (recs as Dictionary).get(key)
		if r is Dictionary:
			records[key] = _sane_record(r)


func _sane_record(r: Dictionary) -> Dictionary:
	return {
		"score": clampi(int(r.get("score", 0)), 0, 1_000_000_000),
		"level": clampi(int(r.get("level", 1)), 1, CFG.LEVEL_MAX * 100),
		"streak": clampi(int(r.get("streak", 0)), 0, 1_000_000),
		"time": clampi(int(r.get("time", 0)), 0, 1_000_000),
		"best_level": clampi(int(r.get("best_level", 1)), 1, CFG.LEVEL_MAX * 100),
	}


func _unit(v: Variant) -> float:
	return clampf(float(v), 0.0, 1.0)
