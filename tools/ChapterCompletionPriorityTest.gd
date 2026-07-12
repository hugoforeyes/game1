extends Node
## Regression: chapter completion is a final ceremony and must stay queued behind
## cutscene queues, active CutscenePlayer cleanup, and conversation rewards.

var pending_narrative := false

func has_pending_narrative_playback() -> bool:
	return pending_narrative

func _ready() -> void:
	add_to_group("narrative_playback_owner")
	GameManager.ui_blocking_input = false
	AnnouncementCenter.reset()
	AnnouncementCenter.set_conversation_active(true)
	assert(AnnouncementCenter.enqueue("objective", {"title": "Objective"}))
	assert(AnnouncementCenter.enqueue("item", {"items": [{"item_id": "item_test", "name": "Item"}]}))
	var ordered := AnnouncementCenter._flush_sorted()
	assert(str((ordered[0] as Dictionary).get("kind", "")) == "item",
		"item ceremony must be ordered before objective ceremony")
	assert(str((ordered[1] as Dictionary).get("kind", "")) == "objective")
	AnnouncementCenter.reset()
	ChapterFlow._pending_celebration = {"chapter": 1, "title": "Test"}

	pending_narrative = true
	ChapterFlow._process(0.0)
	assert(not ChapterFlow._pending_celebration.is_empty(), "Main's cutscene queue/action/teardown barrier must keep chapter completion pending")

	# Standalone objective ceremonies must wait behind the same cutscene barrier.
	AnnouncementCenter.set_conversation_active(true)
	assert(AnnouncementCenter.enqueue("objective", {"title": "Queued objective"}))
	AnnouncementCenter.set_conversation_active(false)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not AnnouncementCenter.playing, "objective ceremony must not start before the cutscene")
	assert(AnnouncementCenter.has_pending(), "deferred objective ceremony must remain queued")
	AnnouncementCenter.reset()
	await get_tree().process_frame

	AnnouncementCenter.set_conversation_active(true)
	assert(AnnouncementCenter.enqueue("quest_complete", {"title": "Queued reward"}))
	pending_narrative = false
	ChapterFlow._process(0.0)
	assert(not ChapterFlow._pending_celebration.is_empty(), "queued reward ceremony must run before chapter completion")

	# Cleanup without releasing the synthetic reward into a real UI ceremony.
	AnnouncementCenter.reset()
	ChapterFlow._pending_celebration = {}
	ChapterFlow.set_process(false)
	GameManager.ui_blocking_input = false
	print("[ChapterCompletionPriorityTest] cutscene, cleanup, and reward priority barriers passed")
	get_tree().quit()
