extends CharacterBody2D

const SPEED_WALK := 144.0
const SPEED_RUN  := 252.0
const FPS := 8.0
const SORT_FEET_OFFSET := 14

@onready var camera: Camera2D = $Camera2D
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $Shadow

var _last_anim: String = "walk_down"

func _ready() -> void:
	_setup_shadow()
	_setup_sprite_frames()

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
	var frame_w: int = texture.get_width() / grid.x
	var frame_h: int = texture.get_height() / grid.y

	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name: String in anim_rows:
		var row: int = anim_rows[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, FPS)
		frames.set_animation_loop(anim_name, true)
		if grid.y == 1:
			row = 0
		for col in grid.x:
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = frames
	anim_sprite.play(_last_anim)

func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed: float = SPEED_RUN if Input.is_action_pressed("run") else SPEED_WALK
	velocity = direction * speed
	move_and_slide()
	z_index = int(global_position.y + SORT_FEET_OFFSET)
	_update_animation(direction)

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
