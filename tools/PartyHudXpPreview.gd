extends Node
## Production-scale QA for talk-XP feedback attached to the overworld player card.

const PartyHudScript := preload("res://scripts/ui/PartyHudView.gd")


func _ready() -> void:
	GameManager.player_level = 4
	GameManager.player_xp = 48

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.07, 0.14, 0.11, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	for index in range(24):
		var block := ColorRect.new()
		block.color = Color(0.12, 0.27, 0.18, 0.72) if index % 3 else Color(0.28, 0.23, 0.14, 0.70)
		block.position = Vector2(20 + (index % 8) * 128, 108 + (index / 8) * 154)
		block.size = Vector2(88, 96)
		add_child(block)

	var hud = PartyHudScript.new()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.talk_xp_awarded.emit("quest", 14, ["Bạn"])
	await get_tree().create_timer(0.20).timeout

	var label: Label = hud._xp_gain_label
	assert(label != null)
	assert(label.text == "+14 KN")
	assert(label.position == label.get_meta("target_position"))
	assert(label.position.y >= hud._xp_rect.end.y)
	assert(label.position.x + label.size.x == hud._xp_rect.end.x)
	assert(hud._xp_fill.modulate != Color.WHITE)

	if DisplayServer.get_name() != "headless":
		var output := "res://assets/ui/party_hud_v1/xp_gain_preview.png"
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
		print("[PartyHudXpPreview] wrote %s" % output)

	# Verify the production path: stats refresh first, then GameManager's talk-XP
	# signal recreates the feedback beside the newly updated bar.
	GameManager.player_level = 1
	GameManager.player_xp = 0
	GameManager.talk_log.erase("npc_hud_preview::quest_beat")
	hud._refresh()
	var result := GameManager.award_talk_xp("npc_hud_preview", "quest_beat", "quest")
	await get_tree().create_timer(0.20).timeout
	label = hud._xp_gain_label
	assert(bool(result.get("awarded", false)))
	assert(label != null)
	assert(label.text == "+%d KN" % int(result.get("amount", 0)))
	assert(GameManager.player_xp == int(result.get("amount", 0)))
	get_tree().quit()
