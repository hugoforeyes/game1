extends Node2D

@onready var background: Sprite2D = $World/Background
@onready var player: CharacterBody2D = $World/Player
@onready var generated_props: Node2D = $World/GeneratedProps
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

	var occupied_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	for key in occupied_tiles.keys():
		var tile: Vector2i = _tile_from_key(str(key))
		_create_collision_tile(tile)

	var spawn_tile: Vector2i = GameManager.find_spawn_tile(package_data, background.texture)
	player.global_position = _tile_to_pixel_center(spawn_tile)
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

	var texture_path: String = GameManager.get_scene_asset_path(str(definition.get("file", "")))
	var texture: Texture2D = GameManager.load_texture(texture_path)
	if texture == null:
		return

	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(tile_position) * GameManager.TILE_SIZE
	var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
	var footprint_height: int = max(int(size_tiles.get("h", 1)), 1)
	sprite.z_index = (tile_position.y + footprint_height) * GameManager.TILE_SIZE
	generated_props.add_child(sprite)

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

func _tile_from_key(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))

func _clear_generated_content() -> void:
	for child in generated_props.get_children():
		child.queue_free()
	for child in generated_collisions.get_children():
		child.queue_free()
