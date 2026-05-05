extends Node

const TILE_SIZE := 36
const TEX_SIZE  := 128

var _canvas_mod:    CanvasModulate  = null
var _lights:        Array[PointLight2D] = []
var _light_data:    Array[Dictionary]   = []
var _dynamic_nodes: Array[Node]         = []
var _shared_tex:    ImageTexture        = null
var _time:          float               = 0.0

# ── Public API ────────────────────────────────────────────────────────────────

func initialize(
	world_node:       Node2D,
	package_data:     Dictionary,
	map_pixel_size:   Vector2,
	occluder_parent:  Node2D,
	solid_instances:  Array[Dictionary],
) -> void:
	_lights.clear()
	_light_data.clear()

	_shared_tex = _make_radial_texture()
	_setup_ambient(world_node, package_data)
	_spawn_instance_lights(world_node, package_data, map_pixel_size)
	_spawn_occluders(occluder_parent, solid_instances)

func _ready() -> void:
	add_to_group("lighting")

func get_dominant_light_pos(char_pos: Vector2) -> Vector2:
	var best_pos   := Vector2.ZERO
	var best_score := -INF
	for i in _lights.size():
		var light: PointLight2D = _lights[i]
		if not is_instance_valid(light):
			continue
		var dist: float = char_pos.distance_to(light.global_position)
		if dist < 1.0:
			dist = 1.0
		var score: float = (light.energy * light.texture_scale) / dist
		if score > best_score:
			best_score = score
			best_pos   = light.global_position
	return best_pos

func cleanup() -> void:
	for n in _dynamic_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_dynamic_nodes.clear()
	_lights.clear()
	_light_data.clear()
	_canvas_mod = null

# ── Process (flicker / pulse animation) ──────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	for i in _lights.size():
		_animate_light(_lights[i], _light_data[i], i)

func _animate_light(light: PointLight2D, cfg: Dictionary, idx: int) -> void:
	var t  := _time
	var be : float = light.get_meta("base_energy")
	var bs : float = light.get_meta("base_scale")
	match str(cfg.get("type", "")):
		"torch":
			var f := (
				sin(t * 11.7 + idx * 1.30) * 0.07 +
				sin(t * 23.3 + idx * 2.71) * 0.04 +
				sin(t *  7.1 + idx * 0.93) * 0.03
			)
			light.energy        = be * clampf(0.90 + f, 0.78, 1.12)
			light.texture_scale = bs * clampf(0.97 + sin(t * 9.2 + idx) * 0.03, 0.92, 1.05)
		"magic_orb":
			var p := sin(t * 1.5 + idx * 2.1) * 0.04 + sin(t * 0.7 + idx * 0.5) * 0.025
			light.energy = be * clampf(0.97 + p, 0.92, 1.06)
		"lantern":
			var p := sin(t * 0.9 + idx * 1.4) * 0.03
			light.energy = be * clampf(0.98 + p, 0.94, 1.04)

# ── Ambient ───────────────────────────────────────────────────────────────────

func _setup_ambient(world: Node2D, package_data: Dictionary) -> void:
	var lighting: Dictionary = package_data.get("lighting", {}) as Dictionary
	var level: float = float(lighting.get("base_light_level", 0.5))

	var dim     := level * 0.75
	var ambient := Color(dim * 0.82, dim * 0.90, dim * 1.0)

	_canvas_mod       = CanvasModulate.new()
	_canvas_mod.color = ambient
	world.add_child(_canvas_mod)
	_dynamic_nodes.append(_canvas_mod)

# ── Lights from placed instances ──────────────────────────────────────────────

func _spawn_instance_lights(world: Node2D, package_data: Dictionary, map_px: Vector2) -> void:
	# Build definition lookup
	var defs: Dictionary = {}
	for d in package_data.get("definitions", []):
		if d is Dictionary:
			defs[str((d as Dictionary).get("id", ""))] = d

	# Pass 1: collect every light source position + config
	var pending: Array[Dictionary] = []
	for raw in package_data.get("instances", []):
		if not (raw is Dictionary):
			continue
		var inst    := raw as Dictionary
		var def_id  := str(inst.get("definition_id", inst.get("id", "")))
		var def     := defs.get(def_id, {}) as Dictionary
		var purpose := str(def.get("purpose", ""))

		var cfg: Dictionary = _light_config(def_id, purpose)
		if cfg.is_empty():
			continue

		var pos_tile:   Dictionary = inst.get("position_tile", {}) as Dictionary
		var size_tiles: Dictionary = def.get("size_tiles", {"w": 1, "h": 1}) as Dictionary
		var tx: float = float(pos_tile.get("x", 0))
		var ty: float = float(pos_tile.get("y", 0))
		var sw: float = float(max(int(size_tiles.get("w", 1)), 1))
		var sh: float = float(max(int(size_tiles.get("h", 1)), 1))
		var pixel_pos := Vector2((tx + sw * 0.5) * TILE_SIZE, (ty + sh * 0.5) * TILE_SIZE)

		pending.append({"cfg": cfg, "pos": pixel_pos})

	# Collect all positions for the adaptive radius calculation
	var all_pos: Array[Vector2] = []
	for item in pending:
		all_pos.append(item.get("pos", Vector2.ZERO) as Vector2)

	# Minimum radius so all lights together cover 70% of the map.
	# Each light is a circle: area = π r². Solving for r:
	#   N × π × r² = 0.70 × map_tiles   →   r = sqrt(0.70 × map_tiles / (N × π))
	var map_tiles: float = (map_px.x / TILE_SIZE) * (map_px.y / TILE_SIZE)
	var n_lights: float  = max(float(all_pos.size()), 1.0)
	var min_r: float     = sqrt((0.70 * map_tiles) / (n_lights * PI))

	# Pass 2: spawn each light — radius is max(adaptive gap-fill, coverage minimum)
	for item in pending:
		var cfg: Dictionary  = item.get("cfg", {}) as Dictionary
		var pos: Vector2     = item.get("pos", Vector2.ZERO) as Vector2
		var base_r: float    = float(cfg.get("radius_tiles", 4.0))
		var adapted_r: float = _adaptive_radius(pos, all_pos, base_r)
		var final_r: float   = maxf(adapted_r, min_r)

		var final_cfg: Dictionary = cfg.duplicate()
		final_cfg["radius_tiles"] = final_r

		var light: PointLight2D = _build_light(final_cfg, pos)
		world.add_child(light)
		_lights.append(light)
		_light_data.append(final_cfg)
		_dynamic_nodes.append(light)

# Expand radius to cover 55% of the gap to the nearest other light,
# clamped between base_r and 2× base_r so no single light dominates.
func _adaptive_radius(pos: Vector2, all_pos: Array[Vector2], base_r: float) -> float:
	var min_dist: float = INF
	for other in all_pos:
		var d: float = pos.distance_to(other)
		if d > 0.1 and d < min_dist:
			min_dist = d
	if min_dist == INF:
		return base_r
	var adaptive: float = (min_dist * 0.55) / TILE_SIZE
	return clampf(adaptive, base_r, base_r * 2.0)

# Returns a light config dict for an instance, or empty dict if it emits no light.
func _light_config(def_id: String, purpose: String) -> Dictionary:
	if "magic_orb" in def_id or purpose == "lighting":
		return {
			"type": "magic_orb", "color_hint": "cool",
			"radius_tiles": 6.0, "intensity": 0.85, "shadows": true,
		}
	if "torch" in def_id:
		return {
			"type": "torch", "color_hint": "warm",
			"radius_tiles": 6.0, "intensity": 0.75, "shadows": true,
		}
	if "blue_lantern" in def_id:
		return {
			"type": "lantern", "color_hint": "cool",
			"radius_tiles": 3.5, "intensity": 0.55, "shadows": false,
		}
	if "memory_lantern" in def_id:
		return {
			"type": "lantern", "color_hint": "eerie",
			"radius_tiles": 2.5, "intensity": 0.40, "shadows": false,
		}
	return {}

func _build_light(cfg: Dictionary, pixel_pos: Vector2) -> PointLight2D:
	var light := PointLight2D.new()
	light.position = pixel_pos

	var hint      := str(cfg.get("color_hint", "warm"))
	var intensity := float(cfg.get("intensity", 0.6))
	light.color   = _color_for_hint(hint)

	var base_e        := intensity * 1.2
	light.energy      = base_e

	var radius_tiles  := float(cfg.get("radius_tiles", 4))
	var base_s        := (radius_tiles * TILE_SIZE) / (TEX_SIZE * 0.5) * 1.5
	light.texture_scale = base_s

	light.texture    = _shared_tex
	light.blend_mode = Light2D.BLEND_MODE_ADD

	var cast_shadows := bool(cfg.get("shadows", false))
	light.shadow_enabled = cast_shadows
	if cast_shadows:
		light.shadow_filter        = Light2D.SHADOW_FILTER_PCF5
		light.shadow_filter_smooth = 2.0
		light.shadow_color         = Color(0.0, 0.0, 0.05, 0.70)

	light.set_meta("base_energy", base_e)
	light.set_meta("base_scale",  base_s)
	return light

# ── Occluders for solid props ─────────────────────────────────────────────────

func _spawn_occluders(parent: Node2D, solid_instances: Array[Dictionary]) -> void:
	for info in solid_instances:
		var def_id := str(info.get("definition_id", ""))
		if not _light_config(def_id, "").is_empty():
			continue
		var pos_tile:   Dictionary = info.get("position_tile", {}) as Dictionary
		var size_tiles: Dictionary = info.get("size_tiles", {}) as Dictionary
		var tw: int = max(int(size_tiles.get("w", 1)), 1)
		var th: int = max(int(size_tiles.get("h", 1)), 1)
		if tw * th < 4:
			continue
		var tx: int = int(pos_tile.get("x", 0))
		var ty: int = int(pos_tile.get("y", 0))

		var sprite_file: String = str(info.get("sprite_file", ""))
		var hull: PackedVector2Array = _pixel_hull_for_sprite(sprite_file)
		if hull.size() >= 3:
			_add_occluder_hull(parent, tx, ty, hull)
		else:
			_add_occluder_rect(parent, tx, ty, tw, th)

func _pixel_hull_for_sprite(sprite_file: String) -> PackedVector2Array:
	if sprite_file.is_empty():
		return PackedVector2Array()
	var full_path := GameManager.get_scene_asset_path(sprite_file)
	var tex: Texture2D = GameManager.load_texture(full_path)
	if tex == null:
		return PackedVector2Array()
	var img: Image = tex.get_image()
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		return PackedVector2Array()
	if img.get_format() >= Image.FORMAT_DXT1:
		return PackedVector2Array()
	return _convex_hull_of_opaque(img)

func _convex_hull_of_opaque(img: Image) -> PackedVector2Array:
	var w := img.get_width()
	var h := img.get_height()
	# Sample ~24 steps per axis — enough resolution without too many hull points
	var step: int = max(int(min(w, h) / 24), 1)
	var pts: Array[Vector2] = []
	for y in range(0, h, step):
		for x in range(0, w, step):
			if img.get_pixel(x, y).a > 0.15:
				pts.append(Vector2(x, y))
	if pts.size() < 3:
		return PackedVector2Array()
	return _convex_hull(pts)

# Gift-wrapping (Jarvis march) convex hull on a list of 2-D points.
func _convex_hull(pts: Array[Vector2]) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return PackedVector2Array(pts)
	# Find leftmost (then topmost) point as start
	var start := 0
	for i in range(1, n):
		if pts[i].x < pts[start].x or (pts[i].x == pts[start].x and pts[i].y < pts[start].y):
			start = i
	var hull: Array[Vector2] = []
	var cur := start
	while true:
		hull.append(pts[cur])
		var nxt := (cur + 1) % n
		for i in range(n):
			if i == cur:
				continue
			# Negative cross product → pts[i] is more counter-clockwise
			if (pts[nxt] - pts[cur]).cross(pts[i] - pts[cur]) < 0.0:
				nxt = i
		cur = nxt
		if cur == start or hull.size() > n:
			break
	return PackedVector2Array(hull)

func _add_occluder_hull(parent: Node2D, tx: int, ty: int, hull: PackedVector2Array) -> void:
	var occ  := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = hull
	occ.occluder = poly
	occ.position = Vector2(float(tx) * TILE_SIZE, float(ty) * TILE_SIZE)
	parent.add_child(occ)
	_dynamic_nodes.append(occ)

func _add_occluder_rect(parent: Node2D, tx: int, ty: int, tw: int, th: int) -> void:
	var occ  := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	const INSET := 4.0
	var pw := float(tw) * TILE_SIZE - INSET * 2.0
	var ph := float(th) * TILE_SIZE - INSET * 2.0
	poly.polygon = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(pw, 0.0),
		Vector2(pw,  ph),  Vector2(0.0, ph),
	])
	occ.occluder = poly
	occ.position = Vector2(float(tx) * TILE_SIZE + INSET, float(ty) * TILE_SIZE + INSET)
	parent.add_child(occ)
	_dynamic_nodes.append(occ)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _color_for_hint(hint: String) -> Color:
	match hint:
		"cool":  return Color(0.60, 0.80, 1.00)
		"eerie": return Color(0.38, 1.00, 0.84)
		"warm":  return Color(1.00, 0.68, 0.28)
		_:       return Color(1.00, 0.90, 0.70)

func _make_radial_texture() -> ImageTexture:
	var img  := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEX_SIZE / 2.0
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var t: float = clampf(Vector2(x - half, y - half).length() / half, 0.0, 1.0)
			# Exponential falloff: bright centre, very gradual fade to zero
			var a: float = pow(1.0 - t, 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
