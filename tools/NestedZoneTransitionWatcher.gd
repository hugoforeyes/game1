extends Node
## Root-parented watcher: survives change_scene_to_file and reports whether the
## black ZoneTransitionOverlay clears + ui_blocking_input drops after the real
## transition into zone_nested_01.

const OVERLAY_NAME := "ZoneTransitionOverlay"

var _frames := 0

func _process(_delta: float) -> void:
	_frames += 1
	var overlay := get_tree().root.get_node_or_null(OVERLAY_NAME)
	if _frames % 30 == 0:
		print("[Watcher] f=%d overlay_present=%s ui_blocking=%s current_scene=%s" % [
			_frames,
			overlay != null,
			GameManager.ui_blocking_input,
			get_tree().current_scene.name if get_tree().current_scene else "<null>",
		])
	if _frames > 6 and overlay == null and not GameManager.ui_blocking_input:
		print("[Watcher] RESULT: screen un-blacked after %d frames  ✅ NO FREEZE" % _frames)
		get_tree().quit(0)
		return
	if _frames > 360:
		print("[Watcher] RESULT: overlay_present=%s ui_blocking=%s  ❌ STILL BLACK/FROZEN after 6s" % [
			overlay != null, GameManager.ui_blocking_input,
		])
		get_tree().quit(2)
