class_name MinimapView
extends Control
## Chapter-wide minimap ("Bản Đồ Chương") — AAA art-directed, authored crisp in
## native 960×540, same visual family as QuestTrackerView/QuestJournalView (dark
## glass panel, gold filigree corners, jewel accents). MinimapManager owns the
## data (zone graph + visited state); this view is pure presentation.
##
## Progressive reveal: a zone only appears once it has been VISITED or is directly
## connected to a visited zone (fogged silhouette — "there is something here, but
## not what"). Zones with no visited neighbor are omitted entirely, matching how
## real exploration games only show the fringe of the explored map.

signal close_requested

const ORN_DIR := "res://assets/ui/quest_journal_v2/ornaments/"
const ICON_DIR := "res://assets/ui/minimap_v1/icons/"

const PANEL_W := 820.0
const PANEL_H := 496.0
const HEADER_H := 46.0
const FOOTER_H := 30.0
const SIDE_PAD := 26.0
const NODE_RADIUS := 21.0
const ICON_SIZE := 30.0

# ── Palette (shared with the journal/tracker) ────────────────────────────────
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
const C_BOSS_RING := Color(0.88, 0.28, 0.24, 0.90)

var _data: Dictionary = {}
var _pulse_tweens: Array[Tween] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5).round()
	size = Vector2(PANEL_W, PANEL_H)


func set_data(data: Dictionary) -> void:
	_data = data
	_rebuild()


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
	var visited: Dictionary = _data.get("visited_zone_ids", {}) as Dictionary
	var zones: Array = _data.get("zones", []) as Array
	var zones_by_id: Dictionary = {}
	for zone in zones:
		if zone is Dictionary:
			zones_by_id[str((zone as Dictionary).get("zone_id", ""))] = zone

	var known: Dictionary = _known_zone_ids(zones_by_id, visited)
	var points: Dictionary = {}  # zone_id -> Vector2 (screen position)
	for zone_id in known.keys():
		var zone: Dictionary = zones_by_id.get(zone_id, {}) as Dictionary
		var center: Dictionary = zone.get("center", {"x": 0.5, "y": 0.5}) as Dictionary
		var nx: float = clampf(float(center.get("x", 0.5)), 0.0, 1.0)
		var ny: float = clampf(float(center.get("y", 0.5)), 0.0, 1.0)
		points[zone_id] = map_rect.position + Vector2(nx * map_rect.size.x, ny * map_rect.size.y)

	_draw_connections(zones_by_id, known, visited, points)
	for zone_id in points.keys():
		_draw_zone_node(zones_by_id.get(zone_id, {}) as Dictionary, points[zone_id], bool(visited.get(zone_id, false)))

	var current_zone_id := str(_data.get("current_zone_id", ""))
	if points.has(current_zone_id):
		_draw_player_marker(points[current_zone_id])

	_footer(known.size(), zones_by_id.size())


## A zone is KNOWN (rendered, even if fogged) once it has been visited or sits
## directly next to a visited zone — the explored fringe of the map.
func _known_zone_ids(zones_by_id: Dictionary, visited: Dictionary) -> Dictionary:
	var known: Dictionary = {}
	for zone_id in zones_by_id.keys():
		if visited.get(zone_id, false):
			known[zone_id] = true
	for zone_id in zones_by_id.keys():
		if known.has(zone_id):
			continue
		var zone: Dictionary = zones_by_id[zone_id] as Dictionary
		for neighbor in (zone.get("connections", []) as Array):
			if visited.get(str(neighbor), false):
				known[zone_id] = true
				break
	return known


# ── frame / chrome ───────────────────────────────────────────────────────────


## A sunken "map surface" behind the zone graph — otherwise the graph floats on
## flat panel-black, which reads as empty menu space rather than a map. When the
## backend's chapter_map_illustration step produced a painted region image, that
## fills the viewport (cropped to cover, darkened for legibility) instead of the
## flat fill + procedural flecks.
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
		# TextureRect's stretch_mode/expand_mode combo proved unreliable for an
		# arbitrary source aspect ratio in practice (drew at native pixel size,
		# ignoring the assigned rect). Sidestep it entirely: crop AND resize the
		# source Image ourselves to the exact target pixel size, then draw the
		# result 1:1 — plus a belt-and-suspenders clip in case of any residual
		# rounding overflow.
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
		# Darken so the gold zone graph/labels stay legible over busy painted terrain.
		_add_rect(self, rect, Color(0.02, 0.024, 0.038, 0.40))
		# Panel's own border is now hidden under the art — redraw it on top.
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
		# A faint constellation of gold flecks gives the void some texture without
		# needing a painted background asset.
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242  # deterministic — stable across rebuilds/frames
		for _i in range(46):
			var pos := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
			_add_disc(self, pos, rng.randf_range(0.6, 1.4), Color(C_GOLD_DIM, rng.randf_range(0.06, 0.16)))


## Center-crops the source image to target_size's aspect ratio ("cover"
## semantics) and resizes it to that EXACT pixel size, computed ourselves
## rather than trusting TextureRect's stretch_mode/expand_mode combo (which
## in practice drew the source at native pixel size, ignoring the assigned
## rect, for a source aspect ratio that didn't match the target). Since the
## returned texture's native size already equals target_size, the caller can
## draw it 1:1 with no further scaling ambiguity.
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
	var title := _label("BẢN ĐỒ CHƯƠNG", 18, C_GOLD, Rect2(0, 10, PANEL_W, 26))
	var title_font := UiKit.title_font()
	if title_font != null:
		var variation := FontVariation.new()
		variation.base_font = title_font
		variation.variation_opentype = {"wght": 640}
		title.add_theme_font_override("font", variation)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	# Close hint, top-right.
	var hint := _label("M / Esc để đóng", 11, C_TEXT_DIM, Rect2(PANEL_W - SIDE_PAD - 140.0, 14, 140.0, 16))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)


func _footer(known_count: int, total_count: int) -> void:
	var text := "Đã khám phá %d / %d khu vực" % [known_count, maxi(total_count, known_count)]
	var label := _label(text, 12, C_TEXT_DIM, Rect2(0, PANEL_H - FOOTER_H + 4.0, PANEL_W, 18))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)


# ── map content ───────────────────────────────────────────────────────────────


func _draw_connections(zones_by_id: Dictionary, known: Dictionary, visited: Dictionary, points: Dictionary) -> void:
	var drawn: Dictionary = {}
	for zone_id in known.keys():
		var zone: Dictionary = zones_by_id.get(zone_id, {}) as Dictionary
		for raw_neighbor in (zone.get("connections", []) as Array):
			var neighbor := str(raw_neighbor)
			if not known.has(neighbor) or not points.has(zone_id) or not points.has(neighbor):
				continue
			var pair_key := "%s|%s" % [zone_id, neighbor] if zone_id < neighbor else "%s|%s" % [neighbor, zone_id]
			if drawn.has(pair_key):
				continue
			drawn[pair_key] = true
			var both_visited: bool = bool(visited.get(zone_id, false)) and bool(visited.get(neighbor, false))
			_dotted_path(points[zone_id], points[neighbor], both_visited)


func _dotted_path(from: Vector2, to: Vector2, lit: bool) -> void:
	var color: Color = C_LINE if lit else C_LINE_FOG
	var distance: float = from.distance_to(to)
	var step: float = 9.0
	var count: int = maxi(int(distance / step), 1)
	for i in range(count + 1):
		var t: float = float(i) / float(count)
		var pos: Vector2 = from.lerp(to, t)
		_add_disc(self, pos, 1.6 if lit else 1.2, color)


func _draw_zone_node(zone: Dictionary, pos: Vector2, visited: bool) -> void:
	var zone_type := str(zone.get("type", ""))
	var is_boss := zone_type == "boss_arena"
	var ring_color: Color = (C_BOSS_RING if (is_boss and visited) else C_GOLD) if visited else C_FOG_RING

	# Outer glow + ring.
	_add_disc(self, pos, NODE_RADIUS + 3.0, Color(ring_color, 0.16 if visited else 0.10))
	_add_disc(self, pos, NODE_RADIUS, Color(0.05, 0.045, 0.09, 0.92))
	_add_ring(self, pos, NODE_RADIUS, 2.0, ring_color)
	_add_ring(self, pos, NODE_RADIUS - 3.5, 1.0, Color(ring_color, 0.5))

	var icon_path: String = _icon_path(zone_type if visited else "locked")
	var icon_rect := Rect2(pos - Vector2(ICON_SIZE, ICON_SIZE) * 0.5, Vector2(ICON_SIZE, ICON_SIZE))
	add_child(_make_tex(icon_path, icon_rect, C_FOG_ICON if not visited else Color.WHITE))

	var label_text := str(zone.get("name", "")) if visited else "???"
	var label := _label(label_text, 11, C_TEXT if visited else C_TEXT_DIM, Rect2(pos.x - 60.0, pos.y + NODE_RADIUS + 3.0, 120.0, 16))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	add_child(label)


func _draw_player_marker(pos: Vector2) -> void:
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

	var ring := Control.new()
	ring.position = pos
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	_add_ring(ring, Vector2.ZERO, NODE_RADIUS + 2.0, 1.6, C_CYAN)
	var ring_tween := create_tween().set_loops()
	ring_tween.tween_property(ring, "modulate:a", 0.15, 0.9).set_trans(Tween.TRANS_SINE)
	ring_tween.tween_property(ring, "modulate:a", 0.85, 0.9).set_trans(Tween.TRANS_SINE)
	_pulse_tweens.append(ring_tween)


# ══════════════════════════════════════════════════════════════════════════════
# RESOLVERS / PRIMITIVES (mirrors QuestTrackerView.gd's conventions)
# ══════════════════════════════════════════════════════════════════════════════


func _icon_path(zone_type: String) -> String:
	var file_name: String = {
		"town": "zone_town.png",
		"dungeon": "zone_dungeon.png",
		"wilderness": "zone_wilderness.png",
		"boss_arena": "zone_boss_arena.png",
		"safe_zone": "zone_safe_zone.png",
		"secret": "zone_secret.png",
		"locked": "zone_locked.png",
	}.get(zone_type, "zone_locked.png")
	return ICON_DIR + file_name


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
	# Procedural fallback: a simple gold diamond glyph.
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
