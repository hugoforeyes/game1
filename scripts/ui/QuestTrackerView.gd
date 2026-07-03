class_name QuestTrackerView
extends Control
## In-game quest tracker HUD — AAA art-directed, authored crisp in native 960×540.
## QuestManager owns the data; this view is pure presentation (expanded + compact).

signal collapse_toggled

const ORN_DIR := "res://assets/ui/quest_journal_v2/ornaments/"
const CREST_DIR := "res://assets/ui/quest_tracker_v3/ornaments/"

const WIDTH := 330.0
const RIGHT_MARGIN := 12.0
const TOP := 12.0
const PAD := 15.0
const COMPACT := 64.0

# ── Palette (shared with the journal) ────────────────────────────────────────
const C_GLASS := Color(0.035, 0.046, 0.066, 0.93)
const C_GOLD := Color(0.99, 0.85, 0.48)
const C_GOLD_DIM := Color(0.76, 0.57, 0.28)
const C_GOLD_DEEP := Color(0.45, 0.33, 0.16)
const C_LINE := Color(0.70, 0.52, 0.25, 0.55)
const C_TEXT := Color(0.94, 0.90, 0.80)
const C_TEXT_DIM := Color(0.94, 0.90, 0.80, 0.55)
const C_AMBER := Color(1.00, 0.71, 0.29)
const C_BLUE := Color(0.46, 0.74, 1.00)
const C_CYAN := Color(0.56, 0.93, 0.96)
const C_PURPLE := Color(0.78, 0.55, 0.97)

var _data: Dictionary = {}
var _panel_height := 120.0

# Exposed for QA assertions.
var line_count := 0
var hint_row_count := 0
var is_compact := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	position = Vector2(get_viewport_rect().size.x - RIGHT_MARGIN - WIDTH, TOP)
	size = Vector2(WIDTH, _panel_height)


func set_data(data: Dictionary) -> void:
	_data = data
	is_compact = bool(data.get("compact", false))
	_rebuild()


# ══════════════════════════════════════════════════════════════════════════════
func _rebuild() -> void:
	for child in get_children():
		child.free()
	if is_compact:
		_build_compact()
	else:
		_build_expanded()


func _build_compact() -> void:
	position = Vector2(get_viewport_rect().size.x - RIGHT_MARGIN - COMPACT, TOP)
	size = Vector2(COMPACT, COMPACT)
	_glass_panel(Rect2(0, 0, COMPACT, COMPACT))
	_corners(Rect2(0, 0, COMPACT, COMPACT))
	var crest := _quest_crest(str(_data.get("type", "main")))
	add_child(_make_tex(crest, Rect2(10, 10, COMPACT - 20, COMPACT - 20)))
	# Click target to expand.
	_add_button(Rect2(0, 0, COMPACT, COMPACT))
	# Tiny "expand" chevron hint, bottom-right.
	_chevron(Vector2(COMPACT - 13, COMPACT - 13), false)


func _build_expanded() -> void:
	var content_w := WIDTH - PAD * 2.0
	var title := str(_data.get("title", ""))
	var objective := str(_data.get("objective", ""))
	var hints: Array = _data.get("hints", []) as Array

	var font := get_theme_default_font()
	# Measure wrapped heights.
	var obj_h: float = clampf(ceilf(font.get_multiline_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, content_w - 2.0, 14).y) + 6.0, 20.0, 80.0)
	var hint_heights: Array[float] = []
	for h in hints:
		var t := "%s" % str((h as Dictionary).get("text", ""))
		var hh: float = clampf(ceilf(font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, content_w - 16.0, 13).y), 16.0, 54.0)
		hint_heights.append(hh)

	# ── Vertical layout cursor ────────────────────────────────────────────────
	var header_bottom := 52.0
	var y := header_bottom + 10.0           # objective heading baseline
	var obj_heading_y := y - 4.0
	var obj_text_y := y + 18.0
	y = obj_text_y + obj_h + 9.0            # hint divider
	var has_hints := not hints.is_empty()
	var hint_div_y := y
	var hint_heading_y := y + 7.0
	var hints_top := y + 26.0
	var hints_total := 0.0
	for hh in hint_heights:
		hints_total += hh + 4.0
	var bottom := hints_top + hints_total + 8.0 if has_hints else obj_text_y + obj_h + 10.0
	_panel_height = bottom

	position = Vector2(get_viewport_rect().size.x - RIGHT_MARGIN - WIDTH, TOP)
	size = Vector2(WIDTH, _panel_height)

	# ── Frame ──────────────────────────────────────────────────────────────────
	_glass_panel(Rect2(0, 0, WIDTH, _panel_height))
	_corners(Rect2(0, 0, WIDTH, _panel_height))
	_center_jewel(Vector2(WIDTH * 0.5, 0.0))
	_center_jewel(Vector2(WIDTH * 0.5, _panel_height))

	# ── Header ───────────────────────────────────────────────────────────────
	add_child(_make_tex(_quest_crest(str(_data.get("type", "main"))), Rect2(PAD - 2, 9, 34, 34)))
	var title_label := _label(title, 17, C_GOLD, Rect2(PAD + 38, 12, content_w - 38 - 26, 26))
	var title_font := UiKit.title_font()
	if title_font != null:
		var title_variation := FontVariation.new()
		title_variation.base_font = title_font
		title_variation.variation_opentype = {"wght": 640}
		title_label.add_theme_font_override("font", title_variation)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
	# Collapse chevron button (top-right).
	var chev_center := Vector2(WIDTH - PAD - 9, 22)
	_circle_button(chev_center, 11.0)
	_chevron(chev_center, true)
	_add_button(Rect2(chev_center.x - 13, chev_center.y - 13, 26, 26))
	# Header divider.
	_divider_ornament(Vector2(WIDTH * 0.5, header_bottom - 4.0), content_w + 6.0)

	# ── Objective ──────────────────────────────────────────────────────────────
	_section_marker(Vector2(PAD + 4, obj_heading_y + 6), C_AMBER)
	add_child(_label("MỤC TIÊU", 12, C_AMBER, Rect2(PAD + 16, obj_heading_y, 160, 16)))
	var obj_label := UiKit.make_label("", 14, C_TEXT)
	obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	obj_label.position = Vector2(PAD + 2, obj_text_y).round()
	obj_label.size = Vector2(content_w - 2, obj_h + 4).round()
	obj_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(obj_label)
	obj_label.text = objective
	line_count = obj_label.get_line_count()

	# ── Hints ────────────────────────────────────────────────────────────────────
	hint_row_count = 0
	if has_hints:
		_thin_divider(Vector2(PAD, hint_div_y), content_w, Color(C_CYAN, 0.40))
		_section_marker_bulb(Vector2(PAD + 4, hint_heading_y + 6))
		add_child(_label("GỢI Ý", 12, C_CYAN, Rect2(PAD + 16, hint_heading_y, 120, 16)))
		var hy := hints_top
		for i in range(hints.size()):
			var text := str((hints[i] as Dictionary).get("text", ""))
			_add_diamond(self, Vector2(PAD + 8, hy + 7), 3.0, Color(C_CYAN, 0.95))
			var hint_label := UiKit.make_label("", 13, Color(C_CYAN, 0.90))
			hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			hint_label.position = Vector2(PAD + 16, hy).round()
			hint_label.size = Vector2(content_w - 16, hint_heights[i] + 3).round()
			hint_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			add_child(hint_label)
			hint_label.text = text
			hy += hint_heights[i] + 4.0
			hint_row_count += 1


# ══════════════════════════════════════════════════════════════════════════════
# FRAME / CHROME
# ══════════════════════════════════════════════════════════════════════════════
func _glass_panel(rect: Rect2) -> void:
	# Soft outer shadow.
	_add_rect(self, Rect2(rect.position.x - 2, rect.position.y - 2, rect.size.x + 4, rect.size.y + 4), Color(0, 0, 0, 0.45))
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = C_GLASS
	style.border_color = Color(C_GOLD_DIM, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	# Inner glass glow + bevels.
	_add_gradient(self, Rect2(rect.position.x + 2, rect.position.y + 2, rect.size.x - 4, 22),
			Color(0.16, 0.20, 0.30, 0.40), Color(0.04, 0.05, 0.07, 0.0), true)
	_add_rect(self, Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, 1), Color(1.0, 0.85, 0.42, 0.20))


func _corners(rect: Rect2) -> void:
	# Minimal, refined corner brackets (shared with the journal's new corner art).
	if _has(ORN_DIR + "corner2_tl.png"):
		var cw := 26.0
		var ch := 20.0
		add_child(_corner_art(ORN_DIR + "corner2_tl.png", Rect2(rect.position.x - 3, rect.position.y - 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_tr.png", Rect2(rect.end.x - cw + 3, rect.position.y - 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_bl.png", Rect2(rect.position.x - 3, rect.end.y - ch + 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_br.png", Rect2(rect.end.x - cw + 3, rect.end.y - ch + 3, cw, ch)))
	elif _has(ORN_DIR + "corner_tl.png"):
		var cs := 22.0
		add_child(_corner_art(ORN_DIR + "corner_tl.png", Rect2(rect.position.x - 4, rect.position.y - 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_tr.png", Rect2(rect.end.x - cs + 4, rect.position.y - 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_bl.png", Rect2(rect.position.x - 4, rect.end.y - cs + 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_br.png", Rect2(rect.end.x - cs + 4, rect.end.y - cs + 4, cs, cs)))


func _center_jewel(center: Vector2) -> void:
	# A small gold setting with a blue gem, like the mockup's top/bottom accents.
	_add_diamond(self, center, 6.0, C_GOLD_DEEP)
	_add_diamond(self, center, 4.6, C_GOLD)
	_add_diamond(self, center, 3.0, C_BLUE)
	_add_diamond(self, center, 1.6, Color(0.85, 0.95, 1.0))


func _divider_ornament(center: Vector2, width: float) -> void:
	if _has(ORN_DIR + "divider.png"):
		var dh := 16.0
		add_child(_make_path(ORN_DIR + "divider.png", Rect2(center.x - width * 0.5, center.y - dh * 0.5, width, dh), TextureRect.STRETCH_KEEP_ASPECT_CENTERED))
	else:
		_thin_divider(Vector2(center.x - width * 0.5, center.y), width, C_LINE)


func _thin_divider(pos: Vector2, width: float, color: Color) -> void:
	_add_rect(self, Rect2(pos.x, pos.y, width, 1), color)
	_add_rect(self, Rect2(pos.x, pos.y + 1, width, 1), Color(0, 0, 0, 0.3))


func _section_marker(center: Vector2, color: Color) -> void:
	_add_diamond(self, center, 4.6, Color(color, 0.20))
	_add_diamond(self, center, 3.4, color)
	_add_diamond(self, center, 1.6, Color(1, 1, 1, 0.7))


func _section_marker_bulb(center: Vector2) -> void:
	_add_disc(self, center + Vector2(0, -0.5), 4.4, Color(C_CYAN, 0.22))
	_add_disc(self, center + Vector2(0, -0.5), 3.0, C_CYAN)
	_add_rect(self, Rect2(center.x - 1.2, center.y + 2.6, 2.4, 2.2), Color(C_CYAN, 0.85))


func _circle_button(center: Vector2, radius: float) -> void:
	_add_disc(self, center, radius + 0.6, Color(C_GOLD_DEEP, 0.9))
	_add_disc(self, center, radius - 0.4, Color(0.10, 0.085, 0.05, 0.95))
	_add_disc(self, center, radius - 0.4, Color(C_GOLD, 0.0))


func _chevron(center: Vector2, down: bool) -> void:
	var line := Line2D.new()
	var dy := 3.0 if down else -3.0
	line.points = PackedVector2Array([
		center + Vector2(-4.0, -dy * 0.6), center + Vector2(0, dy * 0.7), center + Vector2(4.0, -dy * 0.6)])
	line.width = 1.6
	line.default_color = C_GOLD
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	add_child(line)


func _add_button(rect: Rect2) -> void:
	var btn := Control.new()
	btn.position = rect.position
	btn.size = rect.size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			collapse_toggled.emit())
	add_child(btn)


# ══════════════════════════════════════════════════════════════════════════════
# RESOLVERS / PRIMITIVES
# ══════════════════════════════════════════════════════════════════════════════
func _quest_crest(quest_type: String) -> String:
	var crest_name: String = {"main": "crest_main.png", "side": "crest_side.png", "hidden": "crest_hidden.png"}.get(quest_type, "crest_main.png")
	if _has(CREST_DIR + crest_name):
		return CREST_DIR + crest_name
	return ""


func _make_tex(path: String, rect: Rect2) -> Control:
	if path != "" and _has(path):
		return _make_path(path, rect, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	# Procedural crest fallback: gold diamond emblem.
	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := rect.size * 0.5
	_add_diamond(holder, c, rect.size.x * 0.44, Color(C_GOLD, 0.25))
	_add_diamond(holder, c, rect.size.x * 0.34, C_GOLD)
	_add_diamond(holder, c, rect.size.x * 0.22, C_AMBER)
	return holder


func _make_path(path: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var art := TextureRect.new()
	if _has(path):
		art.texture = load(path) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.position = rect.position.round()
	art.size = rect.size.round()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _corner_art(path: String, rect: Rect2) -> TextureRect:
	var art := _make_path(path, rect)
	art.z_index = 20
	return art


func _label(text: String, font_size: int, color: Color, rect: Rect2, vertical: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER) -> Label:
	var label := UiKit.make_label(text, font_size, color)
	label.position = rect.position.round()
	label.size = rect.size.round()
	label.vertical_alignment = vertical
	return label


func _add_diamond(parent: Control, center: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0)])
	poly.color = color
	parent.add_child(poly)


func _add_disc(parent: Control, center: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	poly.color = color
	parent.add_child(poly)


func _frame_outline(parent: Control, rect: Rect2, color: Color) -> void:
	_add_rect(parent, Rect2(rect.position.x, rect.position.y, rect.size.x, 1), color)
	_add_rect(parent, Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Color(color, color.a * 0.8))
	_add_rect(parent, Rect2(rect.position.x, rect.position.y, 1, rect.size.y), Color(color, color.a * 0.85))
	_add_rect(parent, Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), Color(color, color.a * 0.85))


func _add_gradient(parent: Control, rect: Rect2, from_color: Color, to_color: Color, vertical: bool) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, from_color)
	grad.set_color(1, to_color)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 2 if vertical else 64
	tex.height = 64 if vertical else 2
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var node := TextureRect.new()
	node.texture = tex
	node.position = rect.position
	node.size = rect.size
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _add_rect(parent: Control, rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = rect.position.round()
	block.size = rect.size.round()
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _has(path: String) -> bool:
	return ResourceLoader.exists(path)
