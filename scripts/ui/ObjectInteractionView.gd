extends CanvasLayer
## The modal that plays out a world-object interaction: examine the object, then
## search / give / exchange / inspect. On success it reveals the granted item(s)
## with a golden light beam and sparkle — the "you found it" beat.
##
## Authored crisp in native 960x540 (unscaled layer), styled to match the game's
## dialogue_v2 art kit. Self-frees on close and emits `closed`.

signal closed

const PANEL_TEX := "res://assets/ui/dialogue_v2/dialogue_panel.png"
const GEM_TEX := "res://assets/ui/dialogue_v2/divider_gem.png"
const FRAME_TEX := "res://assets/ui/dialogue_v2/portrait_frame.png"
const SLOT_TEX := "res://assets/ui/inventory/slot.png"

const PANEL_RECT := Rect2(250, 120, 460, 300)

enum Stage { EXAMINE, RESULT }

var _object_id: String = ""
var _contract: Dictionary = {}
var _stage: int = Stage.EXAMINE
var _primary_enabled: bool = true
var _closing: bool = false

var _object_name: String = ""
var _root: Control
var _panel: Panel
var _header: Label
var _body: Label
var _reveal_box: HBoxContainer
var _beam: TextureRect
var _burst: TextureRect
var _sparkles: CPUParticles2D
var _action_label: Label
var _action_panel: Panel


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


# ── public ──────────────────────────────────────────────────────────────────────


func open_object(object_id: String) -> void:
	_object_id = object_id
	_contract = ObjectInteractionManager.contract_for(object_id)
	if _contract.is_empty():
		_close()
		return
	GameManager.ui_blocking_input = true
	_object_name = str(_contract.get("name", ""))
	_header.text = _object_name.to_upper()
	_present_initial()
	# entrance animation
	_root.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ── state presentation ────────────────────────────────────────────────────────


func _present_initial() -> void:
	_stage = Stage.EXAMINE
	_clear_reveal()
	var archetype := str(_contract.get("archetype", "inspect"))
	var used := ObjectInteractionManager.is_used(_object_id) and bool(_contract.get("one_shot", false))

	if used:
		_body.text = str(_contract.get("done_text", _contract.get("examine_text", "")))
		_set_action("Đóng", true)
		return
	if archetype == "inspect":
		_body.text = str(_contract.get("examine_text", ""))
		_set_action("Đóng", true)
		return

	var requires: Array = _contract.get("requires", []) as Array
	if not requires.is_empty() and not ObjectInteractionManager.can_fulfill(_contract):
		_body.text = str(_contract.get("locked_text", ""))
		_render_requirements(ObjectInteractionManager.missing_requirements(_contract))
		_set_action("Đóng", true)
		return

	# actionable: examine text + a verb the player confirms to resolve
	_body.text = str(_contract.get("examine_text", ""))
	if not requires.is_empty():
		_render_requirements(_requirement_rows(requires))
	_set_action(str(_contract.get("verb", "Tương tác")), true)


func _resolve() -> void:
	var result: Dictionary = ObjectInteractionManager.run_interaction(_object_id)
	var status := str(result.get("status", "none"))
	_stage = Stage.RESULT
	_clear_reveal()

	match status:
		"success":
			_body.text = str(result.get("text", ""))
			var granted: Array = result.get("granted", []) as Array
			if not granted.is_empty():
				_header.text = "VẬT PHẨM MỚI"  # the classic "item get" beat
				_reveal_items(granted)
			else:
				_header.text = _object_name.to_upper()
			_set_action("Tiếp tục", true)
		"locked":
			_body.text = str(result.get("text", ""))
			_render_requirements(result.get("missing", []) as Array)
			_set_action("Đóng", true)
		"done", "inspect":
			_body.text = str(result.get("text", ""))
			_set_action("Đóng", true)
		_:
			_close()


# ── reveal visuals ──────────────────────────────────────────────────────────────


func _reveal_items(items: Array) -> void:
	_beam.visible = true
	_beam.modulate.a = 0.0
	create_tween().tween_property(_beam, "modulate:a", 0.85, 0.35)
	_burst.visible = true
	_burst.modulate.a = 0.0
	_burst.pivot_offset = _burst.size * 0.5
	_burst.scale = Vector2(0.6, 0.6)
	var burst_tween := create_tween()
	burst_tween.tween_property(_burst, "modulate:a", 0.9, 0.3)
	burst_tween.parallel().tween_property(_burst, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tween.tween_property(_burst, "modulate:a", 0.55, 0.6)
	_sparkles.emitting = true
	_sparkles.restart()

	var i := 0
	for entry in items:
		if not (entry is Dictionary):
			continue
		var card := _make_item_card(entry as Dictionary, true)
		_reveal_box.add_child(card)
		card.modulate.a = 0.0
		card.scale = Vector2(0.6, 0.6)
		card.pivot_offset = Vector2(48, 56)
		var tween := create_tween()
		tween.tween_interval(0.08 * i)
		tween.tween_property(card, "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


func _render_requirements(rows: Array) -> void:
	for entry in rows:
		if not (entry is Dictionary):
			continue
		var card := _make_item_card(entry as Dictionary, false)
		_reveal_box.add_child(card)


func _requirement_rows(requires: Array) -> Array:
	var rows: Array = []
	for req in requires:
		if not (req is Dictionary):
			continue
		var item_id := str((req as Dictionary).get("item_id", ""))
		var need := maxi(1, int((req as Dictionary).get("count", 1)))
		rows.append({
			"item_id": item_id,
			"name": str((req as Dictionary).get("name", item_id)),
			"need": need,
			"have": InventoryManager.count_of(item_id),
		})
	return rows


func _make_item_card(entry: Dictionary, is_grant: bool) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(96, 112)

	var frame := _texture_or_null(SLOT_TEX)
	var slot := Panel.new()
	slot.size = Vector2(80, 80)
	slot.position = Vector2(8, 0)
	if frame != null:
		var style := StyleBoxTexture.new()
		style.texture = frame
		style.set_texture_margin_all(18.0)
		slot.add_theme_stylebox_override("panel", style)
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.02, 0.03, 0.05, 0.9)
		flat.border_color = UiKit.COLOR_PANEL_BORDER
		flat.set_border_width_all(2)
		flat.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", flat)
	card.add_child(slot)

	var icon := InventoryManager.icon_for(InventoryManager.item_def(str(entry.get("item_id", ""))))
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.position = Vector2(16, 8)
		icon_rect.size = Vector2(64, 64)
		if not is_grant:
			var have := int(entry.get("have", 0))
			var need := int(entry.get("need", 1))
			icon_rect.modulate = Color.WHITE if have >= need else Color(0.5, 0.5, 0.55, 0.8)
		card.add_child(icon_rect)

	var name_label := UiKit.make_label(str(entry.get("name", "")), 11, UiKit.COLOR_ACCENT if is_grant else UiKit.COLOR_TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.position = Vector2(0, 82)
	name_label.size = Vector2(96, 28)
	card.add_child(name_label)

	if not is_grant:
		var have := int(entry.get("have", 0))
		var need := int(entry.get("need", 1))
		var count_label := UiKit.make_label("%d / %d" % [have, need], 10, Color(0.55, 0.85, 0.55, 1.0) if have >= need else Color(0.95, 0.55, 0.45, 1.0))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.position = Vector2(8, 60)
		count_label.size = Vector2(64, 14)
		card.add_child(count_label)
	return card


func _clear_reveal() -> void:
	for child in _reveal_box.get_children():
		child.queue_free()
	if _beam != null:
		_beam.visible = false
	if _burst != null:
		_burst.visible = false
	if _sparkles != null:
		_sparkles.emitting = false


# ── construction ────────────────────────────────────────────────────────────────


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.03, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = Panel.new()
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size
	var panel_tex := _texture_or_null(PANEL_TEX)
	if panel_tex != null:
		var style := StyleBoxTexture.new()
		style.texture = panel_tex
		style.set_texture_margin_all(42.0)
		style.set_content_margin_all(8.0)
		_panel.add_theme_stylebox_override("panel", style)
	else:
		_panel.add_theme_stylebox_override("panel", _glass_style())
	_root.add_child(_panel)

	# radial golden burst (the "item get" glow behind the revealed item)
	_burst = TextureRect.new()
	var burst_grad := Gradient.new()
	burst_grad.set_color(0, Color(1.0, 0.92, 0.6, 0.95))
	burst_grad.set_color(1, Color(1.0, 0.82, 0.4, 0.0))
	var burst_tex := GradientTexture2D.new()
	burst_tex.gradient = burst_grad
	burst_tex.fill = GradientTexture2D.FILL_RADIAL
	burst_tex.fill_from = Vector2(0.5, 0.5)
	burst_tex.fill_to = Vector2(1.0, 0.5)
	burst_tex.width = 256
	burst_tex.height = 256
	_burst.texture = burst_tex
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.stretch_mode = TextureRect.STRETCH_SCALE
	var burst_mat := CanvasItemMaterial.new()
	burst_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_burst.material = burst_mat
	_burst.size = Vector2(300, 220)
	_burst.position = Vector2(PANEL_RECT.size.x * 0.5 - 150, 96)
	_burst.visible = false
	_panel.add_child(_burst)

	# golden reveal beam (behind the item cards)
	_beam = TextureRect.new()
	var beam_grad := Gradient.new()
	beam_grad.set_color(0, Color(1.0, 0.86, 0.45, 0.0))
	beam_grad.set_color(1, Color(1.0, 0.86, 0.45, 0.0))
	beam_grad.add_point(0.5, Color(1.0, 0.9, 0.55, 0.9))
	var beam_tex := GradientTexture2D.new()
	beam_tex.gradient = beam_grad
	beam_tex.width = 256
	beam_tex.height = 16
	beam_tex.fill_from = Vector2(0, 0)
	beam_tex.fill_to = Vector2(1, 0)
	_beam.texture = beam_tex
	_beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_beam.stretch_mode = TextureRect.STRETCH_SCALE
	var beam_mat := CanvasItemMaterial.new()
	beam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beam.material = beam_mat
	_beam.position = Vector2(60, 150)
	_beam.size = Vector2(PANEL_RECT.size.x - 120, 120)
	_beam.rotation = 0.0
	_beam.visible = false
	_panel.add_child(_beam)

	var gem := _texture_or_null(GEM_TEX)
	if gem != null:
		var gem_rect := TextureRect.new()
		gem_rect.texture = gem
		gem_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem_rect.position = Vector2(PANEL_RECT.size.x * 0.5 - 22, -14)
		gem_rect.size = Vector2(44, 28)
		_panel.add_child(gem_rect)

	_header = UiKit.make_label("", 18, UiKit.COLOR_ACCENT)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.position = Vector2(24, 26)
	_header.size = Vector2(PANEL_RECT.size.x - 48, 26)
	_header.clip_text = true
	_panel.add_child(_header)

	var divider := ColorRect.new()
	divider.color = Color(0.76, 0.58, 0.27, 0.5)
	divider.position = Vector2(40, 58)
	divider.size = Vector2(PANEL_RECT.size.x - 80, 1)
	_panel.add_child(divider)

	_body = UiKit.make_label("", 13, UiKit.COLOR_TEXT)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.position = Vector2(34, 72)
	_body.size = Vector2(PANEL_RECT.size.x - 68, 70)
	_panel.add_child(_body)

	_reveal_box = HBoxContainer.new()
	_reveal_box.add_theme_constant_override("separation", 16)
	_reveal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_box.position = Vector2(30, 150)
	_reveal_box.size = Vector2(PANEL_RECT.size.x - 60, 116)
	_panel.add_child(_reveal_box)

	_sparkles = CPUParticles2D.new()
	_sparkles.position = Vector2(PANEL_RECT.size.x * 0.5, 200)
	_sparkles.amount = 24
	_sparkles.lifetime = 1.1
	_sparkles.one_shot = false
	_sparkles.explosiveness = 0.4
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.emission_rect_extents = Vector2(150, 50)
	_sparkles.direction = Vector2(0, -1)
	_sparkles.spread = 40.0
	_sparkles.gravity = Vector2(0, -20)
	_sparkles.initial_velocity_min = 10.0
	_sparkles.initial_velocity_max = 36.0
	_sparkles.scale_amount_min = 1.0
	_sparkles.scale_amount_max = 2.4
	_sparkles.color = Color(1.0, 0.86, 0.5, 0.9)
	_sparkles.emitting = false
	_panel.add_child(_sparkles)

	# action chip at the bottom
	_action_panel = Panel.new()
	_action_panel.size = Vector2(180, 34)
	_action_panel.position = Vector2(PANEL_RECT.size.x * 0.5 - 90, PANEL_RECT.size.y - 50)
	_action_panel.add_theme_stylebox_override("panel", _chip_style())
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_action_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_action_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_activate_primary()
			get_viewport().set_input_as_handled()
	)
	_panel.add_child(_action_panel)

	_action_label = UiKit.make_label("", 12, UiKit.COLOR_TEXT)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_label.position = Vector2(0, 1)
	_action_label.size = _action_panel.size
	_action_panel.add_child(_action_label)


func _set_action(label: String, enabled: bool) -> void:
	_primary_enabled = enabled
	_action_label.text = "%s   [Enter]" % label


# ── input / lifecycle ────────────────────────────────────────────────────────────


func _activate_primary() -> void:
	if _closing:
		return
	if _stage == Stage.EXAMINE:
		var archetype := str(_contract.get("archetype", "inspect"))
		var used := ObjectInteractionManager.is_used(_object_id) and bool(_contract.get("one_shot", false))
		var requires: Array = _contract.get("requires", []) as Array
		var blocked := not requires.is_empty() and not ObjectInteractionManager.can_fulfill(_contract)
		if archetype == "inspect" or used or blocked:
			_close()
		else:
			_resolve()
	else:
		_close()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_accept"):
		_activate_primary()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if _closing:
		return
	_closing = true
	if _sparkles != null:
		_sparkles.emitting = false
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func() -> void:
		GameManager.ui_blocking_input = false
		closed.emit()
		queue_free()
	)


# ── helpers ──────────────────────────────────────────────────────────────────────


func _texture_or_null(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _glass_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.022, 0.034, 0.96)
	style.border_color = Color(0.78, 0.60, 0.28, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 3)
	return style


func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.07, 0.86)
	style.border_color = Color(1.0, 0.78, 0.34, 0.86)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
