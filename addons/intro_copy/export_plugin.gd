@tool
extends EditorExportPlugin

const INTRO_SOURCE   := "res://assets/intro/intro.webm"
const INTRO_FILENAME := "intro.webm"

var _export_dir: String = ""

func _get_name() -> String:
	return "IntroCopyPlugin"

func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	if "web" in features:
		_export_dir = path.get_base_dir()
	else:
		_export_dir = ""

func _export_end() -> void:
	if _export_dir.is_empty():
		return

	var source := ProjectSettings.globalize_path(INTRO_SOURCE)
	var dest   := _export_dir.path_join(INTRO_FILENAME)

	if not FileAccess.file_exists(source):
		push_warning("IntroCopyPlugin: intro.webm not found at: %s" % source)
		_export_dir = ""
		return

	var err := DirAccess.copy_absolute(source, dest)
	if err == OK:
		print("IntroCopyPlugin: ✓ copied intro.webm → %s" % dest)
	else:
		push_warning("IntroCopyPlugin: failed to copy intro.webm — %s" % error_string(err))

	_export_dir = ""
