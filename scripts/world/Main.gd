extends Node2D

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")
const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")
const ItemPickupScript := preload("res://scripts/world/ItemPickup.gd")
const WorldObjectScript := preload("res://scripts/world/WorldObject.gd")
const PartyFollowerScript := preload("res://scripts/world/PartyFollower.gd")

@onready var background: Sprite2D = $World/Background
@onready var player: CharacterBody2D = $World/CharacterLayer/GeneratedCharacters/Player
@onready var generated_props: Node2D = $World/GeneratedProps
@onready var generated_characters: Node2D = $World/CharacterLayer/GeneratedCharacters
@onready var generated_prop_tops: Node2D = $World/GeneratedPropTops
@onready var generated_collisions: Node2D = $World/GeneratedCollisions
@onready var lighting_system: Node = $LightingSystem

var _player_spawn_tile := Vector2i.ZERO
var _battle_active: bool = false
var _zone_advancing: bool = false
var _zone_hostiles_cleared_notified: bool = false
var _active_interior_exit: Dictionary = {}
var _triggered_cutscene_active: bool = false
var _pending_triggered_cutscenes: Array = []  # queued cutscene dicts waiting to play

func _ready() -> void:
	NPCConversationManager._start_prewarm()
	print("[Main] ready has_scene_package=%s root='%s'" % [GameManager.has_scene_package(), GameManager.imported_scene_root_dir])
	QuestManager.quests_changed.connect(_on_quests_changed)
	QuestManager.npc_talked.connect(_on_npc_talked_cutscene)
	InventoryManager.item_obtained.connect(_on_item_obtained_cutscene)
	PartyManager.member_joined.connect(_on_party_member_joined)
	PartyManager.member_left.connect(_on_party_member_left)
	if GameManager.has_scene_package():
		_build_imported_world()
		# Register this zone's triggered cutscenes with the director, then play the
		# opening (if any). The zone_enter check runs deferred so it lands AFTER the
		# opening cutscene releases input (the director's drain gate waits on it).
		CutsceneDirector.set_zone_cutscenes(
			str(GameManager.get_scene_context().get("zone_id", "")),
			GameManager.get_scene_package().get("cutscenes", []) as Array,
		)
		_maybe_start_cutscene.call_deferred()
		if ChapterFlow.active:
			QuestManager.notify_zone_entered.call_deferred(str(GameManager.get_scene_context().get("zone_id", "")))
			PartyManager.notify_zone_entered.call_deferred(str(GameManager.get_scene_context().get("zone_id", "")))
			_try_trigger_cutscene.call_deferred("zone_enter")
	else:
		_apply_background_limits(background.texture)
		_spawn_enemies_for_builtin_world()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	if _active_interior_exit.is_empty() or _battle_active or _zone_advancing:
		return
	var leads_to: String = str(_active_interior_exit.get("leads_to", ""))
	if leads_to.is_empty():
		return
	get_viewport().set_input_as_handled()
	_use_scene_exit(leads_to, "")

func _build_imported_world() -> void:
	_clear_generated_content()

	# A freshly loaded world always starts movable; an intro cutscene (started
	# deferred right after this) re-blocks input itself when needed. This also
	# clears any blocking flag left over from a scene-to-scene exit transition.
	GameManager.ui_blocking_input = false
	_active_interior_exit = {}

	var package_data: Dictionary = GameManager.get_scene_package()
	ObjectInteractionManager.register_zone_contracts(package_data)
	var characters: Dictionary = package_data.get("characters", {}) as Dictionary
	var npcs: Array = characters.get("npcs", []) as Array
	print("[Main] build imported world definitions=%d instances=%d npcs=%d" % [
		(package_data.get("definitions", []) as Array).size(),
		(package_data.get("instances", []) as Array).size(),
		npcs.size(),
	])

	var background_path: String = GameManager.get_scene_asset_path(str(package_data.get("background_image", "")))
	var background_texture: Texture2D = GameManager.load_texture(background_path)
	if background_texture != null:
		background.texture = background_texture
		print("[Main] background loaded size=%s path='%s'" % [background_texture.get_size(), background_path])
	else:
		print("[Main] background load FAILED path='%s'" % background_path)

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

		if bool(instance.get("interactive", false)):
			_spawn_world_object(instance, definition)

		if bool(definition.get("solid", false)):
			# Use the full composite sprite for hull tracing; base_file is only the floor layer
			var hull_file: String = str(definition.get("file", definition.get("base_file", "")))
			solid_instances.append({
				"definition_id": instance_id,
				"position_tile": position_tile,
				"size_tiles": definition.get("size_tiles", {}),
				"sprite_file": hull_file,
			})

	var npc_occupied_tiles: Dictionary = {}
	var tile_context: Dictionary = _build_tile_context(package_data, background.texture)
	var spawned_count := 0
	for npc in npcs:
		if npc is Dictionary:
			var npc_data: Dictionary = npc as Dictionary
			# A companion who has joined the party travels as a FOLLOWER, not as a
			# stationary NPC — skip their authored NPC so there aren't two of them.
			if PartyManager.is_member(str(npc_data.get("id", ""))):
				continue
			_spawn_npc(npc_data, tile_context, npc_occupied_tiles)
			npc_occupied_tiles[_tile_key(_read_tile_position(npc_data))] = true
			spawned_count += 1
	print("[Main] spawned_npcs=%d generated_children=%d" % [spawned_count, generated_characters.get_child_count()])

	var occupied_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	for key in occupied_tiles.keys():
		var tile: Vector2i = _tile_from_key(str(key))
		_create_collision_tile(tile)

	_create_map_boundaries(GameManager.get_map_pixel_size(package_data, background.texture))

	var spawn_tile: Vector2i = _resolve_player_spawn_tile(package_data, tile_context)
	_player_spawn_tile = spawn_tile
	player.global_position = _tile_to_pixel_center(spawn_tile)
	player.z_index = 0
	_apply_background_limits(background.texture)

	_spawn_enemies(package_data, tile_context, false)
	_spawn_item_pickups(tile_context)
	_create_scene_exits(tile_context)
	_spawn_party_followers()

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

func _spawn_party_followers() -> void:
	for npc_id in PartyManager.active_member_ids():
		_spawn_follower(str(npc_id))

func _spawn_follower(npc_id: String) -> void:
	if _follower_for(npc_id) != null:
		return
	var follower: Node2D = PartyFollowerScript.new() as Node2D
	follower.name = "Follower_%s" % npc_id
	generated_characters.add_child(follower)
	# stagger lag per member so multiple companions form a line
	var lag: int = 26 + PartyManager.active_member_ids().find(npc_id) * 16
	follower.setup(npc_id, PartyManager.companion_texture(npc_id), player, maxi(26, lag))

func _follower_for(npc_id: String) -> Node2D:
	for child in generated_characters.get_children():
		if child is Node2D and str((child as Node2D).get("npc_id")) == npc_id:
			return child as Node2D
	return null

func _on_party_member_joined(npc_id: String) -> void:
	# Replace the just-joined companion's stationary NPC (if present in this zone) with
	# a follower, so talking to Arlo turns him into a party member who walks with you.
	_despawn_npc(npc_id)
	_spawn_follower(npc_id)

func _on_party_member_left(npc_id: String) -> void:
	var follower := _follower_for(npc_id)
	if follower != null:
		follower.queue_free()

func _despawn_npc(npc_id: String) -> void:
	for child in generated_characters.get_children():
		var data: Variant = child.get("npc_data")
		if data is Dictionary and str((data as Dictionary).get("id", "")) == npc_id:
			child.queue_free()

func _spawn_world_object(instance: Dictionary, definition: Dictionary) -> void:
	var object_id: String = str(instance.get("interaction_object_id", instance.get("id", "")))
	var contract: Dictionary = ObjectInteractionManager.contract_for(object_id)
	if contract.is_empty():
		return
	var world_object: Node2D = WorldObjectScript.new() as Node2D
	generated_characters.add_child(world_object)
	world_object.setup(contract, instance, definition, {"player": player})

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
	var tile_position: Vector2i = _read_tile_position(npc_data)
	print("[Main] spawn npc id='%s' name='%s' tile=%s sprite='%s'" % [
		str(npc_data.get("id", "")),
		str(npc_data.get("name", "")),
		tile_position,
		str(npc_data.get("sprite_sheet_file", "")),
	])
	var world_context := {
		"map_tile_size": tile_context.get("map_tile_size", Vector2i.ZERO),
		"blocked_tiles": tile_context.get("blocked_tiles", {}),
		"occupied_tiles": occupied_tiles,
		"tile_metadata": tile_context.get("tile_metadata", {}),
		"player": player,
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

# ── Scene-to-scene exits ────────────────────────────────────────────────────

func _resolve_player_spawn_tile(package_data: Dictionary, tile_context: Dictionary) -> Vector2i:
	# Arriving through an exit: spawn at the matching edge of the new scene.
	if ChapterFlow.active:
		var entry_edge: String = ChapterFlow.take_pending_entry_edge()
		if entry_edge != "":
			return _entry_spawn_tile(entry_edge, tile_context)
	return _find_player_spawn_tile(package_data)

func _create_scene_exits(tile_context: Dictionary) -> void:
	if not ChapterFlow.active:
		return
	var zone: Dictionary = ChapterFlow.current_zone()
	var edge_exits: Array = zone.get("edge_exits", []) as Array
	var interior_exits: Array = zone.get("interior_exits", []) as Array
	if edge_exits.is_empty() and interior_exits.is_empty():
		return
	var map_tile_size: Vector2i = tile_context.get("map_tile_size", Vector2i.ZERO)
	if map_tile_size == Vector2i.ZERO:
		return
	for exit_data in edge_exits:
		if not (exit_data is Dictionary):
			continue
		var data: Dictionary = exit_data as Dictionary
		var edge: String = str(data.get("edge", ""))
		var leads_to: String = str(data.get("leads_to", ""))
		if edge.is_empty() or leads_to.is_empty():
			continue
		var normalized: float = float(data.get("normalized", 0.5))
		var tile: Vector2i = _edge_exit_tile(edge, normalized, map_tile_size)
		_spawn_scene_exit(tile, edge, leads_to, _zone_display_name(leads_to))
	for exit_data in interior_exits:
		if not (exit_data is Dictionary):
			continue
		var data: Dictionary = exit_data as Dictionary
		var leads_to: String = str(data.get("leads_to", ""))
		if leads_to.is_empty():
			continue
		var tile: Vector2i = _interior_exit_tile(
			float(data.get("x_normalized", 0.5)),
			float(data.get("y_normalized", 0.5)),
			map_tile_size
		)
		tile = _nearest_free_tile(tile, map_tile_size, tile_context.get("blocked_tiles", {}) as Dictionary)
		_spawn_interior_exit(tile, data, _zone_display_name(leads_to))

func _spawn_scene_exit(tile: Vector2i, edge: String, leads_to: String, label_text: String) -> void:
	var area := Area2D.new()
	area.global_position = _tile_to_pixel_center(tile)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# A band spanning the carved 3-cell exit corridor so it is easy to step into.
	if edge == "east" or edge == "west":
		rect.size = Vector2(GameManager.TILE_SIZE * 1.2, GameManager.TILE_SIZE * 3.0)
	else:
		rect.size = Vector2(GameManager.TILE_SIZE * 3.0, GameManager.TILE_SIZE * 1.2)
	shape.shape = rect
	area.add_child(shape)

	var glow := ColorRect.new()
	glow.color = Color(0.55, 0.85, 1.0, 0.16)
	glow.size = rect.size
	glow.position = -rect.size * 0.5
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	area.add_child(glow)

	if not label_text.is_empty():
		var label := Label.new()
		label.text = "→ %s" % label_text
		label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.92))
		label.add_theme_font_size_override("font_size", 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-90, -rect.size.y * 0.5 - 24)
		label.size = Vector2(180, 18)
		area.add_child(label)

	var pulse := area.create_tween().set_loops()
	pulse.tween_property(glow, "color:a", 0.32, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "color:a", 0.10, 0.9).set_trans(Tween.TRANS_SINE)

	var triggered: Array = [false]
	area.body_entered.connect(func(body: Node2D) -> void:
		if triggered[0] or _battle_active or _zone_advancing:
			return
		if body.get("camera") == null:
			return  # only the player carries a camera
		triggered[0] = true
		_use_scene_exit(leads_to, _opposite_edge(edge))
	)
	$World.add_child(area)

func _spawn_interior_exit(tile: Vector2i, exit_data: Dictionary, label_text: String) -> void:
	var leads_to: String = str(exit_data.get("leads_to", ""))
	if leads_to.is_empty():
		return
	var trigger: String = str(exit_data.get("trigger", "interact"))
	var area := Area2D.new()
	area.global_position = _tile_to_pixel_center(tile)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(GameManager.TILE_SIZE * 2.2, GameManager.TILE_SIZE * 2.2)
	shape.shape = rect
	area.add_child(shape)

	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.88, 0.45, 0.18)
	glow.size = rect.size
	glow.position = -rect.size * 0.5
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = glow_mat
	area.add_child(glow)

	var label := Label.new()
	if trigger == "interact":
		label.text = "Press Enter: %s" % label_text
	else:
		label.text = "Enter %s" % label_text
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72, 0.94))
	label.add_theme_font_size_override("font_size", 15)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-100, -rect.size.y * 0.5 - 22)
	label.size = Vector2(200, 18)
	area.add_child(label)

	var pulse := area.create_tween().set_loops()
	pulse.tween_property(glow, "color:a", 0.34, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "color:a", 0.12, 0.9).set_trans(Tween.TRANS_SINE)

	var triggered: Array = [false]
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.get("camera") == null:
			return
		if trigger == "interact":
			_active_interior_exit = exit_data.duplicate(true)
			return
		if triggered[0] or _battle_active or _zone_advancing:
			return
		triggered[0] = true
		_use_scene_exit(leads_to, "")
	)
	area.body_exited.connect(func(body: Node2D) -> void:
		if body.get("camera") == null:
			return
		if str(_active_interior_exit.get("leads_to", "")) == leads_to:
			_active_interior_exit = {}
	)
	$World.add_child(area)

func _use_scene_exit(leads_to: String, arrival_edge: String) -> void:
	# _zone_advancing + the per-area triggered guard stop double-entry. We do NOT
	# raise ui_blocking_input here: it lives on the GameManager autoload and would
	# persist into the freshly loaded scene, freezing the player there.
	_zone_advancing = true
	# Already-downloaded scenes load instantly; otherwise show a download page
	# over the world while ChapterFlow fetches the package.
	if not ChapterFlow.is_zone_cached_by_id(leads_to):
		_show_scene_loading_overlay()
	var err: Error = await ChapterFlow.goto_zone_by_id(leads_to, arrival_edge)
	if err != OK:
		_zone_advancing = false
		print("[Main] scene exit to '%s' failed err=%d" % [leads_to, err])

func _show_scene_loading_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 95
	overlay.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var title := Label.new()
	title.text = "Đang tải cảnh..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.95))
	title.position = Vector2(40, 120)
	title.size = Vector2(400, 22)
	overlay.add_child(title)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92, 0.9))
	status.position = Vector2(40, 146)
	status.size = Vector2(400, 16)
	overlay.add_child(status)

	var updater := Callable(self, "_set_zone_overlay_status").bind(status)
	ChapterFlow.loading_status.connect(updater)
	overlay.tree_exiting.connect(func() -> void:
		if ChapterFlow.loading_status.is_connected(updater):
			ChapterFlow.loading_status.disconnect(updater)
	)

func _set_zone_overlay_status(message: String, status: Label) -> void:
	if status != null and is_instance_valid(status):
		status.text = message

func _edge_exit_tile(edge: String, normalized: float, map_tile_size: Vector2i) -> Vector2i:
	var nx: int = clampi(int(round(normalized * float(map_tile_size.x - 1))), 1, max(map_tile_size.x - 2, 1))
	var ny: int = clampi(int(round(normalized * float(map_tile_size.y - 1))), 1, max(map_tile_size.y - 2, 1))
	match edge:
		"west":
			return Vector2i(0, ny)
		"east":
			return Vector2i(max(map_tile_size.x - 1, 0), ny)
		"north":
			return Vector2i(nx, 0)
		"south":
			return Vector2i(nx, max(map_tile_size.y - 1, 0))
	return Vector2i(nx, ny)

func _interior_exit_tile(x_normalized: float, y_normalized: float, map_tile_size: Vector2i) -> Vector2i:
	var nx: int = clampi(int(round(x_normalized * float(map_tile_size.x - 1))), 1, max(map_tile_size.x - 2, 1))
	var ny: int = clampi(int(round(y_normalized * float(map_tile_size.y - 1))), 1, max(map_tile_size.y - 2, 1))
	return Vector2i(nx, ny)

func _entry_spawn_tile(edge: String, tile_context: Dictionary) -> Vector2i:
	var map_tile_size: Vector2i = tile_context.get("map_tile_size", Vector2i(12, 12))
	var blocked: Dictionary = tile_context.get("blocked_tiles", {})
	var mid_x: int = map_tile_size.x / 2
	var mid_y: int = map_tile_size.y / 2
	# Spawn a few tiles inward from the edge so we do not overlap the return exit.
	var base: Vector2i
	match edge:
		"west":
			base = Vector2i(min(4, map_tile_size.x - 2), mid_y)
		"east":
			base = Vector2i(max(map_tile_size.x - 5, 1), mid_y)
		"north":
			base = Vector2i(mid_x, min(4, map_tile_size.y - 2))
		"south":
			base = Vector2i(mid_x, max(map_tile_size.y - 5, 1))
		_:
			base = Vector2i(mid_x, mid_y)
	return _nearest_free_tile(base, map_tile_size, blocked)

func _nearest_free_tile(start: Vector2i, map_tile_size: Vector2i, blocked: Dictionary) -> Vector2i:
	var max_radius: int = max(map_tile_size.x, map_tile_size.y)
	for radius in range(0, max_radius):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := start + Vector2i(dx, dy)
				if tile.x < 1 or tile.y < 1 or tile.x > map_tile_size.x - 2 or tile.y > map_tile_size.y - 2:
					continue
				if not blocked.has(_tile_key(tile)):
					return tile
	return start

func _opposite_edge(edge: String) -> String:
	match edge:
		"east":
			return "west"
		"west":
			return "east"
		"north":
			return "south"
		"south":
			return "north"
	return ""

func _zone_display_name(zone_id: String) -> String:
	for zone in ChapterFlow.current_chapter_zones():
		if zone is Dictionary and str((zone as Dictionary).get("zone_id", "")) == zone_id:
			return str((zone as Dictionary).get("name", zone_id))
	return zone_id

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

func _spawn_enemies_for_builtin_world() -> void:
	var map_tile_size := Vector2i(12, 12)
	if background.texture != null:
		map_tile_size = Vector2i(
			int(background.texture.get_width() / GameManager.TILE_SIZE),
			int(background.texture.get_height() / GameManager.TILE_SIZE),
		)
	_player_spawn_tile = Vector2i(
		int(player.global_position.x / GameManager.TILE_SIZE),
		int(player.global_position.y / GameManager.TILE_SIZE),
	)
	_spawn_enemies({}, {
		"map_tile_size": map_tile_size,
		"blocked_tiles": {},
	}, true)

func _spawn_enemies(package_data: Dictionary, tile_context: Dictionary, allow_fallback: bool = false) -> void:
	var roster: Array = GameManager.get_enemy_roster()
	if roster.is_empty():
		if allow_fallback:
			roster = _fallback_enemy_roster(tile_context)
			print("[Main] no enemies in package, using fallback roster size=%d" % roster.size())
		else:
			print("[Main] no enemies in package, spawning none")

	var spawned := 0
	for enemy_data in roster:
		if not (enemy_data is Dictionary):
			continue
		var data: Dictionary = (enemy_data as Dictionary).duplicate(true)
		var enemy_id: String = str(data.get("id", ""))
		if GameManager.defeated_enemy_ids.has(enemy_id):
			continue
		if GameManager.spared_enemy_ids.has(enemy_id):
			data["_spared"] = true
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
		generated_characters.add_child(enemy)
		enemy.setup(data, {
			"map_tile_size": tile_context.get("map_tile_size", Vector2i.ZERO),
			"blocked_tiles": tile_context.get("blocked_tiles", {}),
			"player": player,
		})
		enemy.battle_requested.connect(_on_battle_requested)
		spawned += 1
	print("[Main] spawned_enemies=%d" % spawned)

func _on_battle_requested(enemy: Node) -> void:
	if _battle_active:
		return
	_battle_active = true
	print("[Main] battle start enemy='%s'" % str((enemy.enemy_data as Dictionary).get("id", "?")))
	MusicManager.play_boss(GameManager.get_scene_context())
	var battle: CanvasLayer = BattleSceneScript.new()
	add_child(battle)
	battle.battle_finished.connect(_on_battle_finished.bind(enemy))
	battle.open(enemy.enemy_data)

func _on_battle_finished(result: String, enemy_id: String, enemy: Node) -> void:
	_battle_active = false
	print("[Main] battle finished result=%s enemy=%s" % [result, enemy_id])
	# Back to exploration music. If this victory clears the zone, the upcoming
	# scene transition will swap to the next zone's track anyway.
	MusicManager.load_and_play(GameManager.get_scene_context())
	match result:
		"victory":
			GameManager.mark_enemy_defeated(enemy_id)
			QuestManager.notify_enemy_defeated(enemy_id)
			PartyManager.notify_enemy_defeated(enemy_id)
			InventoryManager.grant_linked_items(
				"enemy_drop", enemy_id,
				str(GameManager.get_scene_context().get("zone_id", "")),
			)
			if is_instance_valid(enemy):
				enemy.queue_free()
			_try_trigger_cutscene("enemy_defeated", {"enemy_id": enemy_id})
			_check_zone_cleared.call_deferred()
		"spared":
			GameManager.mark_enemy_spared(enemy_id)
			QuestManager.notify_enemy_defeated(enemy_id)
			PartyManager.notify_enemy_defeated(enemy_id)
			InventoryManager.grant_linked_items(
				"enemy_drop", enemy_id,
				str(GameManager.get_scene_context().get("zone_id", "")),
			)
			if is_instance_valid(enemy):
				enemy.become_passive()
			_try_trigger_cutscene("enemy_defeated", {"enemy_id": enemy_id})
			_check_zone_cleared.call_deferred()
		"fled":
			if is_instance_valid(enemy):
				enemy.start_battle_cooldown()
		"defeat":
			player.global_position = _tile_to_pixel_center(_player_spawn_tile)
			if is_instance_valid(enemy):
				enemy.global_position = enemy._tile_to_pixel_center(enemy.spawn_tile)
				enemy.start_battle_cooldown()

func _spawn_item_pickups(tile_context: Dictionary) -> void:
	if InventoryManager.catalog.is_empty():
		return
	var zone_id: String = str(GameManager.get_scene_context().get("zone_id", ""))
	var blocked: Dictionary = tile_context.get("blocked_tiles", {}) as Dictionary
	var map_size: Vector2i = tile_context.get("map_tile_size", Vector2i(12, 12)) as Vector2i
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(zone_id)  # deterministic scatter per zone
	var used: Dictionary = {}
	var spawned := 0
	for item in InventoryManager.catalog:
		if not (item is Dictionary):
			continue
		var definition: Dictionary = item as Dictionary
		# Items obtained from a world object in this zone live AT that object — never
		# scattered on a random tile (so "the letter inside the clock" stays inside it).
		if ObjectInteractionManager.is_object_sourced_item(str(definition.get("id", "")), zone_id):
			continue
		if not (definition.get("found_in", []) as Array).has(zone_id):
			continue
		var per_zone: Dictionary = definition.get("world_spawns", {}) as Dictionary
		var spawn_count := int(per_zone.get(zone_id, definition.get("world_spawn_count", 1)))
		for _n in range(spawn_count):
			var tile: Vector2i = _find_pickup_tile(rng, map_size, blocked, used)
			if tile == Vector2i(-1, -1):
				continue
			used["%s:%s" % [tile.x, tile.y]] = true
			var pickup: Area2D = ItemPickupScript.new() as Area2D
			generated_props.add_child(pickup)
			pickup.setup(definition, tile)
			spawned += 1
	print("[Main] spawned_item_pickups=%d" % spawned)

func _find_pickup_tile(rng: RandomNumberGenerator, map_size: Vector2i, blocked: Dictionary, used: Dictionary) -> Vector2i:
	for _attempt in range(60):
		var tile := Vector2i(rng.randi_range(1, max(map_size.x - 2, 1)), rng.randi_range(1, max(map_size.y - 2, 1)))
		var key := "%s:%s" % [tile.x, tile.y]
		if blocked.has(key) or used.has(key):
			continue
		if tile.distance_to(_player_spawn_tile) < 3:
			continue
		return tile
	return Vector2i(-1, -1)

func _maybe_start_cutscene() -> void:
	# Always clear any legacy pending intro cutscene so it can't double-play.
	var legacy_actions: Array = ChapterFlow.take_pending_cutscene()
	# Plays only on the initial entry to the chapter's first zone (one-shot).
	var play_opening: bool = ChapterFlow.take_pending_opening()

	var actions: Array = []
	var start_tiles: Dictionary = {}
	if play_opening:
		# Prefer the new opening cutscene packaged into this scene (entry zone).
		# It carries backend pre-placed start tiles so actors barely move.
		var opening: Dictionary = GameManager.get_scene_package().get("opening_cutscene", {}) as Dictionary
		actions = (opening.get("actions", []) as Array)
		start_tiles = (opening.get("start_tiles", {}) as Dictionary)
	if actions.is_empty():
		# Old packages: fall back to the chapter-intro cutscene (already gated).
		actions = legacy_actions
		start_tiles = {}
	if actions.is_empty():
		return

	print("[Main] starting opening cutscene actions=%d start_tiles=%d" % [actions.size(), start_tiles.size()])
	var cutscene: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene)
	cutscene.cutscene_finished.connect(_check_zone_cleared)
	cutscene.play(actions, self, player, generated_characters, start_tiles)

# ── triggered (mid-chapter) cutscenes ───────────────────────────────────────────
# Match a reported event against this zone's packaged cutscenes (CutsceneDirector)
# and play the first unplayed one — the SAME way the opening cutscene plays
# (CutscenePlayer applies the pre-placed start tiles, then restores actors).

func _try_trigger_cutscene(event_type: String, params: Dictionary = {}) -> void:
	if not ChapterFlow.active:
		return
	var cutscene: Dictionary = CutsceneDirector.match_event(event_type, params)
	if cutscene.is_empty():
		return
	var id := str(cutscene.get("id", ""))
	for queued in _pending_triggered_cutscenes:
		if str((queued as Dictionary).get("id", "")) == id:
			return  # already queued
	_pending_triggered_cutscenes.append(cutscene)
	_drain_triggered_cutscenes()

func _drain_triggered_cutscenes() -> void:
	if _pending_triggered_cutscenes.is_empty():
		return
	# Wait for a calm moment: no battle, no zone transition, no other cutscene or
	# blocking UI (the opening cutscene and dialogue set ui_blocking_input).
	if _battle_active or _zone_advancing or _triggered_cutscene_active or GameManager.ui_blocking_input:
		get_tree().create_timer(0.4).timeout.connect(_drain_triggered_cutscenes, CONNECT_ONE_SHOT)
		return
	var cutscene: Dictionary = _pending_triggered_cutscenes.pop_front()
	var id := str(cutscene.get("id", ""))
	if CutsceneDirector.is_played(id):
		_drain_triggered_cutscenes.call_deferred()
		return
	CutsceneDirector.mark_played(id)
	_play_triggered_cutscene(cutscene)

func _play_triggered_cutscene(cutscene: Dictionary) -> void:
	_triggered_cutscene_active = true
	var actions: Array = cutscene.get("actions", []) as Array
	var start_tiles: Dictionary = cutscene.get("start_tiles", {}) as Dictionary
	print("[Main] triggered cutscene id=%s actions=%d start_tiles=%d" % [str(cutscene.get("id", "")), actions.size(), start_tiles.size()])
	var cutscene_player: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene_player)
	cutscene_player.cutscene_finished.connect(func() -> void:
		_triggered_cutscene_active = false
		_drain_triggered_cutscenes.call_deferred()
		_check_zone_cleared.call_deferred()
	)
	cutscene_player.play(actions, self, player, generated_characters, start_tiles)

func _remaining_hostile_count() -> int:
	var count := 0
	for child in generated_characters.get_children():
		if child.has_method("is_hostile") and child.is_hostile():
			count += 1
	return count

func _on_quests_changed() -> void:
	_refresh_quest_markers()
	_try_trigger_cutscene("quest_changed")
	_check_zone_cleared.call_deferred()


func _on_npc_talked_cutscene(npc_id: String) -> void:
	_try_trigger_cutscene("npc_talked", {"npc_id": npc_id})


func _on_item_obtained_cutscene(item_id: String) -> void:
	_try_trigger_cutscene("item_obtained", {"item_id": item_id})

func _refresh_quest_markers() -> void:
	for child in generated_characters.get_children():
		if child.has_method("update_quest_marker"):
			child.update_quest_marker()

func _check_zone_cleared() -> void:
	if not ChapterFlow.active or _battle_active or _zone_advancing:
		return
	if _remaining_hostile_count() > 0:
		return
	var zone_id: String = str(GameManager.get_scene_context().get("zone_id", ""))
	if not _zone_hostiles_cleared_notified:
		_zone_hostiles_cleared_notified = true
		QuestManager.notify_zone_hostiles_cleared(zone_id)
		_try_trigger_cutscene("zone_cleared")
	# Clearing hostiles updates quests, but it no longer auto-advances the zone.
	# The player moves to another scene only through explicit exits/transitions.

func _fallback_enemy_roster(tile_context: Dictionary) -> Array:
	var blocked: Dictionary = tile_context.get("blocked_tiles", {}) as Dictionary
	var map_size: Vector2i = tile_context.get("map_tile_size", Vector2i(12, 12)) as Vector2i
	var spawn_tiles: Array[Vector2i] = []
	var offsets := [Vector2i(6, 0), Vector2i(-6, 2), Vector2i(0, 7), Vector2i(4, -5)]
	for offset in offsets:
		var tile: Vector2i = _player_spawn_tile + offset
		tile.x = clampi(tile.x, 1, max(map_size.x - 2, 1))
		tile.y = clampi(tile.y, 1, max(map_size.y - 2, 1))
		if not blocked.has(_tile_key(tile)):
			spawn_tiles.append(tile)
		if spawn_tiles.size() >= 2:
			break
	while spawn_tiles.size() < 2:
		spawn_tiles.append(_player_spawn_tile + Vector2i(3 + spawn_tiles.size(), 3))

	return [
		_fallback_enemy("fallback_echo_1", "Lost Echo", "minion", 1, false, spawn_tiles[0]),
		_fallback_enemy("fallback_echo_2", "Hollow Warden", "elite", 2, true, spawn_tiles[1]),
	]

func _fallback_enemy(id: String, display_name: String, rank: String, level: int, can_spare: bool, tile: Vector2i) -> Dictionary:
	var mult: float = 1.4 if rank == "elite" else 1.0
	return {
		"id": id,
		"name": display_name,
		"rank": rank,
		"level": level,
		"can_spare": can_spare,
		"stats": {
			"max_hp": int((30 + 14 * level) * mult),
			"attack": int((6 + 2.2 * level) * mult),
			"defense": int((2 + 1.4 * level) * mult * 0.9),
			"speed": 6 + level + (2 if rank == "elite" else 0),
		},
		"xp_reward": int((18 + 9 * level) * mult),
		"skills": [
			{"name": "Flickering Claw", "kind": "strike", "power": 1.0, "telegraph": "It flickers closer, edges sharpening."},
			{"name": "Static Howl", "kind": "hex", "power": 0.8, "telegraph": "A low hum builds inside it..."},
			{"name": "Collapse", "kind": "heavy", "power": 1.8, "telegraph": "It folds inward, gathering itself for something terrible!"},
		],
		"weakness": {
			"hint": "It repeats the same broken motion, like a moment it cannot leave.",
			"probe_options": [
				{"text": "\"Stop! You're hurting people!\"", "correct": false, "reveal": "It does not hear commands. It only repeats."},
				{"text": "\"This moment already ended. You can rest.\"", "correct": true, "reveal": "The echo shudders. For one second, its face becomes a person's face — tired, relieved."},
				{"text": "\"Who are you?\"", "correct": false, "reveal": "Static. It does not remember being anyone."},
			],
			"vulnerable_turns": 3,
			"damage_multiplier": 2.0,
		},
		"phases": [
			{"hp_ratio": 0.5, "story_beat": "The echo's loop is breaking apart...", "behavior": "desperate"},
		],
		"dialogue": {
			"intro": ["A " + display_name + " flickers into your path, repeating a moment that no longer exists."],
			"taunt": ["...it repeats..."],
			"low_hp": ["The loop is almost broken."],
			"player_victory": ["...thank... you..."],
			"player_defeat": ["The echo swallows your light."],
			"spare": ["The echo dims, folds its hands, and stops repeating."],
			"finish": ["The echo scatters into harmless motes of light."],
		},
		"spawn": {
			"position_tile": {"x": tile.x, "y": tile.y},
			"patrol_radius": 3,
			"aggro_radius": 4,
		},
	}

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
