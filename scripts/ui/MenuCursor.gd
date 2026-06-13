extends Control

const CURSOR_COLOR := Color(0.91, 0.75, 0.31, 1.0)
const SHADOW_COLOR := Color(0.03, 0.02, 0.02, 0.78)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var points := PackedVector2Array([
		Vector2(1.0, 1.0),
		Vector2(size.x - 1.0, size.y * 0.5),
		Vector2(1.0, size.y - 1.0),
	])
	var shadow_points := PackedVector2Array([
		points[0] + Vector2(1.0, 1.0),
		points[1] + Vector2(1.0, 1.0),
		points[2] + Vector2(1.0, 1.0),
	])
	draw_colored_polygon(shadow_points, SHADOW_COLOR)
	draw_colored_polygon(points, CURSOR_COLOR)
