extends Node
## Strict wrapper for scene-based QA tests. Godot can return exit code 0 when a
## scene's root script fails to parse, so direct `godot scene.tscn` invocations can
## report a false pass. This loader verifies that both the scene and its root
## script exist before handing control to the test; tests must call quit(nonzero)
## for failed runtime checks.
##
## Usage:
##   godot --headless --path . res://scenes/dev/StrictSceneTestRunner.tscn \
##     -- res://tools/XpBalanceQAPreview.tscn

const TIMEOUT_SECONDS := 15.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_fail("missing target scene argument")
		return
	var scene_path: String = args[0]
	var resource: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	if not (resource is PackedScene):
		_fail("could not load %s" % scene_path)
		return
	var instance: Node = (resource as PackedScene).instantiate()
	if instance == null:
		_fail("could not instantiate %s" % scene_path)
		return
	if instance.get_script() == null:
		instance.free()
		_fail("root script is missing or failed to parse: %s" % scene_path)
		return
	add_child(instance)
	_arm_timeout.call_deferred(scene_path)


func _arm_timeout(scene_path: String) -> void:
	await get_tree().create_timer(TIMEOUT_SECONDS).timeout
	_fail("timed out after %.0f seconds: %s" % [TIMEOUT_SECONDS, scene_path])


func _fail(message: String) -> void:
	push_error("[StrictSceneTestRunner] %s" % message)
	get_tree().quit(1)
