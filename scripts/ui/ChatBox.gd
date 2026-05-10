extends CanvasLayer

# Game viewport is 320×180. The chatbox sits in the bottom portion.
const PANEL_W  := 300.0
const PANEL_H  := 98.0   # keeps 1199:394 aspect ratio at this width
const MARGIN_X := 10.0
const MARGIN_B := 8.0    # gap from bottom edge

var _npc_name  : String = ""
var _npc_data  : Dictionary = {}

@onready var _panel:         TextureRect = $Panel
@onready var _gem:           TextureRect = $Gem
@onready var _portrait_bg:   TextureRect = $PortraitBg
@onready var _portrait_fg:   TextureRect = $PortraitFg
@onready var _portrait_clip: Control     = $PortraitClip
@onready var _npc_portrait:  TextureRect = $PortraitClip/NpcPortrait

func _ready() -> void:
	layer   = 64
	visible = false

	var vp := get_viewport().get_visible_rect().size
	var pw := vp.x - 20.0
	var ph := pw * (394.0 / 1199.0)
	var px := 10.0
	var py := vp.y - ph - 8.0
	_panel.size     = Vector2(pw, ph)
	_panel.position = Vector2(px, py)

	# Gem: scale proportionally to panel height
	var gem_h := ph * 0.70
	var gem_w := gem_h * (46.0 / 252.0)
	_gem.size     = Vector2(gem_w, gem_h)
	# Hook starts exactly at the top-right corner of the panel
	_gem.position = Vector2(px + pw - gem_w - 5.0, py + 8.0)

	# Portrait frame: aspect ratio 317×443, slightly taller than panel, left-aligned
	# Layer order in scene: PortraitBg → [NPC sprite] → PortraitFg
	var pf_h := ph * 1.08
	var pf_w := pf_h * (317.0 / 443.0)
	var pf_pos := Vector2(px, py - (pf_h - ph) * 0.5 - 10.0)
	_portrait_bg.size     = Vector2(pf_w, pf_h)
	_portrait_bg.position = pf_pos
	_portrait_fg.size     = Vector2(pf_w, pf_h)
	_portrait_fg.position = pf_pos

	# Portrait clip area: upper portion of frame only (before compass at ~72% height)
	var clip_h := pf_h * 0.72
	_portrait_clip.position = pf_pos
	_portrait_clip.size     = Vector2(pf_w, clip_h)

	# NPC portrait fills the clip area, scaled by width, centred horizontally
	var np_w := pf_w * 0.82
	var np_h := np_w * (821.0 / 517.0)
	_npc_portrait.size     = Vector2(np_w, np_h)
	_npc_portrait.position = Vector2((pf_w - np_w) * 0.5, pf_h * 0.05)

func open(npc_name: String, npc_data: Dictionary) -> void:
	_npc_name = npc_name
	_npc_data = npc_data
	visible   = true

func close() -> void:
	visible = false

func _draw() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
