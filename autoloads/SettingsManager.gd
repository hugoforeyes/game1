extends Node
## Owns the three user-facing settings exposed by the main-menu Settings panel.
##
## Settings are intentionally separate from SaveManager: they apply before a
## story run exists and persist independently in user://settings.cfg.

signal music_volume_changed(percent: int)
signal fullscreen_changed(enabled: bool)
signal language_changed(locale: String)

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_MUSIC_VOLUME := 80
const DEFAULT_LANGUAGE := "en"
const SUPPORTED_LANGUAGES := ["en", "vi"]
const MUSIC_BUS_NAME := "Music"
const WEB_FULLSCREEN_SYNC_TIMEOUT := 1.5

const UI_COPY: Dictionary = {
	"en": {
		"menu.new_game": "NEW GAME",
		"menu.continue": "CONTINUE",
		"menu.settings": "SETTINGS",
		"settings.title": "SETTINGS",
		"settings.music": "MUSIC VOLUME",
		"settings.fullscreen": "FULLSCREEN",
		"settings.windowed": "WINDOWED",
		"settings.language": "LANGUAGE",
		"settings.english": "ENGLISH",
		"settings.vietnamese": "TIẾNG VIỆT",
		"settings.back": "BACK",
		"menu.no_save": "- NO SAVE FOUND -",
		"menu.connecting": "Connecting to story server...",
		"menu.loading_save": "Loading saved journey...",
		"menu.server_error": "- COULD NOT REACH STORY SERVER -",
		"menu.hint": "ARROW KEYS TO SELECT · ENTER TO CONFIRM",
		"menu.loading_title": "NEW JOURNEY",
		"gacha.title": "CHOOSE YOUR WORLD",
		"gacha.searching_title": "THE GODDESS OF LIFE IS SEEKING WORLDS",
		"gacha.searching_sub": "Your soul awaits its rebirth...",
		"gacha.weaving": "Weaving world %d of %d...",
		"gacha.hint": "ARROW KEYS TO CHOOSE · ENTER TO REINCARNATE · ESC TO RETURN",
		"gacha.reincarnating": "The door is opening...",
		"gacha.error": "- THE GODDESS CANNOT REACH THE WORLDS -",
		"gacha.error_hint": "PRESS ESC TO RETURN",
		"gacha.loading_music": "Downloading world music...",
		"gacha.loading_data": "DOWNLOADING WORLD DATA",
		"gacha.st_items": "Fetching item icons...",
		"gacha.st_chapter_map": "Fetching chapter map illustration...",
		"gacha.st_world_map": "Fetching world map illustration...",
		"gacha.st_intro": "Fetching chapter intro...",
		"gacha.st_build": "Building world...",
		"gacha.st_zone": "Downloading %s...",
	},
	"vi": {
		"menu.new_game": "TRÒ CHƠI MỚI",
		"menu.continue": "TIẾP TỤC",
		"menu.settings": "CÀI ĐẶT",
		"settings.title": "CÀI ĐẶT",
		"settings.music": "ÂM LƯỢNG NHẠC",
		"settings.fullscreen": "TOÀN MÀN HÌNH",
		"settings.windowed": "CỬA SỔ",
		"settings.language": "NGÔN NGỮ",
		"settings.english": "ENGLISH",
		"settings.vietnamese": "TIẾNG VIỆT",
		"settings.back": "QUAY LẠI",
		"menu.no_save": "- CHƯA CÓ BẢN LƯU -",
		"menu.connecting": "Đang kết nối máy chủ cốt truyện...",
		"menu.loading_save": "Đang tải hành trình đã lưu...",
		"menu.server_error": "- KHÔNG THỂ KẾT NỐI MÁY CHỦ -",
		"menu.hint": "PHÍM MŨI TÊN ĐỂ CHỌN · ENTER ĐỂ XÁC NHẬN",
		"menu.loading_title": "HÀNH TRÌNH MỚI",
		"gacha.title": "CHỌN THẾ GIỚI CHUYỂN SINH",
		"gacha.searching_title": "NỮ THẦN SỰ SỐNG ĐANG TÌM KIẾM THẾ GIỚI",
		"gacha.searching_sub": "Linh hồn bạn đang chờ được chuyển sinh...",
		"gacha.weaving": "Đang dệt nên thế giới thứ %d / %d...",
		"gacha.hint": "PHÍM MŨI TÊN ĐỂ CHỌN · ENTER ĐỂ CHUYỂN SINH · ESC QUAY LẠI",
		"gacha.reincarnating": "Cánh cửa đang mở ra...",
		"gacha.error": "- NỮ THẦN KHÔNG THỂ KẾT NỐI CÁC THẾ GIỚI -",
		"gacha.error_hint": "NHẤN ESC ĐỂ QUAY LẠI",
		"gacha.loading_music": "Đang tải âm nhạc thế giới...",
		"gacha.loading_data": "ĐANG TẢI DỮ LIỆU THẾ GIỚI",
		"gacha.st_items": "Đang tải biểu tượng vật phẩm...",
		"gacha.st_chapter_map": "Đang tải bản đồ chương...",
		"gacha.st_world_map": "Đang tải bản đồ thế giới...",
		"gacha.st_intro": "Đang tải màn mở chương...",
		"gacha.st_build": "Đang dựng thế giới...",
		"gacha.st_zone": "Đang tải khu vực %s...",
	},
}

var music_volume_percent: int = DEFAULT_MUSIC_VOLUME
var fullscreen_enabled: bool = false
var language: String = DEFAULT_LANGUAGE
var _web_fullscreen_sync_active := false
var _web_fullscreen_target := false
var _web_fullscreen_elapsed := 0.0


func _ready() -> void:
	set_process(false)
	_ensure_music_bus()
	_load_settings()
	_apply_music_volume()
	TranslationServer.set_locale(language)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_apply_fullscreen_preference.call_deferred()


func _process(delta: float) -> void:
	if not _web_fullscreen_sync_active:
		set_process(false)
		return
	_web_fullscreen_elapsed += delta
	var actual := is_fullscreen_active()
	if actual == _web_fullscreen_target or _web_fullscreen_elapsed >= WEB_FULLSCREEN_SYNC_TIMEOUT:
		_web_fullscreen_sync_active = false
		set_process(false)
		_commit_fullscreen_state(actual, true)


func text(key: String) -> String:
	var copy: Dictionary = UI_COPY.get(language, UI_COPY[DEFAULT_LANGUAGE]) as Dictionary
	return str(copy.get(key, (UI_COPY[DEFAULT_LANGUAGE] as Dictionary).get(key, key)))


func set_music_volume_percent(percent: int) -> void:
	var next_value := clampi(percent, 0, 100)
	if next_value == music_volume_percent:
		return
	music_volume_percent = next_value
	_apply_music_volume()
	_save_settings()
	music_volume_changed.emit(music_volume_percent)


func set_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		_commit_fullscreen_state(enabled, true)
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if OS.get_name() == "Web":
		# Browser fullscreen resolves after its `fullscreenchange` callback. Poll
		# the real state without moving the DisplayServer request outside the
		# direct button gesture that browsers require.
		_web_fullscreen_target = enabled
		_web_fullscreen_elapsed = 0.0
		_web_fullscreen_sync_active = true
		set_process(true)
		return
	_commit_fullscreen_state(is_fullscreen_active(), true)


func refresh_fullscreen_state() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var actual := is_fullscreen_active()
	if _web_fullscreen_sync_active and actual == _web_fullscreen_target:
		_web_fullscreen_sync_active = false
		set_process(false)
	if actual == fullscreen_enabled:
		return
	_commit_fullscreen_state(actual)


func is_fullscreen_active() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]


func set_language(locale: String) -> void:
	var next_locale := locale.to_lower()
	if not SUPPORTED_LANGUAGES.has(next_locale):
		next_locale = DEFAULT_LANGUAGE
	if next_locale == language:
		return
	language = next_locale
	TranslationServer.set_locale(language)
	_save_settings()
	language_changed.emit(language)


func _ensure_music_bus() -> int:
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if bus_index >= 0:
		return bus_index
	AudioServer.add_bus()
	bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, MUSIC_BUS_NAME)
	return bus_index


func _apply_music_volume() -> void:
	var bus_index := _ensure_music_bus()
	var linear := float(music_volume_percent) / 100.0
	AudioServer.set_bus_mute(bus_index, music_volume_percent <= 0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(linear, 0.0001)))


func _apply_fullscreen_preference() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Browsers only allow fullscreen from a direct user gesture. Reflect the real
	# browser state at startup; the Settings button applies it on click.
	if OS.get_name() == "Web":
		fullscreen_enabled = is_fullscreen_active()
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen_enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	fullscreen_enabled = is_fullscreen_active()


func _on_viewport_size_changed() -> void:
	# Covers browser `fullscreenchange` (including Esc-to-exit) and native window
	# mode changes initiated outside the Settings panel.
	refresh_fullscreen_state.call_deferred()


func _commit_fullscreen_state(enabled: bool, force_emit: bool = false) -> void:
	var changed := fullscreen_enabled != enabled
	fullscreen_enabled = enabled
	_save_settings()
	if changed or force_emit:
		fullscreen_changed.emit(fullscreen_enabled)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_path()) != OK:
		return
	music_volume_percent = clampi(
		int(config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)),
		0,
		100,
	)
	fullscreen_enabled = bool(config.get_value("display", "fullscreen", false))
	var saved_language := str(config.get_value("localization", "language", DEFAULT_LANGUAGE)).to_lower()
	language = saved_language if SUPPORTED_LANGUAGES.has(saved_language) else DEFAULT_LANGUAGE


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume_percent)
	config.set_value("display", "fullscreen", fullscreen_enabled)
	config.set_value("localization", "language", language)
	var error := config.save(_settings_path())
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))


func _settings_path() -> String:
	var override := OS.get_environment("GAMEV1_SETTINGS_CONFIG_PATH").strip_edges()
	return override if not override.is_empty() else CONFIG_PATH
