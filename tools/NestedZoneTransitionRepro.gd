extends Node
## Faithful repro of the REAL interior transition INTO zone_nested_01. Creates
## the black ZoneTransitionOverlay (as _use_scene_exit does), primes cache+music,
## then calls ChapterFlow.enter_current_zone() (real change_scene_to_file). A
## SEPARATE watcher node parented to the SceneTree root survives the scene swap
## and reports whether the overlay/ui-block ever clears.

const FLOW_JSON_PATH := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/b9f2c769-e8e4-4392-9745-642ed3d70a9d/scratchpad/flow.json"
const ZIP_PATH := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/b9f2c769-e8e4-4392-9745-642ed3d70a9d/scratchpad/zone_nested_01.zip"
const TARGET_ZONE := "zone_nested_01"
const FROM_ZONE := "zone_01"
const OVERLAY_NAME := "ZoneTransitionOverlay"

const WatcherScript := preload("res://tools/NestedZoneTransitionWatcher.gd")

func _ready() -> void:
	call_deferred("_run_repro")

func _run_repro() -> void:
	var flow_text := FileAccess.get_file_as_string(FLOW_JSON_PATH)
	ChapterFlow.flow = JSON.parse_string(flow_text) as Dictionary
	ChapterFlow.chapter_index = 0
	ChapterFlow.active = true
	var chapter: Dictionary = ChapterFlow.current_chapter()
	QuestManager.reset()
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)

	var zone_key := "%s::%d::%s" % [str(ChapterFlow.flow.get("run_id", "")), 0, TARGET_ZONE]
	var cache_path := ChapterFlow._zone_cache_path(zone_key)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_path.get_base_dir()))
	var src := FileAccess.open(ZIP_PATH, FileAccess.READ)
	var dst := FileAccess.open(cache_path, FileAccess.WRITE)
	dst.store_buffer(src.get_buffer(src.get_length()))
	dst.flush()

	var mkey := "%s::chapter_%d" % [str(ChapterFlow.flow.get("run_id", "")), 1]
	MusicManager._music_cache[mkey] = {"normal_scene": []}

	ChapterFlow.zone_index = ChapterFlow.zone_index_by_id(TARGET_ZONE)
	ChapterFlow.pending_entry_edge = ""
	ChapterFlow.pending_entry_normalized = -1.0
	ChapterFlow.pending_entry_from_zone = FROM_ZONE
	ChapterFlow._suppress_cutscene = true

	_make_black_overlay()
	GameManager.ui_blocking_input = true

	# Persistent watcher survives change_scene_to_file.
	var watcher := WatcherScript.new()
	watcher.name = "TransitionWatcher"
	get_tree().root.add_child(watcher)

	print("[Repro2] calling enter_current_zone() ...")
	ChapterFlow.enter_current_zone()


func _make_black_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = OVERLAY_NAME
	overlay.layer = 120
	get_tree().root.add_child(overlay)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var status := Label.new()
	status.name = "Status"
	status.text = ""
	overlay.add_child(status)
