extends Node2D
## A companion that trails the player while in the party. Uses delayed-playback
## following: it replays the player's own recent positions a fixed number of frames
## behind, so it naturally walks the exact path the player walked (never clips through
## walls) and keeps a steady gap. Renders the companion's 4x4 walk sheet like an NPC.

const FPS := 8.0
const HISTORY_MAX := 360
const FOLLOW_DISTANCE := 58.0
const MIN_PLAYER_SEPARATION := 44.0
const CATCHUP_LERP := 0.35
const IDLE_COMFORT_RADIUS := 18.0

var npc_id: String = ""

var _player: Node2D = null
var _anim: AnimatedSprite2D = null
var _shadow: Polygon2D = null
var _history: Array[Vector2] = []
var _lag_frames: int = 26
var _facing: String = "down"
var _prev_position: Vector2 = Vector2.ZERO
var _last_player_position: Vector2 = Vector2.ZERO


func setup(p_npc_id: String, texture: Texture2D, player: Node2D, lag_frames: int = 26) -> void:
	npc_id = p_npc_id
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


func _physics_process(_delta: float) -> void:
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

	_history.append(player_position)
	if _history.size() > HISTORY_MAX:
		_history.pop_front()

	var idx: int = _history.size() - 1 - _lag_frames
	var target: Vector2 = _history[idx] if idx >= 0 else _offset_behind_player(FOLLOW_DISTANCE)
	target = _separated_from_player(target)
	_prev_position = global_position
	if not player_is_moving and _is_idle_close_enough():
		_face_player_direction()
		return
	global_position = global_position.lerp(target, CATCHUP_LERP)
	global_position = _separated_from_player(global_position)
	_update_animation(global_position - _prev_position)


func _separated_from_player(point: Vector2) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return point
	var player_pos := _player.global_position
	var diff := point - player_pos
	if diff.length() >= MIN_PLAYER_SEPARATION:
		return point
	var behind := _offset_behind_player(FOLLOW_DISTANCE)
	if behind.distance_to(player_pos) >= MIN_PLAYER_SEPARATION:
		return behind
	var direction := diff.normalized() if diff.length() > 0.01 else -_player_facing_vector()
	return player_pos + direction * MIN_PLAYER_SEPARATION


func _offset_behind_player(distance: float) -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return global_position
	return _player.global_position - _player_facing_vector() * distance


func _is_idle_close_enough() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var distance_to_player := global_position.distance_to(_player.global_position)
	return distance_to_player >= MIN_PLAYER_SEPARATION and distance_to_player <= FOLLOW_DISTANCE + IDLE_COMFORT_RADIUS


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
