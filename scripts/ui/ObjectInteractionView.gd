extends CanvasLayer
## The modal that plays out a world-object interaction: examine the object, then
## search / give / exchange / inspect. On success it reveals the granted item(s)
## with a golden light beam and sparkle — the "you found it" beat.
##
## Authored for the project's native 1024x576 viewport, anchored from the true
## viewport center so wider outputs stay precise. Self-frees on close and emits
## `closed`.

signal closed

const PANEL_TEX := "res://assets/ui/item_reveal_v2/frame.png"
const DIVIDER_TEX := "res://assets/ui/dialogue_v2/divider_gem.png"
const SLOT_TEX := "res://assets/ui/inventory/slot.png"
const SLOT_REVEAL_TEX := "res://assets/ui/aaa_kit_v1/slot_selected.png"

const PANEL_SIZE := Vector2(600, 384)
const BODY_REVEAL_RECT := Rect2(54, 117, 492, 36)
const BODY_NARRATIVE_RECT := Rect2(54, 117, 492, 161)
const REVEAL_RECT := Rect2(44, 153, 512, 128)
const ACTION_SIZE := Vector2(212, 36)

enum Stage { EXAMINE, RESULT }

var _object_id: String = ""
var _contract: Dictionary = {}
var _stage: int = Stage.EXAMINE
var _primary_enabled: bool = true
var _closing: bool = false
# Driven by AnnouncementCenter as the in-conversation "item get" ceremony —
# skips the examine flow and leaves input-blocking to the ceremony host.
var _announce_mode: bool = false
var _accept_after_ms: int = 0

var _object_name: String = ""
var _root: Control
var _panel: Panel
var _eyebrow: Label
var _header: Label
var _body: Label
var _reveal_box: HBoxContainer
var _beam: TextureRect
var _burst: TextureRect
var _sparkles: CPUParticles2D
var _action_label: Label
var _action_panel: Panel
var _action_keycap: Panel


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
	_set_heading(_object_name, "KHÁM PHÁ")
	_present_initial()
	# entrance animation
	_root.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## AnnouncementCenter entry: reuse this screen as the "you received items"
## ceremony during a conversation. Jumps straight to the golden reveal stage;
## the items were already added to the inventory — this is display only.
func open_item_announcement(items: Array, body_text: String = "") -> void:
	_announce_mode = true
	_accept_after_ms = Time.get_ticks_msec() + 450
	_stage = Stage.RESULT
	_object_name = ""
	_set_heading("VẬT PHẨM MỚI", "ĐÃ NHẬN ĐƯỢC")
	_body.text = body_text if not body_text.is_empty() else "Đã thêm vào túi đồ của bạn."
	_clear_reveal()
	_reveal_items(items)
	_set_action("Tiếp tục", true)

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
				_set_heading("VẬT PHẨM MỚI", "KHÁM PHÁ THÀNH CÔNG")
				_reveal_items(granted)
			else:
				_set_heading(_object_name, "TƯƠNG TÁC HOÀN TẤT")
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
	_set_content_layout(true)
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

	var valid_count := 0
	for entry in items:
		if entry is Dictionary:
			valid_count += 1
	var card_width := 116.0
	if valid_count > 0:
		card_width = minf(
			180.0,
			floorf((REVEAL_RECT.size.x - 8.0 * float(valid_count - 1)) / float(valid_count)),
		)
	var i := 0
	for entry in items:
		if not (entry is Dictionary):
			continue
		var card := _make_item_card(entry as Dictionary, true, card_width)
		_reveal_box.add_child(card)
		card.modulate.a = 0.0
		card.scale = Vector2(0.72, 0.72)
		card.pivot_offset = card.custom_minimum_size * 0.5
		var tween := create_tween()
		tween.tween_interval(0.08 * i)
		tween.tween_property(card, "modulate:a", 1.0, 0.18)
		tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


func _render_requirements(rows: Array) -> void:
	_set_content_layout(true)
	for entry in rows:
		if not (entry is Dictionary):
			continue
		var card := _make_item_card(entry as Dictionary, false, 116.0)
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


func _make_item_card(entry: Dictionary, is_grant: bool, card_width: float) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(card_width, 128)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slot_size := Vector2(96, 96)
	var slot_position := Vector2((card_width - slot_size.x) * 0.5, 0)
	if is_grant:
		var card_glow := TextureRect.new()
		var glow_gradient := Gradient.new()
		glow_gradient.set_color(0, Color(1.0, 0.83, 0.38, 0.34))
		glow_gradient.set_color(1, Color(0.42, 0.75, 1.0, 0.0))
		var glow_texture := GradientTexture2D.new()
		glow_texture.gradient = glow_gradient
		glow_texture.fill = GradientTexture2D.FILL_RADIAL
		glow_texture.fill_from = Vector2(0.5, 0.5)
		glow_texture.fill_to = Vector2(1.0, 0.5)
		glow_texture.width = 128
		glow_texture.height = 128
		card_glow.texture = glow_texture
		card_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_glow.stretch_mode = TextureRect.STRETCH_SCALE
		card_glow.position = Vector2((card_width - 118.0) * 0.5, -11)
		card_glow.size = Vector2(118, 118)
		card_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow_material := CanvasItemMaterial.new()
		glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		card_glow.material = glow_material
		card.add_child(card_glow)

	var slot_texture := _texture_or_null(SLOT_REVEAL_TEX if is_grant else SLOT_TEX)
	if slot_texture != null:
		var slot := TextureRect.new()
		slot.texture = slot_texture
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_SCALE
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		slot.position = slot_position
		slot.size = slot_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(slot)
	else:
		var slot_fallback := Panel.new()
		slot_fallback.position = slot_position
		slot_fallback.size = slot_size
		slot_fallback.add_theme_stylebox_override("panel", _slot_fallback_style())
		slot_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(slot_fallback)

	var icon := InventoryManager.icon_for(InventoryManager.item_def(str(entry.get("item_id", ""))))
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.position = Vector2((card_width - 66.0) * 0.5, 14)
		icon_rect.size = Vector2(66, 66)
		if not is_grant:
			var have := int(entry.get("have", 0))
			var need := int(entry.get("need", 1))
			icon_rect.modulate = Color.WHITE if have >= need else Color(0.5, 0.5, 0.55, 0.8)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon_rect)

	var name_label := UiKit.make_label_strong(str(entry.get("name", "")), 11, Color("f5ead5") if is_grant else UiKit.COLOR_TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.position = Vector2(0, 96)
	name_label.size = Vector2(card_width, 32)
	name_label.clip_text = true
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(name_label)

	# quantity badge on the slot corner (grants of ×2 and up)
	if is_grant and int(entry.get("count", 1)) > 1:
		var badge := Panel.new()
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Color(0.06, 0.05, 0.03, 0.92)
		badge_style.border_color = Color(1.0, 0.78, 0.34, 0.86)
		badge_style.set_border_width_all(1)
		badge_style.set_corner_radius_all(5)
		badge.add_theme_stylebox_override("panel", badge_style)
		badge.size = Vector2(34, 20)
		badge.position = Vector2(slot_position.x + slot_size.x - 27, 72)
		card.add_child(badge)
		var badge_label := UiKit.make_label_strong("×%d" % int(entry.get("count", 1)), 10, Color("ffe3a0"))
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(badge_label)

	if not is_grant:
		var have := int(entry.get("have", 0))
		var need := int(entry.get("need", 1))
		var count_label := UiKit.make_label("%d / %d" % [have, need], 10, Color(0.55, 0.85, 0.55, 1.0) if have >= need else Color(0.95, 0.55, 0.45, 1.0))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.position = Vector2((card_width - 70.0) * 0.5, 69)
		count_label.size = Vector2(70, 16)
		card.add_child(count_label)
	return card


func _clear_reveal() -> void:
	for child in _reveal_box.get_children():
		_reveal_box.remove_child(child)
		child.queue_free()
	_set_content_layout(false)
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
	dim.color = Color(0.006, 0.009, 0.020, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	# A soft vignette keeps the ceremony legible over both bright exploration
	# scenes and high-contrast battle backdrops without flattening the whole game.
	var vignette := TextureRect.new()
	var vignette_gradient := Gradient.new()
	vignette_gradient.set_color(0, Color(0.04, 0.07, 0.14, 0.02))
	vignette_gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.42))
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = vignette_gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(1.0, 0.5)
	vignette_texture.width = 1024
	vignette_texture.height = 576
	vignette.texture = vignette_texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vignette)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.size = PANEL_SIZE
	_panel.position = -PANEL_SIZE * 0.5 + Vector2(0, 5)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(_panel)

	var panel_shadow := Panel.new()
	panel_shadow.position = Vector2(27, 28)
	panel_shadow.size = Vector2(PANEL_SIZE.x - 54, PANEL_SIZE.y - 56)
	panel_shadow.add_theme_stylebox_override("panel", _panel_shadow_style())
	panel_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(panel_shadow)

	var panel_tex := _texture_or_null(PANEL_TEX)
	if panel_tex != null:
		var panel_frame := TextureRect.new()
		panel_frame.texture = panel_tex
		panel_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		panel_frame.stretch_mode = TextureRect.STRETCH_SCALE
		panel_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		panel_frame.size = PANEL_SIZE
		panel_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(panel_frame)
	else:
		var fallback_panel := Panel.new()
		fallback_panel.position = Vector2(18, 18)
		fallback_panel.size = PANEL_SIZE - Vector2(36, 36)
		fallback_panel.add_theme_stylebox_override("panel", _glass_style())
		fallback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(fallback_panel)

	# Elliptical item halo: smooth on every edge, unlike the old rectangular beam.
	_burst = TextureRect.new()
	var burst_grad := Gradient.new()
	burst_grad.set_color(0, Color(1.0, 0.88, 0.48, 0.52))
	burst_grad.set_color(1, Color(0.32, 0.66, 1.0, 0.0))
	var burst_tex := GradientTexture2D.new()
	burst_tex.gradient = burst_grad
	burst_tex.fill = GradientTexture2D.FILL_RADIAL
	burst_tex.fill_from = Vector2(0.5, 0.5)
	burst_tex.fill_to = Vector2(1.0, 0.5)
	burst_tex.width = 512
	burst_tex.height = 192
	_burst.texture = burst_tex
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.stretch_mode = TextureRect.STRETCH_SCALE
	var burst_mat := CanvasItemMaterial.new()
	burst_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_burst.material = burst_mat
	_burst.position = Vector2(50, 130)
	_burst.size = Vector2(500, 180)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.visible = false
	_panel.add_child(_burst)

	# Thin light streak under the item row; it supports the cards without washing
	# out their names or creating a hard-edged bright rectangle.
	_beam = TextureRect.new()
	var beam_grad := Gradient.new()
	beam_grad.set_color(0, Color(1.0, 0.86, 0.45, 0.0))
	beam_grad.set_color(1, Color(1.0, 0.86, 0.45, 0.0))
	beam_grad.add_point(0.18, Color(0.42, 0.78, 1.0, 0.18))
	beam_grad.add_point(0.5, Color(1.0, 0.91, 0.58, 0.86))
	beam_grad.add_point(0.82, Color(0.42, 0.78, 1.0, 0.18))
	var beam_tex := GradientTexture2D.new()
	beam_tex.gradient = beam_grad
	beam_tex.width = 512
	beam_tex.height = 4
	beam_tex.fill_from = Vector2(0, 0)
	beam_tex.fill_to = Vector2(1, 0)
	_beam.texture = beam_tex
	_beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_beam.stretch_mode = TextureRect.STRETCH_SCALE
	var beam_mat := CanvasItemMaterial.new()
	beam_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beam.material = beam_mat
	_beam.position = Vector2(60, 205)
	_beam.size = Vector2(PANEL_SIZE.x - 120, 3)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beam.visible = false
	_panel.add_child(_beam)

	_eyebrow = UiKit.make_label_strong("", 9, Color(0.66, 0.84, 0.96, 0.82))
	var eyebrow_font := UiKit.body_semibold_font()
	if eyebrow_font != null:
		var eyebrow_variation := FontVariation.new()
		eyebrow_variation.base_font = eyebrow_font
		eyebrow_variation.spacing_glyph = 2
		_eyebrow.add_theme_font_override("font", eyebrow_variation)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow.position = Vector2(62, 66)
	_eyebrow.size = Vector2(PANEL_SIZE.x - 124, 14)
	_panel.add_child(_eyebrow)

	_header = UiKit.make_title("", 22, Color("f4d486"))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.position = Vector2(58, 79)
	_header.size = Vector2(PANEL_SIZE.x - 116, 27)
	_header.clip_text = true
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_header)

	var divider_texture := _texture_or_null(DIVIDER_TEX)
	if divider_texture != null:
		var divider := TextureRect.new()
		divider.texture = divider_texture
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		divider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		divider.position = Vector2(156, 106)
		divider.size = Vector2(288, 10)
		divider.modulate = Color(1, 1, 1, 0.78)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(divider)

	_body = UiKit.make_label("", 12, Color("eee7da"))
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.position = BODY_NARRATIVE_RECT.position
	_body.size = BODY_NARRATIVE_RECT.size
	_body.max_lines_visible = 9
	_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_body)

	_reveal_box = HBoxContainer.new()
	_reveal_box.add_theme_constant_override("separation", 8)
	_reveal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_box.position = REVEAL_RECT.position
	_reveal_box.size = REVEAL_RECT.size
	_reveal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_reveal_box)

	_sparkles = CPUParticles2D.new()
	_sparkles.position = Vector2(PANEL_SIZE.x * 0.5, 208)
	_sparkles.amount = 28
	_sparkles.lifetime = 1.25
	_sparkles.one_shot = true
	_sparkles.explosiveness = 0.72
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.emission_rect_extents = Vector2(212, 52)
	_sparkles.direction = Vector2(0, -1)
	_sparkles.spread = 52.0
	_sparkles.gravity = Vector2(0, -14)
	_sparkles.initial_velocity_min = 8.0
	_sparkles.initial_velocity_max = 30.0
	_sparkles.scale_amount_min = 0.7
	_sparkles.scale_amount_max = 1.8
	_sparkles.color = Color(1.0, 0.88, 0.56, 0.86)
	_sparkles.emitting = false
	_panel.add_child(_sparkles)

	# Bottom action control: action and keyboard affordance are separate visual
	# units, which reads more cleanly than embedding "[Enter]" in the button text.
	_action_panel = Panel.new()
	_action_panel.size = ACTION_SIZE
	_action_panel.position = Vector2((PANEL_SIZE.x - ACTION_SIZE.x) * 0.5, 284)
	_action_panel.add_theme_stylebox_override("panel", _chip_style(false))
	_action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_action_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_action_panel.mouse_entered.connect(func() -> void:
		_action_panel.add_theme_stylebox_override("panel", _chip_style(true))
	)
	_action_panel.mouse_exited.connect(func() -> void:
		_action_panel.add_theme_stylebox_override("panel", _chip_style(false))
	)
	_action_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_activate_primary()
			get_viewport().set_input_as_handled()
	)
	_panel.add_child(_action_panel)

	_action_label = UiKit.make_label_strong("", 11, Color("f5ead5"))
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_label.position = Vector2(12, 1)
	_action_label.size = Vector2(132, ACTION_SIZE.y - 2)
	_action_panel.add_child(_action_label)

	_action_keycap = Panel.new()
	_action_keycap.position = Vector2(150, 7)
	_action_keycap.size = Vector2(50, 22)
	_action_keycap.add_theme_stylebox_override("panel", _keycap_style())
	_action_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_panel.add_child(_action_keycap)
	var enter_label := UiKit.make_label_strong("ENTER", 8, Color(0.76, 0.88, 0.96, 0.90))
	enter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enter_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_keycap.add_child(enter_label)


func _set_action(label: String, enabled: bool) -> void:
	_primary_enabled = enabled
	_action_label.text = label.to_upper()
	_action_panel.modulate = Color.WHITE if enabled else Color(0.55, 0.58, 0.64, 0.70)


func _set_content_layout(with_cards: bool) -> void:
	var body_rect := BODY_REVEAL_RECT if with_cards else BODY_NARRATIVE_RECT
	_body.position = body_rect.position
	_body.size = body_rect.size
	_body.max_lines_visible = 3 if with_cards else 9
	_reveal_box.visible = with_cards


func _set_heading(title: String, eyebrow: String) -> void:
	_header.text = title.to_upper()
	_eyebrow.text = eyebrow.to_upper()
	var font := _header.get_theme_font("font")
	var font_size := 22
	while font_size > 16 and font.get_string_size(
			_header.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
		).x > _header.size.x:
		font_size -= 1
	_header.add_theme_font_size_override("font_size", font_size)


# ── input / lifecycle ────────────────────────────────────────────────────────────


func _activate_primary() -> void:
	if _closing or Time.get_ticks_msec() < _accept_after_ms:
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
		if not _announce_mode:
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


func _panel_shadow_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.28)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 8)
	return style


func _slot_fallback_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.030, 0.055, 0.96)
	style.border_color = Color(0.90, 0.70, 0.31, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _chip_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.105, 0.085, 0.98) if hovered else Color(0.035, 0.055, 0.09, 0.94)
	style.border_color = Color(1.0, 0.83, 0.48, 1.0) if hovered else Color(0.84, 0.66, 0.30, 0.86)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.48, 0.72, 1.0, 0.16) if hovered else Color(0, 0, 0, 0.38)
	style.shadow_size = 8 if hovered else 5
	style.shadow_offset = Vector2(0, 2)
	return style


func _keycap_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.075, 0.98)
	style.border_color = Color(0.42, 0.70, 0.90, 0.54)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
