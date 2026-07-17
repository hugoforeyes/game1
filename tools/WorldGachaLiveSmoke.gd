extends Node
## LIVE end-to-end smoke for the world gacha: real server, real candidates,
## real world load. Boots WorldGachaScene online, waits for the reveal, shoots
## it, confirms the focused door, then a root-level watchdog (which survives the
## scene change) waits for ChapterFlow to swap in the chosen world's scene and
## shoots that too. Requires SceneBuilder on :5001 with world identities built.
## Run:  godot --path GameV1 res://tools/WorldGachaLiveSmoke.tscn

const GachaScene := preload("res://scenes/ui/WorldGachaScene.tscn")
const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/2b0ebb95-42ef-480d-bf94-3d1860f99cd6/scratchpad/world_gacha/shots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame

	var watchdog := Node.new()
	watchdog.name = "GachaSmokeWatchdog"
	watchdog.set_script(load("res://tools/WorldGachaSmokeWatchdog.gd"))
	get_tree().root.add_child(watchdog)

	var scene := GachaScene.instantiate() as Control
	add_child(scene)

	var waited := 0.0
	while int(scene.get("_phase")) != 1 and waited < 180.0:  # Phase.REVEAL
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if int(scene.get("_phase")) == 3:  # Phase.ERROR
			print("[GachaLiveSmoke] FAILED: gacha entered error state")
			get_tree().quit(1)
			return
	if int(scene.get("_phase")) != 1:
		print("[GachaLiveSmoke] FAILED: reveal never arrived (waited %.0fs)" % waited)
		get_tree().quit(1)
		return

	await get_tree().create_timer(3.6).timeout  # let the reveal choreography settle
	await _shot("live_reveal.png")
	print("[GachaLiveSmoke] reveal ok — confirming focused door")
	scene.call("_confirm_choice")

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("[shot] %s" % file_name)
