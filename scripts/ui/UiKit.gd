class_name UiKit
extends RefCounted
## Shared design system for the AAA UI overhaul: standard fonts (Vietnamese-
## capable), one palette, and loaders for the generated aaa_kit_v1 component
## art. Every asset is optional — helpers return styled flat fallbacks so
## scenes never depend on art existing.
##
## Fonts: Playfair Display (ornate serif — titles, nameplates, headers) and
## Be Vietnam Pro (body/UI text; also the project-wide default via
## gui/theme/custom_font). Both bundle full Vietnamese diacritics.

const KIT_DIR := "res://assets/ui/aaa_kit_v1/"

const FONT_TITLE_PATH := "res://assets/fonts/PlayfairDisplay-VariableFont.ttf"
const FONT_BODY_PATH := "res://assets/fonts/BeVietnamPro-Regular.ttf"
const FONT_BODY_SEMIBOLD_PATH := "res://assets/fonts/BeVietnamPro-SemiBold.ttf"
const FONT_BODY_BOLD_PATH := "res://assets/fonts/BeVietnamPro-Bold.ttf"

# Legacy battle kit (kept as fallback art).
const TEX_PANEL := "res://assets/ui/battle/panel.png"
const TEX_CURSOR := "res://assets/ui/battle/cursor.png"
const TEX_BANNER := "res://assets/ui/battle/banner.png"

# ── Palette ───────────────────────────────────────────────────────────────────
const COLOR_TEXT := Color(0.93, 0.89, 0.78, 1.00)
const COLOR_TEXT_DIM := Color(0.93, 0.89, 0.78, 0.55)
const COLOR_TEXT_FAINT := Color(0.93, 0.89, 0.78, 0.32)
const COLOR_ACCENT := Color(0.99, 0.85, 0.48, 1.00)      # warm gold
const COLOR_GOLD_DIM := Color(0.76, 0.57, 0.28, 1.00)
const COLOR_GOLD_LINE := Color(0.70, 0.52, 0.25, 0.55)
const COLOR_CYAN := Color(0.56, 0.93, 0.96, 1.00)
const COLOR_GREEN := Color(0.57, 0.84, 0.43, 1.00)
const COLOR_RED := Color(0.93, 0.45, 0.42, 1.00)
const COLOR_PANEL_BG := Color(0.040, 0.055, 0.105, 0.94) # dark royal-navy glass
const COLOR_PANEL_BG_DEEP := Color(0.022, 0.030, 0.058, 0.97)
const COLOR_PANEL_BORDER := Color(0.78, 0.60, 0.26, 0.65)

static var _font_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


# ── Fonts ─────────────────────────────────────────────────────────────────────
static func _font(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path]
	var font: Font = load(path) if ResourceLoader.exists(path) else null
	_font_cache[path] = font
	return font


static func title_font() -> Font:
	return _font(FONT_TITLE_PATH)


static func body_font() -> Font:
	return _font(FONT_BODY_PATH)


static func body_semibold_font() -> Font:
	return _font(FONT_BODY_SEMIBOLD_PATH)


static func body_bold_font() -> Font:
	return _font(FONT_BODY_BOLD_PATH)


# ── Kit textures ──────────────────────────────────────────────────────────────
static func kit_texture(file_name: String) -> Texture2D:
	var path := KIT_DIR + file_name
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_texture_cache[path] = texture
	return texture


# ── Labels ────────────────────────────────────────────────────────────────────
## Body text label (Be Vietnam Pro via the project default font).
static func make_label(text: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Semibold body label — for emphasis rows, values, button captions.
static func make_label_strong(text: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var label := make_label(text, font_size, color)
	var font := body_semibold_font()
	if font != null:
		label.add_theme_font_override("font", font)
	return label


## Ornate serif display label — titles, headers, nameplates ("AAA gold serif").
static func make_title(text: String, font_size: int, color: Color = COLOR_ACCENT) -> Label:
	var label := Label.new()
	label.text = text
	var font := title_font()
	if font != null:
		var variation := FontVariation.new()
		variation.base_font = font
		variation.variation_opentype = {"wght": 640}
		label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# ── Ornate frame assembler ────────────────────────────────────────────────────
## Builds a resolution-independent ornate frame from a kit texture by slicing
## it into 9 regions and drawing the corners at an exact design-unit size
## (corner_px) while edges/center stretch. Unlike StyleBoxTexture — whose
## texture margins always draw 1:1 in local units — this scales the corner art
## DOWN crisply, so one high-res frame serves panels of any size.
## Returns a Control sized to `size`; add it as the first child of a panel.
static func make_ornate_frame(size: Vector2, texture_name: String = "panel_frame.png", corner_frac: float = 0.16, corner_px: float = 26.0, draw_center: bool = true) -> Control:
	var texture := kit_texture(texture_name)
	var root := Control.new()
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture == null:
		var panel := Panel.new()
		panel.size = size
		panel.add_theme_stylebox_override("panel", flat_panel_style())
		root.add_child(panel)
		return root

	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var m := minf(tw, th) * corner_frac          # source margin (texture px)
	var c := minf(corner_px, minf(size.x, size.y) * 0.42)  # drawn corner size
	var xs := [0.0, m, tw - m, tw]               # source column edges
	var ys := [0.0, m, th - m, th]
	var dx := [0.0, c, size.x - c, size.x]       # destination column edges
	var dy := [0.0, c, size.y - c, size.y]
	for row in range(3):
		for col in range(3):
			var src := Rect2(xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
			var dst := Rect2(dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			if not draw_center and row == 1 and col == 1:
				continue
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = src
			var piece := TextureRect.new()
			piece.texture = atlas
			piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			piece.stretch_mode = TextureRect.STRETCH_SCALE
			piece.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			piece.position = dst.position.round()
			piece.size = dst.size.round() + Vector2(0.5, 0.5)
			piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(piece)
	return root


# ── Panels ────────────────────────────────────────────────────────────────────
## Nine-slice style over a kit texture; margin is in TEXTURE pixels.
static func ninepatch_style(texture: Texture2D, texture_margin: float, content_margin: float = 10.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.set_texture_margin_all(texture_margin)
	style.set_content_margin_all(content_margin)
	return style


## The master ornate frame (aaa_kit_v1/panel_frame.png) as a StyleBox.
## Falls back to the flat glass style when the art is missing.
static func frame_style(content_margin: float = 12.0) -> StyleBox:
	var texture := kit_texture("panel_frame.png")
	if texture != null:
		var margin: float = minf(texture.get_width(), texture.get_height()) * 0.16
		return ninepatch_style(texture, margin, content_margin)
	return flat_panel_style()


static func flat_panel_style() -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	flat.bg_color = COLOR_PANEL_BG
	flat.border_color = COLOR_PANEL_BORDER
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(3)
	return flat


## Legacy helper kept for existing call sites.
static func panel_style(texture_margin: float = 11.0, content_margin: float = 4.0) -> StyleBox:
	if ResourceLoader.exists(TEX_PANEL):
		var style := StyleBoxTexture.new()
		style.texture = load(TEX_PANEL)
		style.set_texture_margin_all(texture_margin)
		style.set_content_margin_all(content_margin)
		return style
	return flat_panel_style()


static func make_panel(rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", panel_style())
	return panel


## Ornate framed panel using the new kit (9-slice, safe to stretch any size).
static func make_frame_panel(rect: Rect2, content_margin: float = 12.0) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", frame_style(content_margin))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## Small sapphire jewel placed at a frame edge midpoint (the kit frame keeps
## its edges plain so it can stretch; jewels are overlaid by code).
static func make_edge_jewel(center: Vector2, size_px: float = 14.0) -> Control:
	var texture := kit_texture("cursor_gem.png")
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		rect.size = Vector2(size_px, size_px)
		rect.position = (center - rect.size * 0.5).round()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var dot := ColorRect.new()
	dot.color = COLOR_ACCENT
	dot.size = Vector2(4, 4)
	dot.position = (center - Vector2(2, 2)).round()
	dot.rotation_degrees = 45.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


# ── Bars ──────────────────────────────────────────────────────────────────────
## Horizontal 3-slice: ornate caps keep their aspect (scaled to the target
## height), the middle stretches. Used for bars and plaques of any width.
static func make_hslice(size: Vector2, texture_name: String, cap_frac: float = 0.17) -> Control:
	var texture := kit_texture(texture_name)
	var root := Control.new()
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture == null:
		return root
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var cap_src := tw * cap_frac
	var cap_w := minf(cap_src * (size.y / th), size.x * 0.4)
	var xs := [0.0, cap_src, tw - cap_src, tw]
	var dx := [0.0, cap_w, size.x - cap_w, size.x]
	for col in range(3):
		var src := Rect2(xs[col], 0, xs[col + 1] - xs[col], th)
		var dst := Rect2(dx[col], 0, dx[col + 1] - dx[col], size.y)
		if dst.size.x <= 0.0:
			continue
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = src
		var piece := TextureRect.new()
		piece.texture = atlas
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		piece.position = dst.position.round()
		piece.size = dst.size.round() + Vector2(0.5, 0)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(piece)
	return root


## Ornate progress bar. Returns {root, fill, track_w} — resize `fill.size.x`
## between 0..track_w to show progress. kind: "red" | "green" | "gold".
## Track and fill are the same 3-slice pill; the fill sits in a clipping
## holder (the returned `fill`), so its art never deforms while revealing.
static func make_bar(rect: Rect2, kind: String = "gold") -> Dictionary:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track_texture := kit_texture("bar_track.png")
	var fill_texture := kit_texture("bar_fill_%s.png" % kind)
	if track_texture != null and fill_texture != null:
		root.add_child(make_hslice(rect.size, "bar_track.png"))
		var holder := Control.new()
		holder.size = rect.size
		holder.clip_contents = true
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(holder)
		holder.add_child(make_hslice(rect.size, "bar_fill_%s.png" % kind))
		return {"root": root, "fill": holder, "track_w": rect.size.x, "track_h": rect.size.y}

	var track_bg := ColorRect.new()
	track_bg.color = Color(0.08, 0.08, 0.16, 0.95)
	track_bg.size = rect.size
	root.add_child(track_bg)
	var fill_flat := ColorRect.new()
	match kind:
		"red": fill_flat.color = Color(0.86, 0.26, 0.26)
		"green": fill_flat.color = Color(0.36, 0.78, 0.34)
		_: fill_flat.color = COLOR_ACCENT
	fill_flat.position = Vector2(1, 1)
	fill_flat.size = rect.size - Vector2(2, 2)
	root.add_child(fill_flat)
	return {"root": root, "fill": fill_flat, "track_w": rect.size.x - 2.0, "track_h": rect.size.y - 2.0}


# ── Legacy loaders ────────────────────────────────────────────────────────────
static func cursor_texture() -> Texture2D:
	var kit := kit_texture("cursor_gem.png")
	if kit != null:
		return kit
	return load(TEX_CURSOR) if ResourceLoader.exists(TEX_CURSOR) else null


static func banner_texture() -> Texture2D:
	return load(TEX_BANNER) if ResourceLoader.exists(TEX_BANNER) else null


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
