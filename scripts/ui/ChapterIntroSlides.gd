extends Control
## Chapter intro — slideshow mode, production presentation.
## Full-bleed illustrated slides with crossfade + Ken Burns drift, chapter
## eyebrow + ornament banner on the opening slide, ornate text panel with
## typewriter narration, progress diamonds, ambient embers, and an input hint.
## Reads ChapterFlow.pending_intro; when finished, hands control back to
## ChapterFlow.enter_current_zone().

const TYPE_SPEED := 34.0
const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TITLE := Color(0.96, 0.88, 0.50, 1.0)

const CHAPTER_WORDS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var slides: Array = []
var slide_index: int = 0
var _typing: bool = false
var _type_target: String = ""
var _type_progress: float = 0.0
var _awaiting_continue: bool = false
var _finishing: bool = false
var _ken_tween: Tween = null

var _image_front: TextureRect
var _image_back: TextureRect
var _image_holder: Control
var _eyebrow_label: Label
var _title_label: Label
var _banner: TextureRect
var _text_panel: Panel
var _text_label: Label
var _continue_marker: Label
var _hint_panel: Panel
var _progress_root: Control
var _progress_pips: Array[ColorRect] = []
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
	var viewport_size := Vector2(480, 270)

	var background := ColorRect.new()
	background.color = Color(0.01, 0.01, 0.03, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Two stacked image rects allow true crossfades between slides.
	_image_holder = Control.new()
	_image_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
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

	_eyebrow_label = UiKit.make_label("", 8, Color(0.85, 0.75, 0.55, 0.9))
	_eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow_label.position = Vector2(20, 30)
	_eyebrow_label.size = Vector2(440, 14)
	add_child(_eyebrow_label)

	_title_label = UiKit.make_label("", 19, COLOR_TITLE)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(20, 48)
	_title_label.size = Vector2(440, 56)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title_label)

	_banner = UiKit.make_banner_rect(170.0)
	if _banner != null:
		_banner.position = Vector2(155, 104)
		_banner.modulate.a = 0.0
		add_child(_banner)

	_text_panel = UiKit.make_panel(Rect2(28, 184, 424, 62))
	add_child(_text_panel)

	_text_label = UiKit.make_label("", 9, COLOR_TEXT)
	_text_label.position = Vector2(14, 9)
	_text_label.size = Vector2(392, 46)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_panel.add_child(_text_label)

	_continue_marker = UiKit.make_label("v", 9, COLOR_TITLE)
	_continue_marker.position = Vector2(404, 44)
	_continue_marker.visible = false
	_text_panel.add_child(_continue_marker)

	_hint_panel = UiKit.make_panel(Rect2(388, 252, 64, 16))
	var hint := UiKit.make_label("ENTER >", 6, UiKit.COLOR_TEXT_DIM)
	hint.position = Vector2(10, 3)
	_hint_panel.add_child(hint)
	add_child(_hint_panel)

	_progress_root = Control.new()
	_progress_root.position = Vector2(240, 258)
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

func _make_image_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.modulate.a = 0.0
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
	for index in range(total):
		var pip := ColorRect.new()
		pip.size = Vector2(6, 6)
		pip.position = Vector2(float(index - total / 2.0) * 14.0, 0)
		pip.rotation_degrees = 45.0
		pip.pivot_offset = Vector2(3, 3)
		_progress_root.add_child(pip)
		_progress_pips.append(pip)
	_refresh_progress_pips()

func _refresh_progress_pips() -> void:
	for index in range(_progress_pips.size()):
		_progress_pips[index].color = COLOR_TITLE if index == slide_index else Color(0.4, 0.36, 0.30, 0.7)

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
	_eyebrow_label.text = _chapter_eyebrow() if first else ""
	_eyebrow_label.modulate.a = 0.0
	_title_label.text = str(slide.get("title", ""))
	_title_label.modulate.a = 0.0
	if _banner != null:
		_banner.modulate.a = 0.0
	_text_label.text = ""

	# Download next image into the back rect, then crossfade front<->back.
	var image_url: Variant = slide.get("image_url")
	var new_texture: Texture2D = null
	if image_url != null and not str(image_url).is_empty():
		new_texture = await ChapterFlow.download_image_texture(str(image_url))

	_image_back.texture = new_texture
	_image_back.modulate.a = 0.0
	var crossfade := create_tween()
	if new_texture != null:
		crossfade.tween_property(_image_back, "modulate:a", 1.0, 0.8)
		crossfade.parallel().tween_property(_image_front, "modulate:a", 0.0, 0.8)
	else:
		crossfade.tween_property(_image_front, "modulate:a", 0.0, 0.6)
	if first:
		crossfade.parallel().tween_property(_fade, "color:a", 0.0, 0.9)
	var swap: TextureRect = _image_front
	_image_front = _image_back
	_image_back = swap
	_start_ken_burns(index)

	var titles := create_tween()
	if not _eyebrow_label.text.is_empty():
		titles.tween_property(_eyebrow_label, "modulate:a", 1.0, 0.9)
	if not _title_label.text.is_empty():
		titles.parallel().tween_property(_title_label, "modulate:a", 1.0, 1.3)
		if _banner != null and first:
			titles.parallel().tween_property(_banner, "modulate:a", 1.0, 1.3)

	# Text panel rises in with the typewriter.
	_text_panel.position.y = 192
	_text_panel.modulate.a = 0.0
	var panel_in := create_tween()
	panel_in.tween_property(_text_panel, "position:y", 184.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	panel_in.parallel().tween_property(_text_panel, "modulate:a", 1.0, 0.4)

	_type_target = str(slide.get("text", ""))
	_type_progress = 0.0
	_typing = true

func _start_ken_burns(index: int) -> void:
	if _ken_tween != null:
		_ken_tween.kill()
	var viewport_size: Vector2 = Vector2(480, 270)
	var overscan: float = 1.12
	_image_front.size = viewport_size * overscan
	var drift: Vector2 = Vector2(-viewport_size.x * (overscan - 1.0), 0.0) if index % 2 == 0 else Vector2(0.0, -viewport_size.y * (overscan - 1.0))
	_image_front.position = Vector2.ZERO if index % 2 == 0 else drift * -1.0
	_ken_tween = create_tween()
	_ken_tween.tween_property(_image_front, "position", _image_front.position + drift, 14.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	if _typing:
		_type_progress += TYPE_SPEED * delta
		var visible_chars: int = mini(int(_type_progress), _type_target.length())
		_text_label.text = _type_target.substr(0, visible_chars)
		if visible_chars >= _type_target.length():
			_typing = false
			_awaiting_continue = true
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
		_text_label.text = _type_target
		_awaiting_continue = true
		_continue_marker.visible = true
		return
	if _awaiting_continue:
		_awaiting_continue = false
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
	if _banner != null:
		_banner.visible = false
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
