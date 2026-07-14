extends CanvasLayer
## Full-screen narrative/reward announcement. Quest-state updates use this
## ceremony everywhere; conversation rewards join the same queue. One view: a gold
## ribbon header, a filigree medallion (emblem or NPC portrait), radiating
## light, a big serif title, a gem divider, a subtitle and an "Enter — Tiếp tục"
## chip, per the announce_v1 mockup. Kinds: new_quest / objective /
## quest_complete / hint / companion.
##
## Authored crisp in native 1024x576 (unscaled layer). present(payload) plays
## the entrance; Enter/Space/click (after a short grace) fades out and emits
## `dismissed`, then the view frees itself.

signal dismissed

const KIT_DIR := "res://assets/ui/announce_v1/"
const INPUT_GRACE := 0.45
const SUBTITLE_SIZE := Vector2(660.0, 62.0)
const SUBTITLE_MAX_FONT := 14
const SUBTITLE_MIN_FONT := 9

const HEADERS := {
	"new_quest": "NHIỆM VỤ MỚI",
	"objective": "MỤC TIÊU MỚI",
	"quest_complete": "HOÀN THÀNH NHIỆM VỤ",
	"hint": "GỢI Ý MỚI",
	"companion": "ĐỒNG ĐỘI MỚI",
}
const EMBLEMS := {
	"new_quest": "emblem_scroll.png",
	"objective": "emblem_star.png",
	"quest_complete": "emblem_laurel.png",
	"hint": "emblem_lantern.png",
	"companion": "emblem_star.png",
}

var _root: Control
var _dim: ColorRect
var _ribbon_group: Control
var _medallion_group: Control
var _rays: Control
var _title_label: Label
var _divider_group: Control
var _subtitle_label: Label
var _meta_label: Label
var _chip: Panel
var _sparkles: CPUParticles2D
var _accent := UiKit.COLOR_ACCENT
var _can_dismiss := false
var _closing := false


## Slowly rotating tapered light rays, drawn additively behind the medallion.
class RayBurst extends Control:
	var color := Color(1.0, 0.86, 0.5, 0.10)
	var ray_count := 12
	var length := 215.0
	var _rot := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = mat

	func _process(delta: float) -> void:
		_rot += delta * 0.10
		queue_redraw()

	func _draw() -> void:
		for i in range(ray_count):
			var angle := TAU * float(i) / float(ray_count) + _rot
			var half_w := 0.055 + 0.03 * float(i % 2)
			var ray_len := length * (0.72 if i % 2 == 0 else 1.0)
			var points := PackedVector2Array([
				Vector2.ZERO,
				Vector2.from_angle(angle - half_w) * ray_len,
				Vector2.from_angle(angle + half_w) * ray_len,
			])
			draw_colored_polygon(points, color)


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS


func present(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", "new_quest"))
	if kind == "hint":
		_accent = UiKit.COLOR_CYAN
	_build(kind, payload)
	_animate_in()
	get_tree().create_timer(INPUT_GRACE).timeout.connect(func() -> void: _can_dismiss = true)


# ── content ─────────────────────────────────────────────────────────────────────


func _content_for(kind: String, payload: Dictionary) -> Dictionary:
	var quest: Dictionary = payload.get("quest", {}) as Dictionary
	match kind:
		"new_quest":
			var quest_type := str(quest.get("type", "main"))
			return {
				"title": str(quest.get("title", "Nhiệm vụ mới")),
				"subtitle": "Một hành trình mới đã bắt đầu.",
				"meta": "Nhiệm vụ chính" if quest_type == "main" else "Nhiệm vụ phụ",
			}
		"objective":
			var objective: Dictionary = payload.get("objective", {}) as Dictionary
			var meta := ""
			if objective.has("count"):
				meta = "%d / %d" % [int(payload.get("progress", 0)), maxi(1, int(objective.get("count", 1)))]
			return {
				"title": str(objective.get("description", "Mục tiêu mới")),
				"subtitle": _objective_narrative_lead_in(payload, objective),
				"meta": meta,
			}
		"quest_complete":
			var xp := int((quest.get("reward", {}) as Dictionary).get("xp", 0))
			return {
				"title": str(quest.get("title", "Nhiệm vụ")),
				"subtitle": "Nhiệm vụ đã hoàn thành xuất sắc.",
				"meta": "+%d KN cho cả đội" % xp if xp > 0 else "",
			}
		"hint":
			var hint: Dictionary = payload.get("hint", {}) as Dictionary
			var level := clampi(int(hint.get("level", 1)), 1, 3)
			return {
				"title": "Từ %s" % str(hint.get("npc_name", "NPC")),
				"subtitle": str(hint.get("text", "")),
				"meta": "Gợi ý %s / III" % ["I", "II", "III"][level - 1],
				"portrait": hint.get("portrait"),
			}
		_:  # companion
			var role := str(payload.get("role", "")).strip_edges()
			return {
				"title": str(payload.get("name", "")),
				"subtitle": ("%s · đã gia nhập đội!" % role) if not role.is_empty() else "đã gia nhập đội!",
				"meta": "",
				"portrait": payload.get("portrait"),
			}


func _objective_narrative_lead_in(payload: Dictionary, objective: Dictionary) -> String:
	# `narrative_lead_in` is the authored connective tissue leading into THIS
	# objective. Legacy aliases make old/imported runs degrade gracefully without
	# ever restoring the quest-name subtitle the new contract replaces.
	var candidates: Array = [
		objective.get("narrative_lead_in", ""),
		payload.get("narrative_lead_in", ""),
		objective.get("lead_in", ""),
	]
	for candidate in candidates:
		var text := str(candidate).strip_edges()
		if not text.is_empty():
			return text

	# Compatibility fallback for content produced before narrative_lead_in existed.
	# A cutscene already supplied the dramatic context, so its fallback is a short
	# hand-off rather than a second recap; the objective ceremony itself still plays.
	var delivery_mode := str(objective.get(
		"delivery_mode", payload.get("delivery_mode", "narration")
	)).strip_edges().to_lower()
	if delivery_mode == "cutscene":
		return "Sau diễn biến vừa rồi, bước tiếp theo đã trở nên rõ ràng."
	return "Một hướng đi mới vừa mở ra trên hành trình."


func _fit_subtitle_font(text: String) -> int:
	if text.strip_edges().is_empty():
		return SUBTITLE_MAX_FONT
	var font: Font = UiKit.body_font()
	if font == null:
		font = ThemeDB.fallback_font
	for candidate in range(SUBTITLE_MAX_FONT, SUBTITLE_MIN_FONT - 1, -1):
		var measured := _measure_subtitle(font, text, candidate)
		var four_line_height := font.get_height(candidate) * 4.0
		if measured.x <= SUBTITLE_SIZE.x + 0.5 \
				and measured.y <= minf(SUBTITLE_SIZE.y, four_line_height + 0.5):
			return candidate
	return SUBTITLE_MIN_FONT


func _measure_subtitle(font: Font, text: String, font_size: int) -> Vector2:
	return font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		SUBTITLE_SIZE.x,
		font_size,
		-1,
		TextServer.BREAK_MANDATORY \
			| TextServer.BREAK_WORD_BOUND \
			| TextServer.BREAK_GRAPHEME_BOUND,
	)


# ── construction ────────────────────────────────────────────────────────────────


func _build(kind: String, payload: Dictionary) -> void:
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x * 0.5
	var content := _content_for(kind, payload)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.008, 0.010, 0.028, 0.80)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	var medallion_center := Vector2(cx, 252.0)

	# light: soft radial glow + rotating rays, both additive, behind everything
	var glow := _radial_glow(Color(_accent.r, _accent.g, _accent.b, 0.34), 460)
	glow.position = medallion_center - glow.size * 0.5
	_root.add_child(glow)

	_rays = RayBurst.new()
	_rays.color = Color(_accent.r, _accent.g, _accent.b, 0.085)
	_rays.position = medallion_center
	_root.add_child(_rays)

	_build_ribbon(cx, str(HEADERS.get(kind, "THÔNG BÁO")))
	_build_medallion(medallion_center, kind, content)

	# ── title ──
	var title_text := str(content.get("title", ""))
	_title_label = UiKit.make_title(title_text, 34, _accent)
	_fit_title(_title_label, title_text, 840.0, 34, 20)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(cx - 420.0, 352.0)
	_title_label.size = Vector2(840.0, 44.0)
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(_title_label)

	_build_divider(Vector2(cx, 412.0))

	# ── subtitle (authored narrative lead-in, up to four fitted lines) ──
	var subtitle_text := str(content.get("subtitle", ""))
	var subtitle_font_size := _fit_subtitle_font(subtitle_text)
	_subtitle_label = UiKit.make_label(subtitle_text, subtitle_font_size, Color(0.93, 0.89, 0.78, 0.88))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.position = Vector2(cx - 330.0, 428.0)
	_subtitle_label.size = SUBTITLE_SIZE
	_subtitle_label.max_lines_visible = 4
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	_root.add_child(_subtitle_label)

	# ── meta chip line (quest type / +XP / progress / hint level) ──
	var meta_text := str(content.get("meta", ""))
	if not meta_text.is_empty():
		_meta_label = UiKit.make_label_strong(meta_text, 13, _accent)
		_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_meta_label.position = Vector2(cx - 200.0, 494.0)
		_meta_label.size = Vector2(400.0, 18.0)
		_root.add_child(_meta_label)

	_build_chip(Vector2(cx, 540.0))

	_sparkles = CPUParticles2D.new()
	_sparkles.position = medallion_center
	_sparkles.amount = 30
	_sparkles.lifetime = 1.6
	_sparkles.preprocess = 0.4
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparkles.emission_sphere_radius = 130.0
	_sparkles.direction = Vector2(0, -1)
	_sparkles.spread = 60.0
	_sparkles.gravity = Vector2(0, -16)
	_sparkles.initial_velocity_min = 6.0
	_sparkles.initial_velocity_max = 24.0
	_sparkles.scale_amount_min = 0.8
	_sparkles.scale_amount_max = 2.2
	_sparkles.color = Color(_accent.r, _accent.g, _accent.b, 0.85)
	_root.add_child(_sparkles)


func _build_ribbon(cx: float, header_text: String) -> void:
	_ribbon_group = Control.new()
	_ribbon_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ribbon_group)

	var ribbon_w := 560.0
	var ribbon_tex := _kit_tex("ribbon_banner.png")
	var ribbon_h := 158.0
	if ribbon_tex != null:
		ribbon_h = ribbon_w * float(ribbon_tex.get_height()) / float(ribbon_tex.get_width())
		var ribbon := TextureRect.new()
		ribbon.texture = ribbon_tex
		ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon.stretch_mode = TextureRect.STRETCH_SCALE
		ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ribbon.position = Vector2(cx - ribbon_w * 0.5, 26.0)
		ribbon.size = Vector2(ribbon_w, ribbon_h)
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ribbon_group.add_child(ribbon)
	else:
		var plaque := Panel.new()
		plaque.position = Vector2(cx - 220.0, 44.0)
		plaque.size = Vector2(440.0, 54.0)
		plaque.add_theme_stylebox_override("panel", UiKit.frame_style(6.0))
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ribbon_group.add_child(plaque)

	# engraved caps centered on the ribbon's flat band
	var header := UiKit.make_label_strong(header_text, 21, Color(0.26, 0.16, 0.04, 1.0))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_shadow_color", Color(1.0, 0.93, 0.62, 0.42))
	header.add_theme_constant_override("shadow_offset_x", 0)
	header.add_theme_constant_override("shadow_offset_y", 1)
	header.position = Vector2(cx - 220.0, 26.0 + ribbon_h * 0.30)
	header.size = Vector2(440.0, ribbon_h * 0.34)
	_ribbon_group.add_child(header)


func _build_medallion(center: Vector2, kind: String, content: Dictionary) -> void:
	_medallion_group = Control.new()
	_medallion_group.position = center
	_medallion_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_medallion_group)

	var ring_h := 168.0
	var ring_tex := _kit_tex("medallion_ring.png")
	var ring_w := ring_h if ring_tex == null else ring_h * float(ring_tex.get_width()) / float(ring_tex.get_height())

	# navy enamel disc filling the ring's hole
	var disc_d := ring_h * 0.76
	var disc := Panel.new()
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(0.045, 0.065, 0.15, 1.0)
	disc_style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.30)
	disc_style.set_border_width_all(1)
	disc_style.set_corner_radius_all(int(disc_d * 0.5))
	disc.add_theme_stylebox_override("panel", disc_style)
	disc.position = Vector2(-disc_d * 0.5, -disc_d * 0.5)
	disc.size = Vector2(disc_d, disc_d)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medallion_group.add_child(disc)

	# emblem or circle-cropped portrait inside the disc
	var portrait := content.get("portrait") as Texture2D
	var center_tex: Texture2D = null
	var center_px := 0.0
	if portrait != null:
		center_tex = _circle_cropped(portrait, 236)
		center_px = disc_d - 6.0
	if center_tex == null:
		center_tex = _kit_tex(str(EMBLEMS.get(kind, "emblem_star.png")))
		center_px = ring_h * 0.52
	if center_tex == null:
		center_tex = UiKit.kit_texture("crest_gold.png" if _accent == UiKit.COLOR_ACCENT else "crest_cyan.png")
		center_px = ring_h * 0.52
	if center_tex != null:
		var emblem := TextureRect.new()
		emblem.texture = center_tex
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		emblem.position = Vector2(-center_px * 0.5, -center_px * 0.5)
		emblem.size = Vector2(center_px, center_px)
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_medallion_group.add_child(emblem)

	if ring_tex != null:
		var ring := TextureRect.new()
		ring.texture = ring_tex
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ring.position = Vector2(-ring_w * 0.5, -ring_h * 0.5)
		ring.size = Vector2(ring_w, ring_h)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_medallion_group.add_child(ring)


func _build_divider(center: Vector2) -> void:
	_divider_group = Control.new()
	_divider_group.position = center
	_divider_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_divider_group)

	var divider_tex := UiKit.kit_texture("divider.png")
	if divider_tex != null:
		var divider := TextureRect.new()
		divider.texture = divider_tex
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_SCALE
		divider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		divider.position = Vector2(-140.0, -9.0)
		divider.size = Vector2(280.0, 18.0)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_divider_group.add_child(divider)
		return
	for side in [-1.0, 1.0]:
		var line := ColorRect.new()
		line.color = Color(_accent.r, _accent.g, _accent.b, 0.45)
		line.position = Vector2(14.0 if side > 0 else -140.0, -0.5)
		line.size = Vector2(126.0, 1.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_divider_group.add_child(line)
	var gem := UiKit.make_edge_jewel(Vector2.ZERO, 14.0)
	_divider_group.add_child(gem)


func _build_chip(center: Vector2) -> void:
	_chip = Panel.new()
	_chip.size = Vector2(204.0, 32.0)
	_chip.position = center - _chip.size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.030, 0.045, 0.095, 0.85)
	style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	_chip.add_theme_stylebox_override("panel", style)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chip)

	var label := UiKit.make_label_strong("Enter — Tiếp tục", 12, Color(0.93, 0.89, 0.78, 0.92))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chip.add_child(label)


# ── animation ───────────────────────────────────────────────────────────────────


func _animate_in() -> void:
	var faders: Array[CanvasItem] = [_dim, _rays, _title_label, _divider_group, _subtitle_label, _chip]
	if _meta_label != null:
		faders.append(_meta_label)
	for node in faders:
		if node != null:
			node.modulate.a = 0.0

	create_tween().tween_property(_dim, "modulate:a", 1.0, 0.22)

	# ribbon drops in with a slight overshoot
	_ribbon_group.modulate.a = 0.0
	_ribbon_group.position.y = -34.0
	var ribbon_tween := create_tween()
	ribbon_tween.tween_interval(0.05)
	ribbon_tween.tween_property(_ribbon_group, "modulate:a", 1.0, 0.20)
	ribbon_tween.parallel().tween_property(_ribbon_group, "position:y", 0.0, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# medallion blooms + light comes up
	_medallion_group.scale = Vector2(0.55, 0.55)
	_medallion_group.modulate.a = 0.0
	var medallion_tween := create_tween()
	medallion_tween.tween_interval(0.12)
	medallion_tween.tween_property(_medallion_group, "modulate:a", 1.0, 0.20)
	medallion_tween.parallel().tween_property(_medallion_group, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	medallion_tween.parallel().tween_property(_rays, "modulate:a", 1.0, 0.5)

	# text block rises in, staggered
	var title_y := _title_label.position.y
	_title_label.position.y = title_y + 16.0
	var text_tween := create_tween()
	text_tween.tween_interval(0.26)
	text_tween.tween_property(_title_label, "modulate:a", 1.0, 0.24)
	text_tween.parallel().tween_property(_title_label, "position:y", title_y, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_divider_group.scale = Vector2(0.2, 1.0)
	var divider_tween := create_tween()
	divider_tween.tween_interval(0.36)
	divider_tween.tween_property(_divider_group, "modulate:a", 1.0, 0.20)
	divider_tween.parallel().tween_property(_divider_group, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var subtitle_tween := create_tween()
	subtitle_tween.tween_interval(0.44)
	subtitle_tween.tween_property(_subtitle_label, "modulate:a", 1.0, 0.24)
	if _meta_label != null:
		subtitle_tween.parallel().tween_property(_meta_label, "modulate:a", 1.0, 0.24)

	# the Enter chip appears last, then pulses forever
	var chip_tween := create_tween()
	chip_tween.tween_interval(0.58)
	chip_tween.tween_property(_chip, "modulate:a", 1.0, 0.22)
	chip_tween.tween_callback(func() -> void:
		var pulse := create_tween().set_loops()
		pulse.tween_property(_chip, "modulate:a", 0.62, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_chip, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	)


func _dismiss() -> void:
	if _closing:
		return
	_closing = true
	if _sparkles != null:
		_sparkles.emitting = false
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.16)
	tween.parallel().tween_property(_medallion_group, "scale", Vector2(1.06, 1.06), 0.16)
	tween.tween_callback(func() -> void:
		dismissed.emit()
		queue_free()
	)


# ── input ───────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not _can_dismiss:
		return
	var confirm := event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		confirm = true
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		confirm = true
	if confirm:
		_dismiss()
		get_viewport().set_input_as_handled()


# ── helpers ─────────────────────────────────────────────────────────────────────


func _kit_tex(file_name: String) -> Texture2D:
	var path := KIT_DIR + file_name
	return load(path) if ResourceLoader.exists(path) else null


## Shrink the ornate title until it fits one centered line of `max_w`.
func _fit_title(label: Label, text: String, max_w: float, start_size: int, min_size: int) -> void:
	var font := UiKit.title_font()
	if font == null:
		font = ThemeDB.fallback_font
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_opentype = {"wght": 640}
	var font_size := start_size
	while font_size > min_size \
			and variation.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > max_w - 16.0:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func _radial_glow(color: Color, size_px: int) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = Vector2(size_px, size_px)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Circle-crop a portrait in Image space (frames/atlases stay reliable; the
## KEEP_ASPECT_COVERED TextureRect path is a known trap). Center square crop
## with a slight upward face bias, hard circle mask with a 1.5px soft edge.
func _circle_cropped(texture: Texture2D, out_px: int) -> Texture2D:
	var image := _texture_image(texture)
	if image == null:
		return null
	var side := mini(image.get_width(), image.get_height())
	var sx := int((image.get_width() - side) * 0.5)
	var sy := int((image.get_height() - side) * 0.30)
	image = image.get_region(Rect2i(sx, sy, side, side))
	image.resize(out_px, out_px, Image.INTERPOLATE_LANCZOS)
	var radius := out_px * 0.5
	var center := Vector2(radius, radius)
	for y in range(out_px):
		for x in range(out_px):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if dist > radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif dist > radius - 1.5:
				var pixel := image.get_pixel(x, y)
				pixel.a *= (radius - dist) / 1.5
				image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)


func _texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		if atlas.atlas == null:
			return null
		var base_image := atlas.atlas.get_image()
		if base_image == null:
			return null
		if base_image.is_compressed():
			base_image.decompress()
		base_image.convert(Image.FORMAT_RGBA8)
		return base_image.get_region(Rect2i(atlas.region))
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
