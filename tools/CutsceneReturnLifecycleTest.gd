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
	cutscene.play(
		[
			{"type": "face", "actor": "player", "direction": "left"},
			{"type": "move", "actor": "npc_return_test", "to": {"x": 3, "y": 4}},
		],
		world,
		player,
		characters,
		{
			"player": {"x": 5, "y": 2},
			"npc_return_test": {"x": home_tile.x, "y": home_tile.y},
		},
	)
	# NPCController continues receiving physics ticks while input is blocked, but
	# it must not overwrite the vertical animation owned by CutscenePlayer.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(npc.anim_sprite.animation == "walk_down", "cutscene movement direction must win over stale NPC facing")
	assert(npc.anim_sprite.is_playing(), "cutscene walk animation must not be paused by NPCController")

	await cutscene.cutscene_finished
	var home_position := _tile_center(home_tile)
	assert(npc.global_position.distance_to(home_position) > GameManager.TILE_SIZE * 0.75, "release must happen before NPC reaches home")
	assert(not GameManager.ui_blocking_input, "world input should unlock as walk-home starts")
	assert(player.camera.is_current(), "player camera should be current on the release frame")
	assert(player.get_facing_vector() == Vector2.LEFT, "cutscene visual facing must sync to interaction-facing logic")
	assert(player.collision_layer == player_layer and player.collision_mask == player_mask, "player collision should restore immediately")
	assert(npc.collision_layer == npc_layer and npc.collision_mask == npc_mask, "returning NPC must use normal collision")
	assert(npc.is_returning_home(), "NPCController should own the return-home state")
	assert(npc.is_physics_processing(), "return-home must use the normal NPC physics loop")
	assert(not cutscene._skip_hint.visible, "ESC hint must disappear at gameplay release")
	assert(not cutscene.is_processing_unhandled_input(), "finished cutscene must no longer consume ESC/Enter")

	# The normal interaction pipeline remains live while the tween owns movement.
	# Drive one real NPC physics tick and the real interaction arbiter directly;
	# headless idle frames are not guaranteed to advance a physics tick.
	npc._physics_process(1.0 / 60.0)
	WorldInteractionManager._process(0.0)
	assert(WorldInteractionManager.is_active(npc, "npc"), "NPC should be interactable while walking home")
	WorldInteractionManager.clear_owner(npc)
	npc._in_interaction_range = false
	npc._resume_return_home()
	# A broad NarrativeState refresh must preserve the autonomous return.
	npc.apply_actor_state({})
	assert(npc.collision_layer == npc_layer and npc.is_returning_home())

	# Runtime speed is 36 px/s, so half a second should cover about 18 px — not
	# the old cinematic 144 px/s (72 px in the same interval).
	var before_walk := npc.global_position
	await get_tree().create_timer(0.5).timeout
	var normal_speed_distance := before_walk.distance_to(npc.global_position)
	assert(normal_speed_distance > 12.0 and normal_speed_distance < 26.0, "walk-home should use normal NPC speed; moved %.2f px" % normal_speed_distance)

	# Blocking UI freezes this NPC through the same global gameplay rule as every
	# other NPC; no CutscenePlayer coordinator is involved.
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

	var return_deadline := Time.get_ticks_msec() + 5000
	while npc.is_returning_home() and Time.get_ticks_msec() < return_deadline:
		await get_tree().process_frame
	assert(not npc.is_returning_home(), "NPC should reach its saved destination")
	assert(npc.global_position.distance_to(home_position) < 1.0)
	assert(npc.collision_layer == npc_layer and npc.collision_mask == npc_mask, "NPC collision should restore on arrival")

	# Fixed/immobile NPCs may author speed=0. That ambient setting must survive,
	# while the one-off return task uses a safe fallback and still completes.
	npc.speed = 0.0
	var zero_speed_return: CanvasLayer = CutscenePlayerScript.new()
	add_child(zero_speed_return)
	zero_speed_return.play(
		[{"type": "move", "actor": "npc_return_test", "to": {"x": 4, "y": 2}}],
		world,
		player,
		characters,
		{"player": {"x": 5, "y": 2}, "npc_return_test": {"x": home_tile.x, "y": home_tile.y}},
	)
	await zero_speed_return.cutscene_finished
	var zero_before := npc.global_position
	await get_tree().create_timer(0.25).timeout
	assert(npc.global_position.distance_to(zero_before) > 4.0, "speed=0 NPC must move with the return fallback")
	var zero_deadline := Time.get_ticks_msec() + 4000
	while npc.is_returning_home() and Time.get_ticks_msec() < zero_deadline:
		await get_tree().process_frame
	assert(not npc.is_returning_home(), "speed=0 NPC must finish returning")
	assert(npc.global_position.distance_to(home_position) < 1.0)
	assert(is_zero_approx(npc.speed), "return fallback must not mutate authored ambient speed")

	# A queued follow-up cutscene may interrupt the walk without teleporting. It
	# inherits the original destination and reissues return-home when it releases.
	var interrupted_return: CanvasLayer = CutscenePlayerScript.new()
	add_child(interrupted_return)
	interrupted_return.play(
		[{"type": "move", "actor": "npc_return_test", "to": {"x": 4, "y": 2}}],
		world,
		player,
		characters,
		{"player": {"x": 5, "y": 2}, "npc_return_test": {"x": home_tile.x, "y": home_tile.y}},
	)
	await interrupted_return.cutscene_finished
	assert(npc.is_returning_home(), "test setup needs an autonomous return")
	await get_tree().process_frame
	var position_before_followup := npc.global_position
	var followup: CanvasLayer = CutscenePlayerScript.new()
	add_child(followup)
	followup.play(
		[{"type": "face", "actor": "npc_return_test", "direction": "left"}],
		world,
		player,
		characters,
	)
	await followup.cutscene_finished
	assert(npc.is_returning_home(), "follow-up cutscene must resume the saved destination")
	assert(npc.global_position.distance_to(home_position) > 1.0, "follow-up cutscene must not snap the NPC home")
	assert(npc.global_position.distance_to(position_before_followup) < GameManager.TILE_SIZE * 0.25)
	assert(npc.collision_layer == npc_layer and npc.collision_mask == npc_mask)
	await followup.actor_return_finished
	await get_tree().process_frame

	# A dialogue outcome that changes a returning NPC into a corpse is
	# authoritative: stale cutscene snapshots must not revive physics/collision.
	npc.apply_actor_state({})
	npc.return_home_to(home_position)
	npc.apply_actor_state({"state": "dead", "presentation": "corpse"})
	assert(not npc.is_physics_processing())
	assert(npc.collision_layer == 0 and npc.collision_mask == 0)
	assert(not npc.is_returning_home())
	WorldInteractionManager.clear_owner(npc)
	GameManager.ui_blocking_input = false
	print("[CutsceneReturnLifecycleTest] autonomous return, collision, interaction, chaining, and state cleanup passed")
	get_tree().quit()


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
