extends Node2D

const PAD := Vector2(8.0, 6.0)
const MAX_W := 110.0
const FONT_SIZE := 8
const LINE_GAP := 2.0
const BG_COLOR := Color(0.03, 0.01, 0.08, 0.92)
const BORDER_COLOR := Color(0.71, 0.55, 0.23, 0.55)
const TEXT_COLOR := Color(0.93, 0.88, 0.75, 1.0)
const PTR_H := 5.0

var _lines: Array[String] = []
var _box := Rect2()
var _font: Font
var _line_h: float

func _ready() -> void:
	z_index = 5
	_font = ThemeDB.fallback_font
	_line_h = _font.get_height(FONT_SIZE) + LINE_GAP
	visible = false

func show_text(text: String) -> void:
	_lines = _wrap(text)
	_build_box()
	visible = true
	queue_redraw()

func _wrap(text: String) -> Array[String]:
	var result: Array[String] = []
	var current := ""
	for word in text.split(" "):
		var candidate := (current + " " + word).strip_edges()
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= MAX_W:
			current = candidate
		else:
			if not current.is_empty():
				result.append(current)
			current = word
	if not current.is_empty():
		result.append(current)
	return result

func _build_box() -> void:
	var text_w := 0.0
	for line in _lines:
		text_w = max(text_w, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var w := text_w + PAD.x * 2.0
	var h := _lines.size() * _line_h + PAD.y * 2.0
	_box = Rect2(-w * 0.5, -(h + PTR_H), w, h)

func _draw() -> void:
	if _lines.is_empty():
		return
	draw_rect(_box, BG_COLOR)
	draw_rect(_box, BORDER_COLOR, false, 1.0)
	var by := _box.end.y
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, by), Vector2(4.0, by), Vector2(0.0, by + PTR_H),
	]), BG_COLOR)
	draw_polyline(PackedVector2Array([
		Vector2(-4.0, by), Vector2(0.0, by + PTR_H), Vector2(4.0, by),
	]), BORDER_COLOR, 1.0)
	var x := _box.position.x + PAD.x
	var ascent := _font.get_ascent(FONT_SIZE)
	for i in range(_lines.size()):
		var y := _box.position.y + PAD.y + ascent + i * _line_h
		draw_string(_font, Vector2(x, y), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
