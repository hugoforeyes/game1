extends Node2D
## Dev-only: loads the chapter item catalog from the server, grants samples,
## opens the inventory screen, and saves a screenshot.

const SAMPLE_ICON_SHEET := "res://assets/ui/inventory/sample_icon_sheet.png"


func _ready() -> void:
	var response: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapters: Array = response.get("chapters", []) as Array
	var items_payload: Dictionary = {}
	var icon_texture: Texture2D = null
	if not chapters.is_empty():
		var chapter: Dictionary = chapters[0] as Dictionary
		items_payload = chapter.get("items", {}) as Dictionary
		icon_texture = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	if items_payload.is_empty() or icon_texture == null:
		items_payload = _sample_items_payload()
		icon_texture = _load_png_texture(SAMPLE_ICON_SHEET)
	InventoryManager.load_chapter_catalog(items_payload, icon_texture)
	for item in InventoryManager.catalog:
		var definition := item as Dictionary
		var amount := int(definition.get("icon_index", 0)) % 4 + 1
		InventoryManager.add_item(str(definition.get("id")), amount, true)
	InventoryManager._toggle_screen()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/inventory_shot.png")
	print("[InventorySmoke] saved /tmp/inventory_shot.png")
	get_tree().quit(0)


func _load_png_texture(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[InventorySmoke] failed to load %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _sample_items_payload() -> Dictionary:
	var items: Array = []
	var kinds := ["heal", "energy", "buff", "quest", "lore"]
	var names := [
		"Cánh Sương", "Nụ Tro", "Nhựa Ngân Ca", "La Bàn Cũ", "Lá Niêm Phong",
		"Hạt Ánh Kim", "Dây Vải Lam", "Túi Đất Mịn", "Mảnh Pha Lê", "Sách Mỏng",
		"Bình Tím", "Đá Xám", "Vòng Da", "Bùa Nhỏ", "Hổ Phách",
		"Bình Gốm", "Cụm Tinh Thể", "Đồng Xu", "Rương Bé", "Ống Kính"
	]
	for i in range(names.size()):
		var kind: String = kinds[i % kinds.size()]
		items.append({
			"id": "sample_%02d" % i,
			"kind": kind,
			"name": names[i],
			"description": "Một vật phẩm nhỏ được giữ lại trong hành trình. Nó có hình dáng riêng, công dụng rõ ràng và một mẩu ký ức giúp người chơi hiểu thêm về thế giới.",
			"icon_index": i % 8,
			"power": 35 + i * 3,
			"droppable": kind in ["heal", "energy", "buff"],
		})
	return {
		"items": items,
		"icon_grid": 3,
		"icon_cell_px": 96,
	}
