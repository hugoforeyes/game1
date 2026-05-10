extends CharacterBody2D

const SpeechBubble       := preload("res://scripts/npc/SpeechBubble.gd")
const InteractionPrompt  := preload("res://scripts/npc/InteractionPrompt.gd")
const FPS := 8.0
const BUBBLE_FULL_TILES  := 2.5
const BUBBLE_FADE_TILES  := 4.0
const ARRIVE_DISTANCE := 2.0
const STUCK_DISTANCE_EPSILON := 0.75
const STUCK_TIME_LIMIT := 0.8
const MAX_PATH_SEARCH_NODES := 240

enum State {
	IDLE,
	WAITING,
	CHOOSING_TARGET,
	MOVING,
	BLOCKED,
}

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $Shadow

var npc_data: Dictionary = {}
var movement: Dictionary = {}
var interaction: Dictionary = {}
var map_tile_size := Vector2i.ZERO
var blocked_tiles: Dictionary = {}
var occupied_tiles: Dictionary = {}
var tile_metadata: Dictionary = {}
var anchor_tile := Vector2i.ZERO
var current_tile := Vector2i.ZERO
var target_tile := Vector2i.ZERO
var target_position := Vector2.ZERO
var state: State = State.IDLE
var wait_timer: float = 0.0
var speed: float = 18.0
var path_tiles: Array[Vector2i] = []
var path_index: int = 0
var path_direction: int = 1
var active_path: Array[Vector2i] = []
var active_path_index: int = 0
var desired_tile := Vector2i.ZERO
var previous_position := Vector2.ZERO
var stuck_timer: float = 0.0
var erratic_returning_to_anchor: bool = false
var last_facing: String = "down"
var _lighting_sys: Node = null
var _bubble: Node2D = null
var _prompt: Node2D = null
var _prompt_layer: CanvasLayer = null
var _player: Node2D = null
var _bubble_lines: Array = []
var _bubble_showing: bool = false
var _interaction_enabled: bool = false
var _interaction_radius: float = 1.5
var _in_interaction_range: bool = false

func setup(data: Dictionary, world_context: Dictionary) -> void:
	npc_data = data
	movement = data.get("movement", {}) as Dictionary
	interaction = data.get("interaction", {}) as Dictionary
	map_tile_size = world_context.get("map_tile_size", Vector2i.ZERO) as Vector2i
	blocked_tiles = (world_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	occupied_tiles = (world_context.get("occupied_tiles", {}) as Dictionary).duplicate()
	tile_metadata = (world_context.get("tile_metadata", {}) as Dictionary).duplicate(true)
	_player = world_context.get("player") as Node2D
	current_tile = _read_tile_position(data)
	anchor_tile = _read_tile_position(movement.get("anchor_tile", {}) as Dictionary)
	if anchor_tile == Vector2i.ZERO:
		anchor_tile = current_tile
	target_tile = current_tile
	target_position = _tile_to_pixel_center(current_tile)
	global_position = target_position
	speed = max(float(movement.get("speed", speed)), 0.0)
	path_tiles = _read_path_tiles(movement.get("path_tiles", []))
	_lighting_sys = get_tree().get_first_node_in_group("lighting")
	_setup_shadow()
	_setup_sprite_frames()
	_start_behavior()
	_setup_bubble()
	_setup_interaction()

func _setup_bubble() -> void:
	_bubble_lines = (npc_data.get("interaction", {}) as Dictionary).get("lines", []) as Array
	if _bubble_lines.is_empty():
		return
	_bubble = SpeechBubble.new()
	_bubble.position = Vector2(0.0, -24.0)
	add_child(_bubble)

func _physics_process(delta: float) -> void:
	match state:
		State.WAITING, State.BLOCKED:
			wait_timer -= delta
			velocity = Vector2.ZERO
			if wait_timer <= 0.0:
				state = State.CHOOSING_TARGET
		State.CHOOSING_TARGET:
			_choose_next_target()
		State.MOVING:
			_move_to_target()
		_:
			velocity = Vector2.ZERO

	_update_animation()
	_update_shadow()
	_update_bubble_alpha()
	_update_interaction()

func _setup_interaction() -> void:
	var inter := npc_data.get("interaction", {}) as Dictionary
	_interaction_enabled = bool(inter.get("enabled", false))
	if not _interaction_enabled:
		return
	_interaction_radius = float(inter.get("proximity_radius_tiles", 1.5))
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 128
	add_child(_prompt_layer)
	_prompt = InteractionPrompt.new()
	_prompt_layer.add_child(_prompt)
	var npc_name := str(npc_data.get("name", "NPC"))
	var raw_opts: Variant = inter.get("options", [])
	var items: Array[String] = []
	if raw_opts is Array:
		for opt in raw_opts:
			items.append(str(opt))
	if items.is_empty():
		items = ["Talk"]
	_prompt.setup_menu(npc_name, items)
	_prompt.track(_player, Vector2(0.0, 0.0))
	_prompt.item_confirmed.connect(_on_interaction_item_confirmed)

func _on_interaction_item_confirmed(item: String, _index: int) -> void:
	print("[NPC] %s → %s" % [str(npc_data.get("name", "")), item])

func _update_interaction() -> void:
	if not _interaction_enabled or _player == null or not is_instance_valid(_player):
		return
	var dist_tiles := global_position.distance_to(_player.global_position) / GameManager.TILE_SIZE
	var in_range   := dist_tiles <= _interaction_radius
	if in_range and not _in_interaction_range:
		_in_interaction_range = true
		state     = State.IDLE
		velocity  = Vector2.ZERO
		_prompt.show_prompt()
	elif not in_range and _in_interaction_range:
		_in_interaction_range = false
		state = State.CHOOSING_TARGET
		_prompt.hide_prompt()
	if _in_interaction_range:
		_face_player()

func _face_player() -> void:
	var diff := _player.global_position - global_position
	if abs(diff.x) >= abs(diff.y):
		last_facing = "right" if diff.x > 0.0 else "left"
	else:
		last_facing = "down" if diff.y > 0.0 else "up"

func _update_bubble_alpha() -> void:
	if _bubble == null:
		return
	if _player == null or not is_instance_valid(_player):
		_bubble.target_alpha = 0.0
		_bubble_showing = false
		return
	var dist_tiles := global_position.distance_to(_player.global_position) / GameManager.TILE_SIZE
	var alpha: float
	if dist_tiles <= BUBBLE_FULL_TILES:
		alpha = 1.0
	elif dist_tiles >= BUBBLE_FADE_TILES:
		alpha = 0.0
	else:
		alpha = 1.0 - (dist_tiles - BUBBLE_FULL_TILES) / (BUBBLE_FADE_TILES - BUBBLE_FULL_TILES)
	if alpha > 0.0 and not _bubble_showing:
		_bubble_showing = true
		_bubble.show_text(str(_bubble_lines.pick_random()))
	elif alpha == 0.0:
		_bubble_showing = false
	_bubble.target_alpha = alpha

func _update_shadow() -> void:
	if _lighting_sys == null or not is_instance_valid(_lighting_sys):
		_lighting_sys = get_tree().get_first_node_in_group("lighting")
	if _lighting_sys == null:
		return
	var light_pos: Vector2 = _lighting_sys.get_dominant_light_pos(global_position)
	if light_pos == Vector2.ZERO:
		shadow.position = Vector2(0.0, 14.0)
		shadow.rotation = 0.0
		shadow.modulate.a = 0.35
		return
	var to_char: Vector2 = global_position - light_pos
	var dist: float = to_char.length()
	var dir: Vector2 = to_char.normalized() if dist > 1.0 else Vector2(0.0, 1.0)
	var tile_dist: float = dist / 36.0
	var offset_px: float = clampf(tile_dist * 1.8, 2.0, 12.0)
	shadow.position = Vector2(0.0, 14.0) + dir * offset_px
	shadow.rotation = dir.angle()
	shadow.modulate.a = clampf(0.65 - tile_dist * 0.04, 0.15, 0.60)

func _setup_shadow() -> void:
	var rx: float = 10.0
	var ry: float = 4.0
	var segments: int = 16
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var angle: float = (TAU / segments) * i
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	shadow.polygon = points

func _setup_sprite_frames() -> void:
	var sprite_sheet_file: String = str(npc_data.get("sprite_sheet_file", ""))
	var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(sprite_sheet_file))
	if texture == null:
		return

	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")
	for direction in ["down", "up", "right", "left"]:
		var animation_name: String = "walk_%s" % direction
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, FPS)
		frames.set_animation_loop(animation_name, true)
		var cells: Array[Vector2i] = _default_animation_cells(direction)
		for cell in cells:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				cell.x * GameManager.CHARACTER_FRAME_SIZE,
				cell.y * GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE,
				GameManager.CHARACTER_FRAME_SIZE
			)
			frames.add_frame(animation_name, atlas)

	anim_sprite.sprite_frames = frames
	anim_sprite.play("walk_%s" % last_facing)
	anim_sprite.pause()

func _start_behavior() -> void:
	var movement_type: String = str(movement.get("type", movement.get("movement_style", npc_data.get("movement_style", "fixed"))))
	if movement_type == "fixed":
		state = State.IDLE
		return

	_wait_random()

func _choose_next_target() -> void:
	var movement_type: String = str(movement.get("type", npc_data.get("movement_style", "fixed")))
	match movement_type:
		"fixed":
			state = State.IDLE
		"idle_loop":
			_turn_randomly()
			_wait_random()
		"linear", "patrol":
			_choose_path_target()
		"erratic":
			_choose_erratic_target()
		_:
			_choose_wander_target()

func _choose_wander_target() -> void:
	var radius: int = max(int(movement.get("radius_tiles", 1)), 0)
	var candidates: Array[Vector2i] = []
	for y in range(anchor_tile.y - radius, anchor_tile.y + radius + 1):
		for x in range(anchor_tile.x - radius, anchor_tile.x + radius + 1):
			var tile := Vector2i(x, y)
			if tile == current_tile:
				continue
			if Vector2(tile).distance_to(Vector2(anchor_tile)) > float(radius) + 0.01:
				continue
			if _is_valid_target_tile(tile):
				candidates.append(tile)

	if candidates.is_empty():
		_wait_random()
		return

	_start_move_to(_pick_best_tile(candidates))

func _choose_erratic_target() -> void:
	if erratic_returning_to_anchor and _is_valid_target_tile(anchor_tile):
		erratic_returning_to_anchor = false
		_start_move_to(anchor_tile)
		return

	erratic_returning_to_anchor = true
	var radius: int = clampi(int(movement.get("radius_tiles", 1)), 1, 2)
	var offsets := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
	]
	offsets.shuffle()
	for offset in offsets:
		var tile: Vector2i = anchor_tile + offset * radius
		if _is_valid_target_tile(tile):
			_start_move_to(_pick_best_tile([tile, anchor_tile]))
			return

	_wait_random()

func _choose_path_target() -> void:
	if path_tiles.is_empty():
		_choose_wander_target()
		return

	var loop: bool = bool(movement.get("loop", true))
	path_index = clampi(path_index, 0, path_tiles.size() - 1)
	var candidate: Vector2i = path_tiles[path_index]
	if _is_valid_target_tile(candidate):
		_start_move_to(candidate)
	else:
		var fallback: Vector2i = _nearest_valid_tile(candidate, max(int(movement.get("radius_tiles", 2)), 2))
		if fallback != current_tile:
			_start_move_to(fallback)

	if path_tiles.size() <= 1:
		path_index = 0
	elif loop:
		path_index = (path_index + 1) % path_tiles.size()
	else:
		if path_index == path_tiles.size() - 1:
			path_direction = -1
		elif path_index == 0:
			path_direction = 1
		path_index += path_direction

func _start_move_to(tile: Vector2i) -> void:
	desired_tile = tile
	active_path = _find_path(current_tile, tile)
	active_path_index = 0
	if active_path.is_empty():
		_handle_stuck()
		return
	_set_next_path_target()
	previous_position = global_position
	stuck_timer = 0.0
	state = State.MOVING

func _move_to_target() -> void:
	var distance: float = global_position.distance_to(target_position)
	if distance <= ARRIVE_DISTANCE:
		global_position = target_position
		current_tile = target_tile
		active_path_index += 1
		if active_path_index >= active_path.size():
			velocity = Vector2.ZERO
			_wait_random()
			return
		_set_next_path_target()
		return

	var direction: Vector2 = global_position.direction_to(target_position)
	velocity = direction * speed
	move_and_slide()
	_update_stuck_timer()
	if get_slide_collision_count() > 0 or stuck_timer >= STUCK_TIME_LIMIT:
		_handle_stuck()

func _set_next_path_target() -> void:
	target_tile = active_path[active_path_index]
	target_position = _tile_to_pixel_center(target_tile)

func _update_stuck_timer() -> void:
	if global_position.distance_to(previous_position) < STUCK_DISTANCE_EPSILON:
		stuck_timer += get_physics_process_delta_time()
	else:
		stuck_timer = 0.0
		previous_position = global_position

func _handle_stuck() -> void:
	if str(movement.get("collision_behavior", "pause_then_repath")) != "pause_then_repath":
		state = State.BLOCKED
		wait_timer = 0.4
		return

	var fallback: Vector2i = _nearest_valid_tile(current_tile, max(int(movement.get("radius_tiles", 2)), 2))
	if fallback != current_tile and fallback != desired_tile:
		active_path = _find_path(current_tile, fallback)
		active_path_index = 0
		if not active_path.is_empty():
			_set_next_path_target()
			previous_position = global_position
			stuck_timer = 0.0
			state = State.MOVING
			return

	velocity = Vector2.ZERO
	state = State.BLOCKED
	wait_timer = 0.6

func _wait_random() -> void:
	state = State.WAITING
	var wait_min: float = float(movement.get("wait_min", 1.0))
	var wait_max: float = max(float(movement.get("wait_max", 2.0)), wait_min)
	wait_timer = randf_range(wait_min, wait_max)

func _turn_randomly() -> void:
	var directions := ["down", "up", "left", "right"]
	last_facing = directions.pick_random()

func _update_animation() -> void:
	if anim_sprite.sprite_frames == null:
		return

	if velocity.length() > 0.1:
		if abs(velocity.x) >= abs(velocity.y):
			last_facing = "right" if velocity.x > 0.0 else "left"
		else:
			last_facing = "down" if velocity.y > 0.0 else "up"
		var animation_name: String = "walk_%s" % last_facing
		if anim_sprite.animation != animation_name:
			anim_sprite.play(animation_name)
		elif not anim_sprite.is_playing():
			anim_sprite.play()
	else:
		var idle_animation: String = "walk_%s" % last_facing
		if anim_sprite.animation != idle_animation:
			anim_sprite.play(idle_animation)
		anim_sprite.pause()

func _is_valid_target_tile(tile: Vector2i) -> bool:
	if map_tile_size != Vector2i.ZERO:
		if tile.x < 0 or tile.y < 0 or tile.x >= map_tile_size.x or tile.y >= map_tile_size.y:
			return false
	if blocked_tiles.has(_tile_key(tile)):
		return false
	if occupied_tiles.has(_tile_key(tile)) and tile != current_tile:
		return false
	var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
	if not metadata.is_empty() and not bool(metadata.get("npc_walkable", true)):
		return false
	var tags: Array[String] = _tile_tags(tile)
	for tag in _movement_tags("avoid_region_tags"):
		if tags.has(tag):
			return false
	return true

func _pick_best_tile(candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return current_tile

	var best_tile: Vector2i = candidates[0]
	var best_score: float = -INF
	for tile in candidates:
		if not _is_valid_target_tile(tile):
			continue
		var score: float = _score_tile(tile)
		if score > best_score:
			best_score = score
			best_tile = tile
	return best_tile

func _score_tile(tile: Vector2i) -> float:
	var score: float = randf_range(0.0, 0.25)
	var tags: Array[String] = _tile_tags(tile)
	var preferred_tags: Array[String] = _movement_tags("movement_region_tags")
	for tag in preferred_tags:
		if tags.has(tag):
			score += 6.0

	if preferred_tags.is_empty() and tags.has("ambient_walkable"):
		score += 1.0
	if tags.has("near_objects"):
		score += 1.5
	if tags.has("edge") and not _tile_tags(anchor_tile).has("edge"):
		score -= 2.0
	if tags.has("object_footprint"):
		score -= 3.0

	var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
	score -= float(metadata.get("near_blocker_count", 0)) * 0.35
	score -= Vector2(tile).distance_to(Vector2(anchor_tile)) * 0.3
	score -= Vector2(tile).distance_to(Vector2(current_tile)) * 0.05
	return score

func _nearest_valid_tile(center_tile: Vector2i, radius: int) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(center_tile.y - radius, center_tile.y + radius + 1):
		for x in range(center_tile.x - radius, center_tile.x + radius + 1):
			var tile := Vector2i(x, y)
			if _is_valid_target_tile(tile):
				candidates.append(tile)
	return _pick_best_tile(candidates)

func _find_path(start_tile: Vector2i, end_tile: Vector2i) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if start_tile == end_tile:
		return empty_path
	if not _is_valid_target_tile(end_tile):
		return empty_path

	var open: Array[Vector2i] = [start_tile]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {_tile_key(start_tile): 0.0}
	var f_score: Dictionary = {_tile_key(start_tile): _tile_distance(start_tile, end_tile)}
	var visited_count: int = 0

	while not open.is_empty() and visited_count < MAX_PATH_SEARCH_NODES:
		visited_count += 1
		var current: Vector2i = _pop_lowest_score_tile(open, f_score)
		if current == end_tile:
			return _reconstruct_path(came_from, current)

		for neighbor in _path_neighbors(current):
			var neighbor_key: String = _tile_key(neighbor)
			var tentative_g: float = float(g_score.get(_tile_key(current), INF)) + _movement_cost(neighbor)
			if tentative_g >= float(g_score.get(neighbor_key, INF)):
				continue
			came_from[neighbor_key] = current
			g_score[neighbor_key] = tentative_g
			f_score[neighbor_key] = tentative_g + _tile_distance(neighbor, end_tile)
			if not open.has(neighbor):
				open.append(neighbor)

	return empty_path

func _path_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for direction in directions:
		var neighbor: Vector2i = tile + direction
		if neighbor == current_tile or _is_valid_target_tile(neighbor):
			neighbors.append(neighbor)
	return neighbors

func _pop_lowest_score_tile(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_index: int = 0
	var best_score: float = INF
	for i in range(open.size()):
		var score: float = float(f_score.get(_tile_key(open[i]), INF))
		if score < best_score:
			best_score = score
			best_index = i
	return open.pop_at(best_index)

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(_tile_key(current)):
		current = came_from[_tile_key(current)] as Vector2i
		path.push_front(current)
	if not path.is_empty() and path[0] == current_tile:
		path.remove_at(0)
	return path

func _tile_distance(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))

func _movement_cost(tile: Vector2i) -> float:
	var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
	var cost: float = float(metadata.get("movement_cost", 1.0))
	cost += float(metadata.get("near_blocker_count", 0)) * 0.25
	if _tile_tags(tile).has("edge") and not _tile_tags(anchor_tile).has("edge"):
		cost += 1.0
	return max(cost, 0.1)

func _movement_tags(key: String) -> Array[String]:
	var tags: Array[String] = []
	var raw_tags: Variant = movement.get(key, npc_data.get(key, []))
	if raw_tags is Array:
		for raw_tag in raw_tags:
			tags.append(str(raw_tag))
	return tags

func _tile_tags(tile: Vector2i) -> Array[String]:
	var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
	var tags: Array[String] = []
	var raw_tags: Variant = metadata.get("region_tags", [])
	if raw_tags is Array:
		for raw_tag in raw_tags:
			tags.append(str(raw_tag))
	return tags

func _read_animation_cells(raw_cells: Variant, direction: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if raw_cells is Array:
		for raw_cell in raw_cells:
			if not (raw_cell is Dictionary):
				cells.clear()
				break
			var cell: Vector2i = _normalize_sprite_cell(raw_cell as Dictionary)
			if cell == Vector2i(-1, -1):
				cells.clear()
				break
			cells.append(cell)

	if cells.is_empty():
		return _default_animation_cells(direction)
	return cells

func _normalize_sprite_cell(raw_cell: Dictionary) -> Vector2i:
	var grid: Vector2i = GameManager.CHARACTER_SPRITE_GRID
	var row: int = int(raw_cell.get("row", 0))
	var col: int = int(raw_cell.get("col", 0))
	if row >= 1 and row <= grid.y:
		row -= 1
	if col >= 1 and col <= grid.x and not raw_cell.get("col", 0) == 0:
		col -= 1
	if row < 0 or col < 0 or row >= grid.y or col >= grid.x:
		return Vector2i(-1, -1)
	return Vector2i(col, row)

func _default_animation_cells(direction: String) -> Array[Vector2i]:
	var row_by_direction := {
		"down": 0,
		"up": 1,
		"right": 2,
		"left": 3,
	}
	var row: int = int(row_by_direction.get(direction, 0))
	var cells: Array[Vector2i] = []
	for col in GameManager.CHARACTER_SPRITE_GRID.x:
		cells.append(Vector2i(col, row))
	return cells

func _read_path_tiles(raw_path: Variant) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not (raw_path is Array):
		return tiles
	for raw_tile in raw_path:
		if raw_tile is Dictionary:
			tiles.append(_read_tile_position(raw_tile as Dictionary))
	return tiles

func _read_tile_position(data: Dictionary) -> Vector2i:
	var position_tile: Dictionary = data.get("position_tile", {}) as Dictionary
	if not position_tile.is_empty():
		return Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))

	if data.has("x") and data.has("y"):
		return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))

	var placement: Dictionary = data.get("placement", {}) as Dictionary
	var placed_cell: Dictionary = placement.get("placed_cell", {}) as Dictionary
	if not placed_cell.is_empty():
		return Vector2i(int(placed_cell.get("x", 0)), int(placed_cell.get("y", 0)))

	return Vector2i.ZERO

func _tile_to_pixel_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)

func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]
