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
## Emitted the moment a player has now heard all 3 hint levels for one objective —
## QuestCompassView listens for this to start pointing toward the exact target.
signal objective_fully_hinted(quest_id: String, objective_id: String)
## Emitted after a moral choice resolves, carrying the applied-consequence
## summary ({option_id, option_label, consequence_text, npc_reaction, chips})
## the ceremony UI displays. Mirrored in last_choice_result.
signal choice_resolved(result: Dictionary)

const TOAST_SECONDS := 2.4
const QuestTrackerViewScript = preload("res://scripts/ui/QuestTrackerView.gd")
const QuestNotificationToastScript = preload("res://scripts/ui/QuestNotificationToast.gd")
const PartyHudViewScript = preload("res://scripts/ui/PartyHudView.gd")
const QuestJournalViewScript = preload("res://scripts/ui/QuestJournalView.gd")
const MoralChoiceViewScript = preload("res://scripts/ui/MoralChoiceView.gd")

var quests: Array = []
var last_choice_result: Dictionary = {}  # summary of the most recent moral choice
var quest_states: Dictionary = {}  # quest_id -> {state, objective_index, progress, choices}
var revealed_hints: Dictionary = {} # quest_id:objective_id -> level -> display payload
var tracked_quest_id: String = ""
var current_zone_id: String = ""
# Zones the player has ACTUALLY set foot in. A `reach` objective completes only
# when its target zone is in here — never via a play-order index comparison (side
# zones like the hidden bakery sort late, which used to falsely "pass" earlier zones).
var visited_zones: Dictionary = {}
# "npc_id:node_id" -> true for every dialogue-tree node ever reached, across every
# conversation session (not just the currently-open one). ChatBox seeds its
# per-session _visited_nodes from this on open, and writes back to it as the
# conversation progresses — so "already picked this topic before" survives
# closing and reopening the chat, not just navigating within one open session.
var visited_dialogue_nodes: Dictionary = {}
# Per-chapter quest-progress snapshots, keyed by String(chapter_number). Captured just
# before load_chapter_quests() wipes the live state for a DIFFERENT chapter (world map
# travel), and re-applied the next time that chapter's quests are loaded — so revisiting
# an already-completed (or partially played) chapter doesn't reset its quest journal back
# to "inactive". World state (visited_zones is chapter-scoped and lives here too;
# defeated_enemy_ids/collected_item_pickup_ids are separate GameManager dicts, untouched).
var _chapter_snapshots: Dictionary = {}

var _ui: CanvasLayer = null
var _journal_layer: CanvasLayer = null
var _tracker_view: QuestTrackerView = null
var _tracker_layer: CanvasLayer = null
var _toast_host: Control
var _toast_queue: Array = []
var _toast_busy: bool = false
var _journal_root: Control
var _journal_view
var _journal_open: bool = false
var _choice_open: bool = false  # a MoralChoiceView ceremony currently owns the screen
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
	current_zone_id = ""
	visited_zones = {}
	visited_dialogue_nodes = {}
	_chapter_snapshots = {}
	_pending_choices.clear()
	_toast_queue.clear()
	_toast_busy = false
	if _toast_host != null:
		for child in _toast_host.get_children():
			child.queue_free()
	quests_changed.emit()
	_refresh_tracker()


# ── persistence (SaveManager) ──────────────────────────────────────────────────


func serialize_save() -> Dictionary:
	return {
		"quest_states": quest_states.duplicate(true),
		"tracked_quest_id": tracked_quest_id,
		"visited_zones": visited_zones.duplicate(true),
		"revealed_hints": revealed_hints.duplicate(true),
		"visited_dialogue_nodes": visited_dialogue_nodes.duplicate(true),
		"chapter_snapshots": _chapter_snapshots.duplicate(true),
	}


## Restore quest progress onto the CURRENTLY loaded chapter quests (call after
## load_chapter_quests so the quest definitions already exist).
func apply_save(data: Dictionary) -> void:
	var saved_states: Dictionary = data.get("quest_states", {}) as Dictionary
	for quest_id in saved_states.keys():
		if quest_states.has(quest_id):
			quest_states[quest_id] = (saved_states[quest_id] as Dictionary).duplicate(true)
	tracked_quest_id = str(data.get("tracked_quest_id", ""))
	visited_zones = (data.get("visited_zones", {}) as Dictionary).duplicate(true)
	revealed_hints = (data.get("revealed_hints", {}) as Dictionary).duplicate(true)
	visited_dialogue_nodes = (data.get("visited_dialogue_nodes", {}) as Dictionary).duplicate(true)
	_chapter_snapshots = (data.get("chapter_snapshots", {}) as Dictionary).duplicate(true)
	quests_changed.emit()
	_refresh_tracker()


## Capture the CURRENTLY loaded chapter's live quest progress before it gets wiped by a
## load_chapter_quests() call for a different chapter (ChapterFlow.goto_chapter). No-op if
## no chapter is loaded yet (chapter_number <= 0, e.g. very first chapter of a new game).
func snapshot_current_chapter(chapter_number: int) -> void:
	if chapter_number <= 0:
		return
	_chapter_snapshots[str(chapter_number)] = {
		"quest_states": quest_states.duplicate(true),
		"revealed_hints": revealed_hints.duplicate(true),
		"tracked_quest_id": tracked_quest_id,
		"visited_zones": visited_zones.duplicate(true),
	}


## Re-apply a previously snapshotted chapter's quest progress onto its freshly loaded
## quest definitions (call right after load_chapter_quests). No-op, returns false, on a
## chapter's first-ever visit (nothing snapshotted yet) — its quests simply start fresh.
func restore_chapter_snapshot(chapter_number: int) -> bool:
	var key := str(chapter_number)
	if not _chapter_snapshots.has(key):
		return false
	var snapshot: Dictionary = _chapter_snapshots[key] as Dictionary
	var saved_states: Dictionary = snapshot.get("quest_states", {}) as Dictionary
	for quest_id in saved_states.keys():
		if quest_states.has(quest_id):
			quest_states[quest_id] = (saved_states[quest_id] as Dictionary).duplicate(true)
	revealed_hints = (snapshot.get("revealed_hints", {}) as Dictionary).duplicate(true)
	tracked_quest_id = str(snapshot.get("tracked_quest_id", ""))
	visited_zones = (snapshot.get("visited_zones", {}) as Dictionary).duplicate(true)
	quests_changed.emit()
	_refresh_tracker()
	print("[Quest] restored chapter %d quest snapshot" % chapter_number)
	return true


func load_chapter_quests(chapter_quests: Array) -> void:
	quests = []
	quest_states = {}
	revealed_hints = {}
	tracked_quest_id = ""
	visited_zones = {}
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
	visited_zones[zone_id] = true
	# A quest GIVEN by an NPC stays inactive until the player actually talks to that
	# giver (see notify_npc_talked) — so the story unfolds through conversation, never
	# "you reached a zone, here's a quest about people you've never met". Only quests
	# with no NPC giver (environmental/auto) start on arrival at their start zone.
	for quest in quests:
		var state: Dictionary = _state_of(quest)
		if str(state.get("state")) != "inactive":
			continue
		if not _quest_giver_npc(quest).is_empty():
			continue
		var start_zone: String = _quest_start_zone(quest)
		if start_zone == zone_id or visited_zones.has(start_zone):
			_activate_quest(quest)
	_progress_reach_objectives()
	_settle_collect_objectives()
	quests_changed.emit()
	_refresh_tracker()


func _activate_quest(quest: Dictionary) -> void:
	var state: Dictionary = _state_of(quest)
	if str(state.get("state")) != "inactive":
		return
	state["state"] = "active"
	if tracked_quest_id.is_empty():
		tracked_quest_id = str(quest.get("id", ""))
	_push_toast("new_quest", quest)
	_skip_unavailable_objectives(quest)
	_finish_quest_if_exhausted(quest)


func _quest_giver_npc(quest: Dictionary) -> String:
	var giver: Dictionary = quest.get("giver", {}) as Dictionary
	if str(giver.get("mode", "npc")) != "npc":
		return ""
	return str(giver.get("npc_id", ""))


func _quest_giver_zone(quest: Dictionary) -> String:
	var giver: Dictionary = quest.get("giver", {}) as Dictionary
	return str(giver.get("zone_id", ""))


func notify_npc_talked(npc_id: String) -> void:
	npc_talked.emit(npc_id)
	# Talking to a quest giver is how that quest BEGINS — the NPC asks for help, and
	# only then do its objectives appear. This is what makes the chain feel like a
	# story ("meet Arlo → he sends you to the field → bring the petals back to him").
	for quest in quests:
		if str(_state_of(quest).get("state")) == "inactive" and _quest_giver_npc(quest) == npc_id:
			_activate_quest(quest)
	# A just-started quest may have its first step satisfiable right here/now.
	_progress_reach_objectives()
	_settle_collect_objectives()
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
	_grant_current_npc_collect_objectives(npc_id)
	_settle_collect_objectives()
	quests_changed.emit()
	_refresh_tracker()


func _grant_current_npc_collect_objectives(npc_id: String) -> void:
	# Some collect steps are fulfilled by talking to an NPC instead of picking up a
	# world item. The acquisition rule is the source of truth for which NPC grants it.
	for quest in quests:
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("kind")) != "collect":
			continue
		if str(objective.get("zone_id")) != current_zone_id:
			continue
		var quest_id := str(quest.get("id", ""))
		var objective_id := str(objective.get("id", ""))
		InventoryManager.grant_linked_items(
			"npc_grant", npc_id, current_zone_id,
			quest_id, objective_id,
		)
		var quest_item: Dictionary = InventoryManager.quest_item_by_id(
			str(objective.get("item_id", objective.get("item_ref", ""))), quest_id
		)
		var item_id := str(quest_item.get("id", ""))
		if item_id.is_empty():
			continue
		if InventoryManager.count_of(item_id) >= int(objective.get("count", 1)):
			continue
		if InventoryManager.has_method("grant_linked_item_for_objective"):
			InventoryManager.grant_linked_item_for_objective(
				item_id, "npc_grant", npc_id, current_zone_id, quest_id, objective_id,
			)


## Resolve an objective the player closes by interacting with a WORLD OBJECT
## (the chapter_object_interactions contract's `completes`). Idempotent: only acts
## when the named objective is the quest's CURRENT active one — `collect` objectives
## are usually already advanced by the item_obtained signal that the grant fired, so
## this is a safety net mainly for give/exchange (non-collect) closures. Returns true
## when it actually advanced the quest.
func notify_object_objective(quest_id: String, objective_id: String) -> bool:
	for quest in quests:
		if str(quest.get("id")) != quest_id:
			continue
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("id")) != objective_id:
			return false
		_complete_current_objective(quest)
		quests_changed.emit()
		_refresh_tracker()
		print("[Quest] %s objective %s closed by object interaction" % [quest_id, objective_id])
		return true
	return false


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


## Re-evaluate every active quest's CURRENT objective against the inventory the
## player already holds. `_on_item_obtained` only fires the moment an item arrives,
## so an item grabbed BEFORE its collect objective became active (e.g. searching a
## chest before the quest reaches that step) would otherwise never register. Calling
## this whenever items change or an objective advances makes collect order-independent.
func notify_items_changed() -> void:
	if _settle_collect_objectives():
		quests_changed.emit()
		_refresh_tracker()


func _settle_collect_objectives() -> bool:
	var changed := false
	for quest in quests:
		var guard := 0
		while guard < 12:
			guard += 1
			var objective: Dictionary = _current_objective(quest)
			if objective.is_empty() or str(objective.get("kind")) != "collect":
				break
			var quest_item: Dictionary = InventoryManager.quest_item_by_id(
				str(objective.get("item_id", objective.get("item_ref", ""))), str(quest.get("id"))
			)
			var wanted: String = str(quest_item.get("id", ""))
			if wanted.is_empty():
				break
			var owned: int = InventoryManager.count_of(wanted)
			if owned < int(objective.get("count", 1)):
				_grant_collect_objective_from_party_sources(quest, objective, wanted)
				owned = InventoryManager.count_of(wanted)
			var state: Dictionary = _state_of(quest)
			state["progress"] = owned
			if owned >= int(objective.get("count", 1)):
				_complete_current_objective(quest)
				changed = true
			else:
				break
	return changed


func _grant_collect_objective_from_party_sources(
		quest: Dictionary,
		objective: Dictionary,
		item_id: String,
	) -> void:
	if item_id.is_empty():
		return
	var objective_zone := str(objective.get("zone_id", ""))
	if not objective_zone.is_empty() and current_zone_id != objective_zone:
		return
	if not InventoryManager.has_method("npc_grant_sources_for_item") \
			or not InventoryManager.has_method("grant_linked_item_for_objective"):
		return
	if not PartyManager.has_method("is_member"):
		return
	var quest_id := str(quest.get("id", ""))
	for npc_id in InventoryManager.npc_grant_sources_for_item(
			item_id, quest_id, objective_zone,
		):
		if not PartyManager.is_member(str(npc_id)):
			continue
		InventoryManager.grant_linked_item_for_objective(
			item_id, "npc_grant", str(npc_id), objective_zone,
			quest_id, str(objective.get("id", "")),
		)
		if InventoryManager.count_of(item_id) >= int(objective.get("count", 1)):
			return


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
			if objective is Dictionary and _collect_objective_needs_npc_grant(
					quest, objective as Dictionary, npc_id,
				):
				return true
		var giver: Dictionary = quest.get("giver", {}) as Dictionary
		if str(giver.get("npc_id", "")) == npc_id:
			return true
	return false


func has_unresolved_npc_objectives(npc_id: String) -> bool:
	## True while any not-yet-completed quest still needs this NPC as a stationary
	## giver/target. PartyManager uses this to delay companion joins until talking
	## to that NPC can no longer be required by the quest journal.
	if npc_id.is_empty():
		return false
	for quest in quests:
		var state: Dictionary = _state_of(quest)
		var quest_state := str(state.get("state", "inactive"))
		if quest_state == "completed":
			continue
		if quest_state == "inactive" and _quest_giver_npc(quest) == npc_id:
			return true
		var objectives: Array = quest.get("objectives", []) as Array
		var start_index := 0
		if quest_state == "active":
			start_index = maxi(0, int(state.get("objective_index", 0)))
		for index in range(start_index, objectives.size()):
			var objective: Dictionary = objectives[index] as Dictionary if objectives[index] is Dictionary else {}
			if str(objective.get("target_npc_id", "")) == npc_id:
				return true
			if _collect_objective_needs_npc_grant(quest, objective, npc_id):
				return true
	return false


func _collect_objective_needs_npc_grant(
		quest: Dictionary,
		objective: Dictionary,
		npc_id: String,
	) -> bool:
	if npc_id.is_empty() or str(objective.get("kind")) != "collect":
		return false
	if not InventoryManager.has_method("has_npc_grant_for_item"):
		return false
	var quest_id := str(quest.get("id", ""))
	var quest_item: Dictionary = InventoryManager.quest_item_by_id(
		str(objective.get("item_id", objective.get("item_ref", ""))), quest_id
	)
	var item_id := str(quest_item.get("id", ""))
	if item_id.is_empty():
		item_id = str(objective.get("item_id", objective.get("item_ref", "")))
	if item_id.is_empty():
		return false
	if InventoryManager.count_of(item_id) >= int(objective.get("count", 1)):
		return false
	return InventoryManager.has_npc_grant_for_item(
		item_id, quest_id, npc_id, str(objective.get("zone_id", "")),
	)


func marker_for_npc(npc_id: String) -> String:
	for quest in quests:
		# A giver with a quest still to offer (here, in this zone) gets a "!" so the
		# player knows conversation will start something.
		if str(_state_of(quest).get("state")) == "inactive" \
				and _quest_giver_npc(quest) == npc_id \
				and _quest_giver_zone(quest) == current_zone_id:
			return "!"
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty():
			continue
		if str(objective.get("zone_id")) != current_zone_id:
			continue
		if str(objective.get("target_npc_id", "")) == npc_id and str(objective.get("kind")) in ["talk", "choice", "deliver"]:
			return "!"
		if _collect_objective_needs_npc_grant(quest, objective, npc_id):
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
	if is_new:
		if not AnnouncementCenter.enqueue("hint", {"hint": payload}):
			_toast_queue.append({"kind": "hint", "hint": payload})
		if hints_by_level.size() >= 3:
			objective_fully_hinted.emit(quest_id, objective_id)
	_refresh_tracker()
	_refresh_open_journal()


func is_objective_fully_hinted(quest_id: String, objective_id: String) -> bool:
	## True once the player has heard all 3 hint levels (L1 vague -> L3 exact) for
	## this objective — QuestCompassView's gate for showing a precise pointer.
	var key := "%s:%s" % [quest_id, objective_id]
	return (revealed_hints.get(key, {}) as Dictionary).size() >= 3


func mark_dialogue_node_visited(npc_id: String, node_id: String) -> void:
	if npc_id.is_empty() or node_id.is_empty():
		return
	visited_dialogue_nodes["%s:%s" % [npc_id, node_id]] = true


func is_dialogue_node_visited(npc_id: String, node_id: String) -> bool:
	return visited_dialogue_nodes.has("%s:%s" % [npc_id, node_id])


func tracked_quest_and_objective() -> Dictionary:
	## Public equivalent of _refresh_tracker()'s "which quest/objective is
	## currently shown on the HUD tracker" selection, for QuestCompassView.
	## Returns {} if no quest currently has an active objective.
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
	if display_quest.is_empty():
		return {}
	return {"quest": display_quest, "objective": _current_objective(display_quest)}


func is_tracked_objective_active(quest_id: String, objective_id: String) -> bool:
	## Like is_objective_active, but ALSO requires this to be the TRACKED quest —
	## not just any quest that happens to be active. Used to gate NPC hint options
	## so an NPC only offers hints for whatever the player is currently following;
	## a hint for a different active-but-untracked quest stays silent until the
	## player switches their tracked quest (journal) to it.
	var tracked := tracked_quest_and_objective()
	if tracked.is_empty():
		return false
	var quest: Dictionary = tracked.get("quest", {}) as Dictionary
	var objective: Dictionary = tracked.get("objective", {}) as Dictionary
	return str(quest.get("id", "")) == quest_id and str(objective.get("id", "")) == objective_id


func are_all_main_quests_completed() -> bool:
	## The chapter-completion signal ChapterFlow watches: every quest authored as
	## type=="main" (the story spine) has reached the "completed" state.
	## An empty quest list never counts as complete — it means the chapter's
	## quests have not loaded yet (e.g. mid-reset, right before
	## load_chapter_quests populates them), not that the chapter genuinely has
	## no main quests. Treating that as vacuously "complete" was firing the
	## chapter-complete celebration the instant a new game started.
	if quests.is_empty():
		return false
	var has_main_quest := false
	for quest in quests:
		if str(quest.get("type", "main")) != "main":
			continue
		has_main_quest = true
		if str(_state_of(quest).get("state", "")) != "completed":
			return false
	return has_main_quest


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
			# Completes only once the player has genuinely set foot in the target zone
			# (exact match against visited zones), never via a play-order shortcut.
			if visited_zones.has(str(objective.get("zone_id"))):
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


## The {quest, objective} payload for a quest whose CURRENT objective is an
## unresolved moral choice — {} otherwise. ChatBox uses this to decide whether a
## choice node hands off to the ceremony, and the ceremony itself feeds on it.
func dialogue_choice_payload(quest_id: String) -> Dictionary:
	for quest in quests:
		if str(quest.get("id")) != quest_id:
			continue
		var objective: Dictionary = _current_objective(quest)
		if objective.is_empty() or str(objective.get("kind")) != "choice":
			return {}
		var state: Dictionary = _state_of(quest)
		if (state.get("choices", {}) as Dictionary).has(str(objective.get("id"))):
			return {}
		return {"quest": quest, "objective": objective}
	return {}


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
		var kept_choices: Array = []
		for payload in _pending_choices:
			var queued_quest: Dictionary = (payload as Dictionary).get("quest", {}) as Dictionary
			var queued_objective: Dictionary = (payload as Dictionary).get("objective", {}) as Dictionary
			if str(queued_quest.get("id", "")) != quest_id or str(queued_objective.get("id", "")) != str(objective.get("id", "")):
				kept_choices.append(payload)
		_pending_choices = kept_choices
		choices[str(objective.get("id"))] = option_id
		var chips: Array = _apply_choice_outcome(outcome)
		_complete_current_objective(quest)
		last_choice_result = {
			"quest_id": quest_id,
			"objective_id": str(objective.get("id", "")),
			"option_id": option_id,
			"option_label": str(selected.get("label", "")),
			"consequence_text": str(selected.get("consequence_text", "")),
			"npc_reaction": str(selected.get("npc_reaction", "")),
			"npc_id": str(objective.get("target_npc_id", "")),
			"chips": chips,
		}
		choice_resolved.emit(last_choice_result)
		quests_changed.emit()
		_refresh_tracker()
		print("[Quest] %s choice resolved in dialogue -> %s" % [quest_id, option_id])
		return true
	return false


## Apply every mechanical consequence of a choice outcome and return the display
## "chips" the ceremony UI shows: [{icon, text, tone: "gain"|"loss"|"neutral"}].
## Flags/relationships/actor-states were already recorded by
## NarrativeState.record_choice — here they only produce their chips.
func _apply_choice_outcome(outcome: Dictionary) -> Array:
	var chips: Array = []

	for grant in outcome.get("give_items", []) as Array:
		if not (grant is Dictionary):
			continue
		var item_id := str((grant as Dictionary).get("item_id", ""))
		# add_item silently refuses ids missing from the catalog — only show the
		# chip for a grant that can actually land.
		if item_id.is_empty() or InventoryManager.item_def(item_id).is_empty():
			continue
		var count := maxi(1, int((grant as Dictionary).get("count", 1)))
		InventoryManager.add_item(item_id, count)
		chips.append({
			"icon": "item", "tone": "gain",
			"text": "Nhận: %s" % _item_display_name(item_id, str((grant as Dictionary).get("name", ""))),
		})

	for taken in outcome.get("take_items", []) as Array:
		if not (taken is Dictionary):
			continue
		var item_id := str((taken as Dictionary).get("item_id", ""))
		if item_id.is_empty():
			continue
		var count := maxi(1, int((taken as Dictionary).get("count", 1)))
		if InventoryManager.remove_item(item_id, count):
			chips.append({
				"icon": "item", "tone": "loss",
				"text": "Mất: %s" % _item_display_name(item_id, str((taken as Dictionary).get("name", ""))),
			})

	var xp := int(outcome.get("xp", 0))
	if xp > 0:
		GameManager.grant_party_xp(xp)
		chips.append({"icon": "xp", "tone": "gain", "text": "+%d KN" % xp})
	elif xp < 0:
		var lost: int = GameManager.lose_xp(-xp)
		if lost > 0:
			chips.append({"icon": "xp", "tone": "loss", "text": "-%d KN" % lost})

	var hp_pct := float(outcome.get("hp_percent", 0))
	if hp_pct != 0.0:
		var applied: int = GameManager.apply_hp_percent(hp_pct)
		if applied != 0:
			chips.append({
				"icon": "hp_gain" if applied > 0 else "hp_loss",
				"tone": "gain" if applied > 0 else "loss",
				"text": "%+d Máu" % applied,
			})

	for change in outcome.get("relationships", []) as Array:
		if not (change is Dictionary):
			continue
		var npc_id := str((change as Dictionary).get("npc_id", ""))
		var delta := int((change as Dictionary).get("delta", 0))
		if npc_id.is_empty() or delta == 0:
			continue
		chips.append({
			"icon": "bond_gain" if delta > 0 else "bond_break",
			"tone": "gain" if delta > 0 else "loss",
			"text": "%s %+d" % [_npc_display_name(npc_id, str((change as Dictionary).get("name", ""))), delta],
		})

	for entry in outcome.get("party", []) as Array:
		if not (entry is Dictionary):
			continue
		var npc_id := str((entry as Dictionary).get("npc_id", ""))
		var action := str((entry as Dictionary).get("action", ""))
		if PartyManager.force_party_change(npc_id, action):
			var display := _npc_display_name(npc_id, str((entry as Dictionary).get("name", "")))
			chips.append({
				"icon": "party_leave", "tone": "loss" if action == "leave" else "gain",
				"text": ("%s rời đội" % display) if action == "leave" else ("%s gia nhập" % display),
			})

	var scaling: Dictionary = outcome.get("enemy_level_delta", {}) as Dictionary \
		if outcome.get("enemy_level_delta") is Dictionary else {}
	var scale_delta := int(scaling.get("delta", 0))
	if scale_delta != 0:
		var zone := str(scaling.get("zone_id", ""))
		if str(scaling.get("scope", "zone")) == "zone" and zone.is_empty():
			zone = current_zone_id
		elif str(scaling.get("scope", "zone")) == "chapter":
			zone = ""
		NarrativeState.add_enemy_level_mod(_current_chapter_number(), zone, scale_delta)
		chips.append({
			"icon": "enemy_up",
			"tone": "loss" if scale_delta > 0 else "gain",
			"text": "Kẻ địch mạnh hơn" if scale_delta > 0 else "Kẻ địch yếu đi",
		})

	for entry in outcome.get("actor_states", []) as Array:
		if not (entry is Dictionary):
			continue
		var actor_id := str((entry as Dictionary).get("actor_id", (entry as Dictionary).get("npc_id", "")))
		if actor_id.is_empty():
			continue
		var state := str((entry as Dictionary).get("state", "")).strip_edges().to_lower()
		if state in ["dead", "died", "killed"]:
			chips.append({"icon": "death", "tone": "loss", "text": "%s đã chết" % _npc_display_name(actor_id, "")})
		elif state in ["hidden", "removed", "despawned", "gone"]:
			chips.append({"icon": "party_leave", "tone": "neutral", "text": "%s đã rời đi" % _npc_display_name(actor_id, "")})

	return chips


func _item_display_name(item_id: String, authored_name: String = "") -> String:
	if not authored_name.is_empty():
		return authored_name
	var definition: Dictionary = InventoryManager.item_def(item_id)
	var display := str(definition.get("name", "")).strip_edges()
	return display if not display.is_empty() else _prettify_id(item_id)


func _npc_display_name(npc_id: String, authored_name: String = "") -> String:
	if not authored_name.is_empty():
		return authored_name
	var from_party := PartyManager.companion_name(npc_id)
	if from_party != npc_id:
		return from_party
	return _prettify_id(npc_id)


func _prettify_id(raw_id: String) -> String:
	var cleaned := raw_id
	for prefix in ["world_npc_", "world_item_", "world_enemy_", "npc_", "item_", "enemy_"]:
		if cleaned.begins_with(prefix):
			cleaned = cleaned.substr(prefix.length())
			break
	return cleaned.replace("_", " ").capitalize()


func _current_chapter_number() -> int:
	var flow := get_node_or_null("/root/ChapterFlow")
	if flow != null and flow.has_method("current_chapter"):
		return int((flow.call("current_chapter") as Dictionary).get("chapter", 0))
	return 0


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
	GameManager.grant_party_xp(xp)
	var reward_item: Dictionary = InventoryManager.reward_item_for(str(quest.get("id")))
	if not reward_item.is_empty():
		InventoryManager.add_item(str(reward_item.get("id")))
	InventoryManager.grant_linked_items(
		"quest_reward", "", current_zone_id, str(quest.get("id", "")),
	)
	_push_toast("quest_complete", quest)
	print("[Quest] completed %s (+%d XP)" % [quest.get("id"), xp])


# ── UI construction ───────────────────────────────────────────────────────────


func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 45
	_ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(_ui)

	# The journal is authored in 480x270 design units but renders into native
	# 960x540 geometry, so it needs an unscaled layer like the inventory screen.
	_journal_layer = CanvasLayer.new()
	_journal_layer.layer = 46
	_journal_layer.transform = Transform2D.IDENTITY
	add_child(_journal_layer)

	# Quest tracker HUD — authored crisp in native 960x540 in its own unscaled layer.
	_tracker_layer = CanvasLayer.new()
	_tracker_layer.layer = 44
	_tracker_layer.transform = Transform2D.IDENTITY
	add_child(_tracker_layer)
	_tracker_view = QuestTrackerViewScript.new()
	_tracker_view.visible = false
	_tracker_layer.add_child(_tracker_view)

	# Toast host (top-center; the layer runs at scale 2 → design width = vp/2)
	_toast_host = Control.new()
	_toast_host.position = Vector2(get_viewport().get_visible_rect().size.x / 4.0, 0)
	_ui.add_child(_toast_host)

	_build_journal()


func _build_journal() -> void:
	_journal_view = QuestJournalViewScript.new()
	_journal_root = _journal_view
	_journal_root.visible = false
	_journal_view.close_requested.connect(_toggle_journal)
	_journal_view.track_requested.connect(_on_journal_track_requested)
	_journal_layer.add_child(_journal_root)
	# Keep an open journal in sync with live quest and inventory state in real time.
	if not quests_changed.is_connected(_refresh_open_journal):
		quests_changed.connect(_refresh_open_journal)
	if not InventoryManager.inventory_changed.is_connected(_refresh_open_journal):
		InventoryManager.inventory_changed.connect(_refresh_open_journal)


# ── UI behavior ───────────────────────────────────────────────────────────────


func _process(_delta: float) -> void:
	if _ui == null:
		return
	if not _toast_queue.is_empty() and not _toast_busy:
		_show_next_toast()
	var has_active: bool = quests.any(func(q): return str(_state_of(q).get("state")) == "active")
	var hud_visible := has_active and not GameManager.ui_blocking_input and not _journal_open \
		and not _choice_open and not _toast_busy
	if _tracker_view != null:
		_tracker_view.visible = hud_visible
		# Dock right under the player card, which grows with the party.
		_tracker_view.position = Vector2(12.0, PartyHudViewScript.bottom_y + 12.0)

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
	if display_quest.is_empty():
		return
	var objective: Dictionary = _current_objective(display_quest)
	var state: Dictionary = _state_of(display_quest)
	var has_count := objective.has("count")
	var current := maxi(0, int(state.get("progress", 0))) if has_count else 0
	var total := maxi(1, int(objective.get("count", 1))) if has_count else 1
	var key := "%s:%s" % [str(display_quest.get("id", "")), str(objective.get("id", ""))]
	var hints_by_level: Dictionary = revealed_hints.get(key, {}) as Dictionary
	var levels: Array[int] = []
	for level_key in hints_by_level:
		levels.append(int(level_key))
	levels.sort()
	var hints: Array = []
	for level in levels:
		var payload: Dictionary = hints_by_level.get(str(level), {}) as Dictionary
		hints.append({"level": level, "text": str(payload.get("text", ""))})
	_tracker_view.set_data({
		"title": str(display_quest.get("title", "")),
		"type": str(display_quest.get("type", "main")),
		"objective": str(objective.get("description", "")),
		"current": current, "total": total, "has_count": has_count,
		"hints": hints,
	})


func _push_toast(kind: String, quest: Dictionary) -> void:
	var payload := {"kind": kind, "quest": quest.duplicate(true)}
	if kind == "objective":
		payload["objective"] = _current_objective(quest).duplicate(true)
		payload["progress"] = int(_state_of(quest).get("progress", 0))
	# During a conversation the event becomes a full-screen ceremony instead of
	# a corner toast (AnnouncementCenter refuses outside conversations).
	if AnnouncementCenter.enqueue(kind, payload):
		return
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


func _refresh_open_journal() -> void:
	if _journal_open:
		_refresh_journal()


func _on_journal_track_requested(quest_id: String) -> void:
	tracked_quest_id = quest_id
	_refresh_tracker()
	_refresh_journal()


# ── choice ceremony ───────────────────────────────────────────────────────────


## Fallback trigger: the player talked to the choice's target NPC but the
## conversation tree never routed into the choice node — the ceremony still
## plays, just without a conversation to hand off from.
func _open_choice(payload: Dictionary) -> void:
	_choice_open = true
	var view := MoralChoiceViewScript.new()
	get_tree().root.add_child(view)
	view.present(payload)
	view.closed.connect(func() -> void: _choice_open = false)


# ── input ─────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_J:
			_toggle_journal()
			get_viewport().set_input_as_handled()
			return

	if _choice_open:
		return  # the MoralChoiceView ceremony owns input while it is open

	if _journal_open:
		if _journal_view != null and _journal_view.handle_input(event):
			get_viewport().set_input_as_handled()
		return
