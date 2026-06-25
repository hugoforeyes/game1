extends Node
## Runtime QA for collect objectives followed by an already-satisfied reach step.


func _ready() -> void:
	QuestManager.set_process(false)
	InventoryManager.reset()
	QuestManager.reset()
	InventoryManager.load_chapter_catalog({
		"items": [
			{"id": "item_gray_petal", "kind": "quest", "quest_id": "quest_01", "name": "Gray Petal"},
			{"id": "item_05", "kind": "quest", "quest_id": "quest_01", "name": "Gray Petal"},
		],
	}, null)
	QuestManager.load_chapter_quests([
		{
			"id": "quest_01",
			"title": "Cánh Hoa Cuối Mùa",
			"type": "main",
			"giver": {"mode": "npc", "zone_id": "zone_05", "npc_id": "arlo"},
			"objectives": [
				{
					"id": "o1", "kind": "collect", "zone_id": "zone_05",
					"item_id": "item_gray_petal", "item_ref": "item_gray_petal",
					"description": "Thu thập 3 Cánh Hoa Xám", "count": 3,
				},
				{
					"id": "o2", "kind": "reach", "zone_id": "zone_05",
					"description": "Xác nhận phát hiện trong cùng khu vực.",
				},
				{
					"id": "o3", "kind": "talk", "zone_id": "zone_05",
					"target_npc_id": "arlo", "description": "Nói chuyện với Arlo.",
				},
			],
			"reward": {"xp": 80},
		},
	])
	QuestManager.notify_zone_entered("zone_05")
	QuestManager._toast_queue.clear()

	InventoryManager.add_item("item_05", 3, true)
	var state: Dictionary = QuestManager.quest_states.get("quest_01", {}) as Dictionary
	assert(int(state.get("objective_index", -1)) == 0)
	assert(int(state.get("progress", -1)) == 0)

	for _i in range(3):
		InventoryManager.add_item("item_gray_petal", 1, true)
	state = QuestManager.quest_states.get("quest_01", {}) as Dictionary
	assert(str(state.get("state", "")) == "active")
	assert(int(state.get("objective_index", -1)) == 1)
	assert(int(state.get("progress", -1)) == 0)
	assert(str(QuestManager._current_objective(QuestManager.quests[0] as Dictionary).get("id", "")) == "o2")

	print("[QuestCollectReachAdvanceTest] collect does not auto-complete following reach objective passed")
	get_tree().quit()
