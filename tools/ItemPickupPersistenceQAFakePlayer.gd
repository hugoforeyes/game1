extends Node2D
## Minimal stand-in for the real Player — ItemPickup._on_body_entered only
## duck-types `body.get("camera") == null` to recognize the player.

var camera: Camera2D = Camera2D.new()
