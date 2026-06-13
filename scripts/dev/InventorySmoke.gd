extends Node2D
## Dev-only: loads the chapter item catalog from the server, grants samples,
## opens the inventory screen, and saves a screenshot.

func _ready() -> void:
	var response: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapter: Dictionary = (response.get("chapters", []) as Array)[0] as Dictionary
	var icon_texture: Texture2D = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	InventoryManager.load_chapter_catalog(chapter.get("items", {}) as Dictionary, icon_texture)
	for item in InventoryManager.catalog.slice(0, 4):
		InventoryManager.add_item(str((item as Dictionary).get("id")), 2, true)
	InventoryManager._toggle_screen()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/inventory_shot.png")
	print("[InventorySmoke] saved /tmp/inventory_shot.png")
	get_tree().quit(0)
