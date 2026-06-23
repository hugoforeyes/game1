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
## Emitted whenever the player talks to an NPC (the quest "talk" beat). Used by the
## CutsceneDirector to fire npc_talked-triggered cutscenes.
signal npc_talked(npc_id: String)

const TOAST_SECONDS := 2.4
const QuestTrackerFrameScript = preload("res://scripts/ui/QuestTrackerFrame.gd")
const QuestNotificationToastScript = preload("res://scripts/ui/QuestNotificationToast.gd")
const QuestJournalViewScript = preload("res://scripts/ui/QuestJournalView.gd")
const QUEST_UI_COMPONENT_DIR := "res://assets/ui/quest_hint_v1/components/"
const TRACKER_V2_COMPONENT_DIR := "res://assets/ui/quest_tracker_v2/components/"
const COLOR_HINT := Color(0.58, 0.94, 0.96, 1.0)
const TRACKER_WIDTH := 170.0
const TRACKER_RIGHT_MARGIN := 6.0
const TRACKER_TOP := 6.0
const TRACKER_EXPANDED_X := 480.0 - TRACKER_RIGHT_MARGIN - TRACKER_WIDTH
const TRACKER_COMPACT_SIZE := 30.0
const TRACKER_COMPACT_X := 480.0 - TRACKER_RIGHT_MARGIN - TRACKER_COMPACT_SIZE

var quests: Array = []
var quest_states: Dictionary = {}  # quest_id -> {state, objective_index, progress, choices}
var revealed_hints: Dictionary = {} # quest_id:objective_id -> level -> display payload
var tracked_quest_id: String = ""
var current_zone_id: String = ""

var _ui: CanvasLayer = null
var _tracker_panel: QuestTrackerFrame
var _tracker_quest_icon: TextureRect
var _tracker_title: Label
var _tracker_objective_heading: Label
var _tracker_objective: Label
var _tracker_progress: Label
var _tracker_collapse_icon: TextureButton
var _tracker_divider: TextureRect
var _tracker_objective_icon: TextureRect
var _tracker_progress_divider: TextureRect
var _tracker_progress_icon: TextureRect
var _tracker_progress_heading: Label
var _tracker_progress_bar_bg: ColorRect
var _tracker_progress_bar_fill: ColorRect
var _tracker_hint_divider: TextureRect
var _tracker_hint_icon: TextureRect
var _tracker_hint_heading: Label
var _tracker_hints_root: Control
var _tracker_hint_rows: Array[Control] = []
var _tracker_core_nodes: Array[CanvasItem] = []
var _tracker_base_height := 48.0
var _tracker_compact: bool = false
var _hint_collapsed: bool = false
var _hint_available: bool = false
var _toast_host: Control
var _toast_queue: Array = []
var _toast_busy: bool = false
var _journal_root: Control
var _journal_view
var _journal_open: bool = false
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
	revealed_hints = {}
	tracked_quest_id = ""
	_tracker_compact = false
	current_zone_id = ""
	_pending_choices.clear()
	_toast_queue.clear()
	_toast_busy = false
	if _toast_host != null:
		for child in _toast_host.get_children():
			child.queue_free()
	quests_changed.emit()
	_refresh_tracker()


func load_chapter_quests(chapter_quests: Array) -> void:
	quests = []
	quest_states = {}
	revealed_hints = {}
	tracked_quest_id = ""
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
			if tracked_quest_id.is_empty():
				tracked_quest_id = str(quest.get("id", ""))
			_push_toast("new_quest", quest)
			_skip_unavailable_objectives(quest)
			_finish_quest_if_exhausted(quest)
	_progress_reach_objectives()
	quests_changed.emit()
	_refresh_tracker()


func notify_npc_talked(npc_id: String) -> void:
	npc_talked.emit(npc_id)
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
				InventoryManager.grant_linked_items(
					"npc_grant", npc_id, current_zone_id,
					str(quest.get("id", "")), str(objective.get("id", "")),
				)
			"choice":
				var state: Dictionary = _state_of(quest)
				if not (state.get("choices", {}) as Dictionary).has(str(objective.get("id"))):
					_pending_choices.append({"quest": quest, "objective": objective})
			"deliver":
				_try_deliver(quest, objective)
	quests_changed.emit()
	_refresh_tracker()


func _try_deliver(quest: Dictionary, objective: Dictionary) -> void:
	var item: Dictionary = InventoryManager.quest_item_by_id(
		str(objective.get("item_id", objective.get("item_ref", ""))), str(quest.get("id"))
	)
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
		var quest_item: Dictionary = InventoryManager.quest_item_by_id(
			str(objective.get("item_id", objective.get("item_ref", ""))), str(quest.get("id"))
		)
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
		if not objective.is_empty() and str(objective.get("kind")) in ["talk", "choice", "collect", "deliver"] \
				and str(objective.get("zone_id")) == zone_id:
			return true
	return false


# ── story-dialogue progress gates ───────────────────────────────────────────────
# Drives the scene_npc_story_dialogue layer: which staged conversation an NPC shows
# depends on how far the player has progressed through the chapter's quests.


func completed_objective_count(quest_id: String) -> int:
	## How many objectives of this quest the player has finished. A completed quest
	## counts all of them; an active quest counts its objective_index; otherwise 0.
	var state: Dictionary = quest_states.get(quest_id, {}) as Dictionary
	if state.is_empty():
		return 0
	match str(state.get("state")):
		"completed":
			for quest in quests:
				if str(quest.get("id")) == quest_id:
					return (quest.get("objectives", []) as Array).size()
			return int(state.get("objective_index", 0))
		"active":
			return int(state.get("objective_index", 0))
		_:
			return 0


func is_objective_active(quest_id: String, objective_id: String) -> bool:
	## True if this quest is active AND the given objective is its current one.
	## Used to gate NPC hint options so a hint only appears while the player is
	## actually working on that objective (never spoiling later steps).
	for quest in quests:
		if str(quest.get("id")) != quest_id:
			continue
		var objective: Dictionary = _current_objective(quest)
		return not objective.is_empty() and str(objective.get("id")) == objective_id
	return false


func reveal_hint(
		npc_name: String,
		hint: Dictionary,
		text: String,
		portrait: Texture2D = null,
) -> void:
	var quest_id := str(hint.get("quest_id", ""))
	var objective_id := str(hint.get("objective_id", ""))
	if quest_id.is_empty() or objective_id.is_empty() or text.strip_edges().is_empty():
		return
	if not is_objective_active(quest_id, objective_id):
		return
	var key := "%s:%s" % [quest_id, objective_id]
	var level := clampi(int(hint.get("level", 1)), 1, 3)
	var hints_by_level: Dictionary = revealed_hints.get(key, {}) as Dictionary
	var level_key := str(level)
	var is_new := not hints_by_level.has(level_key)
	var payload := {
		"quest_id": quest_id,
		"objective_id": objective_id,
		"level": level,
		"npc_name": npc_name,
		"text": text.strip_edges(),
		"portrait": portrait,
	}
	hints_by_level[level_key] = payload
	revealed_hints[key] = hints_by_level
	_hint_collapsed = false
	if is_new:
		_toast_queue.append({"kind": "hint", "hint": payload})
	_refresh_tracker()


func stage_unlocked(unlock: Dictionary) -> bool:
	## True if a story-dialogue stage's unlock condition is satisfied right now.
	## Mirrors utils/npc_dialogue_common + scene_npc_story_dialogue unlock kinds.
	match str(unlock.get("type", "chapter_start")):
		"chapter_start":
			return true
		"quest_complete":
			var st: Dictionary = quest_states.get(str(unlock.get("quest_id", "")), {}) as Dictionary
			return str(st.get("state")) == "completed"
		"quest_objective":
			var need: int = int(unlock.get("objective_index", 1))
			return completed_objective_count(str(unlock.get("quest_id", ""))) >= need
		"quest_choice":
			return NarrativeState.choice_matches(unlock)
		"flag", "relationship":
			return NarrativeState.condition_met(unlock)
		_:
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
	_skip_unavailable_objectives(quest)
	if state["objective_index"] >= objectives.size():
		_finish_quest(quest)
	else:
		_push_toast("objective", quest)
		print("[Quest] %s objective %d/%d" % [quest.get("id"), state["objective_index"], objectives.size()])


func choose_option(option_id: String) -> void:
	var quest: Dictionary = _choice_payload.get("quest", {}) as Dictionary
	resolve_quest_choice(str(quest.get("id", "")), option_id)


## Resolve a quest's moral choice from inside a conversation tree (an option's
## "quest_choice" effect). No-op unless that quest's CURRENT objective is the
## choice — otherwise the separate choice dialog handles it as a fallback.
func resolve_quest_choice(quest_id: String, option_id: String) -> bool:
	for quest in quests:
		if str(quest.get("id")) != quest_id:
			continue
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("kind")) != "choice":
			return false
		var state: Dictionary = _state_of(quest)
		var choices: Dictionary = state.get("choices", {}) as Dictionary
		if choices.has(str(objective.get("id"))):
			return false  # already decided
		var selected: Dictionary = {}
		for option in objective.get("options", []) as Array:
			if option is Dictionary and str((option as Dictionary).get("id", "")) == option_id:
				selected = option as Dictionary
				break
		if selected.is_empty():
			return false
		var outcome: Dictionary = selected.get("outcome", {}) as Dictionary if selected.get("outcome") is Dictionary else {}
		var choice_key := str(objective.get("choice_key", "%s:%s" % [quest_id, objective.get("id", "")]))
		if not NarrativeState.record_choice(
			choice_key,
			quest_id,
			str(objective.get("id", "")),
			option_id,
			outcome,
		):
			return false
		_pending_choices = _pending_choices.filter(func(payload: Dictionary) -> bool:
			var queued_quest: Dictionary = payload.get("quest", {}) as Dictionary
			var queued_objective: Dictionary = payload.get("objective", {}) as Dictionary
			return str(queued_quest.get("id", "")) != quest_id \
				or str(queued_objective.get("id", "")) != str(objective.get("id", ""))
		)
		choices[str(objective.get("id"))] = option_id
		_apply_choice_outcome(outcome)
		_complete_current_objective(quest)
		quests_changed.emit()
		_refresh_tracker()
		print("[Quest] %s choice resolved in dialogue -> %s" % [quest_id, option_id])
		return true
	return false


func _apply_choice_outcome(outcome: Dictionary) -> void:
	for grant in outcome.get("give_items", []) as Array:
		if not (grant is Dictionary):
			continue
		var item_id := str((grant as Dictionary).get("item_id", ""))
		if not item_id.is_empty():
			InventoryManager.add_item(item_id, maxi(1, int((grant as Dictionary).get("count", 1))))
	var xp := maxi(0, int(outcome.get("xp", 0)))
	if xp > 0:
		GameManager.gain_xp(xp)


func _skip_unavailable_objectives(quest: Dictionary) -> void:
	var state: Dictionary = _state_of(quest)
	var objectives: Array = quest.get("objectives", []) as Array
	while int(state.get("objective_index", 0)) < objectives.size():
		var objective: Dictionary = objectives[int(state.get("objective_index", 0))] as Dictionary
		var requirement: Variant = objective.get("requires")
		if not (requirement is Dictionary) or NarrativeState.condition_met(requirement as Dictionary):
			break
		state["objective_index"] = int(state.get("objective_index", 0)) + 1
		state["progress"] = 0


func _finish_quest_if_exhausted(quest: Dictionary) -> void:
	var state: Dictionary = _state_of(quest)
	if str(state.get("state")) == "active" \
			and int(state.get("objective_index", 0)) >= (quest.get("objectives", []) as Array).size():
		_finish_quest(quest)


func _finish_quest(quest: Dictionary) -> void:
	var state: Dictionary = _state_of(quest)
	if str(state.get("state")) == "completed":
		return
	state["state"] = "completed"
	if tracked_quest_id == str(quest.get("id", "")):
		tracked_quest_id = ""
	var xp: int = int((quest.get("reward", {}) as Dictionary).get("xp", 50))
	GameManager.gain_xp(xp)
	var reward_item: Dictionary = InventoryManager.reward_item_for(str(quest.get("id")))
	if not reward_item.is_empty():
		InventoryManager.add_item(str(reward_item.get("id")))
	InventoryManager.grant_linked_items(
		"quest_reward", "", current_zone_id, str(quest.get("id", "")),
	)
	_push_toast("quest_complete", quest)
	print("[Quest] completed %s (+%d XP)" % [quest.get("id"), xp])


# ── UI construction ───────────────────────────────────────────────────────────


func _make_art(file_name: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var art := TextureRect.new()
	art.texture = load(QUEST_UI_COMPONENT_DIR + file_name) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.position = rect.position.round()
	art.size = rect.size.round()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mode == TextureRect.STRETCH_TILE:
		art.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return art


func _make_tracker_art(file_name: String, rect: Rect2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = load(TRACKER_V2_COMPONENT_DIR + file_name) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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


func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 45
	_ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(_ui)

	# Combined quest tracker, anchored to the upper-right of the 480x270 UI canvas.
	_tracker_panel = QuestTrackerFrameScript.new()
	_tracker_panel.setup(Rect2(TRACKER_EXPANDED_X, TRACKER_TOP, TRACKER_WIDTH, 100))
	_tracker_panel.visible = false
	_ui.add_child(_tracker_panel)

	_tracker_quest_icon = _make_tracker_art("badge_expanded.png", Rect2(8, 5, 28, 28))
	_tracker_panel.add_child(_tracker_quest_icon)
	_tracker_title = _place_label(UiKit.make_label("", 8, UiKit.COLOR_ACCENT), Rect2(40, 6, 104, 24))
	_tracker_title.clip_text = true
	_tracker_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tracker_panel.add_child(_tracker_title)
	_tracker_collapse_icon = TextureButton.new()
	_tracker_collapse_icon.texture_normal = load(TRACKER_V2_COMPONENT_DIR + "icon_collapse.png") as Texture2D
	_tracker_collapse_icon.ignore_texture_size = true
	_tracker_collapse_icon.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_tracker_collapse_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tracker_collapse_icon.position = Vector2(148, 10)
	_tracker_collapse_icon.size = Vector2(14, 14)
	_tracker_collapse_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tracker_collapse_icon.pressed.connect(_toggle_tracker_compact)
	_tracker_panel.add_child(_tracker_collapse_icon)
	_tracker_divider = _make_art("divider.png", Rect2(10, 35, 150, 2), TextureRect.STRETCH_TILE)
	_tracker_panel.add_child(_tracker_divider)

	_tracker_objective_icon = _make_tracker_art("icon_objective.png", Rect2(10, 40, 11, 11))
	_tracker_panel.add_child(_tracker_objective_icon)
	_tracker_objective_heading = _place_label(UiKit.make_label("MỤC TIÊU", 6, UiKit.COLOR_ACCENT), Rect2(25, 38, 120, 14))
	_tracker_panel.add_child(_tracker_objective_heading)
	_tracker_objective = _place_label(
		UiKit.make_label("", 6, UiKit.COLOR_TEXT), Rect2(25, 52, 135, 16), VERTICAL_ALIGNMENT_TOP
	)
	_tracker_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_objective.max_lines_visible = 4
	_tracker_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tracker_panel.add_child(_tracker_objective)

	_tracker_progress_divider = _make_art("divider.png", Rect2(10, 72, 150, 2), TextureRect.STRETCH_TILE)
	_tracker_progress_divider.modulate = Color(0.48, 0.72, 1.0, 0.55)
	_tracker_panel.add_child(_tracker_progress_divider)
	_tracker_progress_icon = _make_tracker_art("icon_progress.png", Rect2(10, 78, 10, 10))
	_tracker_panel.add_child(_tracker_progress_icon)
	_tracker_progress_heading = _place_label(UiKit.make_label("TIẾN ĐỘ", 6, Color(0.45, 0.75, 1.0, 1.0)), Rect2(25, 75, 90, 14))
	_tracker_panel.add_child(_tracker_progress_heading)
	_tracker_progress = _place_label(UiKit.make_label("", 6, UiKit.COLOR_TEXT), Rect2(124, 75, 36, 14))
	_tracker_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tracker_panel.add_child(_tracker_progress)
	_tracker_progress_bar_bg = ColorRect.new()
	_tracker_progress_bar_bg.color = Color(0.06, 0.07, 0.08, 1.0)
	_tracker_progress_bar_bg.position = Vector2(25, 91)
	_tracker_progress_bar_bg.size = Vector2(135, 4)
	_tracker_progress_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_panel.add_child(_tracker_progress_bar_bg)
	_tracker_progress_bar_fill = ColorRect.new()
	_tracker_progress_bar_fill.color = Color(0.34, 0.65, 1.0, 0.95)
	_tracker_progress_bar_fill.position = Vector2(26, 92)
	_tracker_progress_bar_fill.size = Vector2(0, 2)
	_tracker_progress_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_panel.add_child(_tracker_progress_bar_fill)

	_tracker_hint_divider = _make_art("divider.png", Rect2(10, 102, 150, 2), TextureRect.STRETCH_TILE)
	_tracker_hint_divider.modulate = Color(0.55, 1.0, 1.0, 0.65)
	_tracker_panel.add_child(_tracker_hint_divider)
	_tracker_hint_icon = _make_tracker_art("icon_hint.png", Rect2(10, 107, 11, 11))
	_tracker_panel.add_child(_tracker_hint_icon)
	_tracker_hint_heading = _place_label(UiKit.make_label("GỢI Ý", 6, COLOR_HINT), Rect2(25, 104, 90, 14))
	_tracker_panel.add_child(_tracker_hint_heading)
	_tracker_hints_root = Control.new()
	_tracker_hints_root.position = Vector2(25, 119)
	_tracker_hints_root.size = Vector2(135, 1)
	_tracker_panel.add_child(_tracker_hints_root)
	_tracker_core_nodes.assign([
		_tracker_quest_icon, _tracker_title, _tracker_divider,
		_tracker_objective_icon, _tracker_objective_heading, _tracker_objective,
		_tracker_progress_divider, _tracker_progress_icon, _tracker_progress_heading,
		_tracker_progress, _tracker_progress_bar_bg, _tracker_progress_bar_fill,
	])

	# Toast host (top-center)
	_toast_host = Control.new()
	_toast_host.position = Vector2(240, 0)
	_ui.add_child(_toast_host)

	_build_journal()
	_build_choice_dialog()


func _build_journal() -> void:
	_journal_view = QuestJournalViewScript.new()
	_journal_root = _journal_view
	_journal_root.visible = false
	_journal_view.close_requested.connect(_toggle_journal)
	_journal_view.track_requested.connect(_on_journal_track_requested)
	_ui.add_child(_journal_root)


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
	if not _toast_queue.is_empty() and not _toast_busy:
		_show_next_toast()
	var has_active: bool = quests.any(func(q): return str(_state_of(q).get("state")) == "active")
	var hud_visible := has_active and not GameManager.ui_blocking_input and not _journal_open \
		and not _choice_open and not _toast_busy
	_tracker_panel.visible = hud_visible

	if not _pending_choices.is_empty() and not _choice_open and not GameManager.ui_blocking_input:
		_open_choice(_pending_choices.pop_front() as Dictionary)

func _refresh_tracker() -> void:
	if _ui == null:
		return
	var display_quest: Dictionary = {}
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty():
			continue
		if display_quest.is_empty():
			display_quest = quest
		if str(quest.get("id", "")) == tracked_quest_id:
			display_quest = quest
			break
	if not display_quest.is_empty():
		var objective: Dictionary = _current_objective(display_quest)
		for node in _tracker_core_nodes:
			node.visible = true
		_tracker_collapse_icon.visible = true
		_tracker_title.text = str(display_quest.get("title", ""))
		_tracker_objective.text = str(objective.get("description", ""))
		var state: Dictionary = _state_of(display_quest)
		var has_count := objective.has("count")
		var current := maxi(0, int(state.get("progress", 0))) if has_count else 0
		var total := maxi(1, int(objective.get("count", 1))) if has_count else 1
		_tracker_progress.text = "%d / %d" % [current, total]
		var ratio := clampf(float(current) / float(total), 0.0, 1.0)
		_tracker_progress_bar_fill.size.x = roundf(133.0 * ratio)
		_layout_tracker_objective()
		_refresh_hint_rows(display_quest, objective)
		_apply_tracker_compact()
		return
	_hint_available = false
	_tracker_title.text = ""
	_tracker_objective.text = ""
	_tracker_progress.text = ""
	_tracker_panel.size = Vector2(TRACKER_WIDTH, 48)
	_tracker_collapse_icon.visible = false
	_tracker_hint_divider.visible = false
	_tracker_hint_icon.visible = false
	_tracker_hints_root.visible = false


func _layout_tracker_objective() -> void:
	var text := _tracker_objective.text
	var font := _tracker_objective.get_theme_font("font")
	var measured := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, 135.0, 6, 4
	)
	var objective_height := clampf(ceilf(measured.y), 14.0, 44.0)
	_tracker_objective.position = Vector2(25, 52)
	_tracker_objective.size = Vector2(135, objective_height)
	var progress_y := 52.0 + objective_height + 4.0
	_tracker_progress_divider.position = Vector2(10, progress_y)
	_tracker_progress_icon.position = Vector2(10, progress_y + 7.0)
	_tracker_progress_heading.position = Vector2(25, progress_y + 4.0)
	_tracker_progress.position = Vector2(124, progress_y + 4.0)
	_tracker_progress_bar_bg.position = Vector2(25, progress_y + 20.0)
	_tracker_progress_bar_fill.position = Vector2(26, progress_y + 21.0)
	_tracker_base_height = progress_y + 30.0
	var hint_divider_y := _tracker_base_height + 1.0
	_tracker_hint_divider.position = Vector2(10, hint_divider_y)
	_tracker_hint_icon.position = Vector2(10, hint_divider_y + 6.0)
	_tracker_hint_heading.position = Vector2(25, hint_divider_y + 3.0)
	_tracker_hints_root.position = Vector2(25, hint_divider_y + 18.0)


func _refresh_hint_rows(quest: Dictionary, objective: Dictionary) -> void:
	for child in _tracker_hints_root.get_children():
		child.free()
	_tracker_hint_rows.clear()
	var key := "%s:%s" % [str(quest.get("id", "")), str(objective.get("id", ""))]
	var hints_by_level: Dictionary = revealed_hints.get(key, {}) as Dictionary
	var levels: Array[int] = []
	for level_key in hints_by_level:
		levels.append(int(level_key))
	levels.sort()
	_hint_available = not levels.is_empty()
	var show_hints := _hint_available and not _hint_collapsed
	_tracker_hint_divider.visible = show_hints
	_tracker_hint_icon.visible = show_hints
	_tracker_hint_heading.visible = show_hints
	_tracker_hints_root.visible = show_hints
	if not show_hints:
		_tracker_panel.size = Vector2(TRACKER_WIDTH, _tracker_base_height)
		return

	var y_offset := 0.0
	for index in range(levels.size()):
		var level := levels[index]
		var payload: Dictionary = hints_by_level.get(str(level), {}) as Dictionary
		var row := Control.new()
		row.position = Vector2(0, y_offset)
		row.size.x = 135
		_tracker_hints_root.add_child(row)
		_tracker_hint_rows.append(row)

		var branch_text := "└" if index == levels.size() - 1 else "├"
		var branch := _place_label(UiKit.make_label(branch_text, 6, COLOR_HINT), Rect2(0, 0, 10, 11), VERTICAL_ALIGNMENT_TOP)
		row.add_child(branch)
		var line_text := "Gợi ý %d · %s" % [level, str(payload.get("text", ""))]
		var line := UiKit.make_label(line_text, 6, Color(COLOR_HINT, 0.86))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.max_lines_visible = 3
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var font := line.get_theme_font("font")
		var measured := font.get_multiline_string_size(line_text, HORIZONTAL_ALIGNMENT_LEFT, 124.0, 6, 3)
		var row_height := clampf(ceilf(measured.y), 11.0, 33.0)
		line.position = Vector2(11, 0)
		line.size = Vector2(124, row_height)
		line.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row.add_child(line)
		row.size.y = row_height
		y_offset += row_height + 2.0

	_tracker_hints_root.size.y = y_offset
	_tracker_panel.size = Vector2(TRACKER_WIDTH, _tracker_hints_root.position.y + y_offset + 7.0)


func _toggle_tracker_compact() -> void:
	_tracker_compact = not _tracker_compact
	_refresh_tracker()


func _apply_tracker_compact() -> void:
	if _tracker_panel == null:
		return
	if _tracker_compact:
		_tracker_panel.set_frame_visible(false)
		for node in _tracker_core_nodes:
			node.visible = false
		_tracker_hint_divider.visible = false
		_tracker_hint_icon.visible = false
		_tracker_hint_heading.visible = false
		_tracker_hints_root.visible = false
		_tracker_panel.position = Vector2(TRACKER_COMPACT_X, TRACKER_TOP)
		_tracker_panel.size = Vector2(TRACKER_COMPACT_SIZE, TRACKER_COMPACT_SIZE)
		_tracker_collapse_icon.position = Vector2.ZERO
		_tracker_collapse_icon.size = Vector2(TRACKER_COMPACT_SIZE, TRACKER_COMPACT_SIZE)
		_tracker_collapse_icon.texture_normal = load(TRACKER_V2_COMPONENT_DIR + "badge_compact.png") as Texture2D
	else:
		_tracker_panel.set_frame_visible(true)
		_tracker_panel.position = Vector2(TRACKER_EXPANDED_X, TRACKER_TOP)
		_tracker_collapse_icon.position = Vector2(148, 10)
		_tracker_collapse_icon.size = Vector2(14, 14)
		_tracker_collapse_icon.texture_normal = load(TRACKER_V2_COMPONENT_DIR + "icon_collapse.png") as Texture2D


func _apply_hint_collapsed() -> void:
	if _tracker_panel == null:
		return
	_refresh_tracker()


func _push_toast(kind: String, quest: Dictionary) -> void:
	var payload := {"kind": kind, "quest": quest.duplicate(true)}
	if kind == "objective":
		payload["objective"] = _current_objective(quest).duplicate(true)
		payload["progress"] = int(_state_of(quest).get("progress", 0))
	_toast_queue.append(payload)


func _show_next_toast() -> void:
	_toast_busy = true
	var item: Dictionary = _toast_queue.pop_front()
	var panel = QuestNotificationToastScript.new()
	panel.setup(_notification_display_data(item))
	panel.position = Vector2(-panel.size.x * 0.5, -panel.size.y - 8).round()
	panel.scale = Vector2(0.96, 0.96)
	panel.modulate.a = 0.0
	_toast_host.add_child(panel)
	panel.animate_effects()

	var tween := create_tween()
	tween.tween_property(panel, "position:y", 8.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(panel, "position:y", -panel.size.y - 8.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		panel.queue_free()
		_toast_busy = false
	)


func _notification_display_data(item: Dictionary) -> Dictionary:
	var kind := str(item.get("kind", "objective"))
	var quest: Dictionary = item.get("quest", {}) as Dictionary
	match kind:
		"new_quest":
			return {
				"palette": "gold", "icon": "new_quest", "header": "NHIỆM VỤ MỚI",
				"title": str(quest.get("title", "Nhiệm vụ mới")),
				"subtitle": "Một hành trình mới đã bắt đầu",
			}
		"quest_complete":
			return {
				"palette": "gold", "icon": "new_quest", "header": "HOÀN THÀNH NHIỆM VỤ",
				"title": str(quest.get("title", "Nhiệm vụ")),
				"subtitle": "+%d XP" % int((quest.get("reward", {}) as Dictionary).get("xp", 0)),
				"title_font_size": 7,
			}
		"hint":
			var hint: Dictionary = item.get("hint", {}) as Dictionary
			return {
				"palette": "cyan", "icon": "new_objective", "header": "GỢI Ý MỚI",
				"title": "Từ %s" % str(hint.get("npc_name", "NPC")),
				"subtitle": "Đã cập nhật bảng gợi ý",
			}
		_:
			var objective: Dictionary = item.get("objective", {}) as Dictionary
			var subtitle := ""
			if objective.has("count"):
				subtitle = "%d / %d" % [int(item.get("progress", 0)), maxi(1, int(objective.get("count", 1)))]
			return {
				"palette": "cyan", "icon": "new_objective", "header": "MỤC TIÊU MỚI",
				"title": str(objective.get("description", "Mục tiêu mới")),
				"subtitle": subtitle,
				"title_font_size": 6,
			}


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
	_refresh_journal()
	_journal_root.visible = true
	_journal_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_journal_root, "modulate:a", 1.0, 0.2)


func _refresh_journal() -> void:
	if _journal_view == null:
		return
	var chapter: Dictionary = ChapterFlow.current_chapter()
	var chapter_number := str(chapter.get("chapter", "?"))
	var chapter_title := str(chapter.get("title", ""))
	var context := "CHƯƠNG %s" % chapter_number
	if not chapter_title.is_empty():
		context += "  ·  " + chapter_title
	_journal_view.set_data(quests, quest_states, revealed_hints, tracked_quest_id, context)


func _on_journal_track_requested(quest_id: String) -> void:
	tracked_quest_id = quest_id
	_refresh_tracker()
	_refresh_journal()


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
		if (event as InputEventKey).physical_keycode == KEY_H and _tracker_panel != null \
				and _tracker_panel.visible \
				and not GameManager.ui_blocking_input and not _journal_open and not _choice_open:
			_toggle_tracker_compact()
			get_viewport().set_input_as_handled()
			return
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
		if _journal_view != null and _journal_view.handle_input(event):
			get_viewport().set_input_as_handled()
		return
