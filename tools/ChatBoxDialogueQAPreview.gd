extends Node2D
## Scripted QA for two ChatBox features:
##   1. Pressing Enter while a line is still typewriter-revealing fast-forwards it.
##   2. An option once selected shows as "already seen" (the existing "* " marker
##      + dimmed color, via _option_leads_to_seen) even in a BRAND NEW ChatBox
##      instance opened later — i.e. QuestManager-backed persistence actually
##      crosses the session boundary, not just navigation within one open chat.

const ChatBoxScene := preload("res://scenes/ui/ChatBox.tscn")
const NPC_ID := "npc_qa_test_01"

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

	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://tools/qa_chatbox_seen_marker.png")
	)
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
