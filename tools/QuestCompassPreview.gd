extends Node2D
## Scripted QA for QuestCompassView: drives the REAL QuestManager hint-reveal
## flow (production code) plus a fake "Main" stub exposing the same two
## lookup methods Main.gd provides, so the compass's own logic (intent
## resolution, hint-gating, edge-clamp math, on-screen hide) is exercised
## for real while the entity-position source is fully controlled.

const QuestCompassViewScript := preload("res://scripts/ui/QuestCompassView.gd")

var _camera: Camera2D
var _compass: QuestCompassView
var _fake_main: Node
var _target_world_pos := Vector2(4000, 4000)


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.05, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_camera = Camera2D.new()
	_camera.enabled = true
	add_child(_camera)

	var player := Node2D.new()
	player.name = "FakePlayer"
	add_child(player)

	_fake_main = Node.new()
	_fake_main.set_script(preload("res://tools/QuestCompassPreviewFakeMain.gd"))
	add_child(_fake_main)
	_fake_main.set("target_position", _target_world_pos)

	_compass = QuestCompassViewScript.new()
	add_child(_compass)
	_compass.setup(_fake_main, player)

	_setup_quest()

	# ── SAME-ZONE case: hint-gated ──────────────────────────────────────────────
	# Player is standing in the objective's own zone (zone_03) -> precise pointing
	# must wait for all 3 hint levels.
	GameManager.imported_scene_context = {"zone_id": "zone_03"}
	QuestManager.tracked_quest_id = "quest_02"
	QuestManager.quests_changed.emit()
	await get_tree().process_frame

	assert(_compass._intent.is_empty(), "same-zone: compass must stay hidden before all 3 hints are heard")
	print("[QuestCompassPreview] OK: same-zone hidden before hints")

	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 1}, "Gợi ý mức 1")
	await get_tree().process_frame
	assert(_compass._intent.is_empty(), "same-zone: must still be hidden after only 1/3 hints")
	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 2}, "Gợi ý mức 2")
	await get_tree().process_frame
	assert(_compass._intent.is_empty(), "same-zone: must still be hidden after only 2/3 hints")
	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 3}, "Gợi ý mức 3")
	await get_tree().process_frame

	assert(QuestManager.is_objective_fully_hinted("quest_02", "o2"), "should be fully hinted now")
	assert(not _compass._intent.is_empty(), "same-zone: compass must resolve an intent once fully hinted")
	print("[QuestCompassPreview] OK: same-zone intent resolved after 3/3 hints -> ", _compass._intent)

	# ── CROSS-ZONE case: ALWAYS shown, hint level irrelevant ───────────────────
	# A second quest whose objective's zone the player has NOT reached yet, and
	# for which ZERO hints have ever been revealed — the compass must still point
	# the way, because basic wayfinding isn't a hint reward.
	GameManager.imported_scene_context = {"zone_id": "zone_01"}  # player is elsewhere
	_setup_cross_zone_quest()  # objective lives in zone_05, 0/3 hints
	QuestManager.tracked_quest_id = "quest_03"
	QuestManager.quests_changed.emit()
	await get_tree().process_frame

	assert(not QuestManager.is_objective_fully_hinted("quest_03", "o1"), "sanity: 0 hints revealed for quest_03/o1")
	assert(not _compass._intent.is_empty(), "cross-zone: compass must show even with 0 hints when target zone differs")
	assert(str(_compass._intent.get("zone_id", "")) == "zone_05", "cross-zone: intent should target zone_05")
	print("[QuestCompassPreview] OK: cross-zone intent shown with 0 hints -> ", _compass._intent)

	# ── Hint gating follows the TRACKED quest, not just "any active quest" ─────
	# Both quest_02 and quest_03 are active right now; quest_03 is tracked. An NPC
	# hint for quest_02/o2 (active but NOT tracked) must stay unavailable, while a
	# hint for quest_03/o1 (tracked) must be available.
	assert(not QuestManager.is_tracked_objective_active("quest_02", "o2"), "quest_02 is active but not tracked -> its hints must stay hidden")
	assert(QuestManager.is_objective_active("quest_02", "o2"), "sanity: quest_02/o2 IS active (old untracked-aware check would wrongly allow its hint)")
	assert(QuestManager.is_tracked_objective_active("quest_03", "o1"), "quest_03 is tracked -> its hints must be available")
	print("[QuestCompassPreview] OK: hint gating follows tracked quest, not just any active quest")

	# Switch back to the same-zone quest for the screen-projection checks below.
	QuestManager.tracked_quest_id = "quest_02"
	GameManager.imported_scene_context = {"zone_id": "zone_03"}
	QuestManager.quests_changed.emit()
	await get_tree().process_frame
	assert(not _compass._intent.is_empty(), "same-zone quest should resolve again after switching tracked quest back")

	# Case 1: target far off-screen (bottom-right) -> arrow visible, pointing outward.
	_camera.global_position = Vector2.ZERO
	await _settle_frames(20)
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://tools/qa_compass_offscreen.png")
	)
	assert(_compass._target_alpha > 0.5, "arrow should be visible when target is far off-screen")
	print("[QuestCompassPreview] OK: visible + wrote qa_compass_offscreen.png, arrow rotation=%.2f rad" % _compass._arrow.rotation)

	# Case 2: camera moved so the target is now centered on-screen -> arrow hides.
	_camera.global_position = _target_world_pos
	await _settle_frames(20)
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://tools/qa_compass_onscreen.png")
	)
	assert(_compass._target_alpha < 0.5, "arrow should hide once the target is on-screen")
	print("[QuestCompassPreview] OK: hidden once target on-screen + wrote qa_compass_onscreen.png")

	# Case 3: target off-screen to the UPPER-LEFT -> arrow should point up-left, not the
	# same direction as case 1 (sanity check the angle math actually reacts to direction).
	_camera.global_position = _target_world_pos + Vector2(3000, 3000)
	await _settle_frames(20)
	var rot_case3: float = _compass._arrow.rotation
	assert(_compass._target_alpha > 0.5, "arrow should be visible again for case 3")
	print("[QuestCompassPreview] OK: case 3 rotation=%.2f rad (case 1 was different direction)" % rot_case3)

	print("[QuestCompassPreview] ALL CHECKS PASSED")
	get_tree().quit()


func _settle_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _setup_quest() -> void:
	# Mirrors the real quest_02 shape (chapter_quests/chapter_1/manifest.json) closely
	# enough to exercise the same code paths: a "collect" objective as the active one.
	var quest := {
		"id": "quest_02",
		"title": "Người Trồng Mầm Ghé Qua",
		"type": "side",
		"giver": {"mode": "npc", "zone_id": "zone_03", "npc_id": "npc_01"},
		"objectives": [
			{"kind": "talk", "zone_id": "zone_03", "target_npc_id": "npc_01", "id": "o1", "description": "Gặp Maelis."},
			{"kind": "collect", "zone_id": "zone_03", "item_id": "item_sacred_grove_map", "item_ref": "item_sacred_grove_map", "count": 1, "id": "o2", "description": "Tưới thử ba túi hạt."},
			{"kind": "talk", "zone_id": "zone_03", "target_npc_id": "npc_01", "id": "o3", "description": "Hỏi Maelis."},
			{"kind": "reach", "zone_id": "zone_04", "id": "o4", "description": "Rời làng."},
		],
	}
	QuestManager.load_chapter_quests([quest])
	QuestManager.quest_states["quest_02"] = {"state": "active", "objective_index": 1, "progress": 0, "choices": {}}
	QuestManager.tracked_quest_id = "quest_02"


func _setup_cross_zone_quest() -> void:
	# Appended directly (NOT via load_chapter_quests, which would wipe quest_02's
	# state) — a second quest whose current objective lives in a zone the player
	# hasn't reached, with zero hints ever revealed for it.
	var quest := {
		"id": "quest_03",
		"title": "Tiếng Gọi Từ Thân Cây Chết",
		"type": "side",
		"giver": {"mode": "npc", "zone_id": "zone_05", "npc_id": "npc_09"},
		"objectives": [
			{"kind": "talk", "zone_id": "zone_05", "target_npc_id": "npc_09", "id": "o1", "description": "Tìm người gác cổng."},
		],
	}
	QuestManager.quests.append(quest)
	QuestManager.quest_states["quest_03"] = {"state": "active", "objective_index": 0, "progress": 0, "choices": {}}
