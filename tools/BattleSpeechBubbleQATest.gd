extends Node
## Headless QA for native-size short / medium / long shout-out templates.
## Run:
##   godot --headless --path . res://tools/BattleSpeechBubbleQATest.tscn

const BubbleScript := preload("res://scripts/battle/BattleSpeechBubble.gd")

var _failures := 0


func _ready() -> void:
	var ultra_quote := "Aaa"
	var very_short_quote := "Đau quá"
	var short_quote := "You will regret this!"
	var medium_quote := "The forest remembers every wound you made."
	var long_quote := "A Smoke Echo flickers into your path, repeating a moment that no longer exists."

	var ultra_bubble: Control = _make_bubble(ultra_quote)
	var very_short_bubble: Control = _make_bubble(very_short_quote)
	var short_bubble: Control = _make_bubble(short_quote)
	var medium_bubble: Control = _make_bubble(medium_quote)
	var long_bubble: Control = _make_bubble(long_quote)
	await get_tree().process_frame

	_check(ultra_bubble.template_id() == "compact", "ultra-short bark must use the compact template")
	_check(very_short_bubble.template_id() == "compact", "very-short bark should share the compact template")
	_check(short_bubble.template_id() == "short", "normal short bark must retain the short template")
	_check(medium_bubble.template_id() == "medium", "medium bark must use the medium template")
	_check(long_bubble.template_id() == "long", "long bark must use the long template")
	_check(ultra_bubble.size == Vector2(158.0, 118.0), "compact template must remain at native 158x118")
	_check(short_bubble.size == Vector2(240.0, 118.0), "short template must remain at native 240x118")
	_check(medium_bubble.size == Vector2(310.0, 147.0), "medium template must remain at native 310x147")
	_check(long_bubble.size == Vector2(410.0, 146.0), "long template must remain at native 410x146")

	for bubble in [ultra_bubble, very_short_bubble, short_bubble, medium_bubble, long_bubble]:
		_check(bubble.scale == Vector2.ONE, "bubble control must not be scaled")
		_check(bubble._frame.scale == Vector2.ONE, "template texture must not be scaled")
		_check(bubble._frame.size == bubble._frame.texture.get_size(), "frame must equal native texture dimensions")
		_check(_count_labels(bubble) == 1, "bubble must contain dialogue only — no enemy-name label")
		_check(bubble._label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,
			"dialogue must never use ellipsis or trimming")

	var original_size: Vector2 = medium_bubble.size
	var right_tip: Vector2 = medium_bubble.pointer_tip_local()
	var right_texture: Texture2D = medium_bubble._frame.texture
	medium_bubble.set_pointer_side(BubbleScript.PointerSide.LEFT)
	var left_tip: Vector2 = medium_bubble.pointer_tip_local()
	_check(medium_bubble.size == original_size, "mirroring must not change template size")
	_check(medium_bubble._frame.texture != right_texture, "left display must use a pre-rendered mirrored asset")
	_check(absf(left_tip.x - (original_size.x - 1.0 - right_tip.x)) < 0.01,
		"mirrored pointer tip must be pixel-symmetric")
	_check(absf(left_tip.y - right_tip.y) < 0.01, "mirroring must preserve pointer height")

	var vietnamese := _make_bubble("Ánh trăng đã ghi dấu máu của ngươi — ký ức ấy sẽ không bao giờ biến mất.")
	await get_tree().process_frame
	_check(vietnamese._label.text.begins_with("Ánh trăng"), "Vietnamese dialogue must remain lossless")
	_check(vietnamese.template_id() == "long", "long Vietnamese bark should route to the long template")
	_check(vietnamese._font_size >= vietnamese.MIN_FONT_SIZE, "font must stay at or above its readability floor")

	for child in get_children():
		if child is Control:
			child.queue_free()
	if _failures == 0:
		print("[BattleSpeechBubbleQA] ALL CHECKS PASSED")
	else:
		push_error("[BattleSpeechBubbleQA] %d CHECK(S) FAILED" % _failures)
	get_tree().quit(_failures)


func _make_bubble(text: String) -> Control:
	var bubble: Control = BubbleScript.new()
	add_child(bubble)
	bubble.setup(text)
	return bubble


func _count_labels(node: Node) -> int:
	var result := 1 if node is Label else 0
	for child in node.get_children():
		result += _count_labels(child)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[BattleSpeechBubbleQA] %s" % message)
