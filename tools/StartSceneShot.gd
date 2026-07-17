extends Node
## Screenshot helper for the start_menu_v2 redesign: boots the REAL StartScene,
## lets the entrance animation finish, and captures menu states in EN and VI.
## Run:  godot --path GameV1 res://tools/StartSceneShot.tscn

const StartSceneRes := preload("res://scenes/ui/StartScene.tscn")
const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/2b0ebb95-42ef-480d-bf94-3d1860f99cd6/scratchpad/start_menu/shots"

var scene: Control

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame
	scene = StartSceneRes.instantiate() as Control
	add_child(scene)

	SettingsManager.set_language("en")
	await get_tree().create_timer(1.1).timeout      # mid-entrance
	await _shot("menu_en_entrance_mid.png")
	await get_tree().create_timer(1.9).timeout      # entrance settled
	await _shot("menu_en_newgame_focus.png")

	scene.settings_button.grab_focus()
	await get_tree().create_timer(0.5).timeout
	await _shot("menu_en_settings_focus.png")

	SettingsManager.set_language("vi")
	scene.new_game_button.grab_focus()
	await get_tree().create_timer(0.5).timeout
	await _shot("menu_vi_newgame_focus.png")

	scene.settings_overlay.open_panel()
	await get_tree().create_timer(0.6).timeout
	await _shot("menu_vi_settings_panel.png")
	scene.settings_overlay.close_panel()

	SettingsManager.set_language("en")
	print("[StartSceneShot] done")
	get_tree().quit(0)

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("[shot] %s" % file_name)
