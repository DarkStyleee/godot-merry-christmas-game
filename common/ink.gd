class_name Ink
extends RefCounted
## Палитра и рисование текста — общее для арены, HUD и экранов интерфейса.
##
## Отдельный файл, потому что цвета обязаны совпадать в трёх местах: в
## иммедиатной отрисовке арены, в HUD и в теме Control-нод (ui/theme.tres,
## значения продублированы там руками — иначе тему пришлось бы собирать кодом).

const TEXT := Color("eaf1ff")
const DIM := Color("9fb0cc")
const MUTED := Color("7d8aa3")
const FAINT := Color("5b6478")
const GOLD := Color("ffd166")
const GREEN := Color("8ef2a4")
const RED := Color("e8433f")
const BLUE := Color("9ad8ff")
const ORANGE := Color("ff9a5c")
const NIGHT := Color(0.027, 0.043, 0.078, 1.0)


static func font() -> Font:
	return ThemeDB.fallback_font


## Рисует строку. from_top=true — Y задаёт верх строки, а не базовую линию
## (как было в canvas с textBaseline='top').
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, bold := false, from_top := false) -> void:
	var f := font()
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0
	if from_top:
		p.y += f.get_ascent(size)
	# Жирного начертания у встроенного шрифта нет — обводка в тот же цвет
	# даёт нужный вес, не таща в проект второй файл шрифта.
	if bold:
		ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 1, color)
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func mmss(seconds: float) -> String:
	var s := int(round(seconds))          # округляем целое, иначе бывает «0:60»
	return "%d:%02d" % [s / 60, s % 60]
