class_name SettingsPanel
extends Control
## AAA main-menu Settings component. All art is text-free; labels are rendered by
## Godot so English and Vietnamese remain crisp and correctly aligned.

signal close_requested

const PANEL_SIZE := Vector2(860.0, 476.0)
const SLIDER_TRACK_WIDTH := 310.0
const SLIDER_KNOB_LEFT := 286.0
const SLIDER_KNOB_TEXTURE := preload("res://assets/ui/settings_v1/slider_knob.png")

@onready var panel_root: Control = $PanelRoot
@onready var panel_visual: Control = $PanelRoot/PanelVisual
@onready var title_label: Label = $PanelRoot/PanelVisual/Title
@onready var music_row: Control = $PanelRoot/PanelVisual/MusicRow
@onready var music_label: Label = $PanelRoot/PanelVisual/MusicRow/Label
@onready var music_fill_clip: Control = $PanelRoot/PanelVisual/MusicRow/SliderFillClip
@onready var music_knob: TextureRect = $PanelRoot/PanelVisual/MusicRow/SliderKnob
@onready var music_slider: HSlider = $PanelRoot/PanelVisual/MusicRow/Slider
@onready var music_value: Label = $PanelRoot/PanelVisual/MusicRow/Value
@onready var fullscreen_row: Control = $PanelRoot/PanelVisual/FullscreenRow
@onready var fullscreen_label: Label = $PanelRoot/PanelVisual/FullscreenRow/Label
@onready var windowed_button: Button = $PanelRoot/PanelVisual/FullscreenRow/Selector/WindowedButton
@onready var fullscreen_button: Button = $PanelRoot/PanelVisual/FullscreenRow/Selector/FullscreenButton
@onready var language_row: Control = $PanelRoot/PanelVisual/LanguageRow
@onready var language_label: Label = $PanelRoot/PanelVisual/LanguageRow/Label
@onready var english_button: Button = $PanelRoot/PanelVisual/LanguageRow/Selector/EnglishButton
@onready var vietnamese_button: Button = $PanelRoot/PanelVisual/LanguageRow/Selector/VietnameseButton
@onready var back_frame: TextureRect = $PanelRoot/PanelVisual/BackFrame
@onready var back_button: Button = $PanelRoot/PanelVisual/BackButton
@onready var back_text: Label = $PanelRoot/PanelVisual/BackText

var _active_row := 0


func _ready() -> void:
	# Settings follows Journey/Inventory: native viewport geometry on an identity
	# CanvasLayer, with linear sampling limited to its OpenAiExtension artwork.
	panel_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_add_resolution_safe_frame()
	_apply_control_styles()
	_connect_controls()
	resized.connect(_layout_panel)
	SettingsManager.music_volume_changed.connect(_on_music_volume_changed)
	SettingsManager.fullscreen_changed.connect(_on_fullscreen_changed)
	SettingsManager.language_changed.connect(_on_language_changed)
	_layout_panel()
	_refresh_all()


func open_panel() -> void:
	SettingsManager.refresh_fullscreen_state()
	_refresh_all()
	show()
	_layout_panel()
	_set_active_row(0)
	music_slider.grab_focus()
	panel_visual.modulate.a = 0.0
	panel_visual.scale = Vector2(0.965, 0.965)
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(panel_visual, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_visual, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func close_panel() -> void:
	if not visible:
		return
	hide()
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func _layout_panel() -> void:
	var available := size
	var fit := minf(
		1.0,
		minf(
			maxf((available.x - 32.0) / PANEL_SIZE.x, 0.1),
			maxf((available.y - 24.0) / PANEL_SIZE.y, 0.1),
		)
	)
	panel_root.size = PANEL_SIZE
	panel_root.scale = Vector2(fit, fit)
	panel_root.position = ((available - PANEL_SIZE * fit) * 0.5).round()


func _add_resolution_safe_frame() -> void:
	# UiKit slices only the straight center/edges; corner filigree keeps a fixed
	# optical size and is never stretched with the panel.
	var frame := UiKit.make_ornate_frame(PANEL_SIZE, "panel_frame.png", 0.16, 68.0, true)
	frame.name = "ResolutionSafeFrame"
	panel_visual.add_child(frame)
	panel_visual.move_child(frame, 0)


func _apply_control_styles() -> void:
	# The invisible native-size grabber makes HSlider's usable mouse travel match
	# the custom 310px track exactly: 348px control width - 38px knob width. The
	# visible texture is 2x-density (76x80), so use a native-size atlas region for
	# input geometry; the HSlider itself is transparent.
	var hit_knob := AtlasTexture.new()
	hit_knob.atlas = SLIDER_KNOB_TEXTURE
	hit_knob.region = Rect2(0.0, 0.0, 38.0, 40.0)
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		music_slider.add_theme_icon_override(icon_name, hit_knob)
	for button in [windowed_button, fullscreen_button, english_button, vietnamese_button]:
		button.add_theme_stylebox_override("normal", _segment_style(false, false))
		button.add_theme_stylebox_override("hover", _segment_style(false, true))
		button.add_theme_stylebox_override("pressed", _segment_style(true, true))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", Color(0.72, 0.66, 0.54, 0.88))
		button.add_theme_color_override("font_hover_color", Color(0.98, 0.88, 0.60, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(1.0, 0.91, 0.64, 1.0))
	back_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	back_button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	back_button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	back_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _segment_style(selected: bool, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.035, 0.16, 0.42, 0.94)
		if selected
		else Color(0.008, 0.020, 0.055, 0.34)
	)
	if highlighted:
		style.bg_color = style.bg_color.lightened(0.10)
	style.set_corner_radius_all(4)
	return style


func _connect_controls() -> void:
	music_slider.value_changed.connect(_on_music_slider_changed)
	windowed_button.pressed.connect(func() -> void: SettingsManager.set_fullscreen(false))
	fullscreen_button.pressed.connect(func() -> void: SettingsManager.set_fullscreen(true))
	english_button.pressed.connect(func() -> void: SettingsManager.set_language("en"))
	vietnamese_button.pressed.connect(func() -> void: SettingsManager.set_language("vi"))
	back_button.pressed.connect(close_panel)

	music_slider.focus_entered.connect(func() -> void: _set_active_row(0))
	windowed_button.focus_entered.connect(func() -> void: _set_active_row(1))
	fullscreen_button.focus_entered.connect(func() -> void: _set_active_row(1))
	english_button.focus_entered.connect(func() -> void: _set_active_row(2))
	vietnamese_button.focus_entered.connect(func() -> void: _set_active_row(2))
	back_button.focus_entered.connect(func() -> void: _set_active_row(3))
	music_row.mouse_entered.connect(func() -> void: _set_active_row(0))
	fullscreen_row.mouse_entered.connect(func() -> void: _set_active_row(1))
	language_row.mouse_entered.connect(func() -> void: _set_active_row(2))
	back_button.mouse_entered.connect(func() -> void: _set_active_row(3))

	windowed_button.focus_neighbor_right = windowed_button.get_path_to(fullscreen_button)
	fullscreen_button.focus_neighbor_left = fullscreen_button.get_path_to(windowed_button)
	english_button.focus_neighbor_right = english_button.get_path_to(vietnamese_button)
	vietnamese_button.focus_neighbor_left = vietnamese_button.get_path_to(english_button)
	english_button.focus_neighbor_bottom = english_button.get_path_to(back_button)
	vietnamese_button.focus_neighbor_bottom = vietnamese_button.get_path_to(back_button)
	_update_focus_neighbors()


func _update_focus_neighbors() -> void:
	var display_target := fullscreen_button if SettingsManager.fullscreen_enabled else windowed_button
	var language_target := vietnamese_button if SettingsManager.language == "vi" else english_button
	music_slider.focus_neighbor_bottom = music_slider.get_path_to(display_target)
	windowed_button.focus_neighbor_top = windowed_button.get_path_to(music_slider)
	fullscreen_button.focus_neighbor_top = fullscreen_button.get_path_to(music_slider)
	windowed_button.focus_neighbor_bottom = windowed_button.get_path_to(language_target)
	fullscreen_button.focus_neighbor_bottom = fullscreen_button.get_path_to(language_target)
	english_button.focus_neighbor_top = english_button.get_path_to(display_target)
	vietnamese_button.focus_neighbor_top = vietnamese_button.get_path_to(display_target)
	back_button.focus_neighbor_top = back_button.get_path_to(language_target)


func _refresh_all() -> void:
	_refresh_copy()
	_on_music_volume_changed(SettingsManager.music_volume_percent)
	_on_fullscreen_changed(SettingsManager.fullscreen_enabled)
	_refresh_language_state()


func _refresh_copy() -> void:
	title_label.text = SettingsManager.text("settings.title")
	music_label.text = SettingsManager.text("settings.music")
	fullscreen_label.text = SettingsManager.text("settings.fullscreen")
	windowed_button.text = SettingsManager.text("settings.windowed")
	fullscreen_button.text = SettingsManager.text("settings.fullscreen")
	language_label.text = SettingsManager.text("settings.language")
	english_button.text = SettingsManager.text("settings.english")
	vietnamese_button.text = SettingsManager.text("settings.vietnamese")
	back_text.text = SettingsManager.text("settings.back")


func _refresh_language_state() -> void:
	_set_segment_selected(english_button, SettingsManager.language == "en")
	_set_segment_selected(vietnamese_button, SettingsManager.language == "vi")


func _set_segment_selected(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", _segment_style(selected, false))
	button.add_theme_stylebox_override("hover", _segment_style(selected, true))
	button.add_theme_color_override(
		"font_color",
		Color(1.0, 0.88, 0.54, 1.0) if selected else Color(0.72, 0.66, 0.54, 0.88),
	)


func _set_active_row(index: int) -> void:
	_active_row = index
	music_row.get_node("Focus").visible = index == 0
	fullscreen_row.get_node("Focus").visible = index == 1
	language_row.get_node("Focus").visible = index == 2
	back_frame.modulate = Color(1.28, 1.15, 0.78, 1.0) if index == 3 else Color.WHITE


func _on_music_slider_changed(value: float) -> void:
	SettingsManager.set_music_volume_percent(roundi(value))


func _on_music_volume_changed(percent: int) -> void:
	music_slider.set_value_no_signal(percent)
	music_value.text = "%d%%" % percent
	var progress := clampf(float(percent) / 100.0, 0.0, 1.0)
	# Native CanvasLayer geometry snaps directly to physical viewport pixels.
	var visual_width := snappedf(progress * SLIDER_TRACK_WIDTH, 1.0)
	music_fill_clip.size.x = visual_width
	music_fill_clip.visible = visual_width > 0.0
	music_knob.position.x = SLIDER_KNOB_LEFT + visual_width


func _on_fullscreen_changed(enabled: bool) -> void:
	_set_segment_selected(windowed_button, not enabled)
	_set_segment_selected(fullscreen_button, enabled)
	_update_focus_neighbors()


func _on_language_changed(_locale: String) -> void:
	_refresh_copy()
	_refresh_language_state()
	_update_focus_neighbors()
