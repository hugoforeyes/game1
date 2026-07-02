extends CanvasLayer
## Story-driven turn-based battle — production presentation layer.
##
## Combat rules: the enemy telegraphs its next move one turn ahead (Guard to
## blunt it), and its story weakness can be discovered mid-fight through Probe
## dialogue choices. Exposing the weakness multiplies damage and unlocks a
## finisher.
##
## Presentation: AI-generated UI kit (ornate panel 9-slice, menu cursor, slash
## effect frames, backdrop, victory ornament) + animated portraits (entrance,
## breathing, lunge, hit-flash, exposed glow), screen shake, particles, damage
## numbers, ghost HP bars, and victory/level-up celebrations. Every asset is
## optional — missing art falls back to flat styles so the battle always runs.

signal battle_finished(result: String, enemy_id: String)

const FONT_SIZE := 16
const TYPE_SPEED := 46.0

const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.00)
const COLOR_TEXT_DIM := Color(0.93, 0.88, 0.75, 0.40)
const COLOR_ACCENT := Color(1.00, 0.85, 0.45, 1.00)
const COLOR_PANEL_BG := Color(0.05, 0.04, 0.13, 0.92)
const COLOR_PANEL_BORDER := Color(0.78, 0.60, 0.26, 0.65)
const COLOR_HP := Color(0.82, 0.25, 0.28, 1.0)
const COLOR_HP_GHOST := Color(0.95, 0.82, 0.55, 0.9)
const COLOR_HP_BG := Color(0.16, 0.06, 0.09, 0.95)
const COLOR_PLAYER_HP := Color(0.32, 0.70, 0.38, 1.0)
const COLOR_XP := Color(0.45, 0.55, 0.90, 1.0)
const COLOR_EXPOSED := Color(0.95, 0.45, 0.95, 1.0)
const COLOR_CRIT := Color(1.0, 0.78, 0.25, 1.0)
const COLOR_PLAYER_DMG := Color(1.0, 0.42, 0.38, 1.0)
const COLOR_HEAL := Color(0.55, 0.95, 0.60, 1.0)

const TEX_PANEL := "res://assets/ui/battle/panel.png"
const TEX_CURSOR := "res://assets/ui/battle/cursor.png"
const TEX_SLASH := "res://assets/ui/battle/slash_sheet.png"
const TEX_BACKDROP := "res://assets/ui/battle/backdrop.png"
const TEX_BANNER := "res://assets/ui/battle/banner.png"
const TEX_B2_COMMAND := "res://assets/ui/battle_v2/command_card.png"
const TEX_B2_COMMAND_SELECTED := "res://assets/ui/battle_v2/command_card_selected.png"
const TEX_B2_ENEMY := "res://assets/ui/battle_v2/panel_enemy.png"
const TEX_B2_INTENT := "res://assets/ui/battle_v2/panel_intent.png"
const TEX_B2_LOG := "res://assets/ui/battle_v2/panel_log.png"
const TEX_B2_PLAYER := "res://assets/ui/battle_v2/panel_player.png"
const TEX_B2_ORNAMENT := "res://assets/ui/battle_v2/ornament_gem.png"
const TEX_B2_TURN_ORDER_ENEMY := "res://assets/ui/battle_v2/turn_order_card_enemy.png"
const TEX_B2_TURN_ORDER_ALLY := "res://assets/ui/battle_v2/turn_order_card_ally.png"
const TEX_B2_ICON_ATTACK := "res://assets/ui/battle_v2/icons/icon_attack.png"
const TEX_B2_ICON_SKILL := "res://assets/ui/battle_v2/icons/icon_skill.png"
const TEX_B2_ICON_PROBE := "res://assets/ui/battle_v2/icons/icon_probe.png"
const TEX_B2_ICON_ITEM := "res://assets/ui/battle_v2/icons/icon_item.png"
const TEX_B2_ICON_GUARD := "res://assets/ui/battle_v2/icons/icon_guard.png"
const TEX_B2_ICON_FLEE := "res://assets/ui/battle_v2/icons/icon_flee.png"
const TEX_B2_ICON_FINISHER := "res://assets/ui/battle_v2/icons/icon_finisher.png"
const TEX_B2_ICON_SPARE := "res://assets/ui/battle_v2/icons/icon_spare.png"

enum UiMode { NONE, TYPING, CONFIRM, MENU }

signal _confirmed
signal _menu_picked(id: String)

# ── combat state (unchanged rules) ───────────────────────────────────────────
var enemy: Dictionary = {}
var enemy_id: String = ""
var enemy_hp: int = 1
var enemy_max_hp: int = 1
var enemy_attack: int = 1
var enemy_defense: int = 0
var enemy_speed: int = 1

var player_stats: Dictionary = {}
var player_sp: int = 0
var focus_active: bool = false
var hexed: bool = false
var guarding: bool = false
var _companion_levelups: Array = []  # companions that leveled during the last XP grant

var exposed_turns: int = 0
var finisher_used: bool = false
var weakness_found: bool = false
var probe_options: Array = []
var triggered_phases: Dictionary = {}
var phase_damage_bonus: float = 1.0
var phase_defense_factor: float = 1.0
var intent: Dictionary = {}
var turns_since_heavy: int = 99
var flee_failed_count: int = 0

var _ui_mode: UiMode = UiMode.NONE
var _type_target: String = ""
var _type_progress: float = 0.0
var _menu_ids: Array[String] = []
var _menu_items: Array[Control] = []
var _menu_index: int = 0
var _battle_over: bool = false

# ── presentation state ───────────────────────────────────────────────────────
var _panel_style: StyleBox = null
var _cursor_texture: Texture2D = null
var _slash_frames: SpriteFrames = null
var _banner_texture: Texture2D = null
var _texture_cache: Dictionary = {}

var _shake_time: float = 0.0
var _shake_strength: float = 0.0

var _root: Control
# Centered 960x540 canvas the battle layout is authored in; the dim/backdrop
# stay full-screen on _root so wider viewports have no empty side bands.
var _design: Control
var _fx_layer: Control
var _enemy_panel: Panel
var _enemy_name_label: Label
var _enemy_rank_label: Label
var _enemy_hp_bar: ColorRect
var _enemy_hp_ghost: ColorRect
var _enemy_status_label: Label
var _intent_label: Label
var _intent_panel: Panel
var _intent_name_label: Label
var _portrait_holder: Control
var _portrait: TextureRect
var _portrait_flash: TextureRect
var _portrait_glow: TextureRect
var _log_panel: Panel
var _log_label: Label
var _continue_marker: Label
var _menu_panel: Panel
var _menu_row: HBoxContainer
var _menu_cursor: Control
var _hint_label: Label
var _player_panel: Panel
var _player_panel_label: Label
var _player_hp_bar: ColorRect
var _player_hp_ghost: ColorRect
var _xp_bar: ColorRect
var _sp_pips: Array[ColorRect] = []
var _sp_pip_row: Control

const ENEMY_HP_BAR_W := 206.0
const PLAYER_HP_BAR_W := 154.0
const PORTRAIT_HOME := Vector2(350, 48)
const PORTRAIT_SIZE := Vector2(280, 290)
const PLAYER_FX_CENTER := Vector2(146, 430)
const SCREEN_CENTER := Vector2(480, 270)


func open(enemy_data: Dictionary) -> void:
	enemy = enemy_data
	enemy_id = str(enemy.get("id", ""))
	var stats: Dictionary = enemy.get("stats", {}) as Dictionary
	enemy_max_hp = max(int(stats.get("max_hp", 40)), 1)
	enemy_hp = enemy_max_hp
	enemy_attack = max(int(stats.get("attack", 8)), 1)
	enemy_defense = max(int(stats.get("defense", 2)), 0)
	enemy_speed = max(int(stats.get("speed", 6)), 1)

	player_stats = GameManager.player_battle_stats()
	player_sp = int(player_stats.get("sp_max", 3))
	probe_options = ((enemy.get("weakness", {}) as Dictionary).get("probe_options", []) as Array).duplicate(true)

	GameManager.ui_blocking_input = true
	layer = 80
	transform = Transform2D.IDENTITY
	# Announce companion level-ups earned from their share of battle XP.
	if not GameManager.companion_leveled.is_connected(_on_companion_leveled):
		GameManager.companion_leveled.connect(_on_companion_leveled)
	_load_ui_kit()
	_build_ui()
	_run_battle()


# ── asset loading ─────────────────────────────────────────────────────────────


func _load_ui_kit() -> void:
	if ResourceLoader.exists(TEX_PANEL):
		var panel_texture: Texture2D = load(TEX_PANEL)
		var style := StyleBoxTexture.new()
		style.texture = panel_texture
		style.set_texture_margin_all(11.0)
		style.set_content_margin_all(4.0)
		_panel_style = style
	if ResourceLoader.exists(TEX_CURSOR):
		_cursor_texture = load(TEX_CURSOR)
	if ResourceLoader.exists(TEX_BANNER):
		_banner_texture = load(TEX_BANNER)
	if ResourceLoader.exists(TEX_SLASH):
		var sheet: Texture2D = load(TEX_SLASH)
		_slash_frames = SpriteFrames.new()
		_slash_frames.remove_animation("default")
		_slash_frames.add_animation("slash")
		_slash_frames.set_animation_speed("slash", 16.0)
		_slash_frames.set_animation_loop("slash", false)
		for index in range(4):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(index * 96, 0, 96, 96)
			_slash_frames.add_frame("slash", atlas)


func _load_png_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture


func _make_panel_style(bg: Color = COLOR_PANEL_BG, border: Color = COLOR_PANEL_BORDER, radius: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _make_panel_node(rect: Rect2, danger: bool = false) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var bg := Color(0.08, 0.02, 0.03, 0.86) if danger else Color(0.015, 0.02, 0.035, 0.84)
	var border := Color(0.88, 0.20, 0.18, 0.72) if danger else COLOR_PANEL_BORDER
	panel.add_theme_stylebox_override("panel", _make_panel_style(bg, border))
	return panel


func _add_texture(parent: Control, path: String, rect: Rect2, alpha: float = 1.0, behind: bool = false) -> TextureRect:
	var texture := _load_png_texture(path)
	var node := TextureRect.new()
	node.position = rect.position
	node.size = rect.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.modulate.a = alpha
	if texture != null:
		node.texture = texture
	if behind:
		parent.add_child(node)
		parent.move_child(node, 0)
	else:
		parent.add_child(node)
	return node


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


# ── ui construction ───────────────────────────────────────────────────────────


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Backdrop: generated art if present, plus dim so the world fades out.
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.016, 0.024, 0.90)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var backdrop_texture := _load_battle_backdrop_texture()
	if backdrop_texture != null:
		var backdrop := TextureRect.new()
		backdrop.texture = backdrop_texture
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.modulate = Color(1, 1, 1, 0.9)
		_root.add_child(backdrop)

	_design = Control.new()
	_design.position = ((get_viewport().get_visible_rect().size - Vector2(960, 540)) * 0.5).floor()
	_design.size = Vector2(960, 540)
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_design)

	# ── enemy panel (slides in from the top) ──
	_enemy_panel = _make_panel_node(Rect2(24, 24, 260, 104))
	_design.add_child(_enemy_panel)
	_add_texture(_enemy_panel, TEX_B2_ENEMY, Rect2(-6, -6, 272, 116), 0.58, true)

	var enemy_kicker := _make_label("ENEMY", 13, COLOR_ACCENT)
	enemy_kicker.position = Vector2(18, 12)
	enemy_kicker.size = Vector2(100, 18)
	_enemy_panel.add_child(enemy_kicker)

	_enemy_name_label = _make_label("", 24, COLOR_TEXT)
	_enemy_name_label.position = Vector2(18, 34)
	_enemy_name_label.size = Vector2(156, 32)
	_enemy_name_label.clip_text = true
	_enemy_panel.add_child(_enemy_name_label)

	_enemy_rank_label = _make_label("", 14, COLOR_TEXT)
	_enemy_rank_label.position = Vector2(174, 36)
	_enemy_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_rank_label.size = Vector2(62, 22)
	_enemy_panel.add_child(_enemy_rank_label)

	var hp_bg := ColorRect.new()
	hp_bg.color = COLOR_HP_BG
	hp_bg.position = Vector2(18, 74)
	hp_bg.size = Vector2(ENEMY_HP_BAR_W, 9)
	_enemy_panel.add_child(hp_bg)

	_enemy_hp_ghost = ColorRect.new()
	_enemy_hp_ghost.color = COLOR_HP_GHOST
	_enemy_hp_ghost.position = hp_bg.position
	_enemy_hp_ghost.size = hp_bg.size
	_enemy_panel.add_child(_enemy_hp_ghost)

	_enemy_hp_bar = ColorRect.new()
	_enemy_hp_bar.color = COLOR_HP
	_enemy_hp_bar.position = hp_bg.position
	_enemy_hp_bar.size = hp_bg.size
	_enemy_panel.add_child(_enemy_hp_bar)

	_enemy_status_label = _make_label("", 13, COLOR_EXPOSED)
	_enemy_status_label.position = Vector2(18, 86)
	_enemy_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status_label.size = Vector2(206, 16)
	_enemy_panel.add_child(_enemy_status_label)

	# ── intent panel ──
	_intent_panel = _make_panel_node(Rect2(580, 36, 292, 126), true)
	_design.add_child(_intent_panel)
	_add_texture(_intent_panel, TEX_B2_INTENT, Rect2(-8, -7, 308, 138), 0.58, true)

	_intent_name_label = _make_label("INTENT (NEXT TURN)", 13, COLOR_ACCENT)
	_intent_name_label.position = Vector2(18, 13)
	_intent_name_label.size = Vector2(220, 18)
	_intent_panel.add_child(_intent_name_label)

	_intent_label = _make_label("", 14, COLOR_TEXT_DIM)
	_intent_label.position = Vector2(48, 42)
	_intent_label.size = Vector2(220, 66)
	_intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intent_label.clip_text = true
	_intent_panel.add_child(_intent_label)

	var danger_mark := _make_label("!", 34, Color(1.0, 0.25, 0.20, 0.95))
	danger_mark.position = Vector2(18, 39)
	danger_mark.size = Vector2(24, 38)
	danger_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_panel.add_child(danger_mark)

	_build_turn_order_strip()

	# ── portrait (entrance from the right, then breathes) ──
	_portrait_holder = Control.new()
	_portrait_holder.position = PORTRAIT_HOME + Vector2(120, 0)
	_portrait_holder.size = PORTRAIT_SIZE
	_portrait_holder.modulate.a = 0.0
	_design.add_child(_portrait_holder)

	_portrait = TextureRect.new()
	_portrait.size = PORTRAIT_SIZE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.pivot_offset = Vector2(PORTRAIT_SIZE.x * 0.5, PORTRAIT_SIZE.y)
	_portrait_holder.add_child(_portrait)
	_load_portrait()

	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_portrait_glow = _portrait.duplicate() as TextureRect
	_portrait_glow.material = add_material
	_portrait_glow.modulate = Color(COLOR_EXPOSED, 0.0)
	_portrait_holder.add_child(_portrait_glow)

	_portrait_flash = _portrait.duplicate() as TextureRect
	_portrait_flash.material = add_material.duplicate()
	_portrait_flash.modulate = Color(1, 1, 1, 0.0)
	_portrait_holder.add_child(_portrait_flash)

	# ── log panel ──
	_log_panel = _make_panel_node(Rect2(24, 198, 282, 126))
	_design.add_child(_log_panel)
	_add_texture(_log_panel, TEX_B2_LOG, Rect2(-8, -7, 298, 140), 0.48, true)

	var log_kicker := _make_label("BATTLE LOG", 13, COLOR_ACCENT)
	log_kicker.position = Vector2(18, 12)
	log_kicker.size = Vector2(180, 18)
	_log_panel.add_child(log_kicker)

	_log_label = _make_label("", FONT_SIZE, COLOR_TEXT)
	_log_label.position = Vector2(20, 42)
	_log_label.size = Vector2(242, 64)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_panel.add_child(_log_label)

	_continue_marker = _make_label("v", FONT_SIZE, COLOR_ACCENT)
	_continue_marker.position = Vector2(252, 94)
	_continue_marker.visible = false
	_log_panel.add_child(_continue_marker)

	# ── menu strip ──
	_menu_panel = _make_panel_node(Rect2(292, 372, 644, 128))
	_menu_panel.visible = false
	_design.add_child(_menu_panel)

	_menu_row = HBoxContainer.new()
	_menu_row.position = Vector2(18, 16)
	_menu_row.size = Vector2(608, 94)
	_menu_row.add_theme_constant_override("separation", 6)
	_menu_panel.add_child(_menu_row)

	_menu_cursor = Control.new()
	var cursor_line := ColorRect.new()
	cursor_line.color = Color(1.0, 0.79, 0.35, 0.95)
	cursor_line.size = Vector2(64, 2)
	_menu_cursor.add_child(cursor_line)
	_menu_cursor.visible = false
	_menu_panel.add_child(_menu_cursor)

	# ── player panel ──
	_player_panel = _make_panel_node(Rect2(24, 364, 260, 136))
	_design.add_child(_player_panel)
	_add_texture(_player_panel, TEX_B2_ORNAMENT, Rect2(6, -4, 82, 25), 0.88)

	_player_panel_label = _make_label("", 16, COLOR_TEXT)
	_player_panel_label.position = Vector2(92, 20)
	_player_panel_label.size = Vector2(138, 34)
	_player_panel.add_child(_player_panel_label)

	var portrait_frame := Panel.new()
	portrait_frame.position = Vector2(18, 24)
	portrait_frame.size = Vector2(56, 72)
	portrait_frame.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.035, 0.92), Color(0.90, 0.66, 0.30, 0.80), 3))
	_player_panel.add_child(portrait_frame)

	var portrait_initial := _make_label("YOU", 18, COLOR_ACCENT)
	portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_initial.size = portrait_frame.size
	portrait_frame.add_child(portrait_initial)

	var player_hp_bg := ColorRect.new()
	player_hp_bg.color = COLOR_HP_BG
	player_hp_bg.position = Vector2(92, 64)
	player_hp_bg.size = Vector2(PLAYER_HP_BAR_W, 8)
	_player_panel.add_child(player_hp_bg)

	_player_hp_ghost = ColorRect.new()
	_player_hp_ghost.color = COLOR_HP_GHOST
	_player_hp_ghost.position = player_hp_bg.position
	_player_hp_ghost.size = player_hp_bg.size
	_player_panel.add_child(_player_hp_ghost)

	_player_hp_bar = ColorRect.new()
	_player_hp_bar.color = COLOR_PLAYER_HP
	_player_hp_bar.position = player_hp_bg.position
	_player_hp_bar.size = player_hp_bg.size
	_player_panel.add_child(_player_hp_bar)

	_sp_pip_row = Control.new()
	_sp_pip_row.position = Vector2(92, 80)
	_player_panel.add_child(_sp_pip_row)
	_build_sp_pips()

	var xp_label := _make_label("XP", 12, COLOR_TEXT_DIM)
	xp_label.position = Vector2(92, 104)
	_player_panel.add_child(xp_label)

	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0.10, 0.10, 0.22, 0.95)
	xp_bg.position = Vector2(122, 110)
	xp_bg.size = Vector2(PLAYER_HP_BAR_W - 30, 5)
	_player_panel.add_child(xp_bg)

	_xp_bar = ColorRect.new()
	_xp_bar.color = COLOR_XP
	_xp_bar.position = xp_bg.position
	_xp_bar.size = xp_bg.size
	_player_panel.add_child(_xp_bar)

	_hint_label = _make_label("Arrows Move    Enter Select    / Esc Back", 13, COLOR_TEXT_DIM)
	_hint_label.position = Vector2(476, 510)
	_hint_label.size = Vector2(420, 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.visible = false
	_design.add_child(_hint_label)

	# ── FX layer on top of everything ──
	_fx_layer = Control.new()
	_fx_layer.position = Vector2.ZERO
	_fx_layer.size = Vector2(960, 540)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(_fx_layer)

	_refresh_enemy_panel()
	_refresh_player_panel()
	_play_intro_animation()


func _build_turn_order_strip() -> void:
	var title := _make_label("TURN ORDER", 12, COLOR_ACCENT)
	title.position = Vector2(858, 176)
	title.size = Vector2(82, 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_design.add_child(title)

	var entries := [
		{"path": TEX_B2_TURN_ORDER_ENEMY, "label": "EN", "color": Color(1.0, 0.38, 0.34, 1.0)},
		{"path": TEX_B2_TURN_ORDER_ALLY, "label": "YOU", "color": Color(0.55, 0.86, 1.0, 1.0)},
		{"path": TEX_B2_TURN_ORDER_ALLY, "label": "SK", "color": Color(0.55, 0.86, 1.0, 0.78)},
		{"path": TEX_B2_TURN_ORDER_ALLY, "label": "IT", "color": Color(0.55, 0.86, 1.0, 0.62)},
	]
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var y := 200 + index * 46
		_add_texture(_design, str(entry["path"]), Rect2(854, y, 86, 36), 0.88)
		var entry_color: Color = entry["color"]
		var label := _make_label(str(entry["label"]), 14, entry_color)
		label.position = Vector2(874, y + 7)
		label.size = Vector2(48, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_design.add_child(label)


func _build_sp_pips() -> void:
	for pip in _sp_pips:
		pip.queue_free()
	_sp_pips.clear()
	var sp_max: int = int(player_stats.get("sp_max", 3))
	for index in range(sp_max):
		var pip := ColorRect.new()
		pip.size = Vector2(10, 10)
		pip.position = Vector2(index * 18 + 5, 2)
		pip.rotation_degrees = 45.0
		pip.pivot_offset = Vector2(5, 5)
		_sp_pip_row.add_child(pip)
		_sp_pips.append(pip)
	_refresh_sp_pips()


func _refresh_sp_pips() -> void:
	for index in range(_sp_pips.size()):
		_sp_pips[index].color = COLOR_ACCENT if index < player_sp else Color(0.25, 0.22, 0.30, 0.9)


func _play_intro_animation() -> void:
	# White flash, panels glide in, portrait enters with a settle bounce.
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.85)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.45)
	flash_tween.tween_callback(flash.queue_free)

	# Slide-in start positions are in _design coordinates; push them past the
	# design canvas' margins so they start fully off-SCREEN, not just off-canvas.
	var off: Vector2 = _design.position
	_enemy_panel.position.y = -150 - off.y
	_intent_panel.position.y = -150 - off.y
	_log_panel.position.x = -320 - off.x
	_menu_panel.position.y = 560 + off.y
	_player_panel.position.x = -320 - off.x

	var slide := create_tween().set_parallel(true)
	slide.tween_property(_enemy_panel, "position:y", 24.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.tween_property(_intent_panel, "position:y", 36.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.tween_property(_log_panel, "position:x", 24.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.tween_property(_menu_panel, "position:y", 372.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.tween_property(_player_panel, "position:x", 24.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(_portrait_holder, "modulate:a", 1.0, 0.4)

	_start_breathing()


func _start_breathing() -> void:
	var breath := create_tween().set_loops()
	breath.tween_property(_portrait, "scale", Vector2(1.0, 1.015), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(_portrait, "scale", Vector2(1.0, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _load_portrait() -> void:
	var portrait_file: String = str(enemy.get("battle_portrait_file", ""))
	var texture: Texture2D = null
	if not portrait_file.is_empty():
		texture = GameManager.load_texture(GameManager.get_scene_asset_path(portrait_file))
	if texture == null:
		var sheet_file: String = str(enemy.get("sprite_sheet_file", ""))
		var sheet: Texture2D = null
		if not sheet_file.is_empty():
			sheet = GameManager.load_texture(GameManager.get_scene_asset_path(sheet_file))
		if sheet == null:
			sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
			_portrait.modulate = Color(1.0, 0.45, 0.45)
		if sheet != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
			texture = atlas
	_portrait.texture = texture
	# High-res AI portraits are minified here — LINEAR keeps their detail.
	# True low-res pixel art (sprite-frame fallbacks) stays NEAREST.
	if texture != null and texture.get_width() > 200:
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _load_battle_backdrop_texture() -> Texture2D:
	var backdrop_file: String = str(enemy.get("battle_background_file", ""))
	if backdrop_file.is_empty():
		var package: Dictionary = GameManager.get_scene_package()
		var battle_background: Dictionary = package.get("battle_background", {}) as Dictionary
		backdrop_file = str(battle_background.get("image", ""))
	if not backdrop_file.is_empty():
		var texture := GameManager.load_texture(GameManager.get_scene_asset_path(backdrop_file))
		if texture != null:
			return texture
	if ResourceLoader.exists(TEX_BACKDROP):
		return load(TEX_BACKDROP) as Texture2D
	return null


# ── battle FX helpers ─────────────────────────────────────────────────────────


func _shake(strength: float, duration: float) -> void:
	_shake_strength = max(_shake_strength, strength)
	_shake_time = max(_shake_time, duration)


func _portrait_center() -> Vector2:
	return _portrait_holder.position + Vector2(PORTRAIT_SIZE.x * 0.5, PORTRAIT_SIZE.y * 0.46)


func _flash_portrait(color: Color = Color(1, 1, 1, 1), strength: float = 0.85) -> void:
	_portrait_flash.modulate = Color(color.r, color.g, color.b, strength)
	var tween := create_tween()
	tween.tween_property(_portrait_flash, "modulate:a", 0.0, 0.28)


func _spawn_slash(at: Vector2, tint: Color = Color(1, 1, 1, 1), effect_scale: float = 1.3, flipped: bool = false) -> void:
	if _slash_frames != null:
		var slash := AnimatedSprite2D.new()
		slash.sprite_frames = _slash_frames
		slash.position = at
		slash.scale = Vector2(-effect_scale if flipped else effect_scale, effect_scale)
		slash.modulate = tint
		slash.rotation_degrees = randf_range(-18.0, 18.0)
		_fx_layer.add_child(slash)
		slash.play("slash")
		slash.animation_finished.connect(slash.queue_free)
	else:
		# Procedural fallback: a quick rotating arc line.
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = tint if tint != Color(1, 1, 1, 1) else COLOR_ACCENT
		for step in range(9):
			var angle: float = deg_to_rad(-60.0 + step * 15.0)
			line.add_point(at + Vector2(cos(angle), sin(angle)) * 34.0)
		_fx_layer.add_child(line)
		var tween := create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.25)
		tween.tween_callback(line.queue_free)


func _spawn_particles(at: Vector2, color: Color, amount: int = 14, spread_up: bool = true) -> void:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.one_shot = true
	particles.emitting = true
	particles.amount = amount
	particles.lifetime = 0.6
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1) if spread_up else Vector2(0, 1)
	particles.spread = 70.0
	particles.gravity = Vector2(0, 160.0)
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 95.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.4
	particles.color = color
	_fx_layer.add_child(particles)
	get_tree().create_timer(1.4).timeout.connect(particles.queue_free)


func _spawn_damage_number(at: Vector2, text: String, color: Color, big: bool = false) -> void:
	var label := _make_label(text, 14 if big else 11, color)
	label.position = at + Vector2(randf_range(-12.0, 12.0), -6.0)
	label.pivot_offset = Vector2(12, 8)
	label.scale = Vector2(1.7, 1.7)
	_fx_layer.add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position:y", label.position.y - 24.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.tween_callback(label.queue_free)


func _enemy_hit_react(heavy: bool = false) -> void:
	_flash_portrait()
	_shake(5.0 if heavy else 3.0, 0.3 if heavy else 0.22)
	var recoil := create_tween()
	recoil.tween_property(_portrait_holder, "position", PORTRAIT_HOME + Vector2(10, -4), 0.07)
	recoil.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enemy_lunge() -> void:
	var lunge := create_tween()
	lunge.tween_property(_portrait_holder, "position", PORTRAIT_HOME + Vector2(-22, 6), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	lunge.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_exposed_glow(active: bool) -> void:
	if active:
		var pulse := create_tween().set_loops()
		pulse.set_meta("exposed_pulse", true)
		pulse.tween_property(_portrait_glow, "modulate:a", 0.45, 0.55).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_portrait_glow, "modulate:a", 0.12, 0.55).set_trans(Tween.TRANS_SINE)
		_portrait_glow.set_meta("pulse_tween", pulse)
	else:
		var pulse: Variant = _portrait_glow.get_meta("pulse_tween") if _portrait_glow.has_meta("pulse_tween") else null
		if pulse is Tween and (pulse as Tween).is_valid():
			(pulse as Tween).kill()
		var fade := create_tween()
		fade.tween_property(_portrait_glow, "modulate:a", 0.0, 0.3)


func _animate_enemy_hp() -> void:
	var ratio: float = clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_enemy_hp_bar, "size:x", ENEMY_HP_BAR_W * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var ghost := create_tween()
	ghost.tween_property(_enemy_hp_ghost, "size:x", ENEMY_HP_BAR_W * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)


func _animate_player_hp() -> void:
	var max_hp: int = int(player_stats.get("max_hp", 80))
	var ratio: float = clampf(float(GameManager.get_player_hp()) / float(max_hp), 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_player_hp_bar, "size:x", PLAYER_HP_BAR_W * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var ghost := create_tween()
	ghost.tween_property(_player_hp_ghost, "size:x", PLAYER_HP_BAR_W * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)
	if _player_hp_bar.size.x / PLAYER_HP_BAR_W > ratio:
		var damage_flash := create_tween()
		damage_flash.tween_property(_player_panel, "modulate", Color(1.0, 0.6, 0.6), 0.08)
		damage_flash.tween_property(_player_panel, "modulate", Color.WHITE, 0.3)


# ── battle flow (rules unchanged, FX added) ──────────────────────────────────


func _run_battle() -> void:
	await get_tree().create_timer(0.6).timeout
	for line in _dialogue("intro"):
		await _say(line)

	_pick_enemy_intent()
	var enemy_first: bool = enemy_speed > int(player_stats.get("speed", 9))
	if enemy_first:
		await _say("%s moves first!" % _enemy_name())
		await _enemy_turn()

	while not _battle_over:
		_apply_party_regen()  # a healer companion mends you a little each turn
		await _player_turn()
		if _battle_over:
			break
		await _check_phases()
		if _battle_over:
			break
		await _enemy_turn()
		if exposed_turns > 0:
			exposed_turns -= 1
			if exposed_turns == 0:
				_set_exposed_glow(false)
				await _say("The opening closes. %s steadies itself." % _enemy_name())
			_refresh_enemy_panel()


func _player_turn() -> void:
	guarding = false
	var ids: Array[String] = ["attack", "skill", "probe", "item", "guard", "flee"]
	var labels: Array[String] = ["Attack", "Skill", "Probe", "Item", "Guard", "Flee"]
	if exposed_turns > 0 and not finisher_used:
		ids.insert(0, "finisher")
		labels.insert(0, "Resolve Strike!")
	if bool(enemy.get("can_spare", false)) and enemy_hp <= int(enemy_max_hp * 0.3):
		ids.append("spare")
		labels.append("Spare")

	var choice: String = await _menu(ids, labels)
	match choice:
		"attack":
			await _player_attack(1.0, "You strike!", COLOR_ACCENT)
		"finisher":
			finisher_used = true
			_flash_portrait(COLOR_EXPOSED, 1.0)
			_shake(7.0, 0.4)
			_spawn_slash(_portrait_center(), COLOR_EXPOSED, 1.9)
			_spawn_slash(_portrait_center() + Vector2(8, 10), Color(1, 1, 1, 0.9), 1.5, true)
			await _player_attack(3.0, "You answer its secret with one decisive blow!", COLOR_EXPOSED)
		"skill":
			await _skill_menu()
		"probe":
			await _probe_menu()
		"item":
			await _item_menu()
		"guard":
			guarding = true
			player_sp = mini(player_sp + 1, int(player_stats.get("sp_max", 3)))
			_refresh_player_panel()
			_spawn_particles(PLAYER_FX_CENTER, Color(0.6, 0.75, 1.0), 10)
			await _say("You brace yourself and watch carefully. (+1 SP)")
		"flee":
			await _try_flee()
		"spare":
			await _spare_enemy()


func _skill_menu() -> void:
	var skills: Array[Dictionary] = GameManager.player_skills()
	var ids: Array[String] = []
	var labels: Array[String] = []
	for index in range(skills.size()):
		var skill: Dictionary = skills[index]
		ids.append(str(index))
		labels.append("%s (%d SP)" % [skill["name"], int(skill["sp_cost"])])
	ids.append("back")
	labels.append("Back")

	var choice: String = await _menu(ids, labels)
	if choice == "back":
		await _player_turn()
		return
	var skill: Dictionary = skills[int(choice)]
	if player_sp < int(skill["sp_cost"]):
		await _say("Not enough SP. Guard to recover.")
		await _player_turn()
		return
	player_sp -= int(skill["sp_cost"])
	_refresh_player_panel()
	# Dispatch on the skill's `effect` (data-driven in GameManager.SKILL_LIBRARY) so
	# new skills can be added without touching the battle code.
	match str(skill.get("effect", "attack")):
		"focus":
			focus_active = true
			_spawn_particles(PLAYER_FX_CENTER, Color(0.45, 0.65, 1.0), 18)
			var aura := create_tween()
			aura.tween_property(_player_panel, "modulate", Color(0.7, 0.85, 1.3), 0.2)
			aura.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
			await _say("You center yourself. Your next attack will hit twice as hard.")
		"heal":
			var heal_amount: int = int(round(float(skill["power"]))) + GameManager.player_level * 2
			GameManager.set_player_hp(GameManager.get_player_hp() + heal_amount)
			_animate_player_hp()
			_refresh_player_panel()
			_spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 18)
			_spawn_damage_number(PLAYER_FX_CENTER + Vector2(0, -18), "+%d" % heal_amount, COLOR_HEAL)
			var glow := create_tween()
			glow.tween_property(_player_panel, "modulate", Color(0.75, 1.25, 0.85), 0.2)
			glow.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
			await _say("You use %s and restore %d HP." % [skill["name"], heal_amount])
		"multi":
			var hits: int = clampi(int(round(float(skill["power"]))), 2, 4)
			var per_hit: float = 0.7
			for hit_index in range(hits):
				if _battle_over or enemy_hp <= 0:
					break
				_spawn_slash(_portrait_center() + Vector2(randf_range(-14, 14), randf_range(-10, 10)), Color(0.7, 0.9, 1.0), 1.4, hit_index % 2 == 0)
				await _player_attack(per_hit, "%s — hit %d!" % [skill["name"], hit_index + 1], Color(0.7, 0.9, 1.0))
		"pierce":
			_spawn_slash(_portrait_center(), Color(1.0, 0.55, 0.85), 1.7)
			await _player_attack(float(skill["power"]), "You unleash %s — it pierces the guard!" % skill["name"], Color(1.0, 0.55, 0.85), true)
		_:  # "attack" and any unknown effect → a single power strike
			_spawn_slash(_portrait_center(), Color(1.0, 0.62, 0.2), 1.6)
			await _player_attack(float(skill["power"]), "You unleash %s!" % skill["name"], Color(1.0, 0.62, 0.2))


func _item_menu() -> void:
	var usable: Array[Dictionary] = InventoryManager.usable_in_battle()
	if usable.is_empty():
		await _say("You carry nothing usable in battle.")
		await _player_turn()
		return
	var ids: Array[String] = []
	var labels: Array[String] = []
	for index in range(usable.size()):
		var item: Dictionary = usable[index]
		ids.append(str(index))
		labels.append("%s ×%d" % [item.get("name", "?"), InventoryManager.count_of(str(item.get("id")))])
	ids.append("back")
	labels.append("Back")

	var choice: String = await _menu(ids, labels)
	if choice == "back":
		await _player_turn()
		return
	var item: Dictionary = usable[int(choice)]
	var item_id: String = str(item.get("id"))
	if not InventoryManager.remove_item(item_id):
		await _player_turn()
		return
	match str(item.get("kind")):
		"heal":
			var amount: int = int(item.get("power", 40))
			GameManager.set_player_hp(GameManager.get_player_hp() + amount)
			_animate_player_hp()
			_refresh_player_panel()
			_spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 16)
			_spawn_damage_number(PLAYER_FX_CENTER + Vector2(0, -18), "+%d" % amount, COLOR_HEAL)
			await _say("You use %s. Restored %d HP." % [item.get("name"), amount])
		"energy":
			var sp_gain: int = int(item.get("power", 2))
			player_sp = mini(player_sp + sp_gain, int(player_stats.get("sp_max", 3)))
			_refresh_player_panel()
			_spawn_particles(PLAYER_FX_CENTER, Color(0.55, 0.6, 1.0), 14)
			await _say("You use %s. Restored %d SP." % [item.get("name"), sp_gain])
		"buff":
			focus_active = true
			_spawn_particles(PLAYER_FX_CENTER, Color(1.0, 0.6, 0.3), 18)
			var aura := create_tween()
			aura.tween_property(_player_panel, "modulate", Color(1.3, 1.0, 0.7), 0.2)
			aura.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
			await _say("You use %s. Your next attack is empowered!" % item.get("name"))


func _probe_menu() -> void:
	var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
	if weakness_found:
		await _say("You already see through it. Its weakness is laid bare.")
		await _player_turn()
		return
	if probe_options.is_empty():
		await _say("It refuses to answer anything more.")
		await _player_turn()
		return

	await _say(str(weakness.get("hint", "You look for a crack in its resolve.")))

	var ids: Array[String] = []
	var labels: Array[String] = []
	for index in range(probe_options.size()):
		ids.append(str(index))
		labels.append(str((probe_options[index] as Dictionary).get("text", "...")))
	ids.append("back")
	labels.append("Back")

	var choice: String = await _menu(ids, labels)
	if choice == "back":
		await _player_turn()
		return

	var option: Dictionary = probe_options[int(choice)] as Dictionary
	probe_options.remove_at(int(choice))
	await _say(str(option.get("reveal", "...")))

	if bool(option.get("correct", false)):
		weakness_found = true
		exposed_turns = int(weakness.get("vulnerable_turns", 3)) + 1
		_set_exposed_glow(true)
		_flash_portrait(COLOR_EXPOSED, 0.8)
		_shake(4.0, 0.3)
		_spawn_particles(_portrait_center(), COLOR_EXPOSED, 22)
		_refresh_enemy_panel()
		await _say("%s is EXPOSED! Your words found the wound. (damage x%.1f)" % [
			_enemy_name(), float(weakness.get("damage_multiplier", 2.0)),
		])
	else:
		await _say("Wrong nerve. %s lashes out while you hesitate!" % _enemy_name())
		await _enemy_strike(0.8, "")


func _player_attack(power: float, flavor: String, fx_color: Color = COLOR_ACCENT, ignore_defense: bool = false) -> void:
	var base: float = float(player_stats.get("attack", 12)) * power
	if focus_active:
		base *= 2.0
		focus_active = false
	if hexed:
		base *= 0.7
		hexed = false
	var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
	var exposed_now: bool = exposed_turns > 0
	if exposed_now:
		base *= float(weakness.get("damage_multiplier", 2.0))
	var variance: float = randf_range(0.85, 1.15)
	var crit: bool = randf() < 0.1
	# Pierce skills shrug off most of the enemy's defense.
	var defense_cut: float = 0.0 if ignore_defense else enemy_defense * phase_defense_factor * 0.5
	var damage: int = maxi(int(round(base * variance * (1.5 if crit else 1.0) - defense_cut)), 1)
	enemy_hp = maxi(enemy_hp - damage, 0)

	_spawn_slash(_portrait_center(), fx_color, 1.5 if power > 1.2 else 1.25)
	_enemy_hit_react(power >= 1.5 or crit)
	_spawn_particles(_portrait_center(), fx_color if not exposed_now else COLOR_EXPOSED)
	_spawn_damage_number(
		_portrait_center() + Vector2(0, -34),
		str(damage) + ("!" if crit else ""),
		COLOR_CRIT if crit else (COLOR_EXPOSED if exposed_now else Color.WHITE),
		crit or power >= 1.8,
	)
	_animate_enemy_hp()
	_refresh_enemy_panel()

	var text: String = "%s %d damage%s" % [flavor + " ", damage, " — CRITICAL!" if crit else "."]
	await _say(text)

	if enemy_hp <= 0:
		await _victory()
	elif enemy_hp <= int(enemy_max_hp * 0.3):
		var low_lines: Array = _dialogue("low_hp")
		if not low_lines.is_empty() and not triggered_phases.has("_low_hp"):
			triggered_phases["_low_hp"] = true
			await _say("%s: \"%s\"" % [_enemy_name(), low_lines[0]])
			if bool(enemy.get("can_spare", false)):
				await _say("It is wavering. You could choose to spare it.")


func _check_phases() -> void:
	var ratio: float = float(enemy_hp) / float(enemy_max_hp)
	for phase in enemy.get("phases", []) as Array:
		if not (phase is Dictionary):
			continue
		var key := str((phase as Dictionary).get("hp_ratio", 0.5))
		if triggered_phases.has(key):
			continue
		if ratio <= float((phase as Dictionary).get("hp_ratio", 0.5)):
			triggered_phases[key] = true
			_flash_portrait(Color(1.0, 0.4, 0.3), 0.7)
			_shake(4.0, 0.35)
			var beat: String = str((phase as Dictionary).get("story_beat", ""))
			if not beat.is_empty():
				await _say("%s: \"%s\"" % [_enemy_name(), beat])
			match str((phase as Dictionary).get("behavior", "aggressive")):
				"aggressive":
					phase_damage_bonus = 1.15
					await _say("Its attacks grow fiercer!")
				"desperate":
					phase_damage_bonus = 1.3
					phase_defense_factor = 0.6
					await _say("It fights desperately — harder, but careless!")


func _enemy_turn() -> void:
	if _battle_over:
		return
	var skill: Dictionary = intent
	_pick_enemy_intent()
	await _enemy_use_skill(skill)


func _enemy_use_skill(skill: Dictionary) -> void:
	var kind: String = str(skill.get("kind", "strike"))
	var skill_name: String = str(skill.get("name", "Attack"))
	var power: float = float(skill.get("power", 1.0))
	if kind == "heavy":
		# Wind-up glow before a heavy hit lands.
		_portrait_flash.modulate = Color(1.0, 0.3, 0.2, 0.0)
		var windup := create_tween()
		windup.tween_property(_portrait_flash, "modulate:a", 0.5, 0.35)
		windup.tween_property(_portrait_flash, "modulate:a", 0.0, 0.15)
		await windup.finished
	match kind:
		"hex":
			hexed = true
			_spawn_particles(PLAYER_FX_CENTER, Color(0.7, 0.35, 0.9), 16, false)
			await _enemy_strike(power * 0.5, "%s uses %s! A weakening curse clings to you." % [_enemy_name(), skill_name])
		"guard_break":
			if guarding:
				await _enemy_strike(power * 1.6, "%s uses %s — it smashes straight through your guard!" % [_enemy_name(), skill_name])
			else:
				await _enemy_strike(power * 0.9, "%s uses %s." % [_enemy_name(), skill_name])
		_:
			await _enemy_strike(power, "%s uses %s!" % [_enemy_name(), skill_name])


func _enemy_strike(power: float, flavor: String) -> void:
	var base: float = float(enemy_attack) * power * phase_damage_bonus
	var variance: float = randf_range(0.85, 1.15)
	var damage: float = base * variance - float(player_stats.get("defense", 5)) * 0.5
	if guarding:
		damage *= 0.5
	var final_damage: int = maxi(int(round(damage)), 1)

	_enemy_lunge()
	await get_tree().create_timer(0.14).timeout
	_shake(5.0 if power >= 1.5 else 3.0, 0.3)
	_spawn_damage_number(PLAYER_FX_CENTER + Vector2(10, -92), str(final_damage), COLOR_PLAYER_DMG, power >= 1.5)
	GameManager.set_player_hp(GameManager.get_player_hp() - final_damage)
	_animate_player_hp()
	_refresh_player_panel()

	var guard_note: String = " You guarded (halved)." if guarding else ""
	if flavor.is_empty():
		await _say("It hits you for %d.%s" % [final_damage, guard_note])
	else:
		await _say("%s %d damage to you.%s" % [flavor + " ", final_damage, guard_note])

	if GameManager.get_player_hp() <= 0:
		await _defeat()


func _pick_enemy_intent() -> void:
	var skills: Array = enemy.get("skills", []) as Array
	var usable: Array[Dictionary] = []
	for skill in skills:
		if skill is Dictionary:
			if str((skill as Dictionary).get("kind", "")) == "heavy" and turns_since_heavy < 2:
				continue
			usable.append(skill as Dictionary)
	if usable.is_empty():
		usable.append({"name": "Attack", "kind": "strike", "power": 1.0, "telegraph": ""})
	intent = usable[randi() % usable.size()]
	if str(intent.get("kind", "")) == "heavy":
		turns_since_heavy = 0
	else:
		turns_since_heavy += 1
	var telegraph: String = str(intent.get("telegraph", ""))
	if str(intent.get("kind", "")) == "heavy":
		_intent_label.add_theme_color_override("font_color", COLOR_HP.lightened(0.3))
	else:
		_intent_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_intent_label.text = telegraph if not telegraph.is_empty() else "It watches you."
	_intent_label.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_intent_label, "modulate:a", 1.0, 0.4)


func _try_flee() -> void:
	var chance: float = clampf(
		0.5 + 0.05 * float(int(player_stats.get("speed", 9)) - enemy_speed) + 0.15 * flee_failed_count,
		0.25,
		0.95,
	)
	if randf() < chance:
		await _say("You slip away from the fight.")
		_finish("fled")
	else:
		flee_failed_count += 1
		_shake(2.0, 0.2)
		await _say("You can't get away!")


func _spare_enemy() -> void:
	for line in _dialogue("spare"):
		await _say("%s: \"%s\"" % [_enemy_name(), line])
	var fade := create_tween()
	fade.tween_property(_portrait_holder, "modulate", Color(1, 1, 1, 0.35), 1.0)
	var xp: int = int(int(enemy.get("xp_reward", 20)) * 0.6)
	await _grant_xp(xp, "You lower your weapon. +%d XP." % xp)
	_finish("spared")


func _victory() -> void:
	_set_exposed_glow(false)
	# Enemy dissolves.
	var dissolve := create_tween()
	dissolve.tween_property(_portrait_holder, "modulate", Color(1.4, 1.4, 1.4, 0.0), 0.9).set_trans(Tween.TRANS_CUBIC)
	dissolve.parallel().tween_property(_portrait_holder, "position:y", PORTRAIT_HOME.y + 24.0, 0.9)
	_spawn_particles(_portrait_center(), Color(1, 1, 1, 0.9), 26)
	_shake(3.0, 0.25)

	for line in _dialogue("finish"):
		await _say(line)
	for line in _dialogue("player_victory"):
		await _say("%s: \"%s\"" % [_enemy_name(), line])

	_show_victory_banner()
	var xp: int = int(enemy.get("xp_reward", 20))
	if weakness_found:
		var bonus: int = int(xp * 0.25)
		xp += bonus
		await _grant_xp(xp, "Victory! +%d XP (+%d for understanding its story)." % [xp, bonus])
	else:
		await _grant_xp(xp, "Victory! +%d XP." % xp)
	var dropped: String = InventoryManager.roll_battle_drop(str(enemy.get("rank", "minion")))
	if not dropped.is_empty():
		_spawn_particles(SCREEN_CENTER, COLOR_ACCENT, 12)
		await _say("It left something behind: %s." % InventoryManager.item_def(dropped).get("name", dropped))
	_finish("victory")


func _show_victory_banner() -> void:
	var banner_root := Control.new()
	banner_root.position = Vector2(480, 180)
	_fx_layer.add_child(banner_root)

	if _banner_texture != null:
		var ornament := TextureRect.new()
		ornament.texture = _banner_texture
		ornament.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var w: float = 360.0
		var h: float = w * float(_banner_texture.get_height()) / float(_banner_texture.get_width())
		ornament.size = Vector2(w, h)
		ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ornament.position = Vector2(-w / 2.0, -h / 2.0)
		banner_root.add_child(ornament)

	var text := _make_label("VICTORY", 34, COLOR_ACCENT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.position = Vector2(-140, -22)
	text.size = Vector2(280, 44)
	banner_root.add_child(text)

	banner_root.scale = Vector2(0.2, 0.2)
	banner_root.pivot_offset = Vector2.ZERO
	banner_root.modulate.a = 0.0
	var pop := create_tween()
	pop.tween_property(banner_root, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.parallel().tween_property(banner_root, "modulate:a", 1.0, 0.3)
	for index in range(5):
		_spawn_particles(Vector2(randf_range(300, 660), randf_range(110, 230)), COLOR_ACCENT, 12)


func _apply_party_regen() -> void:
	# Healer companions in the party mend the protagonist a little at the top of each
	# player turn — a passive, purely-visual heal (no extra confirm prompt).
	var regen: int = int(player_stats.get("party_regen", 0))
	if regen <= 0:
		return
	var max_hp: int = int(player_stats.get("max_hp", 80))
	if GameManager.get_player_hp() >= max_hp:
		return
	GameManager.set_player_hp(GameManager.get_player_hp() + regen)
	_animate_player_hp()
	_refresh_player_panel()
	_spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 8)
	_spawn_damage_number(PLAYER_FX_CENTER + Vector2(-6, -18), "+%d" % regen, COLOR_HEAL)


func _on_companion_leveled(npc_id: String, level: int) -> void:
	_companion_levelups.append({"npc_id": npc_id, "level": level})


func _grant_xp(xp: int, message: String) -> void:
	# Support companions boost XP gain; the whole party shares the reward.
	var boosted: int = int(round(float(xp) * float(player_stats.get("party_xp_mult", 1.0))))
	_companion_levelups.clear()
	var levels: int = GameManager.grant_party_xp(boosted)
	player_stats = GameManager.player_battle_stats()
	var xp_tween := create_tween()
	xp_tween.tween_property(
		_xp_bar, "size:x",
		(PLAYER_HP_BAR_W - 30) * clampf(float(GameManager.player_xp) / float(GameManager.xp_to_next_level()), 0.0, 1.0),
		0.7,
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_refresh_player_panel()
	await _say(message)
	if levels > 0:
		_build_sp_pips()
		_spawn_particles(PLAYER_FX_CENTER, COLOR_ACCENT, 28)
		_spawn_damage_number(PLAYER_FX_CENTER + Vector2(80, -80), "LEVEL UP!", COLOR_ACCENT, true)
		var glow := create_tween()
		glow.tween_property(_player_panel, "modulate", Color(1.4, 1.3, 0.9), 0.25)
		glow.tween_property(_player_panel, "modulate", Color.WHITE, 0.6)
		await _say("LEVEL UP! You are now level %d. You feel restored and stronger." % GameManager.player_level)
	# Companions who leveled from their share of the XP get a shout-out too.
	for entry in _companion_levelups:
		var npc_id: String = str((entry as Dictionary).get("npc_id", ""))
		var comp_name: String = PartyManager.companion_name(npc_id) if PartyManager.has_method("companion_name") else npc_id
		await _say("%s reached level %d!" % [comp_name, int((entry as Dictionary).get("level", 1))])
	_companion_levelups.clear()


func _defeat() -> void:
	var dark := create_tween()
	dark.tween_property(_root, "modulate", Color(0.55, 0.5, 0.6), 1.2)
	for line in _dialogue("player_defeat"):
		await _say("%s: \"%s\"" % [_enemy_name(), line])
	GameManager.lose_xp_on_defeat()
	await _say("Your memory frays... you lose some experience and wake up where you started.")
	_finish("defeat")


func _finish(result: String) -> void:
	_battle_over = true
	GameManager.ui_blocking_input = false
	battle_finished.emit(result, enemy_id)
	queue_free()


# ── ui interaction (typewriter / menus) ──────────────────────────────────────


func _say(text: String) -> void:
	if _battle_over:
		return
	_clear_menu()
	_continue_marker.visible = false
	_type_target = text
	_type_progress = 0.0
	_log_label.text = ""
	_ui_mode = UiMode.TYPING
	while _ui_mode == UiMode.TYPING:
		await get_tree().process_frame
	_continue_marker.visible = true
	var bounce := create_tween().set_loops(3)
	bounce.tween_property(_continue_marker, "position:y", 98.0, 0.25)
	bounce.tween_property(_continue_marker, "position:y", 94.0, 0.25)
	_ui_mode = UiMode.CONFIRM
	await _confirmed
	_continue_marker.visible = false
	_ui_mode = UiMode.NONE


func _menu(ids: Array[String], labels: Array[String]) -> String:
	_clear_menu()
	_menu_ids = ids
	_menu_index = 0
	_menu_panel.visible = true
	_menu_panel.modulate.a = 0.0
	if _hint_label != null:
		_hint_label.visible = true
	var panel_in := create_tween()
	panel_in.tween_property(_menu_panel, "modulate:a", 1.0, 0.16)
	var count: int = maxi(labels.size(), 1)
	var card_w: float = clampf((_menu_row.size.x - float(maxi(count - 1, 0) * 6)) / float(count), 68.0, 196.0)
	var total_w: float = card_w * float(count) + float(maxi(count - 1, 0) * 6)
	_menu_row.position.x = 18.0 + maxf((608.0 - total_w) * 0.5, 0.0)
	_menu_row.size.x = minf(total_w, 608.0)
	for index in range(labels.size()):
		var item := _make_menu_card(labels[index], _menu_icon_path(ids[index], labels[index]), index, card_w)
		_menu_row.add_child(item)
		_menu_items.append(item)
	_menu_cursor.visible = true
	_ui_mode = UiMode.MENU
	_highlight_menu()
	var picked: String = await _menu_picked
	_menu_cursor.visible = false
	_clear_menu()
	_ui_mode = UiMode.NONE
	return picked


func _clear_menu() -> void:
	for item in _menu_items:
		item.queue_free()
	_menu_items.clear()
	_menu_ids.clear()
	if _menu_cursor != null:
		_menu_cursor.visible = false
	if _menu_panel != null:
		_menu_panel.visible = false
	if _hint_label != null:
		_hint_label.visible = false


func _highlight_menu() -> void:
	for index in range(_menu_items.size()):
		var selected: bool = index == _menu_index
		var item := _menu_items[index]
		_set_menu_card_selected(item, selected)
		if selected:
			var bump := create_tween()
			bump.tween_property(item, "position:y", -5.0, 0.08)
			bump.tween_property(item, "position:y", 0.0, 0.12)
	await get_tree().process_frame
	if _menu_index < _menu_items.size():
		var target: Control = _menu_items[_menu_index]
		_menu_cursor.visible = true
		_menu_cursor.position = Vector2(_menu_row.position.x + target.position.x + 10.0, _menu_row.position.y + target.size.y + 4.0)
		if _menu_cursor.get_child_count() > 0 and _menu_cursor.get_child(0) is ColorRect:
			(_menu_cursor.get_child(0) as ColorRect).size.x = maxf(target.size.x - 20.0, 30.0)


func _make_menu_card(text: String, icon_path: String, index: int, width: float) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(width, 94)
	card.size = Vector2(width, 94)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _make_menu_card_style(false))
	card.gui_input.connect(_on_menu_card_gui_input.bind(index))

	_add_texture(card, TEX_B2_COMMAND, Rect2(-2, -6, width + 4, 108), 0.42, true)

	var icon_node: CanvasItem
	if not icon_path.is_empty():
		var icon := _add_texture(card, icon_path, Rect2(width * 0.5 - 20.0, 11, 40, 40), 0.82)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_node = icon
	else:
		var icon := ColorRect.new()
		icon.color = Color(0.95, 0.80, 0.48, 0.72)
		icon.position = Vector2(width * 0.5 - 5, 21)
		icon.size = Vector2(10, 10)
		icon.rotation_degrees = 45
		icon.pivot_offset = Vector2(5, 5)
		card.add_child(icon)
		icon_node = icon
	card.set_meta("icon_node", icon_node)

	var label := _make_label(text, 15 if text.length() <= 10 else 13, COLOR_TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.position = Vector2(7, 54)
	label.size = Vector2(width - 14, 28)
	card.add_child(label)
	card.set_meta("label_node", label)
	return card


func _make_menu_card_style(selected: bool) -> StyleBoxFlat:
	var style := _make_panel_style(
		Color(0.03, 0.035, 0.045, 0.88) if not selected else Color(0.14, 0.10, 0.035, 0.95),
		Color(0.60, 0.50, 0.34, 0.58) if not selected else Color(1.0, 0.78, 0.32, 0.96),
		3
	)
	style.shadow_size = 6 if not selected else 16
	style.shadow_color = Color(0, 0, 0, 0.35) if not selected else Color(1.0, 0.63, 0.18, 0.34)
	return style


func _set_menu_card_selected(card: Control, selected: bool) -> void:
	if card is Panel:
		(card as Panel).add_theme_stylebox_override("panel", _make_menu_card_style(selected))
	if card.has_meta("label_node"):
		var label := card.get_meta("label_node") as Label
		if label != null:
			label.add_theme_color_override("font_color", COLOR_ACCENT if selected else COLOR_TEXT_DIM)
	if card.has_meta("icon_node"):
		var icon := card.get_meta("icon_node") as CanvasItem
		if icon is ColorRect:
			icon.color = Color(1.0, 0.86, 0.40, 1.0) if selected else Color(0.95, 0.80, 0.48, 0.55)
		elif icon != null:
			icon.modulate = Color(1.18, 1.08, 0.82, 1.0) if selected else Color(0.82, 0.80, 0.74, 0.78)


func _menu_icon_path(id: String, label: String) -> String:
	match id:
		"attack":
			return TEX_B2_ICON_ATTACK
		"skill":
			return TEX_B2_ICON_SKILL
		"probe":
			return TEX_B2_ICON_PROBE
		"item":
			return TEX_B2_ICON_ITEM
		"guard":
			return TEX_B2_ICON_GUARD
		"flee":
			return TEX_B2_ICON_FLEE
		"finisher":
			return TEX_B2_ICON_FINISHER
		"spare":
			return TEX_B2_ICON_SPARE
		"back":
			return ""
	var lower_label := label.to_lower()
	if id.is_valid_int():
		if lower_label.contains("potion") or lower_label.contains("tonic") or lower_label.contains("elixir") or lower_label.contains("×"):
			return TEX_B2_ICON_ITEM
		return TEX_B2_ICON_SKILL
	return ""


func _on_menu_card_gui_input(event: InputEvent, index: int) -> void:
	if _ui_mode != UiMode.MENU or index < 0 or index >= _menu_ids.size():
		return
	if event is InputEventMouseMotion and _menu_index != index:
		_menu_index = index
		_highlight_menu()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_menu_index = index
			_highlight_menu()
			_menu_picked.emit(_menu_ids[_menu_index])


func _process(delta: float) -> void:
	if _hint_label != null:
		_hint_label.visible = _ui_mode == UiMode.MENU
	if _menu_panel != null and _ui_mode != UiMode.MENU and _menu_items.is_empty():
		_menu_panel.visible = false

	if _ui_mode == UiMode.TYPING:
		_type_progress += TYPE_SPEED * delta
		var visible_chars: int = mini(int(_type_progress), _type_target.length())
		_log_label.text = _type_target.substr(0, visible_chars)
		if visible_chars >= _type_target.length():
			_finish_typing()

	if _shake_time > 0.0:
		_shake_time -= delta
		var decay: float = _shake_time * 3.0
		_root.position = Vector2(
			randf_range(-1.0, 1.0) * _shake_strength * decay,
			randf_range(-1.0, 1.0) * _shake_strength * decay,
		)
		if _shake_time <= 0.0:
			_root.position = Vector2.ZERO
			_shake_strength = 0.0


func _finish_typing() -> void:
	_log_label.text = _type_target
	_ui_mode = UiMode.NONE


func _unhandled_input(event: InputEvent) -> void:
	if _battle_over:
		return
	if event.is_action_pressed("ui_accept"):
		match _ui_mode:
			UiMode.TYPING:
				_finish_typing()
				get_viewport().set_input_as_handled()
			UiMode.CONFIRM:
				_confirmed.emit()
				get_viewport().set_input_as_handled()
			UiMode.MENU:
				if _menu_index < _menu_ids.size():
					_menu_picked.emit(_menu_ids[_menu_index])
				get_viewport().set_input_as_handled()
		return
	if _ui_mode != UiMode.MENU:
		return
	var moved := false
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_menu_index = (_menu_index + 1) % _menu_ids.size()
		moved = true
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_menu_index = (_menu_index - 1 + _menu_ids.size()) % _menu_ids.size()
		moved = true
	if moved:
		_highlight_menu()
		get_viewport().set_input_as_handled()


# ── panels ────────────────────────────────────────────────────────────────────


func _refresh_enemy_panel() -> void:
	_enemy_name_label.text = _enemy_name()
	_enemy_rank_label.text = "Lv %d" % int(enemy.get("level", 1))
	_enemy_status_label.text = "EXPOSED %d" % exposed_turns if exposed_turns > 0 else ""


func _refresh_player_panel() -> void:
	var max_hp: int = int(player_stats.get("max_hp", 80))
	_player_panel_label.text = "YOU  Lv.%d\nHP %d/%d%s%s" % [
		GameManager.player_level,
		GameManager.get_player_hp(), max_hp,
		"  FOCUS" if focus_active else "",
		"  HEX" if hexed else "",
	]
	_refresh_sp_pips()
	_player_hp_bar.size.x = PLAYER_HP_BAR_W * clampf(float(GameManager.get_player_hp()) / float(max_hp), 0.0, 1.0)
	_xp_bar.size.x = (PLAYER_HP_BAR_W - 30) * clampf(float(GameManager.player_xp) / float(GameManager.xp_to_next_level()), 0.0, 1.0)


func _enemy_name() -> String:
	return str(enemy.get("name", "Enemy"))


func _dialogue(key: String) -> Array:
	var dialogue: Dictionary = enemy.get("dialogue", {}) as Dictionary
	var lines: Array = dialogue.get(key, []) as Array
	var result: Array = []
	for line in lines:
		var text := str(line).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result
