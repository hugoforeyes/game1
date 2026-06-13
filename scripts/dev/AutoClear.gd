extends Node
## Dev helper for flow smoke tests: once the world is up and no UI is blocking,
## instantly defeats all hostiles so zone/chapter advancement can be verified.

var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 3.0:
		return
	_timer = 0.0
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("_check_zone_cleared"):
		return
	if GameManager.ui_blocking_input:
		return
	var characters: Node = main.get("generated_characters")
	if characters == null:
		return
	var cleared := 0
	for child in characters.get_children():
		if child.has_method("is_hostile") and child.is_hostile():
			var data: Dictionary = child.get("enemy_data") as Dictionary
			GameManager.mark_enemy_defeated(str(data.get("id", "")))
			child.queue_free()
			cleared += 1
	if cleared > 0:
		print("[AutoClear] force-defeated %d hostiles" % cleared)
		await get_tree().process_frame
		main._check_zone_cleared()
