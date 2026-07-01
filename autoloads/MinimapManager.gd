extends Node
## Chapter-wide minimap ("Bản Đồ Chương") — owns the toggle state and feeds
## MinimapView with the current chapter's zone graph (from ChapterFlow.flow,
## `chapters[].minimap` — see SceneBuilder chapter_minimap()) plus live
## exploration state (QuestManager.visited_zones, the current zone).
##
## Same layer also hosts WorldMapView ("Bản Đồ Thế Giới"), the chapter-level
## sibling screen — press Tab while the map is open to swap between them. Only
## one of the two is ever visible at a time; this autoload is the single
## authority on which one currently owns input, so WorldMapView doesn't need
## its own _input override (it exposes handle_input() instead, called here).
##
## Mirrors QuestManager's journal / InventoryManager's screen: the view is pure
## presentation, this autoload is the only thing that mutates GameManager.ui_blocking_input.

const MinimapViewScript := preload("res://scripts/ui/MinimapView.gd")
const WorldMapViewScript := preload("res://scripts/ui/WorldMapView.gd")

var _layer: CanvasLayer = null
var _view: MinimapView = null
var _world_view: WorldMapView = null
var _open: bool = false
var _showing_world: bool = false
var _background_texture: Texture2D = null
var _world_background_texture: Texture2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	if _open:
		_close()
	_background_texture = null
	_world_background_texture = null
	_showing_world = false


## Called by ChapterFlow once per chapter load after downloading the painted
## world_map_illustration image (or with null when that step hasn't produced
## one yet) — cached so opening the world map never re-fetches over the network.
func set_world_background_texture(texture: Texture2D) -> void:
	_world_background_texture = texture


## Called by ChapterFlow once per chapter load after downloading the painted
## chapter_map_illustration image (or with null when that step hasn't produced
## one yet) — cached so opening the map never re-fetches over the network.
func set_background_texture(texture: Texture2D) -> void:
	_background_texture = texture


# ── input ─────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_M:
			_toggle()
			get_viewport().set_input_as_handled()
			return
		if _open and (event as InputEventKey).physical_keycode == KEY_TAB:
			_showing_world = not _showing_world
			_refresh_active_view()
			get_viewport().set_input_as_handled()
			return
	if _open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if _open and _showing_world and _world_view != null and _world_view.handle_input(event):
		get_viewport().set_input_as_handled()


# ── open / close ──────────────────────────────────────────────────────────────


func _toggle() -> void:
	if _open:
		_close()
		return
	if GameManager.ui_blocking_input or not ChapterFlow.active:
		return
	var minimap: Dictionary = ChapterFlow.current_chapter().get("minimap", {}) as Dictionary
	if (minimap.get("zones", []) as Array).is_empty():
		return  # no topology to show — never open an empty map
	_open = true
	_showing_world = false
	GameManager.ui_blocking_input = true
	_ensure_view()
	_refresh_active_view()
	var active_view: Control = _world_view if _showing_world else _view
	active_view.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(active_view, "modulate:a", 1.0, 0.18)


func _close() -> void:
	_open = false
	GameManager.ui_blocking_input = false
	if _view != null:
		_view.visible = false
	if _world_view != null:
		_world_view.visible = false


## Shows whichever of the two views is currently selected (rebuilt fresh —
## same "no caching, autoload state is read live" convention as _toggle) and
## hides the other. Called on open and every Tab press.
func _refresh_active_view() -> void:
	if not _open:
		return
	if _showing_world:
		_world_view.set_data(_build_world_view_data())
		_world_view.visible = true
		_view.visible = false
	else:
		var minimap: Dictionary = ChapterFlow.current_chapter().get("minimap", {}) as Dictionary
		_view.set_data(_build_view_data(minimap))
		_view.visible = true
		_world_view.visible = false


func _ensure_view() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 90  # above the world/party HUD, below battle
	add_child(_layer)
	_view = MinimapViewScript.new()
	_view.visible = false
	_layer.add_child(_view)
	_world_view = WorldMapViewScript.new()
	_world_view.visible = false
	_world_view.travel_requested.connect(_on_world_map_travel_requested)
	_layer.add_child(_world_view)


func _build_world_view_data() -> Dictionary:
	var world_map_payload: Dictionary = ChapterFlow.flow.get("world_map", {}) as Dictionary
	var positions_by_number: Dictionary = {}
	for raw_pos in world_map_payload.get("chapters", []) as Array:
		if raw_pos is Dictionary and (raw_pos as Dictionary).has("x_normalized"):
			positions_by_number[int((raw_pos as Dictionary).get("chapter_number", 0))] = raw_pos

	var chapters: Array = []
	for raw in ChapterFlow.chapters():
		if not (raw is Dictionary):
			continue
		var chapter_number := int((raw as Dictionary).get("chapter", 0))
		var entry := {
			"chapter_number": chapter_number,
			"title": str((raw as Dictionary).get("title", "")),
		}
		var placed: Variant = positions_by_number.get(chapter_number)
		if placed is Dictionary:
			entry["x_normalized"] = float((placed as Dictionary).get("x_normalized", 0.5))
			entry["y_normalized"] = float((placed as Dictionary).get("y_normalized", 0.5))
		chapters.append(entry)

	return {
		"current_chapter_number": int(ChapterFlow.current_chapter().get("chapter", 1)),
		"chapters": chapters,
		"completed_chapter_numbers": GameManager.completed_chapter_numbers,
		"background_texture": _world_background_texture,
	}


func _on_world_map_travel_requested(chapter_number: int) -> void:
	_close()
	await ChapterFlow.goto_chapter(chapter_number)


func _build_view_data(minimap: Dictionary) -> Dictionary:
	var visited_zone_ids: Dictionary = {}
	for zone_id in QuestManager.visited_zones.keys():
		visited_zone_ids[str(zone_id)] = true
	return {
		"current_zone_id": str(GameManager.get_scene_context().get("zone_id", "")),
		"visited_zone_ids": visited_zone_ids,
		"zones": minimap.get("zones", []) as Array,
		"background_texture": _background_texture,
	}
