extends Node2D
## Frameless AAA zone-transition marker: the destination name in luminous gold
## serif small-caps, a hairline rule with a diamond accent, and a chevron
## pointing along the travel direction. No panel, no box — just typography
## floating in the world (see assets/ui/zone_marker_v1/mockups/).
##
## Shared by ZoneExitPortal (edge exits — chevron points at the map edge) and
## InteriorExit (door/building entrances — chevron points down at the door).
## The node origin is the chevron; the name + rule stack away from it, so
## callers place this node at the point the player travels toward.
##
## Animation: a one-shot entrance reveal (name drifts in, the rule draws
## itself outward from center, the chevron settles last), then an idle loop —
## breathing alpha, a periodic gold glint sweeping across the letters
## (per-character), a beckoning chevron bob along the travel direction, and a
## twinkling rule diamond.

const FONT_SIZE_BASE := 24
const FONT_SIZE_MIN := 14
const MAX_TEXT_WIDTH := 400.0
const LETTER_SPACING := 3
const CHEVRON_SIZE := Vector2(30.0, 17.0)
const CHEVRON_TEXTURE_PATH := "res://assets/ui/zone_marker_v1/chevron.png"
const GAP_CHEVRON := 9.0
const GAP_RULE := 7.0
const RULE_WIDTH_RATIO := 0.86

const REVEAL_START_TILES := 7.0
const REVEAL_FULL_TILES := 3.2
const ALPHA_FAR := 0.62

const INTRO_DURATION := 1.15
const INTRO_DRIFT := 7.0
const GLINT_PERIOD := 5.2
const GLINT_DURATION := 1.15
const GLINT_SIGMA := 0.085
const BECKON_AMPLITUDE := 2.8

const GOLD := Color(1.0, 0.80, 0.38, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.92, 0.62, 1.0)
const GOLD_GLINT := Color(1.0, 0.98, 0.88, 1.0)
const GOLD_DEEP := Color(0.86, 0.60, 0.24, 1.0)
const SHADOW := Color(0.02, 0.015, 0.01, 0.85)

var _text := ""
var _travel := Vector2.DOWN
var _player: Node2D = null
var _font: FontVariation = null
var _font_size := FONT_SIZE_BASE
var _text_size := Vector2.ZERO
var _chars: PackedStringArray = PackedStringArray()
var _char_starts: PackedFloat32Array = PackedFloat32Array()
var _char_span := 0.0
var _chevron_texture: Texture2D = null
var _time := 0.0
var _age := 0.0
var _alpha := 0.0
var _glint_phase := 0.0


func setup(label_text: String, travel_dir: Vector2, player: Node2D) -> void:
	_text = label_text.strip_edges().to_upper()
	_travel = _cardinal(travel_dir)
	_player = player
	name = "ZoneMarker"
	z_as_relative = false
	z_index = 18


func _ready() -> void:
	var base: Font = UiKit.title_font()
	if base == null:
		base = ThemeDB.fallback_font
	_font = FontVariation.new()
	_font.base_font = base
	_font.variation_embolden = 0.28
	_font.spacing_glyph = LETTER_SPACING
	if ResourceLoader.exists(CHEVRON_TEXTURE_PATH):
		_chevron_texture = load(CHEVRON_TEXTURE_PATH) as Texture2D
	_fit_font_size()
	# Desynchronise glint sweeps between markers in the same zone.
	_glint_phase = fposmod(float(_text.hash() % 1000) * 0.013, GLINT_PERIOD)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_age += delta
	var target := _target_alpha()
	_alpha = lerpf(_alpha, target, minf(delta * 4.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if _text.is_empty() or _font == null or _alpha <= 0.02:
		return
	var breath := 0.94 + 0.06 * sin(_time * 1.7)
	var a := _alpha * breath

	# Entrance reveal envelope (one-shot, eased).
	var intro := clampf(_age / INTRO_DURATION, 0.0, 1.0)
	var intro_e := 1.0 - pow(1.0 - intro, 3.0)
	var drift := -_travel * INTRO_DRIFT * (1.0 - intro_e)

	var name_center := _name_center() + drift
	var rule_center := Vector2(name_center.x, name_center.y + _text_size.y * 0.5 + GAP_RULE)
	_draw_name(name_center, a * smoothstep(0.0, 0.5, intro))
	_draw_rule(rule_center, _text_size.x * RULE_WIDTH_RATIO * smoothstep(0.2, 0.85, intro_e), a * smoothstep(0.2, 0.7, intro))
	_draw_chevron_glyph(a * smoothstep(0.45, 1.0, intro), intro_e)
	_draw_sparks(name_center, a * smoothstep(0.75, 1.0, intro))


# ── Layout ────────────────────────────────────────────────────────────────────
## Content stacks away from the travel direction; the chevron sits at origin.
func _name_center() -> Vector2:
	var block_h := _text_size.y + GAP_RULE + 3.0  # name + rule block height
	match _travel:
		Vector2.UP:
			return Vector2(0.0, CHEVRON_SIZE.y * 0.5 + GAP_CHEVRON + _text_size.y * 0.5)
		Vector2.DOWN:
			return Vector2(0.0, -(CHEVRON_SIZE.y * 0.5 + GAP_CHEVRON + block_h - _text_size.y * 0.5))
		Vector2.RIGHT:
			return Vector2(-(CHEVRON_SIZE.x * 0.5 + GAP_CHEVRON + _text_size.x * 0.5), -3.0)
		Vector2.LEFT:
			return Vector2(CHEVRON_SIZE.x * 0.5 + GAP_CHEVRON + _text_size.x * 0.5, -3.0)
	return Vector2(0.0, -(CHEVRON_SIZE.y * 0.5 + GAP_CHEVRON + block_h - _text_size.y * 0.5))


# ── Pieces ────────────────────────────────────────────────────────────────────
func _draw_name(center: Vector2, alpha: float) -> void:
	if alpha <= 0.01:
		return
	var pos := Vector2(center.x - _text_size.x * 0.5, center.y + _text_size.y * 0.5 - _font.get_descent(_font_size))
	# Soft dark halo so the gold stays legible over bright terrain too.
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var off := Vector2(cos(ang), sin(ang)) * 2.0
		_string(pos + off, _with_alpha(SHADOW, 0.34 * alpha))
	# Crisp dark drop shadow.
	_string(pos + Vector2(1.5, 2.0), _with_alpha(SHADOW, alpha))
	# Soft gold outer glow.
	for i in range(6):
		var ang := TAU * (float(i) + 0.5) / 6.0
		var off := Vector2(cos(ang), sin(ang)) * 2.4
		_string(pos + off, _with_alpha(GOLD, 0.05 * alpha))
	# Body + top sheen. While the periodic glint sweeps across, the body is
	# drawn per character so individual letters can catch the light; the rest
	# of the time a plain full-string draw is both faster and shaping-exact.
	var glint_u := _glint_u()
	if glint_u < 0.0 or _char_span <= 0.0:
		_string(pos, _with_alpha(GOLD, alpha))
		_string(pos + Vector2(0.0, -0.6), _with_alpha(GOLD_BRIGHT, 0.55 * alpha))
		return
	# Scale per-char starts so endpoints match the shaped full-string width
	# (guards against kerning drift versus the soft layers underneath).
	var k := _text_size.x / _char_span
	for i in range(_chars.size()):
		var x0 := pos.x + _char_starts[i] * k
		var cu := _char_starts[i] / maxf(_char_span, 0.001)
		var boost := exp(-pow((cu - glint_u) / GLINT_SIGMA, 2.0))
		var body := GOLD.lerp(GOLD_GLINT, boost * 0.85)
		var sheen := GOLD_BRIGHT.lerp(GOLD_GLINT, boost)
		draw_string(_font, Vector2(x0, pos.y), _chars[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, _with_alpha(body, alpha))
		draw_string(_font, Vector2(x0, pos.y - 0.6), _chars[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, _with_alpha(sheen, 0.55 * alpha))


func _string(pos: Vector2, color: Color) -> void:
	draw_string(_font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, color)


## The sweep position in 0..1 across the name, or -1 while idle between sweeps.
func _glint_u() -> float:
	var t := fposmod(_time + _glint_phase, GLINT_PERIOD)
	if t > GLINT_DURATION:
		return -1.0
	return lerpf(-0.18, 1.18, t / GLINT_DURATION)


func _draw_rule(center: Vector2, width: float, alpha: float) -> void:
	if alpha <= 0.01 or width <= 4.0:
		return
	var half := width * 0.5
	var points := PackedVector2Array()
	var shadow_points := PackedVector2Array()
	var colors := PackedColorArray()
	var shadow_colors := PackedColorArray()
	var steps := 24
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var x := lerpf(-half, half, u)
		points.append(center + Vector2(x, 0.0))
		shadow_points.append(center + Vector2(x, 1.0))
		var fade := 1.0 - pow(absf(u - 0.5) * 2.0, 1.6)
		colors.append(_with_alpha(GOLD_BRIGHT, 0.62 * fade * alpha))
		shadow_colors.append(_with_alpha(SHADOW, 0.55 * fade * alpha))
	draw_polyline_colors(shadow_points, shadow_colors, 1.2, true)
	draw_polyline_colors(points, colors, 1.0, true)
	# Center diamond accent — twinkles gently.
	var twinkle := maxf(0.0, sin(_time * 1.6))
	var d := 3.4 * (1.0 + 0.12 * sin(_time * 2.1))
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -d), center + Vector2(d, 0.0),
		center + Vector2(0.0, d), center + Vector2(-d, 0.0),
	])
	draw_polygon(diamond, _solid(_with_alpha(GOLD, (0.9 + 0.1 * twinkle) * alpha), 4))
	draw_circle(center, 1.1, _with_alpha(GOLD_BRIGHT, alpha))
	# Tiny glint rays at the twinkle peak.
	var flare := pow(twinkle, 3.0)
	if flare > 0.05:
		var r := 5.5 * flare
		var c := _with_alpha(GOLD_GLINT, 0.55 * flare * alpha)
		draw_line(center + Vector2(-r, 0), center + Vector2(r, 0), c, 1.0, true)
		draw_line(center + Vector2(0, -r), center + Vector2(0, r), c, 1.0, true)


func _draw_chevron_glyph(alpha: float, intro_e: float) -> void:
	if alpha <= 0.01:
		return
	var pulse := 0.82 + 0.18 * sin(_time * 2.6)
	# Beckoning bob along the travel direction + entrance settle from the name side.
	var beckon := _travel * BECKON_AMPLITUDE * (0.5 + 0.5 * sin(_time * 2.3))
	var origin := beckon - _travel * 9.0 * (1.0 - intro_e)
	if _chevron_texture != null:
		var tex_size := _chevron_texture.get_size()
		var size := Vector2(CHEVRON_SIZE.x, CHEVRON_SIZE.x * tex_size.y / maxf(tex_size.x, 1.0))
		draw_set_transform(origin, _chevron_rotation(), Vector2.ONE)
		draw_texture_rect(_chevron_texture, Rect2(-size * 0.5, size), false, _with_alpha(Color.WHITE, alpha * pulse))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_set_transform(origin, 0.0, Vector2.ONE)
	_draw_chevron_fallback(alpha, pulse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Procedural fallback: two nested thin chevron strokes + a diamond spark
## just beyond the tip, matching the generated ornament.
func _draw_chevron_fallback(alpha: float, pulse: float) -> void:
	var dir := _travel
	var tangent := Vector2(-dir.y, dir.x)
	for layer in range(2):
		var scale := 1.0 - float(layer) * 0.42
		var back := -dir * CHEVRON_SIZE.y * 0.5 * scale
		var tip := dir * CHEVRON_SIZE.y * 0.28 * scale
		var wing := tangent * CHEVRON_SIZE.x * 0.5 * scale
		var color := _with_alpha(GOLD_BRIGHT if layer == 0 else GOLD, (0.92 - 0.25 * float(layer)) * alpha * pulse)
		draw_polyline(PackedVector2Array([back + wing, tip, back - wing]), color, 1.6, true)
	var spark_center := dir * (CHEVRON_SIZE.y * 0.62)
	var d := 2.2
	var diamond := PackedVector2Array([
		spark_center + Vector2(0.0, -d), spark_center + Vector2(d, 0.0),
		spark_center + Vector2(0.0, d), spark_center + Vector2(-d, 0.0),
	])
	draw_polygon(diamond, _solid(_with_alpha(GOLD_BRIGHT, 0.9 * alpha * pulse), 4))


func _draw_sparks(name_center: Vector2, alpha: float) -> void:
	if alpha <= 0.01:
		return
	for i in range(5):
		var phase := fmod(_time * 0.55 + float(i) * 0.73, 1.0)
		var ang := TAU * (float(i) / 5.0 + _time * 0.03)
		var radius := Vector2(_text_size.x * 0.62 + 10.0, _text_size.y * 1.4 + 8.0)
		var pos := name_center + Vector2(cos(ang) * radius.x, sin(ang) * radius.y)
		var twinkle := sin(phase * PI)
		var size := 1.2 + 1.6 * twinkle
		var color := _with_alpha(GOLD_BRIGHT, 0.30 * twinkle * alpha)
		draw_line(pos + Vector2(-size, 0), pos + Vector2(size, 0), color, 1.0, true)
		draw_line(pos + Vector2(0, -size), pos + Vector2(0, size), color, 1.0, true)


# ── Helpers ───────────────────────────────────────────────────────────────────
func _fit_font_size() -> void:
	_font_size = FONT_SIZE_BASE
	while _font_size > FONT_SIZE_MIN and _measure().x > MAX_TEXT_WIDTH:
		_font_size -= 1
	_text_size = _measure()
	# Per-character start offsets for the glint sweep. Single-char
	# get_string_size omits the inter-glyph LETTER_SPACING that full-string
	# shaping applies, so the gap is added back manually per advance.
	_chars.clear()
	_char_starts.clear()
	var x := 0.0
	for i in range(_text.length()):
		var ch := _text.substr(i, 1)
		_chars.append(ch)
		_char_starts.append(x)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x + float(LETTER_SPACING)
	_char_span = maxf(0.0, x - float(LETTER_SPACING))


func _measure() -> Vector2:
	return _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)


func _target_alpha() -> float:
	if _player == null or not is_instance_valid(_player):
		return ALPHA_FAR
	var dist_tiles := _player.global_position.distance_to(global_position) / float(GameManager.TILE_SIZE)
	if dist_tiles >= REVEAL_START_TILES:
		return ALPHA_FAR
	if dist_tiles <= REVEAL_FULL_TILES:
		return 1.0
	var t := (dist_tiles - REVEAL_FULL_TILES) / (REVEAL_START_TILES - REVEAL_FULL_TILES)
	return lerpf(1.0, ALPHA_FAR, t)


func _chevron_rotation() -> float:
	# The authored texture points DOWN.
	match _travel:
		Vector2.UP:
			return PI
		Vector2.RIGHT:
			return -PI * 0.5
		Vector2.LEFT:
			return PI * 0.5
	return 0.0


func _cardinal(dir: Vector2) -> Vector2:
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y >= 0.0 else Vector2.UP


func _with_alpha(color: Color, alpha_scale: float) -> Color:
	var c := color
	c.a *= alpha_scale
	return c


func _solid(color: Color, count: int) -> PackedColorArray:
	var colors := PackedColorArray()
	for _i in range(count):
		colors.append(color)
	return colors
