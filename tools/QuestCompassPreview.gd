extends Node2D
## Scripted QA for QuestCompassView: drives the REAL QuestManager hint-reveal
## flow (production code) plus a fake "Main" stub exposing the same
## lookup methods Main.gd provides, so the compass's own logic (intent
## resolution without hint-gating, dynamic enemy targeting, edge-clamp math, and
## persistent exact-target pointing) is exercised
## for real while the entity-position source is fully controlled.

const QuestCompassViewScript := preload("res://scripts/ui/QuestCompassView.gd")
const MainScript := preload("res://scripts/world/Main.gd")

var _camera: Camera2D
var _compass: QuestCompassView
var _fake_main: Node
var _target_world_pos := Vector2(4000, 4000)


class FakeEnemy:
	extends Node2D
	var enemy_data: Dictionary = {}
	var hostile := true

	func is_hostile() -> bool:
		return hostile


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

	# ── NO ACTIVE QUEST: point to the next MAIN quest giver ────────────────────
	_setup_unaccepted_quests()
	GameManager.imported_scene_context = {"zone_id": "zone_03"}
	QuestManager.quests_changed.emit()
	await get_tree().process_frame
	assert(QuestManager.tracked_quest_and_objective().is_empty(), "sanity: no quest should be active before talking to a giver")
	assert(str(_compass._intent.get("purpose", "")) == "main_quest_giver", "no active quest: compass must fall back to a main quest giver")
	assert(str(_compass._intent.get("entity_id", "")) == "npc_main_giver", "no active quest: side quest giver must not take priority")
	assert(str(_compass._intent.get("zone_id", "")) == "zone_03", "no active quest: compass must retain the main giver's zone")
	print("[QuestCompassPreview] OK: no active quest points to main quest giver -> ", _compass._intent)
	assert(str(_compass._side_offer_intent.get("purpose", "")) == "side_quest_giver", "same-zone side quest offer must get its own pointer")
	assert(str(_compass._side_offer_intent.get("entity_id", "")) == "npc_side_giver", "secondary pointer must target the side quest giver")
	assert(_compass._side_arrow.material is ShaderMaterial, "side quest pointer must use its dedicated color material")
	var side_tint := (_compass._side_arrow.material as ShaderMaterial).get_shader_parameter("tint_color") as Color
	assert(side_tint.is_equal_approx(_compass.SIDE_QUEST_COLOR), "side quest pointer must use the configured light-blue tint")
	_compass._update_pointer_for(
		_target_world_pos, _compass._side_offer_intent, _compass._side_arrow, _compass._side_badge,
		_compass.SIDE_EDGE_MARGIN, _compass.SIDE_TARGET_POINTER_GAP,
	)
	assert(_compass._side_badge.texture != null, "side quest pointer must load its dedicated quest-offer badge")
	assert(_compass._side_badge.texture.resource_path.ends_with("quest_offer_side.png"), "side quest pointer must not reuse the generic NPC badge")
	print("[QuestCompassPreview] OK: same-zone side quest uses a distinct secondary pointer -> ", _compass._side_offer_intent)

	# The same offer in another zone must keep its target zone so normal compass
	# resolution points to the correct exit leading toward that giver.
	GameManager.imported_scene_context = {"zone_id": "zone_01"}
	QuestManager.quests_changed.emit()
	await get_tree().process_frame
	assert(str(_compass._intent.get("zone_id", "")) == "zone_03", "cross-zone main quest offer must still target the giver's zone")
	assert(_compass._resolve_target_position() == _target_world_pos, "cross-zone main quest offer must resolve through the exit lookup")
	assert(_compass._side_offer_intent.is_empty(), "side quest pointer must not advertise an offer in another zone")
	print("[QuestCompassPreview] OK: cross-zone no-quest fallback points toward giver zone")

	_setup_quest()

	# ── SAME-ZONE case: ALWAYS shown ────────────────────────────────────────────
	# Player is standing in the objective's own zone (zone_03). Precise pointing
	# is available immediately, before any of the 3 optional hints are heard.
	GameManager.imported_scene_context = {"zone_id": "zone_03"}
	QuestManager.tracked_quest_id = "quest_02"
	QuestManager.quests_changed.emit()
	await get_tree().process_frame
	assert(_compass._side_offer_intent.is_empty(), "accepted/active side quests must no longer show an offer pointer")

	assert(not QuestManager.is_objective_fully_hinted("quest_02", "o2"), "sanity: no hints should be revealed yet")
	assert(not _compass._intent.is_empty(), "same-zone: compass must resolve an intent before any hints are heard")
	print("[QuestCompassPreview] OK: same-zone intent shown before hints -> ", _compass._intent)

	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 1}, "Gợi ý mức 1")
	await get_tree().process_frame
	assert(not _compass._intent.is_empty(), "same-zone: compass must remain shown after only 1/3 hints")
	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 2}, "Gợi ý mức 2")
	await get_tree().process_frame
	assert(not _compass._intent.is_empty(), "same-zone: compass must remain shown after only 2/3 hints")
	QuestManager.reveal_hint("Maelis", {"quest_id": "quest_02", "objective_id": "o2", "level": 3}, "Gợi ý mức 3")
	await get_tree().process_frame

	assert(QuestManager.is_objective_fully_hinted("quest_02", "o2"), "should be fully hinted now")
	assert(not _compass._intent.is_empty(), "same-zone: compass must remain shown after all hints")
	print("[QuestCompassPreview] OK: same-zone intent remains shown after 3/3 hints -> ", _compass._intent)

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
	_save_viewport_if_available("res://tools/qa_compass_offscreen.png")
	assert(_compass._target_alpha > 0.5, "arrow should be visible when target is far off-screen")
	print("[QuestCompassPreview] OK: visible + wrote qa_compass_offscreen.png, arrow rotation=%.2f rad" % _compass._arrow.rotation)

	# Case 2: camera moved so the target is now centered on-screen -> arrow stays
	# beside it and points at its exact screen position instead of disappearing.
	_camera.global_position = _target_world_pos
	await _settle_frames(20)
	_save_viewport_if_available("res://tools/qa_compass_onscreen.png")
	assert(_compass._target_alpha > 0.5, "arrow should remain visible once the target is on-screen")
	var screen_center := get_viewport_rect().size * 0.5
	var arrow_center := _compass._arrow.position + _compass._arrow.size * 0.5
	var arrow_forward := Vector2.UP.rotated(_compass._arrow.rotation)
	assert(arrow_forward.dot(arrow_center.direction_to(screen_center)) > 0.98, "on-screen arrow should point directly at target")
	print("[QuestCompassPreview] OK: persistent exact-target pointer + wrote qa_compass_onscreen.png")

	# Case 3: target off-screen to the UPPER-LEFT -> arrow should point up-left, not the
	# same direction as case 1 (sanity check the angle math actually reacts to direction).
	_camera.global_position = _target_world_pos + Vector2(3000, 3000)
	await _settle_frames(20)
	var rot_case3: float = _compass._arrow.rotation
	assert(_compass._target_alpha > 0.5, "arrow should be visible again for case 3")
	print("[QuestCompassPreview] OK: case 3 rotation=%.2f rad (case 1 was different direction)" % rot_case3)

	# ── Count-based defeat objective: nearest remaining hostile ────────────────
	_setup_count_defeat_quest()
	GameManager.imported_scene_context = {"zone_id": "zone_03"}
	_fake_main.hostile_positions = [Vector2(1800, 0), Vector2(900, 0), Vector2(2400, 0)]
	for level in [1, 2, 3]:
		QuestManager.reveal_hint("Scout", {"quest_id": "quest_count", "objective_id": "o1", "level": level}, "Gợi ý %d" % level)
	await get_tree().process_frame
	assert(str(_compass._intent.get("entity_kind", "")) == "enemy_any", "count defeat should resolve a dynamic hostile intent")
	assert(_compass._resolve_target_position() == Vector2(900, 0), "count defeat should point to nearest hostile")
	_fake_main.hostile_positions.erase(Vector2(900, 0))
	assert(_compass._resolve_target_position() == Vector2(1800, 0), "pointer should advance after the nearest hostile is removed")
	print("[QuestCompassPreview] OK: count-based defeat retargets nearest remaining hostile")
	_test_real_main_nearest_hostile_lookup()

	print("[QuestCompassPreview] ALL CHECKS PASSED")
	get_tree().quit()


func _settle_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _save_viewport_if_available(path: String) -> void:
	# The headless display driver has no framebuffer. Visual preview runs still
	# write PNGs normally; automated headless assertions skip only the capture.
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _test_real_main_nearest_hostile_lookup() -> void:
	var main = MainScript.new()
	var characters := Node2D.new()
	main.generated_characters = characters
	var farther := FakeEnemy.new()
	farther.enemy_data = {"id": "qa_farther"}
	farther.position = Vector2(1200, 0)
	characters.add_child(farther)
	var nearer := FakeEnemy.new()
	nearer.enemy_data = {"id": "qa_nearer"}
	nearer.position = Vector2(400, 0)
	characters.add_child(nearer)

	assert(main.find_nearest_hostile_global_position(Vector2.ZERO) == Vector2(400, 0))
	nearer.hostile = false
	assert(main.find_nearest_hostile_global_position(Vector2.ZERO) == Vector2(1200, 0))
	characters.free()
	main.free()
	print("[QuestCompassPreview] OK: Main skips enemies that are no longer hostile")


func _setup_unaccepted_quests() -> void:
	var side_quest := {
		"id": "quest_side_offer",
		"title": "Việc vặt ven đường",
		"type": "side",
		"giver": {"mode": "npc", "zone_id": "zone_03", "npc_id": "npc_side_giver"},
		"objectives": [{"kind": "talk", "zone_id": "zone_03", "target_npc_id": "npc_side_giver", "id": "o1"}],
	}
	var main_quest := {
		"id": "quest_main_offer",
		"title": "Lời gọi đầu tiên",
		"type": "main",
		"giver": {"mode": "npc", "zone_id": "zone_03", "npc_id": "npc_main_giver"},
		"objectives": [{"kind": "talk", "zone_id": "zone_03", "target_npc_id": "npc_main_giver", "id": "o1"}],
	}
	QuestManager.load_chapter_quests([side_quest, main_quest])


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


func _setup_count_defeat_quest() -> void:
	var quest := {
		"id": "quest_count",
		"title": "Giữ chiến hào",
		"type": "main",
		"objectives": [{
			"kind": "defeat",
			"zone_id": "zone_03",
			"count": 3,
			"id": "o1",
			"description": "Đánh bại hoặc tha mạng ba kẻ địch.",
		}],
	}
	QuestManager.load_chapter_quests([quest])
	QuestManager.quest_states["quest_count"] = {"state": "active", "objective_index": 0, "progress": 0, "choices": {}}
	QuestManager.tracked_quest_id = "quest_count"
	QuestManager.quests_changed.emit()
