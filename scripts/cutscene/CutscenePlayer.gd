extends CanvasLayer
## Chapter intro — cutscene mode. Plays a generated script on the live scene:
## real NPC/enemy/player actors walk, turn, speak (with emotion portraits), emote,
## attack, get hurt, die, and shake while a cinematic camera follows, framed by letterbox bars.
## The backend staging pass walks speakers next to their conversation partner;
## this player also auto-faces speaker pairs as a safety net. Esc skips.

signal cutscene_finished
signal actor_return_finished

const TYPE_SPEED := 44.0
const MOVE_SPEED_PX := 144.0
const LETTERBOX_H := 9.0
const PRESTAGE_DISTANCE_TILES := 5.0
const PRESTAGE_APPROACH_TILES := 2.0
const MOVE_CLAMP_TILES := 4  # max tiles a cutscene actor may stray from the player
const ATTACK_LUNGE_PX := 30.0
const HURT_KNOCKBACK_PX := 18.0
const EMOTE_FLOAT_PX := 18.0
const UI_COMPONENT_DIR := "res://assets/ui/cutscene_v3/components/"
const TEX_CORNER_TL := UI_COMPONENT_DIR + "corner_tl.png"
const TEX_CORNER_TR := UI_COMPONENT_DIR + "corner_tr.png"
const TEX_CORNER_BL := UI_COMPONENT_DIR + "corner_bl.png"
const TEX_CORNER_BR := UI_COMPONENT_DIR + "corner_br.png"
const TEX_EDGE_H := UI_COMPONENT_DIR + "edge_horizontal.png"
const TEX_EDGE_V := UI_COMPONENT_DIR + "edge_vertical.png"
const TEX_NAME_CAP_LEFT := UI_COMPONENT_DIR + "name_cap_left.png"
const TEX_NAME_CAP_RIGHT := UI_COMPONENT_DIR + "name_cap_right.png"
const TEX_BORDER_GEM := UI_COMPONENT_DIR + "border_gem.png"
const TEX_CONTINUE_CRYSTAL := UI_COMPONENT_DIR + "continue_crystal.png"

const NAMEPLATE_POSITION := Vector2(112, 159)
const NAMEPLATE_HEIGHT := 18.0
const NAMEPLATE_MIN_WIDTH := 86.0
const NAMEPLATE_MAX_WIDTH := 240.0
const NAMEPLATE_TEXT_PADDING := 14.0

# chat_v3 — the conversation UI's gold+cyan skin, applied over this dialogue
# block too so cutscene and NPC chat read as one system. Only the DRAWING
# swaps; the layout/logic (dynamic nameplate, narrator repositioning) stays.
# Missing assets fall back to the cutscene_v3 modular pieces.
const CHAT_V3_DIR := "res://assets/ui/chat_v3/"
const NAMEPLATE_TEXT_PADDING_V3 := 19.0  # the plaque's pointed caps are wider

const DIALOGUE_PANEL_RECT := Rect2(134, 176, 316, 68)
const NARRATOR_PANEL_TOP := 40.0

const COLOR_SPEAKER := Color(0.96, 0.88, 0.50, 1.0)

var _world: Node2D = null
var _player: Node2D = null
var _characters_root: Node2D = null
var _camera: Camera2D = null
var _player_camera: Camera2D = null

const ScrollingDialogueTextScript := preload("res://scripts/ui/ScrollingDialogueText.gd")

var _chat_v3 := false
var _actions: Array = []
var _skip: bool = false
var _accept_pressed: bool = false
var _last_speaker: String = ""
var _portrait_cache: Dictionary = {}
var _portrait_tint_cache: Dictionary = {}  # actor_id -> Color tint for body-fallback portraits
var _origin_positions: Dictionary = {}  # actor_id -> Vector2 (pre-cutscene)
var _start_tiles: Dictionary = {}  # actor_id -> {x,y}: backend pre-placement (arranged by origin)
var _blocked_tiles: Dictionary = {}
var _astar: AStarGrid2D = null  # walkable-grid pathfinding for cutscene moves
var _collision_state: Dictionary = {}  # actor -> {layer, mask}: restored on finish

# Design-space size of this scale-2 layer (512x288 at a 1024x576 viewport).
# The dialogue/title blocks are authored for a 480x270 canvas and anchored
# against this at runtime. Set in _build_ui.
var _design_size := Vector2(480, 270)

var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _dialogue_root: Control
var _dialogue_panel: Panel
var _name_plate: Panel
var _nameplate_art_root: Control
var _name_label: Label
var _portrait_frame: Control
var _portrait_rect: TextureRect
var _text_label: RichTextLabel  # ScrollingDialogueText — fixed font, scrolls when long
var _continue_marker: TextureRect
var _title_dim: ColorRect
var _title_label: Label
var _title_banner: TextureRect
var _skip_hint: Label


func play(actions: Array, world: Node2D, player: Node2D, characters_root: Node2D, start_tiles: Dictionary = {}) -> void:
	add_to_group("active_cutscene_player")
	_actions = actions
	_world = world
	_player = player
	_characters_root = characters_root
	_start_tiles = start_tiles
	layer = 70
	transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	GameManager.ui_blocking_input = true
	_blocked_tiles = GameManager.get_blocked_tiles(GameManager.get_scene_package())
	_record_origins()
	_disable_actor_collisions()
	_prestage_actors()
	_idle_all_actors()
	_build_ui()
	_setup_camera()
	_run()


func _disable_actor_collisions() -> void:
	# Cutscene movement is driven by tweens, not physics. Turn off every actor's
	# collision so a moving character can't push the player (or others) around and
	# can't snag on walls while it walks its path. Restored in _finish().
	var nodes: Array[Node] = []
	if _player != null:
		nodes.append(_player)
	if _characters_root != null:
		for child in _characters_root.get_children():
			nodes.append(child)
	for node in nodes:
		if node is CollisionObject2D:
			var body := node as CollisionObject2D
			# The player appears in both lists — record its ORIGINAL layer/mask only
			# once, or the second pass would store the already-zeroed values and
			# "restore" the player to no-collision (walking through walls).
			if _collision_state.has(body):
				continue
			_collision_state[body] = {"layer": body.collision_layer, "mask": body.collision_mask}
			if body.has_method("suspend_return_home_for_cutscene"):
				body.call("suspend_return_home_for_cutscene")
			body.collision_layer = 0
			body.collision_mask = 0


func _restore_actor_collisions() -> void:
	for body in _collision_state:
		if is_instance_valid(body) and body is CollisionObject2D:
			(body as CollisionObject2D).collision_layer = int(_collision_state[body]["layer"])
			(body as CollisionObject2D).collision_mask = int(_collision_state[body]["mask"])
	_collision_state.clear()


func _idle_actor(actor: Node2D) -> void:
	# Freeze an actor on a standing frame. The player's walk animation loops from
	# its setup and is never paused while input is blocked, so without this it
	# "walks in place" for the whole cutscene.
	if actor == null:
		return
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	if sprite != null:
		sprite.frame = 0
		sprite.pause()


func _idle_all_actors() -> void:
	_idle_actor(_player)
	for actor_id in _cutscene_participants():
		_idle_actor(_find_actor(actor_id))


func _record_origins() -> void:
	_origin_positions["player"] = _player.global_position
	for child in _characters_root.get_children():
		if not (child is Node2D):
			continue
		for key in ["npc_data", "enemy_data"]:
			var data: Variant = child.get(key)
			if data is Dictionary:
				var actor_id: String = str((data as Dictionary).get("id", ""))
				if not actor_id.is_empty():
					var origin := (child as Node2D).global_position
					if child.has_method("get_return_home_destination"):
						origin = child.call("get_return_home_destination") as Vector2
					_origin_positions[actor_id] = origin


# On-screen tile offsets around the player, ordered by preference (sides and
# slightly below first). The 480x270 viewport at 36px/tile shows ~±6 x, ±3 y.
const PRESTAGE_RING := [
	Vector2i(3, 1), Vector2i(-3, 1), Vector2i(4, 0), Vector2i(-4, 0),
	Vector2i(3, -2), Vector2i(-3, -2), Vector2i(2, 2), Vector2i(-2, 2),
	Vector2i(5, 1), Vector2i(-5, 1), Vector2i(4, 2), Vector2i(-4, 2),
	Vector2i(0, -3), Vector2i(5, -1), Vector2i(-5, -1),
]


func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)


func _prestage_from_start_tiles() -> bool:
	# Preferred path: the backend pre-placed everyone near the action and arranged
	# them by where they naturally come from (origin direction). Treat those tiles
	# as preferences rather than guarantees: malformed/partial data can contain
	# duplicates, which previously put multiple actors on the exact same spot.
	if _start_tiles.is_empty():
		return false
	var player_tile := _tile_of(_player.global_position)
	if _start_tiles.has("player"):
		var pt: Dictionary = _start_tiles["player"] as Dictionary
		var authored_player := Vector2i(int(pt.get("x", player_tile.x)), int(pt.get("y", player_tile.y)))
		if _is_open(authored_player):
			player_tile = authored_player
			_player.global_position = _tile_to_world(player_tile)
	var used: Dictionary = {_tile_key(player_tile): true}
	var ring_index := 0
	for actor_id in _cutscene_participants():
		var actor: Node2D = _find_actor(actor_id)
		if actor == null:
			continue
		var actor_tile := _tile_of(actor.global_position)
		var tile := actor_tile
		var has_authored_tile := _start_tiles.has(actor_id) and _start_tiles[actor_id] is Dictionary
		if has_authored_tile:
			var st: Dictionary = _start_tiles[actor_id] as Dictionary
			tile = Vector2i(int(st.get("x", actor_tile.x)), int(st.get("y", actor_tile.y)))

		var tile_is_usable := _is_open(tile) and not used.has(_tile_key(tile))
		if not tile_is_usable:
			# A missing/duplicate authored tile may still have a good live position.
			var current_is_usable := _is_open(actor_tile) \
					and not used.has(_tile_key(actor_tile)) \
					and Vector2(player_tile).distance_to(Vector2(actor_tile)) <= PRESTAGE_DISTANCE_TILES
			if current_is_usable:
				tile = actor_tile
			else:
				tile = _pick_prestage_tile(player_tile, used, ring_index)
				ring_index += 1
			if has_authored_tile:
				print("[Cutscene] adjusted occupied start_tile for %s -> %s" % [actor_id, tile])

		used[_tile_key(tile)] = true
		actor.global_position = _tile_to_world(tile)
		_face_actor_toward(actor, player_tile)
		print("[Cutscene] pre-placed %s at %s (backend start_tile)" % [actor_id, tile])
	return true


func _prestage_actors() -> void:
	# Every actor the script references should already be on screen near the
	# player when the cutscene starts — no waiting for someone to walk in from
	# off-screen. Prefer backend-arranged start tiles; otherwise teleport
	# participants to free tiles in a ring around the player. Either way they keep
	# their script and walk home afterwards.
	if _prestage_from_start_tiles():
		return
	var player_tile := _tile_of(_player.global_position)
	var used: Dictionary = {_tile_key(player_tile): true}
	var ring_index: int = 0

	for actor_id in _cutscene_participants():
		var actor: Node2D = _find_actor(actor_id)
		if actor == null:
			continue
		var actor_tile := _tile_of(actor.global_position)
		# Already on screen near the player and not stacked on someone — leave it.
		if Vector2(player_tile).distance_to(Vector2(actor_tile)) <= PRESTAGE_DISTANCE_TILES \
				and not used.has(_tile_key(actor_tile)):
			used[_tile_key(actor_tile)] = true
			continue

		var placed: Vector2i = _pick_prestage_tile(player_tile, used, ring_index)
		ring_index += 1
		used[_tile_key(placed)] = true
		actor.global_position = Vector2(placed) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
		_face_actor_toward(actor, player_tile)
		print("[Cutscene] prestaged %s near player at %s" % [actor_id, placed])


func _cutscene_participants() -> Array[String]:
	# Unique actor ids referenced by the script, in first-appearance order,
	# excluding the player and the narrator.
	var seen: Dictionary = {}
	var ordered: Array[String] = []
	for action in _actions:
		if not (action is Dictionary):
			continue
		for key in ["actor", "target", "source"]:
			var actor_id: String = str((action as Dictionary).get(key, "")).strip_edges()
			if actor_id.is_empty() or actor_id == "player" or actor_id == "narrator":
				continue
			if not seen.has(actor_id):
				seen[actor_id] = true
				ordered.append(actor_id)
	return ordered


func _pick_prestage_tile(player_tile: Vector2i, used: Dictionary, start_index: int) -> Vector2i:
	# Prefer the authored on-screen ring; fall back to a spiral search.
	for offset_index in range(PRESTAGE_RING.size()):
		var offset: Vector2i = PRESTAGE_RING[(start_index + offset_index) % PRESTAGE_RING.size()]
		var candidate: Vector2i = player_tile + offset
		if _is_open(candidate) and not used.has(_tile_key(candidate)):
			return candidate
	for radius in range(1, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if max(abs(dx), abs(dy)) != radius:
					continue
				var candidate := player_tile + Vector2i(dx, dy)
				if _is_open(candidate) and not used.has(_tile_key(candidate)):
					return candidate
	return player_tile + Vector2i(2, 2)


func _face_actor_toward(actor: Node2D, target_tile: Vector2i) -> void:
	var delta: Vector2 = Vector2(target_tile) - Vector2(_tile_of(actor.global_position))
	var direction: String
	if abs(delta.x) >= abs(delta.y):
		direction = "right" if delta.x > 0 else "left"
	else:
		direction = "down" if delta.y > 0 else "up"
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % direction):
		sprite.play("walk_%s" % direction)
		sprite.pause()


func _tile_of(world_position: Vector2) -> Vector2i:
	return Vector2i(int(world_position.x / GameManager.TILE_SIZE), int(world_position.y / GameManager.TILE_SIZE))


func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]


func _is_open(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and not _blocked_tiles.has(_tile_key(tile))


func _occupied_actor_tiles(exclude: Node2D = null) -> Dictionary:
	var occupied: Dictionary = {}
	if _player != null and is_instance_valid(_player) and _player != exclude and _player.visible:
		occupied[_tile_key(_tile_of(_player.global_position))] = true
	if _characters_root == null:
		return occupied
	for child in _characters_root.get_children():
		if child is Node2D and child != exclude and (child as Node2D).visible:
			occupied[_tile_key(_tile_of((child as Node2D).global_position))] = true
	return occupied


func _nearest_unoccupied_tile(preferred: Vector2i, occupied: Dictionary) -> Vector2i:
	if _is_open(preferred) and not occupied.has(_tile_key(preferred)):
		return preferred
	for radius in range(1, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if max(abs(dx), abs(dy)) != radius:
					continue
				var candidate := preferred + Vector2i(dx, dy)
				if _is_open(candidate) and not occupied.has(_tile_key(candidate)):
					return candidate
	return preferred


func _map_tile_size() -> Vector2i:
	var bg: Texture2D = null
	if _world != null and _world.has_node("World/Background"):
		var node: Node = _world.get_node("World/Background")
		if node is Sprite2D:
			bg = (node as Sprite2D).texture
	return GameManager.get_map_tile_size(GameManager.get_scene_package(), bg)


func _max_blocked_extent() -> Vector2i:
	# Fallback map bounds derived from the blocked-tile keys ("x:y").
	var mx := 0
	var my := 0
	for key in _blocked_tiles:
		var parts: PackedStringArray = str(key).split(":")
		if parts.size() >= 2:
			mx = maxi(mx, int(parts[0]))
			my = maxi(my, int(parts[1]))
	return Vector2i(mx + 2, my + 2)


func _ensure_astar() -> void:
	# Walkable-grid A* so cutscene actors path around obstacles instead of sliding
	# straight through walls. Built lazily from the scene's blocked tiles.
	if _astar != null:
		return
	var size: Vector2i = _map_tile_size()
	if size.x <= 0 or size.y <= 0:
		size = _max_blocked_extent()  # fallback so A* still builds
	if size.x <= 0 or size.y <= 0:
		return
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in range(size.y):
		for x in range(size.x):
			var tile := Vector2i(x, y)
			if not _is_open(tile):
				_astar.set_point_solid(tile, true)


func _nearest_open_tile(tile: Vector2i) -> Vector2i:
	if _astar == null or not _astar.is_in_boundsv(tile) or not _astar.is_point_solid(tile):
		return tile
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := tile + Vector2i(dx, dy)
				if _astar.is_in_boundsv(candidate) and not _astar.is_point_solid(candidate):
					return candidate
	return tile


func _path_tiles(from_tile: Vector2i, to_tile: Vector2i) -> Array:
	# A* tile path from -> to (excludes the start tile). Falls back to a direct
	# step when no grid/path is available.
	_ensure_astar()
	if _astar == null or not _astar.is_in_boundsv(from_tile) or not _astar.is_in_boundsv(to_tile):
		return [to_tile]
	var goal: Vector2i = _nearest_open_tile(to_tile)
	if _astar.is_point_solid(from_tile) or _astar.is_point_solid(goal):
		return [goal]
	var path: Array[Vector2i] = _astar.get_id_path(from_tile, goal)
	if path.size() <= 1:
		return [goal]
	return path.slice(1)  # drop the start tile


func _clamp_tile_near_player(target_tile: Vector2i, max_tiles: int) -> Vector2i:
	var player_tile := _tile_of(_player.global_position)
	var offset := target_tile - player_tile
	if abs(offset.x) <= max_tiles and abs(offset.y) <= max_tiles:
		return target_tile
	# Pull the target in along the same direction, then snap to an open tile.
	var clamped := Vector2i(
		player_tile.x + clampi(offset.x, -max_tiles, max_tiles),
		player_tile.y + clampi(offset.y, -max_tiles, max_tiles),
	)
	if _is_open(clamped):
		return clamped
	for radius in range(1, 4):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate := clamped + Vector2i(dx, dy)
				if _is_open(candidate) and abs(candidate.x - player_tile.x) <= max_tiles + 1 \
						and abs(candidate.y - player_tile.y) <= max_tiles + 1:
					return candidate
	return clamped


func _build_ui() -> void:
	# Design units: the layer runs at scale 2, so the design canvas is half the
	# real viewport (512x270 at 1024x540). Width-dependent placements below use
	# this instead of the historical fixed 480.
	var viewport_size: Vector2 = Vector2(480, 270)
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size / 2.0
	_design_size = viewport_size
	var design_w := viewport_size.x
	var design_h := viewport_size.y

	_top_bar = ColorRect.new()
	_top_bar.color = Color(0, 0, 0, 1)
	_top_bar.position = Vector2(0, -LETTERBOX_H)
	_top_bar.size = Vector2(viewport_size.x, LETTERBOX_H)
	add_child(_top_bar)

	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color(0, 0, 0, 1)
	_bottom_bar.position = Vector2(0, viewport_size.y)
	_bottom_bar.size = Vector2(viewport_size.x, LETTERBOX_H)
	add_child(_bottom_bar)

	var bars := create_tween()
	bars.tween_property(_top_bar, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	bars.parallel().tween_property(_bottom_bar, "position:y", viewport_size.y - LETTERBOX_H, 0.6).set_trans(Tween.TRANS_CUBIC)

	_skip_hint = UiKit.make_label("ESC  Bỏ qua  ›", 7, Color(0.93, 0.88, 0.75, 0.72))
	_skip_hint.position = Vector2(design_w - 130.0, 8)
	_skip_hint.size = Vector2(120, 12)
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_skip_hint)

	# ── cinematic dialogue block: large portrait + modular ornate frame ──
	# The block is authored for a 480x270 canvas; keep it horizontally centered
	# and bottom-anchored on wider/taller design spaces (repositioned per line
	# in _say as well, for the narrator variant).
	_dialogue_root = Control.new()
	_dialogue_root.position = Vector2((design_w - 480.0) * 0.5, design_h - 270.0)
	_dialogue_root.visible = false
	add_child(_dialogue_root)

	_portrait_frame = Control.new()
	_portrait_frame.position = Vector2(0, 62)
	_portrait_frame.size = Vector2(158, 208)
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.z_index = 2
	_dialogue_root.add_child(_portrait_frame)

	_portrait_rect = TextureRect.new()
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.position = Vector2(0, 0)
	_portrait_rect.size = _portrait_frame.size
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait_rect)

	_chat_v3 = ResourceLoader.exists(CHAT_V3_DIR + "dialogue_panel.png")
	var panel_rect := DIALOGUE_PANEL_RECT
	_dialogue_panel = Panel.new()
	_dialogue_panel.position = panel_rect.position
	_dialogue_panel.size = panel_rect.size
	if _chat_v3:
		# The chat_v3 panel art (damask + gold border + cyan gems) drawn at its
		# TRUE baked aspect, as a CHILD of the panel so the narrator variant's
		# repositioning carries it along. Bottom-aligned with a slight bleed;
		# the extra height rises behind the nameplate.
		_dialogue_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var art_w := panel_rect.size.x + 8.0
		var art_h := art_w * (352.0 / 1474.0)
		var art := TextureRect.new()
		art.texture = load(CHAT_V3_DIR + "dialogue_panel.png") as Texture2D
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size = Vector2(art_w, art_h)
		art.position = Vector2(-4.0, panel_rect.size.y + 2.0 - art_h)
		_dialogue_panel.add_child(art)
	else:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.025, 0.035, 0.085, 0.94)
		panel_style.set_corner_radius_all(2)
		_dialogue_panel.add_theme_stylebox_override("panel", panel_style)
	_dialogue_root.add_child(_dialogue_panel)
	if not _chat_v3:
		_add_modular_frame(_dialogue_root, panel_rect)

	var name_rect := Rect2(NAMEPLATE_POSITION, Vector2(NAMEPLATE_MIN_WIDTH, NAMEPLATE_HEIGHT))
	_name_plate = Panel.new()
	_name_plate.position = name_rect.position
	_name_plate.size = name_rect.size
	if _chat_v3:
		# The chat_v3 plaque art carries its own navy fill.
		_name_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var name_style := StyleBoxFlat.new()
		name_style.bg_color = Color(0.035, 0.045, 0.105, 0.98)
		_name_plate.add_theme_stylebox_override("panel", name_style)
	_dialogue_root.add_child(_name_plate)
	_nameplate_art_root = Control.new()
	_nameplate_art_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_root.add_child(_nameplate_art_root)
	_add_nameplate_art(_nameplate_art_root, name_rect)

	_name_label = UiKit.make_title("", 10, Color(0.98, 0.88, 0.63, 1.0))
	_name_label.position = Vector2(14, 0)
	_name_label.size = Vector2(58, 18)
	_name_label.clip_text = true
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.z_index = 3
	_name_plate.add_child(_name_label)

	# Long lines never shrink or overflow — the passage scrolls (intro slides
	# mechanics: auto-follow the typewriter, wheel/drag to re-read).
	_text_label = ScrollingDialogueTextScript.new()
	_text_label.add_theme_font_override("normal_font", UiKit.body_font())
	_text_label.add_theme_font_size_override("normal_font_size", 8)
	_text_label.add_theme_color_override("default_color", Color(0.95, 0.89, 0.76, 1.0))
	_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_text_label.add_theme_constant_override("shadow_offset_x", 1)
	_text_label.add_theme_constant_override("shadow_offset_y", 1)
	_text_label.add_theme_constant_override("line_separation", 2)
	_text_label.z_index = 3
	_text_label.set_area(Rect2(18, 9, 270, 50), true)
	_dialogue_panel.add_child(_text_label)

	_continue_marker = _make_texture_rect(
		CHAT_V3_DIR + "continue_gem.png" if _chat_v3 else TEX_CONTINUE_CRYSTAL,
		Rect2(291, 37, 12, 24))
	_continue_marker.visible = false
	_continue_marker.z_index = 3
	_dialogue_panel.add_child(_continue_marker)

	# ── title card ──
	_title_dim = ColorRect.new()
	_title_dim.color = Color(0, 0, 0, 0.0)
	_title_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_dim)

	_title_banner = UiKit.make_banner_rect(180.0)
	if _title_banner != null:
		_title_banner.position = Vector2((design_w - 180.0) * 0.5, design_h * 0.5 - 57.0)
		_title_banner.modulate.a = 0.0
		add_child(_title_banner)

	_title_label = UiKit.make_title("", 17, COLOR_SPEAKER)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(20, design_h * 0.5 - 11.0)
	_title_label.size = Vector2(design_w - 40.0, 60)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.modulate.a = 0.0
	add_child(_title_label)


func _make_texture_rect(path: String, rect: Rect2, stretch_mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load(path) as Texture2D
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	texture_rect.stretch_mode = stretch_mode
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if stretch_mode == TextureRect.STRETCH_TILE:
		texture_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _add_modular_frame(parent: Control, rect: Rect2) -> void:
	var corner_size := Vector2(17, 16)
	var corners := [
		[TEX_CORNER_TL, rect.position - Vector2(2, 2)],
		[TEX_CORNER_TR, Vector2(rect.end.x - corner_size.x + 2, rect.position.y - 2)],
		[TEX_CORNER_BL, Vector2(rect.position.x - 2, rect.end.y - corner_size.y + 2)],
		[TEX_CORNER_BR, rect.end - corner_size + Vector2(2, 2)],
	]
	for corner_data in corners:
		parent.add_child(_make_texture_rect(corner_data[0], Rect2(corner_data[1], corner_size)))

	# Generated corner arms resolve to exactly two authored pixels. Keep the
	# repeated edges on those same axes so the joins do not step or widen.
	var horizontal_rect := Rect2(rect.position.x + 10, rect.position.y - 1, rect.size.x - 20, 2)
	_add_repeated_edge(parent, TEX_EDGE_H, horizontal_rect, true)
	horizontal_rect.position.y = rect.end.y - 1
	_add_repeated_edge(parent, TEX_EDGE_H, horizontal_rect, true)

	var vertical_rect := Rect2(rect.position.x - 1, rect.position.y + 10, 2, rect.size.y - 20)
	_add_repeated_edge(parent, TEX_EDGE_V, vertical_rect, false)
	vertical_rect.position.x = rect.end.x - 1
	_add_repeated_edge(parent, TEX_EDGE_V, vertical_rect, false)

	var gem_size := Vector2(20, 8)
	var gem_x := rect.position.x + (rect.size.x - gem_size.x) * 0.5
	parent.add_child(_make_texture_rect(TEX_BORDER_GEM, Rect2(gem_x, rect.position.y - 3, gem_size.x, gem_size.y)))
	parent.add_child(_make_texture_rect(TEX_BORDER_GEM, Rect2(gem_x, rect.end.y - 5, gem_size.x, gem_size.y)))


func _add_nameplate_art(parent: Control, rect: Rect2) -> void:
	if _chat_v3:
		var plaque := load(CHAT_V3_DIR + "nameplate.png") as Texture2D
		if plaque != null:
			# 3-slice: the pointed gold caps (cyan gem on the right) keep their
			# true aspect at any name width; only the straight middle stretches.
			_add_three_slice(parent, plaque, rect.grow_individual(2.0, 3.0, 2.0, 3.0), 0.16, 0.22)
			return
	_add_repeated_edge(parent, TEX_EDGE_H, Rect2(rect.position.x + 8, rect.position.y, rect.size.x - 16, 2), true)
	_add_repeated_edge(parent, TEX_EDGE_H, Rect2(rect.position.x + 8, rect.end.y - 2, rect.size.x - 16, 2), true)
	parent.add_child(_make_texture_rect(TEX_NAME_CAP_LEFT, Rect2(rect.position.x - 6, rect.position.y - 2, 14, 22)))
	parent.add_child(_make_texture_rect(TEX_NAME_CAP_RIGHT, Rect2(rect.end.x - 8, rect.position.y - 2, 14, 22)))


func _add_three_slice(parent: Control, texture: Texture2D, rect: Rect2, cap_frac_l: float, cap_frac_r: float) -> void:
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var cap_l_tex := tw * cap_frac_l
	var cap_r_tex := tw * cap_frac_r
	var cap_l_w := rect.size.y * cap_l_tex / th
	var cap_r_w := rect.size.y * cap_r_tex / th
	var mid_w := maxf(1.0, rect.size.x - cap_l_w - cap_r_w)
	var pieces := [
		[Rect2(0, 0, cap_l_tex, th), Rect2(rect.position, Vector2(cap_l_w, rect.size.y))],
		[Rect2(cap_l_tex, 0, tw - cap_l_tex - cap_r_tex, th),
			Rect2(rect.position + Vector2(cap_l_w, 0), Vector2(mid_w, rect.size.y))],
		[Rect2(tw - cap_r_tex, 0, cap_r_tex, th),
			Rect2(rect.position + Vector2(rect.size.x - cap_r_w, 0), Vector2(cap_r_w, rect.size.y))],
	]
	for piece in pieces:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = piece[0] as Rect2
		var slice := TextureRect.new()
		slice.texture = atlas
		slice.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slice.stretch_mode = TextureRect.STRETCH_SCALE
		slice.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		slice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slice.position = (piece[1] as Rect2).position
		slice.size = (piece[1] as Rect2).size
		parent.add_child(slice)


func _layout_nameplate(speaker: String) -> void:
	var font := _name_label.get_theme_font("font")
	var font_size := _name_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(
		speaker,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
	).x
	# The chat_v3 plaque's pointed caps eat more horizontal room than the flat
	# cutscene_v3 caps did — measure and inset with the wider padding.
	var pad := NAMEPLATE_TEXT_PADDING_V3 if _chat_v3 else NAMEPLATE_TEXT_PADDING
	var plate_width := clampf(
		ceilf(text_width) + pad * 2.0,
		NAMEPLATE_MIN_WIDTH,
		NAMEPLATE_MAX_WIDTH,
	)
	var name_rect := Rect2(NAMEPLATE_POSITION, Vector2(plate_width, NAMEPLATE_HEIGHT))
	_name_plate.position = name_rect.position
	_name_plate.size = name_rect.size
	_name_label.position = Vector2(pad, 0)
	_name_label.size = Vector2(plate_width - pad * 2.0, NAMEPLATE_HEIGHT)

	for child in _nameplate_art_root.get_children():
		child.free()
	_add_nameplate_art(_nameplate_art_root, name_rect)


func _add_repeated_edge(parent: Control, path: String, rect: Rect2, horizontal: bool) -> void:
	var tile_length := 48.0
	var overlap := 0.5
	var total := rect.size.x if horizontal else rect.size.y
	var offset := 0.0
	while offset < total:
		var length := minf(tile_length, total - offset)
		var tile_rect: Rect2
		if horizontal:
			tile_rect = Rect2(rect.position + Vector2(offset, 0), Vector2(length + overlap, rect.size.y))
		else:
			tile_rect = Rect2(rect.position + Vector2(0, offset), Vector2(rect.size.x, length + overlap))
		parent.add_child(_make_texture_rect(path, tile_rect, TextureRect.STRETCH_SCALE))
		offset += tile_length


func _setup_camera() -> void:
	_player_camera = _player.get("camera") as Camera2D
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false
	if _player_camera != null:
		_camera.global_position = _player_camera.get_screen_center_position()
		_camera.limit_left = _player_camera.limit_left
		_camera.limit_top = _player_camera.limit_top
		_camera.limit_right = _player_camera.limit_right
		_camera.limit_bottom = _player_camera.limit_bottom
	else:
		_camera.global_position = _player.global_position
	_world.add_child(_camera)
	_camera.make_current()


func _run() -> void:
	for action in _actions:
		if _skip:
			break
		if not (action is Dictionary):
			continue
		await _execute(action as Dictionary)
	await _finish()


func _execute(action: Dictionary) -> void:
	match str(action.get("type", "")):
		"title":
			await _do_title(str(action.get("text", "")), float(action.get("seconds", 2.5)))
		"wait":
			await _do_wait(float(action.get("seconds", 1.0)))
		"camera":
			await _do_camera(str(action.get("actor", "")), float(action.get("seconds", 1.2)))
		"move":
			await _do_move(str(action.get("actor", "")), action.get("to", {}) as Dictionary)
		"face":
			_do_face(str(action.get("actor", "")), str(action.get("direction", "down")))
			# Keep _execute awaitable even when this instantaneous action is the
			# final/only beat in a cutscene.
			await get_tree().process_frame
		"say":
			await _do_say(action)
		"attack":
			await _do_attack(
				str(action.get("actor", "")),
				str(action.get("target", "")),
				str(action.get("style", "lunge")),
				float(action.get("seconds", 0.55))
			)
		"hurt":
			await _do_hurt(
				str(action.get("actor", "")),
				str(action.get("source", "")),
				str(action.get("severity", "medium")),
				float(action.get("seconds", 0.65))
			)
		"emote":
			await _do_emote(
				str(action.get("actor", "")),
				str(action.get("emotion", "alert")),
				float(action.get("seconds", 0.9))
			)
		"shake":
			await _do_shake(
				str(action.get("actor", "")),
				float(action.get("seconds", 0.45)),
				float(action.get("strength", 5.0))
			)
		"die":
			await _do_die(str(action.get("actor", "")))
		"dead":
			await _do_die(str(action.get("actor", "")))


func _find_actor(actor_id: String) -> Node2D:
	if actor_id == "player":
		return _player
	if _characters_root == null:
		return null
	for child in _characters_root.get_children():
		if not (child is Node2D):
			continue
		var data: Variant = child.get("npc_data")
		if data is Dictionary and str((data as Dictionary).get("id", "")) == actor_id:
			return child
		data = child.get("enemy_data")
		if data is Dictionary and str((data as Dictionary).get("id", "")) == actor_id:
			return child
	return null


func _actor_anim_sprite(actor: Node2D) -> AnimatedSprite2D:
	return actor.get("anim_sprite") as AnimatedSprite2D if actor != null else null


# ── speaker portraits ─────────────────────────────────────────────────────────


func _speaker_portrait(actor_id: String, emotion: String) -> Texture2D:
	var normalized: String = _normalize_emotion(emotion)
	var cache_key := "%s|%s" % [actor_id, normalized]
	if _portrait_cache.has(cache_key):
		return _portrait_cache[cache_key]
	var texture: Texture2D = _resolve_portrait(actor_id, normalized)
	_portrait_cache[cache_key] = texture
	return texture


func _normalize_emotion(emotion: String) -> String:
	# Mirrors ChatBox._normalize_emotion so cutscene and NPC chat portraits
	# behave identically.
	match emotion.strip_edges().to_lower():
		"happy", "joy", "joyful", "pleased", "relieved":
			return "happy"
		"angry", "anger", "mad", "irritated", "annoyed":
			return "angry"
		"sad", "sorrow", "worried", "wary", "uneasy", "haunted", "tired", "afraid", "scared":
			return "sad"
		_:
			return "neutral"


func _resolve_portrait(actor_id: String, emotion: String) -> Texture2D:
	var package: Dictionary = GameManager.get_scene_package()
	var characters: Dictionary = package.get("characters", {}) as Dictionary

	if actor_id == "player":
		var main_character: Variant = characters.get("main_character", {})
		if main_character is Dictionary:
			var generated := _emotion_portrait(main_character as Dictionary, emotion)
			if generated != null:
				return generated
		return _sheet_frame(GameManager.load_texture(GameManager.get_player_sprite_path()))

	for npc in characters.get("npcs", []) as Array:
		if not (npc is Dictionary) or str((npc as Dictionary).get("id", "")) != actor_id:
			continue
		var generated := _emotion_portrait(npc as Dictionary, emotion)
		if generated != null:
			return generated
		# No generated emotion portrait — fall back to THIS character's own
		# sprite (the one walking on the map), never a generic stranger portrait.
		var sheet_file: String = str((npc as Dictionary).get("sprite_sheet_file", ""))
		if not sheet_file.is_empty() and sheet_file != "<null>":
			var frame: Texture2D = _sheet_frame(GameManager.load_texture(GameManager.get_scene_asset_path(sheet_file)))
			if frame != null:
				return frame
		# Sheet-less NPC: on the map it renders as the blue-tinted default body,
		# so the portrait mirrors exactly that (tint applied in _do_say).
		_portrait_tint_cache[actor_id] = Color(0.78, 0.86, 1.0)
		return _sheet_frame(GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH))

	var enemies: Dictionary = package.get("enemies", {}) as Dictionary
	for enemy in enemies.get("roster", []) as Array:
		if enemy is Dictionary and str((enemy as Dictionary).get("id", "")) == actor_id:
			var portrait_file: String = str((enemy as Dictionary).get("battle_portrait_file", ""))
			if not portrait_file.is_empty():
				var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(portrait_file))
				if texture != null:
					return texture
			var sheet: String = str((enemy as Dictionary).get("sprite_sheet_file", ""))
			if not sheet.is_empty():
				return _sheet_frame(GameManager.load_texture(GameManager.get_scene_asset_path(sheet)))
	return null


func _emotion_portrait(character: Dictionary, emotion: String) -> Texture2D:
	var emotion_info: Variant = character.get("emotion_portraits")
	if not (emotion_info is Dictionary):
		return null
	var portraits: Array = (emotion_info as Dictionary).get("portraits", []) as Array
	for wanted in [emotion, "neutral"]:
		for portrait in portraits:
			if portrait is Dictionary and str((portrait as Dictionary).get("emotion", "")) == wanted:
				var texture := GameManager.load_texture(
					GameManager.get_scene_asset_path(str((portrait as Dictionary).get("file", "")))
				)
				if texture != null:
					return texture
	return null


func _sheet_frame(sheet: Texture2D) -> Texture2D:
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
	return atlas


# ── actions ───────────────────────────────────────────────────────────────────


func _do_title(text: String, seconds: float) -> void:
	if text.is_empty():
		return
	_title_label.text = text
	var tween := create_tween()
	tween.tween_property(_title_dim, "color:a", 0.7, 0.5)
	tween.parallel().tween_property(_title_label, "modulate:a", 1.0, 0.9)
	if _title_banner != null:
		_title_banner.position.y = _design_size.y * 0.5 - 51.0
		tween.parallel().tween_property(_title_banner, "modulate:a", 1.0, 0.9)
		tween.parallel().tween_property(_title_banner, "position:y", _design_size.y * 0.5 - 57.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	await _do_wait(seconds)
	var out := create_tween()
	out.tween_property(_title_dim, "color:a", 0.0, 0.5)
	out.parallel().tween_property(_title_label, "modulate:a", 0.0, 0.5)
	if _title_banner != null:
		out.parallel().tween_property(_title_banner, "modulate:a", 0.0, 0.5)
	await out.finished


func _do_wait(seconds: float) -> void:
	var remaining: float = clampf(seconds, 0.0, 6.0)
	while remaining > 0.0 and not _skip:
		await get_tree().process_frame
		remaining -= get_process_delta_time()


func _do_camera(actor_id: String, seconds: float) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or _camera == null:
		return
	var tween := create_tween()
	tween.tween_property(_camera, "global_position", actor.global_position, clampf(seconds, 0.3, 3.0))\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _dir_name(delta: Vector2) -> String:
	if abs(delta.x) >= abs(delta.y):
		return "right" if delta.x > 0 else "left"
	return "down" if delta.y > 0 else "up"


func _play_walk(sprite: AnimatedSprite2D, direction: String) -> void:
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % direction):
		sprite.play("walk_%s" % direction)


func _do_move(actor_id: String, to_tile: Dictionary) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or to_tile.is_empty():
		return
	var requested_tile := Vector2i(int(to_tile.get("x", 0)), int(to_tile.get("y", 0)))
	var start_tile := _tile_of(actor.global_position)
	var occupied := _occupied_actor_tiles(actor)
	var target_tile := requested_tile
	if occupied.has(_tile_key(requested_tile)):
		# If the actor is already beside the requested conversation/attack point,
		# staying put is less disruptive than hopping to an arbitrary neighbour.
		var delta := requested_tile - start_tile
		if maxi(abs(delta.x), abs(delta.y)) <= 1 and _is_open(start_tile):
			target_tile = start_tile
		else:
			target_tile = _nearest_unoccupied_tile(requested_tile, occupied)
	elif not _is_open(requested_tile):
		target_tile = _nearest_unoccupied_tile(requested_tile, occupied)
	if target_tile != requested_tile:
		print("[Cutscene] adjusted occupied move target for %s: %s -> %s" % [actor_id, requested_tile, target_tile])
	if target_tile == start_tile:
		return
	# Walk the A* path tile-by-tile so the actor goes around walls/objects rather
	# than sliding straight through them. The backend already keeps targets sane.
	var path: Array = _path_tiles(start_tile, target_tile)
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	for step_tile in path:
		var target: Vector2 = Vector2(step_tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
		var distance: float = actor.global_position.distance_to(target)
		if distance < 1.0:
			continue
		var direction: Vector2 = (target - actor.global_position).normalized()
		var anim_direction: String
		if abs(direction.x) >= abs(direction.y):
			anim_direction = "right" if direction.x > 0 else "left"
		else:
			anim_direction = "down" if direction.y > 0 else "up"
		if actor.has_method("face_direction"):
			actor.call("face_direction", anim_direction)
		if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % anim_direction):
			sprite.play("walk_%s" % anim_direction)
		var duration: float = distance / MOVE_SPEED_PX
		var tween := create_tween()
		tween.tween_property(actor, "global_position", target, duration)
		# The camera glides with the walking character so moves stay on screen.
		if _camera != null:
			var follow := create_tween()
			follow.tween_property(_camera, "global_position", target, duration)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	if sprite != null:
		sprite.pause()


func _do_face(actor_id: String, direction: String) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor != null and actor.has_method("face_direction"):
		actor.call("face_direction", direction)
		return
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % direction):
		sprite.play("walk_%s" % direction)
		sprite.pause()


func _do_attack(actor_id: String, target_id: String, style: String, seconds: float) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or not actor.visible:
		return
	var target: Node2D = _find_actor(target_id)
	var direction := Vector2.DOWN
	if target != null and target.visible:
		direction = target.global_position - actor.global_position
	if direction.length() < 1.0:
		direction = _facing_vector(actor)
	direction = direction.normalized()
	_do_face(actor_id, _dir_name(direction))

	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	_play_walk(sprite, _dir_name(direction))
	var original_position: Vector2 = actor.global_position
	var original_scale: Vector2 = actor.scale
	var duration: float = clampf(seconds, 0.25, 1.4)
	var lunge_distance := ATTACK_LUNGE_PX
	if style in ["shoot", "cast"]:
		lunge_distance = 10.0
	var lunge_position := original_position + direction * lunge_distance

	var tween := create_tween()
	tween.tween_property(actor, "global_position", lunge_position, duration * 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(actor, "scale", original_scale * 1.08, duration * 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor, "global_position", original_position, duration * 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(actor, "scale", original_scale, duration * 0.35)
	await tween.finished
	actor.global_position = original_position
	actor.scale = original_scale
	if sprite != null:
		sprite.pause()


func _do_hurt(actor_id: String, source_id: String, severity: String, seconds: float) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or not actor.visible:
		return
	var source: Node2D = _find_actor(source_id)
	var away := Vector2.DOWN
	if source != null and source.visible:
		away = actor.global_position - source.global_position
	if away.length() < 1.0:
		away = _facing_vector(actor)
	away = away.normalized()

	var original_position: Vector2 = actor.global_position
	var original_modulate: Color = actor.modulate
	var original_scale: Vector2 = actor.scale
	var duration: float = clampf(seconds, 0.25, 1.5)
	var knockback := HURT_KNOCKBACK_PX
	if severity == "light":
		knockback *= 0.55
	elif severity == "heavy":
		knockback *= 1.55

	var tween := create_tween()
	tween.tween_property(actor, "global_position", original_position + away * knockback, duration * 0.25)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(actor, "modulate", Color(1.0, 0.22, 0.22, original_modulate.a), duration * 0.16)
	tween.parallel().tween_property(actor, "scale", Vector2(original_scale.x * 1.05, original_scale.y * 0.92), duration * 0.16)
	tween.tween_property(actor, "global_position", original_position, duration * 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(actor, "modulate", original_modulate, duration * 0.35)
	tween.parallel().tween_property(actor, "scale", original_scale, duration * 0.35)
	await tween.finished
	actor.global_position = original_position
	actor.modulate = original_modulate
	actor.scale = original_scale


func _do_emote(actor_id: String, emotion: String, seconds: float) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or not actor.visible:
		return
	var marker := Label.new()
	marker.text = _emote_symbol(emotion)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override("font_size", 18)
	marker.add_theme_color_override("font_color", _emote_color(emotion))
	marker.position = Vector2(-32, -58)
	marker.size = Vector2(64, 24)
	marker.z_index = 60
	marker.modulate.a = 0.0
	actor.add_child(marker)

	var original_scale: Vector2 = actor.scale
	var duration: float = clampf(seconds, 0.4, 2.0)
	var tween := create_tween()
	tween.tween_property(marker, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(marker, "position:y", marker.position.y - EMOTE_FLOAT_PX, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(actor, "scale", original_scale * 1.06, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor, "scale", original_scale, 0.16)
	tween.parallel().tween_property(marker, "modulate:a", 0.0, 0.2).set_delay(maxf(duration - 0.25, 0.1))
	await tween.finished
	actor.scale = original_scale
	if is_instance_valid(marker):
		marker.queue_free()


func _do_shake(actor_id: String, seconds: float, strength: float) -> void:
	var target: Node2D = _find_actor(actor_id)
	if target == null:
		target = _camera
	if target == null:
		return
	var original_position: Vector2 = target.global_position
	var duration: float = clampf(seconds, 0.2, 1.2)
	var amount: float = clampf(strength, 1.0, 12.0)
	var steps: int = maxi(3, int(ceil(duration / 0.045)))
	var offsets := [
		Vector2(amount, 0),
		Vector2(-amount, amount * 0.5),
		Vector2(amount * 0.5, -amount),
		Vector2(-amount * 0.5, 0),
	]
	for i in range(steps):
		if _skip:
			break
		target.global_position = original_position + offsets[i % offsets.size()]
		await get_tree().create_timer(duration / float(steps)).timeout
	target.global_position = original_position


func _facing_vector(actor: Node2D) -> Vector2:
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	if sprite != null:
		var anim := str(sprite.animation)
		if anim.ends_with("_left"):
			return Vector2.LEFT
		if anim.ends_with("_right"):
			return Vector2.RIGHT
		if anim.ends_with("_up"):
			return Vector2.UP
	return Vector2.DOWN


func _emote_symbol(emotion: String) -> String:
	match emotion.strip_edges().to_lower():
		"surprise":
			return "!"
		"fear":
			return "!!"
		"anger":
			return "!"
		"sad":
			return "..."
		"relief":
			return "*"
		"determined":
			return "!"
		"question":
			return "?"
		_:
			return "!"


func _emote_color(emotion: String) -> Color:
	match emotion.strip_edges().to_lower():
		"fear":
			return Color(0.70, 0.86, 1.0, 1.0)
		"anger":
			return Color(1.0, 0.34, 0.26, 1.0)
		"sad":
			return Color(0.58, 0.74, 1.0, 1.0)
		"relief":
			return Color(0.70, 1.0, 0.78, 1.0)
		"determined":
			return Color(1.0, 0.86, 0.42, 1.0)
		"question":
			return Color(0.92, 0.92, 1.0, 1.0)
		_:
			return Color(1.0, 0.92, 0.45, 1.0)


func _face_pair(speaker_id: String, target_id: String = "") -> void:
	# Safety net for scripts without staged face actions: speaker and the
	# explicit dialogue target turn toward each other. Older scripts fall back
	# to the previous speaker.
	if speaker_id in ["", "narrator"]:
		return
	var partner_id := target_id
	if partner_id in ["", "narrator"] or partner_id == speaker_id or _find_actor(partner_id) == null:
		partner_id = _last_speaker
	if partner_id in ["", "narrator"] or partner_id == speaker_id:
		return
	var speaker: Node2D = _find_actor(speaker_id)
	var partner: Node2D = _find_actor(partner_id)
	if speaker == null or partner == null:
		return
	var delta: Vector2 = partner.global_position - speaker.global_position
	if delta.length() < 1.0:
		return
	var speaker_direction: String
	var partner_direction: String
	if abs(delta.x) >= abs(delta.y):
		speaker_direction = "right" if delta.x > 0 else "left"
		partner_direction = "left" if delta.x > 0 else "right"
	else:
		speaker_direction = "down" if delta.y > 0 else "up"
		partner_direction = "up" if delta.y > 0 else "down"
	_do_face(speaker_id, speaker_direction)
	_do_face(partner_id, partner_direction)


func _do_say(action: Dictionary) -> void:
	var text: String = str(action.get("text", ""))
	if text.is_empty():
		return
	var actor_id: String = str(action.get("actor", ""))
	var speaker: String = str(action.get("speaker_name", actor_id))
	var emotion: String = str(action.get("emotion", "neutral"))

	_face_pair(actor_id, str(action.get("target", "")))
	if actor_id not in ["", "narrator"]:
		_last_speaker = actor_id

	var portrait: Texture2D = null
	if actor_id != "narrator":
		portrait = _speaker_portrait(actor_id, emotion)
	_portrait_frame.visible = portrait != null
	_portrait_rect.texture = portrait
	_portrait_rect.modulate = _portrait_tint_cache.get(actor_id, Color.WHITE)
	# High-res emotion/battle portraits minify with LINEAR for full detail;
	# sprite-frame fallbacks stay NEAREST to keep pixel-art crispness.
	if portrait != null and portrait.get_width() > 200:
		_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var has_named_speaker := actor_id not in ["", "narrator"]
	# Named speakers: the 480x270-authored block sits bottom-anchored and
	# horizontally centered. Narrator: the panel floats near the top, centered.
	var target_position := Vector2((_design_size.x - 480.0) * 0.5, _design_size.y - 270.0)
	if not has_named_speaker:
		target_position = Vector2(
			_design_size.x * 0.5 - DIALOGUE_PANEL_RECT.get_center().x,
			NARRATOR_PANEL_TOP - DIALOGUE_PANEL_RECT.position.y,
		)
	_dialogue_root.position = target_position

	var was_hidden: bool = not _dialogue_root.visible
	_dialogue_root.visible = true
	_name_plate.visible = has_named_speaker
	_nameplate_art_root.visible = has_named_speaker
	_name_label.text = speaker
	if has_named_speaker:
		_layout_nameplate(speaker)
	if was_hidden:
		_dialogue_root.modulate.a = 0.0
		_dialogue_root.position = target_position + Vector2(0, 8)
		var pop := create_tween()
		pop.tween_property(_dialogue_root, "modulate:a", 1.0, 0.18)
		pop.parallel().tween_property(_dialogue_root, "position", target_position, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if portrait != null:
		_portrait_rect.scale = Vector2(1.04, 1.04)
		_portrait_rect.pivot_offset = Vector2(79, 194)
		var pop_portrait := create_tween()
		pop_portrait.tween_property(_portrait_rect, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_continue_marker.visible = false
	# visible_characters (not substr) so the scrolling view can follow the
	# reveal cursor without re-wrapping the text every frame.
	_text_label.set_passage(text)
	var shown: float = 0.0
	while shown < text.length() and not _skip:
		shown += TYPE_SPEED * get_process_delta_time()
		if _accept_pressed:
			_accept_pressed = false
			break
		_text_label.visible_characters = mini(int(shown), text.length())
		await get_tree().process_frame
	_text_label.reveal_finished()
	if _skip:
		return
	_continue_marker.visible = true
	_accept_pressed = false
	while not _accept_pressed and not _skip:
		await get_tree().process_frame
	_accept_pressed = false
	_continue_marker.visible = false
	_dialogue_root.visible = false


func _do_die(actor_id: String) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null:
		return
	var enemy_data: Variant = actor.get("enemy_data")
	if enemy_data is Dictionary:
		GameManager.mark_enemy_defeated(str((enemy_data as Dictionary).get("id", "")))
	var tween := create_tween()
	tween.tween_property(actor, "modulate", Color(1.0, 0.3, 0.3, 0.0), 1.1)
	tween.parallel().tween_property(actor, "scale", Vector2(1.0, 0.6), 1.1)
	await tween.finished
	actor.visible = false


func _finish() -> void:
	# Resolve any remaining deaths instantly so skipping keeps story state.
	if _skip:
		for action in _actions:
			if action is Dictionary and str((action as Dictionary).get("type", "")) in ["die", "dead"]:
				var actor: Node2D = _find_actor(str((action as Dictionary).get("actor", "")))
				if actor != null and actor.visible:
					var enemy_data: Variant = actor.get("enemy_data")
					if enemy_data is Dictionary:
						GameManager.mark_enemy_defeated(str((enemy_data as Dictionary).get("id", "")))
					actor.visible = false

	_dialogue_root.visible = false
	_title_label.modulate.a = 0.0
	_title_dim.color.a = 0.0
	if _title_banner != null:
		_title_banner.modulate.a = 0.0
	if _skip_hint != null:
		_skip_hint.visible = false
	# This node remains alive only as a background walk-home coordinator. It must
	# no longer consume Esc/Enter after gameplay control is returned.
	set_process_unhandled_input(false)

	# Restore gameplay ownership completely. NPCController receives a return-home
	# destination and handles pathfinding, physics, collision and interaction from
	# this point onward; CutscenePlayer never coordinates background movement.
	_restore_actor_collisions()
	_release_actors_to_world()
	await _restore_player_camera(true)
	if _camera != null:
		_camera.queue_free()
	_restore_collision_for(_player)
	GameManager.ui_blocking_input = false

	var bars := create_tween()
	bars.tween_property(_top_bar, "position:y", -LETTERBOX_H, 0.5)
	bars.parallel().tween_property(_bottom_bar, "position:y", _design_size.y, 0.5)
	cutscene_finished.emit()
	await bars.finished
	actor_return_finished.emit()
	queue_free()


func _restore_player_camera(immediate: bool = false) -> void:
	if _player_camera == null or not is_instance_valid(_player_camera):
		return
	# get_screen_center_position() is the camera's last rendered center. While the
	# cinematic camera is current that value can remain at the player's old/origin
	# position. The player node itself is the authoritative live handoff target.
	var target := _player.global_position if _player != null and is_instance_valid(_player) \
			else _player_camera.global_position
	if _camera != null and is_instance_valid(_camera):
		if immediate:
			_camera.global_position = target
		else:
			var tween := create_tween()
			tween.tween_property(_camera, "global_position", target, 0.6)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			await tween.finished
	# Clear the inactive camera's stale smoothing accumulator before it takes over,
	# then force the viewport update in the same frame for a seamless handoff.
	_player_camera.make_current()
	_player_camera.reset_smoothing()
	_player_camera.force_update_scroll()


func _restore_collision_for(node: Node) -> void:
	if node != null and _collision_state.has(node):
		if is_instance_valid(node) and node is CollisionObject2D:
			var st: Dictionary = _collision_state[node]
			(node as CollisionObject2D).collision_layer = int(st["layer"])
			(node as CollisionObject2D).collision_mask = int(st["mask"])
		_collision_state.erase(node)


func _release_actors_to_world() -> void:
	for actor_id in _origin_positions:
		if actor_id == "player":
			continue
		var actor: Node2D = _find_actor(str(actor_id))
		if actor == null or not actor.visible:
			continue
		var origin: Vector2 = _origin_positions[actor_id]
		if actor.has_method("return_home_to"):
			actor.call("return_home_to", origin)
			continue
		# Non-NPC cutscene actors do not have ambient navigation ownership. Restore
		# them immediately and safely; no CutscenePlayer process remains afterward.
		actor.global_position = origin
		var actor_tile := _tile_of(actor.global_position)
		var occupied := _occupied_actor_tiles(actor)
		if occupied.has(_tile_key(actor_tile)):
			actor.global_position = _tile_to_world(_nearest_unoccupied_tile(actor_tile, occupied))
		_resync_actor_ai(actor)


func _resync_actor_ai(actor: Node2D) -> void:
	# NPC wander state caches tiles and a movement target; point it all at the
	# actor's actual position so AI resumes cleanly when input unblocks.
	if actor.get("enemy_data") != null:
		actor.set("target_position", actor.global_position)
		actor.set("wait_timer", randf_range(0.8, 1.8))
		actor.set("velocity", Vector2.ZERO)
		return
	if actor.get("npc_data") == null:
		return
	var tile := Vector2i(
		int(actor.global_position.x / GameManager.TILE_SIZE),
		int(actor.global_position.y / GameManager.TILE_SIZE),
	)
	var center: Vector2 = Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
	actor.set("current_tile", tile)
	actor.set("target_tile", tile)
	actor.set("target_position", center)
	actor.set("desired_tile", tile)
	actor.set("active_path", [] as Array[Vector2i])
	actor.set("state", 1)  # NPCController.State.WAITING
	actor.set("wait_timer", randf_range(0.6, 1.6))
	actor.set("velocity", Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_skip = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_accept_pressed = true
		get_viewport().set_input_as_handled()
