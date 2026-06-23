extends Node
## Runtime QA for sequential notification playback and HUD suppression.


func _ready() -> void:
	QuestManager.set_process(false)
	QuestManager.reset()
	QuestManager.load_chapter_quests([
		{
			"id": "quest_notification_test",
			"title": "Cánh Hoa Cuối Mùa",
			"type": "main",
			"giver": {"mode": "npc", "zone_id": "zone_01", "npc_id": "arlo"},
			"objectives": [
				{
					"id": "o1", "kind": "collect", "zone_id": "zone_01",
					"description": "Thu thập 3 Cánh Hoa Xám", "count": 3,
				},
			],
			"reward": {"xp": 80},
		},
	])
	QuestManager.notify_zone_entered("zone_01")
	QuestManager._toast_queue.clear()
	var quest: Dictionary = QuestManager.quests[0] as Dictionary
	QuestManager._push_toast("new_quest", quest)
	QuestManager._push_toast("objective", quest)
	var objective_item: Dictionary = QuestManager._toast_queue[1] as Dictionary
	var objective_snapshot: Dictionary = objective_item.get("objective", {}) as Dictionary
	assert(str(objective_snapshot.get("description", "")) == "Thu thập 3 Cánh Hoa Xám")

	QuestManager._process(0.0)
	assert(QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 1)
	assert(QuestManager._toast_host.get_child_count() == 1)
	assert(not QuestManager._tracker_panel.visible)

	await get_tree().create_timer(3.2).timeout
	await get_tree().process_frame
	assert(not QuestManager._toast_busy)
	QuestManager._process(0.0)
	assert(QuestManager._toast_busy)
	assert(QuestManager._toast_queue.is_empty())
	assert(QuestManager._toast_host.get_child_count() == 1)

	await get_tree().create_timer(3.2).timeout
	await get_tree().process_frame
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_host.get_child_count() == 0)
	QuestManager._process(0.0)
	assert(QuestManager._tracker_panel.visible)
	print("[NotificationQueueTest] sequential playback and HUD suppression passed")
	get_tree().quit()
