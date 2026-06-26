extends Node2D

const PromptScript := preload("res://scripts/ui/WorldInteractionPrompt.gd")


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.025, 0.03, 0.04, 1.0))
	_add_backdrop()
	_add_prompt(Vector2(120, 104), "Talk to Mira", "npc")
	_add_prompt(Vector2(120, 180), "Quan sát", "object")
	_add_prompt(Vector2(120, 256), "Search the antique sugar-clock mechanism", "object")
	_add_prompt(Vector2(120, 332), "Talk to Captain Leona about the missing lantern route", "npc")


func _add_backdrop() -> void:
	var label := Label.new()
	label.text = "World Interaction Prompt - single item runtime mock"
	label.position = Vector2(120, 48)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.92, 0.82, 0.58, 1.0))
	add_child(label)

	var sub := Label.new()
	sub.text = "Fixed height. Width grows with text, then truncates at the safe screen max."
	sub.position = Vector2(120, 72)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72, 1.0))
	add_child(sub)


func _add_prompt(pos: Vector2, text: String, kind: String) -> void:
	var prompt: Node2D = PromptScript.new()
	add_child(prompt)
	prompt.position = pos
	prompt.set_item(text, kind)
	prompt.show_prompt()
