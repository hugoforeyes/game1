extends CharacterBody2D

const SPEED_WALK := 144.0
const SPEED_RUN  := 252.0
const SHEET_PATH := "res://assets/sprites/player/godot_sheet.png"
const H_FRAMES := 4
const V_FRAMES := 4
const FPS := 8.0

@onready var camera: Camera2D = $Camera2D
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _last_anim := "walk_down"

func _ready() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 32 * 36   # 1152px
	camera.limit_bottom = 32 * 36 # 1152px
	_setup_sprite_frames()

func _setup_sprite_frames() -> void:
	var texture := load(SHEET_PATH) as Texture2D
	if texture == null:
		push_error("Spritesheet not found: " + SHEET_PATH)
		return

	var frame_w := texture.get_width()  / H_FRAMES
	var frame_h := texture.get_height() / V_FRAMES

	# Row order matches the sheet: down=0, up=1, right=2, left=3
	var anim_rows := {
		"walk_down":  0,
		"walk_up":    1,
		"walk_right": 2,
		"walk_left":  3,
	}

	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name: String in anim_rows:
		var row: int = anim_rows[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, FPS)
		frames.set_animation_loop(anim_name, true)
		for col in H_FRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = frames
	anim_sprite.play(_last_anim)

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := SPEED_RUN if Input.is_action_pressed("run") else SPEED_WALK
	velocity = direction * speed
	move_and_slide()
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
