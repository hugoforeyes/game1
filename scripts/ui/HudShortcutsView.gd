extends CanvasLayer
## Bottom-right screen shortcuts (overworld HUD): three circular icon buttons
## that open the Map (M), Quest Journal (J) and Inventory (I). Refined hud_v1
## art — gold-rimmed glass discs with engraved emblems and tiny keycap labels.
## Hidden while any blocking screen is open, like the rest of the HUD.

const ICON_DIR := "res://assets/ui/hud_v1/"
const BUTTON := 58.0
const GAP := 16.0
const MARGIN_RIGHT := 16.0
const MARGIN_BOTTOM := 14.0

var _root: Control
var _buttons: Array[Control] = []


func _ready() -> void:
	layer = 43
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()


func _build() -> void:
	var entries := [
		{"icon": "icon_map.png", "key": "M", "action": _open_map},
		{"icon": "icon_journal.png", "key": "J", "action": _open_journal},
		{"icon": "icon_bag.png", "key": "I", "action": _open_inventory},
	]
	var vp := _root.get_viewport_rect().size
	var total_w := BUTTON * entries.size() + GAP * (entries.size() - 1)
	var x0 := vp.x - MARGIN_RIGHT - total_w
	var y0 := vp.y - MARGIN_BOTTOM - BUTTON - 14.0

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var x := x0 + float(i) * (BUTTON + GAP)
		var button := Control.new()
		button.position = Vector2(x, y0)
		button.size = Vector2(BUTTON, BUTTON)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_root.add_child(button)
		_buttons.append(button)

		var base := _make_icon("icon_button_base.png", Rect2(0, 0, BUTTON, BUTTON))
		if base == null:
			var disc := Panel.new()
			disc.size = Vector2(BUTTON, BUTTON)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.03, 0.045, 0.09, 0.85)
			style.border_color = Color(0.78, 0.60, 0.26, 0.7)
			style.set_border_width_all(1)
			style.set_corner_radius_all(int(BUTTON * 0.5))
			disc.add_theme_stylebox_override("panel", style)
			disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(disc)
		else:
			button.add_child(base)

		var emblem := _make_icon(str(entry["icon"]), Rect2(13, 12, BUTTON - 26, BUTTON - 26))
		if emblem != null:
			button.add_child(emblem)

		var keycap := UiKit.make_label_strong(str(entry["key"]), 10, Color(0.93, 0.88, 0.75, 0.66))
		keycap.position = Vector2(0, BUTTON + 3.0)
		keycap.size = Vector2(BUTTON, 13.0)
		keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(keycap)

		var action: Callable = entry["action"]
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.is_pressed() \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				action.call()
				button.get_viewport().set_input_as_handled()
		)
		button.mouse_entered.connect(func() -> void:
			button.modulate = Color(1.18, 1.12, 0.95, 1.0))
		button.mouse_exited.connect(func() -> void:
			button.modulate = Color.WHITE)


func _make_icon(file_name: String, rect: Rect2) -> TextureRect:
	var path := ICON_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.position = rect.position
	icon.size = rect.size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _process(_delta: float) -> void:
	# The shortcuts belong to the exploration HUD — hide them the moment any
	# blocking screen (journal, inventory, map, battle, dialogue...) is open.
	_root.visible = not GameManager.ui_blocking_input


func _open_map() -> void:
	var manager := get_node_or_null("/root/MinimapManager")
	if manager != null and manager.has_method("_toggle"):
		manager._toggle()


func _open_journal() -> void:
	var manager := get_node_or_null("/root/QuestManager")
	if manager != null and manager.has_method("_toggle_journal"):
		manager._toggle_journal()


func _open_inventory() -> void:
	var manager := get_node_or_null("/root/InventoryManager")
	if manager != null and manager.has_method("_toggle_screen"):
		manager._toggle_screen()
