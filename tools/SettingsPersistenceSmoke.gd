extends Node
## Two-process persistence smoke. Use a temporary GAMEV1_SETTINGS_CONFIG_PATH.


func _ready() -> void:
	assert(
		not OS.get_environment("GAMEV1_SETTINGS_CONFIG_PATH").strip_edges().is_empty(),
		"Persistence smoke requires a temporary GAMEV1_SETTINGS_CONFIG_PATH",
	)
	var mode := OS.get_environment("SETTINGS_SMOKE_MODE")
	if mode == "write":
		SettingsManager.set_music_volume_percent(35)
		SettingsManager.set_language("vi")
		SettingsManager.set_fullscreen(true)
		assert(FileAccess.file_exists(SettingsManager._settings_path()))
		print("[SettingsPersistenceSmoke] wrote settings")
	elif mode == "read":
		assert(SettingsManager.music_volume_percent == 35)
		assert(SettingsManager.language == "vi")
		assert(SettingsManager.fullscreen_enabled)
		assert(TranslationServer.get_locale().begins_with("vi"))
		var bus_index := AudioServer.get_bus_index(SettingsManager.MUSIC_BUS_NAME)
		assert(bus_index >= 0)
		assert(not AudioServer.is_bus_mute(bus_index))
		assert(absf(AudioServer.get_bus_volume_db(bus_index) - linear_to_db(0.35)) < 0.01)
		print("[SettingsPersistenceSmoke] loaded settings")
	else:
		assert(false, "SETTINGS_SMOKE_MODE must be write or read")
	get_tree().quit()
