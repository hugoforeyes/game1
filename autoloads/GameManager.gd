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
# npc_id -> {"level": int, "xp": int, "hp": int}. Only companions who have joined
# the party accrue progression (they are the ones learning alongside the
# protagonist). "hp" persists between battles like the player's own (-1 = full).
var companion_progress: Dictionary = {}
# Dedup ledger for talk-XP. New entries are scoped by chapter + zone so a recurring
# NPC may legitimately reuse a dialogue-node id elsewhere in the story. Legacy
# saves used "<npc_id>::<node_id>" and are migrated lazily on first encounter.
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

## Choice-consequence: XP drained by a moral choice. Only eats progress within
## the current level — a choice never de-levels the hero. Returns the actual loss.
func lose_xp(amount: int) -> int:
	var lost: int = clampi(amount, 0, player_xp)
	if lost <= 0:
		return 0
	player_xp -= lost
	player_stats_changed.emit()
	_autosave()
	return lost

## Choice-consequence: damage/heal the hero by a percentage of max HP.
## Never lethal (floors at 1 HP). Returns the signed HP change actually applied.
func apply_hp_percent(percent: float) -> int:
	var max_hp: int = int(player_battle_stats()["max_hp"])
	var current: int = get_player_hp()
	var target: int = clampi(current + int(round(max_hp * percent / 100.0)), 1, max_hp)
	if target == current:
		return 0
	set_player_hp(target)
	_autosave()
	return target - current

# ── talk-XP (quest beats vs. world lore) ───────────────────────────────────────
## Award conversation XP the FIRST time the player reaches a given dialogue node.
## category: "quest" (a story beat) or "world" (a piece of lore) — different worth.
## Returns {awarded, category, amount, recipients, player_levels} for the UI.
func award_talk_xp(npc_id: String, node_id: String, category: String) -> Dictionary:
	var key := _scoped_talk_key(npc_id, node_id)
	if talk_log.has(key):
		return {"awarded": false}
	var legacy_key := _legacy_talk_key(npc_id, node_id)
	if talk_log.has(legacy_key):
		# An old save proves this beat already paid once, but not where. Claim it for
		# the current scope, remove the ambiguous key, and allow other scopes later.
		talk_log[key] = talk_log[legacy_key]
		talk_log.erase(legacy_key)
		_autosave()
		return {"awarded": false, "migrated": true}
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
	return talk_log.has(_scoped_talk_key(npc_id, node_id)) \
		or talk_log.has(_legacy_talk_key(npc_id, node_id))


func _scoped_talk_key(npc_id: String, node_id: String) -> String:
	var context: Dictionary = get_scene_context()
	var chapter := str(context.get("chapter", context.get("chapter_key", "0")))
	var zone_id := str(context.get("zone_id", "unknown"))
	return "v2::chapter=%s::zone=%s::%s::%s" % [chapter, zone_id, npc_id, node_id]


func _legacy_talk_key(npc_id: String, node_id: String) -> String:
	return "%s::%s" % [npc_id, node_id]

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
			"hp": -1,
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
		data["hp"] = -1  # level up fully heals, mirroring the protagonist
		levels_gained += 1
	if levels_gained > 0:
		companion_leveled.emit(npc_id, int(data["level"]))
	return levels_gained

## A companion's own combat sheet — now that companions FIGHT actively in battle,
## this is their real actor sheet (HP/attack/defense/speed/SP), tuned slightly
## below the protagonist's own curve so the hero stays the strongest member.
func companion_battle_stats(npc_id: String) -> Dictionary:
	var level: int = companion_level(npc_id)
	return {
		"level": level,
		"max_hp": 50 + 16 * level,
		"attack": 7 + 3 * level,
		"defense": 3 + 2 * level,
		"speed": 7 + level,
		"sp_max": 2 + int(level / 3.0),
	}

## Persistent companion HP (between battles), mirroring the player's lazy pattern:
## -1 means "full", clamped to the level-derived max.
func get_companion_hp(npc_id: String) -> int:
	var data: Dictionary = ensure_companion(npc_id)
	var max_hp: int = int(companion_battle_stats(npc_id)["max_hp"])
	var hp: int = int(data.get("hp", -1))
	if hp < 0 or hp > max_hp:
		data["hp"] = max_hp
		hp = max_hp
	return hp

func set_companion_hp(npc_id: String, value: int) -> void:
	var data: Dictionary = ensure_companion(npc_id)
	var max_hp: int = int(companion_battle_stats(npc_id)["max_hp"])
	# Keep the same lazy "full health" sentinel used by player_hp. Battle defeat
	# and level-up recovery deliberately pass -1 so the next read resolves against
	# the companion's CURRENT level-derived maximum instead of freezing an old max.
	data["hp"] = -1 if value < 0 else clampi(value, 0, max_hp)
	player_stats_changed.emit()

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
## by each companion's level and shaped by their combat role. Since the multi-actor
## battle rework, companions FIGHT actively (their own turn, HP, skills) — the
## passive layer is therefore HALVED versus its original values: it now reads as
## "travelling together sharpens you", not as the companion's whole contribution.
## Encounters also scale in enemy count with party size (see BattleScene), so the
## passive must stay a garnish or a full party would double-dip.
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
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.02 * level, 0.15)
			"tank":
				bonus["defense_mult"] = float(bonus["defense_mult"]) + minf(0.025 * level, 0.20)
				bonus["max_hp_mult"] = float(bonus["max_hp_mult"]) + minf(0.015 * level, 0.12)
			"healer":
				bonus["regen"] = int(bonus["regen"]) + 1 + int(level / 4.0)
				bonus["max_hp_mult"] = float(bonus["max_hp_mult"]) + minf(0.008 * level, 0.06)
			"support":
				bonus["sp_bonus"] = int(bonus["sp_bonus"]) + (1 if level >= 3 else 0)
				bonus["xp_mult"] = float(bonus["xp_mult"]) + minf(0.04 * level, 0.25)
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.008 * level, 0.06)
			_:
				bonus["attack_mult"] = float(bonus["attack_mult"]) + minf(0.005 * level, 0.05)
		bonus["members"].append({"npc_id": id, "level": level, "role": _companion_role(id)})
	# Global guard rails so a large party never gets out of hand.
	bonus["attack_mult"] = minf(float(bonus["attack_mult"]), 1.3)
	bonus["defense_mult"] = minf(float(bonus["defense_mult"]), 1.35)
	bonus["max_hp_mult"] = minf(float(bonus["max_hp_mult"]), 1.25)
	bonus["regen"] = mini(int(bonus["regen"]), 6)
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

# ── status effects (shared vocabulary for the multi-actor battle) ───────────────
## Every battle status an actor (ally OR enemy) can carry. BattleScene owns the
## per-instance state ({id, turns_left, magnitude}); this table is the immutable
## definition. Numeric fields are MULTIPLIERS unless suffixed otherwise.
##   tick_pct      damage per turn as a fraction of max HP (poison/burn)
##   tick_heal     flat healing per turn (regen — magnitude set by the caster)
##   skip_turn     actor loses their action while active (freeze/sleep/stun)
##   skip_chance   probability of losing the action each turn (paralyze)
##   wake_on_hit   taking damage removes the status (sleep)
##   hit_chance    actor's chance for their attacks to connect (blind)
##   no_skills     actor may only use a basic strike (silence)
##   speed_mult    turn-order speed scaling (slow/haste)
##   crit_bonus    additive crit chance (haste)
##   attack_mult / defense_mult   outgoing damage / damage-taken shaping
##   taunt         enemies must target this actor (tank provoke)
##   absorb        the instance's magnitude is a damage-absorbing pool (shield)
const STATUS_LIBRARY: Dictionary = {
	"poison": {"name": "Poison", "kind": "debuff", "turns": 3, "tick_pct": 0.08},
	"burn": {"name": "Burn", "kind": "debuff", "turns": 2, "tick_pct": 0.06, "attack_mult": 0.85},
	"freeze": {"name": "Freeze", "kind": "debuff", "turns": 1, "skip_turn": true},
	"sleep": {"name": "Sleep", "kind": "debuff", "turns": 3, "skip_turn": true, "wake_on_hit": true},
	"paralyze": {"name": "Paralyze", "kind": "debuff", "turns": 2, "skip_chance": 0.5},
	"stun": {"name": "Stun", "kind": "debuff", "turns": 1, "skip_turn": true},
	"blind": {"name": "Blind", "kind": "debuff", "turns": 2, "hit_chance": 0.5},
	"silence": {"name": "Silence", "kind": "debuff", "turns": 2, "no_skills": true},
	"slow": {"name": "Slow", "kind": "debuff", "turns": 3, "speed_mult": 0.6},
	"haste": {"name": "Haste", "kind": "buff", "turns": 3, "speed_mult": 1.4, "crit_bonus": 0.15},
	"shield": {"name": "Shield", "kind": "buff", "turns": 3, "absorb": true},
	"regen": {"name": "Regen", "kind": "buff", "turns": 3, "tick_heal": true},
	"attack_up": {"name": "Attack Up", "kind": "buff", "turns": 3, "attack_mult": 1.25},
	"defense_up": {"name": "Defense Up", "kind": "buff", "turns": 3, "defense_mult": 1.2},
	"weaken": {"name": "Weaken", "kind": "debuff", "turns": 3, "attack_mult": 0.75},
	"armor_break": {"name": "Armor Break", "kind": "debuff", "turns": 3, "defense_mult": 0.65},
	"taunt": {"name": "Provoke", "kind": "buff", "turns": 2, "taunt": true},
}

# ── companion skill pool (companions draw a random-feeling, LLM-chosen set) ─────
## The protagonist keeps the fixed SKILL_LIBRARY above; companions instead carry a
## PERSONAL set of 4 skills picked from this pool by the backend LLM step
## (SceneBuilder utils/chapter_companion_skills.py — the catalog there MUST mirror
## this table; change both together). Slot N unlocks at COMPANION_SKILL_SLOT_LEVELS[N]
## of the COMPANION's own level, so a freshly-joined friend grows into their kit.
## Schema mirrors SKILL_LIBRARY plus:
##   effect   attack | multi | drain | heal | heal_all | shield | cleanse | revive | status
##   status / status_chance   status applied on hit (attack) or directly (status)
##   target   enemy | ally | ally_all | self  (which side the skill points at)
##   roles    which combat_role archetypes favour it (used by the BE fallback)
const COMPANION_SKILL_POOL: Dictionary = {
	"venom_fang": {"name": "Venom Fang", "power": 1.2, "sp_cost": 1, "effect": "attack",
		"status": "poison", "status_chance": 0.9, "target": "enemy", "roles": ["attacker"],
		"desc": "A toxic bite that leaves the foe poisoned."},
	"flame_burst": {"name": "Flame Burst", "power": 1.4, "sp_cost": 2, "effect": "attack",
		"status": "burn", "status_chance": 0.85, "target": "enemy", "roles": ["attacker"],
		"desc": "An explosive blast that sets the foe ablaze."},
	"frost_lance": {"name": "Frost Lance", "power": 1.3, "sp_cost": 2, "effect": "attack",
		"status": "freeze", "status_chance": 0.6, "target": "enemy", "roles": ["attacker"],
		"desc": "An ice lance that can freeze the foe solid."},
	"thunder_jolt": {"name": "Thunder Jolt", "power": 1.3, "sp_cost": 2, "effect": "attack",
		"status": "paralyze", "status_chance": 0.55, "target": "enemy", "roles": ["attacker"],
		"desc": "A lightning strike that may paralyze."},
	"shadow_drain": {"name": "Shadow Drain", "power": 1.2, "sp_cost": 2, "effect": "drain",
		"target": "enemy", "roles": ["attacker"],
		"desc": "Steal the foe's life force to mend your own."},
	"wild_flurry": {"name": "Wild Flurry", "power": 2.0, "sp_cost": 2, "effect": "multi",
		"target": "enemy", "roles": ["attacker"],
		"desc": "A feral storm of quick slashes."},
	"skull_crack": {"name": "Skull Crack", "power": 1.1, "sp_cost": 3, "effect": "attack",
		"status": "stun", "status_chance": 0.7, "target": "enemy", "roles": ["attacker", "tank"],
		"desc": "A heavy blow that can stun the foe."},
	"armor_break": {"name": "Armor Break", "power": 1.0, "sp_cost": 2, "effect": "attack",
		"status": "armor_break", "status_chance": 1.0, "target": "enemy", "roles": ["attacker", "tank"],
		"desc": "Shatter the foe's guard, lowering its defense."},
	"lullaby": {"name": "Lullaby", "power": 0.0, "sp_cost": 2, "effect": "status",
		"status": "sleep", "status_chance": 0.85, "target": "enemy", "roles": ["support"],
		"desc": "A drowsy melody that sings the foe to sleep."},
	"blinding_dust": {"name": "Blinding Dust", "power": 0.0, "sp_cost": 1, "effect": "status",
		"status": "blind", "status_chance": 0.9, "target": "enemy", "roles": ["support"],
		"desc": "A cloud of dust that makes attacks miss."},
	"silencing_seal": {"name": "Silencing Seal", "power": 0.0, "sp_cost": 2, "effect": "status",
		"status": "silence", "status_chance": 0.9, "target": "enemy", "roles": ["support"],
		"desc": "A rune that seals away the foe's techniques."},
	"slow_mire": {"name": "Slowing Mire", "power": 0.0, "sp_cost": 1, "effect": "status",
		"status": "slow", "status_chance": 1.0, "target": "enemy", "roles": ["support"],
		"desc": "Clinging mire that drags the foe's pace down."},
	"war_cry": {"name": "War Cry", "power": 0.0, "sp_cost": 2, "effect": "status",
		"status": "attack_up", "status_chance": 1.0, "target": "ally_all", "roles": ["support", "tank"],
		"desc": "A rallying cry that raises the party's attack."},
	"stone_ward": {"name": "Stone Ward", "power": 0.0, "sp_cost": 2, "effect": "shield",
		"target": "ally", "roles": ["support", "healer", "tank"],
		"desc": "Raise a stone barrier that absorbs damage."},
	"quicksilver": {"name": "Quicksilver", "power": 0.0, "sp_cost": 2, "effect": "status",
		"status": "haste", "status_chance": 1.0, "target": "ally", "roles": ["support"],
		"desc": "Hasten an ally to act sooner and strike truer."},
	"purify": {"name": "Purify", "power": 0.0, "sp_cost": 1, "effect": "cleanse",
		"target": "ally", "roles": ["support", "healer"],
		"desc": "Cleanse an ally's ailments and soothe wounds."},
	"soothing_light": {"name": "Soothing Light", "power": 16.0, "sp_cost": 2, "effect": "heal",
		"target": "ally", "roles": ["healer"],
		"desc": "A gentle light that restores an ally's HP."},
	"verdant_rain": {"name": "Verdant Rain", "power": 10.0, "sp_cost": 3, "effect": "heal_all",
		"target": "ally_all", "roles": ["healer"],
		"desc": "Healing rain that mends the whole party."},
	"regrowth": {"name": "Regrowth", "power": 0.0, "sp_cost": 2, "effect": "status",
		"status": "regen", "status_chance": 1.0, "target": "ally", "roles": ["healer"],
		"desc": "Blessing of growth that heals over time."},
	"guiding_star": {"name": "Guiding Star", "power": 0.0, "sp_cost": 3, "effect": "revive",
		"target": "ally", "roles": ["healer"],
		"desc": "Call a fallen ally back to their feet."},
	"taunt": {"name": "Provoke", "power": 0.0, "sp_cost": 1, "effect": "status",
		"status": "taunt", "status_chance": 1.0, "target": "self", "roles": ["tank"],
		"desc": "Draw every foe's fury onto yourself."},
	"iron_bastion": {"name": "Iron Bastion", "power": 0.0, "sp_cost": 2, "effect": "shield",
		"target": "self", "roles": ["tank"],
		"desc": "Become a living fortress behind heavy iron."},
	"shield_bash": {"name": "Shield Bash", "power": 0.9, "sp_cost": 2, "effect": "attack",
		"status": "stun", "status_chance": 0.4, "target": "enemy", "roles": ["tank"],
		"desc": "Slam the shield forward — it may stun."},
}

# ── enemy skill pool (hostile mirror of the companion pool) ─────────────────────
## Enemies carry a PERSONAL loadout of skills picked by the backend LLM step
## (SceneBuilder utils/scene_enemy_skills.py — the catalog there MUST mirror this
## table; change both together). The backend owns which ids an enemy gets (and a
## Vietnamese telegraph line per pick); this table owns every combat number.
## Schema (per skill):
##   effect          attack | multi | aoe | drain | heal | shield | status
##   power           attack multiplier (aoe = per-target), heal = flat base
##   hits            multi only — number of strikes
##   pierce          attack ignores most defense
##   status / status_chance   STATUS_LIBRARY id applied on hit (attack/aoe) or
##                   directly (status); chance defaults to 1.0
##   target          enemy = the player's party | ally = another foe |
##                   ally_all = the whole foe pack | self
##   cooldown        rounds before the skill is ready again after use
##   windup          true = dramatic telegraphed wind-up (red flash) before firing
##   telegraph       EN fallback intent line (backend telegraphs override in VI)
## Every id has a 4-frame FX strip at assets/fx/skills/<id>_sheet.png.
const ENEMY_SKILL_POOL: Dictionary = {
	# ── ferocious strikes ──────────────────────────────────────────────────
	"savage_bite": {"name": "Savage Bite", "power": 1.25, "effect": "attack", "target": "enemy",
		"cooldown": 1, "telegraph": "It bares its glistening fangs...",
		"desc": "Feral jaws clamp down on one target."},
	"crushing_maul": {"name": "Crushing Maul", "power": 1.85, "effect": "attack", "target": "enemy",
		"cooldown": 2, "windup": true, "telegraph": "It gathers all of its strength...",
		"desc": "A slow, devastating overhead smash."},
	"shadow_rend": {"name": "Shadow Rend", "power": 1.35, "effect": "attack", "target": "enemy",
		"pierce": true, "cooldown": 2, "telegraph": "Darkness pools around its claws...",
		"desc": "Claws of darkness that tear straight through armor."},
	"frenzied_claws": {"name": "Frenzied Claws", "power": 0.55, "effect": "multi", "hits": 3,
		"target": "enemy", "cooldown": 2, "telegraph": "Its claws twitch with wild hunger...",
		"desc": "A wild flurry of rapid slashes."},
	"bone_spear": {"name": "Bone Spear", "power": 1.5, "effect": "attack", "target": "enemy",
		"cooldown": 1, "telegraph": "Splinters of bone knit into a lance...",
		"desc": "A jagged lance of bone hurled at one target."},
	"life_leech": {"name": "Life Leech", "power": 1.1, "effect": "drain", "target": "enemy",
		"cooldown": 2, "telegraph": "A hungry tendril reaches for warm blood...",
		"desc": "Steals the victim's life to mend the attacker."},
	# ── venom & elements (attack + affliction) ─────────────────────────────
	"venom_spit": {"name": "Venom Spit", "power": 0.8, "effect": "attack", "target": "enemy",
		"status": "poison", "status_chance": 0.85, "cooldown": 1,
		"telegraph": "Venom bubbles between its teeth...",
		"desc": "A glob of poison that corrodes and sickens."},
	"cinder_breath": {"name": "Cinder Breath", "power": 0.9, "effect": "attack", "target": "enemy",
		"status": "burn", "status_chance": 0.8, "cooldown": 2,
		"telegraph": "Embers glow deep in its throat...",
		"desc": "A cone of embers that sets the target alight."},
	"frost_grasp": {"name": "Frost Grasp", "power": 0.9, "effect": "attack", "target": "enemy",
		"status": "freeze", "status_chance": 0.45, "cooldown": 3,
		"telegraph": "The air around it crackles with frost...",
		"desc": "An icy clutch that can freeze the victim solid."},
	"numbing_sting": {"name": "Numbing Sting", "power": 0.8, "effect": "attack", "target": "enemy",
		"status": "paralyze", "status_chance": 0.5, "cooldown": 3,
		"telegraph": "Its stinger drips with paralytic venom...",
		"desc": "A paralytic sting that can lock muscles."},
	"skull_hammer": {"name": "Skull Hammer", "power": 1.0, "effect": "attack", "target": "enemy",
		"status": "stun", "status_chance": 0.45, "cooldown": 3, "windup": true,
		"telegraph": "It heaves its weight high for a skull-ringing blow...",
		"desc": "A concussive blow that can stun outright."},
	"rust_gnaw": {"name": "Rust Gnaw", "power": 0.85, "effect": "attack", "target": "enemy",
		"status": "armor_break", "status_chance": 0.9, "cooldown": 2,
		"telegraph": "Corrosion drips from its maw...",
		"desc": "Corrosion that eats through armor plating."},
	# ── pure hexes (status only) ───────────────────────────────────────────
	"night_shroud": {"name": "Night Shroud", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "blind", "status_chance": 0.85, "cooldown": 3,
		"telegraph": "Shadows thicken like spilled ink...",
		"desc": "A veil of darkness that makes attacks miss."},
	"hypnotic_gaze": {"name": "Hypnotic Gaze", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "sleep", "status_chance": 0.7, "cooldown": 4,
		"telegraph": "Its eyes begin to spin with soft light...",
		"desc": "A mesmerizing stare that lulls the victim to sleep."},
	"sealing_hex": {"name": "Sealing Hex", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "silence", "status_chance": 0.85, "cooldown": 3,
		"telegraph": "A rune of binding flickers to life...",
		"desc": "A rune that seals away techniques."},
	"mire_snare": {"name": "Mire Snare", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "slow", "status_chance": 0.95, "cooldown": 3,
		"telegraph": "The ground softens into grasping mud...",
		"desc": "Clinging mud that drags movement to a crawl."},
	"curse_of_rot": {"name": "Curse of Rot", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "weaken", "status_chance": 0.95, "cooldown": 2,
		"telegraph": "A withering sigil takes shape...",
		"desc": "A withering curse that saps strength."},
	"creeping_venom": {"name": "Creeping Venom", "power": 0.0, "effect": "status", "target": "enemy",
		"status": "poison", "status_chance": 0.95, "cooldown": 2,
		"telegraph": "Toxic vapor coils toward its prey...",
		"desc": "Slow-acting toxin guaranteed to take hold."},
	# ── area attacks (hit the whole party) ─────────────────────────────────
	"quake_stomp": {"name": "Quake Stomp", "power": 0.75, "effect": "aoe", "target": "enemy",
		"cooldown": 3, "windup": true, "telegraph": "It rears up — the ground trembles...",
		"desc": "A ground-shattering stomp that rocks the whole party."},
	"venom_mist": {"name": "Venom Mist", "power": 0.5, "effect": "aoe", "target": "enemy",
		"status": "poison", "status_chance": 0.45, "cooldown": 3,
		"telegraph": "A green haze seeps from its body...",
		"desc": "A poisonous fog that washes over everyone."},
	"ember_storm": {"name": "Ember Storm", "power": 0.55, "effect": "aoe", "target": "enemy",
		"status": "burn", "status_chance": 0.4, "cooldown": 3,
		"telegraph": "Sparks spiral upward around it...",
		"desc": "A rain of burning cinders across the battlefield."},
	"howling_gale": {"name": "Howling Gale", "power": 0.65, "effect": "aoe", "target": "enemy",
		"cooldown": 3, "telegraph": "A screaming wind begins to rise...",
		"desc": "A screaming wind that batters the whole party."},
	"doom_roar": {"name": "Doom Roar", "power": 0.4, "effect": "aoe", "target": "enemy",
		"status": "weaken", "status_chance": 0.75, "cooldown": 4, "windup": true,
		"telegraph": "It draws a breath that darkens the air...",
		"desc": "A terror-laden bellow that weakens all who hear it."},
	# ── self / pack support ────────────────────────────────────────────────
	"dark_regeneration": {"name": "Dark Regeneration", "power": 0.0, "effect": "status",
		"target": "self", "status": "regen", "cooldown": 4,
		"telegraph": "Shadow threads crawl across its wounds...",
		"desc": "Knits the caster's wounds with shadow."},
	"stone_carapace": {"name": "Stone Carapace", "power": 0.0, "effect": "status",
		"target": "self", "status": "defense_up", "cooldown": 3,
		"telegraph": "Its hide begins to gray into stone...",
		"desc": "Rocky plates harden the caster's hide."},
	"blood_frenzy": {"name": "Blood Frenzy", "power": 0.0, "effect": "status",
		"target": "self", "status": "attack_up", "cooldown": 3,
		"telegraph": "Its eyes flood crimson...",
		"desc": "Whips the attacker into a killing rage."},
	"shriek_of_haste": {"name": "Shriek of Haste", "power": 0.0, "effect": "status",
		"target": "ally_all", "status": "haste", "cooldown": 4,
		"telegraph": "It lets out a piercing rallying shriek...",
		"desc": "A piercing cry that spurs the whole pack onward."},
	"mend_the_pack": {"name": "Mend the Pack", "power": 12.0, "effect": "heal",
		"target": "ally", "cooldown": 3,
		"telegraph": "A sickly green light gathers over the wounded...",
		"desc": "Restores a wounded packmate's flesh."},
	"bone_ward": {"name": "Bone Ward", "power": 0.0, "effect": "shield",
		"target": "self", "cooldown": 3,
		"telegraph": "Ribs of bone arch up around it...",
		"desc": "A cage of bone that soaks incoming blows."},
}

func enemy_skill_def(skill_id: String) -> Dictionary:
	return (ENEMY_SKILL_POOL.get(skill_id, {}) as Dictionary).duplicate(true)

## Companion skill slot N (0-based) unlocks at this COMPANION level. Spread like the
## player's own pacing: the first two arrive fast (a new friend must feel useful),
## the last two land around later chapter bosses.
const COMPANION_SKILL_SLOT_LEVELS: Array = [1, 3, 6, 10]

## Deterministic per-role fallback sets — used when the backend hasn't authored
## skills for a companion (old runs, LLM failure). Mirrors the BE fallback.
const COMPANION_ROLE_DEFAULT_SKILLS: Dictionary = {
	"attacker": ["venom_fang", "wild_flurry", "flame_burst", "skull_crack"],
	"support": ["war_cry", "blinding_dust", "quicksilver", "lullaby"],
	"healer": ["soothing_light", "regrowth", "verdant_rain", "guiding_star"],
	"tank": ["taunt", "shield_bash", "stone_ward", "iron_bastion"],
	"none": ["war_cry", "stone_ward", "purify", "wild_flurry"],
}

func status_def(status_id: String) -> Dictionary:
	return (STATUS_LIBRARY.get(status_id, {}) as Dictionary).duplicate(true)

## The full, UNLOCKED skill list a companion brings into battle right now:
## backend-authored ids (PartyManager) or the role fallback, gated by the
## companion's own level via COMPANION_SKILL_SLOT_LEVELS.
func companion_skills(npc_id: String) -> Array[Dictionary]:
	var ids: Array = []
	var pm: Node = _party_manager()
	if pm != null and pm.has_method("companion_skill_ids"):
		ids = pm.companion_skill_ids(npc_id)
	if ids.is_empty():
		ids = COMPANION_ROLE_DEFAULT_SKILLS.get(
			_companion_role(npc_id), COMPANION_ROLE_DEFAULT_SKILLS["none"]) as Array
	var level: int = companion_level(npc_id)
	var unlocked: Array[Dictionary] = []
	for slot in range(ids.size()):
		var gate: int = int(COMPANION_SKILL_SLOT_LEVELS[mini(slot, COMPANION_SKILL_SLOT_LEVELS.size() - 1)])
		if level < gate:
			continue
		var skill_id := str(ids[slot])
		if not COMPANION_SKILL_POOL.has(skill_id):
			continue
		var skill: Dictionary = (COMPANION_SKILL_POOL[skill_id] as Dictionary).duplicate(true)
		skill["id"] = skill_id
		skill["unlock_level"] = gate
		unlocked.append(skill)
	return unlocked

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
