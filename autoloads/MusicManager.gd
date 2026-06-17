extends Node

const BASE_URL := "http://127.0.0.1:5001"
const WEB_BASE_URL := ""

## Emitted when a chapter's music finishes caching (so the intro slides can wait
## for music to be ready before entering the world).
signal music_ready(key: String)

var _player: AudioStreamPlayer = null
# chapter cache_key -> generate_music dict, warmed by prefetch() during slides.
var _music_cache: Dictionary = {}


## True once this chapter's music is cached (prefetch finished).
func is_ready(scene_ctx: Dictionary) -> bool:
	return _music_cache.has(_cache_key(scene_ctx))

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

func _cache_key(scene_ctx: Dictionary) -> String:
	return "%s::chapter_%d" % [str(scene_ctx.get("run_id", "")), int(scene_ctx.get("chapter", 1))]

## Cache-or-fetch a chapter's music dict. Keeps it cached so all zones of a
## chapter — and normal/boss switches within a battle — reuse it without
## re-downloading.
func _get_music(scene_ctx: Dictionary) -> Dictionary:
	var key := _cache_key(scene_ctx)
	if _music_cache.has(key):
		return _music_cache[key] as Dictionary
	var music := await _fetch_music(scene_ctx)
	if not music.is_empty():
		_music_cache[key] = music
		music_ready.emit(key)
	return music

## Download + cache a chapter's music in the background (called while the intro
## slides are showing) so load_and_play is instant afterwards.
func prefetch(scene_ctx: Dictionary) -> void:
	if _music_cache.has(_cache_key(scene_ctx)):
		return
	var music := await _get_music(scene_ctx)
	if not music.is_empty():
		print("[Music] prefetched %s" % _cache_key(scene_ctx))

## Play a random Normal Scene (exploration) track for this chapter.
func load_and_play(scene_ctx: Dictionary) -> void:
	await _play_group(scene_ctx, "normal_scene")

## Play a random Boss Scene (combat) track for this chapter.
func play_boss(scene_ctx: Dictionary) -> void:
	await _play_group(scene_ctx, "boss_scene")

func _play_group(scene_ctx: Dictionary, group: String) -> void:
	var music := await _get_music(scene_ctx)
	if music.is_empty():
		return
	var tracks: Array = music.get(group, []) as Array
	if tracks.is_empty() and group != "normal_scene":
		tracks = music.get("normal_scene", []) as Array  # fall back to exploration
	if tracks.is_empty():
		print("[Music] No %s tracks found" % group)
		return

	var track: Dictionary = tracks[randi() % tracks.size()] as Dictionary
	_play_track(track)

func _fetch_music(scene_ctx: Dictionary) -> Dictionary:
	var run_id      := str(scene_ctx.get("run_id", ""))
	var chapter_num := int(scene_ctx.get("chapter", 1))
	var chapter_key := "chapter_%d" % chapter_num

	if run_id.is_empty():
		return {}

	var url := "%s/api/worlds/%s/chapters/%s/data" % [_get_base_url(), run_id, chapter_key]
	print("[Music] GET %s" % url)

	var http := HTTPRequest.new()
	http.timeout = 90.0
	add_child(http)
	var request_error: Error = http.request(url)
	if request_error != OK:
		http.queue_free()
		print("[Music] Request start failed: %s" % error_string(request_error))
		return {}

	var response: Array = await http.request_completed
	http.queue_free()

	var result: int = int(response[0])
	var code: int   = int(response[1])
	var body: PackedByteArray = response[3] as PackedByteArray
	print("[Music] Response result=%d http=%d bytes=%d" % [result, code, body.size()])

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Music] Failed to load chapter data: result=%d HTTP %d" % [result, code])
		return {}

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed as Dictionary).get("ok", false):
		print("[Music] Chapter data response not ok")
		return {}

	var chapter_data: Dictionary = (parsed as Dictionary).get("chapter_data", {}) as Dictionary
	return chapter_data.get("generate_music", {}) as Dictionary

func _get_base_url() -> String:
	if OS.get_name() == "Web":
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(origin) == TYPE_STRING and not str(origin).is_empty():
			return str(origin)
		return WEB_BASE_URL
	return BASE_URL

func _play_track(track: Dictionary) -> void:
	var data_uri := str(track.get("audio_data_uri", ""))
	if data_uri.is_empty():
		print("[Music] Track has no audio_data_uri")
		return

	# Strip "data:audio/mpeg;base64," prefix
	var comma := data_uri.find(",")
	if comma == -1:
		print("[Music] Invalid audio_data_uri format")
		return
	var b64 := data_uri.substr(comma + 1)

	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		print("[Music] Base64 decode failed")
		return
	print("[Music] Decoded track bytes=%d" % raw.size())

	var stream := AudioStreamMP3.new()
	stream.data = raw
	stream.loop  = true

	_player.volume_db = -80.0
	_player.stream = stream
	_player.play()
	print("[Music] Playing: %s" % track.get("label", track.get("id", "?")))

	var tween := create_tween()
	tween.tween_property(_player, "volume_db", 0.0, 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func stop() -> void:
	_player.stop()
