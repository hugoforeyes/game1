extends Node
## Runtime QA for generic cinematic cutscene action primitives.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")

var _finished := false


class FakeActor:
	extends Node2D
	var anim_sprite: AnimatedSprite2D = null
	var camera: Camera2D = null
	var npc_data: Dictionary = {}
	var enemy_data: Dictionary = {}


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	var player := FakeActor.new()
	player.name = "Player"
	player.camera = Camera2D.new()
	player.add_child(player.camera)
	player.global_position = Vector2(64, 64)
	world.add_child(player)

	var characters := Node2D.new()
	characters.name = "GeneratedCharacters"
	world.add_child(characters)

	var attacker := FakeActor.new()
	attacker.name = "Attacker"
	attacker.npc_data = {"id": "npc_attacker"}
	attacker.global_position = Vector2(112, 64)
	characters.add_child(attacker)

	var victim := FakeActor.new()
	victim.name = "Victim"
	victim.enemy_data = {"id": "enemy_victim"}
	victim.global_position = Vector2(160, 64)
	characters.add_child(victim)

	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene.cutscene_finished.connect(func() -> void:
		_finished = true
	)
	cutscene.play(
		[
			{"type": "title", "text": "Action Test", "seconds": 1.0},
			{"type": "emote", "actor": "npc_attacker", "emotion": "alert", "seconds": 0.4},
			{"type": "attack", "actor": "npc_attacker", "target": "enemy_victim", "style": "slash", "seconds": 0.3},
			{"type": "hurt", "actor": "enemy_victim", "source": "npc_attacker", "severity": "heavy", "seconds": 0.3},
			{"type": "shake", "seconds": 0.2, "strength": 4.0},
			{"type": "die", "actor": "enemy_victim"},
		],
		world,
		player,
		characters,
		{}
	)

	var elapsed := 0.0
	while not _finished and elapsed < 12.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	assert(_finished)
	assert(not victim.visible)
	print("[CutsceneActionTypesTest] cinematic action primitives passed")
	get_tree().quit()
