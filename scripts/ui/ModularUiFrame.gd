class_name ModularUiFrame
extends Control
## Pixel-snapped frame assembled from independent corners, repeatable edges and fill.

const COMPONENT_DIR := "res://assets/ui/quest_hint_v1/components/"
const CORNER_SIZE := Vector2(18, 18)
const EDGE_THICKNESS := 2.0
const ARM_LENGTH := 10.0

var _palette := "quest"
var _fill: TextureRect
var _corners: Array[TextureRect] = []
var _edges: Array[TextureRect] = []


func setup(rect: Rect2, palette: String) -> void:
	position = rect.position.round()
	size = rect.size.round()
	_palette = palette if palette in ["quest", "hint"] else "quest"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_build()


func set_frame_visible(is_visible: bool) -> void:
	if _fill != null:
		_fill.visible = is_visible
	for edge in _edges:
		edge.visible = is_visible
	for corner in _corners:
		corner.visible = is_visible


func _build() -> void:
	_fill = _make_piece("panel_fill.png", TextureRect.STRETCH_TILE)
	_fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_fill)

	for suffix in ["horizontal", "horizontal", "vertical", "vertical"]:
		var edge := _make_piece("%s_edge_%s.png" % [_palette, suffix], TextureRect.STRETCH_TILE)
		edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(edge)
		_edges.append(edge)

	for suffix in ["tl", "tr", "bl", "br"]:
		var corner := _make_piece("%s_corner_%s.png" % [_palette, suffix])
		add_child(corner)
		_corners.append(corner)
	_layout_parts()


func _make_piece(file_name: String, mode: TextureRect.StretchMode = TextureRect.STRETCH_SCALE) -> TextureRect:
	var piece := TextureRect.new()
	piece.texture = load(COMPONENT_DIR + file_name) as Texture2D
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = mode
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return piece


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _fill != null:
		_layout_parts()


func _layout_parts() -> void:
	var snapped := size.round()
	_fill.position = Vector2(2, 2)
	_fill.size = Vector2(maxf(0, snapped.x - 4), maxf(0, snapped.y - 4))

	_edges[0].position = Vector2(ARM_LENGTH, 1)
	_edges[0].size = Vector2(maxf(0, snapped.x - ARM_LENGTH * 2), EDGE_THICKNESS)
	_edges[1].position = Vector2(ARM_LENGTH, snapped.y - EDGE_THICKNESS - 1)
	_edges[1].size = Vector2(maxf(0, snapped.x - ARM_LENGTH * 2), EDGE_THICKNESS)
	_edges[2].position = Vector2(1, ARM_LENGTH)
	_edges[2].size = Vector2(EDGE_THICKNESS, maxf(0, snapped.y - ARM_LENGTH * 2))
	_edges[3].position = Vector2(snapped.x - EDGE_THICKNESS - 1, ARM_LENGTH)
	_edges[3].size = Vector2(EDGE_THICKNESS, maxf(0, snapped.y - ARM_LENGTH * 2))

	_corners[0].position = Vector2.ZERO
	_corners[1].position = Vector2(snapped.x - CORNER_SIZE.x, 0)
	_corners[2].position = Vector2(0, snapped.y - CORNER_SIZE.y)
	_corners[3].position = snapped - CORNER_SIZE
	for corner in _corners:
		corner.size = CORNER_SIZE
