class_name QuestCompassView
extends CanvasLayer
## A subtle screen-edge pointer toward the TRACKED quest objective's exact
## target (NPC / world object / item / the right exit door).
##
## Two gating modes:
##  - SAME zone as the objective: shown only once the player has heard all 3
##    hint levels for it (QuestManager.objective_fully_hinted /
##    is_objective_fully_hinted) — hints alone guide the player before that,
##    and the compass is the reward for having listened to every one.
##  - DIFFERENT zone than the objective: always shown, hint level irrelevant —
##    basic "which way do I even go" wayfinding shouldn't be locked behind a
##    hint reward the way precise in-zone pinpointing is.
##
## Hidden whenever the target is already comfortably on-screen (its own glow/
## "!" marker/proximity prompt takes over from there) or while
## GameManager.ui_blocking_input is true (dialogue/battle/cutscene/menus).

const ICON_DIR := "res://assets/ui/objective_compass_v1/icons/"
const ARROW_PATH := ICON_DIR + "compass_arrow.png"
const BADGE_PATHS := {
	"npc": ICON_DIR + "target_npc.png",
	"object": ICON_DIR + "target_object.png",
	"item": ICON_DIR + "target_item.png",
	"enemy": "res://assets/ui/minimap_v1/icons/zone_boss_arena.png",
}

const ARROW_SIZE := 30.0
const BADGE_SIZE := 20.0
const EDGE_MARGIN := 64.0
const ONSCREEN_MARGIN := 90.0  # inside this rect, the target's own glow/marker suffices
const FADE_SPEED := 8.0

var _main: Node = null
var _player: Node2D = null

var _arrow: TextureRect
var _badge: TextureRect
var _root: Control

var _intent: Dictionary = {}  # {entity_kind, entity_id, zone_id} or {}
var _target_alpha := 0.0
var _pulse_t := 0.0


func _ready() -> void:
	layer = 41  # below PartyHudView (43) / quest tracker (44) — a quiet corner element
	_build()
	QuestManager.quests_changed.connect(_on_quests_changed)
	QuestManager.objective_fully_hinted.connect(_on_objective_fully_hinted)


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


func _on_quests_changed() -> void:
	_refresh_intent()


func _on_objective_fully_hinted(_quest_id: String, _objective_id: String) -> void:
	_refresh_intent()


func _refresh_intent() -> void:
	_intent = {}
	if _main == null:
		return
	var tracked: Dictionary = QuestManager.tracked_quest_and_objective()
	if tracked.is_empty():
		return
	var quest: Dictionary = tracked.get("quest", {}) as Dictionary
	var objective: Dictionary = tracked.get("objective", {}) as Dictionary
	if objective.is_empty():
		return
	var intent: Dictionary = _resolve_intent(quest, objective)
	if intent.is_empty():
		return
	var target_zone_id := str(intent.get("zone_id", ""))
	var current_zone_id := str(GameManager.get_scene_context().get("zone_id", ""))
	var in_target_zone := target_zone_id.is_empty() or target_zone_id == current_zone_id
	if in_target_zone:
		# Precise in-zone pinpointing is the reward for hearing every hint.
		var quest_id := str(quest.get("id", ""))
		var objective_id := str(objective.get("id", ""))
		if not QuestManager.is_objective_fully_hinted(quest_id, objective_id):
			return
	# Different zone than the objective: always point the way, hint level or not —
	# basic wayfinding shouldn't be locked behind a hint reward.
	_intent = intent


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
				return {}
			return {"entity_kind": "enemy", "entity_id": enemy_id, "zone_id": zone_id}
		"reach":
			return {"entity_kind": "exit", "entity_id": "", "zone_id": zone_id}
	return {}


func _resolve_target_position() -> Vector2:
	if _intent.is_empty() or _main == null:
		return Vector2.INF
	var target_zone_id := str(_intent.get("zone_id", ""))
	var current_zone_id := str(GameManager.get_scene_context().get("zone_id", ""))
	if not target_zone_id.is_empty() and target_zone_id != current_zone_id:
		return _main.find_exit_toward_zone(target_zone_id)
	var entity_kind := str(_intent.get("entity_kind", ""))
	if entity_kind.is_empty() or entity_kind == "exit":
		return Vector2.INF
	return _main.find_entity_global_position(entity_kind, str(_intent.get("entity_id", "")))


func _process(delta: float) -> void:
	_pulse_t += delta
	var show_now := false
	var target_world: Vector2 = Vector2.INF

	if not _intent.is_empty() and not GameManager.ui_blocking_input and _player != null and is_instance_valid(_player):
		target_world = _resolve_target_position()
		if target_world != Vector2.INF:
			show_now = _update_pointer(target_world)

	_target_alpha = 1.0 if show_now else 0.0
	_root.modulate.a = lerpf(_root.modulate.a, _target_alpha, minf(delta * FADE_SPEED, 1.0))
	var pulse: float = 1.0 + sin(_pulse_t * 3.2) * 0.06
	_arrow.scale = Vector2.ONE * pulse


## Returns true if the arrow should be visible (target off-screen enough to
## need pointing at). Also lays out the arrow/badge when true.
func _update_pointer(target_world: Vector2) -> bool:
	var vp_size := get_viewport().get_visible_rect().size
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * target_world
	var center := vp_size * 0.5
	var onscreen_rect := Rect2(
		Vector2(ONSCREEN_MARGIN, ONSCREEN_MARGIN),
		vp_size - Vector2(ONSCREEN_MARGIN, ONSCREEN_MARGIN) * 2.0,
	)
	if onscreen_rect.has_point(screen_pos):
		return false  # close enough that the target's own glow/marker takes over

	var half_size := vp_size * 0.5 - Vector2.ONE * EDGE_MARGIN
	var direction: Vector2 = screen_pos - center
	if direction == Vector2.ZERO:
		return false
	var scale_x: float = INF if direction.x == 0.0 else half_size.x / absf(direction.x)
	var scale_y: float = INF if direction.y == 0.0 else half_size.y / absf(direction.y)
	var edge_point: Vector2 = center + direction * minf(scale_x, scale_y)

	_arrow.position = (edge_point - _arrow.size * 0.5).round()
	_arrow.rotation = direction.angle() + PI * 0.5  # arrow art points up by default

	var badge_offset: Vector2 = direction.normalized() * -22.0
	_badge.position = (edge_point + badge_offset - _badge.size * 0.5).round()
	var badge_path: String = BADGE_PATHS.get(str(_intent.get("entity_kind", "")), "")
	if not badge_path.is_empty() and _has(badge_path):
		_badge.texture = load(badge_path) as Texture2D
		_badge.visible = true
	else:
		_badge.visible = false
	return true


func _has(path: String) -> bool:
	return ResourceLoader.exists(path)
