extends Node
## Repro harness: boots the REAL Main.tscn exactly the way a walk-through
## transition into zone_nested_01 (from zone_01, via the door) would, using the
## real flow JSON + the real downloaded scene-package zip. Prints frame
## heartbeats so a hang vs. script-error is distinguishable from the log.

const FLOW_JSON_PATH := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/b9f2c769-e8e4-4392-9745-642ed3d70a9d/scratchpad/flow.json"
const ZIP_PATH := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/b9f2c769-e8e4-4392-9745-642ed3d70a9d/scratchpad/zone_nested_01.zip"
const TARGET_ZONE := "zone_nested_01"
const FROM_ZONE := "zone_01"

func _ready() -> void:
	print("[Repro] loading flow json")
	var flow_text := FileAccess.get_file_as_string(FLOW_JSON_PATH)
	var parsed: Variant = JSON.parse_string(flow_text)
	if not (parsed is Dictionary):
		push_error("[Repro] flow json parse failed")
		get_tree().quit(1)
		return
	ChapterFlow.flow = parsed as Dictionary
	ChapterFlow.chapter_index = 0
	ChapterFlow.active = true
	var chapter: Dictionary = ChapterFlow.current_chapter()
	QuestManager.reset()
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)
	var target_index := ChapterFlow.zone_index_by_id(TARGET_ZONE)
	print("[Repro] target zone index=", target_index)
	ChapterFlow.zone_index = target_index
	ChapterFlow.pending_entry_edge = ""
	ChapterFlow.pending_entry_normalized = -1.0
	ChapterFlow.pending_entry_from_zone = FROM_ZONE

	GameManager.reset_runtime_imports(true)
	var err := GameManager.import_scene_package_zip(ZIP_PATH)
	print("[Repro] import err=", err)
	if err != OK:
		get_tree().quit(1)
		return

	# Heartbeat BEFORE instantiating Main so a hard freeze is visible in output.
	print("[Repro] instantiating Main.tscn ...")
	var main: Node2D = (load("res://scenes/world/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	print("[Repro] Main added to tree; waiting frames")
	for i in range(10):
		await get_tree().process_frame
		if i % 3 == 0:
			print("[Repro] heartbeat frame=", i)
	await get_tree().create_timer(3.0).timeout
	print("[Repro] survived 3s after build — no hang in _ready path")
	print("[Repro] ui_blocking_input=", GameManager.ui_blocking_input)
	get_tree().quit(0)
