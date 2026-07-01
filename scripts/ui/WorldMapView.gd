class_name WorldMapView
extends Control
## World map ("Bản Đồ Thế Giới") — the chapter-level sibling of MinimapView,
## same AAA dark-glass/gold-filigree family (native 960×540). Chapters are
## strictly linear (no branching graph like zones), so they're laid out as a
## gentle winding path — a classic world-map "chapter select" chain — rather
## than reusing the zone graph's authored-position projection.
##
## Unlike MinimapView (pure passive display), this screen is INTERACTIVE: the
## player can move a cursor between chapters and travel to any UNLOCKED one at
## will. WorldMapManager owns the data (chapter list + completion state) and
## listens for `travel_requested` to actually perform the jump — this view
## only asks for confirmation and reports the player's choice.

signal travel_requested(chapter_number: int)

const ORN_DIR := "res://assets/ui/quest_journal_v2/ornaments/"
const ICON_DIR := "res://assets/ui/minimap_v1/icons/"
const WORLD_ICON_DIR := "res://assets/ui/world_map_v1/icons/"

const PANEL_W := 820.0
const PANEL_H := 496.0
const HEADER_H := 46.0
const FOOTER_H := 36.0
const SIDE_PAD := 46.0
const NODE_RADIUS := 30.0
const ICON_SIZE := 30.0
const NUMERAL_FONT_SIZE := 22

# ── Palette (shared with the journal/tracker/minimap) ────────────────────────
const C_GLASS := Color(0.035, 0.046, 0.066, 0.95)
const C_GOLD := Color(0.99, 0.85, 0.48)
const C_GOLD_DIM := Color(0.76, 0.57, 0.28)
const C_GOLD_DEEP := Color(0.45, 0.33, 0.16)
const C_LINE := Color(0.70, 0.52, 0.25, 0.60)
const C_LINE_FOG := Color(0.55, 0.50, 0.62, 0.30)
const C_TEXT := Color(0.94, 0.90, 0.80)
const C_TEXT_DIM := Color(0.94, 0.90, 0.80, 0.55)
const C_CYAN := Color(0.56, 0.93, 0.96)
const C_FOG_RING := Color(0.42, 0.38, 0.55, 0.85)
const C_FOG_ICON := Color(0.62, 0.60, 0.72, 0.55)
const C_SELECT_RING := Color(0.56, 0.93, 0.96, 0.9)

var _data: Dictionary = {}
var _pulse_tweens: Array[Tween] = []
var _chapters: Array = []          # normalized chapter dicts, path order
var _selected_index: int = 0
var _confirm_pending: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	position = Vector2((960.0 - PANEL_W) * 0.5, (540.0 - PANEL_H) * 0.5).round()
	size = Vector2(PANEL_W, PANEL_H)


## data: {current_chapter_number:int, chapters:[{chapter_number,title}],
##        completed_chapter_numbers: Dictionary (String(n) -> true)}
func set_data(data: Dictionary) -> void:
	_data = data
	_chapters = (data.get("chapters", []) as Array).filter(func(c): return c is Dictionary)
	_confirm_pending = false
	var current_number := int(data.get("current_chapter_number", 1))
	_selected_index = 0
	for i in range(_chapters.size()):
		if int((_chapters[i] as Dictionary).get("chapter_number", -1)) == current_number:
			_selected_index = i
			break
	_rebuild()


func handle_input(event: InputEvent) -> bool:
	## Returns true if this view consumed the event (caller should mark it handled).
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	match (event as InputEventKey).physical_keycode:
		KEY_LEFT, KEY_A:
			_confirm_pending = false
			_selected_index = maxi(0, _selected_index - 1)
			_rebuild()
			return true
		KEY_RIGHT, KEY_D:
			_confirm_pending = false
			_selected_index = mini(_chapters.size() - 1, _selected_index + 1)
			_rebuild()
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_selected()
			return true
	return false


func _state_of(chapter_number: int) -> String:
	var current_number := int(_data.get("current_chapter_number", 1))
	var completed: Dictionary = _data.get("completed_chapter_numbers", {}) as Dictionary
	var is_completed := completed.has(str(chapter_number))
	if chapter_number == current_number:
		return "current_completed" if is_completed else "current"
	if is_completed:
		return "completed"
	# Chapter 1 is always reachable from the start; any later chapter needs its
	# predecessor completed first.
	if chapter_number == 1 or completed.has(str(chapter_number - 1)):
		return "available"
	return "locked"


func _activate_selected() -> void:
	if _selected_index < 0 or _selected_index >= _chapters.size():
		return
	var chapter: Dictionary = _chapters[_selected_index] as Dictionary
	var chapter_number := int(chapter.get("chapter_number", 0))
	var state := _state_of(chapter_number)
	if state == "locked":
		return  # not reachable yet — cursor can rest here, but nothing to confirm
	if state in ["current", "current_completed"]:
		return  # already here — Esc/Tab closes the map, no travel needed
	if not _confirm_pending:
		_confirm_pending = true
		_rebuild()
		return
	_confirm_pending = false
	travel_requested.emit(chapter_number)


# ══════════════════════════════════════════════════════════════════════════════
func _rebuild() -> void:
	for tween in _pulse_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_pulse_tweens.clear()
	for child in get_children():
		child.free()

	_glass_panel(Rect2(0, 0, PANEL_W, PANEL_H))
	_corners(Rect2(0, 0, PANEL_W, PANEL_H))
	_center_jewel(Vector2(PANEL_W * 0.5, 0.0))
	_center_jewel(Vector2(PANEL_W * 0.5, PANEL_H))
	_header()

	var map_rect := Rect2(
		SIDE_PAD, HEADER_H,
		PANEL_W - SIDE_PAD * 2.0, PANEL_H - HEADER_H - FOOTER_H,
	)
	_map_viewport(map_rect, _data.get("background_texture") as Texture2D)

	var points: Array[Vector2] = []
	for i in range(_chapters.size()):
		points.append(_chapter_position(i, _chapters.size(), map_rect))

	for i in range(1, _chapters.size()):
		var prev_number := int((_chapters[i - 1] as Dictionary).get("chapter_number", 0))
		var lit := _state_of(prev_number) in ["completed", "current_completed"]
		_dotted_path(points[i - 1], points[i], lit)

	for i in range(_chapters.size()):
		var chapter: Dictionary = _chapters[i] as Dictionary
		_draw_chapter_node(chapter, points[i], i == _selected_index)

	_footer()


## Uses the backend's LLM-vision-placed position (world_map_illustration) when
## the chapter has one — grounded in the actual painted terrain, not a guess.
## Any chapter without one (step never run, or the vision call missed it) falls
## back to this view's own procedural winding path, so a chapter is never left
## without a marker.
func _chapter_position(index: int, count: int, map_rect: Rect2) -> Vector2:
	var chapter: Dictionary = _chapters[index] as Dictionary
	if chapter.has("x_normalized") and chapter.has("y_normalized"):
		var nx: float = clampf(float(chapter.get("x_normalized", 0.5)), 0.0, 1.0)
		var ny: float = clampf(float(chapter.get("y_normalized", 0.5)), 0.0, 1.0)
		return map_rect.position + Vector2(nx * map_rect.size.x, ny * map_rect.size.y)
	if count <= 1:
		return map_rect.position + map_rect.size * 0.5
	var t: float = float(index) / float(count - 1)
	var x: float = map_rect.position.x + t * map_rect.size.x
	var wave: float = sin(t * PI * 1.6)
	var y: float = map_rect.position.y + map_rect.size.y * 0.5 + wave * (map_rect.size.y * 0.30)
	return Vector2(x, y)


# ── frame / chrome ───────────────────────────────────────────────────────────


func _map_viewport(rect: Rect2, background_texture: Texture2D) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.024, 0.038, 0.75)
	style.border_color = Color(C_GOLD_DIM, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	if background_texture != null:
		# See MinimapView._map_viewport's identical treatment for why this is done
		# ourselves in Image space rather than trusting TextureRect's stretch_mode.
		var clip := Control.new()
		clip.position = rect.position
		clip.size = rect.size
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(clip)
		var art := TextureRect.new()
		art.texture = _cropped_cover_texture(background_texture, rect.size)
		art.position = Vector2.ZERO
		art.size = rect.size
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(art)
		_add_rect(self, rect, Color(0.02, 0.024, 0.038, 0.40))
		var border := Panel.new()
		border.position = rect.position
		border.size = rect.size
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var border_style := StyleBoxFlat.new()
		border_style.bg_color = Color(0, 0, 0, 0)
		border_style.border_color = Color(C_GOLD_DIM, 0.35)
		border_style.set_border_width_all(1)
		border_style.set_corner_radius_all(3)
		border.add_theme_stylebox_override("panel", border_style)
		add_child(border)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7777  # deterministic — stable across rebuilds/frames
		for _i in range(52):
			var pos := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
			_add_disc(self, pos, rng.randf_range(0.6, 1.4), Color(C_GOLD_DIM, rng.randf_range(0.06, 0.16)))


## Center-crops the source image to target_size's aspect ratio ("cover"
## semantics) and resizes it to that EXACT pixel size — same technique as
## MinimapView._cropped_cover_texture, duplicated rather than imported (this
## codebase's established per-view convention for these small draw helpers).
func _cropped_cover_texture(source: Texture2D, target_size: Vector2) -> Texture2D:
	var source_image := source.get_image()
	if source_image == null:
		return source
	var src_w := source_image.get_width()
	var src_h := source_image.get_height()
	if src_w <= 0 or src_h <= 0 or target_size.x <= 0.0 or target_size.y <= 0.0:
		return source
	var target_aspect: float = target_size.x / target_size.y
	var src_aspect: float = float(src_w) / float(src_h)
	var crop_w := src_w
	var crop_h := src_h
	if src_aspect > target_aspect:
		crop_w = int(round(float(src_h) * target_aspect))
	else:
		crop_h = int(round(float(src_w) / target_aspect))
	crop_w = clampi(crop_w, 1, src_w)
	crop_h = clampi(crop_h, 1, src_h)
	var crop_x := int((src_w - crop_w) / 2)
	var crop_y := int((src_h - crop_h) / 2)
	var cropped := Image.create(crop_w, crop_h, false, source_image.get_format())
	cropped.blit_rect(source_image, Rect2i(crop_x, crop_y, crop_w, crop_h), Vector2i.ZERO)
	cropped.resize(int(round(target_size.x)), int(round(target_size.y)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(cropped)


func _header() -> void:
	_thin_divider(Vector2(SIDE_PAD, HEADER_H - 8.0), PANEL_W - SIDE_PAD * 2.0, C_LINE)
	var title := _label("BẢN ĐỒ THẾ GIỚI", 18, C_GOLD, Rect2(0, 10, PANEL_W, 26))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var hint := _label("Tab để quay lại · Esc để đóng", 11, C_TEXT_DIM, Rect2(PANEL_W - SIDE_PAD - 190.0, 14, 190.0, 16))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)


func _footer() -> void:
	var text := "←/→ để chọn · Enter để đến"
	var color := C_TEXT_DIM
	if _selected_index >= 0 and _selected_index < _chapters.size():
		var chapter: Dictionary = _chapters[_selected_index] as Dictionary
		var chapter_number := int(chapter.get("chapter_number", 0))
		var state := _state_of(chapter_number)
		if state == "locked":
			text = "Chương này chưa mở khoá — hoàn thành chương hiện tại trước"
		elif _confirm_pending:
			text = "Nhấn Enter lần nữa để đến Chương %d: %s" % [chapter_number, str(chapter.get("title", ""))]
			color = C_GOLD
	var label := _label(text, 12, color, Rect2(0, PANEL_H - FOOTER_H + 6.0, PANEL_W, 18))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


# ── map content ───────────────────────────────────────────────────────────────


func _dotted_path(from: Vector2, to: Vector2, lit: bool) -> void:
	var color: Color = C_LINE if lit else C_LINE_FOG
	var distance: float = from.distance_to(to)
	var step: float = 10.0
	var count: int = maxi(int(distance / step), 1)
	for i in range(count + 1):
		var t: float = float(i) / float(count)
		var pos: Vector2 = from.lerp(to, t)
		_add_disc(self, pos, 1.8 if lit else 1.3, color)


func _draw_chapter_node(chapter: Dictionary, pos: Vector2, selected: bool) -> void:
	var chapter_number := int(chapter.get("chapter_number", 0))
	var state := _state_of(chapter_number)
	var locked := state == "locked"
	var completed := state in ["completed", "current_completed"]
	var is_current := state in ["current", "current_completed"]
	var ring_color: Color = C_FOG_RING if locked else C_GOLD

	_add_disc(self, pos, NODE_RADIUS + 4.0, Color(ring_color, 0.10 if locked else 0.18))
	_add_disc(self, pos, NODE_RADIUS, Color(0.05, 0.045, 0.09, 0.92))
	_add_ring(self, pos, NODE_RADIUS, 2.2, ring_color)
	_add_ring(self, pos, NODE_RADIUS - 4.0, 1.0, Color(ring_color, 0.5))

	if locked:
		var icon_rect := Rect2(pos - Vector2(ICON_SIZE, ICON_SIZE) * 0.5, Vector2(ICON_SIZE, ICON_SIZE))
		add_child(_make_tex(ICON_DIR + "zone_locked.png", icon_rect, C_FOG_ICON))
	else:
		var numeral := _label(str(chapter_number), NUMERAL_FONT_SIZE, C_GOLD, Rect2(pos.x - NODE_RADIUS, pos.y - 16.0, NODE_RADIUS * 2.0, 32.0))
		numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(numeral)

	if completed:
		var badge_size := Vector2(20.0, 20.0)
		var badge_pos := pos + Vector2(NODE_RADIUS, -NODE_RADIUS) - badge_size * 0.5
		add_child(_make_tex(WORLD_ICON_DIR + "chapter_completed.png", Rect2(badge_pos, badge_size)))

	var label_text := ("???" if locked else str(chapter.get("title", ""))) as String
	var label := _label(label_text, 11, C_TEXT_DIM if locked else C_TEXT, Rect2(pos.x - 74.0, pos.y + NODE_RADIUS + 5.0, 148.0, 16))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	add_child(label)

	if is_current:
		_draw_here_marker(pos)
	if selected:
		var sel := Control.new()
		sel.position = pos
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sel)
		_add_ring(sel, Vector2.ZERO, NODE_RADIUS + 6.0, 1.8, C_SELECT_RING)
		var sel_tween := create_tween().set_loops()
		sel_tween.tween_property(sel, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
		sel_tween.tween_property(sel, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
		_pulse_tweens.append(sel_tween)


func _draw_here_marker(pos: Vector2) -> void:
	var marker_path := ICON_DIR + "player_marker.png"
	var marker_size := Vector2(22.0, 22.0)
	var holder := Control.new()
	holder.position = (pos - Vector2(0, NODE_RADIUS + 20.0)).round()
	holder.size = marker_size
	holder.pivot_offset = marker_size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	if _has(marker_path):
		var art := _make_path(marker_path, Rect2(Vector2.ZERO, marker_size))
		holder.add_child(art)
	else:
		_add_diamond(holder, marker_size * 0.5, marker_size.x * 0.5, C_CYAN)

	var pulse := create_tween().set_loops()
	pulse.tween_property(holder, "position:y", holder.position.y - 4.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(holder, "position:y", holder.position.y, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tweens.append(pulse)


# ══════════════════════════════════════════════════════════════════════════════
# RESOLVERS / PRIMITIVES (mirrors MinimapView.gd / QuestTrackerView.gd)
# ══════════════════════════════════════════════════════════════════════════════


func _glass_panel(rect: Rect2) -> void:
	_add_rect(self, Rect2(rect.position.x - 2, rect.position.y - 2, rect.size.x + 4, rect.size.y + 4), Color(0, 0, 0, 0.45))
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = C_GLASS
	style.border_color = Color(C_GOLD_DIM, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_add_gradient(self, Rect2(rect.position.x + 2, rect.position.y + 2, rect.size.x - 4, 28),
			Color(0.16, 0.20, 0.30, 0.35), Color(0.04, 0.05, 0.07, 0.0), true)
	_add_rect(self, Rect2(rect.position.x + 3, rect.position.y + 3, rect.size.x - 6, 1), Color(1.0, 0.85, 0.42, 0.18))


func _corners(rect: Rect2) -> void:
	if _has(ORN_DIR + "corner2_tl.png"):
		var cw := 30.0
		var ch := 24.0
		add_child(_corner_art(ORN_DIR + "corner2_tl.png", Rect2(rect.position.x - 3, rect.position.y - 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_tr.png", Rect2(rect.end.x - cw + 3, rect.position.y - 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_bl.png", Rect2(rect.position.x - 3, rect.end.y - ch + 3, cw, ch)))
		add_child(_corner_art(ORN_DIR + "corner2_br.png", Rect2(rect.end.x - cw + 3, rect.end.y - ch + 3, cw, ch)))
	elif _has(ORN_DIR + "corner_tl.png"):
		var cs := 26.0
		add_child(_corner_art(ORN_DIR + "corner_tl.png", Rect2(rect.position.x - 4, rect.position.y - 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_tr.png", Rect2(rect.end.x - cs + 4, rect.position.y - 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_bl.png", Rect2(rect.position.x - 4, rect.end.y - cs + 4, cs, cs)))
		add_child(_corner_art(ORN_DIR + "corner_br.png", Rect2(rect.end.x - cs + 4, rect.end.y - cs + 4, cs, cs)))


func _center_jewel(center: Vector2) -> void:
	_add_diamond(self, center, 6.0, C_GOLD_DEEP)
	_add_diamond(self, center, 4.6, C_GOLD)
	_add_diamond(self, center, 3.0, C_CYAN)
	_add_diamond(self, center, 1.6, Color(0.85, 0.95, 1.0))


func _thin_divider(pos: Vector2, width: float, color: Color) -> void:
	_add_rect(self, Rect2(pos.x, pos.y, width, 1), color)
	_add_rect(self, Rect2(pos.x, pos.y + 1, width, 1), Color(0, 0, 0, 0.3))


func _corner_art(path: String, rect: Rect2) -> TextureRect:
	var art := _make_path(path, rect)
	art.z_index = 20
	return art


func _make_tex(path: String, rect: Rect2, tint: Color = Color.WHITE) -> Control:
	if path != "" and _has(path):
		var art := _make_path(path, rect, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		art.modulate = tint
		return art
	var holder := Control.new()
	holder.position = rect.position
	holder.size = rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := rect.size * 0.5
	_add_diamond(holder, c, rect.size.x * 0.38, Color(tint, 0.85))
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


func _add_ring(parent: Control, center: Vector2, radius: float, thickness: float, color: Color) -> void:
	var line := Line2D.new()
	var pts := PackedVector2Array()
	for i in range(33):
		var a := TAU * float(i) / 32.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	line.points = pts
	line.width = thickness
	line.default_color = color
	line.antialiased = true
	parent.add_child(line)


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
