extends Node
## Root-level watchdog for WorldGachaLiveSmoke: survives the scene change that
## kills the smoke scene, then screenshots whatever world scene ChapterFlow
## swapped in (chapter intro slides or the zone itself) and quits.

const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/2b0ebb95-42ef-480d-bf94-3d1860f99cd6/scratchpad/world_gacha/shots"

var _elapsed := 0.0
var _finishing := false

func _process(delta: float) -> void:
	if _finishing:
		return
	_elapsed += delta
	var current := get_tree().current_scene
	if current != null and current.name not in ["WorldGachaLiveSmoke"]:
		_finishing = true
		_capture_and_quit(current.name)
	elif _elapsed > 420.0:
		_finishing = true
		print("[GachaSmokeWatchdog] FAILED: world scene never arrived (420s)")
		get_tree().quit(1)

func _capture_and_quit(scene_name: String) -> void:
	print("[GachaSmokeWatchdog] world scene arrived: %s" % scene_name)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/live_world_after_choice.png" % SHOT_DIR)
	print("[shot] live_world_after_choice.png (scene=%s)" % scene_name)
	print("[GachaSmokeWatchdog] SUCCESS")
	get_tree().quit(0)
