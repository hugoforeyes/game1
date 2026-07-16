extends Node
## Party / companion runtime. Companions (e.g. Arlo) JOIN or LEAVE the protagonist's
## group on authored story triggers (`party_events`), and while in the party they
## follow the player across every zone. Mirrors the QuestManager / CutsceneDirector
## pattern: it loads chapter data, matches events against the same fixed trigger
## vocabulary, and exposes signals the world (Main) reacts to.

signal member_joined(npc_id: String)
signal member_left(npc_id: String)
## Escort NPCs travel in the overworld and appear in battle as protected actors,
## but they are deliberately NOT companions: they never gain levels, grant party
## passives, take turns, or enter active_members.
signal escort_joined(npc_id: String)
signal escort_left(npc_id: String)

const PartyJoinPopupScript := preload("res://scripts/ui/PartyJoinPopup.gd")

# npc_id -> {name, combat_role, joins_party, zones, sprite_url}
var companions: Dictionary = {}
var events: Array = []                 # party_events
var active_members: Dictionary = {}    # npc_id -> true (currently travelling with the player)
## Chapter-authored non-companion roster (`party.escorts`).
var escorts: Dictionary = {}           # npc_id -> roster definition
## npc_id -> merged roster/objective runtime data. HP and max_hp are snapshots
## captured when the escort objective becomes active and persist until release.
var active_escorts: Dictionary = {}
# npc_id -> true — EVER joined during this run, across chapters. World-continuity
# companions keep stable world ids, so a `carried_over` chapter_start join in a
# later chapter only applies when the player really recruited them earlier.
# Deliberately NOT cleared by load_chapter_party (only by reset()); save-persisted.
var joined_history: Dictionary = {}
var _textures: Dictionary = {}         # npc_id -> Texture2D (companion walk sheet)
var _portraits: Dictionary = {}        # npc_id -> Texture2D (happy face portrait, cropped)
var _escort_textures: Dictionary = {}  # npc_id -> Texture2D (escort walk sheet)
var _escort_portraits: Dictionary = {} # npc_id -> Texture2D (escort portrait, cropped)
var _fired: Dictionary = {}            # event_id -> true (one-shot)
var _pending_join_events: Dictionary = {} # event_id -> event dict waiting for NPC quest work to finish
var _loading_party_catalog: bool = false
var _lifecycle_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	QuestManager.npc_talked.connect(_on_npc_talked)
	QuestManager.quests_changed.connect(_on_quests_changed)
	InventoryManager.item_obtained.connect(_on_item_obtained)


func reset() -> void:
	_lifecycle_id += 1
	companions.clear()
	events = []
	active_members.clear()
	escorts.clear()
	active_escorts.clear()
	joined_history.clear()
	_textures.clear()
	_portraits.clear()
	_escort_textures.clear()
	_escort_portraits.clear()
	_loading_party_catalog = false
	_fired.clear()
	_pending_join_events.clear()


# ── loading ─────────────────────────────────────────────────────────────────────


## ChapterFlow calls this before replacing QuestManager's catalog. It prevents a
## quests_changed emitted by the half-loaded next chapter from reconciling against
## the previous chapter's escort roster (and briefly spawning/toasting twice).
func begin_chapter_party_load() -> void:
	_loading_party_catalog = true
	active_escorts.clear()


func load_chapter_party(party_payload: Dictionary) -> void:
	_loading_party_catalog = true
	companions.clear()
	escorts.clear()
	events = party_payload.get("events", []) as Array
	active_members.clear()
	active_escorts.clear()
	_escort_textures.clear()
	_escort_portraits.clear()
	_fired.clear()
	_pending_join_events.clear()
	for raw in party_payload.get("companions", []) as Array:
		if raw is Dictionary:
			var npc_id := str((raw as Dictionary).get("npc_id", ""))
			if not npc_id.is_empty():
				companions[npc_id] = raw
	for raw in party_payload.get("escorts", []) as Array:
		if raw is Dictionary:
			var npc_id := str((raw as Dictionary).get("npc_id", "")).strip_edges()
			if not npc_id.is_empty():
				escorts[npc_id] = (raw as Dictionary).duplicate(true)
	print("[Party] loaded %d companion(s), %d escort(s), %d event(s)" % [
		companions.size(), escorts.size(), events.size(),
	])
	# chapter_start joins fire immediately
	_evaluate("chapter_start", {})
	# Quest definitions/progress load before the party catalog in ChapterFlow, so an
	# objective may already be active here (chapter revisit). Reconcile immediately.
	_sync_active_escorts()
	_loading_party_catalog = false


func set_companion_texture(npc_id: String, texture: Texture2D) -> void:
	if texture != null:
		_textures[npc_id] = texture


func set_companion_portrait(npc_id: String, sheet: Texture2D) -> void:
	# The portrait sheet is a 2x2 emotion grid (neutral / happy / angry / sad).
	# The "happy" face (top-right) is the warm one for a join celebration.
	if sheet == null:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var half_w := sheet.get_width() / 2
	var half_h := sheet.get_height() / 2
	atlas.region = Rect2(half_w, 0, half_w, half_h)
	_portraits[npc_id] = atlas


func companion_portrait(npc_id: String) -> Texture2D:
	return _portraits.get(npc_id, null) as Texture2D


func set_escort_texture(npc_id: String, texture: Texture2D) -> void:
	if texture != null:
		_escort_textures[npc_id] = texture


func set_escort_portrait(npc_id: String, sheet: Texture2D) -> void:
	if sheet == null:
		return
	_escort_portraits[npc_id] = _happy_portrait_from_sheet(sheet)


func _happy_portrait_from_sheet(sheet: Texture2D) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	var half_w := sheet.get_width() / 2
	var half_h := sheet.get_height() / 2
	atlas.region = Rect2(half_w, 0, half_w, half_h)
	return atlas


# ── queries ─────────────────────────────────────────────────────────────────────


func is_companion(npc_id: String) -> bool:
	return companions.has(npc_id)


func is_member(npc_id: String) -> bool:
	return active_members.has(npc_id)


func active_member_ids() -> Array:
	return active_members.keys()


func companion_texture(npc_id: String) -> Texture2D:
	return _textures.get(npc_id, null) as Texture2D


func companion_name(npc_id: String) -> String:
	return str((companions.get(npc_id, {}) as Dictionary).get("name", npc_id))


## Backend-authored battle skill ids for this companion (the LLM-picked set from
## SceneBuilder's companion-skills step, riding on public_party as `skills`).
## Empty when the payload predates the skill system — GameManager then falls back
## to the combat-role default set.
func companion_skill_ids(npc_id: String) -> Array:
	var data: Dictionary = companions.get(npc_id, {}) as Dictionary
	var skills: Variant = data.get("skills", [])
	if skills is Array and not (skills as Array).is_empty():
		return (skills as Array).duplicate()
	var nested: Dictionary = data.get("companion", {}) as Dictionary
	var nested_skills: Variant = nested.get("skills", [])
	if nested_skills is Array:
		return (nested_skills as Array).duplicate()
	return []


## Combat role drives the party passive bonus in GameManager. Values authored by the
## SceneBuilder party step: attacker / support / healer / tank / none.
func companion_combat_role(npc_id: String) -> String:
	var data: Dictionary = companions.get(npc_id, {}) as Dictionary
	var role := str(data.get("combat_role", "")).strip_edges().to_lower()
	if role.is_empty():
		# Some payloads nest it under a `companion` block; fall back to that.
		var nested: Dictionary = data.get("companion", {}) as Dictionary
		role = str(nested.get("combat_role", "support")).strip_edges().to_lower()
	return role if role in ["attacker", "support", "healer", "tank", "none"] else "support"


# ── escort queries / lifecycle ────────────────────────────────────────────────


func is_escort(npc_id: String) -> bool:
	return escorts.has(npc_id)


func is_escort_active(npc_id: String) -> bool:
	return active_escorts.has(npc_id)


func active_escort_ids() -> Array:
	return active_escorts.keys()


func escort_data(npc_id: String) -> Dictionary:
	if active_escorts.has(npc_id):
		return (active_escorts[npc_id] as Dictionary).duplicate(true)
	return (escorts.get(npc_id, {}) as Dictionary).duplicate(true)


func escort_name(npc_id: String) -> String:
	var data: Dictionary = active_escorts.get(npc_id, escorts.get(npc_id, {})) as Dictionary
	return str(data.get("name", npc_id))


func escort_texture(npc_id: String) -> Texture2D:
	return _escort_textures.get(npc_id, null) as Texture2D


func escort_portrait(npc_id: String) -> Texture2D:
	return _escort_portraits.get(npc_id, null) as Texture2D


func escort_max_hp(npc_id: String) -> int:
	var data: Dictionary = active_escorts.get(npc_id, {}) as Dictionary
	return maxi(0, int(data.get("max_hp", 0)))


func get_escort_hp(npc_id: String) -> int:
	var data: Dictionary = active_escorts.get(npc_id, {}) as Dictionary
	if data.is_empty():
		return 0
	return clampi(int(data.get("hp", data.get("max_hp", 0))), 0, int(data.get("max_hp", 0)))


func set_escort_hp(npc_id: String, value: int) -> void:
	if not active_escorts.has(npc_id):
		return
	var data: Dictionary = active_escorts[npc_id] as Dictionary
	data["hp"] = clampi(value, 0, int(data.get("max_hp", 0)))
	SaveManager.request_autosave()


func reset_escort_hp(npc_id: String) -> void:
	if not active_escorts.has(npc_id):
		return
	var data: Dictionary = active_escorts[npc_id] as Dictionary
	data["hp"] = int(data.get("max_hp", 0))
	SaveManager.request_autosave()


func reset_all_escort_hp() -> void:
	for npc_id in active_escorts.keys():
		var data: Dictionary = active_escorts[npc_id] as Dictionary
		data["hp"] = int(data.get("max_hp", 0))
	SaveManager.request_autosave()


## True while this actor should be represented by PartyFollower in `zone_id`.
## The destination is intentionally excluded: Main builds the authored stationary
## NPC there before QuestManager completes the reach objective, avoiding a frame
## with neither actor (or a follower + NPC duplicate).
func should_follow_in_zone(npc_id: String, zone_id: String) -> bool:
	if is_member(npc_id):
		return true
	if not active_escorts.has(npc_id):
		return false
	var data: Dictionary = active_escorts[npc_id] as Dictionary
	var destination := str(data.get("destination_zone_id", "")).strip_edges()
	return destination.is_empty() or destination != zone_id


## Stable follower ordering: combat companions first, protected escorts after them.
## An actor present in both lanes is emitted once only.
func follower_ids_for_zone(zone_id: String) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for raw_id in active_member_ids():
		var npc_id := str(raw_id)
		if seen.has(npc_id) or not should_follow_in_zone(npc_id, zone_id):
			continue
		seen[npc_id] = true
		result.append(npc_id)
	for raw_id in active_escort_ids():
		var npc_id := str(raw_id)
		if seen.has(npc_id) or not should_follow_in_zone(npc_id, zone_id):
			continue
		seen[npc_id] = true
		result.append(npc_id)
	return result


func travelling_texture(npc_id: String) -> Texture2D:
	if is_member(npc_id):
		return companion_texture(npc_id)
	return escort_texture(npc_id)


## Public mainly for focused runtime smoke tests. Authored play normally starts
## escorts exclusively through _sync_active_escorts and a current quest objective.
func start_escort(npc_id: String, config: Dictionary = {}) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or active_escorts.has(npc_id):
		return false
	_activate_escort(npc_id, config)
	return active_escorts.has(npc_id)


func end_escort(npc_id: String) -> bool:
	if not active_escorts.has(npc_id):
		return false
	var runtime: Dictionary = active_escorts[npc_id] as Dictionary
	active_escorts.erase(npc_id)
	escort_left.emit(npc_id)
	if not bool(runtime.get("silent", false)):
		_toast_after_narrative.call_deferred(
			"Hoàn tất hộ tống %s" % str(runtime.get("name", escort_name(npc_id))),
			_lifecycle_id,
		)
	SaveManager.request_autosave()
	print("[Party] escort %s released" % npc_id)
	return true


# ── event intake ────────────────────────────────────────────────────────────────


## Choice-consequence: a moral choice forces a companion to join or leave the
## party right now. Reuses the trigger pipeline's _apply so the join popup,
## joined_history, deferred-join guard, and toasts all behave as usual.
## Returns true when the roster actually changed.
func force_party_change(npc_id: String, action: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not action in ["join", "leave"]:
		return false
	var before := active_members.size()
	_apply({
		"id": "choice:%s:%s" % [action, npc_id],
		"companion_id": npc_id,
		"action": action,
		"source": "choice",
	})
	return active_members.size() != before


func notify_zone_entered(zone_id: String) -> void:
	_evaluate("zone_enter", {"zone_id": zone_id})


func notify_enemy_defeated(enemy_id: String) -> void:
	_evaluate("enemy_defeated", {"enemy_id": enemy_id})


func _on_npc_talked(npc_id: String) -> void:
	_evaluate("npc_talked", {"npc_id": npc_id})


func _on_item_obtained(item_id: String) -> void:
	_evaluate("item_obtained", {"item_id": item_id})


func _on_quests_changed() -> void:
	if _loading_party_catalog:
		return
	_sync_active_escorts()
	_retry_pending_joins()
	# quest_objective / quest_complete are evaluated against live QuestManager state
	for event in events:
		if not (event is Dictionary) or _fired.has(str((event as Dictionary).get("id", ""))):
			continue
		var trigger: Dictionary = (event as Dictionary).get("trigger", {}) as Dictionary
		match str(trigger.get("type", "")):
			"quest_complete":
				var st: Dictionary = QuestManager.quest_states.get(str(trigger.get("quest_id", "")), {}) as Dictionary
				if str(st.get("state")) == "completed":
					_apply(event as Dictionary)
			"quest_objective":
				var need: int = int(trigger.get("objective_index", 1))
				if QuestManager.completed_objective_count(str(trigger.get("quest_id", ""))) >= need:
					_apply(event as Dictionary)


## Reconcile the escort lane from quest truth. An escort exists exactly while an
## active quest's CURRENT objective contains an `escort` modifier. No dialogue
## link or NPC kind mutation is needed, and loading a save naturally rebuilds the
## same state once QuestManager emits quests_changed.
func _sync_active_escorts() -> void:
	if QuestManager.quests.is_empty():
		# QuestManager.reset happens before PartyManager.reset in the new/continue
		# pipelines. Clear quietly: this is teardown, not a completed escort.
		active_escorts.clear()
		return
	var desired: Dictionary = _desired_escort_specs()
	for raw_id in active_escorts.keys().duplicate():
		var npc_id := str(raw_id)
		var current: Dictionary = active_escorts.get(npc_id, {}) as Dictionary
		var wanted: Dictionary = desired.get(npc_id, {}) as Dictionary
		var identity_changed := not wanted.is_empty() and (
			str(current.get("quest_id", "")) != str(wanted.get("quest_id", ""))
			or str(current.get("objective_id", "")) != str(wanted.get("objective_id", ""))
		)
		if wanted.is_empty() or identity_changed:
			end_escort(npc_id)

	for raw_id in desired.keys():
		var npc_id := str(raw_id)
		var spec: Dictionary = desired[npc_id] as Dictionary
		if active_escorts.has(npc_id):
			# Refresh authored metadata without touching the HP snapshot restored from
			# a save or damaged in an earlier encounter.
			var runtime: Dictionary = active_escorts[npc_id] as Dictionary
			for key in spec.keys():
				if str(key) not in ["hp", "max_hp"]:
					runtime[key] = spec[key]
		else:
			_activate_escort(npc_id, spec)


func _desired_escort_specs() -> Dictionary:
	var desired: Dictionary = {}
	for raw_quest in QuestManager.quests:
		if not (raw_quest is Dictionary):
			continue
		var quest: Dictionary = raw_quest as Dictionary
		var quest_id := str(quest.get("id", ""))
		var state: Dictionary = QuestManager.quest_states.get(quest_id, {}) as Dictionary
		if str(state.get("state", "")) != "active":
			continue
		var objectives: Array = quest.get("objectives", []) as Array
		var objective_index := int(state.get("objective_index", -1))
		if objective_index < 0 or objective_index >= objectives.size() \
				or not (objectives[objective_index] is Dictionary):
			continue
		var objective: Dictionary = objectives[objective_index] as Dictionary
		var modifier_value: Variant = objective.get("escort", {})
		if not (modifier_value is Dictionary) or (modifier_value as Dictionary).is_empty():
			continue
		var modifier: Dictionary = modifier_value as Dictionary
		var ids: Array = []
		var authored_ids: Variant = modifier.get("npc_ids", [])
		if authored_ids is Array:
			ids = (authored_ids as Array).duplicate()
		var singular := str(modifier.get("npc_id", "")).strip_edges()
		if ids.is_empty() and not singular.is_empty():
			ids.append(singular)
		for raw_id in ids:
			var npc_id := str(raw_id).strip_edges()
			if npc_id.is_empty() or desired.has(npc_id):
				continue
			var spec: Dictionary = modifier.duplicate(true)
			spec["npc_id"] = npc_id
			spec["quest_id"] = quest_id
			spec["objective_id"] = str(objective.get("id", ""))
			spec["destination_zone_id"] = str(modifier.get(
				"destination_zone_id", objective.get("zone_id", "")
			))
			if str(spec.get("start_zone_id", "")).is_empty():
				spec["start_zone_id"] = QuestManager.current_zone_id
			spec["battle_mode"] = str(spec.get("battle_mode", "protected"))
			spec["can_act"] = false
			spec["hp_mode"] = "player_max_snapshot"
			spec["on_complete"] = str(spec.get("on_complete", "release"))
			desired[npc_id] = spec
	return desired


func _activate_escort(npc_id: String, config: Dictionary) -> void:
	if npc_id.is_empty() or active_escorts.has(npc_id):
		return
	var runtime: Dictionary = (escorts.get(npc_id, {}) as Dictionary).duplicate(true)
	for key in config.keys():
		runtime[key] = config[key]
	runtime["npc_id"] = npc_id
	runtime["battle_mode"] = str(runtime.get("battle_mode", "protected"))
	runtime["can_act"] = false
	runtime["hp_mode"] = "player_max_snapshot"
	runtime["on_complete"] = str(runtime.get("on_complete", "release"))
	var max_hp := maxi(1, int(GameManager.player_battle_stats().get("max_hp", 1)))
	runtime["max_hp"] = max_hp
	runtime["hp"] = max_hp
	active_escorts[npc_id] = runtime
	escort_joined.emit(npc_id)
	if not _loading_party_catalog and not bool(runtime.get("silent", false)):
		_show_escort_join_popup(npc_id)
	SaveManager.request_autosave()
	print("[Party] escort %s joined (hp=%d destination=%s)" % [
		npc_id, max_hp, str(runtime.get("destination_zone_id", "")),
	])


# ── matching / application ───────────────────────────────────────────────────────


func _evaluate(event_type: String, params: Dictionary) -> void:
	for event in events:
		if not (event is Dictionary):
			continue
		if _fired.has(str((event as Dictionary).get("id", ""))):
			continue
		if _trigger_matches((event as Dictionary).get("trigger", {}) as Dictionary, event_type, params):
			_apply(event as Dictionary)


func _trigger_matches(trigger: Dictionary, event_type: String, params: Dictionary) -> bool:
	if str(trigger.get("type", "")) != event_type:
		return false
	match event_type:
		"chapter_start":
			return true
		"npc_talked":
			return str(trigger.get("npc_id", "")) == str(params.get("npc_id", ""))
		"zone_enter":
			return str(trigger.get("zone_id", "")) == str(params.get("zone_id", ""))
		"enemy_defeated":
			return str(trigger.get("enemy_id", "")) == str(params.get("enemy_id", ""))
		"item_obtained":
			var want := str(trigger.get("item_ref", ""))
			return want.is_empty() or want == str(params.get("item_id", ""))
		_:
			return false


func _apply(event: Dictionary) -> void:
	var event_id := str(event.get("id", ""))
	var npc_id := str(event.get("companion_id", ""))
	if npc_id.is_empty():
		_fired[event_id] = true
		return
	match str(event.get("action", "")):
		"join":
			if active_members.has(npc_id):
				_fired[event_id] = true
				_pending_join_events.erase(event_id)
				return
			var carried := bool(event.get("carried_over", false))
			if carried and not joined_history.has(npc_id):
				# Carried-over join from a previous chapter, but the player never
				# actually recruited them there — don't force the party member.
				_fired[event_id] = true
				_pending_join_events.erase(event_id)
				return
			if QuestManager.has_method("has_unresolved_npc_objectives") \
					and QuestManager.has_unresolved_npc_objectives(npc_id):
				_defer_join(event)
				return
			active_members[npc_id] = true
			joined_history[npc_id] = true
			_fired[event_id] = true
			_pending_join_events.erase(event_id)
			# Begin tracking this companion's XP/level the moment they join the party.
			GameManager.ensure_companion(npc_id)
			member_joined.emit(npc_id)
			if carried:
				# Quiet re-join at chapter start — no fanfare popup on every chapter.
				_toast("%s tiếp tục đồng hành" % companion_name(npc_id))
			else:
				_show_join_popup(npc_id)
			print("[Party] %s joined%s" % [npc_id, " (carried over)" if carried else ""])
		"leave":
			_fired[event_id] = true
			if not active_members.has(npc_id):
				return
			active_members.erase(npc_id)
			member_left.emit(npc_id)
			_toast("%s đã rời đoàn" % companion_name(npc_id))
			print("[Party] %s left" % npc_id)


func _defer_join(event: Dictionary) -> void:
	var event_id := str(event.get("id", ""))
	if event_id.is_empty():
		return
	if not _pending_join_events.has(event_id):
		_pending_join_events[event_id] = event.duplicate(true)
		print("[Party] %s join deferred until NPC quest work is done" % event.get("companion_id", ""))


func _retry_pending_joins() -> void:
	if _pending_join_events.is_empty():
		return
	for event_id in _pending_join_events.keys().duplicate():
		if _fired.has(str(event_id)):
			_pending_join_events.erase(str(event_id))
			continue
		var event: Dictionary = _pending_join_events.get(str(event_id), {}) as Dictionary
		if event.is_empty():
			_pending_join_events.erase(str(event_id))
			continue
		_apply(event)


func _show_join_popup(npc_id: String) -> void:
	var companion: Dictionary = companions.get(npc_id, {}) as Dictionary
	# Joins earned mid-conversation play as a full-screen ceremony in the
	# announcement queue; outside conversations keep the classic slide-in popup.
	if AnnouncementCenter.enqueue("companion", {
		"name": companion_name(npc_id),
		"role": str(companion.get("role", "")),
		"portrait": companion_portrait(npc_id),
	}):
		return
	var popup: CanvasLayer = PartyJoinPopupScript.new()
	# Deferred (in order) so it is safe even when a join fires mid-_ready / during a
	# scene build; the add lands first (popup enters tree → _ready), then show_member
	# runs with the popup already in-tree so its tween binds correctly.
	get_tree().root.add_child.call_deferred(popup)
	popup.show_member.call_deferred({
		"name": companion_name(npc_id),
		"role": str(companion.get("role", "")),
		"portrait": companion_portrait(npc_id),
	})


func _show_escort_join_popup(npc_id: String) -> void:
	# In dialogue, queue behind the handoff exactly like companion joins. ChatBox is
	# above the lightweight popup layer, so showing the fallback immediately there
	# would let it expire invisibly before the conversation closes.
	var payload := {
		"name": escort_name(npc_id),
		"portrait": escort_portrait(npc_id),
	}
	if AnnouncementCenter.enqueue("escort", payload):
		return
	# Open-world/manual activation keeps the non-blocking slide-in presentation.
	var popup: CanvasLayer = PartyJoinPopupScript.new()
	get_tree().root.add_child.call_deferred(popup)
	popup.show_member.call_deferred({
		"kind": "escort",
		"name": payload["name"],
		"portrait": payload["portrait"],
	})


func _toast(text: String) -> void:
	# reuse the inventory toast channel for a quick, consistent notification
	if InventoryManager.has_method("_push_toast"):
		InventoryManager._push_toast("✦ %s" % text)


func _toast_after_narrative(text: String, lifecycle_id: int) -> void:
	# Arrival also advances the reach objective and may trigger a cutscene/ceremony.
	# Inventory's lightweight toast layer sits beneath those screens, so wait until
	# they release input instead of letting the completion message expire invisibly.
	while AnnouncementCenter.conversation_active or AnnouncementCenter.playing \
			or AnnouncementCenter.has_pending() or CutsceneDirector.has_pending_playback() \
			or GameManager.ui_blocking_input:
		if lifecycle_id != _lifecycle_id:
			return
		await get_tree().process_frame
	if lifecycle_id != _lifecycle_id:
		return
	_toast(text)


# ── persistence (SaveManager) ──────────────────────────────────────────────────


func serialize_save() -> Dictionary:
	return {
		"active_members": active_members.duplicate(true),
		"active_escorts": active_escorts.duplicate(true),
		"fired": _fired.duplicate(true),
		"joined_history": joined_history.duplicate(true),
		"pending_join_events": _pending_join_events.duplicate(true),
	}


## Restore party membership from a save. Does NOT re-emit member_joined (no join
## popup on load); Main spawns followers for active_member_ids() when the world builds.
func apply_save(data: Dictionary) -> void:
	active_members = (data.get("active_members", {}) as Dictionary).duplicate(true)
	active_escorts = (data.get("active_escorts", {}) as Dictionary).duplicate(true)
	_fired = (data.get("fired", {}) as Dictionary).duplicate(true)
	joined_history = (data.get("joined_history", {}) as Dictionary).duplicate(true)
	_pending_join_events = (data.get("pending_join_events", {}) as Dictionary).duplicate(true)
	# Older saves predate joined_history — backfill from whoever is in the party.
	for npc_id in active_members.keys():
		joined_history[str(npc_id)] = true
		GameManager.ensure_companion(str(npc_id))
	# Sanitize persisted escort health without recomputing max HP. The contract is
	# player_max_snapshot, so a later player level/passive change must not alter it.
	for raw_id in active_escorts.keys().duplicate():
		var npc_id := str(raw_id).strip_edges()
		var runtime: Dictionary = active_escorts.get(raw_id, {}) as Dictionary
		if npc_id.is_empty() or runtime.is_empty():
			active_escorts.erase(raw_id)
			continue
		var max_hp := maxi(1, int(runtime.get("max_hp", 1)))
		runtime["npc_id"] = npc_id
		runtime["max_hp"] = max_hp
		runtime["hp"] = clampi(int(runtime.get("hp", max_hp)), 0, max_hp)
		runtime["can_act"] = false
		runtime["hp_mode"] = "player_max_snapshot"
		if raw_id != npc_id:
			active_escorts.erase(raw_id)
			active_escorts[npc_id] = runtime
