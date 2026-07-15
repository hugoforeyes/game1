extends Node
## Runtime QA for mandatory quest ceremonies, narrative lead-in projection,
## rapid-objective collapse, and standalone modal/cutscene/item priority.

const AnnouncementViewScript := preload("res://scripts/ui/AnnouncementView.gd")

var pending_narrative := false


func has_pending_narrative_playback() -> bool:
	return pending_narrative


func _ready() -> void:
	add_to_group("narrative_playback_owner")
	QuestManager.set_process(false)
	InventoryManager.set_process(false)
	InventoryManager._toast_queue.clear()
	InventoryManager._toast_busy = false
	GameManager.ui_blocking_input = true
	AnnouncementCenter.reset()
	QuestManager.reset()
	QuestManager.load_chapter_quests([_quest_fixture()])

	_test_mandatory_queue_and_content()
	_test_rapid_objective_collapse()
	_test_instant_completion_drops_stale_objective()
	await _test_standalone_priority_barriers()
	_test_battle_reward_quest_handoff()

	QuestManager.set_process(true)
	InventoryManager.set_process(true)
	print("[NotificationQueueTest] ceremony, collapse, priority, and battle-reward handoff passed")
	get_tree().quit()


func _test_mandatory_queue_and_content() -> void:
	var quest: Dictionary = QuestManager.quests[0] as Dictionary
	QuestManager._activate_quest(quest)

	# Even outside a conversation, quest + first objective go exclusively to the
	# full-screen ceremony queue. The old top-edge queue remains hint-only/empty.
	assert(QuestManager._toast_queue.is_empty())
	assert(AnnouncementCenter._queue.size() == 2)
	assert(str((AnnouncementCenter._queue[0] as Dictionary).get("kind", "")) == "new_quest")
	var objective_entry: Dictionary = AnnouncementCenter._queue[1] as Dictionary
	assert(str(objective_entry.get("kind", "")) == "objective")
	var objective_snapshot: Dictionary = objective_entry.get("objective", {}) as Dictionary
	assert(str(objective_snapshot.get("id", "")) == "o1")
	assert(str(objective_snapshot.get("narrative_lead_in", "")) == "Arlo's warning points toward the mist gate.")

	var presentation: CanvasLayer = AnnouncementViewScript.new()
	var content: Dictionary = presentation._content_for("objective", objective_entry)
	assert(str(content.get("title", "")) == "Reach the mist gate")
	assert(str(content.get("subtitle", "")) == "Arlo's warning points toward the mist gate.")
	assert(not str(content.get("subtitle", "")).contains("Ceremony Contract"),
		"objective subtitle must never fall back to the quest name")

	# A cutscene-delivered objective still receives its ceremony and its authored
	# lead-in. Missing legacy content uses a short, non-empty hand-off instead.
	var cutscene_content: Dictionary = presentation._content_for("objective", {
		"quest": {"title": "Ceremony Contract"},
		"objective": {
			"description": "Inspect the fallen seal",
			"delivery_mode": "cutscene",
			"narrative_lead_in": "The shattered seal exposes a path beneath the keep.",
		},
	})
	assert(str(cutscene_content.get("subtitle", "")) == "The shattered seal exposes a path beneath the keep.")
	var fallback: Dictionary = presentation._content_for("objective", {
		"quest": {"title": "Ceremony Contract"},
		"objective": {"description": "Inspect the fallen seal", "delivery_mode": "cutscene"},
	})
	assert(not str(fallback.get("subtitle", "")).strip_edges().is_empty())
	assert(not str(fallback.get("subtitle", "")).contains("Ceremony Contract"))

	# Stress the backend contract near its 320-character ceiling. The full string
	# must fit the subtitle box in at most four lines; ellipsis is only a defensive
	# fallback for malformed content beyond the contract.
	var long_lead_in := _long_narrative_lead_in()
	assert(long_lead_in.length() >= 310 and long_lead_in.length() <= 320)
	var fitted_size: int = int(presentation._fit_subtitle_font(long_lead_in))
	var body_font: Font = UiKit.body_font()
	if body_font == null:
		body_font = ThemeDB.fallback_font
	var measured: Vector2 = presentation._measure_subtitle(body_font, long_lead_in, fitted_size)
	assert(measured.x <= presentation.SUBTITLE_SIZE.x + 0.5)
	assert(measured.y <= presentation.SUBTITLE_SIZE.y + 0.5)
	assert(measured.y <= body_font.get_height(fitted_size) * 4.0 + 0.5)
	presentation.free()


func _test_rapid_objective_collapse() -> void:
	var quest: Dictionary = QuestManager.quests[0] as Dictionary
	var state: Dictionary = QuestManager.quest_states["quest_ceremony_contract"] as Dictionary
	state["objective_index"] = 1
	QuestManager._queue_quest_announcement("objective", quest)
	state["objective_index"] = 2
	QuestManager._queue_quest_announcement("objective", quest)

	var objective_entries: Array = AnnouncementCenter._queue.filter(func(entry: Variant) -> bool:
		return entry is Dictionary and str((entry as Dictionary).get("kind", "")) == "objective"
	)
	assert(objective_entries.size() == 1, "rapid advances must collapse to one actionable objective")
	var latest: Dictionary = (objective_entries[0] as Dictionary).get("objective", {}) as Dictionary
	assert(str(latest.get("id", "")) == "o3")
	assert(str(latest.get("narrative_lead_in", "")) == "The shattered seal exposes a path beneath the keep.")

	QuestManager._queue_quest_announcement("quest_complete", quest)
	var ordered := AnnouncementCenter._flush_sorted()
	assert(str((ordered[0] as Dictionary).get("kind", "")) == "new_quest")
	assert(str((ordered[1] as Dictionary).get("kind", "")) == "objective")
	assert(str((ordered[2] as Dictionary).get("kind", "")) == "quest_complete")
	AnnouncementCenter.reset()


func _test_instant_completion_drops_stale_objective() -> void:
	# A one-step quest queues its initial objective, then completes in the same
	# synchronous beat. Completion must remove that now-stale objective ceremony.
	QuestManager.reset()
	AnnouncementCenter.reset()
	QuestManager.load_chapter_quests([{
		"id": "quest_instant",
		"title": "One Breath",
		"type": "main",
		"giver": {"mode": "auto", "zone_id": "zone_here"},
		"objectives": [{
			"id": "o1", "kind": "reach", "zone_id": "zone_here",
			"description": "Arrive", "narrative_lead_in": "The road ends here.",
		}],
		"reward": {"xp": 0},
	}])
	QuestManager.notify_zone_entered("zone_here")
	var kinds: Array[String] = []
	for entry in AnnouncementCenter._queue:
		kinds.append(str((entry as Dictionary).get("kind", "")))
	assert(kinds == ["new_quest", "quest_complete"],
		"an objective completed in its activation beat must not leave a stale card")
	assert(QuestManager._toast_queue.is_empty())
	AnnouncementCenter.reset()


func _test_standalone_priority_barriers() -> void:
	var payload := {
		"quest": {"id": "quest_barrier", "title": "Barrier"},
		"objective": {
			"id": "o1", "description": "Continue after every higher-priority beat",
			"narrative_lead_in": "The path opens only after the commotion settles.",
		},
	}

	# The outside-conversation event is accepted immediately, but a cutscene owns
	# the stage first.
	GameManager.ui_blocking_input = false
	pending_narrative = true
	assert(AnnouncementCenter.enqueue("objective", payload))
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not AnnouncementCenter.playing)
	assert(AnnouncementCenter.has_pending())

	# When the cutscene clears, an already-open modal still owns input. This must
	# hold without mistaking AnnouncementCenter's eventual own blocking flag for an
	# external modal (which would deadlock playback).
	pending_narrative = false
	GameManager.ui_blocking_input = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not AnnouncementCenter.playing)
	assert(AnnouncementCenter.has_pending())

	# Open-world item presentation also precedes the resulting objective update.
	InventoryManager._toast_queue.append({"kind": "item", "name": "Test item", "count": 1})
	GameManager.ui_blocking_input = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not AnnouncementCenter.playing)
	assert(AnnouncementCenter.has_pending())
	InventoryManager._toast_queue.clear()

	var view: Node = await _wait_for_announcement(3.0)
	assert(view != null, "ceremony must start once every external barrier clears")
	assert(AnnouncementCenter.playing)
	assert(GameManager.ui_blocking_input)
	await get_tree().create_timer(0.55).timeout
	view.call("_dismiss")
	assert(await _wait_until(func() -> bool:
		return not AnnouncementCenter.playing and not AnnouncementCenter.has_pending()
	, 3.0))
	assert(not GameManager.ui_blocking_input)


func _test_battle_reward_quest_handoff() -> void:
	# BattleScene grants enemy-linked items before Main advances the defeat beat so
	# it can reveal them on the battle backdrop. The explicit post-defeat inventory
	# settle must still complete a collect objective unlocked by that same kill.
	AnnouncementCenter.reset()
	QuestManager.reset()
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"items": [{
			"id": "item_battle_seal",
			"name": "Battle Seal",
			"kind": "quest",
			"icon_index": 0,
			"acquisition": [{
				"mode": "enemy_drop",
				"source_entity_id": "enemy_gatekeeper",
				"zone_id": "zone_gate",
				"chance": 1.0,
				"count": 2,
			}],
		}],
		"icon_grid": 3,
		"icon_cell_px": 48,
	}, load("res://assets/ui/inventory/sample_icon_sheet.png"))
	QuestManager.load_chapter_quests([{
		"id": "quest_battle_handoff",
		"title": "The Gatekeeper's Seal",
		"type": "main",
		"giver": {"mode": "auto", "zone_id": "zone_gate"},
		"objectives": [
			{
				"id": "defeat_gatekeeper",
				"kind": "defeat",
				"zone_id": "zone_gate",
				"target_enemy_id": "enemy_gatekeeper",
				"description": "Defeat the gatekeeper",
			},
			{
				"id": "collect_seal",
				"kind": "collect",
				"zone_id": "zone_gate",
				"item_id": "item_battle_seal",
				"count": 2,
				"description": "Recover the broken seal",
			},
		],
		"reward": {"xp": 0},
	}])
	QuestManager.notify_zone_entered("zone_gate")
	AnnouncementCenter.reset()

	var rewards := InventoryManager.grant_linked_item_rewards_silent(
		"enemy_drop", "enemy_gatekeeper", "zone_gate",
	)
	assert(rewards.size() == 1)
	assert(int(rewards[0].get("count", 0)) == 2)
	assert(InventoryManager._toast_queue.is_empty(),
		"battle ceremony rewards must not enqueue the compact toast")
	assert(int((QuestManager.quest_states["quest_battle_handoff"] as Dictionary).get(
		"objective_index", -1)) == 0,
		"receiving loot before the defeat beat must not skip the defeat objective")

	QuestManager.notify_enemy_defeated("enemy_gatekeeper")
	QuestManager.notify_items_changed()
	assert(str((QuestManager.quest_states["quest_battle_handoff"] as Dictionary).get(
		"state", "")) == "completed",
		"post-defeat inventory settle must consume the already-granted battle loot")
	AnnouncementCenter.reset()


func _wait_for_announcement(timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for child in get_tree().root.get_children():
			if child.get_script() == AnnouncementViewScript:
				return child
		await get_tree().process_frame
	return null


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _quest_fixture() -> Dictionary:
	return {
		"id": "quest_ceremony_contract",
		"title": "Ceremony Contract",
		"type": "main",
		"giver": {"mode": "npc", "zone_id": "zone_01", "npc_id": "arlo"},
		"objectives": [
			{
				"id": "o1", "kind": "reach", "zone_id": "zone_02",
				"description": "Reach the mist gate",
				"narrative_lead_in": "Arlo's warning points toward the mist gate.",
				"delivery_mode": "narration",
			},
			{
				"id": "o2", "kind": "talk", "zone_id": "zone_02", "target_npc_id": "mira",
				"description": "Question Mira",
				"narrative_lead_in": "Fresh tracks lead from the gate to Mira's watch post.",
				"delivery_mode": "narration",
			},
			{
				"id": "o3", "kind": "reach", "zone_id": "zone_03",
				"description": "Inspect the fallen seal",
				"narrative_lead_in": "The shattered seal exposes a path beneath the keep.",
				"delivery_mode": "cutscene",
			},
		],
		"reward": {"xp": 0},
	}


func _long_narrative_lead_in() -> String:
	return "Vết sáng trên phiến lá hé lộ rằng những cánh hoa chỉ nở nơi sương đêm còn đọng lại, nhưng dấu chân mới bên bờ suối cho thấy ai đó đã hái chúng trước bình minh. Lumi phải lần theo mùi hương còn sót lại qua Cánh Đồng Sương, tìm người giữ chiếc giỏ bạc và khám phá vì sao khu rừng đang dần mất đi ánh trăng trước đêm nay."
