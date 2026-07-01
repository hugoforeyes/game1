extends Node
## Scripted QA for the item-pickup persistence fix: drives the REAL
## Main._spawn_item_pickups (not a reimplementation) against synthetic catalog
## data, across two simulated zone (re)loads, to prove an already-collected
## pickup is skipped on reload while everything else's tile stays stable.

const MainScene := preload("res://scenes/world/Main.tscn")
const _FakePlayerScript := preload("res://tools/ItemPickupPersistenceQAFakePlayer.gd")

const ZONE_ID := "zone_qa_test"
const ITEM_ID := "item_qa_potion"


func _ready() -> void:
	GameManager.reset_combat_progress()
	GameManager.imported_scene_context = {"zone_id": ZONE_ID}
	InventoryManager.catalog = [
		{
			"id": ITEM_ID,
			"name": "Thuốc QA",
			"found_in": [ZONE_ID],
			"world_spawn_count": 3,
		},
	]

	var tile_context := {
		"map_tile_size": Vector2i(20, 20),
		"blocked_tiles": {},
	}

	# ── Load 1: nothing collected yet -> all 3 pickups spawn ───────────────────
	var main1: Node2D = MainScene.instantiate()
	add_child(main1)
	await get_tree().process_frame
	main1._spawn_item_pickups(tile_context)
	await get_tree().process_frame

	var pickups1 := _pickup_ids_in(main1)
	assert(pickups1.size() == 3, "first load must spawn all 3 pickups, got %d" % pickups1.size())
	var expected_ids := [
		"%s:%s:0" % [ZONE_ID, ITEM_ID], "%s:%s:1" % [ZONE_ID, ITEM_ID], "%s:%s:2" % [ZONE_ID, ITEM_ID],
	]
	for eid in expected_ids:
		assert(pickups1.has(eid), "missing expected pickup id %s" % eid)
	print("[ItemPickupQA] OK: first load spawns all 3 pickups with stable ids -> ", pickups1)

	# Record each pickup's world tile before "collecting" one, so we can prove the
	# OTHERS don't move on the next load.
	var tile_before := {}
	for child in main1.generated_props.get_children():
		var pid: Variant = child.get("pickup_id")
		if pid != null:
			tile_before[str(pid)] = child.global_position

	# ── Simulate collecting pickup #1 (the middle one) ──────────────────────────
	var target_id := "%s:%s:1" % [ZONE_ID, ITEM_ID]
	for child in main1.generated_props.get_children():
		if str(child.get("pickup_id")) == target_id:
			child._on_body_entered(_fake_player())
	await get_tree().process_frame

	assert(GameManager.is_item_pickup_collected(target_id), "GameManager must record the collected pickup id")
	print("[ItemPickupQA] OK: GameManager recorded collection of ", target_id)

	main1.queue_free()
	await get_tree().process_frame

	# ── Load 2: same zone reloaded -> the collected one must NOT respawn ───────
	var main2: Node2D = MainScene.instantiate()
	add_child(main2)
	await get_tree().process_frame
	main2._spawn_item_pickups(tile_context)
	await get_tree().process_frame

	var pickups2 := _pickup_ids_in(main2)
	assert(pickups2.size() == 2, "second load must skip the collected pickup, got %d" % pickups2.size())
	assert(not pickups2.has(target_id), "collected pickup must not respawn")
	print("[ItemPickupQA] OK: second load skips the collected pickup -> ", pickups2)

	# The two SURVIVING pickups must be at the exact same tiles as load 1 (RNG
	# sequence must stay stable even though one draw was skipped from spawning).
	for child in main2.generated_props.get_children():
		var raw_pid: Variant = child.get("pickup_id")
		if raw_pid != null:
			var pid := str(raw_pid)
			assert(tile_before.has(pid), "unexpected pickup id on reload: %s" % pid)
			assert(child.global_position == tile_before[pid], "pickup %s moved position across reloads: %s vs %s" % [pid, child.global_position, tile_before[pid]])
	print("[ItemPickupQA] OK: surviving pickups kept identical positions across reloads")

	print("[ItemPickupQA] ALL CHECKS PASSED")
	get_tree().quit()


func _pickup_ids_in(main_node: Node) -> Array:
	var ids: Array = []
	for child in main_node.generated_props.get_children():
		var pid: Variant = child.get("pickup_id")
		if pid != null:
			ids.append(str(pid))
	return ids


func _fake_player() -> Node2D:
	return _FakePlayerScript.new()
