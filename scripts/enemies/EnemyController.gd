extends CharacterBody2D

signal battle_requested(enemy: Node)

const FPS := 8.0
const CONTACT_DISTANCE_TILES := 0.9
const CHASE_SPEED := 128.0
const WANDER_SPEED := 44.0
const AGGRO_COOLDOWN_SECONDS := 4.0

enum State { IDLE, WANDER, CHASE, COOLDOWN, PASSIVE, RETURN_HOME }

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $Shadow
@onready var alert_label: Label = $AlertLabel

var enemy_data: Dictionary = {}
var map_tile_size := Vector2i.ZERO
var blocked_tiles: Dictionary = {}
var spawn_tile := Vector2i.ZERO
var patrol_radius: int = 3
var aggro_radius: float = 4.0
var state: State = State.WANDER
var wait_timer: float = 0.0
var cooldown_timer: float = 0.0
var target_position := Vector2.ZERO
var last_facing: String = "down"
var _player: Node2D = null
var _battle_pending: bool = false
var _return_home_active: bool = false
var _return_home_position := Vector2.ZERO
var _return_path: Array[Vector2i] = []
var _return_path_index: int = 0
var _return_retry_timer: float = 0.0
var _return_resume_state: State = State.WANDER
var _return_home_suspended: bool = false
var _cutscene_control_active: bool = false

func setup(data: Dictionary, world_context: Dictionary) -> void:
	enemy_data = data
	map_tile_size = world_context.get("map_tile_size", Vector2i.ZERO) as Vector2i
	blocked_tiles = (world_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	_player = world_context.get("player") as Node2D

	var spawn: Dictionary = data.get("spawn", {}) as Dictionary
	spawn_tile = _read_tile(spawn.get("position_tile"))
	patrol_radius = int(spawn.get("patrol_radius", 3))
	aggro_radius = float(spawn.get("aggro_radius", 4))
	global_position = _tile_to_pixel_center(spawn_tile)
	target_position = global_position

	if bool(data.get("_spared", false)):
		state = State.PASSIVE

	_setup_shadow()
	_setup_sprite_frames()
	alert_label.visible = false
	_pick_wander_target()

func _physics_process(delta: float) -> void:
	if GameManager.ui_blocking_input:
		# Frozen during chats, battles, and cutscenes; cutscenes may drive
		# position and animation directly while this gate holds.
		velocity = Vector2.ZERO
		if not _cutscene_control_active:
			_update_animation()
		return

	match state:
		State.COOLDOWN:
			cooldown_timer -= delta
			_wander_step()
			if cooldown_timer <= 0.0:
				state = State.WANDER
		State.PASSIVE:
			_wander_step()
		State.WANDER, State.IDLE:
			_wander_step()
			_check_aggro()
		State.CHASE:
			_chase_step()
		State.RETURN_HOME:
			_return_home_step(delta)

	move_and_slide()
	_update_animation()

func is_hostile() -> bool:
	var effectively_passive := state == State.PASSIVE \
			or (_return_home_active and _return_resume_state == State.PASSIVE)
	return visible and not is_queued_for_deletion() and not effectively_passive

func start_battle_cooldown() -> void:
	state = State.COOLDOWN
	cooldown_timer = AGGRO_COOLDOWN_SECONDS
	alert_label.visible = false
	_battle_pending = false

func become_passive() -> void:
	if _return_home_active:
		_return_resume_state = State.PASSIVE
	else:
		state = State.PASSIVE
	alert_label.visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.85)

func return_home_to(world_position: Vector2) -> void:
	## Post-cutscene movement is gameplay-owned. EnemyController follows a grid
	## path with its normal collision/speed instead of being snapped by cutscene UI.
	_cutscene_control_active = false
	if not visible or is_queued_for_deletion():
		return
	if not _return_home_active and not _return_home_suspended:
		_return_resume_state = State.PASSIVE if state == State.PASSIVE else State.WANDER
	_return_home_suspended = false
	_return_home_active = true
	_return_home_position = world_position
	_return_retry_timer = 0.0
	_battle_pending = false
	alert_label.visible = false
	state = State.RETURN_HOME
	_build_return_path()

func is_returning_home() -> bool:
	return _return_home_active

func get_return_home_destination() -> Vector2:
	return _return_home_position if _return_home_active else global_position

func suspend_return_home_for_cutscene() -> void:
	_cutscene_control_active = true
	if not _return_home_active:
		_return_resume_state = State.PASSIVE if state == State.PASSIVE else State.WANDER
	_return_home_suspended = true
	_return_home_active = false
	_return_path.clear()
	velocity = Vector2.ZERO

func _return_home_step(delta: float) -> void:
	if not _return_home_active:
		_finish_return_home()
		return
	if _return_path_index >= _return_path.size():
		if global_position.distance_to(_return_home_position) <= 3.0:
			_finish_return_home()
			return
		_return_retry_timer -= delta
		velocity = Vector2.ZERO
		if _return_retry_timer <= 0.0:
			_build_return_path()
		return

	var tile := _return_path[_return_path_index]
	var target := _return_home_position if _return_path_index == _return_path.size() - 1 \
			else _tile_to_pixel_center(tile)
	var to_target := target - global_position
	if to_target.length() <= 3.0:
		global_position = target
		_return_path_index += 1
		if _return_path_index >= _return_path.size():
			_finish_return_home()
		return
	velocity = to_target.normalized() * WANDER_SPEED

func _build_return_path() -> void:
	_return_path.clear()
	_return_path_index = 0
	var start := _pixel_to_tile(global_position)
	var destination := _pixel_to_tile(_return_home_position)
	if start == destination:
		_return_path.append(destination)
		return
	if map_tile_size == Vector2i.ZERO or not _is_walkable(destination):
		_return_retry_timer = 0.5
		return

	var astar := AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, map_tile_size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for key in blocked_tiles:
		var blocked_tile := _tile_from_key(str(key))
		if astar.is_in_boundsv(blocked_tile):
			astar.set_point_solid(blocked_tile, true)
	if not astar.is_in_boundsv(start) or not astar.is_in_boundsv(destination):
		_return_retry_timer = 0.5
		return
	var raw_path := astar.get_id_path(start, destination)
	for index in range(1, raw_path.size()):
		_return_path.append(raw_path[index])
	if _return_path.is_empty():
		_return_retry_timer = 0.5

func _finish_return_home() -> void:
	if _return_home_active:
		global_position = _return_home_position
	_return_home_active = false
	_return_path.clear()
	velocity = Vector2.ZERO
	state = _return_resume_state
	_pick_wander_target()

func _check_aggro() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var distance_tiles: float = global_position.distance_to(_player.global_position) / GameManager.TILE_SIZE
	if distance_tiles <= aggro_radius:
		state = State.CHASE
		alert_label.visible = true

func _chase_step() -> void:
	if _player == null or not is_instance_valid(_player):
		state = State.WANDER
		return
	var to_player: Vector2 = _player.global_position - global_position
	var distance_tiles: float = to_player.length() / GameManager.TILE_SIZE

	if distance_tiles <= CONTACT_DISTANCE_TILES and not _battle_pending:
		_battle_pending = true
		velocity = Vector2.ZERO
		battle_requested.emit(self)
		return

	if distance_tiles > aggro_radius * 1.8:
		state = State.WANDER
		alert_label.visible = false
		_pick_wander_target()
		return

	velocity = to_player.normalized() * CHASE_SPEED

func _wander_step() -> void:
	if wait_timer > 0.0:
		wait_timer -= get_physics_process_delta_time()
		velocity = Vector2.ZERO
		return
	var to_target: Vector2 = target_position - global_position
	if to_target.length() < 3.0:
		wait_timer = randf_range(1.0, 2.6)
		_pick_wander_target()
		velocity = Vector2.ZERO
		return
	velocity = to_target.normalized() * WANDER_SPEED

func _pick_wander_target() -> void:
	for _attempt in range(8):
		var offset := Vector2i(
			randi_range(-patrol_radius, patrol_radius),
			randi_range(-patrol_radius, patrol_radius),
		)
		var tile: Vector2i = spawn_tile + offset
		if _is_walkable(tile):
			target_position = _tile_to_pixel_center(tile)
			return
	target_position = _tile_to_pixel_center(spawn_tile)

func _is_walkable(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0:
		return false
	if map_tile_size != Vector2i.ZERO and (tile.x >= map_tile_size.x or tile.y >= map_tile_size.y):
		return false
	return not blocked_tiles.has("%s:%s" % [tile.x, tile.y])

func _setup_sprite_frames() -> void:
	var sprite_sheet_file: String = str(enemy_data.get("sprite_sheet_file", ""))
	var texture: Texture2D = null
	if not sprite_sheet_file.is_empty():
		texture = GameManager.load_texture(GameManager.get_scene_asset_path(sprite_sheet_file))
	if texture == null:
		# Fallback: use the player sheet tinted red so missing art never blocks play.
		texture = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
		modulate = Color(1.0, 0.45, 0.45)
	if texture == null:
		return

	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for direction_index in range(4):
		var direction: String = ["down", "up", "right", "left"][direction_index]
		var animation_name: String = "walk_%s" % direction
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, FPS)
		frames.set_animation_loop(animation_name, true)
		for col in range(4):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				col * GameManager.CHARACTER_FRAME_SIZE,
				direction_index * GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE
			)
			frames.add_frame(animation_name, atlas)
	anim_sprite.sprite_frames = frames
	anim_sprite.play("walk_down")
	anim_sprite.pause()

func _update_animation() -> void:
	if velocity == Vector2.ZERO:
		anim_sprite.pause()
		return
	var direction: String
	if abs(velocity.x) >= abs(velocity.y):
		direction = "right" if velocity.x > 0 else "left"
	else:
		direction = "down" if velocity.y > 0 else "up"
	last_facing = direction
	var animation_name := "walk_%s" % direction
	if anim_sprite.animation != animation_name or not anim_sprite.is_playing():
		anim_sprite.play(animation_name)

func _setup_shadow() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(16):
		var angle: float = (TAU / 16) * i
		points.append(Vector2(cos(angle) * 20.0, sin(angle) * 8.0))
	shadow.polygon = points

func _tile_to_pixel_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)

func _pixel_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(GameManager.TILE_SIZE)),
		floori(world_position.y / float(GameManager.TILE_SIZE)),
	)

func _tile_from_key(key: String) -> Vector2i:
	var parts := key.split(":")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

func _read_tile(raw: Variant) -> Vector2i:
	if raw is Dictionary:
		return Vector2i(int((raw as Dictionary).get("x", 0)), int((raw as Dictionary).get("y", 0)))
	return Vector2i.ZERO
