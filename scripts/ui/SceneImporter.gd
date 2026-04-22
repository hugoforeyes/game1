extends Control

var scene_zip_path: String = ""
var character_sprite_path: String = ""

@onready var package_value: LineEdit = $Background/Margin/Panel/Content/PackageSection/PackagePathRow/PackageValue
@onready var sprite_value: LineEdit = $Background/Margin/Panel/Content/SpriteSection/SpritePathRow/SpriteValue
@onready var status_label: Label = $Background/Margin/Panel/Content/Status
@onready var import_button: Button = $Background/Margin/Panel/Content/Actions/ImportButton
@onready var package_dialog: FileDialog = $PackageDialog
@onready var sprite_dialog: FileDialog = $SpriteDialog

func _ready() -> void:
	package_dialog.filters = PackedStringArray(["*.zip ; Zip archives"])
	sprite_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Image files"])
	_set_status("Choose a scene zip to build the map. Character sprite upload is optional.")
	_refresh_ui()

func _refresh_ui() -> void:
	package_value.text = scene_zip_path
	sprite_value.text = character_sprite_path
	package_value.placeholder_text = "Paste zip path here, or browse"
	sprite_value.placeholder_text = "Optional sprite path, or browse"
	import_button.disabled = scene_zip_path.is_empty()

func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.modulate = Color(0.9, 0.35, 0.35) if is_error else Color(0.95, 0.94, 0.85)

func _on_choose_package_pressed() -> void:
	_open_dialog(package_dialog)

func _on_choose_sprite_pressed() -> void:
	_open_dialog(sprite_dialog)

func _on_package_dialog_file_selected(path: String) -> void:
	scene_zip_path = path
	_set_status("Scene package selected. Import it when you're ready.")
	_refresh_ui()

func _on_sprite_dialog_file_selected(path: String) -> void:
	character_sprite_path = path
	_set_status("Character sprite selected. Import it together with the scene package.")
	_refresh_ui()

func _on_package_value_text_changed(new_text: String) -> void:
	scene_zip_path = new_text.strip_edges()
	_refresh_ui()

func _on_sprite_value_text_changed(new_text: String) -> void:
	character_sprite_path = new_text.strip_edges()
	_refresh_ui()

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

func _on_default_button_pressed() -> void:
	GameManager.reset_runtime_imports(true)
	get_tree().change_scene_to_file(GameManager.WORLD_SCENE_PATH)

func _open_dialog(dialog: FileDialog) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	dialog.size = Vector2i(
		int(clamp(viewport_size.x * 0.82, 860.0, 1080.0)),
		int(clamp(viewport_size.y * 0.72, 520.0, 680.0))
	)
	dialog.popup_centered()
