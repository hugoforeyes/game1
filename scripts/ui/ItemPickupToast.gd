class_name ItemPickupToast
extends Control
## Compact top-center item acquisition toast.
##
## The component is deliberately code-native: typography, icon placement and
## frame geometry remain crisp at the game's integer-scaled resolutions while
## the chapter-provided item artwork stays the visual focus.

const PANEL_SIZE := Vector2(360, 72)
const ICON_WELL := Rect2(16, 5, 65, 62)
const TEXT_LEFT := 92.0
const QUANTITY_RECT := Rect2(292, 20, 46, 32)
const PROGRESS_RECT := Rect2(82, 66, 258, 2)
const FRAME_PATH := "res://assets/ui/item_pickup_v2/frame.png"
const HOLD_SECONDS := 1.0

const C_NAVY := Color("07111c")
const C_NAVY_INNER := Color("0c1b2d")
const C_IVORY := Color("f5ead5")
const C_GOLD := Color("c8a45a")
const C_GOLD_BRIGHT := Color("f0ca76")
const C_CYAN := Color("65d9e8")

var header_label: Label
var name_label: Label
var quantity_label: Label
var icon_rect: TextureRect

var _progress := 1.0
var _frame_texture: Texture2D
var _panel_style: StyleBoxFlat
var _shadow_style: StyleBoxFlat
var _icon_style: StyleBoxFlat
var _quantity_style: StyleBoxFlat


func setup(data: Dictionary) -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	pivot_offset = PANEL_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	_build_generated_frame()
	_build_content(data)
	queue_redraw()


func _build_styles() -> void:
	_shadow_style = _style(Color(0.0, 0.0, 0.0, 0.55), Color(0, 0, 0, 0), 7, 0)
	_shadow_style.shadow_color = Color(0.0, 0.0, 0.0, 0.32)
	_shadow_style.shadow_size = 8
	_shadow_style.shadow_offset = Vector2(0, 3)

	_panel_style = _style(Color(C_NAVY, 0.965), Color(C_GOLD, 0.78), 6, 1)
	_panel_style.border_width_left = 2
	_panel_style.border_width_right = 2
	_panel_style.shadow_color = Color(C_CYAN, 0.07)
	_panel_style.shadow_size = 3

	_icon_style = _style(Color(C_NAVY_INNER, 0.98), Color(C_GOLD, 0.86), 5, 1)
	_icon_style.border_width_left = 2
	_quantity_style = _style(Color(0.025, 0.045, 0.075, 0.96), Color(C_GOLD, 0.80), 10, 1)


func _build_generated_frame() -> void:
	_frame_texture = load(FRAME_PATH) if ResourceLoader.exists(FRAME_PATH) else null
	if _frame_texture == null:
		return
	var frame := TextureRect.new()
	frame.texture = _frame_texture
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.size = PANEL_SIZE
	frame.show_behind_parent = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)


func _build_content(data: Dictionary) -> void:
	var texture := data.get("icon") as Texture2D
	if texture != null:
		icon_rect = TextureRect.new()
		icon_rect.texture = texture
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.position = Vector2(22, 11)
		icon_rect.size = Vector2(52, 50)
		icon_rect.pivot_offset = icon_rect.size * 0.5
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)

	header_label = UiKit.make_label_strong("VẬT PHẨM NHẬN ĐƯỢC", 9, C_GOLD_BRIGHT)
	var header_font := UiKit.body_semibold_font()
	if header_font != null:
		var header_variation := FontVariation.new()
		header_variation.base_font = header_font
		header_variation.spacing_glyph = 1
		header_label.add_theme_font_override("font", header_variation)
	header_label.position = Vector2(TEXT_LEFT, 11)
	header_label.size = Vector2(188, 15)
	header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_label.clip_text = true
	add_child(header_label)

	name_label = UiKit.make_label_strong(str(data.get("name", "Vật phẩm")), 17, C_IVORY)
	name_label.position = Vector2(TEXT_LEFT, 29)
	name_label.size = Vector2(190, 27)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_fit_name_label()
	add_child(name_label)

	quantity_label = UiKit.make_label_strong("+%d" % maxi(1, int(data.get("count", 1))), 15, C_GOLD_BRIGHT)
	quantity_label.position = QUANTITY_RECT.position
	quantity_label.size = QUANTITY_RECT.size
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fit_quantity_label()
	add_child(quantity_label)


func _fit_name_label() -> void:
	var font := UiKit.body_semibold_font()
	if font == null:
		return
	var font_size := 17
	while font_size > 13 and font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > name_label.size.x:
		font_size -= 1
	name_label.add_theme_font_size_override("font_size", font_size)


func _fit_quantity_label() -> void:
	var font := UiKit.body_semibold_font()
	if font == null:
		return
	var font_size := 15
	while font_size > 10 and font.get_string_size(quantity_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x > quantity_label.size.x - 8:
		font_size -= 1
	quantity_label.add_theme_font_size_override("font_size", font_size)


func play() -> void:
	position = Vector2(-PANEL_SIZE.x * 0.5, -13)
	modulate.a = 0.0
	scale = Vector2(0.965, 0.965)
	if icon_rect != null:
		icon_rect.scale = Vector2(0.72, 0.72)

	var intro := create_tween().set_parallel(true)
	intro.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	intro.tween_property(self, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	intro.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	intro.tween_property(self, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if icon_rect != null:
		intro.tween_property(icon_rect, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.04)
	await intro.finished

	var hold := create_tween()
	hold.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	hold.tween_method(_set_progress, 1.0, 0.0, HOLD_SECONDS).set_trans(Tween.TRANS_LINEAR)
	await hold.finished

	var outro := create_tween().set_parallel(true)
	outro.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	outro.tween_property(self, "position:y", -10.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	outro.tween_property(self, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	outro.tween_property(self, "scale", Vector2(0.985, 0.985), 0.22)
	await outro.finished


func _set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if _frame_texture == null:
		draw_style_box(_shadow_style, Rect2(Vector2.ZERO, PANEL_SIZE))
		draw_style_box(_panel_style, Rect2(Vector2.ZERO, PANEL_SIZE))
		draw_line(Vector2(82, 2), Vector2(PANEL_SIZE.x - 14, 2), Color(C_GOLD_BRIGHT, 0.54), 1.0)
		draw_line(Vector2(81, 11), Vector2(81, 61), Color(C_CYAN, 0.50), 1.0)
		draw_style_box(_icon_style, ICON_WELL)
		draw_style_box(_quantity_style, QUANTITY_RECT)
		var tick := Color(C_GOLD_BRIGHT, 0.72)
		draw_line(Vector2(3, 13), Vector2(3, 5), tick, 1.0)
		draw_line(Vector2(3, 5), Vector2(11, 5), tick, 1.0)
		draw_line(Vector2(PANEL_SIZE.x - 4, 13), Vector2(PANEL_SIZE.x - 4, 5), tick, 1.0)
		draw_line(Vector2(PANEL_SIZE.x - 4, 5), Vector2(PANEL_SIZE.x - 12, 5), tick, 1.0)

	# A quiet runtime halo stays dynamic while the generated frame provides the
	# authored bevels, gemstones and material detail.
	draw_circle(ICON_WELL.get_center(), 23.0, Color(C_CYAN, 0.035))
	draw_arc(ICON_WELL.get_center(), 23.0, 0.0, TAU, 48, Color(C_CYAN, 0.22), 1.0, true)

	# Bottom lifetime line. The tiny gold diamond marks the live edge so the
	# countdown remains legible without adding a numeric timer.
	# Mask the baked reference line so the generated component still exposes an
	# actual countdown rather than a static decoration.
	if _frame_texture != null:
		draw_rect(Rect2(PROGRESS_RECT.position - Vector2(0, 1), PROGRESS_RECT.size + Vector2(0, 3)), Color(C_NAVY, 0.98))
	draw_rect(PROGRESS_RECT, Color(C_GOLD, 0.22))
	var fill_w := PROGRESS_RECT.size.x * _progress
	if fill_w > 0.0:
		var cyan_w := minf(fill_w, PROGRESS_RECT.size.x * 0.58)
		draw_rect(Rect2(PROGRESS_RECT.position, Vector2(cyan_w, PROGRESS_RECT.size.y)), Color(C_CYAN, 0.94))
		if fill_w > cyan_w:
			draw_rect(Rect2(PROGRESS_RECT.position + Vector2(cyan_w, 0), Vector2(fill_w - cyan_w, PROGRESS_RECT.size.y)), Color(C_GOLD_BRIGHT, 0.94))
		var tip := Vector2(PROGRESS_RECT.position.x + fill_w, PROGRESS_RECT.position.y + 1)
		var diamond := PackedVector2Array([
			tip + Vector2(0, -3), tip + Vector2(3, 0),
			tip + Vector2(0, 3), tip + Vector2(-3, 0),
		])
		draw_colored_polygon(diamond, C_GOLD_BRIGHT)

func _style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style
