extends CanvasLayer

const DOT_INTERVAL := 0.38
const FONT_SIZE    := 9
const PAD          := Vector2(18.0, 8.0)
const BG_COLOR     := Color(0.07, 0.05, 0.18, 0.94)
const BORDER_COLOR := Color(0.78, 0.60, 0.26, 0.70)
const TEXT_COLOR   := Color(0.93, 0.88, 0.75, 1.00)

var _dot_count: int   = 1
var _timer:     float = 0.0
var _panel:     Panel
var _label:     Label

func _ready() -> void:
	layer = 100

	_panel = Panel.new()
	add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(_label)

	_rebuild_layout()
	_update_label()

func _rebuild_layout() -> void:
	var vp  := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	var lbl_h := font.get_height(FONT_SIZE)
	var pw := 40.0 + PAD.x * 2.0
	var ph := lbl_h + PAD.y * 2.0

	var style := StyleBoxFlat.new()
	style.bg_color     = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left   = PAD.x
	style.content_margin_right  = PAD.x
	style.content_margin_top    = PAD.y
	style.content_margin_bottom = PAD.y
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size     = Vector2(pw, ph)
	_panel.position = Vector2((vp.x - pw) * 0.5, vp.y * 0.42)

	_label.size     = Vector2(pw - PAD.x * 2.0, lbl_h)
	_label.position = Vector2(PAD.x, PAD.y)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DOT_INTERVAL:
		_timer = 0.0
		_dot_count = (_dot_count % 3) + 1
		_update_label()

func _update_label() -> void:
	_label.text = ".".repeat(_dot_count)
