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

var _icon_sheet: Texture2D = null
var _icon_grid: int = 3
var _icon_cell_px: int = 48

var _ui: CanvasLayer = null
var _screen_root: Control
var _screen_open: bool = false
var _slot_nodes: Array[Control] = []
var _selected: int = 0
var _detail_name: Label
var _detail_kind: Label
var _detail_body: Label
var _action_hint: Label
var _toast_host: Control
var _toast_queue: Array = []
var _toast_busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	catalog = []
	counts = {}
	_icon_sheet = null
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
		(index / _icon_grid) * _icon_cell_px,
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


func _ensure_ui() -> void:
	if _ui != null:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 46
	_ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(_ui)

	_toast_host = Control.new()
	_toast_host.position = Vector2(240, 30)
	_ui.add_child(_toast_host)

	_screen_root = Control.new()
	_screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_root.visible = false
	_ui.add_child(_screen_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(dim)

	var header := UiKit.make_label("HÀNH TRANG", 12, UiKit.COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(20, 10)
	header.size = Vector2(440, 18)
	_screen_root.add_child(header)

	var banner: TextureRect = UiKit.make_banner_rect(120.0)
	if banner != null:
		banner.position = Vector2(180, 26)
		_screen_root.add_child(banner)

	var grid_panel := UiKit.make_panel(Rect2(14, 58, 230, 196))
	_screen_root.add_child(grid_panel)
	for index in range(9):
		var slot := Panel.new()
		slot.position = Vector2(14 + (index % 3) * 70, 12 + (index / 3) * 60)
		slot.size = Vector2(58, 54)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.07, 0.16, 0.9)
		style.border_color = UiKit.COLOR_PANEL_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", style)
		grid_panel.add_child(slot)
		_slot_nodes.append(slot)

	var detail_panel := UiKit.make_panel(Rect2(252, 58, 214, 196))
	_screen_root.add_child(detail_panel)
	_detail_name = UiKit.make_label("", 9, UiKit.COLOR_ACCENT)
	_detail_name.position = Vector2(12, 10)
	_detail_name.size = Vector2(190, 14)
	detail_panel.add_child(_detail_name)
	_detail_kind = UiKit.make_label("", 7, UiKit.COLOR_TEXT_DIM)
	_detail_kind.position = Vector2(12, 26)
	detail_panel.add_child(_detail_kind)
	_detail_body = UiKit.make_label("", 7, UiKit.COLOR_TEXT)
	_detail_body.position = Vector2(12, 42)
	_detail_body.size = Vector2(190, 120)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(_detail_body)
	_action_hint = UiKit.make_label("", 7, UiKit.COLOR_TEXT_DIM)
	_action_hint.position = Vector2(12, 170)
	_action_hint.size = Vector2(190, 12)
	detail_panel.add_child(_action_hint)

	var footer := UiKit.make_label("Di chuyển: phím mũi tên   ·   ENTER dùng   ·   I / ESC đóng", 6, UiKit.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(20, 258)
	footer.size = Vector2(440, 10)
	_screen_root.add_child(footer)


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
	for index in range(_slot_nodes.size()):
		var slot: Control = _slot_nodes[index]
		for child in slot.get_children():
			child.queue_free()
		var style: StyleBoxFlat = (slot.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		style.border_color = UiKit.COLOR_ACCENT if index == _selected else UiKit.COLOR_PANEL_BORDER
		style.set_border_width_all(2 if index == _selected else 1)
		slot.add_theme_stylebox_override("panel", style)
		if index >= catalog.size():
			continue
		var definition: Dictionary = catalog[index] as Dictionary
		var owned: int = count_of(str(definition.get("id")))
		var icon: Texture2D = icon_for(definition)
		if icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = icon
			# expand_mode must be set BEFORE size, or the rect clamps to the
			# texture's minimum size and renders oversized.
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
			icon_rect.position = Vector2(11, 4)
			icon_rect.size = Vector2(36, 36)
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.modulate = Color.WHITE if owned > 0 else Color(0.45, 0.45, 0.5, 0.7)
			slot.add_child(icon_rect)
		var count_label := UiKit.make_label("×%d" % owned, 7, UiKit.COLOR_TEXT if owned > 0 else UiKit.COLOR_TEXT_DIM)
		count_label.position = Vector2(36, 40)
		slot.add_child(count_label)

	if _selected < catalog.size():
		var definition: Dictionary = catalog[_selected] as Dictionary
		var kind: String = str(definition.get("kind"))
		_detail_name.text = str(definition.get("name", ""))
		_detail_kind.text = {
			"heal": "TIÊU HAO · HỒI %d HP" % int(definition.get("power", 0)),
			"energy": "TIÊU HAO · HỒI %d SP (trong trận)" % int(definition.get("power", 2)),
			"buff": "TIÊU HAO · TĂNG SÁT THƯƠNG (trong trận)",
			"quest": "VẬT PHẨM NHIỆM VỤ",
			"lore": "KÝ ỨC · ĐỌC ĐƯỢC",
		}.get(kind, kind.to_upper())
		_detail_body.text = str(definition.get("description", ""))
		var owned: int = count_of(str(definition.get("id")))
		if owned <= 0:
			_action_hint.text = "Chưa sở hữu."
		else:
			_action_hint.text = {
				"heal": "ENTER  dùng ngay",
				"lore": "ENTER  đọc",
				"energy": "Dùng trong trận chiến (menu Item)",
				"buff": "Dùng trong trận chiến (menu Item)",
				"quest": "Dành cho nhiệm vụ — không thể vứt bỏ",
			}.get(kind, "")
	else:
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_body.text = ""
		_action_hint.text = ""


func _use_selected() -> void:
	if _selected >= catalog.size():
		return
	var definition: Dictionary = catalog[_selected] as Dictionary
	var item_id: String = str(definition.get("id"))
	if count_of(item_id) <= 0:
		return
	var message: String = use_item_overworld(item_id)
	if not message.is_empty():
		_detail_body.text = message
	_refresh_screen()
	if not message.is_empty() and str(definition.get("kind")) == "heal":
		_push_toast("✚ %s" % message)


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
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_I:
			_toggle_screen()
			get_viewport().set_input_as_handled()
			return
	if not _screen_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_selected = mini(_selected + 1, 8)
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_selected = maxi(_selected - 1, 0)
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected = mini(_selected + 3, 8)
		_refresh_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected = maxi(_selected - 3, 0)
		_refresh_screen()
		get_viewport().set_input_as_handled()
