class_name QuestJournalView
extends Control
## Theme-neutral full-screen Quest Journal. Runtime data remains owned by QuestManager.

signal close_requested
signal track_requested(quest_id: String)

const COMPONENT_DIR := "res://assets/ui/quest_journal_v1/components/"
const CATEGORY_IDS := ["active", "side", "completed"]
const CATEGORY_LABELS := ["Đang", "Phụ", "Xong"]
const LIST_PAGE_SIZE := 7

const COLOR_GREEN := Color(0.62, 0.82, 0.36, 1.0)
const COLOR_HIDDEN := Color(0.72, 0.48, 0.90, 1.0)
const COLOR_HINT := Color(0.58, 0.94, 0.96, 1.0)
const COLOR_BLUE := Color(0.42, 0.72, 1.0, 1.0)
const COLOR_PANEL_DARK := Color(0.05, 0.045, 0.035, 0.92)
const COLOR_PANEL_SOFT := Color(0.14, 0.105, 0.055, 0.38)
const COLOR_LINE := Color(0.70, 0.52, 0.25, 0.58)

var quests: Array = []
var quest_states: Dictionary = {}
var revealed_hints: Dictionary = {}
var tracked_quest_id := ""
var selected_index := 0
var category_index := 0
var visible_indices: Array[int] = []

var _context_label: Label
var _tabs_host: Control
var _list_host: Control
var _page_label: Label
var _detail_type: Label
var _detail_title: Label
var _detail_summary: Label
var _detail_meta: Label
var _tracked_badge: Label
var _objectives_host: Control
var _hints_host: Control
var _rewards_host: Control

var _hero_host: Control
var _hero_image: TextureRect
var _progress_bar_bg: ColorRect
var _progress_bar_fill: ColorRect
var _progress_label: Label
var _basic_rewards_host: Control
var _bonus_rewards_host: Control
var _track_button_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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


func _build_static_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.008, 0.010, 0.014, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_add_frame(self, Rect2(6, 6, 468, 248))
	_add_rect(self, Rect2(8, 7, 464, 25), Color(0.17, 0.12, 0.065, 0.54))
	add_child(_make_art("icon_journal.png", Rect2(10, 6, 25, 25)))
	var title := _place_label(UiKit.make_label("NHIỆM VỤ", 12, UiKit.COLOR_ACCENT), Rect2(41, 8, 175, 20))
	add_child(title)
	_context_label = _place_label(UiKit.make_label("", 5, UiKit.COLOR_TEXT_DIM), Rect2(215, 12, 188, 10))
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_context_label)
	var close_button := _make_button_shell(Rect2(447, 10, 18, 18), false)
	add_child(close_button)
	var close_hint := _place_label(UiKit.make_label("×", 11, UiKit.COLOR_TEXT), Rect2(0, -1, 18, 18))
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.add_child(close_hint)

	_add_frame(self, Rect2(10, 36, 145, 213))
	_tabs_host = Control.new()
	_tabs_host.position = Vector2(15, 40)
	_tabs_host.size = Vector2(135, 31)
	add_child(_tabs_host)
	_list_host = Control.new()
	_list_host.position = Vector2(15, 74)
	_list_host.size = Vector2(135, 158)
	add_child(_list_host)
	_page_label = _place_label(UiKit.make_label("", 5, UiKit.COLOR_TEXT_DIM), Rect2(15, 235, 135, 8))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_page_label)

	_add_frame(self, Rect2(163, 36, 301, 213))
	_hero_host = Control.new()
	_hero_host.position = Vector2(168, 42)
	_hero_host.size = Vector2(291, 64)
	add_child(_hero_host)
	_build_hero_backdrop()
	_hero_image = TextureRect.new()
	_hero_image.position = Vector2.ZERO
	_hero_image.size = _hero_host.size
	_hero_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_host.add_child(_hero_image)
	_add_rect(_hero_host, Rect2(0, 0, 132, 64), Color(0.025, 0.022, 0.018, 0.60))
	_add_rect(_hero_host, Rect2(130, 0, 84, 64), Color(0.025, 0.022, 0.018, 0.30))

	add_child(_make_art("icon_journal.png", Rect2(174, 49, 28, 28)))
	_detail_title = _place_label(UiKit.make_label("", 11, UiKit.COLOR_ACCENT), Rect2(208, 49, 186, 18))
	_detail_title.clip_text = true
	_detail_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_detail_title)
	_detail_meta = _place_label(UiKit.make_label("", 5, UiKit.COLOR_TEXT_DIM), Rect2(209, 69, 180, 10))
	add_child(_detail_meta)
	_detail_summary = _place_label(UiKit.make_label("", 5, UiKit.COLOR_TEXT), Rect2(174, 83, 172, 19), VERTICAL_ALIGNMENT_TOP)
	_detail_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_summary.max_lines_visible = 2
	_detail_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_detail_summary)
	_detail_type = _place_label(UiKit.make_label("", 5, UiKit.COLOR_ACCENT), Rect2(349, 84, 104, 9))
	_detail_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_detail_type)
	_tracked_badge = _place_label(UiKit.make_label("", 5, COLOR_GREEN), Rect2(349, 94, 104, 9))
	_tracked_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_tracked_badge)

	_add_rect(self, Rect2(168, 109, 291, 1), COLOR_LINE)
	_add_section_title(self, "Mục tiêu nhiệm vụ", Rect2(174, 116, 176, 12), UiKit.COLOR_ACCENT)
	_objectives_host = Control.new()
	_objectives_host.position = Vector2(174, 132)
	_objectives_host.size = Vector2(182, 28)
	add_child(_objectives_host)

	_add_section_title(self, "Tiến độ nhiệm vụ", Rect2(174, 163, 176, 12), UiKit.COLOR_ACCENT)
	_progress_bar_bg = _add_rect(self, Rect2(174, 180, 181, 5), Color(0.03, 0.026, 0.018, 0.88))
	_progress_bar_fill = _add_rect(self, Rect2(175, 181, 0, 3), COLOR_BLUE)
	_progress_label = _place_label(UiKit.make_label("", 5, UiKit.COLOR_TEXT), Rect2(358, 176, 28, 12))
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_progress_label)

	_add_section_title(self, "Thông tin", Rect2(174, 193, 94, 12), UiKit.COLOR_ACCENT)
	_hints_host = Control.new()
	_hints_host.position = Vector2(174, 208)
	_hints_host.size = Vector2(182, 30)
	add_child(_hints_host)

	_add_rect(self, Rect2(363, 110, 1, 132), COLOR_LINE)
	_add_section_title(self, "Phần thưởng", Rect2(371, 117, 82, 12), UiKit.COLOR_ACCENT)
	_basic_rewards_host = Control.new()
	_basic_rewards_host.position = Vector2(371, 136)
	_basic_rewards_host.size = Vector2(82, 30)
	add_child(_basic_rewards_host)
	_bonus_rewards_host = Control.new()
	_bonus_rewards_host.position = Vector2(371, 177)
	_bonus_rewards_host.size = Vector2(82, 26)
	add_child(_bonus_rewards_host)
	_rewards_host = Control.new()
	_rewards_host.position = Vector2(371, 136)
	_rewards_host.size = Vector2(82, 67)
	add_child(_rewards_host)
	var bonus_title := _place_label(UiKit.make_label("Thưởng thêm", 5, UiKit.COLOR_ACCENT), Rect2(371, 166, 82, 9))
	add_child(bonus_title)
	var track_button := _make_button_shell(Rect2(371, 219, 82, 20), true)
	add_child(track_button)
	_track_button_label = _place_label(UiKit.make_label("", 7, UiKit.COLOR_TEXT), Rect2(0, 2, 82, 16))
	_track_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	track_button.add_child(_track_button_label)

	_add_frame(self, Rect2(166, 251, 298, 14))
	var help := _place_label(
		UiKit.make_label("←/→ Danh mục     ↑/↓ Chọn     ENTER Theo dõi     ESC Đóng", 5, UiKit.COLOR_TEXT),
		Rect2(174, 252, 282, 11),
	)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)


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
		match category:
			"active":
				include = state != "completed" and quest_type != "side"
			"side":
				include = state != "completed" and quest_type == "side"
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
	for index in range(CATEGORY_IDS.size()):
		var selected := index == category_index
		var tab := _make_button_shell(Rect2(index * 45.0, 0, 42, 31), selected)
		_tabs_host.add_child(tab)
		tab.add_child(_make_art(_tab_icon_file(CATEGORY_IDS[index]), Rect2(11, 3, 13, 13)))
		var count := _count_for_category(CATEGORY_IDS[index])
		if count > 0:
			var badge := _add_rect(tab, Rect2(31, 1, 8, 8), UiKit.COLOR_ACCENT)
			var count_label := _place_label(UiKit.make_label(str(count), 4, Color(0.12, 0.075, 0.015, 1.0)), Rect2(0, -1, 8, 8))
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.add_child(count_label)
		var label := _place_label(
			UiKit.make_label(CATEGORY_LABELS[index], 4, UiKit.COLOR_ACCENT if selected else UiKit.COLOR_TEXT_DIM),
			Rect2(1, 17, 40, 11),
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_child(label)


func _render_list() -> void:
	_clear(_list_host)
	if visible_indices.is_empty():
		var empty := _place_label(UiKit.make_label("Không có nhiệm vụ", 6, UiKit.COLOR_TEXT_DIM), Rect2(6, 24, 123, 20))
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
		var row := _make_row(Rect2(0, row_index * 22.0, 135, 20), selected)
		_list_host.add_child(row)
		row.add_child(_make_art(_quest_icon_file(quest), Rect2(6, 3, 14, 14)))
		var title := _place_label(UiKit.make_label(str(quest.get("title", "")), 5, UiKit.COLOR_TEXT), Rect2(25, 2, 91, 8))
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)
		var giver: Dictionary = quest.get("giver", {}) as Dictionary
		var location := str(giver.get("zone_id", ""))
		var status_color: Color = _quest_state_label(quest)[1]
		var status := _place_label(UiKit.make_label(location if not location.is_empty() else _quest_state_label(quest)[0], 4, status_color), Rect2(25, 11, 90, 8))
		status.clip_text = true
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(status)
		var right_mark := _status_mark(quest)
		var mark := _place_label(UiKit.make_label(right_mark[0], 7, right_mark[1]), Rect2(117, 4, 13, 12))
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(mark)
	var page_count := ceili(float(visible_indices.size()) / float(LIST_PAGE_SIZE))
	_page_label.text = "%d / %d" % [page + 1, maxi(1, page_count)] if page_count > 1 else ""


func _render_detail() -> void:
	_clear(_objectives_host)
	_clear(_hints_host)
	_clear(_rewards_host)
	_clear(_basic_rewards_host)
	_clear(_bonus_rewards_host)
	var quest := _selected_quest()
	if quest.is_empty():
		_detail_type.text = ""
		_detail_title.text = "Chưa có nhiệm vụ"
		_detail_summary.text = ""
		_detail_meta.text = ""
		_tracked_badge.text = ""
		_progress_label.text = ""
		_progress_bar_fill.size.x = 0
		_hero_image.texture = null
		_track_button_label.text = "Theo dõi"
		return
	var state := _state_of(quest)
	var state_name := str(state.get("state", "inactive"))
	var quest_id := str(quest.get("id", ""))
	var giver: Dictionary = quest.get("giver", {}) as Dictionary
	_detail_type.text = {"main": "Chính tuyến", "side": "Nhiệm vụ phụ", "hidden": "Nhiệm vụ ẩn"}.get(str(quest.get("type", "side")), "Nhiệm vụ")
	_detail_title.text = str(quest.get("title", ""))
	_detail_summary.text = str(quest.get("summary", ""))
	_detail_meta.text = "📍 %s" % str(giver.get("zone_id", "Không rõ"))
	_tracked_badge.text = "Đang theo dõi" if quest_id == tracked_quest_id else ""
	_hero_image.texture = _quest_banner_texture(quest)
	_render_objectives(quest, state, state_name)
	_render_hints(quest, state, state_name)
	_render_rewards(quest)
	_render_progress(quest, state, state_name)
	_track_button_label.text = "Đang theo dõi" if quest_id == tracked_quest_id else "Theo dõi"
	_track_button_label.add_theme_color_override("font_color", COLOR_GREEN if quest_id == tracked_quest_id else UiKit.COLOR_TEXT)


func _render_objectives(quest: Dictionary, state: Dictionary, state_name: String) -> void:
	var objectives: Array = quest.get("objectives", []) as Array
	var current_index := int(state.get("objective_index", 0))
	if objectives.is_empty():
		var empty := _place_label(UiKit.make_label("Chưa có mục tiêu.", 5, UiKit.COLOR_TEXT_DIM), Rect2(16, 0, 160, 20))
		_objectives_host.add_child(empty)
		return
	var objective: Dictionary = objectives[clampi(current_index, 0, objectives.size() - 1)] as Dictionary
	var completed := state_name == "completed"
	var mark := "✓" if completed else "◆"
	var color := COLOR_GREEN if completed else UiKit.COLOR_ACCENT
	var progress := _objective_progress_text(objective, state, completed)
	_objectives_host.add_child(_make_art("icon_main.png", Rect2(0, 2, 12, 12)))
	var line := _place_label(UiKit.make_label("%s  %s" % [mark, str(objective.get("description", ""))], 5, color), Rect2(15, 0, 135, 18), VERTICAL_ALIGNMENT_TOP)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.max_lines_visible = 2
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objectives_host.add_child(line)
	if not progress.is_empty():
		var progress_label := _place_label(UiKit.make_label(progress, 5, UiKit.COLOR_TEXT), Rect2(151, 2, 30, 10))
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_objectives_host.add_child(progress_label)


func _render_hints(quest: Dictionary, state: Dictionary, state_name: String) -> void:
	var info_text := str(quest.get("info", ""))
	if info_text.is_empty():
		info_text = "Theo dõi lời kể, dấu vết và đối thoại trong khu vực để mở thêm gợi ý."
	var info := _place_label(UiKit.make_label(info_text, 4, Color(UiKit.COLOR_TEXT, 0.82)), Rect2(0, 0, 180, 12), VERTICAL_ALIGNMENT_TOP)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.max_lines_visible = 2
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hints_host.add_child(info)
	if state_name != "active":
		return
	var objectives: Array = quest.get("objectives", []) as Array
	var current_index := int(state.get("objective_index", 0))
	if current_index < 0 or current_index >= objectives.size():
		return
	var objective: Dictionary = objectives[current_index] as Dictionary
	var key := "%s:%s" % [str(quest.get("id", "")), str(objective.get("id", ""))]
	var hints_by_level: Dictionary = revealed_hints.get(key, {}) as Dictionary
	if hints_by_level.is_empty():
		return
	var levels: Array[int] = []
	for level_key in hints_by_level:
		levels.append(int(level_key))
	levels.sort()
	var latest_level := levels[levels.size() - 1]
	var payload: Dictionary = hints_by_level.get(str(latest_level), {}) as Dictionary
	_hints_host.add_child(_make_art("icon_hint.png", Rect2(0, 16, 11, 11)))
	var hint := _place_label(UiKit.make_label("Gợi ý: %s" % str(payload.get("text", "")), 4, COLOR_HINT), Rect2(15, 15, 165, 13), VERTICAL_ALIGNMENT_TOP)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hints_host.add_child(hint)


func _render_rewards(quest: Dictionary) -> void:
	var reward: Dictionary = quest.get("reward", {}) as Dictionary
	var reward_item: Dictionary = InventoryManager.reward_item_for(str(quest.get("id", "")))
	var basic_slots := [
		["icon_xp.png", str(reward.get("gold", 500))],
		["icon_unknown.png", str(reward.get("crystal", 30))],
		["icon_hint.png", str(reward.get("potion", 3))],
	]
	for index in range(basic_slots.size()):
		_add_reward_slot(_basic_rewards_host, index, basic_slots[index][0], basic_slots[index][1])
	var bonus_name := str(reward_item.get("name", "Vật phẩm"))
	var bonus_slots := [
		["icon_side.png", ""],
		["icon_journal.png", ""],
		["icon_unknown.png", ""],
	]
	if not bonus_name.is_empty() and bonus_name != "Vật phẩm":
		bonus_slots[0][1] = "1"
	for index in range(bonus_slots.size()):
		_add_reward_slot(_bonus_rewards_host, index, bonus_slots[index][0], bonus_slots[index][1])
	var xp := int(reward.get("xp", 0))
	var xp_line := _place_label(UiKit.make_label("EXP                 %d / 1000" % xp, 5, UiKit.COLOR_TEXT), Rect2(0, 52, 82, 9))
	_rewards_host.add_child(xp_line)


func _render_progress(quest: Dictionary, state: Dictionary, state_name: String) -> void:
	var objectives: Array = quest.get("objectives", []) as Array
	var progress_ratio := 0.0
	if not objectives.is_empty():
		if state_name == "completed":
			progress_ratio = 1.0
		else:
			progress_ratio = clampf(float(int(state.get("objective_index", 0))) / float(objectives.size()), 0.0, 1.0)
	_progress_bar_fill.size.x = floor(179.0 * progress_ratio)
	_progress_label.text = "%d%%" % int(round(progress_ratio * 100.0))


func _selected_quest() -> Dictionary:
	if selected_index >= 0 and selected_index < quests.size() and quests[selected_index] is Dictionary:
		return quests[selected_index] as Dictionary
	return {}


func _state_of(quest: Dictionary) -> Dictionary:
	return quest_states.get(str(quest.get("id", "")), {}) as Dictionary


func _quest_icon_file(quest: Dictionary) -> String:
	if str(_state_of(quest).get("state", "")) == "completed":
		return "icon_completed.png"
	return {
		"main": "icon_main.png",
		"hidden": "icon_hidden.png",
	}.get(str(quest.get("type", "side")), "icon_side.png")


func _tab_icon_file(category: String) -> String:
	return {
		"active": "icon_journal.png",
		"side": "icon_side.png",
		"completed": "icon_completed.png",
	}.get(category, "icon_unknown.png")


func _quest_state_label(quest: Dictionary) -> Array:
	var state := str(_state_of(quest).get("state", "inactive"))
	if state == "completed":
		return ["Đã hoàn thành", COLOR_GREEN]
	if str(quest.get("type", "")) == "hidden":
		return ["Nhiệm vụ ẩn", COLOR_HIDDEN]
	if state == "active":
		return ["Đang thực hiện", UiKit.COLOR_ACCENT]
	return ["Chưa bắt đầu", UiKit.COLOR_TEXT_DIM]


func _status_mark(quest: Dictionary) -> Array:
	var state := str(_state_of(quest).get("state", "inactive"))
	if state == "completed":
		return ["✓", COLOR_GREEN]
	if str(quest.get("id", "")) == tracked_quest_id:
		return ["!", UiKit.COLOR_ACCENT]
	if state == "active":
		return ["◆", COLOR_BLUE]
	return ["•", UiKit.COLOR_TEXT_DIM]


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
				if state != "completed" and quest_type != "side":
					count += 1
			"side":
				if state != "completed" and quest_type == "side":
					count += 1
			"completed":
				if state == "completed":
					count += 1
	return count


func _objective_progress_text(objective: Dictionary, state: Dictionary, completed: bool) -> String:
	if completed:
		return ""
	if objective.has("count"):
		return "%d/%d" % [int(state.get("progress", 0)), int(objective.get("count", 1))]
	return "0/1"


func _quest_banner_texture(quest: Dictionary) -> Texture2D:
	for key in ["banner", "banner_path", "image", "image_path", "hero_image", "thumbnail"]:
		var path := str(quest.get(key, ""))
		if path.is_empty():
			continue
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _add_reward_slot(parent: Control, index: int, icon_file: String, amount: String) -> void:
	var slot := _make_button_shell(Rect2(index * 27.0, 0, 24, 24), false)
	parent.add_child(slot)
	slot.add_child(_make_art(icon_file, Rect2(4, 3, 16, 16)))
	if not amount.is_empty():
		var label := _place_label(UiKit.make_label(amount, 4, UiKit.COLOR_TEXT), Rect2(9, 15, 14, 8))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot.add_child(label)


func _make_button_shell(rect: Rect2, selected: bool) -> Control:
	var shell := Control.new()
	shell.position = rect.position.round()
	shell.size = rect.size.round()
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := _add_rect(shell, Rect2(Vector2.ZERO, shell.size), Color(0.08, 0.065, 0.045, 0.88) if not selected else Color(0.25, 0.17, 0.055, 0.90))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_rect(shell, Rect2(1, 1, shell.size.x - 2, 1), Color(0.82, 0.62, 0.24, 0.70 if selected else 0.38))
	_add_rect(shell, Rect2(1, shell.size.y - 2, shell.size.x - 2, 1), Color(0.82, 0.62, 0.24, 0.64 if selected else 0.32))
	_add_rect(shell, Rect2(1, 1, 1, shell.size.y - 2), Color(0.82, 0.62, 0.24, 0.58 if selected else 0.30))
	_add_rect(shell, Rect2(shell.size.x - 2, 1, 1, shell.size.y - 2), Color(0.82, 0.62, 0.24, 0.58 if selected else 0.30))
	if selected:
		_add_rect(shell, Rect2(4, shell.size.y - 3, shell.size.x - 8, 1), UiKit.COLOR_ACCENT)
	return shell


func _make_row(rect: Rect2, selected: bool) -> Control:
	var row := Control.new()
	row.position = rect.position.round()
	row.size = rect.size.round()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_rect(row, Rect2(Vector2.ZERO, row.size), Color(0.07, 0.055, 0.038, 0.78))
	_add_rect(row, Rect2(0, row.size.y - 1, row.size.x, 1), Color(0.58, 0.42, 0.18, 0.28))
	if selected:
		_add_rect(row, Rect2(0, 0, row.size.x, row.size.y), Color(0.95, 0.63, 0.16, 0.12))
		_add_rect(row, Rect2(1, 1, row.size.x - 2, 1), UiKit.COLOR_ACCENT)
		_add_rect(row, Rect2(1, row.size.y - 2, row.size.x - 2, 1), UiKit.COLOR_ACCENT)
		_add_rect(row, Rect2(1, 1, 1, row.size.y - 2), UiKit.COLOR_ACCENT)
		_add_rect(row, Rect2(row.size.x - 2, 1, 1, row.size.y - 2), UiKit.COLOR_ACCENT)
	return row


func _build_hero_backdrop() -> void:
	_add_rect(_hero_host, Rect2(Vector2.ZERO, _hero_host.size), Color(0.08, 0.10, 0.085, 1.0))
	_add_rect(_hero_host, Rect2(0, 0, 291, 24), Color(0.16, 0.21, 0.23, 0.74))
	_add_rect(_hero_host, Rect2(0, 24, 291, 40), Color(0.16, 0.13, 0.055, 0.72))
	for index in range(0, 10):
		var x := float(index * 31)
		_add_rect(_hero_host, Rect2(x, 36 - (index % 3) * 3, 22, 28), Color(0.18, 0.29, 0.13, 0.45))


func _add_section_title(parent: Control, text: String, rect: Rect2, color: Color) -> void:
	var label := _place_label(UiKit.make_label(text, 6, color), rect)
	parent.add_child(label)
	var left := _add_rect(parent, Rect2(rect.position.x - 8, rect.position.y + 5, 5, 1), COLOR_LINE)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var right := _add_rect(parent, Rect2(rect.position.x + rect.size.x - 32, rect.position.y + 5, 18, 1), COLOR_LINE)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _add_frame(parent: Control, rect: Rect2) -> void:
	var fill := _make_art("panel_fill.png", Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4)), TextureRect.STRETCH_TILE)
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	parent.add_child(fill)
	var corners := [
		["corner_tl.png", rect.position],
		["corner_tr.png", Vector2(rect.end.x - 15, rect.position.y)],
		["corner_bl.png", Vector2(rect.position.x, rect.end.y - 15)],
		["corner_br.png", rect.end - Vector2(15, 15)],
	]
	var edges := [
		Rect2(rect.position + Vector2(9, 1), Vector2(rect.size.x - 18, 2)),
		Rect2(Vector2(rect.position.x + 9, rect.end.y - 3), Vector2(rect.size.x - 18, 2)),
		Rect2(rect.position + Vector2(1, 9), Vector2(2, rect.size.y - 18)),
		Rect2(Vector2(rect.end.x - 3, rect.position.y + 9), Vector2(2, rect.size.y - 18)),
	]
	for index in range(edges.size()):
		var path := "edge_horizontal.png" if index < 2 else "edge_vertical.png"
		var edge := _make_art(path, edges[index], TextureRect.STRETCH_TILE)
		edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		parent.add_child(edge)
	for corner_data in corners:
		parent.add_child(_make_art(corner_data[0], Rect2(corner_data[1], Vector2(15, 15))))


func _make_art(file_name: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var art := TextureRect.new()
	art.texture = load(COMPONENT_DIR + file_name) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.position = rect.position.round()
	art.size = rect.size.round()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _place_label(label: Label, rect: Rect2, vertical: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER) -> Label:
	label.position = rect.position.round()
	label.size = rect.size.round()
	label.vertical_alignment = vertical
	return label


func _add_rect(parent: Control, rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.position = rect.position.round()
	block.size = rect.size.round()
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.free()
