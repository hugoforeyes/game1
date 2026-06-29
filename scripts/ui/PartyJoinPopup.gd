extends CanvasLayer
## A celebratory "new party member" popup. When a companion joins, this slides in a
## framed portrait + name + role and "đã gia nhập đội", holds, then slides out and
## frees itself. Non-blocking (the player keeps control). Authored crisp in native
## 960x540 to match the dialogue_v2 art kit.

const PANEL_TEX := "res://assets/ui/dialogue_v2/dialogue_panel.png"
const GEM_TEX := "res://assets/ui/dialogue_v2/divider_gem.png"
const FRAME_TEX := "res://assets/ui/dialogue_v2/portrait_frame.png"

const CARD := Rect2(266, 66, 428, 152)
const HOLD_SECONDS := 3.0

var _root: Control
var _card: Panel


func _ready() -> void:
	layer = 58  # above the HUD, below blocking modals
	process_mode = Node.PROCESS_MODE_ALWAYS


# data: { name, role, portrait: Texture2D }
func show_member(data: Dictionary) -> void:
	_build(data)
	# entrance: drop in from above + fade + gentle overshoot
	_root.modulate.a = 0.0
	_card.position.y = CARD.position.y - 26.0
	_card.pivot_offset = CARD.size * 0.5
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.22)
	tween.parallel().tween_property(_card, "position:y", CARD.position.y, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(_card, "position:y", CARD.position.y - 22.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _build(data: Dictionary) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_card = Panel.new()
	_card.position = CARD.position
	_card.size = CARD.size
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_tex := _tex(PANEL_TEX)
	if panel_tex != null:
		var style := StyleBoxTexture.new()
		style.texture = panel_tex
		style.set_texture_margin_all(42.0)
		_card.add_theme_stylebox_override("panel", style)
	else:
		_card.add_theme_stylebox_override("panel", _glass_style())
	_root.add_child(_card)

	# ── soft golden glow hugging the portrait ──
	var beam := _radial_glow(Color(1.0, 0.88, 0.5, 0.5))
	beam.size = Vector2(132, 132)
	beam.position = Vector2(11, 10)
	_card.add_child(beam)

	# ── portrait, framed, left ──
	var portrait_box := Rect2(22, 21, 110, 110)
	var portrait: Texture2D = data.get("portrait") as Texture2D
	if portrait != null:
		var pr := TextureRect.new()
		pr.texture = portrait
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pr.position = portrait_box.position + Vector2(8, 8)
		pr.size = portrait_box.size - Vector2(16, 16)
		pr.clip_contents = true
		_card.add_child(pr)
	var frame := _tex(FRAME_TEX)
	if frame != null:
		var fr := TextureRect.new()
		fr.texture = frame
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fr.position = portrait_box.position
		fr.size = portrait_box.size
		_card.add_child(fr)

	# ── gem ornament, top center ──
	var gem := _tex(GEM_TEX)
	if gem != null:
		var gem_rect := TextureRect.new()
		gem_rect.texture = gem
		gem_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem_rect.position = Vector2(CARD.size.x * 0.5 - 24, -14)
		gem_rect.size = Vector2(48, 30)
		_card.add_child(gem_rect)

	# ── text block, CENTERED in the area right of the portrait ──
	var text_x := 144.0
	var text_w := CARD.size.x - text_x - 22.0
	var text_cx := text_x + text_w * 0.5

	var header := UiKit.make_label("ĐỒNG ĐỘI MỚI", 12, UiKit.COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(text_x, 26)
	header.size = Vector2(text_w, 16)
	_card.add_child(header)
	_add_header_flourishes(text_cx, 34.0, "ĐỒNG ĐỘI MỚI", 12)

	var name_label := UiKit.make_label(str(data.get("name", "")), 26, UiKit.COLOR_ACCENT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(text_x, 48)
	name_label.size = Vector2(text_w, 38)
	name_label.clip_text = true
	_card.add_child(name_label)

	var role := str(data.get("role", "")).strip_edges()
	var subtitle := "đã gia nhập đội!" if role.is_empty() else "%s · đã gia nhập đội!" % role
	var sub_label := UiKit.make_label(subtitle, 13, Color(0.93, 0.88, 0.75, 0.92))
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.position = Vector2(text_x, 96)
	sub_label.size = Vector2(text_w, 32)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(sub_label)


func _add_header_flourishes(center_x: float, center_y: float, header_text: String, font_size: int) -> void:
	# small gold diamonds flanking the header, like the mockup
	var font := ThemeDB.fallback_font
	var half := font.get_string_size(header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	for sign in [-1.0, 1.0]:
		var diamond := ColorRect.new()
		diamond.color = UiKit.COLOR_ACCENT
		diamond.size = Vector2(5, 5)
		diamond.pivot_offset = Vector2(2.5, 2.5)
		diamond.rotation = deg_to_rad(45.0)
		diamond.position = Vector2(center_x + sign * (half + 12.0) - 2.5, center_y - 2.5)
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(diamond)

	# ── sparkles ──
	var sparkles := CPUParticles2D.new()
	sparkles.position = Vector2(CARD.size.x * 0.5, CARD.size.y * 0.5)
	sparkles.amount = 26
	sparkles.lifetime = 1.4
	sparkles.explosiveness = 0.15
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparkles.emission_rect_extents = Vector2(CARD.size.x * 0.5, CARD.size.y * 0.5)
	sparkles.direction = Vector2(0, -1)
	sparkles.spread = 50.0
	sparkles.gravity = Vector2(0, -12)
	sparkles.initial_velocity_min = 6.0
	sparkles.initial_velocity_max = 26.0
	sparkles.scale_amount_min = 1.0
	sparkles.scale_amount_max = 2.4
	sparkles.color = Color(1.0, 0.86, 0.5, 0.8)
	_card.add_child(sparkles)


func _radial_glow(color: Color) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _glass_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.022, 0.034, 0.97)
	style.border_color = Color(0.78, 0.60, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 3)
	return style
