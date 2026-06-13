class_name UiKit
extends RefCounted
## Shared loader for the AI-generated UI art kit. Every asset is optional —
## helpers return styled flat fallbacks so scenes never depend on art existing.

const TEX_PANEL := "res://assets/ui/battle/panel.png"
const TEX_CURSOR := "res://assets/ui/battle/cursor.png"
const TEX_BANNER := "res://assets/ui/battle/banner.png"

const COLOR_TEXT := Color(0.93, 0.88, 0.75, 1.00)
const COLOR_TEXT_DIM := Color(0.93, 0.88, 0.75, 0.45)
const COLOR_ACCENT := Color(0.96, 0.88, 0.50, 1.00)
const COLOR_PANEL_BG := Color(0.05, 0.04, 0.13, 0.92)
const COLOR_PANEL_BORDER := Color(0.78, 0.60, 0.26, 0.65)


static func panel_style(texture_margin: float = 11.0, content_margin: float = 4.0) -> StyleBox:
	if ResourceLoader.exists(TEX_PANEL):
		var style := StyleBoxTexture.new()
		style.texture = load(TEX_PANEL)
		style.set_texture_margin_all(texture_margin)
		style.set_content_margin_all(content_margin)
		return style
	var flat := StyleBoxFlat.new()
	flat.bg_color = COLOR_PANEL_BG
	flat.border_color = COLOR_PANEL_BORDER
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	return flat


static func make_panel(rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", panel_style())
	return panel


static func cursor_texture() -> Texture2D:
	return load(TEX_CURSOR) if ResourceLoader.exists(TEX_CURSOR) else null


static func banner_texture() -> Texture2D:
	return load(TEX_BANNER) if ResourceLoader.exists(TEX_BANNER) else null


static func make_label(text: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


static func make_banner_rect(width: float) -> TextureRect:
	var texture: Texture2D = banner_texture()
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Vector2(width, width * float(texture.get_height()) / float(texture.get_width()))
	return rect


static func make_ember_particles(viewport_size: Vector2) -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	embers.position = Vector2(viewport_size.x * 0.5, viewport_size.y + 8.0)
	embers.amount = 22
	embers.lifetime = 7.0
	embers.preprocess = 6.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(viewport_size.x * 0.55, 4.0)
	embers.direction = Vector2(0, -1)
	embers.spread = 14.0
	embers.gravity = Vector2(0, -6.0)
	embers.initial_velocity_min = 14.0
	embers.initial_velocity_max = 34.0
	embers.scale_amount_min = 0.8
	embers.scale_amount_max = 1.8
	embers.color = Color(1.0, 0.78, 0.42, 0.5)
	return embers
