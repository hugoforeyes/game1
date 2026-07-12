extends Node
## Regression coverage for trigger AND connects.from cutscene matching.


func _cutscene(id: String, from_ref: String = "", include_connects: bool = true) -> Dictionary:
	var result := {
		"id": id,
		"trigger": {"type": "zone_enter"},
		"actions": [{"type": "wait", "seconds": 0.01}],
	}
	if include_connects:
		result["connects"] = {"from": from_ref, "to": "quest_01:o7"}
	return result


func _set_cutscenes(cutscenes: Array) -> void:
	CutsceneDirector.reset()
	CutsceneDirector.set_zone_cutscenes("zone_03", cutscenes)


func _ready() -> void:
	QuestManager.reset()
	var objectives: Array = []
	for index in range(7):
		objectives.append({"id": "o%d" % (index + 1)})
	QuestManager.quests = [{
		"id": "quest_01",
		"type": "main",
		"objectives": objectives,
	}]
	QuestManager.quest_states = {
		"quest_01": {"state": "inactive", "objective_index": 0, "progress": 0, "choices": {}},
	}

	_set_cutscenes([_cutscene("guarded", "quest_01:o6")])
	assert(CutsceneDirector.match_event("zone_enter").is_empty(),
		"entering zone_03 before starting the quest must not play the cutscene")

	QuestManager.quest_states["quest_01"] = {
		"state": "active", "objective_index": 5, "progress": 0, "choices": {},
	}
	assert(CutsceneDirector.match_event("zone_enter").is_empty(),
		"o6 must be completed, not merely active")

	QuestManager.quest_states["quest_01"] = {
		"state": "active", "objective_index": 6, "progress": 0, "choices": {},
	}
	assert(str(CutsceneDirector.match_event("zone_enter").get("id", "")) == "guarded",
		"the cutscene must play after o6 is completed")

	_set_cutscenes([_cutscene("invalid", "quest_01:o99")])
	assert(CutsceneDirector.match_event("zone_enter").is_empty(),
		"an invalid explicit story reference must fail closed")

	var false_opening := _cutscene("false_opening", "chapter_start")
	false_opening["role"] = "emotional"
	_set_cutscenes([false_opening])
	assert(CutsceneDirector.match_event("zone_enter").is_empty(),
		"chapter_start must not unlock a non-opening cutscene")
	false_opening["role"] = "opening"
	_set_cutscenes([false_opening])
	assert(str(CutsceneDirector.match_event("zone_enter").get("id", "")) == "false_opening",
		"chapter_start remains valid for the real opening cutscene")

	_set_cutscenes([_cutscene("legacy", "", false)])
	assert(str(CutsceneDirector.match_event("zone_enter").get("id", "")) == "legacy",
		"packages created before connects existed must retain trigger-only behavior")

	QuestManager.quest_states["quest_01"] = {
		"state": "completed", "objective_index": 7, "progress": 0, "choices": {},
	}
	assert(QuestManager.has_reached_story_ref("chapter_start"))
	assert(QuestManager.has_reached_story_ref("quest_01:complete"))
	assert(not QuestManager.has_reached_story_ref("ghost:o1"))

	# npc_talked must publish only after the talk objective is complete so a
	# connects.from gate can match during the same synchronous signal dispatch.
	QuestManager.current_zone_id = "zone_03"
	QuestManager.quests = [{
		"id": "quest_01",
		"type": "main",
		"objectives": [
			{"id": "o1", "kind": "talk", "zone_id": "zone_03", "target_npc_id": "mira"},
			{"id": "o2", "kind": "reach", "zone_id": "zone_04"},
		],
	}]
	QuestManager.quest_states = {
		"quest_01": {"state": "active", "objective_index": 0, "progress": 0, "choices": {}},
	}
	var observed := {"npc_id": "", "completed": -1}
	QuestManager.npc_talked.connect(func(npc_id: String) -> void:
		observed["npc_id"] = npc_id
		observed["completed"] = QuestManager.completed_objective_count("quest_01")
	, CONNECT_ONE_SHOT)
	QuestManager.notify_npc_talked("mira")
	assert(str(observed["npc_id"]) == "mira")
	assert(int(observed["completed"]) == 1,
		"npc_talked observers must see the objective completed")

	QuestManager.reset()
	CutsceneDirector.reset()
	print("[CutsceneConnectsGateTest] trigger + story prerequisite ordering passed")
	get_tree().quit()
