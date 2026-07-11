extends Node
## Regression: enemies released by a cutscene walk home under EnemyController;
## they are never teleported by CutscenePlayer.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")
const PlayerScene := preload("res://scenes/characters/Player.tscn")
const EnemyScene := preload("res://scenes/enemies/Enemy.tscn")

func _ready() -> void:
	var world := Node2D.new()
	add_child(world)
	var characters := Node2D.new()
	world.add_child(characters)

	var player := PlayerScene.instantiate() as CharacterBody2D
	world.add_child(player)
	await get_tree().process_frame
	player.global_position = _tile_center(Vector2i(9, 6))
	player.camera.make_current()

	var enemy := EnemyScene.instantiate() as CharacterBody2D
	characters.add_child(enemy)
	await get_tree().process_frame
	var home_tile := Vector2i(2, 2)
	enemy.setup({
		"id": "enemy_return_test",
		"spawn": {
			"position_tile": {"x": home_tile.x, "y": home_tile.y},
			"patrol_radius": 1,
			"aggro_radius": 1.0,
		},
	}, {
		"player": player,
		"map_tile_size": Vector2i(12, 8),
		"blocked_tiles": {"3:2": true, "4:2": true},
	})
	var enemy_layer := enemy.collision_layer
	var enemy_mask := enemy.collision_mask
	var home_position := _tile_center(home_tile)

	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene.play(
		[{"type": "move", "actor": "enemy_return_test", "to": {"x": 5, "y": 2}}],
		world,
		player,
		characters,
		{"player": {"x": 9, "y": 6}, "enemy_return_test": {"x": 2, "y": 2}},
	)
	await cutscene.cutscene_finished
	assert(enemy.is_returning_home(), "EnemyController must own post-cutscene return")
	assert(enemy.global_position.distance_to(home_position) > GameManager.TILE_SIZE * 2.0, "enemy must not teleport home on release")
	assert(enemy.collision_layer == enemy_layer and enemy.collision_mask == enemy_mask, "enemy return uses normal collision")

	var before := enemy.global_position
	await get_tree().create_timer(0.25).timeout
	var moved := before.distance_to(enemy.global_position)
	assert(moved > 4.0 and moved < 16.0, "enemy should walk at normal speed; moved %.2f px" % moved)

	var deadline := Time.get_ticks_msec() + 12000
	while enemy.is_returning_home() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not enemy.is_returning_home(), "enemy should finish its grid return path; pos=%s path=%s index=%d" % [enemy.global_position, enemy._return_path, enemy._return_path_index])
	assert(enemy.global_position.distance_to(home_position) < 2.0)
	print("[CutsceneEnemyReturnTest] autonomous enemy return, speed, and collision passed")
	get_tree().quit()

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
