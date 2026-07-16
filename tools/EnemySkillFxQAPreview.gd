extends Node2D
## Visual QA for the enemy-skill system + AAA hit feedback. Opens a real
## BattleScene against a foe carrying a catalog loadout, then drives specific
## catalog skills DIRECTLY (fire-and-forget coroutine calls — the established
## BattleScene QA pattern) and screenshots the key beats:
##   1_menu          battle settled at the command menu
##   2_venom_hit     venom_spit landing (skill FX + vignette + card punch)
##   3_poison_stamp  the "TRÚNG ĐỘC!" stamp + poisoned portrait tint
##   4_poison_tick   DoT tick (green vignette breath + bubbles)
##   5_quake_aoe     quake_stomp wind-up → whole-party hit
## Run WINDOWED (screenshots need a real viewport):
##   Godot --path GameV1 res://tools/EnemySkillFxQAPreview.tscn
## Shots land in /tmp/enemy_skill_qa/.

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const MainScript := preload("res://scripts/world/Main.gd")

const OUT_DIR := "/tmp/enemy_skill_qa"

var _battle: CanvasLayer = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameManager.reset_combat_progress()
	PartyManager.companions["comp_tank"] = {
		"npc_id": "comp_tank", "name": "Thorn", "combat_role": "tank",
		"skills": ["taunt", "shield_bash", "stone_ward", "iron_bastion"],
	}
	PartyManager.active_members["comp_tank"] = true
	GameManager.ensure_companion("comp_tank")["level"] = 3

	var main_helper := MainScript.new()
	var enemy_data: Dictionary = main_helper._fallback_enemy(
		"qa_venom_stalker", "Mire Stalker", "elite", 3, true, Vector2i(3, 3)
	)
	main_helper.free()
	enemy_data["name"] = "Mire Stalker"
	enemy_data["skill_loadout"] = {
		"skill_ids": ["venom_spit", "quake_stomp", "bone_ward"],
		"telegraphs": {
			"venom_spit": "Nọc độc sủi bọt giữa hai hàm răng của nó...",
			"quake_stomp": "Nó giậm mạnh — mặt đất rung chuyển dữ dội!",
		},
		"source": "llm",
	}
	_battle = BattleSceneScript.new()
	add_child(_battle)
	_battle.open(enemy_data)
	_run_qa.call_deferred()


func _run_qa() -> void:
	# Let the intro animation land and the menu settle.
	await _wait(2.6)
	await _shot("1_menu")

	var foe: Dictionary = _battle._foes[0]
	var venom: Dictionary = GameManager.enemy_skill_def("venom_spit")
	venom["id"] = "venom_spit"
	venom["status_chance"] = 1.0
	venom["telegraph"] = "Nọc độc sủi bọt giữa hai hàm răng của nó..."
	_battle._foe_use_catalog_skill(foe, venom)
	await _wait(0.9)
	await _shot("2_venom_hit")
	await _wait(0.7)
	await _shot("3_poison_stamp")

	# Force a poison tick on the protagonist for the DoT feedback beat.
	if _battle._find_status(_battle._allies[0], "poison").is_empty():
		_battle._apply_status(_battle._allies[0], "poison")
	_battle._refresh_all_panels()
	_battle._tick_statuses(_battle._allies[0], true)
	await _wait(0.35)
	await _shot("4_poison_tick")
	await _wait(1.2)

	var quake: Dictionary = GameManager.enemy_skill_def("quake_stomp")
	quake["id"] = "quake_stomp"
	quake["telegraph"] = "Nó giậm mạnh — mặt đất rung chuyển dữ dội!"
	_battle._foe_use_catalog_skill(foe, quake)
	await _wait(1.5)
	await _shot("5_quake_aoe")

	print("[EnemySkillFxQA] shots saved to %s" % OUT_DIR)
	await _wait(0.4)
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/%s.png" % [OUT_DIR, label])
		print("[EnemySkillFxQA] shot %s" % label)
