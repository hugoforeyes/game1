extends Node2D
## Dev-only headless smoke for the companion / party system.
##   - Arlo is registered as a companion but is NOT in the party until you meet him
##   - talking to Arlo (npc_talked) makes him JOIN (one-shot)
##   - an authored LEAVE event removes him on its trigger
##   - a PartyFollower spawns and trails the player without error
## Reads the real chapter_quests manifest from disk (no dependency on the running
## server's flow). Exit 0 = all pass, 1 = a failure.

const ROOT := "/Users/dinhhuynh/Documents/FULLGAME"
const PartyFollowerScript := preload("res://scripts/world/PartyFollower.gd")

var _failures: int = 0
var _joined: Array = []
var _left: Array = []


func _ready() -> void:
	var manifest := _read_manifest()
	_check(not manifest.is_empty(), "chapter_quests manifest loaded")
	var party := _build_party_payload(manifest)
	_check((party.get("companions", []) as Array).size() >= 1, "manifest exposes >=1 companion")
	_check((party.get("events", []) as Array).size() >= 1, "manifest exposes >=1 party event")

	PartyManager.member_joined.connect(func(id): _joined.append(id))
	PartyManager.member_left.connect(func(id): _left.append(id))
	PartyManager.load_chapter_party(party)

	var arlo := _first_companion_id(party)
	_check(not arlo.is_empty(), "found companion id (%s)" % arlo)
	_check(PartyManager.is_companion(arlo), "Arlo recognised as a companion")
	_check(not PartyManager.is_member(arlo), "Arlo is NOT in the party before meeting him")

	# fire the companion's REAL join trigger (Arlo gives quest_01 → joins on its
	# completion, so all his quest-giver beats resolve before he follows you)
	var join_event := _event_for(party, arlo, "join")
	_check(not join_event.is_empty(), "Arlo has a join event")
	print("  (join trigger: %s)" % JSON.stringify(join_event.get("trigger", {})))
	_fire_trigger(join_event.get("trigger", {}) as Dictionary)
	_check(PartyManager.is_member(arlo), "Arlo JOINS the party when his join trigger fires")
	_check(_joined.has(arlo), "member_joined fired for Arlo")

	# one-shot: firing again doesn't re-join / re-fire
	_joined.clear()
	_fire_trigger(join_event.get("trigger", {}) as Dictionary)
	_check(_joined.is_empty(), "join is one-shot (no duplicate)")

	_test_leave(arlo)
	_test_follower_spawn(arlo)
	_test_carried_over(arlo)
	_test_deferred_join_until_related_quests_done()
	_test_deferred_join_until_npc_grant_collect_done()
	_finish()


func _test_carried_over(arlo: String) -> void:
	print("\n--- CARRY-OVER: a world-continuity companion re-joins across chapters ---")
	# Next-chapter payload: the companion carries over via a chapter_start join.
	var carried_party := {
		"companions": [{"npc_id": arlo, "name": "Arlo", "combat_role": "support", "zones": []}],
		"events": [{
			"id": "party_join_carried",
			"companion_id": arlo,
			"action": "join",
			"trigger": {"type": "chapter_start"},
			"carried_over": true,
		}],
	}
	# 1) Player NEVER recruited them earlier → the carried join must NOT force them in.
	PartyManager.active_members.clear()
	PartyManager.joined_history.clear()
	PartyManager.load_chapter_party(carried_party)
	_check(not PartyManager.is_member(arlo), "carried join is skipped when they never joined before")
	# 2) They DID join in an earlier chapter → they quietly re-join at chapter start.
	PartyManager.joined_history[arlo] = true
	PartyManager.load_chapter_party(carried_party)
	_check(PartyManager.is_member(arlo), "carried join re-joins when joined_history has them")
	# 3) joined_history survives a save round-trip.
	var saved: Dictionary = PartyManager.serialize_save()
	PartyManager.joined_history.clear()
	PartyManager.apply_save(saved)
	_check(PartyManager.joined_history.has(arlo), "joined_history survives serialize/apply_save")


func _test_deferred_join_until_related_quests_done() -> void:
	print("\n--- DEFERRED JOIN: companion waits until no quest targets them ---")
	var npc_id := "npc_deferred_companion"
	_joined.clear()
	QuestManager.reset()
	PartyManager.reset()
	PartyManager.load_chapter_party({
		"companions": [{"npc_id": npc_id, "name": "Deferred", "combat_role": "support", "zones": []}],
		"events": [{
			"id": "party_join_deferred_companion",
			"companion_id": npc_id,
			"action": "join",
			"trigger": {"type": "npc_talked", "npc_id": npc_id},
		}],
	})
	QuestManager.load_chapter_quests([
		{
			"id": "quest_deferred_join",
			"title": "Deferred Join QA",
			"type": "main",
			"giver": {"mode": "auto", "zone_id": "zone_defer"},
			"objectives": [
				{
					"id": "o1",
					"kind": "talk",
					"zone_id": "zone_defer",
					"target_npc_id": npc_id,
					"description": "Talk once.",
				},
				{
					"id": "o2",
					"kind": "talk",
					"zone_id": "zone_defer",
					"target_npc_id": npc_id,
					"description": "Talk again.",
				},
			],
			"reward": {"xp": 0},
		},
	])
	QuestManager.notify_zone_entered("zone_defer")
	QuestManager._toast_queue.clear()

	QuestManager.notify_npc_talked(npc_id)
	_check(not PartyManager.is_member(npc_id), "join stays deferred while another objective still targets the NPC")
	_check(PartyManager._pending_join_events.has("party_join_deferred_companion"), "join event is kept pending")

	QuestManager.notify_npc_talked(npc_id)
	_check(PartyManager.is_member(npc_id), "companion joins after their final related objective completes")
	_check(_joined.has(npc_id), "member_joined fires after deferred join resolves")
	_check(not PartyManager._pending_join_events.has("party_join_deferred_companion"), "pending join clears after joining")


func _test_deferred_join_until_npc_grant_collect_done() -> void:
	print("\n--- DEFERRED JOIN: companion waits for NPC-granted collect item ---")
	var npc_id := "npc_collect_companion"
	var item_id := "item_white_memory_flower"
	_joined.clear()
	QuestManager.reset()
	PartyManager.reset()
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"icon_grid": 1,
		"icon_cell_px": 48,
		"items": [_quest_grant_item(item_id, "quest_npc_grant", npc_id, "zone_flower", "o_wrong", 1.0)],
	}, null)
	PartyManager.load_chapter_party(_collect_companion_party(npc_id))
	QuestManager.load_chapter_quests([_collect_companion_quest(npc_id, item_id)])
	QuestManager.notify_zone_entered("zone_flower")
	QuestManager._toast_queue.clear()

	QuestManager.notify_npc_talked(npc_id)
	_check(InventoryManager.count_of(item_id) == 1, "NPC-granted collect item is awarded even if rule objective_id is stale")
	_check(str((QuestManager.quest_states.get("quest_npc_grant", {}) as Dictionary).get("state", "")) == "completed", "NPC-granted collect objective completes")
	_check(PartyManager.is_member(npc_id), "companion joins after NPC-granted collect objective completes")
	_check(_joined.has(npc_id), "member_joined fires after collect grant resolves")

	print("\n--- DEFERRED JOIN: unresolved NPC-grant collect keeps companion stationary ---")
	_joined.clear()
	QuestManager.reset()
	PartyManager.reset()
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"icon_grid": 1,
		"icon_cell_px": 48,
		"items": [_quest_grant_item(item_id, "quest_npc_grant", npc_id, "zone_flower", "o2", 0.0)],
	}, null)
	PartyManager.load_chapter_party(_collect_companion_party(npc_id))
	QuestManager.load_chapter_quests([_collect_companion_quest(npc_id, item_id)])
	QuestManager.notify_zone_entered("zone_flower")
	QuestManager._toast_queue.clear()

	QuestManager.notify_npc_talked(npc_id)
	_check(not PartyManager.is_member(npc_id), "join stays deferred while NPC-granted collect item is still missing")
	_check(PartyManager._pending_join_events.has("party_join_collect_companion"), "NPC-grant collect keeps join pending")
	InventoryManager.add_item(item_id, 1, true)
	_check(PartyManager.is_member(npc_id), "companion joins once the NPC-granted collect objective is satisfied")

	print("\n--- RECOVERY: party companion can satisfy their own NPC-grant collect ---")
	_joined.clear()
	QuestManager.reset()
	PartyManager.reset()
	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"icon_grid": 1,
		"icon_cell_px": 48,
		"items": [_quest_grant_item(item_id, "quest_npc_grant", npc_id, "zone_flower", "o_wrong", 1.0)],
	}, null)
	PartyManager.load_chapter_party(_collect_companion_party(npc_id))
	PartyManager.active_members[npc_id] = true
	PartyManager.joined_history[npc_id] = true
	QuestManager.load_chapter_quests([_collect_companion_quest(npc_id, item_id)])
	QuestManager.notify_zone_entered("zone_flower")
	QuestManager.quest_states["quest_npc_grant"] = {"state": "active", "objective_index": 1, "progress": 0, "choices": {}}
	QuestManager.notify_items_changed()
	_check(InventoryManager.count_of(item_id) == 1, "already-joined companion grants the missing collect item")
	_check(str((QuestManager.quest_states.get("quest_npc_grant", {}) as Dictionary).get("state", "")) == "completed", "stuck NPC-grant collect recovers while companion is in party")


func _test_leave(arlo: String) -> void:
	print("\n--- LEAVE: an authored leave event removes the companion ---")
	# inject a synthetic leave event on entering a marker zone
	PartyManager.events.append({
		"id": "party_leave_test",
		"companion_id": arlo,
		"action": "leave",
		"trigger": {"type": "zone_enter", "zone_id": "zone_test_leave"},
	})
	PartyManager.notify_zone_entered("zone_test_leave")
	_check(not PartyManager.is_member(arlo), "entering the leave-zone removed Arlo from the party")
	_check(_left.has(arlo), "member_left fired for Arlo")


func _test_follower_spawn(arlo: String) -> void:
	print("\n--- FOLLOWER: spawns and trails the player without error ---")
	# rejoin so there's an active member to follow
	PartyManager.active_members[arlo] = true
	var player := Node2D.new()
	player.global_position = Vector2(1000, 1000)
	add_child(player)
	var follower: Node2D = PartyFollowerScript.new()
	add_child(follower)
	follower.setup(arlo, PartyManager.companion_texture(arlo), player, 26)
	var start_pos := follower.global_position
	_check(follower.global_position.distance_to(player.global_position) >= 44.0, "follower starts separated from the player")
	for idle_frame in range(40):
		follower._physics_process(1.0 / 60.0)
	_check(follower.global_position.distance_to(player.global_position) >= 44.0, "idle follower does NOT stand on top of the player")
	_check(follower.global_position.distance_to(start_pos) < 2.0, "idle follower stands still when already close enough")
	# drive a few frames of player movement; follower should trail toward it
	for i in range(100):
		player.global_position += Vector2(6, 0)
		follower._physics_process(1.0 / 60.0)
	_check(is_instance_valid(follower), "follower ticked 100 frames without error")
	_check(follower.global_position.x > 1000.0, "follower moved toward the player (x=%.0f)" % follower.global_position.x)
	_check(follower.global_position.distance_to(player.global_position) > 1.0, "follower trails BEHIND the player, not on top")


# ── helpers ──────────────────────────────────────────────────────────────────────


func _read_manifest() -> Dictionary:
	var path := "%s/SceneBuilder/outputs/20260621_071734/chapter_quests/chapter_1/manifest.json" % ROOT
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _build_party_payload(manifest: Dictionary) -> Dictionary:
	var companions: Array = []
	for npc in ((manifest.get("quest_entities", {}) as Dictionary).get("npcs", []) as Array):
		if npc is Dictionary and ((npc as Dictionary).get("companion", {}) as Dictionary).get("is_companion", false):
			var comp := (npc as Dictionary).get("companion", {}) as Dictionary
			companions.append({
				"npc_id": str((npc as Dictionary).get("id", "")),
				"name": str((npc as Dictionary).get("name", "")),
				"combat_role": str(comp.get("combat_role", "support")),
				"zones": comp.get("zones", []),
			})
	return {"companions": companions, "events": manifest.get("party_events", []) as Array}


func _first_companion_id(party: Dictionary) -> String:
	var companions := party.get("companions", []) as Array
	return str((companions[0] as Dictionary).get("npc_id", "")) if not companions.is_empty() else ""


func _event_for(party: Dictionary, companion_id: String, action: String) -> Dictionary:
	for event in party.get("events", []) as Array:
		if event is Dictionary and str((event as Dictionary).get("companion_id")) == companion_id \
				and str((event as Dictionary).get("action")) == action:
			return event as Dictionary
	return {}


func _fire_trigger(trigger: Dictionary) -> void:
	match str(trigger.get("type", "")):
		"npc_talked":
			QuestManager.npc_talked.emit(str(trigger.get("npc_id", "")))
		"quest_complete":
			QuestManager.quest_states[str(trigger.get("quest_id", ""))] = {"state": "completed"}
			QuestManager.quests_changed.emit()
		"zone_enter":
			PartyManager.notify_zone_entered(str(trigger.get("zone_id", "")))
		"enemy_defeated":
			PartyManager.notify_enemy_defeated(str(trigger.get("enemy_id", "")))


func _quest_grant_item(
		item_id: String,
		quest_id: String,
		npc_id: String,
		zone_id: String,
		objective_id: String,
		chance: float,
	) -> Dictionary:
	return {
		"id": item_id,
		"kind": "quest",
		"role": "quest_entity",
		"quest_id": quest_id,
		"quest_ids": [quest_id],
		"name": "White Memory Flower",
		"description": "A quest item granted by the companion NPC.",
		"acquisition": [{
			"mode": "npc_grant",
			"source_entity_id": npc_id,
			"zone_id": zone_id,
			"quest_id": quest_id,
			"objective_id": objective_id,
			"count": 1,
			"chance": chance,
		}],
	}


func _collect_companion_party(npc_id: String) -> Dictionary:
	return {
		"companions": [{"npc_id": npc_id, "name": "Collect Companion", "combat_role": "support", "zones": []}],
		"events": [{
			"id": "party_join_collect_companion",
			"companion_id": npc_id,
			"action": "join",
			"trigger": {"type": "npc_talked", "npc_id": npc_id},
		}],
	}


func _collect_companion_quest(npc_id: String, item_id: String) -> Dictionary:
	return {
		"id": "quest_npc_grant",
		"title": "NPC Grant QA",
		"type": "main",
		"giver": {"mode": "auto", "zone_id": "zone_flower"},
		"objectives": [
			{
				"id": "o1",
				"kind": "talk",
				"zone_id": "zone_flower",
				"target_npc_id": npc_id,
				"description": "Talk to the companion.",
			},
			{
				"id": "o2",
				"kind": "collect",
				"zone_id": "zone_flower",
				"item_id": item_id,
				"count": 1,
				"description": "Receive the quest item from the companion.",
			},
		],
		"reward": {"xp": 0},
	}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _finish() -> void:
	print("\n[PartySmoke] %s (%d failure(s))" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
