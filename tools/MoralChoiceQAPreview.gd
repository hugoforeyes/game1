extends Node
## MoralChoiceQAPreview — drives the REAL moral-choice ceremony end to end:
## synthetic quest -> notify_npc_talked -> pending-choice fallback opens the
## ceremony -> real InputEventKey presses arm + confirm option A -> the reveal
## phase shows -> every consequence (xp loss, hp %, item taken, relationship,
## enemy-level mod, flags) is asserted against the live autoloads, plus the
## battle scaling mirror, PartyManager force join/leave, and the
## relationship hint-lock rewrite in DialogueAssembler.
##
## Run (windowed; saves phase screenshots and quits itself):
##   /Applications/Godot.app/Contents/MacOS/Godot --path GameV1 res://tools/MoralChoiceQAPreview.tscn

const MoralChoiceViewScript := preload("res://scripts/ui/MoralChoiceView.gd")
const ChatBoxScript := preload("res://scripts/ui/ChatBox.gd")  # force-compile the intercept
const DialogueAssemblerScript := preload("res://scripts/ui/DialogueAssembler.gd")
const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")

const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/13b8760e-cdd2-49ba-a5c6-f7d8ea2de458/scratchpad/choice_v2"

var _failures: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame
	await _run()
	if _failures.is_empty():
		print("[QA] ALL PASS")
	else:
		print("[QA] FAILURES: %s" % ", ".join(_failures))
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL %s" % label)


func _key(keycode: Key) -> void:
	# A synthetic key needs BOTH keycode and physical_keycode populated — this
	# codebase checks physical, but built-in ui_* actions match on keycode.
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("  [shot] %s" % file_name)


func _find_ceremony() -> CanvasLayer:
	for child in get_tree().root.get_children():
		if child is CanvasLayer and child.get_script() == MoralChoiceViewScript:
			return child
	return null


func _run() -> void:
	print("[QA] Moral choice ceremony + consequence engine")
	NarrativeState.reset()
	GameManager.player_level = 3
	GameManager.player_xp = 50
	GameManager.player_hp = -1
	InventoryManager.catalog = [{"id": "qa_letter", "name": "Thư Giới Thiệu", "kind": "lore"}]
	InventoryManager.counts = {"qa_letter": 1}

	# ── engine-level: forced party changes ──
	var joined := PartyManager.force_party_change("qa_comp", "join")
	_check(joined and PartyManager.is_member("qa_comp"), "party force join")
	var left := PartyManager.force_party_change("qa_comp", "leave")
	_check(left and not PartyManager.is_member("qa_comp"), "party force leave")

	# ── the quest whose current objective is the moral choice ──
	QuestManager.quests = [{
		"id": "qa_quest", "title": "QA Choice", "type": "main",
		"reward": {"xp": 10},
		"giver": {"mode": "npc", "npc_id": "npc_mira"},
		"objectives": [{
			"id": "o1", "kind": "choice", "zone_id": "qa_zone", "target_npc_id": "npc_mira",
			"prompt": "Lợi dụng bí mật của Mira để ép giá... hay trao đổi công bằng?",
			"options": [
				{
					"id": "a", "label": "Ép buộc",
					"tone_hint": "Nhanh chóng, nhưng tàn nhẫn...",
					"consequence_text": "Tin đồn về sự tàn nhẫn của bạn bắt đầu lan đi...",
					"npc_reaction": "Được. Nhưng đừng bao giờ quay lại đây nữa.",
					"outcome": {
						"xp": -20,
						"hp_percent": -15,
						"take_items": [{"item_id": "qa_letter", "name": "Thư Giới Thiệu"}],
						"relationships": [{"npc_id": "npc_mira", "name": "Mira", "delta": -2}],
						"enemy_level_delta": {"scope": "zone", "delta": 1},
						"set_flags": ["qa_cruel"],
					},
				},
				{
					"id": "b", "label": "Trao đổi công bằng",
					"tone_hint": "Chậm rãi, giữ trọn lòng tin...",
					"consequence_text": "Mira giữ trọn niềm tin nơi bạn.",
					"npc_reaction": "Cảm ơn ngươi. Ta sẽ không quên.",
					"outcome": {"xp": 40, "relationships": [{"npc_id": "npc_mira", "delta": 1}]},
				},
			],
		}],
	}]
	# Mirror what load_chapter_quests seeds: _state_of has no default-create —
	# an unseeded quest reads as {} and can never activate.
	QuestManager.quest_states = {
		"qa_quest": {"state": "inactive", "objective_index": 0, "progress": 0, "choices": {}},
	}
	QuestManager.current_zone_id = "qa_zone"
	# QuestManager._process refuses to pop pending choices until its UI layer
	# exists (normally built when a chapter loads its quests).
	QuestManager._ensure_ui()

	# A prefetched card illustration (what ChapterFlow downloads per option) —
	# the ceremony must mount it into the card window.
	var art_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	art_image.fill(Color(0.2, 0.4, 0.8, 1.0))
	QuestManager.set_choice_illustration("a", ImageTexture.create_from_image(art_image))

	# The real fallback flow: talking to the giver activates the quest and
	# queues the unresolved choice; QuestManager._process opens the ceremony.
	QuestManager.notify_npc_talked("npc_mira")
	var view: CanvasLayer = null
	for _i in range(90):
		await get_tree().process_frame
		view = _find_ceremony()
		if view != null:
			break
	_check(view != null, "ceremony opened from pending choice")
	if view == null:
		return

	await get_tree().create_timer(0.9).timeout  # input grace + dilemma typewriter
	# ── the two-card layout ──
	var cards: Array = view.get("_cards") as Array
	_check(cards.size() == 2, "two option cards built (got %d)" % cards.size())
	var card_a: Dictionary = cards[0] as Dictionary
	_check((card_a.get("image") as TextureRect).texture != null, "prefetched card art mounted on option a")
	_key(KEY_RIGHT)
	await get_tree().process_frame
	_check(int(view.get("_selected")) == 1, "KEY_RIGHT selects card b")
	_key(KEY_LEFT)
	await get_tree().process_frame
	_check(int(view.get("_selected")) == 0, "KEY_LEFT returns to card a")
	await _shot("qa_phase_choice.png")
	_key(KEY_ENTER)  # arm
	await get_tree().create_timer(0.25).timeout
	_key(KEY_ENTER)  # confirm -> resolve option a
	await get_tree().create_timer(1.7).timeout  # reveal + chips pop + DONE phase
	await _shot("qa_phase_reveal.png")

	# ── applied consequences ──
	var result: Dictionary = QuestManager.last_choice_result
	_check(str(result.get("option_id", "")) == "a", "option a resolved")
	_check(NarrativeState.choice_matches({"choice_key": "qa_quest:o1", "option": "a"}), "choice recorded")
	_check(NarrativeState.has_flag("qa_cruel"), "flag set")
	_check(NarrativeState.relationship_with("npc_mira") == -2, "relationship -2")
	_check(NarrativeState.enemy_level_delta_for(0, "qa_zone") == 1, "enemy level mod stored")
	_check(GameManager.player_xp == 40, "xp 50 -20 +10 reward = 40 (got %d)" % GameManager.player_xp)
	var max_hp: int = int(GameManager.player_battle_stats()["max_hp"])
	var expected_hp: int = max_hp - int(round(max_hp * 0.15))
	_check(GameManager.get_player_hp() == expected_hp, "hp -15%% (%d/%d)" % [GameManager.get_player_hp(), max_hp])
	_check(InventoryManager.count_of("qa_letter") == 0, "item taken")
	var chips: Array = result.get("chips", []) as Array
	_check(chips.size() == 5, "5 chips (got %d)" % chips.size())
	_check(str(result.get("npc_reaction", "")).contains("quay lại"), "npc reaction carried")

	# ── persistence roundtrip keeps the enemy mod ──
	var snapshot: Dictionary = NarrativeState.serialize_save()
	NarrativeState.reset()
	_check(NarrativeState.enemy_level_delta_for(0, "qa_zone") == 0, "reset clears enemy mod")
	NarrativeState.apply_save(snapshot)
	_check(NarrativeState.enemy_level_delta_for(0, "qa_zone") == 1, "enemy mod survives save roundtrip")

	# ── battle scaling mirrors enemy_balance ratios ──
	GameManager.imported_scene_context = {"zone_id": "qa_zone"}
	var battle := BattleSceneScript.new()
	add_child(battle)
	var scaled: Dictionary = battle.call("_with_choice_scaling", {
		"id": "qa_enemy", "level": 3,
		"stats": {"max_hp": 72, "attack": 13, "defense": 6, "speed": 9},
	})
	var sstats: Dictionary = scaled.get("stats", {}) as Dictionary
	_check(int(scaled.get("level", 0)) == 4, "enemy level 3->4")
	_check(int(sstats.get("max_hp", 0)) == 86, "hp 72->86 (got %d)" % int(sstats.get("max_hp", 0)))
	_check(int(sstats.get("attack", 0)) == 15, "attack 13->15 (got %d)" % int(sstats.get("attack", 0)))
	_check(int(sstats.get("defense", 0)) == 7, "defense 6->7 (got %d)" % int(sstats.get("defense", 0)))
	_check(int(sstats.get("speed", 0)) == 10, "speed 9->10 (got %d)" % int(sstats.get("speed", 0)))
	battle.queue_free()

	# ── relationship hint-lock rewrites the hint menu into a refusal ──
	QuestManager.quests.append({
		"id": "qa_q2", "title": "QA Hint", "type": "side",
		"giver": {"mode": "npc", "npc_id": "npc_mira"},
		"objectives": [{"id": "o1", "kind": "talk", "zone_id": "qa_zone", "target_npc_id": "npc_mira", "description": "d"}],
	})
	QuestManager.quest_states["qa_q2"] = {"state": "active", "objective_index": 0, "progress": 0, "choices": {}}
	QuestManager.tracked_quest_id = "qa_q2"
	var tree := {
		"start_node": "root",
		"nodes": [{"id": "root", "npc_line": "hi", "options": [{"player_text": "Tạm biệt.", "goto": "__end__"}]}],
	}
	var npc_data := {
		"id": "npc_mira",
		"hint_dialogue": {"options": [{
			"id": "h1", "player_text": "về nhiệm vụ?", "npc_line": "manh mối đây",
			"hint": {"quest_id": "qa_q2", "objective_id": "o1", "level": 1},
		}]},
	}
	var locked: Dictionary = DialogueAssemblerScript._inject_hints(tree, npc_data)
	var locked_ids: Array = (locked.get("nodes", []) as Array).map(func(n): return str((n as Dictionary).get("id", "")))
	_check(locked_ids.has("hint:refused"), "hint-lock refusal injected at rel -2")
	NarrativeState.relationships["npc_mira"] = 1
	var open_tree: Dictionary = DialogueAssemblerScript._inject_hints(tree, npc_data)
	var open_ids: Array = (open_tree.get("nodes", []) as Array).map(func(n): return str((n as Dictionary).get("id", "")))
	_check(open_ids.has("hint:h1") and not open_ids.has("hint:refused"), "hints flow again at rel >= 0")

	# close the ceremony (DONE phase) so teardown is clean
	_key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout

	await _run_dialogue_handoff_check()


## Regression (the "Chiến Hào Tro Lạnh" double-ceremony bug): a story tree
## whose quest-beat node (reveals=="quest") comes BEFORE the choice node makes
## notify_npc_talked queue the choice as a fallback; the ChatBox hand-off then
## used to drop ui_blocking_input for a frame, letting QuestManager._process
## pop that queue and open a SECOND ceremony over the first one.
func _run_dialogue_handoff_check() -> void:
	NarrativeState.reset()
	QuestManager.quests = [{
		"id": "qa_q3", "title": "QA Handoff", "type": "main",
		"reward": {"xp": 5},
		"giver": {"mode": "npc", "npc_id": "npc_trench"},
		"objectives": [{
			"id": "o1", "kind": "choice", "zone_id": "qa_zone", "target_npc_id": "npc_trench",
			"prompt": "Chọn đi.",
			"options": [
				{"id": "a", "label": "A", "consequence_text": "a.", "outcome": {"xp": 5}},
				{"id": "b", "label": "B", "consequence_text": "b.", "outcome": {"xp": 5}},
			],
		}],
	}]
	QuestManager.quest_states = {
		"qa_q3": {"state": "inactive", "objective_index": 0, "progress": 0, "choices": {}},
	}
	QuestManager.current_zone_id = "qa_zone"

	var tree := {
		"start_node": "root",
		"nodes": [
			{"id": "root", "npc_line": "Chào.", "options": [{"player_text": "Về nhiệm vụ.", "goto": "beat"}]},
			{"id": "beat", "npc_line": "Tình hình đây.", "reveals": "quest",
				"options": [{"player_text": "Ta sẽ quyết.", "goto": "choice"}]},
			{"id": "choice", "npc_line": "Chọn đi.", "options": [
				{"player_text": "A", "goto": "root", "effects": [{"type": "quest_choice", "quest_id": "qa_q3", "option": "a"}]},
				{"player_text": "B", "goto": "root", "effects": [{"type": "quest_choice", "quest_id": "qa_q3", "option": "b"}]},
			]},
		],
	}
	var ChatBoxScene := load("res://scenes/ui/ChatBox.tscn") as PackedScene
	var chatbox: Node = ChatBoxScene.instantiate()
	add_child(chatbox)
	chatbox.open_tree("Lính Chiến Hào", {"id": "npc_trench"}, tree)
	await get_tree().process_frame
	chatbox.call("_tree_select", 0)   # -> beat node (reveals quest, queues fallback)
	await get_tree().process_frame
	_check((QuestManager._pending_choices as Array).size() == 1, "quest-beat queued the fallback choice")
	chatbox.call("_tree_select", 0)   # -> choice node: hands off to the ceremony
	# The old bug popped the queue within a frame or two — watch a good while.
	var max_seen := 0
	for _i in range(40):
		await get_tree().process_frame
		max_seen = maxi(max_seen, _count_ceremonies())
	_check(max_seen == 1, "exactly ONE ceremony across the hand-off (saw %d)" % max_seen)
	_check((QuestManager._pending_choices as Array).is_empty(), "hand-off claimed the queued duplicate")

	# Resolve + close, then make sure no late second ceremony sneaks in.
	await get_tree().create_timer(0.8).timeout
	_key(KEY_ENTER)
	await get_tree().create_timer(0.25).timeout
	_key(KEY_ENTER)
	await get_tree().create_timer(1.6).timeout
	_key(KEY_ENTER)
	await get_tree().create_timer(0.6).timeout
	for _i in range(40):
		await get_tree().process_frame
	_check(_count_ceremonies() == 0, "no ceremony re-opens after resolve+close")
	_check(NarrativeState.choice_matches({"choice_key": "qa_q3:o1", "option": "a"}), "hand-off choice recorded")


func _count_ceremonies() -> int:
	var count := 0
	for child in get_tree().root.get_children():
		if child is CanvasLayer and child.get_script() == MoralChoiceViewScript:
			count += 1
	return count
