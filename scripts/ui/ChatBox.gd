extends CanvasLayer

const MenuCursorScript := preload("res://scripts/ui/MenuCursor.gd")

const BUBBLE_RADIUS    := 5
const BUBBLE_MAX_RATIO_NPC := 0.90
const BUBBLE_MAX_RATIO_PLR := 0.68
const AVATAR_SIZE      := 20.0
const AVATAR_GAP       := 4.0
const FONT_SIZE        := 8
const DOT_INTERVAL     := 0.38

const COLOR_NPC_BG     := Color(0.09, 0.07, 0.20, 0.95)
const COLOR_NPC_BORDER := Color(0.78, 0.60, 0.26, 0.65)
const COLOR_PLR_BG     := Color(0.18, 0.15, 0.36, 0.95)
const COLOR_PLR_BORDER := Color(0.52, 0.62, 0.82, 0.55)
const COLOR_TEXT       := Color(0.93, 0.88, 0.75, 1.00)

# Option bubble colours
const COLOR_OPT_BG_DIM     := Color(0.14, 0.11, 0.28, 0.38)
const COLOR_OPT_BG_LIT     := Color(0.22, 0.18, 0.42, 0.95)
const COLOR_OPT_BORDER_DIM := Color(0.52, 0.62, 0.82, 0.22)
const COLOR_OPT_BORDER_LIT := Color(0.72, 0.82, 1.00, 0.85)
const COLOR_OPT_TEXT_DIM   := Color(0.93, 0.88, 0.75, 0.38)
const COLOR_OPT_TEXT_LIT   := Color(0.93, 0.88, 0.75, 1.00)
const COLOR_OPT_ARROW      := Color(1.00, 0.85, 0.45, 1.00)

const OPT_ROW_H := 14.0   # height of each option row (px)
const OPT_SEP   := 2.0    # separation between rows
const OPT_GAP   := 5.0    # gap between options panel and neighbours

var _npc_name      : String = ""
var _npc_data      : Dictionary = {}
var _npc_id        : String = ""
var _default_portrait_texture: Texture2D = null
var _portrait_textures: Dictionary = {}
var _loading_label : Label  = null
var _dot_count     : int    = 1
var _dot_timer     : float  = 0.0
var _chat_history     : Array  = []
var _stream_label     : Label  = null   # label in the currently streaming NPC bubble
var _stream_is_waiting: bool   = false  # true while waiting for first token
var _scroll_countdown : int    = 0      # frames remaining to force-scroll to bottom

# Options state
var _options      : Array[String]      = []
var _selected_opt : int                = 0
var _opt_rows     : Array[Node]        = []
var _opt_styles   : Array[StyleBoxFlat]= []
var _opt_cursors  : Array[CanvasItem]  = []
var _opt_labels   : Array[Label]       = []
var _opt_container: VBoxContainer      = null

# Layout cache (set in _layout, used when showing/hiding options)
var _ib_x          : float = 0.0
var _ib_w          : float = 0.0
var _input_top     : float = 0.0   # top y of the input bar
var _scroll_y      : float = 0.0   # top y of the chat scroll
var _scroll_normal_h: float = 0.0  # scroll height when no options shown

@onready var _panel:        TextureRect     = $Panel
@onready var _gem:          TextureRect     = $Gem
@onready var _portrait_bg:  TextureRect     = $PortraitBg
@onready var _portrait_fg:  TextureRect     = $PortraitFg
@onready var _npc_portrait: TextureRect     = $NpcPortrait
@onready var _input_bar:    TextureRect     = $InputBar
@onready var _chat_input:   LineEdit        = $ChatInput
@onready var _send_btn:     Button          = $SendButton
@onready var _npc_label:    Label           = $NpcLabel
@onready var _chat_scroll:  ScrollContainer = $ChatScroll
@onready var _messages:     VBoxContainer   = $ChatScroll/Messages

func _ready() -> void:
	layer   = 64
	transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))  # UI authored in 480x270
	visible = false
	_default_portrait_texture = _npc_portrait.texture
	_opt_container = VBoxContainer.new()
	_opt_container.add_theme_constant_override("separation", int(OPT_SEP))
	_opt_container.visible = false
	add_child(_opt_container)
	_layout()
	_send_btn.pressed.connect(_on_send)
	_chat_input.text_submitted.connect(_on_send)
	_chat_input.text_changed.connect(_on_input_text_changed)

func _on_input_text_changed(_new_text: String) -> void:
	_apply_options_layout()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size / 2.0
	var pw := vp.x - 20.0
	var ph := pw * (394.0 / 1199.0)
	var px := 10.0
	var py := vp.y - ph - 8.0

	_panel.size     = Vector2(pw, ph)
	_panel.position = Vector2(px, py)

	var gem_h := ph * 0.70
	var gem_w := gem_h * (46.0 / 252.0)
	_gem.size     = Vector2(gem_w, gem_h)
	_gem.position = Vector2(px + pw - gem_w - 5.0, py + 8.0)

	var pf_h   := ph * 1.08
	var pf_w   := pf_h * (317.0 / 443.0)
	var pf_pos := Vector2(px, py - (pf_h - ph) * 0.5 - 10.0)
	_portrait_bg.size     = Vector2(pf_w, pf_h)
	_portrait_bg.position = pf_pos
	_portrait_fg.size     = Vector2(pf_w, pf_h)
	_portrait_fg.position = pf_pos

	var np_w := pf_w * 0.82
	var np_h := np_w * (821.0 / 517.0)
	_npc_portrait.size     = Vector2(np_w, np_h)
	_npc_portrait.position = Vector2(pf_pos.x + (pf_w - np_w) * 0.5,
									 pf_pos.y + pf_h * 0.05 - 10.0)

	var ib_x := px + pf_w + 24.0
	var ib_w := px + pw - ib_x - 60.0
	var ib_h := ib_w * (83.0 / 710.0)
	var ib_y := py + ph - ib_h - 6.0
	_input_bar.size     = Vector2(ib_w, ib_h)
	_input_bar.position = Vector2(ib_x, ib_y - 5.0)

	var leaf_w := ib_h
	var pad_h  := ib_h * 0.10
	var line_h := 12.0
	_chat_input.size     = Vector2(ib_w - leaf_w - pad_h * 2.0 - 18.0, line_h)
	_chat_input.position = Vector2(ib_x + pad_h + 10.0, ib_y + (ib_h - line_h) * 0.5 - 15.0)
	_style_input()

	_send_btn.size     = Vector2(leaf_w, ib_h)
	_send_btn.position = Vector2(ib_x + ib_w - leaf_w, ib_y)

	var label_h := 10.0
	_npc_label.size     = Vector2(pf_w, label_h)
	_npc_label.position = Vector2(pf_pos.x, pf_pos.y + pf_h - label_h - 12.0)
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_label.add_theme_font_size_override("font_size", 12)
	_npc_label.add_theme_color_override("font_color", Color(1.00, 0.85, 0.45))

	_ib_x           = ib_x
	_ib_w           = ib_w
	_input_top      = ib_y - 5.0
	_scroll_y       = py + 22.0
	_scroll_normal_h = _input_top - _scroll_y - 10.0

	_chat_scroll.size     = Vector2(ib_w, _scroll_normal_h)
	_chat_scroll.position = Vector2(ib_x, _scroll_y)
	_style_scroll()
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages.add_theme_constant_override("separation", 5)

func _style_input() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color            = Color(0, 0, 0, 0)
	style.border_width_left   = 0
	style.border_width_right  = 0
	style.border_width_top    = 0
	style.border_width_bottom = 0
	_chat_input.add_theme_stylebox_override("normal", style)
	_chat_input.add_theme_stylebox_override("focus",  style)
	_chat_input.add_theme_color_override("font_color",             Color(0.93, 0.88, 0.75))
	_chat_input.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.40))
	_chat_input.add_theme_font_size_override("font_size", FONT_SIZE)

func _style_scroll() -> void:
	var empty := StyleBoxEmpty.new()
	_chat_scroll.add_theme_stylebox_override("panel", empty)
	_chat_scroll.get_v_scroll_bar().modulate.a = 0.0
	_chat_scroll.get_h_scroll_bar().modulate.a = 0.0

# ── avatar ─────────────────────────────────────────────────────────────────────

func _make_avatar(is_player: bool) -> Control:
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color     = COLOR_PLR_BG     if is_player else COLOR_NPC_BG
	style.border_color = COLOR_PLR_BORDER if is_player else COLOR_NPC_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(AVATAR_SIZE * 0.5))
	avatar.add_theme_stylebox_override("panel", style)

	var icon := Label.new()
	icon.text                  = "P" if is_player else "N"
	icon.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	icon.add_theme_font_size_override("font_size", 6)
	icon.add_theme_color_override("font_color",
		Color(0.52, 0.62, 0.82, 0.80) if is_player else Color(0.78, 0.60, 0.26, 0.80))
	avatar.add_child(icon)
	return avatar

# ── bubble builder ─────────────────────────────────────────────────────────────

func _add_bubble(text: String, is_player: bool) -> void:
	_add_bubble_return_label(text, is_player)

func _add_bubble_return_label(text: String, is_player: bool) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var bubble_ratio := BUBBLE_MAX_RATIO_PLR if is_player else BUBBLE_MAX_RATIO_NPC

	var panel := PanelContainer.new()
	panel.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = bubble_ratio

	var style := StyleBoxFlat.new()
	style.bg_color     = COLOR_PLR_BG     if is_player else COLOR_NPC_BG
	style.border_color = COLOR_PLR_BORDER if is_player else COLOR_NPC_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(BUBBLE_RADIUS)
	if is_player:
		style.corner_radius_bottom_right = 1
	else:
		style.corner_radius_bottom_left = 1
	style.content_margin_left   = 7.0
	style.content_margin_right  = 7.0
	style.content_margin_top    = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text          = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	panel.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 1.0 - bubble_ratio

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(AVATAR_GAP, 0)

	var avatar := _make_avatar(is_player)

	if is_player:
		row.add_child(spacer)
		row.add_child(panel)
		row.add_child(gap)
		row.add_child(avatar)
	else:
		row.add_child(avatar)
		row.add_child(gap)
		row.add_child(panel)
		row.add_child(spacer)

	_messages.add_child(row)
	_scroll_to_bottom()
	return label

# ── portrait emotion ──────────────────────────────────────────────────────────

func _prepare_portraits() -> void:
	_portrait_textures.clear()
	var portrait_data: Variant = _npc_data.get("emotion_portraits", {})
	if not (portrait_data is Dictionary):
		return

	var portraits: Variant = (portrait_data as Dictionary).get("portraits", [])
	if not (portraits is Array):
		return

	for raw_portrait in portraits:
		if not (raw_portrait is Dictionary):
			continue
		var portrait := raw_portrait as Dictionary
		var emotion: String = _normalize_emotion(str(portrait.get("emotion", "")))
		var file_name: String = str(portrait.get("file", ""))
		if emotion.is_empty() or file_name.is_empty():
			continue
		var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(file_name))
		if texture != null:
			_portrait_textures[emotion] = texture

func _set_portrait_for_emotion(emotion: String) -> void:
	var normalized: String = _normalize_emotion(emotion)
	var texture: Texture2D = _portrait_textures.get(normalized, null) as Texture2D
	if texture == null and normalized != "neutral":
		texture = _portrait_textures.get("neutral", null) as Texture2D
		normalized = "neutral"
	if texture == null:
		texture = _default_portrait_texture
	_npc_portrait.texture = texture
	if not normalized.is_empty():
		print("[ChatBox] portrait npc=%s emotion=%s" % [_npc_id, normalized])

func _normalize_emotion(emotion: String) -> String:
	var cleaned: String = emotion.strip_edges().to_lower()
	match cleaned:
		"happy", "joy", "joyful", "pleased", "relieved":
			return "happy"
		"angry", "anger", "mad", "irritated", "annoyed":
			return "angry"
		"sad", "sorrow", "worried", "wary", "uneasy", "haunted", "tired", "afraid", "scared":
			return "sad"
		"neutral", "calm", "curious", "":
			return "neutral"
	return cleaned

# ── options ────────────────────────────────────────────────────────────────────

func _show_options(raw_options: Array) -> void:
	_clear_options()
	_selected_opt = 0

	for opt in raw_options:
		_options.append(str(opt))

	for i in range(_options.size()):
		var label_text := _options[i]

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, OPT_ROW_H)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var sbox := StyleBoxFlat.new()
		sbox.set_border_width_all(1)
		sbox.set_corner_radius_all(3)
		sbox.content_margin_left   = 8.0
		sbox.content_margin_right  = 6.0
		sbox.content_margin_top    = 2.0
		sbox.content_margin_bottom = 2.0
		panel.add_theme_stylebox_override("panel", sbox)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		panel.add_child(row)

		var cursor := Control.new()
		cursor.custom_minimum_size = Vector2(7, 9)
		cursor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cursor.script = MenuCursorScript
		row.add_child(cursor)

		var lbl := Label.new()
		lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text             = true
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		row.add_child(lbl)

		var idx := i
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_selected_opt = idx
				_confirm_option()
		)

		_opt_container.add_child(panel)
		_opt_rows.append(panel)
		_opt_styles.append(sbox)
		_opt_cursors.append(cursor)
		_opt_labels.append(lbl)

	_update_option_highlight()
	_apply_options_layout()

func _apply_options_layout() -> void:
	if _options.is_empty() or _chat_input == null:
		_opt_container.visible = false
		_chat_scroll.size.y = _scroll_normal_h
		return
	if not _chat_input.text.is_empty():
		# options hidden while typing — restore scroll but don't show container
		_opt_container.visible = false
		_chat_scroll.size.y = _scroll_normal_h
		return
	var n       := _options.size()
	var opt_h   := n * OPT_ROW_H + (n - 1) * OPT_SEP
	var opt_y   := _input_top - OPT_GAP - opt_h
	_opt_container.position = Vector2(_ib_x, opt_y)
	_opt_container.size     = Vector2(_ib_w, opt_h)
	_opt_container.visible  = true
	_chat_scroll.size.y     = max(opt_y - OPT_GAP - _scroll_y, 20.0)
	_scroll_to_bottom()

func _clear_options() -> void:
	for row in _opt_rows:
		if is_instance_valid(row):
			row.queue_free()
	_opt_rows.clear()
	_opt_styles.clear()
	_opt_cursors.clear()
	_opt_labels.clear()
	_options.clear()
	if _opt_container != null:
		_opt_container.visible = false
	_chat_scroll.size.y = _scroll_normal_h

func _update_option_highlight() -> void:
	for i in range(_opt_labels.size()):
		var lit := (i == _selected_opt)
		_opt_styles[i].bg_color     = COLOR_OPT_BG_LIT     if lit else COLOR_OPT_BG_DIM
		_opt_styles[i].border_color = COLOR_OPT_BORDER_LIT if lit else COLOR_OPT_BORDER_DIM
		_opt_cursors[i].visible = lit
		_opt_labels[i].text = _options[i]
		_opt_labels[i].add_theme_color_override("font_color",
			COLOR_OPT_TEXT_LIT if lit else COLOR_OPT_TEXT_DIM)
		_opt_labels[i].add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.55) if lit else Color(0, 0, 0, 0))

func _confirm_option() -> void:
	if _options.is_empty() or _selected_opt >= _options.size():
		return
	var opt := _options[_selected_opt]
	_clear_options()
	_send_to_npc(opt)

# ── scroll ──────────────────────────────────────────────────────────────────────

func _scroll_to_bottom() -> void:
	_scroll_countdown = 6

# ── events ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible or _options.is_empty() or not _opt_container.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_UP:
			_selected_opt = (_selected_opt - 1 + _options.size()) % _options.size()
			_update_option_highlight()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_selected_opt = (_selected_opt + 1) % _options.size()
			_update_option_highlight()
			get_viewport().set_input_as_handled()

func _on_send(_text: String = "") -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		if not _options.is_empty():
			_confirm_option()
		return
	_chat_input.text = ""
	_chat_input.grab_focus()
	_clear_options()
	_send_to_npc(msg)

func _send_to_npc(player_msg: String) -> void:
	# cancel_all() stops both start-stream and any previous reply-stream
	NPCConversationManager.cancel_all()
	_stream_label      = null
	_stream_is_waiting = false

	_add_bubble(player_msg, true)
	_chat_history.append({"speaker": "player", "text": player_msg})

	# Create NPC bubble; shows "..." until first token arrives
	_dot_count         = 1
	_dot_timer         = 0.0
	_stream_label      = _add_bubble_return_label(".", false)
	_stream_is_waiting = true

	NPCConversationManager.stream_reply(
		_npc_id,
		player_msg,
		_chat_history.duplicate(),
		GameManager.get_scene_context(),
		_on_stream_token,
		_on_stream_final,
		_on_stream_error
	)

func _on_stream_token(token: String) -> void:
	if _stream_label != null and is_instance_valid(_stream_label):
		if _stream_is_waiting:
			_stream_is_waiting = false
			_stream_label.text = ""
		_stream_label.text += token
		_scroll_to_bottom()

func _on_stream_final(data: Dictionary) -> void:
	_stream_is_waiting = false
	var final_text := str(data.get("npc_reply", ""))
	var emotion := str(data.get("npc_emotion", "neutral"))
	_set_portrait_for_emotion(emotion)
	if _stream_label != null and is_instance_valid(_stream_label):
		if not final_text.is_empty():
			_stream_label.text = final_text
		_stream_label = null

	if not final_text.is_empty():
		_chat_history.append({
			"speaker": "npc",
			"text": final_text,
			"emotion": emotion,
		})

	if data.get("conversation_ended", false):
		_scroll_to_bottom()
		await get_tree().create_timer(1.5).timeout
		close()
		return

	var opts: Variant = data.get("options", [])
	if opts is Array and not (opts as Array).is_empty():
		_show_options(opts as Array)
	else:
		_scroll_to_bottom()

func _on_stream_error(error: String) -> void:
	_stream_is_waiting = false
	if _stream_label != null and is_instance_valid(_stream_label):
		_stream_label.text = "[error]"
		_stream_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		_stream_label = null
	print("[ChatBox] stream error: ", error)

func _process(delta: float) -> void:
	if visible and not _chat_input.has_focus():
		_chat_input.grab_focus()

	if _scroll_countdown > 0:
		_scroll_countdown -= 1
		_chat_scroll.scroll_vertical = _chat_scroll.get_v_scroll_bar().max_value

	var dot_target: Label = null
	if _stream_is_waiting and _stream_label != null and is_instance_valid(_stream_label):
		dot_target = _stream_label
	if dot_target == null:
		return
	_dot_timer += delta
	if _dot_timer >= DOT_INTERVAL:
		_dot_timer = 0.0
		_dot_count = (_dot_count % 3) + 1
		dot_target.text = ".".repeat(_dot_count)

func open(npc_name: String, npc_data: Dictionary, npc_id: String = "", bubble_line: String = "") -> void:
	_npc_name = npc_name
	_npc_data = npc_data
	_npc_id   = npc_id
	_npc_label.text        = npc_name
	_prepare_portraits()
	_set_portrait_for_emotion("neutral")
	_chat_input.editable   = true
	_chat_input.placeholder_text = "Say something..."
	_send_btn.disabled     = false
	_loading_label         = null
	_stream_label      = null
	_stream_is_waiting = false
	_dot_count         = 1
	_dot_timer         = 0.0
	_chat_history      = NPCConversationManager.get_history(npc_id).duplicate()
	_clear_options()

	for child in _messages.get_children():
		child.queue_free()

	if not bubble_line.is_empty():
		_add_bubble(bubble_line, false)

	# Bootstrap: call reply-stream with a silent greeting to get the initial options.
	# Token events are ignored — bubble_line is already shown as the opener.
	NPCConversationManager.stream_reply(
		npc_id,
		"xin chào",
		[],
		GameManager.get_scene_context(),
		func(_token: String) -> void: pass,
		_on_start_final,
		_on_start_error
	)

	GameManager.ui_blocking_input = true
	visible = true
	_chat_input.grab_focus()

func _on_start_final(data: Dictionary) -> void:
	# Sync history now that NPCConversationManager has stored the opener
	_chat_history = NPCConversationManager.get_history(_npc_id).duplicate()
	_set_portrait_for_emotion(str(data.get("npc_emotion", "neutral")))
	var opts: Variant = data.get("options", [])
	if opts is Array and not (opts as Array).is_empty():
		_show_options(opts as Array)

func _on_start_error(error: String) -> void:
	print("[ChatBox] start-stream error: ", error)

func close() -> void:
	NPCConversationManager.cancel_all()
	_loading_label     = null
	_stream_label      = null
	_stream_is_waiting = false
	GameManager.ui_blocking_input = false
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_global_rect().has_point(event.position):
			close()
			get_viewport().set_input_as_handled()
