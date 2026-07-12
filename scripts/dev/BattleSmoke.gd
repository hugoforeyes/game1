extends Node2D
## Dev-only smoke test: opens a battle with fallback enemy data and simulates
## menu input so the whole turn loop runs without a human. Run headless:
## godot --headless --path . res://scenes/dev/BattleSmoke.tscn --quit-after 3000

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const MainScript := preload("res://scripts/world/Main.gd")

var _frames: int = 0
var _battle: CanvasLayer = null

func _ready() -> void:
	var main_helper := MainScript.new()
	var enemy_data: Dictionary = main_helper._fallback_enemy(
		"smoke_enemy", "Smoke Echo", "elite", 2, true, Vector2i(3, 3)
	)
	var bark_override := OS.get_environment("BATTLE_BARK_OVERRIDE").strip_edges()
	if not bark_override.is_empty():
		var dialogue: Dictionary = (enemy_data.get("dialogue", {}) as Dictionary).duplicate(true)
		dialogue["intro"] = [bark_override]
		enemy_data["dialogue"] = dialogue
	main_helper.free()
	_battle = BattleSceneScript.new()
	add_child(_battle)
	_battle.battle_finished.connect(_on_finished)
	_battle.open(enemy_data)
	print("[Smoke] battle opened")

func _on_finished(result: String, enemy_id: String) -> void:
	print("[Smoke] battle finished result=%s enemy=%s" % [result, enemy_id])
	get_tree().quit(0)

func _process(_delta: float) -> void:
	_frames += 1
	if _battle == null or not is_instance_valid(_battle):
		return
	# Mash accept every few frames; occasionally move the cursor so different
	# menu entries (attack/skill/probe/guard) get exercised.
	var slow: bool = OS.get_environment("BATTLE_SHOTS") == "1"
	var press_every: int = 45 if slow else 4
	if _frames % press_every == 0:
		if _frames % (press_every * 6) == 0:
			_press("ui_right")
		_press("ui_accept")
	if slow and DisplayServer.get_name() != "headless" and _frames % 75 == 0:
		var image: Image = get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("/tmp/battle_shot_%03d.png" % (_frames / 75))

func _press(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
