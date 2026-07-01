extends CanvasLayer
## Compact overworld party HUD (top-left). Shows the protagonist's level + a live XP
## bar and every companion currently travelling with the player, with their level and
## combat role. Read-only, rebuilt only when progression changes. Authored crisp in
## the native 960x540 space (matches QuestTrackerView), which sits top-right, so the
## two never overlap.

const LEFT := 12.0
const TOP := 12.0
const WIDTH := 196.0
const ROW_H := 20.0
const HEADER_H := 20.0

const COLOR_PANEL_BG := Color(0.05, 0.045, 0.11, 0.86)
const COLOR_BORDER := Color(0.78, 0.60, 0.26, 0.55)
const COLOR_ACCENT := Color(1.00, 0.85, 0.45, 1.0)
const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TEXT_DIM := Color(0.78, 0.74, 0.66, 0.85)
const COLOR_XP := Color(0.45, 0.62, 0.95, 1.0)
const COLOR_XP_BG := Color(0.12, 0.12, 0.22, 0.95)
const COLOR_HP := Color(0.35, 0.72, 0.42, 1.0)

const ROLE_LABELS := {
	"attacker": "Công", "tank": "Thủ", "healer": "Trị", "support": "Trợ", "none": "—",
}
const ROLE_COLORS := {
	"attacker": Color(1.0, 0.55, 0.45), "tank": Color(0.6, 0.75, 1.0),
	"healer": Color(0.55, 0.95, 0.6), "support": Color(0.9, 0.8, 1.0), "none": Color(0.7, 0.7, 0.7),
}

var _root: Control
var _party_manager: Node


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


func _refresh() -> void:
	if _root == null or not is_instance_valid(_root):
		return
	for child in _root.get_children():
		child.queue_free()

	var members: Array = []
	if _party_manager != null and _party_manager.has_method("active_member_ids"):
		members = _party_manager.active_member_ids()

	var rows: int = 1 + members.size()
	var panel_h: float = HEADER_H + 8.0 + float(rows) * ROW_H + 8.0
	_add_panel(Rect2(LEFT, TOP, WIDTH, panel_h))

	var header := _label("ĐỘI HÌNH", 11, COLOR_ACCENT)
	header.position = Vector2(LEFT + 10.0, TOP + 5.0)
	header.size = Vector2(WIDTH - 20.0, 16.0)

	var y: float = TOP + HEADER_H + 6.0
	_build_player_row(y)
	y += ROW_H
	for npc_id in members:
		_build_companion_row(str(npc_id), y)
		y += ROW_H


func _build_player_row(y: float) -> void:
	var name_label := _label("★ Bạn", 11, COLOR_TEXT)
	name_label.position = Vector2(LEFT + 10.0, y)
	name_label.size = Vector2(120.0, 16.0)

	var lv_label := _label("Lv %d" % GameManager.player_level, 11, COLOR_ACCENT)
	lv_label.position = Vector2(LEFT + WIDTH - 62.0, y)
	lv_label.size = Vector2(52.0, 16.0)
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# XP bar under the player row.
	var bar_x: float = LEFT + 10.0
	var bar_y: float = y + 14.0
	var bar_w: float = WIDTH - 20.0
	_add_rect(Rect2(bar_x, bar_y, bar_w, 3.0), COLOR_XP_BG)
	var ratio: float = clampf(float(GameManager.player_xp) / float(maxi(GameManager.xp_to_next_level(), 1)), 0.0, 1.0)
	_add_rect(Rect2(bar_x, bar_y, bar_w * ratio, 3.0), COLOR_XP)


func _build_companion_row(npc_id: String, y: float) -> void:
	var display_name: String = npc_id
	if _party_manager != null and _party_manager.has_method("companion_name"):
		display_name = str(_party_manager.companion_name(npc_id))
	display_name = _truncate(display_name, 14)

	var name_label := _label("• " + display_name, 10, COLOR_TEXT_DIM)
	name_label.position = Vector2(LEFT + 12.0, y)
	name_label.size = Vector2(108.0, 16.0)

	var role := "support"
	if _party_manager != null and _party_manager.has_method("companion_combat_role"):
		role = str(_party_manager.companion_combat_role(npc_id))
	var role_label := _label(str(ROLE_LABELS.get(role, "—")), 9, ROLE_COLORS.get(role, COLOR_TEXT_DIM))
	role_label.position = Vector2(LEFT + WIDTH - 96.0, y + 1.0)
	role_label.size = Vector2(30.0, 14.0)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var lv_label := _label("Lv %d" % GameManager.companion_level(npc_id), 10, COLOR_ACCENT)
	lv_label.position = Vector2(LEFT + WIDTH - 62.0, y)
	lv_label.size = Vector2(52.0, 16.0)
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
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)


func _add_rect(rect: Rect2, color: Color) -> void:
	var node := ColorRect.new()
	node.position = rect.position
	node.size = rect.size
	node.color = color
	_root.add_child(node)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(label)
	return label


func _truncate(text: String, limit: int) -> String:
	return text if text.length() <= limit else text.substr(0, limit - 1) + "…"
