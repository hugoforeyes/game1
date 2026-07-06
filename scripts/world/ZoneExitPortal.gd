extends Area2D
## Decorative auto-transfer marker for edge zone exits.
## The player still moves by stepping into the exit; this script only upgrades
## the world-space portal and destination callout that replace the old rectangle.

signal exit_requested(leads_to: String, edge: String, normalized: float)

const FONT_PATH := "res://assets/fonts/BeVietnamPro-Regular.ttf"
const PANEL_SIZE := Vector2(336.0, 96.0)
const PANEL_MARGIN := 52.0
const PANEL_REVEAL_START_TILES := 4.6
const PANEL_REVEAL_FULL_TILES := 2.2

const GOLD := Color(1.0, 0.73, 0.28, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.91, 0.54, 1.0)
const GOLD_DIM := Color(0.88, 0.55, 0.22, 1.0)
const CYAN := Color(0.52, 0.94, 1.0, 1.0)
const PANEL_BG := Color(0.035, 0.039, 0.048, 0.95)
const PANEL_EDGE := Color(1.0, 0.74, 0.36, 0.78)
const TEXT_MAIN := Color(1.0, 0.91, 0.70, 1.0)
const TEXT_MUTED := Color(0.84, 0.69, 0.45, 0.92)

var _edge := ""
var _leads_to := ""
var _label_text := ""
var _normalized := 0.5
var _player: Node2D = null
var _time := 0.0
var _panel_alpha := 0.0
var _shape_size := Vector2.ZERO
var _font: Font = null


func setup(
	world_position: Vector2,
	edge: String,
	leads_to: String,
	normalized: float,
	label_text: String,
	player: Node2D
) -> void:
	global_position = world_position
	_edge = edge.to_lower()
	_leads_to = leads_to
	_normalized = normalized
	_label_text = label_text.strip_edges()
	_player = player
	name = "ZoneExitPortal"
	z_as_relative = false
	z_index = 18
	_build_collision()
	body_entered.connect(_on_body_entered)
	set_process(true)


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH) as Font
	if _font == null:
		_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	var target_alpha := _nearby_panel_alpha()
	_panel_alpha = lerpf(_panel_alpha, target_alpha, minf(delta * 5.0, 1.0))
	queue_redraw()


func _draw() -> void:
	_draw_portal_marker()
	if _panel_alpha > 0.02:
		_draw_destination_panel(_panel_alpha)


func _build_collision() -> void:
	var tile := float(GameManager.TILE_SIZE)
	var rect := RectangleShape2D.new()
	if _edge == "east" or _edge == "west":
		_shape_size = Vector2(tile * 1.2, tile * 3.0)
	else:
		_shape_size = Vector2(tile * 3.0, tile * 1.2)
	rect.size = _shape_size

	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)


func _nearby_panel_alpha() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var dist_tiles := _player.global_position.distance_to(global_position) / float(GameManager.TILE_SIZE)
	if dist_tiles >= PANEL_REVEAL_START_TILES:
		return 0.0
	if dist_tiles <= PANEL_REVEAL_FULL_TILES:
		return 1.0
	return 1.0 - ((dist_tiles - PANEL_REVEAL_FULL_TILES) / (PANEL_REVEAL_START_TILES - PANEL_REVEAL_FULL_TILES))


func _draw_portal_marker() -> void:
	var tile := float(GameManager.TILE_SIZE)
	var out := _edge_dir()
	var tangent := _tangent_dir()
	var angle := atan2(out.y, out.x)
	var center := -out * tile * 0.16
	var pulse := (sin(_time * 2.7) + 1.0) * 0.5
	var shimmer := (sin(_time * 4.1) + 1.0) * 0.5
	var radius := tile * 1.92

	draw_circle(center - out * tile * 0.22, radius * 0.72, _alpha(GOLD, 0.045 + pulse * 0.028))
	draw_circle(center + out * tile * 0.18, radius * 0.46, _alpha(GOLD_BRIGHT, 0.055 + shimmer * 0.032))

	draw_arc(center, radius, angle - PI * 0.54, angle + PI * 0.54, 64, _alpha(GOLD_BRIGHT, 0.68 + pulse * 0.18), 3.2, true)
	draw_arc(center + out * 4.0, radius + 13.0, angle - PI * 0.50, angle + PI * 0.50, 64, _alpha(CYAN, 0.38 + shimmer * 0.16), 2.0, true)
	draw_arc(center - out * 2.0, radius - 10.0, angle - PI * 0.48, angle + PI * 0.48, 52, _alpha(GOLD_DIM, 0.28), 1.0, true)

	for i in range(11):
		var u := float(i) / 10.0
		var arc_angle := lerpf(angle - PI * 0.50, angle + PI * 0.50, u)
		var sparkle_phase := fmod(_time * 1.8 + float(i) * 0.37, 1.0)
		var pos := center + Vector2(cos(arc_angle), sin(arc_angle)) * (radius + 3.0 + sin(_time * 3.0 + float(i)) * 3.0)
		_draw_spark(pos, 2.3 + sparkle_phase * 2.0, _alpha(GOLD_BRIGHT, 0.28 + sparkle_phase * 0.38))

	for i in range(4):
		var lane := float(i) - 1.5
		var travel := fmod(_time * 34.0 + float(i) * 18.0, tile * 1.2)
		var pos := center + out * (radius * 0.12 + travel) + tangent * lane * 15.0
		_draw_chevron(pos, out, 8.5 + pulse * 1.5, _alpha(GOLD_BRIGHT, 0.44 + pulse * 0.18))


func _draw_destination_panel(alpha: float) -> void:
	if _font == null:
		return

	var panel_rect := Rect2(_panel_position(), PANEL_SIZE)
	var anchor := _nearest_point(panel_rect, Vector2.ZERO)
	var connector_end := _edge_dir() * float(GameManager.TILE_SIZE) * 1.15

	draw_line(anchor, connector_end, _alpha(GOLD_BRIGHT, 0.34 * alpha), 1.4, true)
	draw_circle(anchor, 5.0, _alpha(Color(0.05, 0.04, 0.03, 1.0), 0.72 * alpha))
	draw_circle(anchor, 3.1, _alpha(GOLD_BRIGHT, 0.84 * alpha))
	draw_circle(connector_end, 4.6, _alpha(Color(0.05, 0.04, 0.03, 1.0), 0.62 * alpha))
	draw_circle(connector_end, 2.8, _alpha(GOLD_BRIGHT, 0.76 * alpha))

	var shadow_rect := panel_rect
	shadow_rect.position += Vector2(0.0, 5.0)
	draw_style_box(_style(Color(0, 0, 0, 0.42 * alpha), Color(0, 0, 0, 0), 0, 4), shadow_rect.grow(4.0))
	draw_style_box(_style(_alpha(PANEL_BG, alpha), _alpha(PANEL_EDGE, alpha), 1, 4), panel_rect)
	draw_style_box(_style(Color(0, 0, 0, 0), _alpha(GOLD_BRIGHT, 0.25 * alpha), 1, 2), panel_rect.grow(-3.0))

	_draw_panel_corners(panel_rect, alpha)
	_draw_panel_icon(panel_rect.position + Vector2(23.0, 19.0), alpha)

	var divider_x := panel_rect.position.x + 86.0
	draw_line(
		Vector2(divider_x, panel_rect.position.y + 18.0),
		Vector2(divider_x, panel_rect.end.y - 18.0),
		_alpha(GOLD_BRIGHT, 0.24 * alpha),
		1.0,
		true
	)

	var title := "Đi tới %s" % _destination_name()
	var title_size := 17
	var hint_size := 12
	var title_x := panel_rect.position.x + 105.0
	var title_max_w := panel_rect.size.x - 126.0
	var title_text := _fit_text(title, title_max_w, title_size)
	var hint_text := _fit_text("Bước vào để di chuyển", title_max_w, hint_size)
	var title_base := panel_rect.position.y + 40.0
	var hint_base := panel_rect.position.y + 66.0

	draw_string(_font, Vector2(title_x + 1.0, title_base + 1.0), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _alpha(Color(0, 0, 0, 0.78), alpha))
	draw_string(_font, Vector2(title_x, title_base), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, _alpha(TEXT_MAIN, alpha))
	draw_string(_font, Vector2(title_x + 1.0, hint_base + 1.0), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size, _alpha(Color(0, 0, 0, 0.62), alpha))
	draw_string(_font, Vector2(title_x, hint_base), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size, _alpha(TEXT_MUTED, alpha))


func _draw_panel_icon(origin: Vector2, alpha: float) -> void:
	var icon_rect := Rect2(origin, Vector2(48.0, 58.0))
	draw_style_box(_style(_alpha(Color(0.09, 0.08, 0.07, 0.72), alpha), _alpha(GOLD_BRIGHT, 0.18 * alpha), 1, 3), icon_rect)

	var center := icon_rect.position + icon_rect.size * 0.5 + Vector2(-1.0, 3.0)
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -24.0),
		center + Vector2(24.0, 0.0),
		center + Vector2(0.0, 24.0),
		center + Vector2(-24.0, 0.0),
	])
	draw_polygon(diamond, _solid_colors(_alpha(GOLD, 0.10 * alpha), diamond.size()))
	draw_polyline(PackedVector2Array([
		center + Vector2(-9.0, 19.0),
		center + Vector2(-3.0, 8.0),
		center + Vector2(-7.0, -3.0),
		center + Vector2(7.0, -19.0),
	]), _alpha(GOLD_BRIGHT, 0.82 * alpha), 4.0, true)
	draw_polyline(PackedVector2Array([
		center + Vector2(-10.0, 18.0),
		center + Vector2(-3.0, 8.0),
		center + Vector2(-7.0, -2.0),
		center + Vector2(7.0, -18.0),
	]), _alpha(Color(1.0, 0.48, 0.18, 1.0), 0.38 * alpha), 1.0, true)
	_draw_chevron(center + Vector2(5.0, -15.0), Vector2.RIGHT.rotated(-0.08), 12.0, _alpha(GOLD_BRIGHT, 0.95 * alpha))


func _draw_panel_corners(rect: Rect2, alpha: float) -> void:
	var len := 10.0
	var inset := 4.0
	var c := _alpha(GOLD_BRIGHT, 0.62 * alpha)
	var tl := rect.position + Vector2(inset, inset)
	var tr := rect.position + Vector2(rect.size.x - inset, inset)
	var bl := rect.position + Vector2(inset, rect.size.y - inset)
	var br := rect.position + rect.size - Vector2(inset, inset)
	draw_line(tl, tl + Vector2(len, 0), c, 1.0, true)
	draw_line(tl, tl + Vector2(0, len), c, 1.0, true)
	draw_line(tr, tr + Vector2(-len, 0), c, 1.0, true)
	draw_line(tr, tr + Vector2(0, len), c, 1.0, true)
	draw_line(bl, bl + Vector2(len, 0), c, 1.0, true)
	draw_line(bl, bl + Vector2(0, -len), c, 1.0, true)
	draw_line(br, br + Vector2(-len, 0), c, 1.0, true)
	draw_line(br, br + Vector2(0, -len), c, 1.0, true)


func _draw_chevron(center: Vector2, direction: Vector2, size: float, color: Color) -> void:
	var dir := direction.normalized()
	var tangent := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		center + dir * size,
		center - dir * size * 0.72 + tangent * size * 0.58,
		center - dir * size * 0.36,
		center - dir * size * 0.72 - tangent * size * 0.58,
	])
	draw_polygon(points, _solid_colors(color, points.size()))


func _draw_spark(center: Vector2, size: float, color: Color) -> void:
	draw_line(center + Vector2(-size, 0.0), center + Vector2(size, 0.0), color, 1.0, true)
	draw_line(center + Vector2(0.0, -size), center + Vector2(0.0, size), color, 1.0, true)
	draw_circle(center, maxf(1.0, size * 0.28), color)


func _panel_position() -> Vector2:
	match _edge:
		"east":
			return Vector2(-PANEL_SIZE.x - PANEL_MARGIN, -PANEL_SIZE.y - PANEL_MARGIN * 0.72)
		"west":
			return Vector2(PANEL_MARGIN, -PANEL_SIZE.y - PANEL_MARGIN * 0.72)
		"north":
			return Vector2(-PANEL_SIZE.x * 0.5, PANEL_MARGIN)
		"south":
			return Vector2(-PANEL_SIZE.x * 0.5, -PANEL_SIZE.y - PANEL_MARGIN)
	return Vector2(-PANEL_SIZE.x * 0.5, -PANEL_SIZE.y - PANEL_MARGIN)


func _destination_name() -> String:
	if _label_text.is_empty():
		return "khu vực mới"
	return _label_text


func _fit_text(text: String, max_w: float, font_size: int) -> String:
	if _font == null:
		return text
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var suffix := "..."
	var result := text
	while result.length() > 0:
		result = result.substr(0, result.length() - 1).strip_edges()
		var candidate := result + suffix
		if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return candidate
	return suffix


func _nearest_point(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


func _edge_dir() -> Vector2:
	match _edge:
		"east":
			return Vector2.RIGHT
		"west":
			return Vector2.LEFT
		"north":
			return Vector2.UP
		"south":
			return Vector2.DOWN
	return Vector2.RIGHT


func _tangent_dir() -> Vector2:
	var out := _edge_dir()
	return Vector2(-out.y, out.x)


func _on_body_entered(body: Node2D) -> void:
	if GameManager.ui_blocking_input:
		return
	if not _is_player_body(body):
		return
	exit_requested.emit(_leads_to, _edge, _normalized)


func _is_player_body(body: Node2D) -> bool:
	if _player != null and is_instance_valid(_player) and body == _player:
		return true
	return body != null and body.get("camera") != null


func _alpha(color: Color, alpha_scale: float) -> Color:
	var c := color
	c.a *= alpha_scale
	return c


func _solid_colors(color: Color, count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	for _i in range(count):
		colors.append(color)
	return colors


func _style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
