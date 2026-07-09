extends Node2D
## Renders the frameless zone-transition markers (ZoneMarker.gd) in all four
## travel directions over a dark mock scene — two of them through the REAL
## ZoneExitPortal / InteriorExit wiring — then saves a screenshot.
## Run: /Applications/Godot.app/Contents/MacOS/Godot --path GameV1 res://tools/ZoneMarkerUiPreview.tscn

const ZoneMarkerScript := preload("res://scripts/world/ZoneMarker.gd")
const ZoneExitPortalScript := preload("res://scripts/world/ZoneExitPortal.gd")
const InteriorExitScript := preload("res://scripts/world/InteriorExit.gd")
const OUTPUT := "res://assets/ui/zone_marker_v1/preview.png"


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.06, 0.075, 0.05, 1.0))
	_add_backdrop()

	var near_player := Node2D.new()
	near_player.position = Vector2(512, 300)
	add_child(near_player)

	var far_player := Node2D.new()
	far_player.position = Vector2(5000, 5000)
	add_child(far_player)

	# North edge exit — long Vietnamese name, player near (full reveal).
	_add_marker(Vector2(512, 96), "Cánh Đồng Hoa Trắng Đầu Tiên", Vector2.UP, near_player)
	# West edge exit — player far away (dimmed state).
	_add_marker(Vector2(96, 520), "Thung Lũng Sương Mù", Vector2.LEFT, far_player)

	# East edge exit through the REAL portal script.
	var portal := ZoneExitPortalScript.new()
	portal.setup(Vector2(956, 260), "east", "zone_b", 0.5, "Làng Gió", near_player)
	add_child(portal)

	# Building entrance through the REAL interior-exit script (3x3 building).
	var footprint := Rect2(Vector2(300.0 - 108.0, 400.0 - 108.0), Vector2(216.0, 216.0))
	_add_building_mock(footprint)
	var door := InteriorExitScript.new()
	door.setup(footprint.get_center(), {"leads_to": "zone_x"}, "Thạch Tâm Phái", near_player, footprint)
	add_child(door)

	# Mid entrance-reveal (~0.35s): name fading in, rule partially drawn.
	await _settle(21)
	_save("res://assets/ui/zone_marker_v1/preview_intro.png")
	# Fully settled idle state.
	await _settle(49)
	_save(OUTPUT)
	# Force every marker to the middle of its glint sweep and capture it.
	for marker in _all_markers():
		marker._time = fposmod(marker.GLINT_DURATION * 0.45 - marker._glint_phase, marker.GLINT_PERIOD)
	await _settle(2)
	_save("res://assets/ui/zone_marker_v1/preview_glint.png")
	get_tree().quit()


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)


func _all_markers() -> Array:
	var found: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.name == "ZoneMarker":
			found.append(node)
		for child in node.get_children():
			stack.append(child)
	return found


func _add_marker(pos: Vector2, text: String, travel: Vector2, player: Node2D) -> void:
	var marker: Node2D = ZoneMarkerScript.new()
	marker.setup(text, travel, player)
	marker.position = pos
	add_child(marker)


func _add_building_mock(footprint: Rect2) -> void:
	var body := ColorRect.new()
	body.position = footprint.position
	body.size = footprint.size
	body.color = Color(0.13, 0.10, 0.08, 1.0)
	add_child(body)
	var door := ColorRect.new()
	door.position = footprint.position + Vector2(footprint.size.x * 0.5 - 22.0, footprint.size.y - 52.0)
	door.size = Vector2(44.0, 52.0)
	door.color = Color(0.32, 0.22, 0.10, 1.0)
	add_child(door)


func _add_backdrop() -> void:
	# Rough tile-ish patches so legibility over a busy pixel scene is judged
	# fairly: dark forest on the left half, bright sunlit grass on the right.
	var base := ColorRect.new()
	base.position = Vector2(512, -20)
	base.size = Vector2(532, 616)
	base.color = Color(0.42, 0.52, 0.28, 1.0)
	add_child(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(220):
		var rect := ColorRect.new()
		rect.position = Vector2(rng.randf_range(-20, 1024), rng.randf_range(-20, 576))
		rect.size = Vector2(rng.randf_range(24, 90), rng.randf_range(18, 70))
		if rect.position.x > 512.0:
			var b := rng.randf_range(0.38, 0.60)
			rect.color = Color(b * rng.randf_range(0.75, 1.05), b, b * rng.randf_range(0.35, 0.55), 1.0)
		else:
			var g := rng.randf_range(0.05, 0.16)
			rect.color = Color(g * rng.randf_range(0.6, 1.0), g, g * rng.randf_range(0.4, 0.8), 1.0)
		add_child(rect)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
