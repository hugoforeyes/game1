extends Node2D
## Scripted QA for WorldMapView: drives the REAL set_data/_state_of/handle_input
## logic (not a reimplementation) against a synthetic 5-chapter world, checking
## the lock/available/completed/current state machine and the two-step
## confirm-before-travel interaction, then captures a screenshot for a visual
## AAA-quality sanity check.

const WorldMapViewScript := preload("res://scripts/ui/WorldMapView.gd")

var _view: WorldMapView
var _travel_requests: Array[int] = []


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.05, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_view = WorldMapViewScript.new()
	add_child(_view)
	_view.travel_requested.connect(func(n): _travel_requests.append(n))

	_view.set_data({
		"current_chapter_number": 3,
		"chapters": [
			{"chapter_number": 1, "title": "Làng Rễ Bình Minh"},
			{"chapter_number": 2, "title": "Rừng Lá Hóa Đá"},
			{"chapter_number": 3, "title": "Thành Cổ Ngủ Quên"},
			{"chapter_number": 4, "title": "Vực Sâu Sương Mù"},
			{"chapter_number": 5, "title": "Đỉnh Trời Tàn Lụi"},
		],
		"completed_chapter_numbers": {"1": true, "2": true},
	})
	await get_tree().process_frame

	assert(_view._state_of(1) == "completed", "chapter 1 should be completed")
	assert(_view._state_of(2) == "completed", "chapter 2 should be completed")
	assert(_view._state_of(3) == "current", "chapter 3 (current, not yet completed) should be 'current'")
	assert(_view._state_of(4) == "locked", "chapter 4 must stay locked until chapter 3 is completed")
	assert(_view._state_of(5) == "locked", "chapter 5 must stay locked (transitively)")
	print("[WorldMapQA] OK: lock/available/completed/current state machine correct")

	assert(_view._selected_index == 2, "cursor should start on the current chapter (index 2 = chapter 3)")
	print("[WorldMapQA] OK: cursor starts on the current chapter")

	# Move right onto the locked chapter 4 -> Enter must be a no-op (no confirm, no travel).
	_view.handle_input(_key_event(KEY_RIGHT))
	_view.handle_input(_key_event(KEY_ENTER))
	assert(not _view._confirm_pending, "Enter on a locked chapter must not start a confirmation")
	assert(_travel_requests.is_empty(), "must not be able to travel to a locked chapter")
	print("[WorldMapQA] OK: locked chapter rejects travel")

	# Back to chapter 3 (current) -> Enter must also be a no-op (already here).
	_view.handle_input(_key_event(KEY_LEFT))
	_view.handle_input(_key_event(KEY_ENTER))
	assert(not _view._confirm_pending, "Enter on the CURRENT chapter must not start a confirmation")
	assert(_travel_requests.is_empty())
	print("[WorldMapQA] OK: current chapter rejects self-travel")

	# Chapter 2 (completed, not current) -> Enter requires TWO presses to travel.
	_view.handle_input(_key_event(KEY_LEFT))
	_view.handle_input(_key_event(KEY_ENTER))
	assert(_view._confirm_pending, "first Enter on a travelable chapter must arm the confirmation")
	assert(_travel_requests.is_empty(), "must NOT travel on the first Enter")
	print("[WorldMapQA] OK: first Enter arms confirmation, does not travel yet")

	_view.handle_input(_key_event(KEY_ENTER))
	assert(_travel_requests == [2], "second Enter must confirm travel to chapter 2, got %s" % [_travel_requests])
	print("[WorldMapQA] OK: second Enter confirms travel -> travel_requested(2)")

	# Moving the cursor should cancel any pending confirmation (safety: an accidental
	# stray Enter later must not silently travel).
	_view.handle_input(_key_event(KEY_LEFT))
	_view.handle_input(_key_event(KEY_ENTER))
	assert(_view._confirm_pending)
	_view.handle_input(_key_event(KEY_RIGHT))
	assert(not _view._confirm_pending, "moving the cursor must cancel a pending confirmation")
	print("[WorldMapQA] OK: moving the cursor cancels a pending confirmation")

	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://tools/qa_world_map.png")
	)
	print("[WorldMapQA] wrote qa_world_map.png")

	# Second pass: the REAL generated illustration + REAL LLM-vision chapter
	# positions from this run (outputs/20260629_143055/world_map_illustration),
	# with real chapter titles — a genuine end-to-end visual check, not just the
	# synthetic-data logic pass above.
	if ResourceLoader.exists("res://tools/qa_world_map_illustration.png"):
		var real_bg := load("res://tools/qa_world_map_illustration.png") as Texture2D
		_view.set_data({
			"current_chapter_number": 3,
			"chapters": [
				{"chapter_number": 1, "title": "Tiếng Hát Cuối Cùng Của Rừng", "x_normalized": 0.1629, "y_normalized": 0.3812},
				{"chapter_number": 2, "title": "Thư Viện Của Lá Rơi", "x_normalized": 0.5114, "y_normalized": 0.2981},
				{"chapter_number": 3, "title": "Thành Phố Trên Tán Lá Gãy", "x_normalized": 0.7264, "y_normalized": 0.4057},
				{"chapter_number": 4, "title": "Mùa Xuân Bị Lãng Quên", "x_normalized": 0.8632, "y_normalized": 0.3079},
				{"chapter_number": 5, "title": "Hạt Giống Bình Minh", "x_normalized": 0.9218, "y_normalized": 0.694},
			],
			"completed_chapter_numbers": {"1": true, "2": true},
			"background_texture": real_bg,
		})
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://tools/qa_world_map_real.png")
		)
		print("[WorldMapQA] wrote qa_world_map_real.png (real illustration + real LLM-vision positions)")
	else:
		print("[WorldMapQA] no real illustration found at tools/qa_world_map_illustration.png, skipping real-data visual pass")

	print("[WorldMapQA] ALL CHECKS PASSED")
	get_tree().quit()


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = false
	return event
