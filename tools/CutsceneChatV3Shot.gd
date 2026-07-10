extends Node
## Screenshot helper: plays a real CutscenePlayer `say` beat (speaker + narrator
## variants) to verify the chat_v3 skin applied over the redesigned dialogue
## block. Saves shots to the session scratchpad and quits.

const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")
const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/0f7519ac-6c6a-4586-96d9-b9196e5b3fc4/scratchpad/chat_kit"


class FakeActor:
	extends Node2D
	var anim_sprite: AnimatedSprite2D = null
	var camera: Camera2D = null
	var npc_data: Dictionary = {}
	var enemy_data: Dictionary = {}


func _ready() -> void:
	var world := Node2D.new()
	world.name = "WorldRoot"
	add_child(world)

	var player := FakeActor.new()
	player.name = "Player"
	player.camera = Camera2D.new()
	player.add_child(player.camera)
	player.global_position = Vector2(64, 64)
	world.add_child(player)

	var characters := Node2D.new()
	characters.name = "GeneratedCharacters"
	world.add_child(characters)

	var speaker := FakeActor.new()
	speaker.name = "Trench"
	speaker.npc_data = {"id": "npc_trench", "name": "Lính Chiến Hào"}
	speaker.global_position = Vector2(112, 64)
	characters.add_child(speaker)

	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene.play(
		[
			{"type": "say", "actor": "npc_trench", "text": "Khu chợ này đã nuôi sống ba thế hệ nhà ta. Ngày ông nội ta dựng sạp đầu tiên, cả vùng còn là bãi lầy hoang vu, người qua kẻ lại chỉ đếm trên đầu ngón tay. Rồi chiến tranh tràn qua, lửa cháy ba ngày ba đêm, nhưng ngươi thấy đấy — chúng ta vẫn đứng dậy, dựng lại từng viên gạch một. Có điều gì ta giúp được không, hỡi lữ khách phương xa?", "seconds": 10.0},
			{"type": "say", "actor": "narrator", "text": "Màn đêm buông xuống Chiến Hào Tro Lạnh, mang theo mùi khói và ký ức.", "seconds": 6.0},
		],
		world,
		player,
		characters,
		{}
	)

	await get_tree().create_timer(2.2).timeout  # long line mid-reveal (scrolled)
	await _shot("cutscene_chatv3_speaker_midscroll.png")
	_press_enter()  # fast-forward: reveal_finished lands on the LAST lines
	await get_tree().create_timer(0.5).timeout
	await _shot("cutscene_chatv3_speaker.png")
	_press_enter()
	await get_tree().create_timer(2.2).timeout  # narrator variant
	await _shot("cutscene_chatv3_narrator.png")
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
