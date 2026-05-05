extends CharacterBody2D

const SPEED_WALK := 144.0
const SPEED_RUN  := 252.0
const FPS := 8.0

@onready var camera: Camera2D = $Camera2D
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $Shadow

var _last_anim: String = "walk_down"
var _lighting_sys: Node = null

func _ready() -> void:
	_setup_shadow()
	_setup_sprite_frames()
	_lighting_sys = get_tree().get_first_node_in_group("lighting")

func _setup_shadow() -> void:
	var rx: float = 10.0  # bán kính ngang
	var ry: float = 4.0   # bán kính dọc (dẹt xuống trông như bóng)
	var segments: int = 16
	var points: PackedVector2Array = PackedVector2Array()
	for i in segments:
		var angle: float = (TAU / segments) * i
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	shadow.polygon = points

func _setup_sprite_frames() -> void:
	var sprite_path: String = GameManager.get_player_sprite_path()
	var texture: Texture2D = GameManager.load_texture(sprite_path)
	if texture == null:
		push_error("Spritesheet not found: " + sprite_path)
		return

	var anim_rows: Dictionary = {
		"walk_down":  0,
		"walk_up":    1,
		"walk_right": 2,
		"walk_left":  3,
	}
	var grid: Vector2i = GameManager.infer_player_sprite_grid(texture, sprite_path)
	var frame_size: int = GameManager.CHARACTER_FRAME_SIZE

	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name: String in anim_rows:
		var row: int = anim_rows[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, FPS)
		frames.set_animation_loop(anim_name, true)
		for col in grid.x:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_size, row * frame_size, frame_size, frame_size)
			frames.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = frames
	anim_sprite.play(_last_anim)

func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = SPEED_RUN if Input.is_action_pressed("run") else SPEED_WALK
	velocity = direction * speed
	move_and_slide()
	_update_animation(direction)
	_update_shadow()

func _update_shadow() -> void:
	if _lighting_sys == null or not is_instance_valid(_lighting_sys):
		_lighting_sys = get_tree().get_first_node_in_group("lighting")
	if _lighting_sys == null:
		return
	var light_pos: Vector2 = _lighting_sys.get_dominant_light_pos(global_position)
	if light_pos == Vector2.ZERO:
		shadow.position = Vector2(0.0, 14.0)
		shadow.rotation = 0.0
		shadow.modulate.a = 0.35
		return
	var to_char: Vector2 = global_position - light_pos
	var dist: float = to_char.length()
	var dir: Vector2 = to_char.normalized() if dist > 1.0 else Vector2(0.0, 1.0)
	var tile_dist: float = dist / 36.0
	var offset_px: float = clampf(tile_dist * 1.8, 2.0, 12.0)
	shadow.position = Vector2(0.0, 14.0) + dir * offset_px
	shadow.rotation = dir.angle()
	shadow.modulate.a = clampf(0.65 - tile_dist * 0.04, 0.15, 0.60)

func _update_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		anim_sprite.pause()
		return

	var anim: String
	if abs(direction.x) >= abs(direction.y):
		anim = "walk_right" if direction.x > 0 else "walk_left"
	else:
		anim = "walk_down" if direction.y > 0 else "walk_up"

	if anim != _last_anim:
		_last_anim = anim
		anim_sprite.play(anim)
	elif not anim_sprite.is_playing():
		anim_sprite.play(anim)
