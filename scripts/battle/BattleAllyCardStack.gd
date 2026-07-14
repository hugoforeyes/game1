class_name BattleAllyCardStack
extends RefCounted
## Layout/focus controller for the party HUD. BattleScene still supplies card
## construction and data refresh callbacks; this class owns ordering and morphs.

const FULL_CARD_H := 112.0
const COMPACT_CARD_H := 74.0
const CARD_W := 312.0
const CARD_X := 2.0
const CARD_GAP := 6.0
const STACK_BOTTOM := 538.0
const TRANSITION_DURATION := 0.34

var focus_index: int = 0

var _host: Node
var _allies: Array[Dictionary]
var _cards: Array[Dictionary]
var _build_card: Callable
var _refresh_card: Callable
var _actor_down: Callable
var _effective_speed: Callable


func configure(
	host: Node,
	allies: Array[Dictionary],
	card_store: Array[Dictionary],
	build_card: Callable,
	refresh_card: Callable,
	actor_down: Callable,
	effective_speed: Callable,
) -> void:
	_host = host
	_allies = allies
	_cards = card_store
	_build_card = build_card
	_refresh_card = refresh_card
	_actor_down = actor_down
	_effective_speed = effective_speed


func build(round_queue: Array[Dictionary], queue_pos: int) -> void:
	_cards.clear()
	if _allies.is_empty():
		return
	focus_index = clampi(focus_index, 0, _allies.size() - 1)
	var rects := target_rects(focus_index, round_queue, queue_pos)
	for index in range(_allies.size()):
		_cards.append(_build_card.call(
			_allies[index], rects[index], index == focus_index))


## The nearest upcoming ally sits directly above the focused full card. Later
## turns climb upward; downed actors absent from the queue stay farthest away.
func upcoming_indices(
	requested_focus: int,
	round_queue: Array[Dictionary],
	queue_pos: int,
) -> Array[int]:
	var ordered: Array[int] = []
	if not round_queue.is_empty():
		for offset in range(1, round_queue.size() + 1):
			var position := (queue_pos + offset) % round_queue.size()
			var entry: Dictionary = round_queue[position]
			if str(entry.get("side", "")) != "ally":
				continue
			var index := int(entry.get("index", -1))
			if index < 0 or index >= _allies.size() \
					or index == requested_focus or ordered.has(index):
				continue
			ordered.append(index)

	var fallback: Array[int] = []
	for index in range(_allies.size()):
		if index != requested_focus and not ordered.has(index):
			fallback.append(index)
	fallback.sort_custom(func(a, b):
		var a_down := bool(_actor_down.call(_allies[a], true))
		var b_down := bool(_actor_down.call(_allies[b], true))
		if a_down != b_down:
			return not a_down
		var a_speed := int(_effective_speed.call(_allies[a]))
		var b_speed := int(_effective_speed.call(_allies[b]))
		return a < b if a_speed == b_speed else a_speed > b_speed
	)
	ordered.append_array(fallback)
	return ordered


func target_rects(
	requested_focus: int,
	round_queue: Array[Dictionary],
	queue_pos: int,
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	rects.resize(_allies.size())
	if _allies.is_empty():
		return rects
	requested_focus = clampi(requested_focus, 0, _allies.size() - 1)
	var full_y := STACK_BOTTOM - FULL_CARD_H
	rects[requested_focus] = Rect2(CARD_X, full_y, CARD_W, FULL_CARD_H)
	var upcoming := upcoming_indices(requested_focus, round_queue, queue_pos)
	for rank in range(upcoming.size()):
		var index := upcoming[rank]
		var y := full_y - CARD_GAP - COMPACT_CARD_H \
			- float(rank) * (COMPACT_CARD_H + CARD_GAP)
		rects[index] = Rect2(CARD_X, y, CARD_W, COMPACT_CARD_H)
	return rects


func set_active(
	ally: Variant,
	round_queue: Array[Dictionary],
	queue_pos: int,
) -> void:
	if ally is Dictionary:
		var active_index := _allies.find(ally)
		if active_index >= 0:
			var rects := target_rects(active_index, round_queue, queue_pos)
			if not _layout_matches(active_index, rects):
				_rebuild(active_index, round_queue, queue_pos, true)
				return

	for index in range(_cards.size()):
		var root: Control = _cards[index]["root"]
		var active: bool = ally is Dictionary and index < _allies.size() \
			and _allies[index] == ally
		var focus_tween := _host.create_tween()
		focus_tween.tween_property(
			root, "modulate", _target_modulate(index, active), 0.18,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func right_edge() -> float:
	return CARD_X + CARD_W


func bottom_edge() -> float:
	return STACK_BOTTOM


func _target_modulate(index: int, active: bool) -> Color:
	var down := index < _allies.size() and bool(_actor_down.call(_allies[index], true))
	var alpha := 0.55 if down else 1.0
	return Color(1.12, 1.08, 0.96, alpha) if active else Color(1.0, 1.0, 1.0, alpha)


func _layout_matches(requested_focus: int, rects: Array[Rect2]) -> bool:
	if _cards.size() != _allies.size() or rects.size() != _allies.size():
		return false
	for index in range(_cards.size()):
		var card: Dictionary = _cards[index]
		var current_rect: Rect2 = card.get("rect", Rect2())
		if bool(card.get("is_full", false)) != (index == requested_focus):
			return false
		if not current_rect.position.is_equal_approx(rects[index].position) \
				or not current_rect.size.is_equal_approx(rects[index].size):
			return false
	return true


func _rebuild(
	requested_focus: int,
	round_queue: Array[Dictionary],
	queue_pos: int,
	animate: bool,
) -> void:
	if _allies.is_empty():
		return
	requested_focus = clampi(requested_focus, 0, _allies.size() - 1)
	var target_layout := target_rects(requested_focus, round_queue, queue_pos)
	var old_cards: Array[Dictionary] = _cards.duplicate()
	var new_cards: Array[Dictionary] = []
	new_cards.resize(_allies.size())
	focus_index = requested_focus
	for index in range(_allies.size()):
		new_cards[index] = _build_card.call(
			_allies[index], target_layout[index], index == requested_focus)
		_refresh_card.call(_allies[index], new_cards[index])
	_cards.clear()
	_cards.append_array(new_cards)

	for index in range(new_cards.size()):
		var new_card: Dictionary = new_cards[index]
		var new_root: Control = new_card["root"]
		var target_rect: Rect2 = target_layout[index]
		var target_color := _target_modulate(index, index == requested_focus)
		if not animate or index >= old_cards.size():
			new_root.modulate = target_color
			continue
		var old_card: Dictionary = old_cards[index]
		var old_root: Control = old_card.get("root") as Control
		if old_root == null or not is_instance_valid(old_root):
			new_root.modulate = target_color
			continue
		var old_rect: Rect2 = old_card.get("rect", target_rect)
		var old_height := maxf(old_rect.size.y, 1.0)
		var new_height := maxf(target_rect.size.y, 1.0)

		new_root.pivot_offset = Vector2(0.0, new_height)
		new_root.position = Vector2(old_rect.position.x, old_rect.end.y - new_height)
		new_root.scale = Vector2(1.0, old_height / new_height)
		new_root.modulate = Color(target_color.r, target_color.g, target_color.b, 0.0)
		var incoming := _host.create_tween().set_parallel(true)
		incoming.tween_property(
			new_root, "position", target_rect.position, TRANSITION_DURATION,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		incoming.tween_property(
			new_root, "scale", Vector2.ONE, TRANSITION_DURATION,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		incoming.tween_property(
			new_root, "modulate", target_color, TRANSITION_DURATION * 0.82,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		old_root.pivot_offset = Vector2(0.0, old_height)
		var old_target_position := Vector2(
			target_rect.position.x, target_rect.end.y - old_height)
		var old_target_scale := Vector2(1.0, new_height / old_height)
		var old_color := old_root.modulate
		var outgoing := _host.create_tween().set_parallel(true)
		outgoing.tween_property(
			old_root, "position", old_target_position, TRANSITION_DURATION,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		outgoing.tween_property(
			old_root, "scale", old_target_scale, TRANSITION_DURATION,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		outgoing.tween_property(
			old_root, "modulate", Color(old_color.r, old_color.g, old_color.b, 0.0),
			TRANSITION_DURATION * 0.72,
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		outgoing.chain().tween_callback(old_root.queue_free)

	if not animate:
		for old_card in old_cards:
			var old_root: Control = old_card.get("root") as Control
			if old_root != null and is_instance_valid(old_root):
				old_root.queue_free()
