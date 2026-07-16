extends Node2D
## Dev-only: renders every reward-ceremony announcement kind and saves
## screenshots so the announce_v1 UI can be eyeballed without playing a chapter.

const AnnouncementViewScript := preload("res://scripts/ui/AnnouncementView.gd")
const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.15, 1.0)
	bg.size = get_viewport().get_visible_rect().size
	add_child(bg)
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"icon_grid": 3,
		"icon_cell_px": 48,
		"items": [
			{"id": "petal", "name": "Cánh Hoa Nguyệt Quang", "kind": "quest", "icon_index": 0},
			{"id": "charm", "name": "Bùa Hộ Mệnh", "kind": "quest", "icon_index": 1},
			{"id": "map", "name": "Bản Đồ Hành Lang Ngập Sương", "kind": "lore", "icon_index": 2},
			{"id": "relic", "name": "Mảnh Thánh Tích Cổ", "kind": "quest", "icon_index": 3},
		],
	}, load("res://assets/ui/inventory/sample_icon_sheet.png"))

	var portrait := _fake_portrait()
	var payloads: Array = [
		{"kind": "new_quest", "quest": {"title": "Tiếng Gọi Rừng Thẳm", "type": "main"}},
		{
			"kind": "objective",
			"quest": {"title": "Tiếng Gọi Rừng Thẳm"},
			"objective": {
				"description": "Thu thập cánh hoa nguyệt quang ở Cánh Đồng Sương",
				"narrative_lead_in": "Vết sáng trên phiến lá hé lộ rằng những cánh hoa chỉ nở nơi sương đêm còn đọng lại, nhưng dấu chân mới bên bờ suối cho thấy ai đó đã hái chúng trước bình minh. Lumi phải lần theo mùi hương còn sót lại qua Cánh Đồng Sương, tìm người giữ chiếc giỏ bạc và khám phá vì sao khu rừng đang dần mất đi ánh trăng trước đêm nay.",
				"delivery_mode": "narration",
				"count": 3,
			},
			"progress": 0,
		},
		{"kind": "quest_complete", "quest": {"title": "Tiếng Gọi Rừng Thẳm", "reward": {"xp": 150}}},
		{
			"kind": "hint",
			"hint": {
				"npc_name": "Bà Miên", "level": 2,
				"text": "Hãy tìm nơi ánh trăng chạm xuống mặt nước — cánh hoa chỉ nở khi đêm thật tĩnh lặng, con ạ.",
				"portrait": portrait,
			},
		},
		{"kind": "companion", "name": "Arlo", "role": "Hộ vệ", "portrait": portrait},
	]

	for payload in payloads:
		var view: CanvasLayer = AnnouncementViewScript.new()
		add_child(view)
		view.present(payload as Dictionary)
		await get_tree().create_timer(1.0).timeout
		await _shot("/tmp/announce_%s.png" % str((payload as Dictionary).get("kind")))
		view._dismiss()
		await view.dismissed

	var item_sets: Array = [
		[
			{"item_id": "petal", "name": "Cánh Hoa Nguyệt Quang", "count": 3},
		],
		[
			{"item_id": "petal", "name": "Cánh Hoa Nguyệt Quang", "count": 3},
			{"item_id": "charm", "name": "Bùa Hộ Mệnh", "count": 1},
		],
		[
			{"item_id": "petal", "name": "Cánh Hoa Nguyệt Quang", "count": 128},
			{"item_id": "charm", "name": "Bùa Hộ Mệnh", "count": 1},
			{"item_id": "map", "name": "Bản Đồ Hành Lang Ngập Sương", "count": 1},
			{"item_id": "relic", "name": "Mảnh Thánh Tích Cổ", "count": 2},
		],
	]
	for item_set in item_sets:
		var item_view: CanvasLayer = ObjectInteractionViewScript.new()
		add_child(item_view)
		var body_text := ""
		if (item_set as Array).size() == 4:
			body_text = "Bạn tìm thấy những vật phẩm được giấu dưới lớp đá cũ; tất cả đã được chuyển vào hành trang."
		item_view.open_item_announcement(item_set as Array, body_text)
		await get_tree().create_timer(1.0).timeout
		var item_count := (item_set as Array).size()
		_assert_item_layout(item_view, item_count)
		await _shot("/tmp/announce_item_%d.png" % item_count)
		if item_count == 2:
			await _shot("/tmp/announce_item.png")
		item_view.queue_free()
		await get_tree().process_frame

	# Exercise the other production entry point: search a world object, then let
	# the same view transition from EXAMINE into the item-reveal result.
	ObjectInteractionManager.reset()
	ObjectInteractionManager.register_zone_contracts({
		"scene_context": {"zone_id": "qa_zone"},
		"object_interactions": {
			"contracts": [{
				"object_id": "qa_hidden_cache",
				"name": "Hốc Đá Phủ Rêu",
				"archetype": "search",
				"verb": "Tìm kiếm",
				"examine_text": "Những vết xước mới trên phiến đá cho thấy có thứ gì đó được giấu phía sau lớp rêu. Những sợi dây leo quanh hốc đá đã bị kéo lệch, còn lớp đất ẩm bên dưới lưu lại một dấu tay rất mới. Có lẽ ai đó đã vội vàng che giấu một món đồ tại đây trước khi rời khỏi khu rừng.",
				"success_text": "Bạn gạt lớp rêu sang một bên và tìm thấy vật phẩm được cất kỹ trong hốc đá.",
				"grants": [{"item_id": "petal", "name": "Cánh Hoa Nguyệt Quang", "count": 3}],
				"one_shot": true,
			}],
			"object_sourced_item_ids": ["petal"],
		},
	})
	var object_view: CanvasLayer = ObjectInteractionViewScript.new()
	add_child(object_view)
	object_view.open_object("qa_hidden_cache")
	await get_tree().create_timer(0.5).timeout
	_assert_narrative_layout(object_view)
	await _shot("/tmp/item_reveal_object_examine.png")
	object_view._activate_primary()
	await get_tree().create_timer(0.8).timeout
	_assert_item_layout(object_view, 1)
	await _shot("/tmp/item_reveal_object_result.png")
	object_view.queue_free()
	await get_tree().process_frame

	get_tree().quit(0)


func _assert_item_layout(view: CanvasLayer, expected_items: int) -> void:
	var panel := view.get("_panel") as Panel
	var body := view.get("_body") as Label
	var reveal_box := view.get("_reveal_box") as HBoxContainer
	var action_panel := view.get("_action_panel") as Panel
	assert(panel != null and panel.size == Vector2(600, 384))
	assert(body != null and body.size.y <= 36.5 and body.max_lines_visible == 3)
	assert(reveal_box != null and reveal_box.get_child_count() == expected_items)
	assert(reveal_box.visible)
	assert(action_panel != null and action_panel.position.y > reveal_box.position.y + reveal_box.size.y)
	var expected_center := get_viewport().get_visible_rect().size * 0.5 + Vector2(0, 5)
	assert(panel.get_global_rect().get_center().distance_to(expected_center) < 0.5)
	for card in reveal_box.get_children():
		assert((card as Control).position.x >= -0.5)
		assert((card as Control).position.x + (card as Control).size.x <= reveal_box.size.x + 0.5)


func _assert_narrative_layout(view: CanvasLayer) -> void:
	var body := view.get("_body") as Label
	var reveal_box := view.get("_reveal_box") as HBoxContainer
	var action_panel := view.get("_action_panel") as Panel
	assert(body != null and body.size.y >= 161.0 and body.max_lines_visible >= 9)
	assert(reveal_box != null and not reveal_box.visible)
	assert(action_panel != null and body.position.y + body.size.y < action_panel.position.y)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[AnnounceShot] saved %s" % path)


## A warm gradient stand-in portrait, so the circle-crop path gets exercised
## without needing chapter data.
func _fake_portrait() -> Texture2D:
	var image := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	for y in range(160):
		for x in range(160):
			var t := float(y) / 159.0
			image.set_pixel(x, y, Color(0.78 - 0.3 * t, 0.55 - 0.2 * t, 0.38, 1.0))
	image.fill_rect(Rect2i(52, 46, 56, 64), Color(0.92, 0.78, 0.62, 1.0))
	return ImageTexture.create_from_image(image)
