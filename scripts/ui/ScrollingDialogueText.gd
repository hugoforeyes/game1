extends RichTextLabel
## Shared long-passage dialogue text (ChatBox + CutscenePlayer): the font NEVER
## shrinks — when a line outgrows its panel the text SCROLLS instead, with the
## intro slides' mechanics: the view auto-follows the typewriter reveal, and
## wheel/drag lets the reader scroll back to re-read (following pauses until
## they return to the bottom). The caller owns the typewriter itself by
## driving `visible_characters`, exactly as it did with a plain Label.

const FOLLOW_LAG := 9.0

var _area := Rect2()
var _center_when_short := false
var _auto_follow := true
var _dragging := false
var _drag_last_y := 0.0


func _init() -> void:
	bbcode_enabled = false
	fit_content = false
	scroll_active = true
	scroll_following = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_STOP  # wheel/drag re-reading
	gui_input.connect(_on_gui_input)


func _ready() -> void:
	# The panel art is the visual frame — the scrollbar itself stays invisible.
	get_v_scroll_bar().modulate.a = 0.0


## Assign the passage and reset reveal + scroll state.
func set_passage(passage: String) -> void:
	text = passage
	visible_characters = 0
	get_v_scroll_bar().value = 0.0
	_auto_follow = true
	_dragging = false
	_refresh_layout_deferred()


## The full rect available for text. Short content centers vertically inside it
## (RichTextLabel has no vertical_alignment); long content fills it and scrolls.
func set_area(area: Rect2, center_when_short: bool) -> void:
	_area = area
	_center_when_short = center_when_short
	position = area.position
	size = area.size
	_refresh_layout_deferred()


## Typewriter finished (naturally or fast-forwarded): show everything and land
## on the LAST lines — the reader can wheel/drag back up to re-read.
func reveal_finished() -> void:
	visible_characters = -1
	var vbar := get_v_scroll_bar()
	vbar.value = vbar.max_value


func _refresh_layout_deferred() -> void:
	call_deferred("_refresh_layout")


func _line_height() -> float:
	var font := get_theme_font("normal_font")
	var font_size := get_theme_font_size("normal_font_size")
	if font == null:
		return 14.0
	return font.get_height(font_size) + float(get_theme_constant("line_separation"))


func _refresh_layout() -> void:
	if _area.size.x <= 0.0:
		return
	var content := float(get_content_height())
	if _center_when_short and content > 0.0 and content < _area.size.y - 1.0:
		position = Vector2(_area.position.x, _area.position.y + floorf((_area.size.y - content) * 0.5))
		size = Vector2(_area.size.x, minf(content + 2.0, _area.size.y))
	else:
		# Overflowing: quantize the view height to WHOLE lines so scrolling
		# never shows a half-cut line at the top or bottom edge.
		var line_h := _line_height()
		var view_h := maxf(line_h, floorf(_area.size.y / line_h) * line_h)
		position = Vector2(_area.position.x, _area.position.y + floorf((_area.size.y - view_h) * 0.5))
		size = Vector2(_area.size.x, view_h)


func _process(delta: float) -> void:
	var vbar := get_v_scroll_bar()
	if text.is_empty() or vbar.max_value <= vbar.page + 1.0:
		return
	# Re-arm following once the reader scrolls back to the bottom.
	if not _auto_follow and vbar.value >= vbar.max_value - vbar.page - 1.0:
		_auto_follow = true
	if _dragging or not _auto_follow or visible_characters < 0:
		return
	var cursor := maxi(0, visible_characters - 1)
	var line := get_character_line(cursor)
	var line_h := _line_height()
	# Snap the follow target to whole lines — paired with the line-quantized
	# view height, both scroll edges always show complete lines.
	var target := clampf(get_line_offset(line) + line_h - size.y, 0.0, vbar.max_value)
	target = roundf(target / line_h) * line_h
	vbar.value = lerpf(vbar.value, target, clampf(delta * FOLLOW_LAG, 0.0, 1.0))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_auto_follow = false
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_auto_follow = false
				_drag_last_y = button.position.y
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		get_v_scroll_bar().value -= motion.position.y - _drag_last_y
		_drag_last_y = motion.position.y
		accept_event()
