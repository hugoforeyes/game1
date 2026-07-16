class_name QuestCompassView
extends CanvasLayer
## A subtle screen-edge pointer toward the TRACKED quest objective's exact
## target (NPC / world object / item / the right exit door).
##
## The pointer is available as soon as the tracked quest has a pointable active
## objective. Before the player has any active quest, it points to the NPC who
## offers the next main quest. Hint progress is intentionally irrelevant: quest
## hints can add story context, but basic wayfinding never requires all 3.
## A second light-blue pointer advertises an unaccepted side quest only when its giver
## is in the player's current zone; it never points through exits to side quests.
##
## Off-screen targets use an edge pointer. Once a target enters the viewport,
## the pointer moves beside it and keeps pointing at its exact position instead
## of disappearing. Hidden only while GameManager.ui_blocking_input is true
## (dialogue/battle/cutscene/menus).

const ICON_DIR := "res://assets/ui/objective_compass_v1/icons/"
const ARROW_PATH := ICON_DIR + "compass_arrow.png"
const SIDE_QUEST_OFFER_BADGE_PATH := ICON_DIR + "quest_offer_side.png"
const BADGE_PATHS := {
	"npc": ICON_DIR + "target_npc.png",
	"object": ICON_DIR + "target_object.png",
	"item": ICON_DIR + "target_item.png",
	"enemy": "res://assets/ui/minimap_v1/icons/zone_boss_arena.png",
	"enemy_any": "res://assets/ui/minimap_v1/icons/zone_boss_arena.png",
}

const ARROW_SIZE := 30.0
const BADGE_SIZE := 20.0
const EDGE_MARGIN := 64.0
const TARGET_POINTER_GAP := 42.0
const SIDE_EDGE_MARGIN := 94.0
const SIDE_TARGET_POINTER_GAP := 58.0
const SIDE_QUEST_COLOR := Color(0.46, 0.82, 1.0, 1.0)
const SIDE_QUEST_TINT_SHADER := """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(0.46, 0.82, 1.0, 1.0);
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float value = max(source.r, max(source.g, source.b));
	COLOR = vec4(tint_color.rgb * value, source.a * tint_color.a);
}
"""
const FADE_SPEED := 8.0

var _main: Node = null
var _player: Node2D = null

var _arrow: TextureRect
var _badge: TextureRect
var _root: Control
var _side_arrow: TextureRect
var _side_badge: TextureRect
var _side_root: Control

var _intent: Dictionary = {}  # {entity_kind, entity_id, zone_id} or {}
var _side_offer_intent: Dictionary = {}
var _target_alpha := 0.0
var _side_target_alpha := 0.0
var _pulse_t := 0.0


func _ready() -> void:
	layer = 41  # below PartyHudView (43) / quest tracker (44) — a quiet corner element
	_build()
	QuestManager.quests_changed.connect(_on_quests_changed)


func setup(main_node: Node, player_node: Node2D) -> void:
	_main = main_node
	_player = player_node
	_refresh_intent()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_badge = TextureRect.new()
	_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_badge.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_badge.pivot_offset = _badge.size * 0.5
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_badge)

	_arrow = TextureRect.new()
	if _has(ARROW_PATH):
		_arrow.texture = load(ARROW_PATH) as Texture2D
	_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_arrow.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_arrow)

	_root.modulate.a = 0.0

	_side_root = Control.new()
	_side_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_side_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_side_root)

	_side_badge = TextureRect.new()
	_side_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_side_badge.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_side_badge.pivot_offset = _side_badge.size * 0.5
	_side_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_root.add_child(_side_badge)

	_side_arrow = TextureRect.new()
	if _has(ARROW_PATH):
		_side_arrow.texture = load(ARROW_PATH) as Texture2D
	_side_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_side_arrow.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	_side_arrow.pivot_offset = _side_arrow.size * 0.5
	_side_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_root.add_child(_side_arrow)
	var side_tint_material := _create_side_quest_tint_material()
	_side_badge.material = side_tint_material
	_side_arrow.material = side_tint_material
	_side_root.modulate.a = 0.0


func _on_quests_changed() -> void:
	_refresh_intent()


func _create_side_quest_tint_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SIDE_QUEST_TINT_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint_color", SIDE_QUEST_COLOR)
	return material


func _refresh_intent() -> void:
	_intent = {}
	_side_offer_intent = {}
	if _main == null:
		return
	_side_offer_intent = _resolve_side_quest_offer_intent()
	var tracked: Dictionary = QuestManager.tracked_quest_and_objective()
	if tracked.is_empty():
		_intent = _resolve_main_quest_offer_intent()
		return
	var quest: Dictionary = tracked.get("quest", {}) as Dictionary
	var objective: Dictionary = tracked.get("objective", {}) as Dictionary
	if objective.is_empty():
		return
	var intent: Dictionary = _resolve_intent(quest, objective)
	if intent.is_empty():
		return
	_intent = intent


func _resolve_main_quest_offer_intent() -> Dictionary:
	var offer: Dictionary = QuestManager.main_quest_to_receive()
	if offer.is_empty():
		return {}
	var npc_id := str(offer.get("npc_id", ""))
	if npc_id.is_empty():
		return {}
	return {
		"entity_kind": "npc",
		"entity_id": npc_id,
		"zone_id": str(offer.get("zone_id", "")),
		"purpose": "main_quest_giver",
	}


func _resolve_side_quest_offer_intent() -> Dictionary:
	var current_zone_id := str(GameManager.get_scene_context().get("zone_id", ""))
	var offers: Array[Dictionary] = QuestManager.side_quest_offers_in_zone(current_zone_id)
	if offers.is_empty():
		return {}
	var best_offer: Dictionary = offers[0]
	var best_distance_sq := INF
	if _player != null and is_instance_valid(_player):
		for offer in offers:
			var npc_id := str(offer.get("npc_id", ""))
			var position: Vector2 = _main.find_entity_global_position("npc", npc_id)
			if position == Vector2.INF:
				continue
			var distance_sq := _player.global_position.distance_squared_to(position)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_offer = offer
	var npc_id := str(best_offer.get("npc_id", ""))
	if npc_id.is_empty():
		return {}
	return {
		"entity_kind": "npc",
		"entity_id": npc_id,
		"zone_id": current_zone_id,
		"purpose": "side_quest_giver",
	}


## Maps an objective's kind to a concrete pointable target: an NPC / world
## object / item pickup / boss-marked enemy in its zone, or (for `reach`) the
## zone itself, resolved to the right exit door by find_exit_toward_zone.
func _resolve_intent(quest: Dictionary, objective: Dictionary) -> Dictionary:
	var zone_id := str(objective.get("zone_id", ""))
	match str(objective.get("kind", "")):
		"talk", "choice", "deliver":
			var npc_id := str(objective.get("target_npc_id", ""))
			if npc_id.is_empty():
				return {}
			return {"entity_kind": "npc", "entity_id": npc_id, "zone_id": zone_id}
		"collect":
			var item_id := str(objective.get("item_id", objective.get("item_ref", "")))
			if item_id.is_empty():
				return {}
			var object_id: String = ObjectInteractionManager.object_id_for_objective(
				str(quest.get("id", "")), str(objective.get("id", "")),
			)
			if not object_id.is_empty():
				return {"entity_kind": "object", "entity_id": object_id, "zone_id": zone_id}
			return {"entity_kind": "item", "entity_id": item_id, "zone_id": zone_id}
		"defeat":
			var enemy_id := str(objective.get("target_enemy_id", ""))
			if enemy_id.is_empty():
				# Count-based defeat objectives mean "any N hostiles" and therefore
				# have no single authored target_enemy_id. Track the nearest remaining
				# hostile and resolve it again every frame as enemies are cleared.
				if int(objective.get("count", 0)) > 0:
					return {"entity_kind": "enemy_any", "entity_id": "", "zone_id": zone_id}
				return {}
			return {"entity_kind": "enemy", "entity_id": enemy_id, "zone_id": zone_id}
		"reach":
			return {"entity_kind": "exit", "entity_id": "", "zone_id": zone_id}
	return {}


func _resolve_target_position() -> Vector2:
	return _resolve_target_position_for(_intent)


func _resolve_target_position_for(intent: Dictionary) -> Vector2:
	if intent.is_empty() or _main == null:
		return Vector2.INF
	var target_zone_id := str(intent.get("zone_id", ""))
	var current_zone_id := str(GameManager.get_scene_context().get("zone_id", ""))
	if not target_zone_id.is_empty() and target_zone_id != current_zone_id:
		return _main.find_exit_toward_zone(target_zone_id)
	var entity_kind := str(intent.get("entity_kind", ""))
	if entity_kind.is_empty() or entity_kind == "exit":
		return Vector2.INF
	if entity_kind == "enemy_any":
		if _player == null or not is_instance_valid(_player) or not _main.has_method("find_nearest_hostile_global_position"):
			return Vector2.INF
		return _main.call("find_nearest_hostile_global_position", _player.global_position) as Vector2
	return _main.find_entity_global_position(entity_kind, str(intent.get("entity_id", "")))


func _process(delta: float) -> void:
	_pulse_t += delta
	var show_now := false
	var target_world: Vector2 = Vector2.INF
	var show_side_now := false
	var side_target_world: Vector2 = Vector2.INF

	if not GameManager.ui_blocking_input and _player != null and is_instance_valid(_player):
		if not _intent.is_empty():
			target_world = _resolve_target_position()
			if target_world != Vector2.INF:
				show_now = _update_pointer(target_world)
		if not _side_offer_intent.is_empty():
			side_target_world = _resolve_target_position_for(_side_offer_intent)
			if side_target_world != Vector2.INF:
				show_side_now = _update_pointer_for(
					side_target_world, _side_offer_intent, _side_arrow, _side_badge,
					SIDE_EDGE_MARGIN, SIDE_TARGET_POINTER_GAP,
				)

	_target_alpha = 1.0 if show_now else 0.0
	_side_target_alpha = 1.0 if show_side_now else 0.0
	_root.modulate.a = lerpf(_root.modulate.a, _target_alpha, minf(delta * FADE_SPEED, 1.0))
	_side_root.modulate.a = lerpf(_side_root.modulate.a, _side_target_alpha, minf(delta * FADE_SPEED, 1.0))
	var pulse: float = 1.0 + sin(_pulse_t * 3.2) * 0.06
	_arrow.scale = Vector2.ONE * pulse
	var side_pulse: float = 1.0 + sin(_pulse_t * 3.2 + PI) * 0.06
	_side_arrow.scale = Vector2.ONE * side_pulse


## Lays out a persistent pointer. Off-screen it hugs the viewport edge; on-screen
## it sits just inward from the target and points at the target's exact center.
func _update_pointer(target_world: Vector2) -> bool:
	return _update_pointer_for(
		target_world, _intent, _arrow, _badge, EDGE_MARGIN, TARGET_POINTER_GAP,
	)


func _update_pointer_for(
		target_world: Vector2,
		intent: Dictionary,
		arrow: TextureRect,
		badge: TextureRect,
		edge_margin: float,
		target_pointer_gap: float,
	) -> bool:
	var vp_size := get_viewport().get_visible_rect().size
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * target_world
	var center := vp_size * 0.5
	var viewport_rect := Rect2(Vector2.ZERO, vp_size)
	var pointer_center: Vector2
	var target_direction: Vector2

	if viewport_rect.has_point(screen_pos):
		# Place the pointer on the side facing the screen centre. This keeps it
		# readable at every edge and leaves the target sprite unobstructed.
		var inward := center - screen_pos
		if inward.length_squared() < 1.0:
			inward = Vector2.UP
		inward = inward.normalized()
		pointer_center = screen_pos + inward * target_pointer_gap
		pointer_center.x = clampf(pointer_center.x, edge_margin, vp_size.x - edge_margin)
		pointer_center.y = clampf(pointer_center.y, edge_margin, vp_size.y - edge_margin)
		target_direction = screen_pos - pointer_center
	else:
		var half_size := vp_size * 0.5 - Vector2.ONE * edge_margin
		var outward := screen_pos - center
		if outward.length_squared() < 1.0:
			outward = Vector2.UP
		var scale_x: float = INF if outward.x == 0.0 else half_size.x / absf(outward.x)
		var scale_y: float = INF if outward.y == 0.0 else half_size.y / absf(outward.y)
		pointer_center = center + outward * minf(scale_x, scale_y)
		target_direction = screen_pos - pointer_center

	if target_direction.length_squared() < 1.0:
		target_direction = screen_pos - center
	if target_direction.length_squared() < 1.0:
		target_direction = Vector2.DOWN
	var target_normal := target_direction.normalized()
	arrow.position = (pointer_center - arrow.size * 0.5).round()
	arrow.rotation = target_normal.angle() + PI * 0.5  # arrow art points up by default

	var badge_center := pointer_center - target_normal * 24.0
	badge.position = (badge_center - badge.size * 0.5).round()
	var badge_path := SIDE_QUEST_OFFER_BADGE_PATH \
		if str(intent.get("purpose", "")) == "side_quest_giver" \
		else str(BADGE_PATHS.get(str(intent.get("entity_kind", "")), ""))
	if not badge_path.is_empty() and _has(badge_path):
		badge.texture = load(badge_path) as Texture2D
		badge.visible = true
	else:
		badge.visible = false
	return true


func _has(path: String) -> bool:
	return ResourceLoader.exists(path)
