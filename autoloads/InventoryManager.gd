extends Node
## Inventory runtime: item catalog (from the chapter_items step), owned counts,
## icons (downloaded AI sheet, sliced), use effects, and the inventory screen.
##
## Obtain paths: world pickups, battle drops, quest events. Use paths:
## overworld inventory screen (heal/lore), battle Item menu (heal/energy/buff),
## quest deliver (consumed on hand-over). Quest items cannot be discarded.

signal inventory_changed
signal item_obtained(item_id: String)

var catalog: Array = []                 # item definitions in icon order
var counts: Dictionary = {}             # item_id -> int owned
var drop_chance: Dictionary = {"minion": 0.45, "elite": 1.0, "boss": 1.0}
var acquisition_claims: Dictionary = {}

var _icon_sheet: Texture2D = null
var _icon_grid: int = 3
var _icon_cell_px: int = 48

var _ui: CanvasLayer = null
var _screen_root: Control
var _screen_open: bool = false
var _slot_nodes: Array[Control] = []
var _tab_nodes: Array[Control] = []
var _active_filter: String = "all"
var _selected: int = 0
var _top_stats: Label
var _page_label: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_owned: Label
var _detail_body: Label
var _action_hint: Label
var _action_button_label: Label
var _toast_host: Control
var _toast_queue: Array = []
var _toast_busy: bool = false
var _inventory_texture_cache: Dictionary = {}

# ── item detail view (BE-authored per-item text/image, chapter_item_details) ──
var _detail_view_root: Control
var _detail_view_title: Label
var _detail_view_caption: Label
var _detail_view_text: Label
var _detail_view_image: TextureRect
var _detail_view_open: bool = false
var _detail_view_current_item_id: String = ""
var _detail_image_cache: Dictionary = {}   # item_id -> Texture2D, session-lifetime

const INV_SLOT_COLUMNS := 6
const INV_SLOT_VISIBLE := 24
const INV_FILTER_IDS := ["all", "use", "battle", "quest", "lore"]
const INV_FILTER_LABELS := ["All", "Use", "Battle", "Quest", "Lore"]
const INV_TEX_PANEL_MAIN := "res://assets/ui/inventory/panel_main.png"
const INV_TEX_PANEL_DETAIL := "res://assets/ui/inventory/panel_detail.png"
const INV_TEX_PANEL_SIDEBAR := "res://assets/ui/inventory/panel_sidebar.png"
const INV_TEX_SLOT := "res://assets/ui/inventory/slot.png"
const INV_TEX_SLOT_SELECTED := "res://assets/ui/inventory/slot_selected.png"
const INV_TEX_TAB := "res://assets/ui/inventory/tab.png"
const INV_TEX_TAB_SELECTED := "res://assets/ui/inventory/tab_selected.png"
const INV_TEX_BUTTON := "res://assets/ui/inventory/button_action.png"
const INV_TEX_FOOTER_BAR := "res://assets/ui/inventory/footer_bar.png"
const INV_TEX_DIVIDER := "res://assets/ui/inventory/divider.png"
const INV_TEX_GEM := "res://assets/ui/inventory/ornament_gem.png"
const INV_TEX_SPARKLE_GOLD := "res://assets/ui/inventory/sparkle_gold.png"
const INV_TEX_SPARKLE_BLUE := "res://assets/ui/inventory/sparkle_blue.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	catalog = []
	counts = {}
	acquisition_claims = {}
	_icon_sheet = null
	_detail_image_cache.clear()
	_close_item_detail_view()
	inventory_changed.emit()


# ── persistence (SaveManager) ──────────────────────────────────────────────────
## Only the player's owned counts + acquisition claims are saved; the catalog/icons
## are re-loaded from the chapter package on load, so they are not stored.


func serialize_save() -> Dictionary:
	return {
		"counts": counts.duplicate(true),
		"acquisition_claims": acquisition_claims.duplicate(true),
	}


func apply_save(data: Dictionary) -> void:
	counts = (data.get("counts", {}) as Dictionary).duplicate(true)
	acquisition_claims = (data.get("acquisition_claims", {}) as Dictionary).duplicate(true)
	inventory_changed.emit()


func load_chapter_catalog(items_payload: Dictionary, icon_sheet: Texture2D) -> void:
	catalog = items_payload.get("items", []) as Array
	_icon_grid = int(items_payload.get("icon_grid", 3))
	_icon_cell_px = int(items_payload.get("icon_cell_px", 48))
	var chances: Dictionary = items_payload.get("drop_chance", {}) as Dictionary
	if not chances.is_empty():
		drop_chance = chances
	_icon_sheet = icon_sheet
	# Owned quest progress carries across zones; counts persist per session.
	for item in catalog:
		var item_id: String = str((item as Dictionary).get("id", ""))
		if not counts.has(item_id):
			counts[item_id] = 0
	print("[Inventory] catalog loaded: %d items, icons=%s" % [catalog.size(), _icon_sheet != null])
	_ensure_ui()
	inventory_changed.emit()


# ── catalog lookups ───────────────────────────────────────────────────────────


func item_def(item_id: String) -> Dictionary:
	for item in catalog:
		if item is Dictionary and str((item as Dictionary).get("id")) == item_id:
			return item as Dictionary
	return {}


func quest_item_for(quest_id: String) -> Dictionary:
	for item in catalog:
		if item is Dictionary and str((item as Dictionary).get("kind")) == "quest" \
				and str((item as Dictionary).get("quest_id")) == quest_id:
			return item as Dictionary
	return {}


# The story keepsake granted on completing this quest (distinct from the
# collect/deliver item above). role == "reward" set by chapter_items.
func reward_item_for(quest_id: String) -> Dictionary:
	for item in catalog:
		if item is Dictionary and str((item as Dictionary).get("role")) == "reward" \
				and str((item as Dictionary).get("quest_id")) == quest_id:
			return item as Dictionary
	return {}


func quest_item_by_id(item_id: String, quest_id: String = "") -> Dictionary:
	if not item_id.is_empty():
		var direct := item_def(item_id)
		if not direct.is_empty():
			return direct
	return quest_item_for(quest_id)


func count_of(item_id: String) -> int:
	return int(counts.get(item_id, 0))


func icon_for(item_def_dict: Dictionary) -> Texture2D:
	if _icon_sheet == null:
		return null
	var index: int = int(item_def_dict.get("icon_index", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = _icon_sheet
	atlas.region = Rect2(
		(index % _icon_grid) * _icon_cell_px,
		int(index / _icon_grid) * _icon_cell_px,
		_icon_cell_px, _icon_cell_px,
	)
	return atlas


func usable_in_battle() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in catalog:
		if not (item is Dictionary):
			continue
		var kind: String = str((item as Dictionary).get("kind"))
		if kind in ["heal", "energy", "buff"] and count_of(str((item as Dictionary).get("id"))) > 0:
			result.append(item as Dictionary)
	return result


# ── obtain / consume ──────────────────────────────────────────────────────────


func add_item(item_id: String, amount: int = 1, silent: bool = false) -> void:
	var definition: Dictionary = item_def(item_id)
	if definition.is_empty():
		return
	counts[item_id] = count_of(item_id) + amount
	if not silent:
		_push_toast("✚ %s ×%d" % [definition.get("name", item_id), amount])
	item_obtained.emit(item_id)
	inventory_changed.emit()


func remove_item(item_id: String, amount: int = 1) -> bool:
	if count_of(item_id) < amount:
		return false
	counts[item_id] = count_of(item_id) - amount
	inventory_changed.emit()
	return true


func roll_battle_drop(enemy_rank: String) -> String:
	if randf() > float(drop_chance.get(enemy_rank, 0.4)):
		return ""
	var pool: Array[String] = []
	for item in catalog:
		if item is Dictionary and bool((item as Dictionary).get("droppable", false)):
			pool.append(str((item as Dictionary).get("id")))
	if pool.is_empty():
		return ""
	var item_id: String = pool[randi() % pool.size()]
	add_item(item_id)
	return item_id


func grant_linked_items(
		mode: String,
		source_entity_id: String,
		zone_id: String,
		quest_id: String = "",
		objective_id: String = "",
	) -> Array[String]:
	## Execute chapter-authored acquisition links. The concrete runtime instance ID
	## may have a `__02` suffix while the rule targets its shared template ID.
	var granted: Array[String] = []
	for raw_item in catalog:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item as Dictionary
		for raw_rule in item.get("acquisition", []) as Array:
			if not (raw_rule is Dictionary):
				continue
			var rule: Dictionary = raw_rule as Dictionary
			if str(rule.get("mode", "")) != mode:
				continue
			var source := str(rule.get("source_entity_id", ""))
			if not source.is_empty() and source_entity_id != source \
					and not source_entity_id.begins_with(source + "__"):
				continue
			var rule_zone := str(rule.get("zone_id", ""))
			if not rule_zone.is_empty() and rule_zone != zone_id:
				continue
			var rule_objective := str(rule.get("objective_id", ""))
			if not rule_objective.is_empty() and not objective_id.is_empty() \
					and rule_objective != objective_id:
				continue
			var item_quests: Array = item.get("quest_ids", []) as Array
			if not quest_id.is_empty() and not item_quests.is_empty() and not item_quests.has(quest_id):
				continue
			var claim_source := source_entity_id if mode == "enemy_drop" else source
			var claim_key := "%s:%s:%s:%s" % [mode, claim_source, item.get("id", ""), rule_objective]
			if acquisition_claims.has(claim_key):
				continue
			if randf() > float(rule.get("chance", 1.0)):
				acquisition_claims[claim_key] = true
				continue
			acquisition_claims[claim_key] = true
			var item_id := str(item.get("id", ""))
			add_item(item_id, maxi(1, int(rule.get("count", 1))))
			granted.append(item_id)
	return granted


## Returns a result message, or "" if the item could not be used here.
func use_item_overworld(item_id: String) -> String:
	var definition: Dictionary = item_def(item_id)
	match str(definition.get("kind", "")):
		"heal":
			var max_hp: int = int(GameManager.player_battle_stats().get("max_hp", 80))
			if GameManager.get_player_hp() >= max_hp:
				return "HP đã đầy."
			if not remove_item(item_id):
				return ""
			GameManager.set_player_hp(GameManager.get_player_hp() + int(definition.get("power", 40)))
			return "Hồi %d HP." % int(definition.get("power", 40))
		"lore":
			return str(definition.get("lore_text", definition.get("description", "")))
		_:
			return "Chỉ dùng được trong chiến đấu." if str(definition.get("kind")) in ["energy", "buff"] else ""


# ── inventory screen ──────────────────────────────────────────────────────────


func _inventory_style(texture_path: String, margin: float = 12.0) -> StyleBox:
	var texture := _inventory_texture(texture_path)
	if texture != null:
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.draw_center = true
		style.set_texture_margin_all(margin)
		style.set_content_margin_all(4.0)
		return style
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.04, 0.045, 0.06, 0.94)
	flat.border_color = UiKit.COLOR_PANEL_BORDER
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	return flat


func _inventory_texture(texture_path: String) -> Texture2D:
	if _inventory_texture_cache.has(texture_path):
		return _inventory_texture_cache[texture_path]
	var texture: Texture2D = null
	var image := Image.new()
	var err := image.load(ProjectSettings.globalize_path(texture_path))
	if err == OK:
		texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(texture_path):
		texture = load(texture_path)
	_inventory_texture_cache[texture_path] = texture
	return texture


func _make_texture_panel(rect: Rect2, texture_path: String, margin: float = 12.0) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _inventory_style(texture_path, margin))
	return panel


func _glass_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.022, 0.030, 0.88)
	style.border_color = Color(0.76, 0.58, 0.27, 0.90)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 2)
	return style


func _footer_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.025, 0.032, 0.72)
	style.border_color = Color(0.76, 0.58, 0.27, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _filter_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.028, 0.037, 0.72)
	style.border_color = Color(0.76, 0.58, 0.27, 0.64)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 1)
	return style


func _slot_style(selected: bool, empty: bool = false) -> StyleBox:
	# aaa_kit_v1 slot art baked at the exact 70x68 slot size, so the
	# StyleBoxTexture margins map 1:1 and nothing deforms.
	var texture := UiKit.kit_texture("slot_selected_70.png" if selected else "slot_70.png")
	if texture != null:
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.set_texture_margin_all(10.0)
		if empty and not selected:
			style.modulate_color = Color(0.62, 0.64, 0.72, 0.55)
		return style
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.015, 0.020, 0.026, 0.88 if not empty else 0.46)
	flat.border_color = Color(1.0, 0.78, 0.28, 1.0) if selected else Color(0.55, 0.43, 0.24, 0.66)
	flat.set_border_width_all(3 if selected else 1)
	flat.set_corner_radius_all(5)
	flat.shadow_color = Color(1.0, 0.74, 0.18, 0.42) if selected else Color(0, 0, 0, 0.22)
	flat.shadow_size = 12 if selected else 3
	flat.shadow_offset = Vector2.ZERO
	return flat


func _tab_style(active: bool) -> StyleBox:
	var texture := UiKit.kit_texture("tab_96.png")
	if texture != null:
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.set_texture_margin_all(9.0)
		style.modulate_color = Color(1.24, 1.12, 0.86, 1.0) if active else Color(0.55, 0.58, 0.68, 0.82)
		return style
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.13, 0.12, 0.09, 0.76) if active else Color(0.015, 0.025, 0.033, 0.36)
	flat.border_color = Color(1.0, 0.78, 0.32, 0.86) if active else Color(0.76, 0.58, 0.27, 0.24)
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(6)
	return flat


func _make_glass_panel(rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	if UiKit.kit_texture("panel_frame.png") != null:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		panel.add_child(UiKit.make_ornate_frame(rect.size, "panel_frame.png", 0.16, 26.0))
	else:
		panel.add_theme_stylebox_override("panel", _glass_panel_style())
	return panel


func _make_texture_rect(texture_path: String, rect: Rect2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = _inventory_texture(texture_path)
	# expand_mode must be set before size: with the default EXPAND_KEEP_SIZE the
	# control clamps to the texture's native size and never shrinks back.
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	return texture_rect


func _catalog_pages() -> int:
	return maxi(1, ceili(float(_filtered_catalog_indices().size()) / float(INV_SLOT_VISIBLE)))


func _selected_page() -> int:
	return int(_selected / INV_SLOT_VISIBLE)


func _max_selectable_index() -> int:
	return maxi(0, _filtered_catalog_indices().size() - 1)


func _filtered_catalog_indices() -> Array[int]:
	var result: Array[int] = []
	for index in range(catalog.size()):
		var definition: Dictionary = catalog[index] as Dictionary
		if _item_matches_filter(definition):
			result.append(index)
	return result


func _item_matches_filter(definition: Dictionary) -> bool:
	var kind := str(definition.get("kind"))
	match _active_filter:
		"use":
			return kind in ["heal", "energy", "buff"]
		"battle":
			return kind in ["energy", "buff"]
		"quest":
			return kind == "quest"
		"lore":
			return kind == "lore"
		_:
			return true


func _definition_at_filtered_index(filtered_index: int) -> Dictionary:
	var indices := _filtered_catalog_indices()
	if filtered_index < 0 or filtered_index >= indices.size():
		return {}
	var catalog_index := indices[filtered_index]
	if catalog_index < 0 or catalog_index >= catalog.size():
		return {}
	return catalog[catalog_index] as Dictionary


func _set_filter(filter_id: String) -> void:
	if filter_id == _active_filter:
		return
	_active_filter = filter_id
	_selected = 0
	_refresh_screen()


func _set_selected_from_slot(visible_slot_index: int) -> void:
	var item_index := _selected_page() * INV_SLOT_VISIBLE + visible_slot_index
	if item_index >= _filtered_catalog_indices().size():
		return
	_selected = item_index
	_refresh_screen()


func _owned_total() -> int:
	var total := 0
	for item in catalog:
		if item is Dictionary:
			total += count_of(str((item as Dictionary).get("id")))
	return total


func _kind_text(definition: Dictionary) -> String:
	var kind: String = str(definition.get("kind"))
	return {
		"heal": "CONSUMABLE · +%d HP" % int(definition.get("power", 0)),
		"energy": "BATTLE · +%d SP" % int(definition.get("power", 2)),
		"buff": "BATTLE · DAMAGE UP",
		"quest": "QUEST ITEM",
		"lore": "LORE · READABLE",
	}.get(kind, kind.to_upper())


func _detail_preview_text(text: String, limit: int = 64) -> String:
	var clean := text.strip_edges()
	if clean.length() <= limit:
		return clean
	var cut := clean.substr(0, limit)
	var last_space := cut.rfind(" ")
	if last_space > 42:
		cut = cut.substr(0, last_space)
	return cut.strip_edges() + "..."


func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 46
	_ui.transform = Transform2D.IDENTITY
	add_child(_ui)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	_toast_host = Control.new()
	_toast_host.position = Vector2(vp.x * 0.5, 60)
	_ui.add_child(_toast_host)

	_screen_root = Control.new()
	_screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_root.visible = false
	_ui.add_child(_screen_root)

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.014, 0.90)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(dim)

	var embers := UiKit.make_ember_particles(vp)
	embers.amount = 28
	embers.color = Color(1.0, 0.78, 0.35, 0.32)
	_screen_root.add_child(embers)

	# The inventory layout is authored for a 960x540 canvas; keep that composition
	# and center it inside wider viewports (dim + embers above stay full-screen).
	var canvas := Control.new()
	canvas.position = ((vp - Vector2(960, 540)) * 0.5).floor()
	canvas.size = Vector2(960, 540)
	_screen_root.add_child(canvas)

	var header_line := ColorRect.new()
	header_line.color = Color(0.76, 0.58, 0.27, 0.72)
	header_line.position = Vector2(272, 61)
	header_line.size = Vector2(594, 2)
	canvas.add_child(header_line)
	var header_gem := _make_texture_rect(INV_TEX_GEM, Rect2(454, 22, 72, 40))
	header_gem.modulate = Color(1, 1, 1, 0.78)
	canvas.add_child(header_gem)

	var header := UiKit.make_title("HÀNH TRANG", 30, UiKit.COLOR_ACCENT)
	header.position = Vector2(48, 34)
	header.size = Vector2(280, 36)
	canvas.add_child(header)

	_top_stats = UiKit.make_label_strong("", 14, UiKit.COLOR_TEXT)
	_top_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_stats.position = Vector2(550, 36)
	_top_stats.size = Vector2(340, 28)
	canvas.add_child(_top_stats)

	var close_badge := _make_texture_panel(Rect2(900, 30, 40, 40), INV_TEX_SLOT, 18.0)
	close_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	close_badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_badge.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_toggle_screen()
			get_viewport().set_input_as_handled()
	)
	canvas.add_child(close_badge)
	var close_label := UiKit.make_label("X", 18, UiKit.COLOR_ACCENT)
	close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close_label.position = Vector2(0, 1)
	close_label.size = close_badge.size
	close_badge.add_child(close_label)

	var tab_bar := Panel.new()
	tab_bar.position = Vector2(48, 84)
	tab_bar.size = Vector2(576, 48)
	tab_bar.add_theme_stylebox_override("panel", _filter_bar_style())
	canvas.add_child(tab_bar)
	_tab_nodes.clear()
	for i in range(INV_FILTER_IDS.size()):
		var tab := Panel.new()
		tab.position = Vector2(24 + i * 106, 9)
		tab.size = Vector2(96, 30)
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab.add_theme_stylebox_override("panel", _tab_style(i == 0))
		var filter_id := str(INV_FILTER_IDS[i])
		tab.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_set_filter(filter_id)
				get_viewport().set_input_as_handled()
		)
		tab_bar.add_child(tab)
		_tab_nodes.append(tab)
		var tab_label := UiKit.make_label(str(INV_FILTER_LABELS[i]), 12, UiKit.COLOR_TEXT if i == 0 else UiKit.COLOR_TEXT_DIM)
		tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tab_label.position = Vector2(0, 1)
		tab_label.size = tab.size
		tab.add_child(tab_label)

	var grid_panel := _make_glass_panel(Rect2(48, 136, 576, 332))
	canvas.add_child(grid_panel)
	_slot_nodes.clear()
	for index in range(INV_SLOT_VISIBLE):
		var slot := Panel.new()
		slot.position = Vector2(31 + (index % INV_SLOT_COLUMNS) * 86, 22 + (index / INV_SLOT_COLUMNS) * 72)
		slot.size = Vector2(70, 68)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.add_theme_stylebox_override("panel", _slot_style(false, true))
		var slot_index := index
		slot.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_set_selected_from_slot(slot_index)
				get_viewport().set_input_as_handled()
		)
		grid_panel.add_child(slot)
		_slot_nodes.append(slot)

	_page_label = UiKit.make_label("", 14, UiKit.COLOR_TEXT_DIM)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.position = Vector2(278, 478)
	_page_label.size = Vector2(116, 20)
	canvas.add_child(_page_label)

	var detail_panel := _make_glass_panel(Rect2(644, 96, 288, 372))
	canvas.add_child(detail_panel)
	var detail_gem_top := _make_texture_rect(INV_TEX_GEM, Rect2(126, -18, 36, 21))
	detail_gem_top.modulate = Color(1, 1, 1, 0.58)
	detail_panel.add_child(detail_gem_top)

	_detail_name = UiKit.make_title("", 16, UiKit.COLOR_ACCENT)
	_detail_name.position = Vector2(30, 40)
	_detail_name.size = Vector2(228, 26)
	_detail_name.clip_text = true
	detail_panel.add_child(_detail_name)
	_detail_kind = UiKit.make_label("", 12, UiKit.COLOR_TEXT_DIM)
	_detail_kind.position = Vector2(30, 68)
	_detail_kind.size = Vector2(220, 20)
	detail_panel.add_child(_detail_kind)

	_detail_icon = TextureRect.new()
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.position = Vector2(86, 94)
	_detail_icon.size = Vector2(116, 116)
	detail_panel.add_child(_detail_icon)

	var icon_sparkle := _make_texture_rect(INV_TEX_SPARKLE_BLUE, Rect2(182, 104, 36, 48))
	icon_sparkle.modulate = Color(1, 1, 1, 0.60)
	detail_panel.add_child(icon_sparkle)

	var detail_divider := ColorRect.new()
	detail_divider.color = Color(0.76, 0.58, 0.27, 0.48)
	detail_divider.position = Vector2(30, 224)
	detail_divider.size = Vector2(228, 1)
	detail_panel.add_child(detail_divider)

	_detail_owned = UiKit.make_label("", 12, UiKit.COLOR_TEXT)
	_detail_owned.position = Vector2(30, 236)
	_detail_owned.size = Vector2(220, 20)
	detail_panel.add_child(_detail_owned)

	_detail_body = UiKit.make_label("", 12, UiKit.COLOR_TEXT)
	_detail_body.position = Vector2(30, 262)
	_detail_body.size = Vector2(228, 52)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.clip_text = true
	detail_panel.add_child(_detail_body)

	var action_button := _make_texture_panel(Rect2(52, 324, 184, 38), INV_TEX_BUTTON, 24.0)
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_use_selected()
			get_viewport().set_input_as_handled()
	)
	detail_panel.add_child(action_button)
	_action_button_label = UiKit.make_label("", 12, UiKit.COLOR_TEXT)
	_action_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_button_label.position = Vector2(0, 1)
	_action_button_label.size = action_button.size
	action_button.add_child(_action_button_label)

	_action_hint = UiKit.make_label("", 10, Color(0.93, 0.88, 0.75, 0.72))
	_action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_action_hint.position = Vector2(438, 480)
	_action_hint.size = Vector2(250, 18)
	canvas.add_child(_action_hint)

	var footer_frame := Panel.new()
	footer_frame.position = Vector2(280, 502)
	footer_frame.size = Vector2(400, 26)
	footer_frame.add_theme_stylebox_override("panel", _footer_panel_style())
	canvas.add_child(footer_frame)
	var footer := UiKit.make_label("Arrows Move     Enter Use     V Detail     1-5 Filter     I / Esc Back", 10, Color(0.93, 0.88, 0.75, 0.72))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(292, 508)
	footer.size = Vector2(376, 16)
	canvas.add_child(footer)

	# ── item detail view: a modal ON TOP of the inventory screen (added after
	# _screen_root as a later sibling of _ui, so it renders above it) — shows
	# the BE-authored per-item text OR full illustration (chapter_item_details).
	_detail_view_root = Control.new()
	_detail_view_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_view_root.visible = false
	_ui.add_child(_detail_view_root)

	var detail_view_dim := ColorRect.new()
	detail_view_dim.color = Color(0.0, 0.0, 0.0, 0.72)
	detail_view_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_view_root.add_child(detail_view_dim)

	var detail_view_canvas := Control.new()
	detail_view_canvas.position = ((vp - Vector2(960, 540)) * 0.5).floor()
	detail_view_canvas.size = Vector2(960, 540)
	_detail_view_root.add_child(detail_view_canvas)

	var detail_view_panel := _make_glass_panel(Rect2(280, 56, 400, 428))
	detail_view_canvas.add_child(detail_view_panel)
	var detail_view_gem := _make_texture_rect(INV_TEX_GEM, Rect2(182, -18, 36, 21))
	detail_view_gem.modulate = Color(1, 1, 1, 0.58)
	detail_view_panel.add_child(detail_view_gem)

	_detail_view_title = UiKit.make_title("", 18, UiKit.COLOR_ACCENT)
	_detail_view_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_view_title.position = Vector2(20, 22)
	_detail_view_title.size = Vector2(360, 28)
	_detail_view_title.clip_text = true
	detail_view_panel.add_child(_detail_view_title)

	_detail_view_caption = UiKit.make_label("", 11, UiKit.COLOR_TEXT_DIM)
	_detail_view_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_view_caption.position = Vector2(20, 52)
	_detail_view_caption.size = Vector2(360, 32)
	_detail_view_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_view_panel.add_child(_detail_view_caption)

	var detail_view_divider := ColorRect.new()
	detail_view_divider.color = Color(0.76, 0.58, 0.27, 0.48)
	detail_view_divider.position = Vector2(20, 88)
	detail_view_divider.size = Vector2(360, 1)
	detail_view_panel.add_child(detail_view_divider)

	_detail_view_image = TextureRect.new()
	_detail_view_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_view_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_view_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_view_image.position = Vector2(30, 100)
	_detail_view_image.size = Vector2(340, 300)
	detail_view_panel.add_child(_detail_view_image)

	_detail_view_text = UiKit.make_label("", 13, UiKit.COLOR_TEXT)
	_detail_view_text.position = Vector2(30, 100)
	_detail_view_text.size = Vector2(340, 300)
	_detail_view_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_view_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_view_panel.add_child(_detail_view_text)

	var detail_view_close_hint := UiKit.make_label("Esc / V để đóng", 10, Color(0.93, 0.88, 0.75, 0.72))
	detail_view_close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_view_close_hint.position = Vector2(20, 402)
	detail_view_close_hint.size = Vector2(360, 16)
	detail_view_panel.add_child(detail_view_close_hint)


func _toggle_screen() -> void:
	if _ui == null or catalog.is_empty():
		return
	if _screen_open:
		_screen_open = false
		_screen_root.visible = false
		GameManager.ui_blocking_input = false
		return
	if GameManager.ui_blocking_input:
		return
	_screen_open = true
	GameManager.ui_blocking_input = true
	_selected = 0
	_refresh_screen()
	_screen_root.visible = true
	_screen_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_screen_root, "modulate:a", 1.0, 0.2)


func _refresh_screen() -> void:
	_selected = mini(_selected, _max_selectable_index())
	var page := _selected_page()
	var page_start := page * INV_SLOT_VISIBLE
	var filtered_indices := _filtered_catalog_indices()
	_top_stats.text = "Items %d   Owned %d   Bag %d/120" % [catalog.size(), _owned_total(), _owned_total()]
	_page_label.text = "%d / %d" % [page + 1, _catalog_pages()]
	for tab_index in range(_tab_nodes.size()):
		var tab := _tab_nodes[tab_index]
		var active := str(INV_FILTER_IDS[tab_index]) == _active_filter
		tab.add_theme_stylebox_override("panel", _tab_style(active))
		if tab.get_child_count() > 0 and tab.get_child(0) is Label:
			var tab_label := tab.get_child(0) as Label
			tab_label.add_theme_color_override("font_color", UiKit.COLOR_TEXT if active else UiKit.COLOR_TEXT_DIM)

	for index in range(_slot_nodes.size()):
		var slot: Control = _slot_nodes[index]
		for child in slot.get_children():
			child.queue_free()
		var item_index := page_start + index
		var is_selected := item_index == _selected
		slot.add_theme_stylebox_override("panel", _slot_style(is_selected, item_index >= filtered_indices.size()))
		slot.modulate = Color.WHITE if item_index < filtered_indices.size() else Color(1, 1, 1, 0.42)
		if item_index >= filtered_indices.size():
			continue
		var definition: Dictionary = catalog[filtered_indices[item_index]] as Dictionary
		var owned: int = count_of(str(definition.get("id")))
		if is_selected:
			var selected_fill := ColorRect.new()
			selected_fill.color = Color(1.0, 0.74, 0.18, 0.10)
			selected_fill.position = Vector2(5, 5)
			selected_fill.size = Vector2(60, 58)
			selected_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(selected_fill)
		var icon: Texture2D = icon_for(definition)
		if icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = icon
			# expand_mode must be set BEFORE size, or the rect clamps to the
			# texture's minimum size and renders oversized.
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
			icon_rect.position = Vector2(14, 8)
			icon_rect.size = Vector2(42, 42)
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.modulate = Color.WHITE if owned > 0 else Color(0.45, 0.45, 0.5, 0.7)
			slot.add_child(icon_rect)
		var count_label := UiKit.make_label(str(owned), 12, UiKit.COLOR_TEXT if owned > 0 else UiKit.COLOR_TEXT_DIM)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.position = Vector2(32, 46)
		count_label.size = Vector2(30, 16)
		slot.add_child(count_label)
		if is_selected:
			var focus_line := ColorRect.new()
			focus_line.color = Color(1.0, 0.86, 0.34, 0.95)
			focus_line.position = Vector2(10, 62)
			focus_line.size = Vector2(50, 2)
			focus_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(focus_line)

	if _selected < filtered_indices.size():
		var definition: Dictionary = catalog[filtered_indices[_selected]] as Dictionary
		var kind: String = str(definition.get("kind"))
		_detail_name.text = str(definition.get("name", ""))
		_detail_kind.text = _kind_text(definition)
		_detail_icon.texture = icon_for(definition)
		_detail_icon.modulate = Color.WHITE if count_of(str(definition.get("id"))) > 0 else Color(0.45, 0.45, 0.5, 0.75)
		_detail_owned.text = "Owned: %d" % count_of(str(definition.get("id")))
		_detail_body.text = _detail_preview_text(str(definition.get("description", "")))
		var owned: int = count_of(str(definition.get("id")))
		if owned <= 0:
			_action_button_label.text = "Locked"
			_action_hint.text = "Item not owned."
		else:
			_action_button_label.text = {
				"heal": "Use",
				"lore": "Read",
				"energy": "Battle",
				"buff": "Battle",
				"quest": "Quest",
			}.get(kind, "Inspect")
			_action_hint.text = {
				"heal": "Enter to use now.",
				"lore": "Enter to read lore.",
				"energy": "Usable from battle Item menu.",
				"buff": "Usable from battle Item menu.",
				"quest": "Quest item cannot be discarded.",
			}.get(kind, "")
			if not _item_detail(definition).is_empty():
				_action_hint.text += "   •   V: Xem chi tiết"
	else:
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_owned.text = ""
		_detail_body.text = ""
		_detail_icon.texture = null
		_action_hint.text = ""
		_action_button_label.text = ""


func _use_selected() -> void:
	var definition := _definition_at_filtered_index(_selected)
	if definition.is_empty():
		return
	var item_id: String = str(definition.get("id"))
	if count_of(item_id) <= 0:
		return
	var message: String = use_item_overworld(item_id)
	if not message.is_empty():
		_detail_body.text = message
	_refresh_screen()
	if not message.is_empty() and str(definition.get("kind")) == "heal":
		_push_toast("✚ %s" % message)


# ── item detail view ─────────────────────────────────────────────────────────
## Not every item has this — only the ones chapter_item_details selected as
## worth a closer look/read. `detail` rides along on the item definition dict
## itself: {kind:"text", text, caption} or {kind:"image", image_url, caption}.


func _item_detail(definition: Dictionary) -> Dictionary:
	var detail: Variant = definition.get("detail")
	return detail if detail is Dictionary else {}


func _open_item_detail_view() -> void:
	var definition := _definition_at_filtered_index(_selected)
	if definition.is_empty() or count_of(str(definition.get("id"))) <= 0:
		return
	var detail := _item_detail(definition)
	if detail.is_empty():
		return
	_ensure_ui()
	var item_id: String = str(definition.get("id"))
	_detail_view_current_item_id = item_id
	_detail_view_title.text = str(definition.get("name", ""))
	_detail_view_caption.text = str(detail.get("caption", ""))
	var kind: String = str(detail.get("kind", ""))
	if kind == "image":
		_detail_view_text.visible = false
		_detail_view_image.visible = true
		_detail_view_image.texture = _detail_image_cache.get(item_id)
		if not _detail_image_cache.has(item_id):
			var url: String = str(detail.get("image_url", ""))
			if not url.is_empty():
				_load_detail_image(item_id, url)
	else:
		_detail_view_image.visible = false
		_detail_view_text.visible = true
		_detail_view_text.text = str(detail.get("text", ""))
	_detail_view_open = true
	_detail_view_root.visible = true


func _load_detail_image(item_id: String, url: String) -> void:
	var texture: Texture2D = await ChapterFlow.download_image_texture(url)
	if texture == null:
		return
	_detail_image_cache[item_id] = texture
	# The player may have closed the overlay or moved to a different item while
	# this download was in flight — only apply if it's still the one showing.
	if _detail_view_open and _detail_view_current_item_id == item_id:
		_detail_view_image.texture = texture


func _close_item_detail_view() -> void:
	_detail_view_open = false
	_detail_view_current_item_id = ""
	if _detail_view_root != null:
		_detail_view_root.visible = false


# ── toasts ────────────────────────────────────────────────────────────────────


func _push_toast(text: String) -> void:
	_ensure_ui()
	_toast_queue.append(text)


func _process(_delta: float) -> void:
	if _ui == null:
		return
	if not _toast_queue.is_empty() and not _toast_busy:
		_show_next_toast()


func _show_next_toast() -> void:
	_toast_busy = true
	var text: String = _toast_queue.pop_front()
	var panel := UiKit.make_panel(Rect2(0, 0, 10, 20))
	var label := UiKit.make_label(text, 8, UiKit.COLOR_TEXT)
	label.position = Vector2(10, 4)
	panel.add_child(label)
	await get_tree().process_frame
	var width: float = clampf(label.size.x + 22.0, 100.0, 380.0)
	panel.size.x = width
	panel.position = Vector2(-width / 2.0, -24)
	_toast_host.add_child(panel)
	var tween := create_tween()
	tween.tween_property(panel, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.8)
	tween.tween_property(panel, "position:y", -24.0, 0.25)
	tween.tween_callback(func() -> void:
		panel.queue_free()
		_toast_busy = false
	)


# ── input ─────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	# The item detail view is a modal ON TOP of the inventory screen — while
	# open, only Esc/V close it; every other key/click is swallowed so it can
	# never fall through to grid navigation or close the whole screen.
	if _detail_view_open:
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			var keycode := (event as InputEventKey).physical_keycode
			if keycode == KEY_V or event.is_action_pressed("ui_cancel"):
				_close_item_detail_view()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_I:
			_toggle_screen()
			get_viewport().set_input_as_handled()
			return
	if not _screen_open:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var keycode := (event as InputEventKey).physical_keycode
		if keycode == KEY_V:
			_open_item_detail_view()
			get_viewport().set_input_as_handled()
			return
		if keycode >= KEY_1 and keycode <= KEY_5:
			var filter_index := int(keycode - KEY_1)
			if filter_index >= 0 and filter_index < INV_FILTER_IDS.size():
				_set_filter(str(INV_FILTER_IDS[filter_index]))
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		_toggle_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_selected = mini(_selected + 1, _max_selectable_index())
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_selected = maxi(_selected - 1, 0)
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected = mini(_selected + INV_SLOT_COLUMNS, _max_selectable_index())
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected = maxi(_selected - INV_SLOT_COLUMNS, 0)
		_refresh_screen()
		get_viewport().set_input_as_handled()
