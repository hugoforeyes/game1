extends Node2D
## Scripted QA for two ChatBox features:
##   1. Pressing Enter while a line is still typewriter-revealing fast-forwards it.
##   2. An option once selected shows as "already seen" (the existing "* " marker
##      + dimmed color, via _option_leads_to_seen) even in a BRAND NEW ChatBox
##      instance opened later — i.e. QuestManager-backed persistence actually
##      crosses the session boundary, not just navigation within one open chat.

const ChatBoxScene := preload("res://scenes/ui/ChatBox.tscn")
const NPC_ID := "npc_qa_test_01"
const DYNAMIC_NPC_ID := "npc_qa_dynamic_01"

var _dynamic_talk_count := 0

var _tree := {
	"start_node": "root",
	"nodes": [
		{
			"id": "root",
			"npc_line": "Chào ngươi. Ngươi muốn hỏi ta điều gì?",
			"emotion": "neutral",
			"options": [
				{"player_text": "Hỏi về chủ đề A.", "goto": "topic_a"},
				{"player_text": "Hỏi về chủ đề B.", "goto": "topic_b"},
				{"player_text": "Tạm biệt.", "goto": "__end__"},
			],
		},
		{
			"id": "topic_a",
			"npc_line": "Đây là câu chuyện về chủ đề A, khá dài để kiểm tra hiệu ứng gõ chữ.",
			"emotion": "neutral",
			"options": [{"player_text": "Ta hiểu rồi.", "goto": "root"}],
		},
		{
			"id": "topic_b",
			"npc_line": "Đây là chủ đề B.",
			"emotion": "neutral",
			"options": [{"player_text": "Ta hiểu rồi.", "goto": "root"}],
		},
	],
}


func _ready() -> void:
	QuestManager.reset()

	# ── Session 1: open, fast-forward via real Enter keypress, pick topic A ────
	var chatbox1: Node = ChatBoxScene.instantiate()
	add_child(chatbox1)
	chatbox1.open_tree("Test NPC", {"id": NPC_ID}, _tree)
	await get_tree().process_frame

	assert(chatbox1._dialogue_revealing, "root line should start out typewriter-revealing")
	print("[ChatBoxQA] OK: root line starts revealing")

	await _press_enter()
	await get_tree().process_frame
	assert(not chatbox1._dialogue_revealing, "Enter must fast-forward the typewriter reveal")
	print("[ChatBoxQA] OK: Enter fast-forwarded the reveal")

	assert(chatbox1._opt_container.visible, "options should be showing once the reveal finished")
	assert(chatbox1._options.size() == 3, "root has 3 options")
	assert(not chatbox1._format_option_label(0).contains("*"), "topic A must NOT be marked seen yet")
	print("[ChatBoxQA] OK: fresh option unmarked before ever being picked")

	chatbox1._tree_select(0)  # picks "Hỏi về chủ đề A." -> enters topic_a
	await get_tree().process_frame
	assert(QuestManager.is_dialogue_node_visited(NPC_ID, "topic_a"), "QuestManager must record topic_a as visited")
	print("[ChatBoxQA] OK: QuestManager recorded topic_a as visited")

	chatbox1.close()  # NPCController's real usage pattern: close() frees itself
	await get_tree().process_frame

	# ── Session 2: a BRAND NEW ChatBox instance, same NPC — must remember ──────
	var chatbox2: Node = ChatBoxScene.instantiate()
	add_child(chatbox2)
	chatbox2.open_tree("Test NPC", {"id": NPC_ID}, _tree)
	await get_tree().process_frame

	# Bonus side effect of the same fix: "root" was already reached in session 1,
	# so it's revisit=true here too -> shown instantly, no typewriter to skip, and
	# its options are already up. Only press Enter if a reveal is still playing —
	# otherwise Enter would land on "confirm the highlighted option" instead.
	if chatbox2._dialogue_revealing:
		await _press_enter()
		await get_tree().process_frame
	else:
		print("[ChatBoxQA] OK: root shown instantly in session 2 (cross-session revisit)")

	assert(chatbox2._opt_container.visible, "root's options should be showing")
	assert(chatbox2._format_option_label(0).contains("*"), "topic A must show as already-seen in a NEW chat session")
	assert(not chatbox2._format_option_label(1).contains("*"), "topic B was never picked -> must stay unmarked")
	print("[ChatBoxQA] OK: cross-session persistence -> topic A marked seen, topic B not")

	chatbox2.close()
	await get_tree().process_frame

	await _run_dynamic_root_refresh_check()

	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var viewport_texture := get_viewport().get_texture()
		if viewport_texture != null:
			var image := viewport_texture.get_image()
			if image != null:
				image.save_png(ProjectSettings.globalize_path("res://tools/qa_chatbox_seen_marker.png"))
				print("[ChatBoxQA] wrote qa_chatbox_seen_marker.png")

	print("[ChatBoxQA] ALL CHECKS PASSED")
	get_tree().quit()


func _press_enter() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	event.echo = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _run_dynamic_root_refresh_check() -> void:
	QuestManager.reset()
	_dynamic_talk_count = 0
	if not QuestManager.npc_talked.is_connected(_on_dynamic_npc_talked):
		QuestManager.npc_talked.connect(_on_dynamic_npc_talked)
	QuestManager.load_chapter_quests([
		{
			"id": "quest_chatbox_dynamic",
			"title": "Dynamic Chat QA",
			"type": "main",
			"giver": {"mode": "auto", "zone_id": "zone_dynamic"},
			"objectives": [
				{
					"id": "talk_1",
					"kind": "talk",
					"zone_id": "zone_dynamic",
					"target_npc_id": DYNAMIC_NPC_ID,
					"description": "Nói chuyện để đổi stage.",
				},
			],
			"reward": {"xp": 0},
		},
	])
	QuestManager.current_zone_id = "zone_dynamic"
	QuestManager.quest_states["quest_chatbox_dynamic"] = {
		"state": "active",
		"objective_index": 0,
		"progress": 0,
		"choices": {},
	}

	var npc_data := {
		"id": DYNAMIC_NPC_ID,
		"name": "Dynamic NPC",
		"story_dialogue": {
			"stages": [
				{
					"order": 0,
					"unlock": {"type": "chapter_start"},
					"tree": {
						"start_node": "root",
						"nodes": [
							{
								"id": "root",
								"npc_line": "Đây là menu cũ.",
								"emotion": "neutral",
								"reveals": "",
								"options": [
									{"player_text": "Nhịp cũ.", "goto": "old_reveal"},
									{"player_text": "Tạm biệt.", "goto": "__end__"},
								],
							},
							{
								"id": "old_reveal",
								"npc_line": "Nhịp cũ hoàn tất nhiệm vụ, nhưng menu chưa đổi ngay.",
								"emotion": "neutral",
								"reveals": "quest",
								"options": [
									{"player_text": "Quay lại.", "goto": "root"},
								],
							},
						],
					},
				},
				{
					"order": 1,
					"unlock": {"type": "quest_complete", "quest_id": "quest_chatbox_dynamic"},
					"tree": {
						"start_node": "root",
						"nodes": [
							{
								"id": "root",
								"npc_line": "Đây là menu mới.",
								"emotion": "neutral",
								"reveals": "",
								"options": [
									{"player_text": "Nhịp mới.", "goto": "new_reveal"},
									{"player_text": "Tạm biệt.", "goto": "__end__"},
								],
							},
							{
								"id": "new_reveal",
								"npc_line": "Nhịp mới có thể tiếp tục phát tín hiệu nói chuyện.",
								"emotion": "neutral",
								"reveals": "quest",
								"options": [
									{"player_text": "Xong.", "goto": "__end__"},
								],
							},
						],
					},
				},
			],
		},
	}

	var chatbox: Node = ChatBoxScene.instantiate()
	add_child(chatbox)
	chatbox.open_tree("Dynamic NPC", npc_data, DialogueAssembler.build_active_tree(npc_data))
	await get_tree().process_frame
	if chatbox._dialogue_revealing:
		await _press_enter()
	assert(chatbox._options[0] == "Nhịp cũ.", "dynamic chat starts on the old root options")

	chatbox._tree_select(0)
	await get_tree().process_frame
	if chatbox._dialogue_revealing:
		await _press_enter()
	assert(_dynamic_talk_count == 1, "quest reveal should notify once in the old tree")
	assert(chatbox._options[0] == "Quay lại.", "current branch keeps its existing options after quest completion")

	chatbox._tree_select(0)
	await get_tree().process_frame
	assert(chatbox._options[0] == "Nhịp mới.", "returning to root refreshes to the newly unlocked stage")

	chatbox._tree_select(0)
	await get_tree().process_frame
	assert(_dynamic_talk_count == 2, "a refreshed tree can notify a new talk beat in the same conversation")
	chatbox.close()
	await get_tree().process_frame
	if QuestManager.npc_talked.is_connected(_on_dynamic_npc_talked):
		QuestManager.npc_talked.disconnect(_on_dynamic_npc_talked)
	print("[ChatBoxQA] OK: quest changes refresh choices only when returning to root")


func _on_dynamic_npc_talked(npc_id: String) -> void:
	if npc_id == DYNAMIC_NPC_ID:
		_dynamic_talk_count += 1
