extends Node2D
## Dev-only smoke test: drives the full server flow exactly like pressing
## New Game — fetch flow, chapter intro, slides (auto-advanced), zone package,
## world build, cutscene. Requires the SceneBuilder server on port 5001.
## godot --headless --path . res://scenes/dev/FlowSmoke.tscn --quit-after 6000

const AutoAcceptScript := preload("res://scripts/dev/AutoAccept.gd")
const AutoClearScript := preload("res://scripts/dev/AutoClear.gd")

func _ready() -> void:
	var presser: Node = AutoAcceptScript.new()
	get_tree().root.add_child.call_deferred(presser)
	if OS.get_environment("FLOW_AUTOCLEAR") == "1":
		var clearer: Node = AutoClearScript.new()
		get_tree().root.add_child.call_deferred(clearer)
	if OS.get_environment("FLOW_AUTOSHOT") == "1":
		var shooter: Node = preload("res://scripts/dev/AutoShot.gd").new()
		get_tree().root.add_child.call_deferred(shooter)
	ChapterFlow.loading_status.connect(func(message: String) -> void: print("[FlowSmoke] status: %s" % message))
	var err: Error = await ChapterFlow.start_new_game()
	print("[FlowSmoke] start_new_game err=%d active=%s chapter=%s zone=%s" % [
		err, ChapterFlow.active, str(ChapterFlow.current_chapter().get("chapter", "?")),
		str(ChapterFlow.current_zone().get("zone_id", "?")),
	])
	if err != OK:
		get_tree().quit(1)
