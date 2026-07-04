extends CanvasLayer
## Chapter-complete celebration: radiant laurel emblem, serif title, "next
## land unlocked" line and a travel prompt (ĐI NGAY / Ở LẠI). Cinematic but
## restrained — dim, embers, staged entrance tweens. Native 960x540-ish design
## centered in the real viewport.

signal travel_confirmed(chapter_number: int)
signal dismissed

const EMBLEM_PATH := "res://assets/ui/complete_kit_v1/laurel_emblem.png"
const GATE_PATH := "res://assets/ui/complete_kit_v1/gate_crest.png"
const FALLBACK_EMBLEM := "res://assets/ui/aaa_kit_v1/crest_gold.png"

const C_GOLD := Color(0.99, 0.85, 0.48)
const C_TEXT := Color(0.94, 0.90, 0.80)
const C_TEXT_DIM := Color(0.94, 0.90, 0.80, 0.62)
const BUTTON_SIZE := Vector2(176, 38)

var _root: Control
var _buttons: Array[Control] = []
var _button_labels: Array[Label] = []
var _selected := 0
var _next_chapter_number := -1
var _has_next := false
var _closing := false


func show_completion(chapter_number: int, chapter_title: String, next_chapter: Dictionary) -> void:
	layer = 96  # above every HUD layer, below nothing that matters mid-exploration
	_has_next = not next_chapter.is_empty()
	_next_chapter_number = int(next_chapter.get("chapter", -1))
	GameManager.ui_blocking_input = true

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var vp: Vector2 = _root.get_viewport_rect().size
	var cx := vp.x * 0.5

	var dim := ColorRect.new()
	dim.color = Color(0.008, 0.010, 0.022, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var embers := UiKit.make_ember_particles(vp)
	embers.amount = 34
	embers.color = Color(1.0, 0.80, 0.38, 0.42)
	_root.add_child(embers)

	# ── radiant emblem ──
	var emblem_path := EMBLEM_PATH if ResourceLoader.exists(EMBLEM_PATH) else FALLBACK_EMBLEM
	var emblem: TextureRect = null
	if ResourceLoader.exists(emblem_path):
		emblem = TextureRect.new()
		emblem.texture = load(emblem_path)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		emblem.size = Vector2(150, 150)
		emblem.position = Vector2(cx - 75.0, 66.0)
		emblem.pivot_offset = emblem.size * 0.5
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(emblem)
		# Additive glow twin that flares on entrance then settles into a pulse.
		var glow := emblem.duplicate() as TextureRect
		var add_material := CanvasItemMaterial.new()
		add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add_material
		glow.modulate = Color(1, 0.9, 0.6, 0.0)
		_root.add_child(glow)
		var pulse := create_tween().set_loops()
		pulse.tween_property(glow, "modulate:a", 0.30, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(1.0)
		pulse.tween_property(glow, "modulate:a", 0.08, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# ── chapter kicker + title ──
	var kicker := UiKit.make_label_strong("CHƯƠNG %d" % chapter_number, 13, Color(C_GOLD, 0.75))
	kicker.position = Vector2(cx - 200.0, 226.0)
	kicker.size = Vector2(400.0, 18.0)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(kicker)

	var title := UiKit.make_title("HOÀN THÀNH CHƯƠNG", 36, C_GOLD)
	title.position = Vector2(cx - 320.0, 246.0)
	title.size = Vector2(640.0, 46.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.pivot_offset = title.size * 0.5
	_root.add_child(title)

	var subtitle := UiKit.make_label(chapter_title, 14, C_TEXT_DIM)
	subtitle.position = Vector2(cx - 250.0, 294.0)
	subtitle.size = Vector2(500.0, 20.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(subtitle)

	# ── kit divider ornament ──
	var divider_texture := UiKit.kit_texture("divider.png")
	var divider: Control = null
	if divider_texture != null:
		var art := TextureRect.new()
		art.texture = divider_texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.position = Vector2(cx - 140.0, 316.0)
		art.size = Vector2(280.0, 26.0)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(art)
		divider = art

	# ── next-chapter unlock line ──
	var unlock_y := 352.0
	if _has_next:
		var next_title := str(next_chapter.get("title", "Chương %d" % _next_chapter_number))
		var lead := UiKit.make_label("Vùng đất mới đã mở khoá:", 13, C_TEXT_DIM)
		lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lead.position = Vector2(cx - 250.0, unlock_y)
		lead.size = Vector2(500.0, 18.0)
		_root.add_child(lead)

		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		name_row.alignment = BoxContainer.ALIGNMENT_CENTER
		name_row.position = Vector2(cx - 250.0, unlock_y + 20.0)
		name_row.size = Vector2(500.0, 26.0)
		name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(name_row)
		if ResourceLoader.exists(GATE_PATH):
			var gate := TextureRect.new()
			gate.texture = load(GATE_PATH)
			gate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			gate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			gate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			gate.custom_minimum_size = Vector2(24, 24)
			gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_row.add_child(gate)
		var next_label := UiKit.make_title(next_title, 19, C_GOLD)
		next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_row.add_child(next_label)
	else:
		var lone := UiKit.make_label("Bạn đã đi qua mọi vùng đất hiện có — hãy tiếp tục khám phá.", 13, C_TEXT_DIM)
		lone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lone.position = Vector2(cx - 280.0, unlock_y + 8.0)
		lone.size = Vector2(560.0, 20.0)
		_root.add_child(lone)

	# ── buttons ──
	var button_y := vp.y - 128.0
	var specs: Array = []
	if _has_next:
		specs = [{"text": "ĐI NGAY", "action": _confirm_travel}, {"text": "Ở LẠI", "action": _dismiss}]
	else:
		specs = [{"text": "TIẾP TỤC", "action": _dismiss}]
	var total_w := BUTTON_SIZE.x * specs.size() + 24.0 * (specs.size() - 1)
	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var button := Control.new()
		button.position = Vector2(cx - total_w * 0.5 + float(i) * (BUTTON_SIZE.x + 24.0), button_y)
		button.size = BUTTON_SIZE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_root.add_child(button)
		_buttons.append(button)

		var backing := TextureRect.new()
		backing.name = "Backing"
		backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backing.stretch_mode = TextureRect.STRETCH_SCALE
		backing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		backing.size = BUTTON_SIZE
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(backing)

		var caption := UiKit.make_title(str(spec["text"]), 15, C_TEXT)
		caption.name = "Caption"
		caption.position = Vector2(0, 1)
		caption.size = BUTTON_SIZE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(caption)
		_button_labels.append(caption)

		var index := i
		var action: Callable = spec["action"]
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.is_pressed() \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_selected = index
				_update_buttons()
				action.call()
				button.get_viewport().set_input_as_handled()
		)
		button.mouse_entered.connect(func() -> void:
			_selected = index
			_update_buttons()
		)
	_update_buttons()

	var hint_text := "←/→ chọn · Enter xác nhận · Esc ở lại" if _has_next else "Enter để tiếp tục"
	var hint := UiKit.make_label(hint_text, 10, Color(C_TEXT, 0.45))
	hint.position = Vector2(cx - 200.0, button_y + 50.0)
	hint.size = Vector2(400.0, 16.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(hint)

	# ── entrance choreography ──
	var fade := create_tween()
	fade.tween_property(dim, "color:a", 0.82, 0.45).set_trans(Tween.TRANS_SINE)
	if emblem != null:
		emblem.scale = Vector2(0.2, 0.2)
		emblem.modulate.a = 0.0
		var pop := create_tween()
		pop.tween_interval(0.15)
		pop.tween_property(emblem, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.parallel().tween_property(emblem, "modulate:a", 1.0, 0.35)
	title.scale = Vector2(0.86, 0.86)
	title.modulate.a = 0.0
	var title_in := create_tween()
	title_in.tween_interval(0.4)
	title_in.tween_property(title, "modulate:a", 1.0, 0.4)
	title_in.parallel().tween_property(title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for node in [kicker, subtitle, divider]:
		if node == null:
			continue
		node.modulate.a = 0.0
		var rise := create_tween()
		rise.tween_interval(0.55)
		rise.tween_property(node, "modulate:a", 1.0, 0.4)
	var late_nodes: Array = []
	for child in _root.get_children():
		if child is HBoxContainer or (child is Label and child != kicker and child != title and child != subtitle):
			late_nodes.append(child)
	for button in _buttons:
		late_nodes.append(button)
	for node in late_nodes:
		(node as CanvasItem).modulate.a = 0.0
		var enter := create_tween()
		enter.tween_interval(0.75)
		enter.tween_property(node, "modulate:a", 1.0, 0.45)


func _update_buttons() -> void:
	for i in range(_buttons.size()):
		var active := i == _selected
		var backing: TextureRect = _buttons[i].get_node("Backing")
		var gold := UiKit.kit_texture("list_row_selected.png")
		var navy := UiKit.kit_texture("list_row.png")
		if gold != null and navy != null:
			backing.texture = gold if active else navy
		_button_labels[i].add_theme_color_override("font_color",
			Color(0.10, 0.08, 0.03, 1.0) if active else C_TEXT_DIM)
		_button_labels[i].add_theme_color_override("font_shadow_color",
			Color(1, 0.92, 0.72, 0.35) if active else Color(0.02, 0.01, 0.0, 0.85))


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		_dismiss()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_LEFT, KEY_A:
			_selected = maxi(0, _selected - 1)
			_update_buttons()
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			_selected = mini(_buttons.size() - 1, _selected + 1)
			_update_buttons()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _has_next and _selected == 0:
				_confirm_travel()
			else:
				_dismiss()
			get_viewport().set_input_as_handled()


func _confirm_travel() -> void:
	if _closing:
		return
	_closing = true
	GameManager.ui_blocking_input = false
	travel_confirmed.emit(_next_chapter_number)
	_fade_out_and_free()


func _dismiss() -> void:
	if _closing:
		return
	_closing = true
	GameManager.ui_blocking_input = false
	dismissed.emit()
	_fade_out_and_free()


func _fade_out_and_free() -> void:
	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, 0.28)
	out.tween_callback(queue_free)
