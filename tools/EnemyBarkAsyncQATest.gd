extends Node
## Runtime QA for independent per-enemy, non-blocking combat barks.

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")

var _failures := 0
var _picked_action := ""


func _ready() -> void:
	var battle: Variant = _make_battle_harness()
	var foe_a: Dictionary = _make_foe(battle, "foe_a", Vector2(350.0, 170.0))
	var foe_b: Dictionary = _make_foe(battle, "foe_b", Vector2(700.0, 170.0))
	var foes: Array[Dictionary] = [foe_a, foe_b]
	battle._foes = foes
	battle._ui_mode = 3 # UiMode.MENU
	var menu_ids: Array[String] = ["attack"]
	battle._menu_ids = menu_ids
	battle._menu_index = 0

	# Enqueue returns synchronously. No active node exists until the deferred worker,
	# and the player's current interaction state is untouched.
	battle._enemy_say(foe_a, "Aaa")
	battle._enemy_say(foe_b, "Đau quá")
	_check(battle._ui_mode == 3, "enqueueing bark must not change MENU input mode")
	_check(battle._enemy_bark_channels.size() == 2, "each enemy needs an independent channel")
	for raw_channel in battle._enemy_bark_channels.values():
		var channel: Dictionary = raw_channel as Dictionary
		_check(channel.get("active") == null, "worker must start deferred, after the caller continues")

	# Same-enemy lines are bounded and serialized instead of stacking bubbles.
	battle._enemy_say(foe_a, "First")
	battle._enemy_say(foe_a, "Second")
	battle._enemy_say(foe_a, "Third")
	battle._enemy_say(foe_a, "Newest")
	var queued_a: Dictionary = battle._enemy_bark_channels["foe_a"] as Dictionary
	_check((queued_a.get("pending", []) as Array).size() == battle.MAX_PENDING_BARKS_PER_ENEMY,
		"same-enemy pending queue must stay bounded")

	await get_tree().process_frame
	await get_tree().process_frame
	var channel_a: Dictionary = battle._enemy_bark_channels["foe_a"] as Dictionary
	var channel_b: Dictionary = battle._enemy_bark_channels["foe_b"] as Dictionary
	var active_a: Control = channel_a.get("active") as Control
	var active_b: Control = channel_b.get("active") as Control
	_check(active_a != null and active_b != null, "different enemies must display barks concurrently")
	_check(active_a != active_b, "enemy channels must not share one bubble instance")
	_check(active_a.mouse_filter == Control.MOUSE_FILTER_IGNORE, "bubble must never intercept pointer input")
	_check(battle._ui_mode == 3, "active playback must leave MENU input mode unchanged")

	# The authored pointer terminates on the near hair/shoulder edge, not face centre.
	for active in [active_a, active_b]:
		if active == null:
			continue
		var face_center: Vector2 = active.get_meta("speaker_face_center", Vector2.ZERO)
		var anchor: Vector2 = active.get_meta("speaker_anchor", Vector2.ZERO)
		_check(absf(anchor.x - face_center.x) >= 20.0,
			"speaking enemy pointer must keep a face-clear horizontal offset")

	# Enter still belongs to the menu while barks are visible; it does not dismiss or
	# advance any bubble.
	battle._menu_picked.connect(func(id: String) -> void: _picked_action = id, CONNECT_ONE_SHOT)
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	battle._unhandled_input(accept)
	_check(_picked_action == "attack", "Enter must continue selecting the player's action")
	_check(battle._enemy_bark_channels.size() == 2, "Enter must not dismiss enemy bark channels")

	# Explicit teardown cancels tweens/signals and releases every active channel.
	battle._shutdown_enemy_barks()
	await get_tree().process_frame
	_check(battle._enemy_bark_channels.is_empty(), "teardown must clear every bark channel")
	battle.queue_free()
	await get_tree().process_frame

	# Natural compact playback also self-removes without user interaction.
	var natural: Variant = _make_battle_harness()
	var natural_foe: Dictionary = _make_foe(natural, "natural", Vector2(520.0, 180.0))
	var natural_foes: Array[Dictionary] = [natural_foe]
	natural._foes = natural_foes
	natural._enemy_say(natural_foe, "Aaa")
	await get_tree().create_timer(2.1).timeout
	_check(natural._enemy_bark_channels.is_empty(), "compact bark must finish and clean itself automatically")
	natural._shutdown_enemy_barks()
	natural.queue_free()
	await get_tree().process_frame

	if _failures == 0:
		print("[EnemyBarkAsyncQA] ALL CHECKS PASSED")
	else:
		push_error("[EnemyBarkAsyncQA] %d CHECK(S) FAILED" % _failures)
	get_tree().quit(_failures)


func _make_battle_harness() -> Variant:
	var battle: Variant = BattleSceneScript.new()
	add_child(battle)
	battle._design = Control.new()
	battle._design.size = Vector2(960.0, 540.0)
	battle.add_child(battle._design)
	return battle


func _make_foe(battle: Variant, id: String, position: Vector2) -> Dictionary:
	var holder := Control.new()
	holder.position = position
	holder.size = Vector2(180.0, 220.0)
	battle._design.add_child(holder)
	return {
		"id": id,
		"name": id,
		"ui": {"holder": holder, "size": holder.size},
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[EnemyBarkAsyncQA] %s" % message)
