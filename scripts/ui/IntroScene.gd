extends Control

const START_SCENE_PATH   := "res://scenes/ui/StartScene.tscn"
const DESKTOP_VIDEO_PATH := "res://assets/intro/intro.ogv"
const WEB_VIDEO_FILE     := "intro.webm"
const BUFFER_MS          := 800

@onready var video_player: VideoStreamPlayer = $VideoPlayer

# Strong reference — prevents GC from collecting the JS callback
var _js_finish_cb: JavaScriptObject = null

func _ready() -> void:
	if OS.get_name() == "Web":
		_play_web_video()
	else:
		_play_desktop_video()

# ── Web ───────────────────────────────────────────────────────────────────────

func _play_web_video() -> void:
	# Create a GDScript-side callback that JS will invoke when the intro ends.
	# Keeping _js_finish_cb as a member prevents it from being garbage-collected.
	_js_finish_cb = JavaScriptBridge.create_callback(_on_js_intro_finished)

	# Expose it on window so the inline JS can reach it
	JavaScriptBridge.get_interface("window").set("__gdIntroFinish", _js_finish_cb)

	JavaScriptBridge.eval("""
		(function () {
			var canvas = document.getElementById('canvas');
			if (canvas) canvas.style.visibility = 'hidden';

			function finish() {
				var el = document.getElementById('__intro');
				if (el) el.parentNode.removeChild(el);
				var gate = document.getElementById('__intro_gate');
				if (gate) gate.parentNode.removeChild(gate);
				if (canvas) {
					canvas.style.visibility = 'visible';
					canvas.tabIndex = 0;
					canvas.focus();
				}
				// Hand control back on the next browser frame after focus is restored.
				requestAnimationFrame(function () {
					if (typeof window.__gdIntroFinish === 'function') {
						window.__gdIntroFinish();
					}
				});
			}

			function startVideo() {
				var gate = document.getElementById('__intro_gate');
				if (gate) gate.parentNode.removeChild(gate);

				var v = document.createElement('video');
				v.id          = '__intro';
				v.src         = '%s';
				v.playsInline = true;
				v.style.cssText =
					'position:fixed;top:0;left:0;width:100%%;height:100%%;' +
					'z-index:2147483647;background:#000;object-fit:contain;cursor:pointer;';

				v.onended = finish;
				v.onerror = finish;
				v.onclick = finish;
				document.addEventListener('keydown', function onKey() {
					document.removeEventListener('keydown', onKey);
					finish();
				});

				document.body.appendChild(v);
				v.play();
			}

			// Gate screen — satisfies browser autoplay policy
			var gate = document.createElement('div');
			gate.id = '__intro_gate';
			gate.style.cssText =
				'position:fixed;top:0;left:0;width:100%%;height:100%%;' +
				'z-index:2147483647;background:#000;display:flex;' +
				'align-items:center;justify-content:center;cursor:pointer;';

			var btn = document.createElement('div');
			btn.innerText = '\\u25b6  Press any key or click to start';
			btn.style.cssText =
				'color:#fff;font-size:16px;font-family:sans-serif;opacity:0;' +
				'transition:opacity 0.8s;pointer-events:none;letter-spacing:1px;';
			gate.appendChild(btn);
			document.body.appendChild(gate);

			setTimeout(function () { btn.style.opacity = '0.75'; }, 400);

			gate.addEventListener('click', startVideo, { once: true });
			document.addEventListener('keydown', function onGateKey() {
				document.removeEventListener('keydown', onGateKey);
				startVideo();
			}, { once: true });
		})();
	""" % WEB_VIDEO_FILE, true)

# Called by JavaScript via __gdIntroFinish() when the video ends/errors/is skipped
func _on_js_intro_finished(_args: Array) -> void:
	_js_finish_cb = null   # release the callback
	_go_to_start()

# ── Desktop fallback ──────────────────────────────────────────────────────────

func _play_desktop_video() -> void:
	var stream := load(DESKTOP_VIDEO_PATH) as VideoStream
	if stream == null:
		_go_to_start()
		return
	video_player.buffering_msec = BUFFER_MS
	video_player.stream = stream
	video_player.finished.connect(_on_video_finished)
	await get_tree().process_frame
	await get_tree().process_frame
	video_player.play()

func _unhandled_input(event: InputEvent) -> void:
	if OS.get_name() != "Web" and event.is_pressed():
		_go_to_start()

func _on_video_finished() -> void:
	_go_to_start()

# ── Shared ────────────────────────────────────────────────────────────────────

func _go_to_start() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	get_tree().change_scene_to_file(START_SCENE_PATH)
