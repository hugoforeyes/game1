extends Control
## AAA main menu — start_menu_v2 full-native-resolution redesign.
## A still anime key-visual background (OpenAiExtension art), engine-typeset
## Playfair title over a generated gold flourish, two ornate plaque buttons
## (New Game / Settings), rising ember motes like the chapter-intro slides,
## and an ornate loading overlay. All text is rendered by Godot so EN/VI stay
## crisp and precisely aligned.

const ART_DIR := "res://assets/ui/start_menu_v2/"
const SETTINGS_SCENE := preload("res://scenes/ui/SettingsPanel.tscn")
const MENU_SELECTION_SFX := preload("res://assets/audio/sfx/menu_selection_click.wav")
const MENU_CONFIRM_SFX := preload("res://assets/audio/sfx/menu_confirm.wav")

const GAME_TITLE := "ONE LIFE, ONE WORLD"
const VERSION_TEXT := "V0.1.0 ALPHA"

const BTN_SIZE := Vector2(400.0, 66.0)
const BTN_GAP := 24.0              # vertical space between the two plaques
const SOUL_CURSOR_SIZE := 38.0
const SOUL_CURSOR_OFFSET_X := -54.0

const COLOR_TITLE := Color(0.99, 0.88, 0.56, 1.0)
const COLOR_TITLE_GLOW := Color(1.0, 0.82, 0.42, 0.30)
const COLOR_BTN_IDLE := Color(0.85, 0.76, 0.55, 0.80)
const COLOR_BTN_LIT := Color(1.00, 0.94, 0.72, 1.00)
const COLOR_HINT := Color(0.86, 0.74, 0.48, 0.55)
const COLOR_VERSION := Color(0.80, 0.68, 0.44, 0.38)

var is_loading_new_game: bool = false
var flash_timer: float = 0.0
var _time: float = 0.0
var _entrance_done := false

var _bg: TextureRect
var _title_glow: Label
var _title_label: Label
var _flourish: TextureRect
var _menu_root: Control
var new_game_button: Button
var settings_button: Button
var _hint_label: Label
var _version_label: Label
var flash_label: Label
var settings_overlay: SettingsPanel
var _intro_fade: ColorRect
var _menu_selection_player: AudioStreamPlayer
var _focused_menu_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_ui()
	MusicManager.play_menu_music()
	_refresh_localized_copy()
	SettingsManager.language_changed.connect(_on_language_changed)
	settings_overlay.close_requested.connect(_on_settings_panel_closed)
	get_viewport().size_changed.connect(_layout)
	new_game_button.grab_focus()
	_refresh_menu_visuals(false)
	_play_entrance()

# ── Construction ──────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.012, 0.05, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var bg_holder := Control.new()
	bg_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_holder.clip_contents = true
	bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_holder)

	_bg = TextureRect.new()
	_bg.texture = _art("background.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_holder.add_child(_bg)

	# Radial vignette keeps the frame edges cinematic and the center luminous.
	var vignette := TextureRect.new()
	vignette.texture = _make_vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	add_child(_make_embers(false))
	add_child(_make_embers(true))

	_title_glow = _make_title_label(COLOR_TITLE_GLOW)
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_title_glow.material = glow_material
	add_child(_title_glow)

	_title_label = _make_title_label(COLOR_TITLE)
	add_child(_title_label)

	_flourish = TextureRect.new()
	_flourish.texture = _art("title_flourish.png")
	_flourish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flourish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flourish)

	_menu_root = Control.new()
	_menu_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_menu_root)
	new_game_button = _make_menu_button()
	new_game_button.pressed.connect(_on_new_game_pressed)
	_menu_root.add_child(new_game_button)
	settings_button = _make_menu_button()
	settings_button.pressed.connect(_on_settings_pressed)
	_menu_root.add_child(settings_button)
	# Two-item vertical menu: arrows wrap around both ways.
	new_game_button.focus_neighbor_bottom = new_game_button.get_path_to(settings_button)
	new_game_button.focus_neighbor_top = new_game_button.get_path_to(settings_button)
	settings_button.focus_neighbor_bottom = settings_button.get_path_to(new_game_button)
	settings_button.focus_neighbor_top = settings_button.get_path_to(new_game_button)

	_menu_selection_player = AudioStreamPlayer.new()
	_menu_selection_player.name = "MenuSelectionPlayer"
	_menu_selection_player.stream = MENU_SELECTION_SFX
	add_child(_menu_selection_player)

	_hint_label = _make_caps_label(13, COLOR_HINT, 3)
	add_child(_hint_label)

	_version_label = _make_caps_label(12, COLOR_VERSION, 2)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_version_label)

	flash_label = UiKit.make_title("", 22, UiKit.COLOR_ACCENT)
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.modulate.a = 0.0
	add_child(flash_label)

	var settings_layer := CanvasLayer.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.layer = 46
	add_child(settings_layer)
	settings_overlay = SETTINGS_SCENE.instantiate() as SettingsPanel
	settings_overlay.name = "SettingsOverlay"
	settings_layer.add_child(settings_overlay)

	_intro_fade = ColorRect.new()
	_intro_fade.color = Color(0.008, 0.006, 0.03, 1.0)
	_intro_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intro_fade)

	_layout()

func _art(file_name: String) -> Texture2D:
	var path := ART_DIR + file_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _make_title_label(color: Color) -> Label:
	var label := Label.new()
	label.text = GAME_TITLE
	var variation := FontVariation.new()
	variation.base_font = UiKit.title_font()
	variation.variation_opentype = {"wght": 640}
	variation.spacing_glyph = 2
	label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", 54)
	label.add_theme_color_override("font_color", color)
	if color.a >= 0.9:
		label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_caps_label(font_size: int, color: Color, spacing: int) -> Label:
	var label := Label.new()
	var variation := FontVariation.new()
	variation.base_font = UiKit.body_semibold_font()
	variation.spacing_glyph = spacing
	label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_menu_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = BTN_SIZE
	button.size = BTN_SIZE
	var empty := StyleBoxEmpty.new()
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style, empty)

	var tex_idle := TextureRect.new()
	tex_idle.texture = _art("button_idle.png")
	tex_idle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_idle.stretch_mode = TextureRect.STRETCH_SCALE
	tex_idle.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_idle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(tex_idle)

	var tex_selected := TextureRect.new()
	tex_selected.texture = _art("button_selected.png")
	tex_selected.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_selected.stretch_mode = TextureRect.STRETCH_SCALE
	tex_selected.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_selected.modulate.a = 0.0
	button.add_child(tex_selected)

	var label := _make_caps_label(20, COLOR_BTN_IDLE, 4)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(label)

	var soul_cursor := _make_soul_cursor()
	soul_cursor.visible = false
	button.add_child(soul_cursor)

	button.set_meta("tex_selected", tex_selected)
	button.set_meta("label", label)
	button.set_meta("cursor", soul_cursor)
	button.pivot_offset = BTN_SIZE * 0.5
	button.focus_entered.connect(_on_menu_button_focused.bind(button))
	button.focus_exited.connect(_refresh_menu_visuals.bind(true))
	button.mouse_entered.connect(button.grab_focus)
	return button

func _make_soul_cursor() -> Control:
	var soul := Control.new()
	soul.name = "SoulCursor"
	soul.size = Vector2(SOUL_CURSOR_SIZE, SOUL_CURSOR_SIZE)
	soul.pivot_offset = soul.size * 0.5
	soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.z_index = 3

	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var halo := TextureRect.new()
	halo.name = "Halo"
	halo.texture = _make_soul_glow_texture(
		Color(0.72, 0.96, 1.0, 0.65),
		Color(0.38, 0.84, 1.0, 0.22),
	)
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.size = Vector2(52, 52)
	halo.position = Vector2(-7, -7)
	halo.material = additive
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.add_child(halo)

	var core := TextureRect.new()
	core.name = "Core"
	core.texture = _make_soul_glow_texture(
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.48, 0.91, 1.0, 0.82),
	)
	core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	core.size = Vector2(18, 18)
	core.position = Vector2(10, 10)
	core.material = additive.duplicate()
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.add_child(core)

	var trail := CPUParticles2D.new()
	trail.name = "Trail"
	trail.position = soul.size * 0.5
	trail.amount = 12
	trail.lifetime = 0.9
	trail.local_coords = false
	trail.direction = Vector2(-1, 0)
	trail.spread = 34.0
	trail.gravity = Vector2(-4, -5)
	trail.initial_velocity_min = 7.0
	trail.initial_velocity_max = 18.0
	trail.scale_amount_min = 0.7
	trail.scale_amount_max = 1.6
	trail.color = Color(0.62, 0.93, 1.0, 0.58)
	soul.add_child(trail)
	return soul

func _make_soul_glow_texture(inner: Color, middle: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([inner, middle, Color(middle.r, middle.g, middle.b, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.32, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 128
	texture.height = 128
	return texture

# ── Layout (native viewport units) ────────────────────────────────────────────

func _layout() -> void:
	var vp := get_viewport_rect().size
	var cx := vp.x * 0.5

	# The key visual is still: keep-aspect cover, centered. The art is authored
	# 16:9 like the viewport, so this is a 1:1 fill at the shipped resolution.
	if _bg.texture != null:
		var art := _bg.texture.get_size()
		var cover := maxf(vp.x / art.x, vp.y / art.y)
		_bg.size = art * cover
		_bg.position = ((vp - _bg.size) * 0.5).round()

	_title_label.size = Vector2(vp.x, 70)
	_title_label.position = Vector2(0, vp.y * 0.145)
	_title_glow.size = _title_label.size
	_title_glow.position = _title_label.position

	var flourish_size := Vector2(500, 50)
	if _flourish.texture != null:
		var aspect := float(_flourish.texture.get_height()) / float(_flourish.texture.get_width())
		flourish_size = Vector2(500, 500.0 * aspect)
	_flourish.size = flourish_size
	_flourish.position = Vector2(cx - flourish_size.x * 0.5, vp.y * 0.295)
	_flourish.pivot_offset = flourish_size * 0.5

	_menu_root.position = Vector2(cx - BTN_SIZE.x * 0.5, vp.y * 0.535)
	_menu_root.size = Vector2(BTN_SIZE.x, BTN_SIZE.y * 2.0 + BTN_GAP)
	new_game_button.position = Vector2.ZERO
	settings_button.position = Vector2(0, BTN_SIZE.y + BTN_GAP)
	for button in [new_game_button, settings_button]:
		var soul_cursor := button.get_meta("cursor") as Control
		soul_cursor.position = Vector2(
			SOUL_CURSOR_OFFSET_X,
			(BTN_SIZE.y - SOUL_CURSOR_SIZE) * 0.5,
		)

	_hint_label.size = Vector2(vp.x, 20)
	_hint_label.position = Vector2(0, vp.y - 36)
	_version_label.size = Vector2(300, 18)
	_version_label.position = Vector2(20, vp.y - 34)

	flash_label.size = Vector2(vp.x, 34)
	flash_label.position = Vector2(0, vp.y * 0.845)

# ── Per-frame ambience ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta

	_title_glow.modulate.a = 0.55 + 0.45 * sin(_time * 1.3)

	if _entrance_done:
		_hint_label.modulate.a = 0.62 + 0.38 * (sin(_time * 2.1) * 0.5 + 0.5)

	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and (focused == new_game_button or focused == settings_button):
		var soul_cursor := focused.get_meta("cursor") as Control
		soul_cursor.position.x = SOUL_CURSOR_OFFSET_X + sin(_time * 4.2) * 3.5
		soul_cursor.modulate.a = 0.82 + 0.18 * sin(_time * 5.0)
		var pulse := 0.94 + 0.08 * (sin(_time * 5.0) * 0.5 + 0.5)
		soul_cursor.scale = Vector2(pulse, pulse)

	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)
		flash_label.modulate.a = minf(flash_timer * 3.0, 1.0)
	elif flash_label.modulate.a > 0.0:
		flash_label.modulate.a = maxf(flash_label.modulate.a - delta * 4.0, 0.0)

# ── Entrance choreography ────────────────────────────────────────────────────

func _play_entrance() -> void:
	var fade := create_tween()
	fade.tween_property(_intro_fade, "color:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(_intro_fade.hide)

	for setup in [
		[_title_label, 0.35, Vector2(0, -16)],
		[_title_glow, 0.35, Vector2(0, -16)],
		[_flourish, 0.6, Vector2.ZERO],
		[new_game_button, 0.85, Vector2(0, 20)],
		[settings_button, 1.0, Vector2(0, 20)],
		[_hint_label, 1.35, Vector2.ZERO],
		[_version_label, 1.35, Vector2.ZERO],
	]:
		var node := setup[0] as Control
		var delay := setup[1] as float
		var offset := setup[2] as Vector2
		var base_position := node.position
		node.modulate.a = 0.0
		node.position = base_position + offset
		var tween := create_tween().set_parallel(true)
		tween.tween_property(node, "modulate:a", 1.0, 0.7).set_delay(delay).set_trans(Tween.TRANS_SINE)
		if offset != Vector2.ZERO:
			tween.tween_property(node, "position", base_position, 0.8) \
				.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# The flourish blooms outward from its gem.
	_flourish.scale = Vector2(0.55, 0.9)
	var bloom := create_tween()
	bloom.tween_property(_flourish, "scale", Vector2.ONE, 0.9) \
		.set_delay(0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var finish := create_tween()
	finish.tween_interval(2.2)
	finish.tween_callback(func() -> void: _entrance_done = true)

# ── Menu state ────────────────────────────────────────────────────────────────

func _on_menu_button_focused(button: Button) -> void:
	if _focused_menu_button != null and _focused_menu_button != button:
		_menu_selection_player.play()
	_focused_menu_button = button
	_refresh_menu_visuals(true)

func _refresh_menu_visuals(animated: bool = true) -> void:
	for button in [new_game_button, settings_button]:
		var active: bool = button.has_focus()
		var tex_selected := button.get_meta("tex_selected") as TextureRect
		var label := button.get_meta("label") as Label
		var soul_cursor := button.get_meta("cursor") as Control
		soul_cursor.visible = active
		var target_alpha := 1.0 if active else 0.0
		var target_color := COLOR_BTN_LIT if active else COLOR_BTN_IDLE
		var target_scale := Vector2(1.03, 1.03) if active else Vector2.ONE
		if animated:
			var tween := create_tween().set_parallel(true)
			tween.tween_property(tex_selected, "modulate:a", target_alpha, 0.16).set_trans(Tween.TRANS_SINE)
			tween.tween_property(label, "theme_override_colors/font_color", target_color, 0.16)
			tween.tween_property(button, "scale", target_scale, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			tex_selected.modulate.a = target_alpha
			label.add_theme_color_override("font_color", target_color)
			button.scale = target_scale

func _play_menu_confirmation() -> void:
	# Keep this one-shot on the SceneTree root so changing scenes cannot cut it off.
	var player := AudioStreamPlayer.new()
	player.name = "MenuConfirmPlayer"
	player.stream = MENU_CONFIRM_SFX
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_overlay.visible:
		settings_overlay.close_panel()
		get_viewport().set_input_as_handled()

# ── Actions ───────────────────────────────────────────────────────────────────

func _on_new_game_pressed() -> void:
	if is_loading_new_game:
		return
	_play_menu_confirmation()
	# The world-gacha (reincarnation) scene owns the whole new-game flow now:
	# candidate fetch, the goddess searching state, world choice, and loading.
	print("[StartScene] New Game pressed — entering the reincarnation sanctuary")
	is_loading_new_game = true
	get_tree().change_scene_to_file("res://scenes/ui/WorldGachaScene.tscn")

func _on_settings_pressed() -> void:
	if is_loading_new_game:
		return
	_play_menu_confirmation()
	settings_overlay.open_panel()

func _on_settings_panel_closed() -> void:
	settings_button.grab_focus()

func _show_flash(message: String) -> void:
	flash_label.text = message
	flash_label.modulate.a = 1.0
	flash_timer = 1.8

# ── Localization ─────────────────────────────────────────────────────────────

func _refresh_localized_copy() -> void:
	(new_game_button.get_meta("label") as Label).text = SettingsManager.text("menu.new_game")
	(settings_button.get_meta("label") as Label).text = SettingsManager.text("menu.settings")
	_hint_label.text = SettingsManager.text("menu.hint")
	_version_label.text = VERSION_TEXT

func _on_language_changed(_locale: String) -> void:
	_refresh_localized_copy()

# ── Ambient builders ─────────────────────────────────────────────────────────

## Rising light motes, native-resolution tuning of the intro slides' embers.
## far=false: bright gold foreground sparks; far=true: faint cyan drift layer.
func _make_embers(far: bool) -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	var vp := get_viewport_rect().size
	embers.position = Vector2(vp.x * 0.5, vp.y + 12.0)
	embers.amount = 18 if far else 30
	embers.lifetime = 11.0 if far else 8.0
	embers.preprocess = 10.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(vp.x * 0.55, 6.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 16.0
	embers.gravity = Vector2(0, -14.0)
	embers.initial_velocity_min = 16.0 if far else 30.0
	embers.initial_velocity_max = 34.0 if far else 74.0
	embers.scale_amount_min = 1.2 if far else 1.5
	embers.scale_amount_max = 2.4 if far else 3.4
	embers.color = Color(0.62, 0.88, 0.95, 0.20) if far else Color(1.0, 0.80, 0.44, 0.55)
	return embers

## Soft radial vignette rendered once into a texture (dark corners, clear center).
func _make_vignette_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0.01, 0.008, 0.04, 0.05), Color(0.01, 0.008, 0.04, 0.42),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, -0.12)
	texture.width = 512
	texture.height = 288
	return texture
