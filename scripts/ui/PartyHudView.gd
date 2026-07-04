extends CanvasLayer
## Overworld player card (top-left): hero portrait, name, Lv chip, HP bar with
## live values, a slim XP bar, and one compact row per travelling companion.
## Refined dark-glass + thin gold look (deliberately NOT ornate — the HUD stays
## quiet under the scene). Authored in the native 960x540 space.
## QuestTrackerView docks itself right below this card via `bottom_y`.

const LEFT := 12.0
const TOP := 12.0
const WIDTH := 232.0
const PORTRAIT := 58.0
const ROW_H := 20.0

const COLOR_PANEL_BG := Color(0.028, 0.040, 0.082, 0.80)
const COLOR_BORDER := Color(0.78, 0.60, 0.26, 0.42)
const COLOR_ACCENT := Color(1.00, 0.85, 0.45, 1.0)
const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TEXT_DIM := Color(0.78, 0.74, 0.66, 0.85)

const ROLE_LABELS := {
	"attacker": "Công", "tank": "Thủ", "healer": "Trị", "support": "Trợ", "none": "—",
}
const ROLE_COLORS := {
	"attacker": Color(1.0, 0.55, 0.45), "tank": Color(0.6, 0.75, 1.0),
	"healer": Color(0.55, 0.95, 0.6), "support": Color(0.9, 0.8, 1.0), "none": Color(0.7, 0.7, 0.7),
}

## Bottom edge of the card in design units — the quest tracker docks below it.
static var bottom_y: float = 96.0

var _root: Control
var _party_manager: Node
var _portrait_cache: Texture2D = null


func _ready() -> void:
	layer = 43  # below the quest tracker (44) and journal/battle
	_party_manager = get_node_or_null("/root/PartyManager")
	_root = Control.new()
	add_child(_root)

	GameManager.player_stats_changed.connect(_refresh)
	GameManager.companion_leveled.connect(_on_companion_leveled)
	if _party_manager != null:
		_party_manager.member_joined.connect(_on_party_changed)
		_party_manager.member_left.connect(_on_party_changed)
	_refresh()


func _on_companion_leveled(_npc_id: String, _level: int) -> void:
	_refresh()


func _on_party_changed(_npc_id: String) -> void:
	_refresh()


func _hero_portrait() -> Texture2D:
	# Re-check the live scene package every call (cheap dict walk) so the card
	# upgrades to the real generated portrait the moment a zone finishes
	# downloading, rather than locking onto a fallback forever.
	var emotion_texture := _player_emotion_portrait_texture()
	if emotion_texture != null:
		_portrait_cache = emotion_texture
		return emotion_texture
	if _portrait_cache != null:
		return _portrait_cache
	var hero_path := "res://assets/ui/battle_v3/hero_portrait.png"
	if ResourceLoader.exists(hero_path):
		_portrait_cache = load(hero_path)
		return _portrait_cache
	var sheet := GameManager.load_texture(GameManager.get_player_sprite_path())
	if sheet == null:
		sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
		_portrait_cache = atlas
	return _portrait_cache


## The player's own generated portrait (story_bible.protagonist, packaged per
## zone as characters.main_character.emotion_portraits — same field BattleScene
## and CutscenePlayer already read). Prefers "neutral"; falls back to whichever
## emotion the run actually generated (some worlds only have one).
func _player_emotion_portrait_texture() -> Texture2D:
	var package: Dictionary = GameManager.get_scene_package()
	var characters: Dictionary = package.get("characters", {}) as Dictionary
	var main_character: Variant = characters.get("main_character", {})
	if not (main_character is Dictionary):
		return null
	var emotion_info: Variant = (main_character as Dictionary).get("emotion_portraits")
	if not (emotion_info is Dictionary):
		return null
	var portraits: Array = (emotion_info as Dictionary).get("portraits", []) as Array
	var fallback_file := ""
	for raw_portrait in portraits:
		if not (raw_portrait is Dictionary):
			continue
		var portrait: Dictionary = raw_portrait as Dictionary
		var file_name: String = str(portrait.get("file", ""))
		if file_name.is_empty():
			continue
		if fallback_file.is_empty():
			fallback_file = file_name
		if str(portrait.get("emotion", "")) == "neutral":
			var texture := GameManager.load_texture(GameManager.get_scene_asset_path(file_name))
			if texture != null:
				return texture
	if not fallback_file.is_empty():
		return GameManager.load_texture(GameManager.get_scene_asset_path(fallback_file))
	return null


## Mirrors BattleScene._player_name(): the protagonist's authored name
## (story_bible.protagonist.name), falling back to "Bạn" for legacy
## packages/no data instead of the placeholder "YOU".
func _player_name() -> String:
	var package: Dictionary = GameManager.get_scene_package()
	var characters: Dictionary = package.get("characters", {}) as Dictionary
	var main_character: Variant = characters.get("main_character", {})
	if main_character is Dictionary:
		var display_name: String = str((main_character as Dictionary).get("name", "")).strip_edges()
		if not display_name.is_empty() and display_name.to_upper() != "YOU":
			return display_name
	return "Bạn"


func _refresh() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	for child in _root.get_children():
		child.queue_free()

	var members: Array = []
	if _party_manager != null and _party_manager.has_method("active_member_ids"):
		members = _party_manager.active_member_ids()

	var base_h := PORTRAIT + 22.0
	var panel_h := base_h + (4.0 + float(members.size()) * ROW_H if not members.is_empty() else 0.0)
	bottom_y = TOP + panel_h
	_add_panel(Rect2(LEFT, TOP, WIDTH, panel_h))

	# ── portrait in a slim frame ──
	var frame := Panel.new()
	frame.position = Vector2(LEFT + 10.0, TOP + 10.0)
	frame.size = Vector2(PORTRAIT, PORTRAIT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.01, 0.015, 0.03, 0.9)
	frame_style.border_color = Color(0.78, 0.60, 0.26, 0.75)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	_root.add_child(frame)

	var portrait_texture := _hero_portrait()
	if portrait_texture != null:
		var picture := TextureRect.new()
		picture.texture = portrait_texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# The hero portrait asset is portrait-aspect; a plain SCALE into the
		# square frame reads best at this small size (covered-stretch is
		# unreliable — see the minimap gotcha).
		picture.stretch_mode = TextureRect.STRETCH_SCALE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if portrait_texture.get_width() > 96 else CanvasItem.TEXTURE_FILTER_NEAREST
		picture.position = frame.position + Vector2(2, 2)
		picture.size = frame.size - Vector2(4, 4)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(picture)

	# ── name + Lv chip ──
	var name_label := UiKit.make_title(_player_name(), 14, COLOR_ACCENT)
	name_label.position = Vector2(LEFT + 78.0, TOP + 8.0)
	name_label.size = Vector2(92.0, 18.0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(name_label)

	var chip_texture: Texture2D = load("res://assets/ui/battle_v3/lv_chip.png") if ResourceLoader.exists("res://assets/ui/battle_v3/lv_chip.png") else null
	var chip_rect := Rect2(LEFT + WIDTH - 58.0, TOP + 9.0, 48.0, 17.0)
	if chip_texture != null:
		var chip := TextureRect.new()
		chip.texture = chip_texture
		chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chip.stretch_mode = TextureRect.STRETCH_SCALE
		chip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		chip.position = chip_rect.position
		chip.size = chip_rect.size
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(chip)
	var lv_label := UiKit.make_label_strong("Lv %d" % GameManager.player_level, 10, COLOR_TEXT)
	lv_label.position = chip_rect.position
	lv_label.size = chip_rect.size
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(lv_label)

	# ── HP bar with live values ──
	var max_hp: int = int(GameManager.player_battle_stats()["max_hp"])
	var hp: int = GameManager.get_player_hp()
	var hp_rect := Rect2(LEFT + 78.0, TOP + 32.0, WIDTH - 90.0, 13.0)
	var bar := UiKit.make_bar(hp_rect, "green")
	(bar["fill"] as Control).size.x = bar["track_w"] * clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	_root.add_child(bar["root"])
	var hp_text := UiKit.make_label_strong("%d / %d" % [hp, max_hp], 8, Color(0.98, 0.95, 0.88, 0.95))
	hp_text.position = hp_rect.position
	hp_text.size = hp_rect.size
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(hp_text)

	# ── slim XP bar ──
	var xp_rect := Rect2(LEFT + 78.0, TOP + 50.0, WIDTH - 90.0, 7.0)
	var xp_bar := UiKit.make_bar(xp_rect, "blue")
	var xp_ratio := clampf(float(GameManager.player_xp) / float(maxi(GameManager.xp_to_next_level(), 1)), 0.0, 1.0)
	(xp_bar["fill"] as Control).size.x = xp_bar["track_w"] * xp_ratio
	_root.add_child(xp_bar["root"])

	# ── companion rows ──
	var y: float = TOP + base_h + 2.0
	for npc_id in members:
		_build_companion_row(str(npc_id), y)
		y += ROW_H


func _build_companion_row(npc_id: String, y: float) -> void:
	var display_name: String = npc_id
	if _party_manager != null and _party_manager.has_method("companion_name"):
		display_name = str(_party_manager.companion_name(npc_id))
	display_name = _truncate(display_name, 15)

	var name_label := _label("• " + display_name, 10, COLOR_TEXT_DIM)
	name_label.position = Vector2(LEFT + 12.0, y)
	name_label.size = Vector2(118.0, 16.0)

	var role := "support"
	if _party_manager != null and _party_manager.has_method("companion_combat_role"):
		role = str(_party_manager.companion_combat_role(npc_id))
	var role_label := _label(str(ROLE_LABELS.get(role, "—")), 9, ROLE_COLORS.get(role, COLOR_TEXT_DIM))
	role_label.position = Vector2(LEFT + WIDTH - 98.0, y + 1.0)
	role_label.size = Vector2(32.0, 14.0)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var lv_label := _label("Lv %d" % GameManager.companion_level(npc_id), 10, COLOR_ACCENT)
	lv_label.position = Vector2(LEFT + WIDTH - 60.0, y)
	lv_label.size = Vector2(50.0, 16.0)
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# ── drawing helpers ───────────────────────────────────────────────────────────


func _add_panel(rect: Rect2) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := UiKit.make_label(text, font_size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(label)
	return label


func _truncate(text: String, limit: int) -> String:
	return text if text.length() <= limit else text.substr(0, limit - 1) + "…"
