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
	assert(QuestManager._tracker_panel.position == Vector2(304, 6))
	assert(QuestManager._tracker_panel.size.x == 170.0)
	assert(QuestManager._tracker_panel.size.y >= 48.0)
	assert(QuestManager._tracker_collapse_icon.visible)
	var base_height := QuestManager._tracker_panel.size.y

	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o2", "level": 1}, "Future hint")
	assert(QuestManager.revealed_hints.is_empty())
	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 2}, "Gợi ý cấp hai")
	QuestManager.reveal_hint("Nara", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 1}, "Gợi ý cấp một")
	QuestManager.reveal_hint("Arlo", {"quest_id": "quest_tree_test", "objective_id": "o1", "level": 2}, "Gợi ý cấp hai cập nhật")
	QuestManager._toast_queue.clear()
	QuestManager._refresh_tracker()
	assert(QuestManager._tracker_hint_rows.size() == 2)
	assert(QuestManager._tracker_collapse_icon.visible)
	assert(QuestManager._tracker_panel.size.y > 48.0)

	QuestManager._hint_collapsed = true
	QuestManager._apply_hint_collapsed()
	assert(QuestManager._tracker_panel.size.y == base_height)
	assert(not QuestManager._tracker_hints_root.visible)
	QuestManager._hint_collapsed = false
	QuestManager._complete_current_objective(QuestManager.quests[0] as Dictionary)
	QuestManager._toast_queue.clear()
	QuestManager._refresh_tracker()
	assert(QuestManager._tracker_hint_rows.is_empty())
	assert(not QuestManager._hint_available)
	assert(QuestManager._tracker_panel.size.y >= 40.0)
	QuestManager._toggle_tracker_compact()
	assert(QuestManager._tracker_panel.position == Vector2(444, 6))
	assert(QuestManager._tracker_panel.size == Vector2(30, 30))
	assert(QuestManager._tracker_collapse_icon.texture_normal.get_size() == Vector2(30, 30))
	QuestManager._toggle_tracker_compact()
	assert(QuestManager._tracker_panel.position == Vector2(304, 6))
	assert(QuestManager._tracker_objective.visible)
	QuestManager._tracker_panel.size = Vector2(210, 140)
	QuestManager._tracker_panel._layout_parts()
	assert(QuestManager._tracker_panel._mid_badges[0].position.x == 94.0)
	assert(QuestManager._tracker_panel._mid_badges[1].position.x == 94.0)
	assert(QuestManager._tracker_panel._mid_badges[2].position.y == 59.0)
	assert(QuestManager._tracker_panel._mid_badges[3].position.y == 59.0)
	assert(QuestManager._tracker_panel._edges[0].texture.get_size() == Vector2(4, 3))
	assert(QuestManager._tracker_panel._edges[1].texture.get_size() == Vector2(4, 3))
	assert(QuestManager._tracker_panel._edges[2].texture.get_size() == Vector2(3, 4))
	assert(QuestManager._tracker_panel._edges[3].texture.get_size() == Vector2(3, 4))
	assert(QuestManager._tracker_quest_icon.texture.get_size() == QuestManager._tracker_quest_icon.size)
	assert(QuestManager._tracker_objective_icon.texture.get_size() == QuestManager._tracker_objective_icon.size)
	assert(QuestManager._tracker_progress_icon.texture.get_size() == QuestManager._tracker_progress_icon.size)
	assert(QuestManager._tracker_hint_icon.texture.get_size() == QuestManager._tracker_hint_icon.size)
	assert(QuestManager._tracker_collapse_icon.texture_normal.get_size() == QuestManager._tracker_collapse_icon.size)
	for badge in QuestManager._tracker_panel._mid_badges:
		assert(badge.position.x >= 0.0 and badge.position.y >= 0.0)
		assert(badge.position.x + badge.size.x <= QuestManager._tracker_panel.size.x)
		assert(badge.position.y + badge.size.y <= QuestManager._tracker_panel.size.y)
	print("[ObjectiveHintTreeTest] objective hierarchy states passed")
	get_tree().quit()
