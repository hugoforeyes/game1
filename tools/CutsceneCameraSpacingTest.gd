extends Node
## Regression QA for cutscene camera handoff and actor tile deconfliction.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")


class FakeActor:
	extends Node2D
	var anim_sprite: AnimatedSprite2D = null
	var camera: Camera2D = null
	var npc_data: Dictionary = {}
	var enemy_data: Dictionary = {}


func _ready() -> void:
	await _test_camera_handoff()
	await _test_actor_spacing()
	await _test_explicit_dialogue_target()
	print("[CutsceneCameraSpacingTest] camera handoff, actor spacing, and dialogue targets passed")
	get_tree().quit()


func _test_camera_handoff() -> void:
	var world := Node2D.new()
	add_child(world)
	var player := FakeActor.new()
	player.camera = Camera2D.new()
	player.camera.position_smoothing_enabled = true
	player.add_child(player.camera)
	player.global_position = Vector2(72, 72)
	world.add_child(player)
	player.camera.make_current()
	await get_tree().process_frame

	var cutscene = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene._world = world
	cutscene._player = player
	cutscene._player_camera = player.camera
	cutscene._camera = Camera2D.new()
	world.add_child(cutscene._camera)
	cutscene._camera.global_position = player.global_position
	cutscene._camera.make_current()

	# Move the player while its camera is inactive, reproducing the stale cached
	# center that used to send the cinematic camera back toward the origin.
	player.global_position = Vector2(504, 360)
	await cutscene._restore_player_camera()
	await get_tree().process_frame
	assert(player.camera.is_current())
	assert(cutscene._camera.global_position.is_equal_approx(player.global_position))
	assert(player.camera.get_screen_center_position().distance_to(player.global_position) < 1.0)
	cutscene.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_actor_spacing() -> void:
	var world := Node2D.new()
	add_child(world)
	var player := FakeActor.new()
	player.global_position = _tile_center(Vector2i(10, 10))
	world.add_child(player)
	var characters := Node2D.new()
	world.add_child(characters)

	var npc_a := _npc("npc_a", Vector2i(2, 2))
	var npc_b := _npc("npc_b", Vector2i(3, 2))
	var npc_c := _npc("npc_c", Vector2i(12, 10))
	characters.add_child(npc_a)
	characters.add_child(npc_b)
	characters.add_child(npc_c)

	var cutscene = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene._world = world
	cutscene._player = player
	cutscene._characters_root = characters
	cutscene._blocked_tiles = {}
	cutscene._actions = [
		{"type": "say", "actor": "npc_a"},
		{"type": "say", "actor": "npc_b"},
		{"type": "say", "actor": "npc_c"},
	]
	cutscene._start_tiles = {
		"player": {"x": 10, "y": 10},
		"npc_a": {"x": 12, "y": 10},
		"npc_b": {"x": 12, "y": 10},
		# npc_c intentionally missing: its live tile is already occupied by npc_a.
	}
	cutscene._prestage_actors()
	assert(_unique_tiles([player, npc_a, npc_b, npc_c]))

	# An authored move into npc_a's occupied tile must resolve beside it.
	var occupied_target := cutscene._tile_of(npc_a.global_position)
	await cutscene._do_move("npc_b", {"x": occupied_target.x, "y": occupied_target.y})
	assert(cutscene._tile_of(npc_b.global_position) != occupied_target)
	assert(_unique_tiles([player, npc_a, npc_b, npc_c]))

	# The real data also contains NPC moves aimed directly at the player tile.
	var player_target := cutscene._tile_of(player.global_position)
	await cutscene._do_move("npc_c", {"x": player_target.x, "y": player_target.y})
	assert(cutscene._tile_of(npc_c.global_position) != player_target)
	assert(_unique_tiles([player, npc_a, npc_b, npc_c]))
	cutscene.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _test_explicit_dialogue_target() -> void:
	var world := Node2D.new()
	add_child(world)
	var player := FakeActor.new()
	player.global_position = Vector2(32, 64)
	_add_direction_sprite(player)
	world.add_child(player)
	var characters := Node2D.new()
	world.add_child(characters)

	var previous := _npc("npc_previous", Vector2i(5, 2))
	_add_direction_sprite(previous)
	characters.add_child(previous)
	var speaker := _npc("npc_speaker", Vector2i(3, 2))
	_add_direction_sprite(speaker)
	characters.add_child(speaker)

	var cutscene = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene._player = player
	cutscene._characters_root = characters
	cutscene._last_speaker = "npc_previous"
	cutscene._face_pair("npc_speaker", "player")

	assert(speaker.anim_sprite.animation == "walk_left", "speaker animation: %s" % speaker.anim_sprite.animation)
	assert(player.anim_sprite.animation == "walk_right", "player animation: %s" % player.anim_sprite.animation)
	assert(previous.anim_sprite.animation == "walk_down", "previous animation: %s" % previous.anim_sprite.animation)
	cutscene.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _npc(id: String, tile: Vector2i) -> FakeActor:
	var actor := FakeActor.new()
	actor.npc_data = {"id": id}
	actor.global_position = _tile_center(tile)
	return actor


func _add_direction_sprite(actor: FakeActor) -> void:
	var frames := SpriteFrames.new()
	for direction in ["down", "up", "left", "right"]:
		var animation := "walk_%s" % direction
		frames.add_animation(animation)
		frames.add_frame(animation, GradientTexture1D.new())
	actor.anim_sprite = AnimatedSprite2D.new()
	actor.anim_sprite.sprite_frames = frames
	actor.anim_sprite.animation = "walk_down"
	actor.add_child(actor.anim_sprite)


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)


func _unique_tiles(actors: Array) -> bool:
	var seen: Dictionary = {}
	for actor in actors:
		var tile := Vector2i(
			int((actor as Node2D).global_position.x / GameManager.TILE_SIZE),
			int((actor as Node2D).global_position.y / GameManager.TILE_SIZE),
		)
		var key := "%d:%d" % [tile.x, tile.y]
		if seen.has(key):
			return false
		seen[key] = true
	return true
