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

var mouse_parallax: Vector2 = Vector2.ZERO
var mouse_target: Vector2 = Vector2.ZERO
var flash_timer: float = 0.0

var stars: Array[Dictionary] = []
var worlds: Array[Dictionary] = []
var nebulae: Array[Dictionary] = []

@onready var bg: ColorRect = $Background
@onready var vignette: ColorRect = $Vignette
@onready var scanlines: ColorRect = $Scanlines
@onready var title_wrap: VBoxContainer = $Ui/Center/Column/TitleWrap
@onready var menu: VBoxContainer = $Ui/Center/Column/Menu
@onready var new_game_button: Button = $Ui/Center/Column/Menu/NewGameButton
@onready var continue_button: Button = $Ui/Center/Column/Menu/ContinueButton
@onready var settings_button: Button = $Ui/Center/Column/Menu/SettingsButton
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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_background_data()
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
	mouse_parallax = mouse_parallax.lerp(mouse_target, 1.0 - pow(0.001, delta))

	var time: float = Time.get_ticks_msec() * 0.001
	title_wrap.modulate.a = clampf(title_wrap.modulate.a + delta * 1.5, 0.0, 1.0)
	menu.modulate.a = clampf(menu.modulate.a + delta * 1.1, 0.0, 1.0)

	title_wrap.position.y = 0.0 + sin(time * 1.2) * 4.0
	menu.position.y = 0.0 + sin(time * 0.9) * 2.0

	press_key.modulate.a = 0.35 + (sin(time * 2.2) * 0.5 + 0.5) * 0.35
	scanlines.modulate.a = 0.12 if scanlines_enabled else 0.0

	if flash_timer > 0.0:
		flash_timer = max(flash_timer - delta, 0.0)
		flash_label.modulate.a = min(flash_timer * 3.0, 1.0)
	else:
		flash_label.modulate.a = max(flash_label.modulate.a - delta * 4.0, 0.0)

	queue_redraw()

func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5
	var time: float = Time.get_ticks_msec() * 0.001

	for nebula in nebulae:
		var pos: Vector2 = Vector2(nebula["fx"] * viewport_size.x, nebula["fy"] * viewport_size.y)
		pos += Vector2(sin(time * nebula["sx"] + nebula["phase"]), cos(time * nebula["sy"] + nebula["phase"])) * nebula["drift"]
		draw_circle(pos, nebula["radius"] * min(viewport_size.x, viewport_size.y), nebula["color"])

	for star in stars:
		var star_pos: Vector2 = Vector2(star["x"] * viewport_size.x, star["y"] * viewport_size.y)
		star_pos += Vector2(mouse_parallax.x * star["layer"] * -28.0, mouse_parallax.y * star["layer"] * -18.0)
		star_pos.x = wrapf(star_pos.x, 0.0, viewport_size.x)
		star_pos.y = wrapf(star_pos.y, 0.0, viewport_size.y)

		var twinkle: float = 0.45 + 0.55 * sin(time * star["speed"] + star["phase"])
		var color: Color = star["color"]
		color.a = 0.25 + 0.75 * twinkle
		var star_size: float = star["size"]
		draw_rect(Rect2(star_pos.floor(), Vector2.ONE * star_size), color, true)

	for world in worlds:
		var angle: float = world["phase"] + time * world["speed"]
		var world_pos: Vector2 = center
		world_pos.x += cos(angle) * world["orbit_rx"] * viewport_size.x
		world_pos.y += sin(angle) * world["orbit_ry"] * viewport_size.y
		world_pos += Vector2(mouse_parallax.x * world["layer"] * -28.0, mouse_parallax.y * world["layer"] * -18.0)

		var radius: float = world["size"]
		var glow: Color = Color(world["glow"].r, world["glow"].g, world["glow"].b, 0.14)
		draw_circle(world_pos, radius * 1.2, glow)
		draw_circle(world_pos, radius, world["base"])
		draw_circle(world_pos + Vector2(-radius * 0.18, -radius * 0.18), radius * 0.72, world["mid"])
		draw_circle(world_pos + Vector2(radius * 0.12, radius * 0.1), radius * 0.42, world["highlight"])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var viewport_size: Vector2 = get_viewport_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			mouse_target.x = ((event.position.x / viewport_size.x) - 0.5) * 2.0
			mouse_target.y = ((event.position.y / viewport_size.y) - 0.5) * 2.0

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

func _build_background_data() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	stars.clear()
	for i in range(340):
		var warm: bool = rng.randf() < 0.3
		stars.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"size": 2.0 if rng.randf() < 0.12 else 1.0,
			"phase": rng.randf() * TAU,
			"speed": 1.2 + rng.randf() * 3.8,
			"layer": rng.randf() * 0.6 + 0.1,
			"color": Color(0.91, 0.85, 0.63, 1.0) if warm else Color(0.66, 0.75, 0.86, 1.0),
		})

	nebulae = [
		{"fx": 0.18, "fy": 0.28, "radius": 0.38, "color": Color(0.22, 0.06, 0.47, 0.06), "sx": 0.18, "sy": 0.22, "phase": 0.8, "drift": 18.0},
		{"fx": 0.76, "fy": 0.62, "radius": 0.32, "color": Color(0.06, 0.14, 0.43, 0.07), "sx": 0.21, "sy": 0.19, "phase": 1.7, "drift": 15.0},
		{"fx": 0.48, "fy": 0.82, "radius": 0.28, "color": Color(0.32, 0.06, 0.31, 0.05), "sx": 0.14, "sy": 0.16, "phase": 2.3, "drift": 12.0},
	]

	worlds = [
		{"size": 54.0, "orbit_rx": 0.30, "orbit_ry": 0.20, "speed": 0.17, "phase": 0.0, "layer": 0.25, "base": Color(0.10, 0.29, 0.19), "mid": Color(0.22, 0.48, 0.20), "highlight": Color(0.50, 0.73, 0.41), "glow": Color(0.31, 0.78, 0.38)},
		{"size": 40.0, "orbit_rx": 0.36, "orbit_ry": 0.17, "speed": -0.13, "phase": 1.26, "layer": 0.37, "base": Color(0.42, 0.06, 0.00), "mid": Color(0.78, 0.19, 0.00), "highlight": Color(0.96, 0.54, 0.25), "glow": Color(0.96, 0.34, 0.12)},
		{"size": 48.0, "orbit_rx": 0.28, "orbit_ry": 0.22, "speed": 0.10, "phase": 2.51, "layer": 0.49, "base": Color(0.10, 0.23, 0.42), "mid": Color(0.29, 0.56, 0.75), "highlight": Color(0.87, 0.95, 1.00), "glow": Color(0.54, 0.76, 0.95)},
		{"size": 35.0, "orbit_rx": 0.40, "orbit_ry": 0.15, "speed": -0.16, "phase": 3.77, "layer": 0.61, "base": Color(0.48, 0.25, 0.06), "mid": Color(0.85, 0.54, 0.13), "highlight": Color(0.96, 0.83, 0.46), "glow": Color(0.93, 0.63, 0.23)},
		{"size": 44.0, "orbit_rx": 0.32, "orbit_ry": 0.18, "speed": 0.08, "phase": 5.03, "layer": 0.73, "base": Color(0.04, 0.10, 0.38), "mid": Color(0.12, 0.24, 0.72), "highlight": Color(0.32, 0.44, 0.91), "glow": Color(0.22, 0.38, 0.96)},
	]

func _apply_visual_styles() -> void:
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
	var cursor_label := button.get_node("Cursor") as Label
	cursor_label.visible = active

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
	_open_importer()

func _on_continue_pressed() -> void:
	_show_flash("— NO SAVE FOUND —")

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
