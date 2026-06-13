extends Node
## Server-driven game flow: chapters → zones, with chapter intros.
##
## The flow comes from GET /api/godot/runs/latest — nothing is hardcoded.
## Each chapter begins with its generated intro (slides and/or in-scene
## cutscene), then its zones are played in order; clearing a zone's hostiles
## advances to the next zone, finishing a chapter advances to the next chapter.

signal loading_status(message: String)

const DOWNLOAD_PATH := "user://downloads/scene-package.zip"
const SLIDES_SCENE_PATH := "res://scenes/ui/ChapterIntroSlides.tscn"
const GAME_END_SCENE_PATH := "res://scenes/ui/GameEndScene.tscn"
const START_SCENE_PATH := "res://scenes/ui/StartScene.tscn"

var flow: Dictionary = {}
var chapter_index: int = 0
var zone_index: int = 0
var active: bool = false
var pending_intro: Dictionary = {}
var pending_cutscene_actions: Array = []

func api_url(path: String) -> String:
	return GameManager.api_base_url() + path

func chapters() -> Array:
	return flow.get("chapters", []) as Array

func current_chapter() -> Dictionary:
	var items: Array = chapters()
	if chapter_index >= 0 and chapter_index < items.size() and items[chapter_index] is Dictionary:
		return items[chapter_index] as Dictionary
	return {}

func current_chapter_zones() -> Array:
	return current_chapter().get("zones", []) as Array

func current_zone() -> Dictionary:
	var zones: Array = current_chapter_zones()
	if zone_index >= 0 and zone_index < zones.size() and zones[zone_index] is Dictionary:
		return zones[zone_index] as Dictionary
	return {}

func progress_label() -> String:
	var chapter: Dictionary = current_chapter()
	var zone: Dictionary = current_zone()
	if chapter.is_empty():
		return ""
	return "CHAPTER %s · %s" % [str(chapter.get("chapter", "?")), str(zone.get("name", chapter.get("title", "")))]

# ── flow control ──────────────────────────────────────────────────────────────

func start_new_game() -> Error:
	loading_status.emit("Connecting to story server...")
	var response: Dictionary = await _http_get_json("/api/godot/runs/latest")
	if not bool(response.get("ok", false)) or (response.get("chapters", []) as Array).is_empty():
		print("[ChapterFlow] no playable run: %s" % str(response))
		return ERR_CANT_CONNECT
	flow = response
	chapter_index = 0
	zone_index = 0
	active = true
	GameManager.reset_runtime_imports(true)
	QuestManager.reset()
	InventoryManager.reset()
	print("[ChapterFlow] flow loaded run=%s chapters=%d" % [str(flow.get("run_id", "")), chapters().size()])
	return await begin_current_chapter()

func begin_current_chapter() -> Error:
	var chapter: Dictionary = current_chapter()
	if chapter.is_empty():
		return _finish_game()
	zone_index = 0
	pending_intro = {}
	pending_cutscene_actions = []
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)

	var items_payload: Dictionary = chapter.get("items", {}) as Dictionary
	if not (items_payload.get("items", []) as Array).is_empty():
		var icon_url: String = str(chapter.get("items_icon_url", ""))
		var icon_texture: Texture2D = null
		if not icon_url.is_empty():
			loading_status.emit("Fetching item icons...")
			icon_texture = await download_image_texture(icon_url)
		InventoryManager.load_chapter_catalog(items_payload, icon_texture)

	loading_status.emit("Fetching chapter intro...")
	var run_id: String = str(flow.get("run_id", ""))
	var intro_response: Dictionary = await _http_get_json(
		"/api/godot/runs/%s/chapters/%d/intro" % [run_id, int(chapter.get("chapter", 0))]
	)
	if bool(intro_response.get("ok", false)):
		pending_intro = intro_response.get("chapter_intro", {}) as Dictionary
	print("[ChapterFlow] chapter %s intro mode='%s' slides=%d cutscene_actions=%d" % [
		str(chapter.get("chapter", "?")),
		str(pending_intro.get("recommended_mode", "none")),
		(pending_intro.get("slides", []) as Array).size(),
		((pending_intro.get("cutscene", {}) as Dictionary).get("actions", []) as Array).size(),
	])

	var mode: String = str(pending_intro.get("recommended_mode", ""))
	var slides: Array = pending_intro.get("slides", []) as Array
	if not slides.is_empty() and mode in ["slides", "both"]:
		get_tree().change_scene_to_file(SLIDES_SCENE_PATH)
		return OK
	return await enter_current_zone()

func enter_current_zone() -> Error:
	var zone: Dictionary = current_zone()
	if zone.is_empty():
		return _finish_game()

	loading_status.emit("Downloading %s..." % str(zone.get("name", "scene")))
	var package_url: String = api_url(str(zone.get("package_url", "")))
	var download_error: Error = await _download_file(package_url, DOWNLOAD_PATH)
	if download_error != OK:
		print("[ChapterFlow] zone download failed err=%d url=%s" % [download_error, package_url])
		return download_error

	loading_status.emit("Building world...")
	GameManager.reset_runtime_imports(true)
	var import_error: Error = GameManager.import_scene_package_zip(DOWNLOAD_PATH)
	if import_error != OK:
		print("[ChapterFlow] zone import failed err=%d" % import_error)
		return import_error

	# In-scene cutscene plays in the chapter's first zone only.
	pending_cutscene_actions = []
	var mode: String = str(pending_intro.get("recommended_mode", ""))
	var cutscene: Dictionary = pending_intro.get("cutscene", {}) as Dictionary
	if zone_index == 0 and mode in ["cutscene", "both"]:
		if str(cutscene.get("zone_id", "")) == str(zone.get("zone_id", "")):
			pending_cutscene_actions = (cutscene.get("actions", []) as Array).duplicate(true)

	loading_status.emit("Loading music...")
	await MusicManager.load_and_play(GameManager.get_scene_context())
	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)
	return OK

func take_pending_cutscene() -> Array:
	var actions: Array = pending_cutscene_actions
	pending_cutscene_actions = []
	return actions

func advance_after_zone_cleared() -> void:
	if not active:
		return
	zone_index += 1
	if zone_index < current_chapter_zones().size():
		var err: Error = await enter_current_zone()
		if err != OK:
			_abort_to_start("Could not load the next scene.")
		return
	chapter_index += 1
	if chapter_index < chapters().size():
		var err: Error = await begin_current_chapter()
		if err != OK:
			_abort_to_start("Could not load the next chapter.")
		return
	_finish_game()

func _finish_game() -> Error:
	active = false
	get_tree().change_scene_to_file(GAME_END_SCENE_PATH)
	return OK

func _abort_to_start(reason: String) -> void:
	print("[ChapterFlow] aborting flow: %s" % reason)
	active = false
	get_tree().change_scene_to_file(START_SCENE_PATH)

# ── http helpers ──────────────────────────────────────────────────────────────

func _http_get_json(path: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	var url: String = api_url(path)
	var start_error: Error = request.request(url)
	if start_error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	var body: PackedByteArray = response[3] as PackedByteArray
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		var result: Dictionary = parsed as Dictionary
		result["_http_code"] = int(response[1])
		return result
	return {}

func _download_file(url: String, output_path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var request := HTTPRequest.new()
	request.timeout = 60.0
	add_child(request)
	var start_error: Error = request.request(url)
	if start_error != OK:
		request.queue_free()
		return start_error
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return ERR_CANT_CONNECT
	var code: int = int(response[1])
	var body: PackedByteArray = response[3] as PackedByteArray
	if code < 200 or code >= 300 or body.is_empty():
		return ERR_FILE_CANT_READ
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(body)
	file.flush()
	return OK

func download_image_texture(url_path: String) -> Texture2D:
	var request := HTTPRequest.new()
	request.timeout = 30.0
	add_child(request)
	var start_error: Error = request.request(api_url(url_path))
	if start_error != OK:
		request.queue_free()
		return null
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) >= 300:
		return null
	var body: PackedByteArray = response[3] as PackedByteArray
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK:
		return null
	return ImageTexture.create_from_image(image)
