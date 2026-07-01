extends Area2D
## A glittering item lying in the world — walk over it to pick it up.
## Visual: the item's AI icon bobbing over a glow, with a sparkle pulse.

var item_id: String = ""
var pickup_id: String = ""

var _icon_rect: Sprite2D
var _glow: Sprite2D


func setup(definition: Dictionary, tile: Vector2i, p_pickup_id: String = "") -> void:
	item_id = str(definition.get("id", ""))
	pickup_id = p_pickup_id
	global_position = Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	shape.shape = circle
	add_child(shape)

	var icon: Texture2D = InventoryManager.icon_for(definition)
	_glow = Sprite2D.new()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = glow_material
	_glow.modulate = Color(1.0, 0.92, 0.6, 0.35)
	add_child(_glow)

	_icon_rect = Sprite2D.new()
	_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if icon != null:
		_icon_rect.texture = icon
		_icon_rect.scale = Vector2(0.45, 0.45)  # 48px icon → ~22px in world
		_glow.texture = icon
		_glow.scale = Vector2(0.6, 0.6)
	add_child(_icon_rect)

	# Bob + glow pulse, forever.
	var bob := create_tween().set_loops()
	bob.tween_property(_icon_rect, "position:y", -10.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.parallel().tween_property(_glow, "modulate:a", 0.55, 0.9)
	bob.tween_property(_icon_rect, "position:y", -2.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.parallel().tween_property(_glow, "modulate:a", 0.25, 0.9)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.get("camera") == null:
		return  # only the player carries a camera
	set_deferred("monitoring", false)
	InventoryManager.add_item(item_id)
	GameManager.mark_item_pickup_collected(pickup_id)
	var sparkle := create_tween()
	sparkle.tween_property(self, "scale", Vector2(1.5, 1.5), 0.18)
	sparkle.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	sparkle.parallel().tween_property(_icon_rect, "position:y", -16.0, 0.2)
	sparkle.tween_callback(queue_free)
