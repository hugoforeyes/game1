class_name EnemyTargetHighlight
extends Control
## Selection-only presentation for a foe. The outline inherits the portrait's
## transforms; the overhead marker belongs to the stable enemy HUD rig.

const OUTLINE_SHADER := preload("res://scripts/battle/EnemyTargetOutline.gdshader")
const TARGET_CURSOR_TEXTURE := preload("res://assets/ui/battle/target_cursor.png")

const GOLD_CORE := Color(1.0, 0.79, 0.26, 0.98)
const GOLD_HALO := Color(1.0, 0.52, 0.08, 0.30)
const OVERHEAD_GAP := 6.0
const METADATA_TOP := -18.0

var marker: Control

var _portrait: TextureRect
var _core_outline: TextureRect
var _soft_outline: TextureRect
var _marker_base_position := Vector2.ZERO
var _selected := false
var _enter_tween: Tween
var _bob_tween: Tween
var _glow_tween: Tween


func setup(portrait: TextureRect, slot_size: Vector2) -> void:
	_portrait = portrait
	position = Vector2.ZERO
	size = slot_size
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Two independently sampled rims give a restrained bright core and a softer
	# amber aura without baking variants for every enemy silhouette.
	_soft_outline = _make_outline_layer(2.6, GOLD_HALO)
	_core_outline = _make_outline_layer(1.1, GOLD_CORE)
	_portrait.add_child(_soft_outline)
	_portrait.add_child(_core_outline)

	marker = _build_marker(slot_size)
	add_child(marker)
	_marker_base_position = marker.position
	_set_nodes_visible(false)


func set_selected(selected: bool, animate: bool = true) -> void:
	if _selected == selected:
		return
	_selected = selected
	_kill_tweens()
	marker.position = _marker_base_position
	marker.scale = Vector2.ONE
	if not selected:
		_set_nodes_visible(false)
		return

	_set_nodes_visible(true)
	_set_outline_opacity(0.0 if animate else 1.0, _core_outline)
	_set_outline_opacity(0.0 if animate else 0.52, _soft_outline)
	marker.modulate.a = 0.0 if animate else 1.0
	marker.scale = Vector2(0.82, 0.82) if animate else Vector2.ONE
	if animate:
		_enter_tween = create_tween().set_parallel(true)
		_enter_tween.tween_method(
			_set_outline_opacity.bind(_core_outline), 0.0, 1.0, 0.16)
		_enter_tween.tween_method(
			_set_outline_opacity.bind(_soft_outline), 0.0, 0.52, 0.22)
		_enter_tween.tween_property(marker, "modulate:a", 1.0, 0.14)
		_enter_tween.tween_property(marker, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(
		marker, "position:y", _marker_base_position.y - 3.0, 0.62,
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(
		marker, "position:y", _marker_base_position.y, 0.62,
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_method(
		_set_outline_opacity.bind(_soft_outline), 0.52, 0.30, 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_method(
		_set_outline_opacity.bind(_soft_outline), 0.30, 0.56, 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func is_selected() -> bool:
	return _selected


func marker_bounds() -> Rect2:
	return Rect2(marker.position, marker.size)


func _exit_tree() -> void:
	_kill_tweens()


func _make_outline_layer(display_radius: float, color: Color) -> TextureRect:
	var layer := TextureRect.new()
	layer.texture = _portrait.texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = _portrait.stretch_mode
	# Selection art is filtered independently: pixel portraits stay crisp while
	# the sampled alpha rim remains thin instead of expanding by one source texel.
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.position = Vector2.ZERO
	layer.size = _portrait.size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = OUTLINE_SHADER
	material.set_shader_parameter("outline_color", color)
	material.set_shader_parameter("outline_step", Vector2(
		display_radius / maxf(size.x, 1.0),
		display_radius / maxf(size.y, 1.0),
	))
	layer.material = material
	return layer


func _build_marker(slot_size: Vector2) -> Control:
	# The OpenAIExtension-authored cursor is deliberately kept as one immutable
	# component: its three-pronged silhouette, bevel and inner highlight never
	# drift apart when the marker animates or the enemy slot changes size.
	var marker_size := clampf(slot_size.x * 0.32, 56.0, 68.0)
	var host := Control.new()
	host.size = Vector2(marker_size, marker_size)
	host.position = Vector2(
		(slot_size.x - marker_size) * 0.5,
		METADATA_TOP - OVERHEAD_GAP - marker_size,
	)
	host.pivot_offset = host.size * 0.5
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := TextureRect.new()
	glow.texture = TARGET_CURSOR_TEXTURE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.position = Vector2(-3.0, -3.0)
	glow.size = host.size + Vector2(6.0, 6.0)
	glow.modulate = Color(1.0, 0.56, 0.12, 0.20)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(glow)

	var cursor := TextureRect.new()
	cursor.texture = TARGET_CURSOR_TEXTURE
	cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor.stretch_mode = TextureRect.STRETCH_SCALE
	cursor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cursor.size = host.size
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(cursor)
	return host


func _set_nodes_visible(visible_state: bool) -> void:
	_core_outline.visible = visible_state
	_soft_outline.visible = visible_state
	marker.visible = visible_state
	if not visible_state:
		_set_outline_opacity(0.0, _core_outline)
		_set_outline_opacity(0.0, _soft_outline)


func _set_outline_opacity(value: float, layer: TextureRect) -> void:
	var material := layer.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("opacity", value)


func _kill_tweens() -> void:
	for tween in [_enter_tween, _bob_tween, _glow_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_enter_tween = null
	_bob_tween = null
	_glow_tween = null
