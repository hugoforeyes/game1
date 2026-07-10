extends Node2D
## Screenshot helper: opens the REAL ChatBox with a synthetic tree and captures
## the dialogue view (typewriter finished, options open) for UI redesign work.

const ChatBoxScene := preload("res://scenes/ui/ChatBox.tscn")
const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/0f7519ac-6c6a-4586-96d9-b9196e5b3fc4/scratchpad/chat_kit"

var _tree := {
	"start_node": "root",
	"nodes": [
		{
			"id": "root",
			"npc_line": "Chào cậu, lữ khách. Khu chợ này đã nuôi sống ba thế hệ nhà ta. Ngày ông nội ta dựng sạp đầu tiên, cả vùng còn là bãi lầy hoang vu, người qua kẻ lại chỉ đếm trên đầu ngón tay. Rồi chiến tranh tràn qua, lửa cháy ba ngày ba đêm, nhưng chúng ta vẫn đứng dậy, dựng lại từng viên gạch một — có điều gì ta giúp được không?",
			"emotion": "happy",
			"options": [
				{"player_text": "Về nhiệm vụ Lá Thư Cuối.", "goto": "topic_a"},
				{"player_text": "(Gợi ý) Xin một lời chỉ dẫn.", "goto": "topic_b"},
				{"player_text": "Hỏi chuyện khác.", "goto": "topic_a"},
				{"player_text": "Tạm biệt.", "goto": "__end__"},
			],
		},
		{
			"id": "topic_a",
			"npc_line": "Chuyện đó dài lắm...",
			"emotion": "neutral",
			"options": [{"player_text": "Ta hiểu rồi.", "goto": "root"}],
		},
		{
			"id": "topic_b",
			"npc_line": "Nghe kỹ đây.",
			"emotion": "neutral",
			"options": [{"player_text": "Cảm ơn.", "goto": "root"}],
		},
	],
}


func _ready() -> void:
	await get_tree().process_frame
	var chatbox: Node = ChatBoxScene.instantiate()
	add_child(chatbox)
	chatbox.open_tree("Bà Mira", {"id": "npc_shot"}, _tree)
	await get_tree().create_timer(0.4).timeout
	_press_enter()  # fast-forward typewriter so the full line + options show
	await get_tree().create_timer(0.8).timeout
	await _shot("chatbox_before.png")
	get_tree().quit(0)


func _press_enter() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = KEY_ENTER
	up.physical_keycode = KEY_ENTER
	up.pressed = false
	Input.parse_input_event(up)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("[shot] %s" % file_name)
