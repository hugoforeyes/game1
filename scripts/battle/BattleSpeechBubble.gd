extends Control
## Fixed-template enemy combat bark.
##
## The four generated shout-out textures are never stretched at runtime. Text is
## measured first, then routed to the smallest native template
## that can contain it. Every right-pointing template has a pixel-identical mirrored
## partner, so the integrated diagonal pointer can face either side of an enemy.

signal playback_finished(cancelled: bool)

enum PointerSide { LEFT, RIGHT }

const COMPACT_RIGHT := preload("res://assets/ui/battle_speech_v4/shout_compact_right.png")
const COMPACT_LEFT := preload("res://assets/ui/battle_speech_v4/shout_compact_left.png")
const SHORT_RIGHT := preload("res://assets/ui/battle_speech_v4/shout_short_right.png")
const SHORT_LEFT := preload("res://assets/ui/battle_speech_v4/shout_short_left.png")
const MEDIUM_RIGHT := preload("res://assets/ui/battle_speech_v4/shout_medium_right.png")
const MEDIUM_LEFT := preload("res://assets/ui/battle_speech_v4/shout_medium_left.png")
const LONG_RIGHT := preload("res://assets/ui/battle_speech_v4/shout_long_right.png")
const LONG_LEFT := preload("res://assets/ui/battle_speech_v4/shout_long_left.png")

const BASE_FONT_SIZE := 15
const MIN_FONT_SIZE := 12
const FONT_WEIGHT := 540
const TEXT_COLOR := Color("ead8ad")
const TEXT_OUTLINE := Color("170f08")
const TEXT_SHADOW := Color(0.0, 0.0, 0.0, 0.88)
const VISUAL_GUTTER := 3.0

var _frame: TextureRect
var _label: Label
var _template_id := "compact"
var _pointer_side := PointerSide.RIGHT
var _font_size := BASE_FONT_SIZE
var _center := Vector2.ZERO
var _playback_tween: Tween
var _playback_active := false


func setup(text: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

	var display_text := text.strip_edges()
	var choice := _choose_template(display_text)
	_template_id = str(choice["id"])
	_font_size = int(choice["font_size"])
	var texture := _texture_for(_template_id, _pointer_side)
	size = texture.get_size()
	_center = size * 0.5
	pivot_offset = _center

	_frame = TextureRect.new()
	_frame.texture = texture
	_frame.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2.ZERO
	_frame.size = size # exact native dimensions; no runtime texture scaling
	add_child(_frame)

	_label = Label.new()
	_label.text = display_text
	var font := _bubble_font()
	if font != null:
		_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", _font_size)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	_label.add_theme_color_override("font_shadow_color", TEXT_SHADOW)
	_label.add_theme_constant_override("outline_size", 1)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_constant_override("line_spacing", 1)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_label.clip_text = false
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_text_rect()
	add_child(_label)


## Swap only between pre-rendered mirrored assets. No negative scale or texture
## transform is used, so the outline and type remain pixel-sharp in both directions.
func set_pointer_side(side: int) -> void:
	_pointer_side = PointerSide.LEFT if side == PointerSide.LEFT else PointerSide.RIGHT
	if _frame != null:
		_frame.texture = _texture_for(_template_id, _pointer_side)
		_apply_text_rect()


func pointer_tip_local() -> Vector2:
	var tip := _right_pointer_tip(_template_id)
	if _pointer_side == PointerSide.LEFT:
		tip.x = size.x - 1.0 - tip.x
	return tip


func template_id() -> String:
	return _template_id


func pointer_side() -> int:
	return _pointer_side


# Compatibility with BattleScene's previous free-aim pointer contract. New battle
# placement uses set_pointer_side() + pointer_tip_local() for exact pixel anchoring.
func point_tail_at(local_point: Vector2) -> void:
	set_pointer_side(PointerSide.LEFT if local_point.x < _center.x else PointerSide.RIGHT)


func center_local() -> Vector2:
	return _center


func oval_a() -> float:
	return size.x * 0.5


func oval_b() -> float:
	return size.y * 0.5


func oval_top_local() -> float:
	return 0.0


func oval_bottom_local() -> float:
	return size.y


func visual_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, size).grow(VISUAL_GUTTER)


func play() -> void:
	# No scale tween: each template remains at its authored native pixel size from
	# first frame to last. One cancellable tween owns the complete lifetime so battle
	# teardown cannot leave timers or suspended coroutine states behind.
	if _playback_active:
		cancel_playback()
	_playback_active = true
	modulate.a = 0.0
	position.y += 4.0
	var resting_position := position - Vector2(0.0, 4.0)
	var character_count := _label.text.length()
	_label.visible_ratio = 0.0
	var type_duration := clampf(float(character_count) * 0.019, 0.16, 1.45)
	var hold_duration := clampf(float(character_count) * 0.043 + 0.78, 1.25, 4.5)

	_playback_tween = create_tween()
	_playback_tween.tween_property(self, "modulate:a", 1.0, 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_playback_tween.parallel().tween_property(self, "position", resting_position, 0.19) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_playback_tween.parallel().tween_property(_label, "visible_ratio", 1.0, type_duration) \
		.set_delay(0.04)
	_playback_tween.tween_interval(hold_duration)
	_playback_tween.tween_property(self, "modulate:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_playback_tween.parallel().tween_property(self, "position:y", resting_position.y - 5.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_playback_tween.finished.connect(_complete_playback.bind(false), CONNECT_ONE_SHOT)


func cancel_playback() -> void:
	if not _playback_active:
		return
	if _playback_tween != null and _playback_tween.is_valid():
		_playback_tween.kill()
	_complete_playback(true)


func _complete_playback(cancelled: bool) -> void:
	if not _playback_active:
		return
	_playback_active = false
	_playback_tween = null
	playback_finished.emit(cancelled)


func _exit_tree() -> void:
	cancel_playback()


func _choose_template(text: String) -> Dictionary:
	var font := _bubble_font()
	var measure_font: Font = font if font != null else ThemeDB.fallback_font
	var natural_width := measure_font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_FONT_SIZE).x
	var compact_rect := _right_text_rect("compact")
	var compact_measure := _measure_wrapped(measure_font, text, compact_rect.size.x, BASE_FONT_SIZE)
	# Compact intentionally absorbs both ultra-short and very-short one-line barks.
	# The existing short template remains useful once type needs more breathing room.
	if natural_width <= compact_rect.size.x * 0.96 and compact_measure.y <= compact_rect.size.y:
		return {"id": "compact", "font_size": BASE_FONT_SIZE}

	var short_rect := _right_text_rect("short")
	var short_measure := _measure_wrapped(measure_font, text, short_rect.size.x, BASE_FONT_SIZE)
	# Capacity thresholds intentionally reserve breathing room around the type. A
	# template is not chosen merely because many tightly packed lines technically fit.
	if natural_width <= short_rect.size.x * 1.15 and short_measure.y <= short_rect.size.y:
		return {"id": "short", "font_size": BASE_FONT_SIZE}

	var medium_rect := _right_text_rect("medium")
	var medium_measure := _measure_wrapped(measure_font, text, medium_rect.size.x, BASE_FONT_SIZE)
	if natural_width <= medium_rect.size.x * 2.0 and medium_measure.y <= medium_rect.size.y:
		return {"id": "medium", "font_size": BASE_FONT_SIZE}

	# The texture still stays native-size. Only exceptionally long authored barks
	# step the type down, preserving every word instead of clipping or ellipsizing.
	var long_rect := _right_text_rect("long")
	for candidate in range(BASE_FONT_SIZE - 1, MIN_FONT_SIZE - 1, -1):
		var measured := _measure_wrapped(measure_font, text, long_rect.size.x, candidate)
		if measured.y <= long_rect.size.y:
			return {"id": "long", "font_size": candidate}
	return {"id": "long", "font_size": MIN_FONT_SIZE}


func _measure_wrapped(font: Font, text: String, width: float, font_size: int) -> Vector2:
	return font.get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		width,
		font_size,
		-1,
		TextServer.BREAK_MANDATORY \
			| TextServer.BREAK_WORD_BOUND \
			| TextServer.BREAK_GRAPHEME_BOUND,
	)


func _apply_text_rect() -> void:
	if _label == null:
		return
	var rect := _right_text_rect(_template_id)
	if _pointer_side == PointerSide.LEFT:
		rect.position.x = size.x - rect.end.x
	_label.position = rect.position
	_label.size = rect.size


func _texture_for(id: String, side: int) -> Texture2D:
	match id:
		"compact":
			return COMPACT_LEFT if side == PointerSide.LEFT else COMPACT_RIGHT
		"medium":
			return MEDIUM_LEFT if side == PointerSide.LEFT else MEDIUM_RIGHT
		"long":
			return LONG_LEFT if side == PointerSide.LEFT else LONG_RIGHT
		_:
			return SHORT_LEFT if side == PointerSide.LEFT else SHORT_RIGHT


func _right_text_rect(id: String) -> Rect2:
	match id:
		"compact":
			return Rect2(24.0, 20.0, 102.0, 40.0)
		"medium":
			return Rect2(40.0, 24.0, 230.0, 66.0)
		"long":
			return Rect2(46.0, 24.0, 322.0, 66.0)
		_:
			return Rect2(34.0, 21.0, 170.0, 52.0)


func _right_pointer_tip(id: String) -> Vector2:
	match id:
		"compact":
			return Vector2(136.0, 113.0)
		"medium":
			return Vector2(235.0, 143.0)
		"long":
			return Vector2(318.0, 142.0)
		_:
			return Vector2(184.0, 114.0)


func _bubble_font() -> Font:
	var base := UiKit.title_font()
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {"wght": FONT_WEIGHT}
	variation.spacing_glyph = 0
	return variation
