extends CanvasLayer

var _npc_name : String = ""
var _npc_data : Dictionary = {}

@onready var _panel:        TextureRect = $Panel
@onready var _gem:          TextureRect = $Gem
@onready var _portrait_bg:  TextureRect = $PortraitBg
@onready var _portrait_fg:  TextureRect = $PortraitFg
@onready var _npc_portrait: TextureRect = $NpcPortrait
@onready var _input_bar:    TextureRect = $InputBar
@onready var _chat_input:   LineEdit    = $ChatInput
@onready var _send_btn:     Button      = $SendButton
@onready var _npc_label:    Label       = $NpcLabel

func _ready() -> void:
	layer   = 64
	visible = false
	_layout()
	_send_btn.pressed.connect(_on_send)
	_chat_input.text_submitted.connect(_on_send)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var pw := vp.x - 20.0
	var ph := pw * (394.0 / 1199.0)
	var px := 10.0
	var py := vp.y - ph - 8.0

	# Main panel
	_panel.size     = Vector2(pw, ph)
	_panel.position = Vector2(px, py)

	# Gem (top-right corner)
	var gem_h := ph * 0.70
	var gem_w := gem_h * (46.0 / 252.0)
	_gem.size     = Vector2(gem_w, gem_h)
	_gem.position = Vector2(px + pw - gem_w - 5.0, py + 8.0)

	# Portrait frame (left side, slightly taller than panel)
	var pf_h   := ph * 1.08
	var pf_w   := pf_h * (317.0 / 443.0)
	var pf_pos := Vector2(px, py - (pf_h - ph) * 0.5 - 10.0)
	_portrait_bg.size     = Vector2(pf_w, pf_h)
	_portrait_bg.position = pf_pos
	_portrait_fg.size     = Vector2(pf_w, pf_h)
	_portrait_fg.position = pf_pos

	# NPC portrait (behind frame fg)
	var np_w := pf_w * 0.82
	var np_h := np_w * (821.0 / 517.0)
	_npc_portrait.size     = Vector2(np_w, np_h)
	_npc_portrait.position = Vector2(pf_pos.x + (pf_w - np_w) * 0.5,
									 pf_pos.y + pf_h * 0.05 - 10.0)

	# Input bar: to the right of portrait, at the bottom of the panel
	# Image aspect ratio: 710×83
	var ib_x := px + pf_w + 24.0
	var ib_w := px + pw - ib_x - 60.0
	var ib_h := ib_w * (83.0 / 710.0)
	var ib_y := py + ph - ib_h - 6.0
	_input_bar.size     = Vector2(ib_w, ib_h)
	_input_bar.position = Vector2(ib_x, ib_y - 5.0)

	# LineEdit: inside bar, left portion (leaf button takes rightmost ~13%)
	var leaf_w   := ib_h   # leaf button is roughly square
	var pad_h    := ib_h * 0.10
	var line_h   := 12.0   # fixed pixel height matching font size 8
	_chat_input.size     = Vector2(ib_w - leaf_w - pad_h * 2.0 - 18.0, line_h)
	_chat_input.position = Vector2(ib_x + pad_h + 10.0, ib_y + (ib_h - line_h) * 0.5 - 15.0)
	_style_input()

	# Send button: over the leaf circle on the right
	_send_btn.size     = Vector2(leaf_w, ib_h)
	_send_btn.position = Vector2(ib_x + ib_w - leaf_w, ib_y)

	# NPC name label: bottom strip of the portrait frame
	var label_h := 10.0
	_npc_label.size     = Vector2(pf_w, label_h)
	_npc_label.position = Vector2(pf_pos.x, pf_pos.y + pf_h - label_h - 12.0)
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_label.add_theme_font_size_override("font_size", 12)
	_npc_label.add_theme_color_override("font_color", Color(1.00, 0.85, 0.45))

func _style_input() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color       = Color(0, 0, 0, 0)
	style.border_width_left   = 0
	style.border_width_right  = 0
	style.border_width_top    = 0
	style.border_width_bottom = 0
	_chat_input.add_theme_stylebox_override("normal", style)
	_chat_input.add_theme_stylebox_override("focus",  style)
	_chat_input.add_theme_color_override("font_color",             Color(0.93, 0.88, 0.75))
	_chat_input.add_theme_color_override("font_placeholder_color", Color(0.55, 0.50, 0.40))
	_chat_input.add_theme_font_size_override("font_size", 8)

func _on_send(_text: String = "") -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	print("[Chat] Player → %s: %s" % [_npc_name, msg])
	_chat_input.text = ""
	_chat_input.grab_focus()

func open(npc_name: String, npc_data: Dictionary) -> void:
	_npc_name = npc_name
	_npc_data = npc_data
	_npc_label.text = npc_name
	visible   = true
	_chat_input.grab_focus()

func close() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
