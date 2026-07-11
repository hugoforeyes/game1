extends Node2D
## Dev-only smoke test for the MULTI-ACTOR battle: fabricates two companions
## (healer + attacker with pool skills), opens a battle against a minion (which
## grows reinforcement echoes to match the party), asserts the group shapes,
## then drives deterministic Attack input so the whole round loop — target selection included — runs
## without a human. Run headless:
## godot --headless --path . res://scenes/dev/PartyBattleSmoke.tscn --quit-after 4000

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const MainScript := preload("res://scripts/world/Main.gd")

var _frames: int = 0
var _battle: CanvasLayer = null
var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[PartySmoke] FAIL: %s" % message)

func _ready() -> void:
	GameManager.reset_combat_progress()
	PartyManager.companions["comp_healer"] = {
		"npc_id": "comp_healer", "name": "Arlo", "combat_role": "healer",
		"skills": ["soothing_light", "regrowth", "verdant_rain", "guiding_star"],
	}
	PartyManager.companions["comp_striker"] = {
		"npc_id": "comp_striker", "name": "Mira", "combat_role": "attacker",
		"skills": ["venom_fang", "wild_flurry", "flame_burst", "skull_crack"],
	}
	PartyManager.active_members["comp_healer"] = true
	PartyManager.active_members["comp_striker"] = true
	GameManager.ensure_companion("comp_healer")["level"] = 3
	GameManager.ensure_companion("comp_striker")["level"] = 3

	# Companion skill resolution: level 3 unlocks slots 1+2 of the authored set.
	var healer_skills := GameManager.companion_skills("comp_healer")
	_check(healer_skills.size() == 2, "level 3 healer should have 2 unlocked skills")
	if not healer_skills.is_empty():
		_check(str(healer_skills[0]["id"]) == "soothing_light", "authored skill order must hold")

	var main_helper := MainScript.new()
	var enemy_data: Dictionary = main_helper._fallback_enemy(
		"smoke_enemy", "Smoke Echo", "minion", 2, true, Vector2i(3, 3)
	)
	main_helper.free()
	_battle = BattleSceneScript.new()
	add_child(_battle)
	_battle.battle_finished.connect(_on_finished)
	_battle.open(enemy_data)
	if OS.get_environment("PARTY_BATTLE_SHOTS") == "1":
		_capture_party_shot.call_deferred()

	_check(_battle._allies.size() == 3, "player + 2 companions expected")
	_check(_battle._foes.size() == 3, "minion + 2 echoes expected for a 3-ally party")
	_check(bool(_battle._foes[1]["synthetic"]), "echo must be synthetic")
	_check(int(_battle._foes[1]["xp_reward"]) < int(_battle._foes[0]["xp_reward"]),
		"echo XP must be reduced")
	_assert_visual_catalog()
	_assert_boss_party_scaling(enemy_data)

	# Status engine sanity, straight on the live actors.
	var foe: Dictionary = _battle._foes[1]
	_battle._apply_status(foe, "poison")
	_check(not _battle._find_status(foe, "poison").is_empty(), "poison must stick")
	_battle._refresh_all_panels()
	var foe_status_row: HBoxContainer = (_battle._foe_ui(foe) as Dictionary)["status_row"]
	_check(foe_status_row.get_child_count() == 1, "foe status card should render the poison icon")
	if foe_status_row.get_child_count() > 0:
		var poison_token: Control = foe_status_row.get_child(0)
		_check(not str(poison_token.tooltip_text).is_empty(), "status icon should explain itself via tooltip")
		_check(poison_token.get_child_count() >= 2, "timed status icon should include a turn-count badge")
	var upkeep: Dictionary = _battle._tick_statuses(foe, false)
	_check(int(foe["hp"]) < int(foe["max_hp"]), "poison tick must damage")
	_check(not bool(upkeep["skip"]), "poison must not skip the turn")
	_battle._apply_status(foe, "stun")
	var stunned: Dictionary = _battle._tick_statuses(foe, false)
	_check(bool(stunned["skip"]), "stun must skip the turn")
	_check(_battle._find_status(foe, "stun").is_empty(), "1-turn stun must expire after ticking")
	var ally: Dictionary = _battle._allies[1]
	_battle._apply_status(ally, "shield", 12.0)
	_battle._refresh_all_panels()
	var ally_status_row: HBoxContainer = (_battle._ally_cards[1] as Dictionary)["status_row"]
	_check(ally_status_row.get_child_count() == 1, "ally status card should render the shield icon")
	var leftover: int = _battle._absorb_with_shields(ally, 9)
	_check(leftover == 0, "shield should eat a 9-damage hit fully")
	leftover = _battle._absorb_with_shields(ally, 10)
	_check(leftover == 7, "3 shield points remained, 7 damage should pass")
	print("[PartySmoke] shape+status assertions OK — automating the battle")


func _capture_party_shot() -> void:
	await get_tree().create_timer(0.35).timeout
	if DisplayServer.get_name() == "headless":
		return
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("/tmp/party_battle_overview.png")


func _assert_visual_catalog() -> void:
	var skill_ids: Dictionary = {}
	for raw_skill in GameManager.SKILL_LIBRARY:
		skill_ids[str((raw_skill as Dictionary).get("id", ""))] = true
	for raw_id in GameManager.COMPANION_SKILL_POOL.keys():
		skill_ids[str(raw_id)] = true
	_check(skill_ids.size() == 31, "visual catalog must cover 8 hero + 23 companion skills")
	for raw_id in skill_ids.keys():
		var skill_id := str(raw_id)
		var frames: SpriteFrames = _battle._skill_fx_frames(skill_id)
		_check(frames != null, "missing FX sheet: %s" % skill_id)
		if frames == null:
			continue
		_check(frames.has_animation("fx"), "FX animation missing for %s" % skill_id)
		if frames.has_animation("fx"):
			_check(frames.get_frame_count("fx") == 4, "FX sheet must have 4 frames: %s" % skill_id)

	var status_ids: Array = GameManager.STATUS_LIBRARY.keys()
	status_ids.append("focus")
	_check(status_ids.size() == 18, "status art must cover 17 catalog statuses + focus")
	for raw_id in status_ids:
		var status_id := str(raw_id)
		var path := "res://assets/ui/battle/status/%s.png" % status_id
		_check(_battle._load_png_texture(path) != null, "missing status icon: %s" % status_id)
	print("[PartySmoke] visual catalog OK — 31 skill FX + 18 status icons")


func _assert_boss_party_scaling(base_enemy: Dictionary) -> void:
	var boss_data: Dictionary = base_enemy.duplicate(true)
	boss_data["id"] = "smoke_boss"
	boss_data["name"] = "Smoke Sovereign"
	boss_data["rank"] = "boss"
	var base_hp: int = int((boss_data.get("stats", {}) as Dictionary).get("max_hp", 1))

	var solo := BattleSceneScript.new()
	solo.enemy = boss_data
	solo.enemy_id = "smoke_boss"
	solo._allies = [_battle._allies[0].duplicate(true)]
	solo._build_foes()
	_check(solo._foes.size() == 1, "a solo boss must not spawn echoes")
	_check(int(solo._foes[0]["max_hp"]) == base_hp, "solo boss HP must remain unchanged")
	_check(int(solo._foes[0]["actions_per_round"]) == 1, "solo boss keeps one action")
	solo.free()

	var grouped := BattleSceneScript.new()
	grouped.enemy = boss_data
	grouped.enemy_id = "smoke_boss"
	grouped._allies = _battle._allies.duplicate(true)
	grouped._build_foes()
	_check(grouped._foes.size() == 1, "party boss stays a single story actor")
	_check(
		int(grouped._foes[0]["max_hp"]) == int(round(base_hp * 2.1)),
		"three-ally boss must receive the calibrated 2.1x HP",
	)
	_check(int(grouped._foes[0]["actions_per_round"]) == 3, "three-ally boss gets three interleaved actions")
	_check(absf(grouped._hard_cc_resistance_for({"rank": "boss"}, "stun") - 0.65) < 0.001,
		"boss hard-control resistance must mirror backend")
	_check(grouped._hard_cc_resistance_for({"rank": "boss"}, "poison") == 0.0,
		"boss DoT must remain reliable")
	var queue: Array[Dictionary] = grouped._build_round_queue()
	var boss_slots: Array[int] = []
	for entry in queue:
		if str(entry.get("side")) == "foe":
			boss_slots.append(int(entry.get("action_slot", -1)))
	_check(boss_slots.size() == 3, "turn queue must contain every boss action")
	_check(boss_slots.has(0) and boss_slots.has(1) and boss_slots.has(2),
		"boss action slots must be unique and complete")
	grouped._allies[2]["downed"] = true
	var comeback_queue: Array[Dictionary] = grouped._build_round_queue()
	var remaining_boss_actions: int = 0
	for entry in comeback_queue:
		if str(entry.get("side")) == "foe":
			remaining_boss_actions += 1
	_check(remaining_boss_actions == 2,
		"boss pressure must drop with the living party to prevent defeat snowball")
	grouped.free()
	print("[PartySmoke] boss scaling OK — solo unchanged, 3-player pressure calibrated")

func _on_finished(result: String, enemy_id: String) -> void:
	print("[PartySmoke] battle finished result=%s enemy=%s" % [result, enemy_id])
	_check(result == "victory", "automated party battle should end in victory, got %s" % result)
	if _failures == 0:
		print("[PartySmoke] ALL CHECKS PASSED")
	else:
		print("[PartySmoke] %d CHECK(S) FAILED" % _failures)
	get_tree().quit(_failures)

func _process(_delta: float) -> void:
	_frames += 1
	if OS.get_environment("PARTY_BATTLE_SHOTS") == "1" \
			and DisplayServer.get_name() != "headless" and _frames % 30 == 0:
		var image: Image = get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("/tmp/party_battle_shot_%03d.png" % (_frames / 30))
	if _frames >= 3900:
		_check(false, "battle timed out before emitting battle_finished")
		get_tree().quit(_failures)
		return
	if _battle == null or not is_instance_valid(_battle):
		return
	# Keep the automated route deterministic: the default action is Attack. Cycle
	# only while choosing among multiple foes, never while a command menu is open.
	if _frames % 4 == 0:
		if int(_battle._ui_mode) == 4 and _frames % 40 == 0:  # UiMode.TARGET
			_press("ui_right")
		_press("ui_accept")

func _press(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
