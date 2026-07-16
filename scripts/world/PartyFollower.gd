extends Node2D
## A companion that trails the player while in the party. Uses delayed-playback
## following: it replays the player's own recent positions a fixed number of frames
## behind, so it naturally walks the exact path the player walked (never clips through
## walls) and keeps a steady gap. Renders the companion's 4x4 walk sheet like an NPC.

const FPS := 8.0
const HISTORY_MAX := 360
const FOLLOW_DISTANCE := 58.0
const MIN_PLAYER_SEPARATION := 44.0
const TRAIL_SAMPLE_DISTANCE := 1.5
const FOLLOW_SPEED := 360.0
const CATCHUP_SPEED := 600.0
const CATCHUP_DISTANCE := 174.0
const FORMATION_ARRIVE_DISTANCE := 2.0
const PLAYER_AVOID_RADIUS := 50.0
const ORBIT_STEP_RADIANS := 0.42

var npc_id: String = ""
## Mirrors NPCController's discoverability contract. CutscenePlayer, the quest
## compass and Main can therefore resolve a travelling companion/escort by the
## same actor id as its stationary NPC form.
var npc_data: Dictionary = {}
var anim_sprite: AnimatedSprite2D = null

var _player: Node2D = null
var _anim: AnimatedSprite2D = null
var _shadow: Polygon2D = null
var _history: Array[Vector2] = []
var _lag_frames: int = 26
var _facing: String = "down"
var _prev_position: Vector2 = Vector2.ZERO
var _last_player_position: Vector2 = Vector2.ZERO
var _formation_orbit_sign: float = 0.0


func setup(p_npc_id: String, texture: Texture2D, player: Node2D, lag_frames: int = 26) -> void:
	npc_id = p_npc_id
	npc_data = {"id": p_npc_id, "name": p_npc_id, "travelling": true}
	add_to_group("party_follower")
	_player = player
	_lag_frames = max(8, lag_frames)
	z_index = 0
	global_position = _offset_behind_player(FOLLOW_DISTANCE)
	_prev_position = global_position
	_last_player_position = player.global_position if player != null else global_position
	_seed_history()
	_setup_shadow()
	_setup_sprite(texture)


func _seed_history() -> void:
	_history.clear()
	if _player == null or not is_instance_valid(_player):
		return
	for i in range(_lag_frames + 1):
		_history.append(_offset_behind_player(FOLLOW_DISTANCE))


func _setup_shadow() -> void:
	_shadow = Polygon2D.new()
	var points := PackedVector2Array()
	for i in 16:
		var a: float = (TAU / 16.0) * i
		points.append(Vector2(cos(a) * 10.0, sin(a) * 4.0))
	_shadow.polygon = points
	_shadow.color = Color(0, 0, 0, 0.32)
	_shadow.position = Vector2(0, 28)
	add_child(_shadow)


func _setup_sprite(texture: Texture2D) -> void:
	_anim = AnimatedSprite2D.new()
	anim_sprite = _anim
	add_child(_anim)
	if texture == null:
		texture = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
	if texture == null:
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var row_by_dir := {"down": 0, "up": 1, "right": 2, "left": 3}
	for direction in row_by_dir:
		var anim_name: String = "walk_%s" % direction
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, FPS)
		frames.set_animation_loop(anim_name, true)
		for col in GameManager.CHARACTER_SPRITE_GRID.x:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				col * GameManager.CHARACTER_FRAME_SIZE,
				int(row_by_dir[direction]) * GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE,
			)
			frames.add_frame(anim_name, atlas)
	_anim.sprite_frames = frames
	_anim.play("walk_down")
	_anim.pause()


## Snap and reseed after an intentional player teleport (battle defeat, scripted
## relocation). Without this the follower replays an obsolete cross-map trail.
func reseed_after_player_teleport() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	global_position = _offset_behind_player(FOLLOW_DISTANCE)
	_prev_position = global_position
	_last_player_position = _player.global_position
	_formation_orbit_sign = 0.0
	_seed_history()
	_face_player_direction()


## CutscenePlayer records/restores actor homes through these methods. Keeping the
## implementation here prevents its generic NPC-AI reset from writing controller
## fields that a lightweight follower intentionally does not own.
func get_return_home_destination() -> Vector2:
	return global_position


func return_home_to(destination: Vector2) -> void:
	global_position = destination
	_prev_position = destination
	_last_player_position = _player.global_position if _player != null else destination
	_seed_history()


func face_direction(direction: String) -> void:
	if direction not in ["up", "down", "left", "right"]:
		return
	_facing = direction
	if _anim != null and _anim.sprite_frames != null \
			and _anim.sprite_frames.has_animation("walk_%s" % direction):
		_anim.play("walk_%s" % direction)
		_anim.pause()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if GameManager.ui_blocking_input:
		# Frozen during chats/battles/cutscenes — hold position, freeze animation.
		if _anim != null:
			_anim.pause()
		return

	var player_position := _player.global_position
	var player_is_moving := player_position.distance_to(_last_player_position) > 0.35
	_last_player_position = player_position

	# Facing changes are not movement. Recording the same player position every
	# frame would eventually erase the real trail and replace it with a new
	# direction-based offset, making the companion jump across the player.
	if _history.is_empty() or player_position.distance_to(_history.back()) >= TRAIL_SAMPLE_DISTANCE:
		_history.append(player_position)
		if _history.size() > HISTORY_MAX:
			_history.pop_front()

	_prev_position = global_position
	if not player_is_moving:
		_move_into_idle_formation(delta)
		return
	_formation_orbit_sign = 0.0
	var idx: int = _history.size() - 1 - _lag_frames
	var target: Vector2 = _history[idx] if idx >= 0 else _offset_behind_player(FOLLOW_DISTANCE)
	target = _separated_from_player(target)
	var follow_speed := CATCHUP_SPEED if global_position.distance_to(target) > CATCHUP_DISTANCE else FOLLOW_SPEED
	global_position = global_position.move_toward(target, follow_speed * delta)
	_update_animation(global_position - _prev_position)


func _move_into_idle_formation(delta: float) -> void:
	var formation_target := _offset_behind_player(FOLLOW_DISTANCE)
	if global_position.distance_to(formation_target) <= FORMATION_ARRIVE_DISTANCE:
		global_position = formation_target
		_update_animation(Vector2.ZERO)
		_face_player_direction()
		_formation_orbit_sign = 0.0
		return

	var navigation_target := _formation_navigation_target(formation_target)
	global_position = global_position.move_toward(navigation_target, FOLLOW_SPEED * delta)
	_update_animation(global_position - _prev_position)


func _formation_navigation_target(formation_target: Vector2) -> Vector2:
	var player_pos := _player.global_position
	var current_rel := global_position - player_pos
	var target_rel := formation_target - player_pos
	if current_rel.length() < PLAYER_AVOID_RADIUS:
		var escape_dir := current_rel.normalized() if current_rel.length() > 0.01 else -_player_facing_vector()
		return player_pos + escape_dir * PLAYER_AVOID_RADIUS
	if not _segment_crosses_player(global_position, formation_target):
		_formation_orbit_sign = 0.0
		return formation_target

	var current_angle := current_rel.angle()
	var target_angle := target_rel.angle()
	var angle_delta := wrapf(target_angle - current_angle, -PI, PI)
	if _formation_orbit_sign == 0.0:
		_formation_orbit_sign = 1.0 if angle_delta >= 0.0 else -1.0
	var step := minf(absf(angle_delta), ORBIT_STEP_RADIANS) * _formation_orbit_sign
	return player_pos + Vector2.from_angle(current_angle + step) * FOLLOW_DISTANCE


func _segment_crosses_player(from: Vector2, to: Vector2) -> bool:
	var segment := to - from
	var length_sq := segment.length_squared()
	if length_sq <= 0.001:
		return false
	var t := clampf((_player.global_position - from).dot(segment) / length_sq, 0.0, 1.0)
	var closest := from + segment * t
	return closest.distance_to(_player.global_position) < PLAYER_AVOID_RADIUS


func _separated_from_player(point: Vector2) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return point
	var player_pos := _player.global_position
	var diff := point - player_pos
	if diff.length() >= MIN_PLAYER_SEPARATION:
		return point
	# Keep the target on the follower's CURRENT side of the player. Never derive
	# this correction from facing direction: turning in place must not swap sides.
	var current_diff := global_position - player_pos
	var direction := current_diff.normalized() if current_diff.length() > 0.01 else diff.normalized()
	if direction.length() <= 0.01:
		direction = Vector2.DOWN
	return player_pos + direction * MIN_PLAYER_SEPARATION


func _offset_behind_player(distance: float) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return global_position
	return _player.global_position - _player_facing_vector() * distance


func _player_facing_vector() -> Vector2:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_facing_vector"):
		var raw: Variant = _player.call("get_facing_vector")
		if raw is Vector2 and (raw as Vector2).length() > 0.01:
			return (raw as Vector2).normalized()
	if _history.size() >= 2:
		var motion := _history[_history.size() - 1] - _history[_history.size() - 2]
		if motion.length() > 0.01:
			return motion.normalized()
	return Vector2.DOWN


func _update_animation(motion: Vector2) -> void:
	if _anim == null:
		return
	if motion.length() > 0.6:
		if abs(motion.x) >= abs(motion.y):
			_facing = "right" if motion.x > 0.0 else "left"
		else:
			_facing = "down" if motion.y > 0.0 else "up"
		var anim_name: String = "walk_%s" % _facing
		if _anim.animation != anim_name:
			_anim.play(anim_name)
		elif not _anim.is_playing():
			_anim.play()
	else:
		if _anim.animation != "walk_%s" % _facing:
			_anim.play("walk_%s" % _facing)
		_anim.pause()


func _face_player_direction() -> void:
	if _anim == null:
		return
	var facing_vector := _player_facing_vector()
	if abs(facing_vector.x) >= abs(facing_vector.y):
		_facing = "right" if facing_vector.x > 0.0 else "left"
	else:
		_facing = "down" if facing_vector.y > 0.0 else "up"
	var anim_name := "walk_%s" % _facing
	if _anim.animation != anim_name:
		_anim.play(anim_name)
	_anim.pause()
