extends Node2D
## Manual battle sandbox for checking menu visuals and input without auto-play.

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const MainScript := preload("res://scripts/world/Main.gd")
const SAMPLE_ITEM_ICONS := preload("res://assets/ui/inventory/sample_icon_sheet.png")

var _battle: CanvasLayer


func _ready() -> void:
	GameManager.reset_combat_progress()
	GameManager.player_level = 18
	GameManager.player_xp = 0
	GameManager.player_hp = -1

	PartyManager.companions.clear()
	PartyManager.active_members.clear()
	PartyManager.companions["sandbox_mira"] = {
		"npc_id": "sandbox_mira",
		"name": "Mira",
		"combat_role": "support",
		"skills": ["quicksilver", "purify", "stone_ward", "guiding_star"],
	}
	PartyManager.active_members["sandbox_mira"] = true
	GameManager.ensure_companion("sandbox_mira")["level"] = 10
	GameManager.ensure_companion("sandbox_mira")["xp"] = 0
	GameManager.ensure_companion("sandbox_mira")["hp"] = -1

	InventoryManager.reset()
	InventoryManager.load_chapter_catalog({
		"items": [
			{"id": "sandbox_potion", "name": "Potion", "kind": "heal", "power": 80,
				"desc": "Restore HP to an ally.", "icon_index": 0},
			{"id": "sandbox_ether", "name": "Ether", "kind": "energy", "power": 3,
				"desc": "Restore SP to an ally.", "icon_index": 1},
			{"id": "sandbox_tonic", "name": "Focus Tonic", "kind": "buff", "power": 0,
				"desc": "Empower the next attack.", "icon_index": 2},
		],
		"icon_grid": 3,
		"icon_cell_px": 96,
	}, SAMPLE_ITEM_ICONS)
	InventoryManager.add_item("sandbox_potion", 5, true)
	InventoryManager.add_item("sandbox_ether", 5, true)
	InventoryManager.add_item("sandbox_tonic", 5, true)

	_open_battle()
	if OS.get_environment("BATTLE_SANDBOX_FX_QA") == "1":
		_capture_attack_fx.call_deferred()
	elif OS.get_environment("BATTLE_SANDBOX_LAYOUT_QA") == "1":
		_capture_command_layout.call_deferred()


func _open_battle() -> void:
	var main_helper := MainScript.new()
	var enemy_data: Dictionary = main_helper._fallback_enemy(
		"sandbox_echo", "Training Echo", "elite", 8, true, Vector2i(3, 3)
	)
	main_helper.free()

	_battle = BattleSceneScript.new()
	add_child(_battle)
	_battle.battle_finished.connect(_on_battle_finished)
	_battle.open(enemy_data)
	print("[BattleSandbox] Ready. Test Attack, Skill, Probe, Item, Guard and companion skills.")


func _on_battle_finished(_result: String, _enemy_id: String) -> void:
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree():
		_open_battle()


## Optional visual-regression capture; the normal manual sandbox remains idle.
func _capture_command_layout() -> void:
	if not await _wait_for_ui_mode(3): # BattleScene.UiMode.MENU
		push_error("[BattleSandbox] initial command menu did not open")
		get_tree().quit(1)
		return
	# Target-layout captures should not be covered by a concurrent intro bark.
	_battle._shutdown_enemy_barks()
	await get_tree().process_frame
	await get_tree().create_timer(0.22).timeout
	_print_command_geometry("main")
	_save_viewport("/tmp/battle_command_main_layout.png")

	# Attack starts focused on the first of two living foes.
	_press("ui_accept")
	if await _wait_for_ui_mode(4): # BattleScene.UiMode.TARGET
		await get_tree().create_timer(0.22).timeout
		_print_target_geometry()
		_save_viewport("/tmp/battle_target_layout.png")
	_press("ui_cancel")
	await get_tree().process_frame
	await _wait_for_menu_count(6)

	# Skill menu (nine fixed-size command cards).
	_press("ui_right")
	_press("ui_accept")
	await get_tree().process_frame
	await _wait_for_menu_count(9)
	await get_tree().create_timer(0.22).timeout
	_print_command_geometry("skill")
	_save_viewport("/tmp/battle_command_skill_layout.png")

	# Back is the last skill card; return to the action menu, then open Item.
	_press("ui_left")
	_press("ui_accept")
	await get_tree().process_frame
	await _wait_for_menu_count(6)
	for step in range(3):
		_press("ui_right")
		await get_tree().process_frame
	_press("ui_accept")
	await get_tree().process_frame
	await _wait_for_menu_count(4)
	await get_tree().create_timer(0.22).timeout
	_assert_item_menu_catalog_data()
	_print_command_geometry("item")
	_save_viewport("/tmp/battle_command_item_layout.png")
	print("[BattleSandbox] Target, command and item layout QA captured.")
	_battle.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## Captures the largest authored frame of a representative offensive skill at
## its real ally-to-foe display scale. This keeps impact sizing reviewable
## without automating an entire turn through the command picker.
func _capture_attack_fx() -> void:
	if not await _wait_for_ui_mode(3): # BattleScene.UiMode.MENU
		push_error("[BattleSandbox] initial command menu did not open")
		get_tree().quit(1)
		return
	_battle._shutdown_enemy_barks()
	var foe: Dictionary = _battle._foes[0]
	var impact_position: Vector2 = _battle._foe_center(foe)
	_battle._play_ally_attack_fx("power_strike", impact_position)
	_battle._spawn_slash(impact_position, Color(1.0, 0.85, 0.45), 1.4375)
	await get_tree().create_timer(0.13).timeout
	_save_viewport("/tmp/battle_attack_fx_layout.png")
	print("[BattleSandbox] Offensive FX scale QA captured.")
	_battle.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _wait_for_ui_mode(expected_mode: int, timeout_ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _battle != null and is_instance_valid(_battle) \
				and int(_battle._ui_mode) == expected_mode:
			return true
		await get_tree().process_frame
	return false


func _wait_for_menu_count(expected_count: int, timeout_ms: int = 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _battle != null and is_instance_valid(_battle) \
				and int(_battle._ui_mode) == 3 \
				and _battle._command_menu._ids.size() == expected_count:
			return true
		await get_tree().process_frame
	return false


func _save_viewport(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)


func _print_command_geometry(label: String) -> void:
	var menu: BattleCommandMenu = _battle._command_menu
	var row: HBoxContainer = menu._row
	var first: Control = menu._items[0] if not menu._items.is_empty() else null
	var frame: Control = first.get_meta("frame_selected") as Control if first != null else null
	var content_width := 0.0
	if not menu._items.is_empty():
		var last: Control = menu._items[-1]
		content_width = last.position.x + last.size.x
	print("[BattleSandbox] %s menu=%s row=%s first=%s frame=%s content_center=%.1f" % [
		label,
		Rect2(menu.position, menu.size),
		Rect2(row.position, row.size),
		Rect2(first.position, first.size) if first != null else Rect2(),
		Rect2(frame.position, frame.size) if frame != null else Rect2(),
		menu.position.x + row.position.x + content_width * 0.5,
	])


func _print_target_geometry() -> void:
	for index in range(_battle._foes.size()):
		var ui: Dictionary = _battle._foe_ui(_battle._foes[index])
		var target_visual: EnemyTargetHighlight = ui["target_visual"]
		var identity: EnemyIdentityPlate = ui["identity_root"]
		print("[BattleSandbox] target[%d] selected=%s marker=%s hp_y=%.1f name_y=%.1f" % [
			index,
			target_visual.is_selected(),
			target_visual.marker_bounds(),
			float(ui["hp_y"]),
			identity.nameplate_bounds().position.y,
		])


func _assert_item_menu_catalog_data() -> void:
	var usable: Array[Dictionary] = InventoryManager.usable_in_battle()
	assert(not usable.is_empty(), "sandbox needs a usable item")
	var expected: Texture2D = InventoryManager.icon_for(usable[0])
	var actual: Texture2D = _battle._command_menu._items[0].get_meta(
		"icon_texture", null) as Texture2D
	assert(expected is AtlasTexture and actual is AtlasTexture,
		"item command card must use the catalog AtlasTexture")
	assert((actual as AtlasTexture).atlas == (expected as AtlasTexture).atlas,
		"item command card must use the catalog icon sheet")
	assert((actual as AtlasTexture).region == (expected as AtlasTexture).region,
		"item command card must use the item's own atlas region")
	assert(_battle._command_menu._descs[0] == "Restore 80 HP to one ally.",
		"item readout must show mechanics instead of flavor description")
	print("[BattleSandbox] item catalog icon + effect copy OK")


func _press(action: String) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
