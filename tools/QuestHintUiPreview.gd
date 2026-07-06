extends Node
## Renders a deterministic 960x540 visual QA image for the modular quest HUD.


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.12, 0.24, 0.20, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var title := UiKit.make_label("TOP-RIGHT RESPONSIVE QUEST TRACKER · 960×540 QA", 14, Color(0.86, 0.91, 0.82, 0.72))
	title.position = Vector2(32, 30)
	title.size = Vector2(600, 30)
	add_child(title)

	for index in range(10):
		var block := ColorRect.new()
		block.color = Color(0.20, 0.38, 0.25, 0.65) if index % 2 == 0 else Color(0.34, 0.28, 0.18, 0.65)
		block.position = Vector2(40 + (index % 5) * 105, 100 + (index / 5) * 120)
		block.size = Vector2(72, 72)
		add_child(block)

	QuestManager.reset()
	QuestManager.load_chapter_quests([
		{
			"id": "quest_preview",
			"title": "Cánh Hoa Cuối Mùa",
			"type": "main",
			"summary": "Arlo nhờ Lumi điều tra những cánh hoa đang mất màu.",
			"giver": {"mode": "npc", "zone_id": "zone_01", "npc_id": "arlo"},
			"objectives": [
				{
					"id": "o1",
					"kind": "collect",
					"zone_id": "zone_01",
					"description": "Đi đến Cánh Đồng Hoa Dương để điều tra nguồn gốc những cánh hoa đang dần mất màu.",
					"count": 3,
				},
			],
			"reward": {"xp": 80},
		},
	])
	QuestManager.notify_zone_entered("zone_01")
	var state: Dictionary = QuestManager.quest_states.get("quest_preview", {}) as Dictionary
	state["progress"] = 2
	QuestManager.reveal_hint(
		"Arlo",
		{"quest_id": "quest_preview", "objective_id": "o1", "level": 1},
		"Tìm quanh những luống hoa đã mất màu.",
	)
	QuestManager.reveal_hint(
		"Nara",
		{"quest_id": "quest_preview", "objective_id": "o1", "level": 2},
		"Chúng thường nằm gần rìa cánh đồng.",
	)
	QuestManager.reveal_hint(
		"Breni",
		{"quest_id": "quest_preview", "objective_id": "o1", "level": 3},
		"Kiểm tra các bụi hoa cạnh hàng rào gỗ.",
		load("res://assets/ui/chatbox_npc_portrait.png") as Texture2D,
	)
	QuestManager._refresh_tracker()
	QuestManager._toast_queue.clear()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var view = QuestManager._tracker_view
	assert(view != null)
	assert(view._data.get("current") == 2 and view._data.get("total") == 3)
	assert(view.line_count >= 1)
	assert(QuestManager._hint_available)
	assert(view.hint_row_count == 3)
	assert(view._panel_height > 150.0)
	view.visible = true
	var output := "res://assets/ui/quest_tracker_v3/preview_expanded.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[QuestHintUiPreview] wrote %s" % output)
	get_tree().quit()
