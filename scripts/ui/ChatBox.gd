extends CanvasLayer

const MenuCursorScript := preload("res://scripts/ui/MenuCursor.gd")
const InteractionPromptScript := preload("res://scripts/npc/InteractionPrompt.gd")

const TEX_DIALOGUE_PANEL_PATH := "res://assets/ui/dialogue_v2/dialogue_panel.png"
const TEX_PORTRAIT_FRAME_PATH := "res://assets/ui/dialogue_v2/portrait_frame.png"
const TEX_NAMEPLATE_PATH      := "res://assets/ui/dialogue_v2/nameplate.png"
const TEX_CHOICE_CURSOR_PATH  := "res://assets/ui/dialogue_choice_clean/choice_cursor.png"
const TEX_CHOICE_HILITE_PATH  := "res://assets/ui/dialogue_choice_clean/choice_highlight.png"
const TEX_CHOICE_ANCHOR_PATH  := "res://assets/ui/dialogue_choice_clean/choice_anchor.png"
const TEX_CHOICE_JEWEL_PATH   := "res://assets/ui/dialogue_choice_clean/choice_jewel.png"
const TEX_CHOICE_FILL_PATH    := "res://assets/ui/dialogue_choice_clean/choice_fill.png"
const TEX_CHOICE_CORNER_TL_PATH := "res://assets/ui/dialogue_choice_clean/choice_corner_tl.png"
const TEX_CHOICE_CORNER_TR_PATH := "res://assets/ui/dialogue_choice_clean/choice_corner_tr.png"
const TEX_CHOICE_CORNER_BL_PATH := "res://assets/ui/dialogue_choice_clean/choice_corner_bl.png"
const TEX_CHOICE_CORNER_BR_PATH := "res://assets/ui/dialogue_choice_clean/choice_corner_br.png"
const TEX_CHOICE_EDGE_TOP_PATH := "res://assets/ui/dialogue_choice_clean/choice_edge_top.png"
const TEX_CHOICE_EDGE_BOTTOM_PATH := "res://assets/ui/dialogue_choice_clean/choice_edge_bottom.png"
const TEX_CHOICE_EDGE_LEFT_PATH := "res://assets/ui/dialogue_choice_clean/choice_edge_left.png"
const TEX_CHOICE_EDGE_RIGHT_PATH := "res://assets/ui/dialogue_choice_clean/choice_edge_right.png"
const TEX_DIVIDER_PATH        := "res://assets/ui/dialogue_v2/divider_gem.png"

const BUBBLE_RADIUS    := 5
const BUBBLE_MAX_RATIO_NPC := 0.90
const BUBBLE_MAX_RATIO_PLR := 0.68
const AVATAR_SIZE      := 20.0
const AVATAR_GAP       := 4.0
const FONT_SIZE        := 8
const DIALOGUE_FONT_SIZE := 9
const NAME_FONT_SIZE     := 10
const OPTION_FONT_SIZE   := 9
const DOT_INTERVAL     := 0.38
const DIALOGUE_CHARS_PER_SECOND := 44.0
const UI_SCALE := 1.78

const COLOR_NPC_BG     := Color(0.09, 0.07, 0.20, 0.95)
const COLOR_NPC_BORDER := Color(0.78, 0.60, 0.26, 0.65)
const COLOR_PLR_BG     := Color(0.18, 0.15, 0.36, 0.95)
const COLOR_PLR_BORDER := Color(0.52, 0.62, 0.82, 0.55)
const COLOR_TEXT       := Color(0.93, 0.88, 0.75, 1.00)

# Option bubble colours
const COLOR_OPT_BG_DIM     := Color(0, 0, 0, 0)
const COLOR_OPT_BG_LIT     := Color(0.55, 0.43, 0.24, 0.50)
const COLOR_OPT_BORDER_DIM := Color(0, 0, 0, 0)
const COLOR_OPT_BORDER_LIT := Color(1.00, 0.77, 0.30, 0.80)
const COLOR_OPT_TEXT_DIM   := Color(0.84, 0.78, 0.64, 0.88)
const COLOR_OPT_TEXT_LIT := Color(0.10, 0.08, 0.03, 1.0)
const COLOR_OPT_TEXT_SEEN  := Color(0.55, 0.51, 0.44, 0.70)  # an option already explored
const COLOR_OPT_ARROW      := Color(1.00, 0.85, 0.45, 1.00)

const OPT_ROW_H := 18.0   # height of each option row (px)
const OPT_SEP   := 0.0    # separation between rows
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

# Conversation-tree (select-flow) state — when set, there is no free typing and
# every line comes from the pre-authored tree assembled by DialogueAssembler
# (world dialogue ⊕ the unlocked story stage).
var _tree_mode      : bool       = false
var _tree_nodes     : Dictionary = {}    # node id -> node dict
var _tree_options   : Array      = []    # current node's option dicts (parallel to _options)
var _tree_start_node: String     = "root"
var _tree_signature : String     = ""
var _tree_refresh_pending: bool  = false
var _quest_refresh_connected: bool = false
var _talk_notified  : bool       = false # fired notify_npc_talked once for the current tree beat
var _tree_has_quest_reveal: bool = false # quest trees must reach their reveal node
var _visited_nodes  : Dictionary = {}    # node ids the player has already reached
var _opt_rows     : Array[Node]        = []
var _opt_styles   : Array[StyleBoxFlat]= []
var _opt_cursors  : Array[CanvasItem]  = []
var _opt_highlights: Array[CanvasItem] = []
var _opt_labels   : Array[Label]       = []
var _opt_container: VBoxContainer      = null
var _choice_panel_bg: Panel            = null
var _choice_anchor: TextureRect        = null
var _choice_jewel: TextureRect         = null
var _choice_corners: Array[TextureRect] = []
var _choice_edges: Array[TextureRect] = []
var _screen_dim: ColorRect             = null
var _nameplate: TextureRect            = null
var _dialogue_label: Label             = null
var _divider: TextureRect              = null
var _leaf_waiting := false
var _dialogue_revealing := false
var _dialogue_visible_chars := 0.0
var _pending_tree_labels: Array = []
var _pending_tree_leaf := false
var _tex_dialogue_panel: Texture2D = null
var _tex_portrait_frame: Texture2D = null
var _tex_nameplate: Texture2D = null
var _tex_choice_cursor: Texture2D = null
var _tex_choice_hilite: Texture2D = null
var _tex_choice_anchor: Texture2D = null
var _tex_choice_jewel: Texture2D = null
var _tex_choice_fill: Texture2D = null
var _tex_choice_corners: Array[Texture2D] = []
var _tex_choice_edges: Array[Texture2D] = []
var _tex_divider: Texture2D = null
var _player_camera: Camera2D = null
var _staged_camera: Camera2D = null
var _conversation_player: Node2D = null
var _conversation_npc: Node2D = null
var _choice_prompt: Node2D = null

# Layout cache (set in _layout, used when showing/hiding options)
var _ib_x          : float = 0.0
var _ib_w          : float = 0.0
var _input_top     : float = 0.0   # top y of the input bar
var _scroll_y      : float = 0.0   # top y of the chat scroll
var _scroll_normal_h: float = 0.0  # scroll height when no options shown
var _choice_rect   : Rect2 = Rect2()

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
	transform = Transform2D.IDENTITY.scaled(Vector2(UI_SCALE, UI_SCALE))  # authored near 480x270
	visible = false
	_default_portrait_texture = _npc_portrait.texture
	_build_dialogue_v2_nodes()
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

func _build_dialogue_v2_nodes() -> void:
	_tex_dialogue_panel = load(TEX_DIALOGUE_PANEL_PATH) as Texture2D
	_tex_portrait_frame = load(TEX_PORTRAIT_FRAME_PATH) as Texture2D
	_tex_nameplate = load(TEX_NAMEPLATE_PATH) as Texture2D
	_tex_choice_cursor = UiKit.kit_texture("cursor_gem.png")
	if _tex_choice_cursor == null:
		_tex_choice_cursor = load(TEX_CHOICE_CURSOR_PATH) as Texture2D
	_tex_choice_hilite = UiKit.kit_texture("list_row_selected_22.png")
	if _tex_choice_hilite == null:
		_tex_choice_hilite = load(TEX_CHOICE_HILITE_PATH) as Texture2D
	_tex_choice_anchor = load(TEX_CHOICE_ANCHOR_PATH) as Texture2D
	_tex_choice_jewel = load(TEX_CHOICE_JEWEL_PATH) as Texture2D
	_tex_choice_fill = load(TEX_CHOICE_FILL_PATH) as Texture2D
	_tex_choice_corners = [
		load(TEX_CHOICE_CORNER_TL_PATH) as Texture2D,
		load(TEX_CHOICE_CORNER_TR_PATH) as Texture2D,
		load(TEX_CHOICE_CORNER_BL_PATH) as Texture2D,
		load(TEX_CHOICE_CORNER_BR_PATH) as Texture2D,
	]
	_tex_choice_edges = [
		load(TEX_CHOICE_EDGE_TOP_PATH) as Texture2D,
		load(TEX_CHOICE_EDGE_BOTTOM_PATH) as Texture2D,
		load(TEX_CHOICE_EDGE_LEFT_PATH) as Texture2D,
		load(TEX_CHOICE_EDGE_RIGHT_PATH) as Texture2D,
	]
	_tex_divider = load(TEX_DIVIDER_PATH) as Texture2D

	_screen_dim = ColorRect.new()
	_screen_dim.color = Color(0.0, 0.0, 0.0, 0.42)
	_screen_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_dim)
	move_child(_screen_dim, 0)

	_panel.texture = _tex_dialogue_panel
	_panel.modulate = Color(1, 1, 1, 0.98)
	_gem.visible = false
	_portrait_bg.visible = false
	_portrait_fg.texture = _tex_portrait_frame
	_portrait_fg.modulate = Color(1, 1, 1, 1)

	_nameplate = TextureRect.new()
	_nameplate.texture = _tex_nameplate
	_nameplate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_nameplate.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_nameplate)
	move_child(_nameplate, _npc_label.get_index())

	_dialogue_label = Label.new()
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_dialogue_label.add_theme_font_size_override("font_size", DIALOGUE_FONT_SIZE)
	_dialogue_label.add_theme_color_override("font_color", COLOR_TEXT)
	_dialogue_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.82))
	_dialogue_label.add_theme_constant_override("shadow_offset_x", 1)
	_dialogue_label.add_theme_constant_override("shadow_offset_y", 1)
	_dialogue_label.add_theme_constant_override("line_spacing", 2)
	add_child(_dialogue_label)

	_divider = TextureRect.new()
	_divider.texture = _tex_divider
	_divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_divider.modulate = Color(1, 1, 1, 0.92)
	add_child(_divider)

	_choice_panel_bg = Panel.new()
	if _tex_choice_fill != null:
		var choice_bg_style := _make_texture_style(_tex_choice_fill, 0.0, 0.0, 0.0, 0.0)
		_choice_panel_bg.add_theme_stylebox_override("panel", choice_bg_style)
	else:
		var choice_bg_style := StyleBoxFlat.new()
		choice_bg_style.bg_color = Color(0.035, 0.040, 0.085, 0.92)
		choice_bg_style.set_corner_radius_all(2)
		_choice_panel_bg.add_theme_stylebox_override("panel", choice_bg_style)
	_choice_panel_bg.visible = false
	add_child(_choice_panel_bg)

	for texture in _tex_choice_edges:
		var edge := TextureRect.new()
		edge.texture = texture
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_TILE
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.visible = false
		add_child(edge)
		_choice_edges.append(edge)

	for texture in _tex_choice_corners:
		var corner := TextureRect.new()
		corner.texture = texture
		corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		corner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.visible = false
		add_child(corner)
		_choice_corners.append(corner)

	_choice_jewel = TextureRect.new()
	_choice_jewel.texture = _tex_choice_jewel
	_choice_jewel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_choice_jewel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_choice_jewel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_jewel.visible = false
	add_child(_choice_jewel)

	_choice_anchor = TextureRect.new()
	_choice_anchor.visible = false
	_choice_anchor.texture = _tex_choice_anchor
	_choice_anchor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_choice_anchor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_choice_anchor.flip_h = false
	_choice_anchor.modulate = Color(1, 1, 1, 0.9)
	_choice_anchor.visible = false
	add_child(_choice_anchor)

	_choice_prompt = InteractionPromptScript.new()
	_choice_prompt.visible = false
	_choice_prompt.item_confirmed.connect(_on_choice_prompt_confirmed)
	add_child(_choice_prompt)

func _make_texture_style(
	texture: Texture2D,
	left: float,
	top: float,
	right: float,
	bottom: float,
	content_margin: float = 0.0
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = left
	style.texture_margin_top = top
	style.texture_margin_right = right
	style.texture_margin_bottom = bottom
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size / UI_SCALE
	if _screen_dim != null:
		_screen_dim.size = vp

	var pw := minf(vp.x - 54.0, 414.0)
	var ph := pw * (338.0 / 1412.0)
	var px := (vp.x - pw) * 0.5
	var py := vp.y - ph - 17.0

	_panel.size     = Vector2(pw, ph)
	_panel.position = Vector2(px, py)

	var pf_h := minf(ph + 22.0, 108.0)
	var pf_w := pf_h * (346.0 / 436.0)
	var pf_pos := Vector2(px + 8.0, py - 8.0)
	_portrait_fg.size     = Vector2(pf_w, pf_h)
	_portrait_fg.position = pf_pos

	var np_w := pf_w * 0.70
	var np_h := pf_h * 0.95
	_npc_portrait.size = Vector2(np_w, np_h)
	_npc_portrait.position = Vector2(
		pf_pos.x + (pf_w - np_w) * 0.5,
		pf_pos.y + (pf_h - np_h) * 0.5
	)
	_npc_portrait.clip_contents = true
	_npc_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var ib_x := px + 76.0
	var ib_w := px + pw - ib_x - 22.0
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

	_apply_nameplate_layout(px, py, pw, pf_pos, pf_w)

	if _dialogue_label != null:
		var text_x := maxf(px + 104.0, pf_pos.x + pf_w + 22.0)
		var text_y := py + 31.0
		var text_right_pad := 36.0
		_dialogue_label.position = Vector2(text_x, text_y - 6.0)
		_dialogue_label.size = Vector2(maxf(96.0, px + pw - text_x - text_right_pad), maxf(36.0, ph - 53.0))
		_fit_dialogue_label(_dialogue_label.text)

	if _divider != null:
		_divider.size = Vector2(104.0, 16.0)
		_divider.position = Vector2(px + pw * 0.5 - 52.0, py + ph - 24.0)

	var choice_w := minf(210.0, vp.x * 0.45)
	var choice_h := 108.0
	var choice_x := vp.x - choice_w - 18.0
	var choice_y := maxf(21.0, py - choice_h - 22.0)
	_choice_rect = Rect2(choice_x, choice_y, choice_w, choice_h)
	_layout_choice_frame(_choice_rect)

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

func _apply_nameplate_layout(px: float, py: float, pw: float, pf_pos: Vector2, pf_w: float) -> void:
	if _nameplate == null:
		return

	var font: Font = UiKit.title_font()
	if font == null:
		font = ThemeDB.fallback_font
	var name_text := _npc_label.text.strip_edges()
	var font_size := NAME_FONT_SIZE
	var name_left := pf_pos.x + pf_w - 14.0
	var name_max_w := maxf(98.0, minf(pw * 0.48, maxf(98.0, px + pw - name_left - 92.0)))
	var desired_w := 98.0
	if not name_text.is_empty():
		desired_w = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x + 30.0
	var name_w := clampf(desired_w, 98.0, name_max_w)
	while font_size > 7 and font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > name_w - 22.0:
		font_size -= 1

	_nameplate.size = Vector2(name_w, 23.0)
	_nameplate.position = Vector2(name_left, py - 6.0)

	var label_h := 12.0
	_npc_label.size = Vector2(maxf(24.0, name_w - 20.0), label_h)
	_npc_label.position = Vector2(name_left + 10.0, py - 2.0)
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_npc_label.clip_text = true
	_npc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_npc_label.add_theme_font_size_override("font_size", font_size)
	var title_font := UiKit.title_font()
	if title_font != null:
		var variation := FontVariation.new()
		variation.base_font = title_font
		variation.variation_opentype = {"wght": 640}
		_npc_label.add_theme_font_override("font", variation)
	_npc_label.add_theme_color_override("font_color", Color(1.00, 0.85, 0.45))
	_npc_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_npc_label.add_theme_constant_override("shadow_offset_x", 1)
	_npc_label.add_theme_constant_override("shadow_offset_y", 1)

func _fit_dialogue_label(text: String) -> void:
	if _dialogue_label == null:
		return
	var font := ThemeDB.fallback_font
	var font_size := DIALOGUE_FONT_SIZE
	var available_h := maxf(1.0, _dialogue_label.size.y)
	var available_w := maxf(1.0, _dialogue_label.size.x)
	while font_size > 7:
		var line_h := font.get_height(font_size) + 2.0
		var required_h := _estimate_wrapped_line_count(text, font, font_size, available_w) * line_h
		if required_h <= available_h:
			break
		font_size -= 1
	_dialogue_label.add_theme_font_size_override("font_size", font_size)

func _estimate_wrapped_line_count(text: String, font: Font, font_size: int, width: float) -> int:
	if text.strip_edges().is_empty():
		return 1
	var lines := 1
	var current_w := 0.0
	var space_w := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	for paragraph in text.split("\n"):
		if paragraph.is_empty():
			lines += 1
			current_w = 0.0
			continue
		for word in paragraph.split(" ", false):
			var word_w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			var extra_w := 0.0 if current_w <= 0.0 else space_w
			if current_w > 0.0 and current_w + extra_w + word_w > width:
				lines += 1
				current_w = word_w
			else:
				current_w += extra_w + word_w
		current_w = 0.0
	return maxi(1, lines)

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
	_leaf_waiting = false

	for opt in raw_options:
		_options.append(str(opt))

	for i in range(_options.size()):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, OPT_ROW_H)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var sbox := StyleBoxFlat.new()
		sbox.bg_color = Color(0, 0, 0, 0)
		sbox.border_color = Color(0.72, 0.64, 0.50, 0.20)
		sbox.border_width_bottom = 1
		sbox.content_margin_left   = 6.0
		sbox.content_margin_right  = 6.0
		sbox.content_margin_top    = 1.0
		sbox.content_margin_bottom = 1.0
		panel.add_theme_stylebox_override("panel", sbox)

		var highlight := Panel.new()
		highlight.add_theme_stylebox_override("panel", _make_texture_style(_tex_choice_hilite, 13.0, 5.0, 13.0, 5.0))
		highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
		highlight.offset_left = -3.0
		highlight.offset_top = -2.0
		highlight.offset_right = 3.0
		highlight.offset_bottom = 2.0
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(highlight)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 4.0
		row.offset_right = -4.0
		panel.add_child(row)

		var cursor := TextureRect.new()
		cursor.texture = _tex_choice_cursor
		cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cursor.custom_minimum_size = Vector2(14, 14)
		cursor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cursor)

		var lbl := Label.new()
		lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.clip_text = false
		lbl.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
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
		_opt_highlights.append(highlight)
		_opt_labels.append(lbl)

	_update_option_highlight()
	_apply_options_layout()

func _apply_options_layout() -> void:
	if _options.is_empty() or _chat_input == null:
		_opt_container.visible = false
		_set_choice_frame_visible(false)
		_chat_scroll.size.y = _scroll_normal_h
		return
	if not _tree_mode and not _chat_input.text.is_empty():
		# options hidden while typing — restore scroll but don't show container
		_opt_container.visible = false
		_set_choice_frame_visible(false)
		_chat_scroll.size.y = _scroll_normal_h
		return
	var n       := _options.size()
	var vp := get_viewport().get_visible_rect().size / UI_SCALE
	var font := ThemeDB.fallback_font
	var max_text_w := 0.0
	for i in range(_options.size()):
		max_text_w = maxf(max_text_w, font.get_string_size(
			_format_option_label(i),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			OPTION_FONT_SIZE
		).x)
	var choice_w := clampf(max_text_w + 86.0, 254.0, minf(vp.x - 28.0, 340.0))
	var label_w := maxf(choice_w - 60.0, 48.0)
	var line_h := font.get_height(OPTION_FONT_SIZE) + 3.0
	var row_heights: Array[float] = []
	var opt_h := 0.0
	for i in range(_options.size()):
		var label_text := _format_option_label(i)
		var text_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, OPTION_FONT_SIZE).x
		var lines := maxi(1, int(ceil(text_w / label_w)))
		var row_h := maxf(OPT_ROW_H, lines * line_h + 4.0)
		row_heights.append(row_h)
		opt_h += row_h
	opt_h += maxf(0.0, float(n - 1)) * OPT_SEP
	var choice_h := maxf(opt_h + 54.0, 104.0)
	var choice_x := vp.x - choice_w - 18.0
	var choice_y := maxf(20.0, _panel.position.y - choice_h - 20.0)
	_choice_rect = Rect2(choice_x, choice_y, choice_w, choice_h)
	_layout_choice_frame(_choice_rect)

	var opt_x := _choice_rect.position.x + 22.0
	var opt_y := _choice_rect.position.y + clampf((_choice_rect.size.y - opt_h) * 0.50, 27.0, 32.0)
	_opt_container.position = Vector2(opt_x, opt_y)
	_opt_container.size     = Vector2(_choice_rect.size.x - 42.0, opt_h)
	for i in range(mini(_opt_rows.size(), row_heights.size())):
		var row := _opt_rows[i] as Control
		row.custom_minimum_size.y = row_heights[i]
	_opt_container.visible  = true
	_set_choice_frame_visible(true)
	_chat_scroll.size.y     = max(opt_y - OPT_GAP - _scroll_y, 20.0)
	_retarget_staged_camera()
	_scroll_to_bottom()

func _layout_choice_frame(rect: Rect2) -> void:
	if _choice_panel_bg != null:
		_choice_panel_bg.position = rect.position + Vector2(11.0, 10.0)
		_choice_panel_bg.size = Vector2(maxf(1.0, rect.size.x - 22.0), maxf(1.0, rect.size.y - 20.0))

	if _choice_edges.size() >= 4:
		var x := rect.position.x
		var y := rect.position.y
		var w := rect.size.x
		var h := rect.size.y
		_set_edge(_choice_edges[0], Vector2(x + 18.0, y + 8.0), Vector2(maxf(1.0, w - 36.0), 7.0))
		_set_edge(_choice_edges[1], Vector2(x + 18.0, y + h - 15.0), Vector2(maxf(1.0, w - 36.0), 7.0))
		_set_edge(_choice_edges[2], Vector2(x + 8.0, y + 20.0), Vector2(7.0, maxf(1.0, h - 40.0)))
		_set_edge(_choice_edges[3], Vector2(x + w - 15.0, y + 20.0), Vector2(7.0, maxf(1.0, h - 40.0)))

	if _choice_corners.size() >= 4:
		var corner_size := Vector2(26.0, 26.0)
		_choice_corners[0].position = rect.position + Vector2(6.0, 6.0)
		_choice_corners[1].position = rect.position + Vector2(rect.size.x - corner_size.x - 6.0, 6.0)
		_choice_corners[2].position = rect.position + Vector2(6.0, rect.size.y - corner_size.y - 6.0)
		_choice_corners[3].position = rect.position + Vector2(rect.size.x - corner_size.x - 6.0, rect.size.y - corner_size.y - 6.0)
		for corner in _choice_corners:
			corner.size = corner_size

	if _choice_jewel != null:
		_choice_jewel.size = Vector2(20.0, 20.0)
		_choice_jewel.position = rect.position + Vector2(rect.size.x * 0.5 - 10.0, 3.0)

	if _choice_anchor != null:
		_choice_anchor.position = rect.position + Vector2(-13.0, rect.size.y * 0.5 - 7.0)
		_choice_anchor.size = Vector2(18.0, 14.0)

func _set_edge(edge: TextureRect, position: Vector2, size: Vector2) -> void:
	edge.position = position
	edge.size = size

func _set_choice_frame_visible(show: bool) -> void:
	if _choice_panel_bg != null:
		_choice_panel_bg.visible = show
	for edge in _choice_edges:
		edge.visible = show
	for corner in _choice_corners:
		corner.visible = show
	if _choice_jewel != null:
		_choice_jewel.visible = show
	if _choice_anchor != null:
		_choice_anchor.visible = false  # anchor arrow retired in the aaa_kit redesign

func _clear_options() -> void:
	for row in _opt_rows:
		if is_instance_valid(row):
			row.queue_free()
	_opt_rows.clear()
	_opt_styles.clear()
	_opt_cursors.clear()
	_opt_highlights.clear()
	_opt_labels.clear()
	_options.clear()
	if _opt_container != null:
		_opt_container.visible = false
	_set_choice_frame_visible(false)
	if _choice_prompt != null:
		_choice_prompt.hide_prompt()
		_choice_prompt.visible = false
	_chat_scroll.size.y = _scroll_normal_h

func _update_option_highlight() -> void:
	for i in range(_opt_labels.size()):
		var lit := (i == _selected_opt)
		var seen := _option_leads_to_seen(i)
		_opt_styles[i].bg_color = Color(0, 0, 0, 0)
		_opt_styles[i].border_color = Color(0, 0, 0, 0) if lit else Color(0.72, 0.64, 0.50, 0.20)
		_opt_cursors[i].visible = true
		_opt_cursors[i].modulate.a = 1.0 if lit else 0.0
		_opt_highlights[i].visible = lit
		_opt_labels[i].text = _format_option_label(i)
		var col := COLOR_OPT_TEXT_LIT
		if not lit:
			col = COLOR_OPT_TEXT_SEEN if seen else COLOR_OPT_TEXT_DIM
		_opt_labels[i].add_theme_color_override("font_color", col)
		_opt_labels[i].add_theme_color_override("font_shadow_color",
			Color(1, 0.92, 0.72, 0.35) if lit else Color(0, 0, 0, 0))

# True if this option leads to a content node the player already explored — used
# to grey it out + tick it so the player can see which topics they've covered.
# Checks BOTH this session's navigation and QuestManager's cross-session history,
# so a topic picked in an earlier conversation still shows as already seen here.
func _option_leads_to_seen(index: int) -> bool:
	if not _tree_mode or index >= _tree_options.size():
		return false
	var goto := str((_tree_options[index] as Dictionary).get("goto", ""))
	if goto.is_empty() or goto == "root" or goto == "__end__":
		return false
	return _visited_nodes.has(goto) or QuestManager.is_dialogue_node_visited(_npc_id, goto)

func _format_option_label(index: int) -> String:
	if index < 0 or index >= _options.size():
		return ""
	var mark := "* " if _option_leads_to_seen(index) else ""
	return "%d.  %s%s" % [index + 1, mark, _options[index]]

func _play_open_effect() -> void:
	var animated: Array[CanvasItem] = [
		_screen_dim,
		_panel,
		_portrait_fg,
		_npc_portrait,
		_nameplate,
		_npc_label,
		_dialogue_label,
		_divider,
		_choice_panel_bg,
		_choice_anchor,
		_opt_container,
	]
	for item in animated:
		if item == null or not is_instance_valid(item):
			continue
		item.modulate.a = 0.0

	var tween := create_tween()
	for item in animated:
		if item == null or not is_instance_valid(item):
			continue
		tween.parallel().tween_property(item, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel.position.y += 6.0
	_portrait_fg.position.y += 6.0
	_npc_portrait.position.y += 6.0
	_nameplate.position.y += 6.0
	_npc_label.position.y += 6.0
	_dialogue_label.position.y += 6.0
	_divider.position.y += 6.0
	tween.parallel().tween_property(_panel, "position:y", _panel.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_portrait_fg, "position:y", _portrait_fg.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_npc_portrait, "position:y", _npc_portrait.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_nameplate, "position:y", _nameplate.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_npc_label, "position:y", _npc_label.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_dialogue_label, "position:y", _dialogue_label.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_divider, "position:y", _divider.position.y - 6.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _show_choice_prompt(items: Array[String]) -> void:
	if _choice_prompt == null:
		return
	_choice_prompt.visible = true
	_choice_prompt.setup_menu("", items)
	_position_choice_prompt()
	_choice_prompt.show_prompt()

func _on_choice_prompt_confirmed(_item: String, index: int) -> void:
	if _tree_mode:
		_tree_select(index)

func _position_choice_prompt() -> void:
	if _choice_prompt == null or _options.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size / UI_SCALE
	var prompt_size: Vector2 = _choice_prompt.panel_size() if _choice_prompt.has_method("panel_size") else Vector2(170.0, 80.0)
	var pos := Vector2(vp.x - prompt_size.x - 18.0, maxf(18.0, _panel.position.y - prompt_size.y - 18.0))

	if _conversation_player != null and is_instance_valid(_conversation_player) \
			and _conversation_npc != null and is_instance_valid(_conversation_npc):
		var midpoint := (_conversation_player.global_position + _conversation_npc.global_position) * 0.5
		var screen_pos := get_viewport().get_canvas_transform() * midpoint
		pos = screen_pos / UI_SCALE + Vector2(26.0, -prompt_size.y * 0.5)

	var max_y := _panel.position.y - prompt_size.y - 12.0
	pos.x = clampf(pos.x, 12.0, maxf(12.0, vp.x - prompt_size.x - 12.0))
	pos.y = clampf(pos.y, 16.0, maxf(16.0, max_y))
	_choice_prompt.position = pos

func stage_camera_for_conversation(player: Node2D, npc: Node2D) -> void:
	if player == null or npc == null or not is_instance_valid(player) or not is_instance_valid(npc):
		return
	_conversation_player = player
	_conversation_npc = npc
	_player_camera = player.get("camera") as Camera2D
	if _player_camera == null or not is_instance_valid(_player_camera):
		return

	var camera_parent := npc.get_parent()
	if camera_parent == null:
		camera_parent = player.get_parent()
	if camera_parent == null:
		return

	_staged_camera = Camera2D.new()
	_staged_camera.position_smoothing_enabled = false
	_staged_camera.zoom = _player_camera.zoom
	_staged_camera.limit_left = _player_camera.limit_left
	_staged_camera.limit_top = _player_camera.limit_top
	_staged_camera.limit_right = _player_camera.limit_right
	_staged_camera.limit_bottom = _player_camera.limit_bottom
	_staged_camera.global_position = _player_camera.get_screen_center_position()
	camera_parent.add_child(_staged_camera)
	_staged_camera.make_current()

	_retarget_staged_camera(0.28)

func _retarget_staged_camera(duration: float = 0.22) -> void:
	if _staged_camera == null or not is_instance_valid(_staged_camera):
		return
	if _conversation_player == null or not is_instance_valid(_conversation_player) \
			or _conversation_npc == null or not is_instance_valid(_conversation_npc):
		return
	var target := _conversation_camera_target(_staged_camera)
	if _staged_camera.global_position.distance_to(target) < 1.0:
		return
	var tween := create_tween()
	tween.tween_property(_staged_camera, "global_position", target, duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)

func _conversation_camera_target(camera: Camera2D) -> Vector2:
	var midpoint := (_conversation_player.global_position + _conversation_npc.global_position) * 0.5
	var vp := get_viewport().get_visible_rect().size
	var anchor := _conversation_actor_screen_anchor()
	var offset := Vector2(
		(vp.x * 0.5 - anchor.x) / maxf(camera.zoom.x, 0.001),
		(vp.y * 0.5 - anchor.y) / maxf(camera.zoom.y, 0.001)
	)
	return _clamp_camera_target(midpoint + offset, camera)

func _conversation_actor_screen_anchor() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var dialogue_top := _panel.position.y * UI_SCALE
	var top_margin := 28.0
	var stage_bottom := maxf(top_margin + 120.0, dialogue_top - 34.0)
	var anchor_y := lerpf(top_margin, stage_bottom, 0.54)

	if _choice_panel_bg != null and _choice_panel_bg.visible and _choice_rect.size.x > 0.0:
		var choice_left := _choice_rect.position.x * UI_SCALE
		var open_right := clampf(choice_left - 36.0, vp.x * 0.28, vp.x - 36.0)
		var anchor_x := clampf(open_right * 0.56, 120.0, vp.x * 0.44)
		return Vector2(anchor_x, anchor_y)

	return Vector2(vp.x * 0.5, anchor_y)

func _clamp_camera_target(target: Vector2, camera: Camera2D) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var half := Vector2(
		vp.x * 0.5 / maxf(camera.zoom.x, 0.001),
		vp.y * 0.5 / maxf(camera.zoom.y, 0.001)
	)
	var left_limit := float(camera.limit_left)
	var right_limit := float(camera.limit_right)
	var top_limit := float(camera.limit_top)
	var bottom_limit := float(camera.limit_bottom)
	if right_limit > left_limit:
		target.x = clampf(target.x, left_limit + half.x, right_limit - half.x)
	if bottom_limit > top_limit:
		target.y = clampf(target.y, top_limit + half.y, bottom_limit - half.y)
	return target

func _restore_staged_camera() -> void:
	if _player_camera != null and is_instance_valid(_player_camera):
		_player_camera.make_current()
	if _staged_camera != null and is_instance_valid(_staged_camera):
		_staged_camera.queue_free()
	_staged_camera = null
	_player_camera = null
	_conversation_player = null
	_conversation_npc = null

# ── conversation tree (select flow) ─────────────────────────────────────────────

func open_tree(npc_name: String, npc_data: Dictionary, tree: Dictionary) -> void:
	_tree_mode = true
	_leaf_waiting = false
	_talk_notified = false
	_tree_refresh_pending = false
	_visited_nodes = {}
	_npc_name  = npc_name
	_npc_data  = npc_data
	_npc_id    = str(npc_data.get("id", ""))
	_npc_label.text = npc_name
	_layout()
	_prepare_portraits()
	_set_portrait_for_emotion("neutral")

	# No free typing in select flow — hide the input bar entirely.
	_input_bar.visible = false
	_chat_input.visible = false
	_chat_input.editable = false
	_send_btn.visible = false
	_chat_scroll.visible = false
	if _dialogue_label != null:
		_dialogue_label.visible = true

	_clear_options()
	for child in _messages.get_children():
		child.queue_free()

	_load_tree(tree)
	_connect_quest_refresh()

	GameManager.ui_blocking_input = true
	visible = true
	_play_open_effect()
	_enter_tree_node(_tree_start_node)

func _load_tree(tree: Dictionary) -> void:
	_tree_start_node = str(tree.get("start_node", "root"))
	if _tree_start_node.is_empty():
		_tree_start_node = "root"
	_tree_signature = _signature_for_tree(tree)
	_tree_has_quest_reveal = false
	_tree_nodes = {}
	for node in (tree.get("nodes", []) as Array):
		if node is Dictionary:
			var nid := str((node as Dictionary).get("id", ""))
			if not nid.is_empty():
				_tree_nodes[nid] = node
				if str((node as Dictionary).get("reveals", "")) == "quest":
					_tree_has_quest_reveal = true

func _signature_for_tree(tree: Dictionary) -> String:
	return JSON.stringify(tree)

func _connect_quest_refresh() -> void:
	if _quest_refresh_connected:
		return
	QuestManager.quests_changed.connect(_on_quests_changed_during_tree)
	_quest_refresh_connected = true

func _disconnect_quest_refresh() -> void:
	if not _quest_refresh_connected:
		return
	if QuestManager.quests_changed.is_connected(_on_quests_changed_during_tree):
		QuestManager.quests_changed.disconnect(_on_quests_changed_during_tree)
	_quest_refresh_connected = false

func _on_quests_changed_during_tree() -> void:
	if _tree_mode and visible:
		_tree_refresh_pending = true

func _refresh_tree_if_due_at(node_id: String) -> String:
	if not _tree_refresh_pending or node_id != _tree_start_node:
		return node_id
	_tree_refresh_pending = false
	var next_tree: Dictionary = DialogueAssembler.build_active_tree(_npc_data)
	if next_tree.is_empty():
		return node_id
	var next_signature := _signature_for_tree(next_tree)
	if next_signature == _tree_signature:
		return node_id
	_load_tree(next_tree)
	_talk_notified = false
	return _tree_start_node

func _set_dialogue_text(text: String, queued_labels: Array = [], queued_leaf: bool = false, instant: bool = false) -> void:
	if _dialogue_label == null:
		return
	_dialogue_label.text = text
	_fit_dialogue_label(text)
	_pending_tree_labels = queued_labels.duplicate()
	_pending_tree_leaf = queued_leaf
	_leaf_waiting = false
	if instant:
		# Going back to a node already seen: no typewriter, no waiting — show the
		# line fully and the options/menu immediately.
		_dialogue_label.visible_characters = -1
		_dialogue_visible_chars = 0.0
		_dialogue_revealing = false
		_finish_dialogue_reveal()
		return
	_dialogue_label.visible_characters = 0
	_dialogue_visible_chars = 0.0
	_dialogue_revealing = not text.is_empty()
	if not _dialogue_revealing:
		_finish_dialogue_reveal()

func _finish_dialogue_reveal() -> void:
	_dialogue_revealing = false
	if _dialogue_label != null:
		_dialogue_label.visible_characters = -1
	if not _pending_tree_labels.is_empty():
		var labels := _pending_tree_labels.duplicate()
		_pending_tree_labels.clear()
		_pending_tree_leaf = false
		_show_options(labels)
	elif _pending_tree_leaf:
		_pending_tree_leaf = false
		_leaf_waiting = true

func _enter_tree_node(node_id: String) -> void:
	node_id = _refresh_tree_if_due_at(node_id)
	var node: Dictionary = _tree_nodes.get(node_id, {}) as Dictionary
	if node.is_empty():
		close()
		return
	# "Seen before" survives across conversation sessions (QuestManager, per NPC),
	# not just navigation within the currently-open one.
	var revisit: bool = _visited_nodes.has(node_id) or QuestManager.is_dialogue_node_visited(_npc_id, node_id)
	_visited_nodes[node_id] = true
	QuestManager.mark_dialogue_node_visited(_npc_id, node_id)
	_apply_dialogue_effects(node.get("effects"))  # node effects fire on arrival
	# Phase 3: a "talk" objective completes the moment the player reaches a node
	# that reveals quest information (the quest beat) — not only at conversation end.
	if not _talk_notified and str(node.get("reveals", "")) == "quest":
		_talk_notified = true
		QuestManager.notify_npc_talked(_npc_id)
	_set_portrait_for_emotion(str(node.get("emotion", "neutral")))
	var line := str(node.get("npc_line", "")).strip_edges()
	# Talking earns XP for the whole party — a story beat is worth more than a piece
	# of world lore, and each line pays out only the first time it is ever reached.
	_award_talk_xp(node_id, node, line)
	if not revisit and str(node.get("reveals", "")) == "hint" and node.get("hint") is Dictionary:
		QuestManager.reveal_hint(_npc_name, node.get("hint") as Dictionary, line, _npc_portrait.texture)

	_tree_options = []
	var labels: Array = []
	for opt in (node.get("options", []) as Array):
		if opt is Dictionary:
			_tree_options.append(opt)
			labels.append(str((opt as Dictionary).get("player_text", "...")))
	_clear_options()
	_set_dialogue_text(line, labels, labels.is_empty(), revisit)

# Award talk-XP for reaching a dialogue node. Quest beats (reveals == "quest") pay
# the larger reward; world-layer lore nodes (w:* in the merged tree, or any node the
# author tagged reveals == "world"/"lore"/etc.) pay the smaller one. GameManager
# dedupes per (npc, node) so re-reading a line never farms XP.
func _award_talk_xp(node_id: String, node: Dictionary, line: String) -> void:
	if _npc_id.is_empty():
		return
	var reveals := str(node.get("reveals", ""))
	var category := ""
	if reveals == "quest":
		category = "quest"
	elif reveals in ["world", "lore", "personal", "scene"] \
			or (node_id.begins_with("w:") and node_id != "w:root"):
		if not line.is_empty():
			category = "world"
	if category.is_empty():
		return
	var result: Dictionary = GameManager.award_talk_xp(_npc_id, node_id, category)
	if bool(result.get("awarded", false)):
		_show_talk_xp_popup(category, int(result.get("amount", 0)), result.get("recipients", []) as Array)

# A small floating "+XP" cue over the conversation. Authored in the ChatBox's
# ~480x270 space (the layer carries a UI_SCALE transform).
func _show_talk_xp_popup(category: String, amount: int, recipients: Array) -> void:
	var label := Label.new()
	var tag := "Nhiệm vụ" if category == "quest" else "Thế giới"
	var who := "" if recipients.size() <= 1 else "  (cả đội)"
	label.text = "+%d KN · %s%s" % [amount, tag, who]
	label.add_theme_font_size_override("font_size", 11)
	var col := Color(1.0, 0.85, 0.45) if category == "quest" else Color(0.55, 0.85, 1.0)
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(170.0, 54.0)
	label.size = Vector2(140.0, 16.0)
	label.z_index = 50
	add_child(label)
	label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(label, "position:y", 40.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tween.tween_callback(label.queue_free)

func _tree_select(index: int) -> void:
	if index < 0 or index >= _tree_options.size():
		return
	var opt: Dictionary = _tree_options[index] as Dictionary
	_apply_dialogue_effects(opt.get("effects"))  # option effects fire on choice
	var goto := str(opt.get("goto", "__end__"))
	_clear_options()
	if goto == "__end__":
		# Trees with an authored quest beat must actually reach that node. The
		# end-of-conversation fallback is only for ordinary trees with no quest beat.
		if not _talk_notified and not _tree_has_quest_reveal:
			_talk_notified = true
			QuestManager.notify_npc_talked(_npc_id)
		close()  # "Tạm biệt" leaves immediately
		return
	_enter_tree_node(goto)

# Apply quest/inventory effects authored on a node or option.
func _apply_dialogue_effects(effects: Variant) -> void:
	if not (effects is Array):
		return
	for effect in (effects as Array):
		if not (effect is Dictionary):
			continue
		var eff: Dictionary = effect as Dictionary
		var etype := str(eff.get("type", ""))
		var quest_id := str(eff.get("quest_id", ""))
		match etype:
			"quest_choice":
				QuestManager.resolve_quest_choice(quest_id, str(eff.get("option", "a")))
			"actor_state", "set_actor_state", "set_actor_states":
				_apply_actor_state_effect(eff)
			"give_item":
				_apply_item_effect(eff, true)
			"take_item":
				_apply_item_effect(eff, false)

func _apply_actor_state_effect(eff: Dictionary) -> void:
	var outcome := eff.duplicate(true)
	if not outcome.has("actor_state") \
			and not outcome.has("actor_states") \
			and not outcome.has("set_actor_states"):
		outcome = {"actor_state": eff}
	NarrativeState.apply_actor_state_changes(outcome)

func _apply_item_effect(eff: Dictionary, give: bool) -> void:
	var quest_id := str(eff.get("quest_id", ""))
	# Default to the keepsake REWARD item — giving the collect item via dialogue
	# would hand the player the thing they were sent to gather. "quest_item"
	# (the collect/deliver item) is still honoured if an effect asks for it.
	var item_ref := str(eff.get("item_ref", "reward_item"))
	var count := int(eff.get("count", 1))
	var item_id := item_ref
	if not quest_id.is_empty():
		if item_ref == "reward_item":
			item_id = str(InventoryManager.reward_item_for(quest_id).get("id", ""))
		elif item_ref == "quest_item":
			item_id = str(InventoryManager.quest_item_for(quest_id).get("id", ""))
	if item_id.is_empty():
		return
	if give:
		InventoryManager.add_item(item_id, count)
	else:
		if not InventoryManager.remove_item(item_id, count):
			var item_name := str(InventoryManager.item_def(item_id).get("name", item_id))
			InventoryManager._push_toast("Cần: %s" % item_name)

func _confirm_option() -> void:
	if _options.is_empty() or _selected_opt >= _options.size():
		return
	if _tree_mode:
		_tree_select(_selected_opt)
		return
	var opt := _options[_selected_opt]
	_clear_options()
	_send_to_npc(opt)

# ── scroll ──────────────────────────────────────────────────────────────────────

func _scroll_to_bottom() -> void:
	_scroll_countdown = 6

# ── events ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _tree_mode and _dialogue_revealing and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				# Fast-forward the current line's typewriter instead of waiting it out.
				_finish_dialogue_reveal()
				get_viewport().set_input_as_handled()
				return
	if _tree_mode and _leaf_waiting and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				close()
				get_viewport().set_input_as_handled()
				return
	if _options.is_empty() or not _opt_container.visible:
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
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# In select flow there is no text field to submit, so confirm here.
			if _tree_mode:
				_confirm_option()
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
	if visible and not _tree_mode and _chat_input.visible and not _chat_input.has_focus():
		_chat_input.grab_focus()

	if _tree_mode and _choice_prompt != null and _choice_prompt.visible and not _options.is_empty():
		_position_choice_prompt()

	if _dialogue_revealing and _dialogue_label != null:
		_dialogue_visible_chars += delta * DIALOGUE_CHARS_PER_SECOND
		var total_chars := _dialogue_label.text.length()
		_dialogue_label.visible_characters = mini(total_chars, int(floor(_dialogue_visible_chars)))
		if _dialogue_label.visible_characters >= total_chars:
			_finish_dialogue_reveal()

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
	_tree_mode = false
	_leaf_waiting = false
	_npc_name = npc_name
	_npc_data = npc_data
	_npc_id   = npc_id
	_npc_label.text        = npc_name
	_layout()
	_prepare_portraits()
	_set_portrait_for_emotion("neutral")
	_chat_scroll.visible = true
	_input_bar.visible = true
	_chat_input.visible = true
	_send_btn.visible = true
	if _dialogue_label != null:
		_dialogue_label.text = ""
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
	_disconnect_quest_refresh()
	NPCConversationManager.cancel_all()
	_loading_label     = null
	_stream_label      = null
	_stream_is_waiting = false
	_dialogue_revealing = false
	_pending_tree_labels.clear()
	_pending_tree_leaf = false
	_leaf_waiting = false
	_restore_staged_camera()
	GameManager.ui_blocking_input = false
	visible = false
	# NPCController instantiates a fresh ChatBox per interaction, so free this one.
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var inside_dialogue := _panel.get_global_rect().has_point(event.position)
		var inside_choices := _choice_panel_bg != null \
			and _choice_panel_bg.visible \
			and _choice_panel_bg.get_global_rect().has_point(event.position)
		if not inside_dialogue and not inside_choices:
			close()
			get_viewport().set_input_as_handled()
