extends Node
## Runtime QA for collect objectives fulfilled by an NPC acquisition grant.


func _ready() -> void:
	QuestManager.set_process(false)
	InventoryManager.reset()
	QuestManager.reset()
	InventoryManager.load_chapter_catalog({
		"items": [
			{
				"id": "item_mailbag_frontline",
				"kind": "quest",
				"quest_id": "quest_01",
				"quest_ids": ["quest_01"],
				"name": "Tui Thu Tien Tuyen",
				"acquisition": [
					{
						"mode": "npc_grant",
						"source_entity_id": "npc_02",
						"zone_id": "zone_nested_01",
						"objective_id": "o2",
						"quest_id": "quest_01",
						"count": 1,
						"chance": 1.0,
					},
				],
			},
		],
	}, null)
	QuestManager.load_chapter_quests([
		{
			"id": "quest_01",
			"title": "Nhung La Thu Chua Bao Gio Den",
			"type": "main",
			"giver": {"mode": "npc", "zone_id": "zone_nested_01", "npc_id": "npc_02"},
			"objectives": [
				{
					"id": "o1", "kind": "talk", "zone_id": "zone_nested_01",
					"target_npc_id": "npc_02", "description": "Noi chuyen voi Roland.",
				},
				{
					"id": "o2", "kind": "collect", "zone_id": "zone_nested_01",
					"item_id": "item_mailbag_frontline", "item_ref": "item_mailbag_frontline",
					"count": 1, "description": "Nhan tui thu tu Roland.",
				},
				{
					"id": "o3", "kind": "talk", "zone_id": "zone_nested_01",
					"target_npc_id": "npc_02", "description": "Bao lai voi Roland.",
				},
			],
			"reward": {"xp": 80},
		},
	])
	QuestManager.notify_zone_entered("zone_nested_01")
	QuestManager._toast_queue.clear()

	QuestManager.notify_npc_talked("npc_02")

	var state: Dictionary = QuestManager.quest_states.get("quest_01", {}) as Dictionary
	assert(InventoryManager.count_of("item_mailbag_frontline") == 1)
	assert(str(state.get("state", "")) == "active")
	assert(int(state.get("objective_index", -1)) == 2)
	assert(str(QuestManager._current_objective(QuestManager.quests[0] as Dictionary).get("id", "")) == "o3")

	print("[NpcGrantCollectObjectiveTest] NPC-granted collect objective passed")
	get_tree().quit()
