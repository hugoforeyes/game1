extends Node
## Runtime QA for sequential notification playback and HUD suppression.

var pending_narrative := false


func has_pending_narrative_playback() -> bool:
	return pending_narrative


func _ready() -> void:
	add_to_group("narrative_playback_owner")
	GameManager.ui_blocking_input = false
	QuestManager.set_process(false)
	InventoryManager.set_process(false)
	InventoryManager._toast_queue.clear()
	InventoryManager._toast_busy = false
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
	QuestManager.quest_states["quest_notification_test"] = {
		"state": "active", "objective_index": 0, "progress": 0, "choices": {},
	}
	QuestManager._toast_queue.clear()
	var quest: Dictionary = QuestManager.quests[0] as Dictionary
	QuestManager._push_toast("new_quest", quest)
	QuestManager._push_toast("objective", quest)
	var objective_item: Dictionary = QuestManager._toast_queue[1] as Dictionary
	var objective_snapshot: Dictionary = objective_item.get("objective", {}) as Dictionary
	assert(str(objective_snapshot.get("description", "")) == "Thu thập 3 Cánh Hoa Xám")

	# Item acquisition is presented before the objective update it produces.
	InventoryManager._push_item_toast({"id": "item_test", "name": "Cánh Hoa Xám"}, 1)
	QuestManager._process(0.0)
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 2)
	InventoryManager._toast_queue.clear()

	# World-object item reveals are modal. Their silent inventory grant may update
	# a quest synchronously, but the objective toast must wait until the reveal closes.
	GameManager.ui_blocking_input = true
	QuestManager._process(0.0)
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 2)
	GameManager.ui_blocking_input = false

	# A queued cutscene owns the stage before any quest notification starts.
	pending_narrative = true
	QuestManager._process(0.0)
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 2)
	assert(QuestManager._toast_host.get_child_count() == 0)

	pending_narrative = false
	QuestManager._process(0.0)
	assert(QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 1)
	assert(QuestManager._toast_host.get_child_count() == 1)
	assert(not QuestManager._tracker_view.visible)

	# An item arriving just after a quest toast starts immediately requeues that
	# quest toast; it will restart only after the item notification is finished.
	InventoryManager._push_item_toast({"id": "item_test", "name": "Cánh Hoa Xám"}, 1)
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 2)
	await get_tree().process_frame
	assert(QuestManager._toast_host.get_child_count() == 0)
	InventoryManager._process(0.0)
	assert(InventoryManager._toast_busy)
	assert(InventoryManager._toast_host.get_child_count() == 1)
	QuestManager._process(0.0)
	assert(not QuestManager._toast_busy)
	await get_tree().create_timer(1.8).timeout
	await get_tree().process_frame
	assert(not InventoryManager._toast_busy)
	assert(InventoryManager._toast_host.get_child_count() == 0)
	QuestManager._process(0.0)
	assert(QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 1)

	# If a cutscene arrives just after a toast starts, restart that toast after the
	# cutscene instead of letting it overlap or silently consuming it.
	pending_narrative = true
	QuestManager._process(0.0)
	assert(not QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 2)
	await get_tree().process_frame
	assert(QuestManager._toast_host.get_child_count() == 0)

	pending_narrative = false
	QuestManager._process(0.0)
	assert(QuestManager._toast_busy)
	assert(QuestManager._toast_queue.size() == 1)

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
	assert(QuestManager._tracker_view.visible)
	print("[NotificationQueueTest] sequential playback and HUD suppression passed")
	get_tree().quit()
