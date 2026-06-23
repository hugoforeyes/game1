class_name QuestNotificationToast
extends Control
## Compact, pixel-snapped quest notification assembled from modular atlas parts.

const COMPONENT_DIR := "res://assets/ui/notification_v1/components/"
const PANEL_SIZE := Vector2(174, 44)
const CORNER_SIZE := Vector2(15, 15)
const EDGE_THICKNESS := 2.0
const ARM_LENGTH := 9.0

var header_label: Label
var title_label: Label
var subtitle_label: Label
var palette := "gold"
var _effect_nodes: Array[CanvasItem] = []


func setup(data: Dictionary) -> void:
	size = PANEL_SIZE
	pivot_offset = PANEL_SIZE * 0.5
	palette = str(data.get("palette", "gold"))
	if palette not in ["gold", "cyan"]:
		palette = "gold"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	_build_content(data)


func animate_effects() -> void:
	for index in range(_effect_nodes.size()):
		var node := _effect_nodes[index]
		node.modulate.a = 0.25
		var tween := create_tween().set_loops(2)
		tween.tween_interval(0.08 * index)
		tween.tween_property(node, "modulate:a", 1.0, 0.16)
		tween.tween_property(node, "modulate:a", 0.35, 0.28)


func _build_frame() -> void:
	var flare := _make_art("%s_flare.png" % palette, Rect2(-24, 14, 222, 14))
	flare.modulate.a = 0.78
	add_child(flare)
	_effect_nodes.append(flare)

	for x_position in [-7.0, PANEL_SIZE.x - 3.0]:
		var sparkle := _make_art("sparkle.png", Rect2(x_position, 15, 10, 10))
		add_child(sparkle)
		_effect_nodes.append(sparkle)

	var fill := _make_art("panel_fill.png", Rect2(2, 2, PANEL_SIZE.x - 4, PANEL_SIZE.y - 4), TextureRect.STRETCH_TILE)
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(fill)

	var edges := [
		_make_art("%s_edge_horizontal.png" % palette, Rect2(ARM_LENGTH, 1, PANEL_SIZE.x - ARM_LENGTH * 2, EDGE_THICKNESS), TextureRect.STRETCH_TILE),
		_make_art("%s_edge_horizontal.png" % palette, Rect2(ARM_LENGTH, PANEL_SIZE.y - 3, PANEL_SIZE.x - ARM_LENGTH * 2, EDGE_THICKNESS), TextureRect.STRETCH_TILE),
		_make_art("%s_edge_vertical.png" % palette, Rect2(1, ARM_LENGTH, EDGE_THICKNESS, PANEL_SIZE.y - ARM_LENGTH * 2), TextureRect.STRETCH_TILE),
		_make_art("%s_edge_vertical.png" % palette, Rect2(PANEL_SIZE.x - 3, ARM_LENGTH, EDGE_THICKNESS, PANEL_SIZE.y - ARM_LENGTH * 2), TextureRect.STRETCH_TILE),
	]
	for edge in edges:
		edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(edge)

	var corner_positions := [
		Vector2.ZERO,
		Vector2(PANEL_SIZE.x - CORNER_SIZE.x, 0),
		Vector2(0, PANEL_SIZE.y - CORNER_SIZE.y),
		PANEL_SIZE - CORNER_SIZE,
	]
	for index in range(4):
		var suffix: String = ["tl", "tr", "bl", "br"][index]
		add_child(_make_art("%s_corner_%s.png" % [palette, suffix], Rect2(corner_positions[index], CORNER_SIZE)))


func _build_content(data: Dictionary) -> void:
	var icon_name := str(data.get("icon", "new_quest"))
	add_child(_make_art("icon_%s.png" % icon_name, Rect2(8, 8, 28, 28)))

	var divider := _make_art("%s_header_divider.png" % palette, Rect2(43, 13, 123, 4))
	add_child(divider)
	var header_gap := _make_art("panel_fill.png", Rect2(70, 2, 70, 12), TextureRect.STRETCH_TILE)
	header_gap.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(header_gap)

	var accent := Color(0.98, 0.83, 0.34, 1.0) if palette == "gold" else Color(0.45, 0.95, 1.0, 1.0)
	header_label = _place_label(UiKit.make_label(str(data.get("header", "")), 6, accent), Rect2(43, 2, 123, 12))
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(header_label)

	title_label = _place_label(
		UiKit.make_label(str(data.get("title", "")), int(data.get("title_font_size", 7)), UiKit.COLOR_TEXT),
		Rect2(43, 16, 123, 14),
		VERTICAL_ALIGNMENT_TOP,
	)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)

	subtitle_label = _place_label(
		UiKit.make_label(str(data.get("subtitle", "")), 5, Color(0.93, 0.88, 0.75, 0.82)),
		Rect2(43, 31, 123, 10),
		VERTICAL_ALIGNMENT_TOP,
	)
	add_child(subtitle_label)


func _make_art(file_name: String, rect: Rect2, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var art := TextureRect.new()
	art.texture = load(COMPONENT_DIR + file_name) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = mode
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.position = rect.position.round()
	art.size = rect.size.round()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


func _place_label(label: Label, rect: Rect2, vertical: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER) -> Label:
	label.position = rect.position.round()
	label.size = rect.size.round()
	label.vertical_alignment = vertical
	return label
