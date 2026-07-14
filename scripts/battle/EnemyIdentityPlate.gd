class_name EnemyIdentityPlate
extends Control
## Enemy metadata header assembled from independent caps and repeatable rails.
## Width follows measured text; ornamental caps always keep their authored aspect.

const NAME_LEFT := preload("res://assets/ui/enemy_identity_v1/nameplate_left.png")
const NAME_MIDDLE := preload("res://assets/ui/enemy_identity_v1/nameplate_middle.png")
const NAME_RIGHT := preload("res://assets/ui/enemy_identity_v1/nameplate_right.png")
const META_HEIGHT := 18.0
const NAMEPLATE_HEIGHT := 28.0
const NAMEPLATE_GAP := 2.0
const NAMEPLATE_MIN_WIDTH := 100.0
const NAMEPLATE_ABSOLUTE_MAX_WIDTH := 224.0
const META_SEPARATOR_GAP := 5.0

var name_label: Label
var level_label: Label
var status_row: HBoxContainer
var nameplate_width := NAMEPLATE_MIN_WIDTH

var _slot_width := 0.0
var _portrait_height := 0.0
var _group_size := 1
var _nameplate_root: Control
var _meta_separator: ColorRect
var _name_slices: Dictionary
var _nameplate_x := 0.0
var _nameplate_top := -1.0
var _status_capacity_width := 0.0


func setup(
	display_name: String,
	level: int,
	slot_width: float,
	portrait_height: float,
	group_size: int,
) -> void:
	_slot_width = slot_width
	_portrait_height = portrait_height
	_group_size = maxi(group_size, 1)
	position = Vector2.ZERO
	size = Vector2(_slot_width, _portrait_height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

	_nameplate_root = Control.new()
	_nameplate_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_nameplate_root)
	_name_slices = _build_three_slice(_nameplate_root, NAME_LEFT, NAME_MIDDLE, NAME_RIGHT)

	name_label = UiKit.make_title("", 12 if _group_size < 3 else 11, Color(0.98, 0.91, 0.72, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(name_label)

	level_label = UiKit.make_label_strong("", 9 if _group_size < 3 else 8, Color(1.0, 0.86, 0.50, 0.96))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(level_label)

	_meta_separator = ColorRect.new()
	_meta_separator.color = Color(0.91, 0.70, 0.32, 0.58)
	_meta_separator.size = Vector2(1, 8)
	_meta_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta_separator.visible = false
	add_child(_meta_separator)

	status_row = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	status_row.add_theme_constant_override("separation", 2)
	status_row.set_meta("icon_size", 16)
	status_row.mouse_filter = Control.MOUSE_FILTER_PASS
	status_row.visible = false
	add_child(status_row)

	set_identity(display_name, level)


func set_identity(display_name: String, level: int) -> void:
	name_label.text = display_name
	name_label.tooltip_text = display_name
	level_label.text = "LV %d" % level
	_layout_nameplate()
	_layout_metadata()


func refresh_status_layout() -> void:
	_layout_metadata()


func holder_local_bounds() -> Rect2:
	return Rect2(Vector2(0, -META_HEIGHT - 2.0), Vector2(_slot_width, META_HEIGHT + 2.0))


func nameplate_bottom() -> float:
	return _nameplate_root.position.y + NAMEPLATE_HEIGHT


func set_nameplate_top(top: float) -> void:
	_nameplate_top = top
	_layout_nameplate()


func set_targeted(targeted: bool) -> void:
	_nameplate_root.modulate = Color(1.12, 1.06, 0.90, 1.0) if targeted else Color.WHITE
	name_label.modulate = Color(1.08, 1.03, 0.88, 1.0) if targeted else Color.WHITE


func nameplate_bounds() -> Rect2:
	return Rect2(_nameplate_root.position, _nameplate_root.size)


func _layout_nameplate() -> void:
	var font_size := 12 if _group_size < 3 else 11
	var font := name_label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var text_width := font.get_string_size(
		name_label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
	).x
	var left_cap_width := _cap_width(NAME_LEFT, NAMEPLATE_HEIGHT)
	var right_cap_width := _cap_width(NAME_RIGHT, NAMEPLATE_HEIGHT)
	var desired_width := ceilf(text_width) + left_cap_width + right_cap_width + 12.0
	var max_width := minf(NAMEPLATE_ABSOLUTE_MAX_WIDTH, _slot_width - 8.0)
	nameplate_width = clampf(desired_width, minf(NAMEPLATE_MIN_WIDTH, max_width), max_width)
	_nameplate_x = roundf((_slot_width - nameplate_width) * 0.5)

	var plate_rect := Rect2(
		_nameplate_x,
		_nameplate_top if _nameplate_top >= 0.0 else _portrait_height + NAMEPLATE_GAP,
		nameplate_width,
		NAMEPLATE_HEIGHT,
	)
	_nameplate_root.position = plate_rect.position
	_nameplate_root.size = plate_rect.size
	_layout_three_slice(_name_slices, plate_rect.size)

	var inset_left := left_cap_width - 4.0
	var inset_right := right_cap_width - 4.0
	name_label.position = Vector2(
		plate_rect.position.x + inset_left,
		plate_rect.position.y - 1.0,
	)
	name_label.size = Vector2(
		maxf(1.0, plate_rect.size.x - inset_left - inset_right),
		plate_rect.size.y,
	)
	_fit_name_font(font_size, 9)

	var level_width := _level_text_width()
	_status_capacity_width = maxf(24.0, _slot_width - level_width - META_SEPARATOR_GAP * 2.0 - 1.0)
	status_row.set_meta(
		"capacity_width",
		_status_capacity_width,
	)


func _layout_metadata() -> void:
	if status_row == null or level_label == null:
		return
	var children := status_row.get_children()
	var separation := float(status_row.get_theme_constant("separation"))
	var status_width := 0.0
	for child in children:
		status_width += (child as Control).custom_minimum_size.x
	if children.size() > 1:
		status_width += separation * float(children.size() - 1)
	status_width = minf(status_width, _status_capacity_width)

	var level_width := _level_text_width()
	var has_status := not children.is_empty()
	var metadata_width := level_width
	if has_status:
		metadata_width += META_SEPARATOR_GAP * 2.0 + 1.0 + status_width
	var metadata_x := roundf((_slot_width - metadata_width) * 0.5)
	var metadata_y := -META_HEIGHT
	level_label.position = Vector2(metadata_x, metadata_y)
	level_label.size = Vector2(level_width, META_HEIGHT)

	_meta_separator.visible = has_status
	status_row.visible = has_status
	if not has_status:
		return
	_meta_separator.position = Vector2(
		metadata_x + level_width + META_SEPARATOR_GAP,
		metadata_y + 5.0,
	)
	status_row.position = Vector2(
		_meta_separator.position.x + 1.0 + META_SEPARATOR_GAP,
		metadata_y + 1.0,
	)
	status_row.size = Vector2(maxf(1.0, status_width), 16.0)


func _level_text_width() -> float:
	var font := level_label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	return ceilf(font.get_string_size(
		level_label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		level_label.get_theme_font_size("font_size"),
	).x) + 2.0


func _fit_name_font(start_size: int, min_size: int) -> void:
	var font := name_label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var fitted := start_size
	while fitted > min_size and font.get_string_size(
		name_label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		fitted,
	).x > name_label.size.x:
		fitted -= 1
	name_label.add_theme_font_size_override("font_size", fitted)


func _build_three_slice(
	host: Control,
	left_texture: Texture2D,
	middle_texture: Texture2D,
	right_texture: Texture2D,
) -> Dictionary:
	var left := _texture_piece(left_texture)
	var middle := _texture_piece(middle_texture)
	var right := _texture_piece(right_texture)
	# The authored middle sample is perfectly uniform. Scale only this rail so
	# its complete top/bottom bevel survives the 4x source-to-design downsample;
	# caps remain independent 1:1-aspect pieces and are never stretched sideways.
	middle.stretch_mode = TextureRect.STRETCH_SCALE
	host.add_child(left)
	host.add_child(middle)
	host.add_child(right)
	return {
		"left": left,
		"middle": middle,
		"right": right,
		"left_texture": left_texture,
		"right_texture": right_texture,
	}


func _layout_three_slice(parts: Dictionary, target_size: Vector2) -> void:
	var left_texture: Texture2D = parts["left_texture"]
	var right_texture: Texture2D = parts["right_texture"]
	var left_width := _cap_width(left_texture, target_size.y)
	var right_width := _cap_width(right_texture, target_size.y)
	var middle_width := maxf(1.0, target_size.x - left_width - right_width)
	var left: TextureRect = parts["left"]
	var middle: TextureRect = parts["middle"]
	var right: TextureRect = parts["right"]
	left.position = Vector2.ZERO
	left.size = Vector2(left_width, target_size.y)
	middle.position = Vector2(left_width, 0)
	middle.size = Vector2(middle_width, target_size.y)
	right.position = Vector2(target_size.x - right_width, 0)
	right.size = Vector2(right_width, target_size.y)


func _texture_piece(texture: Texture2D) -> TextureRect:
	var piece := TextureRect.new()
	piece.texture = texture
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_SCALE
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return piece


func _cap_width(texture: Texture2D, display_height: float) -> float:
	return display_height * float(texture.get_width()) / float(texture.get_height())
