class_name QuestNotificationToast
extends Control
## Quest/objective notification toast — aaa_kit_v1 ornate plaque with a crest
## medallion on the left and a three-line text block (header / title /
## subtitle). Lives on QuestManager's scale-2 layer, so all coordinates here
## are design units (x2 on screen). API kept from v1: setup(data) +
## animate_effects(); the host reads `size` for centering/slide tweens.

const PANEL_SIZE := Vector2(216, 46)
const MEDALLION_SIZE := 36.0
const MEDALLION_X := 8.0
const TEXT_X := 58.0
const TEXT_RIGHT_PAD := 28.0

var header_label: Label
var title_label: Label
var subtitle_label: Label
var palette := "gold"
var _effect_nodes: Array[CanvasItem] = []


func setup(data: Dictionary) -> void:
	size = PANEL_SIZE
	pivot_offset = PANEL_SIZE * 0.5
	palette = str(data.get("palette", "gold"))
	if palette not in ["gold", "cyan"]:
		palette = "gold"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	_build_content(data)


func animate_effects() -> void:
	for index in range(_effect_nodes.size()):
		var node := _effect_nodes[index]
		node.modulate.a = 0.35
		var tween := create_tween().set_loops(2)
		tween.tween_interval(0.09 * index)
		tween.tween_property(node, "modulate:a", 1.0, 0.18)
		tween.tween_property(node, "modulate:a", 0.55, 0.30)


func _build_frame() -> void:
	var plaque_texture := UiKit.kit_texture("toast_plaque.png")
	if plaque_texture != null:
		var plaque := TextureRect.new()
		plaque.texture = plaque_texture
		plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plaque.stretch_mode = TextureRect.STRETCH_SCALE
		plaque.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		plaque.size = PANEL_SIZE
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(plaque)
	else:
		var panel := Panel.new()
		panel.size = PANEL_SIZE
		panel.add_theme_stylebox_override("panel", UiKit.frame_style(6.0))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)


func _build_content(data: Dictionary) -> void:
	# Crest medallion, vertically centered on the plaque's left.
	var crest_texture := UiKit.kit_texture("crest_%s.png" % palette)
	if crest_texture == null:
		var icon_name := str(data.get("icon", "new_quest"))
		var legacy_path := "res://assets/ui/notification_v1/components/icon_%s.png" % icon_name
		if ResourceLoader.exists(legacy_path):
			crest_texture = load(legacy_path)
	if crest_texture != null:
		var crest := TextureRect.new()
		crest.texture = crest_texture
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		crest.position = Vector2(MEDALLION_X, (PANEL_SIZE.y - MEDALLION_SIZE) * 0.5).round()
		crest.size = Vector2(MEDALLION_SIZE, MEDALLION_SIZE)
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(crest)
		_effect_nodes.append(crest)

	var accent := UiKit.COLOR_ACCENT if palette == "gold" else UiKit.COLOR_CYAN
	var text_w := PANEL_SIZE.x - TEXT_X - TEXT_RIGHT_PAD

	# Two lines inside the plaque band. Line 1 is an HBox — header caps on the
	# left, dim subtitle filling the rest — so long subtitles shrink/clip
	# inside the band instead of spilling past the plaque.
	var header_text := str(data.get("header", ""))
	var subtitle_text := str(data.get("subtitle", "")).strip_edges()
	var top_line := HBoxContainer.new()
	top_line.position = Vector2(TEXT_X, 9)
	top_line.size = Vector2(text_w, 9)
	top_line.add_theme_constant_override("separation", 8)
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_line)

	header_label = UiKit.make_label_strong(header_text, 6, accent)
	header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_line.add_child(header_label)

	subtitle_label = UiKit.make_label(subtitle_text, 6, UiKit.COLOR_TEXT_DIM)
	if not subtitle_text.is_empty():
		subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subtitle_label.clip_text = true
		subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top_line.add_child(subtitle_label)

	title_label = UiKit.make_title(str(data.get("title", "")), int(data.get("title_font_size", 10)), UiKit.COLOR_TEXT)
	title_label.position = Vector2(TEXT_X, 18)
	title_label.size = Vector2(text_w, 14)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
