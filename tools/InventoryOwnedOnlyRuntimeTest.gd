extends Node
## Regression coverage for inventory visibility and long detail-text scrolling.


func _ready() -> void:
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"items": [
			{
				"id": "unowned_potion",
				"name": "Potion chưa nhặt",
				"kind": "heal",
			},
			{
				"id": "owned_letter",
				"name": "Bức thư đã nhặt",
				"kind": "lore",
				"detail": {
					"kind": "text",
					"text": "Một dòng nội dung rất dài để kiểm tra vùng cuộn. ".repeat(80),
				},
			},
			{
				"id": "unowned_quest_item",
				"name": "Vật phẩm nhiệm vụ chưa nhặt",
				"kind": "quest",
			},
		],
	}, null)
	InventoryManager.add_item("owned_letter", 1, true)

	InventoryManager._active_filter = "all"
	assert(InventoryManager._filtered_catalog_indices() == [1])
	assert(InventoryManager._owned_catalog_size() == 1)
	InventoryManager._active_filter = "quest"
	assert(InventoryManager._filtered_catalog_indices().is_empty())
	InventoryManager._active_filter = "lore"
	assert(InventoryManager._filtered_catalog_indices() == [1])

	InventoryManager._selected = 0
	InventoryManager._toggle_screen()
	await get_tree().process_frame
	InventoryManager._activate_selected()
	await get_tree().process_frame
	await get_tree().process_frame

	assert(InventoryManager._detail_view_text is RichTextLabel)
	assert(InventoryManager._detail_view_text.scroll_active)
	assert(InventoryManager._detail_view_text.get_content_height() > InventoryManager._detail_view_text.size.y)
	var scroll_bar := InventoryManager._detail_view_text.get_v_scroll_bar()
	assert(scroll_bar.max_value > scroll_bar.page)
	InventoryManager._scroll_detail_text(72.0)
	assert(scroll_bar.value > 0.0)

	InventoryManager._close_item_detail_view()
	InventoryManager.remove_item("owned_letter", 1)
	assert(InventoryManager._filtered_catalog_indices().is_empty())

	print("[InventoryOwnedOnlyRuntimeTest] owned-only filtering and detail scrolling passed")
	get_tree().quit()
