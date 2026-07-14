extends Node
## Renders the remaining lightweight top-edge notification at production scale.
## Quest/objective/completion updates intentionally do not appear here: they use
## AnnouncementView's full-screen ceremony in every gameplay context.

const ToastScript := preload("res://scripts/ui/QuestNotificationToast.gd")


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.12, 0.24, 0.20, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	for index in range(18):
		var block := ColorRect.new()
		block.color = Color(0.20, 0.38, 0.25, 0.68) if index % 2 == 0 else Color(0.34, 0.28, 0.18, 0.68)
		block.position = Vector2(45 + (index % 6) * 145, 85 + (index / 6) * 150)
		block.size = Vector2(96, 96)
		add_child(block)

	var ui := CanvasLayer.new()
	ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))
	add_child(ui)

	var hint_toast = ToastScript.new()
	hint_toast.setup({
		"palette": "cyan",
		"icon": "new_objective",
		"header": "GỢI Ý MỚI",
		"title": "Từ Bà Miên",
		"subtitle": "Đã cập nhật bảng gợi ý",
	})
	hint_toast.position = Vector2(132, 14)
	ui.add_child(hint_toast)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hint_toast.size == Vector2(216, 46))
	assert(hint_toast.title_label.get_line_count() == 1)
	assert(hint_toast.header_label.text == "GỢI Ý MỚI")
	assert(hint_toast.header_label.position.x + hint_toast.header_label.size.x \
		<= hint_toast.subtitle_label.position.x,
		"hint header and subtitle rectangles must never overlap")
	assert(hint_toast.subtitle_label.size.x > 0.0)

	var output := "res://assets/ui/notification_v1/preview.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[NotificationUiPreview] wrote hint-only %s" % output)
	get_tree().quit()
