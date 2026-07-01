extends Node
## Renders deterministic 960x540 visual QA images for MinimapView: once with the
## procedural gold-fleck viewport (no chapter_map_illustration), once with a
## painted background texture standing in for the LLM-generated map art — proves
## both rendering paths (utils/chapter_map_illustration.py's optional output).


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.07, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var view: MinimapView = MinimapView.new()
	add_child(view)

	# Mirrors the real /api/godot/runs/latest chapters[].minimap payload shape
	# (verified live against SceneBuilder), plus a synthetic disconnected zone to
	# prove an unconnected/never-adjacent-to-visited zone is omitted entirely.
	var data := {
		"current_zone_id": "zone_02",
		"visited_zone_ids": {"zone_01": true, "zone_02": true},
		"zones": [
			{"zone_id": "zone_01", "name": "Làng Rễ Bình Minh", "type": "town",
				"center": {"x": 0.16, "y": 0.74}, "connections": ["zone_02", "zone_secret_01"]},
			{"zone_id": "zone_02", "name": "Quảng Trường Cổ Mộc", "type": "safe_zone",
				"center": {"x": 0.43, "y": 0.685}, "connections": ["zone_01", "zone_03"]},
			{"zone_id": "zone_03", "name": "Lều Của Hội Người Trồng Mầm", "type": "town",
				"center": {"x": 0.64, "y": 0.67}, "connections": ["zone_02"]},
			{"zone_id": "zone_secret_01", "name": "Hốc Rễ Chiếc Lá Không Héo", "type": "secret",
				"center": {"x": 0.13, "y": 0.535}, "connections": ["zone_01"]},
			{"zone_id": "zone_boss", "name": "Bìa Rừng Ngủ Quên", "type": "boss_arena",
				"center": {"x": 0.90, "y": 0.20}, "connections": []},
			# Never adjacent to a visited zone -> must be entirely omitted.
			{"zone_id": "zone_far_unknown", "name": "Should Never Appear", "type": "dungeon",
				"center": {"x": 0.95, "y": 0.95}, "connections": []},
		],
	}
	view.set_data(data)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert(view.get_child_count() > 0)
	view.visible = true
	var output := "res://assets/ui/minimap_v1/preview.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("[MinimapUiPreview] wrote %s" % output)

	# Second pass: same topology, now with a background texture — either a real
	# generated illustration on disk (dev convenience) or a synthetic painted-look
	# gradient/noise image standing in for one.
	var bg_texture := _load_or_synthesize_background()
	data["background_texture"] = bg_texture
	view.set_data(data)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var output_bg := "res://assets/ui/minimap_v1/preview_with_background.png"
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output_bg))
	print("[MinimapUiPreview] wrote %s" % output_bg)

	get_tree().quit()


func _load_or_synthesize_background() -> Texture2D:
	var real_path := "res://tools/qa_map_illustration.png"
	if ResourceLoader.exists(real_path):
		return load(real_path) as Texture2D
	var image := Image.create(1536, 1024, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for y in range(1024):
		var t: float = float(y) / 1024.0
		var base := Color(0.18, 0.28, 0.14).lerp(Color(0.09, 0.14, 0.20), t)
		for x in range(1536):
			var jitter := rng.randf_range(-0.03, 0.03)
			image.set_pixel(x, y, Color(base.r + jitter, base.g + jitter, base.b + jitter))
	return ImageTexture.create_from_image(image)
