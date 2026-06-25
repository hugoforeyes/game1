extends Node
## Runtime QA for objective-line and revealed-hint hierarchy behavior.


func _ready() -> void:
	QuestManager.set_process(false)
	QuestManager.reset()
	QuestManager.load_chapter_quests([
		{
			"id": "quest_tree_test",
			"title": "Cánh Hoa Cuối Mùa",
			"type": "main",
			"giver": {"mode": "npc", "zone_id": "zone_01", "npc_id": "arlo"},
			"objectives": [
				{
					"id": "o1", "kind": "collect", "zone_id": "zone_01",
					"description": "Thu thập 3 Cánh Hoa Xám", "count": 3,
				},
				{
					"id": "o2", "kind": "talk", "zone_id": "zone_01",
					"description": "Nói chuyện với Arlo", "target_npc_id": "arlo",
				},
			],
			"reward": {"xp": 80},
		},
	])
	QuestManager.notify_zone_entered("zone_01")
	QuestManager._toast_queue.clear()
	QuestManager._refresh_tracker()
	var view = QuestManager._tracker_view
	assert(view != null)
	assert(not view.is_compact)
	assert(view._data.get("title", "") == "Cánh Hoa Cuối Mùa")
	assert(view.line_count >= 1)

	# Hints for a not-yet-active objective are ignored.
	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o2", "level": 1}, "Future hint")
	assert(QuestManager.revealed_hints.is_empty())
	# Reveal + dedup-by-level for the active objective.
	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 2}, "Gợi ý cấp hai")
	QuestManager.reveal_hint("Nara", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 1}, "Gợi ý cấp một")
	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 2}, "Gợi ý cấp hai cập nhật")
	QuestManager._toast_queue.clear()
	QuestManager._refresh_tracker()
	assert(view.hint_row_count == 2)
	assert(QuestManager._hint_available)
	assert(view._panel_height > 150.0)

	# Completing the objective advances to one without hints.
	QuestManager._complete_current_objective(QuestManager.quests[0] as Dictionary)
	QuestManager._toast_queue.clear()
	QuestManager._refresh_tracker()
	assert(view.hint_row_count == 0)
	assert(not QuestManager._hint_available)
	assert(view._data.get("objective", "") == "Nói chuyện với Arlo")

	# Compact toggle.
	QuestManager._toggle_tracker_compact()
	assert(view.is_compact)
	assert(view.size == Vector2(64, 64))
	QuestManager._toggle_tracker_compact()
	assert(not view.is_compact)
	print("[ObjectiveHintTreeTest] objective hierarchy states passed")
	get_tree().quit()
