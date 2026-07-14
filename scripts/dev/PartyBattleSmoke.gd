extends Node2D
## Dev-only smoke test for the MULTI-ACTOR battle: fabricates two companions
## (healer + attacker with pool skills), opens a battle against a minion (which
## grows reinforcement echoes to match the party), asserts the group shapes,
## then drives deterministic Attack input so the whole round loop — target selection included — runs
## without a human. Run headless:
## godot --headless --path . res://scenes/dev/PartyBattleSmoke.tscn --quit-after 4000

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const EnemyIdentityPlateScript := preload("res://scripts/battle/EnemyIdentityPlate.gd")
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
	_assert_enemy_identity_layout()
	_assert_visual_catalog()
	_assert_boss_party_scaling(enemy_data)
	_assert_sp_pip_fit()
	_assert_item_effect_copy()

	# Status engine sanity, straight on the live actors.
	var foe: Dictionary = _battle._foes[1]
	_battle._apply_status(foe, "poison")
	_check(not _battle._find_status(foe, "poison").is_empty(), "poison must stick")
	_battle._refresh_all_panels()
	var foe_status_row: HBoxContainer = (_battle._foe_ui(foe) as Dictionary)["status_row"]
	_check(foe_status_row.get_child_count() == 1, "foe status card should render the poison icon")
	_check(foe_status_row.position.y < 0.0, "foe status metadata must float above the portrait")
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


func _assert_enemy_identity_layout() -> void:
	var absolute_nameplates: Array[Rect2] = []
	for foe in _battle._foes:
		var ui: Dictionary = _battle._foe_ui(foe)
		var identity: Control = ui.get("identity_root") as Control
		_check(identity != null, "every foe needs an identity component")
		if identity == null:
			continue
		var level_label: Label = ui["level_label"]
		_check(level_label.position.y < 0.0, "level must float above the portrait")
		_check(level_label.text.begins_with("LV "), "level label must use the compact LV format")
		var bounds: Rect2 = identity.nameplate_bounds()
		var portrait_size: Vector2 = ui["size"]
		_check(bounds.position.y >= portrait_size.y, "enemy name must remain below the portrait")
		var hp_root: Control = ui["hp_root"]
		_check(hp_root.position.y + hp_root.size.y <= bounds.position.y + 0.01,
			"enemy HP must sit above the nameplate")
		var target_visual: EnemyTargetHighlight = ui["target_visual"]
		_check(target_visual != null, "every foe needs the modular target highlight")
		if target_visual != null:
			_check(target_visual.marker_bounds().end.y <= level_label.position.y - 4.0,
				"target marker must remain clear of level/status metadata")
			_check(not target_visual.is_selected(),
				"target highlight must start hidden outside target mode")
		_check(bounds.size.x <= portrait_size.x - 8.0 + 0.01, "nameplate must stay inside its foe slot")
		absolute_nameplates.append(Rect2((ui["home"] as Vector2) + bounds.position, bounds.size))
	for left_index in range(absolute_nameplates.size()):
		for right_index in range(left_index + 1, absolute_nameplates.size()):
			_check(
				not absolute_nameplates[left_index].intersects(absolute_nameplates[right_index]),
				"trio nameplates must not overlap",
			)

	var short_plate := EnemyIdentityPlateScript.new()
	short_plate.setup("A", 3, 152.0, 162.0, 3)
	var long_plate := EnemyIdentityPlateScript.new()
	long_plate.setup("Kẻ Canh Giữ Hoàng Hôn Vĩnh Cửu", 18, 152.0, 162.0, 3)
	_check(long_plate.nameplate_width > short_plate.nameplate_width,
		"only the middle rail should grow for a longer localized name")
	_check(long_plate.nameplate_width <= 144.01, "long trio names must respect the slot cap")
	short_plate.free()
	long_plate.free()

	# Selection must transfer atomically and clear completely on cancel/resolve.
	var qa_targets: Array[int] = [0, 1]
	_battle._target_candidates = qa_targets
	_battle._target_is_ally = false
	_battle._target_pos = 0
	_battle._update_target_arrows()
	_check((_battle._foe_ui(_battle._foes[0])["target_visual"] as EnemyTargetHighlight).is_selected(),
		"first target should own the highlight")
	_check(not (_battle._foe_ui(_battle._foes[1])["target_visual"] as EnemyTargetHighlight).is_selected(),
		"unfocused target must not retain the highlight")
	_battle._target_pos = 1
	_battle._update_target_arrows()
	_check(not (_battle._foe_ui(_battle._foes[0])["target_visual"] as EnemyTargetHighlight).is_selected(),
		"highlight must leave the previous target")
	_check((_battle._foe_ui(_battle._foes[1])["target_visual"] as EnemyTargetHighlight).is_selected(),
		"highlight must follow target navigation")
	_battle._hide_target_arrows()
	_check(not (_battle._foe_ui(_battle._foes[1])["target_visual"] as EnemyTargetHighlight).is_selected(),
		"target highlight must clear after selection")
	_battle._target_foe_index = 0
	print("[PartySmoke] enemy identity layout OK — floating metadata + modular nameplate")


func _assert_sp_pip_fit() -> void:
	# Level 18 currently produces 13 SP: the regression case that previously
	# extended 55px beyond a full ally card.
	for sample in [
		{"width": 182.0, "count": 13, "shrinks": true},
		{"width": 220.0, "count": 13, "shrinks": true},
		{"width": 182.0, "count": 9, "shrinks": false},
		{"width": 220.0, "count": 11, "shrinks": false},
		{"width": 182.0, "count": 1, "shrinks": false},
		{"width": 182.0, "count": 0, "shrinks": false},
	]:
		var row := Control.new()
		var available_width := float(sample["width"])
		row.size = Vector2(available_width, 15.0)
		var pips: Array = _battle._build_sp_pips_for(
			row, int(sample["count"]), available_width)
		var rendered_right := 0.0
		for pip in pips:
			var control := pip as Control
			rendered_right = maxf(rendered_right, control.position.x + control.size.x)
		_check(rendered_right <= available_width + 0.01,
			"SP pips must stay inside the ally card")
		if not pips.is_empty():
			var first_side := (pips[0] as Control).size.x
			_check(first_side < 15.0 if bool(sample["shrinks"]) else is_equal_approx(first_side, 15.0),
				"SP pips must shrink only when their natural row is too wide")
		row.free()
	print("[PartySmoke] SP pip fit OK — full and compact cards remain bounded")


func _assert_item_effect_copy() -> void:
	var flavor := "A sentimental description that must never appear in battle."
	var heal := {"kind": "heal", "power": 80, "description": flavor}
	var energy := {"kind": "energy", "power": 3, "description": flavor}
	var buff := {"kind": "buff", "power": 0, "description": flavor}
	_check(_battle._item_battle_effect_text(heal) == "Restore 80 HP to one ally.",
		"heal item menu copy must come from its gameplay power")
	_check(_battle._item_battle_effect_text(energy) == "Restore 3 SP to one ally.",
		"energy item menu copy must come from its gameplay power")
	_check(_battle._item_battle_effect_text(buff).contains("double damage"),
		"buff item menu copy must state its real combat effect")
	_check(not _battle._item_battle_effect_text(heal).contains(flavor),
		"battle item menu must not reuse flavor description")
	print("[PartySmoke] item effect copy OK — mechanics replace flavor descriptions")


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
	_check(
		_battle._load_png_texture("res://assets/ui/enemy_identity_v1/exposed.png") != null,
		"missing OpenAiExtension EXPOSED icon",
	)
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
