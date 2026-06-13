extends Node

const BASE_URL  := "http://127.0.0.1:5001"
const API_HOST  := "127.0.0.1"
const API_PORT  := 5001

signal conversation_ready(npc_id: String)

var _start_cache      : Dictionary = {}
var _history          : Dictionary = {}
var _loading          : Dictionary = {}
var _gen_id           : int    = 0       # increment to cancel all in-flight requests
var active_request_id : String = ""      # request_id of the latest in-flight stream
var _prewarm_client   : HTTPClient = null  # pre-connected client ready for next request

# ── cancellation ──────────────────────────────────────────────────────────────

func cancel_all() -> void:
	active_request_id = ""
	_gen_id += 1
	_loading.clear()

func _new_request_id() -> String:
	var t := Time.get_ticks_msec()
	var r := randi() % 0xFFFFFF
	return "req_%d_%06x" % [t, r]

# ── pre-connect ───────────────────────────────────────────────────────────────

func _api_host() -> String:
	if OS.has_feature("web"):
		var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
		if host is String and not str(host).is_empty():
			return str(host)
	return API_HOST

func _api_port() -> int:
	if OS.has_feature("web"):
		var port: Variant = JavaScriptBridge.eval("window.location.port", true)
		var port_text := str(port) if port != null else ""
		if not port_text.is_empty():
			return int(port_text)
		return 80
	return API_PORT

func _start_prewarm() -> void:
	_prewarm_client = HTTPClient.new()
	var err := _prewarm_client.connect_to_host(_api_host(), _api_port())
	if err != OK:
		print("[NPC] Pre-connect failed: %d" % err)
		_prewarm_client = null
		return
	while _prewarm_client != null and _prewarm_client.get_status() in [
			HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		await get_tree().process_frame
		_prewarm_client.poll()
	if _prewarm_client != null and _prewarm_client.get_status() == HTTPClient.STATUS_CONNECTED:
		print("[NPC] Pre-connect ready")
	else:
		print("[NPC] Pre-connect failed (status %s)" % (
			str(_prewarm_client.get_status()) if _prewarm_client else "null"))
		_prewarm_client = null

# ── start conversation (SSE streaming) ────────────────────────────────────────

func stream_start_npc(npc_id: String, scene_ctx: Dictionary,
		on_token: Callable, on_final: Callable, on_error: Callable) -> void:
	if npc_id.is_empty() or _start_cache.has(npc_id) or _loading.has(npc_id):
		return
	_loading[npc_id] = true
	var my_gen := _gen_id
	active_request_id = _new_request_id()
	var body := {
		"request_id": active_request_id,
		"run_id":   scene_ctx.get("run_id", ""),
		"chapter":  scene_ctx.get("chapter", 1),
		"zone_id":  scene_ctx.get("zone_id", ""),
		"npc_id":   npc_id,
		"player_state": {"distance_tiles": 1, "has_interacted_before": false, "active_quest_ids": []},
		"conversation_memory": [],
	}
	var rid := active_request_id
	print("[NPC] POST /start-stream  npc_id=%s request_id=%s" % [npc_id, rid])
	_do_stream("/api/npc-conversation/start-stream", body, my_gen,
		on_token,
		func(data: Dictionary) -> void:
			_loading.erase(npc_id)
			if data.get("ok", false):
				_start_cache[npc_id] = data
				_history[npc_id] = []
				var npc_line := str(data.get("npc_line", ""))
				if not npc_line.is_empty():
					(_history[npc_id] as Array).append({"speaker": "npc", "text": npc_line, "emotion": ""})
				print("[NPC] Start-stream ready: %s" % npc_id)
			else:
				print("[NPC] Start-stream failed %s: %s" % [npc_id, data.get("error", "")])
			on_final.call(data)
			conversation_ready.emit(npc_id),
		func(err: String) -> void:
			_loading.erase(npc_id)
			on_error.call(err)
			conversation_ready.emit(npc_id),
		rid
	)

func get_start(npc_id: String)    -> Dictionary: return _start_cache.get(npc_id, {}) as Dictionary
func get_history(npc_id: String)  -> Array:      return _history.get(npc_id, []) as Array
func is_ready(npc_id: String)     -> bool:       return _start_cache.has(npc_id)
func is_loading(npc_id: String)   -> bool:       return _loading.has(npc_id)

func append_history(npc_id: String, entry: Dictionary) -> void:
	if not _history.has(npc_id):
		_history[npc_id] = []
	(_history[npc_id] as Array).append(entry)

# ── stream reply ──────────────────────────────────────────────────────────────

func stream_reply(
		npc_id       : String,
		player_msg   : String,
		chat_history : Array,
		scene_ctx    : Dictionary,
		on_token     : Callable,
		on_final     : Callable,
		on_error     : Callable) -> void:
	cancel_all()
	var my_gen := _gen_id
	active_request_id = _new_request_id()
	var body : Dictionary = {
		"request_id":     active_request_id,
		"run_id":         scene_ctx.get("run_id", ""),
		"chapter":        scene_ctx.get("chapter", 1),
		"zone_id":        scene_ctx.get("zone_id", ""),
		"npc_id":         npc_id,
		"player_message": player_msg,
		"chat_history":   chat_history,
		"player_state":   {"distance_tiles": 1, "has_interacted_before": true},
	}
	print("[NPC] POST /reply-stream  npc_id=%s request_id=%s" % [npc_id, active_request_id])
	_do_stream("/api/npc-conversation/reply-stream", body, my_gen, on_token, on_final, on_error, active_request_id)

# ── private: SSE streaming ────────────────────────────────────────────────────

func _do_stream(path: String, body: Dictionary, gen_id: int,
		on_token: Callable, on_final: Callable, on_error: Callable,
		expected_rid: String = "") -> void:
	var client: HTTPClient
	if _prewarm_client != null and _prewarm_client.get_status() == HTTPClient.STATUS_CONNECTED:
		print("[NPC] Reusing pre-connected client")
		client = _prewarm_client
		_prewarm_client = null
		_start_prewarm()   # immediately prepare next connection in background
	else:
		print("[NPC] No pre-connect available, connecting fresh")
		client = HTTPClient.new()
		var err := client.connect_to_host(_api_host(), _api_port())
		if err != OK:
			if gen_id == _gen_id:
				on_error.call("connect_to_host failed: %d" % err)
			return
		while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
			await get_tree().process_frame
			client.poll()
			if gen_id != _gen_id:
				client.close()
				return
		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			if gen_id == _gen_id:
				on_error.call("Could not connect (status %d)" % client.get_status())
			client.close()
			return

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: text/event-stream",
	])
	client.request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(body))

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		await get_tree().process_frame
		client.poll()
		if gen_id != _gen_id:
			client.close()
			return

	if not client.has_response():
		if gen_id == _gen_id:
			on_error.call("No response from server")
		client.close()
		return

	var buffer := ""
	while true:
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				if gen_id != _gen_id:
					client.close()
					return
				buffer += chunk.get_string_from_utf8()
				buffer = _parse_sse(buffer, gen_id, expected_rid, on_token, on_final, on_error)
				if gen_id != _gen_id:
					client.close()
					return
			else:
				await get_tree().process_frame
		elif status == HTTPClient.STATUS_CONNECTED:
			# Stream ended naturally — clear active request and recycle connection
			if active_request_id != "" and gen_id == _gen_id:
				active_request_id = ""
			if _prewarm_client == null:
				_prewarm_client = client
				print("[NPC] Recycled connection as pre-connect")
			else:
				client.close()
			return
		else:
			break

	client.close()

func _parse_sse(buffer: String, gen_id: int, expected_rid: String,
		on_token: Callable, on_final: Callable, on_error: Callable) -> String:
	while true:
		var sep := buffer.find("\n\n")
		if sep == -1:
			break
		var block  := buffer.substr(0, sep)
		buffer      = buffer.substr(sep + 2)
		if gen_id != _gen_id:
			break
		var event_type := ""
		var data_str   := ""
		for line in block.split("\n"):
			if line.begins_with("event: "):
				event_type = line.substr(7).strip_edges()
			elif line.begins_with("data: "):
				data_str = line.substr(6).strip_edges()
		if data_str.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(data_str)
		if not (parsed is Dictionary):
			continue
		var data := parsed as Dictionary
		var resp_rid := str(data.get("request_id", ""))
		if not expected_rid.is_empty() and not resp_rid.is_empty() and resp_rid != expected_rid:
			print("[NPC] Dropped event '%s' — request_id mismatch (got %s, expected %s)" % [event_type, resp_rid, expected_rid])
			continue
		match event_type:
			"token":
				on_token.call(str(data.get("text", "")))
			"final":
				if gen_id == _gen_id:
					active_request_id = ""
				on_final.call(data)
			"error":
				if gen_id == _gen_id:
					active_request_id = ""
				on_error.call(str(data.get("error", "stream error")))
			"cancelled":
				pass   # server confirmed cancel; local gen_id already handled it
	return buffer
