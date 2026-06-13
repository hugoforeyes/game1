extends Node2D

# ── constants ──────────────────────────────────────────────────────────────────
const FONT_SIZE  := 7
const FADE_SPEED := 8.0
const SIDE_GAP   := 26.0   # screen px: player centre → arrow tip

# 3-slice cap height (game px). The top/bottom caps always render at this height;
# only the middle strip stretches to accommodate more items.
const CAP_H      := 10.0

# Left-pointing arrow drawn in code at the panel's vertical centre.
const ARROW_W    := 5.0
const ARROW_H    := 8.0
const IND_W      := 8.0
const IND_H      := 6.0

# Horizontal interior margins as fraction of the *panel body* width
# (measured from the 1389×220 texture, same on every slice row).
const INT_L_FRAC := 0.092
const INT_R_FRAC := 0.970

# Within each cap (100 px source), the dark interior starts/ends at these
# fractions of the cap source height. Used to compute text y-positions.
const CAP_TOP_INT_FRAC := 0.42   # interior starts 42 % into the top cap
const CAP_BOT_INT_FRAC := 0.58   # interior ends  58 % into the bottom cap

# Texture source regions (image is 1389 × 220)
const SRC_TOP := Rect2(0,   0, 1389, 100)   # top border cap
const SRC_MID := Rect2(0, 100, 1389,  20)   # stretchable dark interior strip
const SRC_BOT := Rect2(0, 120, 1389, 100)   # bottom border cap

const INNER_PAD  := Vector2(4.0, 2.0)
const LINE_GAP   := 1.5

const TITLE_COLOR    := Color(1.00, 0.85, 0.45, 1.00)
const TEXT_COLOR     := Color(0.93, 0.88, 0.75, 1.00)
const SELECT_BG      := Color(1.00, 0.85, 0.45, 0.18)
const INDICATOR_COL  := Color(1.00, 0.85, 0.45, 1.00)
const DIVIDER_COL    := Color(0.75, 0.58, 0.25, 0.45)
const ARROW_FILL     := Color(0.85, 0.65, 0.18, 1.00)
const ARROW_BORDER   := Color(1.00, 0.88, 0.50, 0.90)

# ── signals ───────────────────────────────────────────────────────────────────
signal item_confirmed(item: String, index: int)

# ── state ──────────────────────────────────────────────────────────────────────
var _target_alpha := 0.0
var _font         : Font
var _title        := ""
var _items        : Array[String] = []
var _selected     := 0
var _panel_w      := 0.0   # width of panel body (without ARROW_W)
var _panel_h      := 0.0   # total panel height
var _texture      : Texture2D = null
var _item_rects   : Array[Rect2] = []
var _world_node   : Node2D = null
var _world_offset : Vector2 = Vector2.ZERO

# ── lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	z_index    = 0
	_font      = ThemeDB.fallback_font
	modulate.a = 0.0
	_texture   = load("res://assets/ui/interaction_menu_panel.png") as Texture2D
	_build()

# ── public API ─────────────────────────────────────────────────────────────────
func setup_menu(title: String, items: Array[String]) -> void:
	_title    = title
	_items    = items
	_selected = 0
	_build()

func set_label(text: String) -> void:
	setup_menu(text, [])

func track(node: Node2D, offset: Vector2) -> void:
	_world_node   = node
	_world_offset = offset

func show_prompt() -> void:
	_target_alpha = 1.0

func hide_prompt() -> void:
	_target_alpha = 0.0

# ── input ──────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if _target_alpha < 0.5 or _items.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_selected = (_selected + 1) % _items.size()
				queue_redraw()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				item_confirmed.emit(_items[_selected], _selected)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := get_local_mouse_position()
		for i in range(_item_rects.size()):
			if _item_rects[i].has_point(local_pos):
				_selected = i
				queue_redraw()
				item_confirmed.emit(_items[_selected], _selected)
				get_viewport().set_input_as_handled()
				break

# ── process ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _world_node != null and is_instance_valid(_world_node):
		var screen_pos := get_viewport().get_canvas_transform() * _world_node.global_position
		# Arrow tip (local x = 0) sits SIDE_GAP px to the right of the player centre.
		# Panel is centred vertically so the arrow points at the player's mid-height.
		position.x = screen_pos.x + SIDE_GAP
		position.y = screen_pos.y + _world_offset.y - _panel_h * 0.5

	if absf(modulate.a - _target_alpha) < 0.004:
		modulate.a = _target_alpha
		return
	modulate.a = lerpf(modulate.a, _target_alpha, minf(delta * FADE_SPEED, 1.0))

# ── layout ─────────────────────────────────────────────────────────────────────
func _build() -> void:
	var line_h := _font.get_height(FONT_SIZE) + LINE_GAP
	var ind_w  := IND_W

	# Widest text (title or any item + indicator prefix)
	var max_tw := _font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	for item in _items:
		var tw := ind_w + _font.get_string_size(item, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		max_tw = maxf(max_tw, tw)

	var need_int_w := max_tw + INNER_PAD.x * 2.0
	var body_w := maxf(need_int_w / (INT_R_FRAC - INT_L_FRAC), 60.0)

	# Interior y-space needed:
	#   optional title row, optional divider+gap, N item rows, top+bottom inner padding
	var rows  := 1 if not _title.is_empty() else 0
	var div_h := 0.0
	if not _items.is_empty():
		rows  += _items.size()
		if not _title.is_empty():
			div_h = 3.0   # divider + 1 px gap each side

	var need_int_h := rows * line_h + div_h + INNER_PAD.y * 2.0

	# Interior available = mid_h + interior portions of both caps
	# cap interior fraction: CAP_TOP_INT_FRAC of CAP_H at top + CAP_BOT_INT_FRAC at bottom
	var cap_interior := (1.0 - CAP_TOP_INT_FRAC) * CAP_H + CAP_BOT_INT_FRAC * CAP_H
	var mid_h := maxf(need_int_h - cap_interior, 2.0)

	_panel_w = body_w
	_panel_h = CAP_H + mid_h + CAP_H

	# Compute item hit rects (same y logic as _draw)
	_item_rects.clear()
	if not _items.is_empty():
		var lh   := _font.get_height(FONT_SIZE) + LINE_GAP
		var base := CAP_TOP_INT_FRAC * CAP_H + INNER_PAD.y
		var iy   := base + (lh + 3.0 if not _title.is_empty() else 0.0)
		var rx   := ARROW_W
		for _i in range(_items.size()):
			_item_rects.append(Rect2(rx, iy - 1.0, ARROW_W + body_w - rx, lh + 1.0))
			iy += lh

	queue_redraw()

# ── drawing ────────────────────────────────────────────────────────────────────
func _draw() -> void:
	var px := ARROW_W          # panel body starts here in local x
	var pw := _panel_w
	var ph := _panel_h
	var mid_h := ph - CAP_H * 2.0

	# --- 3-slice panel texture ---
	if _texture != null:
		draw_texture_rect_region(_texture, Rect2(px, 0,              pw, CAP_H),  SRC_TOP)
		draw_texture_rect_region(_texture, Rect2(px, CAP_H,          pw, mid_h), SRC_MID)
		draw_texture_rect_region(_texture, Rect2(px, CAP_H + mid_h,  pw, CAP_H),  SRC_BOT)

	# --- left-pointing arrow ---
	var cy    := ph * 0.5
	var a_pts := PackedVector2Array([
		Vector2(0.0,          cy),
		Vector2(ARROW_W + 1.0, cy - ARROW_H * 0.5),
		Vector2(ARROW_W + 1.0, cy + ARROW_H * 0.5),
	])
	draw_colored_polygon(a_pts, ARROW_FILL)
	var a_border := a_pts.duplicate(); a_border.append(a_border[0])
	draw_polyline(a_border, ARROW_BORDER, 1.0)

	# --- text layout ---
	var line_h := _font.get_height(FONT_SIZE) + LINE_GAP
	var ascent := _font.get_ascent(FONT_SIZE)
	var ind_w  := IND_W

	# Interior origin
	var ix  := px + pw * INT_L_FRAC + INNER_PAD.x
	var irx := px + pw * INT_R_FRAC - INNER_PAD.x
	var iy  := CAP_TOP_INT_FRAC * CAP_H + INNER_PAD.y

	# Title (optional)
	if not _title.is_empty():
		draw_string(_font, Vector2(ix, iy + ascent), _title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TITLE_COLOR)
		iy += line_h

	if _items.is_empty():
		return

	# Divider (only when title exists)
	if not _title.is_empty():
		iy += 1.0
		draw_line(Vector2(ix, iy), Vector2(irx, iy), DIVIDER_COL, 0.5)
		iy += 2.0

	# Items
	for i in range(_items.size()):
		if i == _selected:
			draw_rect(Rect2(ix - 2.0, iy - 1.0, irx - ix + 4.0, line_h + 1.0), SELECT_BG)
			_draw_item_indicator(Vector2(ix + 1.0, iy + line_h * 0.5))
		draw_string(_font, Vector2(ix + ind_w, iy + ascent), _items[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		iy += line_h

func _draw_item_indicator(center: Vector2) -> void:
	var points := PackedVector2Array([
		Vector2(center.x, center.y - IND_H * 0.5),
		Vector2(center.x + IND_W - 2.0, center.y),
		Vector2(center.x, center.y + IND_H * 0.5),
	])
	draw_colored_polygon(points, INDICATOR_COL)
