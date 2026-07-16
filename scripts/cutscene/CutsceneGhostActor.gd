extends Node2D
## A cutscene-only apparition: a translucent silhouette standing in for a dead or
## absent figure declared by the backend cutscene plan (`ghost_actors`). Spawned by
## CutscenePlayer for the duration of one cutscene and freed when it finishes — it
## never exists in normal gameplay, is never talkable, and never collides.
##
## It deliberately borrows an existing walk sheet (the player's) purely as a body
## SILHOUETTE: the ghost tint + transparency make it read as a memory of the dead,
## not as any specific living character.

const GHOST_TINT := Color(0.72, 0.88, 1.0, 0.58)

var npc_data: Dictionary = {}  # {id, name, ghost: true} — CutscenePlayer._find_actor matches on id
var anim_sprite: AnimatedSprite2D = null


func setup(ghost_id: String, ghost_name: String, frames: SpriteFrames) -> void:
	npc_data = {"id": ghost_id, "name": ghost_name, "ghost": true}
	anim_sprite = AnimatedSprite2D.new()
	if frames != null:
		anim_sprite.sprite_frames = frames
		if frames.has_animation("walk_down"):
			anim_sprite.animation = "walk_down"
	anim_sprite.modulate = GHOST_TINT
	anim_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(anim_sprite)
