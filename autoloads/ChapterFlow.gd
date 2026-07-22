extends Node
## Server-driven game flow: chapters → zones, with chapter intros.
##
## The flow comes from GET /api/godot/runs/latest — nothing is hardcoded.
## Each chapter begins with its generated intro (slides and/or in-scene
## cutscene), then its zones are played through explicit scene exits/transitions.

signal loading_status(message: String)
## Emitted whenever a zone package cache request finishes successfully.
signal zone_download_finished()

const CACHE_DIR := "user://downloads/zones"
const INTRO_IMAGE_CACHE_DIR := "user://downloads/intro"
const SLIDES_SCENE_PATH := "res://scenes/ui/ChapterIntroSlides.tscn"
const GAME_END_SCENE_PATH := "res://scenes/ui/GameEndScene.tscn"
const START_SCENE_PATH := "res://scenes/ui/StartScene.tscn"

var flow: Dictionary = {}
var chapter_index: int = 0
var zone_index: int = 0
var active: bool = false
var pending_intro: Dictionary = {}
var pending_cutscene_actions: Array = []
# One-shot legacy fallback: true only on the initial entry to the chapter's first
# zone (not on walk-back transitions). New packages use a planned zone_enter
# cutscene with role="opening"; old packages may still have opening_cutscene.
var pending_play_opening: bool = false
# When the player walks through an exit, the edge they should arrive at in the
# next scene (opposite of the exit edge). Consumed by Main on spawn.
var pending_entry_edge: String = ""
var pending_entry_normalized: float = -1.0
var pending_entry_from_zone: String = ""
var _suppress_cutscene: bool = false
# Per-zone package cache. Each zone is downloaded to its own file under
# CACHE_DIR so every zone of a chapter can be cached at once. _prefetching_zones
# maps zone_key -> true while that zone's download is in flight (dedup guard).
var _prefetching_zones: Dictionary = {}
var _prefetch_all_running: bool = false
var _prefetch_requested_chapter_index: int = -1
# The imported zone waiting behind a mandatory chapter intro. Matching this key
# lets the slides hand off without any network or world-building work.
var _prepared_zone_key: String = ""


func _ready() -> void:
	QuestManager.quests_changed.connect(_check_chapter_completion)


## Fires the moment the CURRENT chapter's story is done: every main quest
## completed and its boss zone reached (see QuestManager.are_all_main_quests_
## completed / visited_zones). Marks it in GameManager (unlocks the next
## chapter on the world map) and lets the player know — travel happens on
## their own schedule, nothing here forces a transition.
func _check_chapter_completion() -> void:
	if not active:
		return
	var chapter: Dictionary = current_chapter()
	var chapter_number := int(chapter.get("chapter", 0))
	if chapter_number <= 0 or GameManager.is_chapter_completed(chapter_number):
		return
	if not QuestManager.are_all_main_quests_completed():
		return
	var boss_zone_id := str((chapter.get("minimap", {}) as Dictionary).get("boss_zone_id", ""))
	if not boss_zone_id.is_empty() and not QuestManager.visited_zones.has(boss_zone_id):
		return
	GameManager.mark_chapter_completed(chapter_number)
	_queue_chapter_celebration(chapter_number, str(chapter.get("title", "")))


const ChapterCompleteViewScript := preload("res://scripts/ui/ChapterCompleteView.gd")
var _pending_celebration: Dictionary = {}


## The completion can fire while another screen (battle wrap-up, dialogue...)
## still blocks input — hold the celebration until the player is free, then
## play it. Polled cheaply from _process only while something is pending.
func _queue_chapter_celebration(chapter_number: int, chapter_title: String) -> void:
	_pending_celebration = {"chapter": chapter_number, "title": chapter_title}
	set_process(true)


func _process(_delta: float) -> void:
	if _pending_celebration.is_empty():
		set_process(false)
		return
	if _higher_priority_narrative_playback_pending():
		return
	var pending: Dictionary = _pending_celebration
	_pending_celebration = {}
	set_process(false)
	_show_chapter_celebration(int(pending["chapter"]), str(pending["title"]))


func _higher_priority_narrative_playback_pending() -> bool:
	# Chapter completion is the final ceremony. Shared ui_blocking_input covers
	# battles, dialogue and choices; the explicit checks below also cover gaps
	# between queued cutscenes, their letterbox teardown, and queued rewards.
	if GameManager.ui_blocking_input:
		return true
	if AnnouncementCenter.conversation_active or AnnouncementCenter.playing \
			or AnnouncementCenter.has_pending():
		return true
	return CutsceneDirector.has_pending_playback()


func _show_chapter_celebration(chapter_number: int, chapter_title: String) -> void:
	var next_chapter: Dictionary = {}
	var items: Array = chapters()
	for i in range(items.size()):
		if int((items[i] as Dictionary).get("chapter", -1)) == chapter_number and i + 1 < items.size():
			next_chapter = items[i + 1] as Dictionary
			break
	var view := ChapterCompleteViewScript.new()
	add_child(view)
	view.travel_confirmed.connect(func(next_number: int) -> void:
		goto_chapter(next_number))
	view.show_completion(chapter_number, chapter_title, next_chapter)


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

# ── balance anchor (mirror of SceneBuilder/utils/enemy_balance.py) ─────────────
# expected_player_level(chapter, zone_distance) = 1 + (chapter-1)*3 + distance.
# If you change these, change enemy_balance.py too (same rule as the level curve).
const CHAPTER_LEVEL_STEP := 3
const DISTANCE_LEVEL_STEP := 1


## The level the balance system expects the player to be in the CURRENT zone —
## the anchor GameManager.xp_gap_factor scales conversation XP against.
func expected_level_here() -> int:
	var chapter_number := maxi(1, int(current_chapter().get("chapter", 1)))
	return 1 + (chapter_number - 1) * CHAPTER_LEVEL_STEP \
		+ current_zone_distance() * DISTANCE_LEVEL_STEP


## BFS hop-distance of the current zone from the chapter's entrance zone (the
## first zone of the flow — where begin_current_chapter drops the player).
## Mirrors enemy_balance.chapter_zone_distances: undirected `connections` graph,
## unreachable zones fall back to their array order index.
func current_zone_distance() -> int:
	var zones: Array = current_chapter_zones()
	if zones.is_empty() or zone_index <= 0:
		return 0
	var current_id := str(current_zone().get("zone_id", ""))
	var adjacency: Dictionary = {}
	var order: Array[String] = []
	for entry in zones:
		if not (entry is Dictionary):
			continue
		var zid := str((entry as Dictionary).get("zone_id", ""))
		if zid.is_empty():
			continue
		order.append(zid)
		if not adjacency.has(zid):
			adjacency[zid] = {}
	for entry in zones:
		if not (entry is Dictionary):
			continue
		var zid := str((entry as Dictionary).get("zone_id", ""))
		for other in (entry as Dictionary).get("connections", []) as Array:
			var oid := str(other)
			if adjacency.has(zid) and adjacency.has(oid):
				(adjacency[zid] as Dictionary)[oid] = true
				(adjacency[oid] as Dictionary)[zid] = true
	if order.is_empty() or not adjacency.has(current_id):
		return 0
	var entrance: String = order[0]
	var distances: Dictionary = {entrance: 0}
	var queue: Array[String] = [entrance]
	var head := 0
	while head < queue.size():
		var zid: String = queue[head]
		head += 1
		for neighbor in (adjacency[zid] as Dictionary).keys():
			if not distances.has(neighbor):
				distances[neighbor] = int(distances[zid]) + 1
				queue.append(str(neighbor))
	if distances.has(current_id):
		return int(distances[current_id])
	return order.find(current_id) if order.has(current_id) else 0


func progress_label() -> String:
	var chapter: Dictionary = current_chapter()
	var zone: Dictionary = current_zone()
	if chapter.is_empty():
		return ""
	return "CHAPTER %s · %s" % [str(chapter.get("chapter", "?")), str(zone.get("name", chapter.get("title", "")))]

# ── flow control ──────────────────────────────────────────────────────────────

func start_new_game() -> Error:
	return await start_game_with_run("")

## Start a brand-new game on one SPECIFIC world (run) — the world-gacha's entry
## point after the soul chooses a door. Empty run_id falls back to the latest
## playable run (the pre-gacha behavior, kept for tools and stale-save paths).
func start_game_with_run(run_id: String) -> Error:
	loading_status.emit("Connecting to story server...")
	var flow_path: String = "/api/godot/runs/latest" if run_id.is_empty() else "/api/godot/runs/%s/flow" % run_id
	var response: Dictionary = await _http_get_json(flow_path)
	if not bool(response.get("ok", false)) or (response.get("chapters", []) as Array).is_empty():
		print("[ChapterFlow] no playable run: %s" % str(response))
		return ERR_CANT_CONNECT
	flow = response
	chapter_index = 0
	zone_index = 0
	active = true
	GameManager.reset_runtime_imports(true)
	GameManager.reset_combat_progress()  # a brand-new game starts at level 1
	SaveManager.clear_save()             # discard any previous run's save
	_clear_zone_cache()
	QuestManager.reset()
	InventoryManager.reset()
	ObjectInteractionManager.reset()
	PartyManager.reset()
	NarrativeState.reset()
	CutsceneDirector.reset()
	MinimapManager.reset()
	AnnouncementCenter.reset()
	print("[ChapterFlow] flow loaded run=%s chapters=%d" % [str(flow.get("run_id", "")), chapters().size()])
	return await begin_current_chapter()

## Public: jump directly to any chapter the world map allows (unlocked or
## completed) — the player's own choice of when to move on, not a forced
## advance. Chapter identity is the AUTHORED "chapter" number, not array
## position (the two can diverge). Returns ERR_DOES_NOT_EXIST if not found.
func goto_chapter(chapter_number: int) -> Error:
	var items: Array = chapters()
	var leaving_number := int(current_chapter().get("chapter", 0))
	if leaving_number != chapter_number:
		QuestManager.snapshot_current_chapter(leaving_number)
	for i in range(items.size()):
		if int((items[i] as Dictionary).get("chapter", -1)) == chapter_number:
			chapter_index = i
			return await begin_current_chapter()
	return ERR_DOES_NOT_EXIST


func begin_current_chapter() -> Error:
	var chapter: Dictionary = current_chapter()
	if chapter.is_empty():
		return _finish_game()
	zone_index = 0
	pending_intro = {}
	pending_cutscene_actions = []
	pending_play_opening = false
	_prepared_zone_key = ""
	# Planned-cutscene ids repeat across chapters (every chapter's opening is
	# `cs_opening_main`, ending `cs_ending_main`, etc.). The played set is per-run,
	# so without clearing it here a later chapter's opening/ending would be treated
	# as "already played" and silently skipped. begin_current_chapter only fires at
	# a chapter boundary (world-map travel or forward advance), never zone-to-zone,
	# so this never suppresses a cutscene within a chapter.
	CutsceneDirector.reset()
	await _load_chapter_content(chapter)

	# The loading screen carries the chapter's MUSIC download too, so both the
	# intro slides and the first zone start with sound already warmed.
	if not MusicManager.is_ready(scene_music_context()):
		loading_status.emit(SettingsManager.text("gacha.loading_music"))
		await MusicManager.prefetch(scene_music_context())

	loading_status.emit("Fetching chapter intro...")
	var run_id: String = str(flow.get("run_id", ""))
	var intro_response: Dictionary = await _http_get_json(
		"/api/godot/runs/%s/chapters/%d/intro" % [run_id, int(chapter.get("chapter", 0))]
	)
	if not bool(intro_response.get("ok", false)):
		print("[ChapterFlow] required chapter intro request failed: %s" % str(intro_response))
		return ERR_CANT_CONNECT
	pending_intro = intro_response.get("chapter_intro", {}) as Dictionary
	var intro_prepare_error := await _prepare_intro_slides()
	if intro_prepare_error != OK:
		return intro_prepare_error
	var cutscene_payload: Variant = pending_intro.get("cutscene", {})
	var cutscene_action_count := 0
	if cutscene_payload is Dictionary:
		cutscene_action_count = ((cutscene_payload as Dictionary).get("actions", []) as Array).size()
	print("[ChapterFlow] chapter %s intro mode='%s' slides=%d cutscene_actions=%d" % [
		str(chapter.get("chapter", "?")),
		str(pending_intro.get("recommended_mode", "none")),
		(pending_intro.get("slides", []) as Array).size(),
		cutscene_action_count,
	])

	var zone_prepare_error := await prepare_current_zone()
	if zone_prepare_error != OK:
		return zone_prepare_error
	# Start the cached chapter track as the mandatory intro opens. MusicManager is
	# an autoload, so the same playback continues seamlessly into the world.
	await MusicManager.load_and_play(GameManager.get_scene_context())
	# The slideshow is a required chapter beat. recommended_mode only controls
	# the optional in-world cutscene fallback after these slides.
	get_tree().change_scene_to_file(SLIDES_SCENE_PATH)
	return OK


## Download and validate every slide image during the loading phase. The scene
## receives stable local paths instead of transient ImageTexture objects, so a
## scene change cannot drop the artwork and the slideshow performs no network IO.
func _prepare_intro_slides() -> Error:
	var source_slides: Array = pending_intro.get("slides", []) as Array
	var prepared_slides: Array = []
	for slide_index in range(source_slides.size()):
		var raw_slide: Variant = source_slides[slide_index]
		if not (raw_slide is Dictionary):
			continue
		var slide := (raw_slide as Dictionary).duplicate(true)
		var image_url := str(slide.get("image_url", ""))
		if image_url.is_empty():
			print("[ChapterFlow] required intro slide %d has no image URL" % [slide_index + 1])
			return ERR_FILE_NOT_FOUND
		var local_path := await _ensure_intro_image_cached(image_url)
		if local_path.is_empty():
			print("[ChapterFlow] intro slide image preparation failed url=%s" % image_url)
			return ERR_CANT_CONNECT
		slide["_runtime_image_path"] = local_path
		prepared_slides.append(slide)
	if prepared_slides.is_empty():
		print("[ChapterFlow] required chapter intro contains no valid slides")
		return ERR_FILE_CORRUPT
	pending_intro["slides"] = prepared_slides
	return OK


func _ensure_intro_image_cached(image_url: String) -> String:
	var cache_name := "%s.png" % image_url.sha256_text()
	var cache_path := INTRO_IMAGE_CACHE_DIR.path_join(cache_name)
	if FileAccess.file_exists(cache_path):
		if _is_valid_intro_image(cache_path):
			return cache_path
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	var download_error := await _download_file(api_url(image_url), cache_path)
	if download_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
		return ""
	if not _is_valid_intro_image(cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
		return ""
	return cache_path


func _is_valid_intro_image(path: String) -> bool:
	var image := Image.new()
	return image.load(path) == OK and image.get_width() > 0 and image.get_height() > 0


## Load a chapter's content catalogs (quests, item catalog + icons, companion roster
## + sprites). Shared by begin_current_chapter and continue_saved_game.
func _load_chapter_content(chapter: Dictionary) -> void:
	PartyManager.begin_chapter_party_load()
	QuestManager.load_chapter_quests(chapter.get("quests", []) as Array)
	# Revisiting a chapter (world map travel) restores its own quest progress instead of
	# starting fresh — no-op on a chapter's first-ever visit (nothing snapshotted yet).
	QuestManager.restore_chapter_snapshot(int(chapter.get("chapter", 0)))

	# Moral-choice card art (optional) — the zone-level scene_choice_illustrations
	# step paints one anime panel per option; prefetch so the ceremony opens with
	# its cards already dressed. MoralChoiceView still lazy-downloads as a backstop.
	for raw_quest in chapter.get("quests", []) as Array:
		if not (raw_quest is Dictionary):
			continue
		for raw_objective in (raw_quest as Dictionary).get("objectives", []) as Array:
			if not (raw_objective is Dictionary) or str((raw_objective as Dictionary).get("kind", "")) != "choice":
				continue
			for raw_option in (raw_objective as Dictionary).get("options", []) as Array:
				if not (raw_option is Dictionary):
					continue
				var illustration_url := str((raw_option as Dictionary).get("illustration_url", ""))
				if illustration_url.is_empty():
					continue
				var illustration: Texture2D = await download_image_texture(illustration_url)
				if illustration != null:
					QuestManager.set_choice_illustration(str((raw_option as Dictionary).get("id", "")), illustration)

	var items_payload: Dictionary = chapter.get("items", {}) as Dictionary
	if not (items_payload.get("items", []) as Array).is_empty():
		var icon_url: String = str(chapter.get("items_icon_url", ""))
		var icon_texture: Texture2D = null
		if not icon_url.is_empty():
			loading_status.emit("Fetching item icons...")
			icon_texture = await download_image_texture(icon_url)
		InventoryManager.load_chapter_catalog(items_payload, icon_texture)

	# Party roster — load events/objective-driven escorts, then fetch walk sheets
	# and portraits so both companion and protected-escort followers survive zones.
	var party_payload: Dictionary = chapter.get("party", {}) as Dictionary
	PartyManager.load_chapter_party(party_payload)
	for raw_companion in party_payload.get("companions", []) as Array:
		if not (raw_companion is Dictionary):
			continue
		var companion := raw_companion as Dictionary
		var sprite_url := str(companion.get("sprite_url", ""))
		if not sprite_url.is_empty():
			var sprite_texture: Texture2D = await download_image_texture(sprite_url)
			PartyManager.set_companion_texture(str(companion.get("npc_id", "")), sprite_texture)
		var portrait_url := str(companion.get("portrait_url", ""))
		if not portrait_url.is_empty():
			var portrait_texture: Texture2D = await download_image_texture(portrait_url)
			PartyManager.set_companion_portrait(str(companion.get("npc_id", "")), portrait_texture)
	for raw_escort in party_payload.get("escorts", []) as Array:
		if not (raw_escort is Dictionary):
			continue
		var escort := raw_escort as Dictionary
		var npc_id := str(escort.get("npc_id", ""))
		var sprite_url := str(escort.get("sprite_url", ""))
		if not sprite_url.is_empty():
			var sprite_texture: Texture2D = await download_image_texture(sprite_url)
			PartyManager.set_escort_texture(npc_id, sprite_texture)
		var portrait_url := str(escort.get("portrait_url", ""))
		if not portrait_url.is_empty():
			var portrait_texture: Texture2D = await download_image_texture(portrait_url)
			PartyManager.set_escort_portrait(npc_id, portrait_texture)

	# Chapter map illustration (optional) — painted region art for the minimap
	# background. Re-fetched per chapter; null when the BE step hasn't produced
	# one yet, so MinimapView falls back to its procedural look.
	var minimap_payload: Dictionary = chapter.get("minimap", {}) as Dictionary
	var minimap_bg_url := str(minimap_payload.get("background_image_url", ""))
	if not minimap_bg_url.is_empty():
		loading_status.emit("Fetching chapter map illustration...")
		var minimap_bg_texture: Texture2D = await download_image_texture(minimap_bg_url)
		MinimapManager.set_background_texture(minimap_bg_texture)
	else:
		MinimapManager.set_background_texture(null)

	# World map illustration (optional, world-scoped not per-chapter — re-fetched
	# on each chapter load same as the minimap one above; MinimapManager just
	# caches whatever it's given, so a redundant re-fetch is harmless).
	var world_map_payload: Dictionary = flow.get("world_map", {}) as Dictionary
	var world_bg_url := str(world_map_payload.get("background_image_url", ""))
	if not world_bg_url.is_empty():
		loading_status.emit("Fetching world map illustration...")
		var world_bg_texture: Texture2D = await download_image_texture(world_bg_url)
		MinimapManager.set_world_background_texture(world_bg_texture)
	else:
		MinimapManager.set_world_background_texture(null)


## Position snapshot for SaveManager — where the player is in the chapter→zone flow.
func serialize_position() -> Dictionary:
	return {
		"run_id": str(flow.get("run_id", "")),
		"chapter_index": chapter_index,
		"zone_index": zone_index,
		"chapter_number": int(current_chapter().get("chapter", 0)),
		"zone_id": str(current_zone().get("zone_id", "")),
	}


## Resume a saved run: re-fetch the flow, and if it is the SAME world the save was
## made in, restore the chapter/zone position + all progression and drop the player
## straight back into the saved zone (no intro). Falls back to a new game if there is
## no save or the saved world is no longer the latest one.
func continue_saved_game() -> Error:
	var snapshot: Dictionary = SaveManager.peek()
	var saved_flow: Dictionary = snapshot.get("flow", {}) as Dictionary
	if snapshot.is_empty() or saved_flow.is_empty():
		return await start_new_game()

	loading_status.emit("Connecting to story server...")
	# Resume the SAVED world directly (worlds are chosen per-run via the gacha,
	# so "latest" is no longer the save's world in general).
	var saved_run_id: String = str(saved_flow.get("run_id", ""))
	var flow_path: String = (
		"/api/godot/runs/%s/flow" % saved_run_id if not saved_run_id.is_empty()
		else "/api/godot/runs/latest"
	)
	var response: Dictionary = await _http_get_json(flow_path)
	if not bool(response.get("ok", false)) or (response.get("chapters", []) as Array).is_empty():
		# The saved world no longer exists server-side — the save is stale.
		print("[ChapterFlow] saved run not playable anymore; starting a new game")
		return await start_new_game()
	flow = response
	if saved_run_id != str(flow.get("run_id", "")):
		print("[ChapterFlow] saved run mismatch; starting a new game")
		return await start_new_game()

	active = true
	GameManager.reset_runtime_imports(true)
	GameManager.reset_combat_progress()
	_clear_zone_cache()
	QuestManager.reset()
	InventoryManager.reset()
	ObjectInteractionManager.reset()
	PartyManager.reset()
	NarrativeState.reset()
	CutsceneDirector.reset()
	MinimapManager.reset()
	AnnouncementCenter.reset()

	chapter_index = clampi(int(saved_flow.get("chapter_index", 0)), 0, maxi(chapters().size() - 1, 0))
	var chapter: Dictionary = current_chapter()
	if chapter.is_empty():
		return await start_new_game()
	pending_intro = {}
	pending_cutscene_actions = []
	pending_play_opening = false
	await _load_chapter_content(chapter)

	# Restore progression/quests/inventory/party onto the freshly loaded catalogs.
	SaveManager.apply_to_managers(snapshot)

	zone_index = clampi(int(saved_flow.get("zone_index", 0)), 0, maxi(current_chapter_zones().size() - 1, 0))
	_suppress_cutscene = true  # do not replay the opening on a resume
	print("[ChapterFlow] continuing run=%s chapter=%d zone=%d level=%d" % [
		str(flow.get("run_id", "")), chapter_index, zone_index, GameManager.player_level,
	])
	return await enter_current_zone()

## Download and import the current zone without changing scenes. Chapter starts
## call this before the mandatory slides so the intro contains no hidden loading.
func prepare_current_zone() -> Error:
	var zone: Dictionary = current_zone()
	if zone.is_empty():
		return _finish_game()

	var package_url: String = api_url(str(zone.get("package_url", "")))
	var zone_key: String = _current_zone_key()
	if _prepared_zone_key == zone_key:
		return OK
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

	# Legacy in-scene intro cutscene plays in the chapter's first zone only, and
	# never when the player merely walked back into a zone through an exit.
	pending_cutscene_actions = []
	# New packages play opening through CutsceneDirector as a planned zone_enter
	# beat. This only gates legacy opening_cutscene/chapter-intro fallback.
	pending_play_opening = (zone_index == 0 and not _suppress_cutscene)
	var mode: String = str(pending_intro.get("recommended_mode", ""))
	# Some intro manifests carry "cutscene": null — a bare `as Dictionary` cast
	# would raise an invalid-cast script error on those.
	var cutscene_variant: Variant = pending_intro.get("cutscene", {})
	var cutscene: Dictionary = cutscene_variant if cutscene_variant is Dictionary else {}
	if pending_play_opening and mode in ["cutscene", "both"]:
		if str(cutscene.get("zone_id", "")) == str(zone.get("zone_id", "")):
			pending_cutscene_actions = (cutscene.get("actions", []) as Array).duplicate(true)
	_suppress_cutscene = false
	_prepared_zone_key = zone_key
	return OK


## General entry path used by saves and zone exits. These routes may still need
## preparation because they do not pass through the chapter intro loading phase.
func enter_current_zone() -> Error:
	var prepare_error := await prepare_current_zone()
	if prepare_error != OK:
		return prepare_error

	if not MusicManager.is_ready(GameManager.get_scene_context()):
		loading_status.emit("Loading music...")
	await MusicManager.load_and_play(GameManager.get_scene_context())
	return _commit_prepared_zone_entry()


## Mandatory intro handoff. All remote data and world building completed before
## the slides opened, so this path performs no downloads and changes scene now.
func enter_prepared_current_zone() -> Error:
	if _prepared_zone_key != _current_zone_key():
		push_error("Chapter intro finished without a prepared current zone")
		return ERR_UNCONFIGURED
	# Chapter music already started before the intro scene and must not restart
	# when the final slide hands off to gameplay.
	return _commit_prepared_zone_entry()


func _commit_prepared_zone_entry() -> Error:
	# Start caching later zones only after the intro has finished and gameplay is
	# entering, never while the mandatory slides are on screen.
	prefetch_remaining_zones()
	# Runtime slide textures are no longer needed once the intro hands off.
	pending_intro = {}
	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)
	# Persist the new position + progression so a later "Continue" resumes here.
	SaveManager.request_autosave()
	return OK

func take_pending_cutscene() -> Array:
	var actions: Array = pending_cutscene_actions
	pending_cutscene_actions = []
	return actions

func take_pending_opening() -> bool:
	var should: bool = pending_play_opening
	pending_play_opening = false
	return should

func take_pending_entry_edge() -> String:
	var edge: String = pending_entry_edge
	pending_entry_edge = ""
	return edge

func take_pending_entry_normalized() -> float:
	var normalized: float = pending_entry_normalized
	pending_entry_normalized = -1.0
	return normalized

func take_pending_entry_from_zone() -> String:
	var zone_id: String = pending_entry_from_zone
	pending_entry_from_zone = ""
	return zone_id

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
	_prefetch_requested_chapter_index = -1
	_prepared_zone_key = ""
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

## Background-download the current chapter one zone at a time. Only after every
## package in it is cached, continue with the next chapter so advancing there is
## instant too. Calls made while the worker is busy are remembered (for example
## when the player travels to another chapter from the world map).
func prefetch_remaining_zones() -> void:
	if not active:
		return
	_prefetch_requested_chapter_index = chapter_index
	if _prefetch_all_running:
		return
	_prefetch_all_running = true
	while active and _prefetch_requested_chapter_index >= 0:
		var requested_index := _prefetch_requested_chapter_index
		_prefetch_requested_chapter_index = -1
		var current_chapter_complete := await _prefetch_chapter_zones(requested_index)
		if current_chapter_complete and active:
			await _prefetch_chapter_zones(requested_index + 1)
	_prefetch_all_running = false


## Cache every zone package (and warm the music) for one chapter without changing
## chapter_index/zone_index or loading that chapter's catalogs into live managers.
## Returns false when a package fails so the following chapter is not started
## before the requested chapter is genuinely complete.
func _prefetch_chapter_zones(target_chapter_index: int) -> bool:
	var chapter_items: Array = chapters()
	if target_chapter_index < 0 or target_chapter_index >= chapter_items.size():
		return true
	if not (chapter_items[target_chapter_index] is Dictionary):
		return false
	var chapter: Dictionary = chapter_items[target_chapter_index] as Dictionary
	var run_id: String = str(flow.get("run_id", ""))
	MusicManager.prefetch({
		"run_id": run_id,
		"chapter": int(chapter.get("chapter", target_chapter_index + 1)),
	})
	for entry in chapter.get("zones", []) as Array:
		if not active:
			return false
		if not (entry is Dictionary):
			continue
		var zid: String = str((entry as Dictionary).get("zone_id", ""))
		if zid.is_empty():
			continue
		var zkey: String = "%s::%d::%s" % [run_id, target_chapter_index, zid]
		var err := await _ensure_zone_cached(
			zkey,
			api_url(str((entry as Dictionary).get("package_url", "")))
		)
		if err != OK:
			print("[ChapterFlow] chapter prefetch stopped chapter=%d zone=%s err=%d" % [
				int(chapter.get("chapter", target_chapter_index + 1)), zid, err,
			])
			return false
	print("[ChapterFlow] chapter %d cached in background" % int(
		chapter.get("chapter", target_chapter_index + 1)
	))
	return true

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
func goto_zone_by_id(zone_id: String, arrival_edge: String = "", arrival_normalized: float = -1.0) -> Error:
	if not active:
		return ERR_UNCONFIGURED
	var from_zone_id: String = str(current_zone().get("zone_id", ""))
	var target_index: int = zone_index_by_id(zone_id)
	if target_index < 0:
		print("[ChapterFlow] goto_zone_by_id: unknown zone '%s'" % zone_id)
		return ERR_DOES_NOT_EXIST
	zone_index = target_index
	pending_entry_edge = arrival_edge
	pending_entry_normalized = arrival_normalized
	pending_entry_from_zone = from_zone_id
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

# ── world gacha (reincarnation screen) ───────────────────────────────────────

## Up to `count` random playable worlds for the reincarnation screen. Each entry
## has run_id + ready; ready ones carry name/tagline/traits (EN+VI), accent_color
## and gate_image_url. [] on connection failure.
func fetch_world_candidates(count: int = 3) -> Array:
	var response: Dictionary = await _http_get_json("/api/godot/worlds/candidates?count=%d" % count)
	if not bool(response.get("ok", false)):
		return []
	return response.get("candidates", []) as Array

## Ask the server to generate a world's identity (name + gate art) on the spot —
## the fallback when the gacha drew a world whose identity was never pre-built.
## Generation runs an LLM call plus one image render, so this can take minutes;
## the goddess "searching" phase is designed to cover exactly this wait.
func request_world_identity(run_id: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 600.0
	add_child(request)
	var body: String = JSON.stringify({"run_id": run_id, "provider": "openai_extension"})
	var start_error: Error = request.request(
		api_url("/api/world-identity/generate"),
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body,
	)
	if start_error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}

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
