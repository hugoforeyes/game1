extends Node2D

@onready var background: Sprite2D = $World/Background
@onready var player: CharacterBody2D = $World/CharacterLayer/GeneratedCharacters/Player
@onready var generated_props: Node2D = $World/GeneratedProps
@onready var generated_characters: Node2D = $World/CharacterLayer/GeneratedCharacters
@onready var generated_prop_tops: Node2D = $World/GeneratedPropTops
@onready var generated_collisions: Node2D = $World/GeneratedCollisions

func _ready() -> void:
	if GameManager.has_scene_package():
		_build_imported_world()
	else:
		_apply_background_limits(background.texture)

func _build_imported_world() -> void:
	_clear_generated_content()

	var package_data: Dictionary = GameManager.get_scene_package()
	var background_path: String = GameManager.get_scene_asset_path(str(package_data.get("background_image", "")))
	var background_texture: Texture2D = GameManager.load_texture(background_path)
	if background_texture != null:
		background.texture = background_texture

	if background.texture != null:
		background.position = background.texture.get_size() / 2.0

	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue

		var instance_id: String = str(instance.get("id", ""))
		var definition: Dictionary = definitions.get(instance_id, {}) as Dictionary
		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		var tile_position: Vector2i = Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))

		_create_instance_sprite(definition, tile_position)

	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	for npc in characters.get("npcs", []):
		if npc is Dictionary:
			_create_character_sprite(npc as Dictionary)

	var occupied_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	for key in occupied_tiles.keys():
		var tile: Vector2i = _tile_from_key(str(key))
		_create_collision_tile(tile)

	var spawn_tile: Vector2i = _find_player_spawn_tile(package_data)
	player.global_position = _tile_to_pixel_center(spawn_tile)
	player.z_index = 0
	_apply_background_limits(background.texture)

func _apply_background_limits(texture: Texture2D) -> void:
	if texture == null:
		return

	background.position = texture.get_size() / 2.0
	var player_camera: Variant = player.get("camera")
	if player_camera is Camera2D:
		player_camera.limit_left = 0
		player_camera.limit_top = 0
		player_camera.limit_right = texture.get_width()
		player_camera.limit_bottom = texture.get_height()

func _create_instance_sprite(definition: Dictionary, tile_position: Vector2i) -> void:
	if definition.is_empty():
		return

	var base_file: String = str(definition.get("base_file", ""))
	var top_file: String = str(definition.get("top_file", ""))
	if base_file.is_empty() and top_file.is_empty():
		base_file = str(definition.get("file", ""))

	_create_layered_prop_sprite(base_file, tile_position, generated_props)
	_create_layered_prop_sprite(top_file, tile_position, generated_prop_tops)

func _create_layered_prop_sprite(file_name: String, tile_position: Vector2i, parent: Node2D) -> void:
	if file_name.is_empty() or file_name == "<null>":
		return

	var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(file_name))
	if texture == null:
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(tile_position) * GameManager.TILE_SIZE
	sprite.z_index = 0
	parent.add_child(sprite)

func _create_character_sprite(character_data: Dictionary) -> void:
	var sprite_sheet_file: String = str(character_data.get("sprite_sheet_file", ""))
	if sprite_sheet_file.is_empty():
		return

	var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(sprite_sheet_file))
	if texture == null:
		return

	var tile_position: Vector2i = _read_tile_position(character_data)
	var grid: Vector2i = GameManager.get_character_sprite_grid(texture, GameManager.get_scene_asset_path(sprite_sheet_file))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = max(grid.x, 1)
	sprite.vframes = max(grid.y, 1)
	sprite.frame = 0
	sprite.position = _tile_to_pixel_center(tile_position)
	sprite.z_index = 0
	generated_characters.add_child(sprite)

func _create_collision_tile(tile: Vector2i) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = _tile_to_pixel_center(tile)

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2.ONE * GameManager.TILE_SIZE

	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)

	generated_collisions.add_child(body)

func _tile_to_pixel_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)

func _definitions_by_id(package_data: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	for definition in package_data.get("definitions", []):
		if definition is Dictionary:
			definitions[str(definition.get("id", ""))] = definition
	return definitions

func _find_player_spawn_tile(package_data: Dictionary) -> Vector2i:
	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var main_character: Dictionary = characters.get("main_character", {}) as Dictionary
	var authored_tile: Vector2i = _read_tile_position(main_character)
	if authored_tile != Vector2i.ZERO:
		return authored_tile
	return GameManager.find_spawn_tile(package_data, background.texture)

func _read_tile_position(data: Dictionary) -> Vector2i:
	var position_tile: Dictionary = data.get("position_tile", {}) as Dictionary
	if not position_tile.is_empty():
		return Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))

	var placement: Dictionary = data.get("placement", {}) as Dictionary
	var placed_cell: Dictionary = placement.get("placed_cell", {}) as Dictionary
	if not placed_cell.is_empty():
		return Vector2i(int(placed_cell.get("x", 0)), int(placed_cell.get("y", 0)))

	return Vector2i.ZERO

func _tile_from_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

func _clear_generated_content() -> void:
	for child in generated_props.get_children():
		child.queue_free()
	for child in generated_characters.get_children():
		if child != player:
			child.queue_free()
	for child in generated_prop_tops.get_children():
		child.queue_free()
	for child in generated_collisions.get_children():
		child.queue_free()
