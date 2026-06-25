extends Node
## Integration QA for journal filtering, selection, tracking, and close behavior.


func _ready() -> void:
	QuestManager.set_process(false)
	QuestManager.reset()
	InventoryManager.reset()
	QuestManager.load_chapter_quests([
		{
			"id": "main", "title": "Main Quest", "type": "main",
			"giver": {"zone_id": "zone_01", "npc_id": "guide"},
			"objectives": [{"id": "m1", "kind": "collect", "zone_id": "zone_01", "description": "Collect signals", "count": 3}],
			"reward": {"xp": 100},
		},
		{
			"id": "side", "title": "Side Quest", "type": "side",
			"giver": {"zone_id": "zone_01", "npc_id": "witness"},
			"objectives": [{"id": "s1", "kind": "collect", "zone_id": "zone_01", "description": "Check traces", "count": 2}],
			"reward": {"xp": 50},
		},
		{
			"id": "done", "title": "Completed Quest", "type": "main",
			"giver": {"zone_id": "zone_00", "npc_id": "ally"},
			"objectives": [{"id": "d1", "kind": "reach", "zone_id": "zone_00", "description": "Reach the gate"}],
			"reward": {"xp": 25},
		},
		{
			"id": "later", "title": "Later Quest", "type": "main",
			"giver": {"zone_id": "zone_02", "npc_id": "scout"},
			"objectives": [{"id": "l1", "kind": "reach", "zone_id": "zone_02", "description": "Reach the bridge"}],
			"reward": {"xp": 10},
		},
	])
	QuestManager.quest_states["main"] = {"state": "active", "objective_index": 0, "progress": 1, "choices": {}}
	QuestManager.quest_states["side"] = {"state": "active", "objective_index": 0, "progress": 0, "choices": {}}
	QuestManager.quest_states["done"] = {"state": "completed", "objective_index": 1, "progress": 0, "choices": {}}
	QuestManager.quest_states["later"] = {"state": "inactive", "objective_index": 0, "progress": 0, "choices": {}}
	QuestManager.tracked_quest_id = "main"
	QuestManager._toggle_journal()
	await get_tree().process_frame

	var journal = QuestManager._journal_view
	assert(QuestManager._journal_open)
	assert(QuestManager._journal_layer != null)
	assert(QuestManager._journal_root.get_parent() == QuestManager._journal_layer)
	assert(QuestManager._journal_layer.transform == Transform2D.IDENTITY)
	assert(journal._hero_host.size == Vector2(400, 108))
	assert(journal.visible_indices == [0])
	assert(journal.selected_index == 0)
	assert(journal._tabs_host.get_child_count() == 3)
	assert(journal._track_button_label.text == "ĐANG THEO DÕI")
	assert(journal._hints_host.get_child_count() == 0)
	assert(journal._basic_rewards_host.get_child_count() == 1)

	QuestManager.quest_states["later"] = {"state": "active", "objective_index": 0, "progress": 0, "choices": {}}
	QuestManager.quests_changed.emit()
	assert(journal.visible_indices == [0, 3])

	QuestManager.reveal_hint("Guide", {"quest_id": "main", "objective_id": "m1", "level": 1}, "Look near the blue flowers.")
	assert(journal._hints_host.get_child_count() > 0)

	InventoryManager.catalog.append({
		"id": "reward_badge", "name": "Reward Badge", "kind": "lore", "role": "reward",
		"quest_id": "main", "acquisition": [{"mode": "quest_reward", "quest_id": "main", "count": 1}],
	})
	InventoryManager.inventory_changed.emit()
	assert(journal._basic_rewards_host.get_child_count() == 2)
	assert(_reward_texts(journal._basic_rewards_host).has("Reward Badge"))

	journal.handle_input(_action("ui_right"))
	assert(journal.category_index == 1)
	assert(journal.visible_indices == [1])
	assert(journal.selected_index == 1)
	journal.handle_input(_action("ui_accept"))
	assert(QuestManager.tracked_quest_id == "side")
	QuestManager._refresh_tracker()
	assert(QuestManager._tracker_view._data.get("title", "") == "Side Quest")

	journal.handle_input(_action("ui_right"))
	assert(journal.category_index == 2)
	assert(journal.visible_indices == [2])
	journal.handle_input(_action("ui_left"))
	assert(journal.category_index == 1)
	assert(journal.visible_indices == [1])
	journal.handle_input(_action("ui_left"))
	assert(journal.category_index == 0)
	assert(journal.visible_indices == [0, 3])

	journal.handle_input(_action("ui_cancel"))
	assert(not QuestManager._journal_open)
	assert(not GameManager.ui_blocking_input)
	print("[QuestJournalRuntimeTest] filters, navigation, tracking, and close passed")
	get_tree().quit()


func _action(action_name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


func _reward_texts(parent: Node) -> Array[String]:
	var texts: Array[String] = []
	_collect_label_texts(parent, texts)
	return texts


func _collect_label_texts(parent: Node, texts: Array[String]) -> void:
	for child in parent.get_children():
		if child is Label:
			var text := str((child as Label).text)
			if not text.is_empty():
				texts.append(text)
		_collect_label_texts(child, texts)
