extends Node2D

signal item_confirmed(item: String, index: int)

const PANEL_LEFT_PATH := "res://assets/ui/interaction_prompt_v1/panel_left.png"
const PANEL_MIDDLE_PATH := "res://assets/ui/interaction_prompt_v1/panel_middle.png"
const PANEL_RIGHT_PATH := "res://assets/ui/interaction_prompt_v1/panel_right.png"

const HEIGHT := 34.0
const MIN_W := 108.0
const MAX_W := 292.0
const SIDE_GAP := 18.0
const EDGE_PAD := 12.0
const FONT_SIZE := 11
const FADE_SPEED := 12.0
const TEXT_PAD_X := 3.0
const CONTENT_LEFT := 25.0
const CONTENT_LEFT_FLIPPED := 30.0
const CONTENT_RIGHT := 14.0

const GOLD := Color(1.0, 0.76, 0.28, 1.0)
const GOLD_SOFT := Color(1.0, 0.86, 0.48, 0.64)
const TEXT := Color(0.96, 0.91, 0.80, 1.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.38)

var _font: Font = null
var _label := ""
var _display_label := ""
var _panel_w := MIN_W
var _target_alpha := 0.0
var _target_scale := 0.96
var _world_node: Node2D = null
var _world_offset := Vector2.ZERO
var _arrow_on_left := true
var _shine_t := 0.0
var _hovering := false
var _panel_left: Texture2D = null
var _panel_middle: Texture2D = null
var _panel_right: Texture2D = null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_panel_left = _load_texture(PANEL_LEFT_PATH)
	_panel_middle = _load_texture(PANEL_MIDDLE_PATH)
	_panel_right = _load_texture(PANEL_RIGHT_PATH)
	modulate.a = 0.0
	scale = Vector2.ONE * _target_scale
	set_process_unhandled_input(true)
	_build()


func _load_texture(texture_path: String) -> Texture2D:
	if ResourceLoader.exists(texture_path):
		var loaded := load(texture_path) as Texture2D
		if loaded != null:
			return loaded
	var image := Image.new()
	var path := ProjectSettings.globalize_path(texture_path)
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


func set_item(text: String, _kind: String = "object") -> void:
	_label = text.strip_edges()
	_build()


func track(node: Node2D, offset: Vector2 = Vector2.ZERO) -> void:
	_world_node = node
	_world_offset = offset


func show_prompt() -> void:
	_target_alpha = 1.0
	_target_scale = 1.0


func hide_prompt() -> void:
	_target_alpha = 0.0
	_target_scale = 0.96


func panel_size() -> Vector2:
	return Vector2(_panel_w, HEIGHT)


func _unhandled_input(event: InputEvent) -> void:
	if _target_alpha < 0.5:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER \
				or key_event.keycode == KEY_E or key_event.keycode == KEY_SPACE:
			item_confirmed.emit(_label, 0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if Rect2(Vector2.ZERO, panel_size()).has_point(get_local_mouse_position()):
			item_confirmed.emit(_label, 0)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_shine_t += delta
	if _world_node != null and is_instance_valid(_world_node):
		_update_tracked_position()

	var target := Vector2.ONE * _target_scale
	scale = scale.lerp(target, minf(delta * 10.0, 1.0))
	if absf(modulate.a - _target_alpha) < 0.003:
		modulate.a = _target_alpha
	else:
		modulate.a = lerpf(modulate.a, _target_alpha, minf(delta * FADE_SPEED, 1.0))

	var was_hovering := _hovering
	_hovering = Rect2(Vector2.ZERO, panel_size()).has_point(get_local_mouse_position())
	if was_hovering != _hovering:
		queue_redraw()


func _update_tracked_position() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var screen_pos := get_viewport().get_canvas_transform() * _world_node.global_position
	screen_pos += _world_offset
	var size := panel_size()

	var right_x := screen_pos.x + SIDE_GAP
	var y := clampf(screen_pos.y - size.y * 0.5, EDGE_PAD, maxf(EDGE_PAD, vp_size.y - size.y - EDGE_PAD))
	var old_arrow_on_left := _arrow_on_left
	if right_x + size.x <= vp_size.x - EDGE_PAD:
		_arrow_on_left = true
		position = Vector2(right_x, y)
	else:
		_arrow_on_left = false
		position = Vector2(clampf(screen_pos.x - SIDE_GAP - size.x, EDGE_PAD, vp_size.x - size.x - EDGE_PAD), y)
	if old_arrow_on_left != _arrow_on_left:
		_build()


func _build() -> void:
	if _font == null:
		return
	var text_w := _font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var desired_w := CONTENT_LEFT + TEXT_PAD_X + text_w + CONTENT_RIGHT
	_panel_w = clampf(desired_w, MIN_W, MAX_W)
	var content_left := CONTENT_LEFT if _arrow_on_left else CONTENT_LEFT_FLIPPED
	var available_w := maxf(12.0, _panel_w - content_left - TEXT_PAD_X - CONTENT_RIGHT)
	_display_label = _fit_text(_label, available_w)
	queue_redraw()


func _fit_text(text: String, max_w: float) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= max_w:
		return text
	var suffix := "..."
	var result := text
	while result.length() > 0:
		result = result.substr(0, result.length() - 1).strip_edges()
		var candidate := result + suffix
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x <= max_w:
			return candidate
	return suffix


func _draw() -> void:
	var panel_rect := Rect2(0.0, 0.0, _panel_w, HEIGHT)
	_draw_panel_frame(panel_rect)

	var glint_x := panel_rect.position.x + fmod(_shine_t * 48.0, maxf(1.0, panel_rect.size.x + 36.0)) - 36.0
	draw_rect(Rect2(glint_x, 5.0, 24.0, 1.0), Color(1.0, 0.92, 0.62, 0.10))

	var content_left := CONTENT_LEFT if _arrow_on_left else CONTENT_LEFT_FLIPPED
	var baseline := (HEIGHT + _font.get_ascent(FONT_SIZE) - _font.get_descent(FONT_SIZE)) * 0.5
	var text_x := panel_rect.position.x + content_left + TEXT_PAD_X
	draw_string(_font, Vector2(text_x + 1.0, baseline + 1.0), _display_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.62))
	draw_string(_font, Vector2(text_x, baseline), _display_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)


func _draw_panel_frame(rect: Rect2) -> void:
	if _panel_left == null or _panel_middle == null or _panel_right == null:
		draw_style_box(_style(Color(0.045, 0.052, 0.064, 0.94), GOLD_SOFT, 1, 8, SHADOW, Vector2(0, 4)), rect)
		draw_style_box(_style(Color(0, 0, 0, 0.0), GOLD, 1, 8), rect.grow(-2.0))
		return
	if _arrow_on_left:
		_draw_panel_slices(rect)
	else:
		draw_set_transform(Vector2(rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		_draw_panel_slices(rect)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_panel_slices(rect: Rect2) -> void:
	var dst_l := _texture_width_at_height(_panel_left, rect.size.y)
	var dst_r := _texture_width_at_height(_panel_right, rect.size.y)
	var dst_left := Rect2(rect.position, Vector2(dst_l, rect.size.y))
	var dst_mid := Rect2(rect.position + Vector2(dst_l, 0.0), Vector2(maxf(1.0, rect.size.x - dst_l - dst_r), rect.size.y))
	var dst_right := Rect2(rect.position + Vector2(rect.size.x - dst_r, 0.0), Vector2(dst_r, rect.size.y))
	draw_texture_rect(_panel_left, dst_left, false)
	draw_texture_rect(_panel_middle, dst_mid, false)
	draw_texture_rect(_panel_right, dst_right, false)


func _texture_width_at_height(texture: Texture2D, height: float) -> float:
	if texture == null:
		return 0.0
	var size := texture.get_size()
	if size.y <= 0.0:
		return 0.0
	return size.x * height / size.y


func _style(bg: Color, border: Color, border_width: int, radius: int, shadow_color: Color = Color(0, 0, 0, 0), shadow_offset: Vector2 = Vector2.ZERO) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = shadow_color
	style.shadow_offset = shadow_offset
	style.shadow_size = 10 if shadow_color.a > 0.0 else 0
	return style
