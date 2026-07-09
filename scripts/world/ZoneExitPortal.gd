extends Area2D
## Auto-transfer trigger for edge zone exits. The player moves by stepping into
## the exit; the visual is a frameless ZoneMarker (destination name + chevron
## pointing at the map edge) — no panel, no box (see scripts/world/ZoneMarker.gd).

signal exit_requested(leads_to: String, edge: String, normalized: float)

const ZoneMarkerScript := preload("res://scripts/world/ZoneMarker.gd")

var _edge := ""
var _leads_to := ""
var _normalized := 0.5
var _player: Node2D = null


func setup(
	world_position: Vector2,
	edge: String,
	leads_to: String,
	normalized: float,
	label_text: String,
	player: Node2D
) -> void:
	global_position = world_position
	_edge = edge.to_lower()
	_leads_to = leads_to
	_normalized = normalized
	_player = player
	name = "ZoneExitPortal"
	_build_collision()
	_build_marker(label_text, player)
	body_entered.connect(_on_body_entered)


func _build_collision() -> void:
	var tile := float(GameManager.TILE_SIZE)
	var rect := RectangleShape2D.new()
	if _edge == "east" or _edge == "west":
		rect.size = Vector2(tile * 1.2, tile * 3.0)
	else:
		rect.size = Vector2(tile * 3.0, tile * 1.2)

	var shape := CollisionShape2D.new()
	shape.shape = rect
	add_child(shape)


func _build_marker(label_text: String, player: Node2D) -> void:
	var marker := ZoneMarkerScript.new() as Node2D
	marker.setup(label_text, _edge_dir(), player)
	# The chevron (marker origin) hugs the exit mouth; the name stacks inward.
	marker.position = _edge_dir() * float(GameManager.TILE_SIZE) * 0.35
	add_child(marker)


func _edge_dir() -> Vector2:
	match _edge:
		"east":
			return Vector2.RIGHT
		"west":
			return Vector2.LEFT
		"north":
			return Vector2.UP
		"south":
			return Vector2.DOWN
	return Vector2.RIGHT


func _on_body_entered(body: Node2D) -> void:
	if GameManager.ui_blocking_input:
		return
	if not _is_player_body(body):
		return
	exit_requested.emit(_leads_to, _edge, _normalized)


func _is_player_body(body: Node2D) -> bool:
	if _player != null and is_instance_valid(_player) and body == _player:
		return true
	return body != null and body.get("camera") != null
