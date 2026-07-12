extends Node
## Runtime director for the chapter's planned cutscenes.
##
## Each zone's scene_package carries a `cutscenes` array authored by the
## scene_cutscenes step: every entry has a `trigger` (zone_enter / zone_cleared /
## enemy_defeated / quest_objective / quest_complete / quest_choice /
## flag / relationship / item_obtained / npc_talked)
## plus an `actions` + absolute `start_tiles` script. This director
## keeps the current zone's list and a per-run "already played" set, and matches
## events the game reports against the unplayed cutscenes' triggers. Every modern
## plan also carries connects.from; it is an additional causal prerequisite
## resolved against QuestManager so visiting a later zone cannot skip quest order.
## Quest trigger gates reuse QuestManager.stage_unlocked (same contract as story dialogue).
##
## It only MATCHES — Main owns playback (so it can gate on battle/transitions and
## reuse the same CutscenePlayer for every planned beat).

var _played: Dictionary = {}        # cutscene_id -> true (one-shot for this run)
var _zone_cutscenes: Array = []     # current zone's packaged cutscenes
var _current_zone_id: String = ""


func reset() -> void:
	_played.clear()
	_zone_cutscenes = []
	_current_zone_id = ""


func set_zone_cutscenes(zone_id: String, cutscenes: Array) -> void:
	_current_zone_id = zone_id
	_zone_cutscenes = cutscenes if cutscenes is Array else []
	print("[CutsceneDirector] zone=%s cutscenes=%d" % [zone_id, _zone_cutscenes.size()])


func is_played(cutscene_id: String) -> bool:
	return _played.has(cutscene_id)


func mark_played(cutscene_id: String) -> void:
	if not cutscene_id.is_empty():
		_played[cutscene_id] = true


func has_pending_playback() -> bool:
	## Shared priority barrier for quest/reward UI. Main owns the planned-cutscene
	## queue, while CutscenePlayer owns the active/teardown phase.
	if get_tree().get_first_node_in_group("active_cutscene_player") != null:
		return true
	var owner := get_tree().get_first_node_in_group("narrative_playback_owner")
	if owner == null:
		owner = get_tree().current_scene
	return owner != null and owner.has_method("has_pending_narrative_playback") \
			and bool(owner.call("has_pending_narrative_playback"))


## First unplayed cutscene in the current zone whose trigger matches this event,
## or {} if none. `event_type` is one of: zone_enter, zone_cleared, quest_changed,
## enemy_defeated, item_obtained, npc_talked. `params` carries event specifics.
func match_event(event_type: String, params: Dictionary = {}) -> Dictionary:
	for cs in _zone_cutscenes:
		if not (cs is Dictionary):
			continue
		var id := str((cs as Dictionary).get("id", ""))
		if id.is_empty() or is_played(id):
			continue
		if ((cs as Dictionary).get("actions", []) as Array).is_empty():
			continue
		if not _trigger_matches((cs as Dictionary).get("trigger", {}) as Dictionary, event_type, params):
			continue
		if not _connects_from_reached(cs as Dictionary):
			continue
		return cs as Dictionary
	return {}


func _connects_from_reached(cutscene: Dictionary) -> bool:
	# Packages created before connects became a runtime gate have no edge (or an
	# empty one); preserve their trigger-only behavior. Once an edge is present,
	# malformed/missing `from` fails closed instead of replaying content out of order.
	if not cutscene.has("connects"):
		return true
	var raw_connects: Variant = cutscene.get("connects")
	if not (raw_connects is Dictionary):
		return false
	var connects := raw_connects as Dictionary
	if connects.is_empty():
		return true
	if not connects.has("from"):
		return false
	var from_ref := str(connects.get("from", "")).strip_edges()
	if from_ref.is_empty():
		return false
	if from_ref == "chapter_start" and str(cutscene.get("role", "")) != "opening":
		return false
	return QuestManager.has_reached_story_ref(from_ref)


func _trigger_matches(trigger: Dictionary, event_type: String, params: Dictionary) -> bool:
	var t := str(trigger.get("type", ""))
	match event_type:
		"zone_enter":
			# On entering a zone: fire zone_enter beats, and also any quest gate that
			# is ALREADY satisfied (so a beat tied to past progress still plays here).
			if t == "zone_enter":
				return true
			if t in ["quest_complete", "quest_objective", "quest_choice", "flag", "relationship"]:
				return QuestManager.stage_unlocked(trigger)
			return false
		"quest_changed":
			if t in ["quest_complete", "quest_objective", "quest_choice", "flag", "relationship"]:
				return QuestManager.stage_unlocked(trigger)
			return false
		"zone_cleared":
			return t == "zone_cleared"
		"enemy_defeated":
			return t == "enemy_defeated" and str(trigger.get("enemy_id", "")) == str(params.get("enemy_id", ""))
		"item_obtained":
			return t == "item_obtained" and _item_matches(trigger, str(params.get("item_id", "")))
		"npc_talked":
			return t == "npc_talked" and str(trigger.get("npc_id", "")) == str(params.get("npc_id", ""))
	return false


func _item_matches(trigger: Dictionary, obtained_item_id: String) -> bool:
	if obtained_item_id.is_empty():
		return false
	var quest_id := str(trigger.get("quest_id", ""))
	var item_ref := str(trigger.get("item_ref", "reward_item"))
	var item: Dictionary = (
		InventoryManager.reward_item_for(quest_id) if item_ref == "reward_item"
		else InventoryManager.quest_item_for(quest_id) if item_ref == "quest_item"
		else InventoryManager.item_def(item_ref)
	)
	return not item.is_empty() and str(item.get("id", "")) == obtained_item_id
