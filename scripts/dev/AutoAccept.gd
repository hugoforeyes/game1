extends Node
## Dev helper: periodically presses ui_accept so intros/cutscenes auto-advance
## in headless smoke tests. Lives at the tree root, survives scene changes.

var _frames: int = 0
var _press_interval: int = 30

func _ready() -> void:
	if OS.get_environment("FLOW_SHOTS") == "1":
		_press_interval = 110

func _process(_delta: float) -> void:
	_frames += 1
	if OS.get_environment("FLOW_SHOTS") == "1" and _frames % 55 == 0:
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png("/tmp/flow_shot_%03d.png" % (_frames / 55))
	if OS.get_environment("FLOW_SHOTS") == "1" and _frames in [4300, 4900]:
		# Open the inventory, then the quest journal, near the end of the run.
		var press := InputEventKey.new()
		press.physical_keycode = KEY_I if _frames == 4300 else KEY_J
		press.pressed = true
		Input.parse_input_event(press)
	if OS.get_environment("FLOW_SHOTS") == "1" and _frames == 4700:
		var esc := InputEventAction.new()
		esc.action = "ui_cancel"
		esc.pressed = true
		Input.parse_input_event(esc)
	if _frames % _press_interval != 0:
		return
	var press := InputEventAction.new()
	press.action = "ui_accept"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = "ui_accept"
	release.pressed = false
	Input.parse_input_event(release)
