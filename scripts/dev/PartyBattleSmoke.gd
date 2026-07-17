extends Node2D
## Dev-only smoke test for the MULTI-ACTOR battle: fabricates two companions
## (healer + attacker with pool skills), opens a battle against a minion (which
## grows reinforcement echoes to match the party), asserts the group shapes,
## then drives deterministic Attack input so the whole round loop — target selection included — runs
## without a human. Run headless:
## godot --headless --path . res://scenes/dev/PartyBattleSmoke.tscn --quit-after 10000

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const EnemyIdentityPlateScript := preload("res://scripts/battle/EnemyIdentityPlate.gd")
const MainScript := preload("res://scripts/world/Main.gd")

var _frames: int = 0
var _battle: CanvasLayer = null
var _failures: int = 0
const MAX_AUTOMATION_FRAMES := 9000


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
	# Exercise the CATALOG enemy-skill system end-to-end: the primary foe carries
	# a real backend-shaped loadout (frost_grasp is hard-CC so the echo-stripping
	# rule is also observable) and the automated battle drives the new dispatch.
	enemy_data["skill_loadout"] = {
		"skill_ids": ["venom_spit", "bone_ward", "frost_grasp"],
		"telegraphs": {"venom_spit": "Nọc độc sủi bọt giữa hai hàm răng..."},
		"source": "llm",
	}
	await _assert_escort_battle_contract(enemy_data)
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
	_assert_enemy_skill_system()
	_assert_boss_party_scaling(enemy_data)
	_assert_sp_pip_fit()
	_assert_starting_sp_policy()
	_assert_ally_card_hierarchy()
	_assert_companion_command_access()
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
	var compact_ally_card: Dictionary = _battle._ally_cards[1]
	_check(compact_ally_card.get("status_row") == null,
		"waiting ally must omit status metadata from the compact presentation")
	# Promote the shielded companion without animation so the same stored status
	# can be verified in the full card, then restore the initial player focus.
	_battle._ally_stack._rebuild(1, _battle._round_queue, _battle._queue_pos, false)
	var ally_status_row: HBoxContainer = (_battle._ally_cards[1] as Dictionary)["status_row"]
	_check(ally_status_row != null and ally_status_row.get_child_count() == 1,
		"focused ally card should render the stored shield icon")
	_battle._ally_stack._rebuild(0, _battle._round_queue, _battle._queue_pos, false)
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


func _assert_starting_sp_policy() -> void:
	for sample in [
		{"max": 0, "rank": "minion", "expected": 0},
		{"max": 1, "rank": "minion", "expected": 1},
		{"max": 2, "rank": "minion", "expected": 2},
		{"max": 3, "rank": "minion", "expected": 2},
		{"max": 6, "rank": "minion", "expected": 3},
		{"max": 12, "rank": "minion", "expected": 6},
		{"max": 13, "rank": "minion", "expected": 7},
		{"max": 6, "rank": "elite", "expected": 4},
		{"max": 12, "rank": "elite", "expected": 8},
		{"max": 13, "rank": "elite", "expected": 9},
		{"max": 6, "rank": "boss", "expected": 5},
		{"max": 12, "rank": "boss", "expected": 9},
		{"max": 13, "rank": "boss", "expected": 10},
		{"max": 6, "rank": "unknown", "expected": 3},
	]:
		var actual: int = _battle._starting_sp_for(
			int(sample["max"]), str(sample["rank"]))
		_check(actual == int(sample["expected"]),
			"starting SP formula mismatch for %s" % sample)

	var encounter_rank := str(_battle.enemy.get("rank", "minion"))
	for index in range(_battle._allies.size()):
		var ally: Dictionary = _battle._allies[index]
		var sp_max := int(ally.get("sp_max", 0))
		var expected: int = int(_battle._starting_sp_for(sp_max, encounter_rank))
		_check(int(ally.get("sp", -1)) == expected,
			"every ally must use the shared rank-aware opening SP policy")
		_check(expected >= 0 and expected <= sp_max,
			"opening SP must remain within the actor's pool")
		if encounter_rank == "minion" and sp_max > 2:
			_check(expected < sp_max,
				"normal encounters must not refill a nontrivial SP pool")

		# The HUD must immediately represent the partial reserve, not briefly draw
		# a full row until the first action refreshes the card.
		var card: Dictionary = _battle._ally_cards[index]
		var rendered_filled := 0
		var textured_pips := true
		for raw_pip in card.get("sp_pips", []) as Array:
			if not (raw_pip is TextureRect):
				textured_pips = false
				break
			var pip := raw_pip as TextureRect
			if pip.texture == pip.get_meta("filled_texture"):
				rendered_filled += 1
		if textured_pips:
			_check(rendered_filled == expected,
				"SP gems must match the partial opening reserve on the first frame")
	print("[PartySmoke] opening SP policy OK — normal/elite/boss reserves calibrated")


func _assert_ally_card_hierarchy() -> void:
	var player_focus: Array[Rect2] = _battle._ally_stack.target_rects(
		0, _battle._round_queue, _battle._queue_pos)
	_check(player_focus.size() == _battle._allies.size(),
		"ally stack must return one card rect per party member")
	if player_focus.size() >= 2:
		_check(player_focus[0].size.x > player_focus[1].size.x,
			"focused ally card must be wider than waiting cards")
		_check(is_equal_approx(player_focus[0].position.x, player_focus[1].position.x),
			"full and compact ally cards must keep the same left edge")
		_check(player_focus[0].size.x - player_focus[1].size.x >= 20.0,
			"compact width reduction must remain visually legible")

		var companion_focus: Array[Rect2] = _battle._ally_stack.target_rects(
			1, _battle._round_queue, _battle._queue_pos)
		_check(companion_focus[1].size.x > companion_focus[0].size.x,
			"width hierarchy must follow whichever ally is controlled")

		var full_card: Dictionary = _battle._ally_cards[0]
		var compact_card: Dictionary = _battle._ally_cards[1]
		_check(str((full_card["root"] as Control).get_meta("ally_card_form", "")) == "full",
			"controlled ally must retain the ornate full-card form")
		_check(str((compact_card["root"] as Control).get_meta("ally_card_form", "")) == "compact",
			"waiting ally must use the borderless compact form")
		_check(compact_card.get("name_label") == null,
			"waiting ally must not render a name")
		_check(compact_card.get("lv_label") == null,
			"waiting ally must not render a level chip")
		_check(compact_card.get("status_row") == null,
			"waiting ally must not render statuses")
		_check(compact_card.get("xp_bar") == null and compact_card.get("xp_text") == null,
			"waiting ally must not render XP")
		_check(compact_card.get("portrait") != null
			and compact_card.get("hp_bar") != null
			and compact_card.get("sp_row") != null,
			"waiting ally must retain portrait, HP and SP")
		var compact_root: Panel = compact_card["root"] as Panel
		var compact_style: StyleBox = compact_root.get_theme_stylebox("panel")
		_check(compact_style is StyleBoxEmpty,
			"waiting ally root must not draw any rectangular card surface")
		var compact_scrim: TextureRect = compact_card.get("compact_scrim") as TextureRect
		_check(compact_scrim != null and compact_scrim.texture is GradientTexture2D,
			"waiting ally must reuse the command-readout radial scrim")
		if compact_scrim != null and compact_scrim.texture is GradientTexture2D:
			var gradient_texture := compact_scrim.texture as GradientTexture2D
			_check(gradient_texture.fill == GradientTexture2D.FILL_RADIAL,
				"waiting ally scrim must dissolve radially into the battle art")
			_check(gradient_texture.fill_from.is_equal_approx(Vector2(0.5, 0.5))
				and gradient_texture.fill_to.is_equal_approx(Vector2(0.5, 0.0)),
				"waiting ally scrim must match the command-readout focus point")
			var gradient := gradient_texture.gradient
			_check(gradient != null and gradient.colors.size() == 3,
				"waiting ally scrim must keep the shared three-stop falloff")
			if gradient != null and gradient.colors.size() == 3:
				_check(is_equal_approx(gradient.colors[0].a, 0.72)
					and is_equal_approx(gradient.colors[1].a, 0.50)
					and is_zero_approx(gradient.colors[2].a),
					"waiting ally scrim must fade from dark focus to transparent edges")
	print("[PartySmoke] ally card hierarchy OK — waiting cards remain compact")


func _assert_companion_command_access() -> void:
	var companion: Dictionary = _battle._allies[1]
	var companion_ids: Array[String] = []
	for command in _battle._ally_action_commands(companion):
		companion_ids.append(str(command.get("id", "")))
	_check(companion_ids == ["attack", "skill", "item", "guard", "flee"],
		"companions must receive Item and Flee without protagonist-only commands")
	_check(not companion_ids.has("probe") and not companion_ids.has("finisher"),
		"Probe and Resolve Strike must remain protagonist-only")

	var primary: Dictionary = _battle._foes[0]
	var old_hp := int(primary.get("hp", 1))
	var old_can_spare := bool(_battle.enemy.get("can_spare", false))
	var old_exposed: int = int(_battle.exposed_turns)
	var old_finisher: bool = bool(_battle.finisher_used)
	primary["hp"] = maxi(1, int(primary.get("max_hp", 1)) * 3 / 10)
	_battle.enemy["can_spare"] = true
	_battle.exposed_turns = 1
	_battle.finisher_used = false
	companion_ids.clear()
	for command in _battle._ally_action_commands(companion):
		companion_ids.append(str(command.get("id", "")))
	_check(companion_ids.has("spare"), "an eligible companion must be able to Spare")
	_check(not companion_ids.has("finisher"),
		"an exposed foe must not give a companion the protagonist's finisher")
	var player_ids: Array[String] = []
	for command in _battle._ally_action_commands(_battle._allies[0]):
		player_ids.append(str(command.get("id", "")))
	_check(player_ids.has("finisher") and player_ids.has("spare"),
		"protagonist finisher/spare behavior must remain intact")
	primary["hp"] = old_hp
	_battle.enemy["can_spare"] = old_can_spare
	_battle.exposed_turns = old_exposed
	_battle.finisher_used = old_finisher

	var old_speed := int(companion.get("speed", 0))
	var old_failures: int = int(_battle.flee_failed_count)
	_battle.flee_failed_count = 0
	companion["speed"] = 2
	var slow_chance: float = float(_battle._flee_chance(companion))
	companion["speed"] = 18
	var fast_chance: float = float(_battle._flee_chance(companion))
	_check(fast_chance > slow_chance,
		"companion flee chance must use the acting companion's effective speed")
	companion["speed"] = old_speed
	_battle.flee_failed_count = old_failures
	print("[PartySmoke] companion Item/Flee/Spare command access OK")


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


func _assert_enemy_skill_system() -> void:
	# Catalog integrity: 29 enemy skills, ids disjoint from the 31 hero/companion
	# ids, each with its own 4-frame FX strip.
	_check(GameManager.ENEMY_SKILL_POOL.size() == 29,
		"enemy skill pool must hold the 29-skill catalog")
	for raw_id in GameManager.ENEMY_SKILL_POOL.keys():
		var skill_id := str(raw_id)
		_check(not GameManager.COMPANION_SKILL_POOL.has(skill_id),
			"enemy skill id collides with companion pool: %s" % skill_id)
		var def: Dictionary = GameManager.enemy_skill_def(skill_id)
		var status_id := str(def.get("status", ""))
		if not status_id.is_empty():
			_check(GameManager.STATUS_LIBRARY.has(status_id),
				"enemy skill %s references unknown status %s" % [skill_id, status_id])
		var frames: SpriteFrames = _battle._skill_fx_frames(skill_id)
		_check(frames != null, "missing enemy FX sheet: %s" % skill_id)
		if frames != null and frames.has_animation("fx"):
			_check(frames.get_frame_count("fx") == 4,
				"enemy FX sheet must have 4 frames: %s" % skill_id)

	# Loadout resolution on the live battle: the primary carries the packaged
	# kit (with the Vietnamese telegraph override), echoes shed hard control.
	var primary: Dictionary = _battle._foes[0]
	_check(bool(primary.get("has_catalog_loadout", false)),
		"primary foe must detect the packaged skill_loadout")
	var primary_ids: Array[String] = []
	for skill in primary.get("catalog_skills", []) as Array:
		primary_ids.append(str((skill as Dictionary).get("id", "")))
		if str((skill as Dictionary).get("id", "")) == "venom_spit":
			_check(str((skill as Dictionary).get("telegraph", "")).begins_with("Nọc độc"),
				"backend Vietnamese telegraph must override the EN default")
	_check(primary_ids == ["venom_spit", "bone_ward", "frost_grasp"],
		"primary foe must resolve every packaged catalog id in order")
	var echo: Dictionary = _battle._foes[1]
	var echo_ids: Array[String] = []
	for skill in echo.get("catalog_skills", []) as Array:
		echo_ids.append(str((skill as Dictionary).get("id", "")))
	_check(not echo_ids.has("frost_grasp"),
		"echo reinforcements must shed hard-CC skills")
	_check(echo_ids.has("venom_spit"),
		"echo reinforcements keep the non-CC kit")

	# Intent AI: silence strips down to the basic attack; a kit fully on
	# cooldown also falls back to the basic attack.
	var intent: Dictionary = _battle._pick_catalog_intent(primary)
	_check(intent.has("effect"), "catalog intent must be an effect-shaped skill")
	var ready: Dictionary = primary.get("skill_ready_round", {}) as Dictionary
	for skill_id in primary_ids:
		ready[skill_id] = _battle._round_serial + 3
	var cooled: Dictionary = _battle._pick_catalog_intent(primary)
	_check(str(cooled.get("id", "x")) == "" and str(cooled.get("name")) == "Attack",
		"a kit fully on cooldown must fall back to the basic attack")
	ready.clear()
	_battle._apply_status(primary, "silence")
	var silenced: Dictionary = _battle._pick_catalog_intent(primary)
	_check(str(silenced.get("name")) == "Attack", "silence must strip catalog skills")
	_battle._remove_status(primary, "silence")

	# Support targeting helpers.
	var wounded: Dictionary = _battle._most_wounded_foe_ally(primary)
	_check(wounded.is_empty(), "an unhurt pack has no heal target")
	echo["hp"] = int(int(echo["max_hp"]) * 0.3)
	wounded = _battle._most_wounded_foe_ally(primary)
	_check(str(wounded.get("id", "")) == str(echo.get("id", "")),
		"the most wounded packmate must be the heal target")
	echo["hp"] = int(echo["max_hp"])
	var open_victim: Dictionary = _battle._victim_without_status("poison")
	_check(not open_victim.is_empty(), "hexes must find an unafflicted party member")

	# The stamped status banner is fire-and-forget and must survive headless.
	_battle._announce_status_applied(_battle._allies[0], true, "poison")
	_check(_battle.STATUS_STAMP_VI.size() == GameManager.STATUS_LIBRARY.size(),
		"every catalog status needs a Vietnamese stamp")
	for status_id in GameManager.STATUS_LIBRARY.keys():
		_check(_battle.STATUS_FX_COLORS.has(str(status_id)),
			"every catalog status needs a signature FX color: %s" % status_id)
	print("[PartySmoke] enemy skill system OK — loadout, intent AI, echo CC-strip, stamps")


func _assert_escort_battle_contract(base_enemy: Dictionary) -> void:
	const ESCORT_ID := "escort_smoke_ansel"
	var started: bool = PartyManager.start_escort(ESCORT_ID, {
		"npc_id": ESCORT_ID,
		"name": "Ansel Smoke",
		"battle_mode": "protected",
		"can_act": false,
		"hp_mode": "player_max_snapshot",
	})
	_check(started, "dev escort must activate through PartyManager")
	if not started:
		return

	var snapshot_max := int(GameManager.player_battle_stats().get("max_hp", 1))
	_check(PartyManager.escort_max_hp(ESCORT_ID) == snapshot_max,
		"escort max HP must snapshot the player's current battle max")
	PartyManager.set_escort_hp(ESCORT_ID, snapshot_max - 7)

	var probe := BattleSceneScript.new()
	add_child(probe)
	probe.enemy = base_enemy.duplicate(true)
	probe.enemy["dialogue"] = {}
	probe.enemy_id = "escort_contract_probe"
	probe.player_stats = GameManager.player_battle_stats()
	probe._build_allies()
	probe._build_foes()

	var escort: Dictionary = {}
	var escort_index := -1
	for index in range(probe._allies.size()):
		if str(probe._allies[index].get("id", "")) == ESCORT_ID:
			escort = probe._allies[index]
			escort_index = index
			break
	_check(not escort.is_empty(), "active escort must enter the ally card/target lane")
	if escort.is_empty():
		PartyManager.end_escort(ESCORT_ID)
		probe.queue_free()
		return

	_check(str(escort.get("kind", "")) == "escort", "escort actor kind must stay distinct")
	_check(int(escort.get("max_hp", 0)) == snapshot_max,
		"battle actor must preserve PartyManager's max-HP snapshot")
	_check(probe._ally_hp(escort) == snapshot_max - 7,
		"escort current HP must persist into battle")
	_check(not bool(escort.get("can_act", true)) and int(escort.get("sp_max", -1)) == 0,
		"escort must have no turn or SP pool")
	_check((escort.get("skills", []) as Array).is_empty()
		and probe._ally_action_commands(escort).is_empty(),
		"escort must expose neither skills nor action commands")
	_check(probe._combat_ally_roster_size() == 3,
		"escort must not increase the three-combatant roster")
	_check(probe._targetable_allies().has(escort_index),
		"standing escort must remain targetable")
	_check(not probe._living_combat_allies().has(escort_index),
		"escort must not count as a living combatant")
	_check(probe._foes.size() == 3,
		"escort must not add a reinforcement beyond the combat roster")

	var queue: Array[Dictionary] = probe._build_round_queue()
	var ally_turns := 0
	var escort_turn_found := false
	for entry in queue:
		if str(entry.get("side", "")) != "ally":
			continue
		ally_turns += 1
		if int(entry.get("index", -1)) == escort_index:
			escort_turn_found = true
	_check(ally_turns == 3 and not escort_turn_found,
		"initiative must contain combatants only, never the escort")

	var boss_data := base_enemy.duplicate(true)
	boss_data["rank"] = "boss"
	var base_hp := int((boss_data.get("stats", {}) as Dictionary).get("max_hp", 1))
	var boss_probe := BattleSceneScript.new()
	boss_probe.enemy = boss_data
	boss_probe.enemy_id = "escort_contract_boss"
	boss_probe._allies = probe._allies.duplicate(true)
	boss_probe._build_foes()
	_check(int(boss_probe._foes[0].get("max_hp", 0)) == int(round(base_hp * 2.1)),
		"escort must not increase boss HP scaling")
	_check(int(boss_probe._foes[0].get("actions_per_round", 0)) == 3,
		"escort must not increase boss action scaling")
	boss_probe.free()

	# Give direct heal/shield/status helpers a minimal FX host; this exercises the
	# real persistent HP path without opening a second animated encounter.
	probe._root = Control.new()
	probe.add_child(probe._root)
	probe._fx_layer = Control.new()
	probe._root.add_child(probe._fx_layer)
	probe._heal_raw(escort, true, 3)
	_check(PartyManager.get_escort_hp(ESCORT_ID) == snapshot_max - 4,
		"friendly healing must update persistent escort HP")
	probe._apply_status(escort, "shield", 9.0)
	_check(probe._absorb_with_shields(escort, 7) == 0,
		"escort must receive and consume shield status")
	_check(probe._absorb_with_shields(escort, 5) == 3,
		"escort shield overflow must reach HP normally")

	# Escort KO is terminal for the attempt, unavailable to revive, restores the
	# stored snapshot for retry and runs the exact same XP-losing defeat path.
	(escort["statuses"] as Array).clear()
	PartyManager.set_escort_hp(ESCORT_ID, 0)
	escort["downed"] = true
	var revive_target: int = await probe._pick_ally_target(true)
	_check(revive_target == -1, "escort KO must not be a valid revive target")
	PartyManager.set_escort_hp(ESCORT_ID, 1)
	escort["downed"] = false
	probe._apply_status(escort, "poison")
	var old_xp := GameManager.player_xp
	GameManager.player_xp = 19
	probe._round_serial += 1
	await probe._tick_escort_statuses_for_round()
	_check(probe.failure_reason == "escort_ko"
		and probe._pending_finish_result == "defeat",
		"escort KO must enter the normal defeat/respawn result")
	_check(GameManager.player_xp == int(19 * 0.75),
		"escort defeat must apply the normal player XP penalty")
	_check(PartyManager.get_escort_hp(ESCORT_ID) == snapshot_max
		and not bool(escort.get("downed", true)),
		"escort defeat must restore snapshot HP for retry")

	# An ordinary player defeat must reset active escorts too, even when the
	# protected actor was still standing when the battle ended.
	var normal_defeat_probe := BattleSceneScript.new()
	add_child(normal_defeat_probe)
	normal_defeat_probe.enemy = base_enemy.duplicate(true)
	normal_defeat_probe.enemy["dialogue"] = {}
	normal_defeat_probe.enemy_id = "escort_normal_defeat_probe"
	normal_defeat_probe.player_stats = GameManager.player_battle_stats()
	normal_defeat_probe._build_allies()
	normal_defeat_probe._root = Control.new()
	normal_defeat_probe.add_child(normal_defeat_probe._root)
	PartyManager.set_escort_hp(ESCORT_ID, 1)
	GameManager.player_xp = 19
	await normal_defeat_probe._defeat()
	_check(normal_defeat_probe.failure_reason.is_empty()
		and normal_defeat_probe._pending_finish_result == "defeat",
		"ordinary player KO must retain the ordinary defeat reason/result")
	_check(GameManager.player_xp == int(19 * 0.75),
		"ordinary player KO must keep applying the normal XP penalty")
	_check(PartyManager.get_escort_hp(ESCORT_ID) == snapshot_max,
		"ordinary player defeat must also restore active escort HP")
	normal_defeat_probe.queue_free()
	GameManager.player_xp = old_xp

	PartyManager.end_escort(ESCORT_ID)
	probe.queue_free()
	print("[PartySmoke] escort battle contract OK — targetable, inert, scaled out, defeat-linked")


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
	if _frames >= MAX_AUTOMATION_FRAMES:
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
