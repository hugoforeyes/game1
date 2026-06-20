extends Node
## Persistent, declarative story consequences for one game run. Quest state resets
## per chapter; choices, flags, and relationships intentionally do not.

signal narrative_changed

var choices: Dictionary = {}       # choice_key -> {quest_id, objective_id, option}
var flags: Dictionary = {}         # flag -> true
var relationships: Dictionary = {} # npc_id -> int


func reset() -> void:
	choices.clear()
	flags.clear()
	relationships.clear()
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
	for flag in outcome.get("set_flags", []) as Array:
		var key := str(flag).strip_edges()
		if not key.is_empty():
			flags[key] = true
	for flag in outcome.get("clear_flags", []) as Array:
		flags.erase(str(flag).strip_edges())
	for change in outcome.get("relationships", []) as Array:
		if not (change is Dictionary):
			continue
		var npc_id := str((change as Dictionary).get("npc_id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		relationships[npc_id] = int(relationships.get(npc_id, 0)) + int((change as Dictionary).get("delta", 0))
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
	return false
