extends SceneTree
## Headless runtime check for the XP / level / talk-XP / companion progression logic.
## Run:  Godot --headless --path GameV1 -s res://scripts/dev/ProgressionSmoke.gd
## Exercises GameManager in isolation (no other autoloads needed): the party bonus
## simply sees an empty party, which is exactly the "solo protagonist" baseline.

var _failures: int = 0


func _init() -> void:
	var gm: Node = load("res://autoloads/GameManager.gd").new()
	get_root().add_child(gm)

	_test_level_curve(gm)
	_test_skill_unlocks(gm)
	_test_talk_xp(gm)
	_test_companion_progression(gm)
	_test_party_bonus_default(gm)
	_test_serialize_roundtrip(gm)

	if _failures == 0:
		print("\n[ProgressionSmoke] ALL TESTS PASSED ✅")
	else:
		print("\n[ProgressionSmoke] %d ASSERTION(S) FAILED ❌" % _failures)
	quit(_failures)


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  ok  - %s" % label)
	else:
		_failures += 1
		print("  FAIL- %s" % label)


func _test_level_curve(gm: Node) -> void:
	print("[level curve]")
	gm.reset_combat_progress()
	_ok(gm.player_level == 1 and gm.player_xp == 0, "starts at level 1")
	_ok(gm.xp_to_next_level_for(1) == 30, "xp_to_next(1) == 30")
	var levels: int = gm.gain_xp(30)
	_ok(levels == 1 and gm.player_level == 2, "30 XP -> level 2")
	gm.reset_combat_progress()
	# 180 total XP should reach level 4 (cumulative curve 15*L*(L-1)).
	gm.gain_xp(180)
	_ok(gm.player_level == 4, "180 XP -> level 4 (got %d)" % gm.player_level)


func _test_skill_unlocks(gm: Node) -> void:
	print("[skills]")
	gm.reset_combat_progress()
	var ids1: Array = _skill_ids(gm.player_skills())
	_ok(ids1.has("strike") and ids1.has("power_strike"), "level 1 has strike + power_strike")
	_ok(not ids1.has("focus"), "level 1 lacks focus")
	gm.player_level = 3
	_ok(_skill_ids(gm.player_skills()).has("focus"), "level 3 unlocks focus")
	gm.player_level = 6
	var ids6: Array = _skill_ids(gm.player_skills())
	_ok(ids6.has("ember_slash") and not ids6.has("crush"), "level 6 (ch1 boss) unlocks ember_slash, not crush yet")
	_ok(not gm.locked_skills().is_empty(), "the roster must NOT be maxed out by chapter 1 (level 6)")
	gm.player_level = 9
	_ok(_skill_ids(gm.player_skills()).has("crush"), "level 9 (ch2 boss) unlocks crush")
	gm.player_level = 12
	_ok(_skill_ids(gm.player_skills()).has("mend"), "level 12 (ch3 boss) unlocks mend")
	gm.player_level = 15
	_ok(_skill_ids(gm.player_skills()).has("tempest"), "level 15 (ch4 boss) unlocks tempest")
	gm.player_level = 18
	var ids18: Array = _skill_ids(gm.player_skills())
	_ok(ids18.has("pierce"), "level 18 (ch5 boss / final) unlocks pierce")
	_ok(gm.locked_skills().is_empty(), "the full roster is unlocked by the true final boss level (18)")


func _skill_ids(skills: Array) -> Array:
	var out: Array = []
	for s in skills:
		out.append(str((s as Dictionary).get("id", "")))
	return out


func _test_talk_xp(gm: Node) -> void:
	print("[talk XP]")
	gm.reset_combat_progress()
	var before: int = gm.player_xp
	var r1: Dictionary = gm.award_talk_xp("npc_1", "s:beat_1", "quest")
	_ok(bool(r1.get("awarded")) and int(r1.get("amount")) == gm.TALK_XP_QUEST, "quest beat awards TALK_XP_QUEST")
	_ok(gm.player_xp == before + gm.TALK_XP_QUEST, "quest talk XP applied to player")
	var r2: Dictionary = gm.award_talk_xp("npc_1", "s:beat_1", "quest")
	_ok(not bool(r2.get("awarded")), "same node does NOT award twice (history remembered)")
	var r3: Dictionary = gm.award_talk_xp("npc_1", "w:lore_1", "world")
	_ok(bool(r3.get("awarded")) and int(r3.get("amount")) == gm.TALK_XP_WORLD, "world lore awards TALK_XP_WORLD")
	_ok(gm.TALK_XP_QUEST != gm.TALK_XP_WORLD, "quest and world talk XP are different amounts")
	_ok(gm.has_logged_talk("npc_1", "w:lore_1"), "talk log records the awarded node")


func _test_companion_progression(gm: Node) -> void:
	print("[companions]")
	gm.reset_combat_progress()
	gm.player_level = 3
	var data: Dictionary = gm.ensure_companion("arlo")
	_ok(int(data.get("level")) == 2, "new companion starts near the player (level 2)")
	var leveled: Array = [0]
	gm.companion_leveled.connect(func(_id: String, _lv: int) -> void: leveled[0] += 1)
	# Enough XP to definitely push arlo up at least one level.
	var gained: int = gm.gain_companion_xp("arlo", 500)
	_ok(gained >= 1 and int(leveled[0]) >= 1, "companion levels up and emits companion_leveled")
	_ok(gm.companion_level("arlo") == 2 + gained, "companion level advanced by the number gained")


func _test_party_bonus_default(gm: Node) -> void:
	print("[party bonus baseline]")
	var bonus: Dictionary = gm.party_passive_bonus()
	_ok(abs(float(bonus.get("attack_mult")) - 1.0) < 0.001, "solo attack_mult == 1.0")
	_ok(int(bonus.get("regen")) == 0, "solo regen == 0")
	var stats: Dictionary = gm.player_battle_stats()
	_ok(stats.has("party_regen") and stats.has("party_xp_mult"), "battle stats expose party fields")


func _test_serialize_roundtrip(gm: Node) -> void:
	print("[serialize roundtrip]")
	gm.reset_combat_progress()
	gm.player_level = 5
	gm.player_xp = 42
	gm.mark_enemy_defeated("enemy_x")
	gm.ensure_companion("arlo")
	gm.gain_companion_xp("arlo", 10)
	gm.award_talk_xp("npc_2", "w:topic", "world")  # nudges player_xp up by TALK_XP_WORLD
	var expect_level: int = gm.player_level
	var expect_xp: int = gm.player_xp
	var snapshot: Dictionary = gm.serialize_progress()

	var gm2: Node = load("res://autoloads/GameManager.gd").new()
	get_root().add_child(gm2)
	gm2.apply_progress(snapshot)
	_ok(gm2.player_level == expect_level and gm2.player_xp == expect_xp, "player level/xp restored")
	_ok(gm2.defeated_enemy_ids.has("enemy_x"), "defeated enemies restored")
	_ok(gm2.companion_level("arlo") == gm.companion_level("arlo"), "companion progress restored")
	_ok(gm2.has_logged_talk("npc_2", "w:topic"), "talk history restored")
	gm2.queue_free()
