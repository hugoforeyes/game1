extends Node
## Runtime for player ↔ world-object interactions: searching containers, giving
## items to mechanisms, and exchanging items — the object/item half of the quest
## loop (NPCs cover the talk/choice half).
##
## Contracts are authored on the backend (chapter_object_interactions step) and ride
## inside each zone's scene_package under `object_interactions`. They bind an object
## to the quest items it hides / needs, so an item the story says is "inside the
## clock" is obtained BY interacting with that clock — never scattered at random.
##
## Archetypes:
##   search   → object hides item(s); interacting reveals & grants them (one-shot)
##   give     → object needs item(s); interacting consumes them and activates
##   exchange → give item(s) then receive different item(s)
##   inspect  → lore / flavour only
##
## Mirrors the QuestManager / InventoryManager autoload pattern (process-always,
## reset() on new game, signals the world listens to).

signal object_interacted(object_id: String, result: Dictionary)

# object_id -> contract dictionary (merged across every zone visited this run)
var _contracts: Dictionary = {}
# object_id -> true once its one-shot interaction has been consumed
var _used: Dictionary = {}
# zone_id -> Array[String] of item ids that are obtained from an object in that zone
# (so Main suppresses their random world scatter)
var _zone_object_items: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	_contracts.clear()
	_used.clear()
	_zone_object_items.clear()


# ── zone loading ────────────────────────────────────────────────────────────────


func register_zone_contracts(package_data: Dictionary) -> void:
	## Called by Main when a zone package loads. Merges this zone's contracts into
	## the chapter-wide registry (used-state persists across zone reloads).
	var oi: Dictionary = package_data.get("object_interactions", {}) as Dictionary
	if oi.is_empty():
		return
	var zone_id := str((package_data.get("scene_context", {}) as Dictionary).get("zone_id", ""))
	for raw in oi.get("contracts", []) as Array:
		if raw is Dictionary:
			var object_id := str((raw as Dictionary).get("object_id", ""))
			if not object_id.is_empty():
				_contracts[object_id] = raw
	var item_ids: Array[String] = []
	for raw_id in oi.get("object_sourced_item_ids", []) as Array:
		item_ids.append(str(raw_id))
	if not zone_id.is_empty():
		_zone_object_items[zone_id] = item_ids
	print("[ObjInteract] zone %s registered contracts=%d object_items=%s" % [zone_id, (oi.get("contracts", []) as Array).size(), item_ids])


# ── queries ─────────────────────────────────────────────────────────────────────


func contract_for(object_id: String) -> Dictionary:
	return _contracts.get(object_id, {}) as Dictionary


func has_interaction(object_id: String) -> bool:
	return _contracts.has(object_id)


func is_used(object_id: String) -> bool:
	return bool(_used.get(object_id, false))


func is_object_sourced_item(item_id: String, zone_id: String) -> bool:
	## True when the item is provided by interacting with an object in this zone —
	## the random-scatter spawner must skip it so it lives only at its object.
	var ids: Array = _zone_object_items.get(zone_id, []) as Array
	return ids.has(item_id)


func can_fulfill(contract: Dictionary) -> bool:
	for req in contract.get("requires", []) as Array:
		if not (req is Dictionary):
			continue
		var item_id := str((req as Dictionary).get("item_id", ""))
		var need := maxi(1, int((req as Dictionary).get("count", 1)))
		if InventoryManager.count_of(item_id) < need:
			return false
	return true


func missing_requirements(contract: Dictionary) -> Array:
	var missing: Array = []
	for req in contract.get("requires", []) as Array:
		if not (req is Dictionary):
			continue
		var item_id := str((req as Dictionary).get("item_id", ""))
		var need := maxi(1, int((req as Dictionary).get("count", 1)))
		var have := InventoryManager.count_of(item_id)
		if have < need:
			missing.append({"item_id": item_id, "name": str((req as Dictionary).get("name", item_id)), "need": need, "have": have})
	return missing


func marker_for_object(object_id: String) -> String:
	## A gold "!" floats over an interactable object whose completion is the player's
	## CURRENT objective — the same "do this now" affordance NPCs use.
	var contract := contract_for(object_id)
	if contract.is_empty() or is_used(object_id):
		return ""
	for comp in contract.get("completes", []) as Array:
		if comp is Dictionary and QuestManager.is_objective_active(
				str((comp as Dictionary).get("quest_id", "")),
				str((comp as Dictionary).get("objective_id", "")),
		):
			return "!"
	return ""


# ── execution ───────────────────────────────────────────────────────────────────


func run_interaction(object_id: String) -> Dictionary:
	## Execute the contract and return a UI-ready result dictionary:
	##   {status, archetype, object_name, text, granted:[], given:[], missing:[]}
	## status ∈ none | inspect | locked | success | done
	var contract := contract_for(object_id)
	if contract.is_empty():
		return {"status": "none"}

	var archetype := str(contract.get("archetype", "inspect"))
	var object_name := str(contract.get("name", ""))
	var one_shot := bool(contract.get("one_shot", false))

	if one_shot and is_used(object_id):
		return {
			"status": "done", "archetype": archetype, "object_name": object_name,
			"text": str(contract.get("done_text", contract.get("examine_text", ""))),
			"granted": [], "given": [], "missing": [],
		}

	if archetype == "inspect":
		return {
			"status": "inspect", "archetype": archetype, "object_name": object_name,
			"text": str(contract.get("examine_text", "")),
			"granted": [], "given": [], "missing": [],
		}

	# give / exchange must clear the requirement first
	var requires: Array = contract.get("requires", []) as Array
	if not requires.is_empty() and not can_fulfill(contract):
		return {
			"status": "locked", "archetype": archetype, "object_name": object_name,
			"text": str(contract.get("locked_text", "")),
			"granted": [], "given": [], "missing": missing_requirements(contract),
		}

	var given: Array = []
	if bool(contract.get("consume_requires", false)):
		for req in requires:
			if not (req is Dictionary):
				continue
			var item_id := str((req as Dictionary).get("item_id", ""))
			var count := maxi(1, int((req as Dictionary).get("count", 1)))
			if InventoryManager.remove_item(item_id, count):
				given.append({"item_id": item_id, "name": str((req as Dictionary).get("name", item_id)), "count": count})

	# grant items — add_item fires InventoryManager.item_obtained, which the
	# QuestManager already turns into collect-objective progress automatically.
	var granted: Array = []
	for grant in contract.get("grants", []) as Array:
		if not (grant is Dictionary):
			continue
		var item_id := str((grant as Dictionary).get("item_id", ""))
		var count := maxi(1, int((grant as Dictionary).get("count", 1)))
		InventoryManager.add_item(item_id, count, true)  # silent: the reveal UI announces it
		granted.append({"item_id": item_id, "name": str((grant as Dictionary).get("name", item_id)), "count": count})

	if one_shot:
		_used[object_id] = true

	# settle collect objectives against the items we just granted (order-independent),
	# then explicitly resolve any non-collect objectives the contract closes.
	QuestManager.notify_items_changed()
	for comp in contract.get("completes", []) as Array:
		if comp is Dictionary:
			QuestManager.notify_object_objective(
				str((comp as Dictionary).get("quest_id", "")),
				str((comp as Dictionary).get("objective_id", "")),
			)

	var result := {
		"status": "success", "archetype": archetype, "object_name": object_name,
		"text": str(contract.get("success_text", "")),
		"granted": granted, "given": given, "missing": [],
	}
	object_interacted.emit(object_id, result)
	return result
