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

	var portrait := _fake_portrait()
	var payloads: Array = [
		{"kind": "new_quest", "quest": {"title": "Tiếng Gọi Rừng Thẳm", "type": "main"}},
		{
			"kind": "objective",
			"quest": {"title": "Tiếng Gọi Rừng Thẳm"},
			"objective": {"description": "Thu thập cánh hoa nguyệt quang ở Cánh Đồng Sương", "count": 3},
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

	var item_view: CanvasLayer = ObjectInteractionViewScript.new()
	add_child(item_view)
	item_view.open_item_announcement([
		{"item_id": "petal", "name": "Cánh Hoa Nguyệt Quang", "count": 3},
		{"item_id": "charm", "name": "Bùa Hộ Mệnh", "count": 1},
	])
	await get_tree().create_timer(1.0).timeout
	await _shot("/tmp/announce_item.png")

	get_tree().quit(0)


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
