extends Node
## AnnouncementCenter — the in-conversation reward ceremony.
##
## While the player is talking to an NPC, reward events (new quest / objective /
## quest complete / hint / item / companion join) do NOT show as corner toasts.
## They queue here; ChatBox hides the conversation, each announcement plays as a
## full-screen ceremony one at a time, and the conversation then returns exactly
## where it was. Outside conversations enqueue() refuses and every caller falls
## back to its existing toast/popup behavior, so nothing changes in the open world.

const AnnouncementViewScript := preload("res://scripts/ui/AnnouncementView.gd")
const ObjectInteractionViewScript := preload("res://scripts/ui/ObjectInteractionView.gd")

## Narrative playback order (stable within a kind): acquired items are revealed
## before their resulting quest/objective updates; companion remains the finale.
const KIND_PRIORITY := {
	"item": 0,
	"new_quest": 1,
	"objective": 2,
	"quest_complete": 3,
	"hint": 4,
	"companion": 5,
}
const MAX_ITEMS_PER_SCREEN := 4
const BREATH_BETWEEN := 0.10

var conversation_active: bool = false
var playing: bool = false
var _queue: Array = []
var _standalone_waiting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	_queue.clear()
	conversation_active = false
	_standalone_waiting = false


## ChatBox marks the conversation window. Closing a conversation that still has
## queued rewards (e.g. a quest completing on the goodbye beat) plays them as a
## standalone ceremony right after the chat disappears.
func set_conversation_active(active: bool) -> void:
	conversation_active = active
	if not active and has_pending() and not playing and not _standalone_waiting:
		_play_standalone()


## Accepts the event only while a conversation (or a running ceremony) owns the
## screen; returns false so the caller falls back to its toast/popup.
func enqueue(kind: String, payload: Dictionary) -> bool:
	if not conversation_active and not playing:
		return false
	if not KIND_PRIORITY.has(kind):
		return false
	var entry := payload.duplicate(true)
	entry["kind"] = kind
	_queue.append(entry)
	return true


func has_pending() -> bool:
	return not _queue.is_empty()


## Drop every still-queued "objective" ceremony for one quest. QuestManager calls
## this when a quest advances several objectives in a single beat (e.g. talk-to-NPC
## completes a talk objective and immediately settles the next collect objective)
## so only the newest objective plays instead of a flicker of intermediate ones.
func drop_pending_objectives(quest_id: String) -> void:
	if quest_id.is_empty():
		return
	var kept: Array = []
	for entry in _queue:
		if str((entry as Dictionary).get("kind", "")) == "objective" \
				and str(((entry as Dictionary).get("quest", {}) as Dictionary).get("id", "")) == quest_id:
			continue
		kept.append(entry)
	_queue = kept


## Play every queued announcement, one at a time; returns when the queue is
## drained (awaitable from ChatBox). Player input stays blocked throughout;
## afterwards the blocking flag is left to the conversation if one is open.
func play_queue() -> void:
	if playing:
		while playing:
			await get_tree().process_frame
		return
	# A cutscene is the higher-priority story beat. Keep every queued objective /
	# reward ceremony intact until its action, letterbox and camera teardown finish.
	while CutsceneDirector.has_pending_playback():
		if _queue.is_empty():
			return
		await get_tree().process_frame
	# Another caller may have been waiting on the same cutscene barrier.
	if playing:
		while playing:
			await get_tree().process_frame
		return
	playing = true
	GameManager.ui_blocking_input = true
	while not _queue.is_empty():
		for entry in _flush_sorted():
			await _present(entry as Dictionary)
			GameManager.ui_blocking_input = true
			await get_tree().create_timer(BREATH_BETWEEN).timeout
	playing = false
	GameManager.ui_blocking_input = conversation_active


func _play_standalone() -> void:
	_standalone_waiting = true
	while CutsceneDirector.has_pending_playback():
		if conversation_active or not has_pending():
			_standalone_waiting = false
			return
		await get_tree().process_frame
	if conversation_active or not has_pending():
		_standalone_waiting = false
		return
	await play_queue()
	_standalone_waiting = false


## Drain the queue into playback order: stable-sort by kind priority, then
## collapse every "item" entry into combined card screens (≤4 cards each,
## duplicate item ids merged) so one visit to the item ceremony shows the haul.
func _flush_sorted() -> Array:
	var entries := _queue
	_queue = []
	var order := range(entries.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa: int = int(KIND_PRIORITY.get(str((entries[a] as Dictionary).get("kind", "")), 9))
		var pb: int = int(KIND_PRIORITY.get(str((entries[b] as Dictionary).get("kind", "")), 9))
		if pa == pb:
			return a < b
		return pa < pb)

	var result: Array = []
	var item_cards: Array = []
	var item_screens_at := -1
	for index in order:
		var entry: Dictionary = entries[index] as Dictionary
		if str(entry.get("kind", "")) == "item":
			if item_screens_at < 0:
				item_screens_at = result.size()
			for card in entry.get("items", []) as Array:
				if card is Dictionary:
					_merge_item_card(item_cards, card as Dictionary)
		else:
			result.append(entry)

	if not item_cards.is_empty():
		var screens: Array = []
		for start in range(0, item_cards.size(), MAX_ITEMS_PER_SCREEN):
			screens.append({
				"kind": "item",
				"items": item_cards.slice(start, start + MAX_ITEMS_PER_SCREEN),
			})
		var insert_at := clampi(item_screens_at, 0, result.size())
		for offset in range(screens.size()):
			result.insert(insert_at + offset, screens[offset])
	return result


func _merge_item_card(cards: Array, card: Dictionary) -> void:
	var item_id := str(card.get("item_id", ""))
	for existing in cards:
		if str((existing as Dictionary).get("item_id", "")) == item_id and not item_id.is_empty():
			(existing as Dictionary)["count"] = int((existing as Dictionary).get("count", 1)) + int(card.get("count", 1))
			return
	cards.append(card.duplicate(true))


func _present(entry: Dictionary) -> void:
	if str(entry.get("kind", "")) == "item":
		var item_view: CanvasLayer = ObjectInteractionViewScript.new()
		get_tree().root.add_child(item_view)
		item_view.layer = 70
		item_view.open_item_announcement(entry.get("items", []) as Array)
		await item_view.closed
	else:
		var view: CanvasLayer = AnnouncementViewScript.new()
		get_tree().root.add_child(view)
		view.present(entry)
		await view.dismissed
