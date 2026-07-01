extends Node
## Test-only stand-in for Main.gd's two compass-facing lookup methods — lets
## QuestCompassPreview.gd control exactly where "the target" is without
## needing a fully loaded zone.

var target_position: Vector2 = Vector2.INF


func find_entity_global_position(_kind: String, _entity_id: String) -> Vector2:
	return target_position


func find_exit_toward_zone(_target_zone_id: String) -> Vector2:
	return target_position
