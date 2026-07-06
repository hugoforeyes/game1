extends Node
## Persistent, declarative story consequences for one game run. Quest state resets
## per chapter; choices, flags, and relationships intentionally do not.

signal narrative_changed

var choices: Dictionary = {}       # choice_key -> {quest_id, objective_id, option}
var flags: Dictionary = {}         # flag -> true
var relationships: Dictionary = {} # npc_id -> int
var actor_states: Dictionary = {}  # actor_id -> {state, presentation, ...}


func reset() -> void:
	choices.clear()
	flags.clear()
	relationships.clear()
	actor_states.clear()
	narrative_changed.emit()


# ── persistence (SaveManager) ──────────────────────────────────────────────────


func serialize_save() -> Dictionary:
	return {
			"choices": choices.duplicate(true),
			"flags": flags.duplicate(true),
			"relationships": relationships.duplicate(true),
			"actor_states": actor_states.duplicate(true),
		}


func apply_save(data: Dictionary) -> void:
	choices = (data.get("choices", {}) as Dictionary).duplicate(true)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	relationships = (data.get("relationships", {}) as Dictionary).duplicate(true)
	actor_states = (data.get("actor_states", {}) as Dictionary).duplicate(true)
	narrative_changed.emit()


func record_choice(
		choice_key: String,
		quest_id: String,
		objective_id: String,
		option: String,
		outcome: Dictionary = {},
) -> bool:
	if choice_key.is_empty() or option.is_empty() or choices.has(choice_key):
		return false
	choices[choice_key] = {
		"quest_id": quest_id,
		"objective_id": objective_id,
		"option": option,
	}
	for set_flag in outcome.get("set_flags", []) as Array:
		var key := str(set_flag).strip_edges()
		if not key.is_empty():
			flags[key] = true
	for clear_flag in outcome.get("clear_flags", []) as Array:
		flags.erase(str(clear_flag).strip_edges())
	for change in outcome.get("relationships", []) as Array:
		if not (change is Dictionary):
			continue
		var npc_id := str((change as Dictionary).get("npc_id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		relationships[npc_id] = int(relationships.get(npc_id, 0)) + int((change as Dictionary).get("delta", 0))
	apply_actor_state_changes(outcome, false)
	narrative_changed.emit()
	return true


func choice_matches(condition: Dictionary) -> bool:
	var choice_key := str(condition.get("choice_key", ""))
	var wanted := str(condition.get("option", ""))
	if choice_key.is_empty() or wanted.is_empty():
		return false
	var recorded: Dictionary = choices.get(choice_key, {}) as Dictionary
	return str(recorded.get("option", "")) == wanted


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func relationship_with(npc_id: String) -> int:
	return int(relationships.get(npc_id, 0))


func actor_state(actor_id: String) -> Dictionary:
	var key := actor_id.strip_edges()
	if key.is_empty():
		return {}
	var stored: Variant = actor_states.get(key, {})
	if stored is Dictionary:
		return (stored as Dictionary).duplicate(true)
	return {}


func actor_state_name(actor_id: String) -> String:
	return str(actor_state(actor_id).get("state", ""))


func actor_presentation(actor_id: String) -> String:
	var state_data := actor_state(actor_id)
	var presentation := str(state_data.get("presentation", "")).strip_edges()
	if not presentation.is_empty():
		return presentation
	return _default_presentation_for_state(str(state_data.get("state", "")))


func should_hide_actor(actor_id: String) -> bool:
	var state_name := _normalized_token(actor_state_name(actor_id))
	var presentation := _normalized_token(actor_presentation(actor_id))
	return presentation in ["hidden", "despawn", "removed", "none"] \
		or state_name in ["hidden", "despawned", "removed"]


func apply_actor_state_changes(outcome: Dictionary, emit_change: bool = true) -> bool:
	var changed := false
	for key in ["actor_states", "set_actor_states"]:
		var entries: Variant = outcome.get(key, [])
		if not (entries is Array):
			continue
		for entry in entries as Array:
			if entry is Dictionary:
				changed = _store_actor_state(_normalize_actor_state(entry as Dictionary)) or changed
	var single_entry: Variant = outcome.get("actor_state")
	if single_entry is Dictionary:
		changed = _store_actor_state(_normalize_actor_state(single_entry as Dictionary)) or changed

	changed = _store_actor_list(outcome.get("despawn_actors"), "hidden", "despawn") or changed
	changed = _store_actor_list(outcome.get("hide_actors"), "hidden", "hidden") or changed
	changed = _store_actor_list(outcome.get("remove_actors"), "removed", "despawn") or changed
	changed = _store_actor_list(outcome.get("despawn_npcs"), "hidden", "despawn") or changed
	changed = _store_actor_list(outcome.get("remove_npcs"), "removed", "despawn") or changed
	changed = _store_actor_list(outcome.get("dead_actors"), "dead", "corpse") or changed
	changed = _store_actor_list(outcome.get("dead_npcs"), "dead", "corpse") or changed
	if changed and emit_change:
		narrative_changed.emit()
	return changed


func condition_met(condition: Dictionary) -> bool:
	match str(condition.get("type", "")):
		"quest_choice":
			return choice_matches(condition)
		"flag":
			return has_flag(str(condition.get("flag", ""))) == bool(condition.get("value", true))
		"relationship":
			var value := relationship_with(str(condition.get("npc_id", "")))
			return value >= int(condition.get("min", -2147483648)) \
				and value <= int(condition.get("max", 2147483647))
		"actor_state":
			return _actor_state_condition_met(condition)
	return false


func _store_actor_list(values: Variant, state_name: String, presentation: String) -> bool:
	if not (values is Array):
		return false
	var changed := false
	for value in values as Array:
		changed = _store_actor_state(_normalize_actor_state({
			"actor_id": str(value),
			"state": state_name,
			"presentation": presentation,
		})) or changed
	return changed


func _store_actor_state(state_data: Dictionary) -> bool:
	var actor_id := str(state_data.get("actor_id", "")).strip_edges()
	if actor_id.is_empty():
		return false
	var state_name := _normalized_token(str(state_data.get("state", "")))
	var should_clear := bool(state_data.get("clear", false)) \
		or state_name in ["alive", "present", "active", "normal"]
	if should_clear:
		if actor_states.has(actor_id):
			actor_states.erase(actor_id)
			return true
		return false
	var previous: Variant = actor_states.get(actor_id)
	if previous is Dictionary and (previous as Dictionary) == state_data:
		return false
	actor_states[actor_id] = state_data.duplicate(true)
	return true


func _normalize_actor_state(raw: Dictionary) -> Dictionary:
	var actor_id := _actor_id_from(raw)
	if actor_id.is_empty():
		return {}
	var state_name := _normalize_state_name(raw.get("state", raw.get("status", raw.get("lifecycle", ""))))
	var presentation := _normalize_presentation(raw.get("presentation", raw.get("render_as", raw.get("visibility", ""))))
	if state_name.is_empty():
		if presentation == "corpse":
			state_name = "dead"
		elif presentation in ["hidden", "despawn"]:
			state_name = "hidden"
		else:
			state_name = "normal"
	if presentation.is_empty():
		presentation = _default_presentation_for_state(state_name)
	var normalized := {
		"actor_id": actor_id,
		"state": state_name,
		"presentation": presentation,
	}
	if bool(raw.get("clear", false)):
		normalized["clear"] = true
	for key in ["reason", "label"]:
		var value := str(raw.get(key, "")).strip_edges()
		if not value.is_empty():
			normalized[key] = value
	return normalized


func _actor_id_from(raw: Dictionary) -> String:
	for key in ["actor_id", "actor_ref", "npc_id", "npc_ref", "entity_id", "entity_ref", "id", "ref"]:
		var value := str(raw.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


func _normalize_state_name(value: Variant) -> String:
	var token := _normalized_token(str(value))
	match token:
		"alive", "active", "ok":
			return "present"
		"died", "killed", "corpse":
			return "dead"
		"hide":
			return "hidden"
		"gone", "remove":
			return "removed"
		"despawn":
			return "despawned"
		"disabled":
			return "inactive"
		"rescued":
			return "saved"
	return token


func _normalize_presentation(value: Variant) -> String:
	var token := _normalized_token(str(value))
	match token:
		"show", "visible", "alive":
			return "normal"
		"body", "dead":
			return "corpse"
		"hide":
			return "hidden"
		"gone", "none", "remove", "removed", "vanish", "vanished", "despawned":
			return "despawn"
		"disabled":
			return "inactive"
	return token


func _default_presentation_for_state(state_name: String) -> String:
	match _normalized_token(state_name):
		"dead":
			return "corpse"
		"hidden", "removed", "despawned":
			return "despawn"
		"inactive", "disabled":
			return "inactive"
	return "normal"


func _normalized_token(value: String) -> String:
	return value.strip_edges().to_lower().replace(" ", "_").replace("-", "_")


func _actor_state_condition_met(condition: Dictionary) -> bool:
	var actor_id := str(
		condition.get("actor_id", condition.get("npc_id", condition.get("entity_id", "")))
	).strip_edges()
	if actor_id.is_empty():
		return false
	var state_data := actor_state(actor_id)
	var wanted_state := _normalize_state_name(condition.get("state", ""))
	if not wanted_state.is_empty() and str(state_data.get("state", "")) != wanted_state:
		return false
	var wanted_presentation := _normalize_presentation(condition.get("presentation", ""))
	if not wanted_presentation.is_empty() and actor_presentation(actor_id) != wanted_presentation:
		return false
	if condition.has("hidden"):
		return should_hide_actor(actor_id) == bool(condition.get("hidden"))
	return not state_data.is_empty()
