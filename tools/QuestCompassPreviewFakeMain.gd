extends Node
## Test-only stand-in for Main.gd's two compass-facing lookup methods — lets
## QuestCompassPreview.gd control exactly where "the target" is without
## needing a fully loaded zone.

var target_position: Vector2 = Vector2.INF
var hostile_positions: Array = []


func find_entity_global_position(_kind: String, _entity_id: String) -> Vector2:
	return target_position


func find_exit_toward_zone(_target_zone_id: String) -> Vector2:
	return target_position


func find_nearest_hostile_global_position(from_position: Vector2) -> Vector2:
	var nearest := Vector2.INF
	var nearest_distance_sq := INF
	for raw_position in hostile_positions:
		if not (raw_position is Vector2):
			continue
		var position := raw_position as Vector2
		var distance_sq := from_position.distance_squared_to(position)
		if distance_sq < nearest_distance_sq:
			nearest = position
			nearest_distance_sq = distance_sq
	return nearest
