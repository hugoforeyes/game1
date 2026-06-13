extends Node

const TILE_SIZE := 72  # world pixel density: 72 px/tile (Option C)
const CHARACTER_SHEET_SIZE := Vector2i(288, 288)
const CHARACTER_SPRITE_GRID := Vector2i(4, 4)
const CHARACTER_FRAME_SIZE := TILE_SIZE
const DEFAULT_PLAYER_SPRITE_PATH := "res://assets/sprites/player/godot_sheet.png"
const IMPORT_ROOT_DIR := "user://imports"
const SCENE_IMPORT_DIR := "user://imports/scene_package"
const PLAYER_IMPORT_DIR := "user://imports/player"
const WORLD_SCENE_PATH := "res://scenes/world/Main.tscn"
const API_BASE_URL := "http://127.0.0.1:5001"

# On web exports the page is served with a same-origin /api proxy to the
# backend (see run_game.sh). HTTPRequest needs absolute URLs, so use the
# page origin (e.g. http://localhost:8000) instead of 127.0.0.1:5001.
func api_base_url() -> String:
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and not str(origin).is_empty():
			return str(origin)
	return API_BASE_URL

var player_data := {
	"health": 100,
	"max_health": 100,
	"level": 1,
	"experience": 0,
}

# ── combat / progression ──────────────────────────────────────────────────────

signal player_stats_changed

var player_level: int = 1
var player_xp: int = 0
var player_hp: int = -1  # -1 = full (computed lazily from level)
var defeated_enemy_ids: Dictionary = {}
var spared_enemy_ids: Dictionary = {}

func player_battle_stats() -> Dictionary:
	return {
		"max_hp": 60 + 20 * player_level,
		"attack": 9 + 3 * player_level,
		"defense": 3 + 2 * player_level,
		"speed": 8 + player_level,
		"sp_max": 3 + int(player_level / 2.0),
	}

func get_player_hp() -> int:
	var max_hp: int = int(player_battle_stats()["max_hp"])
	if player_hp < 0 or player_hp > max_hp:
		player_hp = max_hp
	return player_hp

func set_player_hp(value: int) -> void:
	player_hp = clampi(value, 0, int(player_battle_stats()["max_hp"]))
	player_stats_changed.emit()

func xp_to_next_level() -> int:
	return 30 * player_level

func gain_xp(amount: int) -> int:
	var levels_gained := 0
	player_xp += max(amount, 0)
	while player_xp >= xp_to_next_level():
		player_xp -= xp_to_next_level()
		player_level += 1
		levels_gained += 1
		player_hp = -1  # level up fully heals
	player_stats_changed.emit()
	return levels_gained

func lose_xp_on_defeat() -> void:
	player_xp = int(player_xp * 0.75)
	player_hp = -1
	player_stats_changed.emit()

func player_skills() -> Array[Dictionary]:
	var skills: Array[Dictionary] = [
		{"id": "strike", "name": "Strike", "power": 1.0, "sp_cost": 0, "unlock_level": 1},
		{"id": "power_strike", "name": "Power Strike", "power": 1.6, "sp_cost": 1, "unlock_level": 1},
		{"id": "focus", "name": "Focus", "power": 0.0, "sp_cost": 1, "unlock_level": 2, "effect": "focus"},
		{"id": "crush", "name": "Crushing Blow", "power": 2.2, "sp_cost": 2, "unlock_level": 3},
	]
	var unlocked: Array[Dictionary] = []
	for skill in skills:
		if player_level >= int(skill["unlock_level"]):
			unlocked.append(skill)
	return unlocked

func mark_enemy_defeated(enemy_id: String) -> void:
	defeated_enemy_ids[enemy_id] = true

func mark_enemy_spared(enemy_id: String) -> void:
	spared_enemy_ids[enemy_id] = true

func reset_combat_progress() -> void:
	player_level = 1
	player_xp = 0
	player_hp = -1
	defeated_enemy_ids.clear()
	spared_enemy_ids.clear()

func get_enemy_roster() -> Array:
	var enemies: Dictionary = imported_scene_package.get("enemies", {}) as Dictionary
	var roster: Array = enemies.get("roster", []) as Array
	var valid: Array = []
	for item in roster:
		if item is Dictionary and not str((item as Dictionary).get("id", "")).is_empty():
			valid.append(item)
	return valid

var imported_scene_package: Dictionary = {}
var imported_scene_root_dir: String = ""
var imported_player_sprite_path: String = ""
var imported_scene_context: Dictionary = {}
var ui_blocking_input: bool = false

func reset_runtime_imports(clear_files := false) -> void:
	reset_combat_progress()
	imported_scene_package.clear()
	imported_scene_root_dir = ""
	imported_player_sprite_path = ""
	imported_scene_context.clear()
	if clear_files:
		_remove_tree(IMPORT_ROOT_DIR)

func has_scene_package() -> bool:
	return not imported_scene_package.is_empty() and not imported_scene_root_dir.is_empty()

func get_scene_package() -> Dictionary:
	return imported_scene_package.duplicate(true)

func get_scene_context() -> Dictionary:
	return imported_scene_context.duplicate(true)

func get_scene_asset_path(relative_path: String) -> String:
	if imported_scene_root_dir.is_empty() or relative_path.is_empty():
		return ""
	return imported_scene_root_dir.path_join(relative_path)

func get_player_sprite_path() -> String:
	return imported_player_sprite_path if not imported_player_sprite_path.is_empty() else DEFAULT_PLAYER_SPRITE_PATH

func import_scene_package_zip(zip_path: String) -> Error:
	print("[GameManager] import_scene_package_zip path='%s'" % zip_path)
	_remove_tree(SCENE_IMPORT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_IMPORT_DIR))

	var zip_reader: ZIPReader = ZIPReader.new()
	var open_error: Error = zip_reader.open(zip_path)
	if open_error != OK:
		print("[GameManager] zip open failed err=%d" % open_error)
		return open_error

	var scene_json_internal_path: String = ""
	var zip_files: PackedStringArray = zip_reader.get_files()
	print("[GameManager] zip file count=%d" % zip_files.size())
	for internal_path in zip_files:
		if internal_path.get_file() == "scene_package.json":
			scene_json_internal_path = internal_path
			break

	if scene_json_internal_path.is_empty():
		zip_reader.close()
		print("[GameManager] scene_package.json missing in zip")
		return ERR_FILE_NOT_FOUND

	for internal_path in zip_files:
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
		print("[GameManager] apply scene package failed err=%d" % load_error)
		return load_error
	print("[GameManager] import complete root='%s'" % imported_scene_root_dir)
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
		print("[GameManager] load_texture FAILED path='%s' err=%d" % [texture_path, error])
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
	var characters_for_log: Dictionary = package_data.get("characters", {}) as Dictionary
	var npcs_for_log: Array = characters_for_log.get("npcs", []) as Array
	print("[GameManager] apply_scene_package root='%s' definitions=%d instances=%d npcs=%d" % [
		scene_root_dir,
		(package_data.get("definitions", []) as Array).size(),
		(package_data.get("instances", []) as Array).size(),
		npcs_for_log.size(),
	])
	if not package_data.has("background_image"):
		print("[GameManager] package missing background_image")
		return ERR_INVALID_DATA
	if not package_data.has("definitions"):
		print("[GameManager] package missing definitions")
		return ERR_INVALID_DATA
	if not package_data.has("instances"):
		print("[GameManager] package missing instances")
		return ERR_INVALID_DATA

	var background_path: String = scene_root_dir.path_join(str(package_data.get("background_image", "")))
	if not FileAccess.file_exists(background_path):
		print("[GameManager] background missing path='%s'" % background_path)
		return ERR_FILE_NOT_FOUND

	for definition in package_data.get("definitions", []):
		if not (definition is Dictionary):
			continue
		var file_name: String = str(definition.get("file", ""))
		if file_name.is_empty():
			print("[GameManager] definition has empty file id='%s'" % str(definition.get("id", "")))
			return ERR_INVALID_DATA
		if not FileAccess.file_exists(scene_root_dir.path_join(file_name)):
			print("[GameManager] definition file missing path='%s'" % scene_root_dir.path_join(file_name))
			return ERR_FILE_NOT_FOUND

	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var main_character: Dictionary = characters.get("main_character", {}) as Dictionary
	var main_sprite_file: String = str(main_character.get("sprite_sheet_file", ""))
	if not main_sprite_file.is_empty():
		var main_sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(main_sprite_file))
		if main_sprite_error != OK:
			print("[GameManager] main sprite invalid path='%s' err=%d" % [scene_root_dir.path_join(main_sprite_file), main_sprite_error])
			return main_sprite_error

	for npc in characters.get("npcs", []):
		if not (npc is Dictionary):
			continue
		var sprite_file: String = str((npc as Dictionary).get("sprite_sheet_file", ""))
		if sprite_file.is_empty() or sprite_file == "<null>":
			# NPC without a generated sheet — the runtime uses a fallback sprite.
			continue
		var sprite_error: Error = _validate_character_sprite_file(scene_root_dir.path_join(sprite_file))
		if sprite_error != OK:
			print("[GameManager] npc sprite invalid id='%s' path='%s' err=%d" % [
				str((npc as Dictionary).get("id", "")),
				scene_root_dir.path_join(sprite_file),
				sprite_error,
			])
			return sprite_error

	imported_scene_package = package_data
	imported_scene_root_dir = scene_root_dir
	imported_scene_context = package_data.get("scene_context", {}) as Dictionary
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
