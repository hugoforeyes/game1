extends Node
## Regression: turning the player in place must never teleport a companion from
## one side of the player to the other.

const PartyFollowerScript := preload("res://scripts/world/PartyFollower.gd")

class FacingPlayer extends Node2D:
	var facing := Vector2.RIGHT

	func get_facing_vector() -> Vector2:
		return facing


func _ready() -> void:
	var player := FacingPlayer.new()
	player.global_position = Vector2(1000, 1000)
	add_child(player)

	var follower: Node2D = PartyFollowerScript.new()
	add_child(follower)
	follower.setup("companion_test", null, player, 26)
	assert(follower.global_position.x < player.global_position.x)

	# Let an idle period exceed the old lag window, then reverse facing without
	# moving the player. The companion must walk AROUND the player into the new
	# behind position, never teleport or cross through the player's body.
	for _i in range(40):
		follower._physics_process(1.0 / 60.0)
	player.facing = Vector2.LEFT
	var max_step := 0.0
	var min_separation := INF
	for _i in range(120):
		var before := follower.global_position
		follower._physics_process(1.0 / 60.0)
		max_step = maxf(max_step, before.distance_to(follower.global_position))
		min_separation = minf(min_separation, follower.global_position.distance_to(player.global_position))

	var expected_behind := player.global_position - player.facing * PartyFollowerScript.FOLLOW_DISTANCE
	assert(follower.global_position.distance_to(expected_behind) < 1.0, "idle companion must settle behind the player")
	assert(follower.global_position.x > player.global_position.x, "companion must reach the new behind side by walking")
	assert(min_separation >= PartyFollowerScript.PLAYER_AVOID_RADIUS - 0.5, "companion path must go around, not through, the player")
	assert(max_step <= PartyFollowerScript.CATCHUP_SPEED / 60.0 + 0.01, "every position change must be speed-bounded, not a teleport")
	assert(follower._anim.animation == "walk_left", "idle companion must face the same direction as the player")
	assert(not follower._anim.is_playing())
	print("[PartyFollowerMovementTest] idle formation, shared facing, avoidance, and speed bounds passed")
	get_tree().quit()
