extends Node2D
## Dev-only smoke for the in-conversation reward-ceremony flow:
##   - rewards earned during an open ChatBox queue in AnnouncementCenter
##   - when the line finishes revealing, the chat HIDES and ceremonies play
##     one at a time, quest banner BEFORE item reveal (priority order)
##   - dismissing them brings the conversation back with its options intact
##   - closing a conversation with rewards still queued plays them standalone
## Exit code 0 = all pass, 1 = a failure. Needs the SceneBuilder server on :5001.

const ChatBoxScene := preload("res://scenes/ui/ChatBox.tscn")
const AnnouncementViewScript := preload("res://scripts/ui/AnnouncementView.gd")
const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")

var _failures := 0
var _item_id := ""


func _ready() -> void:
	var flow: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapter: Dictionary = (flow.get("chapters", []) as Array)[0] as Dictionary
	InventoryManager.load_chapter_catalog(chapter.get("items", {}) as Dictionary, null)
	for item in InventoryManager.catalog:
		if item is Dictionary and not str((item as Dictionary).get("id", "")).is_empty():
			_item_id = str((item as Dictionary).get("id"))
			break
	_check(not _item_id.is_empty(), "found a catalog item to grant")

	await _test_mid_conversation_ceremony()
	await _test_close_with_pending()
	_finish()


func _test_mid_conversation_ceremony() -> void:
	print("\n--- TEST 1: reward mid-conversation → chat hides, ceremonies play in order, chat returns ---")
	var chatbox: CanvasLayer = ChatBoxScene.instantiate()
	get_tree().root.add_child(chatbox)
	var tree := {
		"start_node": "root",
		"nodes": [{
			"id": "root",
			"npc_line": "Cầm lấy món quà này, con của rừng thẳm.",
			"options": [
				{"player_text": "Cảm ơn bà.", "goto": "__end__"},
				{"player_text": "Bà là ai?", "goto": "root"},
			],
		}],
	}
	chatbox.open_tree("Bà Miên", {"id": "npc_smoke"}, tree)
	_check(AnnouncementCenter.conversation_active, "opening the chat marks the conversation active")

	# a reward lands while the NPC line is still typing out
	InventoryManager.add_item(_item_id, 3)
	_check(AnnouncementCenter.has_pending(), "the item was queued as a ceremony, not a toast")
	# a quest banner enqueued AFTER the item must still play FIRST (priority)
	AnnouncementCenter.enqueue("new_quest", {"quest": {"title": "Tiếng Gọi Rừng Thẳm", "type": "main"}})

	var hid := await _wait_until(func() -> bool: return not chatbox.visible, 6.0)
	_check(hid, "the chat screen hid once the line finished revealing")
	var first: Node = await _wait_for_ceremony(3.0)
	_check(first != null and first.get_script() == AnnouncementViewScript,
		"the NEW QUEST banner plays before the item reveal (priority order)")
	await _shot("/tmp/announce_flow_quest.png")
	await _dismiss_and_free(first)

	var second: Node = await _wait_for_ceremony(3.0)
	_check(second != null and second.get_script() == ObjectInteractionViewScript,
		"the item ceremony plays second")
	await _shot("/tmp/announce_flow_item.png")
	await _dismiss_and_free(second)

	var back := await _wait_until(func() -> bool: return chatbox.visible, 4.0)
	_check(back, "the conversation came back after the ceremonies")
	var options_visible := await _wait_until(func() -> bool: return chatbox._opt_container.visible, 3.0)
	_check(options_visible, "the dialogue options are showing again (state restored)")
	_check(GameManager.ui_blocking_input, "player input is still blocked by the open conversation")
	await _shot("/tmp/announce_flow_back.png")

	chatbox.close()
	await get_tree().create_timer(0.3).timeout
	_check(not AnnouncementCenter.conversation_active, "closing the chat clears conversation_active")
	_check(not GameManager.ui_blocking_input, "closing the chat unblocks input")


func _test_close_with_pending() -> void:
	print("\n--- TEST 2: closing the conversation with rewards still queued plays them standalone ---")
	var chatbox: CanvasLayer = ChatBoxScene.instantiate()
	get_tree().root.add_child(chatbox)
	var tree := {
		"start_node": "root",
		"nodes": [{"id": "root", "npc_line": "Tạm biệt.", "options": []}],
	}
	chatbox.open_tree("Bà Miên", {"id": "npc_smoke_2"}, tree)
	InventoryManager.add_item(_item_id, 1)
	_check(AnnouncementCenter.has_pending(), "reward queued during the goodbye beat")
	chatbox.close()
	var view: Node = await _wait_for_ceremony(3.0)
	_check(view != null, "a standalone ceremony plays right after the chat closes")
	_check(GameManager.ui_blocking_input, "input stays blocked while the standalone ceremony is up")
	await _dismiss_and_free(view)
	var unblocked := await _wait_until(func() -> bool: return not GameManager.ui_blocking_input, 3.0)
	_check(unblocked, "input unblocks once the standalone queue drains")


# ── plumbing ────────────────────────────────────────────────────────────────────


func _find_ceremony() -> Node:
	for child in get_tree().root.get_children():
		if child.get_script() == AnnouncementViewScript:
			return child
		if child.get_script() == ObjectInteractionViewScript and child.get("_announce_mode") == true:
			return child
	return null


func _wait_for_ceremony(timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var view := _find_ceremony()
		if view != null:
			return view
		await get_tree().process_frame
	return null


func _dismiss_and_free(view: Node) -> void:
	# wait out the input grace, then confirm and wait until it leaves the tree
	await get_tree().create_timer(0.6).timeout
	if view.get_script() == AnnouncementViewScript:
		view._dismiss()
	else:
		view._activate_primary()
	await _wait_until(func() -> bool: return not is_instance_valid(view) or not view.is_inside_tree(), 3.0)
	await get_tree().create_timer(0.25).timeout  # breath between ceremonies


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[AnnounceFlowSmoke] saved %s" % path)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("\n[AnnounceFlowSmoke] ALL PASS")
	else:
		print("\n[AnnounceFlowSmoke] FAILED (%d failure(s))" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
