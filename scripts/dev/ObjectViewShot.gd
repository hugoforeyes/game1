extends Node2D
## Dev-only: renders the ObjectInteractionView in both states and saves screenshots
## so the new UI can be eyeballed without playing through a zone.

const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")
const ROOT := "/Users/dinhhuynh/Documents/FULLGAME"


func _ready() -> void:
	var flow: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapter: Dictionary = (flow.get("chapters", []) as Array)[0] as Dictionary
	var icon: Texture2D = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	InventoryManager.load_chapter_catalog(chapter.get("items", {}) as Dictionary, icon)
	var run_id: String = str(flow.get("run_id", ""))

	var pkg: Dictionary = _read_package(run_id, 1, "zone_04")
	ObjectInteractionManager.register_zone_contracts(pkg)

	# a soft world backdrop so the panel reads in context
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.10, 1.0)
	bg.size = Vector2(960, 540)
	add_child(bg)

	var view: CanvasLayer = ObjectInteractionViewScript.new()
	add_child(view)
	view.open_object("object_memory_garden")
	await get_tree().create_timer(0.5).timeout
	await _shot("/tmp/object_view_examine.png")

	# advance to the reveal state
	view._activate_primary()
	await get_tree().create_timer(0.7).timeout
	await _shot("/tmp/object_view_reveal.png")
	view.queue_free()

	# a pure-lore object (the LLM's story/world flavour) — the most common interaction
	var pkg3: Dictionary = _read_package(run_id, 1, "zone_03")
	ObjectInteractionManager.register_zone_contracts(pkg3)
	var lore_view: CanvasLayer = ObjectInteractionViewScript.new()
	add_child(lore_view)
	lore_view.open_object("sugar_clock_tower")
	await get_tree().create_timer(0.5).timeout
	await _shot("/tmp/object_view_lore.png")

	get_tree().quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw  # ensure the latest frame is on the GPU
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("[ObjViewShot] saved %s" % path)


func _read_package(run_id: String, chapter: int, zone_id: String) -> Dictionary:
	var path := "%s/SceneBuilder/outputs/%s/scene_background_render/chapter_%d/%s/package/scene_package.json" % [ROOT, run_id, chapter, zone_id]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
