extends Node

const TILE_SIZE := 36
const CHARACTER_SHEET_SIZE := Vector2i(144, 144)
const CHARACTER_SPRITE_GRID := Vector2i(4, 4)
const CHARACTER_FRAME_SIZE := TILE_SIZE
const DEFAULT_PLAYER_SPRITE_PATH := "res://assets/sprites/player/godot_sheet.png"
const IMPORT_ROOT_DIR := "user://imports"
const SCENE_IMPORT_DIR := "user://imports/scene_package"
const PLAYER_IMPORT_DIR := "user://imports/player"
const WORLD_SCENE_PATH := "res://scenes/world/Main.tscn"

var player_data := {
	"health": 100,
	"max_health": 100,
	"level": 1,
	"experience": 0,
}

var imported_scene_package: Dictionary = {}
var imported_scene_root_dir: String = ""
var imported_player_sprite_path: String = ""

func reset_runtime_imports(clear_files := false) -> void:
	imported_scene_package.clear()
	imported_scene_root_dir = ""
	imported_player_sprite_path = ""
	if clear_files:
		_remove_tree(IMPORT_ROOT_DIR)

func has_scene_package() -> bool:
	return not imported_scene_package.is_empty() and not imported_scene_root_dir.is_empty()

func get_scene_package() -> Dictionary:
	return imported_scene_package.duplicate(true)

func get_scene_asset_path(relative_path: String) -> String:
	if imported_scene_root_dir.is_empty() or relative_path.is_empty():
		return ""
	return imported_scene_root_dir.path_join(relative_path)

func get_player_sprite_path() -> String:
	return imported_player_sprite_path if not imported_player_sprite_path.is_empty() else DEFAULT_PLAYER_SPRITE_PATH

func import_scene_package_zip(zip_path: String) -> Error:
	_remove_tree(SCENE_IMPORT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_IMPORT_DIR))

	var zip_reader: ZIPReader = ZIPReader.new()
	var open_error: Error = zip_reader.open(zip_path)
	if open_error != OK:
		return open_error

	var scene_json_internal_path: String = ""
	for internal_path in zip_reader.get_files():
		if internal_path.get_file() == "scene_package.json":
			scene_json_internal_path = internal_path
			break

	if scene_json_internal_path.is_empty():
		zip_reader.close()
		return ERR_FILE_NOT_FOUND

	for internal_path in zip_reader.get_files():
		if internal_path.ends_with("/"):
			continue
		var bytes: PackedByteArray = zip_reader.read_file(internal_path)
		var output_path: String = SCENE_IMPORT_DIR.path_join(internal_path)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
		var output_file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if output_file == null:
			zip_reader.close()
			return FileAccess.get_open_error()
		output_file.store_buffer(bytes)

	zip_reader.close()

	var scene_json_path: String = SCENE_IMPORT_DIR.path_join(scene_json_internal_path)
	var json_file: FileAccess = FileAccess.open(scene_json_path, FileAccess.READ)
	if json_file == null:
		return FileAccess.get_open_error()

	var scene_json_text: String = json_file.get_as_text()
	var parsed_data: Variant = JSON.parse_string(scene_json_text)
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR

	var scene_root_dir: String = scene_json_path.get_base_dir()
	var load_error: Error = _apply_scene_package(parsed_data as Dictionary, scene_root_dir)
	if load_error != OK:
		return load_error
	return OK

func load_scene_package_file(scene_json_path: String) -> Error:
	var json_file: FileAccess = FileAccess.open(scene_json_path, FileAccess.READ)
	if json_file == null:
		return FileAccess.get_open_error()

	var parsed_data: Variant = JSON.parse_string(json_file.get_as_text())
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR

	return _apply_scene_package(parsed_data as Dictionary, scene_json_path.get_base_dir())

func import_player_sprite(sprite_path: String) -> Error:
	_remove_tree(PLAYER_IMPORT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAYER_IMPORT_DIR))

	var extension: String = sprite_path.get_extension().to_lower()
	if extension.is_empty():
		extension = "png"

	var source_file: FileAccess = FileAccess.open(sprite_path, FileAccess.READ)
	if source_file == null:
		return FileAccess.get_open_error()

	var source_image: Image = Image.new()
	var image_error: Error = source_image.load(sprite_path)
	if image_error != OK:
		return image_error
	if source_image.get_size() != CHARACTER_SHEET_SIZE:
		return ERR_INVALID_DATA

	var destination_path: String = PLAYER_IMPORT_DIR.path_join("player_sprite.%s" % extension)
	var destination_file: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		return FileAccess.get_open_error()

	destination_file.store_buffer(source_file.get_buffer(source_file.get_length()))
	imported_player_sprite_path = destination_path
	return OK

func load_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null

	if texture_path.begins_with("res://"):
		return load(texture_path) as Texture2D

	var image: Image = Image.new()
	var error: Error = image.load(texture_path)
	if error != OK:
		return null

	return ImageTexture.create_from_image(image)

func get_map_tile_size(package_data: Dictionary, background_texture: Texture2D) -> Vector2i:
	var max_tile := Vector2i.ZERO
	for cell in package_data.get("background_collision", []):
		if cell is Array and cell.size() >= 2:
			max_tile.x = max(max_tile.x, int(cell[0]))
			max_tile.y = max(max_tile.y, int(cell[1]))

	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var instance_id: String = str(instance.get("id", ""))
		var definition: Dictionary = definitions.get(instance_id, {}) as Dictionary
		var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		max_tile.x = max(max_tile.x, int(position_tile.get("x", 0)) + max(int(size_tiles.get("w", 1)) - 1, 0))
		max_tile.y = max(max_tile.y, int(position_tile.get("y", 0)) + max(int(size_tiles.get("h", 1)) - 1, 0))

	if background_texture != null:
		max_tile.x = max(max_tile.x, int(round(float(background_texture.get_width()) / TILE_SIZE)) - 1)
		max_tile.y = max(max_tile.y, int(round(float(background_texture.get_height()) / TILE_SIZE)) - 1)

	return max_tile + Vector2i.ONE

func get_map_pixel_size(package_data: Dictionary, background_texture: Texture2D) -> Vector2:
	var tile_size: Vector2i = get_map_tile_size(package_data, background_texture)
	if background_texture != null:
		return Vector2(background_texture.get_width(), background_texture.get_height())
	return Vector2(tile_size.x * TILE_SIZE, tile_size.y * TILE_SIZE)

func find_spawn_tile(package_data: Dictionary, background_texture: Texture2D) -> Vector2i:
	var blocked_tiles: Dictionary = get_blocked_tiles(package_data)
	var map_tile_size: Vector2i = get_map_tile_size(package_data, background_texture)
	var center: Vector2 = Vector2(map_tile_size) / 2.0
	var best_tile: Vector2i = Vector2i.ZERO
	var best_score: float = INF

	for y in range(map_tile_size.y):
		for x in range(map_tile_size.x):
			var candidate: Vector2i = Vector2i(x, y)
			if _blocked_tiles_has(blocked_tiles, candidate):
				continue

			var score: float = center.distance_squared_to(Vector2(candidate) + Vector2(0.5, 0.5))
			if score < best_score:
				best_score = score
				best_tile = candidate

	return best_tile

func get_blocked_tiles(package_data: Dictionary) -> Dictionary:
	var blocked_tiles := {}
	for cell in package_data.get("background_collision", []):
		if cell is Array and cell.size() >= 2:
			blocked_tiles[_tile_key(Vector2i(int(cell[0]), int(cell[1])))] = true

	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var definition: Dictionary = definitions.get(str(instance.get("id", "")), {}) as Dictionary
		if not bool(definition.get("solid", false)):
			continue

		var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
		var base_tile: Vector2i = Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
		for collision_cell in definition.get("collision", []):
			if collision_cell is Array and collision_cell.size() >= 2:
				var tile: Vector2i = base_tile + Vector2i(int(collision_cell[0]), int(collision_cell[1]))
				blocked_tiles[_tile_key(tile)] = true

	return blocked_tiles

func get_character_sprite_grid(texture: Texture2D, texture_path := "") -> Vector2i:
	if texture == null:
		return CHARACTER_SPRITE_GRID
	if Vector2i(texture.get_width(), texture.get_height()) != CHARACTER_SHEET_SIZE:
		push_warning("Character spritesheet should be 144x144 px: %s" % texture_path)
	return CHARACTER_SPRITE_GRID

func infer_player_sprite_grid(texture: Texture2D, texture_path: String) -> Vector2i:
	return get_character_sprite_grid(texture, texture_path)

func _definitions_by_id(package_data: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	for definition in package_data.get("definitions", []):
		if definition is Dictionary:
			definitions[str(definition.get("id", ""))] = definition
	return definitions

func _apply_scene_package(package_data: Dictionary, scene_root_dir: String) -> Error:
	if not package_data.has("background_image"):
		return ERR_INVALID_DATA
	if not package_data.has("definitions"):
		return ERR_INVALID_DATA
	if not package_data.has("instances"):
		return ERR_INVALID_DATA

	var background_path: String = scene_root_dir.path_join(str(package_data.get("background_image", "")))
	if not FileAccess.file_exists(background_path):
		return ERR_FILE_NOT_FOUND

	for definition in package_data.get("definitions", []):
		if not (definition is Dictionary):
			continue
		var file_name: String = str(definition.get("file", ""))
		if file_name.is_empty():
			return ERR_INVALID_DATA
		if not FileAccess.file_exists(scene_root_dir.path_join(file_name)):
			return ERR_FILE_NOT_FOUND

	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var main_character: Dictionary = characters.get("main_character", {}) as Dictionary
	var main_sprite_file: String = str(main_character.get("sprite_sheet_file", ""))
	if not main_sprite_file.is_empty():
		var main_sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(main_sprite_file))
		if main_sprite_error != OK:
			return main_sprite_error

	for npc in characters.get("npcs", []):
		if not (npc is Dictionary):
			continue
		var sprite_file: String = str((npc as Dictionary).get("sprite_sheet_file", ""))
		if sprite_file.is_empty():
			continue
		var sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(sprite_file))
		if sprite_error != OK:
			return sprite_error

	imported_scene_package = package_data
	imported_scene_root_dir = scene_root_dir
	if not main_sprite_file.is_empty():
		imported_player_sprite_path = scene_root_dir.path_join(main_sprite_file)
	return OK

func _validate_character_sprite_file(sprite_path: String) -> Error:
	if not FileAccess.file_exists(sprite_path):
		return ERR_FILE_NOT_FOUND

	if sprite_path.begins_with("res://"):
		var texture: Texture2D = load(sprite_path) as Texture2D
		if texture == null:
			return ERR_FILE_CANT_OPEN
		if Vector2i(texture.get_width(), texture.get_height()) != CHARACTER_SHEET_SIZE:
			return ERR_INVALID_DATA
		return OK

	var image: Image = Image.new()
	var image_error: Error = image.load(sprite_path)
	if image_error != OK:
		return image_error
	if image.get_size() != CHARACTER_SHEET_SIZE:
		return ERR_INVALID_DATA
	return OK

func _blocked_tiles_has(blocked_tiles: Dictionary, tile: Vector2i) -> bool:
	return blocked_tiles.has(_tile_key(tile))

func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]

func _remove_tree(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return

	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry == "." or entry == "..":
			entry = directory.get_next()
			continue
		var child_path: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child_path)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
		entry = directory.get_next()
	directory.list_dir_end()

	DirAccess.remove_absolute(absolute_path)
