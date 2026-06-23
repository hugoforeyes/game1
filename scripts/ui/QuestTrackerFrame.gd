class_name QuestTrackerFrame
extends Control
## Resizable tracker frame built from one complete generated-frame source.

const COMPONENT_DIR := "res://assets/ui/quest_tracker_v2/components/"
const CORNER_SIZE := Vector2(24, 24)
const EDGE_THICKNESS := 3.0

var _background: ColorRect
var _corners: Array[TextureRect] = []
var _edges: Array[TextureRect] = []
var _mid_badges: Array[TextureRect] = []


func setup(rect: Rect2) -> void:
	position = rect.position.round()
	size = rect.size.round()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_build()


func set_frame_visible(is_visible: bool) -> void:
	_background.visible = is_visible
	for node in _corners:
		node.visible = is_visible
	for node in _edges:
		node.visible = is_visible
	for node in _mid_badges:
		node.visible = is_visible


func _build() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.045, 0.038, 0.030, 0.93)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	for side in ["top", "bottom", "left", "right"]:
		var edge := _make_piece("edge_%s.png" % side, TextureRect.STRETCH_TILE)
		edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		add_child(edge)
		_edges.append(edge)

	for suffix in ["tl", "tr", "bl", "br"]:
		var corner := _make_piece("corner_%s.png" % suffix)
		add_child(corner)
		_corners.append(corner)

	for side in ["top", "bottom", "left", "right"]:
		var badge := _make_piece("mid_%s.png" % side)
		add_child(badge)
		_mid_badges.append(badge)
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
	if what == NOTIFICATION_RESIZED and _background != null:
		_layout_parts()


func _layout_parts() -> void:
	var snapped := size.round()
	_background.position = Vector2(3, 3)
	_background.size = Vector2(maxf(0, snapped.x - 6), maxf(0, snapped.y - 6))

	_edges[0].position = Vector2(18, 0)
	_edges[0].size = Vector2(maxf(0, snapped.x - 36), EDGE_THICKNESS)
	_edges[1].position = Vector2(18, snapped.y - EDGE_THICKNESS)
	_edges[1].size = Vector2(maxf(0, snapped.x - 36), EDGE_THICKNESS)
	_edges[2].position = Vector2(0, 18)
	_edges[2].size = Vector2(EDGE_THICKNESS, maxf(0, snapped.y - 36))
	_edges[3].position = Vector2(snapped.x - EDGE_THICKNESS, 18)
	_edges[3].size = Vector2(EDGE_THICKNESS, maxf(0, snapped.y - 36))

	_corners[0].position = Vector2.ZERO
	_corners[1].position = Vector2(snapped.x - CORNER_SIZE.x, 0)
	_corners[2].position = Vector2(0, snapped.y - CORNER_SIZE.y)
	_corners[3].position = snapped - CORNER_SIZE
	for corner in _corners:
		corner.size = CORNER_SIZE

	_mid_badges[0].position = Vector2(roundf((snapped.x - 22.0) * 0.5), 0)
	_mid_badges[0].size = Vector2(22, 12)
	_mid_badges[1].position = Vector2(roundf((snapped.x - 22.0) * 0.5), snapped.y - 12)
	_mid_badges[1].size = Vector2(22, 12)
	_mid_badges[2].position = Vector2(0, roundf((snapped.y - 22.0) * 0.5))
	_mid_badges[2].size = Vector2(12, 22)
	_mid_badges[3].position = Vector2(snapped.x - 12, roundf((snapped.y - 22.0) * 0.5))
	_mid_badges[3].size = Vector2(12, 22)
