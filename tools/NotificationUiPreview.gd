extends Node
## Renders both notification variants at production scale for visual QA.

const ToastScript = preload("res://scripts/ui/QuestNotificationToast.gd")


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

	var quest_toast = ToastScript.new()
	quest_toast.setup({
		"palette": "gold",
		"icon": "new_quest",
		"header": "NHIỆM VỤ MỚI",
		"title": "Cánh Hoa Cuối Mùa",
		"subtitle": "Một hành trình mới đã bắt đầu",
	})
	quest_toast.position = Vector2(153, 14)
	ui.add_child(quest_toast)

	var objective_toast = ToastScript.new()
	objective_toast.setup({
		"palette": "cyan",
		"icon": "new_objective",
		"header": "MỤC TIÊU MỚI",
		"title": "Thu thập 3 Cánh Hoa Xám",
		"subtitle": "0 / 3",
		"title_font_size": 6,
	})
	objective_toast.position = Vector2(153, 72)
	ui.add_child(objective_toast)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(quest_toast.size == Vector2(174, 44))
	assert(objective_toast.size == Vector2(174, 44))
	assert(quest_toast.title_label.get_line_count() == 1)
	assert(objective_toast.title_label.get_line_count() <= 2)
	assert(quest_toast.header_label.text == "NHIỆM VỤ MỚI")
	assert(objective_toast.header_label.text == "MỤC TIÊU MỚI")

	var output := "res://assets/ui/notification_v1/preview.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[NotificationUiPreview] wrote %s" % output)
	get_tree().quit()
