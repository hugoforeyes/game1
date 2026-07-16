extends Node2D
## Headless regression smoke for ORDER-INDEPENDENT `defeat` objectives.
##
## Reproduces the Chapter 2 · Lối Mòn Rừng Tro soft-lock: the "rescue Ansel"
## quest asks you to defeat `enemy_ashwood_stalker` (objective o4), but if the
## player kills that beast BEFORE the objective becomes active, the kill is
## recorded permanently in GameManager.defeated_enemy_ids (defeated enemies never
## respawn) yet QuestManager.notify_enemy_defeated ignores it because o4 is not the
## current objective — leaving o4 impossible to complete.
##
## The fix (_settle_defeat_objectives, mirroring _settle_collect_objectives) makes a
## target-id defeat settle against already-defeated/spared enemies whenever an
## objective advances or a zone is entered. This test drives QuestManager directly
## with a synthetic chapter-2-shaped quest — no SceneBuilder server required.
##
## Exit code 0 = all pass, 1 = a failure.

var _failures: int = 0


func _ready() -> void:
	_test_kill_before_active_does_not_softlock()
	_test_normal_live_kill_still_works()
	_test_spared_enemy_also_settles()
	_test_uninvolved_enemy_does_not_settle()
	_finish()


func _make_quest() -> Dictionary:
	# Mirrors ch2 quest_01: talk giver (Mira) -> defeat beasts -> talk Ansel.
	return {
		"id": "quest_test_defeat_order",
		"title": "Cứu Ansel Brigg",
		"type": "main",
		"giver": {"mode": "npc", "zone_id": "zone_01", "npc_id": "npc_giver"},
		"objectives": [
			{"id": "o1", "kind": "talk", "zone_id": "zone_01", "target_npc_id": "npc_giver"},
			{"id": "o2", "kind": "defeat", "zone_id": "zone_01", "target_enemy_id": "enemy_beast"},
			{"id": "o3", "kind": "talk", "zone_id": "zone_01", "target_npc_id": "npc_ansel"},
		],
		"reward": {"xp": 50},
	}


func _reset() -> Dictionary:
	GameManager.reset_combat_progress()
	var quest := _make_quest()
	QuestManager.load_chapter_quests([quest])
	return QuestManager.quests[0] as Dictionary


func _test_kill_before_active_does_not_softlock() -> void:
	print("\n--- TEST 1: killing the beast BEFORE the defeat step is active must not soft-lock ---")
	var quest := _reset()
	QuestManager.notify_zone_entered("zone_01")
	_check(_state(quest) == "inactive", "quest with a giver stays inactive on zone entry")

	# Player wanders the trail and kills the beast long before meeting the giver.
	GameManager.mark_enemy_defeated("enemy_beast")
	QuestManager.notify_enemy_defeated("enemy_beast")
	_check(_obj_index(quest) == 0 and _state(quest) == "inactive",
		"the early kill lands while the quest is inactive (nothing to credit yet)")

	# Now the story starts: talk to the giver. o1 (talk giver) closes, advancing to
	# o2 (defeat) — which must auto-settle because the beast is already dead.
	QuestManager.notify_npc_talked("npc_giver")
	_check(_state(quest) == "active", "talking to the giver starts the quest")
	_check(_obj_index(quest) == 2,
		"quest advanced PAST the defeat step to o3 (idx=%d, expected 2)" % _obj_index(quest))
	_check(str(_current_objective(quest).get("kind")) == "talk"
		and str(_current_objective(quest).get("target_npc_id")) == "npc_ansel",
		"current objective is now 'talk to Ansel', so the quest is completable")


func _test_normal_live_kill_still_works() -> void:
	print("\n--- TEST 2: the normal flow (kill while the objective IS active) still works ---")
	var quest := _reset()
	QuestManager.notify_zone_entered("zone_01")
	QuestManager.notify_npc_talked("npc_giver")
	_check(_obj_index(quest) == 1 and str(_current_objective(quest).get("kind")) == "defeat",
		"with the beast still alive, the quest waits on the defeat step (idx=%d)" % _obj_index(quest))

	GameManager.mark_enemy_defeated("enemy_beast")
	QuestManager.notify_enemy_defeated("enemy_beast")
	_check(_obj_index(quest) == 2,
		"defeating the beast now completes the defeat step and advances to o3 (idx=%d)" % _obj_index(quest))


func _test_spared_enemy_also_settles() -> void:
	print("\n--- TEST 3: a beast SPARED before the step is active also settles the objective ---")
	var quest := _reset()
	QuestManager.notify_zone_entered("zone_01")
	GameManager.mark_enemy_spared("enemy_beast")
	QuestManager.notify_npc_talked("npc_giver")
	_check(_obj_index(quest) == 2,
		"a spared (not killed) beast still clears the defeat step (idx=%d)" % _obj_index(quest))


func _test_uninvolved_enemy_does_not_settle() -> void:
	print("\n--- TEST 4: an unrelated dead enemy must NOT wrongly clear the defeat step ---")
	var quest := _reset()
	QuestManager.notify_zone_entered("zone_01")
	GameManager.mark_enemy_defeated("enemy_someone_else")
	QuestManager.notify_npc_talked("npc_giver")
	_check(_obj_index(quest) == 1 and str(_current_objective(quest).get("kind")) == "defeat",
		"defeat step stays active while the ACTUAL target is still alive (idx=%d)" % _obj_index(quest))


# ── helpers ──────────────────────────────────────────────────────────────────────


func _state(quest: Dictionary) -> String:
	return str(QuestManager.quest_states.get(str(quest.get("id")), {}).get("state", "?"))


func _obj_index(quest: Dictionary) -> int:
	return int(QuestManager.quest_states.get(str(quest.get("id")), {}).get("objective_index", -1))


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
	print("\n[DefeatOrderSmoke] %s (%d failure(s))" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
