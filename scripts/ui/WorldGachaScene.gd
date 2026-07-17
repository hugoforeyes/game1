extends Control
## World gacha — the reincarnation sanctuary. After New Game, the player's soul
## (a small cyan wisp) stands before the Goddess of Life while she seeks worlds;
## the server answers with up to three random candidate worlds, which appear as
## three arched portal-gates (world vista + name + traits, EN/VI). Choosing one
## sends the soul through the door and starts that world via
## ChapterFlow.start_game_with_run(). All art is text-free (world_gacha_v1 +
## start_menu_v2 plaques); every string is typeset by Godot.

const ART_DIR := "res://assets/ui/world_gacha_v1/"
const MENU_ART_DIR := "res://assets/ui/start_menu_v2/"
const START_SCENE_PATH := "res://scenes/ui/StartScene.tscn"

const DOOR_ASPECT := 781.0 / 1279.0    # door_frame.png trim
const DOOR_HEIGHT := 336.0
const DOOR_SPACING := 300.0
const DOOR_TOP_Y := 88.0
const MIN_SEARCH_SECONDS := 2.4

# Loading-background measurements, in the 1536x1024 source image.  Keeping the
# geometry in source pixels means the painted gate, its invisible runtime
# aperture, and the soul route all share the exact same cover transform.
const LOADING_REFERENCE_SIZE := Vector2(1536.0, 1024.0)
const LOADING_APERTURE_SOURCE := Rect2(614.0, 231.0, 308.0, 522.0)
const LOADING_ARCH_SPRING_V := 173.0 / 522.0
const LOADING_ROUTE_SOURCE := [
	Vector2(316.0, 864.0),
	Vector2(321.0, 851.0),
	Vector2(360.0, 827.0),
	Vector2(445.0, 803.0),
	Vector2(565.0, 781.0),
	Vector2(670.0, 764.0),
	Vector2(768.0, 753.0),
]

const COLOR_TITLE := Color(0.99, 0.88, 0.56, 1.0)
const COLOR_SOUL := Color(0.62, 0.93, 1.0, 1.0)
const COLOR_NAME_IDLE := Color(0.85, 0.76, 0.55, 0.85)
const COLOR_NAME_LIT := Color(1.00, 0.94, 0.72, 1.00)
const COLOR_HINT := Color(0.86, 0.74, 0.48, 0.55)
const COLOR_DIM_UNFOCUSED := Color(0.56, 0.60, 0.72, 1.0)
const COLOR_ERROR := Color(0.95, 0.62, 0.42, 1.0)

const ARCH_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D mask_tex;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= texture(mask_tex, UV).r;
	COLOR = c;
}
"""

# The photographed gate is a round elliptical arch.  The old arch_mask.png is
# intentionally not used here: it is a pointed gothic silhouette and becomes
# visibly wrong as soon as the separate frame sprite is hidden.
const LOADING_ARCH_SHADER_CODE := """
shader_type canvas_item;
uniform vec2 mask_uv_scale = vec2(1.0, 1.0);
uniform vec2 mask_uv_offset = vec2(0.0, 0.0);
uniform float spring_v = 0.331418;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 p = UV * mask_uv_scale + mask_uv_offset;
	vec2 ellipse = vec2((p.x - 0.5) / 0.5, (p.y - spring_v) / spring_v);
	float cap = 1.0 - smoothstep(0.993, 1.007, length(ellipse));
	float body = step(spring_v, p.y);
	float bounds = step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
	c.a *= max(cap, body) * bounds;
	COLOR = c;
}
"""

enum Phase { SEARCHING, REVEAL, CONFIRMING, ERROR }

var _phase: int = Phase.SEARCHING
var _time := 0.0
var _candidates: Array = []            # ready candidates, each with gate_texture
var _doors: Array = []                 # door node bundles (Dictionary of refs)
var _focus_index := 0
var _reveal_ready := false             # input unlocks once the door choreography lands
var _goddess_idle := true              # false while a transition tween owns her transform
var _goddess_strength := 1.0           # idle-motion amplitude (softer once she presides)
var _soul_anchor := Vector2.ZERO
var _search_started_msec := 0

var _bg: TextureRect               # goddess-free sanctuary (searching backdrop)
var _bg_goddess: TextureRect       # sanctuary WITH the baked goddess (reveal backdrop)
var _goddess: Control              # large animated goddess during searching/error
var _ring_outer: TextureRect
var _ring_inner: TextureRect
var _soul: Control
var _soul_halo: TextureRect
var _searching_root: Control
var _search_title: Label
var _search_sub: Label
var _search_status: Label
var _reveal_root: Control
var _reveal_title: Label
var _reveal_flourish: TextureRect
var _tagline_label: Label
var _hint_label: Label
var _flash: ColorRect
var _loading_overlay: Control
var _loading_chapter: Label
var _loading_status: Label
var _ld_background: TextureRect     # supplied sanctuary image, goddess already baked in
var _ld_door: Control               # the destination gate (art + leaves + frame)
var _ld_art: TextureRect            # chosen world's vista behind the leaves
var _ld_glow: TextureRect           # light spilling through the opening
var _ld_leaf_left: TextureRect
var _ld_leaf_right: TextureRect
var _ld_path: Node2D                # subtle shimmer exactly over the painted floor route
var _ld_path_glow: Line2D
var _ld_path_core: Line2D
var _ld_route := Curve2D.new()
var _ld_reference_scale := 1.0
var _ld_reference_offset := Vector2.ZERO
var _ld_soul: Control               # the traveling soul on the loading screen
var _ld_plate_label: Label          # world name on the plaque
var _ld_percent: Label
var _ld_progress := 0.0             # displayed (smoothed) 0..1
var _ld_target := 0.0               # milestone-driven target
var _chosen_candidate: Dictionary = {}
var _intro_fade: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_ui()
	_refresh_localized_copy()
	SettingsManager.language_changed.connect(_on_language_changed)
	get_viewport().size_changed.connect(_layout)
	_play_entrance()
	_run_flow()

# ── Construction ──────────────────────────────────────────────────────────────

func _art(file_name: String, dir: String = ART_DIR) -> Texture2D:
	var path := dir + file_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.010, 0.010, 0.045, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_bg = TextureRect.new()
	_bg.texture = _art("bg_sanctuary.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Once the gates stand, the sanctuary "remembers" its goddess: the reveal
	# crossfades to the variant with her painted in while the live cutout fades.
	_bg_goddess = TextureRect.new()
	_bg_goddess.texture = _art("bg_sanctuary_goddess.png")
	_bg_goddess.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_goddess.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_goddess.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_goddess.modulate.a = 0.0
	add_child(_bg_goddess)

	var vignette := TextureRect.new()
	vignette.texture = _make_radial_texture(
		Color(0, 0, 0, 0.0), Color(0.008, 0.006, 0.035, 0.46), 0.60
	)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	add_child(_make_motes(true))
	add_child(_make_motes(false))

	# The goddess herself — a cutout of the sanctuary figure, drawn large and
	# alive (breathing, bobbing, pulsing aura) while she seeks the worlds.
	_goddess = _build_goddess()
	add_child(_goddess)

	# ── searching phase ──
	_searching_root = Control.new()
	_searching_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_searching_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_searching_root)

	_ring_outer = _make_ring(300.0, 1.0)
	_searching_root.add_child(_ring_outer)
	_ring_inner = _make_ring(196.0, 0.55)
	_searching_root.add_child(_ring_inner)

	_search_title = _make_title_label(22, COLOR_TITLE)
	_searching_root.add_child(_search_title)
	_search_sub = _make_caps_label(13, Color(0.88, 0.80, 0.62, 0.78), 2)
	_searching_root.add_child(_search_sub)
	_search_status = UiKit.make_label("", 12, UiKit.COLOR_TEXT_DIM)
	_search_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_searching_root.add_child(_search_status)

	# ── reveal phase (populated once candidates land) ──
	_reveal_root = Control.new()
	_reveal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_reveal_root.visible = false
	add_child(_reveal_root)

	_reveal_title = _make_title_label(24, COLOR_TITLE)
	_reveal_root.add_child(_reveal_title)
	_reveal_flourish = TextureRect.new()
	_reveal_flourish.texture = _art("title_flourish.png", MENU_ART_DIR)
	_reveal_flourish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reveal_flourish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reveal_flourish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_root.add_child(_reveal_flourish)

	_tagline_label = UiKit.make_label("", 13, Color(0.90, 0.83, 0.66, 0.85))
	_tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal_root.add_child(_tagline_label)

	_hint_label = _make_caps_label(12, COLOR_HINT, 3)
	_reveal_root.add_child(_hint_label)

	# ── the soul (shared by both phases — the player) ──
	_soul = _build_soul()
	add_child(_soul)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.95, 0.82, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_build_loading_overlay()

	_intro_fade = ColorRect.new()
	_intro_fade.color = Color(0.008, 0.006, 0.03, 1.0)
	_intro_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intro_fade)

	_layout()

func _make_title_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	var variation := FontVariation.new()
	variation.base_font = UiKit.title_font()
	variation.variation_opentype = {"wght": 640}
	variation.spacing_glyph = 3
	label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
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

func _make_ring(size_px: float, alpha: float) -> TextureRect:
	var ring := TextureRect.new()
	ring.texture = _art("rune_ring.png")
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.size = Vector2(size_px, size_px)
	ring.pivot_offset = ring.size * 0.5
	ring.modulate.a = alpha
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ring

func _build_soul(register_halo: bool = true) -> Control:
	var soul := Control.new()
	soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.z_index = 5

	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var halo := TextureRect.new()
	halo.name = "Halo"
	halo.texture = _make_radial_texture(
		Color(COLOR_SOUL.r, COLOR_SOUL.g, COLOR_SOUL.b, 0.55), Color(COLOR_SOUL.r, COLOR_SOUL.g, COLOR_SOUL.b, 0.0), 0.5, true
	)
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.size = Vector2(96, 96)
	halo.position = -halo.size * 0.5
	halo.material = add_material
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.add_child(halo)
	if register_halo:
		_soul_halo = halo

	var core := TextureRect.new()
	core.texture = _make_radial_texture(Color(1.0, 1.0, 1.0, 1.0), Color(COLOR_SOUL.r, COLOR_SOUL.g, COLOR_SOUL.b, 0.0), 0.5, true)
	core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	core.size = Vector2(30, 30)
	core.position = -core.size * 0.5
	core.material = add_material.duplicate()
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.add_child(core)

	var trail := CPUParticles2D.new()
	trail.amount = 26
	trail.lifetime = 1.5
	trail.local_coords = false
	trail.direction = Vector2(0, -1)
	trail.spread = 40.0
	trail.gravity = Vector2(0, -18.0)
	trail.initial_velocity_min = 6.0
	trail.initial_velocity_max = 22.0
	trail.scale_amount_min = 1.0
	trail.scale_amount_max = 2.2
	trail.color = Color(COLOR_SOUL.r, COLOR_SOUL.g, COLOR_SOUL.b, 0.5)
	soul.add_child(trail)
	return soul

## The goddess figure as a self-animating group: divine light veil (also washes
## out the smaller goddess baked into the background art), additive glow copy,
## and the cutout itself. Returns an empty Control if the asset is missing.
func _build_goddess() -> Control:
	var group := Control.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := _art("goddess.png")
	if texture == null:
		return group
	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var veil := TextureRect.new()
	veil.name = "Veil"
	veil.texture = _make_radial_texture(
		Color(1.0, 0.94, 0.78, 0.42), Color(1.0, 0.9, 0.7, 0.0), 0.5, true
	)
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.material = add_material
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(veil)

	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.material = add_material.duplicate()
	glow.modulate = Color(1.0, 0.86, 0.55, 0.3)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(glow)

	var figure := TextureRect.new()
	figure.name = "Figure"
	figure.texture = texture
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(figure)
	return group

## Position one goddess group: figure height `height`, centered on `center`.
func _layout_goddess(group: Control, center: Vector2, height: float) -> void:
	if group.get_child_count() == 0:
		return
	var figure := group.get_node("Figure") as TextureRect
	var aspect := 0.66
	if figure.texture != null:
		aspect = float(figure.texture.get_width()) / float(figure.texture.get_height())
	var size := Vector2(height * aspect, height)
	group.size = size
	group.scale = Vector2.ONE
	group.position = center - size * 0.5
	group.pivot_offset = size * 0.5
	group.set_meta("base_y", group.position.y)
	figure.size = size
	figure.position = Vector2.ZERO
	var glow := group.get_node("Glow") as TextureRect
	glow.size = size * 1.05
	glow.position = (size - glow.size) * 0.5
	var veil := group.get_node("Veil") as TextureRect
	veil.size = Vector2(size.x * 2.1, size.y * 1.25)
	veil.position = (size - veil.size) * 0.5

## The loading-data screen: the chosen soul travels a glowing floor path toward
## the world's gate while its double doors swing open with download progress —
## the opening door IS the progress bar. The chosen world's vista glows behind
## the leaves; the supplied background already contains the goddess.
func _build_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	_loading_overlay.z_index = 10
	add_child(_loading_overlay)

	_ld_background = TextureRect.new()
	_ld_background.name = "LoadingBackground"
	_ld_background.texture = _art("bg_loading_gateway.png")
	_ld_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ld_background.stretch_mode = TextureRect.STRETCH_SCALE
	_ld_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(_ld_background)

	# A restrained grade keeps the supplied art vivid while unifying the world
	# vista that appears inside the opening doors.
	var dim := ColorRect.new()
	dim.color = Color(0.008, 0.012, 0.035, 0.10)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(dim)

	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# Two additive hairlines provide a living shimmer without redrawing or
	# flattening the luminous S-curve that is already painted into the image.
	_ld_path = Node2D.new()
	_ld_path.name = "PathShimmer"
	_ld_path_glow = Line2D.new()
	_ld_path_glow.width = 13.0
	_ld_path_glow.default_color = Color(1.0, 0.73, 0.30, 0.16)
	_ld_path_glow.antialiased = true
	_ld_path_glow.material = add_material
	_ld_path.add_child(_ld_path_glow)
	_ld_path_core = Line2D.new()
	_ld_path_core.width = 2.4
	_ld_path_core.default_color = Color(1.0, 0.94, 0.70, 0.58)
	_ld_path_core.antialiased = true
	_ld_path_core.material = add_material.duplicate()
	_ld_path.add_child(_ld_path_core)
	_loading_overlay.add_child(_ld_path)

	# the destination gate: world vista → light spill → closed leaves → frame
	_ld_door = Control.new()
	_ld_door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(_ld_door)

	_ld_art = TextureRect.new()
	_ld_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ld_art.stretch_mode = TextureRect.STRETCH_SCALE
	_ld_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ld_art.material = _make_loading_arch_material(Vector2.ONE, Vector2.ZERO)
	_ld_door.add_child(_ld_art)

	_ld_glow = TextureRect.new()
	_ld_glow.texture = _make_radial_texture(
		Color(1.0, 0.95, 0.78, 0.9), Color(1.0, 0.9, 0.6, 0.0), 0.5, true
	)
	_ld_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ld_glow.material = _make_loading_arch_material(Vector2.ONE, Vector2.ZERO)
	_ld_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ld_door.add_child(_ld_glow)

	_ld_leaf_left = _make_leaf("door_leaf_left.png")
	_ld_leaf_left.material = _make_loading_arch_material(Vector2(0.5, 1.0), Vector2.ZERO)
	_ld_door.add_child(_ld_leaf_left)
	_ld_leaf_right = _make_leaf("door_leaf_right.png")
	_ld_leaf_right.material = _make_loading_arch_material(Vector2(0.5, 1.0), Vector2(0.5, 0.0))
	_ld_door.add_child(_ld_leaf_right)

	# Retain the frame node as the invisible alignment object requested by the
	# design.  The photographed frame is the only visible frame on this screen.
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.texture = _art("door_frame.png")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	_ld_door.add_child(frame)

	# the traveling soul (its own instance — the scene's soul sits below this overlay)
	_ld_soul = _build_soul(false)
	_loading_overlay.add_child(_ld_soul)

	# Compact bottom HUD keeps every label away from the measured aperture and
	# preserves the cinematic composition at the native 16:9 viewport.
	var hud := Panel.new()
	hud.name = "LoadingHud"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.006, 0.010, 0.028, 0.82)
	hud_style.border_color = Color(0.86, 0.68, 0.31, 0.34)
	hud_style.border_width_top = 1
	hud_style.border_width_left = 1
	hud_style.corner_radius_top_left = 14
	hud.add_theme_stylebox_override("panel", hud_style)
	_loading_overlay.add_child(hud)

	# world nameplate + chapter + status + percent
	var plate := Control.new()
	plate.name = "Plate"
	plate.size = Vector2(264, 36)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(plate)
	var plate_texture := _make_plate_texture("button_selected.png", plate.size)
	plate.add_child(plate_texture)
	_ld_plate_label = _make_caps_label(15, COLOR_NAME_LIT, 2)
	_ld_plate_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ld_plate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(_ld_plate_label)

	_loading_chapter = _make_caps_label(12, Color(0.85, 0.73, 0.48, 0.9), 2)
	_loading_overlay.add_child(_loading_chapter)
	_loading_status = UiKit.make_label("", 12, UiKit.COLOR_TEXT_DIM)
	_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_overlay.add_child(_loading_status)
	_ld_percent = _make_title_label(20, COLOR_TITLE)
	_loading_overlay.add_child(_ld_percent)

func _make_loading_arch_material(uv_scale: Vector2, uv_offset: Vector2) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LOADING_ARCH_SHADER_CODE
	material.shader = shader
	material.set_shader_parameter("mask_uv_scale", uv_scale)
	material.set_shader_parameter("mask_uv_offset", uv_offset)
	material.set_shader_parameter("spring_v", LOADING_ARCH_SPRING_V)
	return material

func _make_leaf(file_name: String) -> TextureRect:
	var leaf := TextureRect.new()
	var source := _art(file_name)
	# The original leaf PNGs include large transparent margins and a pointed
	# arch baked for door_frame.png.  Sample the clean rectangular panel body;
	# the measured ellipse shader now supplies the correct photographed arch.
	if source != null:
		var image := source.get_image()
		if image != null:
			var panel_region := Rect2i(240, 500, 150, 647) if file_name.contains("left") \
				else Rect2i(0, 500, 151, 647)
			leaf.texture = ImageTexture.create_from_image(image.get_region(panel_region))
		else:
			leaf.texture = source
	leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	leaf.stretch_mode = TextureRect.STRETCH_SCALE
	leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return leaf

## One door bundle: frame + masked world art + glow + nameplate + chips.
func _build_door(candidate: Dictionary, index: int) -> Dictionary:
	var door_size := Vector2(DOOR_HEIGHT * DOOR_ASPECT, DOOR_HEIGHT)
	var root := Control.new()
	root.size = door_size
	root.pivot_offset = door_size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_reveal_root.add_child(root)

	var accent := Color.from_string(str(candidate.get("accent_color", "")), UiKit.COLOR_ACCENT)

	# world vista, cropped to the door aspect and clipped to the arch aperture.
	# The crop happens CPU-side: an AtlasTexture would keep atlas-page UVs in the
	# canvas_item shader, so the aperture mask lookup would sample the wrong
	# region — with a plain texture, quad UV = 0..1 and mask UV aligns exactly.
	var art := TextureRect.new()
	var gate_texture: Texture2D = candidate.get("gate_texture")
	if gate_texture != null:
		art.texture = _cropped_to_door_aspect(gate_texture)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = ARCH_SHADER_CODE
	art_material.shader = shader
	art_material.set_shader_parameter("mask_tex", _art("arch_mask.png"))
	art.material = art_material
	root.add_child(art)

	var frame := TextureRect.new()
	frame.texture = _art("door_frame.png")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)

	# accent-tinted additive glow copy of the frame — the "chosen door" aura
	var glow := TextureRect.new()
	glow.texture = frame.texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_material
	glow.modulate = Color(accent.r, accent.g, accent.b, 0.0)
	root.add_child(glow)

	# nameplate (start-menu plaque art, engine-typeset caption)
	var plate := Control.new()
	plate.size = Vector2(244, 34)
	plate.position = Vector2((door_size.x - plate.size.x) * 0.5, door_size.y + 10.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var plate_idle := _make_plate_texture("button_idle.png", plate.size)
	plate.add_child(plate_idle)
	var plate_lit := _make_plate_texture("button_selected.png", plate.size)
	plate_lit.modulate.a = 0.0
	plate.add_child(plate_lit)
	var name_label := _make_caps_label(15, COLOR_NAME_IDLE, 2)
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(name_label)

	# trait chips row — populated per-language by _refresh_candidate_copy, which
	# also fits the row inside the door column so neighbors never collide.
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 6)
	chips.position = Vector2(-40.0, door_size.y + 52.0)
	chips.size = Vector2(door_size.x + 80.0, 22)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chips)

	root.mouse_entered.connect(func() -> void:
		if _reveal_ready:
			_set_focus(index, true)
	)
	root.gui_input.connect(func(event: InputEvent) -> void:
		if not _reveal_ready:
			return
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _focus_index == index:
				_confirm_choice()
			else:
				_set_focus(index, true)
	)

	return {
		"root": root, "glow": glow, "plate": plate, "plate_lit": plate_lit,
		"name_label": name_label, "chips": chips, "accent": accent,
		"candidate": candidate,
	}

## Center-crop a world vista to the door frame's aspect so it can be drawn on
## the exact door rect (UV 0..1) under the arch-aperture mask shader.
func _cropped_to_door_aspect(texture: Texture2D) -> Texture2D:
	return _cropped_to_aspect(texture, DOOR_ASPECT)

func _cropped_to_aspect(texture: Texture2D, target_aspect: float) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	var w := image.get_width()
	var h := image.get_height()
	var crop_w := mini(w, int(round(float(h) * target_aspect)))
	var crop_h := mini(h, int(round(float(crop_w) / target_aspect)))
	var region := Rect2i((w - crop_w) / 2, (h - crop_h) / 2, crop_w, crop_h)
	return ImageTexture.create_from_image(image.get_region(region))

func _make_plate_texture(file_name: String, plate_size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _art(file_name, MENU_ART_DIR)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = plate_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _make_trait_chip(text: String, font_size: int, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.10, 0.88)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_right = 9
	style.corner_radius_bottom_left = 9
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_caps_label(font_size, Color(0.92, 0.85, 0.66, 0.95), 1)
	label.text = text
	chip.add_child(label)
	return chip

## Rebuild one door's trait chips in the current language, shrinking the font
## and finally dropping trailing chips so the row always fits its door column
## (real trait labels like "EMOTIONAL HEALING" overflowed into the neighbor).
func _rebuild_chips(bundle: Dictionary) -> void:
	var chips_box := bundle["chips"] as HBoxContainer
	for child in chips_box.get_children():
		child.queue_free()
	var candidate := bundle["candidate"] as Dictionary
	var accent := bundle["accent"] as Color
	var texts: Array[String] = []
	for trait_item in (candidate.get("traits", []) as Array):
		if trait_item is Dictionary:
			var text := str((trait_item as Dictionary).get("label_vi" if _is_vi() else "label_en", "")).strip_edges().to_upper()
			if not text.is_empty():
				texts.append(text)
	if texts.is_empty():
		return
	var font := UiKit.body_semibold_font()
	if font == null:
		font = ThemeDB.fallback_font
	var max_width := chips_box.size.x
	var chosen_count := 1
	var chosen_size := 8
	var found := false
	for count in [texts.size(), 2, 1]:
		if found or count > texts.size() or count < 1:
			continue
		for font_size in [10, 9, 8]:
			var total := 6.0 * float(count - 1)
			for i in range(count):
				# +1px/char for spacing_glyph, +16 chip padding, +2 border/fudge
				total += font.get_string_size(texts[i], HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x \
					+ float(texts[i].length()) + 18.0
			if total <= max_width:
				chosen_count = count
				chosen_size = font_size
				found = true
				break
	for i in range(chosen_count):
		chips_box.add_child(_make_trait_chip(texts[i], chosen_size, accent))

# ── Layout ────────────────────────────────────────────────────────────────────

func _layout() -> void:
	var vp := get_viewport_rect().size
	var cx := vp.x * 0.5

	for backdrop: TextureRect in [_bg, _bg_goddess]:
		if backdrop.texture != null:
			var art: Vector2 = backdrop.texture.get_size()
			var cover := maxf(vp.x / art.x, vp.y / art.y)
			backdrop.size = art * cover
			backdrop.position = ((vp - backdrop.size) * 0.5).round()
	_layout_loading_background(vp)

	# The animated goddess dominates the top while she searches; the reveal
	# hands her back to the painted background.
	_layout_goddess(_goddess, Vector2(cx, vp.y * 0.365), 420.0)
	var ring_center := Vector2(cx, vp.y * 0.575)
	_ring_outer.position = ring_center - _ring_outer.size * 0.5
	_ring_inner.position = ring_center - _ring_inner.size * 0.5
	if _phase == Phase.SEARCHING or _phase == Phase.ERROR:
		_soul_anchor = ring_center

	_search_title.size = Vector2(vp.x, 30)
	_search_title.position = Vector2(0, vp.y * 0.845)
	_search_sub.size = Vector2(vp.x, 20)
	_search_sub.position = Vector2(0, vp.y * 0.902)
	_search_status.size = Vector2(vp.x, 18)
	_search_status.position = Vector2(0, vp.y * 0.948)

	_reveal_title.size = Vector2(vp.x, 32)
	_reveal_title.position = Vector2(0, 18)
	_reveal_flourish.size = Vector2(300, 30)
	_reveal_flourish.position = Vector2(cx - 150.0, 52)
	_tagline_label.size = Vector2(vp.x - 120.0, 20)
	_tagline_label.position = Vector2(60.0, vp.y - 62.0)
	_hint_label.size = Vector2(vp.x, 18)
	_hint_label.position = Vector2(0, vp.y - 32.0)

	var door_size := Vector2(DOOR_HEIGHT * DOOR_ASPECT, DOOR_HEIGHT)
	var count := _doors.size()
	for i in range(count):
		var root := (_doors[i] as Dictionary)["root"] as Control
		var center_x := cx + (float(i) - float(count - 1) * 0.5) * DOOR_SPACING
		root.position = Vector2(center_x - door_size.x * 0.5, DOOR_TOP_Y)

	# Loading screen: map every runtime element through the exact same transform
	# as the supplied image.  The separate frame stays invisible; this rect is
	# the photographed gate's clear aperture, not its ornamental outer bounds.
	var aperture := _loading_source_rect_to_viewport(LOADING_APERTURE_SOURCE)
	var ld_door_size := aperture.size
	_ld_door.size = ld_door_size
	_ld_door.position = aperture.position
	_ld_art.size = ld_door_size
	_ld_art.position = Vector2.ZERO
	_ld_glow.size = ld_door_size
	_ld_glow.position = Vector2.ZERO
	var leaf_size := Vector2(ld_door_size.x * 0.5, ld_door_size.y)
	_ld_leaf_left.size = leaf_size
	_ld_leaf_left.position = Vector2.ZERO
	_ld_leaf_left.pivot_offset = Vector2(0.0, leaf_size.y * 0.5)
	_ld_leaf_right.size = leaf_size
	_ld_leaf_right.position = Vector2(leaf_size.x, 0.0)
	_ld_leaf_right.pivot_offset = Vector2(leaf_size.x, leaf_size.y * 0.5)
	_rebuild_loading_route()
	var hud := _loading_overlay.get_node("LoadingHud") as Control
	hud.position = Vector2(vp.x - 424.0, vp.y - 64.0)
	hud.size = Vector2(424.0, 64.0)
	var plate := _loading_overlay.get_node("Plate") as Control
	plate.position = Vector2(vp.x - 412.0, vp.y - 58.0)
	_loading_chapter.size = Vector2(100.0, 18.0)
	_loading_chapter.position = Vector2(vp.x - 404.0, vp.y - 20.0)
	_loading_status.size = Vector2(276.0, 18.0)
	_loading_status.position = Vector2(vp.x - 304.0, vp.y - 20.0)
	_ld_percent.size = Vector2(112.0, 30.0)
	_ld_percent.position = Vector2(vp.x - 128.0, vp.y - 53.0)

func _layout_loading_background(vp: Vector2) -> void:
	if _ld_background == null or _ld_background.texture == null:
		_ld_reference_scale = 1.0
		_ld_reference_offset = Vector2.ZERO
		return
	# Cover the viewport without distortion.  Top alignment preserves the full
	# goddess, halo, crown, and arch; only distant foreground floor is cropped.
	_ld_reference_scale = maxf(vp.x / LOADING_REFERENCE_SIZE.x, vp.y / LOADING_REFERENCE_SIZE.y)
	var draw_size := LOADING_REFERENCE_SIZE * _ld_reference_scale
	_ld_reference_offset = Vector2((vp.x - draw_size.x) * 0.5, 0.0)
	_ld_background.position = _ld_reference_offset
	_ld_background.size = draw_size

func _loading_source_to_viewport(source_point: Vector2) -> Vector2:
	return _ld_reference_offset + source_point * _ld_reference_scale

func _loading_source_rect_to_viewport(source_rect: Rect2) -> Rect2:
	return Rect2(
		_loading_source_to_viewport(source_rect.position),
		source_rect.size * _ld_reference_scale
	)

func _rebuild_loading_route() -> void:
	_ld_route = Curve2D.new()
	_ld_route.bake_interval = 2.0
	var points: Array[Vector2] = []
	for source_point: Vector2 in LOADING_ROUTE_SOURCE:
		points.append(_loading_source_to_viewport(source_point))
	for i in range(points.size()):
		var previous := points[maxi(i - 1, 0)]
		var following := points[mini(i + 1, points.size() - 1)]
		var handle := (following - previous) / 6.0
		var handle_in := -handle if i > 0 else Vector2.ZERO
		var handle_out := handle if i < points.size() - 1 else Vector2.ZERO
		_ld_route.add_point(points[i], handle_in, handle_out)
	var baked := _ld_route.get_baked_points()
	_ld_path_glow.points = baked
	_ld_path_core.points = baked

# ── Flow ──────────────────────────────────────────────────────────────────────

func _run_flow() -> void:
	# QA hook: StartGachaShot drives phases by hand with fake candidates so the
	# visual pass never triggers real server-side identity generation.
	if has_meta("qa_offline"):
		return
	_search_started_msec = Time.get_ticks_msec()
	var candidates: Array = await ChapterFlow.fetch_world_candidates(3)
	if candidates.is_empty():
		_enter_error()
		return

	# Generate identities the goddess hasn't woven yet (server-side, minutes).
	var ready: Array = []
	for i in range(candidates.size()):
		var candidate: Dictionary = candidates[i] as Dictionary
		if not bool(candidate.get("ready", false)):
			_search_status.text = SettingsManager.text("gacha.weaving") % [i + 1, candidates.size()]
			var generated: Dictionary = await ChapterFlow.request_world_identity(str(candidate.get("run_id", "")))
			if not bool(generated.get("ok", false)):
				continue
			# The generate response has no flow knowledge — keep the count the
			# candidates endpoint already computed for this run.
			generated["chapter_count"] = candidate.get("chapter_count", 0)
			candidate = generated
		ready.append(candidate)

	# Fetch every gate vista; a world without a face cannot be offered.
	var offered: Array = []
	for candidate_variant in ready:
		var candidate: Dictionary = candidate_variant as Dictionary
		var texture: Texture2D = await ChapterFlow.download_image_texture(str(candidate.get("gate_image_url", "")))
		if texture == null:
			continue
		candidate["gate_texture"] = texture
		offered.append(candidate)

	if offered.is_empty():
		_enter_error()
		return

	var elapsed := float(Time.get_ticks_msec() - _search_started_msec) / 1000.0
	if elapsed < MIN_SEARCH_SECONDS:
		await get_tree().create_timer(MIN_SEARCH_SECONDS - elapsed).timeout
	_enter_reveal(offered)

func _enter_error(force: bool = false) -> void:
	if _phase != Phase.SEARCHING and not force:
		return
	_phase = Phase.ERROR
	_search_title.text = SettingsManager.text("gacha.error")
	_search_title.add_theme_color_override("font_color", COLOR_ERROR)
	_search_sub.text = SettingsManager.text("gacha.error_hint")
	_search_status.text = ""

## The goddess's magic condenses into the soul, which casts three light-seeds;
## where each seed lands, a pillar of light erupts and a gate materializes out
## of a rune-ring flash, gold burst and bloom — then the UI text settles in.
func _enter_reveal(offered: Array) -> void:
	if _phase != Phase.SEARCHING:
		return
	_phase = Phase.REVEAL
	_reveal_ready = false
	_candidates = offered
	for i in range(offered.size()):
		_doors.append(_build_door(offered[i] as Dictionary, i))
	_refresh_candidate_copy()
	_layout()

	_reveal_root.modulate.a = 1.0
	_reveal_root.visible = true
	for node in [_reveal_title, _reveal_flourish, _tagline_label, _hint_label]:
		node.modulate.a = 0.0

	# A) searching copy bows out while the rune rings collapse into the soul.
	var text_out := create_tween().set_parallel(true)
	for node in [_search_title, _search_sub, _search_status]:
		text_out.tween_property(node, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	for ring in [_ring_outer, _ring_inner]:
		var collapse := create_tween().set_parallel(true)
		collapse.tween_property(ring, "scale", Vector2(0.08, 0.08), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		collapse.tween_property(ring, "modulate:a", 0.0, 0.5) \
			.set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var hide_search := create_tween()
	hide_search.tween_interval(0.55)
	hide_search.tween_callback(_searching_root.hide)

	# The living goddess dissolves into the painted sanctuary — the background
	# with her figure fades back in as the gates take the stage.
	if _goddess.visible and _goddess.get_child_count() > 0:
		_goddess_idle = false
		var handoff := create_tween().set_parallel(true)
		handoff.tween_property(_goddess, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
		handoff.tween_property(_bg_goddess, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
		handoff.chain().tween_callback(_goddess.hide)

	# ...the soul surges as it absorbs the magic...
	var surge := create_tween()
	surge.tween_property(_soul, "scale", Vector2(1.55, 1.55), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	surge.tween_property(_soul, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	# B/C) ...and casts one seed per gate; each landing births a door.
	var land_last := 0.0
	for i in range(_doors.size()):
		var bundle := _doors[i] as Dictionary
		var root := bundle["root"] as Control
		root.modulate.a = 0.0
		root.pivot_offset = root.size * 0.5
		root.scale = Vector2(0.82, 0.82)
		(bundle["plate"] as Control).modulate.a = 0.0
		(bundle["chips"] as Control).modulate.a = 0.0
		var door_center: Vector2 = root.position + root.size * 0.5
		var launch := 0.5 + 0.14 * float(i)
		var flight := 0.5
		var land := launch + flight
		land_last = maxf(land_last, land)
		_launch_seed(door_center, launch, flight, bundle["accent"] as Color)
		_schedule_reveal_fx(door_center, root.size, bundle["accent"] as Color, land)

		var materialize := create_tween().set_parallel(true)
		materialize.tween_property(root, "modulate:a", 1.0, 0.28).set_delay(land)
		materialize.tween_property(root, "scale", Vector2.ONE, 0.7) \
			.set_delay(land).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		materialize.tween_property(bundle["plate"], "modulate:a", 1.0, 0.4).set_delay(land + 0.3)
		materialize.tween_property(bundle["chips"], "modulate:a", 1.0, 0.4).set_delay(land + 0.42)

	# D) headings settle once the last gate stands; then the soul chooses.
	var heading := create_tween().set_parallel(true)
	heading.tween_property(_reveal_title, "modulate:a", 1.0, 0.6).set_delay(land_last + 0.25)
	heading.tween_property(_reveal_flourish, "modulate:a", 1.0, 0.6).set_delay(land_last + 0.38)
	heading.tween_property(_tagline_label, "modulate:a", 1.0, 0.6).set_delay(land_last + 0.55)
	heading.tween_property(_hint_label, "modulate:a", 1.0, 0.6).set_delay(land_last + 0.68)

	_focus_index = 0
	var finish := create_tween()
	finish.tween_interval(land_last + 0.7)
	finish.tween_callback(func() -> void:
		_reveal_ready = true
		_set_focus(0, true))

## A small glowing light-seed flies from the soul to a door position, trailing
## sparks, and vanishes on arrival (the reveal FX takes over from there).
func _launch_seed(target: Vector2, delay: float, flight: float, accent: Color) -> void:
	var seed := TextureRect.new()
	seed.texture = _make_radial_texture(
		Color(1.0, 1.0, 1.0, 0.95), Color(accent.r, accent.g, accent.b, 0.0), 0.5, true
	)
	seed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seed.size = Vector2(44, 44)
	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	seed.material = add_material
	seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed.z_index = 6
	seed.visible = false
	seed.position = _soul_anchor - seed.size * 0.5
	add_child(seed)

	var trail := CPUParticles2D.new()
	trail.position = seed.size * 0.5
	trail.amount = 20
	trail.lifetime = 0.55
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 4.0
	trail.initial_velocity_max = 16.0
	trail.scale_amount_min = 1.0
	trail.scale_amount_max = 2.0
	trail.color = Color(accent.r, accent.g, accent.b, 0.6)
	trail.emitting = false
	seed.add_child(trail)

	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		seed.visible = true
		seed.position = _soul_anchor - seed.size * 0.5
		trail.emitting = true)
	tween.tween_property(seed, "position", target - seed.size * 0.5, flight) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: trail.emitting = false)
	tween.tween_property(seed, "modulate:a", 0.0, 0.12)
	tween.tween_interval(0.6)   # let the last trail sparks die before freeing
	tween.tween_callback(seed.queue_free)

func _schedule_reveal_fx(center: Vector2, door_size: Vector2, accent: Color, at: float) -> void:
	var tween := create_tween()
	tween.tween_interval(at)
	tween.tween_callback(_spawn_reveal_fx.bind(center, door_size, accent))

## The moment a seed lands: pillar of light + rune-ring flash + radial bloom
## behind the door, and a one-shot golden burst of sparks over it.
func _spawn_reveal_fx(center: Vector2, door_size: Vector2, accent: Color) -> void:
	var vp := get_viewport_rect().size
	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var beam := TextureRect.new()
	beam.texture = _make_beam_texture(accent)
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.size = Vector2(door_size.x * 0.95, vp.y * 1.1)
	beam.position = center - beam.size * 0.5
	beam.pivot_offset = beam.size * 0.5
	beam.scale = Vector2(0.1, 1.0)
	beam.material = add_material
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_root.add_child(beam)
	_reveal_root.move_child(beam, 0)
	var beam_tween := create_tween()
	beam_tween.tween_property(beam, "scale:x", 1.0, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	beam_tween.tween_property(beam, "modulate:a", 0.0, 0.5) \
		.set_delay(0.08).set_trans(Tween.TRANS_SINE)
	beam_tween.tween_callback(beam.queue_free)

	var bloom := TextureRect.new()
	bloom.texture = _make_radial_texture(
		Color(1.0, 0.95, 0.8, 0.85), Color(accent.r, accent.g, accent.b, 0.0), 0.5, true
	)
	bloom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bloom.size = Vector2(460, 460)
	bloom.position = center - bloom.size * 0.5
	bloom.pivot_offset = bloom.size * 0.5
	bloom.scale = Vector2(0.55, 0.55)
	bloom.material = add_material.duplicate()
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_root.add_child(bloom)
	_reveal_root.move_child(bloom, 0)
	var bloom_tween := create_tween().set_parallel(true)
	bloom_tween.tween_property(bloom, "scale", Vector2(1.3, 1.3), 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bloom_tween.tween_property(bloom, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE)
	bloom_tween.chain().tween_callback(bloom.queue_free)

	var ring := TextureRect.new()
	ring.texture = _art("rune_ring.png")
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.size = Vector2(320, 320)
	ring.position = center - ring.size * 0.5
	ring.pivot_offset = ring.size * 0.5
	ring.scale = Vector2(0.3, 0.3)
	ring.material = add_material.duplicate()
	ring.modulate = Color(accent.r * 0.6 + 0.4, accent.g * 0.6 + 0.4, accent.b * 0.6 + 0.4, 0.95)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_root.add_child(ring)
	var ring_tween := create_tween().set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector2(1.15, 1.15), 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring, "rotation", 0.7, 0.6)
	ring_tween.tween_property(ring, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	ring_tween.chain().tween_callback(ring.queue_free)

	var burst := CPUParticles2D.new()
	burst.position = center
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 46
	burst.lifetime = 0.95
	burst.spread = 180.0
	burst.gravity = Vector2(0, 150.0)
	burst.initial_velocity_min = 70.0
	burst.initial_velocity_max = 200.0
	burst.scale_amount_min = 1.4
	burst.scale_amount_max = 3.0
	burst.color = Color(
		accent.r * 0.5 + 0.5, accent.g * 0.5 + 0.45, accent.b * 0.5 + 0.35, 0.9
	)
	burst.emitting = true
	_reveal_root.add_child(burst)
	var burst_tween := create_tween()
	burst_tween.tween_interval(1.3)
	burst_tween.tween_callback(burst.queue_free)

## Vertical pillar-of-light texture: bright core, soft horizontal falloff.
func _make_beam_texture(accent: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(accent.r, accent.g, accent.b, 0.0),
		Color(1.0, 0.97, 0.86, 0.85),
		Color(accent.r, accent.g, accent.b, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 64
	return texture

func _confirm_choice() -> void:
	if _phase != Phase.REVEAL or _doors.is_empty():
		return
	_phase = Phase.CONFIRMING
	var bundle := _doors[_focus_index] as Dictionary
	var candidate := bundle["candidate"] as Dictionary
	var run_id := str(candidate.get("run_id", ""))
	_chosen_candidate = candidate
	print("[WorldGacha] soul chose world run=%s (%s)" % [run_id, str(candidate.get("world_name_en", ""))])

	# The soul flies through the chosen door; light floods out of it.
	var root := bundle["root"] as Control
	var door_center: Vector2 = root.position + root.size * 0.5 - Vector2(0, 20)
	var glow := bundle["glow"] as TextureRect
	var accent := bundle["accent"] as Color

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "_soul_anchor", door_center, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_soul, "scale", Vector2(0.25, 0.25), 0.85) \
		.set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_soul, "modulate:a", 0.0, 0.35).set_delay(0.75)
	tween.tween_property(glow, "modulate:a", 1.0, 0.8).set_delay(0.3)

	# The moment the soul crosses the threshold, white light pours OUT OF THE
	# DOOR and swallows the screen, carrying us straight into the download UI.
	var ignite := create_tween()
	ignite.tween_interval(0.72)
	ignite.tween_callback(_ignite_door_light.bind(door_center, run_id, accent))

## Radiating white light from the chosen door: a warm-white radial burst with a
## solid core grows from the door center until its core covers the farthest
## screen corner, then the full-screen flash takes over seamlessly and the
## loading overlay crossfades in beneath it.
func _ignite_door_light(center: Vector2, run_id: String, accent: Color) -> void:
	var vp := get_viewport_rect().size
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 0.97, 0.88, 1.0), Color(1.0, 0.97, 0.88, 1.0), Color(1.0, 0.94, 0.8, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 512
	texture.height = 512

	var light := TextureRect.new()
	light.texture = texture
	light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	light.size = Vector2(1600, 1600)
	light.position = center - light.size * 0.5
	light.pivot_offset = light.size * 0.5
	light.scale = Vector2(0.1, 0.1)
	light.modulate.a = 0.0
	light.z_index = 9   # above the scene, below the loading overlay (z 10)
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(light)

	# The solid core (55% of the radius) must reach the farthest corner.
	var corner_distance := 0.0
	for corner in [Vector2.ZERO, Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		corner_distance = maxf(corner_distance, center.distance_to(corner))
	var final_scale := corner_distance / (0.55 * light.size.x * 0.5) * 1.08

	var tween := create_tween().set_parallel(true)
	tween.tween_property(light, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "scale", Vector2(final_scale, final_scale), 0.85) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		_flash.color.a = 1.0        # seamless: the core is already wall-to-wall white
		light.queue_free()
		_start_chosen_world(run_id, accent))

func _start_chosen_world(run_id: String, _accent: Color) -> void:
	_show_loading(SettingsManager.text("gacha.reincarnating"))
	# Cross-fade out of the white flash into the loading panel — no hard cut.
	_loading_overlay.modulate.a = 0.0
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_loading_overlay, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	fade.tween_property(_flash, "color:a", 0.0, 0.9).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	if has_meta("qa_offline"):
		return
	if not ChapterFlow.loading_status.is_connected(_on_flow_status):
		ChapterFlow.loading_status.connect(_on_flow_status)
	_launch_flow(run_id)

func _launch_flow(run_id: String) -> void:
	var flow_error: Error = await ChapterFlow.start_game_with_run(run_id)
	if flow_error != OK:
		print("[WorldGacha] flow start failed err=%d" % flow_error)
		_hide_loading()
		_enter_error(true)
		_searching_root.modulate.a = 1.0
		_searching_root.show()
		_reveal_root.hide()
		_soul.modulate.a = 1.0
		_soul.scale = Vector2.ONE
		_goddess.modulate = Color.WHITE
		_goddess.show()
		_bg_goddess.modulate.a = 0.0
		_goddess_idle = true
		_goddess_strength = 1.0
		_layout()   # ERROR phase → goddess back to her large searching pose
	# On success ChapterFlow has switched the scene (intro slides or world).

const LOAD_MILESTONES: Array = [
	["Connecting", 0.10],
	["Fetching item icons", 0.32],
	["Fetching chapter map", 0.44],
	["Fetching world map", 0.52],
	["Fetching chapter intro", 0.78],
	["Downloading ", 0.88],
	["Building world", 0.96],
]

## ChapterFlow's statuses are English-authored; show them in the player's
## language (unknown ones pass through untouched).
const STATUS_KEYS := {
	"Connecting to story server...": "menu.connecting",
	"Fetching item icons...": "gacha.st_items",
	"Fetching chapter map illustration...": "gacha.st_chapter_map",
	"Fetching world map illustration...": "gacha.st_world_map",
	"Fetching chapter intro...": "gacha.st_intro",
	"Building world...": "gacha.st_build",
}

func _localized_status(message: String) -> String:
	if STATUS_KEYS.has(message):
		return SettingsManager.text(STATUS_KEYS[message] as String)
	if message.begins_with("Downloading ") and message != SettingsManager.text("gacha.loading_music"):
		var zone_name := message.trim_prefix("Downloading ").trim_suffix("...")
		return SettingsManager.text("gacha.st_zone") % zone_name
	return message

func _on_flow_status(message: String) -> void:
	_loading_status.text = _localized_status(message)
	_loading_chapter.text = ChapterFlow.progress_label()
	_bump_progress(message)

## Advance the door-opening target from known loading milestones; unknown
## statuses still inch it forward so the screen always feels alive.
func _bump_progress(message: String) -> void:
	var target := 0.0
	if message == SettingsManager.text("gacha.loading_music"):
		target = 0.66
	else:
		for milestone in LOAD_MILESTONES:
			if message.begins_with(milestone[0] as String):
				target = milestone[1] as float
				break
	if target <= _ld_target:
		target = minf(_ld_target + 0.04, 0.95)
	_ld_target = target

func _show_loading(initial_status: String) -> void:
	# The white flash covers this moment — retire the reveal/searching layers so
	# nothing ghosts through the loading screen's dim.
	_reveal_root.hide()
	_searching_root.hide()
	_loading_chapter.text = ""
	_loading_status.text = _localized_status(initial_status)
	_ld_progress = 0.0
	_ld_target = 0.08
	_refresh_loading_copy()
	var gate_texture: Texture2D = _chosen_candidate.get("gate_texture")
	var aperture_aspect := LOADING_APERTURE_SOURCE.size.x / LOADING_APERTURE_SOURCE.size.y
	_ld_art.texture = _cropped_to_aspect(gate_texture, aperture_aspect) if gate_texture != null else null
	var accent := Color.from_string(str(_chosen_candidate.get("accent_color", "")), UiKit.COLOR_ACCENT)
	_ld_glow.self_modulate = accent.lerp(Color.WHITE, 0.55)
	for leaf: TextureRect in [_ld_leaf_left, _ld_leaf_right]:
		leaf.scale = Vector2.ONE
		leaf.modulate = Color.WHITE
	_ld_art.modulate = Color(0.55, 0.55, 0.55, 1.0)
	_ld_glow.modulate.a = 0.16
	_ld_soul.modulate = Color.WHITE
	_ld_soul.scale = Vector2(0.76, 0.76)
	_loading_overlay.show()

func _refresh_loading_copy() -> void:
	if _chosen_candidate.is_empty():
		_ld_plate_label.text = ""
		return
	_ld_plate_label.text = _candidate_text(_chosen_candidate, "world_name").to_upper()
	_fit_label_font(_ld_plate_label, 212.0, 15, 11)

func _hide_loading() -> void:
	_loading_overlay.hide()

# ── Focus / input ─────────────────────────────────────────────────────────────

func _set_focus(index: int, animated: bool) -> void:
	if _phase != Phase.REVEAL or _doors.is_empty():
		return
	_focus_index = clampi(index, 0, _doors.size() - 1)
	for i in range(_doors.size()):
		var bundle := _doors[i] as Dictionary
		var focused := i == _focus_index
		var root := bundle["root"] as Control
		var glow := bundle["glow"] as TextureRect
		var plate_lit := bundle["plate_lit"] as TextureRect
		var name_label := bundle["name_label"] as Label
		var target_modulate := Color.WHITE if focused else COLOR_DIM_UNFOCUSED
		var target_scale := Vector2(1.045, 1.045) if focused else Vector2.ONE
		var glow_alpha := 0.55 if focused else 0.0
		var plate_alpha := 1.0 if focused else 0.0
		var name_color := COLOR_NAME_LIT if focused else COLOR_NAME_IDLE
		if animated:
			var tween := create_tween().set_parallel(true)
			tween.tween_property(root, "modulate", target_modulate, 0.22)
			tween.tween_property(root, "scale", target_scale, 0.22) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(glow, "modulate:a", glow_alpha, 0.25)
			tween.tween_property(plate_lit, "modulate:a", plate_alpha, 0.2)
			tween.tween_property(name_label, "theme_override_colors/font_color", name_color, 0.2)
		else:
			root.modulate = target_modulate
			root.scale = target_scale
			glow.modulate.a = glow_alpha
			plate_lit.modulate.a = plate_alpha
			name_label.add_theme_color_override("font_color", name_color)

	var focused_bundle := _doors[_focus_index] as Dictionary
	var focused_root := focused_bundle["root"] as Control
	var hover := focused_root.position + Vector2(focused_root.size.x * 0.5, focused_root.size.y * 0.86)
	if animated:
		var soul_tween := create_tween()
		soul_tween.tween_property(self, "_soul_anchor", hover, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_soul_anchor = hover
	_refresh_tagline()

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.REVEAL:
		if event.is_action_pressed("ui_cancel"):
			_back_to_menu()
			get_viewport().set_input_as_handled()
			return
		if not _reveal_ready:
			return   # navigation unlocks once the gates finish materializing
		if event.is_action_pressed("ui_left"):
			_set_focus(_focus_index - 1, true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			_set_focus(_focus_index + 1, true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_confirm_choice()
			get_viewport().set_input_as_handled()
	elif _phase == Phase.SEARCHING or _phase == Phase.ERROR:
		if event.is_action_pressed("ui_cancel"):
			var viewport := get_viewport()
			_back_to_menu()
			if viewport != null:
				viewport.set_input_as_handled()

func _back_to_menu() -> void:
	get_tree().change_scene_to_file(START_SCENE_PATH)

# ── Per-frame ambience ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta

	if _searching_root.visible:
		_ring_outer.rotation += delta * 0.22
		_ring_inner.rotation -= delta * 0.34
		var breath := 0.9 + 0.1 * sin(_time * 1.8)
		_ring_outer.modulate.a = (0.9 if _phase != Phase.ERROR else 0.35) * breath
		_ring_inner.modulate.a = (0.5 if _phase != Phase.ERROR else 0.2) * breath

	_soul_halo.modulate.a = 0.7 + 0.3 * sin(_time * 2.3)
	var bob := Vector2(sin(_time * 1.1) * 3.0, sin(_time * 1.7) * 5.0)
	_soul.position = _soul_anchor + bob

	if _goddess.visible and _goddess_idle:
		_animate_goddess(_goddess, _goddess_strength)
	if _loading_overlay.visible:
		# The opening door IS the progress bar: creep the target so motion never
		# stalls, smooth the displayed value, and drive every element from it.
		_ld_target = clampf(_ld_target + delta * 0.006, 0.0, 0.97)
		_ld_progress = lerpf(_ld_progress, _ld_target, minf(delta * 2.0, 1.0))
		var open := clampf((_ld_progress - 0.10) / 0.85, 0.0, 1.0)
		var eased := open * open * (3.0 - 2.0 * open)
		_ld_leaf_left.scale.x = 1.0 - 0.94 * eased
		_ld_leaf_right.scale.x = 1.0 - 0.94 * eased
		var leaf_shade := 1.0 - 0.22 * eased
		# fully-open doors dissolve so no hinge sliver lingers over the light
		var leaf_alpha := 1.0 - clampf((eased - 0.86) / 0.14, 0.0, 1.0)
		_ld_leaf_left.modulate = Color(leaf_shade, leaf_shade, leaf_shade, leaf_alpha)
		_ld_leaf_right.modulate = _ld_leaf_left.modulate
		_ld_glow.modulate.a = (0.16 + 0.84 * eased) * (0.85 + 0.15 * sin(_time * 2.4))
		var art_lum := 0.55 + 0.45 * eased
		_ld_art.modulate = Color(art_lum, art_lum, art_lum, 1.0)
		var travel := clampf(_ld_progress / 0.95, 0.0, 1.0)
		if _ld_route.get_point_count() > 1:
			var route_offset := _ld_route.get_baked_length() * travel
			_ld_soul.position = _ld_route.sample_baked(route_offset, true) \
				+ Vector2(0.0, sin(_time * 1.7) * 1.8)
		var perspective := lerpf(0.76, 0.24, travel * travel * (3.0 - 2.0 * travel))
		_ld_soul.scale = Vector2(perspective, perspective)
		_ld_soul.modulate.a = 1.0 - 0.65 * smoothstep(0.82, 1.0, travel)
		var loading_halo := _ld_soul.get_node_or_null("Halo") as TextureRect
		if loading_halo != null:
			loading_halo.modulate.a = 0.72 + 0.28 * sin(_time * 2.5)
		_ld_path.modulate.a = 0.72 + 0.18 * sin(_time * 1.9)
		_ld_percent.text = "%d%%" % int(round(_ld_progress * 100.0))

	if _phase == Phase.REVEAL and _reveal_ready and not _doors.is_empty():
		var bundle := _doors[_focus_index] as Dictionary
		var glow := bundle["glow"] as TextureRect
		if glow.modulate.a > 0.0:
			glow.modulate.a = 0.42 + 0.16 * sin(_time * 2.6)
		_hint_label.modulate.a = 0.62 + 0.38 * (sin(_time * 2.1) * 0.5 + 0.5)

## Divine idle motion: slow bob, breathing scale, pulsing aura + veil.
func _animate_goddess(group: Control, strength: float) -> void:
	if group.get_child_count() == 0 or not group.has_meta("base_y"):
		return
	group.position.y = float(group.get_meta("base_y")) + sin(_time * 0.85) * 6.0 * strength
	var breath := 1.0 + 0.011 * strength * sin(_time * 1.35)
	group.scale = Vector2(breath, breath)
	(group.get_node("Glow") as TextureRect).modulate.a = (0.22 + 0.13 * sin(_time * 1.1)) * strength
	(group.get_node("Veil") as TextureRect).modulate.a = (0.75 + 0.25 * sin(_time * 0.7)) * minf(strength, 1.0)

func _play_entrance() -> void:
	var fade := create_tween()
	fade.tween_property(_intro_fade, "color:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(_intro_fade.hide)

	_soul.scale = Vector2(0.4, 0.4)
	var soul_in := create_tween()
	soul_in.tween_property(_soul, "scale", Vector2.ONE, 1.4) \
		.set_delay(0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ── Localization ─────────────────────────────────────────────────────────────

func _is_vi() -> bool:
	return SettingsManager.language == "vi"

func _candidate_text(candidate: Dictionary, base: String) -> String:
	return str(candidate.get(base + ("_vi" if _is_vi() else "_en"), ""))

func _refresh_localized_copy() -> void:
	_search_title.text = SettingsManager.text("gacha.searching_title")
	_search_sub.text = SettingsManager.text("gacha.searching_sub")
	_reveal_title.text = SettingsManager.text("gacha.title")
	_hint_label.text = SettingsManager.text("gacha.hint")
	_refresh_loading_copy()
	if _phase == Phase.ERROR:
		_search_title.text = SettingsManager.text("gacha.error")
		_search_sub.text = SettingsManager.text("gacha.error_hint")
	_refresh_candidate_copy()

func _refresh_candidate_copy() -> void:
	for bundle_variant in _doors:
		var bundle := bundle_variant as Dictionary
		var candidate := bundle["candidate"] as Dictionary
		var name_label := bundle["name_label"] as Label
		name_label.text = _candidate_text(candidate, "world_name").to_upper()
		_fit_label_font(name_label, 196.0, 15, 11)
		_rebuild_chips(bundle)
	_refresh_tagline()

## Shrink a caption's font size until its shaped width fits max_width (longest
## VI world names would otherwise spill past the plaque's pointed tips).
func _fit_label_font(label: Label, max_width: float, size_max: int, size_min: int) -> void:
	var font := label.get_theme_font("font")
	if font == null:
		return
	for size in range(size_max, size_min - 1, -1):
		label.add_theme_font_size_override("font_size", size)
		if font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size
		).x <= max_width or size == size_min:
			break

func _refresh_tagline() -> void:
	if _doors.is_empty():
		_tagline_label.text = ""
		return
	var bundle := _doors[_focus_index] as Dictionary
	var candidate := bundle["candidate"] as Dictionary
	var text := "“%s”" % _candidate_text(candidate, "tagline")
	var chapter_count := int(candidate.get("chapter_count", 0))
	if chapter_count > 0:
		text += "   ·   %d %s" % [chapter_count, "CHƯƠNG" if _is_vi() else ("CHAPTERS" if chapter_count > 1 else "CHAPTER")]
	_tagline_label.text = text

func _on_language_changed(_locale: String) -> void:
	_refresh_localized_copy()

# ── Ambient builders ─────────────────────────────────────────────────────────

func _make_motes(far: bool) -> CPUParticles2D:
	var motes := CPUParticles2D.new()
	var vp := get_viewport_rect().size
	motes.position = Vector2(vp.x * 0.5, vp.y + 12.0)
	motes.amount = 16 if far else 26
	motes.lifetime = 12.0 if far else 8.5
	motes.preprocess = 10.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(vp.x * 0.55, 6.0)
	motes.direction = Vector2(0, -1)
	motes.spread = 14.0
	motes.gravity = Vector2(0, -12.0)
	motes.initial_velocity_min = 12.0 if far else 26.0
	motes.initial_velocity_max = 28.0 if far else 60.0
	motes.scale_amount_min = 1.1 if far else 1.4
	motes.scale_amount_max = 2.2 if far else 3.0
	motes.color = Color(0.62, 0.88, 0.95, 0.18) if far else Color(1.0, 0.82, 0.48, 0.5)
	return motes

func _make_radial_texture(inner: Color, outer: Color, radius: float, small: bool = false) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([inner, outer])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.5 - radius)
	texture.width = 128 if small else 512
	texture.height = 128 if small else 288
	return texture
