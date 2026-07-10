extends CanvasLayer
## MoralChoiceView — the full-screen moral-choice ceremony (choice_v1 kit).
##
## Every moral choice plays here, moonlit-silver and deliberately COLD compared
## to the gold UI of the rest of the game. Two phases in one view:
##   CHOICE  — crescent emblem, dilemma panel (NPC medallion + typewriter), the
##             options as vertically stacked bars (↑↓ + Enter, second Enter to
##             confirm — a moral choice is irreversible).
##   REVEAL  — cracked crescent, the chosen bar, the NPC's in-character
##             reaction, then the consequence chips (from
##             QuestManager.last_choice_result) and the narrator caption.
##
## While open it owns AnnouncementCenter.conversation_active, so quest/item
## rewards triggered by the resolution queue up and play as the usual reward
## ceremonies right after this view closes.

signal closed

const KIT_DIR := "res://assets/ui/choice_v1/"
const INPUT_GRACE := 0.45

const BAR_ASPECT := 640.0 / 72.0      # option_bar_*.png are baked at exactly this
const SELECTED_OVERSIZE := 1.08       # uniform-scale overhang for the baked glow
const PANEL_SIZE := Vector2(760, 120) # panel_frame.png is baked at exactly this

const SILVER := Color(0.84, 0.90, 0.99, 1.0)
const SILVER_DIM := Color(0.84, 0.90, 0.99, 0.58)
const SILVER_FAINT := Color(0.84, 0.90, 0.99, 0.34)
const ICE := Color(0.64, 0.86, 1.0, 1.0)
const RED_COLD := Color(0.90, 0.47, 0.49, 1.0)
const DIM_COLOR := Color(0.006, 0.010, 0.026, 0.62)

## Frosted-glass backdrop: the live scene stays visible behind the ceremony,
## blurred (mipmap LOD) and gently tinted toward moonlit navy for contrast.
const FROSTED_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod = 2.4;
uniform vec4 tint : source_color = vec4(0.006, 0.010, 0.026, 0.58);
void fragment() {
	vec3 scene = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	COLOR = vec4(mix(scene, tint.rgb, tint.a), 1.0);
}
"""

enum Phase { CHOICE, ARMED, RESOLVING, REVEAL, DONE }

var _phase: int = Phase.CHOICE
var _quest: Dictionary = {}
var _objective: Dictionary = {}
var _options: Array = []
var _npc_name: String = ""
var _npc_portrait: Texture2D = null
var _selected: int = 0
var _can_input: bool = false
var _closing: bool = false

var _root: Control
var _choice_group: Control
var _reveal_group: Control
var _option_bars: Array = []       # [{holder, bar_selected, bar_normal, label, hint}]
var _cursor: TextureRect
var _footer: Label
var _dilemma_label: Label
var _reveal_timer: SceneTreeTimer = null


func _ready() -> void:
	layer = 72  # above AnnouncementView (70) — a queued reward never covers the choice
	process_mode = Node.PROCESS_MODE_ALWAYS


## payload = {quest, objective} (the same shape QuestManager queues).
func present(payload: Dictionary, npc_name: String = "", npc_portrait: Texture2D = null) -> void:
	_quest = payload.get("quest", {}) as Dictionary
	_objective = payload.get("objective", {}) as Dictionary
	_options = (_objective.get("options", []) as Array).filter(func(o): return o is Dictionary)
	_npc_name = npc_name
	_npc_portrait = npc_portrait
	GameManager.ui_blocking_input = true
	AnnouncementCenter.conversation_active = true
	_build_shell()
	_build_choice_phase()
	_animate_in()
	get_tree().create_timer(INPUT_GRACE).timeout.connect(func() -> void: _can_input = true)


# ── shared shell (dim, letterbox, motes) ─────────────────────────────────────────


func _build_shell() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	# The color is only the fallback look if the shader ever fails to compile —
	# normally the frosted shader fully overrides the fragment output.
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frost := Shader.new()
	frost.code = FROSTED_SHADER
	var frost_material := ShaderMaterial.new()
	frost_material.shader = frost
	dim.material = frost_material
	_root.add_child(dim)

	var vp := _viewport_size()
	for edge_y in [0.0, vp.y - 44.0]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.position = Vector2(0, edge_y)
		bar.size = Vector2(vp.x, 44.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(bar)

	var motes := CPUParticles2D.new()
	motes.position = Vector2(vp.x * 0.5, vp.y * 0.62)
	motes.amount = 26
	motes.lifetime = 4.2
	motes.preprocess = 3.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(vp.x * 0.52, vp.y * 0.4)
	motes.direction = Vector2(0, -1)
	motes.spread = 24.0
	motes.gravity = Vector2(0, -5)
	motes.initial_velocity_min = 3.0
	motes.initial_velocity_max = 10.0
	motes.scale_amount_min = 0.7
	motes.scale_amount_max = 1.8
	motes.color = Color(ICE.r, ICE.g, ICE.b, 0.42)
	_root.add_child(motes)


# ── phase A: the choice ──────────────────────────────────────────────────────────


func _build_choice_phase() -> void:
	var vp := _viewport_size()
	var cx := vp.x * 0.5
	_choice_group = Control.new()
	_choice_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_choice_group)

	_place_emblem(_choice_group, "crescent_emblem.png", Vector2(cx, 58.0), 92.0)
	_place_title(_choice_group, "QUYẾT ĐỊNH", Vector2(cx, 106.0))
	_place_divider(_choice_group, Vector2(cx, 132.0), 300.0)

	# Dilemma panel + NPC medallion + typewriter prompt.
	var panel_rect := Rect2(Vector2(cx - PANEL_SIZE.x * 0.5, 158.0), PANEL_SIZE)
	_place_panel(_choice_group, panel_rect)
	if _npc_portrait != null:
		_place_medallion(_choice_group, Vector2(cx, panel_rect.position.y), 84.0)
	_dilemma_label = _make_serif(str(_objective.get("prompt", _objective.get("description", ""))), 15, Color(0.96, 0.97, 1.0, 0.95), true)
	_dilemma_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dilemma_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dilemma_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dilemma_label.position = panel_rect.position + Vector2(56.0, 30.0)
	_dilemma_label.size = panel_rect.size - Vector2(112.0, 48.0)
	_dilemma_label.visible_characters = 0
	_choice_group.add_child(_dilemma_label)
	var dilemma_type := func(count: int) -> void: _dilemma_label.visible_characters = count
	var dilemma_chars := _dilemma_label.get_total_character_count()
	var reveal_tween := create_tween()
	reveal_tween.tween_method(dilemma_type, 0, dilemma_chars, minf(1.4, 0.022 * dilemma_chars))

	# Option bars, stacked. Sizing adapts so up to 4 options stay on screen —
	# the bar art is baked at BAR_ASPECT, so a shorter bar also narrows to keep
	# the border art pixel-true (never stretched off-ratio).
	var count := maxi(_options.size(), 1)
	var bar_h := 72.0 if count <= 2 else 60.0
	var gap := 18.0 if count <= 2 else 12.0
	var block_h := count * bar_h + (count - 1) * gap
	var start_y := 306.0 + maxf(0.0, (200.0 - block_h) * 0.5)
	var bar_w := bar_h * BAR_ASPECT
	_option_bars.clear()
	for index in range(_options.size()):
		var option: Dictionary = _options[index] as Dictionary
		var holder := Control.new()
		holder.position = Vector2(cx - bar_w * 0.5, start_y + index * (bar_h + gap))
		holder.size = Vector2(bar_w, bar_h)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_choice_group.add_child(holder)

		var tex_selected := _tex("option_bar_selected.png")
		var tex_normal := _tex("option_bar_normal.png")
		# The selected art bakes its glow inside the strip, so it draws with a
		# UNIFORM oversize (same factor on both axes — aspect stays true).
		var sel_size := Vector2(bar_w, bar_h) * SELECTED_OVERSIZE
		var bar_selected := _stretch(tex_selected, sel_size, (Vector2(bar_w, bar_h) - sel_size) * 0.5)
		var bar_normal := _stretch(tex_normal, Vector2(bar_w, bar_h), Vector2.ZERO)
		holder.add_child(bar_normal)
		holder.add_child(bar_selected)

		var hint_line := str(option.get("tone_hint", option.get("hint_line", "")))
		var label := _make_serif(str(option.get("label", "...")), 17, SILVER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(16.0, (0.0 if hint_line.is_empty() else -10.0))
		label.size = Vector2(bar_w - 32.0, bar_h)
		label.uppercase = true
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		holder.add_child(label)

		var hint: Label = null
		if not hint_line.is_empty():
			hint = _make_serif(hint_line, 11, SILVER_DIM, true)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# The bar art bakes its glow inside the strip, so the usable interior
			# is inset — keep the hint clear of the lower border.
			hint.position = Vector2(16.0, bar_h - 34.0)
			hint.size = Vector2(bar_w - 32.0, 18.0)
			hint.clip_text = true
			hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			holder.add_child(hint)

		_option_bars.append({
			"holder": holder, "selected": bar_selected, "normal": bar_normal,
			"label": label, "hint": hint,
		})

	_cursor = TextureRect.new()
	_cursor.texture = _tex("cursor_moonstone.png")
	_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor.stretch_mode = TextureRect.STRETCH_SCALE
	_cursor.size = Vector2(44, 44)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_group.add_child(_cursor)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_cursor, "modulate:a", 0.62, 0.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_cursor, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	_footer = _make_serif("↑ ↓  Chọn      ·      Enter  Xác nhận", 11, SILVER_FAINT)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.position = Vector2(cx - 260.0, vp.y - 36.0)
	_footer.size = Vector2(520.0, 16.0)
	_choice_group.add_child(_footer)

	_apply_selection()


func _apply_selection() -> void:
	for index in range(_option_bars.size()):
		var entry: Dictionary = _option_bars[index] as Dictionary
		var is_sel := index == _selected
		(entry["selected"] as Control).visible = is_sel
		(entry["normal"] as Control).visible = not is_sel
		(entry["label"] as Label).add_theme_color_override(
			"font_color", SILVER if is_sel else Color(0.66, 0.72, 0.84, 0.66))
		if entry["hint"] != null:
			(entry["hint"] as Label).visible = is_sel
		if is_sel and _cursor != null:
			var holder := entry["holder"] as Control
			_cursor.position = holder.position + Vector2(-56.0, holder.size.y * 0.5 - 22.0)


func _arm_confirm() -> void:
	if _option_bars.is_empty():
		_close()
		return
	_phase = Phase.ARMED
	_footer.text = "Enter  lần nữa — quyết định không thể đảo ngược      ·      Esc  nghĩ lại"
	_footer.add_theme_color_override("font_color", Color(SILVER.r, SILVER.g, SILVER.b, 0.85))
	var entry: Dictionary = _option_bars[_selected] as Dictionary
	var bar := entry["selected"] as Control
	var flash := create_tween()
	flash.tween_property(bar, "modulate", Color(1.35, 1.35, 1.5, 1.0), 0.12)
	flash.tween_property(bar, "modulate", Color.WHITE, 0.30)


func _disarm_confirm() -> void:
	_phase = Phase.CHOICE
	_footer.text = "↑ ↓  Chọn      ·      Enter  Xác nhận"
	_footer.add_theme_color_override("font_color", SILVER_FAINT)


# ── phase B: the reveal ──────────────────────────────────────────────────────────


func _confirm_choice() -> void:
	if _options.is_empty():
		_close()
		return
	_phase = Phase.RESOLVING
	var option: Dictionary = _options[_selected] as Dictionary
	var quest_id := str(_quest.get("id", ""))
	var resolved := QuestManager.resolve_quest_choice(quest_id, str(option.get("id", "a")))
	if not resolved:
		# Already decided elsewhere (or state moved on) — nothing to ceremony.
		_close()
		return
	_build_reveal_phase(option, QuestManager.last_choice_result)
	var fade := create_tween()
	fade.tween_property(_choice_group, "modulate:a", 0.0, 0.28)
	fade.tween_callback(func() -> void: _choice_group.visible = false)
	fade.parallel().tween_property(_reveal_group, "modulate:a", 1.0, 0.34).from(0.0)
	_phase = Phase.REVEAL
	_can_input = false
	_reveal_timer = get_tree().create_timer(INPUT_GRACE + 0.9)
	_reveal_timer.timeout.connect(func() -> void:
		_can_input = true
		_phase = Phase.DONE)


func _build_reveal_phase(option: Dictionary, result: Dictionary) -> void:
	var vp := _viewport_size()
	var cx := vp.x * 0.5
	_reveal_group = Control.new()
	_reveal_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_group.modulate.a = 0.0
	_root.add_child(_reveal_group)

	_place_emblem(_reveal_group, "crescent_cracked.png", Vector2(cx, 42.0), 72.0)
	_place_title(_reveal_group, "ĐÃ QUYẾT ĐỊNH", Vector2(cx, 96.0))
	_place_divider(_reveal_group, Vector2(cx, 122.0), 300.0)

	# The chosen option, sealed — same exact bar slot as the choice phase.
	var bar_h := 72.0
	var bar_w := bar_h * BAR_ASPECT
	var sel_size := Vector2(bar_w, bar_h) * SELECTED_OVERSIZE
	var chosen := _stretch(_tex("option_bar_selected.png"), sel_size,
		Vector2(cx, 140.0 + bar_h * 0.5) - sel_size * 0.5)
	_reveal_group.add_child(chosen)
	var chosen_label := _make_serif(str(option.get("label", result.get("option_label", ""))), 17, SILVER)
	chosen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chosen_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chosen_label.uppercase = true
	chosen_label.position = Vector2(cx - bar_w * 0.5, 140.0)
	chosen_label.size = Vector2(bar_w, bar_h)
	_reveal_group.add_child(chosen_label)

	# NPC reaction panel (portrait medallion left, in-character line right).
	var reaction := str(result.get("npc_reaction", "")).strip_edges()
	if reaction.is_empty():
		reaction = str(option.get("npc_reaction", "")).strip_edges()
	if reaction.is_empty():
		reaction = "Vậy là ngươi đã quyết."
	var panel_rect := Rect2(Vector2(cx - PANEL_SIZE.x * 0.5, 236.0), PANEL_SIZE)
	_place_panel(_reveal_group, panel_rect)
	var has_portrait := _npc_portrait != null
	if has_portrait:
		_place_medallion(_reveal_group, panel_rect.position + Vector2(84.0, panel_rect.size.y * 0.5), 104.0)
	var quote := _make_serif("“%s”" % reaction, 15, Color(0.96, 0.97, 1.0, 0.95), true)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var text_left := (168.0 if has_portrait else 46.0)
	quote.position = panel_rect.position + Vector2(text_left, 20.0)
	quote.size = Vector2(panel_rect.size.x - text_left - 46.0, panel_rect.size.y - 40.0)
	quote.visible_characters = 0
	_reveal_group.add_child(quote)
	var quote_type := func(count: int) -> void: quote.visible_characters = count
	var quote_chars := quote.get_total_character_count()
	var type_tween := create_tween()
	type_tween.tween_interval(0.30)
	type_tween.tween_method(quote_type, 0, quote_chars, minf(1.2, 0.024 * quote_chars))

	# HẬU QUẢ divider + consequence chips.
	var chips: Array = result.get("chips", []) as Array
	var section_y := 376.0
	var mini := _make_serif("HẬU QUẢ", 12, SILVER_DIM)
	mini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mini.uppercase = true
	mini.position = Vector2(cx - 120.0, section_y)
	mini.size = Vector2(240.0, 16.0)
	_reveal_group.add_child(mini)
	_place_divider(_reveal_group, Vector2(cx - 150.0, section_y + 8.0), 90.0)
	_place_divider(_reveal_group, Vector2(cx + 150.0, section_y + 8.0), 90.0)

	if chips.is_empty():
		chips = [{"icon": "item", "tone": "neutral", "text": "Câu chuyện sẽ ghi nhớ điều này"}]
	var per_row := 4
	var chip_w := 200.0
	var chip_h := 46.0
	var chip_gap := 14.0
	var delay := 0.55
	for index in range(chips.size()):
		var chip: Dictionary = chips[index] as Dictionary
		var row: int = int(float(index) / float(per_row))
		var in_row_count: int = mini(chips.size() - row * per_row, per_row)
		var col := index % per_row
		var row_w := in_row_count * chip_w + (in_row_count - 1) * chip_gap
		var pos := Vector2(cx - row_w * 0.5 + col * (chip_w + chip_gap), section_y + 26.0 + row * (chip_h + 8.0))
		var node := _build_chip(chip, Vector2(chip_w, chip_h))
		node.position = pos
		node.modulate.a = 0.0
		node.scale = Vector2(0.92, 0.92)
		node.pivot_offset = Vector2(chip_w, chip_h) * 0.5
		_reveal_group.add_child(node)
		var pop := create_tween()
		pop.tween_interval(delay + index * 0.14)
		pop.tween_property(node, "modulate:a", 1.0, 0.20)
		pop.parallel().tween_property(node, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Narrator caption (consequence_text — its true home). Clamped so a second
	# chip row can never push it into the footer line.
	var rows := ceili(float(chips.size()) / float(per_row))
	var caption_text := str(result.get("consequence_text", "")).strip_edges()
	if not caption_text.is_empty():
		var caption := _make_serif(caption_text, 12, Color(0.78, 0.82, 0.92, 0.62), true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.max_lines_visible = 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var caption_y: float = minf(section_y + 26.0 + rows * (chip_h + 8.0) + 6.0, vp.y - 72.0)
		caption.position = Vector2(cx - 330.0, caption_y)
		caption.size = Vector2(660.0, 36.0)
		_reveal_group.add_child(caption)

	var footer := _make_serif("Enter  Tiếp tục", 11, SILVER_FAINT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(cx - 130.0, vp.y - 32.0)
	footer.size = Vector2(260.0, 16.0)
	footer.modulate.a = 0.0
	_reveal_group.add_child(footer)
	var footer_in := create_tween()
	footer_in.tween_interval(delay + chips.size() * 0.14 + 0.35)
	footer_in.tween_property(footer, "modulate:a", 1.0, 0.3)


func _build_chip(chip: Dictionary, chip_size: Vector2) -> Control:
	var holder := Control.new()
	holder.size = chip_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_stretch(_tex("chip_frame.png"), chip_size, Vector2.ZERO))
	var icon_name := str(chip.get("icon", "item"))
	var icon_tex := _tex("icons/%s.png" % icon_name)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.size = Vector2(28, 28)
		icon.position = Vector2(12.0, chip_size.y * 0.5 - 14.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
	var tone := str(chip.get("tone", "neutral"))
	var color := RED_COLD if tone == "loss" else (ICE if tone == "gain" else SILVER_DIM)
	var text := _make_serif(str(chip.get("text", "")), 12, color)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.position = Vector2(48.0, 0.0)
	text.size = Vector2(chip_size.x - 58.0, chip_size.y)
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	holder.add_child(text)
	return holder


# ── input ────────────────────────────────────────────────────────────────────────


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if not _can_input and _phase != Phase.ARMED:
		return
	match _phase:
		Phase.CHOICE:
			if event.is_action_pressed("ui_down"):
				_selected = mini(_selected + 1, _option_bars.size() - 1)
				_apply_selection()
			elif event.is_action_pressed("ui_up"):
				_selected = maxi(_selected - 1, 0)
				_apply_selection()
			elif event.is_action_pressed("ui_accept"):
				_arm_confirm()
		Phase.ARMED:
			if event.is_action_pressed("ui_accept"):
				_confirm_choice()
			elif event.is_action_pressed("ui_cancel"):
				_disarm_confirm()
			elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
				_disarm_confirm()
				if event.is_action_pressed("ui_down"):
					_selected = mini(_selected + 1, _option_bars.size() - 1)
				else:
					_selected = maxi(_selected - 1, 0)
				_apply_selection()
		Phase.DONE:
			if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
				_close()
		_:
			pass


func _close() -> void:
	if _closing:
		return
	_closing = true
	var fade := create_tween()
	fade.tween_property(_root, "modulate:a", 0.0, 0.30)
	fade.tween_callback(func() -> void:
		GameManager.ui_blocking_input = false
		# Hand the stage to any reward ceremonies the resolution queued up.
		AnnouncementCenter.set_conversation_active(false)
		closed.emit()
		queue_free())


# ── construction helpers ─────────────────────────────────────────────────────────


func _viewport_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(1024, 576)


func _tex(file_name: String) -> Texture2D:
	var path := KIT_DIR + file_name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _stretch(texture: Texture2D, target: Vector2, offset: Vector2) -> Control:
	if texture == null:
		var fallback := Panel.new()
		fallback.add_theme_stylebox_override("panel", UiKit.flat_panel_style())
		fallback.position = offset
		fallback.size = target
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return fallback
	var rect := TextureRect.new()
	rect.texture = texture
	# expand_mode BEFORE size: with the default KEEP_SIZE the texture's native
	# resolution acts as a minimum and silently clamps the size assignment.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = offset
	rect.size = target
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _place_emblem(parent: Control, file_name: String, center: Vector2, height: float) -> void:
	var texture := _tex(file_name)
	if texture == null:
		return
	var width := height * texture.get_width() / maxf(1.0, float(texture.get_height()))
	var rect := _stretch(texture, Vector2(width, height), center - Vector2(width * 0.5, height * 0.5))
	parent.add_child(rect)


func _place_title(parent: Control, text: String, center: Vector2) -> void:
	var title := UiKit.make_title(text, 26, SILVER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.uppercase = true
	title.position = Vector2(center.x - 320.0, center.y - 18.0)
	title.size = Vector2(640.0, 36.0)
	parent.add_child(title)


func _place_divider(parent: Control, center: Vector2, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color(SILVER.r, SILVER.g, SILVER.b, 0.30)
	line.position = Vector2(center.x - width * 0.5, center.y)
	line.size = Vector2(width, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	var jewel := ColorRect.new()
	jewel.color = Color(SILVER.r, SILVER.g, SILVER.b, 0.75)
	jewel.position = Vector2(center.x - 2.5, center.y - 2.0)
	jewel.size = Vector2(5.0, 5.0)
	jewel.rotation_degrees = 45.0
	jewel.pivot_offset = Vector2(2.5, 2.5)
	jewel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(jewel)


func _place_panel(parent: Control, rect: Rect2) -> void:
	parent.add_child(_stretch(_tex("panel_frame.png"), rect.size, rect.position))


func _place_medallion(parent: Control, center: Vector2, diameter: float) -> void:
	if _npc_portrait != null:
		var portrait := TextureRect.new()
		portrait.texture = _circle_cropped(_npc_portrait, int(diameter - 16.0))
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_SCALE
		portrait.size = Vector2(diameter - 16.0, diameter - 16.0)
		portrait.position = center - portrait.size * 0.5
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(portrait)
	var ring := _stretch(_tex("portrait_ring.png"), Vector2(diameter, diameter), center - Vector2(diameter, diameter) * 0.5)
	parent.add_child(ring)


func _circle_cropped(texture: Texture2D, out_px: int) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var side := mini(image.get_width(), image.get_height())
	var src := Image.create(side, side, false, Image.FORMAT_RGBA8)
	src.blit_rect(image, Rect2i((image.get_width() - side) / 2, 0, side, side), Vector2i.ZERO)
	src.resize(out_px, out_px, Image.INTERPOLATE_LANCZOS)
	var radius := out_px * 0.5
	for y in range(out_px):
		for x in range(out_px):
			var dist := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			if dist > radius - 1.0:
				var px := src.get_pixel(x, y)
				px.a *= clampf(radius - dist, 0.0, 1.0)
				src.set_pixel(x, y, px)
	return ImageTexture.create_from_image(src)


func _make_serif(text: String, font_size: int, color: Color, italic: bool = false) -> Label:
	var label := UiKit.make_label(text, font_size, color)
	if italic:
		var base := label.get_theme_font("font")
		if base != null:
			var variation := FontVariation.new()
			variation.base_font = base
			variation.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.22, 1.0), Vector2.ZERO)
			label.add_theme_font_override("font", variation)
	return label


func _animate_in() -> void:
	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.4)
