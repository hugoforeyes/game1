extends Node
## Renders the production Quest Journal at 960x540 and validates its key layout states.

const JournalViewScript = preload("res://scripts/ui/QuestJournalView.gd")


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08, 0.14, 0.18, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var ui := CanvasLayer.new()
	ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))
	add_child(ui)
	var journal = JournalViewScript.new()
	ui.add_child(journal)
	journal.set_data(_quests(), _states(), _hints(), "quest_main", "CHƯƠNG 04  ·  MIỀN ĐẤT CHƯA BIẾT")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(journal.visible_indices == [0, 2])
	assert(journal._tabs_host.get_child_count() == 3)
	assert(journal._list_host.get_child_count() == 2)
	assert(journal._detail_title.text == "Tiếng Gọi Từ Phương Xa")
	assert(journal._tracked_badge.text == "Đang theo dõi")
	assert(journal._objectives_host.get_child_count() >= 3)
	assert(journal._hints_host.get_child_count() >= 3)
	assert(journal._basic_rewards_host.get_child_count() == 3)
	assert(journal._bonus_rewards_host.get_child_count() == 3)
	assert(journal._rewards_host.get_child_count() == 1)
	assert(journal._track_button_label.text == "Đang theo dõi")

	var output := "res://assets/ui/quest_journal_v1/preview.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[QuestJournalUiPreview] wrote %s" % output)
	get_tree().quit()


func _quests() -> Array:
	return [
		{
			"id": "quest_main", "title": "Tiếng Gọi Từ Phương Xa", "type": "main",
			"summary": "Một tín hiệu bí ẩn vọng qua biên giới, mở ra dấu vết của một hành trình mới.",
			"giver": {"npc_id": "Người Dẫn Đường", "zone_id": "Vùng Biên"},
			"objectives": [
				{"id": "o1", "description": "Tìm lối vào khu vực bị lãng quên"},
				{"id": "o2", "description": "Thu thập 4 mảnh tín hiệu", "count": 4},
				{"id": "o3", "description": "Giải mã thông điệp cổ"},
				{"id": "o4", "description": "Đối mặt với người canh giữ"},
			],
			"reward": {"xp": 240},
		},
		{
			"id": "quest_side", "title": "Dấu Chân Không Tên", "type": "side",
			"summary": "Một chuỗi dấu vết lạ xuất hiện gần khu dân cư.",
			"giver": {"npc_id": "Nhân Chứng", "zone_id": "Khu Trung Tâm"},
			"objectives": [{"id": "o1", "description": "Kiểm tra ba địa điểm khả nghi", "count": 3}],
			"reward": {"xp": 90},
		},
		{
			"id": "quest_hidden", "title": "Những Trang Bị Xé", "type": "hidden",
			"summary": "Các trang nhật ký rời rạc dường như cùng kể một câu chuyện.",
			"giver": {"npc_id": "Không rõ", "zone_id": "Không rõ"},
			"objectives": [{"id": "o1", "description": "Khám phá nguồn gốc cuốn nhật ký"}],
			"reward": {"xp": 150},
		},
		{
			"id": "quest_done", "title": "Khởi Đầu", "type": "main",
			"summary": "Bước đầu tiên của hành trình đã hoàn tất.",
			"giver": {"npc_id": "Người Đồng Hành", "zone_id": "Điểm Khởi Hành"},
			"objectives": [{"id": "o1", "description": "Rời khỏi nơi trú ẩn"}],
			"reward": {"xp": 50},
		},
		{
			"id": "quest_side_2", "title": "Món Đồ Thất Lạc", "type": "side",
			"summary": "Một vật kỷ niệm đã biến mất trên đường di chuyển.",
			"giver": {"npc_id": "Du Khách", "zone_id": "Trạm Dừng"},
			"objectives": [{"id": "o1", "description": "Tìm vật kỷ niệm bị thất lạc"}],
			"reward": {"xp": 70},
		},
	]


func _states() -> Dictionary:
	return {
		"quest_main": {"state": "active", "objective_index": 1, "progress": 2},
		"quest_side": {"state": "active", "objective_index": 0, "progress": 1},
		"quest_hidden": {"state": "inactive", "objective_index": 0, "progress": 0},
		"quest_done": {"state": "completed", "objective_index": 1, "progress": 0},
		"quest_side_2": {"state": "inactive", "objective_index": 0, "progress": 0},
	}


func _hints() -> Dictionary:
	return {
		"quest_main:o2": {
			"1": {"text": "Quan sát những nơi có ánh sáng bất thường."},
			"2": {"text": "Tín hiệu mạnh hơn khi tiến gần ranh giới bản đồ."},
			"3": {"text": "Một mảnh nằm sau vật thể có biểu tượng giống nhau."},
		},
	}
