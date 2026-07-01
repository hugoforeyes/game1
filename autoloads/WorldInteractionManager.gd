extends Node

const WorldInteractionPrompt := preload("res://scripts/ui/WorldInteractionPrompt.gd")

var _layer: CanvasLayer = null
var _prompt: Node2D = null
var _candidates: Array[Dictionary] = []
var _active_candidate: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_prompt()


func submit_candidate(owner: Node, kind: String, label: String, priority: int, distance: float, player: Node2D, method: String) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if player == null or not is_instance_valid(player):
		return
	if label.strip_edges().is_empty() or method.strip_edges().is_empty():
		return
	_candidates.append({
		"owner": owner,
		"owner_id": owner.get_instance_id(),
		"kind": kind,
		"label": label.strip_edges(),
		"priority": priority,
		"distance": distance,
		"player": player,
		"method": method,
	})


func is_active(owner: Node, kind: String) -> bool:
	if owner == null or _active_candidate.is_empty():
		return false
	return int(_active_candidate.get("owner_id", 0)) == owner.get_instance_id() \
		and str(_active_candidate.get("kind", "")) == kind


func clear_owner(owner: Node) -> void:
	if owner == null:
		return
	if int(_active_candidate.get("owner_id", 0)) == owner.get_instance_id():
		_clear_active()


func _process(_delta: float) -> void:
	_ensure_prompt()
	if GameManager.ui_blocking_input:
		_candidates.clear()
		_clear_active()
		return

	var selected := _select_candidate()
	_candidates.clear()
	if selected.is_empty():
		_clear_active()
		return

	_active_candidate = selected
	if _prompt != null:
		_prompt.set_item(str(selected.get("label", "")), str(selected.get("kind", "object")))
		_prompt.track(selected.get("player") as Node2D, Vector2.ZERO)
		_prompt.show_prompt()


func _ensure_prompt() -> void:
	if _prompt != null and is_instance_valid(_prompt):
		return
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.layer = 128
		add_child(_layer)
	_prompt = WorldInteractionPrompt.new()
	_prompt.item_confirmed.connect(_on_prompt_confirmed)
	_layer.add_child(_prompt)
	_prompt.hide_prompt()


func _select_candidate() -> Dictionary:
	var live: Array[Dictionary] = []
	for candidate in _candidates:
		# Never `as Node` a Variant that may reference an already-freed object — the
		# cast itself touches freed memory ("Trying to cast a freed object"). During
		# a scene transition an NPC/WorldObject can submit itself one frame and be
		# freed (deferred) before this runs next frame, so check is_instance_valid()
		# on the raw Variant FIRST; that call is safe even on a freed reference.
		var owner_ref: Variant = candidate.get("owner")
		var player_ref: Variant = candidate.get("player")
		if is_instance_valid(owner_ref) and is_instance_valid(player_ref):
			live.append(candidate)
	if live.is_empty():
		return {}
	live.sort_custom(_candidate_before)
	return live[0]


func _candidate_before(a: Dictionary, b: Dictionary) -> bool:
	var ap := int(a.get("priority", 99))
	var bp := int(b.get("priority", 99))
	if ap != bp:
		return ap < bp
	var ad := float(a.get("distance", 999999.0))
	var bd := float(b.get("distance", 999999.0))
	if not is_equal_approx(ad, bd):
		return ad < bd
	return int(a.get("owner_id", 0)) < int(b.get("owner_id", 0))


func _clear_active() -> void:
	_active_candidate = {}
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.hide_prompt()


func _on_prompt_confirmed(item: String, index: int) -> void:
	if _active_candidate.is_empty():
		return
	# Same rule as _select_candidate(): validate the raw Variant before casting.
	var owner_ref: Variant = _active_candidate.get("owner")
	var method := str(_active_candidate.get("method", ""))
	if not is_instance_valid(owner_ref) or method.is_empty():
		_clear_active()
		return
	var owner: Node = owner_ref
	if not owner.has_method(method):
		_clear_active()
		return
	_prompt.hide_prompt()
	owner.call(method, item, index)
