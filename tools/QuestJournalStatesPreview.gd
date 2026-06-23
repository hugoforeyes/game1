extends Node
## Renders the Quest Journal in several states to catch edge-case layout/text bugs.

const JournalViewScript = preload("res://scripts/ui/QuestJournalView.gd")
const PreviewData = preload("res://tools/QuestJournalUiPreview.gd")


func _ready() -> void:
	var data := PreviewData.new()
	var states := [
		{"name": "side", "cat": 1, "sel": 1, "track": "quest_side"},
		{"name": "completed", "cat": 2, "sel": 3, "track": "quest_done"},
	]
	for entry in states:
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.10, 0.14, 1.0)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var ui := CanvasLayer.new()
		ui.transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))
		add_child(ui)
		var journal = JournalViewScript.new()
		ui.add_child(journal)
		journal.set_data(data._quests(), data._states(), data._hints(), str(entry["track"]), "CHƯƠNG 04  ·  MIỀN ĐẤT CHƯA BIẾT")
		journal.category_index = int(entry["cat"])
		journal.selected_index = int(entry["sel"])
		journal._rebuild_visible_indices()
		journal._render()
		await get_tree().process_frame
		await get_tree().process_frame
		var out := "res://assets/ui/quest_journal_v2/preview_%s.png" % str(entry["name"])
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(out))
		print("[states] wrote %s" % out)
		ui.queue_free()
		bg.queue_free()
		await get_tree().process_frame
	get_tree().quit()
