extends Control
## Shown when every playable chapter has been cleared.

func _ready() -> void:
	GameManager.ui_blocking_input = false
	anchors_preset = Control.PRESET_TOP_LEFT
	position = Vector2.ZERO
	size = Vector2(480, 270)
	scale = Vector2(2, 2)

	var background := ColorRect.new()
	background.color = Color(0.01, 0.01, 0.03, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var title := Label.new()
	title.text = "THE STORY RESTS HERE"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.50, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(20, 100)
	title.size = Vector2(440, 30)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "You have cleared every chapter in this build.\nMore of the world is still being generated."
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color(0.93, 0.88, 0.75, 0.85))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(20, 140)
	subtitle.size = Vector2(440, 40)
	add_child(subtitle)

	var hint := Label.new()
	hint.text = "Press Enter to return to the title screen"
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.82, 0.73, 0.51, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(20, 210)
	hint.size = Vector2(440, 20)
	add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/ui/StartScene.tscn")
