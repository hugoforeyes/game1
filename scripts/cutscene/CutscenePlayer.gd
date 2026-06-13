extends CanvasLayer
## Chapter intro — cutscene mode. Plays a generated script on the live scene:
## real NPC/enemy/player actors walk, turn, speak (with emotion portraits),
## and die while a cinematic camera follows, framed by letterbox bars.
## The backend staging pass walks speakers next to their conversation partner;
## this player also auto-faces speaker pairs as a safety net. Esc skips.

signal cutscene_finished

const TYPE_SPEED := 44.0
const MOVE_SPEED_PX := 144.0
const LETTERBOX_H := 30.0
const PRESTAGE_DISTANCE_TILES := 5.0
const PRESTAGE_APPROACH_TILES := 2.0
const WALK_BACK_MAX_SECONDS := 2.5
const MOVE_CLAMP_TILES := 4  # max tiles a cutscene actor may stray from the player
const DEFAULT_PORTRAIT := "res://assets/ui/chatbox_npc_portrait.png"

const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.0)
const COLOR_SPEAKER := Color(0.96, 0.88, 0.50, 1.0)

# Dialogue block vertical offset when flipped to the top of the screen so it
# never covers speakers standing in the lower half.
const DIALOGUE_TOP_OFFSET := -146.0

var _world: Node2D = null
var _player: Node2D = null
var _characters_root: Node2D = null
var _camera: Camera2D = null
var _player_camera: Camera2D = null

var _actions: Array = []
var _skip: bool = false
var _accept_pressed: bool = false
var _last_speaker: String = ""
var _portrait_cache: Dictionary = {}
var _portrait_tint_cache: Dictionary = {}  # actor_id -> Color tint for body-fallback portraits
var _origin_positions: Dictionary = {}  # actor_id -> Vector2 (pre-cutscene)
var _blocked_tiles: Dictionary = {}

var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _dialogue_root: Control
var _dialogue_panel: Panel
var _name_plate: Panel
var _name_label: Label
var _portrait_frame: Panel
var _portrait_rect: TextureRect
var _text_label: Label
var _continue_marker: Label
var _title_dim: ColorRect
var _title_label: Label
var _title_banner: TextureRect
var _skip_hint: Label


func play(actions: Array, world: Node2D, player: Node2D, characters_root: Node2D) -> void:
	_actions = actions
	_world = world
	_player = player
	_characters_root = characters_root
	layer = 70
	transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	GameManager.ui_blocking_input = true
	_blocked_tiles = GameManager.get_blocked_tiles(GameManager.get_scene_package())
	_record_origins()
	_prestage_actors()
	_build_ui()
	_setup_camera()
	_run()


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
					_origin_positions[actor_id] = (child as Node2D).global_position


# On-screen tile offsets around the player, ordered by preference (sides and
# slightly below first). The 480x270 viewport at 36px/tile shows ~±6 x, ±3 y.
const PRESTAGE_RING := [
	Vector2i(3, 1), Vector2i(-3, 1), Vector2i(4, 0), Vector2i(-4, 0),
	Vector2i(3, -2), Vector2i(-3, -2), Vector2i(2, 2), Vector2i(-2, 2),
	Vector2i(5, 1), Vector2i(-5, 1), Vector2i(4, 2), Vector2i(-4, 2),
	Vector2i(0, -3), Vector2i(5, -1), Vector2i(-5, -1),
]


func _prestage_actors() -> void:
	# Every actor the script references should already be on screen near the
	# player when the cutscene starts — no waiting for someone to walk in from
	# off-screen. Off-screen participants are teleported to free tiles in a ring
	# around the player; they keep their script and walk home afterwards.
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
		var actor_id: String = str((action as Dictionary).get("actor", "")).strip_edges()
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
	var viewport_size: Vector2 = Vector2(480, 270)

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

	_skip_hint = UiKit.make_label("ESC  skip", 7, UiKit.COLOR_TEXT_DIM)
	_skip_hint.position = Vector2(430, 8)
	add_child(_skip_hint)

	# ── dialogue block: portrait frame + name plate + ornate text panel ──
	_dialogue_root = Control.new()
	_dialogue_root.position = Vector2(0, 0)
	_dialogue_root.visible = false
	add_child(_dialogue_root)

	_portrait_frame = UiKit.make_panel(Rect2(26, 182, 58, 58))
	_dialogue_root.add_child(_portrait_frame)

	_portrait_rect = TextureRect.new()
	_portrait_rect.position = Vector2(5, 5)
	_portrait_rect.size = Vector2(48, 48)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_frame.add_child(_portrait_rect)

	_dialogue_panel = UiKit.make_panel(Rect2(88, 196, 366, 56))
	_dialogue_root.add_child(_dialogue_panel)

	_name_plate = UiKit.make_panel(Rect2(96, 184, 110, 20))
	_dialogue_root.add_child(_name_plate)

	_name_label = UiKit.make_label("", 8, COLOR_SPEAKER)
	_name_label.position = Vector2(8, 4)
	_name_label.size = Vector2(96, 12)
	_name_label.clip_text = true
	_name_plate.add_child(_name_label)

	_text_label = UiKit.make_label("", 8, COLOR_TEXT)
	_text_label.position = Vector2(12, 16)
	_text_label.size = Vector2(342, 34)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_panel.add_child(_text_label)

	_continue_marker = UiKit.make_label("v", 8, COLOR_SPEAKER)
	_continue_marker.position = Vector2(348, 40)
	_continue_marker.visible = false
	_dialogue_panel.add_child(_continue_marker)

	# ── title card ──
	_title_dim = ColorRect.new()
	_title_dim.color = Color(0, 0, 0, 0.0)
	_title_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_dim)

	_title_banner = UiKit.make_banner_rect(180.0)
	if _title_banner != null:
		_title_banner.position = Vector2(150, 78)
		_title_banner.modulate.a = 0.0
		add_child(_title_banner)

	_title_label = UiKit.make_label("", 17, COLOR_SPEAKER)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(20, 124)
	_title_label.size = Vector2(440, 60)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.modulate.a = 0.0
	add_child(_title_label)


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
		"say":
			await _do_say(action)
		"die":
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


# ── dialogue placement ────────────────────────────────────────────────────────


func _should_place_dialogue_on_top(actor_id: String) -> bool:
	if _camera == null:
		return false
	var screen_center: Vector2 = _camera.get_screen_center_position()
	var participants: Array[Node2D] = []
	var speaker: Node2D = _find_actor(actor_id)
	if speaker != null:
		participants.append(speaker)
	if actor_id != "player":
		participants.append(_player)
	for participant in participants:
		var screen_y: float = participant.global_position.y - screen_center.y + 270.0
		if screen_y > 300.0:
			return true
	return false


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

	if actor_id == "player":
		return _sheet_frame(GameManager.load_texture(GameManager.get_player_sprite_path()))

	var characters: Dictionary = package.get("characters", {}) as Dictionary
	for npc in characters.get("npcs", []) as Array:
		if not (npc is Dictionary) or str((npc as Dictionary).get("id", "")) != actor_id:
			continue
		var emotion_info: Variant = (npc as Dictionary).get("emotion_portraits")
		if emotion_info is Dictionary:
			var portraits: Array = (emotion_info as Dictionary).get("portraits", []) as Array
			for wanted in [emotion, "neutral"]:
				for portrait in portraits:
					if portrait is Dictionary and str((portrait as Dictionary).get("emotion", "")) == wanted:
						var texture: Texture2D = GameManager.load_texture(
							GameManager.get_scene_asset_path(str((portrait as Dictionary).get("file", "")))
						)
						if texture != null:
							return texture
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
		_title_banner.position.y = 84
		tween.parallel().tween_property(_title_banner, "modulate:a", 1.0, 0.9)
		tween.parallel().tween_property(_title_banner, "position:y", 78.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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


func _do_move(actor_id: String, to_tile: Dictionary) -> void:
	var actor: Node2D = _find_actor(actor_id)
	if actor == null or to_tile.is_empty():
		return
	var target_tile := Vector2i(int(to_tile.get("x", 0)), int(to_tile.get("y", 0)))
	# Keep cutscene movement on screen: pull any destination that would wander
	# far from the player back toward the player (the camera anchor). Without
	# this, the LLM's authored far-flung move targets make actors walk off the
	# screen even after they were pre-staged nearby.
	if actor_id != "player":
		target_tile = _clamp_tile_near_player(target_tile, MOVE_CLAMP_TILES)
	var target: Vector2 = Vector2(target_tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)
	var distance: float = actor.global_position.distance_to(target)
	if distance < 2.0:
		return
	var direction: Vector2 = (target - actor.global_position).normalized()
	var anim_direction: String
	if abs(direction.x) >= abs(direction.y):
		anim_direction = "right" if direction.x > 0 else "left"
	else:
		anim_direction = "down" if direction.y > 0 else "up"
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
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
	var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % direction):
		sprite.play("walk_%s" % direction)
		sprite.pause()


func _face_pair(speaker_id: String) -> void:
	# Safety net for scripts without staged face actions: speaker and the
	# previous speaker turn toward each other.
	if speaker_id in ["", "narrator"] or _last_speaker in ["", "narrator"] or _last_speaker == speaker_id:
		return
	var speaker: Node2D = _find_actor(speaker_id)
	var partner: Node2D = _find_actor(_last_speaker)
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
	_do_face(_last_speaker, partner_direction)


func _do_say(action: Dictionary) -> void:
	var text: String = str(action.get("text", ""))
	if text.is_empty():
		return
	var actor_id: String = str(action.get("actor", ""))
	var speaker: String = str(action.get("speaker_name", actor_id))
	var emotion: String = str(action.get("emotion", "neutral"))

	_face_pair(actor_id)
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

	# Flip the dialogue block to the top when the speaker (or the player)
	# stands in the lower half of the screen, so it never covers them.
	_dialogue_root.position.y = DIALOGUE_TOP_OFFSET if _should_place_dialogue_on_top(actor_id) else 0.0

	var base_y: float = _dialogue_root.position.y
	var was_hidden: bool = not _dialogue_root.visible
	_dialogue_root.visible = true
	_name_plate.visible = actor_id != "narrator"
	_name_label.text = speaker
	if was_hidden:
		_dialogue_root.modulate.a = 0.0
		_dialogue_root.position.y = base_y + 8.0
		var pop := create_tween()
		pop.tween_property(_dialogue_root, "modulate:a", 1.0, 0.18)
		pop.parallel().tween_property(_dialogue_root, "position:y", base_y, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if portrait != null:
		_portrait_rect.scale = Vector2(1.12, 1.12)
		_portrait_rect.pivot_offset = Vector2(24, 48)
		var pop_portrait := create_tween()
		pop_portrait.tween_property(_portrait_rect, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_continue_marker.visible = false
	var shown: float = 0.0
	while shown < text.length() and not _skip:
		shown += TYPE_SPEED * get_process_delta_time()
		if _accept_pressed:
			_accept_pressed = false
			break
		_text_label.text = text.substr(0, mini(int(shown), text.length()))
		await get_tree().process_frame
	_text_label.text = text
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
			if action is Dictionary and str((action as Dictionary).get("type", "")) == "die":
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

	await _walk_actors_home()

	if _player_camera != null:
		var tween := create_tween()
		tween.tween_property(_camera, "global_position", _player_camera.get_screen_center_position(), 0.7)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
		_player_camera.make_current()

	var bars := create_tween()
	bars.tween_property(_top_bar, "position:y", -LETTERBOX_H, 0.5)
	bars.parallel().tween_property(_bottom_bar, "position:y", 270.0, 0.5)
	await bars.finished

	if _camera != null:
		_camera.queue_free()
	GameManager.ui_blocking_input = false
	cutscene_finished.emit()
	queue_free()


func _walk_actors_home() -> void:
	# NPCs (and enemies) the script displaced walk back to their pre-cutscene
	# spots while the letterbox is still up, then their wander AI is re-synced
	# so it does not resume from stale pre-cutscene state. The player keeps
	# their scripted position.
	var max_duration: float = 0.0
	var displaced: Array[Array] = []  # [actor, origin, duration]
	for actor_id in _origin_positions:
		if actor_id == "player":
			continue
		var actor: Node2D = _find_actor(str(actor_id))
		if actor == null or not actor.visible:
			continue
		var origin: Vector2 = _origin_positions[actor_id]
		var distance: float = actor.global_position.distance_to(origin)
		if distance < GameManager.TILE_SIZE * 0.75:
			_resync_actor_ai(actor)
			continue
		var duration: float = minf(distance / MOVE_SPEED_PX, WALK_BACK_MAX_SECONDS)
		displaced.append([actor, origin, duration])
		max_duration = maxf(max_duration, duration)

	if displaced.is_empty():
		return

	for entry in displaced:
		var actor: Node2D = entry[0]
		var origin: Vector2 = entry[1]
		var duration: float = entry[2]
		if _skip:
			actor.global_position = origin
			_resync_actor_ai(actor)
			continue
		var delta: Vector2 = origin - actor.global_position
		var direction: String
		if abs(delta.x) >= abs(delta.y):
			direction = "right" if delta.x > 0 else "left"
		else:
			direction = "down" if delta.y > 0 else "up"
		var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
		if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk_%s" % direction):
			sprite.play("walk_%s" % direction)
		var tween := create_tween()
		tween.tween_property(actor, "global_position", origin, duration)

	if not _skip:
		await get_tree().create_timer(max_duration + 0.1).timeout
	for entry in displaced:
		var actor: Node2D = entry[0]
		var sprite: AnimatedSprite2D = _actor_anim_sprite(actor)
		if sprite != null:
			sprite.pause()
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
