extends Area2D
## A clickable/tappable interior scene exit. It uses the same shared world prompt
## as NPCs and interactable objects, so building doors feel like normal world
## interactions instead of a special-case "press Enter" label.

signal exit_requested(leads_to: String)

const ZoneMarkerScript := preload("res://scripts/world/ZoneMarker.gd")
const PROMPT_KIND := "exit"
const PROMPT_PRIORITY := 0
const PLAYER_COLLISION_OFFSET := Vector2(0.0, 28.0)
const PLAYER_COLLISION_HALF := Vector2(10.0, 6.0)
const TOUCH_GROW_PX := 3.0

var _exit_data: Dictionary = {}
var _label_text: String = ""
var _player: Node2D = null
var _player_in_range: bool = false
var _triggered: bool = false
var _footprint_center: Vector2 = Vector2.ZERO
var _footprint_rect: Rect2 = Rect2()


func setup(
	world_position: Vector2,
	exit_data: Dictionary,
	label_text: String,
	player: Node2D,
	footprint_rect: Rect2 = Rect2()
) -> void:
	_exit_data = exit_data.duplicate(true)
	_label_text = label_text
	_player = player
	_build(world_position, footprint_rect)
	_build_marker()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	WorldInteractionManager.clear_owner(self)


func _process(_delta: float) -> void:
	if _triggered:
		return
	if GameManager.ui_blocking_input or _player == null or not is_instance_valid(_player):
		WorldInteractionManager.clear_owner(self)
		return
	var touch_distance := _touch_distance_tiles()
	if touch_distance > 0.0:
		if _player_in_range:
			_player_in_range = false
			WorldInteractionManager.clear_owner(self)
		return
	_player_in_range = true
	WorldInteractionManager.submit_candidate(
		self,
		PROMPT_KIND,
		_prompt_label(),
		PROMPT_PRIORITY,
		touch_distance + _player.global_position.distance_to(_footprint_center) / GameManager.TILE_SIZE * 0.001,
		_player,
		"_on_prompt_confirmed"
	)


func _build(world_position: Vector2, footprint_rect: Rect2) -> void:
	if footprint_rect.size != Vector2.ZERO:
		_footprint_rect = footprint_rect
		_footprint_center = footprint_rect.position + footprint_rect.size * 0.5
		global_position = _footprint_center
	else:
		var fallback_size := Vector2(GameManager.TILE_SIZE * 2.2, GameManager.TILE_SIZE * 2.2)
		global_position = world_position
		_footprint_rect = Rect2(global_position - fallback_size * 0.5, fallback_size)
		_footprint_center = global_position

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _footprint_rect.size
	shape.shape = rect
	add_child(shape)


## Frameless destination marker floating above the entrance (same design
## system as ZoneExitPortal's edge marker): name + hairline rule + a chevron
## pointing down at the door. No panel — see scripts/world/ZoneMarker.gd.
func _build_marker() -> void:
	if _label_text.strip_edges().is_empty():
		return
	var marker := ZoneMarkerScript.new() as Node2D
	marker.setup(_label_text, Vector2.DOWN, _player)
	marker.position = Vector2(0.0, -(_footprint_rect.size.y * 0.5 + 12.0))
	add_child(marker)


func _touch_distance_tiles() -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	var foot_center := _player.global_position + PLAYER_COLLISION_OFFSET
	var player_rect := Rect2(foot_center - PLAYER_COLLISION_HALF, PLAYER_COLLISION_HALF * 2.0).grow(TOUCH_GROW_PX)
	if player_rect.intersects(_footprint_rect, true):
		return 0.0
	var nearest := Vector2(
		clampf(foot_center.x, _footprint_rect.position.x, _footprint_rect.end.x),
		clampf(foot_center.y, _footprint_rect.position.y, _footprint_rect.end.y),
	)
	return maxf(0.0, foot_center.distance_to(nearest) - PLAYER_COLLISION_HALF.length()) / GameManager.TILE_SIZE


func _prompt_label() -> String:
	if _label_text.strip_edges().is_empty():
		return "Vào"
	return "Vào %s" % _label_text


func _on_body_entered(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	WorldInteractionManager.clear_owner(self)


func _on_prompt_confirmed(_item: String, _index: int) -> void:
	_request_exit()


func _request_exit() -> void:
	if _triggered:
		return
	var leads_to := str(_exit_data.get("leads_to", ""))
	if leads_to.is_empty():
		return
	_triggered = true
	WorldInteractionManager.clear_owner(self)
	exit_requested.emit(leads_to)


func _is_player_body(body: Node2D) -> bool:
	if _player != null and is_instance_valid(_player) and body == _player:
		return true
	return body != null and body.get("camera") != null
