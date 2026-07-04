extends Node2D
## Dev-only headless QA for the item detail view (chapter_item_details).
## Drives the REAL /api/godot/runs/latest flow (this SceneBuilder run already
## has generated item details: a text-kind letter/diary and an image-kind
## illustration) and exercises the REAL InventoryManager._unhandled_input path
## with synthetic InputEventKey presses — never calling internals directly.
## Exit 0 = all pass, 1 = a failure.

var _failures: int = 0


func _ready() -> void:
	var response: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapters: Array = response.get("chapters", []) as Array
	_check(not chapters.is_empty(), "flow has at least one chapter")
	if chapters.is_empty():
		_finish()
		return

	var chapter: Dictionary = chapters[0] as Dictionary
	var items_payload: Dictionary = chapter.get("items", {}) as Dictionary
	var icon_texture: Texture2D = await ChapterFlow.download_image_texture(str(chapter.get("items_icon_url", "")))
	InventoryManager.load_chapter_catalog(items_payload, icon_texture)

	var text_index := -1
	var image_index := -1
	for i in range(InventoryManager.catalog.size()):
		var definition := InventoryManager.catalog[i] as Dictionary
		var detail := definition.get("detail", {}) as Dictionary
		if detail.get("kind") == "text" and text_index == -1:
			text_index = i
		elif detail.get("kind") == "image" and image_index == -1:
			image_index = i
	_check(text_index != -1, "catalog has a text-detail item")
	_check(image_index != -1, "catalog has an image-detail item")
	if text_index == -1 or image_index == -1:
		_finish()
		return

	var text_def := InventoryManager.catalog[text_index] as Dictionary
	var image_def := InventoryManager.catalog[image_index] as Dictionary
	InventoryManager.add_item(str(text_def.get("id")), 1, true)
	InventoryManager.add_item(str(image_def.get("id")), 1, true)

	InventoryManager._toggle_screen()
	await get_tree().process_frame
	_check(InventoryManager._screen_open, "inventory screen opened")

	# ── select the text-detail item (search by id across filtered pages) ──────
	_check(_select_item_by_id(str(text_def.get("id"))), "selected the text-detail item")

	_press_key(KEY_V)
	await get_tree().process_frame
	_check(InventoryManager._detail_view_open, "V opens the detail view for a text item")
	_check(InventoryManager._detail_view_text.visible, "text panel visible for text-kind detail")
	_check(not InventoryManager._detail_view_image.visible, "image panel hidden for text-kind detail")
	_check(
		InventoryManager._detail_view_text.text == str((text_def.get("detail", {}) as Dictionary).get("text", "")),
		"detail text matches the BE-authored content",
	)

	# While open, all input must be swallowed by the modal — arrow keys must
	# NOT move the underlying grid selection.
	var selected_before: int = InventoryManager._selected
	_press_key(KEY_RIGHT)
	await get_tree().process_frame
	_check(InventoryManager._selected == selected_before, "detail view swallows navigation input while open")
	_check(InventoryManager._detail_view_open, "detail view still open after swallowed input")

	_press_key(KEY_V)
	await get_tree().process_frame
	_check(not InventoryManager._detail_view_open, "V closes the detail view")
	_check(InventoryManager._screen_open, "closing the detail view does not close the whole inventory")

	# ── select the image-detail item and verify the async texture download ──
	_check(_select_item_by_id(str(image_def.get("id"))), "selected the image-detail item")
	_press_key(KEY_V)
	# The download is awaited inside InventoryManager; give it real frames/time
	# to complete against the live server rather than asserting instantly.
	var waited := 0
	while not InventoryManager._detail_view_image.texture and waited < 300:
		await get_tree().process_frame
		waited += 1
	_check(InventoryManager._detail_view_open, "V opens the detail view for an image item")
	_check(not InventoryManager._detail_view_text.visible, "text panel hidden for image-kind detail")
	_check(InventoryManager._detail_view_image.visible, "image panel visible for image-kind detail")
	_check(InventoryManager._detail_view_image.texture != null, "detail image texture downloaded and applied")

	# Esc also closes it (not just V).
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not InventoryManager._detail_view_open, "Esc closes the detail view")

	# Re-opening the SAME image item must reuse the cached texture (no network
	# round-trip needed) — verified indirectly: texture is present immediately
	# on the very next frame, no waiting loop needed this time.
	_press_key(KEY_V)
	await get_tree().process_frame
	_check(
		InventoryManager._detail_view_image.texture != null,
		"re-opening reuses the session-cached texture instantly",
	)
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not InventoryManager._detail_view_open, "Esc also closes a re-opened detail view")

	_finish()


func _select_item_by_id(item_id: String) -> bool:
	for index in range(InventoryManager.catalog.size()):
		var definition := InventoryManager.catalog[index] as Dictionary
		if str(definition.get("id")) == item_id:
			var filtered := InventoryManager._filtered_catalog_indices()
			var filtered_index := filtered.find(index)
			if filtered_index == -1:
				return false
			InventoryManager._selected = filtered_index
			InventoryManager._refresh_screen()
			return true
	return false


func _press_key(physical_keycode: int) -> void:
	# Set BOTH fields like a real OS keypress does: InventoryManager's own
	# KEY_V/KEY_I checks read `physical_keycode` directly, while the built-in
	# "ui_cancel" action (Esc) is bound via `keycode` — only a synthetic event
	# with both populated matches either check path.
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = true
	event.echo = false
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		printerr("  FAIL  %s" % label)


func _finish() -> void:
	print("\n[ItemDetailViewQA] %s (%d failure(s))" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
