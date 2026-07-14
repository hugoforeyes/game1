extends Node2D
## Renders the production enemy-header component at real Godot scale. The art
## comes from OpenAiExtension; typography/layout are the exact runtime code.

const BattleSceneScript := preload("res://scripts/battle/BattleScene.gd")
const EnemyIdentityPlateScript := preload("res://scripts/battle/EnemyIdentityPlate.gd")
const HERO_PORTRAIT := preload("res://assets/ui/battle_v3/hero_portrait.png")
const BACKDROP := preload("res://assets/ui/battle/backdrop.png")

const VIEW_SIZE := Vector2(1024, 576)


func _ready() -> void:
	_build_showcase()
	_capture.call_deferred()


func _build_showcase() -> void:
	var canvas := Control.new()
	canvas.size = VIEW_SIZE
	add_child(canvas)

	var backdrop := TextureRect.new()
	backdrop.texture = BACKDROP
	backdrop.size = VIEW_SIZE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	canvas.add_child(backdrop)

	var veil := ColorRect.new()
	veil.color = Color(0.015, 0.018, 0.035, 0.55)
	veil.size = VIEW_SIZE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(veil)

	var title := UiKit.make_title("ENEMY IDENTITY", 28, Color(1.0, 0.84, 0.48, 1.0))
	title.position = Vector2(0, 27)
	title.size = Vector2(VIEW_SIZE.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(title)

	var subtitle := UiKit.make_label_strong(
		"Modular caps · repeatable rails · runtime-measured typography",
		11,
		Color(0.86, 0.82, 0.73, 0.78),
	)
	subtitle.position = Vector2(0, 67)
	subtitle.size = Vector2(VIEW_SIZE.x, 22)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(subtitle)

	var helper := BattleSceneScript.new()
	var examples: Array[Dictionary] = [
		{
			"x": 50.0, "slot": 230.0, "name": "Nyx", "level": 4, "group": 1,
			"tint": Color(0.58, 0.34, 0.42, 0.92), "statuses": [],
		},
		{
			"x": 397.0, "slot": 230.0, "name": "Vệ Binh Tro Tàn", "level": 12, "group": 2,
			"tint": Color(0.45, 0.34, 0.62, 0.92),
			"statuses": [{
				"id": "exposed", "label": "EXP", "wide_label": "EXPOSED", "count": 2,
				"tooltip": "Exposed · takes amplified damage · 2 turns",
			}],
		},
		{
			"x": 744.0, "slot": 230.0,
			"name": "Kẻ Canh Giữ Hoàng Hôn Vĩnh Cửu", "level": 18, "group": 3,
			"tint": Color(0.38, 0.38, 0.54, 0.92),
			"statuses": [
				{"id": "poison", "label": "POI", "count": 3, "tooltip": "Poison · 3 turns"},
				{"id": "stun", "label": "STU", "count": 1, "tooltip": "Stun · 1 turn"},
			],
		},
	]

	for index in range(examples.size()):
		var example: Dictionary = examples[index]
		var holder := Control.new()
		holder.position = Vector2(float(example["x"]), 154)
		holder.size = Vector2(float(example["slot"]), 320)
		canvas.add_child(holder)

		var portrait_shadow := ColorRect.new()
		portrait_shadow.position = Vector2(17, 8)
		portrait_shadow.size = Vector2(holder.size.x - 34, 252)
		portrait_shadow.color = Color(0.01, 0.015, 0.035, 0.60)
		portrait_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(portrait_shadow)

		var portrait := TextureRect.new()
		portrait.texture = HERO_PORTRAIT
		portrait.position = Vector2(17, 8)
		portrait.size = Vector2(holder.size.x - 34, 252)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.modulate = example["tint"]
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(portrait)

		var fade := ColorRect.new()
		fade.position = Vector2(17, 178)
		fade.size = Vector2(holder.size.x - 34, 82)
		fade.color = Color(0.015, 0.018, 0.035, 0.50)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fade)

		var identity := EnemyIdentityPlateScript.new()
		identity.setup(
			str(example["name"]),
			int(example["level"]),
			holder.size.x,
			252.0,
			int(example["group"]),
		)
		holder.add_child(identity)
		for entry in example["statuses"] as Array:
			identity.status_row.add_child(helper._make_status_token(entry as Dictionary, 16))
		identity.refresh_status_layout()

		var tag := UiKit.make_label_strong(
			["SHORT NAME", "TACTICAL STATE", "LONG LOCALIZED NAME"][index],
			9,
			Color(0.93, 0.86, 0.68, 0.72),
		)
		tag.position = Vector2(0, 292)
		tag.size = Vector2(holder.size.x, 18)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(tag)

	helper.free()

	var footer := UiKit.make_label(
		"Level and statuses remain independent modules; only the center rails change width.",
		10,
		Color(0.82, 0.79, 0.72, 0.66),
	)
	footer.position = Vector2(0, 522)
	footer.size = Vector2(VIEW_SIZE.x, 22)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(footer)


func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var output := String(OS.get_environment("ENEMY_IDENTITY_MOCKUP_PATH")).strip_edges()
	if output.is_empty():
		output = (ProjectSettings.globalize_path("res://")
			+ "../SceneBuilder/outputs/enemy_identity_v1/enemy_identity_mockup.png").simplify_path()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output)
	print("[EnemyIdentityShowcase] saved=%s error=%s" % [output, error_string(error)])
	get_tree().quit(0 if error == OK else 1)
