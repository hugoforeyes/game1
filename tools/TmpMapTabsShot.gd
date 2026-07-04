extends Node2D
func _ready() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.10, 0.12, 0.09); bg.size = get_viewport().get_visible_rect().size; add_child(bg)
	ChapterFlow.flow = {"chapters": [
		{"chapter": 1, "title": "Lời Thì Thầm Đầu Tiên", "minimap": {
			"entrance_zone_id": "zone_01", "boss_zone_id": "zone_03", "background_image_url": "",
			"zones": [
				{"zone_id": "zone_01", "name": "Làng Rễ Bình Minh", "type": "town", "center": {"x": 0.2, "y": 0.6}, "connections": ["zone_02"]},
				{"zone_id": "zone_02", "name": "Quảng Trường Cổ Mộc", "type": "town", "center": {"x": 0.5, "y": 0.45}, "connections": ["zone_01", "zone_03"]},
				{"zone_id": "zone_03", "name": "Tháp Vọng Gió", "type": "dungeon", "center": {"x": 0.8, "y": 0.55}, "connections": ["zone_02"]},
			]}},
		{"chapter": 2, "title": "Miền Đất Chưa Biết"},
	]}
	ChapterFlow.chapter_index = 0
	ChapterFlow.active = true
	QuestManager.visited_zones = {"zone_01": true, "zone_02": true}
	GameManager.imported_scene_context = {"zone_id": "zone_02"}
	MinimapManager._toggle()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/map_frame_shot.png")
	print("[Tmp] wrote /tmp/map_frame_shot.png")
	get_tree().quit()
