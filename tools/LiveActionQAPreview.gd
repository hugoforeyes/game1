extends Node
## Scripted QA for the REAL-TIME ambient live-action system: drives the REAL
## NPCController / EnemyController / LiveActionDirector (no reimplementation)
## through all four stage verbs — chase, standoff, sentry, shuttle — and proves
## for each one that the show overrides normal movement while gameplay runs,
## that its end condition fires, and that every surviving actor walks back to
## its pre-show position and resumes normal behavior.
##
## Run: Godot --headless --path GameV1 res://tools/LiveActionQAPreview.tscn

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")
const LiveActionDirectorScript := preload("res://scripts/world/LiveActionDirector.gd")

const MAP := Vector2i(40, 40)
const HOME_EPSILON_PX := 10.0

var _world: Node2D
var _characters: Node2D
var _player: CharacterBody2D
var _failures: Array[String] = []


func _ready() -> void:
	Engine.time_scale = 5.0
	GameManager.reset_combat_progress()
	GameManager.ui_blocking_input = false

	_world = Node2D.new()
	add_child(_world)
	_characters = Node2D.new()
	_world.add_child(_characters)
	_player = CharacterBody2D.new()
	_player.global_position = _tile_px(Vector2i(35, 35))  # far away: never interferes
	_world.add_child(_player)

	await _phase_chase()
	await _phase_standoff()
	await _phase_sentry()
	await _phase_shuttle()

	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("[LiveActionQA] ALL PHASES OK (chase, standoff, sentry, shuttle)")
	else:
		for failure in _failures:
			printerr("[LiveActionQA] FAIL: ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# ── phases ──────────────────────────────────────────────────────────────────────

func _phase_chase() -> void:
	print("[LiveActionQA] ── phase: chase")
	var victim := _spawn_npc("npc_qa_victim", Vector2i(10, 10))
	var hunter_a := _spawn_enemy("enemy_qa_hunter", Vector2i(14, 10))
	var hunter_b := _spawn_enemy("enemy_qa_hunter__02", Vector2i(14, 12))
	var victim_origin: Vector2 = victim.global_position
	var director := _mount_director([{
		"id": "qa_chase", "kind": "chase",
		"target_npc_id": "npc_qa_victim",
		"pursuer_enemy_ids": ["enemy_qa_hunter", "enemy_qa_hunter__02"],
		"area": {"center_tile": {"x": 10, "y": 10}, "radius_tiles": 4},
		"speeds": {"target_tiles_per_sec": 2.4, "pursuer_tiles_per_sec": 2.05},
		"catch_distance_tiles": 0.9,
		"catch_behavior": {"outcome": "cower", "hold_seconds": 1.0},
		"start_delay_seconds": 0.2,
		"ends_when": {"player_talks_to_target": true, "story_ref_reached": "", "timeout_seconds": 0},
	}])

	await _run_sim(3.0)
	_check(victim.is_in_live_action(), "chase: victim must be in live action")
	_check(hunter_a.is_in_live_action() and hunter_b.is_in_live_action(),
		"chase: both hunters must be in live action")
	_check(victim.global_position.distance_to(victim_origin) > 4.0
		or not victim.live_action_idle(),
		"chase: victim must be moving, not standing at home")

	# Defeat hunter A (battle victory frees the node) — the show must continue.
	hunter_a.queue_free()
	await _run_sim(1.5)
	_check(victim.is_in_live_action(), "chase: show continues while one hunter lives")
	_check(not GameManager.is_live_action_ended("qa_chase"), "chase: not ended early")

	# Defeat hunter B — "một trong những actor bị sao đó" resolves the show.
	hunter_b.queue_free()
	await _run_sim(1.5)
	_check(GameManager.is_live_action_ended("qa_chase"), "chase: ends when all hunters gone")
	_check(not victim.is_in_live_action(), "chase: victim released from live action")
	await _wait_actor_home(victim, victim_origin, 20.0, "chase victim")
	_teardown(director)


func _phase_standoff() -> void:
	print("[LiveActionQA] ── phase: standoff")
	var holder := _spawn_npc("npc_qa_holder", Vector2i(10, 10))
	var brute_a := _spawn_enemy("enemy_qa_brute", Vector2i(16, 10))
	var brute_b := _spawn_enemy("enemy_qa_brute__02", Vector2i(16, 12))
	var brute_a_origin: Vector2 = brute_a.global_position
	var holder_origin: Vector2 = holder.global_position
	var director := _mount_director([{
		"id": "qa_standoff", "kind": "standoff",
		"holder_npc_ids": ["npc_qa_holder"],
		"aggressor_enemy_ids": ["enemy_qa_brute", "enemy_qa_brute__02"],
		"gap_tiles": 3,
		"area": {"center_tile": {"x": 13, "y": 10}, "radius_tiles": 5},
		"speeds": {"target_tiles_per_sec": 2.4, "pursuer_tiles_per_sec": 2.05},
		"start_delay_seconds": 0.2,
		"ends_when": {"player_talks_to_target": true, "story_ref_reached": "", "timeout_seconds": 0},
	}])

	# Watch the confrontation for a while: sides must take posts, and at least one
	# feint lunge must bring an aggressor meaningfully closer to the holder.
	var min_brute_distance := INF
	var elapsed := 0.0
	while elapsed < 9.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		for brute in [brute_a, brute_b]:
			if is_instance_valid(brute):
				min_brute_distance = minf(
					min_brute_distance,
					(brute as Node2D).global_position.distance_to(holder.global_position),
				)
	_check(holder.is_in_live_action(), "standoff: holder in live action")
	_check(brute_a.is_in_live_action(), "standoff: aggressor in live action")
	var tile := float(GameManager.TILE_SIZE)
	_check(brute_a.global_position.distance_to(brute_a_origin) > 1.0 * tile,
		"standoff: aggressor left its spawn for its post")
	_check(min_brute_distance < 2.6 * tile,
		"standoff: a lunge must close in on the holder (min %.1f px)" % min_brute_distance)
	_check(min_brute_distance > 0.4 * tile,
		"standoff: lunge must stop short of touching the holder")

	# Peaceful intervention: the player talks to the holder.
	QuestManager.npc_talked.emit("npc_qa_holder")
	await _run_sim(1.0)
	_check(GameManager.is_live_action_ended("qa_standoff"), "standoff: talk ends the show")
	await _wait_actor_home(holder, holder_origin, 20.0, "standoff holder")
	await _wait_actor_home(brute_a, brute_a_origin, 20.0, "standoff aggressor")
	_teardown(director)


func _phase_sentry() -> void:
	print("[LiveActionQA] ── phase: sentry")
	var protected := _spawn_npc("npc_qa_protected", Vector2i(10, 10), "fixed")
	var guard_a := _spawn_enemy("enemy_qa_guard", Vector2i(13, 10))
	var guard_b := _spawn_enemy("enemy_qa_guard__02", Vector2i(7, 10))
	var director := _mount_director([{
		"id": "qa_sentry", "kind": "sentry",
		"sentry_enemy_ids": ["enemy_qa_guard", "enemy_qa_guard__02"],
		"protected_npc_id": "npc_qa_protected",
		"area": {"center_tile": {"x": 10, "y": 10}, "radius_tiles": 3},
		"speeds": {"target_tiles_per_sec": 1.8, "pursuer_tiles_per_sec": 1.6},
		"start_delay_seconds": 0.2,
		"ends_when": {"player_talks_to_target": true, "story_ref_reached": "", "timeout_seconds": 0},
	}])

	await _run_sim(2.0)
	var anchor: Vector2 = protected.global_position
	var ring_samples := 0
	var ring_ok := 0
	# Integrate the UNWRAPPED angular travel — a guard that laps the ring whole
	# times would alias to ~0 in a naive start-vs-end angle comparison.
	var previous_angle: float = (guard_a.global_position - anchor).angle()
	var traveled_rad := 0.0
	var elapsed := 0.0
	while elapsed < 7.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(guard_a):
			break
		var current_angle: float = (guard_a.global_position - anchor).angle()
		traveled_rad += wrapf(current_angle - previous_angle, -PI, PI)
		previous_angle = current_angle
		if fmod(elapsed, 0.5) < 1.0 / 60.0:
			ring_samples += 1
			var distance_tiles: float = guard_a.global_position.distance_to(anchor) / float(GameManager.TILE_SIZE)
			if distance_tiles >= 1.2 and distance_tiles <= 5.0:
				ring_ok += 1
	_check(not protected.is_in_live_action(),
		"sentry: the protected NPC keeps its normal life (never controlled)")
	_check(guard_a.is_in_live_action(), "sentry: guard in live action")
	_check(ring_ok >= ring_samples - 2,
		"sentry: guard stays on the ring (%d/%d samples)" % [ring_ok, ring_samples])
	_check(absf(traveled_rad) > 1.5,
		"sentry: the ring must rotate (traveled %.2f rad)" % traveled_rad)

	guard_a.queue_free()
	guard_b.queue_free()
	await _run_sim(1.5)
	_check(GameManager.is_live_action_ended("qa_sentry"), "sentry: ends when guards fall")
	_teardown(director)


func _phase_shuttle() -> void:
	print("[LiveActionQA] ── phase: shuttle")
	var carrier := _spawn_npc("npc_qa_carrier", Vector2i(8, 10))
	var medic := _spawn_npc("npc_qa_medic", Vector2i(16, 10), "fixed")
	var carrier_origin: Vector2 = carrier.global_position
	var director := _mount_director([{
		"id": "qa_shuttle", "kind": "shuttle",
		"carrier_npc_ids": ["npc_qa_carrier"],
		"to_npc_id": "npc_qa_medic",
		"pause_seconds": 0.6,
		"area": {"center_tile": {"x": 12, "y": 10}, "radius_tiles": 5},
		"speeds": {"target_tiles_per_sec": 2.4, "pursuer_tiles_per_sec": 2.05},
		"start_delay_seconds": 0.2,
		"ends_when": {"player_talks_to_target": true, "story_ref_reached": "", "timeout_seconds": 0},
	}])

	# One full round trip: reach the medic, then come back near home.
	var reached_b := false
	var returned_a := false
	var tile := float(GameManager.TILE_SIZE)
	var elapsed := 0.0
	while elapsed < 18.0 and not (reached_b and returned_a):
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		var to_b: float = carrier.global_position.distance_to(medic.global_position) / tile
		var to_a: float = carrier.global_position.distance_to(carrier_origin) / tile
		if to_b <= 1.8:
			reached_b = true
		if reached_b and to_a <= 1.8:
			returned_a = true
	_check(carrier.is_in_live_action(), "shuttle: carrier in live action")
	_check(not medic.is_in_live_action(), "shuttle: anchor NPC keeps its normal life")
	_check(reached_b, "shuttle: carrier must reach the destination NPC")
	_check(returned_a, "shuttle: carrier must come back near its origin")

	QuestManager.npc_talked.emit("npc_qa_carrier")
	await _run_sim(1.0)
	_check(GameManager.is_live_action_ended("qa_shuttle"), "shuttle: talk ends the show")
	await _wait_actor_home(carrier, carrier_origin, 20.0, "shuttle carrier")
	_teardown(director)


# ── harness helpers ─────────────────────────────────────────────────────────────

func _spawn_npc(npc_id: String, tile: Vector2i, movement_type: String = "wander") -> CharacterBody2D:
	var npc: CharacterBody2D = NPC_SCENE.instantiate() as CharacterBody2D
	_characters.add_child(npc)
	npc.setup({
		"id": npc_id,
		"name": npc_id,
		"sprite_sheet_file": "",
		"position_tile": {"x": tile.x, "y": tile.y},
		"movement": {"type": movement_type, "radius_tiles": 2, "speed": 18.0,
			"wait_min": 0.4, "wait_max": 0.9},
		"interaction": {"enabled": false},
	}, {
		"map_tile_size": MAP,
		"blocked_tiles": {},
		"occupied_tiles": {},
		"tile_metadata": {},
		"actor_state": {},
		"player": _player,
	})
	return npc


func _spawn_enemy(enemy_id: String, tile: Vector2i) -> CharacterBody2D:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	_characters.add_child(enemy)
	enemy.setup({
		"id": enemy_id,
		"name": enemy_id,
		"sprite_sheet_file": "",
		"spawn": {"position_tile": {"x": tile.x, "y": tile.y}, "patrol_radius": 2, "aggro_radius": 0.0},
	}, {
		"map_tile_size": MAP,
		"blocked_tiles": {},
		"player": _player,
	})
	return enemy


func _mount_director(live_actions: Array) -> Node:
	var director: LiveActionDirector = LiveActionDirectorScript.new()
	add_child(director)
	director.setup(_player, _characters, live_actions)
	return director


func _run_sim(seconds: float) -> void:
	for _i in range(int(ceil(seconds * 60.0))):
		await get_tree().physics_frame


func _wait_actor_home(actor: Node2D, origin: Vector2, budget_seconds: float, label: String) -> void:
	# Success = the actor passes back through its pre-show spot. It legitimately
	# RESUMES NORMAL BEHAVIOR right after (wandering away from that exact pixel),
	# so this asserts "touched home", never "parked at home".
	var elapsed := 0.0
	var best := INF
	while elapsed < budget_seconds:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if not is_instance_valid(actor):
			_failures.append("%s: actor freed while walking home" % label)
			return
		best = minf(best, actor.global_position.distance_to(origin))
		if best <= HOME_EPSILON_PX:
			print("[LiveActionQA] %s back home after %.1fs (sim)" % [label, elapsed])
			return
	_failures.append("%s: did not return home within %.0fs (closest %.1fpx)" % [
		label, budget_seconds, best,
	])


func _tile_px(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LiveActionQA] ok: ", message)
	else:
		_failures.append(message)


func _teardown(director: Node) -> void:
	if is_instance_valid(director):
		director.queue_free()
	for child in _characters.get_children():
		child.queue_free()
	await _run_sim(0.2)
