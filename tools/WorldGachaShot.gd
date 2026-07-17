extends Node
## Screenshot helper for the world-gacha redesign: boots the REAL WorldGachaScene
## offline (qa_offline meta), drives searching → reveal with three fake worlds,
## and captures every state in EN and VI.
## Run:  godot --path GameV1 res://tools/WorldGachaShot.tscn

const GachaScene := preload("res://scenes/ui/WorldGachaScene.tscn")
const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/2b0ebb95-42ef-480d-bf94-3d1860f99cd6/scratchpad/world_gacha/shots"
const GATE_IMAGE := "/Users/dinhhuynh/Documents/FULLGAME/SceneBuilder/outputs/20260703_201230/world_identity/gate.png"

var scene: Control

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame
	scene = GachaScene.instantiate() as Control
	scene.set_meta("qa_offline", true)
	add_child(scene)

	SettingsManager.set_language("vi")
	await get_tree().create_timer(1.6).timeout
	await _shot("gacha_vi_searching.png")

	scene.call("_enter_reveal", _fake_candidates())
	await get_tree().create_timer(1.12).timeout
	await _shot("gacha_vi_reveal_burst.png")     # mid-choreography: beams/rings/sparks
	await get_tree().create_timer(2.3).timeout
	await _shot("gacha_vi_reveal_focus0.png")

	scene.call("_set_focus", 1, true)
	await get_tree().create_timer(0.6).timeout
	await _shot("gacha_vi_reveal_focus1.png")

	SettingsManager.set_language("en")
	await get_tree().create_timer(0.3).timeout
	await _shot("gacha_en_reveal_focus1.png")

	# loading-data screen (VI): the soul walks the light-path while the door opens
	SettingsManager.set_language("vi")
	scene.set("_chosen_candidate", _fake_candidates()[0])
	scene.call("_show_loading", SettingsManager.text("menu.connecting"))
	await get_tree().create_timer(0.08).timeout
	await _shot("gacha_loading_closed.png")
	scene.call("_on_flow_status", "Fetching item icons...")
	await get_tree().create_timer(1.4).timeout
	await _shot("gacha_loading_early.png")
	scene.call("_on_flow_status", SettingsManager.text("gacha.loading_music"))
	await get_tree().create_timer(1.2).timeout
	await _shot("gacha_loading_mid.png")
	scene.call("_on_flow_status", "Building world...")
	await get_tree().create_timer(2.4).timeout
	await _shot("gacha_loading_open.png")
	scene.call("_hide_loading")
	SettingsManager.set_language("en")
	(scene.get("_reveal_root") as Control).show()   # confirm QA needs the doors back

	# Confirm sequence: white light pours out of the chosen door and swallows
	# the screen, then the download overlay crossfades in. (The fake run id
	# 404s afterwards — the error state lands after our captures.)
	scene.call("_confirm_choice")
	await get_tree().create_timer(1.15).timeout
	await _shot("gacha_en_confirm_burst.png")
	await get_tree().create_timer(0.5).timeout
	await _shot("gacha_en_confirm_white.png")
	await get_tree().create_timer(0.65).timeout
	await _shot("gacha_en_confirm_loading.png")

	print("[WorldGachaShot] done")
	get_tree().quit(0)

func _fake_candidates() -> Array:
	var textures: Array[Texture2D] = []
	for path in [
		GATE_IMAGE,
		"/Users/dinhhuynh/Documents/FULLGAME/GameV1/assets/ui/start_menu_v2/background.png",
		"/Users/dinhhuynh/Documents/FULLGAME/GameV1/assets/ui/world_gacha_v1/bg_sanctuary.png",
	]:
		var image := Image.load_from_file(path)
		textures.append(ImageTexture.create_from_image(image) if image != null else null)
	return [
		{
			"run_id": "qa_1", "gate_texture": textures[0], "accent_color": "#e8d7a8", "chapter_count": 2,
			"world_name_vi": "Hoa Ký Ức", "world_name_en": "Memory Bloom",
			"tagline_vi": "Hoa vẫn nở khi ký ức dần lặng im.",
			"tagline_en": "Flowers bloom even as memories quietly fade.",
			"traits": [
				{"label_vi": "Bi thương", "label_en": "Bittersweet"},
				{"label_vi": "Hoa Trắng Ký Ức", "label_en": "White Blossoms"},
				{"label_vi": "Chữa lành tâm hồn", "label_en": "Emotional Healing"},
			],
		},
		{
			"run_id": "qa_2", "gate_texture": textures[1], "accent_color": "#63d8c2",
			"world_name_vi": "Rừng Hóa Đá", "world_name_en": "Petrified Song",
			"tagline_vi": "Bài ca cuối cùng của khu rừng đang lịm dần.",
			"tagline_en": "The forest sings its final, fading song.",
			"traits": [
				{"label_vi": "Kỳ ảo", "label_en": "Mythic"},
				{"label_vi": "Cổ Mộc", "label_en": "Elder Trees"},
				{"label_vi": "Hy vọng", "label_en": "Hope"},
			],
		},
		{
			"run_id": "qa_3", "gate_texture": textures[2], "accent_color": "#f2a0c0",
			"world_name_vi": "Thung Lũng Kẹo Ngọt", "world_name_en": "Sugarbloom Vale",
			"tagline_vi": "Vị ngọt nào rồi cũng cần được nhớ.",
			"tagline_en": "Every sweetness deserves to be remembered.",
			"traits": [
				{"label_vi": "Ấm áp", "label_en": "Cozy"},
				{"label_vi": "Lễ Hội", "label_en": "Festival"},
				{"label_vi": "Tình bạn", "label_en": "Friendship"},
			],
		},
	]

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("[shot] %s" % file_name)
