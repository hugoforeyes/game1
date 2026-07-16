extends Node
## Runtime QA for cutscene-only ghost actors (dead figures from the backend plan).
## Proves: a ghost id listed in ghost_actors spawns as a translucent silhouette for
## the cutscene's duration, plays actions (move/emote/die), never touches living
## actors, and is freed — not returned home — when the cutscene finishes.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")

var _finished := false


class FakeActor:
	extends Node2D
	var anim_sprite: AnimatedSprite2D = null
	var camera: Camera2D = null
	var npc_data: Dictionary = {}
	var enemy_data: Dictionary = {}


func _direction_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	for direction in ["down", "up", "left", "right"]:
		frames.add_animation("walk_%s" % direction)
	return frames


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	var player := FakeActor.new()
	player.name = "Player"
	player.camera = Camera2D.new()
	player.add_child(player.camera)
	player.anim_sprite = AnimatedSprite2D.new()
	player.anim_sprite.sprite_frames = _direction_frames()
	player.add_child(player.anim_sprite)
	player.global_position = Vector2(64, 64)
	world.add_child(player)

	var characters := Node2D.new()
	characters.name = "GeneratedCharacters"
	world.add_child(characters)

	var living := FakeActor.new()
	living.name = "LivingIvar"
	living.npc_data = {"id": "npc_gray_wounded_ivar"}
	living.anim_sprite = AnimatedSprite2D.new()
	living.anim_sprite.sprite_frames = _direction_frames()
	living.add_child(living.anim_sprite)
	living.global_position = Vector2(112, 64)
	characters.add_child(living)
	var base_children := characters.get_child_count()

	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene.cutscene_finished.connect(func() -> void:
		_finished = true
	)
	cutscene.play(
		[
			{"type": "title", "text": "Ghost Test", "seconds": 1.0},
			{"type": "move", "actor": "ghost_01", "to": {"x": 2, "y": 1}},
			{"type": "emote", "actor": "ghost_01", "emotion": "sad", "seconds": 0.4},
			{"type": "die", "actor": "ghost_01"},
		],
		world,
		player,
		characters,
		{"player": {"x": 1, "y": 1}, "ghost_01": {"x": 2, "y": 2}},
		[{"id": "ghost_01", "name": "Người Đã Khuất"}]
	)

	# The apparition exists the moment the cutscene starts.
	var ghost: Node2D = cutscene._find_actor("ghost_01")
	assert(ghost != null, "ghost actor was not spawned")
	assert(ghost.get_parent() == characters)
	assert(characters.get_child_count() == base_children + 1)
	var ghost_sprite: AnimatedSprite2D = ghost.get("anim_sprite")
	assert(ghost_sprite != null and ghost_sprite.sprite_frames != null)
	assert(ghost_sprite.modulate.a < 1.0, "ghost must be translucent")
	assert(str((ghost.get("npc_data") as Dictionary).get("name", "")) == "Người Đã Khuất")

	# Its portrait is the tinted body-fallback silhouette, never a living face.
	assert(cutscene._resolve_portrait("ghost_01", "neutral") != null)
	assert(cutscene._portrait_tint_cache.has("ghost_01"))

	var elapsed := 0.0
	while not _finished and elapsed < 12.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	assert(_finished)
	await cutscene.actor_return_finished
	await get_tree().process_frame

	# The apparition never outlives its cutscene; the living actor is untouched.
	assert(not is_instance_valid(ghost) or ghost.is_queued_for_deletion())
	assert(is_instance_valid(living) and living.visible)
	print("[CutsceneGhostActorTest] ghost spawn, translucency, playback, and cleanup passed")
	get_tree().quit()
