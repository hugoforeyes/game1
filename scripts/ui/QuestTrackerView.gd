class_name QuestTrackerView
extends Control
## In-game quest tracker HUD — AAA art-directed, authored crisp in native 960×540.
## QuestManager owns the data; this view is pure presentation. Always fully
## expanded (no minimize) and every line wraps in full — never ellipsized.

const ORN_DIR := "res://assets/ui/quest_journal_v2/ornaments/"
const CREST_DIR := "res://assets/ui/quest_tracker_v3/ornaments/"

const WIDTH := 330.0
const RIGHT_MARGIN := 12.0
const TOP := 12.0
const PAD := 15.0

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	position = Vector2(12.0, 104.0)
	size = Vector2(WIDTH, _panel_height)


func set_data(data: Dictionary) -> void:
	_data = data
	_rebuild()


# ══════════════════════════════════════════════════════════════════════════════
func _rebuild() -> void:
	for child in get_children():
		child.free()
	_build_expanded()


func _build_expanded() -> void:
	# Frameless: title / objective / hints float straight on the scene over a
	# soft feathered scrim — no panel, no borders (mockup_hud style). Every line
	# wraps to its full measured height; nothing is ever trimmed with an ellipsis.
	var content_w := WIDTH - PAD * 2.0
	var title := str(_data.get("title", ""))
	var objective := str(_data.get("objective", ""))
	if bool(_data.get("has_count", false)):
		objective += "  (%d/%d)" % [int(_data.get("current", 0)), int(_data.get("total", 1))]
	var hints: Array = _data.get("hints", []) as Array

	var font := get_theme_default_font()

	# Title now wraps in full — measure it with the exact font it renders in.
	var title_w := content_w - 8.0
	var title_font := UiKit.title_font()
	var title_variation: FontVariation = null
	if title_font != null:
		title_variation = FontVariation.new()
		title_variation.base_font = title_font
		title_variation.variation_opentype = {"wght": 640}
	var title_font_used: Font = title_variation if title_variation != null else font
	var title_h: float = maxf(ceilf(title_font_used.get_multiline_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, title_w, 16).y) + 4.0, 22.0)

	var obj_h: float = maxf(ceilf(font.get_multiline_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, content_w - 16.0, 14).y) + 4.0, 18.0)
	var hint_heights: Array[float] = []
	for h in hints:
		var t := str((h as Dictionary).get("text", ""))
		var hh: float = maxf(ceilf(font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, content_w - 16.0, 12).y), 15.0)
		hint_heights.append(hh)

	var obj_y := title_h + 6.0
	var hints_top := obj_y + obj_h + 6.0
	var hints_total := 0.0
	for hh in hint_heights:
		hints_total += hh + 3.0
	var has_hints := not hints.is_empty()
	_panel_height = (hints_top + hints_total + 4.0) if has_hints else (obj_y + obj_h + 6.0)
	size = Vector2(WIDTH, _panel_height)

	_scrim(Rect2(-24, -16, WIDTH + 60, _panel_height + 40))

	# ── Title: gold diamond + serif title (wraps fully, never truncated) ──
	_add_diamond(self, Vector2(PAD - 4, 12), 4.0, C_GOLD)
	var title_label := _label(title, 16, C_GOLD, Rect2(PAD + 8, 0, title_w, title_h), VERTICAL_ALIGNMENT_TOP)
	if title_variation != null:
		title_label.add_theme_font_override("font", title_variation)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title_label)

	# ── Objective line: small amber diamond + text ──
	_add_diamond(self, Vector2(PAD + 4, obj_y + 8), 3.2, C_AMBER)
	var obj_label := UiKit.make_label("", 14, C_TEXT)
	obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_label.position = Vector2(PAD + 14, obj_y).round()
	obj_label.size = Vector2(content_w - 16, obj_h + 3).round()
	obj_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(obj_label)
	obj_label.text = objective
	line_count = obj_label.get_line_count()

	# ── Hints: dim cyan lines with tiny diamonds ──
	hint_row_count = 0
	if has_hints:
		var hy := hints_top
		for i in range(hints.size()):
			var text := str((hints[i] as Dictionary).get("text", ""))
			_add_diamond(self, Vector2(PAD + 4, hy + 7), 2.6, Color(C_CYAN, 0.85))
			var hint_label := UiKit.make_label("", 12, Color(C_CYAN, 0.82))
			hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_label.position = Vector2(PAD + 14, hy).round()
			hint_label.size = Vector2(content_w - 16, hint_heights[i] + 3).round()
			hint_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			add_child(hint_label)
			hint_label.text = text
			hy += hint_heights[i] + 3.0
			hint_row_count += 1


## Soft feathered translucent backing — readability without any frame.
func _scrim(rect: Rect2) -> void:
	var scrim := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.008, 0.012, 0.028, 0.66),
		Color(0.008, 0.012, 0.028, 0.46),
		Color(0.008, 0.012, 0.028, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = maxi(int(rect.size.x), 8)
	texture.height = maxi(int(rect.size.y), 8)
	scrim.texture = texture
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.position = rect.position
	scrim.size = rect.size
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


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
