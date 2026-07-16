extends CanvasLayer
## MoralChoiceView — the full-screen moral-choice ceremony (choice_v2 layout).
##
## Every moral choice plays here, moonlit-silver and deliberately COLD compared
## to the gold UI of the rest of the game. Two phases in one view:
##   CHOICE  — crescent emblem, the dilemma floating on a soft haze, and TWO
##             illustrated CARDS side by side (one anime painting per option,
##             from the zone-level scene_choice_illustrations step). ←/→ picks,
##             Enter + second Enter confirms — a moral choice is irreversible.
##   REVEAL  — cracked crescent, the chosen card sealed at the left, the NPC's
##             in-character reaction beside it, then the consequence chips
##             (from QuestManager.last_choice_result) and the narrator caption.
##
## Card art is OPTIONAL at every level: no kit → procedural silver-on-navy
## frames; no illustration → a moonlit crescent placeholder. Illustrations come
## from QuestManager's prefetched cache first, then lazily from the option's
## illustration_url (never blocking the ceremony).
##
## While open it owns AnnouncementCenter.conversation_active, so quest/item
## rewards triggered by the resolution queue up and play as the usual reward
## ceremonies right after this view closes.

signal closed

const KIT_DIR := "res://assets/ui/choice_v1/"
const KIT2_DIR := "res://assets/ui/choice_v2/"
const INPUT_GRACE := 0.45

const CARD_W := 240.0
const CARD_H := 316.0
const CARD_GAP := 64.0
const CARD_SELECTED_OVERSIZE := 1.06  # uniform-scale overhang for the baked glow

const SILVER := Color(0.84, 0.90, 0.99, 1.0)
const SILVER_DIM := Color(0.84, 0.90, 0.99, 0.58)
const SILVER_FAINT := Color(0.84, 0.90, 0.99, 0.34)
const ICE := Color(0.64, 0.86, 1.0, 1.0)
const RED_COLD := Color(0.90, 0.47, 0.49, 1.0)
const DIM_COLOR := Color(0.006, 0.010, 0.026, 0.62)
const GLASS_NAVY := Color(0.016, 0.026, 0.058, 0.88)

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
var _cards: Array = []  # [{holder, frame_selected, frame_normal, image, placeholder, label, hint}]
var _card_art: Dictionary = {}  # option_id -> Texture2D (resolved for this ceremony)
var _cursor: TextureRect
var _footer: HBoxContainer
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
	for index in range(_options.size()):
		_resolve_card_art(index)
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

	_place_emblem(_choice_group, "crescent_emblem.png", Vector2(cx, 44.0), 56.0)
	_place_title(_choice_group, "QUYẾT ĐỊNH", Vector2(cx, 86.0), 22)
	_place_divider(_choice_group, Vector2(cx, 108.0), 300.0)

	# The dilemma floats on a soft haze — frameless, like the chat menu, so the
	# text area can be any size without stretching baked border art.
	var haze_rect := Rect2(Vector2(cx - 360.0, 116.0), Vector2(720.0, 78.0))
	_place_haze(_choice_group, haze_rect)
	_dilemma_label = _make_serif(str(_objective.get("prompt", _objective.get("description", ""))), 14, Color(0.96, 0.97, 1.0, 0.95), true)
	_dilemma_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dilemma_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dilemma_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dilemma_label.position = haze_rect.position + Vector2(28.0, 6.0)
	_dilemma_label.size = haze_rect.size - Vector2(56.0, 12.0)
	_dilemma_label.visible_characters = 0
	_choice_group.add_child(_dilemma_label)
	var dilemma_type := func(count: int) -> void: _dilemma_label.visible_characters = count
	var dilemma_chars := _dilemma_label.get_total_character_count()
	var reveal_tween := create_tween()
	reveal_tween.tween_method(dilemma_type, 0, dilemma_chars, minf(1.4, 0.022 * dilemma_chars))

	# The two option cards, side by side. More than two options degrade to a
	# tighter row — the card art aspect is preserved by scaling W with H.
	var count := maxi(_options.size(), 1)
	var card_w := CARD_W
	var gap := CARD_GAP
	if count > 2:
		card_w = minf(CARD_W, (vp.x - 120.0 - (count - 1) * 28.0) / float(count))
		gap = 28.0
	var card_h := card_w * (CARD_H / CARD_W)
	var row_w := count * card_w + (count - 1) * gap
	var start_x := cx - row_w * 0.5
	var card_y := 206.0 + (CARD_H - card_h) * 0.5
	_cards.clear()
	for index in range(_options.size()):
		var option: Dictionary = _options[index] as Dictionary
		var holder := _build_card(option, Vector2(card_w, card_h))
		holder["holder"].position = Vector2(start_x + index * (card_w + gap), card_y)
		_choice_group.add_child(holder["holder"])
		_cards.append(holder)
		# Staggered entrance: each card rises out of the haze.
		var node := holder["holder"] as Control
		node.modulate.a = 0.0
		node.position.y += 14.0
		var enter := create_tween()
		enter.tween_interval(0.12 + index * 0.12)
		enter.tween_property(node, "modulate:a", 1.0, 0.32)
		enter.parallel().tween_property(node, "position:y", card_y, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_cursor = TextureRect.new()
	_cursor.texture = _tex("cursor_moonstone.png")
	_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor.stretch_mode = TextureRect.STRETCH_SCALE
	_cursor.size = Vector2(40, 40)
	_cursor.visible = _cursor.texture != null
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_group.add_child(_cursor)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_cursor, "modulate:a", 0.62, 0.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_cursor, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	_footer = _build_footer(_choice_group, vp.y - 38.0)
	_footer_parts(_footer, [
		{"keys": ["←", "→"], "text": "Chọn"},
		{"keys": ["Enter"], "text": "Xác nhận"},
	], Color(SILVER.r, SILVER.g, SILVER.b, 0.48))

	_apply_selection()


## One option card: glass base, illustration window, ornate frame (kit art when
## present, procedural silver-on-navy otherwise), label + tone hint underneath.
## compact = the reveal-phase keepsake: label only, no hint, smaller type.
func _build_card(option: Dictionary, card_size: Vector2, compact: bool = false) -> Dictionary:
	var holder := Control.new()
	holder.size = card_size
	holder.pivot_offset = card_size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1) Dark glass base — always present, the frame's window looks into it.
	var glass := Panel.new()
	var glass_style := StyleBoxFlat.new()
	glass_style.bg_color = GLASS_NAVY
	glass_style.set_corner_radius_all(7)
	glass.add_theme_stylebox_override("panel", glass_style)
	glass.position = Vector2.ZERO
	glass.size = card_size
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glass)

	# 2) Illustration window (art arrives async; placeholder holds the mood).
	var window := _card_window_rect(card_size)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.position = window.position
	image.size = window.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(image)

	var placeholder := _build_card_placeholder(window)
	holder.add_child(placeholder)

	# 3) Frame on top. Kit art (baked at the exact card aspect) or procedural.
	var tex_normal := _tex2("card_frame_normal.png")
	var tex_selected := _tex2("card_frame_selected.png")
	var frame_normal: Control
	var frame_selected: Control
	if tex_normal != null and tex_selected != null:
		frame_normal = _stretch(tex_normal, card_size, Vector2.ZERO)
		# The selected art bakes its glow inside the sheet, so it draws with a
		# UNIFORM oversize (same factor on both axes — aspect stays true).
		var sel_size := card_size * CARD_SELECTED_OVERSIZE
		frame_selected = _stretch(tex_selected, sel_size, (card_size - sel_size) * 0.5)
	else:
		frame_normal = _procedural_frame(card_size, false)
		frame_selected = _procedural_frame(card_size, true)
	holder.add_child(frame_normal)
	holder.add_child(frame_selected)

	# 4) Label + tone hint in the text zone under the window, split from the
	# illustration by a slim silver hairline (the kit frame bakes its own).
	var text_top := window.position.y + window.size.y
	if tex_normal == null:
		var hairline := ColorRect.new()
		hairline.color = Color(SILVER.r, SILVER.g, SILVER.b, 0.22)
		hairline.position = Vector2(card_size.x * 0.22, text_top + 1.0)
		hairline.size = Vector2(card_size.x * 0.56, 1.0)
		hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(hairline)
	# Text hugs the WINDOW's inset, not the outer card edge — long labels must
	# never ride over the ornate border art.
	var side_pad := maxf(16.0, window.position.x + 6.0)
	var label := _make_serif(str(option.get("label", "...")), 12 if compact else 14, SILVER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.uppercase = true
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.position = Vector2(side_pad, text_top + 4.0)
	label.size = Vector2(card_size.x - side_pad * 2.0, (card_size.y - text_top) - 8.0 if compact else 46.0)
	holder.add_child(label)

	var hint_line := "" if compact else str(option.get("tone_hint", option.get("hint_line", "")))
	var hint: Label = null
	if not hint_line.is_empty():
		hint = _make_serif(hint_line, 10, SILVER_DIM, true)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = 2
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.position = Vector2(side_pad + 2.0, text_top + 52.0)
		hint.size = Vector2(card_size.x - side_pad * 2.0 - 4.0, 30.0)
		holder.add_child(hint)

	return {
		"holder": holder, "selected": frame_selected, "normal": frame_normal,
		"image": image, "placeholder": placeholder, "label": label, "hint": hint,
		"window": window,
	}


## The illustration window inside a card. When the kit ships card_layout.json
## (measured off the generated frame art) that geometry wins; otherwise a
## sensible inset default matches the procedural frame.
func _card_window_rect(card_size: Vector2) -> Rect2:
	var layout := _kit2_layout()
	if not layout.is_empty():
		var size_block: Dictionary = layout.get("size", {}) as Dictionary
		var window_block: Dictionary = layout.get("window", {}) as Dictionary
		var tex_w := float(size_block.get("w", 0.0))
		var tex_h := float(size_block.get("h", 0.0))
		if tex_w > 0.0 and tex_h > 0.0:
			return Rect2(
				Vector2(float(window_block.get("x", 0.0)) / tex_w, float(window_block.get("y", 0.0)) / tex_h) * Vector2(card_size.x, card_size.y),
				Vector2(float(window_block.get("w", 0.0)) / tex_w, float(window_block.get("h", 0.0)) / tex_h) * Vector2(card_size.x, card_size.y))
	var inset := 12.0
	return Rect2(Vector2(inset, inset), Vector2(card_size.x - inset * 2.0, card_size.y * 0.70 - inset))


var _kit2_layout_cache: Variant = null

func _kit2_layout() -> Dictionary:
	if _kit2_layout_cache is Dictionary:
		return _kit2_layout_cache
	_kit2_layout_cache = {}
	var path := KIT2_DIR + "card_layout.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_kit2_layout_cache = parsed
	return _kit2_layout_cache


## Waiting-for-art / no-art look: moonlit gradient with a faint crescent floating
## in the window. Doubles as the permanent look when the step hasn't run.
func _build_card_placeholder(window: Rect2) -> Control:
	var placeholder := Control.new()
	placeholder.position = window.position
	placeholder.size = window.size
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash := ColorRect.new()
	wash.color = Color(0.030, 0.048, 0.096, 1.0)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.add_child(wash)
	var crescent := _tex("crescent_emblem.png")
	if crescent != null:
		var h := window.size.y * 0.42
		var w := h * crescent.get_width() / maxf(1.0, float(crescent.get_height()))
		var mark := _stretch(crescent, Vector2(w, h), Vector2((window.size.x - w) * 0.5, (window.size.y - h) * 0.5))
		mark.modulate = Color(1, 1, 1, 0.16)
		placeholder.add_child(mark)
	return placeholder


## Procedural card frame used until the choice_v2 kit exists: thin silver border
## on the glass, plus a cold glow halo for the selected state.
func _procedural_frame(card_size: Vector2, selected: bool) -> Control:
	var frame := Panel.new()
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_corner_radius_all(7)
	style.set_border_width_all(2 if not selected else 3)
	style.border_color = Color(SILVER.r, SILVER.g, SILVER.b, 0.38) if not selected else Color(0.92, 0.96, 1.0, 0.95)
	if selected:
		style.shadow_color = Color(ICE.r, ICE.g, ICE.b, 0.32)
		style.shadow_size = 14
	frame.add_theme_stylebox_override("panel", style)
	frame.position = Vector2.ZERO
	frame.size = card_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


## Resolve one card's illustration: ceremony-local cache → QuestManager's
## prefetched chapter cache → lazy download from the option's illustration_url.
## Never blocks the ceremony; the placeholder simply stays when nothing lands.
func _resolve_card_art(index: int) -> void:
	if index >= _options.size() or index >= _cards.size():
		return
	var option: Dictionary = _options[index] as Dictionary
	var option_id := str(option.get("id", ""))
	if option_id.is_empty():
		return
	var texture: Texture2D = _card_art.get(option_id)
	if texture == null:
		texture = QuestManager.choice_illustration(option_id)
	if texture == null:
		var url := str(option.get("illustration_url", ""))
		if url.is_empty():
			return
		var flow := get_node_or_null("/root/ChapterFlow")
		if flow == null or not flow.has_method("download_image_texture"):
			return
		texture = await flow.download_image_texture(url)
		if texture != null:
			QuestManager.set_choice_illustration(option_id, texture)
	if texture == null or _closing or index >= _cards.size():
		return
	_card_art[option_id] = texture
	var card: Dictionary = _cards[index] as Dictionary
	_mount_card_art(card, texture)


func _mount_card_art(card: Dictionary, texture: Texture2D) -> void:
	var image := card.get("image") as TextureRect
	var placeholder := card.get("placeholder") as Control
	if image == null or not is_instance_valid(image):
		return
	var window: Rect2 = card.get("window", Rect2()) as Rect2
	image.texture = _cover_cropped(texture, window.size)
	image.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(image, "modulate:a", 1.0, 0.35)
	if placeholder != null and is_instance_valid(placeholder):
		fade.parallel().tween_property(placeholder, "modulate:a", 0.0, 0.35)


func _apply_selection() -> void:
	for index in range(_cards.size()):
		var entry: Dictionary = _cards[index] as Dictionary
		var is_sel := index == _selected
		(entry["selected"] as Control).visible = is_sel
		(entry["normal"] as Control).visible = not is_sel
		var holder := entry["holder"] as Control
		var scale_tween := create_tween()
		scale_tween.tween_property(holder, "scale", Vector2.ONE if is_sel else Vector2(0.955, 0.955), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		(entry["image"] as TextureRect).self_modulate = Color(1, 1, 1, 1) if is_sel else Color(0.72, 0.76, 0.85, 1.0)
		(entry["label"] as Label).add_theme_color_override(
			"font_color", SILVER if is_sel else Color(0.66, 0.72, 0.84, 0.66))
		if entry["hint"] != null:
			(entry["hint"] as Label).add_theme_color_override(
				"font_color", SILVER_DIM if is_sel else Color(0.66, 0.72, 0.84, 0.36))
		if is_sel and _cursor != null:
			# The moonstone gem sits ON the card's left border (mockup), not beside it.
			_cursor.position = holder.position + Vector2(-22.0, holder.size.y * 0.5 - 20.0)


func _arm_confirm() -> void:
	if _cards.is_empty():
		_close()
		return
	_phase = Phase.ARMED
	_footer_parts(_footer, [
		{"keys": ["Enter"], "text": "lần nữa — quyết định không thể đảo ngược"},
		{"keys": ["Esc"], "text": "nghĩ lại"},
	], Color(SILVER.r, SILVER.g, SILVER.b, 0.85))
	var entry: Dictionary = _cards[_selected] as Dictionary
	var frame := entry["selected"] as Control
	var flash := create_tween()
	flash.tween_property(frame, "modulate", Color(1.35, 1.35, 1.5, 1.0), 0.12)
	flash.tween_property(frame, "modulate", Color.WHITE, 0.30)


func _disarm_confirm() -> void:
	_phase = Phase.CHOICE
	_footer_parts(_footer, [
		{"keys": ["←", "→"], "text": "Chọn"},
		{"keys": ["Enter"], "text": "Xác nhận"},
	], Color(SILVER.r, SILVER.g, SILVER.b, 0.48))


func _move_selection(delta: int) -> void:
	_selected = clampi(_selected + delta, 0, maxi(_cards.size() - 1, 0))
	_apply_selection()


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
	# Mockup layout (reveal_raw.png): the chosen card stays LARGE on the left;
	# the right column stacks cracked crescent + title, the NPC reaction row
	# (medallion, name over a thin rule, floating italic quote — no box), the
	# HẬU QUẢ header, a 2-per-row grid of consequence plaques, then a full-width
	# narrator caption and the keycap footer.
	var vp := _viewport_size()
	var cx := vp.x * 0.5
	_reveal_group = Control.new()
	_reveal_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_group.modulate.a = 0.0
	_root.add_child(_reveal_group)

	# The chosen card, sealed as a keepsake — same size as the choice phase.
	var card_size := Vector2(CARD_W, CARD_H)
	var card_pos := Vector2(96.0, 116.0)
	var keepsake := _build_card(option, card_size, true)
	var keepsake_holder := keepsake["holder"] as Control
	keepsake_holder.position = card_pos
	(keepsake["selected"] as Control).visible = true
	(keepsake["normal"] as Control).visible = false
	_reveal_group.add_child(keepsake_holder)
	keepsake_holder.scale = Vector2(0.94, 0.94)
	var settle := create_tween()
	settle.tween_property(keepsake_holder, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var option_id := str(option.get("id", ""))
	var art: Texture2D = _card_art.get(option_id)
	if art == null:
		art = QuestManager.choice_illustration(option_id)
	if art != null:
		_mount_card_art(keepsake, art)

	# Right column axis: centered in the space the card leaves free.
	var rx := card_pos.x + card_size.x + (vp.x - (card_pos.x + card_size.x) - 40.0) * 0.5
	_place_emblem(_reveal_group, "crescent_cracked.png", Vector2(rx, 58.0), 58.0)
	_place_title(_reveal_group, "ĐÃ QUYẾT ĐỊNH", Vector2(rx, 104.0), 22)
	_place_divider(_reveal_group, Vector2(rx, 126.0), 320.0)

	# NPC reaction row: medallion left, name over a thin rule, floating quote.
	var reaction := str(result.get("npc_reaction", "")).strip_edges()
	if reaction.is_empty():
		reaction = str(option.get("npc_reaction", "")).strip_edges()
	if reaction.is_empty():
		reaction = "Vậy là ngươi đã quyết."
	var row_top := 146.0
	var has_portrait := _npc_portrait != null
	var text_left := rx - 240.0
	if has_portrait:
		_place_medallion(_reveal_group, Vector2(rx - 250.0, row_top + 62.0), 100.0)
		text_left = rx - 178.0
	var text_width := rx + 250.0 - text_left
	var quote_top := row_top + 10.0
	if not _npc_name.is_empty():
		var who := _make_serif(_npc_name, 11, SILVER_DIM)
		who.uppercase = true
		who.position = Vector2(text_left, row_top)
		who.size = Vector2(text_width, 14.0)
		_reveal_group.add_child(who)
		var rule := ColorRect.new()
		rule.color = Color(SILVER.r, SILVER.g, SILVER.b, 0.22)
		rule.position = Vector2(text_left, row_top + 20.0)
		rule.size = Vector2(minf(text_width, 220.0), 1.0)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reveal_group.add_child(rule)
		quote_top = row_top + 28.0
	var quote := _make_serif("“%s”" % reaction, 14, Color(0.96, 0.97, 1.0, 0.95), true)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quote.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.max_lines_visible = 4
	quote.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	quote.position = Vector2(text_left, quote_top)
	quote.size = Vector2(text_width, 96.0)
	quote.visible_characters = 0
	_reveal_group.add_child(quote)
	var quote_type := func(count: int) -> void: quote.visible_characters = count
	var quote_chars := quote.get_total_character_count()
	var type_tween := create_tween()
	type_tween.tween_interval(0.30)
	type_tween.tween_method(quote_type, 0, quote_chars, minf(1.2, 0.024 * quote_chars))

	# HẬU QUẢ header between ornamented dividers, then the plaque grid.
	var chips: Array = result.get("chips", []) as Array
	if chips.is_empty():
		chips = [{"icon": "item", "tone": "neutral", "text": "Câu chuyện sẽ ghi nhớ điều này"}]
	var section_y := 296.0
	var header := _make_serif("HẬU QUẢ", 13, SILVER_DIM)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.uppercase = true
	header.position = Vector2(rx - 120.0, section_y)
	header.size = Vector2(240.0, 18.0)
	_reveal_group.add_child(header)
	_place_divider(_reveal_group, Vector2(rx - 175.0, section_y + 9.0), 110.0)
	_place_divider(_reveal_group, Vector2(rx + 175.0, section_y + 9.0), 110.0)

	# Plaques follow the mockup's larger 2-column grid; with more than 4 chips
	# the grid tightens so the caption band is never squeezed.
	var per_row := 2
	var chip_h := 56.0 if chips.size() <= 4 else 48.0
	var chip_w := chip_h * (400.0 / 92.0)  # chip_frame.png baked aspect
	var chip_gap := 16.0
	var row_gap := 12.0 if chips.size() <= 4 else 8.0
	var grid_top := section_y + 28.0
	var delay := 0.55
	for index in range(chips.size()):
		var chip: Dictionary = chips[index] as Dictionary
		var row: int = int(float(index) / float(per_row))
		var in_row_count: int = mini(chips.size() - row * per_row, per_row)
		var col := index % per_row
		var row_w := in_row_count * chip_w + (in_row_count - 1) * chip_gap
		var pos := Vector2(rx - row_w * 0.5 + col * (chip_w + chip_gap), grid_top + row * (chip_h + row_gap))
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

	# Narrator caption — full-width beneath card and grid (its mockup home),
	# clamped clear of the footer line.
	var rows := ceili(float(chips.size()) / float(per_row))
	var caption_text := str(result.get("consequence_text", "")).strip_edges()
	if not caption_text.is_empty():
		var caption := _make_serif(caption_text, 13, Color(0.82, 0.86, 0.94, 0.70), true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.max_lines_visible = 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var grid_bottom := grid_top + rows * (chip_h + row_gap) - row_gap
		var caption_y: float = minf(maxf(grid_bottom + 14.0, card_pos.y + card_size.y + 14.0), vp.y - 86.0)
		caption.position = Vector2(cx - 380.0, caption_y)
		caption.size = Vector2(760.0, 40.0)
		_reveal_group.add_child(caption)

	var footer := _build_footer(_reveal_group, vp.y - 38.0)
	_footer_parts(footer, [{"keys": ["Enter"], "text": "Tiếp tục"}], Color(SILVER.r, SILVER.g, SILVER.b, 0.48))
	footer.modulate.a = 0.0
	var footer_in := create_tween()
	footer_in.tween_interval(delay + chips.size() * 0.14 + 0.35)
	footer_in.tween_property(footer, "modulate:a", 1.0, 0.3)


func _build_chip(chip: Dictionary, chip_size: Vector2) -> Control:
	# Contents scale with the plaque height so the mockup's larger reveal grid
	# and any tightened variant read identically.
	var holder := Control.new()
	holder.size = chip_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_stretch(_tex("chip_frame.png"), chip_size, Vector2.ZERO))
	var icon_side := chip_size.y * 0.58
	var icon_left := chip_size.y * 0.28
	var text_left := icon_left + icon_side + 10.0
	var icon_name := str(chip.get("icon", "item"))
	var icon_tex := _tex("icons/%s.png" % icon_name)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.size = Vector2(icon_side, icon_side)
		icon.position = Vector2(icon_left, (chip_size.y - icon_side) * 0.5)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
	var tone := str(chip.get("tone", "neutral"))
	var color := RED_COLD if tone == "loss" else (ICE if tone == "gain" else SILVER_DIM)
	var text := _make_serif(str(chip.get("text", "")), 13 if chip_size.y >= 52.0 else 12, color)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.position = Vector2(text_left, 0.0)
	text.size = Vector2(chip_size.x - text_left - 14.0, chip_size.y)
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
			if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
				_move_selection(1)
			elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
				_move_selection(-1)
			elif event.is_action_pressed("ui_accept"):
				_arm_confirm()
		Phase.ARMED:
			if event.is_action_pressed("ui_accept"):
				_confirm_choice()
			elif event.is_action_pressed("ui_cancel"):
				_disarm_confirm()
			elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down") \
					or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
				_disarm_confirm()
				if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
					_move_selection(1)
				else:
					_move_selection(-1)
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


func _tex2(file_name: String) -> Texture2D:
	var path := KIT2_DIR + file_name
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


## Center-crop a texture to the window's aspect in Image space — the card
## window then scales it uniformly (never squashed, never letterboxed).
func _cover_cropped(texture: Texture2D, target_size: Vector2) -> Texture2D:
	if texture == null or target_size.x <= 0.0 or target_size.y <= 0.0:
		return texture
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var src_w := image.get_width()
	var src_h := image.get_height()
	var target_aspect := target_size.x / target_size.y
	var src_aspect := float(src_w) / maxf(1.0, float(src_h))
	var crop_w := src_w
	var crop_h := src_h
	if src_aspect > target_aspect:
		crop_w = int(round(src_h * target_aspect))
	else:
		crop_h = int(round(src_w / target_aspect))
	var x0 := int((src_w - crop_w) * 0.5)
	# Bias the vertical crop upward — faces live in the upper half of the art.
	var y0 := int((src_h - crop_h) * 0.38)
	var out := Image.create(crop_w, crop_h, false, Image.FORMAT_RGBA8)
	out.blit_rect(image, Rect2i(x0, y0, crop_w, crop_h), Vector2i.ZERO)
	return ImageTexture.create_from_image(out)


func _place_emblem(parent: Control, file_name: String, center: Vector2, height: float) -> void:
	var texture := _tex(file_name)
	if texture == null:
		return
	var width := height * texture.get_width() / maxf(1.0, float(texture.get_height()))
	var rect := _stretch(texture, Vector2(width, height), center - Vector2(width * 0.5, height * 0.5))
	parent.add_child(rect)


func _place_title(parent: Control, text: String, center: Vector2, font_size: int = 26) -> void:
	var title := UiKit.make_title(text, font_size, SILVER)
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


## Footer key-hint line rendered as keycap chips ( [←][→] Chọn · [Enter] Xác
## nhận — the mockup's treatment) instead of a plain text string.
func _build_footer(parent: Control, y: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, y)
	row.size = Vector2(_viewport_size().x, 22.0)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


func _footer_parts(row: HBoxContainer, parts: Array, color: Color) -> void:
	for child in row.get_children():
		child.queue_free()
	var first := true
	for part in parts:
		if not (part is Dictionary):
			continue
		if not first:
			var sep := _make_serif("·", 11, Color(color.r, color.g, color.b, color.a * 0.6))
			sep.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(sep)
		first = false
		for key in (part as Dictionary).get("keys", []) as Array:
			row.add_child(_make_keycap(str(key), color))
		var text := _make_serif(str((part as Dictionary).get("text", "")), 11, color)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(text)


func _make_keycap(glyph: String, color: Color) -> Control:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.06)
	style.set_border_width_all(1)
	style.border_color = Color(color.r, color.g, color.b, color.a * 0.55)
	style.set_corner_radius_all(4)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 2.0
	cap.add_theme_stylebox_override("panel", style)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_serif(glyph, 10, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_child(label)
	return cap


## Soft frameless haze behind floating text — smooth gradients are the one case
## where stretching is invisible, so a procedural panel serves any size. Kept
## deliberately faint (the mockup's dilemma floats with no visible box).
func _place_haze(parent: Control, rect: Rect2) -> void:
	var haze := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008, 0.014, 0.034, 0.30)
	style.set_corner_radius_all(int(minf(22.0, rect.size.y * 0.30)))
	style.shadow_color = Color(0.008, 0.014, 0.034, 0.22)
	style.shadow_size = 22
	haze.add_theme_stylebox_override("panel", style)
	haze.position = rect.position
	haze.size = rect.size
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(haze)


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
