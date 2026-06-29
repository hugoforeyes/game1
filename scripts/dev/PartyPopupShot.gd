extends Node2D
## Dev-only: renders the party-join popup with the real companion portrait and saves
## a screenshot so the AAA design can be eyeballed without playing to the join beat.

const PartyJoinPopupScript := preload("res://scripts/ui/PartyJoinPopup.gd")


func _ready() -> void:
	var flow: Dictionary = await ChapterFlow._http_get_json("/api/godot/runs/latest")
	var chapter: Dictionary = (flow.get("chapters", []) as Array)[0] as Dictionary
	var party: Dictionary = chapter.get("party", {}) as Dictionary
	var companions: Array = party.get("companions", []) as Array
	if companions.is_empty():
		push_error("[PartyPopupShot] no companions in flow")
		get_tree().quit(1)
		return
	var companion: Dictionary = companions[0] as Dictionary
	var npc_id := str(companion.get("npc_id", ""))
	var portrait_sheet: Texture2D = await ChapterFlow.download_image_texture(str(companion.get("portrait_url", "")))
	PartyManager.set_companion_portrait(npc_id, portrait_sheet)

	# soft world backdrop so the card reads in context
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.11, 1.0)
	bg.size = Vector2(960, 540)
	add_child(bg)

	var popup: CanvasLayer = PartyJoinPopupScript.new()
	add_child(popup)
	popup.show_member({
		"name": companion.get("name", ""),
		"role": str(companion.get("role", "")),
		"portrait": PartyManager.companion_portrait(npc_id),
	})
	await get_tree().create_timer(0.7).timeout
	await _shot("/tmp/party_join_popup.png")
	get_tree().quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[PartyPopupShot] saved %s" % path)
