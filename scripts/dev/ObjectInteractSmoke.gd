extends Node2D
## Dev-only headless smoke for the world-object interaction system. Loads the real
## chapter catalog + quests from the running backend, registers the real zone
## packages, and drives two flows with assertions:
##   A) Memory Garden (zone_04 / quest_02): searching grants the lost pinwheel +
##      paper star and auto-advances both collect objectives.
##   B) Sugar Clock (zone_03 / quest_03): searching BEFORE talking to Tilda still
##      yields the hidden letter, and the collect objective settles when talking
##      later — proving collect is order-independent.
## Exit code 0 = all pass, 1 = a failure.

const ROOT := "/Users/dinhhuynh/Documents/FULLGAME"
const WorldObjectScript := preload("res://scripts/world/WorldObject.gd")

var _failures: int = 0


func _ready() -> void:
	var flow: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapters: Array = flow.get("chapters", []) as Array
	if chapters.is_empty():
		_fail("no chapters from backend")
		return _finish()
	var run_id: String = str(flow.get("run_id", ""))
	var chapter: Dictionary = chapters[0] as Dictionary
	var items_payload: Dictionary = chapter.get("items", {}) as Dictionary
	var icon: Texture2D = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	InventoryManager.load_chapter_catalog(items_payload, icon)
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)
	print("[ObjSmoke] run=%s items=%d quests=%d" % [run_id, InventoryManager.catalog.size(), QuestManager.quests.size()])

	_test_memory_garden(run_id)
	_test_sugar_clock(run_id)
	_test_world_object_spawn(run_id)
	_test_give_and_exchange()
	_test_all_objects_interactable(run_id)
	_finish()


func _test_all_objects_interactable(run_id: String) -> void:
	print("\n--- TEST F: every object interactable (lore + minor loot) ---")
	var pkg: Dictionary = _read_package(run_id, 1, "zone_03")
	ObjectInteractionManager.register_zone_contracts(pkg)
	var oi: Dictionary = pkg.get("object_interactions", {}) as Dictionary
	var contracts: Array = oi.get("contracts", []) as Array
	_check(contracts.size() >= 8, "zone_03 exposes many interactable objects (%d)" % contracts.size())

	# a pure-lore object: inspect, evocative text, no item
	var lore_id := ""
	var item_id := ""
	for c in contracts:
		if not (c is Dictionary):
			continue
		var cd := c as Dictionary
		if str(cd.get("archetype")) == "inspect" and lore_id.is_empty():
			lore_id = str(cd.get("object_id"))
		elif str(cd.get("archetype")) == "search" and str(cd.get("source")) == "scene" and item_id.is_empty():
			item_id = str(cd.get("object_id"))

	_check(not lore_id.is_empty(), "found a lore (inspect) object")
	if not lore_id.is_empty():
		var lore_res: Dictionary = ObjectInteractionManager.run_interaction(lore_id)
		_check(str(lore_res.get("status")) == "inspect", "lore object → inspect")
		_check(not str(lore_res.get("text", "")).strip_edges().is_empty(), "lore object has story/world text")

	_check(not item_id.is_empty(), "found a non-quest object that hides a minor item")
	if not item_id.is_empty():
		var grant_item := str((((ObjectInteractionManager.contract_for(item_id).get("grants", []) as Array)[0]) as Dictionary).get("item_id"))
		var before := InventoryManager.count_of(grant_item)
		var res: Dictionary = ObjectInteractionManager.run_interaction(item_id)
		_check(str(res.get("status")) == "success", "searching a prop yields its item")
		_check(InventoryManager.count_of(grant_item) == before + 1, "minor loot added to inventory")
		_check(ObjectInteractionManager.is_object_sourced_item(grant_item, "zone_03") == false, "generic loot is NOT scatter-suppressed")


func _test_give_and_exchange() -> void:
	print("\n--- TEST D/E: give + exchange archetypes ---")
	# pick two real, freely-grantable catalog items as stand-ins
	var consumable := _first_item_of_kind("heal")
	var reward := _first_item_of_kind("energy")
	if consumable.is_empty() or reward.is_empty():
		_check(false, "found two catalog items for give/exchange test")
		return

	# inject synthetic contracts (the world data only authors 'search', but the
	# system supports give/exchange — prove both run end to end)
	ObjectInteractionManager._contracts["test_altar"] = {
		"object_id": "test_altar", "name": "Bệ Thờ Thử", "archetype": "give",
		"verb": "Dâng", "examine_text": "...", "requires": [{"item_id": consumable, "name": "X", "count": 1}],
		"grants": [], "consume_requires": true, "completes": [], "one_shot": true,
		"locked_text": "Cần lễ vật.", "success_text": "Đã dâng lễ.", "done_text": "Đã yên.",
	}
	ObjectInteractionManager._contracts["test_shrine"] = {
		"object_id": "test_shrine", "name": "Đền Đổi Chác", "archetype": "exchange",
		"verb": "Trao đổi", "examine_text": "...", "requires": [{"item_id": consumable, "name": "X", "count": 1}],
		"grants": [{"item_id": reward, "name": "Y", "count": 1}], "consume_requires": true,
		"completes": [], "one_shot": true, "locked_text": "Cần vật phẩm.", "success_text": "Đã trao đổi.", "done_text": "Xong.",
	}

	# GIVE: locked when missing, success + consume when held
	while InventoryManager.count_of(consumable) > 0:
		InventoryManager.remove_item(consumable, 1)
	var locked: Dictionary = ObjectInteractionManager.run_interaction("test_altar")
	_check(str(locked.get("status")) == "locked", "give is locked without the required item")
	_check((locked.get("missing", []) as Array).size() == 1, "locked reports the missing item")
	InventoryManager.add_item(consumable, 1, true)
	var given: Dictionary = ObjectInteractionManager.run_interaction("test_altar")
	_check(str(given.get("status")) == "success", "give succeeds when the item is held")
	_check(InventoryManager.count_of(consumable) == 0, "give consumed the required item")

	# EXCHANGE: give one item, receive a different one
	InventoryManager.add_item(consumable, 1, true)
	var before_reward := InventoryManager.count_of(reward)
	var swapped: Dictionary = ObjectInteractionManager.run_interaction("test_shrine")
	_check(str(swapped.get("status")) == "success", "exchange succeeds")
	_check(InventoryManager.count_of(consumable) == 0, "exchange consumed the given item")
	_check(InventoryManager.count_of(reward) == before_reward + 1, "exchange granted the received item")


func _first_item_of_kind(kind: String) -> String:
	for item in InventoryManager.catalog:
		if item is Dictionary and str((item as Dictionary).get("kind")) == kind:
			return str((item as Dictionary).get("id"))
	return ""


func _test_world_object_spawn(run_id: String) -> void:
	print("\n--- TEST C: WorldObject in-world spawn (no runtime error) ---")
	var pkg: Dictionary = _read_package(run_id, 1, "zone_04")
	ObjectInteractionManager.register_zone_contracts(pkg)
	var definitions := {}
	for d in pkg.get("definitions", []) as Array:
		if d is Dictionary:
			definitions[str((d as Dictionary).get("id", ""))] = d
	var target: Dictionary = {}
	for inst in pkg.get("instances", []) as Array:
		if inst is Dictionary and str((inst as Dictionary).get("interaction_object_id", "")) == "object_memory_garden":
			target = inst as Dictionary
			break
	_check(not target.is_empty(), "found the garden interactive instance to spawn")
	if target.is_empty():
		return
	var dummy_player := Node2D.new()
	dummy_player.global_position = Vector2(2000, 2000)  # far, so the prompt stays hidden
	add_child(dummy_player)
	var world_object: Node2D = WorldObjectScript.new()
	add_child(world_object)
	world_object.setup(
		ObjectInteractionManager.contract_for(str(target.get("interaction_object_id", target.get("id", "")))),
		target,
		definitions.get(str(target.get("id", "")), {}) as Dictionary,
		{"player": dummy_player},
	)
	world_object._process(0.1)  # tick once: proximity + glow + marker update
	_check(is_instance_valid(world_object), "WorldObject set up and ticked without error")
	_check(world_object.get("object_id") == "object_memory_garden", "WorldObject bound to the right object id")


func _test_memory_garden(run_id: String) -> void:
	print("\n--- TEST A: Memory Garden (zone_04 / quest_02) ---")
	var pkg: Dictionary = _read_package(run_id, 1, "zone_04")
	_check(not pkg.is_empty(), "zone_04 package loaded")
	_check(pkg.has("object_interactions"), "zone_04 package carries object_interactions")
	ObjectInteractionManager.register_zone_contracts(pkg)
	QuestManager.notify_zone_entered("zone_04")
	# quest_02 is given by Milo (npc_04) — it only begins once the player meets him.
	QuestManager.notify_npc_talked("npc_04")

	_check(ObjectInteractionManager.has_interaction("object_memory_garden"), "garden contract registered")
	_check(ObjectInteractionManager.is_object_sourced_item("item_milo_pinwheel", "zone_04"), "pinwheel is object-sourced (no random scatter)")

	var before_pinwheel := InventoryManager.count_of("item_milo_pinwheel")
	var before_star := InventoryManager.count_of("item_paper_star")
	var result: Dictionary = ObjectInteractionManager.run_interaction("object_memory_garden")
	_check(str(result.get("status")) == "success", "garden interaction succeeded")
	_check((result.get("granted", []) as Array).size() == 2, "garden revealed 2 items")
	_check(InventoryManager.count_of("item_milo_pinwheel") == before_pinwheel + 1, "received pinwheel")
	_check(InventoryManager.count_of("item_paper_star") == before_star + 1, "received paper star")
	_check(_objective_index("quest_02") >= 2, "quest_02 advanced past both collect objectives (idx=%d)" % _objective_index("quest_02"))
	_check(ObjectInteractionManager.is_used("object_memory_garden"), "garden marked used (one-shot)")

	var again: Dictionary = ObjectInteractionManager.run_interaction("object_memory_garden")
	_check(str(again.get("status")) == "done", "re-searching garden returns 'done'")


func _test_sugar_clock(run_id: String) -> void:
	print("\n--- TEST B: Sugar Clock (zone_03 / quest_03), search-before-talk ---")
	var pkg: Dictionary = _read_package(run_id, 1, "zone_03")
	_check(not pkg.is_empty(), "zone_03 package loaded")
	ObjectInteractionManager.register_zone_contracts(pkg)
	QuestManager.notify_zone_entered("zone_03")

	_check(ObjectInteractionManager.has_interaction("object_sugar_clock"), "clock contract registered")
	# quest_03 is Tilda's — it has NOT started just by entering her zone.
	_check(_quest_state("quest_03") == "inactive", "quest_03 not started before meeting Tilda")

	# search the clock BEFORE talking to Tilda — you still find the letter...
	var before_letter := InventoryManager.count_of("item_hidden_letter")
	var result: Dictionary = ObjectInteractionManager.run_interaction("object_sugar_clock")
	_check(str(result.get("status")) == "success", "clock interaction succeeded")
	_check(InventoryManager.count_of("item_hidden_letter") == before_letter + 1, "found the hidden letter")
	_check(_quest_state("quest_03") == "inactive", "...but the quest still hasn't started (no NPC met)")

	# meeting Tilda starts the quest, closes its 'talk to Tilda' step, and settles the
	# already-found letter — fast-forwarding straight to the deliver step.
	QuestManager.notify_npc_talked("npc_03")
	_check(_quest_state("quest_03") == "active", "talking to Tilda started quest_03")
	var kind_after := _objective_kind("quest_03")
	_check(kind_after == "deliver" or _objective_index("quest_03") >= 2,
		"collect objective auto-settled after talk (now '%s', idx=%d)" % [kind_after, _objective_index("quest_03")])


# ── helpers ──────────────────────────────────────────────────────────────────────


func _objective_index(quest_id: String) -> int:
	return int((QuestManager.quest_states.get(quest_id, {}) as Dictionary).get("objective_index", -1))


func _quest_state(quest_id: String) -> String:
	return str((QuestManager.quest_states.get(quest_id, {}) as Dictionary).get("state", "?"))


func _objective_kind(quest_id: String) -> String:
	for quest in QuestManager.quests:
		if str(quest.get("id")) == quest_id:
			var idx := _objective_index(quest_id)
			var objs: Array = quest.get("objectives", []) as Array
			if idx >= 0 and idx < objs.size():
				return str((objs[idx] as Dictionary).get("kind", ""))
	return ""


func _read_package(run_id: String, chapter: int, zone_id: String) -> Dictionary:
	var path := "%s/SceneBuilder/outputs/%s/scene_background_render/chapter_%d/%s/package/scene_package.json" % [ROOT, run_id, chapter, zone_id]
	if not FileAccess.file_exists(path):
		push_error("[ObjSmoke] missing package: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _fail(message: String) -> void:
	_failures += 1
	printerr("[ObjSmoke] %s" % message)


func _finish() -> void:
	print("\n[ObjSmoke] %s (%d failure(s))" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
