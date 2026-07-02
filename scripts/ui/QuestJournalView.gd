class_name QuestJournalView
extends Control
## Full-screen Quest Journal — AAA art-directed redesign.
## Authored in 480x270 design units, rendered into a native 960x540 CanvasLayer.
## Runtime data remains owned by QuestManager; this view is pure presentation.

signal close_requested
signal track_requested(quest_id: String)

const COMPONENT_DIR := "res://assets/ui/quest_journal_v1/components/"
const V2_DIR := "res://assets/ui/quest_journal_v2/"
const ICON_DIR := "res://assets/ui/quest_journal_v2/icons/"
const ORN_DIR := "res://assets/ui/quest_journal_v2/ornaments/"
const DEFAULT_BANNER := "res://assets/ui/quest_journal_v2/hero_banner_default.png"
const CANVAS_SCALE := 2.0

const CATEGORY_IDS := ["active", "side", "completed"]
const CATEGORY_LABELS := ["Chính", "Phụ", "Xong"]
const LIST_PAGE_SIZE := 6

# Native 960x540 typography, tuned against InventoryManager's readable scale.
const FONT_HEADER := 28
const FONT_HEADER_SUB := 10
const FONT_CONTEXT := 12
const FONT_CLOSE := 18
const FONT_PANEL_TITLE := 12
const FONT_SECTION := 12
const FONT_TAB := 10
const FONT_BADGE := 8
const FONT_LIST_TITLE := 10
const FONT_LIST_META := 8
const FONT_LIST_MARK := 11
const FONT_DETAIL_OVERLINE := 10
const FONT_DETAIL_TITLE := 20
const FONT_BODY := 11
const FONT_META := 10
const FONT_PROGRESS := 12
const FONT_OBJECTIVE := 10
const FONT_OBJECTIVE_ACTIVE := 11
const FONT_OBJECTIVE_SMALL := 9
const FONT_OBJECTIVE_GLYPH := 12
const FONT_REWARD_QTY := 11
const FONT_REWARD_GHOST := 18
const FONT_REWARD_NAME := 8
const FONT_BUTTON := 13
const FONT_NOTE := 9

# ── Palette ──────────────────────────────────────────────────────────────────
const C_BG_DEEP := Color(0.027, 0.035, 0.050)
const C_BG_PANEL := Color(0.055, 0.070, 0.098, 0.97)
const C_BG_INSET := Color(0.015, 0.020, 0.030, 0.94)
const C_BG_SOFT := Color(0.105, 0.090, 0.060, 0.30)
const C_GOLD := Color(0.99, 0.85, 0.48)
const C_GOLD_DIM := Color(0.76, 0.57, 0.28)
const C_GOLD_DEEP := Color(0.45, 0.33, 0.16)
const C_LINE := Color(0.70, 0.52, 0.25, 0.55)
const C_TEXT := Color(0.94, 0.90, 0.80)
const C_TEXT_DIM := Color(0.94, 0.90, 0.80, 0.52)
const C_TEXT_FAINT := Color(0.94, 0.90, 0.80, 0.30)
const C_GREEN := Color(0.57, 0.84, 0.43)
const C_BLUE := Color(0.44, 0.74, 1.00)
const C_AMBER := Color(1.00, 0.71, 0.29)
const C_PURPLE := Color(0.78, 0.55, 0.97)
const C_CYAN := Color(0.56, 0.93, 0.96)
const C_RED := Color(0.93, 0.45, 0.42)

# ── Runtime state ────────────────────────────────────────────────────────────
var quests: Array = []
var quest_states: Dictionary = {}
var revealed_hints: Dictionary = {}
var tracked_quest_id := ""
var selected_index := 0
var category_index := 0
var visible_indices: Array[int] = []

# ── Node references ──────────────────────────────────────────────────────────
var _context_label: Label
var _tabs_host: Control
var _list_host: Control
var _page_label: Label
var _list_count_label: Label

var _hero_image: TextureRect
var _detail_type: Label
var _detail_title: Label
var _detail_summary: Label
var _detail_meta: Label
var _tracked_badge: Label
var _objectives_host: Control
var _hints_host: Control

var _basic_rewards_host: Control
var _bonus_rewards_host: Control
var _track_button: Control
var _track_button_label: Label

# Hosts kept for legacy preview assertions / structural parity.
var _hero_host: Control
var _detail_meta_host: Control

# All content is authored for a 960x540 canvas (480x270 design units x 2).
# _canvas centers that composition inside wider viewports; only the dim
# backdrop stays truly full-screen.
var _canvas: Control


func _scaled_vec(value: Vector2) -> Vector2:
	return (value * CANVAS_SCALE).round()


func _scaled_rect(rect: Rect2) -> Rect2:
	return Rect2(_scaled_vec(rect.position), _scaled_vec(rect.size))


func _scaled_value(value: float) -> float:
	return roundf(value * CANVAS_SCALE)


func _scaled_int(value: float) -> int:
	return int(roundf(value * CANVAS_SCALE))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas = Control.new()
	_canvas.position = ((get_viewport_rect().size - Vector2(960, 540)) * 0.5).floor()
	_canvas.size = Vector2(960, 540)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_static_ui()


func set_data(
		quest_data: Array,
		state_data: Dictionary,
		hint_data: Dictionary,
		tracked_id: String,
		context_text: String,
) -> void:
	quests = quest_data
	quest_states = state_data
	revealed_hints = hint_data
	tracked_quest_id = tracked_id
	_context_label.text = context_text
	_rebuild_visible_indices()
	_render()


func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		return true
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var direction := -1 if event.is_action_pressed("ui_left") else 1
		category_index = posmod(category_index + direction, CATEGORY_IDS.size())
		_rebuild_visible_indices()
		_render()
		return true
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		if not visible_indices.is_empty():
			var current_position := visible_indices.find(selected_index)
			if current_position < 0:
				current_position = 0
			var step := -1 if event.is_action_pressed("ui_up") else 1
			selected_index = visible_indices[posmod(current_position + step, visible_indices.size())]
			_render()
		return true
	if event.is_action_pressed("ui_accept"):
		var selected := _selected_quest()
		if not selected.is_empty() and str(_state_of(selected).get("state", "inactive")) != "completed":
			tracked_quest_id = str(selected.get("id", ""))
			track_requested.emit(tracked_quest_id)
			_render()
		return true
	return false


# ══════════════════════════════════════════════════════════════════════════════
# STATIC UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════════════════════
func _build_static_ui() -> void:
	_build_backdrop()
	_build_master_frame()
	_build_header()
	_build_list_panel()
	_build_detail_panel()
	_build_rewards_panel()


func _build_backdrop() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.006, 0.010, 0.97)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(_canvas)
	# Vertical depth gradient across the whole canvas.
	_add_gradient(_canvas, Rect2(0, 0, 480, 270),
			Color(0.045, 0.058, 0.080, 1.0), Color(0.012, 0.016, 0.026, 1.0), true)
	# Soft warm glow behind the frame centre for depth.
	_add_radial(_canvas, Rect2(40, 20, 400, 230),
			Color(0.22, 0.18, 0.12, 0.30), Color(0.0, 0.0, 0.0, 0.0))


func _build_master_frame() -> void:
	var frame := Rect2(5, 5, 470, 260)
	# Drop shadow halo.
	_add_rect(_canvas, Rect2(frame.position.x - 2, frame.position.y - 2, frame.size.x + 4, frame.size.y + 4),
			Color(0.0, 0.0, 0.0, 0.55))
	# Panel body.
	var panel := Panel.new()
	var frame_px := _scaled_rect(frame)
	panel.position = frame_px.position
	panel.size = frame_px.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = C_BG_PANEL
	style.border_color = C_GOLD_DIM
	style.set_border_width_all(_scaled_int(2))
	style.set_corner_radius_all(_scaled_int(2))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = _scaled_int(3)
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	# Inner bevel lines.
	_add_rect(_canvas, Rect2(frame.position.x + 3, frame.position.y + 3, frame.size.x - 6, 1), Color(1.0, 0.82, 0.40, 0.22))
	_add_rect(_canvas, Rect2(frame.position.x + 3, frame.end.y - 4, frame.size.x - 6, 1), Color(0.0, 0.0, 0.0, 0.30))
	_add_rect(_canvas, Rect2(frame.position.x + 3, frame.position.y + 4, 1, frame.size.y - 8), Color(1.0, 0.82, 0.40, 0.10))
	# Ornate filigree corners.
	if _has_ornament("corner_tl.png"):
		var cs := Vector2(21, 20)
		_canvas.add_child(_make_ornament("corner_tl.png", Rect2(frame.position.x - 3, frame.position.y - 3, cs.x, cs.y)))
		_canvas.add_child(_make_ornament("corner_tr.png", Rect2(frame.end.x - cs.x + 3, frame.position.y - 3, cs.x, cs.y)))
		_canvas.add_child(_make_ornament("corner_bl.png", Rect2(frame.position.x - 3, frame.end.y - cs.y + 3, cs.x, cs.y)))
		_canvas.add_child(_make_ornament("corner_br.png", Rect2(frame.end.x - cs.x + 3, frame.end.y - cs.y + 3, cs.x, cs.y)))
	else:
		_canvas.add_child(_make_art("corner_tl.png", Rect2(frame.position.x - 1, frame.position.y - 1, 15, 15)))
		_canvas.add_child(_make_art("corner_tr.png", Rect2(frame.end.x - 14, frame.position.y - 1, 15, 15)))
		_canvas.add_child(_make_art("corner_bl.png", Rect2(frame.position.x - 1, frame.end.y - 14, 15, 15)))
		_canvas.add_child(_make_art("corner_br.png", Rect2(frame.end.x - 14, frame.end.y - 14, 15, 15)))


func _build_header() -> void:
	# Header band fill with a subtle warm sheen.
	_add_rect(_canvas, Rect2(9, 9, 462, 31), Color(0.12, 0.095, 0.050, 0.55))
	_add_gradient(_canvas, Rect2(9, 9, 462, 16), Color(0.22, 0.16, 0.07, 0.55), Color(0.10, 0.08, 0.04, 0.0), true)
	# Title medallion.
	_build_medallion(Rect2(12, 10, 26, 26), "icon_journal.png")
	# Title + subtitle.
	var title := _place_label(UiKit.make_label("NHẬT KÝ NHIỆM VỤ", FONT_HEADER, C_GOLD), Rect2(46, 8, 220, 20))
	_canvas.add_child(title)
	_canvas.add_child(_place_label(UiKit.make_label("HỒ SƠ HÀNH TRÌNH", FONT_HEADER_SUB, C_TEXT_DIM), Rect2(47, 27, 140, 9)))
	# Chapter context (right aligned, before the close button).
	_context_label = _place_label(UiKit.make_label("", FONT_CONTEXT, C_TEXT_DIM), Rect2(250, 16, 192, 12))
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_canvas.add_child(_context_label)
	# Close button.
	var close_button := _make_button_shell(Rect2(450, 11, 21, 21), false)
	_canvas.add_child(close_button)
	var close_glyph := _place_label(UiKit.make_label("X", FONT_CLOSE, C_TEXT), Rect2(0, -1, 21, 21))
	close_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.add_child(close_glyph)
	# Header underline with a centred jewelled divider ornament.
	_add_rect(_canvas, Rect2(10, 40, 461, 1), Color(0.97, 0.74, 0.30, 0.42))
	_add_rect(_canvas, Rect2(10, 41, 461, 1), Color(0.0, 0.0, 0.0, 0.35))
	if _has_ornament("divider.png"):
		var divider := _make_ornament("divider.png", Rect2(170, 31, 140, 20), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		divider.z_index = 30
		_canvas.add_child(divider)
	else:
		_add_diamond(_canvas, Vector2(240, 40.5), 3.0, C_GOLD)


# ── Left list panel ──────────────────────────────────────────────────────────
func _build_list_panel() -> void:
	var rect := Rect2(9, 45, 138, 213)
	_build_panel(rect)
	_panel_caption(Rect2(14, 49, 128, 12), "DANH MỤC")
	_tabs_host = _spawn_host(Rect2(14, 63, 128, 30))
	# List sub-header with live count.
	_section_label(Rect2(15, 96, 90, 10), "DANH SÁCH")
	_list_count_label = _place_label(UiKit.make_label("", FONT_META, C_GOLD), Rect2(95, 96, 47, 10))
	_list_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_canvas.add_child(_list_count_label)
	_add_rect(_canvas, Rect2(15, 107, 127, 1), C_LINE)
	_list_host = _spawn_host(Rect2(13, 110, 130, 132))
	_page_label = _place_label(UiKit.make_label("", FONT_META, C_TEXT_DIM), Rect2(14, 245, 128, 9))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(_page_label)


# ── Center detail panel ──────────────────────────────────────────────────────
func _build_detail_panel() -> void:
	var rect := Rect2(151, 45, 208, 213)
	_build_panel(rect)

	# Hero banner.
	_hero_host = _spawn_host(Rect2(155, 49, 200, 54))
	_add_rect(_hero_host, Rect2(Vector2.ZERO, Vector2(200, 54)), Color(0.05, 0.07, 0.09, 1.0))
	_hero_image = TextureRect.new()
	_hero_image.position = Vector2.ZERO
	_hero_image.size = _hero_host.size
	_hero_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hero_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_host.add_child(_hero_image)
	# Banner framing + scrims.
	_add_gradient(_hero_host, Rect2(0, 30, 200, 24), Color(0.01, 0.02, 0.03, 0.0), Color(0.01, 0.02, 0.03, 0.80), true)
	_add_rect(_hero_host, Rect2(0, 0, 200, 1), Color(1.0, 0.82, 0.40, 0.35))
	_add_rect(_hero_host, Rect2(0, 53, 200, 1), Color(0.0, 0.0, 0.0, 0.6))
	_add_rect(_hero_host, Rect2(0, 0, 1, 54), Color(1.0, 0.82, 0.40, 0.18))
	_add_rect(_hero_host, Rect2(199, 0, 1, 54), Color(1.0, 0.82, 0.40, 0.18))
	# Type ribbon (top-left).
	_detail_type = _place_label(UiKit.make_label("", FONT_DETAIL_OVERLINE, C_GOLD), Rect2(6, 5, 120, 10))
	_hero_host.add_child(_detail_type)
	# Tracked badge (top-right).
	_tracked_badge = _place_label(UiKit.make_label("", FONT_DETAIL_OVERLINE, C_GREEN), Rect2(74, 5, 120, 10))
	_tracked_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hero_host.add_child(_tracked_badge)
	# Title over the bottom scrim.
	_detail_title = _place_label(UiKit.make_label("", FONT_DETAIL_TITLE, C_GOLD), Rect2(7, 24, 186, 17))
	_detail_title.clip_text = true
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hero_host.add_child(_detail_title)

	# Meta + summary.
	_detail_meta_host = _spawn_host(Rect2(156, 103, 198, 9))
	_detail_summary = _place_label(UiKit.make_label("", FONT_BODY, C_TEXT), Rect2(156, 114, 198, 21), VERTICAL_ALIGNMENT_TOP)
	_detail_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_summary.max_lines_visible = 2
	_detail_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_canvas.add_child(_detail_summary)

	_add_rect(_canvas, Rect2(156, 135, 198, 1), C_LINE)

	# Objectives.
	_section_label(Rect2(157, 139, 120, 11), "MỤC TIÊU")
	_objectives_host = _spawn_host(Rect2(157, 153, 197, 55))
	_objectives_host.clip_contents = true

	# Field hint card.
	_hints_host = _spawn_host(Rect2(156, 211, 198, 24))
	_hints_host.clip_contents = true


# ── Right rewards panel ──────────────────────────────────────────────────────
func _build_rewards_panel() -> void:
	var rect := Rect2(363, 45, 108, 213)
	_build_panel(rect)
	_panel_caption(Rect2(368, 49, 98, 12), "PHẦN THƯỞNG")

	# Unified reward rows: icon + readable item name + amount.
	_basic_rewards_host = _spawn_host(Rect2(370, 72, 96, 150))
	_bonus_rewards_host = _spawn_host(Rect2(370, 72, 96, 150))

	# Track button.
	_track_button = Control.new()
	var track_rect := _scaled_rect(Rect2(368, 229, 98, 27))
	_track_button.position = track_rect.position
	_track_button.size = track_rect.size
	_track_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_track_button)
	if _has_ornament("button_plate.png"):
		_add_radial(_track_button, Rect2(6, 0, 86, 26), Color(1.0, 0.80, 0.34, 0.22), Color(0, 0, 0, 0))
		_track_button.add_child(_make_ornament("button_plate.png", Rect2(0, 3, 98, 21)))
		_track_button_label = _place_label(UiKit.make_label("", FONT_BUTTON, Color(0.22, 0.13, 0.04)), Rect2(0, 3, 98, 21))
	else:
		_track_button.add_child(_make_button_shell(Rect2(0, 1, 98, 25), true))
		_track_button.add_child(_make_art("icon_main.png", Rect2(9, 7, 13, 13)))
		_track_button_label = _place_label(UiKit.make_label("", FONT_BUTTON, C_TEXT), Rect2(22, 5, 70, 16))
	_track_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_button.add_child(_track_button_label)


# ══════════════════════════════════════════════════════════════════════════════
# RENDER
# ══════════════════════════════════════════════════════════════════════════════
func _render() -> void:
	_render_tabs()
	_render_list()
	_render_detail()


func _rebuild_visible_indices() -> void:
	visible_indices.clear()
	var category: String = CATEGORY_IDS[category_index]
	for index in range(quests.size()):
		if not (quests[index] is Dictionary):
			continue
		var quest: Dictionary = quests[index] as Dictionary
		var state := str(_state_of(quest).get("state", "inactive"))
		var quest_type := str(quest.get("type", "side"))
		var include := false
		# Only quests the player has actually received (active) or finished (completed)
		# ever appear — not-yet-received (inactive) quests stay hidden.
		match category:
			"active":
				include = state == "active" and quest_type != "side"
			"side":
				include = state == "active" and quest_type == "side"
			"completed":
				include = state == "completed"
		if include:
			visible_indices.append(index)
	if visible_indices.is_empty() and category_index != 0:
		category_index = 0
		_rebuild_visible_indices()
		return
	if not visible_indices.has(selected_index):
		selected_index = visible_indices[0] if not visible_indices.is_empty() else -1


func _render_tabs() -> void:
	_clear(_tabs_host)
	var tab_w := 41.0
	var gap := 2.5
	var has_ring := _has_ornament("tab_normal.png")
	for index in range(CATEGORY_IDS.size()):
		var selected := index == category_index
		var cx := tab_w * 0.5
		if has_ring:
			var tab := Control.new()
			var tab_rect := _scaled_rect(Rect2(index * (tab_w + gap), 0, tab_w, 30))
			tab.position = tab_rect.position
			tab.size = tab_rect.size
			tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tabs_host.add_child(tab)
			# Icon nested inside the ornate ring (ring drawn on top so its rim frames it).
			var icon_tint := 1.0 if selected else 0.78
			var icon := _make_art(_tab_icon_file(CATEGORY_IDS[index]), Rect2(cx - 6, 4, 12, 11))
			icon.modulate = Color(1, 1, 1, icon_tint)
			tab.add_child(icon)
			tab.add_child(_make_ornament("tab_glow.png" if selected else "tab_normal.png",
					Rect2(cx - 11, 1, 22, 19), TextureRect.STRETCH_KEEP_ASPECT_CENTERED))
			var count := _count_for_category(CATEGORY_IDS[index])
			if count > 0:
				_add_round_count_badge(tab, count, Vector2(cx + 9.0, 3.0))
			var label := _place_label(
					UiKit.make_label(CATEGORY_LABELS[index], FONT_TAB, C_GOLD if selected else C_TEXT_DIM),
					Rect2(0, 20, tab_w, 11))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tab.add_child(label)
		else:
			var tab := _make_button_shell(Rect2(index * (tab_w + gap), 0, tab_w, 30), selected)
			_tabs_host.add_child(tab)
			tab.add_child(_make_icon_plate(_tab_icon_file(CATEGORY_IDS[index]), Rect2(tab_w * 0.5 - 7, 4, 14, 14), selected))
			var count := _count_for_category(CATEGORY_IDS[index])
			if count > 0:
				_add_count_badge(tab, count, Vector2(tab_w - 11, 2))
			var label := _place_label(
					UiKit.make_label(CATEGORY_LABELS[index], FONT_TAB, C_GOLD if selected else C_TEXT_DIM),
					Rect2(0, 19, tab_w, 11))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tab.add_child(label)


func _render_list() -> void:
	_clear(_list_host)
	_list_count_label.text = "%d" % visible_indices.size()
	if visible_indices.is_empty():
		var empty := _place_label(UiKit.make_label("Không có nhiệm vụ", FONT_BODY, C_TEXT_DIM), Rect2(6, 30, 118, 20))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_host.add_child(empty)
		_page_label.text = ""
		return
	var selected_position := maxi(0, visible_indices.find(selected_index))
	var page: int = selected_position / LIST_PAGE_SIZE
	var page_start := page * LIST_PAGE_SIZE
	var page_indices := visible_indices.slice(page_start, mini(page_start + LIST_PAGE_SIZE, visible_indices.size()))
	for row_index in range(page_indices.size()):
		var quest_index: int = page_indices[row_index]
		var quest: Dictionary = quests[quest_index] as Dictionary
		var selected := quest_index == selected_index
		var row := _make_row(Rect2(0, row_index * 22.0, 130, 22), selected)
		_list_host.add_child(row)
		row.add_child(_make_icon_plate(_quest_icon_file(quest), Rect2(6, 4, 13, 13), selected))
		var title := _place_label(UiKit.make_label(str(quest.get("title", "")), FONT_LIST_TITLE, C_TEXT if not selected else C_GOLD), Rect2(24, 2, 90, 10))
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)
		var giver: Dictionary = quest.get("giver", {}) as Dictionary
		var location := _quest_location_label(quest, giver)
		var status_pair := _quest_state_label(quest)
		var subtitle_text: String = location if not location.is_empty() and location != "Không rõ" else str(status_pair[0])
		var subtitle := _place_label(UiKit.make_label(subtitle_text, FONT_LIST_META, status_pair[1]), Rect2(24, 9, 92, 8))
		subtitle.clip_text = true
		subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(subtitle)
		_add_status_mark(row, quest, Rect2(118, 5, 10, 10))
	var page_count := ceili(float(visible_indices.size()) / float(LIST_PAGE_SIZE))
	_page_label.text = "Trang %d / %d" % [page + 1, maxi(1, page_count)] if page_count > 1 else ""


func _render_detail() -> void:
	_clear(_objectives_host)
	_clear(_hints_host)
	_clear(_basic_rewards_host)
	_clear(_bonus_rewards_host)
	_clear(_detail_meta_host)
	var quest := _selected_quest()
	if quest.is_empty():
		_detail_type.text = ""
		_detail_title.text = "Chưa chọn nhiệm vụ"
		_detail_summary.text = ""
		_tracked_badge.text = ""
		_hero_image.texture = _banner_or_default({})
		_track_button_label.text = "Theo dõi"
		return
	var state := _state_of(quest)
	var state_name := str(state.get("state", "inactive"))
	var quest_id := str(quest.get("id", ""))
	var giver: Dictionary = quest.get("giver", {}) as Dictionary
	var is_tracked := quest_id == tracked_quest_id
	var type_pair: Dictionary = {
		"main": "CHÍNH TUYẾN", "side": "NHIỆM VỤ PHỤ", "hidden": "NHIỆM VỤ ẨN",
	}
	_detail_type.text = type_pair.get(str(quest.get("type", "side")), "NHIỆM VỤ")
	_detail_type.add_theme_color_override("font_color", _type_color(str(quest.get("type", "side"))))
	_detail_title.text = str(quest.get("title", ""))
	_detail_summary.text = str(quest.get("summary", ""))
	# Location pin + label.
	_detail_meta_host.add_child(_make_art("icon_hidden.png", Rect2(0, 0, 8, 8)))
	_detail_meta = _place_label(UiKit.make_label("Khu vực: %s" % _quest_location_label(quest, giver), FONT_META, Color(C_GOLD, 0.80)), Rect2(11, 0, 187, 9))
	_detail_meta_host.add_child(_detail_meta)
	var state_pair := _quest_state_label(quest)
	if state_name == "completed":
		_tracked_badge.text = "ĐÃ HOÀN THÀNH"
		_tracked_badge.add_theme_color_override("font_color", C_GREEN)
	else:
		_tracked_badge.text = "ĐANG THEO DÕI" if is_tracked else state_pair[0]
		_tracked_badge.add_theme_color_override("font_color", C_GREEN if is_tracked else state_pair[1])
	_hero_image.texture = _banner_or_default(quest)
	_render_objectives(quest, state, state_name)
	_render_hints(quest, state, state_name)
	_render_rewards(quest)
	var on_plate := _has_ornament("button_plate.png")
	var c_active := Color(0.08, 0.26, 0.07) if on_plate else C_GREEN
	var c_idle := Color(0.22, 0.13, 0.03) if on_plate else C_TEXT
	if state_name == "completed":
		_track_button_label.text = "ĐÃ HOÀN THÀNH"
		_track_button_label.add_theme_color_override("font_color", c_active)
	else:
		_track_button_label.text = "ĐANG THEO DÕI" if is_tracked else "THEO DÕI"
		_track_button_label.add_theme_color_override("font_color", c_active if is_tracked else c_idle)


func _render_objectives(quest: Dictionary, state: Dictionary, state_name: String) -> void:
	var objectives: Array = quest.get("objectives", []) as Array
	var current_index := int(state.get("objective_index", 0))
	if objectives.is_empty():
		_objectives_host.add_child(_place_label(UiKit.make_label("Chưa có mục tiêu.", FONT_BODY, C_TEXT_DIM), Rect2(16, 2, 170, 12)))
		return
	var completed := state_name == "completed"
	var latest_index := objectives.size() - 1 if completed else clampi(current_index, 0, objectives.size() - 1)
	var visible_indices: Array[int] = []
	for index in range(latest_index, -1, -1):
		visible_indices.append(index)
		if visible_indices.size() >= 3:
			break
	var y := 0.0
	for row_index in range(visible_indices.size()):
		var index := visible_indices[row_index]
		if not (objectives[index] is Dictionary):
			continue
		var objective: Dictionary = objectives[index] as Dictionary
		var done := completed or index < current_index
		var active := not completed and index == clampi(current_index, 0, objectives.size() - 1)
		var description := str(objective.get("description", ""))
		var line_width := 180.0
		var text_color := C_TEXT if active else Color(C_GREEN, 0.90) if done else Color(C_TEXT, 0.50)
		# Objectives always render on a SINGLE line — the font shrinks just enough so the
		# full text fits, so there is never a wrapped second line or phantom gap.
		var font_choices := ([FONT_OBJECTIVE_ACTIVE, FONT_OBJECTIVE, FONT_OBJECTIVE_SMALL] if active
				else [FONT_OBJECTIVE, FONT_OBJECTIVE_SMALL])
		var objective_font := _fit_single_line_font(description, font_choices, line_width)
		var row_height := 15.0
		# Connector spine.
		if row_index < visible_indices.size() - 1:
			_add_rect(_objectives_host, Rect2(5, y + 11, 1, row_height - 6), Color(C_GOLD_DIM, 0.45 if done else 0.28))
		var node_color := C_GREEN if done else C_AMBER if active else Color(C_TEXT_DIM, 0.85)
		# Node halo + ring.
		_add_diamond(_objectives_host, Vector2(5.5, y + 5.5), 5.0 if active else 4.0, Color(node_color, 0.16))
		_add_diamond_outline(_objectives_host, Vector2(5.5, y + 5.5), 4.0, node_color)
		if done:
			_add_check_mark(_objectives_host, Vector2(2.3, y + 2.5), node_color)
		elif active:
			_add_diamond(_objectives_host, Vector2(5.5, y + 5.5), 2.0, node_color)
		else:
			_add_disc(_objectives_host, Vector2(5.5, y + 5.5), 1.5, node_color)
		var line := _place_label(UiKit.make_label(description, objective_font, text_color), Rect2(15, y, line_width, 13), VERTICAL_ALIGNMENT_TOP)
		line.clip_text = true
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_objectives_host.add_child(line)
		y += row_height
	if y <= 46.0:
		var older_count := maxi(0, latest_index + 1 - visible_indices.size())
		var future_count := maxi(0, objectives.size() - latest_index - 1)
		var note_text := ""
		if older_count > 0:
			note_text = "+%d bước trước đó" % older_count
		elif future_count > 0:
			note_text = "+%d bước tiếp theo" % future_count
		if not note_text.is_empty():
			_objectives_host.add_child(_place_label(UiKit.make_label(note_text, FONT_NOTE, C_TEXT_DIM), Rect2(15, y, 170, 8)))


func _render_hints(quest: Dictionary, state: Dictionary, state_name: String) -> void:
	# Only ever show hints the player has actually unlocked — nothing otherwise.
	var revealed := _latest_hint_text(quest, state, state_name)
	if revealed.is_empty():
		return
	# Card chrome.
	_add_rect(_hints_host, Rect2(0, 0, 198, 24), Color(0.035, 0.060, 0.062, 0.42))
	_add_rect(_hints_host, Rect2(0, 0, 2, 24), Color(C_CYAN, 0.85))
	_add_rect(_hints_host, Rect2(0, 0, 198, 1), Color(C_CYAN, 0.16))
	_add_rect(_hints_host, Rect2(0, 23, 198, 1), Color(0.0, 0.0, 0.0, 0.35))
	_hints_host.add_child(_make_art("icon_hint.png", Rect2(6, 5, 11, 11)))

	var label_text := "Gợi ý: %s" % revealed
	var hint_font := FONT_NOTE if label_text.length() > 82 else FONT_META
	var hint := _place_label(UiKit.make_label(label_text, hint_font, C_CYAN), Rect2(22, 2, 172, 20), VERTICAL_ALIGNMENT_TOP)
	_allow_wrapped_text(hint, 2)
	_hints_host.add_child(hint)


func _latest_hint_text(quest: Dictionary, state: Dictionary, state_name: String) -> String:
	if state_name != "active":
		return ""
	var objectives: Array = quest.get("objectives", []) as Array
	var current_index := int(state.get("objective_index", 0))
	if current_index < 0 or current_index >= objectives.size():
		return ""
	var objective: Dictionary = objectives[current_index] as Dictionary
	var key := "%s:%s" % [str(quest.get("id", "")), str(objective.get("id", ""))]
	var hints_by_level: Dictionary = revealed_hints.get(key, {}) as Dictionary
	if hints_by_level.is_empty():
		return ""
	var levels: Array[int] = []
	for level_key in hints_by_level:
		levels.append(int(level_key))
	levels.sort()
	var payload: Dictionary = hints_by_level.get(str(levels[levels.size() - 1]), {}) as Dictionary
	return str(payload.get("text", ""))


func _render_rewards(quest: Dictionary) -> void:
	var entries := _real_reward_entries(quest)
	for index in range(mini(entries.size(), 4)):
		_add_reward_slot(_basic_rewards_host, index, entries[index] as Dictionary)


func _real_reward_entries(quest: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var reward: Dictionary = quest.get("reward", {}) as Dictionary
	var xp := maxi(0, int(reward.get("xp", 0)))
	if xp > 0:
		entries.append({"glyph": "xp", "name": "EXP", "amount": str(xp)})

	var quest_id := str(quest.get("id", ""))
	var seen_items := {}
	var reward_item := InventoryManager.reward_item_for(quest_id)
	if not reward_item.is_empty():
		entries.append({"glyph": "item", "name": _reward_item_name(reward_item), "amount": "", "item": reward_item})
		seen_items[str(reward_item.get("id", ""))] = true

	for raw_item in InventoryManager.catalog:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item as Dictionary
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or seen_items.has(item_id):
			continue
		var best_count := 0
		for raw_rule in item.get("acquisition", []) as Array:
			if not (raw_rule is Dictionary):
				continue
			var rule: Dictionary = raw_rule as Dictionary
			if str(rule.get("mode", "")) != "quest_reward":
				continue
			var rule_quest := str(rule.get("quest_id", item.get("quest_id", "")))
			var item_quests: Array = item.get("quest_ids", []) as Array
			if rule_quest != quest_id and not item_quests.has(quest_id):
				continue
			best_count = maxi(best_count, maxi(1, int(rule.get("count", 1))))
		if best_count > 0:
			entries.append({
				"glyph": "item",
				"name": _reward_item_name(item),
				"amount": str(best_count) if best_count > 1 else "",
				"item": item,
			})
			seen_items[item_id] = true
	return entries


func _reward_item_name(item: Dictionary) -> String:
	var name := str(item.get("name", ""))
	if not name.is_empty():
		return name
	var item_id := str(item.get("id", ""))
	if item_id.is_empty():
		return "Vật phẩm"
	return item_id.replace("_", " ").capitalize()


# ══════════════════════════════════════════════════════════════════════════════
# DATA HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _selected_quest() -> Dictionary:
	if selected_index >= 0 and selected_index < quests.size() and quests[selected_index] is Dictionary:
		return quests[selected_index] as Dictionary
	return {}


func _state_of(quest: Dictionary) -> Dictionary:
	return quest_states.get(str(quest.get("id", "")), {}) as Dictionary


func _quest_icon_file(quest: Dictionary) -> String:
	if str(_state_of(quest).get("state", "")) == "completed":
		return "icon_completed.png"
	return {"main": "icon_main.png", "hidden": "icon_hidden.png"}.get(str(quest.get("type", "side")), "icon_side.png")


func _tab_icon_file(category: String) -> String:
	return {"active": "icon_main.png", "side": "icon_side.png", "completed": "icon_completed.png"}.get(category, "icon_unknown.png")


func _type_color(quest_type: String) -> Color:
	return {"main": C_GOLD, "side": C_BLUE, "hidden": C_PURPLE}.get(quest_type, C_GOLD)


func _quest_state_label(quest: Dictionary) -> Array:
	var state := str(_state_of(quest).get("state", "inactive"))
	if state == "completed":
		return ["Đã hoàn thành", C_GREEN]
	if str(quest.get("type", "")) == "hidden":
		return ["Nhiệm vụ ẩn", C_PURPLE]
	if state == "active":
		return ["Đang thực hiện", C_AMBER]
	return ["Chưa bắt đầu", Color(C_TEXT, 0.60)]


func _status_mark(quest: Dictionary) -> Array:
	var state := str(_state_of(quest).get("state", "inactive"))
	if state == "completed":
		return ["done", C_GREEN]
	if str(quest.get("id", "")) == tracked_quest_id:
		return ["tracked", C_AMBER]
	if state == "active":
		return ["active", C_BLUE]
	return ["idle", C_TEXT_DIM]


func _add_status_mark(parent: Control, quest: Dictionary, rect: Rect2) -> void:
	var mark := _status_mark(quest)
	var kind := str(mark[0])
	var color: Color = mark[1]
	var center := rect.position + rect.size * 0.5
	match kind:
		"done":
			_add_check_mark(parent, rect.position + Vector2(1.5, 2.5), color)
		"tracked":
			_add_diamond(parent, center, 3.7, Color(color, 0.22))
			_add_diamond_outline(parent, center, 3.8, color)
		"active":
			_add_diamond_outline(parent, center, 3.6, color)
			_add_disc(parent, center, 1.3, color)
		_:
			_add_diamond_outline(parent, center, 3.3, Color(color, 0.55))


func _count_for_category(category: String) -> int:
	var count := 0
	for quest in quests:
		if not (quest is Dictionary):
			continue
		var quest_dict: Dictionary = quest as Dictionary
		var state := str(_state_of(quest_dict).get("state", "inactive"))
		var quest_type := str(quest_dict.get("type", "side"))
		match category:
			"active":
				if state == "active" and quest_type != "side":
					count += 1
			"side":
				if state == "active" and quest_type == "side":
					count += 1
			"completed":
				if state == "completed":
					count += 1
	return count


func _quest_location_label(quest: Dictionary, giver: Dictionary) -> String:
	for key in ["zone_name", "location_name", "location", "area_name", "display_zone"]:
		var value := str(giver.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	for key in ["zone_name", "location_name", "location", "area_name", "display_zone"]:
		var value := str(quest.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	var zone_id := str(giver.get("zone_id", "")).strip_edges()
	if zone_id.is_empty():
		var objectives: Array = quest.get("objectives", []) as Array
		if not objectives.is_empty() and objectives[0] is Dictionary:
			zone_id = str((objectives[0] as Dictionary).get("zone_id", "")).strip_edges()
	if zone_id.is_empty():
		return "Không rõ"
	for zone in ChapterFlow.current_chapter_zones():
		if zone is Dictionary and str((zone as Dictionary).get("zone_id", "")) == zone_id:
			var display_name := str((zone as Dictionary).get("name", "")).strip_edges()
			if not display_name.is_empty():
				return display_name
	return _format_zone_id(zone_id)


func _format_zone_id(zone_id: String) -> String:
	var clean := zone_id.strip_edges()
	if clean.begins_with("zone_"):
		var suffix := clean.trim_prefix("zone_")
		if suffix.is_valid_int():
			return "Khu %02d" % int(suffix)
	return clean.capitalize().replace("_", " ")


func _banner_or_default(quest: Dictionary) -> Texture2D:
	for key in ["banner", "banner_path", "image", "image_path", "hero_image", "thumbnail"]:
		var path := str(quest.get(key, ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			return load(path) as Texture2D
	if ResourceLoader.exists(DEFAULT_BANNER):
		return load(DEFAULT_BANNER) as Texture2D
	return null


# ══════════════════════════════════════════════════════════════════════════════
# WIDGET BUILDERS
# ══════════════════════════════════════════════════════════════════════════════
func _build_panel(rect: Rect2) -> void:
	var panel := Panel.new()
	var panel_rect := _scaled_rect(rect)
	panel.position = panel_rect.position
	panel.size = panel_rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = C_BG_INSET
	style.border_color = Color(C_GOLD_DIM, 0.85)
	style.set_border_width_all(_scaled_int(1))
	style.set_corner_radius_all(_scaled_int(1))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = _scaled_int(2)
	style.shadow_offset = _scaled_vec(Vector2(0, 1))
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	# Top inner sheen + bottom shade for depth.
	_add_gradient(_canvas, Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, 10),
			Color(0.16, 0.13, 0.08, 0.45), Color(0.05, 0.06, 0.08, 0.0), true)
	_add_rect(_canvas, Rect2(rect.position.x + 1, rect.position.y + 1, rect.size.x - 2, 1), Color(1.0, 0.82, 0.40, 0.16))


func _build_medallion(rect: Rect2, icon_file: String) -> void:
	if _has_ornament("medallion.png"):
		# Soft glow halo behind the medallion.
		_add_radial(_canvas, Rect2(rect.position.x - 4, rect.position.y - 4, rect.size.x + 8, rect.size.y + 8),
				Color(1.0, 0.78, 0.34, 0.28), Color(0, 0, 0, 0))
		_canvas.add_child(_make_ornament("medallion.png", rect, TextureRect.STRETCH_KEEP_ASPECT_CENTERED))
		return
	var plate := Control.new()
	var plate_rect := _scaled_rect(rect)
	plate.position = plate_rect.position
	plate.size = plate_rect.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(plate)
	_add_rect(plate, Rect2(Vector2.ZERO, rect.size), Color(0.05, 0.045, 0.030, 0.95))
	_add_gradient(plate, Rect2(1, 1, rect.size.x - 2, rect.size.y * 0.5), Color(0.30, 0.22, 0.10, 0.6), Color(0.05, 0.04, 0.02, 0.0), true)
	# Double border.
	_frame_outline(plate, Rect2(0, 0, rect.size.x, rect.size.y), Color(C_GOLD, 0.85))
	_frame_outline(plate, Rect2(2, 2, rect.size.x - 4, rect.size.y - 4), Color(C_GOLD_DEEP, 0.7))
	plate.add_child(_make_art(icon_file, Rect2(4, 4, rect.size.x - 8, rect.size.y - 8)))


func _panel_caption(rect: Rect2, title: String) -> void:
	_add_rect(_canvas, rect, Color(0.10, 0.085, 0.05, 0.75))
	_add_rect(_canvas, Rect2(rect.position.x, rect.position.y, rect.size.x, 1), Color(C_GOLD, 0.30))
	_add_rect(_canvas, Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Color(0.0, 0.0, 0.0, 0.40))
	_add_rect(_canvas, Rect2(rect.position.x, rect.position.y, 2, rect.size.y), C_GOLD)
	_canvas.add_child(_place_label(UiKit.make_label(title, FONT_PANEL_TITLE, C_GOLD), Rect2(rect.position.x + 6, rect.position.y, rect.size.x - 10, rect.size.y)))


func _section_label(rect: Rect2, text: String) -> void:
	# Expand the text box so tall Vietnamese diacritics are never clipped.
	var lr := Rect2(rect.position.x, rect.position.y - 3, rect.size.x, rect.size.y + 6)
	_canvas.add_child(_place_label(UiKit.make_label(text, FONT_SECTION, Color(C_GOLD, 0.92)), lr))
	# Decorative leading ticks.
	_add_rect(_canvas, Rect2(rect.position.x - 6, rect.position.y + 5, 3, 1), Color(C_GOLD_DIM, 0.8))
	_add_diamond(_canvas, Vector2(rect.position.x - 8, rect.position.y + 5.5), 1.5, Color(C_GOLD, 0.7))


## A progress fill that reveals a fixed-width gradient by clipping — robust to any
## fill width. Set the returned control's size.x at render time.
func _make_clipped_fill(rect: Rect2, top: Color, bottom: Color) -> Control:
	var inner_w := rect.size.x - 2
	var inner_h := rect.size.y - 2
	var fill := Control.new()
	fill.position = _scaled_vec(rect.position + Vector2(1, 1))
	fill.size = Vector2(0, _scaled_value(inner_h))
	fill.clip_contents = true
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_meta("full_w", _scaled_value(inner_w))
	_canvas.add_child(fill)
	_add_gradient(fill, Rect2(0, 0, inner_w, inner_h), top, bottom, true)
	_add_rect(fill, Rect2(0, 0, inner_w, 1), Color(1.0, 1.0, 1.0, 0.40))
	return fill


func _add_count_badge(parent: Control, count: int, pos: Vector2) -> void:
	var badge := Control.new()
	badge.position = _scaled_vec(pos)
	badge.size = _scaled_vec(Vector2(11, 10))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(badge)
	_add_rect(badge, Rect2(0, 0, 11, 10), Color(0.07, 0.055, 0.032, 0.96))
	_add_gradient(badge, Rect2(1, 1, 9, 4), Color(0.32, 0.23, 0.10, 0.7), Color(0.07, 0.05, 0.02, 0.0), true)
	_frame_outline(badge, Rect2(0, 0, 11, 10), Color(C_GOLD, 0.78))
	var label := _place_label(UiKit.make_label(str(count), FONT_BADGE, C_GOLD), Rect2(0, -1, 11, 11))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(label)


func _add_round_count_badge(parent: Control, count: int, center: Vector2) -> void:
	_add_disc(parent, center, 4.7, Color(0.88, 0.68, 0.30, 1.0))
	_add_disc(parent, center, 3.7, Color(0.11, 0.08, 0.045, 1.0))
	var label := _place_label(UiKit.make_label(str(count), FONT_BADGE, C_GOLD), Rect2(center.x - 6, center.y - 6, 12, 12))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _make_icon_plate(icon_file: String, rect: Rect2, selected: bool) -> Control:
	var plate := Control.new()
	var plate_rect := _scaled_rect(rect)
	plate.position = plate_rect.position
	plate.size = plate_rect.size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local_size := rect.size
	_add_rect(plate, Rect2(Vector2.ZERO, local_size), Color(0.020, 0.018, 0.013, 0.90))
	_add_gradient(plate, Rect2(1, 1, local_size.x - 2, local_size.y * 0.5), Color(0.20, 0.16, 0.08, 0.5), Color(0.0, 0.0, 0.0, 0.0), true)
	_frame_outline(plate, Rect2(0, 0, local_size.x, local_size.y), Color(C_GOLD, 0.55 if selected else 0.32))
	plate.add_child(_make_art(icon_file, Rect2(2, 2, local_size.x - 4, local_size.y - 4)))
	return plate


func _add_reward_slot(parent: Control, index: int, entry: Dictionary) -> void:
	var slot := Control.new()
	var slot_rect := _scaled_rect(Rect2(0, index * 38.0, 96, 36))
	slot.position = slot_rect.position
	slot.size = slot_rect.size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	var use_frame := _has_ornament("slot_item.png")

	# Recessed dark inset behind the icon.
	_add_rect(slot, Rect2(4, 4, 22, 22), Color(0.020, 0.026, 0.038, 0.92))
	_add_gradient(slot, Rect2(4, 4, 22, 11), Color(0.16, 0.18, 0.24, 0.30), Color(0.0, 0.0, 0.0, 0.0), true)
	var item: Dictionary = entry.get("item", {}) as Dictionary
	if not item.is_empty():
		var icon_texture := InventoryManager.icon_for(item)
		if icon_texture != null:
			var icon := TextureRect.new()
			var icon_rect := _scaled_rect(Rect2(6, 5, 18, 18))
			icon.position = icon_rect.position
			icon.size = icon_rect.size
			icon.texture = icon_texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			slot.add_child(icon)
		else:
			slot.add_child(_make_reward_icon("item", Rect2(6, 5, 18, 18), C_GOLD))
	else:
		slot.add_child(_make_reward_icon(str(entry.get("glyph", "item")), Rect2(6, 5, 18, 18), C_GOLD))

	# Single refined frame for every item.
	if use_frame:
		slot.add_child(_make_ornament("slot_item.png", Rect2(-1, -1, 32, 32), TextureRect.STRETCH_SCALE))
	else:
		_frame_outline(slot, Rect2(0, 0, 30, 30), Color(C_GOLD_DIM, 0.7))

	var reward_name := str(entry.get("name", "Vật phẩm"))
	var name_label := _place_label(UiKit.make_label(reward_name, FONT_REWARD_NAME, C_TEXT), Rect2(34, 0, 60, 18), VERTICAL_ALIGNMENT_TOP)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	slot.add_child(name_label)

	var amount := str(entry.get("amount", ""))
	if not amount.is_empty():
		var qty := _place_label(UiKit.make_label(amount, FONT_REWARD_QTY, C_GOLD), Rect2(34, 21, 60, 11))
		slot.add_child(qty)


## Reward icon: prefers generated art (ICON_DIR), falls back to a kit medallion,
## then to a coloured procedural glyph so the slot is never empty.
func _make_reward_icon(glyph: String, rect: Rect2, tint: Color) -> Control:
	var art_path := ICON_DIR + "icon_%s.png" % glyph
	if ResourceLoader.exists(art_path):
		return _make_art_path(art_path, rect)
	# Procedural fallback glyph.
	var holder := Control.new()
	var holder_rect := _scaled_rect(rect)
	holder.position = holder_rect.position
	holder.size = holder_rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := rect.size * 0.5
	match glyph:
		"xp":
			_add_diamond(holder, c, rect.size.x * 0.44, C_GOLD)
			_add_diamond(holder, c, rect.size.x * 0.30, Color(1.0, 0.94, 0.58))
			_add_rect(holder, Rect2(c.x - 4, c.y - 0.5, 8, 1), Color(0.55, 0.36, 0.10, 0.85))
			_add_rect(holder, Rect2(c.x - 0.5, c.y - 4, 1, 8), Color(0.55, 0.36, 0.10, 0.85))
		"gold":
			_add_disc(holder, c, rect.size.x * 0.42, C_GOLD)
			_add_disc(holder, c, rect.size.x * 0.30, Color(1.0, 0.92, 0.55))
			_add_rect(holder, Rect2(c.x - 1, c.y - 3, 2, 6), Color(0.65, 0.45, 0.12, 0.8))
		"crystal":
			_add_diamond(holder, c, rect.size.x * 0.42, C_CYAN)
			_add_diamond(holder, c - Vector2(0, 1), rect.size.x * 0.24, Color(0.80, 0.98, 1.0))
		"potion":
			_add_disc(holder, c + Vector2(0, 2), rect.size.x * 0.34, C_RED)
			_add_rect(holder, Rect2(c.x - 2, c.y - 7, 4, 5), Color(0.7, 0.7, 0.75))
			_add_rect(holder, Rect2(c.x - 2.5, c.y - 8, 5, 2), C_GOLD)
		"scroll":
			_add_rect(holder, Rect2(c.x - 5, c.y - 6, 10, 12), Color(0.92, 0.84, 0.62))
			_add_rect(holder, Rect2(c.x - 6, c.y - 6, 12, 2), C_GOLD_DIM)
			_add_rect(holder, Rect2(c.x - 6, c.y + 4, 12, 2), C_GOLD_DIM)
		"rune":
			_add_diamond(holder, c, rect.size.x * 0.44, Color(C_BLUE, 0.9))
			_add_rect(holder, Rect2(c.x - 0.5, c.y - 4, 1, 8), Color(0.85, 0.95, 1.0))
			_add_rect(holder, Rect2(c.x - 3, c.y - 0.5, 6, 1), Color(0.85, 0.95, 1.0))
		_:
			_add_diamond(holder, c, rect.size.x * 0.42, tint)
	return holder


func _make_button_shell(rect: Rect2, selected: bool) -> Control:
	var shell := Control.new()
	var shell_rect := _scaled_rect(rect)
	shell.position = shell_rect.position
	shell.size = shell_rect.size
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local_size := rect.size
	_add_rect(shell, Rect2(Vector2.ZERO, local_size), Color(0.075, 0.062, 0.045, 0.92) if not selected else Color(0.34, 0.21, 0.060, 0.95))
	_add_gradient(shell, Rect2(1, 1, local_size.x - 2, maxf(2.0, local_size.y * 0.5)),
			Color(1.0, 0.74, 0.26, 0.16 if selected else 0.08), Color(1.0, 0.6, 0.2, 0.0), true)
	_frame_outline(shell, Rect2(0, 0, local_size.x, local_size.y), Color(0.85, 0.64, 0.26, 0.78 if selected else 0.40))
	_add_rect(shell, Rect2(1, 1, local_size.x - 2, 1), Color(1.0, 0.90, 0.50, 0.40 if selected else 0.22))
	if selected:
		_add_rect(shell, Rect2(0, local_size.y - 1, local_size.x, 1), Color(C_GOLD, 0.6))
	return shell


func _make_row(rect: Rect2, selected: bool) -> Control:
	var row := Control.new()
	var row_rect := _scaled_rect(rect)
	row.position = row_rect.position
	row.size = row_rect.size
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local_size := rect.size
	if selected:
		_add_gradient(row, Rect2(Vector2.ZERO, local_size), Color(0.40, 0.26, 0.085, 0.92), Color(0.20, 0.13, 0.05, 0.85), false)
		_add_rect(row, Rect2(0, 0, 3, local_size.y), C_AMBER)
		_add_rect(row, Rect2(3, 0, local_size.x - 3, 1), Color(C_GOLD, 0.80))
		_add_rect(row, Rect2(3, local_size.y - 1, local_size.x - 3, 1), Color(C_GOLD, 0.55))
		_add_rect(row, Rect2(local_size.x - 1, 1, 1, local_size.y - 2), Color(C_GOLD, 0.45))
	else:
		_add_rect(row, Rect2(Vector2.ZERO, local_size), Color(0.060, 0.056, 0.048, 0.55))
		_add_rect(row, Rect2(0, local_size.y - 1, local_size.x, 1), Color(0.55, 0.40, 0.18, 0.18))
	return row


# ══════════════════════════════════════════════════════════════════════════════
# PRIMITIVE HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _spawn_host(rect: Rect2) -> Control:
	var host := Control.new()
	var host_rect := _scaled_rect(rect)
	host.position = host_rect.position
	host.size = host_rect.size
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(host)
	return host


func _frame_outline(parent: Control, rect: Rect2, color: Color) -> void:
	_add_rect(parent, Rect2(rect.position.x, rect.position.y, rect.size.x, 1), color)
	_add_rect(parent, Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), Color(color, color.a * 0.8))
	_add_rect(parent, Rect2(rect.position.x, rect.position.y, 1, rect.size.y), Color(color, color.a * 0.85))
	_add_rect(parent, Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), Color(color, color.a * 0.85))


func _add_diamond(parent: Control, center: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	var c := _scaled_vec(center)
	var r := _scaled_value(radius)
	poly.polygon = PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0),
		c + Vector2(0, r), c + Vector2(-r, 0)])
	poly.color = color
	parent.add_child(poly)


func _add_diamond_outline(parent: Control, center: Vector2, radius: float, color: Color) -> void:
	var line := Line2D.new()
	var c := _scaled_vec(center)
	var r := _scaled_value(radius)
	line.points = PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0),
		c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
	line.width = _scaled_value(1.0)
	line.default_color = color
	line.antialiased = false
	parent.add_child(line)


func _add_check_mark(parent: Control, origin: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([
		_scaled_vec(origin + Vector2(0.0, 3.4)),
		_scaled_vec(origin + Vector2(3.0, 6.2)),
		_scaled_vec(origin + Vector2(8.2, 0.2)),
	])
	line.width = _scaled_value(1.4)
	line.default_color = color
	line.antialiased = false
	parent.add_child(line)


func _add_disc(parent: Control, center: Vector2, radius: float, color: Color) -> void:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var c := _scaled_vec(center)
	var r := _scaled_value(radius)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	poly.polygon = pts
	poly.color = color
	parent.add_child(poly)


func _add_gradient(parent: Control, rect: Rect2, from_color: Color, to_color: Color, vertical: bool) -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, from_color)
	grad.set_color(1, to_color)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 2 if vertical else 64
	tex.height = 64 if vertical else 2
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var node := TextureRect.new()
	node.texture = tex
	var node_rect := _scaled_rect(rect)
	node.position = node_rect.position
	node.size = node_rect.size
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _add_radial(parent: Control, rect: Rect2, inner: Color, outer: Color) -> void:
	var grad := Gradient.new()
	grad.set_color(0, inner)
	grad.set_color(1, outer)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 96
	tex.height = 96
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var node := TextureRect.new()
	node.texture = tex
	var node_rect := _scaled_rect(rect)
	node.position = node_rect.position
	node.size = node_rect.size
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)


func _make_art(file_name: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	return _make_art_path(COMPONENT_DIR + file_name, rect, mode)


func _make_art_path(path: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var art := TextureRect.new()
	if ResourceLoader.exists(path):
		art.texture = load(path) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var art_rect := _scaled_rect(rect)
	art.position = art_rect.position
	art.size = art_rect.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


## Ornate gold/jewel decoration art — detailed, so it uses smooth linear filtering.
func _make_ornament(file_name: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var art := TextureRect.new()
	var path := ORN_DIR + file_name
	if ResourceLoader.exists(path):
		art.texture = load(path) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var art_rect := _scaled_rect(rect)
	art.position = art_rect.position
	art.size = art_rect.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _has_ornament(file_name: String) -> bool:
	return ResourceLoader.exists(ORN_DIR + file_name)


func _allow_wrapped_text(label: Label, max_lines: int) -> void:
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = max_lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS


## Largest font from `choices` at which `text` fits on a single line within the
## on-screen (scaled) width — used to keep objectives to one line without wrapping.
func _fit_single_line_font(text: String, choices: Array, unscaled_width: float) -> int:
	var font := get_theme_default_font()
	if font == null:
		return int(choices[choices.size() - 1])
	var avail := _scaled_value(unscaled_width)
	for size_option in choices:
		var fs := int(size_option)
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x <= avail:
			return fs
	return int(choices[choices.size() - 1])


func _place_label(label: Label, rect: Rect2, vertical: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER) -> Label:
	var label_rect := _scaled_rect(rect)
	label.position = label_rect.position
	label.size = label_rect.size
	label.vertical_alignment = vertical
	return label


func _add_rect(parent: Control, rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	var block_rect := _scaled_rect(rect)
	block.position = block_rect.position
	block.size = block_rect.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.free()
