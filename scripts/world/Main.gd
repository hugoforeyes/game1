extends Node2D

const NPC_SCENE := preload("res://scenes/npc/NPC.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")
const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const CutscenePlayerScript := preload("res://scripts/cutscene/CutscenePlayer.gd")
const ItemPickupScript := preload("res://scripts/world/ItemPickup.gd")
const WorldObjectScript := preload("res://scripts/world/WorldObject.gd")
const InteriorExitScript := preload("res://scripts/world/InteriorExit.gd")
const ZoneExitPortalScript := preload("res://scripts/world/ZoneExitPortal.gd")
const PartyFollowerScript := preload("res://scripts/world/PartyFollower.gd")
const PartyHudViewScript := preload("res://scripts/ui/PartyHudView.gd")
const QuestCompassViewScript := preload("res://scripts/ui/QuestCompassView.gd")
const HudShortcutsViewScript := preload("res://scripts/ui/HudShortcutsView.gd")
const ZONE_TRANSITION_OVERLAY_NAME := "ZoneTransitionOverlay"
const ZONE_TRANSITION_FADE_SECONDS := 0.35
const ZONE_TRANSITION_CAMERA_SETTLE_FRAMES := 3
const ENTRY_SPAWN_INSET_TILES := 2

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
var _triggered_cutscene_active: bool = false
var _pending_triggered_cutscenes: Array = []  # queued cutscene dicts waiting to play
var _cutscene_conversation_handoff_pending: bool = false

func _ready() -> void:
	add_to_group("narrative_playback_owner")
	NPCConversationManager._start_prewarm()
	_mount_party_hud()
	_mount_quest_compass()
	print("[Main] ready has_scene_package=%s root='%s'" % [GameManager.has_scene_package(), GameManager.imported_scene_root_dir])
	QuestManager.quests_changed.connect(_on_quests_changed)
	QuestManager.npc_talked.connect(_on_npc_talked_cutscene)
	InventoryManager.item_obtained.connect(_on_item_obtained_cutscene)
	PartyManager.member_joined.connect(_on_party_member_joined)
	PartyManager.member_left.connect(_on_party_member_left)
	NarrativeState.narrative_changed.connect(_on_narrative_changed)
	if GameManager.has_scene_package():
		_build_imported_world()
		# Register this zone's planned cutscenes with the director. Opening cutscenes
		# are now normal zone_enter beats in scene_package.cutscenes.
		CutsceneDirector.set_zone_cutscenes(
			str(GameManager.get_scene_context().get("zone_id", "")),
			GameManager.get_scene_package().get("cutscenes", []) as Array,
		)
		_complete_imported_zone_entry.call_deferred()
	else:
		_apply_background_limits(background.texture)
		_spawn_enemies_for_builtin_world()
		_fade_in_pending_zone_transition.call_deferred()

func _complete_imported_zone_entry() -> void:
	# Reveal the new zone before dispatching any opening/zone-enter cutscene. Starting
	# one behind the persistent black transition layer can leave two independent UI
	# owners fighting over ui_blocking_input and makes a valid cutscene look frozen.
	await _fade_in_pending_zone_transition()
	_maybe_start_cutscene()
	if not ChapterFlow.active:
		return
	var zone_id := str(GameManager.get_scene_context().get("zone_id", ""))
	QuestManager.notify_zone_entered(zone_id)
	PartyManager.notify_zone_entered(zone_id)
	_try_trigger_cutscene("zone_enter")

func _build_imported_world() -> void:
	_clear_generated_content()

	# A freshly loaded world starts movable unless it is still under the persistent
	# zone fade overlay; fade-in clears the block once the new scene is visible.
	GameManager.ui_blocking_input = get_tree().root.get_node_or_null(ZONE_TRANSITION_OVERLAY_NAME) != null

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

		if bool(instance.get("interactive", false)) and not bool(instance.get("transition_object", false)):
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
	var npc_map_size: Vector2i = tile_context.get("map_tile_size", Vector2i.ZERO) as Vector2i
	var npc_blocked: Dictionary = (tile_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	var authored_player_tile := _find_player_spawn_tile(package_data)
	if authored_player_tile != Vector2i.ZERO:
		npc_blocked[_tile_key(authored_player_tile)] = true
	var spawned_count := 0
	for npc in npcs:
		if npc is Dictionary:
			var npc_data: Dictionary = (npc as Dictionary).duplicate(true)
			var npc_id: String = str(npc_data.get("id", "")).strip_edges()
			if NarrativeState.should_hide_actor(npc_id):
				continue
			# A companion who has joined the party travels as a FOLLOWER, not as a
			# stationary NPC — skip their authored NPC so there aren't two of them.
			if PartyManager.is_member(npc_id):
				continue
			var authored_tile := _read_tile_position(npc_data)
			var resolved_tile := authored_tile
			if npc_map_size != Vector2i.ZERO:
				resolved_tile = _nearest_open_tile(authored_tile, npc_map_size, npc_blocked)
			if resolved_tile != authored_tile:
				print("[Main] adjusted occupied npc spawn id='%s': %s -> %s" % [npc_id, authored_tile, resolved_tile])
				npc_data["position_tile"] = {"x": resolved_tile.x, "y": resolved_tile.y}
				var movement: Dictionary = (npc_data.get("movement", {}) as Dictionary).duplicate(true)
				var raw_anchor: Dictionary = movement.get("anchor_tile", {}) as Dictionary
				var anchor := Vector2i(int(raw_anchor.get("x", 0)), int(raw_anchor.get("y", 0)))
				if anchor == authored_tile:
					movement["anchor_tile"] = {"x": resolved_tile.x, "y": resolved_tile.y}
					npc_data["movement"] = movement
			_spawn_npc(npc_data, tile_context, npc_occupied_tiles)
			npc_occupied_tiles[_tile_key(resolved_tile)] = true
			npc_blocked[_tile_key(resolved_tile)] = true
			spawned_count += 1
	print("[Main] spawned_npcs=%d generated_children=%d" % [spawned_count, generated_characters.get_child_count()])

	var occupied_tiles: Dictionary = GameManager.get_blocked_tiles(package_data)
	for key in occupied_tiles.keys():
		var tile: Vector2i = _tile_from_key(str(key))
		_create_collision_tile(tile)

	_create_map_boundaries(GameManager.get_map_pixel_size(package_data, background.texture))

	var spawn_tile: Vector2i = _resolve_player_spawn_tile(package_data, tile_context)
	# Final guarantee across ALL spawn paths (entry / authored / center-fallback):
	# never drop the player onto a solid tile or a walled-in pocket they can't leave.
	var player_spawn_blocked: Dictionary = (tile_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	for key in npc_occupied_tiles:
		player_spawn_blocked[key] = true
	spawn_tile = _nearest_open_tile(
		spawn_tile,
		tile_context.get("map_tile_size", Vector2i.ZERO) as Vector2i,
		player_spawn_blocked,
	)
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
		_snap_player_camera()

func _snap_player_camera() -> void:
	var player_camera: Camera2D = player.get("camera") as Camera2D
	if player_camera == null:
		return
	player_camera.make_current()
	if player_camera.has_method("reset_smoothing"):
		player_camera.call("reset_smoothing")
	if player_camera.has_method("force_update_scroll"):
		player_camera.call("force_update_scroll")

func _mount_party_hud() -> void:
	# Overworld level/party readout (top-left). Self-contained; reads GameManager.
	var shortcuts: CanvasLayer = HudShortcutsViewScript.new()
	add_child(shortcuts)
	var hud: CanvasLayer = PartyHudViewScript.new()
	hud.name = "PartyHud"
	add_child(hud)


func _mount_quest_compass() -> void:
	# Screen-edge pointer toward the tracked objective's exact target, once fully
	# hinted. Needs Main's live entity lookups + the player node, unlike the
	# self-contained HUD views above.
	var compass: QuestCompassView = QuestCompassViewScript.new()
	compass.name = "QuestCompass"
	add_child(compass)
	compass.setup(self, player)


func _spawn_party_followers() -> void:
	for npc_id in PartyManager.active_member_ids():
		_spawn_follower(str(npc_id))

func _spawn_follower(npc_id: String) -> void:
	if NarrativeState.should_hide_actor(npc_id):
		return
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
	if not NarrativeState.should_hide_actor(npc_id):
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

func _on_narrative_changed() -> void:
	_apply_actor_states_to_spawned_characters()

func _apply_actor_states_to_spawned_characters() -> void:
	if generated_characters == null:
		return
	for child in generated_characters.get_children():
		var actor_id := _actor_id_for_node(child)
		if actor_id.is_empty():
			continue
		if NarrativeState.should_hide_actor(actor_id):
			child.queue_free()
			continue
		if child.has_method("apply_actor_state"):
			child.call("apply_actor_state", NarrativeState.actor_state(actor_id))

func _actor_id_for_node(node: Node) -> String:
	var data: Variant = node.get("npc_data")
	if data is Dictionary:
		var id := str((data as Dictionary).get("id", "")).strip_edges()
		if not id.is_empty():
			return id
	for key in ["npc_id", "actor_id", "entity_id"]:
		var value := str(node.get(key)).strip_edges()
		if not value.is_empty() and value != "<null>":
			return value
	return ""

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
		"actor_state": NarrativeState.actor_state(str(npc_data.get("id", ""))),
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
	# Arriving through an exit: edge exits use the matching edge. Interior/object
	# exits have no edge, so spawn beside the matching return door instead.
	if ChapterFlow.active:
		var entry_edge: String = ChapterFlow.take_pending_entry_edge()
		var entry_normalized: float = ChapterFlow.take_pending_entry_normalized()
		var from_zone_id: String = ChapterFlow.take_pending_entry_from_zone()
		if not entry_edge.is_empty():
			return _entry_spawn_tile(entry_edge, entry_normalized, from_zone_id, tile_context)
		if not from_zone_id.is_empty():
			var interior_spawn := _interior_entry_spawn_tile(from_zone_id, package_data, tile_context)
			if interior_spawn != Vector2i(-1, -1):
				return interior_spawn
	return _find_player_spawn_tile(package_data)

func _interior_entry_spawn_tile(from_zone_id: String, package_data: Dictionary, tile_context: Dictionary) -> Vector2i:
	var map_tile_size: Vector2i = tile_context.get("map_tile_size", Vector2i.ZERO)
	if map_tile_size == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var blocked: Dictionary = tile_context.get("blocked_tiles", {}) as Dictionary
	var zone: Dictionary = ChapterFlow.current_zone()
	for exit_data in (zone.get("interior_exits", []) as Array):
		if not (exit_data is Dictionary):
			continue
		var data: Dictionary = exit_data as Dictionary
		if str(data.get("leads_to", "")) != from_zone_id:
			continue
		var tile: Vector2i = _interior_exit_object_tile(package_data, data)
		if tile == Vector2i(-1, -1):
			tile = _interior_exit_tile(
				float(data.get("x_normalized", 0.5)),
				float(data.get("y_normalized", 0.5)),
				map_tile_size
			)
		return _nearest_open_tile(tile, map_tile_size, blocked)
	return Vector2i(-1, -1)

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
		_spawn_scene_exit(tile, edge, leads_to, normalized, _zone_display_name(leads_to))
	for exit_data in interior_exits:
		if not (exit_data is Dictionary):
			continue
		var data: Dictionary = exit_data as Dictionary
		var leads_to: String = str(data.get("leads_to", ""))
		if leads_to.is_empty():
			continue
		var package_data: Dictionary = GameManager.get_scene_package()
		var tile: Vector2i = _interior_exit_object_tile(package_data, data)
		var footprint_rect: Rect2 = _interior_exit_object_rect(package_data, data)
		if tile == Vector2i(-1, -1):
			tile = _interior_exit_tile(
				float(data.get("x_normalized", 0.5)),
				float(data.get("y_normalized", 0.5)),
				map_tile_size
			)
			tile = _nearest_free_tile(tile, map_tile_size, tile_context.get("blocked_tiles", {}) as Dictionary)
		_spawn_interior_exit(tile, data, _zone_display_name(leads_to), footprint_rect)

func _spawn_scene_exit(tile: Vector2i, edge: String, leads_to: String, normalized: float, label_text: String) -> void:
	var portal := ZoneExitPortalScript.new()
	portal.setup(_tile_to_pixel_center(tile), edge, leads_to, normalized, label_text, player)
	portal.exit_requested.connect(_on_scene_exit_requested)
	$World.add_child(portal)

func _on_scene_exit_requested(leads_to: String, edge: String, normalized: float) -> void:
	if leads_to.is_empty() or _battle_active or _zone_advancing:
		return
	_use_scene_exit(leads_to, _opposite_edge(edge), normalized)

func _spawn_interior_exit(tile: Vector2i, exit_data: Dictionary, label_text: String, footprint_rect: Rect2 = Rect2()) -> void:
	var leads_to: String = str(exit_data.get("leads_to", ""))
	if leads_to.is_empty():
		return
	var area := InteriorExitScript.new()
	area.setup(_tile_to_pixel_center(tile), exit_data, label_text, player, footprint_rect)
	area.connect("exit_requested", Callable(self, "_on_interior_exit_requested"))
	$World.add_child(area)

func _on_interior_exit_requested(leads_to: String) -> void:
	if leads_to.is_empty() or _battle_active or _zone_advancing:
		return
	_use_scene_exit(leads_to, "")

func _use_scene_exit(leads_to: String, arrival_edge: String, arrival_normalized: float = -1.0) -> void:
	# _zone_advancing + the per-area triggered guard stop double-entry.
	_zone_advancing = true
	GameManager.ui_blocking_input = true
	var overlay: CanvasLayer = _ensure_zone_transition_overlay()
	await _fade_zone_transition_overlay(overlay, 1.0, ZONE_TRANSITION_FADE_SECONDS)

	if not ChapterFlow.is_zone_cached_by_id(leads_to):
		_set_zone_transition_status("Đang tải cảnh...")
	var err: Error = await ChapterFlow.goto_zone_by_id(leads_to, arrival_edge, arrival_normalized)
	if err != OK:
		_zone_advancing = false
		GameManager.ui_blocking_input = false
		await _fade_zone_transition_overlay(overlay, 0.0, ZONE_TRANSITION_FADE_SECONDS)
		overlay.queue_free()
		print("[Main] scene exit to '%s' failed err=%d" % [leads_to, err])

func _ensure_zone_transition_overlay() -> CanvasLayer:
	var root: Window = get_tree().root
	var existing: Node = root.get_node_or_null(ZONE_TRANSITION_OVERLAY_NAME)
	if existing is CanvasLayer:
		return existing as CanvasLayer

	var overlay := CanvasLayer.new()
	overlay.name = ZONE_TRANSITION_OVERLAY_NAME
	overlay.layer = 120
	root.add_child(overlay)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var status := Label.new()
	status.name = "Status"
	status.text = ""
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.95))
	status.modulate.a = 0.0
	status.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(status)

	return overlay

func _fade_zone_transition_overlay(overlay: CanvasLayer, target_alpha: float, seconds: float) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var dim := overlay.get_node_or_null("Dim") as ColorRect
	if dim == null:
		return
	var tween := create_tween()
	tween.tween_property(dim, "color:a", target_alpha, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var status := overlay.get_node_or_null("Status") as Label
	if status != null and not status.text.is_empty():
		tween.parallel().tween_property(status, "modulate:a", target_alpha, seconds * 0.8)
	await tween.finished

func _fade_in_pending_zone_transition() -> void:
	var root: Window = get_tree().root
	var overlay := root.get_node_or_null(ZONE_TRANSITION_OVERLAY_NAME) as CanvasLayer
	if overlay == null:
		GameManager.ui_blocking_input = false
		return
	_set_zone_transition_status("")
	await _settle_player_camera_for_transition()
	await _fade_zone_transition_overlay(overlay, 0.0, ZONE_TRANSITION_FADE_SECONDS)
	if is_instance_valid(overlay):
		overlay.queue_free()
	GameManager.ui_blocking_input = false

func _settle_player_camera_for_transition() -> void:
	_snap_player_camera()
	for _i in range(ZONE_TRANSITION_CAMERA_SETTLE_FRAMES):
		await get_tree().process_frame
		_snap_player_camera()

func _set_zone_transition_status(message: String) -> void:
	var root: Window = get_tree().root
	var overlay := root.get_node_or_null(ZONE_TRANSITION_OVERLAY_NAME) as CanvasLayer
	if overlay == null:
		return
	var status := overlay.get_node_or_null("Status") as Label
	if status == null:
		return
	status.text = message
	status.modulate.a = 1.0 if not message.is_empty() else 0.0

func _show_scene_loading_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 95
	overlay.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.06, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# Design space = half the real viewport (the overlay layer runs at scale 2).
	var design: Vector2 = get_viewport().get_visible_rect().size / 2.0

	var title := Label.new()
	title.text = "Đang tải cảnh..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.95))
	title.position = Vector2((design.x - 400.0) * 0.5, design.y * 0.5 - 15.0)
	title.size = Vector2(400, 22)
	overlay.add_child(title)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92, 0.9))
	status.position = Vector2((design.x - 400.0) * 0.5, design.y * 0.5 + 11.0)
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

func _interior_exit_object_tile(package_data: Dictionary, exit_data: Dictionary) -> Vector2i:
	var object_id: String = str(exit_data.get("object_id", ""))
	if object_id.is_empty():
		return Vector2i(-1, -1)
	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var data: Dictionary = instance as Dictionary
		var instance_id: String = str(data.get("id", ""))
		var interaction_id: String = str(data.get("interaction_object_id", ""))
		var transition_id: String = str(data.get("transition_object_id", ""))
		if object_id != instance_id and object_id != interaction_id and object_id != transition_id:
			continue
		var position_tile: Dictionary = data.get("position_tile", {}) as Dictionary
		var base_tile := Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
		var definition: Dictionary = definitions.get(str(data.get("definition_id", instance_id)), {}) as Dictionary
		var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
		var width: int = max(int(size_tiles.get("w", 1)), 1)
		var height: int = max(int(size_tiles.get("h", 1)), 1)
		var center_offset := Vector2i(
			int(round(float(max(width - 1, 0)) / 2.0)),
			int(round(float(max(height - 1, 0)) / 2.0))
		)
		return base_tile + center_offset
	return Vector2i(-1, -1)

func _interior_exit_object_rect(package_data: Dictionary, exit_data: Dictionary) -> Rect2:
	var object_id: String = str(exit_data.get("object_id", ""))
	if object_id.is_empty():
		return Rect2()
	var definitions: Dictionary = _definitions_by_id(package_data)
	for instance in package_data.get("instances", []):
		if not (instance is Dictionary):
			continue
		var data: Dictionary = instance as Dictionary
		var instance_id: String = str(data.get("id", ""))
		var interaction_id: String = str(data.get("interaction_object_id", ""))
		var transition_id: String = str(data.get("transition_object_id", ""))
		if object_id != instance_id and object_id != interaction_id and object_id != transition_id:
			continue
		var position_tile: Dictionary = data.get("position_tile", {}) as Dictionary
		var base_tile := Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
		var definition: Dictionary = definitions.get(str(data.get("definition_id", instance_id)), {}) as Dictionary
		var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
		var width: int = max(int(size_tiles.get("w", 1)), 1)
		var height: int = max(int(size_tiles.get("h", 1)), 1)
		return Rect2(
			Vector2(base_tile) * GameManager.TILE_SIZE,
			Vector2(width, height) * GameManager.TILE_SIZE
		)
	return Rect2()

func _entry_spawn_tile(edge: String, fallback_normalized: float, from_zone_id: String, tile_context: Dictionary) -> Vector2i:
	var map_tile_size: Vector2i = tile_context.get("map_tile_size", Vector2i(12, 12))
	var blocked: Dictionary = tile_context.get("blocked_tiles", {})
	var normalized: float = _entry_normalized_for(edge, from_zone_id, fallback_normalized)
	var exit_tile: Vector2i = _edge_exit_tile(edge, normalized, map_tile_size)
	var spawn_tile: Vector2i = _shortest_walkable_entry_spawn(exit_tile, edge, map_tile_size, blocked)
	if spawn_tile != Vector2i(-1, -1):
		return spawn_tile
	return _nearest_free_tile(_entry_fallback_base(edge, normalized, map_tile_size), map_tile_size, blocked)

func _entry_normalized_for(edge: String, from_zone_id: String, fallback_normalized: float) -> float:
	if not from_zone_id.is_empty():
		var zone: Dictionary = ChapterFlow.current_zone()
		for exit_data in (zone.get("edge_exits", []) as Array):
			if not (exit_data is Dictionary):
				continue
			var data: Dictionary = exit_data as Dictionary
			if str(data.get("edge", "")) == edge and str(data.get("leads_to", "")) == from_zone_id:
				return clampf(float(data.get("normalized", 0.5)), 0.0, 1.0)
	if fallback_normalized >= 0.0:
		return clampf(fallback_normalized, 0.0, 1.0)
	return 0.5

func _shortest_walkable_entry_spawn(exit_tile: Vector2i, edge: String, map_tile_size: Vector2i, blocked: Dictionary) -> Vector2i:
	var queue: Array[Vector2i] = [exit_tile]
	var visited: Dictionary = {_tile_key(exit_tile): true}
	var head := 0
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP,
	]
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		if _is_entry_spawn_candidate(tile, edge, map_tile_size, blocked):
			return tile
		for dir in directions:
			var next: Vector2i = tile + dir
			var key := _tile_key(next)
			if visited.has(key):
				continue
			if next.x < 0 or next.y < 0 or next.x >= map_tile_size.x or next.y >= map_tile_size.y:
				continue
			if blocked.has(key):
				continue
			visited[key] = true
			queue.append(next)
	return Vector2i(-1, -1)

func _is_entry_spawn_candidate(tile: Vector2i, edge: String, map_tile_size: Vector2i, blocked: Dictionary) -> bool:
	if blocked.has(_tile_key(tile)):
		return false
	if tile.x < 1 or tile.y < 1 or tile.x > map_tile_size.x - 2 or tile.y > map_tile_size.y - 2:
		return false
	match edge:
		"west":
			return tile.x >= min(ENTRY_SPAWN_INSET_TILES, map_tile_size.x - 2)
		"east":
			return tile.x <= max(map_tile_size.x - 1 - ENTRY_SPAWN_INSET_TILES, 1)
		"north":
			return tile.y >= min(ENTRY_SPAWN_INSET_TILES, map_tile_size.y - 2)
		"south":
			return tile.y <= max(map_tile_size.y - 1 - ENTRY_SPAWN_INSET_TILES, 1)
	return true

func _entry_fallback_base(edge: String, normalized: float, map_tile_size: Vector2i) -> Vector2i:
	var edge_x: int = clampi(int(round(normalized * float(map_tile_size.x - 1))), 1, max(map_tile_size.x - 2, 1))
	var edge_y: int = clampi(int(round(normalized * float(map_tile_size.y - 1))), 1, max(map_tile_size.y - 2, 1))
	match edge:
		"west":
			return Vector2i(min(ENTRY_SPAWN_INSET_TILES, map_tile_size.x - 2), edge_y)
		"east":
			return Vector2i(max(map_tile_size.x - 1 - ENTRY_SPAWN_INSET_TILES, 1), edge_y)
		"north":
			return Vector2i(edge_x, min(ENTRY_SPAWN_INSET_TILES, map_tile_size.y - 2))
		"south":
			return Vector2i(edge_x, max(map_tile_size.y - 1 - ENTRY_SPAWN_INSET_TILES, 1))
	return Vector2i(map_tile_size.x / 2, map_tile_size.y / 2)

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

## Nearest tile to `start` that is free AND not a sealed pocket — it has at least
## one free orthogonal neighbour, so an actor placed there can actually move. This
## is what `_nearest_free_tile` misses: a lone free cell walled in by objects on all
## sides reads as "free" but traps the actor. Prefers the most-open tile in the
## nearest ring; falls back to any free tile, then `start`. `blocked` must already
## include object collision (GameManager.get_blocked_tiles) plus tiles taken by
## other actors so spawns never stack.
func _nearest_open_tile(start: Vector2i, map_tile_size: Vector2i, blocked: Dictionary) -> Vector2i:
	var first_free := Vector2i(-1, -1)
	var max_radius: int = max(map_tile_size.x, map_tile_size.y)
	for radius in range(0, max_radius):
		var best := Vector2i(-1, -1)
		var best_openness := 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and max(abs(dx), abs(dy)) != radius:
					continue  # only the ring at this exact radius (inner rings already checked)
				var tile := start + Vector2i(dx, dy)
				if tile.x < 1 or tile.y < 1 or tile.x > map_tile_size.x - 2 or tile.y > map_tile_size.y - 2:
					continue
				if blocked.has(_tile_key(tile)):
					continue
				if first_free == Vector2i(-1, -1):
					first_free = tile
				var openness := _free_orthogonal_neighbors(tile, map_tile_size, blocked)
				if openness > best_openness:
					best_openness = openness
					best = tile
		if best != Vector2i(-1, -1) and best_openness >= 1:
			return best
	return first_free if first_free != Vector2i(-1, -1) else start

func _free_orthogonal_neighbors(tile: Vector2i, map_tile_size: Vector2i, blocked: Dictionary) -> int:
	var count := 0
	for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var n: Vector2i = tile + dir
		if n.x < 0 or n.y < 0 or n.x >= map_tile_size.x or n.y >= map_tile_size.y:
			continue
		if not blocked.has(_tile_key(n)):
			count += 1
	return count

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


## Public: the live global_position of a currently-spawned entity in THIS zone,
## or Vector2.INF if it isn't here (different zone, not yet spawned, or already
## consumed/defeated). Queried by QuestCompassView every frame it needs a fresh
## target — cheap since a zone has at most a few dozen children.
## kind: "npc" | "object" | "item" | "enemy"
func find_entity_global_position(kind: String, entity_id: String) -> Vector2:
	if entity_id.is_empty():
		return Vector2.INF
	match kind:
		"npc":
			for child in generated_characters.get_children():
				var npc: Variant = child.get("npc_data")
				if npc is Dictionary and str((npc as Dictionary).get("id", "")) == entity_id:
					return (child as Node2D).global_position
		"object":
			for child in generated_characters.get_children():
				var object_id: Variant = child.get("object_id")
				if object_id != null and str(object_id) == entity_id:
					return (child as Node2D).global_position
		"enemy":
			for child in generated_characters.get_children():
				var enemy_data: Variant = child.get("enemy_data")
				if enemy_data is Dictionary and str((enemy_data as Dictionary).get("id", "")) == entity_id:
					return (child as Node2D).global_position
		"item":
			for child in generated_props.get_children():
				var item_id: Variant = child.get("item_id")
				if item_id != null and str(item_id) == entity_id:
					return (child as Node2D).global_position
	return Vector2.INF


## Public: nearest currently hostile enemy to a world position. Count-based
## defeat objectives have no target_enemy_id, so QuestCompassView re-evaluates
## this every frame and naturally advances to the next enemy after a defeat or
## spare without keeping a stale entity reference.
func find_nearest_hostile_global_position(from_position: Vector2) -> Vector2:
	var nearest_position := Vector2.INF
	var nearest_distance_sq := INF
	for child in generated_characters.get_children():
		if not (child is Node2D) or not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var enemy_data: Variant = child.get("enemy_data")
		if not (enemy_data is Dictionary):
			continue
		var enemy_id := str((enemy_data as Dictionary).get("id", ""))
		if enemy_id.is_empty() or GameManager.defeated_enemy_ids.has(enemy_id) or GameManager.spared_enemy_ids.has(enemy_id):
			continue
		if child.has_method("is_hostile") and not bool(child.call("is_hostile")):
			continue
		var child_position := (child as Node2D).global_position
		var distance_sq := from_position.distance_squared_to(child_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_position = child_position
	return nearest_position


## Public: the global_position of the exit door in THIS zone that leads (directly,
## or via the fewest hops through the chapter's zone graph) toward target_zone_id.
## Returns Vector2.INF if there is no route (or no exit data) to point at.
func find_exit_toward_zone(target_zone_id: String) -> Vector2:
	if not ChapterFlow.active or target_zone_id.is_empty():
		return Vector2.INF
	var zone: Dictionary = ChapterFlow.current_zone()
	var current_zone_id := str(zone.get("zone_id", ""))
	if current_zone_id == target_zone_id:
		return Vector2.INF
	var edge_exits: Array = zone.get("edge_exits", []) as Array
	if edge_exits.is_empty():
		return Vector2.INF
	var next_hop := _next_hop_zone_id(current_zone_id, target_zone_id)
	if next_hop.is_empty():
		return Vector2.INF
	var map_tile_size: Vector2i = GameManager.get_map_tile_size(GameManager.get_scene_package(), background.texture)
	if map_tile_size == Vector2i.ZERO:
		return Vector2.INF
	for exit_data in edge_exits:
		if not (exit_data is Dictionary):
			continue
		var data: Dictionary = exit_data as Dictionary
		if str(data.get("leads_to", "")) != next_hop:
			continue
		var edge: String = str(data.get("edge", ""))
		var normalized: float = float(data.get("normalized", 0.5))
		if edge.is_empty():
			continue
		return _tile_to_pixel_center(_edge_exit_tile(edge, normalized, map_tile_size))
	return Vector2.INF


## BFS over the chapter's zone `connections` graph (the same topology the minimap
## draws) for the first hop from `from_zone_id` toward `target_zone_id`. Returns
## "" if unreachable or already adjacent-less.
func _next_hop_zone_id(from_zone_id: String, target_zone_id: String) -> String:
	var zones: Array = ChapterFlow.current_chapter_zones()
	var connections_by_id: Dictionary = {}
	for entry in zones:
		if entry is Dictionary:
			connections_by_id[str((entry as Dictionary).get("zone_id", ""))] = (entry as Dictionary).get("connections", []) as Array
	if not connections_by_id.has(from_zone_id) or not connections_by_id.has(target_zone_id):
		return ""
	if (connections_by_id[from_zone_id] as Array).has(target_zone_id):
		return target_zone_id
	var visited: Dictionary = {from_zone_id: true}
	var queue: Array = [[from_zone_id, ""]]  # [zone_id, first_hop_from_start]
	var head := 0
	while head < queue.size():
		var pair: Array = queue[head]
		head += 1
		var zone_id: String = pair[0]
		var first_hop: String = pair[1]
		for neighbor in (connections_by_id.get(zone_id, []) as Array):
			var neighbor_id := str(neighbor)
			if visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			var hop: String = first_hop if not first_hop.is_empty() else neighbor_id
			if neighbor_id == target_zone_id:
				return hop
			queue.append([neighbor_id, hop])
	return ""

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

	# Enemies get the same spawn safety as the player: nudge each off any solid /
	# walled-in tile to the nearest open one, and reserve tiles as we go so two
	# enemies (or an enemy and the player) never share a spawn.
	var enemy_map_size: Vector2i = tile_context.get("map_tile_size", Vector2i.ZERO) as Vector2i
	var enemy_blocked: Dictionary = (tile_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	enemy_blocked[_tile_key(_player_spawn_tile)] = true

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
		if enemy_map_size != Vector2i.ZERO:
			var spawn_info: Dictionary = (data.get("spawn", {}) as Dictionary).duplicate()
			var raw_pt: Dictionary = spawn_info.get("position_tile", {}) as Dictionary
			var raw_tile := Vector2i(int(raw_pt.get("x", 0)), int(raw_pt.get("y", 0)))
			var open_tile: Vector2i = _nearest_open_tile(raw_tile, enemy_map_size, enemy_blocked)
			enemy_blocked[_tile_key(open_tile)] = true
			spawn_info["position_tile"] = {"x": open_tile.x, "y": open_tile.y}
			data["spawn"] = spawn_info
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
			# Enemy-linked loot is granted inside BattleScene so it can be revealed
			# over that backdrop. Re-settle inventory objectives after the defeat beat
			# advances, preserving the old defeat -> collect quest ordering.
			QuestManager.notify_items_changed()
			PartyManager.notify_enemy_defeated(enemy_id)
			# BattleScene has already granted and revealed every enemy-linked drop on
			# the battle backdrop, immediately after the victory presentation.
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
		for n in range(spawn_count):
			# Always draw a tile (even for an already-collected pickup) so the RNG
			# sequence — and therefore every OTHER pickup's position — stays
			# identical across reloads; only whether we actually SPAWN it differs.
			var tile: Vector2i = _find_pickup_tile(rng, map_size, blocked, used)
			if tile == Vector2i(-1, -1):
				continue
			used["%s:%s" % [tile.x, tile.y]] = true
			var pickup_id := "%s:%s:%d" % [zone_id, str(definition.get("id", "")), n]
			if GameManager.is_item_pickup_collected(pickup_id):
				continue
			var pickup: Area2D = ItemPickupScript.new() as Area2D
			generated_props.add_child(pickup)
			pickup.setup(definition, tile, pickup_id)
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
	if _has_planned_opening_cutscene():
		return

	var actions: Array = []
	var start_tiles: Dictionary = {}
	if play_opening:
		# Legacy packages only: newer packages put opening in cutscenes as a
		# zone_enter beat with role="opening".
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

func _has_planned_opening_cutscene() -> bool:
	var package_data: Dictionary = GameManager.get_scene_package()
	var cutscenes: Array = package_data.get("cutscenes", []) as Array
	for cutscene in cutscenes:
		if not (cutscene is Dictionary):
			continue
		var data: Dictionary = cutscene as Dictionary
		if str(data.get("role", "")) != "opening":
			continue
		var trigger: Dictionary = data.get("trigger", {}) as Dictionary
		if str(trigger.get("type", "")) == "zone_enter":
			return true
	return false

# ── planned cutscenes ──────────────────────────────────────────────────────────
# Match a reported event against this zone's packaged cutscenes (CutsceneDirector)
# and play the first unplayed one. CutscenePlayer applies the pre-placed start
# tiles, then restores actors.

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
	QuestManager.yield_notifications_to_cutscene()
	if _interrupt_active_chat_for_cutscene():
		_cutscene_conversation_handoff_pending = true
		_drain_triggered_cutscenes.call_deferred()
		return
	_drain_triggered_cutscenes()

func _interrupt_active_chat_for_cutscene() -> bool:
	var chatbox := get_tree().get_first_node_in_group("active_chatbox")
	if chatbox == null or not is_instance_valid(chatbox) \
			or not chatbox.has_method("interrupt_for_cutscene"):
		return false
	return bool(chatbox.call("interrupt_for_cutscene"))

func has_pending_narrative_playback() -> bool:
	# Narrative UI uses this as an explicit priority barrier. Include the queue,
	# action phase, and CutscenePlayer's letterbox/camera cleanup phase.
	return _triggered_cutscene_active \
			or not _pending_triggered_cutscenes.is_empty() \
			or get_tree().get_first_node_in_group("active_cutscene_player") != null

func _drain_triggered_cutscenes() -> void:
	if _pending_triggered_cutscenes.is_empty():
		return
	# Wait for a calm moment: no battle, no zone transition, no other cutscene or
	# blocking UI (the opening cutscene and dialogue set ui_blocking_input). Actors
	# returning home are deliberately not blockers; their controllers preserve the
	# destination across a new cutscene and resume afterward.
	if _battle_active or _zone_advancing or _triggered_cutscene_active \
			or GameManager.ui_blocking_input:
		get_tree().create_timer(0.05).timeout.connect(_drain_triggered_cutscenes, CONNECT_ONE_SHOT)
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
	var conversation_handoff := _cutscene_conversation_handoff_pending
	_cutscene_conversation_handoff_pending = false
	var actions: Array = cutscene.get("actions", []) as Array
	var start_tiles: Dictionary = cutscene.get("start_tiles", {}) as Dictionary
	print("[Main] triggered cutscene id=%s actions=%d start_tiles=%d" % [str(cutscene.get("id", "")), actions.size(), start_tiles.size()])
	var cutscene_player: CanvasLayer = CutscenePlayerScript.new()
	add_child(cutscene_player)
	cutscene_player.cutscene_finished.connect(func() -> void:
		_triggered_cutscene_active = false
		_check_zone_cleared.call_deferred()
		_drain_triggered_cutscenes.call_deferred()
	)
	if conversation_handoff:
		cutscene_player.actor_return_finished.connect(func() -> void:
			# Quest/item ceremonies earned on the interrupted dialogue resume only
			# after the cutscene UI and letterbox have fully left the stage.
			AnnouncementCenter.set_conversation_active(false)
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
