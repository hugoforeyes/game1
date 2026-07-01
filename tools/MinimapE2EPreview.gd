extends Node
## End-to-end check: drives the REAL autoload wiring (ChapterFlow -> MinimapManager
## -> QuestManager.visited_zones) instead of MinimapView in isolation, without
## risking a scene-transition mid-script (ChapterFlow.start_new_game() would
## change_scene_to_file and free this test node). Fetches the live minimap
## payload from the running SceneBuilder backend, exactly like the real game does.


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.07, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var flow: Dictionary = await _http_get_json("/api/godot/runs/latest")
	if not bool(flow.get("ok", false)):
		print("[MinimapE2EPreview] FAILED to fetch flow: %s" % str(flow))
		get_tree().quit(1)
		return

	ChapterFlow.flow = flow
	ChapterFlow.chapter_index = 0
	ChapterFlow.zone_index = 0
	ChapterFlow.active = true

	var minimap: Dictionary = ChapterFlow.current_chapter().get("minimap", {}) as Dictionary
	var zone_ids: Array = []
	for zone in (minimap.get("zones", []) as Array):
		if zone is Dictionary:
			zone_ids.append(str((zone as Dictionary).get("zone_id", "")))
	print("[MinimapE2EPreview] fetched minimap zones: %s" % str(zone_ids))
	assert(zone_ids.size() >= 2, "expected at least 2 real minimap zones from the live backend")

	# Simulate real exploration: the player has visited the entrance + one more
	# zone (mirrors QuestManager.notify_zone_entered's visited_zones bookkeeping).
	QuestManager.reset()
	var entrance_id := str(minimap.get("entrance_zone_id", zone_ids[0]))
	QuestManager.visited_zones[entrance_id] = true
	var second_id: String = ""
	for zid in zone_ids:
		if zid != entrance_id:
			second_id = zid
			break
	if second_id != "":
		QuestManager.visited_zones[second_id] = true
	GameManager.imported_scene_context = {"zone_id": second_id if second_id != "" else entrance_id}

	# Drive the exact same toggle path KEY_M triggers in the real game.
	assert(not GameManager.ui_blocking_input)
	MinimapManager._toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert(MinimapManager._open, "MinimapManager did not open")
	assert(GameManager.ui_blocking_input, "opening the minimap must block world input")
	assert(MinimapManager._view != null and MinimapManager._view.visible)
	print("[MinimapE2EPreview] minimap opened via the real KEY_M toggle path")

	var output := "res://assets/ui/minimap_v1/preview_e2e.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[MinimapE2EPreview] wrote %s" % output)

	# Close path.
	MinimapManager._toggle()
	await get_tree().process_frame
	assert(not MinimapManager._open)
	assert(not GameManager.ui_blocking_input, "closing the minimap must release world input")
	print("[MinimapE2EPreview] close path OK — all assertions passed")
	get_tree().quit()


func _http_get_json(path: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	var start_error: Error = request.request(GameManager.api_base_url() + path)
	if start_error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	var body: PackedByteArray = response[3] as PackedByteArray
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}
