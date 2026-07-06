extends Node

const TILE_SIZE := 72  # world pixel density: 72 px/tile (Option C)
const CHARACTER_SHEET_SIZE := Vector2i(288, 288)
const CHARACTER_SPRITE_GRID := Vector2i(4, 4)
const CHARACTER_FRAME_SIZE := TILE_SIZE
const DEFAULT_PLAYER_SPRITE_PATH := "res://assets/sprites/player/godot_sheet.png"
const IMPORT_ROOT_DIR := "user://imports"
const SCENE_IMPORT_DIR := "user://imports/scene_package"
const PLAYER_IMPORT_DIR := "user://imports/player"
const WORLD_SCENE_PATH := "res://scenes/world/Main.tscn"
const API_BASE_URL := "http://127.0.0.1:5001"

# On web exports the page is served with a same-origin /api proxy to the
# backend (see run_game.sh). HTTPRequest needs absolute URLs, so use the
# page origin (e.g. http://localhost:8000) instead of 127.0.0.1:5001.
func api_base_url() -> String:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and not str(origin).is_empty():
			return str(origin)
	return API_BASE_URL

var player_data := {
	"health": 100,
	"max_health": 100,
	"level": 1,
	"experience": 0,
}

# ── combat / progression ──────────────────────────────────────────────────────
## The protagonist AND every active companion share one progression spine: a level
## curve, XP from battles, and XP from talking to NPCs (a quest beat is worth more
## than a piece of world lore). Stats are derived from level, then a party passive
## bonus from the companions currently travelling with the player is layered on top.
## Everything here is serialized by SaveManager so it survives zone changes AND
## quitting the game ("lưu giữ các thông số xuyên suốt các zone").

signal player_stats_changed
## Emitted when a companion gains a level: (npc_id, new_level).
signal companion_leveled(npc_id: String, level: int)
## Emitted when talk-XP is granted so the world can pop a floating toast:
## (category "quest"|"world", amount, recipients = ["You", companion names...]).
signal talk_xp_awarded(category: String, amount: int, recipients: Array)

# Talk-XP economy. Engaging with a quest beat teaches more than idle world chatter,
# so the two are deliberately different amounts (the user's requirement). Each is
# awarded ONCE per unique conversation node (tracked in talk_log).
const TALK_XP_QUEST := 14
const TALK_XP_WORLD := 7
# Companions share a fraction of whatever XP the protagonist earns (battles + talk).
const COMPANION_XP_SHARE := 0.7

# Level-gap XP governor ("rubber band"): every XP source is scaled by how far the
# player has out-leveled the content it comes from (the enemy's own level in battle,
# the zone's expected player level for conversation — see enemy_balance.py, whose
# expected_player_level anchor this mirrors). Measured on real chapter-1 data, the
# raw talk pool alone (~6100 XP) would push a diligent talker past level 20 against
# a level-6 boss; with this table every engaged playstyle converges to level 7-9
# instead, while a player 2+ levels BELOW the content catches up 25% faster.
# Floor XP_GAP_MIN_FACTOR keeps a trickle (never 0 — talking must always feel
# rewarded), and gain_xp's floor of 1 XP guarantees at least a point.
const XP_GAP_FACTORS := {1: 0.7, 2: 0.45, 3: 0.25}
const XP_GAP_MIN_FACTOR := 0.1
const XP_GAP_CATCHUP_FACTOR := 1.25  # when 2+ levels below the content


## The balance anchor conversation XP scales against: the current zone's expected
## player level from ChapterFlow. Looked up by path (not the global identifier) so
## GameManager still runs in isolation (scripts/dev/ProgressionSmoke.gd) — with no
## ChapterFlow the anchor is 1, which at level 1 means full-value talk XP.
func _talk_reference_level() -> int:
	if not is_inside_tree():
		return 1
	var flow: Node = get_node_or_null("/root/ChapterFlow")
	if flow != null:
		return int(flow.expected_level_here())
	return 1


## Multiplier for XP earned from content anchored at `reference_level` (an enemy's
## level, or a zone's expected player level). Over-leveling the content shrinks the
## reward toward XP_GAP_MIN_FACTOR; being well under it grants a catch-up bonus.
func xp_gap_factor(reference_level: int) -> float:
	var gap: int = player_level - maxi(1, reference_level)
	if gap <= -2:
		return XP_GAP_CATCHUP_FACTOR
	if gap <= 0:
		return 1.0
	return float(XP_GAP_FACTORS.get(gap, XP_GAP_MIN_FACTOR))

var player_level: int = 1
var player_xp: int = 0
var player_hp: int = -1  # -1 = full (computed lazily from level)
var defeated_enemy_ids: Dictionary = {}
var spared_enemy_ids: Dictionary = {}
# "zone_id:item_definition_id:spawn_index" -> true for every world-pickup instance
# ever collected (spawn order is deterministic per zone — see Main._spawn_item_pickups
# — so this index is a stable identity across reloads). Checked before spawning so a
# picked-up item never respawns just by leaving and re-entering the zone.
var collected_item_pickup_ids: Dictionary = {}
# String(chapter_number) -> true once that chapter's story is done (all main
# quests completed + its boss zone reached — see ChapterFlow._check_chapter_
# completion). Unlocks the NEXT chapter on the world map; the player travels
# there on their own schedule, nothing auto-advances.
var completed_chapter_numbers: Dictionary = {}
# npc_id -> {"level": int, "xp": int}. Only companions who have joined the party
# accrue progression (they are the ones learning alongside the protagonist).
var companion_progress: Dictionary = {}
# Dedup ledger for talk-XP: "<npc_id>::<node_id>" -> category already awarded.
# This is the "đã nhận điểm kinh nghiệm chưa" history the game must remember.
var talk_log: Dictionary = {}

func _base_player_stats() -> Dictionary:
	return {
		"max_hp": 60 + 20 * player_level,
		"attack": 9 + 3 * player_level,
		"defense": 3 + 2 * player_level,
		"speed": 8 + player_level,
		"sp_max": 3 + int(player_level / 2.0),
	}

## Final protagonist combat stats = base (from level) + the active party's passive
## bonus. Used by BattleScene every time it opens / refreshes.
func player_battle_stats() -> Dictionary:
	var stats: Dictionary = _base_player_stats()
	var bonus: Dictionary = party_passive_bonus()
	stats["max_hp"] = int(round(stats["max_hp"] * float(bonus.get("max_hp_mult", 1.0))))
	stats["attack"] = int(round(stats["attack"] * float(bonus.get("attack_mult", 1.0))))
	stats["defense"] = int(round(stats["defense"] * float(bonus.get("defense_mult", 1.0))))
	stats["sp_max"] = int(stats["sp_max"]) + int(bonus.get("sp_bonus", 0))
	stats["party_regen"] = int(bonus.get("regen", 0))
	stats["party_xp_mult"] = float(bonus.get("xp_mult", 1.0))
	return stats

func get_player_hp() -> int:
	var max_hp: int = int(player_battle_stats()["max_hp"])
	if player_hp < 0 or player_hp > max_hp:
		player_hp = max_hp
	return player_hp

func set_player_hp(value: int) -> void:
	player_hp = clampi(value, 0, int(player_battle_stats()["max_hp"]))
	player_stats_changed.emit()

func xp_to_next_level() -> int:
	return xp_to_next_level_for(player_level)

func xp_to_next_level_for(level: int) -> int:
	return 30 * maxi(level, 1)

## Protagonist-only XP. Returns levels gained. Prefer grant_party_xp() for anything
## the whole party earns together (battles, quests, conversations).
func gain_xp(amount: int) -> int:
	var levels_gained := 0
	player_xp += max(amount, 0)
	while player_xp >= xp_to_next_level():
		player_xp -= xp_to_next_level()
		player_level += 1
		levels_gained += 1
		player_hp = -1  # level up fully heals
	player_stats_changed.emit()
	if levels_gained > 0:
		_autosave()
	return levels_gained

## Party-wide XP: the protagonist gains the full amount; every companion currently
## travelling with the player gains a share. Returns the protagonist's levels gained.
func grant_party_xp(amount: int) -> int:
	amount = max(amount, 0)
	var levels_gained := gain_xp(amount)
	var share: int = int(round(amount * COMPANION_XP_SHARE))
	if share > 0:
		for npc_id in active_companion_ids():
			gain_companion_xp(str(npc_id), share)
	_autosave()
	return levels_gained

func lose_xp_on_defeat() -> void:
	player_xp = int(player_xp * 0.75)
	player_hp = -1
	player_stats_changed.emit()
	_autosave()

# ── talk-XP (quest beats vs. world lore) ───────────────────────────────────────
## Award conversation XP the FIRST time the player reaches a given dialogue node.
## category: "quest" (a story beat) or "world" (a piece of lore) — different worth.
## Returns {awarded, category, amount, recipients, player_levels} for the UI.
func award_talk_xp(npc_id: String, node_id: String, category: String) -> Dictionary:
	var key := "%s::%s" % [npc_id, node_id]
	if talk_log.has(key):
		return {"awarded": false}
	talk_log[key] = category
	var base_amount: int = TALK_XP_QUEST if category == "quest" else TALK_XP_WORLD
	# Conversation XP is anchored to the zone the conversation happens in: once the
	# player out-levels what this zone expects, chatter teaches less and less.
	var amount: int = maxi(1, int(round(base_amount * xp_gap_factor(_talk_reference_level()))))
	var recipients: Array = ["Bạn"]
	for cid in active_companion_ids():
		recipients.append(_companion_display_name(str(cid)))
	var levels := grant_party_xp(amount)
	talk_xp_awarded.emit(category, amount, recipients)
	return {
		"awarded": true,
		"category": category,
		"amount": amount,
		"recipients": recipients,
		"player_levels": levels,
	}

func has_logged_talk(npc_id: String, node_id: String) -> bool:
	return talk_log.has("%s::%s" % [npc_id, node_id])

# ── companion progression ──────────────────────────────────────────────────────

func _party_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/PartyManager")

func active_companion_ids() -> Array:
	# PartyManager is a sibling autoload; read the members travelling right now.
	var pm: Node = _party_manager()
	if pm != null and pm.has_method("active_member_ids"):
		return pm.active_member_ids()
	return []

func ensure_companion(npc_id: String) -> Dictionary:
	if not companion_progress.has(npc_id):
		# New companions start near the protagonist so they are immediately useful.
		var start_level: int = maxi(1, player_level - 1)
		companion_progress[npc_id] = {
			"level": start_level,
			"xp": 0,
		}
	return companion_progress[npc_id]

func companion_level(npc_id: String) -> int:
	return int(ensure_companion(npc_id).get("level", 1))

func companion_xp(npc_id: String) -> int:
	return int(ensure_companion(npc_id).get("xp", 0))

func gain_companion_xp(npc_id: String, amount: int) -> int:
	var data: Dictionary = ensure_companion(npc_id)
	var levels_gained := 0
	data["xp"] = int(data.get("xp", 0)) + max(amount, 0)
	while int(data["xp"]) >= xp_to_next_level_for(int(data["level"])):
		data["xp"] = int(data["xp"]) - xp_to_next_level_for(int(data["level"]))
		data["level"] = int(data["level"]) + 1
		levels_gained += 1
	if levels_gained > 0:
		companion_leveled.emit(npc_id, int(data["level"]))
	return levels_gained

## A companion's own combat sheet — used for the party passive bonus and any UI.
func companion_battle_stats(npc_id: String) -> Dictionary:
	var level: int = companion_level(npc_id)
	return {
		"level": level,
		"max_hp": 50 + 16 * level,
		"attack": 7 + 3 * level,
		"defense": 3 + 2 * level,
		"speed": 7 + level,
	}

func _companion_role(npc_id: String) -> String:
	var pm: Node = _party_manager()
	if pm != null and pm.has_method("companion_combat_role"):
		return str(pm.companion_combat_role(npc_id))
	return "support"

func _companion_display_name(npc_id: String) -> String:
	var pm: Node = _party_manager()
	if pm != null and pm.has_method("companion_name"):
		return str(pm.companion_name(npc_id))
	return npc_id

## Aggregate passive bonus from every companion travelling with the player, scaled
## by each companion's level and shaped by their combat role. Kept gentle and capped
## so a full party is a clear help without trivializing fights.
func party_passive_bonus() -> Dictionary:
	var bonus := {
		"attack_mult": 1.0,
		"defense_mult": 1.0,
		"max_hp_mult": 1.0,
		"sp_bonus": 0,
		"regen": 0,
		"xp_mult": 1.0,
		"members": [],
	}
	for npc_id in active_companion_ids():
		var id := str(npc_id)
		var level: int = companion_level(id)
		match _companion_role(id):
			"attacker":
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.04 * level, 0.30)
			"tank":
				bonus["defense_mult"] = float(bonus["defense_mult"]) + minf(0.05 * level, 0.40)
				bonus["max_hp_mult"] = float(bonus["max_hp_mult"]) + minf(0.03 * level, 0.25)
			"healer":
				bonus["regen"] = int(bonus["regen"]) + 1 + int(level / 2.0)
				bonus["max_hp_mult"] = float(bonus["max_hp_mult"]) + minf(0.015 * level, 0.12)
			"support":
				bonus["sp_bonus"] = int(bonus["sp_bonus"]) + (1 if level >= 3 else 0)
				bonus["xp_mult"] = float(bonus["xp_mult"]) + minf(0.04 * level, 0.25)
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.015 * level, 0.12)
			_:
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.01 * level, 0.10)
		bonus["members"].append({"npc_id": id, "level": level, "role": _companion_role(id)})
	# Global guard rails so a large party never gets out of hand.
	bonus["attack_mult"] = minf(float(bonus["attack_mult"]), 1.6)
	bonus["defense_mult"] = minf(float(bonus["defense_mult"]), 1.7)
	bonus["max_hp_mult"] = minf(float(bonus["max_hp_mult"]), 1.5)
	bonus["regen"] = mini(int(bonus["regen"]), 12)
	bonus["xp_mult"] = minf(float(bonus["xp_mult"]), 1.5)
	return bonus

# ── skills (data-driven; richer roster that unlocks as you level) ───────────────
## Each skill: id, name, power (attack multiplier), sp_cost, unlock_level, effect,
## desc. `effect` drives BattleScene's dispatch: "" / "attack" = a power strike,
## "focus" = empower next hit, "heal" = restore HP (power = HP per caster level),
## "multi" = several hits (hits = power rounded), "pierce" = ignore most defense.
##
## unlock_level is spread across the WHOLE 5-chapter journey, not just chapter 1.
## Each threshold beyond the starter pair lines up with that chapter's boss level:
## a boss zone typically sits ~3 map-hops from its chapter's entrance, so
## enemy_balance.scaled_enemy_level(chapter, 3, "boss", is_boss_zone=true) works out
## to 3*(chapter+1) — 6, 9, 12, 15, 18 for chapters 1-5 (mirrors the real chapter-1
## generation: its boss zone was distance 3, boss level 6). Landing a new skill right
## at each chapter's boss level means the player unlocks their next tool DURING that
## chapter, in time to use it on the fight it was paced for — and the roster still has
## something left to unlock all the way to the true final boss (level 18, the
## MAX_ENEMY_LEVEL ceiling), instead of maxing out by the end of chapter 1.
const SKILL_LIBRARY: Array = [
	{"id": "strike", "name": "Strike", "power": 1.0, "sp_cost": 0, "unlock_level": 1, "effect": "attack",
		"desc": "A basic attack. Costs no SP."},
	{"id": "power_strike", "name": "Power Strike", "power": 1.6, "sp_cost": 1, "unlock_level": 1, "effect": "attack",
		"desc": "Channel your strength into one heavy blow."},
	{"id": "focus", "name": "Focus", "power": 0.0, "sp_cost": 1, "unlock_level": 3, "effect": "focus",
		"desc": "Your next attack hits twice as hard."},
	{"id": "ember_slash", "name": "Ember Slash", "power": 1.9, "sp_cost": 2, "unlock_level": 6, "effect": "attack",
		"desc": "A blade wreathed in fire that scorches the foe."},
	{"id": "crush", "name": "Crushing Blow", "power": 2.2, "sp_cost": 2, "unlock_level": 9, "effect": "attack",
		"desc": "A devastating, full-force strike."},
	{"id": "mend", "name": "Mend", "power": 18.0, "sp_cost": 2, "unlock_level": 12, "effect": "heal",
		"desc": "Gather your focus to restore your own HP."},
	{"id": "tempest", "name": "Tempest", "power": 3.0, "sp_cost": 3, "unlock_level": 15, "effect": "multi",
		"desc": "Unleash a flurry of chained slashes."},
	{"id": "pierce", "name": "Pierce", "power": 2.0, "sp_cost": 3, "unlock_level": 18, "effect": "pierce",
		"desc": "A thrust that punches through the enemy's defense."},
]

func player_skills() -> Array[Dictionary]:
	var unlocked: Array[Dictionary] = []
	for skill in SKILL_LIBRARY:
		if player_level >= int((skill as Dictionary)["unlock_level"]):
			unlocked.append((skill as Dictionary).duplicate(true))
	return unlocked

## Skills the player has NOT unlocked yet — handy for a "next unlock" UI hint.
func locked_skills() -> Array[Dictionary]:
	var locked: Array[Dictionary] = []
	for skill in SKILL_LIBRARY:
		if player_level < int((skill as Dictionary)["unlock_level"]):
			locked.append((skill as Dictionary).duplicate(true))
	return locked

func mark_enemy_defeated(enemy_id: String) -> void:
	defeated_enemy_ids[enemy_id] = true
	_autosave()

func mark_enemy_spared(enemy_id: String) -> void:
	spared_enemy_ids[enemy_id] = true
	_autosave()

func mark_item_pickup_collected(pickup_id: String) -> void:
	if pickup_id.is_empty():
		return
	collected_item_pickup_ids[pickup_id] = true
	_autosave()

func is_item_pickup_collected(pickup_id: String) -> bool:
	return collected_item_pickup_ids.has(pickup_id)

func mark_chapter_completed(chapter_number: int) -> void:
	completed_chapter_numbers[str(chapter_number)] = true
	_autosave()

func is_chapter_completed(chapter_number: int) -> bool:
	return completed_chapter_numbers.has(str(chapter_number))

func reset_combat_progress() -> void:
	player_level = 1
	player_xp = 0
	player_hp = -1
	defeated_enemy_ids.clear()
	spared_enemy_ids.clear()
	companion_progress.clear()
	talk_log.clear()
	collected_item_pickup_ids.clear()
	completed_chapter_numbers.clear()

# ── serialization (consumed by SaveManager) ────────────────────────────────────

func serialize_progress() -> Dictionary:
	return {
		"player_level": player_level,
		"player_xp": player_xp,
		"player_hp": player_hp,
		"defeated_enemy_ids": defeated_enemy_ids.duplicate(true),
		"spared_enemy_ids": spared_enemy_ids.duplicate(true),
		"companion_progress": companion_progress.duplicate(true),
		"talk_log": talk_log.duplicate(true),
		"collected_item_pickup_ids": collected_item_pickup_ids.duplicate(true),
		"completed_chapter_numbers": completed_chapter_numbers.duplicate(true),
	}

func apply_progress(data: Dictionary) -> void:
	player_level = maxi(1, int(data.get("player_level", 1)))
	player_xp = maxi(0, int(data.get("player_xp", 0)))
	player_hp = int(data.get("player_hp", -1))
	defeated_enemy_ids = (data.get("defeated_enemy_ids", {}) as Dictionary).duplicate(true)
	spared_enemy_ids = (data.get("spared_enemy_ids", {}) as Dictionary).duplicate(true)
	companion_progress = (data.get("companion_progress", {}) as Dictionary).duplicate(true)
	talk_log = (data.get("talk_log", {}) as Dictionary).duplicate(true)
	collected_item_pickup_ids = (data.get("collected_item_pickup_ids", {}) as Dictionary).duplicate(true)
	completed_chapter_numbers = (data.get("completed_chapter_numbers", {}) as Dictionary).duplicate(true)
	player_stats_changed.emit()

func _autosave() -> void:
	if not is_inside_tree():
		return
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("request_autosave"):
		sm.request_autosave()

func get_enemy_roster() -> Array:
	var enemies: Dictionary = imported_scene_package.get("enemies", {}) as Dictionary
	var roster: Array = enemies.get("roster", []) as Array
	var valid: Array = []
	for item in roster:
		if item is Dictionary and not str((item as Dictionary).get("id", "")).is_empty():
			valid.append(item)
	return valid

var imported_scene_package: Dictionary = {}
var imported_scene_root_dir: String = ""
var imported_player_sprite_path: String = ""
var imported_scene_context: Dictionary = {}
var ui_blocking_input: bool = false

## Clear the imported SCENE only. Combat/progression is intentionally NOT reset here
## anymore — it must survive moving between zones ("lưu giữ các thông số xuyên suốt
## các zone"). A brand-new game resets progression explicitly via reset_combat_progress()
## (see ChapterFlow.start_new_game).
func reset_runtime_imports(clear_files := false) -> void:
	imported_scene_package.clear()
	imported_scene_root_dir = ""
	imported_player_sprite_path = ""
	imported_scene_context.clear()
	if clear_files:
		_remove_tree(IMPORT_ROOT_DIR)

func has_scene_package() -> bool:
	return not imported_scene_package.is_empty() and not imported_scene_root_dir.is_empty()

func get_scene_package() -> Dictionary:
	return imported_scene_package.duplicate(true)

func get_scene_context() -> Dictionary:
	return imported_scene_context.duplicate(true)

func get_scene_asset_path(relative_path: String) -> String:
	if imported_scene_root_dir.is_empty() or relative_path.is_empty():
		return ""
	return imported_scene_root_dir.path_join(relative_path)

func get_player_sprite_path() -> String:
	return imported_player_sprite_path if not imported_player_sprite_path.is_empty() else DEFAULT_PLAYER_SPRITE_PATH

func import_scene_package_zip(zip_path: String) -> Error:
	print("[GameManager] import_scene_package_zip path='%s'" % zip_path)
	_remove_tree(SCENE_IMPORT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_IMPORT_DIR))

	var zip_reader: ZIPReader = ZIPReader.new()
	var open_error: Error = zip_reader.open(zip_path)
	if open_error != OK:
		print("[GameManager] zip open failed err=%d" % open_error)
		return open_error

	var scene_json_internal_path: String = ""
	var zip_files: PackedStringArray = zip_reader.get_files()
	print("[GameManager] zip file count=%d" % zip_files.size())
	for internal_path in zip_files:
		if internal_path.get_file() == "scene_package.json":
			scene_json_internal_path = internal_path
			break

	if scene_json_internal_path.is_empty():
		zip_reader.close()
		print("[GameManager] scene_package.json missing in zip")
		return ERR_FILE_NOT_FOUND

	for internal_path in zip_files:
		if internal_path.ends_with("/"):
			continue
		var bytes: PackedByteArray = zip_reader.read_file(internal_path)
		var output_path: String = SCENE_IMPORT_DIR.path_join(internal_path)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
		var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output_file == null:
			zip_reader.close()
			return FileAccess.get_open_error()
		output_file.store_buffer(bytes)

	zip_reader.close()

	var scene_json_path: String = SCENE_IMPORT_DIR.path_join(scene_json_internal_path)
	var json_file: FileAccess = FileAccess.open(scene_json_path, FileAccess.READ)
	if json_file == null:
		return FileAccess.get_open_error()

	var scene_json_text: String = json_file.get_as_text()
	var parsed_data: Variant = JSON.parse_string(scene_json_text)
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR

	var scene_root_dir: String = scene_json_path.get_base_dir()
	var load_error: Error = _apply_scene_package(parsed_data as Dictionary, scene_root_dir)
	if load_error != OK:
		print("[GameManager] apply scene package failed err=%d" % load_error)
		return load_error
	print("[GameManager] import complete root='%s'" % imported_scene_root_dir)
	return OK

func load_scene_package_file(scene_json_path: String) -> Error:
	var json_file: FileAccess = FileAccess.open(scene_json_path, FileAccess.READ)
	if json_file == null:
		return FileAccess.get_open_error()

	var parsed_data: Variant = JSON.parse_string(json_file.get_as_text())
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR

	return _apply_scene_package(parsed_data as Dictionary, scene_json_path.get_base_dir())

func import_player_sprite(sprite_path: String) -> Error:
	_remove_tree(PLAYER_IMPORT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAYER_IMPORT_DIR))

	var extension: String = sprite_path.get_extension().to_lower()
	if extension.is_empty():
		extension = "png"

	var source_file: FileAccess = FileAccess.open(sprite_path, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()

	var source_image: Image = Image.new()
	var image_error: Error = source_image.load(sprite_path)
	if image_error != OK:
		return image_error
	if source_image.get_size() != CHARACTER_SHEET_SIZE:
		return ERR_INVALID_DATA

	var destination_path: String = PLAYER_IMPORT_DIR.path_join("player_sprite.%s" % extension)
	var destination_file: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		return FileAccess.get_open_error()

	destination_file.store_buffer(source_file.get_buffer(source_file.get_length()))
	imported_player_sprite_path = destination_path
	return OK

func load_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null

	if texture_path.begins_with("res://"):
		return load(texture_path) as Texture2D

	var image: Image = Image.new()
	var error: Error = image.load(texture_path)
	if error != OK:
		print("[GameManager] load_texture FAILED path='%s' err=%d" % [texture_path, error])
		return null

	return ImageTexture.create_from_image(image)

func get_map_tile_size(package_data: Dictionary, background_texture: Texture2D) -> Vector2i:
	var max_tile := Vector2i.ZERO
	for cell in package_data.get("background_collision", []):
		if cell is Array and cell.size() >= 2:
			max_tile.x = max(max_tile.x, int(cell[0]))
			max_tile.y = max(max_tile.y, int(cell[1]))

	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var instance_id: String = str(instance.get("id", ""))
		var definition: Dictionary = definitions.get(instance_id, {}) as Dictionary
		var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		max_tile.x = max(max_tile.x, int(position_tile.get("x", 0)) + max(int(size_tiles.get("w", 1)) - 1, 0))
		max_tile.y = max(max_tile.y, int(position_tile.get("y", 0)) + max(int(size_tiles.get("h", 1)) - 1, 0))

	if background_texture != null:
		max_tile.x = max(max_tile.x, int(round(float(background_texture.get_width()) / TILE_SIZE)) - 1)
		max_tile.y = max(max_tile.y, int(round(float(background_texture.get_height()) / TILE_SIZE)) - 1)

	return max_tile + Vector2i.ONE

func get_map_pixel_size(package_data: Dictionary, background_texture: Texture2D) -> Vector2:
	var tile_size: Vector2i = get_map_tile_size(package_data, background_texture)
	if background_texture != null:
		return Vector2(background_texture.get_width(), background_texture.get_height())
	return Vector2(tile_size.x * TILE_SIZE, tile_size.y * TILE_SIZE)

func find_spawn_tile(package_data: Dictionary, background_texture: Texture2D) -> Vector2i:
	var blocked_tiles: Dictionary = get_blocked_tiles(package_data)
	var map_tile_size: Vector2i = get_map_tile_size(package_data, background_texture)
	var center: Vector2 = Vector2(map_tile_size) / 2.0
	var best_tile: Vector2i = Vector2i.ZERO
	var best_score: float = INF

	for y in range(map_tile_size.y):
		for x in range(map_tile_size.x):
			var candidate: Vector2i = Vector2i(x, y)
			if _blocked_tiles_has(blocked_tiles, candidate):
				continue

			var score: float = center.distance_squared_to(Vector2(candidate) + Vector2(0.5, 0.5))
			if score < best_score:
				best_score = score
				best_tile = candidate

	return best_tile

func get_blocked_tiles(package_data: Dictionary) -> Dictionary:
	var blocked_tiles := {}
	for cell in package_data.get("background_collision", []):
		if cell is Array and cell.size() >= 2:
			blocked_tiles[_tile_key(Vector2i(int(cell[0]), int(cell[1])))] = true

	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var definition: Dictionary = definitions.get(str(instance.get("id", "")), {}) as Dictionary
		if not bool(definition.get("solid", false)):
			continue

		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		var base_tile: Vector2i = Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
		for collision_cell in definition.get("collision", []):
			if collision_cell is Array and collision_cell.size() >= 2:
				var tile: Vector2i = base_tile + Vector2i(int(collision_cell[0]), int(collision_cell[1]))
				blocked_tiles[_tile_key(tile)] = true

	return blocked_tiles

func get_character_sprite_grid(texture: Texture2D, texture_path := "") -> Vector2i:
	if texture == null:
		return CHARACTER_SPRITE_GRID
	if Vector2i(texture.get_width(), texture.get_height()) != CHARACTER_SHEET_SIZE:
		push_warning("Character spritesheet should be 144x144 px: %s" % texture_path)
	return CHARACTER_SPRITE_GRID

func infer_player_sprite_grid(texture: Texture2D, texture_path: String) -> Vector2i:
	return get_character_sprite_grid(texture, texture_path)

func _definitions_by_id(package_data: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	for definition in package_data.get("definitions", []):
		if definition is Dictionary:
			definitions[str(definition.get("id", ""))] = definition
	return definitions

func _apply_scene_package(package_data: Dictionary, scene_root_dir: String) -> Error:
	var characters_for_log: Dictionary = package_data.get("characters", {}) as Dictionary
	var npcs_for_log: Array = characters_for_log.get("npcs", []) as Array
	print("[GameManager] apply_scene_package root='%s' definitions=%d instances=%d npcs=%d" % [
		scene_root_dir,
		(package_data.get("definitions", []) as Array).size(),
		(package_data.get("instances", []) as Array).size(),
		npcs_for_log.size(),
	])
	if not package_data.has("background_image"):
		print("[GameManager] package missing background_image")
		return ERR_INVALID_DATA
	if not package_data.has("definitions"):
		print("[GameManager] package missing definitions")
		return ERR_INVALID_DATA
	if not package_data.has("instances"):
		print("[GameManager] package missing instances")
		return ERR_INVALID_DATA

	var background_path: String = scene_root_dir.path_join(str(package_data.get("background_image", "")))
	if not FileAccess.file_exists(background_path):
		print("[GameManager] background missing path='%s'" % background_path)
		return ERR_FILE_NOT_FOUND

	for definition in package_data.get("definitions", []):
		if not (definition is Dictionary):
			continue
		var file_name: String = str(definition.get("file", ""))
		if file_name.is_empty():
			print("[GameManager] definition has empty file id='%s'" % str(definition.get("id", "")))
			return ERR_INVALID_DATA
		if not FileAccess.file_exists(scene_root_dir.path_join(file_name)):
			print("[GameManager] definition file missing path='%s'" % scene_root_dir.path_join(file_name))
			return ERR_FILE_NOT_FOUND

	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var main_character: Dictionary = characters.get("main_character", {}) as Dictionary
	var main_sprite_file: String = str(main_character.get("sprite_sheet_file", ""))
	if not main_sprite_file.is_empty():
		var main_sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(main_sprite_file))
		if main_sprite_error != OK:
			print("[GameManager] main sprite invalid path='%s' err=%d" % [scene_root_dir.path_join(main_sprite_file), main_sprite_error])
			return main_sprite_error

	for npc in characters.get("npcs", []):
		if not (npc is Dictionary):
			continue
		var sprite_file: String = str((npc as Dictionary).get("sprite_sheet_file", ""))
		if sprite_file.is_empty() or sprite_file == "<null>":
			# NPC without a generated sheet — the runtime uses a fallback sprite.
			continue
		var sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(sprite_file))
		if sprite_error != OK:
			print("[GameManager] npc sprite invalid id='%s' path='%s' err=%d" % [
				str((npc as Dictionary).get("id", "")),
				scene_root_dir.path_join(sprite_file),
				sprite_error,
			])
			return sprite_error

	imported_scene_package = package_data
	imported_scene_root_dir = scene_root_dir
	imported_scene_context = package_data.get("scene_context", {}) as Dictionary
	if not main_sprite_file.is_empty():
		imported_player_sprite_path = scene_root_dir.path_join(main_sprite_file)
	return OK

func _validate_character_sprite_file(sprite_path: String) -> Error:
	if not FileAccess.file_exists(sprite_path):
		return ERR_FILE_NOT_FOUND

	if sprite_path.begins_with("res://"):
		var texture: Texture2D = load(sprite_path) as Texture2D
		if texture == null:
			return ERR_FILE_CANT_OPEN
		if Vector2i(texture.get_width(), texture.get_height()) != CHARACTER_SHEET_SIZE:
			return ERR_INVALID_DATA
		return OK

	var image: Image = Image.new()
	var image_error: Error = image.load(sprite_path)
	if image_error != OK:
		return image_error
	if image.get_size() != CHARACTER_SHEET_SIZE:
		return ERR_INVALID_DATA
	return OK

func _blocked_tiles_has(blocked_tiles: Dictionary, tile: Vector2i) -> bool:
	return blocked_tiles.has(_tile_key(tile))

func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]

func _remove_tree(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return

	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry == "." or entry == "..":
			entry = directory.get_next()
			continue
		var child_path: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
		entry = directory.get_next()
	directory.list_dir_end()

	DirAccess.remove_absolute(absolute_path)
