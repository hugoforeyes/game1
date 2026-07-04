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
var _tab_bar: Control = null
var _tabs: Array[Control] = []
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
			_set_showing_world(not _showing_world)
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
	_update_tab_bar()
	_tab_bar.visible = true
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
	if _tab_bar != null:
		_tab_bar.visible = false


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
	_build_tab_bar()


## The map screens are switched by CLICKING these two folder-style tabs sitting
## on the panel's top edge (Tab key still works as a shortcut). The active tab
## uses the gold map_kit art; the inactive one stays dark and dim.
func _build_tab_bar() -> void:
	const TAB_W := 196.0
	const TAB_H := 38.0
	const TAB_GAP := 6.0
	var vp: Vector2 = _layer.get_viewport().get_visible_rect().size
	var panel_top := (vp.y - 496.0) * 0.5
	_tab_bar = Control.new()
	_tab_bar.visible = false
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_tab_bar)

	var labels := ["BẢN ĐỒ CHƯƠNG", "BẢN ĐỒ THẾ GIỚI"]
	var total := TAB_W * 2.0 + TAB_GAP
	var x0 := (vp.x - total) * 0.5
	_tabs.clear()
	for i in range(2):
		var tab := Control.new()
		tab.position = Vector2(x0 + float(i) * (TAB_W + TAB_GAP), panel_top - TAB_H + 7.0)
		tab.size = Vector2(TAB_W, TAB_H)
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_tab_bar.add_child(tab)
		_tabs.append(tab)

		var art_path := "res://assets/ui/map_kit_v1/maptab.png"
		if ResourceLoader.exists(art_path):
			var backing := TextureRect.new()
			backing.name = "Backing"
			backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			backing.stretch_mode = TextureRect.STRETCH_SCALE
			backing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			backing.size = tab.size
			backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tab.add_child(backing)
		else:
			var panel := Panel.new()
			panel.name = "Backing"
			panel.size = tab.size
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tab.add_child(panel)

		var label := UiKit.make_title(labels[i], 14, Color(0.94, 0.90, 0.80, 0.60))
		label.name = "Caption"
		label.position = Vector2(0, 1)
		label.size = tab.size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		tab.add_child(label)

		var wants_world := i == 1
		tab.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.is_pressed() 					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_set_showing_world(wants_world)
				tab.get_viewport().set_input_as_handled()
		)
		tab.mouse_entered.connect(func() -> void:
			if (wants_world) != _showing_world:
				tab.modulate = Color(1.18, 1.12, 0.95, 1.0))
		tab.mouse_exited.connect(func() -> void:
			tab.modulate = Color.WHITE)


func _set_showing_world(world: bool) -> void:
	if not _open:
		return
	if _showing_world == world:
		return
	_showing_world = world
	_refresh_active_view()
	_update_tab_bar()


func _update_tab_bar() -> void:
	if _tab_bar == null:
		return
	for i in range(_tabs.size()):
		var tab := _tabs[i]
		var active := (i == 1) == _showing_world
		tab.modulate = Color.WHITE
		var backing := tab.get_node_or_null("Backing")
		var caption: Label = tab.get_node_or_null("Caption")
		var active_path := "res://assets/ui/map_kit_v1/maptab_active.png"
		var normal_path := "res://assets/ui/map_kit_v1/maptab.png"
		if backing is TextureRect and ResourceLoader.exists(active_path):
			(backing as TextureRect).texture = load(active_path if active else normal_path)
		elif backing is Panel:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.55, 0.42, 0.16, 0.96) if active else Color(0.03, 0.045, 0.09, 0.9)
			style.border_color = Color(1.0, 0.82, 0.40, 0.95) if active else Color(0.76, 0.58, 0.27, 0.5)
			style.set_border_width_all(1)
			style.corner_radius_top_left = 8
			style.corner_radius_top_right = 8
			(backing as Panel).add_theme_stylebox_override("panel", style)
		if caption != null:
			caption.add_theme_color_override("font_color",
				Color(0.10, 0.08, 0.03, 1.0) if active else Color(0.94, 0.90, 0.80, 0.60))
			caption.add_theme_color_override("font_shadow_color",
				Color(1, 0.92, 0.72, 0.35) if active else Color(0.02, 0.01, 0.0, 0.85))


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
