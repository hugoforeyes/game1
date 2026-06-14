extends Control
## Chapter intro — slideshow mode, production presentation.
## Full-bleed illustrated slides with crossfade + Ken Burns drift, cinematic
## title card typography, generated ornate UI frame assets, typewriter
## narration, progress diamonds, ambient embers, and an input hint.
## Reads ChapterFlow.pending_intro; when finished, hands control back to
## ChapterFlow.enter_current_zone().

const TYPE_SPEED := 34.0
const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TITLE := Color(0.96, 0.88, 0.50, 1.0)
const COLOR_GOLD_LINE := Color(0.98, 0.74, 0.28, 0.78)
const COLOR_GOLD_DIM := Color(0.77, 0.58, 0.31, 0.55)

const TEX_TITLE_PLAQUE := "res://assets/ui/chapter_intro/title_plaque.png"
const TEX_NARRATION_PANEL := "res://assets/ui/chapter_intro/narration_panel.png"
const TEX_PROGRESS_ACTIVE := "res://assets/ui/chapter_intro/progress_active.png"
const TEX_PROGRESS_INACTIVE := "res://assets/ui/chapter_intro/progress_inactive.png"
const TEX_HINT_BADGE := "res://assets/ui/chapter_intro/hint_badge.png"

const DESIGN_SIZE := Vector2(480, 270)
const IMAGE_LAYER_SCALE := 0.5
const IMAGE_LAYER_SIZE := DESIGN_SIZE / IMAGE_LAYER_SCALE
const KEN_BURNS_DURATION := 34.0
const KEN_BURNS_OVERSCAN := 1.06
const KEN_BURNS_DRIFT_STRENGTH := 0.60
const TEXT_PAGE_TARGET_CHARS := 170
const TEXT_MAX_LINES := 3
const TEXT_FONT_MAX := 9
const TEXT_FONT_MIN := 7
const TEXT_LINE_SPACING := 2

const CHAPTER_WORDS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var slides: Array = []
var slide_index: int = 0
var _typing: bool = false
var _type_target: String = ""
var _type_progress: float = 0.0
var _text_pages: Array[String] = []
var _text_page_index: int = 0
var _awaiting_continue: bool = false
var _finishing: bool = false
var _ken_active: bool = false
var _ken_elapsed: float = 0.0
var _ken_start_pos: Vector2 = Vector2.ZERO
var _ken_end_pos: Vector2 = Vector2.ZERO

var _image_front: TextureRect
var _image_back: TextureRect
var _image_holder: Control
var _title_group: Control
var _title_plaque: TextureRect
var _eyebrow_label: Label
var _title_label: Label
var _title_line_left: ColorRect
var _title_line_right: ColorRect
var _title_center_ornament: TextureRect
var _text_panel: Control
var _text_frame: TextureRect
var _text_label: Label
var _continue_marker: Label
var _hint_panel: Control
var _progress_root: Control
var _progress_pips: Array[TextureRect] = []
var _loading_label: Label
var _fade: ColorRect

func _ready() -> void:
	GameManager.ui_blocking_input = true
	_build_ui()
	slides = ChapterFlow.pending_intro.get("slides", []) as Array
	if slides.is_empty():
		_finish()
		return
	ChapterFlow.loading_status.connect(_on_loading_status)
	_build_progress_pips()
	_play_slide(0)

func _build_ui() -> void:
	# Authored in 480x270 design space, scaled 2x to the 960x540 viewport.
	anchors_preset = Control.PRESET_TOP_LEFT
	position = Vector2.ZERO
	size = Vector2(480, 270)
	scale = Vector2(2, 2)
	var viewport_size := DESIGN_SIZE

	var background := ColorRect.new()
	background.color = Color(0.01, 0.01, 0.03, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Two stacked image rects allow true crossfades between slides.
	_image_holder = Control.new()
	_image_holder.position = Vector2.ZERO
	_image_holder.size = IMAGE_LAYER_SIZE
	_image_holder.scale = Vector2(IMAGE_LAYER_SCALE, IMAGE_LAYER_SCALE)
	_image_holder.clip_contents = true
	add_child(_image_holder)

	_image_back = _make_image_rect()
	_image_holder.add_child(_image_back)
	_image_front = _make_image_rect()
	_image_holder.add_child(_image_front)

	# Soft bottom gradient so panel text always reads over bright art.
	var gradient := TextureRect.new()
	gradient.texture = _make_gradient_texture()
	gradient.position = Vector2(0, 150)
	gradient.size = Vector2(480, 120)
	gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(gradient)

	add_child(UiKit.make_ember_particles(viewport_size))

	_title_group = Control.new()
	_title_group.position = Vector2(0, 16)
	_title_group.size = Vector2(480, 94)
	add_child(_title_group)

	_title_plaque = _make_ui_texture(TEX_TITLE_PLAQUE, Rect2(169, 0, 142, 25))
	_title_group.add_child(_title_plaque)

	_eyebrow_label = UiKit.make_label("", 8, Color(0.85, 0.75, 0.55, 0.9))
	_eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_eyebrow_label.add_theme_constant_override("shadow_offset_y", 1)
	_eyebrow_label.position = Vector2(169, 0)
	_eyebrow_label.size = Vector2(142, 25)
	_title_group.add_child(_eyebrow_label)

	_title_label = UiKit.make_label("", 19, COLOR_TITLE)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.88))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(10, 28)
	_title_label.size = Vector2(460, 38)
	_title_group.add_child(_title_label)

	_title_line_left = _make_line(Rect2(50, 48, 80, 1), COLOR_GOLD_LINE)
	_title_line_left.visible = false
	_title_group.add_child(_title_line_left)
	_title_line_right = _make_line(Rect2(350, 48, 80, 1), COLOR_GOLD_LINE)
	_title_line_right.visible = false
	_title_group.add_child(_title_line_right)
	_title_center_ornament = _make_ui_texture(TEX_PROGRESS_INACTIVE, Rect2(234, 65, 12, 12))
	_title_center_ornament.modulate = Color(1.0, 0.83, 0.42, 0.9)
	_title_group.add_child(_title_center_ornament)
	_title_group.move_child(_title_label, _title_group.get_child_count() - 1)

	_text_panel = Control.new()
	_text_panel.position = Vector2(76, 176)
	_text_panel.size = Vector2(328, 72)
	add_child(_text_panel)

	_text_frame = _make_ui_texture(TEX_NARRATION_PANEL, Rect2(0, 0, 328, 72))
	_text_panel.add_child(_text_frame)

	_text_label = UiKit.make_label("", 9, COLOR_TEXT)
	_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	_text_label.add_theme_constant_override("line_spacing", TEXT_LINE_SPACING)
	_text_label.position = Vector2(45, 15)
	_text_label.size = Vector2(238, 45)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.clip_text = true
	_text_panel.add_child(_text_label)

	_continue_marker = UiKit.make_label("›", 12, COLOR_TITLE)
	_continue_marker.position = Vector2(288, 46)
	_continue_marker.size = Vector2(16, 14)
	_continue_marker.visible = false
	_text_panel.add_child(_continue_marker)

	_hint_panel = Control.new()
	_hint_panel.position = Vector2(394, 238)
	_hint_panel.size = Vector2(70, 31)
	var hint_badge := _make_ui_texture(TEX_HINT_BADGE, Rect2(0, 0, 70, 31))
	_hint_panel.add_child(hint_badge)
	var hint := UiKit.make_label("ENTER ›", 7, COLOR_TITLE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.position = Vector2.ZERO
	hint.size = Vector2(70, 31)
	_hint_panel.add_child(hint)
	add_child(_hint_panel)

	_progress_root = Control.new()
	_progress_root.position = Vector2(240, 255)
	add_child(_progress_root)

	_loading_label = UiKit.make_label("", 9, COLOR_TEXT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.position = Vector2(20, 130)
	_loading_label.size = Vector2(440, 20)
	_loading_label.visible = false
	add_child(_loading_label)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)

func _make_ui_texture(path: String, rect: Rect2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if ResourceLoader.exists(path):
		texture_rect.texture = load(path)
	return texture_rect

func _make_line(rect: Rect2, color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.position = rect.position
	line.size = rect.size
	line.color = color
	return line

func _make_image_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.modulate.a = 0.0
	rect.size = IMAGE_LAYER_SIZE
	return rect

func _make_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0.01, 0.01, 0.04, 0.85)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	return texture

func _build_progress_pips() -> void:
	var total: int = slides.size()
	var spacing := 24.0
	for index in range(total):
		var pip := _make_ui_texture(TEX_PROGRESS_INACTIVE, Rect2(0, 0, 14, 14))
		var center_x := (float(index) - float(total - 1) * 0.5) * spacing
		pip.position = Vector2(center_x - pip.size.x * 0.5, -pip.size.y * 0.5)
		_progress_root.add_child(pip)
		_progress_pips.append(pip)
		if index < total - 1:
			var connector := _make_line(Rect2(center_x + 9.0, -0.5, spacing - 18.0, 1.0), COLOR_GOLD_DIM)
			_progress_root.add_child(connector)
	_refresh_progress_pips()

func _refresh_progress_pips() -> void:
	var total := _progress_pips.size()
	var spacing := 24.0
	for index in range(_progress_pips.size()):
		var active := index == slide_index
		var size := Vector2(15, 15) if active else Vector2(12, 12)
		var center_x := (float(index) - float(total - 1) * 0.5) * spacing
		_progress_pips[index].texture = load(TEX_PROGRESS_ACTIVE if active else TEX_PROGRESS_INACTIVE)
		_progress_pips[index].size = size
		_progress_pips[index].position = Vector2(center_x - size.x * 0.5, -size.y * 0.5)

func _chapter_eyebrow() -> String:
	var chapter_number: int = int(ChapterFlow.pending_intro.get("chapter", 0))
	if chapter_number <= 0:
		return ""
	var numeral: String = CHAPTER_WORDS[chapter_number] if chapter_number < CHAPTER_WORDS.size() else str(chapter_number)
	return "—  CHAPTER %s  —" % numeral

func _play_slide(index: int) -> void:
	slide_index = index
	_refresh_progress_pips()
	var slide: Dictionary = slides[index] as Dictionary
	var first: bool = index == 0

	if first:
		var fade_in := create_tween()
		fade_in.tween_property(_fade, "color:a", 1.0, 0.0)
		await fade_in.finished

	_continue_marker.visible = false
	_title_group.modulate.a = 0.0
	_eyebrow_label.text = _chapter_eyebrow() if first else ""
	_title_label.text = str(slide.get("title", ""))
	_fit_title_label()
	_title_plaque.visible = not _eyebrow_label.text.is_empty()
	_title_line_left.visible = false
	_title_line_right.visible = false
	_title_center_ornament.visible = not _title_label.text.is_empty()
	_text_label.text = ""

	# Download next image into the back rect, then crossfade front<->back.
	var image_url: Variant = slide.get("image_url")
	var new_texture: Texture2D = null
	if image_url != null and not str(image_url).is_empty():
		new_texture = await ChapterFlow.download_image_texture(str(image_url))
		new_texture = _make_smooth_slide_texture(new_texture)

	_image_back.texture = new_texture
	_image_back.modulate.a = 0.0
	_configure_ken_burns_rect(_image_back, index, 0.0)
	var crossfade := create_tween()
	if new_texture != null:
		crossfade.tween_property(_image_back, "modulate:a", 1.0, 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		crossfade.parallel().tween_property(_image_front, "modulate:a", 0.0, 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		crossfade.tween_property(_image_front, "modulate:a", 0.0, 0.6)
	if first:
		crossfade.parallel().tween_property(_fade, "color:a", 0.0, 0.9)
	var swap: TextureRect = _image_front
	_image_front = _image_back
	_image_back = swap
	_start_ken_burns(index)

	var titles := create_tween()
	if not _eyebrow_label.text.is_empty() or not _title_label.text.is_empty():
		titles.tween_property(_title_group, "modulate:a", 1.0, 1.1)

	# Text panel rises in with the typewriter.
	_text_panel.position.y = 187
	_text_panel.modulate.a = 0.0
	var panel_in := create_tween()
	panel_in.tween_property(_text_panel, "position:y", 176.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	panel_in.parallel().tween_property(_text_panel, "modulate:a", 1.0, 0.4)

	_text_pages = _paginate_text(str(slide.get("text", "")))
	_begin_text_page(0)

func _fit_title_label() -> void:
	var text := _title_label.text
	var size := 25
	if text.length() > 44:
		size = 18
	elif text.length() > 36:
		size = 19
	elif text.length() > 28:
		size = 23
	_title_label.add_theme_font_size_override("font_size", size)

func _fit_text_label(text: String) -> void:
	var width := maxf(1.0, _text_label.size.x)
	var height := maxf(1.0, _text_label.size.y)
	var font: Font = _text_label.get_theme_font("font")
	for font_size in range(TEXT_FONT_MAX, TEXT_FONT_MIN - 1, -1):
		var line_count := _estimate_wrapped_line_count(text, font, font_size, width)
		var estimated_height := _estimate_text_height(line_count, font, font_size)
		if line_count <= TEXT_MAX_LINES and estimated_height <= height:
			_text_label.add_theme_font_size_override("font_size", font_size)
			return
	_text_label.add_theme_font_size_override("font_size", TEXT_FONT_MIN)

func _estimate_wrapped_line_count(text: String, font: Font, font_size: int, width: float) -> int:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return 1
	if font == null:
		var chars_per_line := maxf(8.0, width / (float(font_size) * 0.58))
		return int(ceil(float(cleaned.length()) / chars_per_line))
	var lines := 1
	var current := ""
	for word in cleaned.split(" ", false):
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= width:
			current = candidate
		else:
			if not current.is_empty():
				lines += 1
			current = word
	return lines

func _estimate_text_height(line_count: int, font: Font, font_size: int) -> float:
	var line_height := float(font_size + 3)
	if font != null:
		line_height = font.get_height(font_size)
	return float(maxi(line_count, 1)) * line_height + float(maxi(line_count - 1, 0)) * TEXT_LINE_SPACING

func _text_fits_page(text: String) -> bool:
	var font: Font = _text_label.get_theme_font("font")
	var line_count := _estimate_wrapped_line_count(text, font, TEXT_FONT_MIN, maxf(1.0, _text_label.size.x))
	var estimated_height := _estimate_text_height(line_count, font, TEXT_FONT_MIN)
	return line_count <= TEXT_MAX_LINES and estimated_height <= maxf(1.0, _text_label.size.y)

func _paginate_text(text: String) -> Array[String]:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return [""]
	var pages: Array[String] = []
	var current := ""
	var words := cleaned.split(" ", false)
	for word in words:
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if (candidate.length() > TEXT_PAGE_TARGET_CHARS or not _text_fits_page(candidate)) and not current.is_empty():
			pages.append(current.strip_edges())
			current = word
		else:
			current = candidate
	if not current.strip_edges().is_empty():
		pages.append(current.strip_edges())
	return pages

func _begin_text_page(page_index: int) -> void:
	_text_page_index = clampi(page_index, 0, maxi(0, _text_pages.size() - 1))
	_type_target = _text_pages[_text_page_index] if _text_pages.size() > 0 else ""
	_fit_text_label(_type_target)
	_text_label.text = _type_target
	_text_label.visible_characters = 0
	_type_progress = 0.0
	_typing = true
	_awaiting_continue = false
	_continue_marker.visible = false

func _make_smooth_slide_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return texture
	if image.has_mipmaps() or image.generate_mipmaps() == OK:
		return ImageTexture.create_from_image(image)
	return texture

func _ken_burns_points(index: int) -> Array[Vector2]:
	var overscan_size := IMAGE_LAYER_SIZE * KEN_BURNS_OVERSCAN
	var margin := overscan_size - IMAGE_LAYER_SIZE
	var center := -margin * 0.5
	var drift := margin * KEN_BURNS_DRIFT_STRENGTH * 0.5
	var directions := [
		Vector2(1.0, 0.25),
		Vector2(-0.35, 1.0),
		Vector2(-1.0, -0.25),
		Vector2(0.35, -1.0),
	]
	var direction: Vector2 = directions[index % directions.size()]
	return [center - drift * direction, center + drift * direction]

func _configure_ken_burns_rect(rect: TextureRect, index: int, t: float) -> void:
	rect.size = IMAGE_LAYER_SIZE * KEN_BURNS_OVERSCAN
	var points := _ken_burns_points(index)
	rect.position = points[0].lerp(points[1], _smootherstep(clampf(t, 0.0, 1.0)))

func _start_ken_burns(index: int) -> void:
	_ken_active = true
	_ken_elapsed = 0.0
	_image_front.size = IMAGE_LAYER_SIZE * KEN_BURNS_OVERSCAN
	var points := _ken_burns_points(index)
	_ken_start_pos = points[0]
	_ken_end_pos = points[1]
	_image_front.position = _ken_start_pos

func _smootherstep(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

func _process(delta: float) -> void:
	if _ken_active:
		_ken_elapsed = minf(_ken_elapsed + delta, KEN_BURNS_DURATION)
		var t := _ken_elapsed / KEN_BURNS_DURATION
		var eased := _smootherstep(t)
		_image_front.position = _ken_start_pos.lerp(_ken_end_pos, eased)

	if _typing:
		_type_progress += TYPE_SPEED * delta
		var visible_chars: int = mini(int(_type_progress), _type_target.length())
		_text_label.visible_characters = visible_chars
		if visible_chars >= _type_target.length():
			_typing = false
			_awaiting_continue = true
			_text_label.visible_characters = -1
			_continue_marker.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_accept"):
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_typing = false
		_text_label.visible_characters = -1
		_awaiting_continue = true
		_continue_marker.visible = true
		return
	if _awaiting_continue:
		_awaiting_continue = false
		if _text_page_index + 1 < _text_pages.size():
			_begin_text_page(_text_page_index + 1)
			return
		if slide_index + 1 < slides.size():
			_play_slide(slide_index + 1)
		else:
			_finish()

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_typing = false
	_continue_marker.visible = false
	_loading_label.visible = true
	_loading_label.text = "..."
	var fade := create_tween()
	fade.tween_property(_fade, "color:a", 1.0, 0.5)
	await fade.finished
	_title_label.visible = false
	_eyebrow_label.visible = false
	_title_group.visible = false
	_text_panel.visible = false
	_hint_panel.visible = false
	_progress_root.visible = false
	_image_front.visible = false
	_image_back.visible = false
	_fade.color.a = 0.85
	_loading_label.visible = true
	GameManager.ui_blocking_input = false
	var err: Error = await ChapterFlow.enter_current_zone()
	if err != OK:
		_loading_label.text = "Could not load the scene. Returning to menu..."
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file(ChapterFlow.START_SCENE_PATH)

func _on_loading_status(message: String) -> void:
	_loading_label.text = message
