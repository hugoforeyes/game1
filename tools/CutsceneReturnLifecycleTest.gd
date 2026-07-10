extends Node
## End-to-end regression QA for the non-blocking post-cutscene NPC walk home.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")
const PlayerScene := preload("res://scenes/characters/Player.tscn")
const NPCScene := preload("res://scenes/npc/NPC.tscn")


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)
	var characters := Node2D.new()
	characters.name = "GeneratedCharacters"
	world.add_child(characters)

	var player := PlayerScene.instantiate() as CharacterBody2D
	world.add_child(player)
	await get_tree().process_frame
	player.global_position = _tile_center(Vector2i(5, 2))
	player.face_direction("right")
	player.camera.make_current()
	var player_layer := player.collision_layer
	var player_mask := player.collision_mask

	var npc := NPCScene.instantiate() as CharacterBody2D
	characters.add_child(npc)
	await get_tree().process_frame
	var home_tile := Vector2i(3, 2)
	npc.setup({
		"id": "npc_return_test",
		"name": "Nira",
		"position_tile": {"x": home_tile.x, "y": home_tile.y},
		"movement": {
			"type": "fixed",
			"speed": 18,
			"anchor_tile": {"x": home_tile.x, "y": home_tile.y},
		},
		"interaction": {
			"enabled": true,
			"proximity_radius_tiles": 3.0,
			"options": ["Talk"],
		},
	}, {
		"player": player,
		"map_tile_size": Vector2i(12, 8),
		"blocked_tiles": {},
		"occupied_tiles": {},
		"tile_metadata": {},
	})
	var npc_layer := npc.collision_layer
	var npc_mask := npc.collision_mask
	assert(is_equal_approx(npc.speed, 36.0), "authored speed 18 should scale to the normal 36 px/s runtime speed")

	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	var authored_runtime_speed: float = float(npc.get("speed"))
	npc.set("speed", 0.0)
	assert(is_equal_approx(cutscene._normal_return_speed(npc), 36.0), "fixed NPCs need the normal fallback speed to return home")
	npc.set("speed", authored_runtime_speed)
	cutscene.play(
		[
			{"type": "face", "actor": "player", "direction": "left"},
			{"type": "move", "actor": "npc_return_test", "to": {"x": 4, "y": 2}},
		],
		world,
		player,
		characters,
		{
			"player": {"x": 5, "y": 2},
			"npc_return_test": {"x": home_tile.x, "y": home_tile.y},
		},
	)

	await cutscene.cutscene_finished
	var home_position := _tile_center(home_tile)
	assert(npc.global_position.distance_to(home_position) > GameManager.TILE_SIZE * 0.75, "release must happen before NPC reaches home")
	assert(not GameManager.ui_blocking_input, "world input should unlock as walk-home starts")
	assert(player.camera.is_current(), "player camera should be current on the release frame")
	assert(player.get_facing_vector() == Vector2.LEFT, "cutscene visual facing must sync to interaction-facing logic")
	assert(player.collision_layer == player_layer and player.collision_mask == player_mask, "player collision should restore immediately")
	assert(npc.collision_layer == 0 and npc.collision_mask == 0, "moving NPC collision stays disabled until arrival")
	assert(npc.is_scripted_return_active(), "NPC should use interaction-only scripted return mode")
	assert(not cutscene._skip_hint.visible, "ESC hint must disappear at gameplay release")
	assert(not cutscene.is_processing_unhandled_input(), "finished cutscene must no longer consume ESC/Enter")

	# The normal interaction pipeline remains live while the tween owns movement.
	# Drive one real NPC physics tick and the real interaction arbiter directly;
	# headless idle frames are not guaranteed to advance a physics tick.
	npc._physics_process(1.0 / 60.0)
	WorldInteractionManager._process(0.0)
	assert(WorldInteractionManager.is_active(npc, "npc"), "NPC should be interactable while walking home")
	# A broad NarrativeState refresh must not turn collision/AI back on mid-return.
	npc.apply_actor_state({})
	assert(npc.collision_layer == 0 and npc.is_scripted_return_active())

	# Runtime speed is 36 px/s, so half a second should cover about 18 px — not
	# the old cinematic 144 px/s (72 px in the same interval).
	var before_walk := npc.global_position
	await get_tree().create_timer(0.5).timeout
	var normal_speed_distance := before_walk.distance_to(npc.global_position)
	assert(normal_speed_distance > 12.0 and normal_speed_distance < 26.0, "walk-home should use normal NPC speed; moved %.2f px" % normal_speed_distance)

	# Opening a dialogue/menu sets ui_blocking_input. The background coordinator
	# must pause both position and walk animation, then resume afterward.
	GameManager.ui_blocking_input = true
	await get_tree().process_frame
	await get_tree().process_frame
	var paused_position := npc.global_position
	await get_tree().create_timer(0.25).timeout
	assert(npc.global_position.distance_to(paused_position) < 0.5, "NPC return tween should pause during blocking UI")
	assert(not npc.anim_sprite.is_playing(), "NPC must not walk in place during blocking UI")
	GameManager.ui_blocking_input = false
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	assert(npc.global_position.distance_to(paused_position) > 2.0, "NPC return tween should resume after UI closes")

	await cutscene.actor_return_finished
	assert(npc.global_position.distance_to(home_position) < 1.0)
	assert(not npc.is_scripted_return_active())
	assert(npc.collision_layer == npc_layer and npc.collision_mask == npc_mask, "NPC collision should restore on arrival")

	# A dialogue outcome that changes a returning NPC into a corpse is
	# authoritative: stale cutscene snapshots must not revive physics/collision.
	var state_guard: CanvasLayer = CutscenePlayerScript.new()
	add_child(state_guard)
	npc.apply_actor_state({})
	npc.set_scripted_return_active(true)
	state_guard._collision_state[npc] = {"layer": npc_layer, "mask": npc_mask}
	npc.apply_actor_state({"state": "dead", "presentation": "corpse"})
	state_guard._finalize_walked_actor(npc, npc.anim_sprite)
	assert(not npc.is_physics_processing())
	assert(npc.collision_layer == 0 and npc.collision_mask == 0)
	assert(not state_guard._collision_state.has(npc))
	state_guard.queue_free()
	WorldInteractionManager.clear_owner(npc)
	GameManager.ui_blocking_input = false
	print("[CutsceneReturnLifecycleTest] early release, normal speed, interaction, pause, and cleanup passed")
	get_tree().quit()


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
