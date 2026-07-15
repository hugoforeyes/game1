class_name BattleCommandMenu
extends Panel
## Self-contained command picker used by BattleScene. Combat flow owns WHEN the
## menu opens; this component owns presentation, selection and input behavior.

signal choice_picked(id: String)

const COLOR_ACCENT := Color(1.0, 0.8, 0.35, 1.0)
const COLOR_TEXT_DIM := Color(0.93, 0.88, 0.75, 0.4)
const COLOR_INFO_TEXT := Color(0.93, 0.88, 0.72, 0.98)

const BATTLE_V3_DIR := "res://assets/ui/battle_v3/"
const COMMAND_DIR := "res://assets/ui/battle_command_v1/"
const COMMAND_ICON_DIR := COMMAND_DIR + "icons/"
const SLOT_NORMAL := COMMAND_DIR + "components/command_slot_normal.png"
const SLOT_SELECTED := COMMAND_DIR + "components/command_slot_selected.png"

const LEGACY_ICON_ATTACK := "res://assets/ui/battle_v2/icons/icon_attack.png"
const LEGACY_ICON_SKILL := "res://assets/ui/battle_v2/icons/icon_skill.png"
const LEGACY_ICON_PROBE := "res://assets/ui/battle_v2/icons/icon_probe.png"
const LEGACY_ICON_ITEM := "res://assets/ui/battle_v2/icons/icon_item.png"
const LEGACY_ICON_GUARD := "res://assets/ui/battle_v2/icons/icon_guard.png"
const LEGACY_ICON_FLEE := "res://assets/ui/battle_v2/icons/icon_flee.png"
const LEGACY_ICON_FINISHER := "res://assets/ui/battle_v2/icons/icon_finisher.png"
const LEGACY_ICON_SPARE := "res://assets/ui/battle_v2/icons/icon_spare.png"

const DEFAULT_SIZE := Vector2(470, 172)
const CARD_SIDE := 60.0
const CARD_GAP := 8
const CARD_MIN_GAP := 4
const ROW_SIDE_MARGIN := 5.0
const INFO_ICON_SIDE := 34.0
const INFO_TEXT_MAX_WIDTH := 346.0
const INFO_GAP := 10.0
const SELECTED_GLOW_MIN_ALPHA := 0.46
const SELECTED_GLOW_MAX_ALPHA := 0.78
# The authored frame PNGs contain transparent pixels below their visible gold
# edge. Compensate inside the fixed 60px card so the painted edge—not merely the
# Control rect—lands on the ally-card baseline.
const FRAME_ALPHA_BOTTOM_COMPENSATION := 6.5

var _ids: Array[String] = []
var _descs: Array[String] = []
var _items: Array[Control] = []
var _index: int = 0
var _open: bool = false
var _resolving: bool = false
var _texture_cache: Dictionary = {}
var _fade_tween: Tween

var _info_icon: TextureRect
var _info_name: Label
var _info_desc: Label
var _row: HBoxContainer


func setup(panel_size: Vector2 = DEFAULT_SIZE) -> void:
	size = panel_size
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()


## Shared soft-focus backdrop used behind command information and lightweight
## battle HUD groups. Its radial falloff has no readable panel boundary.
static func make_soft_info_scrim(
	display_size: Vector2,
	texture_size: Vector2i = Vector2i.ZERO,
) -> TextureRect:
	var info_gradient := Gradient.new()
	info_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	info_gradient.colors = PackedColorArray([
		Color(0.008, 0.012, 0.028, 0.72),
		Color(0.008, 0.012, 0.028, 0.50),
		Color(0.008, 0.012, 0.028, 0.0),
	])
	var info_texture := GradientTexture2D.new()
	info_texture.gradient = info_gradient
	info_texture.fill = GradientTexture2D.FILL_RADIAL
	info_texture.fill_from = Vector2(0.5, 0.5)
	info_texture.fill_to = Vector2(0.5, 0.0)
	info_texture.width = maxi(
		1, texture_size.x if texture_size.x > 0 else roundi(display_size.x))
	info_texture.height = maxi(
		1, texture_size.y if texture_size.y > 0 else roundi(display_size.y))
	var info_scrim := TextureRect.new()
	info_scrim.texture = info_texture
	info_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	info_scrim.size = display_size
	info_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return info_scrim


func _build_ui() -> void:
	var scrim_width := minf(size.x, 560.0)
	var info_scrim := make_soft_info_scrim(
		Vector2(scrim_width, 104), Vector2i(int(scrim_width), 86))
	info_scrim.position = Vector2((size.x - scrim_width) * 0.5, -34)
	add_child(info_scrim)

	_info_icon = TextureRect.new()
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_info_icon.position = Vector2(0, 8)
	_info_icon.size = Vector2(INFO_ICON_SIDE, INFO_ICON_SIDE)
	_info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info_icon)

	_info_name = UiKit.make_title("", 16, COLOR_ACCENT)
	_info_name.position = Vector2(0, 2)
	_info_name.size = Vector2(INFO_TEXT_MAX_WIDTH, 22)
	_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_name.clip_text = false
	_info_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_info_name)

	_info_desc = UiKit.make_label("", 10, COLOR_INFO_TEXT)
	_info_desc.position = Vector2(0, 26)
	_info_desc.size = Vector2(INFO_TEXT_MAX_WIDTH, 14)
	_info_desc.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_info_desc.add_theme_constant_override("shadow_offset_x", 1)
	_info_desc.add_theme_constant_override("shadow_offset_y", 1)
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_desc.clip_text = false
	_info_desc.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(_info_desc)

	_row = HBoxContainer.new()
	_row.position = Vector2(0, 56)
	_row.size = Vector2(size.x, CARD_SIDE)
	_row.add_theme_constant_override("separation", CARD_GAP)
	add_child(_row)
	_layout_readout_horizontal(true)


func choose(
	ids: Array[String],
	labels: Array[String],
	descs: Array[String] = [],
	icon_keys: Array = [],
) -> String:
	clear()
	_ids = ids.duplicate()
	_descs = descs.duplicate()
	_index = 0
	_open = true
	_resolving = false
	visible = true
	modulate.a = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.16)

	var count := maxi(labels.size(), 1)
	var gap := CARD_GAP
	if count > 1:
		var row_width := maxf(CARD_SIDE, size.x - ROW_SIDE_MARGIN * 2.0)
		var available_gap := floori(
			(row_width - CARD_SIDE * float(count)) / float(count - 1))
		gap = clampi(available_gap, CARD_MIN_GAP, CARD_GAP)
	var total_width := CARD_SIDE * float(count) + float(maxi(count - 1, 0) * gap)
	_row.add_theme_constant_override("separation", gap)
	_row.position.x = (size.x - total_width) * 0.5
	_row.size.x = total_width

	for item_index in range(labels.size()):
		var id := ids[item_index] if item_index < ids.size() else ""
		var icon_source: Variant = icon_keys[item_index] \
			if item_index < icon_keys.size() else id
		var icon_texture := _resolve_icon_texture(
			icon_source, id, labels[item_index])
		var card := _make_card(labels[item_index], icon_texture, item_index)
		_row.add_child(card)
		_items.append(card)
	_highlight()

	var picked: String = await choice_picked
	clear()
	return picked


func clear() -> void:
	_open = false
	_resolving = false
	for item in _items:
		if is_instance_valid(item):
			_stop_card_glow(item)
			if item.get_parent() == _row:
				_row.remove_child(item)
			item.queue_free()
	_items.clear()
	_ids.clear()
	_descs.clear()
	visible = false


func is_open() -> bool:
	return _open


func handle_input(event: InputEvent) -> bool:
	if not _open or _ids.is_empty():
		return false
	if event.is_action_pressed("ui_accept"):
		_resolve_current()
		return true
	var moved := false
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_index = (_index + 1) % _ids.size()
		moved = true
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_index = (_index - 1 + _ids.size()) % _ids.size()
		moved = true
	if moved:
		_highlight()
	return moved


func _resolve_current() -> void:
	if _resolving or _index < 0 or _index >= _ids.size():
		return
	_resolving = true
	choice_picked.emit(_ids[_index])


func _on_card_gui_input(event: InputEvent, card_index: int) -> void:
	if not _open or card_index < 0 or card_index >= _ids.size():
		return
	if event is InputEventMouseMotion and _index != card_index:
		_index = card_index
		_highlight()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_index = card_index
			_highlight()
			_resolve_current()


func _highlight() -> void:
	for item_index in range(_items.size()):
		var selected := item_index == _index
		_set_card_selected(_items[item_index], selected)
		if selected:
			var bump := create_tween()
			bump.tween_property(_items[item_index], "position:y", -5.0, 0.08)
			bump.tween_property(_items[item_index], "position:y", 0.0, 0.12)


func _make_card(text: String, icon_texture: Texture2D, card_index: int) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_SIDE, CARD_SIDE)
	card.size = Vector2(CARD_SIDE, CARD_SIDE)
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var visual_y_offset := 0.0
	var slot_normal := _load_png_texture(SLOT_NORMAL)
	var slot_selected := _load_png_texture(SLOT_SELECTED)
	if slot_normal != null and slot_selected != null:
		visual_y_offset = FRAME_ALPHA_BOTTOM_COMPENSATION
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var selection_glow := _make_selection_glow(visual_y_offset)
		card.add_child(selection_glow)
		card.set_meta("selection_glow", selection_glow)
		var frame_normal := _add_texture(card, SLOT_NORMAL, Rect2(
			Vector2(0, visual_y_offset), card.size))
		var frame_selected := _add_texture(card, SLOT_SELECTED, Rect2(
			Vector2(0, visual_y_offset), card.size))
		frame_selected.visible = false
		card.set_meta("frame_normal", frame_normal)
		card.set_meta("frame_selected", frame_selected)
	elif UiKit.kit_texture("card.png") != null:
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var frame_normal := UiKit.make_ornate_frame(card.size, "card.png", 0.24, 14.0)
		var frame_selected := UiKit.make_ornate_frame(card.size, "card_selected.png", 0.24, 14.0)
		frame_selected.visible = false
		card.add_child(frame_normal)
		card.add_child(frame_selected)
		card.set_meta("frame_normal", frame_normal)
		card.set_meta("frame_selected", frame_selected)
	else:
		card.add_theme_stylebox_override("panel", _make_card_style(false))
	card.gui_input.connect(_on_card_gui_input.bind(card_index))
	card.set_meta("label_text", text)
	card.set_meta("icon_texture", icon_texture)

	var icon_node: CanvasItem
	if icon_texture != null:
		var icon_size := CARD_SIDE - 24.0
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(
			(CARD_SIDE - icon_size) * 0.5,
			(CARD_SIDE - icon_size) * 0.5 + visual_y_offset,
		)
		icon.size = Vector2(icon_size, icon_size)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if icon_texture is AtlasTexture:
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate.a = 0.92
		icon.texture = icon_texture
		card.add_child(icon)
		icon_node = icon
	else:
		var fallback := ColorRect.new()
		fallback.color = Color(0.95, 0.8, 0.48, 0.72)
		fallback.position = Vector2(
			CARD_SIDE * 0.5 - 6, CARD_SIDE * 0.5 - 6 + visual_y_offset)
		fallback.size = Vector2(12, 12)
		fallback.rotation_degrees = 45
		fallback.pivot_offset = Vector2(6, 6)
		card.add_child(fallback)
		icon_node = fallback
	card.set_meta("icon_node", icon_node)
	return card


func _set_card_selected(card: Control, selected: bool) -> void:
	var was_selected := bool(card.get_meta("is_selected", false))
	card.set_meta("is_selected", selected)
	if card.has_meta("frame_normal"):
		(card.get_meta("frame_normal") as Control).visible = not selected
		(card.get_meta("frame_selected") as Control).visible = selected
	elif card is Panel:
		(card as Panel).add_theme_stylebox_override("panel", _make_card_style(selected))
	if card.has_meta("icon_node"):
		var icon := card.get_meta("icon_node") as CanvasItem
		if icon is ColorRect:
			icon.color = Color(1.0, 0.86, 0.4, 1.0) if selected else Color(0.95, 0.8, 0.48, 0.55)
		elif icon != null:
			icon.modulate = Color(1.18, 1.08, 0.82, 1.0) if selected else Color(0.82, 0.8, 0.74, 0.78)
	if selected and not was_selected:
		_start_card_glow(card)
	elif not selected and was_selected:
		_stop_card_glow(card)
	if selected:
		_refresh_info()


func _make_selection_glow(visual_y_offset: float) -> Panel:
	var glow := Panel.new()
	glow.position = Vector2(4.0, visual_y_offset + 4.0)
	glow.size = Vector2(CARD_SIDE - 8.0, CARD_SIDE - 8.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.72, 0.20, 0.025)
	style.border_color = Color(1.0, 0.79, 0.30, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(1.0, 0.58, 0.10, 0.30)
	style.shadow_size = 9
	style.shadow_offset = Vector2.ZERO
	glow.add_theme_stylebox_override("panel", style)
	return glow


func _start_card_glow(card: Control) -> void:
	if not card.has_meta("selection_glow"):
		return
	_stop_card_glow(card)
	var glow := card.get_meta("selection_glow") as Control
	if glow == null:
		return
	glow.visible = true
	glow.modulate.a = SELECTED_GLOW_MIN_ALPHA
	var tween := create_tween().set_loops()
	tween.tween_property(glow, "modulate:a", SELECTED_GLOW_MAX_ALPHA, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(glow, "modulate:a", SELECTED_GLOW_MIN_ALPHA, 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	card.set_meta("selection_glow_tween", tween)


func _stop_card_glow(card: Control) -> void:
	if card.has_meta("selection_glow_tween"):
		var tween := card.get_meta("selection_glow_tween") as Tween
		if tween != null and tween.is_valid():
			tween.kill()
		card.remove_meta("selection_glow_tween")
	if card.has_meta("selection_glow"):
		var glow := card.get_meta("selection_glow") as Control
		if glow != null:
			glow.visible = false


func _refresh_info() -> void:
	if _index < 0 or _index >= _ids.size() or _index >= _items.size():
		return
	var card := _items[_index]
	var label_text := str(card.get_meta("label_text", ""))
	var icon_texture: Texture2D = card.get_meta("icon_texture", null) as Texture2D
	_info_icon.texture = icon_texture
	_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if icon_texture is AtlasTexture:
		_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_info_icon.visible = icon_texture != null
	_info_name.text = label_text
	var description := _descs[_index].strip_edges() if _index < _descs.size() else ""
	_info_desc.text = description
	_info_desc.visible = not description.is_empty()
	_layout_readout_horizontal(_info_icon.visible)
	_layout_info(not description.is_empty())


func _layout_readout_horizontal(has_icon: bool) -> void:
	# Title and description share one left edge. Center that measured text block
	# on the same axis as the command row; the optional icon remains a satellite
	# and never participates in the centering calculation.
	var visual_text_width := _readout_visual_width()
	var text_left := floorf((size.x - visual_text_width) * 0.5)
	_info_name.position.x = text_left
	_info_desc.position.x = text_left
	_info_name.size.x = visual_text_width
	_info_desc.size.x = visual_text_width
	if has_icon:
		_info_icon.position.x = text_left - INFO_GAP - INFO_ICON_SIDE


func _readout_visual_width() -> float:
	var visual_width := _label_text_width(_info_name)
	if _info_desc.visible:
		visual_width = maxf(visual_width, _label_text_width(_info_desc))
	return clampf(visual_width, 1.0, INFO_TEXT_MAX_WIDTH)


func _label_text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var widest := 0.0
	for source_line in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(
			source_line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	return minf(widest, INFO_TEXT_MAX_WIDTH)


func _layout_info(has_desc: bool) -> void:
	var name_height := _wrapped_label_height(_info_name, 22.0, 40.0)
	_info_name.size.y = name_height
	if not has_desc:
		_info_name.position.y = 8.0 + (34.0 - name_height) * 0.5
		_info_desc.size.y = 0.0
		return
	var desc_height := _wrapped_label_height(_info_desc, 14.0, 36.0)
	var total_height := name_height + 2.0 + desc_height
	var top := clampf(minf(2.0, _row.position.y - 4.0 - total_height), -28.0, 2.0)
	_info_name.position.y = top
	_info_desc.position.y = top + name_height + 2.0
	_info_desc.size.y = desc_height


func _wrapped_label_height(label: Label, min_height: float, max_height: float) -> float:
	var line_count := maxi(label.get_line_count(), 1)
	var line_height := float(label.get_line_height())
	if line_height <= 0.0:
		line_height = float(label.get_theme_font_size("font_size")) + 2.0
	return clampf(float(line_count) * line_height + 2.0, min_height, max_height)


func _make_card_style(selected: bool) -> StyleBox:
	var texture := UiKit.kit_texture("card_selected.png" if selected else "card.png")
	if texture != null:
		return UiKit.ninepatch_style(
			texture, minf(texture.get_width(), texture.get_height()) * 0.26, 6.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.035, 0.045, 0.88) if not selected else Color(0.14, 0.1, 0.035, 0.95)
	style.border_color = Color(0.6, 0.5, 0.34, 0.58) if not selected else Color(1.0, 0.78, 0.32, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_size = 6 if not selected else 16
	style.shadow_color = Color(0, 0, 0, 0.35) if not selected else Color(1.0, 0.63, 0.18, 0.34)
	return style


func _icon_path(id: String, label: String) -> String:
	var direct_path := _existing_icon_path(id)
	if not direct_path.is_empty():
		return direct_path
	var command_path := COMMAND_ICON_DIR + "icon_%s.png" % id
	if ResourceLoader.exists(command_path):
		return command_path
	var v3_path := BATTLE_V3_DIR + "icon_%s.png" % id
	if ResourceLoader.exists(v3_path):
		return v3_path
	match id:
		"attack": return LEGACY_ICON_ATTACK
		"skill": return LEGACY_ICON_SKILL
		"probe": return LEGACY_ICON_PROBE
		"item": return LEGACY_ICON_ITEM
		"guard": return LEGACY_ICON_GUARD
		"flee": return LEGACY_ICON_FLEE
		"finisher": return LEGACY_ICON_FINISHER
		"spare": return LEGACY_ICON_SPARE
		"back": return ""
	var lower_label := label.to_lower()
	if id.is_valid_int():
		if lower_label.contains("potion") or lower_label.contains("tonic") \
				or lower_label.contains("elixir") or lower_label.contains("×"):
			return LEGACY_ICON_ITEM
		return LEGACY_ICON_SKILL
	if id != "back" and not id.is_empty():
		return LEGACY_ICON_SKILL
	return ""


func _resolve_icon_texture(
	source: Variant,
	id: String,
	label: String,
) -> Texture2D:
	if source is Texture2D:
		return source as Texture2D
	var icon_key := id
	if typeof(source) == TYPE_STRING:
		icon_key = str(source)
	var icon_path := _icon_path(icon_key, label)
	return _load_png_texture(icon_path) if not icon_path.is_empty() else null


func _existing_icon_path(source: String) -> String:
	if source.is_empty():
		return ""
	var looks_like_path := source.begins_with("res://") \
		or source.begins_with("user://") \
		or source.begins_with("uid://") \
		or source.is_absolute_path() \
		or source.contains("/") \
		or not source.get_extension().is_empty()
	if not looks_like_path:
		return ""
	if FileAccess.file_exists(source):
		return source
	if (source.begins_with("res://") or source.begins_with("user://") \
			or source.begins_with("uid://")) and ResourceLoader.exists(source):
		return source
	if source.begins_with("res://") or source.begins_with("user://") \
			or source.begins_with("uid://") \
			or source.is_absolute_path():
		return ""
	var project_path := "res://" + source.trim_prefix("./")
	if FileAccess.file_exists(project_path) or ResourceLoader.exists(project_path):
		return project_path
	return ""


func _add_texture(
	parent: Control,
	path: String,
	rect: Rect2,
	alpha: float = 1.0,
) -> TextureRect:
	var node := TextureRect.new()
	# Set IGNORE_SIZE before assigning the texture. Otherwise TextureRect adopts
	# the source PNG's 256px minimum and silently rejects the requested 60/36px.
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.position = rect.position
	node.size = rect.size
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.modulate.a = alpha
	node.texture = _load_png_texture(path)
	parent.add_child(node)
	return node


func _load_png_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	var resource_path := path.begins_with("res://") \
		or path.begins_with("user://") \
		or path.begins_with("uid://")
	if resource_path and ResourceLoader.exists(path):
		texture = load(path)
	else:
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK:
			texture = ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture
