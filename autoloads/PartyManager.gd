extends Node
## Party / companion runtime. Companions (e.g. Arlo) JOIN or LEAVE the protagonist's
## group on authored story triggers (`party_events`), and while in the party they
## follow the player across every zone. Mirrors the QuestManager / CutsceneDirector
## pattern: it loads chapter data, matches events against the same fixed trigger
## vocabulary, and exposes signals the world (Main) reacts to.

signal member_joined(npc_id: String)
signal member_left(npc_id: String)

const PartyJoinPopupScript := preload("res://scripts/ui/PartyJoinPopup.gd")

# npc_id -> {name, combat_role, joins_party, zones, sprite_url}
var companions: Dictionary = {}
var events: Array = []                 # party_events
var active_members: Dictionary = {}    # npc_id -> true (currently travelling with the player)
# npc_id -> true — EVER joined during this run, across chapters. World-continuity
# companions keep stable world ids, so a `carried_over` chapter_start join in a
# later chapter only applies when the player really recruited them earlier.
# Deliberately NOT cleared by load_chapter_party (only by reset()); save-persisted.
var joined_history: Dictionary = {}
var _textures: Dictionary = {}         # npc_id -> Texture2D (companion walk sheet)
var _portraits: Dictionary = {}        # npc_id -> Texture2D (happy face portrait, cropped)
var _fired: Dictionary = {}            # event_id -> true (one-shot)
var _pending_join_events: Dictionary = {} # event_id -> event dict waiting for NPC quest work to finish


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	QuestManager.npc_talked.connect(_on_npc_talked)
	QuestManager.quests_changed.connect(_on_quests_changed)
	InventoryManager.item_obtained.connect(_on_item_obtained)


func reset() -> void:
	companions.clear()
	events = []
	active_members.clear()
	joined_history.clear()
	_textures.clear()
	_portraits.clear()
	_fired.clear()
	_pending_join_events.clear()


# ── loading ─────────────────────────────────────────────────────────────────────


func load_chapter_party(party_payload: Dictionary) -> void:
	companions.clear()
	events = party_payload.get("events", []) as Array
	active_members.clear()
	_fired.clear()
	_pending_join_events.clear()
	for raw in party_payload.get("companions", []) as Array:
		if raw is Dictionary:
			var npc_id := str((raw as Dictionary).get("npc_id", ""))
			if not npc_id.is_empty():
				companions[npc_id] = raw
	print("[Party] loaded %d companion(s), %d event(s)" % [companions.size(), events.size()])
	# chapter_start joins fire immediately
	_evaluate("chapter_start", {})


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


# ── event intake ────────────────────────────────────────────────────────────────


func notify_zone_entered(zone_id: String) -> void:
	_evaluate("zone_enter", {"zone_id": zone_id})


func notify_enemy_defeated(enemy_id: String) -> void:
	_evaluate("enemy_defeated", {"enemy_id": enemy_id})


func _on_npc_talked(npc_id: String) -> void:
	_evaluate("npc_talked", {"npc_id": npc_id})


func _on_item_obtained(item_id: String) -> void:
	_evaluate("item_obtained", {"item_id": item_id})


func _on_quests_changed() -> void:
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


func _toast(text: String) -> void:
	# reuse the inventory toast channel for a quick, consistent notification
	if InventoryManager.has_method("_push_toast"):
		InventoryManager._push_toast("✦ %s" % text)


# ── persistence (SaveManager) ──────────────────────────────────────────────────


func serialize_save() -> Dictionary:
	return {
		"active_members": active_members.duplicate(true),
		"fired": _fired.duplicate(true),
		"joined_history": joined_history.duplicate(true),
		"pending_join_events": _pending_join_events.duplicate(true),
	}


## Restore party membership from a save. Does NOT re-emit member_joined (no join
## popup on load); Main spawns followers for active_member_ids() when the world builds.
func apply_save(data: Dictionary) -> void:
	active_members = (data.get("active_members", {}) as Dictionary).duplicate(true)
	_fired = (data.get("fired", {}) as Dictionary).duplicate(true)
	joined_history = (data.get("joined_history", {}) as Dictionary).duplicate(true)
	_pending_join_events = (data.get("pending_join_events", {}) as Dictionary).duplicate(true)
	# Older saves predate joined_history — backfill from whoever is in the party.
	for npc_id in active_members.keys():
		joined_history[str(npc_id)] = true
		GameManager.ensure_companion(str(npc_id))
