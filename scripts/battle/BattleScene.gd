extends CanvasLayer













const BattleSpeechBubbleScript := preload("res://scripts/battle/BattleSpeechBubble.gd")
const EnemyIdentityPlateScript := preload("res://scripts/battle/EnemyIdentityPlate.gd")
const EnemyTargetHighlightScript := preload("res://scripts/battle/EnemyTargetHighlight.gd")
const BattleCommandMenuScript := preload("res://scripts/battle/BattleCommandMenu.gd")
const BattleAllyCardStackScript := preload("res://scripts/battle/BattleAllyCardStack.gd")
const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")

signal battle_finished(result: String, enemy_id: String)

const FONT_SIZE: = 16
const BATTLE_LOG_FONT_SIZE: = 11
const MAX_BATTLE_LOG_ENTRIES: = 8
const BATTLE_LOG_ENTRY_TTL: = 8.0
const BATTLE_LOG_APPEND_DURATION: = 0.18
const BATTLE_LOG_EXIT_DURATION: = 0.2
const BATTLE_LOG_SCROLL_DURATION: = 0.28
const BATTLE_LOG_APPEND_OFFSET: = Vector2(0, 3)
const BATTLE_LOG_EXIT_OFFSET: = Vector2(-4, 0)
const BATTLE_LOG_ENTRY_GAP: = 3
const BATTLE_LOG_MIN_ENTRY_HEIGHT: = 15.0
const BATTLE_FINISH_CONFIRM_DELAY: = 1.2
const TURN_TRANSITION_DELAY: = 1.0
# Offensive effects are authored at a conservative baseline so they also fit
# ally cards. Player/companion attacks landing on the much larger foe portraits
# get a small, consistent lift without enlarging heals or enemy attacks.
const ALLY_TO_FOE_FX_SCALE: = 1.15

const COLOR_TEXT: = Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TEXT_DIM: = Color(0.93, 0.88, 0.75, 0.4)
const COLOR_ACCENT: = Color(1.0, 0.85, 0.45, 1.0)
const COLOR_PANEL_BG: = Color(0.05, 0.04, 0.13, 0.92)
const COLOR_PANEL_BORDER: = Color(0.78, 0.6, 0.26, 0.65)
const COLOR_HP: = Color(0.82, 0.25, 0.28, 1.0)
const COLOR_HP_GHOST: = Color(0.95, 0.82, 0.55, 0.9)
const COLOR_HP_BG: = Color(0.16, 0.06, 0.09, 0.95)
const COLOR_PLAYER_HP: = Color(0.32, 0.7, 0.38, 1.0)
const COLOR_XP: = Color(0.45, 0.55, 0.9, 1.0)
const COLOR_EXPOSED: = Color(0.95, 0.45, 0.95, 1.0)
const COLOR_CRIT: = Color(1.0, 0.78, 0.25, 1.0)
const COLOR_PLAYER_DMG: = Color(1.0, 0.42, 0.38, 1.0)
const COLOR_HEAL: = Color(0.55, 0.95, 0.6, 1.0)

const TEX_PANEL: = "res://assets/ui/battle/panel.png"
const TEX_SLASH: = "res://assets/ui/battle/slash_sheet.png"
const TEX_BACKDROP: = "res://assets/ui/battle/backdrop.png"
const TEX_BANNER: = "res://assets/ui/battle/banner.png"
const TEX_B2_ENEMY: = "res://assets/ui/battle_v2/panel_enemy.png"
const TEX_B2_LOG: = "res://assets/ui/battle_v2/panel_log.png"
const TEX_B2_PLAYER: = "res://assets/ui/battle_v2/panel_player.png"
const TEX_B2_ORNAMENT: = "res://assets/ui/battle_v2/ornament_gem.png"
const TEX_B2_TURN_ORDER_ENEMY: = "res://assets/ui/battle_v2/turn_order_card_enemy.png"
const TEX_B2_TURN_ORDER_ALLY: = "res://assets/ui/battle_v2/turn_order_card_ally.png"

enum UiMode{NONE, TYPING, CONFIRM, MENU, TARGET}

# Party-balance constants mirror SceneBuilder/utils/enemy_balance.py.
const PARTY_ECHO_XP_FACTOR: = 0.5
const BOSS_HP_PER_EXTRA_ALLY: = 0.55
const BOSS_MAX_ACTIONS_PER_ROUND: = 3
const ELITE_HARD_CC_RESISTANCE: = 0.35
const BOSS_HARD_CC_RESISTANCE: = 0.65
const HARD_CC_STATUS_IDS: = {
    "freeze": true,
    "sleep": true,
    "paralyze": true,
    "stun": true,
}

# ── multi-actor battle state ─────────────────────────────────────────────────
# The battle is party-vs-group: every combatant is an "actor" Dictionary.
# Ally actor: {kind:"player"|"companion", id, name, level, max_hp, attack, defense,
#   speed, sp, sp_max, statuses:[], skills:[], downed, focus, guarding, portrait}
# Foe actor: {id, name, level, rank, data, max_hp, hp, attack, defense, speed,
#   statuses:[], xp_reward, synthetic, intent, turns_since_heavy, ui:{...}}
# Status instance (on actor.statuses): {id, turns_left, magnitude} — definitions
# live in GameManager.STATUS_LIBRARY.
var _allies: Array[Dictionary] = []
var _foes: Array[Dictionary] = []

# The PRIMARY foe = the world enemy the player touched. Story systems (weakness
# probe, HP phases, spare, dialogue) stay anchored to it; reinforcement echoes
# are pure combat filler.
var enemy: Dictionary = {}
var enemy_id: String = ""

var player_stats: Dictionary = {}
var _companion_levelups: Array = []

var exposed_turns: int = 0
var finisher_used: bool = false
var weakness_found: bool = false
var probe_options: Array = []
var triggered_phases: Dictionary = {}
var phase_damage_bonus: float = 1.0
var phase_defense_factor: float = 1.0
var flee_failed_count: int = 0

var _ui_mode: UiMode = UiMode.NONE
var _battle_over: bool = false
var _pending_finish_result: String = ""
var _finish_confirm_ready: bool = false
var _battle_log_entries: Array[Dictionary] = []
var _next_battle_log_entry_id: int = 1
var _battle_log_scroll_queued: bool = false
var _battle_log_scroll_tween: Tween

# Enemy barks are real-time overlays, independent from the turn/input state. Each
# foe owns a small bounded FIFO: different enemies may speak simultaneously while
# repeated lines from one enemy remain ordered without creating stacked bubbles.
const MAX_PENDING_BARKS_PER_ENEMY := 3
const ENEMY_BARK_VERTICAL_LIFT := 16.0
var _enemy_bark_channels: Dictionary = {}
var _enemy_bark_generation: int = 0
var _enemy_barks_shutting_down: bool = false


var _panel_style: StyleBox = null
var _slash_frames: SpriteFrames = null
var _banner_texture: Texture2D = null
var _texture_cache: Dictionary = {}

var _shake_time: float = 0.0
var _shake_strength: float = 0.0

var _root: Control


var _design: Control
var _fx_layer: Control
var _turn_stack: Control
var _turn_cards: Array[Control] = []
var _turn_active_actor: = "player"
var _log_panel: Panel
var _log_scroll: ScrollContainer
var _log_list: VBoxContainer
var _continue_marker: Label
var _command_menu: BattleCommandMenu
var _hint_label: Label

# Per-ally status cards (index-parallel with _allies):
# {root, name_label, lv_label, hp_bar, hp_ghost, hp_text, status_row, sp_pips,
#  xp_bar, xp_text, fx_center: Vector2}
var _ally_cards: Array[Dictionary] = []
var _ally_stack: BattleAllyCardStack

# Round-based turn queue: [{"side": "ally"|"foe", "index": int}, ...]
var _round_queue: Array[Dictionary] = []
var _queue_pos: int = 0
var _round_serial: int = 0

# The foe the target cursor last rested on (drives intent + selection helpers).
var _target_foe_index: int = 0

# Per-skill FX sheets (assets/fx/skills/<id>_sheet.png), cached SpriteFrames.
var _skill_fx_cache: Dictionary = {}

const PLAYER_HP_BAR_W: = 130.0
const DESIGN_SIZE: = Vector2(960, 540)
const LOG_PANEL_POS: = Vector2(2, 2)
const LOG_PANEL_SIZE: = Vector2(330, 152)
const PLAYER_PANEL_POS: = Vector2(2, 380)
const PLAYER_PANEL_SIZE: = Vector2(312, 158)
const MENU_PANEL_TOP: = 422.0
const MENU_PANEL_HEIGHT: = 172.0
const TURN_ORDER_STACK_POS: = Vector2(0, 2)
const TURN_ORDER_STACK_SIZE: = Vector2(960, 230)
const FOE_VERTICAL_OFFSET: = 10.0
const PORTRAIT_HOME: = Vector2(350, 48)
const PORTRAIT_SIZE: = Vector2(280, 290)
const PLAYER_FX_CENTER: = Vector2(124, 454)
const SCREEN_CENTER: = Vector2(480, 270)
const VICTORY_BANNER_CENTER: = Vector2(480, 145)
const VICTORY_TITLE_RECT: = Rect2(-160, -36, 320, 48)
const VICTORY_ORNAMENT_WIDTH: = 240.0
const VICTORY_ORNAMENT_TOP: = 18.0
const VICTORY_REWARD_REVEAL_DELAY: = 0.60
const MAX_BATTLE_REWARDS_PER_SCREEN: = 4


func open(enemy_data: Dictionary) -> void :
    enemy = _with_choice_scaling(enemy_data)
    enemy_id = str(enemy.get("id", ""))
    probe_options = ((enemy.get("weakness", {}) as Dictionary).get("probe_options", []) as Array).duplicate(true)

    player_stats = GameManager.player_battle_stats()
    _build_allies()
    _build_foes()

    GameManager.ui_blocking_input = true
    layer = 80
    transform = Transform2D.IDENTITY

    if not GameManager.companion_leveled.is_connected(_on_companion_leveled):
        GameManager.companion_leveled.connect(_on_companion_leveled)
    _load_ui_kit()
    _build_ui()
    _run_battle()


## The player's side: the protagonist plus every companion currently travelling
## with them. Companions bring their own persistent HP, level-derived stats and
## their LLM-authored skill set (GameManager.companion_skills).
func _build_allies() -> void :
    _allies.clear()
    _allies.append({
        "kind": "player",
        "id": "player",
        "name": _player_name(),
        "level": GameManager.player_level,
        "max_hp": int(player_stats.get("max_hp", 80)),
        "attack": int(player_stats.get("attack", 12)),
        "defense": int(player_stats.get("defense", 5)),
        "speed": int(player_stats.get("speed", 9)),
        "sp": int(player_stats.get("sp_max", 3)),
        "sp_max": int(player_stats.get("sp_max", 3)),
        "statuses": [],
        "skills": GameManager.player_skills(),
        "downed": GameManager.get_player_hp() <= 0,
        "focus": false,
        "guarding": false,
    })
    for raw_id in GameManager.active_companion_ids():
        var npc_id: = str(raw_id)
        var stats: Dictionary = GameManager.companion_battle_stats(npc_id)
        _allies.append({
            "kind": "companion",
            "id": npc_id,
            "name": PartyManager.companion_name(npc_id),
            "level": int(stats.get("level", 1)),
            "max_hp": int(stats.get("max_hp", 50)),
            "attack": int(stats.get("attack", 10)),
            "defense": int(stats.get("defense", 4)),
            "speed": int(stats.get("speed", 8)),
            "sp": int(stats.get("sp_max", 2)),
            "sp_max": int(stats.get("sp_max", 2)),
            "statuses": [],
            "skills": GameManager.companion_skills(npc_id),
            "downed": GameManager.get_companion_hp(npc_id) <= 0,
            "focus": false,
            "guarding": false,
        })


func _ally_hp(ally: Dictionary) -> int:
    if str(ally.get("kind")) == "player":
        return GameManager.get_player_hp()
    return GameManager.get_companion_hp(str(ally.get("id")))


func _set_ally_hp(ally: Dictionary, value: int) -> void :
    if str(ally.get("kind")) == "player":
        GameManager.set_player_hp(value)
    else:
        GameManager.set_companion_hp(str(ally.get("id")), value)


## The hostile side: the touched world enemy plus reinforcement "echoes" sized to
## the party ("nhiều đấu nhiều"). Echoes are synthetic combat filler — one level
## below the primary, minion-grade XP — so a solo player still fights the same 1v1
## the balance curves were tuned for, while a full party faces a real group.
## Bosses stay alone, gaining HP and interleaved actions instead of visual clones.
func _build_foes() -> void :
    _foes.clear()
    _foes.append(_make_foe_actor(enemy, 0, false))
    var rank: = str(enemy.get("rank", "minion"))
    var extra_budget: int = clampi(_allies.size() - 1, 0, 2)
    if rank == "boss":
        extra_budget = 0
    elif rank == "elite":
        extra_budget = mini(extra_budget, 1)
    for index in range(extra_budget):
        _foes.append(_make_echo_foe(index + 1))
    if rank == "boss":
        var primary: Dictionary = _foes[0]
        var scaled_hp: int = maxi(1, int(round(
            int(primary.get("max_hp", 1)) * _boss_hp_multiplier(_allies.size())
        )))
        primary["max_hp"] = scaled_hp
        primary["hp"] = scaled_hp
        primary["actions_per_round"] = _boss_actions_per_round(_allies.size())


func _boss_hp_multiplier(party_size: int) -> float:
    return 1.0 + BOSS_HP_PER_EXTRA_ALLY * maxi(0, party_size - 1)


func _boss_actions_per_round(party_size: int) -> int:
    return clampi(party_size, 1, BOSS_MAX_ACTIONS_PER_ROUND)


func _make_foe_actor(data: Dictionary, index: int, synthetic: bool) -> Dictionary:
    var stats: Dictionary = data.get("stats", {}) as Dictionary
    return {
        "id": str(data.get("id", "foe_%d" % index)),
        "name": str(data.get("name", "Enemy")),
        "level": maxi(1, int(data.get("level", 1))),
        "rank": str(data.get("rank", "minion")),
        "data": data,
        "max_hp": maxi(int(stats.get("max_hp", 40)), 1),
        "hp": maxi(int(stats.get("max_hp", 40)), 1),
        "attack": maxi(int(stats.get("attack", 8)), 1),
        "defense": maxi(int(stats.get("defense", 2)), 0),
        "speed": maxi(int(stats.get("speed", 6)), 1),
        "statuses": [],
        "xp_reward": maxi(int(data.get("xp_reward", 20)), 1),
        "synthetic": synthetic,
        "intent": {},
        "turns_since_heavy": 99,
        "actions_per_round": 1,
        "ui": {},
    }


## A reinforcement copy of the primary enemy: one level lower (stat ratios mirror
## utils/enemy_balance.py's linear curves, same rule as _with_choice_scaling) and
## worth 50% XP so grinding echoes never out-earns real roster enemies.
func _make_echo_foe(ordinal: int) -> Dictionary:
    var base: Dictionary = enemy.duplicate(true)
    var old_level: int = maxi(1, int(base.get("level", 1)))
    var new_level: int = maxi(1, old_level - 1)
    var stats: Dictionary = (base.get("stats", {}) as Dictionary).duplicate(true)
    if new_level != old_level:
        var hp_ratio: = (30.0 + 14.0 * new_level) / (30.0 + 14.0 * old_level)
        var atk_ratio: = (6.0 + 2.2 * new_level) / (6.0 + 2.2 * old_level)
        var def_ratio: = (2.0 + 1.4 * new_level) / (2.0 + 1.4 * old_level)
        stats["max_hp"] = maxi(1, int(round(int(stats.get("max_hp", 40)) * hp_ratio)))
        stats["attack"] = maxi(1, int(round(int(stats.get("attack", 8)) * atk_ratio)))
        stats["defense"] = maxi(0, int(round(int(stats.get("defense", 2)) * def_ratio)))
        stats["speed"] = maxi(1, int(stats.get("speed", 6)) - 1)
    base["stats"] = stats
    base["level"] = new_level
    base["id"] = "%s__echo%d" % [enemy_id, ordinal]
    base["name"] = "%s %s" % [str(enemy.get("name", "Enemy")), "II" if ordinal == 1 else "III"]
    base["xp_reward"] = maxi(1, int(round(int(enemy.get("xp_reward", 20)) * PARTY_ECHO_XP_FACTOR)))
    base["rank"] = "minion"
    base.erase("phases")
    base["can_spare"] = false
    return _make_foe_actor(base, ordinal, true)


# ── status-effect engine ──────────────────────────────────────────────────────
# Definitions live in GameManager.STATUS_LIBRARY; an actor carries instances
# {id, turns_left, magnitude}. Rules of the loop:
#   * skip decision + damage/heal ticks happen at the START of the actor's turn,
#   * durations decrement AFTER the tick (one turn controls one normal actor turn;
#     a multi-action boss resolves hard control once for the whole round),
#   * sleep breaks when the sleeper takes a hit (wake_on_hit),
#   * shield magnitude is a damage-absorbing pool consumed before HP.


func _find_status(actor: Dictionary, status_id: String) -> Dictionary:
    for status in actor.get("statuses", []) as Array:
        if str((status as Dictionary).get("id")) == status_id:
            return status
    return {}


func _apply_status(actor: Dictionary, status_id: String, magnitude: float = 0.0) -> bool:
    var def: Dictionary = GameManager.status_def(status_id)
    if def.is_empty():
        return false
    var resistance: float = _hard_cc_resistance_for(actor, status_id)
    if resistance > 0.0 and randf() < resistance:
        return false
    var existing: Dictionary = _find_status(actor, status_id)
    if not existing.is_empty():
        # Re-applying refreshes duration and keeps the strongest magnitude.
        existing["turns_left"] = int(def.get("turns", 2))
        existing["magnitude"] = maxf(float(existing.get("magnitude", 0.0)), magnitude)
        return true
    (actor["statuses"] as Array).append({
        "id": status_id,
        "turns_left": int(def.get("turns", 2)),
        "magnitude": magnitude,
    })
    return true


func _hard_cc_resistance_for(actor: Dictionary, status_id: String) -> float:
    if not HARD_CC_STATUS_IDS.has(status_id):
        return 0.0
    match str(actor.get("rank", "")):
        "boss":
            return BOSS_HARD_CC_RESISTANCE
        "elite":
            return ELITE_HARD_CC_RESISTANCE
        _:
            return 0.0


func _remove_status(actor: Dictionary, status_id: String) -> void :
    var statuses: Array = actor.get("statuses", []) as Array
    for index in range(statuses.size() - 1, -1, -1):
        if str((statuses[index] as Dictionary).get("id")) == status_id:
            statuses.remove_at(index)


func _clear_debuffs(actor: Dictionary) -> int:
    var statuses: Array = actor.get("statuses", []) as Array
    var removed: = 0
    for index in range(statuses.size() - 1, -1, -1):
        var def: Dictionary = GameManager.status_def(str((statuses[index] as Dictionary).get("id")))
        if str(def.get("kind", "")) == "debuff":
            statuses.remove_at(index)
            removed += 1
    return removed


## Product of a multiplier key (attack_mult / defense_mult / speed_mult /
## hit_chance) across the actor's live statuses.
func _status_mult(actor: Dictionary, key: String) -> float:
    var value: = 1.0
    for status in actor.get("statuses", []) as Array:
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        if def.has(key):
            value *= float(def.get(key, 1.0))
    return value


## Additive sum of a bonus key (crit_bonus) across live statuses.
func _status_bonus(actor: Dictionary, key: String) -> float:
    var value: = 0.0
    for status in actor.get("statuses", []) as Array:
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        value += float(def.get(key, 0.0))
    return value


func _status_flag(actor: Dictionary, key: String) -> bool:
    for status in actor.get("statuses", []) as Array:
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        if bool(def.get(key, false)):
            return true
    return false


func _effective_speed(actor: Dictionary) -> int:
    return maxi(1, int(round(int(actor.get("speed", 6)) * _status_mult(actor, "speed_mult"))))


## Taking a hit wakes a sleeper.
func _on_actor_damaged(actor: Dictionary) -> void :
    for status in (actor.get("statuses", []) as Array).duplicate():
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        if bool(def.get("wake_on_hit", false)):
            _remove_status(actor, str((status as Dictionary).get("id")))


## Route incoming damage through any shield pools first. Returns the damage that
## still reaches HP; shield magnitudes are consumed in place.
func _absorb_with_shields(actor: Dictionary, damage: int) -> int:
    var remaining: = damage
    var statuses: Array = actor.get("statuses", []) as Array
    for index in range(statuses.size() - 1, -1, -1):
        if remaining <= 0:
            break
        var status: Dictionary = statuses[index]
        var def: Dictionary = GameManager.status_def(str(status.get("id")))
        if not bool(def.get("absorb", false)):
            continue
        var pool: int = int(round(float(status.get("magnitude", 0.0))))
        var eaten: int = mini(pool, remaining)
        remaining -= eaten
        if eaten >= pool:
            statuses.remove_at(index)
        else:
            status["magnitude"] = float(pool - eaten)
    return remaining


## Start-of-turn upkeep for ANY actor: DoT/regen ticks, then the skip decision,
## then duration decrement. Returns {skip: bool, notes: Array[String]} — notes
## are already-formatted log lines for the caller to _say.
func _tick_statuses(actor: Dictionary, is_ally: bool) -> Dictionary:
    var notes: Array[String] = []
    var skip: = false
    var actor_name: = str(actor.get("name", "?"))
    var max_hp: int = int(actor.get("max_hp", 1))

    for status in (actor.get("statuses", []) as Array).duplicate():
        var status_id: = str((status as Dictionary).get("id"))
        var def: Dictionary = GameManager.status_def(status_id)
        var tick_pct: = float(def.get("tick_pct", 0.0))
        if tick_pct > 0.0:
            var dot: int = maxi(1, int(round(max_hp * tick_pct)))
            _deal_raw_damage(actor, is_ally, dot, Color(0.55, 0.9, 0.35) if status_id == "poison" else Color(1.0, 0.5, 0.2))
            notes.append("%s takes %d %s damage." % [actor_name, dot, str(def.get("name", status_id)).to_lower()])
        if bool(def.get("tick_heal", false)):
            var heal: int = maxi(1, int(round(float((status as Dictionary).get("magnitude", 6.0)))))
            _heal_raw(actor, is_ally, heal)
            notes.append("%s regenerates %d HP." % [actor_name, heal])

    if _actor_down(actor, is_ally):
        return {"skip": true, "notes": notes}

    for status in (actor.get("statuses", []) as Array).duplicate():
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        if bool(def.get("skip_turn", false)):
            skip = true
            notes.append("%s is %s and cannot move!" % [actor_name, str(def.get("name", "?")).to_lower()])
            break
        var skip_chance: = float(def.get("skip_chance", 0.0))
        if skip_chance > 0.0 and randf() < skip_chance:
            skip = true
            notes.append("%s is paralyzed and cannot move!" % actor_name)
            break

    var statuses: Array = actor.get("statuses", []) as Array
    for index in range(statuses.size() - 1, -1, -1):
        var status: Dictionary = statuses[index]
        status["turns_left"] = int(status.get("turns_left", 1)) - 1
        if int(status["turns_left"]) <= 0:
            statuses.remove_at(index)

    return {"skip": skip, "notes": notes}


## A boss may act up to three times, but status periods are ROUND-based. Cache
## the upkeep decision so DoT/regen, duration decay and CC RNG happen once; a
## hard control that lands skips all of that boss's actions for the round.
func _status_upkeep_for_round(actor: Dictionary, is_ally: bool) -> Dictionary:
    if int(actor.get("_status_upkeep_round", -1)) == _round_serial:
        return {
            "skip": bool(actor.get("_status_skip_round", false)),
            "notes": [],
        }
    var upkeep: Dictionary = _tick_statuses(actor, is_ally)
    actor["_status_upkeep_round"] = _round_serial
    actor["_status_skip_round"] = bool(upkeep.get("skip", false))
    return upkeep


## Direct HP change helpers that work for both sides (DoTs, regen) without any
## attack math. FX are anchored to the actor's battlefield position.
func _deal_raw_damage(actor: Dictionary, is_ally: bool, amount: int, color: Color) -> void :
    amount = _absorb_with_shields(actor, amount)
    if amount <= 0:
        return
    if is_ally:
        _set_ally_hp(actor, _ally_hp(actor) - amount)
        if _ally_hp(actor) <= 0:
            actor["downed"] = true
    else:
        actor["hp"] = maxi(int(actor.get("hp", 1)) - amount, 0)
    _spawn_damage_number(_actor_fx_center(actor, is_ally), str(amount), color)
    _refresh_all_panels()


func _heal_raw(actor: Dictionary, is_ally: bool, amount: int) -> void :
    if is_ally:
        _set_ally_hp(actor, _ally_hp(actor) + amount)
    else:
        actor["hp"] = mini(int(actor.get("hp", 1)) + amount, int(actor.get("max_hp", 1)))
    _spawn_damage_number(_actor_fx_center(actor, is_ally), "+%d" % amount, COLOR_HEAL)
    _refresh_all_panels()


func _actor_down(actor: Dictionary, is_ally: bool) -> bool:
    if is_ally:
        return _ally_hp(actor) <= 0 or bool(actor.get("downed", false))
    return int(actor.get("hp", 0)) <= 0


func _living_allies() -> Array[int]:
    var out: Array[int] = []
    for index in range(_allies.size()):
        if not _actor_down(_allies[index], true):
            out.append(index)
    return out


func _living_foes() -> Array[int]:
    var out: Array[int] = []
    for index in range(_foes.size()):
        if not _actor_down(_foes[index], false):
            out.append(index)
    return out


## One human-readable status summary line, e.g. "POISON 2 · SHIELD 14".
func _status_summary(actor: Dictionary) -> String:
    var parts: Array[String] = []
    for status in actor.get("statuses", []) as Array:
        var def: Dictionary = GameManager.status_def(str((status as Dictionary).get("id")))
        var label: = str(def.get("name", (status as Dictionary).get("id"))).to_upper()
        if bool(def.get("absorb", false)):
            parts.append("%s %d" % [label, int(round(float((status as Dictionary).get("magnitude", 0.0))))])
        else:
            parts.append("%s %d" % [label, int((status as Dictionary).get("turns_left", 0))])
    return " · ".join(parts)


## Compact icon data shared by the top readout, each foe plate and each ally card.
## `extra` carries actor-only states such as EXPOSED, DOWN, FOCUS and GUARD.
func _status_entries(actor: Dictionary, extra: Array[Dictionary] = []) -> Array[Dictionary]:
    var entries: Array[Dictionary] = extra.duplicate(true)
    for raw_status in actor.get("statuses", []) as Array:
        var status: Dictionary = raw_status as Dictionary
        var status_id: = str(status.get("id", ""))
        var definition: Dictionary = GameManager.status_def(status_id)
        var status_name: = str(definition.get("name", status_id.capitalize()))
        var turns: int = maxi(int(status.get("turns_left", 0)), 0)
        var tooltip: = "%s · %d turn%s" % [status_name, turns, "" if turns == 1 else "s"]
        if bool(definition.get("absorb", false)):
            tooltip += " · absorbs %d damage" % int(round(float(status.get("magnitude", 0.0))))
        elif float(definition.get("tick_pct", 0.0)) > 0.0:
            tooltip += " · %.0f%% max HP damage each turn" % (float(definition.get("tick_pct", 0.0)) * 100.0)
        elif bool(definition.get("tick_heal", false)):
            tooltip += " · restores %d HP each turn" % int(round(float(status.get("magnitude", 0.0))))
        entries.append({
            "id": status_id,
            "label": status_name.left(3).to_upper(),
            "count": turns,
            "tooltip": tooltip,
        })
    return entries


func _make_status_row(parent: Control, rect: Rect2, alignment: int, icon_size: int) -> HBoxContainer:
    var row: = HBoxContainer.new()
    row.position = rect.position
    row.size = rect.size
    row.alignment = alignment
    row.add_theme_constant_override("separation", STATUS_TOKEN_GAP)
    row.set_meta("icon_size", icon_size)
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    parent.add_child(row)
    return row


## Rebuild only when status ids/counts change. Missing artwork becomes a compact
## three-letter text token, so old/custom statuses remain readable.
func _refresh_status_row(row: HBoxContainer, actor: Dictionary, extra: Array[Dictionary] = []) -> void :
    if row == null:
        return
    var entries: Array[Dictionary] = _status_entries(actor, extra)
    var signature: = JSON.stringify(entries)
    if str(row.get_meta("signature", "")) == signature:
        return
    row.set_meta("signature", signature)
    for child in row.get_children():
        row.remove_child(child)
        child.queue_free()
    if entries.is_empty():
        return

    var icon_size: int = int(row.get_meta("icon_size", 15))
    var capacity_width: float = float(row.get_meta("capacity_width", row.size.x))
    var more_width: float = float(icon_size + 3)
    var visible_count: int = 0
    var used_width: float = 0.0
    for index in range(entries.size()):
        var token_width: float = _status_token_width(entries[index], icon_size)
        var separator: float = STATUS_TOKEN_GAP if visible_count > 0 else 0.0
        var reserve_more: float = (
            STATUS_TOKEN_GAP + more_width if index < entries.size() - 1 else 0.0)
        if visible_count == 0 or used_width + separator + token_width + reserve_more <= capacity_width:
            used_width += separator + token_width
            visible_count += 1
        else:
            break
    for index in range(visible_count):
        row.add_child(_make_status_token(entries[index], icon_size))
    if entries.size() > visible_count:
        var hidden: int = entries.size() - visible_count
        row.add_child(_make_status_token({
            "id": "more",
            "label": "+%d" % hidden,
            "count": 0,
            "tooltip": "%d more effect%s" % [hidden, "" if hidden == 1 else "s"],
        }, icon_size))


func _status_token_width(entry: Dictionary, icon_size: int) -> float:
    var wide_label: = str(entry.get("wide_label", ""))
    if wide_label.is_empty():
        return float(icon_size + 3)
    var label_size: int = maxi(7, icon_size - 8)
    var font: Font = UiKit.body_semibold_font()
    if font == null:
        font = ThemeDB.fallback_font
    return float(icon_size + 5) + ceilf(font.get_string_size(
        wide_label,
        HORIZONTAL_ALIGNMENT_LEFT,
        -1.0,
        label_size,
    ).x)


func _make_status_token(entry: Dictionary, icon_size: int) -> Control:
    var token: = Control.new()
    var token_width: float = _status_token_width(entry, icon_size)
    token.custom_minimum_size = Vector2(token_width, icon_size)
    token.size = token.custom_minimum_size
    token.tooltip_text = str(entry.get("tooltip", entry.get("label", "")))
    token.mouse_filter = Control.MOUSE_FILTER_STOP

    var status_id: = str(entry.get("id", ""))
    var icon_path: = (
        ENEMY_EXPOSED_ICON if status_id == "exposed"
        else STATUS_ICON_DIR + status_id + ".png")
    # Actor-only tokens without authored art still use the text fallback. Guard
    # the load so Image.load_from_file never logs a false ERROR for custom states.
    var icon: Texture2D = null
    if ResourceLoader.exists(icon_path) or FileAccess.file_exists(icon_path):
        icon = _load_png_texture(icon_path)
    if icon != null:
        var image: = TextureRect.new()
        image.texture = icon
        image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        image.size = Vector2(icon_size, icon_size)
        image.mouse_filter = Control.MOUSE_FILTER_IGNORE
        token.add_child(image)
    else:
        var fallback: = UiKit.make_label_strong(str(entry.get("label", "?")), maxi(7, icon_size - 7), COLOR_TEXT)
        fallback.size = Vector2(icon_size + 2, icon_size)
        fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        fallback.clip_text = true
        fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
        token.add_child(fallback)

    var wide_label: = str(entry.get("wide_label", ""))
    if not wide_label.is_empty():
        var caption: = UiKit.make_label_strong(
            wide_label,
            maxi(7, icon_size - 8),
            COLOR_EXPOSED if status_id == "exposed" else COLOR_TEXT,
        )
        caption.position = Vector2(icon_size + 2, 0)
        caption.size = Vector2(maxf(1.0, token_width - icon_size - 2.0), icon_size)
        caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        caption.clip_text = true
        caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
        token.add_child(caption)

    var count: int = int(entry.get("count", 0))
    if count > 0:
        var badge: = UiKit.make_label_strong(str(count), maxi(7, icon_size - 7), Color.WHITE)
        badge.position = Vector2(icon_size - 5, icon_size - 9)
        badge.size = Vector2(8, 9)
        badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
        badge.add_theme_constant_override("shadow_offset_x", 1)
        badge.add_theme_constant_override("shadow_offset_y", 1)
        badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        token.add_child(badge)
    return token


## Choice-consequence: shift this enemy's level by the NarrativeState modifier
## recorded for the current chapter+zone ("word of your deeds spreads"). The
## stat curves mirror utils/enemy_balance.py enemy_stats_for as RATIOS over the
## packaged stats, so the rank multiplier cancels out — keep the constants in
## sync with the backend, same rule as the XP curve.
func _with_choice_scaling(enemy_data: Dictionary) -> Dictionary:
    var narrative: = get_node_or_null("/root/NarrativeState")
    if narrative == null:
        return enemy_data
    var zone_id: = str(GameManager.get_scene_context().get("zone_id", ""))
    var chapter: = 0
    var flow: = get_node_or_null("/root/ChapterFlow")
    if flow != null and flow.has_method("current_chapter"):
        chapter = int((flow.call("current_chapter") as Dictionary).get("chapter", 0))
    var delta: int = narrative.call("enemy_level_delta_for", chapter, zone_id)
    if delta == 0:
        return enemy_data
    var old_level: int = max(1, int(enemy_data.get("level", 1)))
    var new_level: int = clampi(old_level + delta, 1, 18)  # MAX_ENEMY_LEVEL mirror
    if new_level == old_level:
        return enemy_data
    var scaled: Dictionary = enemy_data.duplicate(true)
    var stats: Dictionary = (scaled.get("stats", {}) as Dictionary).duplicate(true)
    var hp_ratio: = (30.0 + 14.0 * new_level) / (30.0 + 14.0 * old_level)
    var atk_ratio: = (6.0 + 2.2 * new_level) / (6.0 + 2.2 * old_level)
    var def_ratio: = (2.0 + 1.4 * new_level) / (2.0 + 1.4 * old_level)
    stats["max_hp"] = max(1, int(round(int(stats.get("max_hp", 40)) * hp_ratio)))
    stats["attack"] = max(1, int(round(int(stats.get("attack", 8)) * atk_ratio)))
    stats["defense"] = max(0, int(round(int(stats.get("defense", 2)) * def_ratio)))
    stats["speed"] = max(1, int(stats.get("speed", 6)) + (new_level - old_level))
    scaled["stats"] = stats
    scaled["level"] = new_level
    print("[Battle] choice scaling: %s level %d -> %d" % [str(scaled.get("id", "?")), old_level, new_level])
    return scaled





func _load_ui_kit() -> void :
    if ResourceLoader.exists(TEX_PANEL):
        var panel_texture: Texture2D = load(TEX_PANEL)
        var style: = StyleBoxTexture.new()
        style.texture = panel_texture
        style.set_texture_margin_all(11.0)
        style.set_content_margin_all(4.0)
        _panel_style = style
    if ResourceLoader.exists(TEX_BANNER):
        _banner_texture = load(TEX_BANNER)
    if ResourceLoader.exists(TEX_SLASH):
        var sheet: Texture2D = load(TEX_SLASH)
        _slash_frames = SpriteFrames.new()
        _slash_frames.remove_animation("default")
        _slash_frames.add_animation("slash")
        _slash_frames.set_animation_speed("slash", 16.0)
        _slash_frames.set_animation_loop("slash", false)
        for index in range(4):
            var atlas: = AtlasTexture.new()
            atlas.atlas = sheet
            atlas.region = Rect2(index * 96, 0, 96, 96)
            _slash_frames.add_frame("slash", atlas)


func _load_png_texture(path: String) -> Texture2D:
    if _texture_cache.has(path):
        return _texture_cache[path]
    var texture: Texture2D = null
    if ResourceLoader.exists(path):
        texture = load(path)
    else:
        var image: = Image.new()
        if image.load(ProjectSettings.globalize_path(path)) == OK:
            texture = ImageTexture.create_from_image(image)
    _texture_cache[path] = texture
    return texture




const BATTLE_V3_DIR: = "res://assets/ui/battle_v3/"
const STATUS_ICON_DIR: = "res://assets/ui/battle/status/"
const ENEMY_EXPOSED_ICON: = "res://assets/ui/enemy_identity_v1/exposed.png"
const STATUS_TOKEN_GAP: = 2


func _v3(file_name: String) -> Texture2D:
    var path: = BATTLE_V3_DIR + file_name
    return load(path) if ResourceLoader.exists(path) else null




func _cropped_portrait(texture: Texture2D, out_size: int, circle: bool) -> Texture2D:
    if texture == null:
        return null
    var image: = texture.get_image()
    if image == null:
        return texture
    image = image.duplicate()
    if image.is_compressed():
        image.decompress()
    image.convert(Image.FORMAT_RGBA8)
    var side: int = mini(image.get_width(), image.get_height())
    var square: = image.get_region(Rect2i(
        int((image.get_width() - side) / 2.0), int((image.get_height() - side) / 2.0), side, side))
    var interp: = Image.INTERPOLATE_NEAREST if side <= 96 else Image.INTERPOLATE_LANCZOS
    square.resize(out_size, out_size, interp)
    if circle:
        var radius: = out_size * 0.5
        for y in range(out_size):
            for x in range(out_size):
                var dist: = Vector2(x - radius + 0.5, y - radius + 0.5).length()
                if dist > radius - 1.5:
                    var color: = square.get_pixel(x, y)
                    color.a *= clampf(radius - dist, 0.0, 1.0)
                    square.set_pixel(x, y, color)
    return ImageTexture.create_from_image(square)



func _make_chip(rect: Rect2) -> Dictionary:
    var root: = Control.new()
    root.position = rect.position
    root.size = rect.size
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var chip_texture: = _v3("lv_chip.png")
    if chip_texture != null:
        var art: = TextureRect.new()
        art.texture = chip_texture
        art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        art.stretch_mode = TextureRect.STRETCH_SCALE
        art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        art.size = rect.size
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(art)
    else:
        var panel: = Panel.new()
        panel.size = rect.size
        var style: = StyleBoxFlat.new()
        style.bg_color = Color(0.03, 0.045, 0.09, 0.92)
        style.border_color = Color(0.76, 0.58, 0.27, 0.85)
        style.set_border_width_all(1)
        style.set_corner_radius_all(5)
        panel.add_theme_stylebox_override("panel", style)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(panel)
    var label: = UiKit.make_label_strong("", 12, UiKit.COLOR_TEXT)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.position = Vector2.ZERO
    label.size = rect.size
    label.clip_text = true
    root.add_child(label)
    return {"root": root, "label": label}



func _make_portrait_token(rect: Rect2, portrait: Texture2D) -> Control:
    var root: = Control.new()
    root.position = rect.position
    root.size = rect.size
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var inset: = rect.size * 0.11
    var picture: = TextureRect.new()
    picture.texture = _cropped_portrait(portrait, int(rect.size.x - inset.x * 2.0), false)
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_SCALE
    picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    picture.position = inset
    picture.size = rect.size - inset * 2.0
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(picture)
    var frame_texture: = _v3("token_frame.png")
    if frame_texture != null:
        var frame: = TextureRect.new()
        frame.texture = frame_texture
        frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        frame.stretch_mode = TextureRect.STRETCH_SCALE
        frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        frame.size = rect.size
        frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(frame)
    else:
        root.add_child(UiKit.make_ornate_frame(rect.size, "slot.png", 0.22, 12.0))
    return root



func _fit_label_font(label: Label, start_size: int, min_size: int) -> void :
    var font: = label.get_theme_font("font")
    if font == null:
        font = ThemeDB.fallback_font
    var size: = start_size
    while size > min_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > label.size.x:
        size -= 1
    label.add_theme_font_size_override("font_size", size)





func _make_ornate_bar(rect: Rect2, kind: String, ghost_tint: Color) -> Dictionary:
    var bar: = UiKit.make_bar(rect, kind)
    var root: Control = bar["root"]
    var ghost: Control
    var gold_texture: = UiKit.kit_texture("bar_fill_gold.png")
    if gold_texture != null:
        ghost = Control.new()
        ghost.size = rect.size
        ghost.clip_contents = true
        ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var ghost_fill: = TextureRect.new()
        ghost_fill.texture = gold_texture
        ghost_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ghost_fill.stretch_mode = TextureRect.STRETCH_SCALE
        ghost_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        ghost_fill.size = rect.size
        ghost_fill.modulate = ghost_tint
        ghost_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ghost.add_child(ghost_fill)
    else:
        var ghost_flat: = ColorRect.new()
        ghost_flat.color = ghost_tint
        ghost_flat.size = rect.size
        ghost = ghost_flat

    root.add_child(ghost)
    root.move_child(ghost, 1)
    return {"root": root, "fill": bar["fill"], "ghost": ghost}


func _make_panel_style(bg: Color = COLOR_PANEL_BG, border: Color = COLOR_PANEL_BORDER, radius: int = 5) -> StyleBox:
    var flat: = StyleBoxFlat.new()
    flat.bg_color = bg
    flat.border_color = border
    flat.set_border_width_all(2)
    flat.set_corner_radius_all(radius)
    flat.shadow_color = Color(0, 0, 0, 0.42)
    flat.shadow_size = 10
    flat.shadow_offset = Vector2(0, 2)
    flat.content_margin_left = 12
    flat.content_margin_right = 12
    flat.content_margin_top = 10
    flat.content_margin_bottom = 10
    return flat


func _make_panel_node(rect: Rect2, danger: bool = false) -> Panel:
    var panel: = Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    if UiKit.kit_texture("panel_frame.png") != null:
        panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
        var frame: = UiKit.make_ornate_frame(rect.size, "panel_frame.png", 0.16, 24.0)
        if danger:
            frame.modulate = Color(1.0, 0.58, 0.52, 1.0)
        panel.add_child(frame)
    else:
        var style: = _make_panel_style()
        if danger:
            (style as StyleBoxFlat).bg_color = Color(0.08, 0.02, 0.03, 0.86)
            (style as StyleBoxFlat).border_color = Color(0.88, 0.2, 0.18, 0.72)
        panel.add_theme_stylebox_override("panel", style)
    return panel


func _add_texture(parent: Control, path: String, rect: Rect2, alpha: float = 1.0, behind: bool = false) -> TextureRect:
    var texture: = _load_png_texture(path)
    var node: = TextureRect.new()
    node.position = rect.position
    node.size = rect.size
    node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    node.stretch_mode = TextureRect.STRETCH_SCALE
    node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.modulate.a = alpha
    if texture != null:
        node.texture = texture
    if behind:
        parent.add_child(node)
        parent.move_child(node, 0)
    else:
        parent.add_child(node)
    return node


func _make_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_label(text, font_size, color)



func _make_header_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_label_strong(text, font_size, color)



func _make_display_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_title(text, font_size, color)





func _build_ui() -> void :
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)


    var dim: = ColorRect.new()
    dim.color = Color(0.015, 0.016, 0.024, 0.9)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(dim)
    var backdrop_texture: = _load_battle_backdrop_texture()
    if backdrop_texture != null:
        var backdrop: = TextureRect.new()
        backdrop.texture = backdrop_texture
        backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
        backdrop.modulate = Color(1, 1, 1, 0.9)
        _root.add_child(backdrop)

    _design = Control.new()
    _design.position = ((get_viewport().get_visible_rect().size - DESIGN_SIZE) * 0.5).floor()
    _design.size = DESIGN_SIZE
    _design.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_design)


    # The top-left enemy card was removed — the foe's name + HP already show under
    # its sprite, while the target cursor marks which foe is selected. The battle
    # action readout takes over this space without a separate intent/telegraph row.

    _build_turn_order_strip()
    _build_foe_row()


    _log_panel = Panel.new()
    _log_panel.position = LOG_PANEL_POS
    _log_panel.size = LOG_PANEL_SIZE
    _log_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    _log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_log_panel)


    var scrim: = TextureRect.new()
    var scrim_gradient: = Gradient.new()
    scrim_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
    scrim_gradient.colors = PackedColorArray([
        Color(0.008, 0.012, 0.028, 0.72), 
        Color(0.008, 0.012, 0.028, 0.52), 
        Color(0.008, 0.012, 0.028, 0.0), 
    ])
    var scrim_texture: = GradientTexture2D.new()
    scrim_texture.gradient = scrim_gradient
    scrim_texture.fill = GradientTexture2D.FILL_RADIAL
    scrim_texture.fill_from = Vector2(0.5, 0.5)
    scrim_texture.fill_to = Vector2(0.5, 0.0)
    scrim_texture.width = 330
    scrim_texture.height = 152
    scrim.texture = scrim_texture
    scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    scrim.stretch_mode = TextureRect.STRETCH_SCALE
    scrim.position = Vector2(-26, -18)
    scrim.size = Vector2(382, 188)
    scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(scrim)


    # Each action owns its own row so its TTL/fade can run independently. A
    # single RichTextLabel would force every existing line (and icon) to flash
    # whenever just one history entry expires.
    _log_scroll = ScrollContainer.new()
    _log_scroll.position = Vector2(6, 6)
    _log_scroll.size = Vector2(300, 134)
    _log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    _log_scroll.follow_focus = false
    _log_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(_log_scroll)

    _log_list = VBoxContainer.new()
    _log_list.custom_minimum_size = Vector2(286, 0)
    _log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _log_list.add_theme_constant_override("separation", BATTLE_LOG_ENTRY_GAP)
    _log_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_scroll.add_child(_log_list)

    var log_scrollbar := _log_scroll.get_v_scroll_bar()
    log_scrollbar.modulate.a = 0.0
    log_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

    # Only terminal results use Enter. Ordinary action-log entries append and
    # auto-scroll without ever showing this marker or taking input focus.
    _continue_marker = _make_label("v", FONT_SIZE, COLOR_ACCENT)
    _continue_marker.position = Vector2(292, 120)
    _continue_marker.visible = false
    _log_panel.add_child(_continue_marker)


    _build_ally_stack()
    var command_left := _ally_stack.right_edge()
    _command_menu = BattleCommandMenuScript.new()
    _command_menu.position = Vector2(command_left, MENU_PANEL_TOP)
    _design.add_child(_command_menu)
    _command_menu.setup(Vector2(DESIGN_SIZE.x - command_left, MENU_PANEL_HEIGHT))

    _hint_label = _make_label("Arrows Move    Enter Select    / Esc Back", 13, COLOR_TEXT_DIM)
    _hint_label.position = Vector2(476, 520)
    _hint_label.size = Vector2(420, 20)
    _hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _hint_label.visible = false
    _design.add_child(_hint_label)


    _fx_layer = Control.new()
    _fx_layer.position = Vector2.ZERO
    _fx_layer.size = DESIGN_SIZE
    _fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_fx_layer)

    _refresh_all_panels()
    _play_intro_animation()


# ── foe row (multi-enemy battlefield) ─────────────────────────────────────────
## Portrait layout per group size: solo keeps the classic hero-shot, pairs and
## trios shrink + spread so nothing overlaps the left panels or the turn strip.
func _foe_layout() -> Array:
    match _foes.size():
        1:
            return [{"home": Vector2(350, 48), "size": Vector2(280, 290)}]
        2:
            return [
                {"home": Vector2(346, 92), "size": Vector2(210, 220)},
                {"home": Vector2(576, 92), "size": Vector2(210, 220)},
            ]
        _:
            return [
                {"home": Vector2(322, 122), "size": Vector2(152, 162)},
                {"home": Vector2(482, 122), "size": Vector2(152, 162)},
                {"home": Vector2(642, 122), "size": Vector2(152, 162)},
            ]


func _build_foe_row() -> void :
    var layout: Array = _foe_layout()
    var add_material: = CanvasItemMaterial.new()
    add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

    for index in range(_foes.size()):
        var foe: Dictionary = _foes[index]
        var slot: Dictionary = layout[mini(index, layout.size() - 1)]
        # Shift the complete foe rig as one unit so the portrait, labels, bars,
        # status row, target marker, speech anchor, animations, and FX stay aligned.
        var home: Vector2 = slot["home"] + Vector2(0, FOE_VERTICAL_OFFSET)
        var size: Vector2 = slot["size"]

        var holder: = Control.new()
        holder.position = home + Vector2(120, 0)
        holder.size = size
        holder.modulate.a = 0.0
        _design.add_child(holder)

        # Every portrait effect shares one bottom-pivoted transform. The target
        # rim, EXPOSED glow and hit flash therefore breathe with the enemy while
        # metadata and the overhead cursor remain perfectly stable.
        var visual_root := Control.new()
        visual_root.size = size
        visual_root.pivot_offset = Vector2(size.x * 0.5, size.y)
        visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(visual_root)

        var portrait: = TextureRect.new()
        portrait.size = size
        portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        var texture: = _foe_portrait_texture(foe)
        portrait.texture = texture
        portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if texture != null and texture.get_width() > 200 else CanvasItem.TEXTURE_FILTER_NEAREST
        portrait.pivot_offset = Vector2(size.x * 0.5, size.y)
        if texture == null:
            portrait.modulate = Color(1.0, 0.45, 0.45)
        visual_root.add_child(portrait)

        var glow: = portrait.duplicate() as TextureRect
        glow.material = add_material
        glow.modulate = Color(COLOR_EXPOSED, 0.0)
        visual_root.add_child(glow)

        var flash: = portrait.duplicate() as TextureRect
        flash.material = add_material.duplicate()
        flash.modulate = Color(1, 1, 1, 0.0)
        visual_root.add_child(flash)

        var target_visual := EnemyTargetHighlightScript.new()
        target_visual.setup(portrait, size)
        holder.add_child(target_visual)

        # Lightweight level/status metadata floats above the portrait, while the
        # redesigned nameplate stays below the enemy like the original layout.
        # Name width follows measured text; only its middle rail changes width.
        var identity: = EnemyIdentityPlateScript.new()
        identity.setup(
            str(foe.get("name")),
            int(foe.get("level", 1)),
            size.x,
            size.y,
            _foes.size(),
        )
        holder.add_child(identity)
        var status_row: HBoxContainer = identity.status_row

        # Match the approved hierarchy: portrait → HP → name. The footer keeps
        # the same total height as before, so pair/trio layouts do not drift.
        var bar_w: = size.x * 0.88
        var bar_x: = (size.x - bar_w) * 0.5
        var hp_y := size.y + 2.0
        var hp_height := 14.0
        identity.set_nameplate_top(hp_y + hp_height + 2.0)
        var bar: = _make_ornate_bar(
            Rect2(bar_x, hp_y, bar_w, hp_height), "red", COLOR_HP_GHOST)
        holder.add_child(bar["root"])

        var hp_text: = UiKit.make_title(
            "", 9 if _foes.size() >= 3 else 10, Color(0.98, 0.95, 0.88, 0.98))
        hp_text.position = Vector2(bar_x, hp_y + HP_TEXT_Y_OFFSET)
        hp_text.size = Vector2(bar_w, hp_height)
        hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        holder.add_child(hp_text)

        var overhead_bounds: Rect2 = identity.holder_local_bounds().merge(
            target_visual.marker_bounds())

        foe["ui"] = {
            "holder": holder,
            "visual_root": visual_root,
            "portrait": portrait,
            "glow": glow,
            "flash": flash,
            "home": home,
            "size": size,
            "hp_bar": bar["fill"],
            "hp_ghost": bar["ghost"],
            "hp_text": hp_text,
            "hp_root": bar["root"],
            "hp_y": hp_y,
            "identity_root": identity,
            "identity_bounds": overhead_bounds,
            "name_label": identity.name_label,
            "level_label": identity.level_label,
            "status_row": status_row,
            "target_visual": target_visual,
            "arrow": target_visual.marker,
            "bar_w": bar_w,
        }


func _foe_ui(foe: Dictionary) -> Dictionary:
    return foe.get("ui", {}) as Dictionary


func _foe_center(foe: Dictionary) -> Vector2:
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return SCREEN_CENTER
    var holder: Control = ui["holder"]
    var size: Vector2 = ui["size"]
    return holder.position + Vector2(size.x * 0.5, size.y * 0.46)


func _actor_fx_center(actor: Dictionary, is_ally: bool) -> Vector2:
    if is_ally:
        var index: = _allies.find(actor)
        if index >= 0 and index < _ally_cards.size():
            return _ally_cards[index].get("fx_center", PLAYER_FX_CENTER)
        return PLAYER_FX_CENTER
    return _foe_center(actor)


# ── enemy speech bubbles (real-time barks, kept OUT of the battle log) ─────────
## Enqueue-only by design: this function never awaits playback, changes _ui_mode,
## or consumes input. Each enemy drains its own fixed-template bark channel.
func _enemy_say(foe: Dictionary, quote: String) -> void :
    if _battle_over or _enemy_barks_shutting_down:
        return
    var text: = quote.strip_edges()
    if text.is_empty():
        return

    var key := _enemy_bark_key(foe)
    var channel: Dictionary = _enemy_bark_channels.get(key, {}) as Dictionary
    if channel.is_empty():
        channel = {
            "foe": foe,
            "pending": [],
            "active": null,
            "current": "",
            "running": false,
            "generation": 0,
        }
    var pending: Array = channel.get("pending", []) as Array
    var current := str(channel.get("current", ""))
    if current == text or (not pending.is_empty() and str(pending[pending.size() - 1]) == text):
        return
    if pending.size() >= MAX_PENDING_BARKS_PER_ENEMY:
        pending[pending.size() - 1] = text # newest context replaces stale backlog
    else:
        pending.append(text)
    channel["foe"] = foe
    channel["pending"] = pending

    if not bool(channel.get("running", false)):
        _enemy_bark_generation += 1
        channel["running"] = true
        channel["generation"] = _enemy_bark_generation
        _enemy_bark_channels[key] = channel
        # Deferred start guarantees the caller continues its action in this frame.
        call_deferred("_start_next_enemy_bark", key, _enemy_bark_generation)
    else:
        _enemy_bark_channels[key] = channel


func _start_next_enemy_bark(key: String, generation: int) -> void:
    if _enemy_barks_shutting_down or not is_inside_tree():
        return
    if _design == null or not _design.is_inside_tree() or not _enemy_bark_channels.has(key):
        return
    var channel: Dictionary = _enemy_bark_channels[key] as Dictionary
    if int(channel.get("generation", -1)) != generation:
        return
    var pending: Array = channel.get("pending", []) as Array
    if pending.is_empty():
        _enemy_bark_channels.erase(key)
        return

    var text := str(pending.pop_front())
    var foe: Dictionary = channel.get("foe", {}) as Dictionary
    channel["pending"] = pending
    channel["current"] = text
    var bubble := _spawn_enemy_bubble(foe, text)
    channel["active"] = bubble
    _enemy_bark_channels[key] = channel
    if bubble == null:
        channel["current"] = ""
        _enemy_bark_channels[key] = channel
        call_deferred("_start_next_enemy_bark", key, generation)
        return

    # Signal-driven sequencing avoids suspended coroutine states. Cancellation,
    # natural completion and tree teardown all pass through the same cleanup path.
    bubble.playback_finished.connect(
        _on_enemy_bark_playback_finished.bind(key, generation, bubble),
        CONNECT_ONE_SHOT,
    )
    bubble.play()


func _on_enemy_bark_playback_finished(
    _cancelled: bool,
    key: String,
    generation: int,
    bubble: Control,
) -> void:
    if is_instance_valid(bubble) and bubble.is_inside_tree():
        bubble.queue_free()
    if _enemy_barks_shutting_down or not _enemy_bark_channels.has(key):
        return
    var channel: Dictionary = _enemy_bark_channels[key] as Dictionary
    if int(channel.get("generation", -1)) != generation:
        return
    channel["active"] = null
    channel["current"] = ""
    var pending: Array = channel.get("pending", []) as Array
    if pending.is_empty():
        _enemy_bark_channels.erase(key)
        return
    _enemy_bark_channels[key] = channel
    # Always defer the next add_child: a cancellation signal can originate while
    # the previous bubble or its parent is in the middle of exiting the tree.
    call_deferred("_start_next_enemy_bark", key, generation)


func _enemy_bark_key(foe: Dictionary) -> String:
    var key := str(foe.get("id", ""))
    if not key.is_empty():
        return key
    var index := _foes.find(foe)
    return "foe_%d" % maxi(index, 0)


func _shutdown_enemy_barks() -> void:
    if _enemy_barks_shutting_down:
        return
    _enemy_barks_shutting_down = true
    _enemy_bark_generation += 1
    for raw_channel in _enemy_bark_channels.values():
        var channel: Dictionary = raw_channel as Dictionary
        var active: Variant = channel.get("active")
        if active != null and is_instance_valid(active):
            if (active as Object).has_method("cancel_playback"):
                (active as Object).call("cancel_playback")
            (active as Node).queue_free()
    _enemy_bark_channels.clear()


func _spawn_enemy_bubble(foe: Dictionary, text: String) -> Control:
    var bubble: = BattleSpeechBubbleScript.new()
    bubble.setup(text)
    _design.add_child(bubble)   # newest child → drawn above the battlefield

    # Start from the face centre for layout, but anchor the pointer on the near
    # hair/horn/shoulder edge so the speaking enemy's expression stays visible.
    var face_center: Vector2
    var face_safe_x := 30.0
    var ui: = _foe_ui(foe)
    var identity_rect := Rect2()
    var has_identity_rect := false
    if ui.is_empty():
        var c: = _foe_center(foe)
        face_center = c - Vector2(0.0, 40.0)
    else:
        var holder: Control = ui["holder"]
        var slot: Vector2 = ui["size"]
        # Generated battle portraits often keep generous transparent padding.
        face_center = holder.position + Vector2(slot.x * 0.5, slot.y * 0.32)
        face_safe_x = clampf(slot.x * 0.16, 24.0, 48.0)
        if ui.has("identity_bounds"):
            var local_identity: Rect2 = ui["identity_bounds"]
            identity_rect = Rect2(holder.position + local_identity.position, local_identity.size).grow(4.0)
            has_identity_rect = true

    var w: float = bubble.size.x
    var h: float = bubble.size.y

    # Evaluate both authored directions. Preference follows the enemy's half of
    # the screen, while overflow and collision with the battle log carry a much
    # larger penalty. No template is stretched or procedurally re-aimed.
    var prefer_bubble_on_right: = face_center.x < DESIGN_SIZE.x * 0.52
    var candidates: Array[Dictionary] = []
    for bubble_on_right in [true, false]:
        # Bubble on the right of the enemy needs the mirrored down-left pointer.
        var pointer_side: int = 0 if bubble_on_right else 1
        bubble.set_pointer_side(pointer_side)
        var tip: Vector2 = bubble.pointer_tip_local()
        var side_sign := 1.0 if bubble_on_right else -1.0
        # Keep the fixed pointer attached near the upper hair/horn edge while
        # lifting the complete bubble slightly above the speaking enemy.
        var speaker_anchor := face_center + Vector2(
            face_safe_x * side_sign,
            -4.0 - ENEMY_BARK_VERTICAL_LIFT,
        )
        var candidate_pos: = speaker_anchor - tip
        var candidate_rect: = Rect2(candidate_pos, Vector2(w, h))
        var penalty: = 0.0
        penalty += maxf(12.0 - candidate_rect.position.x, 0.0) * 180.0
        penalty += maxf(candidate_rect.end.x - (DESIGN_SIZE.x - 12.0), 0.0) * 180.0
        penalty += maxf(12.0 - candidate_rect.position.y, 0.0) * 120.0
        penalty += maxf(candidate_rect.end.y - (DESIGN_SIZE.y - 12.0), 0.0) * 120.0
        var log_rect := Rect2(LOG_PANEL_POS, LOG_PANEL_SIZE).grow(8.0)
        if candidate_rect.intersects(log_rect):
            var overlap := candidate_rect.intersection(log_rect)
            penalty += overlap.size.x * overlap.size.y * 0.9
        if has_identity_rect and candidate_rect.intersects(identity_rect):
            var identity_overlap := candidate_rect.intersection(identity_rect)
            penalty += identity_overlap.size.x * identity_overlap.size.y * 1.5

        # Concurrent barks remain independent, but prefer opposite sides when two
        # live templates would obscure each other.
        for raw_channel in _enemy_bark_channels.values():
            var other_channel: Dictionary = raw_channel as Dictionary
            var other: Variant = other_channel.get("active")
            if other == null or not is_instance_valid(other) or other == bubble:
                continue
            var other_bubble := other as Control
            var other_rect := Rect2(other_bubble.position, other_bubble.size).grow(5.0)
            if candidate_rect.intersects(other_rect):
                var bubble_overlap := candidate_rect.intersection(other_rect)
                penalty += bubble_overlap.size.x * bubble_overlap.size.y * 1.2
        if bubble_on_right != prefer_bubble_on_right:
            penalty += 28.0
        candidates.append({
            "right": bubble_on_right,
            "position": candidate_pos,
            "anchor": speaker_anchor,
            "penalty": penalty,
        })

    var chosen: Dictionary = candidates[0]
    if float(candidates[1]["penalty"]) < float(chosen["penalty"]):
        chosen = candidates[1]
    var on_right: bool = bool(chosen["right"])
    bubble.set_pointer_side(0 if on_right else 1)
    var pos: Vector2 = chosen["position"]
    pos.x = clampf(pos.x, 12.0, DESIGN_SIZE.x - w - 12.0)
    pos.y = clampf(pos.y, 12.0, DESIGN_SIZE.y - h - 12.0)

    # Clamping near a screen edge can pull the authored tip back toward the eyes.
    # Nudge it outward once more when canvas room allows.
    var actual_tip := pos + bubble.pointer_tip_local()
    var minimum_face_clearance := face_safe_x * 0.72
    if absf(actual_tip.x - face_center.x) < minimum_face_clearance:
        var clearance_sign := 1.0 if on_right else -1.0
        var desired_tip_x := face_center.x + minimum_face_clearance * clearance_sign
        pos.x += desired_tip_x - actual_tip.x
        pos.x = clampf(pos.x, 12.0, DESIGN_SIZE.x - w - 12.0)
    bubble.position = pos
    bubble.set_meta("speaker_face_center", face_center)
    bubble.set_meta("speaker_anchor", pos + bubble.pointer_tip_local())
    return bubble


# ── ally card stack (hero + companions, bottom-left) ─────────────────────────
const HP_TEXT_Y_OFFSET: = -4.0
const SP_PIP_SIDE := 15.0
const SP_PIP_GAP := 5.0
const SP_ROW_HEIGHT := 15.0
const COMPACT_ALLY_SCRIM_OVERSCAN := Vector2(18.0, 10.0)


func _build_ally_stack() -> void:
    _ally_stack = BattleAllyCardStackScript.new()
    _ally_stack.configure(
        self,
        _allies,
        _ally_cards,
        Callable(self, "_build_ally_card"),
        Callable(self, "_refresh_ally_card"),
        Callable(self, "_actor_down"),
        Callable(self, "_effective_speed"),
    )
    _ally_stack.build(_round_queue, _queue_pos)


func _build_ally_card(ally: Dictionary, rect: Rect2, is_full: bool) -> Dictionary:
    var panel: Panel
    var compact_scrim: TextureRect = null
    if is_full:
        panel = _make_panel_node(rect)
    else:
        # Match the selected-command readout: a radial dark haze that dissolves
        # into the battle art instead of reading as a rectangular card.
        panel = Panel.new()
        panel.position = rect.position
        panel.size = rect.size
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
        compact_scrim = BattleCommandMenuScript.make_soft_info_scrim(
            rect.size + COMPACT_ALLY_SCRIM_OVERSCAN * 2.0)
        compact_scrim.position = -COMPACT_ALLY_SCRIM_OVERSCAN
        panel.add_child(compact_scrim)
    panel.set_meta("ally_card_form", "full" if is_full else "compact")
    _design.add_child(panel)
    # Runtime card swaps happen after the FX layer exists. Keep cards below it
    # just like the initial stack so hit/heal effects remain visible.
    if _fx_layer != null and is_instance_valid(_fx_layer):
        _design.move_child(panel, _fx_layer.get_index())

    var portrait_side: = rect.size.y - 20.0
    var holder: = Control.new()
    holder.position = Vector2(10, 10)
    holder.size = Vector2(portrait_side, portrait_side)
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(holder)
    var picture: = TextureRect.new()
    var texture: = _ally_portrait_texture(ally)
    picture.texture = texture
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if texture != null and texture.get_width() > 200 else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if texture != null and texture.get_width() > 200 else CanvasItem.TEXTURE_FILTER_NEAREST
    picture.position = Vector2.ZERO
    picture.size = holder.size
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(picture)

    var left: = 20.0 + portrait_side
    var name_label: Label = null
    var lv_label: Label = null
    if is_full:
        name_label = _make_display_label(str(ally.get("name")), 18, COLOR_ACCENT)
        name_label.position = Vector2(left, 8)
        name_label.size = Vector2(rect.size.x - left - 74, 22)
        name_label.clip_text = true
        panel.add_child(name_label)

        var chip: = _make_chip(Rect2(rect.size.x - 70, 10, 56, 19))
        lv_label = chip["label"] as Label
        lv_label.add_theme_font_size_override("font_size", 11)
        panel.add_child(chip["root"])

    var bar_w: = rect.size.x - left - 18.0
    var hp_y: = 34.0 if is_full else 30.0
    var bar: = _make_ornate_bar(Rect2(left, hp_y, bar_w, 13), "green", COLOR_HP_GHOST)
    panel.add_child(bar["root"])

    var hp_text: = UiKit.make_label_strong("", 9, Color(0.98, 0.95, 0.88, 0.96))
    hp_text.position = Vector2(left, hp_y + HP_TEXT_Y_OFFSET)
    hp_text.size = Vector2(bar_w, 13)
    hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    panel.add_child(hp_text)

    # SP gem pips.
    var sp_row: = Control.new()
    sp_row.position = Vector2(left, hp_y + 17)
    sp_row.size = Vector2(bar_w, SP_ROW_HEIGHT)
    # The fit calculation keeps every pip inside; clipping is a final guard for
    # fractional rendering at unusual viewport scales.
    sp_row.clip_contents = true
    panel.add_child(sp_row)
    var sp_pips: Array = _build_sp_pips_for(
        sp_row, int(ally.get("sp_max", 3)), bar_w)

    var status_row: HBoxContainer = null
    if is_full:
        status_row = _make_status_row(
            panel, Rect2(left, hp_y + 34, bar_w, 15), BoxContainer.ALIGNMENT_BEGIN, 14)

    var xp_bar: Control = null
    var xp_text: Label = null
    if is_full:
        var xp_label: = UiKit.make_label_strong("XP", 10, COLOR_TEXT_DIM)
        xp_label.position = Vector2(left, hp_y + 52)
        panel.add_child(xp_label)
        var xp: = UiKit.make_bar(Rect2(left + 24, hp_y + 54, bar_w - 24, 9), "blue")
        panel.add_child(xp["root"])
        xp_bar = xp["fill"]
        xp_text = _make_label("", 8, COLOR_TEXT_DIM)
        xp_text.position = Vector2(left + 24, hp_y + 64)
        xp_text.size = Vector2(bar_w - 24, 11)
        xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        panel.add_child(xp_text)

    # Ally-side target arrow (heal/shield targeting).
    var arrow: = _make_display_label("▶", 18, COLOR_ACCENT)
    arrow.position = Vector2(-24, rect.size.y * 0.5 - 12)
    arrow.size = Vector2(22, 24)
    arrow.visible = false
    panel.add_child(arrow)

    return {
        "root": panel,
        "rect": rect,
        "is_full": is_full,
        "name_label": name_label,
        "lv_label": lv_label,
        "hp_bar": bar["fill"],
        "hp_ghost": bar["ghost"],
        "hp_text": hp_text,
        "sp_pips": sp_pips,
        "sp_row": sp_row,
        "status_row": status_row,
        "xp_bar": xp_bar,
        "xp_text": xp_text,
        "compact_scrim": compact_scrim,
        "bar_w": bar_w,
        "arrow": arrow,
        "fx_center": rect.position + rect.size * 0.5,
        "portrait": picture,
    }


func _ally_portrait_texture(ally: Dictionary) -> Texture2D:
    if str(ally.get("kind")) == "player":
        return _hero_portrait_texture()
    var npc_id: = str(ally.get("id"))
    var portrait: Texture2D = PartyManager.companion_portrait(npc_id)
    if portrait != null:
        return portrait
    return PartyManager.companion_texture(npc_id)


func _build_turn_order_strip() -> void :
    # The "TURN ORDER" title was removed; the card stack now sits at the top edge.
    _turn_stack = Control.new()
    _turn_stack.position = TURN_ORDER_STACK_POS
    _turn_stack.size = TURN_ORDER_STACK_SIZE
    _turn_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_turn_stack)


const TURN_CARD_SIZE: = Vector2(148, 44)
# Card right edge sits 2px from the canvas edge (960) so the gap on the right
# matches the stack's 2px gap from the top (TURN_ORDER_STACK_POS.y).
const TURN_CARD_RIGHT: = 958.0
const TURN_CARD_TUCK: = 0.0
const TURN_CARD_POP: = 6.0




## Render the given queue entries ([{texture, label}, ...], first = acting now)
## into the right-edge card stack. Fed by _update_turn_order_view from the REAL
## speed-ordered round queue.
func _rebuild_turn_cards(display: Array, animate: bool = true) -> void :
    if _turn_stack == null:
        return
    for card in _turn_cards:
        if animate:
            # Departing queue scrolls up and fades out.
            var out := create_tween()
            out.tween_property(card, "position:y", card.position.y - 54.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
            out.parallel().tween_property(card, "modulate:a", 0.0, 0.22)
            out.tween_callback(card.queue_free)
        else:
            card.queue_free()
    _turn_cards.clear()

    for index in range(display.size()):
        var entry: Dictionary = display[index]
        var is_active: = index == 0
        var card: = _make_turn_card(entry, is_active)
        var final_x: = TURN_CARD_RIGHT - TURN_CARD_SIZE.x - (TURN_CARD_POP if is_active else 0.0) + (0.0 if is_active else TURN_CARD_TUCK)
        var y: = float(index) * (TURN_CARD_SIZE.y + 10.0)
        if animate:
            # Incoming queue scrolls UP into place while fading in.
            card.position = Vector2(final_x, y + 54.0)
            card.modulate.a = 0.0
            var rise := create_tween()
            rise.tween_property(card, "position:y", y, 0.28).set_delay(0.05 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
            rise.parallel().tween_property(card, "modulate:a", 1.0 if index > 0 else 1.0, 0.26).set_delay(0.05 * index)
            if index > 0:
                rise.parallel().tween_property(card, "modulate", Color(0.72, 0.74, 0.84, 0.82), 0.26).set_delay(0.05 * index)
        else:
            card.position = Vector2(final_x, y)
        _turn_stack.add_child(card)
        _turn_cards.append(card)




func _player_turn_texture() -> Texture2D:
    return _hero_portrait_texture()


## Crop a character texture into a slanted banner that FILLS a turn card:
## center-cropped to the card aspect (face-biased), then alpha-masked to the
## card art's parallelogram interior so it never spills past the gold border.
func _banner_portrait(texture: Texture2D, out_w: int = 296, out_h: int = 88) -> Texture2D:
    if texture == null:
        return null
    var image := texture.get_image()
    if image == null:
        return texture
    image = image.duplicate()
    if image.is_compressed():
        image.decompress()
    image.convert(Image.FORMAT_RGBA8)
    var ratio := float(out_w) / float(out_h)
    var crop_w := float(image.get_width())
    var crop_h := crop_w / ratio
    if crop_h > float(image.get_height()):
        crop_h = float(image.get_height())
        crop_w = crop_h * ratio
    var x0 := int((image.get_width() - crop_w) * 0.5)
    var y0 := int(clampf((image.get_height() - crop_h) * 0.32, 0.0, float(image.get_height()) - crop_h))
    var band := image.get_region(Rect2i(x0, y0, int(crop_w), int(crop_h)))
    var interp := Image.INTERPOLATE_NEAREST if image.get_width() <= 96 else Image.INTERPOLATE_LANCZOS
    band.resize(out_w, out_h, interp)
    var slant := out_w * 0.145
    var inset := out_w * 0.028
    for y in range(out_h):
        var t := float(y) / float(out_h - 1)
        var left_edge := slant * (1.0 - t) + inset
        var right_edge := float(out_w) - inset * 1.6
        var row_alpha := 1.0 if y >= int(inset) and y < out_h - int(inset) else 0.0
        for x in range(out_w):
            var alpha := row_alpha
            if float(x) < left_edge:
                alpha *= clampf(float(x) - left_edge + 1.5, 0.0, 1.0)
            elif float(x) > right_edge:
                alpha *= clampf(right_edge - float(x) + 1.5, 0.0, 1.0)
            if alpha < 1.0:
                var color := band.get_pixel(x, y)
                color.a *= alpha
                band.set_pixel(x, y, color)
    return ImageTexture.create_from_image(band)


func _make_turn_card(entry: Dictionary, is_active: bool) -> Control:
    var card := Control.new()
    card.size = TURN_CARD_SIZE
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var art := _v3("turncard_active.png" if is_active else "turncard.png")
    if art != null:
        var backing := TextureRect.new()
        backing.texture = art
        backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        backing.stretch_mode = TextureRect.STRETCH_SCALE
        backing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        backing.size = TURN_CARD_SIZE
        backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(backing)
    else:
        var flat := ColorRect.new()
        flat.color = Color(0.14, 0.11, 0.04, 0.92) if is_active else Color(0.03, 0.045, 0.09, 0.85)
        flat.size = TURN_CARD_SIZE
        flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(flat)

    # The character image fills the whole card (parallelogram-masked band),
    # no name text — the picture IS the card.
    var source: Texture2D = entry.get("texture")
    var banner := TextureRect.new()
    banner.texture = _banner_portrait(source)
    banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    banner.stretch_mode = TextureRect.STRETCH_SCALE
    banner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if source != null and source.get_width() > 96 else CanvasItem.TEXTURE_FILTER_NEAREST
    banner.size = TURN_CARD_SIZE
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(banner)

    if not is_active:
        card.modulate = Color(0.72, 0.74, 0.84, 0.82)
    return card

## Build SP gem pips into `row` and return the pip node list (per ally card).
## Normal counts keep the authored 15px gem and 5px gap. Larger pools scale
## both proportionally so the complete row always fits its full/compact card.
func _build_sp_pips_for(row: Control, sp_max: int, available_width: float) -> Array:
    var pips: Array = []
    var filled_texture: = _v3("sp_gem.png")
    var empty_texture: = _v3("sp_gem_empty.png")
    var pip_count := maxi(sp_max, 0)
    if pip_count == 0:
        return pips
    var natural_width := float(pip_count) * SP_PIP_SIDE \
        + float(maxi(pip_count - 1, 0)) * SP_PIP_GAP
    var fit_scale := minf(1.0, maxf(available_width, 0.0) / maxf(natural_width, 1.0))
    var pip_side := SP_PIP_SIDE * fit_scale
    var pip_gap := SP_PIP_GAP * fit_scale
    var pip_step := pip_side + pip_gap
    var pip_y := (SP_ROW_HEIGHT - pip_side) * 0.5
    for index in range(pip_count):
        if filled_texture != null:
            var gem: = TextureRect.new()
            gem.texture = filled_texture
            gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            gem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            gem.position = Vector2(float(index) * pip_step, pip_y)
            gem.size = Vector2.ONE * pip_side
            gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
            gem.set_meta("empty_texture", empty_texture)
            gem.set_meta("filled_texture", filled_texture)
            row.add_child(gem)
            pips.append(gem)
        else:
            var pip: = ColorRect.new()
            var fallback_side := 9.0 * fit_scale
            pip.size = Vector2.ONE * fallback_side
            pip.position = Vector2(
                float(index) * pip_step + (pip_side - fallback_side) * 0.5,
                (SP_ROW_HEIGHT - fallback_side) * 0.5,
            )
            pip.rotation_degrees = 45.0
            pip.pivot_offset = Vector2.ONE * fallback_side * 0.5
            pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
            row.add_child(pip)
            pips.append(pip)
    return pips


func _refresh_sp_pips_for(card: Dictionary, ally: Dictionary) -> void :
    var pips: Array = card.get("sp_pips", []) as Array
    # SP max can grow on level-up mid battle — rebuild when the count drifts.
    if pips.size() != int(ally.get("sp_max", 3)):
        for pip in pips:
            var pip_node := pip as Node
            if pip_node.get_parent() == card["sp_row"]:
                (card["sp_row"] as Node).remove_child(pip_node)
            pip_node.queue_free()
        card["sp_pips"] = _build_sp_pips_for(
            card["sp_row"],
            int(ally.get("sp_max", 3)),
            float(card.get("bar_w", 0.0)),
        )
        pips = card["sp_pips"]
    var sp: int = int(ally.get("sp", 0))
    for index in range(pips.size()):
        var pip: Variant = pips[index]
        var filled: = index < sp
        if pip is TextureRect and (pip as TextureRect).has_meta("filled_texture"):
            var empty_texture: Texture2D = (pip as TextureRect).get_meta("empty_texture")
            if empty_texture != null:
                (pip as TextureRect).texture = (pip as TextureRect).get_meta("filled_texture") if filled else empty_texture
            else:
                (pip as TextureRect).texture = (pip as TextureRect).get_meta("filled_texture")
                (pip as TextureRect).modulate = Color(1, 1, 1, 1.0) if filled else Color(0.35, 0.35, 0.42, 0.8)
        elif pip is ColorRect:
            (pip as ColorRect).color = COLOR_ACCENT if filled else Color(0.25, 0.22, 0.3, 0.9)


func _play_intro_animation() -> void :

    var flash: = ColorRect.new()
    flash.color = Color(1, 1, 1, 0.85)
    flash.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(flash)
    var flash_tween: = create_tween()
    flash_tween.tween_property(flash, "color:a", 0.0, 0.45)
    flash_tween.tween_callback(flash.queue_free)



    var off: Vector2 = _design.position
    _log_panel.position.x = -LOG_PANEL_SIZE.x - 40.0 - off.x
    _command_menu.position.y = DESIGN_SIZE.y + 24.0 + off.y

    var slide: = create_tween().set_parallel(true)
    slide.tween_property(_log_panel, "position:x", LOG_PANEL_POS.x, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    slide.tween_property(_command_menu, "position:y", MENU_PANEL_TOP, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

    for index in range(_ally_cards.size()):
        var card_root: Control = _ally_cards[index]["root"]
        var rect: Rect2 = _ally_cards[index]["rect"]
        card_root.position.x = -rect.size.x - 40.0 - off.x
        slide.tween_property(card_root, "position:x", rect.position.x, 0.5 + 0.06 * index).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

    for index in range(_foes.size()):
        var ui: Dictionary = _foe_ui(_foes[index])
        if ui.is_empty():
            continue
        var holder: Control = ui["holder"]
        slide.tween_property(holder, "position", ui["home"], 0.55 + 0.08 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        slide.tween_property(holder, "modulate:a", 1.0, 0.4 + 0.08 * index)

    _start_breathing()


func _start_breathing() -> void :
    for foe in _foes:
        var ui: Dictionary = _foe_ui(foe)
        if ui.is_empty():
            continue
        var breath: = create_tween().set_loops()
        breath.tween_property(ui["visual_root"], "scale", Vector2(1.0, 1.015), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        breath.tween_property(ui["visual_root"], "scale", Vector2(1.0, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _battle_portrait_texture() -> Texture2D:
    return _portrait_texture_for(enemy)


func _foe_portrait_texture(foe: Dictionary) -> Texture2D:
    return _portrait_texture_for(foe.get("data", {}) as Dictionary)


func _portrait_texture_for(data: Dictionary) -> Texture2D:
    var portrait_file: String = str(data.get("battle_portrait_file", ""))
    var texture: Texture2D = null
    if not portrait_file.is_empty():
        texture = GameManager.load_texture(GameManager.get_scene_asset_path(portrait_file))
    if texture == null:
        var sheet_file: String = str(data.get("sprite_sheet_file", ""))
        var sheet: Texture2D = null
        if not sheet_file.is_empty():
            sheet = GameManager.load_texture(GameManager.get_scene_asset_path(sheet_file))
        if sheet == null:
            sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
        if sheet != null:
            var atlas: = AtlasTexture.new()
            atlas.atlas = sheet
            atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
            texture = atlas
    return texture



func _hero_portrait_texture() -> Texture2D:
    var emotion_portrait: = _player_emotion_portrait_texture("neutral")
    if emotion_portrait != null:
        return emotion_portrait
    var hero: = _v3("hero_portrait.png")
    if hero != null:
        return hero
    var sheet: = GameManager.load_texture(GameManager.get_player_sprite_path())
    if sheet == null:
        sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
    if sheet != null:
        var atlas: = AtlasTexture.new()
        atlas.atlas = sheet
        atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
        return atlas
    return null


func _player_emotion_portrait_texture(emotion: String) -> Texture2D:
    var package: Dictionary = GameManager.get_scene_package()
    var characters: Dictionary = package.get("characters", {}) as Dictionary
    var main_character: Variant = characters.get("main_character", {})
    if main_character is Dictionary:
        return _character_emotion_portrait_texture(main_character as Dictionary, emotion)
    return null


func _character_emotion_portrait_texture(character: Dictionary, emotion: String) -> Texture2D:
    var emotion_info: Variant = character.get("emotion_portraits")
    if not (emotion_info is Dictionary):
        return null
    var portraits: Array = (emotion_info as Dictionary).get("portraits", []) as Array
    for wanted in [_normalize_battle_emotion(emotion), "neutral"]:
        for raw_portrait in portraits:
            if not (raw_portrait is Dictionary):
                continue
            var portrait: Dictionary = raw_portrait as Dictionary
            if str(portrait.get("emotion", "")) != wanted:
                continue
            var file_name: String = str(portrait.get("file", ""))
            if file_name.is_empty():
                continue
            var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(file_name))
            if texture != null:
                return texture
    return null


func _normalize_battle_emotion(emotion: String) -> String:
    match emotion.strip_edges().to_lower():
        "happy", "joy", "joyful", "pleased", "relieved":
            return "happy"
        "angry", "anger", "mad", "irritated", "annoyed":
            return "angry"
        "sad", "sorrow", "worried", "wary", "uneasy", "haunted", "tired", "afraid", "scared":
            return "sad"
        _:
            return "neutral"


func _load_battle_backdrop_texture() -> Texture2D:
    var backdrop_file: String = str(enemy.get("battle_background_file", ""))
    if backdrop_file.is_empty():
        var package: Dictionary = GameManager.get_scene_package()
        var battle_background: Dictionary = package.get("battle_background", {}) as Dictionary
        backdrop_file = str(battle_background.get("image", ""))
    if not backdrop_file.is_empty():
        var texture: = GameManager.load_texture(GameManager.get_scene_asset_path(backdrop_file))
        if texture != null:
            return texture
    if ResourceLoader.exists(TEX_BACKDROP):
        return load(TEX_BACKDROP) as Texture2D
    return null





func _shake(strength: float, duration: float) -> void :
    _shake_strength = max(_shake_strength, strength)
    _shake_time = max(_shake_time, duration)


## Center of the PRIMARY foe (story fx: probe reveals, finisher).
func _portrait_center() -> Vector2:
    if _foes.is_empty():
        return SCREEN_CENTER
    return _foe_center(_foes[0])


func _flash_portrait(foe: Dictionary, color: Color = Color(1, 1, 1, 1), strength: float = 0.85) -> void :
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return
    var flash: TextureRect = ui["flash"]
    flash.modulate = Color(color.r, color.g, color.b, strength)
    var tween: = create_tween()
    tween.tween_property(flash, "modulate:a", 0.0, 0.28)


func _spawn_slash(at: Vector2, tint: Color = Color(1, 1, 1, 1), effect_scale: float = 1.3, flipped: bool = false) -> void :
    if _slash_frames != null:
        var slash: = AnimatedSprite2D.new()
        slash.sprite_frames = _slash_frames
        slash.position = at
        slash.scale = Vector2( - effect_scale if flipped else effect_scale, effect_scale)
        slash.modulate = tint
        slash.rotation_degrees = randf_range(-18.0, 18.0)
        _fx_layer.add_child(slash)
        slash.play("slash")
        slash.animation_finished.connect(slash.queue_free)
    else:

        var line: = Line2D.new()
        var fallback_scale: float = effect_scale / 1.3
        line.width = 3.0 * fallback_scale
        line.default_color = tint if tint != Color(1, 1, 1, 1) else COLOR_ACCENT
        for step in range(9):
            var angle: float = deg_to_rad(-60.0 + step * 15.0)
            line.add_point(at + Vector2(cos(angle), sin(angle)) * 34.0 * fallback_scale)
        _fx_layer.add_child(line)
        var tween: = create_tween()
        tween.tween_property(line, "modulate:a", 0.0, 0.25)
        tween.tween_callback(line.queue_free)


func _spawn_particles(at: Vector2, color: Color, amount: int = 14, spread_up: bool = true) -> void :
    var particles: = CPUParticles2D.new()
    particles.position = at
    particles.one_shot = true
    particles.emitting = true
    particles.amount = amount
    particles.lifetime = 0.6
    particles.explosiveness = 0.95
    particles.direction = Vector2(0, -1) if spread_up else Vector2(0, 1)
    particles.spread = 70.0
    particles.gravity = Vector2(0, 160.0)
    particles.initial_velocity_min = 40.0
    particles.initial_velocity_max = 95.0
    particles.scale_amount_min = 1.0
    particles.scale_amount_max = 2.4
    particles.color = color
    _fx_layer.add_child(particles)
    get_tree().create_timer(1.4).timeout.connect(particles.queue_free)


func _spawn_damage_number(at: Vector2, text: String, color: Color, big: bool = false) -> void :
    var label: = _make_label(text, 14 if big else 11, color)
    label.position = at + Vector2(randf_range(-12.0, 12.0), -6.0)
    label.pivot_offset = Vector2(12, 8)
    label.scale = Vector2(1.7, 1.7)
    _fx_layer.add_child(label)
    var tween: = create_tween()
    tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(label, "position:y", label.position.y - 24.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
    tween.tween_callback(label.queue_free)


func _enemy_hit_react(foe: Dictionary, heavy: bool = false) -> void :
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return
    _flash_portrait(foe)
    _shake(5.0 if heavy else 3.0, 0.3 if heavy else 0.22)
    var holder: Control = ui["holder"]
    var home: Vector2 = ui["home"]
    var recoil: = create_tween()
    recoil.tween_property(holder, "position", home + Vector2(10, -4), 0.07)
    recoil.tween_property(holder, "position", home, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enemy_lunge(foe: Dictionary) -> void :
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return
    var holder: Control = ui["holder"]
    var home: Vector2 = ui["home"]
    var lunge: = create_tween()
    lunge.tween_property(holder, "position", home + Vector2(-22, 6), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    lunge.tween_property(holder, "position", home, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Exposed glow always concerns the PRIMARY foe (the probe/weakness story system).
func _set_exposed_glow(active: bool) -> void :
    if _foes.is_empty():
        return
    var ui: Dictionary = _foe_ui(_foes[0])
    if ui.is_empty():
        return
    var glow: TextureRect = ui["glow"]
    if active:
        var pulse: = create_tween().set_loops()
        pulse.set_meta("exposed_pulse", true)
        pulse.tween_property(glow, "modulate:a", 0.45, 0.55).set_trans(Tween.TRANS_SINE)
        pulse.tween_property(glow, "modulate:a", 0.12, 0.55).set_trans(Tween.TRANS_SINE)
        glow.set_meta("pulse_tween", pulse)
    else:
        var pulse: Variant = glow.get_meta("pulse_tween") if glow.has_meta("pulse_tween") else null
        if pulse is Tween and (pulse as Tween).is_valid():
            (pulse as Tween).kill()
        var fade: = create_tween()
        fade.tween_property(glow, "modulate:a", 0.0, 0.3)


func _animate_foe_hp(foe: Dictionary) -> void :
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return
    var bar_w: float = float(ui.get("bar_w", 120.0))
    (ui["hp_text"] as Label).text = "%d / %d" % [maxi(int(foe.get("hp", 0)), 0), int(foe.get("max_hp", 1))]
    var ratio: float = clampf(float(foe.get("hp", 0)) / float(foe.get("max_hp", 1)), 0.0, 1.0)
    var tween: = create_tween()
    tween.tween_property(ui["hp_bar"], "size:x", bar_w * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var ghost: = create_tween()
    ghost.tween_property(ui["hp_ghost"], "size:x", bar_w * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)
    if _target_foe_index < _foes.size() and _foes[_target_foe_index] == foe:
        _refresh_target_readout()


func _animate_ally_hp(ally: Dictionary) -> void :
    var index: = _allies.find(ally)
    if index < 0 or index >= _ally_cards.size():
        return
    var card: Dictionary = _ally_cards[index]
    var max_hp: int = int(ally.get("max_hp", 80))
    var hp: int = _ally_hp(ally)
    var bar_w: float = float(card.get("bar_w", PLAYER_HP_BAR_W))
    (card["hp_text"] as Label).text = "%d / %d" % [hp, max_hp]
    var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
    var tween: = create_tween()
    tween.tween_property(card["hp_bar"], "size:x", bar_w * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var ghost: = create_tween()
    ghost.tween_property(card["hp_ghost"], "size:x", bar_w * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)
    if (card["hp_bar"] as Control).size.x / bar_w > ratio:
        var damage_flash: = create_tween()
        damage_flash.tween_property(card["root"], "modulate", Color(1.0, 0.6, 0.6), 0.08)
        damage_flash.tween_property(card["root"], "modulate", Color.WHITE, 0.3)





func _run_battle() -> void :
    await get_tree().create_timer(0.6).timeout
    for line in _dialogue("intro"):
        if _foes.is_empty():
            break
        _enemy_say(_foes[0], line)
    if _foes.size() > 1:
        await _say("%s does not come alone — %d foes face your party of %d!" % [_enemy_name(), _foes.size(), _allies.size()])

    for foe in _foes:
        _pick_foe_intent(foe)
    _refresh_all_panels()

    while not _battle_over:
        _round_serial += 1
        _round_queue = _build_round_queue()
        _queue_pos = 0
        while _queue_pos < _round_queue.size():
            if _battle_over:
                return
            var entry: Dictionary = _round_queue[_queue_pos]
            var index: int = int(entry.get("index", 0))
            var turn_performed := false
            if str(entry.get("side")) == "ally":
                if index < _allies.size() and not _actor_down(_allies[index], true):
                    turn_performed = true
                    _update_turn_order_view()
                    await _ally_turn(_allies[index])
            else:
                if index < _foes.size() and not _actor_down(_foes[index], false):
                    turn_performed = true
                    _update_turn_order_view()
                    await _foe_turn(_foes[index])
            if _battle_over:
                return
            await _check_phases()
            if _battle_over:
                return
            _queue_pos += 1
            if turn_performed:
                await get_tree().create_timer(TURN_TRANSITION_DELAY).timeout
                if _battle_over:
                    return

        # End-of-round upkeep: the exposed window closes one step.
        if exposed_turns > 0:
            exposed_turns -= 1
            if exposed_turns == 0:
                _set_exposed_glow(false)
                await _say("The opening closes. %s steadies itself." % _enemy_name())
            _refresh_all_panels()


## Speed-ordered queue over every living combatant. Boss action 1 competes at its
## effective speed; extra actions sit just behind progressively slower allies so
## the boss applies steady pressure instead of dumping a three-hit block. Haste /
## slow still move every slot, and ties break randomly per round.
func _build_round_queue() -> Array[Dictionary]:
    var entries: Array[Dictionary] = []
    var ally_speeds: Array[int] = []
    for index in _living_allies():
        var speed: int = _effective_speed(_allies[index])
        ally_speeds.append(speed)
        entries.append({"side": "ally", "index": index,
            "key": _initiative_key(float(speed)), "action_slot": 0})
    ally_speeds.sort()
    ally_speeds.reverse()
    for index in _living_foes():
        var foe: Dictionary = _foes[index]
        var actions: int = maxi(1, int(foe.get("actions_per_round", 1)))
        if str(foe.get("rank", "")) == "boss":
            # Pressure follows the LIVING party, not the opening roster. If an
            # ally falls, the boss sheds one action next round so defeat does not
            # cascade into an unavoidable 3-v-1 lock; a revive restores it.
            actions = _boss_actions_per_round(_living_allies().size())
            foe["actions_per_round"] = actions
        for action_slot in range(actions):
            var initiative: float = _foe_action_initiative(foe, action_slot, actions, ally_speeds)
            entries.append({"side": "foe", "index": index,
                "key": _initiative_key(initiative), "action_slot": action_slot})
    entries.sort_custom(func(a, b): return int(a["key"]) > int(b["key"]))
    return entries


func _initiative_key(initiative: float) -> int:
    # A 0.25 initiative gap is 2500 points, safely larger than this tie jitter.
    return int(round(initiative * 10000.0)) + randi() % 1000


func _foe_action_initiative(foe: Dictionary, action_slot: int, action_count: int, ally_speeds: Array[int]) -> float:
    var base: float = float(_effective_speed(foe))
    if action_slot <= 0 or ally_speeds.is_empty():
        return base
    var anchor_index: int = 0
    if action_count >= 3 and action_slot == action_count - 1:
        anchor_index = ally_speeds.size() - 1
    var behind_own_previous: float = base - 0.25 * action_slot
    var behind_ally: float = float(ally_speeds[anchor_index]) - 0.25
    return minf(behind_own_previous, behind_ally)


func _actor_for_entry(entry: Dictionary) -> Dictionary:
    var index: int = int(entry.get("index", 0))
    if str(entry.get("side")) == "ally":
        return _allies[index] if index < _allies.size() else {}
    return _foes[index] if index < _foes.size() else {}


# ── ally turns ────────────────────────────────────────────────────────────────


func _ally_turn(ally: Dictionary) -> void :
    _set_active_ally(ally)
    var upkeep: Dictionary = _status_upkeep_for_round(ally, true)
    for note in upkeep.get("notes", []) as Array:
        await _say(str(note))
    _refresh_all_panels()
    if _living_allies().is_empty():
        await _defeat()
        return
    if _actor_down(ally, true) or bool(upkeep.get("skip", false)):
        _set_active_ally(null)
        return
    if str(ally.get("kind")) == "player":
        _apply_party_regen()
    ally["guarding"] = false
    await _ally_action_menu(ally)
    _set_active_ally(null)


## The action menu proper — separated from _ally_turn so a cancelled submenu can
## re-open it WITHOUT re-running the start-of-turn status upkeep.
func _ally_action_menu(ally: Dictionary) -> void :
    if _battle_over:
        return
    var commands := _ally_action_commands(ally)
    var ids: Array[String] = []
    var labels: Array[String] = []
    var descs: Array[String] = []
    for command in commands:
        ids.append(str(command.get("id", "")))
        labels.append(str(command.get("label", "")))
        descs.append(str(command.get("description", "")))

    var choice: String = await _menu(ids, labels, descs)
    match choice:
        "attack":
            var target: int = await _pick_foe_target()
            if target < 0:
                await _ally_action_menu(ally)
                return
            var foe: Dictionary = _foes[target]
            _play_ally_attack_fx("strike", _foe_center(foe))
            await _ally_attack(ally, foe, 1.0, "%s strikes!" % str(ally.get("name")), COLOR_ACCENT)
        "finisher":
            finisher_used = true
            var primary: Dictionary = _foes[0]
            _flash_portrait(primary, COLOR_EXPOSED, 1.0)
            _shake(7.0, 0.4)
            _spawn_slash(
                _foe_center(primary), COLOR_EXPOSED, 1.9 * ALLY_TO_FOE_FX_SCALE)
            _spawn_slash(
                _foe_center(primary) + Vector2(8, 10),
                Color(1, 1, 1, 0.9),
                1.5 * ALLY_TO_FOE_FX_SCALE,
                true,
            )
            await _ally_attack(ally, primary, 3.0, "You answer its secret with one decisive blow!", COLOR_EXPOSED)
        "skill":
            await _skill_menu(ally)
        "probe":
            await _probe_menu(ally)
        "item":
            await _item_menu(ally)
        "guard":
            ally["guarding"] = true
            ally["sp"] = mini(int(ally.get("sp", 0)) + 1, int(ally.get("sp_max", 3)))
            _refresh_all_panels()
            _spawn_particles(_actor_fx_center(ally, true), Color(0.6, 0.75, 1.0), 10)
            await _say("%s braces and watches carefully. (+1 SP)" % str(ally.get("name")))
        "flee":
            await _try_flee(ally)
        "spare":
            await _spare_enemy(ally)


## Pure command specification shared by the live menu and regression tests.
## Probe/finisher remain protagonist story abilities; inventory and encounter-wide
## decisions belong to whichever living party member currently owns the turn.
func _ally_action_commands(ally: Dictionary) -> Array[Dictionary]:
    var is_player: = str(ally.get("kind")) == "player"
    var commands: Array[Dictionary] = [
        {
            "id": "attack",
            "label": "Attack",
            "description": "A precise strike with your blade." if is_player else "%s attacks a foe." % str(ally.get("name")),
        },
        {"id": "skill", "label": "Skill", "description": "Channel a special technique."},
    ]
    if is_player:
        commands.append({
            "id": "probe",
            "label": "Probe",
            "description": "Study the enemy for a weakness.",
        })
    commands.append({
        "id": "item",
        "label": "Item",
        "description": "Use something from your pack.",
    })
    commands.append({
        "id": "guard",
        "label": "Guard",
        "description": "Brace yourself and recover 1 SP.",
    })
    commands.append({
        "id": "flee",
        "label": "Flee",
        "description": "Attempt to escape the battle.",
    })
    if is_player:
        if exposed_turns > 0 and not finisher_used:
            commands.insert(0, {
                "id": "finisher",
                "label": "Resolve Strike!",
                "description": "Exploit the opening — a decisive blow.",
            })
    if _can_spare_primary_foe():
        commands.append({
            "id": "spare",
            "label": "Spare",
            "description": "Show mercy and end the fight.",
        })
    return commands


func _can_spare_primary_foe() -> bool:
    if _foes.is_empty():
        return false
    var primary: Dictionary = _foes[0]
    return bool(enemy.get("can_spare", false)) \
        and int(primary.get("hp", 1)) <= int(int(primary.get("max_hp", 1)) * 0.3) \
        and not _actor_down(primary, false)


func _skill_menu(ally: Dictionary) -> void :
    if _status_flag(ally, "no_skills"):
        await _say("%s's techniques are sealed by silence!" % str(ally.get("name")))
        await _ally_action_menu(ally)
        return
    var skills: Array = ally.get("skills", []) as Array
    if skills.is_empty():
        await _say("%s knows no techniques yet." % str(ally.get("name")))
        await _ally_action_menu(ally)
        return
    var ids: Array[String] = []
    var labels: Array[String] = []
    var descs: Array[String] = []
    var icon_keys: Array[String] = []
    for index in range(skills.size()):
        var skill: Dictionary = skills[index]
        ids.append(str(index))
        labels.append("%s (%d SP)" % [skill.get("name"), int(skill.get("sp_cost", 1))])
        descs.append(str(skill.get("desc", "")))
        icon_keys.append(str(skill.get("id", "skill")))
    ids.append("back")
    labels.append("Back")
    descs.append("")
    icon_keys.append("back")

    var choice: String = await _menu(ids, labels, descs, icon_keys)
    if choice == "back":
        await _ally_action_menu(ally)
        return
    var skill: Dictionary = skills[int(choice)]
    if int(ally.get("sp", 0)) < int(skill.get("sp_cost", 1)):
        await _say("Not enough SP. Guard to recover.")
        await _skill_menu(ally)
        return
    var used: bool = await _use_skill(ally, skill)
    if not used:
        await _skill_menu(ally)


## Executes a skill. Returns false when the player cancelled out of target
## selection (SP is only deducted after a target is confirmed).
func _use_skill(ally: Dictionary, skill: Dictionary) -> bool:
    var effect: = str(skill.get("effect", "attack"))
    var skill_id: = str(skill.get("id", ""))
    var skill_name: = str(skill.get("name", "?"))
    var caster_name: = str(ally.get("name", "?"))
    var level: int = int(ally.get("level", 1))
    var power: = float(skill.get("power", 1.0))

    match effect:
        "focus":
            _spend_sp(ally, skill)
            ally["focus"] = true
            _play_skill_fx(skill_id, _actor_fx_center(ally, true))
            _spawn_particles(_actor_fx_center(ally, true), Color(0.45, 0.65, 1.0), 18)
            await _say("%s centers themselves. The next attack will hit twice as hard." % caster_name)
        "heal":
            var target: int = await _pick_ally_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var patient: Dictionary = _allies[target]
            var heal_amount: int = int(round(power)) + level * 2
            _play_skill_fx(skill_id, _actor_fx_center(patient, true))
            _heal_raw(patient, true, heal_amount)
            _spawn_particles(_actor_fx_center(patient, true), COLOR_HEAL, 18)
            await _say("%s uses %s — %s recovers %d HP." % [caster_name, skill_name, patient.get("name"), heal_amount])
        "heal_all":
            _spend_sp(ally, skill)
            var heal_all: int = int(round(power)) + int(round(level * 1.8))
            for index in _living_allies():
                var member: Dictionary = _allies[index]
                _play_skill_fx(skill_id, _actor_fx_center(member, true))
                _heal_raw(member, true, heal_all)
            await _say("%s uses %s — the whole party recovers %d HP." % [caster_name, skill_name, heal_all])
        "multi":
            var target: int = await _pick_foe_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var foe: Dictionary = _foes[target]
            var hits: int = clampi(int(round(power)), 2, 4)
            for hit_index in range(hits):
                if _battle_over or _actor_down(foe, false):
                    break
                _play_ally_attack_fx(
                    skill_id,
                    _foe_center(foe) + Vector2(
                        randf_range(-14, 14), randf_range(-10, 10)),
                )
                await _ally_attack(ally, foe, 0.7, "%s — hit %d!" % [skill_name, hit_index + 1], Color(0.7, 0.9, 1.0))
        "pierce":
            var target: int = await _pick_foe_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var foe: Dictionary = _foes[target]
            _play_ally_attack_fx(skill_id, _foe_center(foe))
            await _ally_attack(ally, foe, power, "%s unleashes %s — it pierces the guard!" % [caster_name, skill_name], Color(1.0, 0.55, 0.85), true)
        "drain":
            var target: int = await _pick_foe_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var foe: Dictionary = _foes[target]
            _play_ally_attack_fx(skill_id, _foe_center(foe))
            var dealt: int = await _ally_attack(ally, foe, power, "%s uses %s!" % [caster_name, skill_name], Color(0.7, 0.4, 0.9))
            if dealt > 0 and not _actor_down(ally, true):
                var siphon: int = maxi(1, int(round(dealt * 0.6)))
                _heal_raw(ally, true, siphon)
                await _say("%s drains %d HP from the wound." % [caster_name, siphon])
        "shield":
            var target: int = _allies.find(ally) if str(skill.get("target")) == "self" else await _pick_ally_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var ward: Dictionary = _allies[target]
            var pool: int = 12 + 3 * level
            _apply_status(ward, "shield", float(pool))
            _play_skill_fx(skill_id, _actor_fx_center(ward, true))
            _spawn_particles(_actor_fx_center(ward, true), Color(0.75, 0.7, 0.5), 14)
            _refresh_all_panels()
            await _say("%s raises %s — %s gains a %d-point shield." % [caster_name, skill_name, ward.get("name"), pool])
        "cleanse":
            var target: int = await _pick_ally_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var patient: Dictionary = _allies[target]
            var removed: int = _clear_debuffs(patient)
            var soothe: int = 8 + level
            _play_skill_fx(skill_id, _actor_fx_center(patient, true))
            _heal_raw(patient, true, soothe)
            await _say("%s purifies %s — %d ailment(s) washed away." % [caster_name, patient.get("name"), removed])
        "revive":
            var target: int = await _pick_ally_target(true)
            if target < 0:
                return false
            var fallen: Dictionary = _allies[target]
            if not _actor_down(fallen, true):
                await _say("%s is still standing." % str(fallen.get("name")))
                return false
            _spend_sp(ally, skill)
            fallen["downed"] = false
            _set_ally_hp(fallen, maxi(1, int(round(int(fallen.get("max_hp", 1)) * 0.4))))
            _play_skill_fx(skill_id, _actor_fx_center(fallen, true))
            _spawn_particles(_actor_fx_center(fallen, true), COLOR_ACCENT, 24)
            _refresh_all_panels()
            await _say("%s calls %s back to their feet!" % [caster_name, fallen.get("name")])
        "status":
            var status_id: = str(skill.get("status", ""))
            match str(skill.get("target", "enemy")):
                "enemy":
                    var target: int = await _pick_foe_target()
                    if target < 0:
                        return false
                    _spend_sp(ally, skill)
                    var foe: Dictionary = _foes[target]
                    _play_ally_attack_fx(skill_id, _foe_center(foe))
                    if randf() < float(skill.get("status_chance", 1.0)) and _apply_status(foe, status_id):
                        _refresh_all_panels()
                        await _say("%s uses %s — %s is afflicted by %s!" % [caster_name, skill_name, foe.get("name"), _status_label(status_id)])
                    else:
                        await _say("%s uses %s — but %s resists!" % [caster_name, skill_name, foe.get("name")])
                "ally":
                    var target: int = await _pick_ally_target()
                    if target < 0:
                        return false
                    _spend_sp(ally, skill)
                    var member: Dictionary = _allies[target]
                    _apply_buff_status(member, status_id, level)
                    _play_skill_fx(skill_id, _actor_fx_center(member, true))
                    _refresh_all_panels()
                    await _say("%s uses %s — %s gains %s!" % [caster_name, skill_name, member.get("name"), _status_label(status_id)])
                "ally_all":
                    _spend_sp(ally, skill)
                    for index in _living_allies():
                        _apply_buff_status(_allies[index], status_id, level)
                        _play_skill_fx(skill_id, _actor_fx_center(_allies[index], true))
                    _refresh_all_panels()
                    await _say("%s uses %s — the party gains %s!" % [caster_name, skill_name, _status_label(status_id)])
                _:
                    _spend_sp(ally, skill)
                    _apply_buff_status(ally, status_id, level)
                    _play_skill_fx(skill_id, _actor_fx_center(ally, true))
                    _refresh_all_panels()
                    await _say("%s uses %s!" % [caster_name, skill_name])
        _:
            var target: int = await _pick_foe_target()
            if target < 0:
                return false
            _spend_sp(ally, skill)
            var foe: Dictionary = _foes[target]
            _play_ally_attack_fx(skill_id, _foe_center(foe))
            var dealt: int = await _ally_attack(ally, foe, maxf(power, 0.1), "%s unleashes %s!" % [caster_name, skill_name], Color(1.0, 0.62, 0.2))
            var rider: = str(skill.get("status", ""))
            if dealt > 0 and not rider.is_empty() and not _actor_down(foe, false):
                if randf() < float(skill.get("status_chance", 0.0)):
                    if not _apply_status(foe, rider):
                        await _say("%s resists %s!" % [foe.get("name"), _status_label(rider)])
                        return true
                    _refresh_all_panels()
                    await _say("%s is afflicted by %s!" % [foe.get("name"), _status_label(rider)])
    return true


func _spend_sp(ally: Dictionary, skill: Dictionary) -> void :
    ally["sp"] = maxi(int(ally.get("sp", 0)) - int(skill.get("sp_cost", 1)), 0)
    _refresh_all_panels()


func _status_label(status_id: String) -> String:
    return str(GameManager.status_def(status_id).get("name", status_id))


## Regen/haste magnitudes scale with the caster; other statuses use defaults.
func _apply_buff_status(actor: Dictionary, status_id: String, caster_level: int) -> void :
    var magnitude: = 0.0
    if status_id == "regen":
        magnitude = float(6 + caster_level)
    _apply_status(actor, status_id, magnitude)


func _item_menu(ally: Dictionary) -> void :
    var usable: Array[Dictionary] = InventoryManager.usable_in_battle()
    if usable.is_empty():
        await _say("You carry nothing usable in battle.")
        await _ally_action_menu(ally)
        return
    var ids: Array[String] = []
    var labels: Array[String] = []
    var descs: Array[String] = []
    var icon_sources: Array = []
    for index in range(usable.size()):
        var item: Dictionary = usable[index]
        ids.append(str(index))
        labels.append("%s ×%d" % [item.get("name", "?"), InventoryManager.count_of(str(item.get("id")))])
        # Battle copy comes from real mechanics, never from flavor description.
        descs.append(_item_battle_effect_text(item))
        var item_icon: Texture2D = InventoryManager.icon_for(item)
        icon_sources.append(item_icon if item_icon != null else "item")
    ids.append("back")
    labels.append("Back")
    descs.append("")
    icon_sources.append("back")

    var choice: String = await _menu(ids, labels, descs, icon_sources)
    if choice == "back":
        await _ally_action_menu(ally)
        return
    var item: Dictionary = usable[int(choice)]
    var item_id: String = str(item.get("id"))
    var kind: = str(item.get("kind"))

    var target: int = _allies.find(ally)
    if kind == "heal" or kind == "energy":
        target = await _pick_ally_target()
        if target < 0:
            await _item_menu(ally)
            return
    if not InventoryManager.remove_item(item_id):
        await _ally_action_menu(ally)
        return
    var patient: Dictionary = _allies[maxi(target, 0)]
    match kind:
        "heal":
            var amount: int = int(item.get("power", 40))
            _heal_raw(patient, true, amount)
            _spawn_particles(_actor_fx_center(patient, true), COLOR_HEAL, 16)
            await _say("%s uses %s. %s restores %d HP." % [ally.get("name"), item.get("name"), patient.get("name"), amount])
        "energy":
            var sp_gain: int = int(item.get("power", 2))
            patient["sp"] = mini(int(patient.get("sp", 0)) + sp_gain, int(patient.get("sp_max", 3)))
            _refresh_all_panels()
            _spawn_particles(_actor_fx_center(patient, true), Color(0.55, 0.6, 1.0), 14)
            await _say("%s uses %s. %s restores %d SP." % [ally.get("name"), item.get("name"), patient.get("name"), sp_gain])
        "buff":
            ally["focus"] = true
            _spawn_particles(_actor_fx_center(ally, true), Color(1.0, 0.6, 0.3), 18)
            await _say("%s uses %s. The next attack is empowered!" % [ally.get("name"), item.get("name")])


func _item_battle_effect_text(item: Dictionary) -> String:
    var power := int(item.get("power", 0))
    match str(item.get("kind", "")):
        "heal":
            return "Restore %d HP to one ally." % maxi(power, 0)
        "energy":
            return "Restore %d SP to one ally." % maxi(power, 0)
        "buff":
            return "Empower the user's next attack to deal double damage."
        _:
            return "Usable during battle."


func _probe_menu(ally: Dictionary) -> void :
    var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
    if weakness_found:
        await _say("You already see through it. Its weakness is laid bare.")
        await _ally_action_menu(ally)
        return
    if probe_options.is_empty():
        await _say("It refuses to answer anything more.")
        await _ally_action_menu(ally)
        return

    await _say(str(weakness.get("hint", "You look for a crack in its resolve.")))

    var ids: Array[String] = []
    var labels: Array[String] = []
    var icon_keys: Array[String] = []
    for index in range(probe_options.size()):
        ids.append(str(index))
        labels.append(str((probe_options[index] as Dictionary).get("text", "...")))
        icon_keys.append("probe")
    ids.append("back")
    labels.append("Back")
    icon_keys.append("back")

    var choice: String = await _menu(ids, labels, [], icon_keys)
    if choice == "back":
        await _ally_action_menu(ally)
        return

    var option: Dictionary = probe_options[int(choice)] as Dictionary
    probe_options.remove_at(int(choice))
    await _say(str(option.get("reveal", "...")))

    var primary: Dictionary = _foes[0]
    if bool(option.get("correct", false)):
        weakness_found = true
        exposed_turns = int(weakness.get("vulnerable_turns", 3)) + 1
        _set_exposed_glow(true)
        _flash_portrait(primary, COLOR_EXPOSED, 0.8)
        _shake(4.0, 0.3)
        _spawn_particles(_foe_center(primary), COLOR_EXPOSED, 22)
        _refresh_all_panels()
        await _say("%s is EXPOSED! Your words found the wound. (damage x%.1f)" % [
            _enemy_name(), float(weakness.get("damage_multiplier", 2.0)),
        ])
    else:
        await _say("Wrong nerve. %s lashes out while you hesitate!" % _enemy_name())
        await _foe_strike(primary, _allies[0], 0.8, "")


## Shared ally→foe damage. Returns the damage actually dealt (0 on a miss).
func _ally_attack(ally: Dictionary, foe: Dictionary, power: float, flavor: String, fx_color: Color = COLOR_ACCENT, ignore_defense: bool = false) -> int:
    # Blind can make the whole swing whiff.
    var hit_chance: = _status_mult(ally, "hit_chance")
    if hit_chance < 1.0 and randf() > hit_chance:
        _spawn_damage_number(_foe_center(foe) + Vector2(0, -34), "MISS", COLOR_TEXT_DIM)
        await _say("%s's attack goes wide!" % str(ally.get("name")))
        return 0

    var base: float = float(ally.get("attack", 12)) * power
    base *= _status_mult(ally, "attack_mult")
    if bool(ally.get("focus", false)):
        base *= 2.0
        ally["focus"] = false
    var is_primary: = foe == _foes[0]
    var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
    var exposed_now: bool = exposed_turns > 0 and is_primary
    if exposed_now:
        base *= float(weakness.get("damage_multiplier", 2.0))
    var variance: float = randf_range(0.85, 1.15)
    var crit: bool = randf() < 0.1 + _status_bonus(ally, "crit_bonus")

    var defense: float = float(foe.get("defense", 2)) * _status_mult(foe, "defense_mult")
    if is_primary:
        defense *= phase_defense_factor
    var defense_cut: float = 0.0 if ignore_defense else defense * 0.5
    var damage: int = maxi(int(round(base * variance * (1.5 if crit else 1.0) - defense_cut)), 1)
    foe["hp"] = maxi(int(foe.get("hp", 1)) - damage, 0)
    _on_actor_damaged(foe)

    var hit_slash_scale: float = (1.5 if power > 1.2 else 1.25) \
        * ALLY_TO_FOE_FX_SCALE
    _spawn_slash(_foe_center(foe), fx_color, hit_slash_scale)
    _enemy_hit_react(foe, power >= 1.5 or crit)
    _spawn_particles(_foe_center(foe), fx_color if not exposed_now else COLOR_EXPOSED)
    _spawn_damage_number(
        _foe_center(foe) + Vector2(0, -34),
        str(damage) + ("!" if crit else ""),
        COLOR_CRIT if crit else (COLOR_EXPOSED if exposed_now else Color.WHITE),
        crit or power >= 1.8,
    )
    _animate_foe_hp(foe)
    _refresh_all_panels()

    var text: String = "%s %d damage%s" % [flavor + " ", damage, " — CRITICAL!" if crit else "."]
    await _say(text)

    if _actor_down(foe, false):
        await _handle_foe_death(foe)
        if _living_foes().is_empty():
            await _victory()
    elif is_primary and int(foe.get("hp", 0)) <= int(int(foe.get("max_hp", 1)) * 0.3):
        var low_lines: Array = _dialogue("low_hp")
        if not low_lines.is_empty() and not triggered_phases.has("_low_hp"):
            triggered_phases["_low_hp"] = true
            _enemy_say(foe, str(low_lines[0]))
            if bool(enemy.get("can_spare", false)):
                await _say("It is wavering. You could choose to spare it.")
    return damage


func _handle_foe_death(foe: Dictionary) -> void :
    # The primary foe's final bark starts in real time as its dissolve begins; it
    # never delays death resolution or the player's transition to rewards.
    if _living_foes().is_empty() and not _foes.is_empty() and _foes[0] == foe:
        for line in _dialogue("player_victory"):
            _enemy_say(foe, str(line))
    var ui: Dictionary = _foe_ui(foe)
    if not ui.is_empty():
        var holder: Control = ui["holder"]
        var dissolve: = create_tween()
        dissolve.tween_property(holder, "modulate", Color(1.4, 1.4, 1.4, 0.0), 0.7).set_trans(Tween.TRANS_CUBIC)
        dissolve.parallel().tween_property(holder, "position:y", holder.position.y + 20.0, 0.7)
        _spawn_particles(_foe_center(foe), Color(1, 1, 1, 0.9), 22)
    if not _living_foes().is_empty():
        await _say("%s is defeated!" % str(foe.get("name")))
        # The readout should follow a living foe.
        var living: Array[int] = _living_foes()
        if not living.is_empty() and _actor_down(_foes[_target_foe_index], false):
            _target_foe_index = living[0]
        _refresh_all_panels()


func _check_phases() -> void :
    if _foes.is_empty():
        return
    var primary: Dictionary = _foes[0]
    if _actor_down(primary, false):
        return
    var ratio: float = float(primary.get("hp", 0)) / float(primary.get("max_hp", 1))
    for phase in enemy.get("phases", []) as Array:
        if not (phase is Dictionary):
            continue
        var key: = str((phase as Dictionary).get("hp_ratio", 0.5))
        if triggered_phases.has(key):
            continue
        if ratio <= float((phase as Dictionary).get("hp_ratio", 0.5)):
            triggered_phases[key] = true
            _flash_portrait(primary, Color(1.0, 0.4, 0.3), 0.7)
            _shake(4.0, 0.35)
            var beat: String = str((phase as Dictionary).get("story_beat", ""))
            if not beat.is_empty():
                _enemy_say(primary, beat)
            match str((phase as Dictionary).get("behavior", "aggressive")):
                "aggressive":
                    phase_damage_bonus = 1.15
                    await _say("Its attacks grow fiercer!")
                "desperate":
                    phase_damage_bonus = 1.3
                    phase_defense_factor = 0.6
                    await _say("It fights desperately — harder, but careless!")


# ── foe turns ─────────────────────────────────────────────────────────────────


func _foe_turn(foe: Dictionary) -> void :
    if _battle_over:
        return
    var upkeep: Dictionary = _status_upkeep_for_round(foe, false)
    for note in upkeep.get("notes", []) as Array:
        await _say(str(note))
    _refresh_all_panels()
    if _actor_down(foe, false):
        await _handle_foe_death(foe)
        if _living_foes().is_empty():
            await _victory()
        return
    if bool(upkeep.get("skip", false)):
        return
    var skill: Dictionary = foe.get("intent", {}) as Dictionary
    _pick_foe_intent(foe)
    await _foe_use_skill(foe, skill)


func _foe_use_skill(foe: Dictionary, skill: Dictionary) -> void :
    var kind: String = str(skill.get("kind", "strike"))
    var skill_name: String = str(skill.get("name", "Attack"))
    var power: float = float(skill.get("power", 1.0))
    var victim: Dictionary = _pick_foe_victim()
    if victim.is_empty():
        return
    if kind == "heavy":
        var ui: Dictionary = _foe_ui(foe)
        if not ui.is_empty():
            var flash: TextureRect = ui["flash"]
            flash.modulate = Color(1.0, 0.3, 0.2, 0.0)
            var windup: = create_tween()
            windup.tween_property(flash, "modulate:a", 0.5, 0.35)
            windup.tween_property(flash, "modulate:a", 0.0, 0.15)
            await windup.finished
    match kind:
        "hex":
            _apply_status(victim, "weaken")
            _spawn_particles(_actor_fx_center(victim, true), Color(0.7, 0.35, 0.9), 16, false)
            _refresh_all_panels()
            await _foe_strike(foe, victim, power * 0.5, "%s uses %s! A weakening curse clings to %s." % [foe.get("name"), skill_name, victim.get("name")])
        "guard_break":
            if bool(victim.get("guarding", false)):
                await _foe_strike(foe, victim, power * 1.6, "%s uses %s — it smashes straight through the guard!" % [foe.get("name"), skill_name])
            else:
                await _foe_strike(foe, victim, power * 0.9, "%s uses %s." % [foe.get("name"), skill_name])
        _:
            await _foe_strike(foe, victim, power, "%s uses %s!" % [foe.get("name"), skill_name])


## Which ally does a foe swing at? A taunting tank forces the choice; otherwise
## the protagonist draws a little more heat than each companion.
func _pick_foe_victim() -> Dictionary:
    var living: Array[int] = _living_allies()
    if living.is_empty():
        return {}
    for index in living:
        if _status_flag(_allies[index], "taunt"):
            return _allies[index]
    var weights: Array[float] = []
    var total: = 0.0
    for index in living:
        var weight: = 6.0 if str(_allies[index].get("kind")) == "player" else 4.0
        weights.append(weight)
        total += weight
    var roll: = randf() * total
    for position in range(living.size()):
        roll -= weights[position]
        if roll <= 0.0:
            return _allies[living[position]]
    return _allies[living.back()]


func _foe_strike(foe: Dictionary, victim: Dictionary, power: float, flavor: String) -> void :
    var hit_chance: = _status_mult(foe, "hit_chance")
    if hit_chance < 1.0 and randf() > hit_chance:
        _enemy_lunge(foe)
        await get_tree().create_timer(0.14).timeout
        _spawn_damage_number(_actor_fx_center(victim, true) + Vector2(10, -60), "MISS", COLOR_TEXT_DIM)
        await _say("%s's attack misses %s!" % [foe.get("name"), victim.get("name")])
        return

    var is_primary: = foe == _foes[0]
    var base: float = float(foe.get("attack", 8)) * power
    base *= _status_mult(foe, "attack_mult")
    if is_primary:
        base *= phase_damage_bonus
    var variance: float = randf_range(0.85, 1.15)
    var defense: float = float(victim.get("defense", 5)) * _status_mult(victim, "defense_mult")
    var damage: float = base * variance - defense * 0.5
    if bool(victim.get("guarding", false)):
        damage *= 0.5
    var final_damage: int = maxi(int(round(damage)), 1)
    final_damage = _absorb_with_shields(victim, final_damage)

    _enemy_lunge(foe)
    await get_tree().create_timer(0.14).timeout
    _shake(5.0 if power >= 1.5 else 3.0, 0.3)
    if final_damage > 0:
        _spawn_damage_number(_actor_fx_center(victim, true) + Vector2(10, -30), str(final_damage), COLOR_PLAYER_DMG, power >= 1.5)
        _set_ally_hp(victim, _ally_hp(victim) - final_damage)
        _on_actor_damaged(victim)
        if _ally_hp(victim) <= 0:
            victim["downed"] = true
    else:
        _spawn_damage_number(_actor_fx_center(victim, true) + Vector2(10, -30), "BLOCKED", Color(0.75, 0.8, 0.95))
    _animate_ally_hp(victim)
    _refresh_all_panels()

    var guard_note: String = " %s guarded (halved)." % str(victim.get("name")) if bool(victim.get("guarding", false)) else ""
    if final_damage <= 0:
        await _say("%s The shield absorbs the blow!" % (flavor if not flavor.is_empty() else "%s attacks." % str(foe.get("name"))))
    elif flavor.is_empty():
        await _say("It hits %s for %d.%s" % [victim.get("name"), final_damage, guard_note])
    else:
        await _say("%s %d damage to %s.%s" % [flavor + " ", final_damage, victim.get("name"), guard_note])

    if bool(victim.get("downed", false)):
        await _say("%s falls!" % str(victim.get("name")))
    if _living_allies().is_empty():
        await _defeat()


func _pick_foe_intent(foe: Dictionary) -> void :
    var skills: Array = (foe.get("data", {}) as Dictionary).get("skills", []) as Array
    var usable: Array[Dictionary] = []
    var silenced: = _status_flag(foe, "no_skills")
    for skill in skills:
        if skill is Dictionary:
            if silenced and str((skill as Dictionary).get("kind", "")) != "strike":
                continue
            if str((skill as Dictionary).get("kind", "")) == "heavy" and int(foe.get("turns_since_heavy", 99)) < 2:
                continue
            usable.append(skill as Dictionary)
    if usable.is_empty():
        usable.append({"name": "Attack", "kind": "strike", "power": 1.0, "telegraph": ""})
    foe["intent"] = usable[randi() % usable.size()]
    if str((foe["intent"] as Dictionary).get("kind", "")) == "heavy":
        foe["turns_since_heavy"] = 0
    else:
        foe["turns_since_heavy"] = int(foe.get("turns_since_heavy", 99)) + 1
    _refresh_target_readout()


func _flee_chance(ally: Dictionary) -> float:
    var fastest_foe_speed := 0
    for foe_index in _living_foes():
        fastest_foe_speed = maxi(fastest_foe_speed, _effective_speed(_foes[foe_index]))
    return clampf(
        0.5 + 0.05 * float(_effective_speed(ally) - fastest_foe_speed) \
            + 0.15 * flee_failed_count,
        0.25,
        0.95,
    )


func _try_flee(ally: Dictionary) -> void :
    var chance := _flee_chance(ally)
    if randf() < chance:
        await _say("Your party slips away from the fight.")
        _finish("fled")
    else:
        flee_failed_count += 1
        _shake(2.0, 0.2)
        if str(ally.get("kind", "")) == "player":
            await _say("You can't get away!")
        else:
            await _say("%s can't find a way out!" % str(ally.get("name", "Companion")))


func _spare_enemy(ally: Dictionary) -> void :
    for line in _dialogue("spare"):
        if not _foes.is_empty():
            _enemy_say(_foes[0], str(line))
    for foe in _foes:
        var ui: Dictionary = _foe_ui(foe)
        if not ui.is_empty():
            var fade: = create_tween()
            fade.tween_property(ui["holder"], "modulate", Color(1, 1, 1, 0.35), 1.0)
    var xp: int = _scaled_battle_xp(int(int(enemy.get("xp_reward", 20)) * 0.6), int(_foes[0].get("level", 1)))
    var message := "You lower your weapon. +%d XP." % xp
    if str(ally.get("kind", "")) != "player":
        message = "%s lowers their weapon. +%d XP." % [str(ally.get("name", "Companion")), xp]
    await _grant_xp(xp, message)
    _finish("spared")


func _victory() -> void :
    _set_exposed_glow(false)
    _shake(3.0, 0.25)

    # player_victory was already queued as a real-time bark when the foe began to
    # dissolve; the log keeps only the neutral mechanical "finish" line.
    for line in _dialogue("finish"):
        await _say(line)

    _show_victory_banner()
    var xp: = 0
    for foe in _foes:
        xp += _scaled_battle_xp(int(foe.get("xp_reward", 20)), int(foe.get("level", 1)))
    if weakness_found:
        var bonus: int = int(xp * 0.25)
        xp += bonus
        await _grant_xp(xp, "Victory! +%d XP (+%d for understanding its story)." % [xp, bonus])
    else:
        await _grant_xp(xp, "Victory! +%d XP." % xp)

    # Fallen party members pick themselves back up after the fight.
    for ally in _allies:
        if _actor_down(ally, true):
            ally["downed"] = false
            var recover: int = maxi(1, int(round(int(ally.get("max_hp", 1)) * (0.25 if str(ally.get("kind")) == "player" else 0.3))))
            _set_ally_hp(ally, recover)
    _refresh_all_panels()

    var item_rewards := _collect_victory_item_rewards()
    if not item_rewards.is_empty():
        _spawn_particles(SCREEN_CENTER, COLOR_ACCENT, 12)
        if item_rewards.size() == 1:
            await _say("It left something behind: %s." % str(item_rewards[0].get("name", "Item")))
        else:
            await _say("The defeated foes left battle spoils behind.")
        # Battle-log and XP updates are intentionally non-blocking. Hold only for
        # the banner's 0.45 s pop plus a short visual breath, then reveal loot.
        await get_tree().create_timer(VICTORY_REWARD_REVEAL_DELAY).timeout
        await _show_battle_item_rewards(item_rewards)
    _finish("victory")


func _collect_victory_item_rewards() -> Array[Dictionary]:
    var rewards: Array[Dictionary] = []
    var dropped := InventoryManager.roll_battle_drop(
        str(enemy.get("rank", "minion")), true,
    )
    if not dropped.is_empty():
        var definition := InventoryManager.item_def(dropped)
        _merge_item_reward(rewards, {
            "item_id": dropped,
            "name": str(definition.get("name", dropped)),
            "count": 1,
        })

    var linked_rewards := InventoryManager.grant_linked_item_rewards_silent(
        "enemy_drop",
        enemy_id,
        str(GameManager.get_scene_context().get("zone_id", "")),
    )
    for reward in linked_rewards:
        _merge_item_reward(rewards, reward)
    return rewards


func _merge_item_reward(rewards: Array[Dictionary], reward: Dictionary) -> void:
    var item_id := str(reward.get("item_id", ""))
    if item_id.is_empty():
        return
    for existing in rewards:
        if str(existing.get("item_id", "")) == item_id:
            existing["count"] = int(existing.get("count", 1)) + maxi(1, int(reward.get("count", 1)))
            return
    rewards.append({
        "item_id": item_id,
        "name": str(reward.get("name", item_id)),
        "count": maxi(1, int(reward.get("count", 1))),
    })


func _show_battle_item_rewards(items: Array[Dictionary]) -> void:
    if items.is_empty():
        return
    # Match AnnouncementCenter's established four-card capacity. Large authored
    # hauls become consecutive pages instead of squeezing or spilling the panel.
    for start in range(0, items.size(), MAX_BATTLE_REWARDS_PER_SCREEN):
        var page: Array[Dictionary] = []
        var end := mini(start + MAX_BATTLE_REWARDS_PER_SCREEN, items.size())
        for index in range(start, end):
            page.append(items[index])
        var item_view := _open_battle_item_reward_view(page)
        await item_view.tree_exited


func _open_battle_item_reward_view(items: Array[Dictionary]) -> CanvasLayer:
    # Reuse the exact full item-reveal ceremony from conversations and world
    # objects, but place it one layer above BattleScene so the battle backdrop is
    # retained beneath its dimmer while the terminal battle state stays paused.
    var item_view: CanvasLayer = ObjectInteractionViewScript.new()
    item_view.name = "BattleItemRewards"
    get_tree().root.add_child(item_view)
    item_view.layer = layer + 10
    item_view.open_item_announcement(items)
    return item_view


func _show_victory_banner() -> Control :
    var banner_root: = Control.new()
    banner_root.name = "VictoryBanner"
    banner_root.position = VICTORY_BANNER_CENTER
    banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fx_layer.add_child(banner_root)

    if _banner_texture != null:
        var ornament: = TextureRect.new()
        ornament.name = "Ornament"
        ornament.texture = _banner_texture
        ornament.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        var w: float = VICTORY_ORNAMENT_WIDTH
        var h: float = w * float(_banner_texture.get_height()) / float(_banner_texture.get_width())
        ornament.size = Vector2(w, h)
        ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ornament.position = Vector2(-w / 2.0, VICTORY_ORNAMENT_TOP)
        ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
        banner_root.add_child(ornament)

    var text: = _make_display_label("VICTORY", 34, COLOR_ACCENT)
    text.name = "Title"
    text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    text.position = VICTORY_TITLE_RECT.position
    text.size = VICTORY_TITLE_RECT.size
    text.mouse_filter = Control.MOUSE_FILTER_IGNORE
    banner_root.add_child(text)

    banner_root.scale = Vector2(0.2, 0.2)
    banner_root.pivot_offset = Vector2.ZERO
    banner_root.modulate.a = 0.0
    var pop: = create_tween()
    pop.tween_property(banner_root, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    pop.parallel().tween_property(banner_root, "modulate:a", 1.0, 0.3)
    for index in range(5):
        _spawn_particles(Vector2(randf_range(300, 660), randf_range(110, 230)), COLOR_ACCENT, 12)
    return banner_root


## Passive healer-regen from the party bonus, applied on the protagonist's turn
## to every living, wounded ally.
func _apply_party_regen() -> void :
    var regen: int = int(player_stats.get("party_regen", 0))
    if regen <= 0:
        return
    for index in _living_allies():
        var ally: Dictionary = _allies[index]
        if _ally_hp(ally) >= int(ally.get("max_hp", 1)):
            continue
        _heal_raw(ally, true, regen)


func _on_companion_leveled(npc_id: String, level: int) -> void :
    _companion_levelups.append({"npc_id": npc_id, "level": level})


## Level-gap governor: an enemy far below the player's level teaches little
## (mirrors the talk-XP scaling in GameManager.award_talk_xp) — grinding
## low-level minions can't push the player far past the zone's balance anchor.
## Applied per foe at the reward call sites so "+N XP" shows the real number.
func _scaled_battle_xp(raw: int, reference_level: int) -> int:
    if reference_level <= 0:
        reference_level = ChapterFlow.expected_level_here()
    return maxi(1, int(round(float(raw) * GameManager.xp_gap_factor(reference_level))))


func _grant_xp(xp: int, message: String) -> void :
    var boosted: int = int(round(float(xp) * float(player_stats.get("party_xp_mult", 1.0))))
    _companion_levelups.clear()
    var levels: int = GameManager.grant_party_xp(boosted)
    player_stats = GameManager.player_battle_stats()
    _sync_ally_actor_stats()
    var hero_card: Dictionary = _ally_cards[0] if not _ally_cards.is_empty() else {}
    if not hero_card.is_empty() and hero_card.get("xp_bar") != null:
        var xp_tween: = create_tween()
        xp_tween.tween_property(
            hero_card["xp_bar"], "size:x",
            (float(hero_card.get("bar_w", PLAYER_HP_BAR_W)) - 24.0) * clampf(float(GameManager.player_xp) / float(GameManager.xp_to_next_level()), 0.0, 1.0),
            0.7,
        ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _refresh_all_panels()
    await _say(message)
    if levels > 0:
        _spawn_particles(_actor_fx_center(_allies[0], true), COLOR_ACCENT, 28)
        _spawn_damage_number(_actor_fx_center(_allies[0], true) + Vector2(80, -50), "LEVEL UP!", COLOR_ACCENT, true)
        if not hero_card.is_empty():
            var glow: = create_tween()
            glow.tween_property(hero_card["root"], "modulate", Color(1.4, 1.3, 0.9), 0.25)
            glow.tween_property(hero_card["root"], "modulate", Color.WHITE, 0.6)
        await _say("LEVEL UP! You are now level %d. You feel restored and stronger." % GameManager.player_level)

    for entry in _companion_levelups:
        var npc_id: String = str((entry as Dictionary).get("npc_id", ""))
        var comp_name: String = PartyManager.companion_name(npc_id) if PartyManager.has_method("companion_name") else npc_id
        await _say("%s reached level %d!" % [comp_name, int((entry as Dictionary).get("level", 1))])
    _companion_levelups.clear()
    _sync_ally_actor_stats()
    _refresh_all_panels()


## Mid-battle level-ups change the underlying sheets — pull the fresh numbers
## back into the live actor dictionaries (downed state and current HP persist).
func _sync_ally_actor_stats() -> void :
    for ally in _allies:
        if str(ally.get("kind")) == "player":
            ally["level"] = GameManager.player_level
            ally["max_hp"] = int(player_stats.get("max_hp", 80))
            ally["attack"] = int(player_stats.get("attack", 12))
            ally["defense"] = int(player_stats.get("defense", 5))
            ally["speed"] = int(player_stats.get("speed", 9))
            ally["sp_max"] = int(player_stats.get("sp_max", 3))
            ally["skills"] = GameManager.player_skills()
        else:
            var npc_id: = str(ally.get("id"))
            var stats: Dictionary = GameManager.companion_battle_stats(npc_id)
            ally["level"] = int(stats.get("level", 1))
            ally["max_hp"] = int(stats.get("max_hp", 50))
            ally["attack"] = int(stats.get("attack", 10))
            ally["defense"] = int(stats.get("defense", 4))
            ally["speed"] = int(stats.get("speed", 8))
            ally["sp_max"] = int(stats.get("sp_max", 2))
            ally["skills"] = GameManager.companion_skills(npc_id)
        ally["sp"] = mini(int(ally.get("sp", 0)), int(ally.get("sp_max", 3)))


func _defeat() -> void :
    var dark: = create_tween()
    dark.tween_property(_root, "modulate", Color(0.55, 0.5, 0.6), 1.2)
    for line in _dialogue("player_defeat"):
        if not _foes.is_empty():
            _enemy_say(_foes[0], str(line))
    GameManager.lose_xp_on_defeat()
    # Companions wake alongside the protagonist.
    for ally in _allies:
        if str(ally.get("kind")) == "companion":
            ally["downed"] = false
            GameManager.set_companion_hp(str(ally.get("id")), -1)
    await _say("Your memory frays... you lose some experience and wake up where you started.")
    _finish("defeat")


# ── target selection (gold arrow over foes / ally cards) ─────────────────────


## Cursor-pick a living foe. Auto-resolves when only one foe stands. Returns the
## foe index, or -1 when the player backs out.
func _pick_foe_target() -> int:
    var living: Array[int] = _living_foes()
    if living.is_empty():
        return -1
    if living.size() == 1:
        _target_foe_index = living[0]
        _refresh_target_readout()
        return living[0]
    return await _run_target_pick(living, false)


## Cursor-pick an ally (heal/shield/revive). only_downed lists fallen members.
func _pick_ally_target(only_downed: bool = false) -> int:
    var candidates: Array[int] = []
    for index in range(_allies.size()):
        var down: = _actor_down(_allies[index], true)
        if (only_downed and down) or (not only_downed and not down):
            candidates.append(index)
    if candidates.is_empty():
        return -1
    if candidates.size() == 1:
        return candidates[0]
    return await _run_target_pick(candidates, true)


var _target_candidates: Array[int] = []
var _target_pos: int = 0
var _target_is_ally: bool = false
signal _target_picked(index: int)


func _run_target_pick(candidates: Array[int], is_ally: bool) -> int:
    _target_candidates = candidates
    _target_pos = 0
    _target_is_ally = is_ally
    if not is_ally:
        var preferred: = _target_candidates.find(_target_foe_index)
        if preferred >= 0:
            _target_pos = preferred
    _ui_mode = UiMode.TARGET
    _show_target_arrows()
    var picked: int = await _target_picked
    _hide_target_arrows()
    _ui_mode = UiMode.NONE
    return picked


func _show_target_arrows() -> void :
    _update_target_arrows()


func _update_target_arrows() -> void :
    # Hide everything first, then light the hovered candidate.
    for foe in _foes:
        var ui: Dictionary = _foe_ui(foe)
        if not ui.is_empty():
            _set_foe_targeted(ui, false)
    for card in _ally_cards:
        (card["arrow"] as Control).visible = false
    if _target_pos >= _target_candidates.size():
        return
    var index: int = _target_candidates[_target_pos]
    if _target_is_ally:
        if index < _ally_cards.size():
            var arrow: Control = _ally_cards[index]["arrow"]
            arrow.visible = true
            _pulse_arrow(arrow)
    else:
        var ui: Dictionary = _foe_ui(_foes[index])
        if not ui.is_empty():
            _set_foe_targeted(ui, true)
        _target_foe_index = index
        _refresh_target_readout()


func _set_foe_targeted(ui: Dictionary, targeted: bool) -> void:
    var target_visual: EnemyTargetHighlight = ui.get("target_visual") as EnemyTargetHighlight
    if target_visual != null:
        target_visual.set_selected(targeted)
    var identity: EnemyIdentityPlate = ui.get("identity_root") as EnemyIdentityPlate
    if identity != null:
        identity.set_targeted(targeted)
    var hp_root: Control = ui.get("hp_root") as Control
    if hp_root != null:
        hp_root.modulate = Color(1.10, 1.05, 0.90, 1.0) if targeted else Color.WHITE


func _pulse_arrow(arrow: Control) -> void :
    var pulse: = create_tween().set_loops(2)
    pulse.tween_property(arrow, "modulate:a", 0.55, 0.28)
    pulse.tween_property(arrow, "modulate:a", 1.0, 0.28)


func _hide_target_arrows() -> void :
    for foe in _foes:
        var ui: Dictionary = _foe_ui(foe)
        if not ui.is_empty():
            _set_foe_targeted(ui, false)
    for card in _ally_cards:
        (card["arrow"] as Control).visible = false


# ── per-skill FX (generated sheets with graceful fallback) ────────────────────

const SKILL_FX_DIR: = "res://assets/fx/skills/"


## Every skill can ship a dedicated 4-frame FX sheet (512x128, generated via the
## OpenAI extension pipeline). Missing sheets degrade to the classic slash.
func _skill_fx_frames(skill_id: String) -> SpriteFrames:
    if skill_id.is_empty():
        return null
    if _skill_fx_cache.has(skill_id):
        return _skill_fx_cache[skill_id]
    var path: = "%s%s_sheet.png" % [SKILL_FX_DIR, skill_id]
    var frames: SpriteFrames = null
    # _load_png_texture also reads the raw PNG before Godot has generated a
    # .import sidecar, which keeps fresh-checkout headless smoke tests reliable.
    var sheet: Texture2D = _load_png_texture(path)
    if sheet != null:
        var frame_size: int = sheet.get_height()
        var count: int = maxi(int(sheet.get_width() / maxi(frame_size, 1)), 1)
        frames = SpriteFrames.new()
        frames.remove_animation("default")
        frames.add_animation("fx")
        frames.set_animation_speed("fx", 12.0)
        frames.set_animation_loop("fx", false)
        for index in range(count):
            var atlas: = AtlasTexture.new()
            atlas.atlas = sheet
            atlas.region = Rect2(index * frame_size, 0, frame_size, frame_size)
            frames.add_frame("fx", atlas)
    _skill_fx_cache[skill_id] = frames
    return frames


func _play_skill_fx(skill_id: String, at: Vector2, effect_scale: float = 1.5) -> void :
    var frames: = _skill_fx_frames(skill_id)
    if frames == null:
        return
    var sprite: = AnimatedSprite2D.new()
    sprite.sprite_frames = frames
    sprite.position = at
    sprite.scale = Vector2(effect_scale, effect_scale)
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _fx_layer.add_child(sprite)
    sprite.play("fx")
    sprite.animation_finished.connect(sprite.queue_free)


func _play_ally_attack_fx(
    skill_id: String,
    at: Vector2,
    effect_scale: float = 1.5,
) -> void:
    _play_skill_fx(skill_id, at, effect_scale * ALLY_TO_FOE_FX_SCALE)


# ── panel refresh (readout + foe bars + ally cards) ──────────────────────────


func _refresh_all_panels() -> void :
    _refresh_target_readout()
    for foe in _foes:
        _refresh_foe_overlay(foe)
    for index in range(mini(_allies.size(), _ally_cards.size())):
        _refresh_ally_card(_allies[index], _ally_cards[index])


## Keeps target-index bookkeeping for the selection cursor. Name/HP/status come
## from the per-foe readout under each sprite (which also shows EXPOSED).
func _refresh_target_readout() -> void :
    if _foes.is_empty():
        return
    var living: Array[int] = _living_foes()
    if _target_foe_index >= _foes.size() or (_actor_down(_foes[_target_foe_index], false) and not living.is_empty()):
        _target_foe_index = living[0] if not living.is_empty() else 0


func _refresh_foe_overlay(foe: Dictionary) -> void :
    var ui: Dictionary = _foe_ui(foe)
    if ui.is_empty():
        return
    var identity: Control = ui.get("identity_root") as Control
    if identity != null and identity.has_method("set_identity"):
        identity.call("set_identity", str(foe.get("name", "Enemy")), int(foe.get("level", 1)))
    var bar_w: float = float(ui.get("bar_w", 120.0))
    var ratio: float = clampf(float(foe.get("hp", 0)) / float(foe.get("max_hp", 1)), 0.0, 1.0)
    (ui["hp_bar"] as Control).size.x = bar_w * ratio
    (ui["hp_text"] as Label).text = "%d / %d" % [maxi(int(foe.get("hp", 0)), 0), int(foe.get("max_hp", 1))]
    var status_extra: Array[Dictionary] = []
    if exposed_turns > 0 and foe == _foes[0]:
        status_extra.append({
            "id": "exposed", "label": "EXP", "wide_label": "EXPOSED", "count": exposed_turns,
            "tooltip": "Exposed · takes amplified damage · %d turn%s" % [
                exposed_turns, "" if exposed_turns == 1 else "s"],
        })
    _refresh_status_row(ui["status_row"] as HBoxContainer, foe, status_extra)
    if identity != null and identity.has_method("refresh_status_layout"):
        identity.call("refresh_status_layout")


func _refresh_ally_card(ally: Dictionary, card: Dictionary) -> void :
    var name_label: Label = card.get("name_label") as Label
    if name_label != null:
        name_label.text = str(ally.get("name"))
    var lv_label: Label = card.get("lv_label") as Label
    if lv_label != null:
        lv_label.text = "Lv.%d" % int(ally.get("level", 1))
    var max_hp: int = int(ally.get("max_hp", 1))
    var hp: int = _ally_hp(ally)
    (card["hp_text"] as Label).text = "%d / %d" % [hp, max_hp]
    (card["hp_bar"] as Control).size.x = float(card.get("bar_w", PLAYER_HP_BAR_W)) * clampf(float(hp) / float(max_hp), 0.0, 1.0)
    _refresh_sp_pips_for(card, ally)
    var status_extra: Array[Dictionary] = []
    if bool(ally.get("downed", false)) or hp <= 0:
        status_extra.append({"id": "down", "label": "KO", "count": 0, "tooltip": "Down · cannot act until revived"})
    if bool(ally.get("focus", false)):
        status_extra.append({"id": "focus", "label": "FOC", "count": 0, "tooltip": "Focus · next attack deals double damage"})
    if bool(ally.get("guarding", false)):
        status_extra.append({"id": "guard", "label": "GRD", "count": 0, "tooltip": "Guard · incoming damage is halved"})
    var status_row: HBoxContainer = card.get("status_row") as HBoxContainer
    if status_row != null:
        _refresh_status_row(status_row, ally, status_extra)
    (card["root"] as Control).modulate.a = 0.55 if (bool(ally.get("downed", false)) or hp <= 0) else 1.0
    if card.get("xp_text") != null:
        var current_xp: int
        var needed_xp: int
        if str(ally.get("kind")) == "player":
            current_xp = GameManager.player_xp
            needed_xp = GameManager.xp_to_next_level()
        else:
            current_xp = GameManager.companion_xp(str(ally.get("id", "")))
            needed_xp = GameManager.xp_to_next_level_for(int(ally.get("level", 1)))
        needed_xp = maxi(needed_xp, 1)
        (card["xp_text"] as Label).text = "%d / %d" % [current_xp, needed_xp]
        if card.get("xp_bar") != null:
            (card["xp_bar"] as Control).size.x = \
                (float(card.get("bar_w", PLAYER_HP_BAR_W)) - 24.0) \
                * clampf(float(current_xp) / float(needed_xp), 0.0, 1.0)


## The controlled ally owns the full card at the fixed bottom position. No card
## moves sideways; focus is communicated by the full form and a restrained tint.
func _set_active_ally(ally: Variant) -> void :
    if _ally_stack != null:
        _ally_stack.set_active(ally, _round_queue, _queue_pos)


## Rebuild the right-edge queue strip from the REAL round order: the next up to
## 4 turns starting at the current queue position (peeking into a predicted next
## round when the current one is nearly done).
func _update_turn_order_view(animate: bool = true) -> void :
    var display: Array = []
    var pos: = _queue_pos
    var queue: Array[Dictionary] = _round_queue
    var safety: = 0
    while display.size() < 4 and safety < 3:
        if pos >= queue.size():
            queue = _build_round_queue()
            pos = 0
            safety += 1
            if queue.is_empty():
                break
            continue
        var entry: Dictionary = queue[pos]
        var actor: Dictionary = _actor_for_entry(entry)
        pos += 1
        if actor.is_empty():
            continue
        var is_ally: = str(entry.get("side")) == "ally"
        if _actor_down(actor, is_ally):
            continue
        var texture: Texture2D = null
        if is_ally:
            texture = _ally_portrait_texture(actor)
        else:
            texture = _foe_portrait_texture(actor)
        display.append({"texture": texture, "label": str(actor.get("name", ""))})
    _rebuild_turn_cards(display, animate)


func _finish(result: String) -> void :
    if _battle_over:
        return
    _battle_over = true
    _pending_finish_result = result
    _finish_confirm_ready = false
    _ui_mode = UiMode.CONFIRM
    if _continue_marker != null:
        _continue_marker.visible = false
    # Preserve victory/spare/defeat/flee presentation. The final Enter prompt is
    # enabled only after the longest terminal tween (defeat darkening: 1.2 s).
    get_tree().create_timer(BATTLE_FINISH_CONFIRM_DELAY).timeout.connect(
        _enable_finish_confirmation,
        CONNECT_ONE_SHOT,
    )


func _enable_finish_confirmation() -> void:
    if not is_inside_tree() or _pending_finish_result.is_empty():
        return
    _finish_confirm_ready = true
    if _continue_marker != null:
        _continue_marker.visible = true
        var bounce := create_tween().set_loops()
        bounce.tween_property(_continue_marker, "position:y", 124.0, 0.25)
        bounce.tween_property(_continue_marker, "position:y", 120.0, 0.25)


func _finalize_finish() -> void:
    if not is_inside_tree() or not _finish_confirm_ready:
        return
    var result := _pending_finish_result
    _pending_finish_result = ""
    _finish_confirm_ready = false
    _ui_mode = UiMode.NONE
    if _continue_marker != null:
        _continue_marker.visible = false
    _shutdown_enemy_barks()
    GameManager.ui_blocking_input = false
    battle_finished.emit(result, enemy_id)
    queue_free()


func _exit_tree() -> void:
    _clear_battle_log_runtime()
    _shutdown_enemy_barks()







func _decorate_log_line(text: String) -> String:
    var icon_file: = "log_sparkle.png"
    var lower: = text.to_lower()
    if lower.contains("damage") or lower.contains("attack") or lower.contains("strike") or lower.contains("hit"):
        icon_file = "log_sword.png"
    elif lower.contains("prepar") or lower.contains("smoke") or lower.contains("hex") or lower.contains("gather") or lower.contains("materializ"):
        icon_file = "log_swirl.png"
    var body: = text
    var enemy_name: = _enemy_name()
    if not enemy_name.is_empty():
        body = body.replace(enemy_name, "[color=#e5534b]%s[/color]" % enemy_name)
    var icon_path: = BATTLE_V3_DIR + icon_file
    if ResourceLoader.exists(icon_path):
        return "[img=15x15]%s[/img]  %s" % [icon_path, body]
    return body


func _say(text: String) -> void :
    if _battle_over or _log_list == null:
        return
    var line := text.strip_edges()
    if line.is_empty():
        return
    var entry_id := _next_battle_log_entry_id
    _next_battle_log_entry_id += 1
    var entry := _make_battle_log_entry(entry_id, _decorate_log_line(line))
    _battle_log_entries.append(entry)
    _log_list.add_child(entry["root"])
    (entry["timer"] as Timer).start()
    while _battle_log_entries.size() > MAX_BATTLE_LOG_ENTRIES:
        _drop_oldest_battle_log_entry()
    _finalize_battle_log_entry.call_deferred(entry_id)


func _make_battle_log_entry(entry_id: int, decorated_text: String) -> Dictionary:
    # The raw Control deliberately owns the row height. Its RichTextLabel child
    # cannot impose a minimum size, so expiry can smoothly collapse this height
    # and let VBoxContainer scroll the remaining history upward.
    var root := Control.new()
    root.name = "BattleLogEntry_%d" % entry_id
    root.clip_contents = true
    root.custom_minimum_size = Vector2(0, BATTLE_LOG_MIN_ENTRY_HEIGHT)
    root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.modulate = Color(1, 1, 1, 0.68)

    var label := RichTextLabel.new()
    label.name = "Text"
    label.bbcode_enabled = true
    label.text = decorated_text
    label.visible_characters = -1
    label.scroll_active = false
    label.fit_content = false
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.anchor_right = 1.0
    label.offset_bottom = 256.0
    label.position = BATTLE_LOG_APPEND_OFFSET
    label.add_theme_font_size_override("normal_font_size", BATTLE_LOG_FONT_SIZE)
    label.add_theme_color_override("default_color", COLOR_TEXT)
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    label.add_theme_constant_override("line_separation", BATTLE_LOG_ENTRY_GAP)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(label)

    var timer := Timer.new()
    timer.name = "TimeToLive"
    timer.one_shot = true
    timer.wait_time = BATTLE_LOG_ENTRY_TTL
    timer.timeout.connect(_expire_battle_log_entry.bind(entry_id), CONNECT_ONE_SHOT)
    root.add_child(timer)

    return {
        "id": entry_id,
        "root": root,
        "label": label,
        "timer": timer,
        "arrival_tween": null,
        "exit_tween": null,
        "removing": false,
    }


func _finalize_battle_log_entry(entry_id: int) -> void:
    var entry := _battle_log_entry(entry_id)
    if entry.is_empty() or bool(entry.get("removing", false)):
        return
    var root: Control = entry["root"]
    var label: RichTextLabel = entry["label"]
    if not is_instance_valid(root) or not is_instance_valid(label):
        return
    # RichTextLabel needs one layout pass before wrapped content height is exact.
    var content_height := maxf(
        BATTLE_LOG_MIN_ENTRY_HEIGHT,
        ceilf(label.get_content_height()),
    )
    root.custom_minimum_size.y = content_height
    label.offset_bottom = content_height

    var arrival := create_tween().set_parallel(true)
    entry["arrival_tween"] = arrival
    arrival.tween_property(
        label, "position", Vector2.ZERO, BATTLE_LOG_APPEND_DURATION,
    ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    arrival.tween_property(
        root, "modulate", Color.WHITE, BATTLE_LOG_APPEND_DURATION,
    ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _schedule_battle_log_scroll()


func _expire_battle_log_entry(entry_id: int) -> void:
    var entry := _battle_log_entry(entry_id)
    if entry.is_empty() or bool(entry.get("removing", false)):
        return
    var root: Control = entry["root"]
    var label: RichTextLabel = entry["label"]
    if not is_instance_valid(root) or not is_instance_valid(label):
        _erase_battle_log_entry(entry_id, false)
        return
    entry["removing"] = true
    _kill_battle_log_entry_tween(entry, "arrival_tween")
    root.custom_minimum_size.y = maxf(
        BATTLE_LOG_MIN_ENTRY_HEIGHT,
        maxf(root.size.y, root.custom_minimum_size.y),
    )

    # Fade/slide the expired row while its height closes. VBoxContainer reflows
    # on every tween frame, which is the requested smooth scroll-on-removal.
    var exit := create_tween().set_parallel(true)
    entry["exit_tween"] = exit
    exit.tween_property(
        root, "modulate:a", 0.0, BATTLE_LOG_EXIT_DURATION,
    ).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    exit.tween_property(
        label, "position", BATTLE_LOG_EXIT_OFFSET, BATTLE_LOG_EXIT_DURATION,
    ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    exit.tween_property(
        root, "custom_minimum_size:y", 0.0, BATTLE_LOG_EXIT_DURATION,
    ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    exit.chain().tween_callback(_finish_battle_log_entry_expiry.bind(entry_id))


func _finish_battle_log_entry_expiry(entry_id: int) -> void:
    var entry := _battle_log_entry(entry_id)
    if entry.is_empty():
        return
    # Do not kill the tween from inside its own completion callback.
    entry["exit_tween"] = null
    _erase_battle_log_entry(entry_id, true)


func _drop_oldest_battle_log_entry() -> void:
    if _battle_log_entries.is_empty():
        return
    _erase_battle_log_entry(int(_battle_log_entries[0].get("id", -1)), true)


func _erase_battle_log_entry(entry_id: int, schedule_scroll: bool) -> void:
    var index := _battle_log_entry_index(entry_id)
    if index < 0:
        return
    var entry: Dictionary = _battle_log_entries[index]
    var timer: Timer = entry.get("timer") as Timer
    if timer != null and is_instance_valid(timer):
        timer.stop()
    _kill_battle_log_entry_tween(entry, "arrival_tween")
    _kill_battle_log_entry_tween(entry, "exit_tween")
    var root: Control = entry.get("root") as Control
    if root != null and is_instance_valid(root):
        if root.get_parent() != null:
            root.get_parent().remove_child(root)
        root.queue_free()
    _battle_log_entries.remove_at(index)
    if schedule_scroll:
        _schedule_battle_log_scroll()


func _battle_log_entry(entry_id: int) -> Dictionary:
    var index := _battle_log_entry_index(entry_id)
    return _battle_log_entries[index] if index >= 0 else {}


func _battle_log_entry_index(entry_id: int) -> int:
    for index in range(_battle_log_entries.size()):
        if int(_battle_log_entries[index].get("id", -1)) == entry_id:
            return index
    return -1


func _kill_battle_log_entry_tween(entry: Dictionary, key: String) -> void:
    var tween: Tween = entry.get(key) as Tween
    if tween != null and tween.is_valid():
        tween.kill()
    entry[key] = null


func _schedule_battle_log_scroll() -> void:
    if _battle_log_scroll_queued:
        return
    _battle_log_scroll_queued = true
    _scroll_battle_log_to_bottom.call_deferred()


func _scroll_battle_log_to_bottom() -> void:
    _battle_log_scroll_queued = false
    if _log_scroll == null or not is_instance_valid(_log_scroll):
        return
    var scrollbar := _log_scroll.get_v_scroll_bar()
    var target := maxf(0.0, scrollbar.max_value - scrollbar.page)
    if target <= 0.5:
        scrollbar.value = 0.0
        return
    if _battle_log_scroll_tween != null and _battle_log_scroll_tween.is_valid():
        _battle_log_scroll_tween.kill()
    _battle_log_scroll_tween = create_tween()
    _battle_log_scroll_tween.tween_property(
        scrollbar, "value", target, BATTLE_LOG_SCROLL_DURATION,
    ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _clear_battle_log_runtime() -> void:
    _battle_log_scroll_queued = false
    if _battle_log_scroll_tween != null and _battle_log_scroll_tween.is_valid():
        _battle_log_scroll_tween.kill()
    _battle_log_scroll_tween = null
    for entry in _battle_log_entries:
        var timer: Timer = entry.get("timer") as Timer
        if timer != null and is_instance_valid(timer):
            timer.stop()
        _kill_battle_log_entry_tween(entry, "arrival_tween")
        _kill_battle_log_entry_tween(entry, "exit_tween")
    _battle_log_entries.clear()


func _menu(
    ids: Array[String],
    labels: Array[String],
    descs: Array[String] = [],
    icon_sources: Array = [],
) -> String:
    if _hint_label != null:
        _hint_label.visible = false
    _ui_mode = UiMode.MENU
    var picked: String = await _command_menu.choose(ids, labels, descs, icon_sources)
    _ui_mode = UiMode.NONE
    return picked


func _process(delta: float) -> void :
    if _hint_label != null:
        _hint_label.visible = false

    if _shake_time > 0.0:
        _shake_time -= delta
        var decay: float = _shake_time * 3.0
        _root.position = Vector2(
            randf_range(-1.0, 1.0) * _shake_strength * decay, 
            randf_range(-1.0, 1.0) * _shake_strength * decay, 
        )
        if _shake_time <= 0.0:
            _root.position = Vector2.ZERO
            _shake_strength = 0.0

func _unhandled_input(event: InputEvent) -> void :
    if _battle_over:
        if _ui_mode == UiMode.CONFIRM and event.is_action_pressed("ui_accept"):
            if _finish_confirm_ready:
                _finalize_finish()
            get_viewport().set_input_as_handled()
        return
    if _ui_mode == UiMode.MENU:
        if _command_menu.handle_input(event):
            get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed("ui_accept"):
        match _ui_mode:
            UiMode.TARGET:
                if _target_pos < _target_candidates.size():
                    _target_picked.emit(_target_candidates[_target_pos])
                get_viewport().set_input_as_handled()
        return
    if _ui_mode == UiMode.TARGET:
        if event.is_action_pressed("ui_cancel"):
            _target_picked.emit(-1)
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
            if not _target_candidates.is_empty():
                _target_pos = (_target_pos + 1) % _target_candidates.size()
                _update_target_arrows()
            get_viewport().set_input_as_handled()
        elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
            if not _target_candidates.is_empty():
                _target_pos = (_target_pos - 1 + _target_candidates.size()) % _target_candidates.size()
                _update_target_arrows()
            get_viewport().set_input_as_handled()
        return





func _enemy_name() -> String:
    return str(enemy.get("name", "Enemy"))


func _player_name() -> String:
    var package: Dictionary = GameManager.get_scene_package()
    var characters: Dictionary = package.get("characters", {}) as Dictionary
    var main_character: Variant = characters.get("main_character", {})
    if main_character is Dictionary:
        var name: String = str((main_character as Dictionary).get("name", "")).strip_edges()
        if not name.is_empty() and name.to_upper() != "YOU":
            return name
    return "Bạn"


func _dialogue(key: String) -> Array:
    var dialogue: Dictionary = enemy.get("dialogue", {}) as Dictionary
    var lines: Array = dialogue.get(key, []) as Array
    var result: Array = []
    for line in lines:
        var text: = str(line).strip_edges()
        if not text.is_empty():
            result.append(text)
    return result
