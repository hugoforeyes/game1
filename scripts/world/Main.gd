extends Node2D

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")

@onready var background: Sprite2D = $World/Background
@onready var player: CharacterBody2D = $World/CharacterLayer/GeneratedCharacters/Player
@onready var generated_props: Node2D = $World/GeneratedProps
@onready var generated_characters: Node2D = $World/CharacterLayer/GeneratedCharacters
@onready var generated_prop_tops: Node2D = $World/GeneratedPropTops
@onready var generated_collisions: Node2D = $World/GeneratedCollisions
@onready var lighting_system: Node = $LightingSystem

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
	var solid_instances: Array[Dictionary] = []
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue

		var instance_id: String = str(instance.get("id", ""))
		var definition: Dictionary = definitions.get(instance_id, {}) as Dictionary
		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		var tile_position: Vector2i = Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))

		_create_instance_sprite(definition, tile_position)

		if bool(definition.get("solid", false)):
			# Use the full composite sprite for hull tracing; base_file is only the floor layer
			var hull_file: String = str(definition.get("file", definition.get("base_file", "")))
			solid_instances.append({
				"definition_id": instance_id,
				"position_tile": position_tile,
				"size_tiles": definition.get("size_tiles", {}),
				"sprite_file": hull_file,
			})

	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var npc_occupied_tiles: Dictionary = {}
	var tile_context: Dictionary = _build_tile_context(package_data, background.texture)
	for npc in characters.get("npcs", []):
		if npc is Dictionary:
			var npc_data: Dictionary = npc as Dictionary
			_spawn_npc(npc_data, tile_context, npc_occupied_tiles)
			npc_occupied_tiles[_tile_key(_read_tile_position(npc_data))] = true

	var occupied_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	for key in occupied_tiles.keys():
		var tile: Vector2i = _tile_from_key(str(key))
		_create_collision_tile(tile)

	_create_map_boundaries(GameManager.get_map_pixel_size(package_data, background.texture))

	var spawn_tile: Vector2i = _find_player_spawn_tile(package_data)
	player.global_position = _tile_to_pixel_center(spawn_tile)
	player.z_index = 0
	_apply_background_limits(background.texture)

	var map_pixel_size: Vector2 = GameManager.get_map_pixel_size(package_data, background.texture)
	lighting_system.initialize($World, package_data, map_pixel_size, generated_props, solid_instances)

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

func _spawn_npc(npc_data: Dictionary, tile_context: Dictionary, occupied_tiles: Dictionary) -> void:
	var npc: CharacterBody2D = NPC_SCENE.instantiate() as CharacterBody2D
	generated_characters.add_child(npc)
	var world_context := {
		"map_tile_size": tile_context.get("map_tile_size", Vector2i.ZERO),
		"blocked_tiles": tile_context.get("blocked_tiles", {}),
		"occupied_tiles": occupied_tiles,
		"tile_metadata": tile_context.get("tile_metadata", {}),
	}
	npc.setup(npc_data, world_context)

func _build_tile_context(package_data: Dictionary, background_texture: Texture2D) -> Dictionary:
	var map_tile_size: Vector2i = GameManager.get_map_tile_size(package_data, background_texture)
	var blocked_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	var tile_metadata: Dictionary = {}

	for y in range(map_tile_size.y):
		for x in range(map_tile_size.x):
			var tile := Vector2i(x, y)
			var tags: Array[String] = ["ambient_walkable"]
			if x <= 1 or y <= 1 or x >= map_tile_size.x - 2 or y >= map_tile_size.y - 2:
				tags.append("edge")
			tile_metadata[_tile_key(tile)] = {
				"npc_walkable": not blocked_tiles.has(_tile_key(tile)),
				"region_tags": tags,
				"movement_cost": 1.0,
				"near_blocker_count": 0,
			}

	_apply_object_tile_metadata(package_data, tile_metadata)
	_apply_near_object_metadata(map_tile_size, tile_metadata)
	return {
		"map_tile_size": map_tile_size,
		"blocked_tiles": blocked_tiles,
		"tile_metadata": tile_metadata,
	}

func _apply_object_tile_metadata(package_data: Dictionary, tile_metadata: Dictionary) -> void:
	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var definition: Dictionary = definitions.get(str((instance as Dictionary).get("id", "")), {}) as Dictionary
		var position_tile: Dictionary = (instance as Dictionary).get("position_tile", {}) as Dictionary
		var base_tile := Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
		var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
		var width: int = max(int(size_tiles.get("w", 1)), 1)
		var height: int = max(int(size_tiles.get("h", 1)), 1)
		for y in range(height):
			for x in range(width):
				var tile: Vector2i = base_tile + Vector2i(x, y)
				var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
				if metadata.is_empty():
					continue
				var tags: Array[String] = _metadata_tags(metadata)
				if not tags.has("object_footprint"):
					tags.append("object_footprint")
				metadata["region_tags"] = tags
				tile_metadata[_tile_key(tile)] = metadata

func _apply_near_object_metadata(map_tile_size: Vector2i, tile_metadata: Dictionary) -> void:
	var directions := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
	]
	for y in range(map_tile_size.y):
		for x in range(map_tile_size.x):
			var tile := Vector2i(x, y)
			var metadata: Dictionary = tile_metadata.get(_tile_key(tile), {}) as Dictionary
			if metadata.is_empty():
				continue
			var near_blocker_count: int = 0
			var near_object: bool = false
			for direction in directions:
				var neighbor: Vector2i = tile + direction
				var neighbor_metadata: Dictionary = tile_metadata.get(_tile_key(neighbor), {}) as Dictionary
				if neighbor_metadata.is_empty():
					continue
				if not bool(neighbor_metadata.get("npc_walkable", false)):
					near_blocker_count += 1
				if _metadata_tags(neighbor_metadata).has("object_footprint"):
					near_object = true
			var tags: Array[String] = _metadata_tags(metadata)
			if near_object and not tags.has("near_objects"):
				tags.append("near_objects")
			metadata["region_tags"] = tags
			metadata["near_blocker_count"] = near_blocker_count
			tile_metadata[_tile_key(tile)] = metadata

func _create_collision_tile(tile: Vector2i) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = _tile_to_pixel_center(tile)

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2.ONE * GameManager.TILE_SIZE

	var collision_shape: CollisionShape2D = CollisionShape2D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)

	generated_collisions.add_child(body)

func _create_map_boundaries(map_pixel_size: Vector2) -> void:
	if map_pixel_size == Vector2.ZERO:
		return

	var thickness: float = GameManager.TILE_SIZE
	_create_collision_rect(Vector2(-thickness * 0.5, map_pixel_size.y * 0.5), Vector2(thickness, map_pixel_size.y + thickness * 2.0))
	_create_collision_rect(Vector2(map_pixel_size.x + thickness * 0.5, map_pixel_size.y * 0.5), Vector2(thickness, map_pixel_size.y + thickness * 2.0))
	_create_collision_rect(Vector2(map_pixel_size.x * 0.5, -thickness * 0.5), Vector2(map_pixel_size.x + thickness * 2.0, thickness))
	_create_collision_rect(Vector2(map_pixel_size.x * 0.5, map_pixel_size.y + thickness * 0.5), Vector2(map_pixel_size.x + thickness * 2.0, thickness))

func _create_collision_rect(position: Vector2, size: Vector2) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.position = position

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size

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

func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]

func _metadata_tags(metadata: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	var raw_tags: Variant = metadata.get("region_tags", [])
	if raw_tags is Array:
		for raw_tag in raw_tags:
			tags.append(str(raw_tag))
	return tags

func _clear_generated_content() -> void:
	lighting_system.cleanup()
	for child in generated_props.get_children():
		child.queue_free()
	for child in generated_characters.get_children():
		if child != player:
			child.queue_free()
	for child in generated_prop_tops.get_children():
		child.queue_free()
	for child in generated_collisions.get_children():
		child.queue_free()
