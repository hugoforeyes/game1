extends Node
## Runtime visual QA for the production StartScene Settings overlay.

const START_SCENE := preload("res://scenes/ui/StartScene.tscn")
const PREVIEW_CONFIG_ENV := "GAMEV1_SETTINGS_CONFIG_PATH"


func _ready() -> void:
	# SettingsManager autoloads before this scene, but every setter resolves the
	# override dynamically. Redirect all QA writes away from the real player file.
	if OS.get_environment(PREVIEW_CONFIG_ENV).strip_edges().is_empty():
		OS.set_environment(
			PREVIEW_CONFIG_ENV,
			OS.get_temp_dir().path_join(
				"gamev1_settings_ui_preview_%d.cfg" % OS.get_process_id()
			),
		)
	var width_text := OS.get_environment("SETTINGS_PREVIEW_WIDTH")
	var height_text := OS.get_environment("SETTINGS_PREVIEW_HEIGHT")
	var width := 1024 if width_text.is_empty() else int(width_text)
	var height := 576 if height_text.is_empty() else int(height_text)
	var locale := OS.get_environment("SETTINGS_PREVIEW_LOCALE").to_lower()
	if locale not in ["en", "vi"]:
		locale = "en"
	get_window().size = Vector2i(width, height)
	SettingsManager.set_language(locale)

	var start_scene := START_SCENE.instantiate()
	add_child(start_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# start_menu_v2: plaque buttons render their captions on child Labels so the
	# generated art stays text-free; read them via the buttons' meta refs.
	var new_game_label: Label = start_scene.new_game_button.get_meta("label")
	var settings_label: Label = start_scene.settings_button.get_meta("label")
	assert(new_game_label.text == SettingsManager.text("menu.new_game"))
	assert(settings_label.text == SettingsManager.text("menu.settings"))
	start_scene.settings_overlay.open_panel()
	# Let the production 200 ms entrance animation settle before visual QA.
	await get_tree().create_timer(0.28).timeout
	if DisplayServer.get_name() != "headless":
		# Metal may upload newly imported textures a draw behind the scene tree. Wait
		# for completed render frames so screenshots never capture partial art.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

	var panel: SettingsPanel = start_scene.get_node("SettingsLayer/SettingsOverlay")
	_assert_settings_contract(panel, locale)
	if DisplayServer.get_name() == "headless":
		print("[SettingsUiPreview] contract passed (%dx%d, %s, headless)" % [width, height, locale])
		get_tree().quit()
		return
	var output := OS.get_environment("SETTINGS_PREVIEW_OUTPUT")
	if output.is_empty():
		output = "res://tools/qa_settings_%s.png" % locale
	if output.begins_with("res://") or output.begins_with("user://"):
		output = ProjectSettings.globalize_path(output)
	var error := get_viewport().get_texture().get_image().save_png(output)
	assert(error == OK, "could not save Settings preview: %s" % error_string(error))
	print("[SettingsUiPreview] wrote %s (%dx%d, %s)" % [output, width, height, locale])
	get_tree().quit()


func _assert_settings_contract(panel: SettingsPanel, locale: String) -> void:
	assert(panel.visible)
	assert(panel.music_slider.has_focus())
	assert(panel.music_slider.value == SettingsManager.music_volume_percent)
	assert(panel.title_label.text == SettingsManager.text("settings.title"))
	assert(panel.english_button.text == "ENGLISH")
	assert(panel.vietnamese_button.text == "TIẾNG VIỆT")
	assert(not panel.has_node("PanelRoot/PanelVisual/SfxRow"))
	assert(not panel.has_node("PanelRoot/PanelVisual/ScanlineRow"))
	assert(SettingsManager.SUPPORTED_LANGUAGES == ["en", "vi"])
	assert(SettingsManager.language == locale)
	assert(panel.size == get_viewport().get_visible_rect().size)

	var fitted_rect := Rect2(panel.panel_root.position, SettingsPanel.PANEL_SIZE * panel.panel_root.scale)
	assert(fitted_rect.position.x >= 0.0 and fitted_rect.position.y >= 0.0)
	assert(fitted_rect.end.x <= panel.size.x + 0.5)
	assert(fitted_rect.end.y <= panel.size.y + 0.5)
	assert(panel.music_row.size == Vector2(740.0, 68.0))
	assert(panel.fullscreen_row.size == Vector2(740.0, 68.0))
	assert(panel.language_row.size == Vector2(740.0, 68.0))
	_assert_native_resolution_components(panel)
	_assert_text_fits(panel.title_label)
	_assert_text_fits(panel.music_label)
	_assert_text_fits(panel.fullscreen_label)
	_assert_text_fits(panel.language_label)
	_assert_text_fits(panel.windowed_button)
	_assert_text_fits(panel.fullscreen_button)
	_assert_text_fits(panel.english_button)
	_assert_text_fits(panel.vietnamese_button)
	_assert_text_fits(panel.back_text)

	var bus_index := AudioServer.get_bus_index(SettingsManager.MUSIC_BUS_NAME)
	assert(bus_index >= 0)
	var original_volume := SettingsManager.music_volume_percent
	SettingsManager.set_music_volume_percent(65)
	assert(not AudioServer.is_bus_mute(bus_index))
	assert(absf(AudioServer.get_bus_volume_db(bus_index) - linear_to_db(0.65)) < 0.01)
	assert(is_equal_approx(panel.music_fill_clip.size.x, snappedf(310.0 * 0.65, 1.0)))
	assert(is_equal_approx(panel.music_knob.position.x, 286.0 + panel.music_fill_clip.size.x))
	SettingsManager.set_music_volume_percent(original_volume)


func _assert_native_resolution_components(panel: SettingsPanel) -> void:
	assert(panel.panel_visual.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
	assert(is_zero_approx(panel.music_slider.self_modulate.a))
	assert(panel.music_slider.get_theme_icon("grabber").get_size() == panel.music_knob.size)
	var music_idle: TextureRect = panel.music_row.get_node("Idle")
	var slider_track: TextureRect = panel.music_row.get_node("SliderTrack")
	var slider_fill: TextureRect = panel.music_fill_clip.get_node("Fill")
	var selector_frame: TextureRect = panel.fullscreen_row.get_node("Selector/Frame")
	var divider: TextureRect = panel.panel_visual.get_node("Divider")
	var back_frame: TextureRect = panel.panel_visual.get_node("BackFrame")
	var top_crest: TextureRect = panel.panel_visual.get_node("TopCrest")
	assert(music_idle.texture.get_size() == music_idle.size * 2.0)
	assert(slider_track.texture.get_size() == slider_track.size * 2.0)
	assert(slider_fill.texture.get_size() == slider_track.texture.get_size())
	assert(selector_frame.texture.get_size() == selector_frame.size * 2.0)
	assert(divider.texture.get_size() == divider.size * 2.0)
	assert(back_frame.texture.get_size() == back_frame.size * 2.0)
	assert(top_crest.texture.get_width() >= roundi(top_crest.size.x))
	assert(top_crest.texture.get_height() >= roundi(top_crest.size.y))


func _assert_text_fits(control: Control) -> void:
	var text := str(control.get("text"))
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	assert(width <= control.size.x - 4.0, "%s clips: %.1f > %.1f" % [text, width, control.size.x - 4.0])
