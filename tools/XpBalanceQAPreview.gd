extends Node
## Scripted QA for the level-gap XP governor: drives the REAL GameManager.
## xp_gap_factor / award_talk_xp / BattleScene._scaled_battle_xp and
## ChapterFlow.expected_level_here / current_zone_distance (not
## reimplementations) against a synthetic chapter flow, then replays chapter
## 1's REAL measured dialogue-node counts to prove a diligent talker
## converges near the boss's level instead of hitting L20+.

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")


func _ready() -> void:
	# ── gap-factor table (must mirror enemy_balance.xp_gap_factor exactly) ──────
	GameManager.reset_combat_progress()
	GameManager.player_level = 3
	assert(GameManager.xp_gap_factor(5) == 1.25, "2+ below content -> catch-up 1.25")
	GameManager.player_level = 5
	assert(GameManager.xp_gap_factor(5) == 1.0, "on-level -> 1.0")
	GameManager.player_level = 6
	assert(GameManager.xp_gap_factor(5) == 0.7, "+1 over -> 0.7")
	GameManager.player_level = 7
	assert(GameManager.xp_gap_factor(5) == 0.45, "+2 over -> 0.45")
	GameManager.player_level = 8
	assert(GameManager.xp_gap_factor(5) == 0.25, "+3 over -> 0.25")
	GameManager.player_level = 12
	assert(GameManager.xp_gap_factor(5) == 0.1, "+4 or more -> floor 0.1")
	assert(GameManager.xp_gap_factor(0) == GameManager.xp_gap_factor(1), "reference floors at 1")
	print("[XpBalanceQA] OK: xp_gap_factor mirrors enemy_balance.py's table")

	# ── ChapterFlow zone-distance BFS + expected level ──────────────────────────
	ChapterFlow.flow = {"chapters": [{
		"chapter": 1,
		"zones": [
			{"zone_id": "z1", "connections": ["z2"]},
			{"zone_id": "z2", "connections": ["z1", "z3", "z_secret"]},
			{"zone_id": "z_secret", "connections": ["z2"]},
			{"zone_id": "z3", "connections": ["z2", "z4"]},
			{"zone_id": "z4", "connections": ["z3"]},
		],
	}]}
	ChapterFlow.chapter_index = 0
	var expected_by_zone := {"z1": 1, "z2": 2, "z_secret": 3, "z3": 3, "z4": 4}
	var distance_by_zone := {"z1": 0, "z2": 1, "z_secret": 2, "z3": 2, "z4": 3}
	for zone_index in range(5):
		ChapterFlow.zone_index = zone_index
		var zid := str(ChapterFlow.current_zone().get("zone_id"))
		assert(ChapterFlow.current_zone_distance() == int(distance_by_zone[zid]),
			"BFS distance for %s: expected %d got %d" % [zid, int(distance_by_zone[zid]), ChapterFlow.current_zone_distance()])
		assert(ChapterFlow.expected_level_here() == int(expected_by_zone[zid]),
			"expected level for %s" % zid)
	print("[XpBalanceQA] OK: current_zone_distance BFS + expected_level_here match enemy_balance anchors")

	# Chapter 2 entrance: expected = 1 + 3 = 4 (chapter step mirrors CHAPTER_LEVEL_STEP).
	ChapterFlow.flow = {"chapters": [{"chapter": 2, "zones": [{"zone_id": "c2z1", "connections": []}]}]}
	ChapterFlow.chapter_index = 0
	ChapterFlow.zone_index = 0
	assert(ChapterFlow.expected_level_here() == 4, "chapter 2 entrance expects level 4")
	print("[XpBalanceQA] OK: chapter step (+3/chapter) mirrored")

	# ── award_talk_xp applies the governor (real call path) ─────────────────────
	ChapterFlow.flow = {"chapters": [{"chapter": 1, "zones": [{"zone_id": "z1", "connections": []}]}]}
	ChapterFlow.chapter_index = 0
	ChapterFlow.zone_index = 0
	GameManager.reset_combat_progress()
	var res1: Dictionary = GameManager.award_talk_xp("npc_a", "n1", "quest")
	assert(bool(res1.get("awarded")) and int(res1.get("amount")) == 14,
		"on-level quest talk pays full 14, got %s" % str(res1))
	var res_dup: Dictionary = GameManager.award_talk_xp("npc_a", "n1", "quest")
	assert(not bool(res_dup.get("awarded")), "dedup ledger still blocks repeat nodes")
	GameManager.player_level = 8  # 7 over the zone's expected level 1
	var res2: Dictionary = GameManager.award_talk_xp("npc_a", "n2", "quest")
	assert(int(res2.get("amount")) == 1, "far over-leveled quest talk decays to the 1-XP floor, got %s" % str(res2))
	var res3: Dictionary = GameManager.award_talk_xp("npc_a", "n3", "world")
	assert(int(res3.get("amount")) == 1, "world talk floors at 1 XP, never 0")
	print("[XpBalanceQA] OK: award_talk_xp scales by the governor and floors at 1 XP")

	# ── battle XP path (real BattleScene._scaled_battle_xp) ─────────────────────
	var battle := BattleSceneScript.new()
	battle.enemy = {"level": 3, "xp_reward": 45}
	GameManager.player_level = 3
	assert(battle._scaled_battle_xp(45) == 45, "on-level enemy pays full reward")
	GameManager.player_level = 5
	assert(battle._scaled_battle_xp(45) == 20, "+2 over the enemy -> 45*0.45 = 20")
	GameManager.player_level = 12
	assert(battle._scaled_battle_xp(45) == 5, "far over-leveled grinding -> 45*0.1 = 5")
	GameManager.player_level = 1
	assert(battle._scaled_battle_xp(45) == 56, "2 below the enemy -> catch-up 45*1.25 = 56")
	battle.enemy = {}  # legacy enemy with no level -> falls back to the zone anchor
	GameManager.player_level = 1
	assert(battle._scaled_battle_xp(30) == 30, "no enemy level -> zone anchor keeps full value at L1")
	battle.free()
	print("[XpBalanceQA] OK: battle XP scales by enemy level (with zone-anchor fallback)")

	# ── full chapter-1 replay with REAL measured node counts ────────────────────
	# (zone_id -> quest@14 / world@7 node counts from run 20260629_143055)
	ChapterFlow.flow = {"chapters": [{
		"chapter": 1,
		"zones": [
			{"zone_id": "z1", "connections": ["z2"], "q": 30, "w": 112},
			{"zone_id": "z2", "connections": ["z1", "zs", "z3"], "q": 58, "w": 139},
			{"zone_id": "zs", "connections": ["z2"], "q": 10, "w": 40},
			{"zone_id": "z3", "connections": ["z2", "z4"], "q": 3, "w": 55},
			{"zone_id": "z4", "connections": ["z3", "z5"], "q": 51, "w": 72},
			{"zone_id": "z5", "connections": ["z4"], "q": 44, "w": 64},
		],
	}]}
	ChapterFlow.chapter_index = 0
	GameManager.reset_combat_progress()
	var node_counter := 0
	for zone_index in range(6):
		ChapterFlow.zone_index = zone_index
		var zone: Dictionary = ChapterFlow.current_zone()
		for i in range(int(zone.get("q", 0))):
			node_counter += 1
			GameManager.award_talk_xp("npc_sim", "q%d" % node_counter, "quest")
		for i in range(int(zone.get("w", 0))):
			node_counter += 1
			GameManager.award_talk_xp("npc_sim", "w%d" % node_counter, "world")
	var final_level := GameManager.player_level
	print("[XpBalanceQA] diligent talker after ALL %d chapter-1 nodes -> level %d" % [node_counter, final_level])
	assert(final_level >= 6 and final_level <= 9,
		"diligent talker must land in the boss's challenge band (6-9), got %d" % final_level)
	print("[XpBalanceQA] OK: full-talk chapter 1 converges to L%d (boss is L6) instead of L20+" % final_level)

	print("[XpBalanceQA] ALL CHECKS PASSED")
	get_tree().quit()
