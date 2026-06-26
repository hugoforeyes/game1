extends Node2D
## An interactable quest world-object (chest / clock / shrine / garden …). It sits
## over the object's rendered sprite and gives the player the object/item half of
## the quest loop: search it to find a hidden item, give it an item it needs, or
## exchange. Mirrors the NPC interaction feel — a proximity prompt, a gold "!" when
## its objective is current, and a soft glow so the player reads it as interactable.

const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")

const PLAYER_COLLISION_OFFSET := Vector2(0.0, 28.0)
const PLAYER_COLLISION_HALF := Vector2(10.0, 6.0)
const TOUCH_GROW_PX := 3.0

var object_id: String = ""
var contract: Dictionary = {}

var _player: Node2D = null
var _footprint_center: Vector2 = Vector2.ZERO
var _in_range: bool = false
var _marker: Label = null
var _glow: Sprite2D = null
var _glow_time: float = 0.0
var _view_open: bool = false
var _footprint_rect: Rect2 = Rect2()
var _has_affordance_glow: bool = false


func setup(p_contract: Dictionary, instance: Dictionary, definition: Dictionary, world_context: Dictionary) -> void:
	contract = p_contract
	object_id = str(p_contract.get("object_id", instance.get("interaction_object_id", instance.get("id", ""))))
	_player = world_context.get("player") as Node2D

	var position_tile: Dictionary = instance.get("position_tile", {}) as Dictionary
	var base_tile := Vector2i(int(position_tile.get("x", 0)), int(position_tile.get("y", 0)))
	var size_tiles: Dictionary = definition.get("size_tiles", {}) as Dictionary
	var w: int = maxi(int(size_tiles.get("w", 1)), 1)
	var h: int = maxi(int(size_tiles.get("h", 1)), 1)

	var origin: Vector2 = Vector2(base_tile) * GameManager.TILE_SIZE
	# distance is measured to the footprint RECT, not its center, so big objects are
	# reachable from any adjacent tile (a tall clock tower included).
	_footprint_rect = Rect2(origin, Vector2(w, h) * GameManager.TILE_SIZE)
	_footprint_center = origin + Vector2(w, h) * GameManager.TILE_SIZE * 0.5
	position = _footprint_center

	# A glow only marks objects that reward the player (a hidden item or a quest);
	# pure lore props reveal their prompt on approach so the world stays uncluttered.
	_has_affordance_glow = not (contract.get("grants", []) as Array).is_empty() \
		or not (contract.get("completes", []) as Array).is_empty() \
		or not (contract.get("quest_ids", []) as Array).is_empty()

	if _has_affordance_glow:
		_setup_glow(w, h)
	_setup_marker(h)


func _exit_tree() -> void:
	WorldInteractionManager.clear_owner(self)


func _setup_glow(w: int, h: int) -> void:
	# A soft additive radial bloom hugging the object base — the "you can touch this"
	# affordance. Generated at runtime so it needs no art asset.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.86, 0.45, 0.55))
	gradient.set_color(1, Color(1.0, 0.80, 0.35, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96

	_glow = Sprite2D.new()
	_glow.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	# scale glow to the footprint, sit it slightly low (toward the object's base)
	var glow_w: float = maxf(w, 1) * GameManager.TILE_SIZE * 1.25
	var glow_h: float = maxf(h, 1) * GameManager.TILE_SIZE * 1.05
	_glow.scale = Vector2(glow_w / 96.0, glow_h / 96.0)
	_glow.position = Vector2(0.0, h * GameManager.TILE_SIZE * 0.18)
	_glow.z_index = -1
	_glow.modulate.a = 0.0
	add_child(_glow)


func _setup_marker(h: int) -> void:
	_marker = Label.new()
	_marker.text = "!"
	_marker.position = Vector2(-6, -h * GameManager.TILE_SIZE - 4)
	_marker.add_theme_font_size_override("font_size", 30)
	_marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_marker.add_theme_constant_override("shadow_offset_y", 1)
	_marker.visible = false
	add_child(_marker)


func _process(delta: float) -> void:
	_update_glow(delta)
	_update_marker()

	if GameManager.ui_blocking_input or _player == null or not is_instance_valid(_player):
		if _in_range:
			_in_range = false
			WorldInteractionManager.clear_owner(self)
		return

	var touch_distance := _touch_distance_tiles()
	var touching := touch_distance <= 0.0
	if touching:
		WorldInteractionManager.submit_candidate(
			self,
			"object",
			_current_verb(),
			1,
			touch_distance + _player.global_position.distance_to(_footprint_center) / GameManager.TILE_SIZE * 0.001,
			_player,
			"_on_prompt_confirmed"
		)

	var active := WorldInteractionManager.is_active(self, "object")
	if active and not _in_range:
		_in_range = true
	elif not active and _in_range:
		_in_range = false


func _current_verb() -> String:
	if ObjectInteractionManager.is_used(object_id) and bool(contract.get("one_shot", false)):
		return "Xem lại"
	return str(contract.get("verb", "Quan sát"))


func _touch_distance_tiles() -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	var foot_center := _player.global_position + PLAYER_COLLISION_OFFSET
	var player_rect := Rect2(foot_center - PLAYER_COLLISION_HALF, PLAYER_COLLISION_HALF * 2.0).grow(TOUCH_GROW_PX)
	if player_rect.intersects(_footprint_rect, true):
		return 0.0
	var nearest := Vector2(
		clampf(foot_center.x, _footprint_rect.position.x, _footprint_rect.end.x),
		clampf(foot_center.y, _footprint_rect.position.y, _footprint_rect.end.y),
	)
	return maxf(0.0, foot_center.distance_to(nearest) - PLAYER_COLLISION_HALF.length()) / GameManager.TILE_SIZE


func _update_glow(delta: float) -> void:
	if _glow == null:
		return
	# fade the bloom out once the object has been used up
	var used := ObjectInteractionManager.is_used(object_id) and bool(contract.get("one_shot", false))
	_glow_time += delta
	var target := 0.0 if used else (0.45 + 0.25 * sin(_glow_time * 2.2))
	_glow.modulate.a = lerpf(_glow.modulate.a, target, minf(delta * 4.0, 1.0))


func _update_marker() -> void:
	if _marker == null:
		return
	var should_show := ObjectInteractionManager.marker_for_object(object_id) == "!"
	if should_show and not _marker.visible:
		_marker.visible = true
		var bounce := create_tween().set_loops()
		var base_y := _marker.position.y
		bounce.tween_property(_marker, "position:y", base_y - 6.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bounce.tween_property(_marker, "position:y", base_y, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_marker.set_meta("bounce", bounce)
	elif not should_show and _marker.visible:
		_marker.visible = false
		var bounce: Variant = _marker.get_meta("bounce") if _marker.has_meta("bounce") else null
		if bounce is Tween and (bounce as Tween).is_valid():
			(bounce as Tween).kill()


func _on_prompt_confirmed(_item: String, _index: int) -> void:
	if _view_open or GameManager.ui_blocking_input:
		return
	_view_open = true
	WorldInteractionManager.clear_owner(self)
	var view: CanvasLayer = ObjectInteractionViewScript.new()
	get_tree().root.add_child(view)
	view.closed.connect(_on_view_closed)
	view.open_object(object_id)


func _on_view_closed() -> void:
	_view_open = false
