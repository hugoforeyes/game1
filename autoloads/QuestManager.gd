extends Node
## Quest system runtime: state machine, event bus, and all quest UI
## (HUD tracker, journal, toasts, moral-choice dialog).
##
## Quests arrive compiled from the server (chapter_quests step): objectives are
## bound to real scene NPCs/enemies/zones with four trackable kinds —
## talk / defeat / reach / choice. Quests auto-start when the player enters
## their starting zone; objectives complete from gameplay events; rewards grant
## XP. The design follows the classic journal + tracked-objective model.

signal quests_changed

const TOAST_SECONDS := 2.4

var quests: Array = []
var quest_states: Dictionary = {}  # quest_id -> {state, objective_index, progress, choices}
var current_zone_id: String = ""

var _ui: CanvasLayer = null
var _tracker_panel: Panel
var _tracker_title: Label
var _tracker_objective: Label
var _tracker_hint: Label
var _toast_host: Control
var _toast_queue: Array = []
var _toast_busy: bool = false
var _journal_root: Control
var _journal_list: VBoxContainer
var _journal_title: Label
var _journal_body: Label
var _journal_open: bool = false
var _journal_index: int = 0
var _choice_root: Control
var _choice_prompt: Label
var _choice_options_box: VBoxContainer
var _choice_open: bool = false
var _choice_index: int = 0
var _choice_payload: Dictionary = {}
var _choice_showing_consequence: bool = false
var _pending_choices: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InventoryManager.item_obtained.connect(_on_item_obtained)


# ── lifecycle ─────────────────────────────────────────────────────────────────


func reset() -> void:
	quests = []
	quest_states = {}
	current_zone_id = ""
	_pending_choices.clear()
	_toast_queue.clear()
	quests_changed.emit()
	_refresh_tracker()


func load_chapter_quests(chapter_quests: Array) -> void:
	quests = []
	quest_states = {}
	for quest in chapter_quests:
		if not (quest is Dictionary):
			continue
		var quest_id: String = str((quest as Dictionary).get("id", ""))
		if quest_id.is_empty() or (quest as Dictionary).get("objectives", []) == []:
			continue
		quests.append(quest)
		quest_states[quest_id] = {"state": "inactive", "objective_index": 0, "progress": 0, "choices": {}}
	print("[Quest] loaded %d quests for chapter" % quests.size())
	_ensure_ui()
	quests_changed.emit()
	_refresh_tracker()


# ── event bus ─────────────────────────────────────────────────────────────────


func notify_zone_entered(zone_id: String) -> void:
	current_zone_id = zone_id
	var zone_index: int = _zone_play_index(zone_id)
	for quest in quests:
		var state: Dictionary = _state_of(quest)
		if str(state.get("state")) != "inactive":
			continue
		var start_zone: String = _quest_start_zone(quest)
		# Start when entering the start zone, or if it was somehow passed.
		if start_zone == zone_id or _zone_play_index(start_zone) <= zone_index:
			state["state"] = "active"
			_push_toast("new_quest", quest)
	_progress_reach_objectives()
	quests_changed.emit()
	_refresh_tracker()


func notify_npc_talked(npc_id: String) -> void:
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty():
			continue
		if str(objective.get("zone_id")) != current_zone_id:
			continue
		if str(objective.get("target_npc_id", "")) != npc_id:
			continue
		match str(objective.get("kind")):
			"talk":
				_complete_current_objective(quest)
			"choice":
				var state: Dictionary = _state_of(quest)
				if not (state.get("choices", {}) as Dictionary).has(str(objective.get("id"))):
					_pending_choices.append({"quest": quest, "objective": objective})
			"deliver":
				_try_deliver(quest, objective)
	quests_changed.emit()
	_refresh_tracker()


func _try_deliver(quest: Dictionary, objective: Dictionary) -> void:
	var item: Dictionary = InventoryManager.quest_item_for(str(quest.get("id")))
	if item.is_empty():
		_complete_current_objective(quest)  # no item exists — never block the story
		return
	var item_id: String = str(item.get("id"))
	if InventoryManager.count_of(item_id) <= 0:
		InventoryManager._push_toast("Cần: %s" % item.get("name", item_id))
		return
	InventoryManager.remove_item(item_id, 1)
	InventoryManager._push_toast("Đã trao: %s" % item.get("name", item_id))
	_complete_current_objective(quest)


func _on_item_obtained(item_id: String) -> void:
	var changed: bool = false
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("kind")) != "collect":
			continue
		var quest_item: Dictionary = InventoryManager.quest_item_for(str(quest.get("id")))
		var wanted: String = str(quest_item.get("id", ""))
		if wanted.is_empty() or wanted != item_id:
			continue
		var state: Dictionary = _state_of(quest)
		state["progress"] = InventoryManager.count_of(item_id)
		if state["progress"] >= int(objective.get("count", 1)):
			_complete_current_objective(quest)
		changed = true
	if changed:
		quests_changed.emit()
		_refresh_tracker()


func notify_enemy_defeated(enemy_id: String) -> void:
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("kind")) != "defeat":
			continue
		if str(objective.get("zone_id")) != current_zone_id:
			continue
		var target: String = str(objective.get("target_enemy_id", ""))
		if not target.is_empty():
			if target == enemy_id:
				_complete_current_objective(quest)
			continue
		var state: Dictionary = _state_of(quest)
		state["progress"] = int(state.get("progress", 0)) + 1
		if state["progress"] >= int(objective.get("count", 1)):
			_complete_current_objective(quest)
	quests_changed.emit()
	_refresh_tracker()


func notify_zone_hostiles_cleared(zone_id: String) -> void:
	# Safety: a count-based defeat objective can never exceed what spawned.
	var changed: bool = false
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if not objective.is_empty() and str(objective.get("kind")) == "defeat" \
				and str(objective.get("zone_id")) == zone_id:
			_complete_current_objective(quest)
			changed = true
	if changed:
		quests_changed.emit()
		_refresh_tracker()


func is_quest_npc(npc_id: String) -> bool:
	# True if this NPC is a target of ANY objective of ANY quest this chapter —
	# such NPCs must stay interactable regardless of package interaction config.
	for quest in quests:
		for objective in quest.get("objectives", []) as Array:
			if objective is Dictionary and str((objective as Dictionary).get("target_npc_id", "")) == npc_id:
				return true
		var giver: Dictionary = quest.get("giver", {}) as Dictionary
		if str(giver.get("npc_id", "")) == npc_id:
			return true
	return false


func marker_for_npc(npc_id: String) -> String:
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty():
			continue
		if str(objective.get("zone_id")) != current_zone_id:
			continue
		if str(objective.get("target_npc_id", "")) == npc_id and str(objective.get("kind")) in ["talk", "choice", "deliver"]:
			return "!"
	return ""


func has_blocking_objectives_in_zone(zone_id: String) -> bool:
	# Zone advancement waits for talk/choice objectives staged in this zone.
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if not objective.is_empty() and str(objective.get("zone_id")) == zone_id \
				and str(objective.get("kind")) in ["talk", "choice", "collect", "deliver"]:
			return true
	return false


# ── internals ─────────────────────────────────────────────────────────────────


func _state_of(quest: Dictionary) -> Dictionary:
	return quest_states.get(str(quest.get("id")), {}) as Dictionary


func _current_objective(quest: Dictionary) -> Dictionary:
	var state: Dictionary = _state_of(quest)
	if str(state.get("state")) != "active":
		return {}
	var objectives: Array = quest.get("objectives", []) as Array
	var index: int = int(state.get("objective_index", 0))
	if index >= 0 and index < objectives.size() and objectives[index] is Dictionary:
		return objectives[index] as Dictionary
	return {}


func _quest_start_zone(quest: Dictionary) -> String:
	var giver: Dictionary = quest.get("giver", {}) as Dictionary
	if not str(giver.get("zone_id", "")).is_empty():
		return str(giver.get("zone_id"))
	var objectives: Array = quest.get("objectives", []) as Array
	if not objectives.is_empty() and objectives[0] is Dictionary:
		return str((objectives[0] as Dictionary).get("zone_id", ""))
	return ""


func _zone_play_index(zone_id: String) -> int:
	var zones: Array = ChapterFlow.current_chapter_zones()
	for index in range(zones.size()):
		if zones[index] is Dictionary and str((zones[index] as Dictionary).get("zone_id")) == zone_id:
			return index
	return 99


func _progress_reach_objectives() -> void:
	var advanced: bool = true
	while advanced:
		advanced = false
		for quest in quests:
			var objective: Dictionary = _current_objective(quest)
			if objective.is_empty() or str(objective.get("kind")) != "reach":
				continue
			# Reaching the zone — or already being past it — completes it.
			if _zone_play_index(str(objective.get("zone_id"))) <= _zone_play_index(current_zone_id):
				_complete_current_objective(quest)
				advanced = true


func _complete_current_objective(quest: Dictionary) -> void:
	var state: Dictionary = _state_of(quest)
	var objectives: Array = quest.get("objectives", []) as Array
	var index: int = int(state.get("objective_index", 0))
	state["objective_index"] = index + 1
	state["progress"] = 0
	if state["objective_index"] >= objectives.size():
		state["state"] = "completed"
		var xp: int = int((quest.get("reward", {}) as Dictionary).get("xp", 50))
		GameManager.gain_xp(xp)
		_push_toast("quest_complete", quest)
		print("[Quest] completed %s (+%d XP)" % [quest.get("id"), xp])
	else:
		_push_toast("objective", quest)
		print("[Quest] %s objective %d/%d" % [quest.get("id"), state["objective_index"], objectives.size()])


func choose_option(option_id: String) -> void:
	var quest: Dictionary = _choice_payload.get("quest", {}) as Dictionary
	var objective: Dictionary = _choice_payload.get("objective", {}) as Dictionary
	var state: Dictionary = _state_of(quest)
	(state.get("choices", {}) as Dictionary)[str(objective.get("id"))] = option_id
	_complete_current_objective(quest)
	quests_changed.emit()
	_refresh_tracker()


# ── UI construction ───────────────────────────────────────────────────────────


func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 45
	_ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(_ui)

	# HUD tracker (top-right)
	_tracker_panel = UiKit.make_panel(Rect2(318, 6, 156, 52))
	_tracker_panel.visible = false
	_ui.add_child(_tracker_panel)

	_tracker_title = UiKit.make_label("", 7, UiKit.COLOR_ACCENT)
	_tracker_title.position = Vector2(8, 5)
	_tracker_title.size = Vector2(140, 11)
	_tracker_title.clip_text = true
	_tracker_panel.add_child(_tracker_title)

	_tracker_objective = UiKit.make_label("", 7, UiKit.COLOR_TEXT)
	_tracker_objective.position = Vector2(8, 17)
	_tracker_objective.size = Vector2(140, 24)
	_tracker_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_panel.add_child(_tracker_objective)

	_tracker_hint = UiKit.make_label("J  Nhật ký nhiệm vụ", 6, UiKit.COLOR_TEXT_DIM)
	_tracker_hint.position = Vector2(8, 41)
	_tracker_panel.add_child(_tracker_hint)

	# Toast host (top-center)
	_toast_host = Control.new()
	_toast_host.position = Vector2(240, 0)
	_ui.add_child(_toast_host)

	_build_journal()
	_build_choice_dialog()


func _build_journal() -> void:
	_journal_root = Control.new()
	_journal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journal_root.visible = false
	_ui.add_child(_journal_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journal_root.add_child(dim)

	var header := UiKit.make_label("NHẬT KÝ NHIỆM VỤ", 12, UiKit.COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(20, 10)
	header.size = Vector2(440, 18)
	_journal_root.add_child(header)

	var banner: TextureRect = UiKit.make_banner_rect(120.0)
	if banner != null:
		banner.position = Vector2(180, 26)
		_journal_root.add_child(banner)

	var list_panel := UiKit.make_panel(Rect2(14, 58, 160, 196))
	_journal_root.add_child(list_panel)
	_journal_list = VBoxContainer.new()
	_journal_list.position = Vector2(10, 10)
	_journal_list.size = Vector2(140, 178)
	_journal_list.add_theme_constant_override("separation", 6)
	list_panel.add_child(_journal_list)

	var detail_panel := UiKit.make_panel(Rect2(182, 58, 284, 196))
	_journal_root.add_child(detail_panel)
	_journal_title = UiKit.make_label("", 9, UiKit.COLOR_ACCENT)
	_journal_title.position = Vector2(12, 8)
	_journal_title.size = Vector2(260, 14)
	detail_panel.add_child(_journal_title)
	_journal_body = UiKit.make_label("", 7, UiKit.COLOR_TEXT)
	_journal_body.position = Vector2(12, 26)
	_journal_body.size = Vector2(260, 162)
	_journal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(_journal_body)

	var hint := UiKit.make_label("W/S chọn nhiệm vụ    ·    J / ESC đóng", 6, UiKit.COLOR_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(20, 258)
	hint.size = Vector2(440, 10)
	_journal_root.add_child(hint)


func _build_choice_dialog() -> void:
	_choice_root = Control.new()
	_choice_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_root.visible = false
	_ui.add_child(_choice_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_root.add_child(dim)

	var panel := UiKit.make_panel(Rect2(70, 60, 340, 150))
	_choice_root.add_child(panel)

	var header := UiKit.make_label("LỰA CHỌN", 9, UiKit.COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(0, 8)
	header.size = Vector2(340, 12)
	panel.add_child(header)

	_choice_prompt = UiKit.make_label("", 7, UiKit.COLOR_TEXT)
	_choice_prompt.position = Vector2(16, 26)
	_choice_prompt.size = Vector2(308, 52)
	_choice_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_choice_prompt)

	_choice_options_box = VBoxContainer.new()
	_choice_options_box.position = Vector2(24, 84)
	_choice_options_box.size = Vector2(292, 56)
	_choice_options_box.add_theme_constant_override("separation", 8)
	panel.add_child(_choice_options_box)


# ── UI behavior ───────────────────────────────────────────────────────────────


func _process(_delta: float) -> void:
	if _ui == null:
		return
	var has_active: bool = quests.any(func(q): return str(_state_of(q).get("state")) == "active")
	_tracker_panel.visible = has_active and not GameManager.ui_blocking_input and not _journal_open and not _choice_open

	if not _pending_choices.is_empty() and not _choice_open and not GameManager.ui_blocking_input:
		_open_choice(_pending_choices.pop_front() as Dictionary)

	if not _toast_queue.is_empty() and not _toast_busy:
		_show_next_toast()


func _refresh_tracker() -> void:
	if _ui == null:
		return
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty():
			continue
		_tracker_title.text = "✦ " + str(quest.get("title", ""))
		var progress_note: String = ""
		if str(objective.get("kind")) in ["defeat", "collect"] and objective.has("count"):
			var state: Dictionary = _state_of(quest)
			progress_note = "  (%d/%d)" % [int(state.get("progress", 0)), int(objective.get("count", 1))]
		_tracker_objective.text = "◆ " + str(objective.get("description", "")) + progress_note
		return
	_tracker_title.text = ""
	_tracker_objective.text = ""


func _push_toast(kind: String, quest: Dictionary) -> void:
	_toast_queue.append({"kind": kind, "quest": quest})


func _show_next_toast() -> void:
	_toast_busy = true
	var item: Dictionary = _toast_queue.pop_front()
	var kind: String = str(item.get("kind"))
	var quest: Dictionary = item.get("quest", {}) as Dictionary

	var text: String
	var color: Color = UiKit.COLOR_TEXT
	match kind:
		"new_quest":
			text = "✦ Nhiệm vụ mới: %s" % quest.get("title", "")
			color = UiKit.COLOR_ACCENT
		"quest_complete":
			text = "✦ Hoàn thành: %s  (+%d XP)" % [quest.get("title", ""), int((quest.get("reward", {}) as Dictionary).get("xp", 0))]
			color = UiKit.COLOR_ACCENT
		_:
			var objective: Dictionary = _current_objective(quest)
			text = "◆ " + str(objective.get("description", "Mục tiêu mới")) if not objective.is_empty() else "◆ Mục tiêu hoàn thành"

	var panel := UiKit.make_panel(Rect2(0, 0, 10, 22))
	var label := UiKit.make_label(text, 8, color)
	label.position = Vector2(12, 5)
	panel.add_child(label)
	await get_tree().process_frame
	var width: float = clampf(label.size.x + 26.0, 120.0, 420.0)
	panel.size.x = width
	panel.position = Vector2(-width / 2.0, -26)
	_toast_host.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "position:y", 8.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(panel, "position:y", -30.0, 0.3)
	tween.tween_callback(func() -> void:
		panel.queue_free()
		_toast_busy = false
	)


# ── journal ───────────────────────────────────────────────────────────────────


func _toggle_journal() -> void:
	if _ui == null or quests.is_empty():
		return
	if _journal_open:
		_journal_open = false
		_journal_root.visible = false
		GameManager.ui_blocking_input = false
		return
	if GameManager.ui_blocking_input or _choice_open:
		return
	_journal_open = true
	GameManager.ui_blocking_input = true
	_journal_index = clampi(_journal_index, 0, quests.size() - 1)
	_refresh_journal()
	_journal_root.visible = true
	_journal_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_journal_root, "modulate:a", 1.0, 0.2)


func _refresh_journal() -> void:
	for child in _journal_list.get_children():
		child.queue_free()
	for index in range(quests.size()):
		var quest: Dictionary = quests[index]
		var state: String = str(_state_of(quest).get("state"))
		var prefix: String = "✓ " if state == "completed" else ("◆ " if state == "active" else "· ")
		var entry := UiKit.make_label(
			prefix + str(quest.get("title", "")),
			7,
			UiKit.COLOR_ACCENT if index == _journal_index else (UiKit.COLOR_TEXT if state != "inactive" else UiKit.COLOR_TEXT_DIM),
		)
		entry.size = Vector2(140, 11)
		entry.clip_text = true
		_journal_list.add_child(entry)

	var selected: Dictionary = quests[_journal_index] if _journal_index < quests.size() else {}
	if selected.is_empty():
		return
	var quest_state: Dictionary = _state_of(selected)
	var state_name: String = str(quest_state.get("state"))
	var type_tag: String = {"main": "CHÍNH TUYẾN", "side": "PHỤ", "hidden": "ẨN"}.get(str(selected.get("type", "side")), "PHỤ")
	_journal_title.text = "%s   [%s]" % [selected.get("title", ""), type_tag]

	var lines: Array[String] = []
	lines.append(str(selected.get("summary", "")))
	lines.append("")
	var objectives: Array = selected.get("objectives", []) as Array
	var objective_index: int = int(quest_state.get("objective_index", 0))
	for index in range(objectives.size()):
		var objective: Dictionary = objectives[index] as Dictionary
		var mark: String
		if state_name == "completed" or index < objective_index:
			mark = "✓"
		elif index == objective_index and state_name == "active":
			mark = "◆"
		else:
			mark = "·"
		if state_name == "inactive" or (index > objective_index and state_name != "completed"):
			lines.append("%s ???" % mark)
		else:
			lines.append("%s %s" % [mark, objective.get("description", "")])
	lines.append("")
	if state_name == "completed":
		lines.append(str(selected.get("completion_text", "")))
	var reward_xp: int = int((selected.get("reward", {}) as Dictionary).get("xp", 0))
	if reward_xp > 0:
		lines.append("Phần thưởng: %d XP" % reward_xp)
	_journal_body.text = "\n".join(lines)


# ── choice dialog ─────────────────────────────────────────────────────────────


func _open_choice(payload: Dictionary) -> void:
	_choice_payload = payload
	_choice_open = true
	_choice_index = 0
	_choice_showing_consequence = false
	GameManager.ui_blocking_input = true
	var objective: Dictionary = payload.get("objective", {}) as Dictionary
	_choice_prompt.text = str(objective.get("prompt", objective.get("description", "")))
	_render_choice_options()
	_choice_root.visible = true
	_choice_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_choice_root, "modulate:a", 1.0, 0.25)


func _render_choice_options() -> void:
	for child in _choice_options_box.get_children():
		child.queue_free()
	var objective: Dictionary = _choice_payload.get("objective", {}) as Dictionary
	var options: Array = objective.get("options", []) as Array
	for index in range(options.size()):
		var option: Dictionary = options[index] as Dictionary
		var selected: bool = index == _choice_index
		var entry := UiKit.make_label(
			("> " if selected else "  ") + str(option.get("label", "")),
			8,
			UiKit.COLOR_ACCENT if selected else UiKit.COLOR_TEXT_DIM,
		)
		entry.size = Vector2(292, 12)
		_choice_options_box.add_child(entry)


func _confirm_choice() -> void:
	var objective: Dictionary = _choice_payload.get("objective", {}) as Dictionary
	var options: Array = objective.get("options", []) as Array
	if _choice_showing_consequence:
		_choice_root.visible = false
		_choice_open = false
		GameManager.ui_blocking_input = false
		var picked: Dictionary = options[_choice_index] as Dictionary if _choice_index < options.size() else {}
		choose_option(str(picked.get("id", "a")))
		return
	if _choice_index >= options.size():
		return
	var option: Dictionary = options[_choice_index] as Dictionary
	_choice_showing_consequence = true
	_choice_prompt.text = str(option.get("consequence_text", "")) if not str(option.get("consequence_text", "")).is_empty() else str(option.get("label", ""))
	for child in _choice_options_box.get_children():
		child.queue_free()
	var hint := UiKit.make_label("ENTER  tiếp tục", 7, UiKit.COLOR_TEXT_DIM)
	_choice_options_box.add_child(hint)


# ── input ─────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_J:
			_toggle_journal()
			get_viewport().set_input_as_handled()
			return

	if _choice_open:
		if event.is_action_pressed("ui_accept"):
			_confirm_choice()
			get_viewport().set_input_as_handled()
		elif not _choice_showing_consequence and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
			var objective: Dictionary = _choice_payload.get("objective", {}) as Dictionary
			var count: int = (objective.get("options", []) as Array).size()
			if count > 0:
				_choice_index = (_choice_index + (1 if event.is_action_pressed("ui_down") else count - 1)) % count
				_render_choice_options()
			get_viewport().set_input_as_handled()
		return

	if _journal_open:
		if event.is_action_pressed("ui_cancel"):
			_toggle_journal()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			if not quests.is_empty():
				var step: int = 1 if event.is_action_pressed("ui_down") else quests.size() - 1
				_journal_index = (_journal_index + step) % quests.size()
				_refresh_journal()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
