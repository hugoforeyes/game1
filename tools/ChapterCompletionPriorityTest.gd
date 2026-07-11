extends Node
## Regression: chapter completion is a final ceremony and must stay queued behind
## cutscene queues, active CutscenePlayer cleanup, and conversation rewards.

var pending_narrative := false

func has_pending_narrative_playback() -> bool:
	return pending_narrative

func _ready() -> void:
	GameManager.ui_blocking_input = false
	AnnouncementCenter.reset()
	ChapterFlow._pending_celebration = {"chapter": 1, "title": "Test"}

	pending_narrative = true
	ChapterFlow._process(0.0)
	assert(not ChapterFlow._pending_celebration.is_empty(), "Main's cutscene queue/action/teardown barrier must keep chapter completion pending")

	pending_narrative = false
	AnnouncementCenter.set_conversation_active(true)
	assert(AnnouncementCenter.enqueue("quest_complete", {"title": "Queued reward"}))
	ChapterFlow._process(0.0)
	assert(not ChapterFlow._pending_celebration.is_empty(), "queued reward ceremony must run before chapter completion")

	# Cleanup without releasing the synthetic reward into a real UI ceremony.
	AnnouncementCenter.reset()
	ChapterFlow._pending_celebration = {}
	ChapterFlow.set_process(false)
	GameManager.ui_blocking_input = false
	print("[ChapterCompletionPriorityTest] cutscene, cleanup, and reward priority barriers passed")
	get_tree().quit()
