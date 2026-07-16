extends Node
## Focused headless regression for the non-companion escort lane. Covers quest
## derivation, historical-destination gating, follower-zone policy, HP snapshot,
## save/load continuity, release signals, and companion-lane isolation.

var _failures := 0
var _joined: Array[String] = []
var _left: Array[String] = []

const PartyJoinPopupScript := preload("res://scripts/ui/PartyJoinPopup.gd")
const AnnouncementViewScript := preload("res://scripts/ui/AnnouncementView.gd")
const ESCORT_ID := "npc_escort_test"
const SOURCE_ZONE := "zone_escort_source"
const DESTINATION_ZONE := "zone_escort_destination"


func _ready() -> void:
	var original_level := GameManager.player_level
	var original_hp := GameManager.player_hp
	PartyManager.reset()
	QuestManager.reset()
	GameManager.player_level = 3
	GameManager.player_hp = -1

	PartyManager.escort_joined.connect(func(npc_id: String) -> void: _joined.append(npc_id))
	PartyManager.escort_left.connect(func(npc_id: String) -> void: _left.append(npc_id))
	var party_payload := {
		"companions": [],
		"events": [],
		"escorts": [{
			"npc_id": ESCORT_ID,
			"name": "Ansel Test",
			"role": "Người được hộ tống",
			"zones": [SOURCE_ZONE, DESTINATION_ZONE],
		}],
	}
	var quests := [_escort_quest()]
	QuestManager.load_chapter_quests(quests)
	PartyManager.load_chapter_party(party_payload)

	# Visiting the destination before accepting the quest must not satisfy an
	# escort reach objective from history.
	QuestManager.notify_zone_entered(DESTINATION_ZONE)
	QuestManager.notify_zone_entered(SOURCE_ZONE)
	QuestManager.notify_npc_talked("npc_escort_giver")
	_check(PartyManager.is_escort(ESCORT_ID), "escort is registered separately")
	_check(PartyManager.is_escort_active(ESCORT_ID), "current escort objective activates escort")
	_check(not PartyManager.is_member(ESCORT_ID), "escort never enters companion active_members")
	_check(_joined.count(ESCORT_ID) == 1, "escort_joined emits exactly once")
	_check(PartyManager.should_follow_in_zone(ESCORT_ID, SOURCE_ZONE), "escort follows in source zone")
	_check(not PartyManager.should_follow_in_zone(ESCORT_ID, DESTINATION_ZONE), "escort materializes stationary at destination")
	_check(PartyManager.follower_ids_for_zone(SOURCE_ZONE) == [ESCORT_ID], "escort has deterministic follower ordering")
	_test_join_popup_copy()
	var snap_max := int(GameManager.player_battle_stats().get("max_hp", 0))
	_check(PartyManager.escort_max_hp(ESCORT_ID) == snap_max, "escort snapshots current player max HP")

	PartyManager.set_escort_hp(ESCORT_ID, snap_max - 17)
	var party_save := PartyManager.serialize_save()
	var quest_save := QuestManager.serialize_save()
	PartyManager.reset()
	QuestManager.reset()
	QuestManager.load_chapter_quests(quests)
	PartyManager.load_chapter_party(party_payload)
	# Mirrors SaveManager order: party is restored before QuestManager emits the
	# saved objective state; reconciliation must retain the persisted HP snapshot.
	PartyManager.apply_save(party_save)
	QuestManager.apply_save(quest_save)
	_check(PartyManager.is_escort_active(ESCORT_ID), "escort restores from save")
	_check(PartyManager.escort_max_hp(ESCORT_ID) == snap_max, "saved max HP snapshot remains stable")
	_check(PartyManager.get_escort_hp(ESCORT_ID) == snap_max - 17, "escort damage persists across save/load")

	QuestManager.notify_zone_entered(DESTINATION_ZONE)
	_check(not PartyManager.is_escort_active(ESCORT_ID), "arrival releases escort")
	_check(_left.count(ESCORT_ID) == 1, "escort_left emits once on release")

	PartyManager.reset()
	QuestManager.reset()
	InventoryManager.reset()
	AnnouncementCenter.reset()
	GameManager.player_level = original_level
	GameManager.player_hp = original_hp
	# Manager resets queue_free their transient UI. Let those deletions settle before
	# quitting so the focused smoke does not report false ObjectDB leak warnings.
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures == 0:
		print("[EscortRuntimeTest] all checks passed")
		get_tree().quit(0)
	else:
		push_error("[EscortRuntimeTest] %d check(s) failed" % _failures)
		get_tree().quit(1)


func _escort_quest() -> Dictionary:
	return {
		"id": "quest_escort_runtime_test",
		"title": "Escort Runtime QA",
		"type": "main",
		"giver": {"mode": "npc", "npc_id": "npc_escort_giver", "zone_id": SOURCE_ZONE},
		"objectives": [{
			"id": "o1",
			"kind": "reach",
			"zone_id": DESTINATION_ZONE,
			"description": "Escort the protected NPC.",
			"escort": {
				"npc_ids": [ESCORT_ID],
				"start_zone_id": SOURCE_ZONE,
				"battle_mode": "protected",
				"can_act": false,
				"hp_mode": "player_max_snapshot",
				"on_complete": "release",
				"silent": true,
			},
		}],
		"reward": {"xp": 0},
	}


func _test_join_popup_copy() -> void:
	AnnouncementCenter.reset()
	AnnouncementCenter.set_conversation_active(true)
	var queued := AnnouncementCenter.enqueue("escort", {"name": "Ansel Test"})
	_check(queued and AnnouncementCenter.has_pending(), "escort joins queue behind an active conversation")
	_check(str(AnnouncementViewScript.HEADERS.get("escort", "")) == "NHÂN VẬT HỘ TỐNG", "escort ceremony has a distinct header")
	var ceremony: CanvasLayer = AnnouncementViewScript.new()
	var ceremony_content: Dictionary = ceremony.call("_content_for", "escort", {"name": "Ansel Test"}) as Dictionary
	_check(str(ceremony_content.get("subtitle", "")) == "đã đi cùng nhóm · không thể chiến đấu", "escort ceremony uses fixed non-combat copy")
	ceremony.free()
	AnnouncementCenter.reset()

	var escort_popup: CanvasLayer = PartyJoinPopupScript.new()
	add_child(escort_popup)
	escort_popup.call("_build", {"kind": "escort", "name": "Ansel Test"})
	var escort_copy := _label_copy(escort_popup)
	_check("NHÂN VẬT HỘ TỐNG" in escort_copy, "escort join popup has a distinct header")
	_check("không thể chiến đấu" in escort_copy, "escort join popup clearly marks non-combat status")
	remove_child(escort_popup)
	escort_popup.free()

	var companion_popup: CanvasLayer = PartyJoinPopupScript.new()
	add_child(companion_popup)
	companion_popup.call("_build", {"name": "Companion Test"})
	var companion_copy := _label_copy(companion_popup)
	_check("ĐỒNG ĐỘI MỚI" in companion_copy, "companion join popup copy remains unchanged")
	_check("đã gia nhập đội" in companion_copy, "companion join subtitle remains unchanged")
	remove_child(companion_popup)
	companion_popup.free()


func _label_copy(root: Node) -> String:
	var lines: Array[String] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Label:
			lines.append((node as Label).text)
		for child in node.get_children():
			pending.append(child)
	return "\n".join(lines)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
		return
	_failures += 1
	push_error("  FAIL  %s" % label)
