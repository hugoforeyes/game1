extends Node
## MoralChoiceE2EPreview — the two-card ceremony against the LIVE backend:
## downloads /api/godot/runs/latest, finds chapter 1's real choice objective
## (with illustration_url per option from scene_choice_illustrations), presents
## the REAL MoralChoiceView, and lets it lazy-download both anime card
## paintings through ChapterFlow.download_image_texture. Asserts both cards
## mount real art, then confirms option A to screenshot the reveal.
##
## Run (windowed; needs SceneBuilder on :5001 with a packaged run):
##   /Applications/Godot.app/Contents/MacOS/Godot --path GameV1 res://tools/MoralChoiceE2EPreview.tscn

const MoralChoiceViewScript := preload("res://scripts/ui/MoralChoiceView.gd")

const SHOT_DIR := "/private/tmp/claude-501/-Users-dinhhuynh-Documents-FULLGAME/13b8760e-cdd2-49ba-a5c6-f7d8ea2de458/scratchpad/choice_v2"

var _failures: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await get_tree().process_frame
	await _run()
	if _failures.is_empty():
		print("[E2E] ALL PASS")
	else:
		print("[E2E] FAILURES: %s" % ", ".join(_failures))
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL %s" % label)


func _key(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s" % [SHOT_DIR, file_name])
	print("  [shot] %s" % file_name)


func _fetch_json(url_path: String) -> Variant:
	var request := HTTPRequest.new()
	add_child(request)
	if request.request(ChapterFlow.api_url(url_path)) != OK:
		request.queue_free()
		return null
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) >= 300:
		return null
	return JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())


func _run() -> void:
	print("[E2E] Two-card ceremony against the live backend")
	var flow: Variant = await _fetch_json("/api/godot/runs/latest")
	if not (flow is Dictionary):
		_check(false, "backend reachable (/api/godot/runs/latest)")
		return
	var quest: Dictionary = {}
	var objective: Dictionary = {}
	var choice_index := -1
	for chapter in (flow as Dictionary).get("chapters", []) as Array:
		if int((chapter as Dictionary).get("chapter", 0)) != 1:
			continue
		for raw_quest in (chapter as Dictionary).get("quests", []) as Array:
			var objectives: Array = (raw_quest as Dictionary).get("objectives", []) as Array
			for index in range(objectives.size()):
				var raw_objective: Dictionary = objectives[index] as Dictionary
				if str(raw_objective.get("kind", "")) == "choice":
					quest = raw_quest as Dictionary
					objective = raw_objective
					choice_index = index
					break
			if choice_index >= 0:
				break
	_check(choice_index >= 0, "chapter 1 has a choice objective")
	if choice_index < 0:
		return
	var options: Array = objective.get("options", []) as Array
	var with_urls := 0
	for option in options:
		if not str((option as Dictionary).get("illustration_url", "")).is_empty():
			with_urls += 1
	_check(with_urls == options.size() and with_urls >= 2,
		"every option carries illustration_url (%d/%d)" % [with_urls, options.size()])

	# Seed QuestManager so resolve_quest_choice works on the real data shape.
	QuestManager.quests = [quest]
	QuestManager.quest_states = {
		str(quest.get("id", "")): {
			"state": "active", "objective_index": choice_index, "progress": 0, "choices": {},
		},
	}
	QuestManager.current_zone_id = str(objective.get("zone_id", ""))
	QuestManager._ensure_ui()

	var view: CanvasLayer = MoralChoiceViewScript.new()
	get_tree().root.add_child(view)
	view.present({"quest": quest, "objective": objective}, "Đại Úy Roland")

	# Both cards must mount REAL downloaded art (lazy path, no prefetch here).
	var mounted := 0
	for _i in range(200):  # up to ~10s for two downloads
		await get_tree().process_frame
		mounted = 0
		var cards: Array = view.get("_cards") as Array
		for card in cards:
			if ((card as Dictionary).get("image") as TextureRect).texture != null:
				mounted += 1
		if mounted >= 2:
			break
		await get_tree().create_timer(0.05).timeout
	_check(mounted >= 2, "both cards downloaded real illustrations (got %d)" % mounted)

	await get_tree().create_timer(1.2).timeout  # typewriter + fade-ins settle
	await _shot("e2e_choice_real.png")

	_key(KEY_ENTER)
	await get_tree().create_timer(0.25).timeout
	_key(KEY_ENTER)
	await get_tree().create_timer(1.8).timeout
	_check(not QuestManager.last_choice_result.is_empty(), "real choice resolved")
	await _shot("e2e_reveal_real.png")
	_key(KEY_ENTER)
	await get_tree().create_timer(0.6).timeout
