extends Node
## End-to-end runtime QA for item payload creation, queue playback and legacy
## text-toast compatibility.


func _ready() -> void:
	AnnouncementCenter.reset()
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"icon_grid": 3,
		"icon_cell_px": 48,
		"items": [{
			"id": "item_gray_petal",
			"name": "Cánh Hoa Xám",
			"kind": "quest",
			"icon_index": 0,
		}],
	}, load("res://assets/ui/inventory/sample_icon_sheet.png"))
	InventoryManager._toast_queue.clear()
	InventoryManager._toast_busy = false

	InventoryManager.add_item("item_gray_petal", 3)
	assert(InventoryManager.count_of("item_gray_petal") == 3)
	assert(InventoryManager._toast_queue.size() == 1)
	var payload: Dictionary = InventoryManager._toast_queue[0] as Dictionary
	assert(str(payload.get("kind", "")) == "item")
	assert(str(payload.get("name", "")) == "Cánh Hoa Xám")
	assert(int(payload.get("count", 0)) == 3)
	assert(payload.get("icon") is Texture2D)

	InventoryManager._process(0.0)
	assert(InventoryManager._toast_busy)
	assert(InventoryManager._toast_host.get_child_count() == 1)
	var toast := InventoryManager._toast_host.get_child(0) as ItemPickupToast
	assert(toast != null)
	assert(toast._frame_texture != null)
	assert(toast.header_label.text == "VẬT PHẨM NHẬN ĐƯỢC")
	assert(toast.name_label.text == "Cánh Hoa Xám")
	assert(toast.quantity_label.text == "+3")

	await get_tree().create_timer(3.15).timeout
	await get_tree().process_frame
	assert(not InventoryManager._toast_busy)
	assert(InventoryManager._toast_host.get_child_count() == 0)

	# Call sites such as party and quest messaging still use the compact legacy
	# text toast and must remain queue-compatible after the structured payload.
	InventoryManager._push_toast("Cập nhật hành trình")
	InventoryManager._process(0.0)
	assert(InventoryManager._toast_busy)
	await get_tree().process_frame
	assert(InventoryManager._toast_host.get_child_count() == 1)
	await get_tree().create_timer(2.55).timeout
	await get_tree().process_frame
	assert(not InventoryManager._toast_busy)
	assert(InventoryManager._toast_host.get_child_count() == 0)

	print("[ItemPickupToastRuntimeTest] item and text toast playback passed")
	get_tree().quit()
