extends Control

const MENU_DEFAULT_COLOR := Color(0.82, 0.73, 0.51, 0.55)
const MENU_ACTIVE_COLOR := Color(0.96, 0.88, 0.50, 1.0)
const PANEL_BG := Color(0.03, 0.02, 0.09, 0.93)
const PANEL_BORDER := Color(0.78, 0.61, 0.24, 0.35)

var scene_zip_path: String = ""
var character_sprite_path: String = ""
var music_value: int = 8
var sfx_value: int = 10
var scanlines_enabled: bool = true
var is_loading_new_game: bool = false

var flash_timer: float = 0.0
var spinner_timer: float = 0.0
var spinner_index: int = 0
const SPINNER_FRAMES := ["* . . .", ". * . .", ". . * .", ". . . *"]


@onready var bg: TextureRect = $BackgroundImage
@onready var vignette: ColorRect = $Vignette
@onready var scanlines: ColorRect = $Scanlines
@onready var menu: VBoxContainer = $Ui/MenuLayer/Menu
@onready var new_game_button: Button = $Ui/MenuLayer/Menu/NewGameButton
@onready var continue_button: Button = $Ui/MenuLayer/Menu/ContinueButton
@onready var settings_button: Button = $Ui/MenuLayer/Menu/SettingsButton
@onready var press_key: Label = $PressKey
@onready var version_label: Label = $Version
@onready var settings_overlay: Control = $SettingsOverlay
@onready var music_value_label: Label = $SettingsOverlay/Center/Wrap/Panel/Margin/Content/MusicRow/ValueWrap/Value
@onready var sfx_value_label: Label = $SettingsOverlay/Center/Wrap/Panel/Margin/Content/SfxRow/ValueWrap/Value
@onready var scanlines_toggle_button: Button = $SettingsOverlay/Center/Wrap/Panel/Margin/Content/ScanlineRow/ValueWrap/ToggleButton
@onready var importer_overlay: Control = $ImporterOverlay
@onready var package_value: LineEdit = $ImporterOverlay/Center/Panel/Margin/Content/PackageSection/PathRow/PackageValue
@onready var sprite_value: LineEdit = $ImporterOverlay/Center/Panel/Margin/Content/SpriteSection/PathRow/SpriteValue
@onready var status_label: Label = $ImporterOverlay/Center/Panel/Margin/Content/Status
@onready var import_button: Button = $ImporterOverlay/Center/Panel/Margin/Content/Actions/ImportButton
@onready var package_dialog: FileDialog = $PackageDialog
@onready var sprite_dialog: FileDialog = $SpriteDialog
@onready var flash_label: Label = $FlashMessage
@onready var loading_overlay: Control = $LoadingOverlay
@onready var loading_chapter_label: Label = $LoadingOverlay/Center/Content/ChapterLabel
@onready var loading_status_label: Label = $LoadingOverlay/Center/Content/StatusLabel
@onready var loading_spinner_label: Label = $LoadingOverlay/Center/Content/SpinnerLabel

func _ready() -> void:
	# Authored in 480x270 design space, scaled 2x to the 960x540 viewport.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(480, 270)
	scale = Vector2(2, 2)
	mouse_filter = Control.MOUSE_FILTER_PASS
	package_dialog.filters = PackedStringArray(["*.zip ; Zip archives"])
	sprite_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image files"])
	_apply_visual_styles()
	_refresh_import_ui()
	_refresh_settings_ui()
	_refresh_menu_state()
	_set_status("Select New Game to import a scene package.")

	new_game_button.grab_focus()
	get_viewport().size_changed.connect(_on_viewport_resized)

func _process(delta: float) -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	menu.modulate.a = clampf(menu.modulate.a + delta * 1.1, 0.0, 1.0)

	press_key.modulate.a = 0.35 + (sin(time * 2.2) * 0.5 + 0.5) * 0.35
	scanlines.modulate.a = 0.12 if scanlines_enabled else 0.0

	if flash_timer > 0.0:
		flash_timer = max(flash_timer - delta, 0.0)
		flash_label.modulate.a = min(flash_timer * 3.0, 1.0)
	else:
		flash_label.modulate.a = max(flash_label.modulate.a - delta * 4.0, 0.0)

	if loading_overlay.visible:
		spinner_timer += delta
		if spinner_timer >= 0.25:
			spinner_timer = 0.0
			spinner_index = (spinner_index + 1) % SPINNER_FRAMES.size()
			loading_spinner_label.text = SPINNER_FRAMES[spinner_index]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if importer_overlay.visible:
			_close_importer()
			get_viewport().set_input_as_handled()
			return
		if settings_overlay.visible:
			_close_settings()
			get_viewport().set_input_as_handled()
			return

func _apply_visual_styles() -> void:
	var empty_box: StyleBoxEmpty = StyleBoxEmpty.new()
	var panel_box: StyleBoxFlat = StyleBoxFlat.new()
	panel_box.bg_color = PANEL_BG
	panel_box.border_color = PANEL_BORDER
	panel_box.set_border_width_all(1)
	panel_box.content_margin_left = 0
	panel_box.content_margin_top = 0
	panel_box.content_margin_right = 0
	panel_box.content_margin_bottom = 0

	var line_edit_box: StyleBoxFlat = StyleBoxFlat.new()
	line_edit_box.bg_color = Color(0.10, 0.08, 0.16, 0.96)
	line_edit_box.border_color = Color(0.72, 0.58, 0.27, 0.32)
	line_edit_box.set_border_width_all(1)
	line_edit_box.corner_radius_top_left = 4
	line_edit_box.corner_radius_top_right = 4
	line_edit_box.corner_radius_bottom_right = 4
	line_edit_box.corner_radius_bottom_left = 4
	line_edit_box.content_margin_left = 12
	line_edit_box.content_margin_right = 12
	line_edit_box.content_margin_top = 10
	line_edit_box.content_margin_bottom = 10

	var button_box: StyleBoxFlat = StyleBoxFlat.new()
	button_box.bg_color = Color(0.10, 0.08, 0.16, 0.92)
	button_box.border_color = Color(0.74, 0.59, 0.27, 0.35)
	button_box.set_border_width_all(1)
	button_box.corner_radius_top_left = 4
	button_box.corner_radius_top_right = 4
	button_box.corner_radius_bottom_right = 4
	button_box.corner_radius_bottom_left = 4
	button_box.content_margin_left = 14
	button_box.content_margin_right = 14
	button_box.content_margin_top = 10
	button_box.content_margin_bottom = 10

	var button_hover: StyleBoxFlat = button_box.duplicate() as StyleBoxFlat
	button_hover.bg_color = Color(0.18, 0.12, 0.06, 0.95)
	button_hover.border_color = Color(0.90, 0.74, 0.35, 0.7)

	var panel_nodes: Array[PanelContainer] = [
		$SettingsOverlay/Center/Wrap/Panel,
		$ImporterOverlay/Center/Panel,
	]
	for panel in panel_nodes:
		panel.add_theme_stylebox_override("panel", panel_box)

	var boxed_buttons: Array[Button] = [
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/MusicRow/ValueWrap/DownButton,
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/MusicRow/ValueWrap/UpButton,
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/SfxRow/ValueWrap/DownButton,
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/SfxRow/ValueWrap/UpButton,
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/ScanlineRow/ValueWrap/ToggleButton,
		$SettingsOverlay/Center/Wrap/Panel/Margin/Content/FullscreenRow/ValueWrap/ToggleButton,
		$SettingsOverlay/Center/Wrap/CloseSettingsButton,
		$ImporterOverlay/Center/Panel/Margin/Content/PackageSection/PathRow/ChoosePackage,
		$ImporterOverlay/Center/Panel/Margin/Content/SpriteSection/PathRow/ChooseSprite,
		$ImporterOverlay/Center/Panel/Margin/Content/Actions/ImportButton,
		$ImporterOverlay/Center/Panel/Margin/Content/Actions/BuiltinButton,
		$ImporterOverlay/Center/Panel/Margin/Content/CloseButton,
	]
	for button in boxed_buttons:
		button.add_theme_stylebox_override("normal", button_box)
		button.add_theme_stylebox_override("hover", button_hover)
		button.add_theme_stylebox_override("pressed", button_hover)
		button.add_theme_stylebox_override("focus", button_hover)
		button.add_theme_color_override("font_color", Color(0.91, 0.75, 0.31, 1.0))

	var menu_buttons: Array[Button] = [
		new_game_button,
		continue_button,
		settings_button,
	]
	for button in menu_buttons:
		button.add_theme_stylebox_override("normal", empty_box)
		button.add_theme_stylebox_override("hover", empty_box)
		button.add_theme_stylebox_override("pressed", empty_box)
		button.add_theme_stylebox_override("focus", empty_box)

	var input_fields: Array[LineEdit] = [package_value, sprite_value]
	for field in input_fields:
		field.add_theme_stylebox_override("normal", line_edit_box)
		field.add_theme_stylebox_override("focus", button_hover)
		field.add_theme_color_override("font_color", Color(0.93, 0.88, 0.75, 1.0))
		field.add_theme_color_override("font_placeholder_color", Color(0.63, 0.57, 0.45, 0.7))

func _refresh_menu_state() -> void:
	_style_menu_button(new_game_button)
	_style_menu_button(continue_button)
	_style_menu_button(settings_button)

func _style_menu_button(button: Button) -> void:
	var active: bool = button.has_focus()
	button.modulate = MENU_ACTIVE_COLOR if active else MENU_DEFAULT_COLOR
	button.position.x = 10.0 if active else 0.0
	var cursor: CanvasItem = button.get_node("Cursor") as CanvasItem
	cursor.visible = active

func _refresh_import_ui() -> void:
	package_value.text = scene_zip_path
	sprite_value.text = character_sprite_path
	import_button.disabled = scene_zip_path.is_empty()

func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.modulate = Color(0.92, 0.35, 0.35) if is_error else Color(0.80, 0.66, 0.38, 0.92)

func _refresh_settings_ui() -> void:
	music_value_label.text = str(music_value)
	sfx_value_label.text = str(sfx_value)
	scanlines_toggle_button.text = "ON" if scanlines_enabled else "OFF"
	scanlines.modulate.a = 0.12 if scanlines_enabled else 0.0

func _show_flash(message: String) -> void:
	flash_label.text = message
	flash_label.modulate.a = 1.0
	flash_timer = 1.8

func _open_importer() -> void:
	scene_zip_path = ""
	character_sprite_path = ""
	GameManager.reset_runtime_imports(true)
	_refresh_import_ui()
	_set_status("Choose a new scene zip and optional character sprite.")
	importer_overlay.show()
	package_value.grab_focus()

func _close_importer() -> void:
	importer_overlay.hide()
	new_game_button.grab_focus()

func _open_settings() -> void:
	settings_overlay.show()

func _close_settings() -> void:
	settings_overlay.hide()
	settings_button.grab_focus()

func _on_new_game_pressed() -> void:
	if is_loading_new_game:
		return

	print("[StartScene] New Game pressed — fetching world flow from server")
	is_loading_new_game = true
	new_game_button.disabled = true
	_show_loading("Connecting to story server...")
	if not ChapterFlow.loading_status.is_connected(_on_flow_status):
		ChapterFlow.loading_status.connect(_on_flow_status)

	var flow_error: Error = await ChapterFlow.start_new_game()
	if flow_error != OK:
		print("[StartScene] flow start failed err=%d" % flow_error)
		is_loading_new_game = false
		new_game_button.disabled = false
		_hide_loading()
		_show_flash("- COULD NOT REACH STORY SERVER -")
		return
	# ChapterFlow has switched the scene (intro slides or world).

func _on_flow_status(message: String) -> void:
	_set_loading_status(message)
	loading_chapter_label.text = ChapterFlow.progress_label()

func _show_loading(initial_status: String) -> void:
	loading_chapter_label.text = ""
	loading_status_label.text = initial_status
	spinner_index = 0
	spinner_timer = 0.0
	loading_spinner_label.text = SPINNER_FRAMES[0]
	loading_overlay.show()

func _hide_loading() -> void:
	loading_overlay.hide()

func _set_loading_status(message: String) -> void:
	loading_status_label.text = message



func _on_continue_pressed() -> void:
	_show_flash("- NO SAVE FOUND -")

func _on_settings_pressed() -> void:
	_open_settings()

func _on_music_down_pressed() -> void:
	music_value = max(music_value - 1, 0)
	_refresh_settings_ui()

func _on_music_up_pressed() -> void:
	music_value = min(music_value + 1, 10)
	_refresh_settings_ui()

func _on_sfx_down_pressed() -> void:
	sfx_value = max(sfx_value - 1, 0)
	_refresh_settings_ui()

func _on_sfx_up_pressed() -> void:
	sfx_value = min(sfx_value + 1, 10)
	_refresh_settings_ui()

func _on_scanlines_toggle_pressed() -> void:
	scanlines_enabled = not scanlines_enabled
	_refresh_settings_ui()

func _on_fullscreen_toggle_pressed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _on_close_settings_pressed() -> void:
	_close_settings()

func _on_close_importer_pressed() -> void:
	_close_importer()

func _on_package_value_text_changed(new_text: String) -> void:
	scene_zip_path = new_text.strip_edges()
	_refresh_import_ui()

func _on_sprite_value_text_changed(new_text: String) -> void:
	character_sprite_path = new_text.strip_edges()
	_refresh_import_ui()

func _on_choose_package_pressed() -> void:
	_open_dialog(package_dialog)

func _on_choose_sprite_pressed() -> void:
	_open_dialog(sprite_dialog)

func _on_package_dialog_file_selected(path: String) -> void:
	scene_zip_path = path
	_set_status("Scene package selected. Import it when you're ready.")
	_refresh_import_ui()

func _on_sprite_dialog_file_selected(path: String) -> void:
	character_sprite_path = path
	_set_status("Character sprite selected. Import it together with the scene package.")
	_refresh_import_ui()

func _on_import_button_pressed() -> void:
	if scene_zip_path.is_empty():
		_set_status("Select a zip file that contains scene_package.json first.", true)
		return

	GameManager.reset_runtime_imports(true)
	var import_error: Error = GameManager.import_scene_package_zip(scene_zip_path)
	if import_error != OK:
		_set_status("Could not import the scene zip: %s" % error_string(import_error), true)
		return

	if not character_sprite_path.is_empty():
		var sprite_error: Error = GameManager.import_player_sprite(character_sprite_path)
		if sprite_error != OK:
			_set_status("Could not import the character sprite: %s" % error_string(sprite_error), true)
			return

	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)

func _on_use_builtin_pressed() -> void:
	GameManager.reset_runtime_imports(true)
	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)

func _open_dialog(dialog: FileDialog) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	dialog.size = Vector2i(
		int(clamp(viewport_size.x * 0.82, 860.0, 1080.0)),
		int(clamp(viewport_size.y * 0.72, 520.0, 680.0))
	)
	dialog.popup_centered()

func _on_viewport_resized() -> void:
	queue_redraw()

func _on_menu_focus_entered() -> void:
	_refresh_menu_state()
