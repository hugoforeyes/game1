extends Node
## Server-driven game flow: chapters → zones, with chapter intros.
##
## The flow comes from GET /api/godot/runs/latest — nothing is hardcoded.
## Each chapter begins with its generated intro (slides and/or in-scene
## cutscene), then its zones are played through explicit scene exits/transitions.

signal loading_status(message: String)
## Emitted when a background prefetch_current_zone() finishes (success or fail).
signal zone_download_finished()

const CACHE_DIR := "user://downloads/zones"
const SLIDES_SCENE_PATH := "res://scenes/ui/ChapterIntroSlides.tscn"
const GAME_END_SCENE_PATH := "res://scenes/ui/GameEndScene.tscn"
const START_SCENE_PATH := "res://scenes/ui/StartScene.tscn"

var flow: Dictionary = {}
var chapter_index: int = 0
var zone_index: int = 0
var active: bool = false
var pending_intro: Dictionary = {}
var pending_cutscene_actions: Array = []
# When the player walks through an exit, the edge they should arrive at in the
# next scene (opposite of the exit edge). Consumed by Main on spawn.
var pending_entry_edge: String = ""
var _suppress_cutscene: bool = false
# Per-zone package cache. Each zone is downloaded to its own file under
# CACHE_DIR so every zone of a chapter can be cached at once. _prefetching_zones
# maps zone_key -> true while that zone's download is in flight (dedup guard).
var _prefetching_zones: Dictionary = {}
var _prefetch_all_running: bool = false

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
	_clear_zone_cache()
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

	var package_url: String = api_url(str(zone.get("package_url", "")))
	var zone_key: String = _current_zone_key()
	var cache_path: String = _zone_cache_path(zone_key)

	if FileAccess.file_exists(cache_path):
		print("[ChapterFlow] using cached zone '%s'" % str(zone.get("name", "scene")))
	else:
		loading_status.emit("Downloading %s..." % str(zone.get("name", "scene")))
	var download_error: Error = await _ensure_zone_cached(zone_key, package_url)
	if download_error != OK:
		print("[ChapterFlow] zone download failed err=%d url=%s" % [download_error, package_url])
		return download_error

	loading_status.emit("Building world...")
	GameManager.reset_runtime_imports(true)
	var import_error: Error = GameManager.import_scene_package_zip(cache_path)
	if import_error != OK:
		print("[ChapterFlow] zone import failed err=%d" % import_error)
		return import_error

	# Once in the world, keep filling the cache with the chapter's other zones so
	# walking through an exit is instant when the target is already downloaded.
	prefetch_remaining_zones()

	# In-scene cutscene plays in the chapter's first zone only, and never when
	# the player merely walked back into a zone through an exit.
	pending_cutscene_actions = []
	var mode: String = str(pending_intro.get("recommended_mode", ""))
	var cutscene: Dictionary = pending_intro.get("cutscene", {}) as Dictionary
	if zone_index == 0 and mode in ["cutscene", "both"] and not _suppress_cutscene:
		if str(cutscene.get("zone_id", "")) == str(zone.get("zone_id", "")):
			pending_cutscene_actions = (cutscene.get("actions", []) as Array).duplicate(true)
	_suppress_cutscene = false

	loading_status.emit("Loading music...")
	await MusicManager.load_and_play(GameManager.get_scene_context())
	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)
	return OK

func take_pending_cutscene() -> Array:
	var actions: Array = pending_cutscene_actions
	pending_cutscene_actions = []
	return actions

func take_pending_entry_edge() -> String:
	var edge: String = pending_entry_edge
	pending_entry_edge = ""
	return edge

func _current_zone_key() -> String:
	return "%s::%d::%s" % [str(flow.get("run_id", "")), chapter_index, str(current_zone().get("zone_id", ""))]

func scene_music_context() -> Dictionary:
	return {
		"run_id": str(flow.get("run_id", "")),
		"chapter": int(current_chapter().get("chapter", 1)),
	}

func _clear_zone_cache() -> void:
	_prefetching_zones.clear()
	_prefetch_all_running = false
	var dir: DirAccess = DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _zone_cache_path(zone_key: String) -> String:
	var safe: String = zone_key.replace("::", "_").replace("/", "_").replace(":", "_")
	return "%s/%s.zip" % [CACHE_DIR, safe]

func _zone_key_for(zone_id: String) -> String:
	return "%s::%d::%s" % [str(flow.get("run_id", "")), chapter_index, zone_id]

func is_zone_cached_by_id(zone_id: String) -> bool:
	return FileAccess.file_exists(_zone_cache_path(_zone_key_for(zone_id)))

## Download one zone's package to its cache file (idempotent + race-safe). If
## another task is already downloading it, waits for that instead of re-fetching.
func _ensure_zone_cached(zone_key: String, package_url: String) -> Error:
	var cache_path: String = _zone_cache_path(zone_key)
	if FileAccess.file_exists(cache_path):
		return OK
	while _prefetching_zones.has(zone_key):
		await get_tree().create_timer(0.1).timeout
	if FileAccess.file_exists(cache_path):
		return OK
	_prefetching_zones[zone_key] = true
	var err: Error = await _download_file(package_url, cache_path)
	_prefetching_zones.erase(zone_key)
	if err == OK:
		zone_download_finished.emit()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))  # drop partial
	return err

## Start downloading the current zone's package AND warming its music in the
## background. Called while the chapter intro slides are showing so the world is
## ready the instant the slides finish. Safe to call more than once.
func prefetch_current_zone() -> void:
	if not active:
		return
	var zone: Dictionary = current_zone()
	if zone.is_empty():
		return
	var zone_key: String = _current_zone_key()
	# Music is a separate endpoint — fetch it in parallel (fire-and-forget).
	MusicManager.prefetch(scene_music_context())
	await _ensure_zone_cached(zone_key, api_url(str(zone.get("package_url", ""))))

## Background-download every other zone of the current chapter so scene-to-scene
## transitions are instant once cached. Runs one zone at a time.
func prefetch_remaining_zones() -> void:
	if _prefetch_all_running:
		return
	_prefetch_all_running = true
	MusicManager.prefetch(scene_music_context())
	var run_id: String = str(flow.get("run_id", ""))
	for entry in current_chapter_zones():
		if not active:
			break
		if not (entry is Dictionary):
			continue
		var zid: String = str((entry as Dictionary).get("zone_id", ""))
		if zid.is_empty():
			continue
		var zkey: String = "%s::%d::%s" % [run_id, chapter_index, zid]
		await _ensure_zone_cached(zkey, api_url(str((entry as Dictionary).get("package_url", ""))))
	_prefetch_all_running = false

func is_zone_prefetch_in_progress() -> bool:
	return _prefetching_zones.has(_current_zone_key())

func zone_index_by_id(zone_id: String) -> int:
	var zones: Array = current_chapter_zones()
	for i in zones.size():
		if zones[i] is Dictionary and str((zones[i] as Dictionary).get("zone_id", "")) == zone_id:
			return i
	return -1

## Walk-through transition: jump to a specific connected zone in this chapter and
## spawn the player at arrival_edge. Does NOT replay the chapter intro cutscene.
func goto_zone_by_id(zone_id: String, arrival_edge: String = "") -> Error:
	if not active:
		return ERR_UNCONFIGURED
	var target_index: int = zone_index_by_id(zone_id)
	if target_index < 0:
		print("[ChapterFlow] goto_zone_by_id: unknown zone '%s'" % zone_id)
		return ERR_DOES_NOT_EXIST
	zone_index = target_index
	pending_entry_edge = arrival_edge
	_suppress_cutscene = true
	return await enter_current_zone()

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
