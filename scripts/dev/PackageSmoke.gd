extends Node2D
## Dev-only smoke test: imports a scene package zip (path from PACKAGE_ZIP env
## var) and switches to the world scene so spawn logs can be inspected.
## godot --headless --path . res://scenes/dev/PackageSmoke.tscn --quit-after 600

func _ready() -> void:
	var zip_path: String = OS.get_environment("PACKAGE_ZIP")
	if zip_path.is_empty():
		push_error("[PackageSmoke] PACKAGE_ZIP env var not set")
		get_tree().quit(1)
		return
	var err: Error = GameManager.import_scene_package_zip(zip_path)
	print("[PackageSmoke] import err=%d roster=%d" % [err, GameManager.get_enemy_roster().size()])
	if err != OK:
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/world/Main.tscn")
