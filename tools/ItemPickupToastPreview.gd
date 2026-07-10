extends Node
## Production-scale visual QA for the item acquisition toast.

const ToastScript = preload("res://scripts/ui/ItemPickupToast.gd")


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.075, 0.15, 0.12, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	# Abstracted gameplay blocks make contrast and safe-area issues obvious while
	# keeping the preview deterministic and asset-independent.
	for index in range(24):
		var block := ColorRect.new()
		block.color = Color(0.12, 0.27, 0.18, 0.72) if index % 3 else Color(0.28, 0.23, 0.14, 0.70)
		block.position = Vector2(20 + (index % 8) * 128, 108 + (index / 8) * 154)
		block.size = Vector2(88, 96)
		add_child(block)

	var sample_icon: Texture2D = load("res://assets/ui/inventory/sparkle_blue.png")
	var toast = ToastScript.new()
	toast.setup({"name": "Cánh Hoa Xám", "count": 3, "icon": sample_icon})
	toast.position = Vector2(512 - 180, 44)
	add_child(toast)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(toast.size == Vector2(360, 72))
	assert(toast._frame_texture != null)
	assert(toast.header_label.text == "VẬT PHẨM NHẬN ĐƯỢC")
	assert(toast.name_label.text == "Cánh Hoa Xám")
	assert(toast.quantity_label.text == "+3")
	assert(toast.header_label.position == Vector2(92, 11))
	assert(toast.name_label.position == Vector2(92, 29))

	var output := "res://assets/ui/item_pickup_v2/preview.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[ItemPickupToastPreview] wrote %s" % output)
	get_tree().quit()
