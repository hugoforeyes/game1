extends Node
## Regression: a planned cutscene triggered from dialogue closes ChatBox
## immediately while holding queued reward ceremonies until cutscene completion.

const ChatBoxScene := preload("res://scenes/ui/ChatBox.tscn")

func _ready() -> void:
	AnnouncementCenter.reset()
	var chatbox: CanvasLayer = ChatBoxScene.instantiate()
	get_tree().root.add_child.call_deferred(chatbox)
	await get_tree().process_frame
	await get_tree().process_frame
	chatbox.open_tree("Roland", {"id": "npc_test"}, {
		"start_node": "root",
		"nodes": [{
			"id": "root",
			"npc_line": "Nhiệm vụ đã hoàn thành.",
			"options": [],
		}],
	})
	assert(GameManager.ui_blocking_input)
	assert(AnnouncementCenter.conversation_active)
	assert(AnnouncementCenter.enqueue("objective", {"title": "Complete"}))
	assert(get_tree().get_first_node_in_group("active_chatbox") == chatbox)

	assert(chatbox.interrupt_for_cutscene())
	chatbox.close()  # synchronous dialogue stack may attempt an ordinary close too
	assert(not chatbox.visible)
	assert(not GameManager.ui_blocking_input, "camera/UI must be handed to the cutscene immediately")
	assert(AnnouncementCenter.conversation_active, "queued ceremonies must remain held during cutscene")
	assert(AnnouncementCenter.has_pending())
	await get_tree().process_frame
	assert(get_tree().get_first_node_in_group("active_chatbox") == null)

	AnnouncementCenter.reset()
	GameManager.ui_blocking_input = false
	print("[ChatBoxCutsceneHandoffTest] immediate dialogue interruption and reward handoff passed")
	get_tree().quit()
