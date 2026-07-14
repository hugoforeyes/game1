extends Node
## Focused regression test for independent action-log TTL, animated removal,
## burst-cap dropping, and teardown safety.
## Run:
## godot --headless --path . res://scenes/dev/BattleLogTtlQATest.tscn

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")

var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[BattleLogTTL] FAIL: %s" % message)


func _ready() -> void:
	var battle: CanvasLayer = BattleSceneScript.new()
	add_child(battle)
	battle._load_ui_kit()
	battle._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame

	battle._say("Aaa")
	battle._say("A deliberately long action-history line that wraps without affecting another entry.")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(battle._battle_log_entries.size() == 2, "two messages must own two rows")

	var first: Dictionary = battle._battle_log_entries[0]
	var second: Dictionary = battle._battle_log_entries[1]
	var first_root: Control = first["root"]
	var second_root: Control = second["root"]
	var first_height_before := first_root.custom_minimum_size.y
	var second_y_before := second_root.position.y
	_check(first_root != second_root, "entries must not share a visual node")
	_check(
		second_root.custom_minimum_size.y > first_root.custom_minimum_size.y,
		"wrapped text must receive its own measured row height",
	)

	# Shorten only the first row's timer to exercise the real automatic timeout.
	var first_timer: Timer = first["timer"]
	first_timer.stop()
	first_timer.wait_time = 0.05
	first_timer.start()
	await get_tree().create_timer(0.12).timeout
	_check(bool(first.get("removing", false)), "expired entry must enter removal state")
	_check(first_root.modulate.a < 1.0, "expired entry must fade independently")
	_check(
		first_root.custom_minimum_size.y < first_height_before,
		"expired entry height must collapse to scroll remaining rows",
	)
	await get_tree().create_timer(0.16).timeout
	_check(battle._battle_log_entries.size() == 1, "expired row must leave the model")
	_check(second_root.position.y < second_y_before, "remaining row must scroll upward")

	# Burst traffic may drop old history, but may never exceed the UI cap or let
	# a removed Timer later target a newer row.
	for index in range(10):
		battle._say("Burst entry %d" % index)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(
		battle._battle_log_entries.size() == BattleSceneScript.MAX_BATTLE_LOG_ENTRIES,
		"burst history must stay at the configured cap",
	)
	_check(
		int(battle._battle_log_entries[0]["id"]) < int(battle._battle_log_entries[-1]["id"]),
		"retained entries must preserve append order",
	)
	if OS.get_environment("BATTLE_LOG_TTL_SHOT") == "1" and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("/tmp/battle_log_ttl_qa.png")

	# Several simultaneous expirations must remove by stable ID, not stale index.
	var expiring_ids: Array[int] = []
	for index in range(3):
		expiring_ids.append(int(battle._battle_log_entries[index]["id"]))
	for entry_id in expiring_ids:
		battle._expire_battle_log_entry(entry_id)
	await get_tree().create_timer(BattleSceneScript.BATTLE_LOG_EXIT_DURATION + 0.08).timeout
	_check(
		battle._battle_log_entries.size() == BattleSceneScript.MAX_BATTLE_LOG_ENTRIES - 3,
		"simultaneous expiry must remove exactly the requested rows",
	)

	battle.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("[BattleLogTTL] ALL CHECKS PASSED")
	else:
		push_error("[BattleLogTTL] %d CHECK(S) FAILED" % _failures)
	get_tree().quit(_failures)
