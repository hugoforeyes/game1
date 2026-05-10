extends Node2D

const PAD        := Vector2(9.0, 7.0)
const MAX_W      := 110.0
const FONT_SIZE  := 8
const LINE_GAP   := 2.0
const CORNER_R   := 6.0
const PTR_H      := 6.0
const PTR_W      := 9.0
const ALPHA_SPEED := 7.0

const SHADOW_COLOR := Color(0.00, 0.00, 0.00, 0.50)
const BG_COLOR     := Color(0.05, 0.02, 0.12, 0.95)
const BORDER_COLOR := Color(0.75, 0.58, 0.25, 0.80)
const INNER_COLOR  := Color(1.00, 1.00, 1.00, 0.06)
const TEXT_COLOR   := Color(0.93, 0.88, 0.75, 1.00)

var target_alpha := 0.0  # driven externally by NPCController

var _lines  : Array[String] = []
var _box    := Rect2()
var _font   : Font
var _line_h : float

func _ready() -> void:
	z_index    = 5
	_font      = ThemeDB.fallback_font
	_line_h    = _font.get_height(FONT_SIZE) + LINE_GAP
	modulate.a = 0.0
	visible    = true

func show_text(text: String) -> void:
	_lines = _wrap(text)
	_build_box()

func _process(delta: float) -> void:
	if absf(modulate.a - target_alpha) < 0.004:
		modulate.a = target_alpha
		return
	modulate.a = lerpf(modulate.a, target_alpha, minf(delta * ALPHA_SPEED, 1.0))

# ── layout ────────────────────────────────────────────────────────────────────

func _wrap(text: String) -> Array[String]:
	var result : Array[String] = []
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
		text_w = maxf(text_w, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var w := text_w + PAD.x * 2.0
	var h := _lines.size() * _line_h + PAD.y * 2.0
	_box = Rect2(-w * 0.5, -(h + PTR_H), w, h)
	queue_redraw()

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _lines.is_empty():
		return

	var poly := _box_with_ptr(_box, CORNER_R)
	var so   := Vector2(1.5, 2.0)

	draw_colored_polygon(_offset(poly, so), SHADOW_COLOR)
	draw_colored_polygon(poly, BG_COLOR)
	draw_line(
		Vector2(_box.position.x + CORNER_R + 1.0, _box.position.y + 1.5),
		Vector2(_box.end.x      - CORNER_R - 1.0, _box.position.y + 1.5),
		INNER_COLOR, 1.0
	)
	var border := poly.duplicate()
	border.append(border[0])
	draw_polyline(border, BORDER_COLOR, 1.0)

	var x      := _box.position.x + PAD.x
	var ascent := _font.get_ascent(FONT_SIZE)
	for i in range(_lines.size()):
		var y := _box.position.y + PAD.y + ascent + i * _line_h
		draw_string(_font, Vector2(x, y), _lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

# ── helpers ───────────────────────────────────────────────────────────────────

func _box_with_ptr(rect: Rect2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rc  := minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var mid := (rect.position.x + rect.end.x) * 0.5
	var by  := rect.end.y
	_arc(pts, Vector2(rect.position.x + rc, rect.position.y + rc), rc, PI,       PI * 1.5)
	_arc(pts, Vector2(rect.end.x      - rc, rect.position.y + rc), rc, PI * 1.5, TAU     )
	_arc(pts, Vector2(rect.end.x      - rc, rect.end.y      - rc), rc, 0.0,      PI * 0.5)
	pts.append(Vector2(mid + PTR_W * 0.5, by))
	pts.append(Vector2(mid,               by + PTR_H))
	pts.append(Vector2(mid - PTR_W * 0.5, by))
	_arc(pts, Vector2(rect.position.x + rc, rect.end.y      - rc), rc, PI * 0.5, PI      )
	return pts

func _arc(pts: PackedVector2Array, center: Vector2, r: float, a_from: float, a_to: float) -> void:
	var steps := 4
	for i in range(steps + 1):
		var angle := a_from + (a_to - a_from) * float(i) / float(steps)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)

func _offset(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for pt in poly:
		result.append(pt + by)
	return result
