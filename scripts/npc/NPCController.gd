extends CharacterBody2D

const SpeechBubble       := preload("res://scripts/npc/SpeechBubble.gd")
const ChatBoxScene       := preload("res://scenes/ui/ChatBox.tscn")
const LoadingPopupScript := preload("res://scripts/ui/LoadingPopup.gd")
const FPS := 8.0
const BUBBLE_FULL_TILES  := 2.5
const BUBBLE_FADE_TILES  := 4.0
const BUBBLE_FULL_SECONDS := 3.0
const ARRIVE_DISTANCE := 4.0
const STUCK_DISTANCE_EPSILON := 1.5
const STUCK_TIME_LIMIT := 0.8
const MAX_PATH_SEARCH_NODES := 240
const RETURN_HOME_FALLBACK_SPEED := 36.0

enum State {
	IDLE,
	WAITING,
	CHOOSING_TARGET,
	MOVING,
	BLOCKED,
	LIVE_ACTION,
}

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $Shadow

var npc_data: Dictionary = {}
var movement: Dictionary = {}
var interaction: Dictionary = {}
var actor_state: Dictionary = {}
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
var _player: Node2D = null
var _bubble_lines: Array = []
var _interaction_items: Array[String] = []
var _bubble_showing: bool = false
var _bubble_full_timer: float = 0.0
var _bubble_cycle_expired: bool = false
var _interaction_enabled: bool = false
var _interaction_radius: float = 1.5
var _in_interaction_range: bool = false
var _loading_popup: Node = null
var _awaited_npc_id: String = ""
var _quest_marker: Label = null
var _default_collision_layer: int = 1
var _default_collision_mask: int = 1
var _default_modulate: Color = Color.WHITE
var _default_sprite_modulate: Color = Color.WHITE
var _default_sprite_rotation_degrees: float = 0.0
var _default_shadow_visible: bool = true
var _return_home_active: bool = false
var _return_home_tile := Vector2i.ZERO
var _return_home_position := Vector2.ZERO
var _cutscene_control_active: bool = false
# Real-time ambient live action (LiveActionDirector): the show overrides normal
# wander while gameplay continues — never a cutscene, never ui_blocking.
var _live_action_active: bool = false
var _live_action_speed: float = 0.0

func setup(data: Dictionary, world_context: Dictionary) -> void:
	npc_data = data
	# Packages may carry explicit nulls for these — guard the casts.
	movement = data.get("movement") if data.get("movement") is Dictionary else {}
	interaction = data.get("interaction") if data.get("interaction") is Dictionary else {}
	map_tile_size = world_context.get("map_tile_size", Vector2i.ZERO) as Vector2i
	blocked_tiles = (world_context.get("blocked_tiles", {}) as Dictionary).duplicate()
	occupied_tiles = (world_context.get("occupied_tiles", {}) as Dictionary).duplicate()
	tile_metadata = (world_context.get("tile_metadata", {}) as Dictionary).duplicate(true)
	actor_state = (world_context.get("actor_state", {}) as Dictionary).duplicate(true) if world_context.get("actor_state") is Dictionary else {}
	_player = world_context.get("player") as Node2D
	current_tile = _read_tile_position(data)
	anchor_tile = _read_tile_position(movement.get("anchor_tile", {}) as Dictionary)
	if anchor_tile == Vector2i.ZERO:
		anchor_tile = current_tile
	target_tile = current_tile
	target_position = _tile_to_pixel_center(current_tile)
	global_position = target_position
	speed = max(float(movement.get("speed", speed)), 0.0) * (float(GameManager.TILE_SIZE) / 36.0)
	path_tiles = _read_path_tiles(movement.get("path_tiles", []))
	_lighting_sys = get_tree().get_first_node_in_group("lighting")
	_setup_shadow()
	_setup_sprite_frames()
	_capture_actor_defaults()
	_start_behavior()
	_setup_bubble()
	_setup_interaction()
	_setup_quest_marker()
	apply_actor_state(actor_state)

func _exit_tree() -> void:
	WorldInteractionManager.clear_owner(self)

func _setup_quest_marker() -> void:
	_quest_marker = Label.new()
	_quest_marker.text = "!"
	_quest_marker.position = Vector2(-6, -68)
	_quest_marker.add_theme_font_size_override("font_size", 26)
	_quest_marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_quest_marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_quest_marker.add_theme_constant_override("shadow_offset_y", 1)
	_quest_marker.visible = false
	add_child(_quest_marker)
	update_quest_marker()

func update_quest_marker() -> void:
	if _quest_marker == null:
		return
	var marker: String = QuestManager.marker_for_npc(str(npc_data.get("id", "")))
	_quest_marker.text = marker
	var should_show: bool = not marker.is_empty()
	if should_show and not _quest_marker.visible:
		_quest_marker.visible = true
		var bounce := create_tween().set_loops()
		bounce.tween_property(_quest_marker, "position:y", -74.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bounce.tween_property(_quest_marker, "position:y", -68.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_quest_marker.set_meta("bounce", bounce)
	elif not should_show and _quest_marker.visible:
		_quest_marker.visible = false
		var bounce: Variant = _quest_marker.get_meta("bounce") if _quest_marker.has_meta("bounce") else null
		if bounce is Tween and (bounce as Tween).is_valid():
			(bounce as Tween).kill()

func apply_actor_state(state_data: Dictionary) -> void:
	actor_state = state_data.duplicate(true)
	var state_name := _actor_state_token(actor_state.get("state", ""))
	var presentation := _actor_state_token(actor_state.get("presentation", ""))
	if presentation.is_empty():
		presentation = _default_presentation_for_actor_state(state_name)
	if presentation in ["hidden", "despawn", "removed", "none"] \
			or state_name in ["hidden", "despawned", "removed"]:
		_apply_hidden_actor_state()
	elif presentation == "corpse" or state_name == "dead":
		_apply_corpse_actor_state()
	elif presentation == "inactive" or state_name in ["inactive", "disabled"]:
		_apply_inactive_actor_state()
	else:
		_apply_normal_actor_state()

func _capture_actor_defaults() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_default_modulate = modulate
	_default_sprite_modulate = anim_sprite.modulate
	_default_sprite_rotation_degrees = anim_sprite.rotation_degrees
	_default_shadow_visible = shadow.visible

func _apply_normal_actor_state() -> void:
	visible = true
	set_physics_process(true)
	velocity = Vector2.ZERO
	modulate = _default_modulate
	anim_sprite.visible = true
	anim_sprite.rotation_degrees = _default_sprite_rotation_degrees
	anim_sprite.modulate = _default_sprite_modulate
	shadow.visible = _default_shadow_visible
	_setup_interaction()
	if _bubble != null:
		_bubble.visible = true
	update_quest_marker()
	if _return_home_active:
		# A narrative refresh must not replace an in-flight gameplay return with
		# ambient wandering. Return-home uses normal physics and collision.
		_set_actor_collision_enabled(true)
		set_physics_process(true)
		_resume_return_home()
		return
	if _live_action_active:
		# Same rule for a running ambient live action: the director owns movement
		# until the show resolves; a narrative refresh must not restart wandering.
		_set_actor_collision_enabled(true)
		set_physics_process(true)
		state = State.LIVE_ACTION
		return
	_set_actor_collision_enabled(true)
	_start_behavior()

func _apply_hidden_actor_state() -> void:
	_cancel_return_home()
	_live_action_active = false
	visible = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	_disable_actor_interaction()
	_set_actor_collision_enabled(false)

func _apply_corpse_actor_state() -> void:
	_cancel_return_home()
	_live_action_active = false
	visible = true
	velocity = Vector2.ZERO
	state = State.IDLE
	path_tiles.clear()
	active_path.clear()
	set_physics_process(false)
	_disable_actor_interaction()
	_set_actor_collision_enabled(false)
	anim_sprite.visible = true
	anim_sprite.pause()
	anim_sprite.rotation_degrees = 90.0
	anim_sprite.modulate = Color(0.65, 0.65, 0.7, 0.9)
	shadow.visible = false

func _apply_inactive_actor_state() -> void:
	_cancel_return_home()
	_live_action_active = false
	visible = true
	velocity = Vector2.ZERO
	state = State.IDLE
	path_tiles.clear()
	active_path.clear()
	set_physics_process(false)
	_disable_actor_interaction()
	_set_actor_collision_enabled(false)
	anim_sprite.rotation_degrees = _default_sprite_rotation_degrees
	anim_sprite.modulate = _default_sprite_modulate
	shadow.visible = _default_shadow_visible

func _disable_actor_interaction() -> void:
	_interaction_enabled = false
	_in_interaction_range = false
	WorldInteractionManager.clear_owner(self)
	if _bubble != null:
		_bubble.target_alpha = 0.0
		_bubble.visible = false
	_bubble_showing = false
	if _quest_marker != null:
		_quest_marker.visible = false

func _set_actor_collision_enabled(enabled: bool) -> void:
	collision_layer = _default_collision_layer if enabled else 0
	collision_mask = _default_collision_mask if enabled else 0
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.disabled = not enabled

func _default_presentation_for_actor_state(state_name: String) -> String:
	match state_name:
		"dead":
			return "corpse"
		"hidden", "removed", "despawned":
			return "despawn"
		"inactive", "disabled":
			return "inactive"
	return "normal"

func _actor_state_token(value: Variant) -> String:
	return str(value).strip_edges().to_lower().replace(" ", "_").replace("-", "_")

func _setup_bubble() -> void:
	var lines: Variant = interaction.get("lines", [])
	_bubble_lines = lines if lines is Array else []
	if _bubble_lines.is_empty():
		return
	_bubble = SpeechBubble.new()
	_bubble.position = Vector2(0.0, -48.0)
	_bubble.scale = Vector2(2, 2)  # bubble art authored for 36px characters
	add_child(_bubble)

func _physics_process(delta: float) -> void:
	if GameManager.ui_blocking_input:
		# Frozen during chats, battles, and cutscenes; cutscenes may drive
		# position and animation directly while this gate holds.
		velocity = Vector2.ZERO
		if not _cutscene_control_active:
			# Chat/menu/battle owns no character animation, so stop the current walk.
			# During a cutscene, CutscenePlayer is the sole animation authority.
			_update_animation()
		_update_shadow()
		_suppress_bubble(true)
		return
	match state:
		State.WAITING, State.BLOCKED:
			wait_timer -= delta
			velocity = Vector2.ZERO
			if wait_timer <= 0.0:
				if _return_home_active:
					_resume_return_home()
				else:
					state = State.CHOOSING_TARGET
		State.CHOOSING_TARGET:
			_choose_next_target()
		State.MOVING:
			_move_to_target()
		State.LIVE_ACTION:
			_live_action_step()
		_:
			velocity = Vector2.ZERO

	_update_animation()
	_update_shadow()
	_update_interaction()
	_update_bubble_alpha(delta)


# ── real-time ambient live action (LiveActionDirector) ─────────────────────────
# The director overrides normal wander while the player keeps playing: the NPC
# keeps its body, collision, animation, bubble and interaction — only WHERE it
# moves is scripted. Waypoints come from the director; this node only walks them
# with its ordinary A* pathing so it can never phase through walls.


func begin_live_action(tiles_per_sec: float) -> void:
	if not can_return_home():
		return
	_cancel_return_home()
	_live_action_active = true
	_live_action_speed = maxf(tiles_per_sec, 0.5) * float(GameManager.TILE_SIZE)
	current_tile = _pixel_to_tile(global_position)
	velocity = Vector2.ZERO
	active_path.clear()
	state = State.LIVE_ACTION


func live_action_move_to(tile: Vector2i) -> bool:
	## Directed waypoint. Returns false when the tile is unreachable so the
	## director can pick another one.
	if not _live_action_active:
		return false
	current_tile = _pixel_to_tile(global_position)
	if tile == current_tile:
		return false
	var path := _find_path(current_tile, tile)
	if path.is_empty():
		return false
	active_path = path
	active_path_index = 0
	desired_tile = tile
	_set_next_path_target()
	previous_position = global_position
	stuck_timer = 0.0
	state = State.LIVE_ACTION
	return true


func live_action_hold() -> void:
	if not _live_action_active:
		return
	active_path.clear()
	velocity = Vector2.ZERO


func live_action_idle() -> bool:
	## True when the NPC finished (or lost) its current waypoint and awaits the next.
	return _live_action_active and (active_path.is_empty() or active_path_index >= active_path.size())


func is_in_live_action() -> bool:
	return _live_action_active


func is_live_action_engaged() -> bool:
	## False when something else (interaction freeze, a cutscene release) stole the
	## state machine — the director re-asserts on its next tick.
	return _live_action_active and state == State.LIVE_ACTION


func is_player_engaged() -> bool:
	return _in_interaction_range


func end_live_action() -> void:
	if not _live_action_active:
		return
	_live_action_active = false
	_live_action_speed = 0.0
	active_path.clear()
	velocity = Vector2.ZERO
	if state == State.LIVE_ACTION:
		state = State.IDLE


func _live_action_step() -> void:
	if active_path.is_empty() or active_path_index >= active_path.size():
		velocity = Vector2.ZERO
		return
	var distance: float = global_position.distance_to(target_position)
	if distance <= ARRIVE_DISTANCE:
		global_position = target_position
		current_tile = target_tile
		active_path_index += 1
		if active_path_index >= active_path.size():
			velocity = Vector2.ZERO
			active_path.clear()
			return
		_set_next_path_target()
		return
	velocity = global_position.direction_to(target_position) * _live_action_speed
	move_and_slide()
	_update_stuck_timer()
	if get_slide_collision_count() > 0 or stuck_timer >= STUCK_TIME_LIMIT:
		# Blocked mid-run (a body crossed the route): drop the waypoint and let the
		# director issue a fresh one instead of waiting out a BLOCKED timer.
		active_path.clear()
		velocity = Vector2.ZERO


func return_home_to(world_position: Vector2) -> void:
	## Gameplay-owned post-cutscene return. The NPC keeps its ordinary physics,
	## collision, animation and interaction while navigating back to this point.
	_cutscene_control_active = false
	_live_action_active = false
	if not can_return_home():
		return
	_return_home_active = true
	_return_home_position = world_position
	_return_home_tile = _pixel_to_tile(world_position)
	current_tile = _pixel_to_tile(global_position)
	_set_actor_collision_enabled(true)
	set_physics_process(true)
	_resume_return_home()


func is_returning_home() -> bool:
	return _return_home_active


func get_return_home_destination() -> Vector2:
	return _return_home_position if _return_home_active else global_position


func suspend_return_home_for_cutscene() -> void:
	# CutscenePlayer records the destination first, then suspends gameplay motion.
	# Its next release will issue a fresh return command to the same destination.
	_cutscene_control_active = true
	_cancel_return_home()


func can_return_home() -> bool:
	if not visible:
		return false
	var state_name := _actor_state_token(actor_state.get("state", ""))
	var presentation := _actor_state_token(actor_state.get("presentation", ""))
	return state_name not in ["dead", "hidden", "despawned", "removed", "inactive", "disabled"] \
		and presentation not in ["corpse", "hidden", "despawn", "removed", "inactive", "none"]


func _resume_return_home() -> void:
	if not _return_home_active or not can_return_home():
		_cancel_return_home()
		return
	current_tile = _pixel_to_tile(global_position)
	if current_tile == _return_home_tile:
		active_path = [_return_home_tile]
	else:
		active_path = _find_path(current_tile, _return_home_tile)
	active_path_index = 0
	desired_tile = _return_home_tile
	if active_path.is_empty():
		velocity = Vector2.ZERO
		state = State.BLOCKED
		wait_timer = 0.35
		return
	_set_next_path_target()
	previous_position = global_position
	stuck_timer = 0.0
	state = State.MOVING


func _finish_return_home() -> void:
	global_position = _return_home_position
	current_tile = _return_home_tile
	velocity = Vector2.ZERO
	_return_home_active = false
	active_path.clear()
	_start_behavior()


func _cancel_return_home() -> void:
	_return_home_active = false
	active_path.clear()
	velocity = Vector2.ZERO

func _setup_interaction() -> void:
	var inter: Dictionary = interaction
	_interaction_items.clear()
	# Quest participants — and any NPC that has a generated conversation tree —
	# must always be approachable, whatever the package interaction flag says.
	_interaction_enabled = bool(inter.get("enabled", false)) \
		or QuestManager.is_quest_npc(str(npc_data.get("id", ""))) \
		or _has_conversation_tree()
	if not _interaction_enabled:
		return
	_interaction_radius = float(inter.get("proximity_radius_tiles", 1.5))
	var npc_name := str(npc_data.get("name", "NPC"))
	var raw_opts: Variant = inter.get("options", [])
	var items: Array[String] = []
	if raw_opts is Array:
		for opt in raw_opts:
			var opt_str := str(opt)
			items.append("Talk to %s" % npc_name if opt_str == "Talk" else opt_str)
	if items.is_empty():
		items = ["Talk to %s" % npc_name]
	_interaction_items = items

func _has_conversation_tree() -> bool:
	# True if this NPC has any authored dialogue: the two-layer world/story
	# dialogue, or a legacy pre-merged conversation_tree.
	return DialogueAssembler.has_dialogue(npc_data)

func _on_interaction_item_confirmed(item: String, _index: int) -> void:
	if item.begins_with("Talk"):
		WorldInteractionManager.clear_owner(self)
		if _bubble != null:
			_bubble.target_alpha = 0.0
			_bubble_showing = false
			_bubble_full_timer = 0.0
			_bubble_cycle_expired = false
		var bubble_line := ""
		if not _bubble_lines.is_empty():
			bubble_line = str(_bubble_lines.pick_random())
		var chatbox: Node = ChatBoxScene.instantiate()
		get_tree().root.add_child(chatbox)
		if chatbox.has_method("stage_camera_for_conversation"):
			chatbox.stage_camera_for_conversation(_player, self)
		# Story-first select flow: assemble the active tree from the two dialogue
		# layers (evergreen world ⊕ the story stage the player has unlocked).
		# (Legacy free-chat is only used for old packages without a tree.)
		var active_tree: Dictionary = DialogueAssembler.build_active_tree(npc_data)
		if not active_tree.is_empty():
			# Phase 1: the tree completes the "talk" objective when the player
			# finishes the conversation (ChatBox fires notify_npc_talked at __end__),
			# so the player must actually converse — not just bump the NPC.
			chatbox.open_tree(str(npc_data.get("name", "")), npc_data, active_tree)
		else:
			chatbox.open(str(npc_data.get("name", "")), npc_data, str(npc_data.get("id", "")), bubble_line)
			QuestManager.notify_npc_talked(str(npc_data.get("id", "")))

func _update_interaction() -> void:
	if not _interaction_enabled or _player == null or not is_instance_valid(_player):
		return
	var dist_tiles := global_position.distance_to(_player.global_position) / GameManager.TILE_SIZE
	var in_range   := dist_tiles <= _interaction_radius
	var is_facing := _player_is_facing_this_npc()
	if in_range and is_facing and not _interaction_items.is_empty():
		WorldInteractionManager.submit_candidate(
			self,
			"npc",
			_interaction_items[0],
			0,
			dist_tiles,
			_player,
			"_on_interaction_item_confirmed"
		)

	var is_active := WorldInteractionManager.is_active(self, "npc")
	if is_active and not _in_interaction_range:
		_in_interaction_range = true
		state     = State.IDLE
		velocity  = Vector2.ZERO
	elif not is_active and _in_interaction_range:
		_in_interaction_range = false
		if _return_home_active:
			_resume_return_home()
		elif _live_action_active:
			# The interaction freeze paused the show; hand the state machine back to
			# the director (it re-issues the next waypoint on its own tick).
			state = State.LIVE_ACTION
		else:
			state = State.CHOOSING_TARGET
	if _in_interaction_range:
		_face_player()

func _player_is_facing_this_npc() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var to_npc := global_position - _player.global_position
	if to_npc.length() <= 1.0:
		return true
	var facing := Vector2.ZERO
	if _player.has_method("get_facing_vector"):
		facing = _player.call("get_facing_vector") as Vector2
	if facing == Vector2.ZERO:
		facing = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if facing == Vector2.ZERO:
		return false
	return facing.normalized().dot(to_npc.normalized()) >= 0.55

func _face_player() -> void:
	var diff := _player.global_position - global_position
	if abs(diff.x) >= abs(diff.y):
		last_facing = "right" if diff.x > 0.0 else "left"
	else:
		last_facing = "down" if diff.y > 0.0 else "up"

func _update_bubble_alpha(delta: float) -> void:
	if _bubble == null:
		return
	if _player == null or not is_instance_valid(_player):
		_reset_bubble_cycle()
		return
	var dist_tiles := global_position.distance_to(_player.global_position) / GameManager.TILE_SIZE
	if dist_tiles >= BUBBLE_FADE_TILES:
		_reset_bubble_cycle()
		return
	if GameManager.ui_blocking_input or WorldInteractionManager.is_prompt_active():
		_suppress_bubble(true)
		return
	if _bubble_cycle_expired:
		_bubble.target_alpha = 0.0
		return

	var alpha: float
	if dist_tiles <= BUBBLE_FULL_TILES:
		alpha = 1.0
	else:
		alpha = 1.0 - (dist_tiles - BUBBLE_FULL_TILES) / (BUBBLE_FADE_TILES - BUBBLE_FULL_TILES)
	if alpha > 0.0 and not _bubble_showing:
		_bubble_showing = true
		_bubble_full_timer = 0.0
		_bubble.show_text(str(_bubble_lines.pick_random()))

	if alpha >= 1.0 and _bubble.modulate.a >= 0.98:
		_bubble_full_timer += delta
		if _bubble_full_timer >= BUBBLE_FULL_SECONDS:
			_bubble_cycle_expired = true
			_bubble.target_alpha = 0.0
			return
	else:
		_bubble_full_timer = 0.0
	_bubble.target_alpha = alpha


func _suppress_bubble(expire_current_cycle: bool = false) -> void:
	if _bubble == null:
		return
	_bubble.target_alpha = 0.0
	_bubble_full_timer = 0.0
	if expire_current_cycle and _bubble_showing:
		_bubble_cycle_expired = true


func _reset_bubble_cycle() -> void:
	if _bubble == null:
		return
	_bubble.target_alpha = 0.0
	_bubble_showing = false
	_bubble_full_timer = 0.0
	_bubble_cycle_expired = false

func _update_shadow() -> void:
	if _lighting_sys == null or not is_instance_valid(_lighting_sys):
		_lighting_sys = get_tree().get_first_node_in_group("lighting")
	if _lighting_sys == null:
		return
	var light_pos: Vector2 = _lighting_sys.get_dominant_light_pos(global_position)
	if light_pos == Vector2.ZERO:
		shadow.position = Vector2(0.0, 28.0)
		shadow.rotation = 0.0
		shadow.modulate.a = 0.35
		return
	var to_char: Vector2 = global_position - light_pos
	var dist: float = to_char.length()
	var dir: Vector2 = to_char.normalized() if dist > 1.0 else Vector2(0.0, 1.0)
	var tile_dist: float = dist / float(GameManager.TILE_SIZE)
	var offset_px: float = clampf(tile_dist * 3.6, 4.0, 24.0)
	shadow.position = Vector2(0.0, 28.0) + dir * offset_px
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
	if sprite_sheet_file == "<null>":
		sprite_sheet_file = ""
	var texture: Texture2D = null
	if not sprite_sheet_file.is_empty():
		texture = GameManager.load_texture(GameManager.get_scene_asset_path(sprite_sheet_file))
	if texture == null:
		print("[NPC] %s texture missing, using fallback sheet" % npc_data.get("id","?"))
		texture = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
		modulate = Color(0.78, 0.86, 1.0)
	if texture == null:
		return
	print("[NPC] %s texture OK size=%s" % [npc_data.get("id","?"), texture.get_size()])

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
			if _return_home_active:
				_finish_return_home()
			else:
				_wait_random()
			return
		_set_next_path_target()
		return

	var direction: Vector2 = global_position.direction_to(target_position)
	var movement_speed := _return_home_speed() if _return_home_active else speed
	velocity = direction * movement_speed
	move_and_slide()
	_update_stuck_timer()
	if get_slide_collision_count() > 0 or stuck_timer >= STUCK_TIME_LIMIT:
		_handle_stuck()

func _return_home_speed() -> float:
	# Authored fixed NPCs legitimately use speed=0 for ambient behavior. Returning
	# from a cutscene is a one-off navigation task and must still make progress;
	# preserve the authored value and use this fallback only during that task.
	return speed if speed > 0.0 else RETURN_HOME_FALLBACK_SPEED

func _set_next_path_target() -> void:
	target_tile = active_path[active_path_index]
	target_position = _return_home_position \
			if _return_home_active and target_tile == _return_home_tile \
			else _tile_to_pixel_center(target_tile)

func _update_stuck_timer() -> void:
	if global_position.distance_to(previous_position) < STUCK_DISTANCE_EPSILON:
		stuck_timer += get_physics_process_delta_time()
	else:
		stuck_timer = 0.0
		previous_position = global_position

func _handle_stuck() -> void:
	if _return_home_active:
		# Dynamic bodies may temporarily occupy the route. Keep normal collision,
		# wait briefly, then repath to the same home destination.
		velocity = Vector2.ZERO
		state = State.BLOCKED
		wait_timer = 0.35
		return
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

func _pixel_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(GameManager.TILE_SIZE)),
		floori(world_position.y / float(GameManager.TILE_SIZE)),
	)

func _tile_key(tile: Vector2i) -> String:
	return "%s:%s" % [tile.x, tile.y]
