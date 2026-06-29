extends Node2D
## Dev-only headless smoke for quest STORY FLOW coherence (Vương Quốc Kẹo Sương):
##   - quests with an NPC giver do NOT start on zone entry — only on talking to the giver
##   - the giver shows a "!" before you talk to them
##   - a `reach` objective completes only when its target zone is genuinely visited
##     (entering the hidden bakery must NOT auto-complete "reach the flower field")
##   - talking to a giver whose first step is "talk to me" closes that step at once
## Exit code 0 = all pass, 1 = a failure. Needs the SceneBuilder server on :5001.

var _failures: int = 0


func _ready() -> void:
	var flow: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapter: Dictionary = (flow.get("chapters", []) as Array)[0] as Dictionary
	var icon: Texture2D = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	InventoryManager.load_chapter_catalog(chapter.get("items", {}) as Dictionary, icon)
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)

	# locate the flower-field reach quest (quest_01) and the clock quest (quest_03)
	var q_reach := _quest_with_first_kind("reach")
	var q_talk := _quest_with_first_kind("talk")
	_check(not q_reach.is_empty(), "found a quest whose first step is 'reach'")
	_check(not q_talk.is_empty(), "found a quest whose first step is 'talk'")

	_test_giver_gating(q_reach)
	_test_reach_not_shortcut(q_reach)
	_test_talk_start_quest(q_talk)
	_finish()


func _test_giver_gating(quest: Dictionary) -> void:
	print("\n--- TEST 1: quests start by talking to the giver, not by entering a zone ---")
	var giver_npc := str((quest.get("giver", {}) as Dictionary).get("npc_id", ""))
	var giver_zone := str((quest.get("giver", {}) as Dictionary).get("zone_id", ""))

	QuestManager.notify_zone_entered("zone_01")
	_check(_state(quest) == "inactive", "entering the entrance zone does NOT start the quest")

	QuestManager.notify_zone_entered(giver_zone)
	_check(_state(quest) == "inactive", "being in the giver's zone (without talking) does NOT start it")
	_check(QuestManager.marker_for_npc(giver_npc) == "!", "the giver shows a '!' to offer the quest")

	QuestManager.notify_npc_talked(giver_npc)
	_check(_state(quest) == "active", "talking to the giver STARTS the quest")
	_check(_first_objective_kind(quest) == "reach", "its first objective ('reach') is now the current one")


func _test_reach_not_shortcut(quest: Dictionary) -> void:
	print("\n--- TEST 2: the hidden bakery must NOT auto-complete 'reach the flower field' ---")
	# quest is active and on the reach objective from test 1
	var reach_zone := str(_current_objective(quest).get("zone_id", ""))
	var idx_before := _obj_index(quest)

	# the bakery (zone_02) is a hidden side zone that sorts LAST in play order — the old
	# index comparison falsely treated it as "past" the flower field
	QuestManager.notify_zone_entered("zone_02")
	_check(_obj_index(quest) == idx_before, "entering the bakery did NOT advance the quest")
	_check(_current_objective(quest).get("kind") == "reach", "still on the 'reach' objective")

	# actually arriving at the target zone completes it
	QuestManager.notify_zone_entered(reach_zone)
	_check(_obj_index(quest) > idx_before, "arriving at the real target zone completed the reach (idx %d→%d)" % [idx_before, _obj_index(quest)])


func _test_talk_start_quest(quest: Dictionary) -> void:
	print("\n--- TEST 3: a 'talk to me' first step closes the moment you meet the giver ---")
	var giver_npc := str((quest.get("giver", {}) as Dictionary).get("npc_id", ""))
	var giver_zone := str((quest.get("giver", {}) as Dictionary).get("zone_id", ""))
	QuestManager.notify_zone_entered(giver_zone)
	_check(_state(quest) == "inactive", "quest still not started before talking")
	QuestManager.notify_npc_talked(giver_npc)
	_check(_state(quest) == "active", "talking started the quest")
	# the first objective was "talk to the giver" — it should already be done, moving to step 2
	_check(_obj_index(quest) >= 1, "the redundant 'talk to giver' step auto-closed (now at step %d)" % (_obj_index(quest) + 1))


# ── helpers ──────────────────────────────────────────────────────────────────────


func _quest_with_first_kind(kind: String) -> Dictionary:
	for quest in QuestManager.quests:
		var objs: Array = (quest as Dictionary).get("objectives", []) as Array
		if not objs.is_empty() and str((objs[0] as Dictionary).get("kind")) == kind:
			return quest as Dictionary
	return {}


func _state(quest: Dictionary) -> String:
	return str(QuestManager.quest_states.get(str(quest.get("id")), {}).get("state", "?"))


func _obj_index(quest: Dictionary) -> int:
	return int(QuestManager.quest_states.get(str(quest.get("id")), {}).get("objective_index", -1))


func _first_objective_kind(quest: Dictionary) -> String:
	return str(_current_objective(quest).get("kind", ""))


func _current_objective(quest: Dictionary) -> Dictionary:
	var idx := _obj_index(quest)
	var objs: Array = quest.get("objectives", []) as Array
	if idx >= 0 and idx < objs.size():
		return objs[idx] as Dictionary
	return {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _finish() -> void:
	print("\n[QuestFlowSmoke] %s (%d failure(s))" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
