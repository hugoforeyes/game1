extends Node
class_name LiveActionDirector
## Runtime director for the zone's REAL-TIME ambient live actions
## (scene_package.live_actions, authored by SceneBuilder's scene_live_actions step).
##
## NOT a cutscene: gameplay never pauses and ui_blocking_input is never touched.
## The zone's own NPC/enemy bodies keep living in the world — this director only
## overrides WHERE they move (NPCController/EnemyController State.LIVE_ACTION)
## so they act out a continuous story moment while the player plays: e.g. the
## Ashwood stalkers visibly circling and chasing Ansel Brigg because the quest
## says he is pinned down by beasts.
##
## Lifecycle per live action:
##   PENDING  — waits for the zone to settle (start_delay, no ui block), skips
##              shows that already resolved (persisted id / defeated pursuers /
##              story ref already reached).
##   RUNNING  — victim orbits the staging area (A*-walked waypoints, flips
##              direction to evade), pursuers hunt the victim. Deliberate player
##              contact with a pursuer still opens the battle; talking to the
##              victim is the peaceful intervention.
##   CATCH    — a pursuer reached the victim: brief cower/hold beat, then the
##              victim breaks away and the loop resumes (the show never harms
##              quest actors).
##   ENDED    — pursuers all defeated/spared, the gating objective completed,
##              the player intervened, a timeout elapsed, or a real cutscene
##              took the stage. Every surviving actor walks back to its
##              pre-show position (return_home_to) and resumes normal behavior;
##              the id is persisted so the show never replays.

const STATE_PENDING := 0
const STATE_RUNNING := 1
const STATE_CATCH := 2
const STATE_ENDED := 3

const DEFAULT_TARGET_SPEED := 2.4    # tiles/sec — victim slightly outruns...
const DEFAULT_PURSUER_SPEED := 2.05  # ...the hunters, so the loop reads as a chase
const DEFAULT_CATCH_DISTANCE := 0.9  # tiles
const DEFAULT_HOLD_SECONDS := 2.5
const DEFAULT_START_DELAY := 2.0
const DEFAULT_RADIUS_TILES := 5
const CATCH_GRACE_SECONDS := 1.5     # no re-catch right after a cower beat
const WAYPOINT_REFRESH_SECONDS := 1.2
const STORY_REF_POLL_SECONDS := 0.5
const BATTLE_CONTACT_COOLDOWN := 4.0

var _records: Array[Dictionary] = []
var _characters_root: Node2D = null
var _player: Node2D = null


func setup(player: Node2D, characters_root: Node2D, live_actions: Array) -> void:
	_player = player
	_characters_root = characters_root
	for raw in live_actions:
		if not (raw is Dictionary):
			continue
		var config := raw as Dictionary
		var id := str(config.get("id", ""))
		if id.is_empty() or str(config.get("kind", "chase")) != "chase":
			continue
		_records.append({
			"config": config,
			"id": id,
			"state": STATE_PENDING,
			"delay": maxf(float(config.get("start_delay_seconds", DEFAULT_START_DELAY)), 0.0),
			"victim": null,
			"pursuers": [],
			"origins": {},
			"orbit_dir": 1.0,
			"waypoint_timer": 0.0,
			"hold_timer": 0.0,
			"catch_grace": 0.0,
			"elapsed": 0.0,
			"story_poll": 0.0,
			"talked": false,
			"pending_end_reason": "",
		})
	if not _records.is_empty():
		QuestManager.npc_talked.connect(_on_npc_talked)
	print("[LiveAction] zone live_actions=%d" % _records.size())


func _physics_process(delta: float) -> void:
	if _records.is_empty():
		return
	if GameManager.ui_blocking_input:
		# The world is frozen (chat/battle/cutscene) — actors already hold still via
		# their own gates. A REAL cutscene may reposition/repurpose our actors, so a
		# running show ends gracefully once the stage is free again.
		if get_tree().get_first_node_in_group("active_cutscene_player") != null:
			for record in _records:
				if int(record["state"]) in [STATE_RUNNING, STATE_CATCH] \
						and str(record["pending_end_reason"]).is_empty():
					record["pending_end_reason"] = "cutscene"
		return
	for record in _records:
		match int(record["state"]):
			STATE_PENDING:
				_step_pending(record, delta)
			STATE_RUNNING:
				_step_running(record, delta)
			STATE_CATCH:
				_step_catch(record, delta)


# ── pending / casting ───────────────────────────────────────────────────────────

func _step_pending(record: Dictionary, delta: float) -> void:
	var config := record["config"] as Dictionary
	if GameManager.is_live_action_ended(str(record["id"])):
		record["state"] = STATE_ENDED
		return
	var story_ref := _story_ref(config)
	if not story_ref.is_empty() and QuestManager.has_reached_story_ref(story_ref):
		# The danger this show dramatizes is already resolved — never stage it.
		record["state"] = STATE_ENDED
		GameManager.mark_live_action_ended(str(record["id"]))
		return
	record["delay"] = float(record["delay"]) - delta
	if float(record["delay"]) > 0.0:
		return

	var victim := _find_npc(str(config.get("target_npc_id", "")))
	if victim == null or not victim.can_return_home():
		record["state"] = STATE_ENDED
		return
	var pursuers: Array = []
	for pursuer_id in config.get("pursuer_enemy_ids", []) as Array:
		var enemy := _find_enemy(str(pursuer_id))
		if enemy != null and enemy.is_hostile():
			pursuers.append(enemy)
	if pursuers.is_empty():
		# All hunters are already dealt with (defeated ids persist across loads).
		record["state"] = STATE_ENDED
		GameManager.mark_live_action_ended(str(record["id"]))
		return

	var origins := {}
	origins[_actor_key(victim)] = victim.global_position
	for pursuer in pursuers:
		origins[_actor_key(pursuer)] = (pursuer as Node2D).global_position
	record["victim"] = victim
	record["pursuers"] = pursuers
	record["origins"] = origins
	record["state"] = STATE_RUNNING

	var speeds := config.get("speeds", {}) as Dictionary
	victim.begin_live_action(float(speeds.get("target_tiles_per_sec", DEFAULT_TARGET_SPEED)))
	for pursuer in pursuers:
		pursuer.begin_live_action_chase(
			victim, float(speeds.get("pursuer_tiles_per_sec", DEFAULT_PURSUER_SPEED)),
		)
	print("[LiveAction] start id=%s victim=%s pursuers=%d" % [
		record["id"], config.get("target_npc_id", "?"), pursuers.size(),
	])


# ── running ─────────────────────────────────────────────────────────────────────

func _step_running(record: Dictionary, delta: float) -> void:
	if not str(record["pending_end_reason"]).is_empty():
		_end_action(record, str(record["pending_end_reason"]))
		return
	var config := record["config"] as Dictionary
	record["elapsed"] = float(record["elapsed"]) + delta
	record["catch_grace"] = maxf(float(record["catch_grace"]) - delta, 0.0)
	record["waypoint_timer"] = float(record["waypoint_timer"]) - delta

	# End conditions first.
	var ends := config.get("ends_when", {}) as Dictionary
	if bool(record["talked"]) and bool(ends.get("player_talks_to_target", true)):
		_end_action(record, "player_intervened")
		return
	var timeout := float(ends.get("timeout_seconds", 0))
	if timeout > 0.0 and float(record["elapsed"]) >= timeout:
		_end_action(record, "timeout")
		return
	record["story_poll"] = float(record["story_poll"]) - delta
	if float(record["story_poll"]) <= 0.0:
		record["story_poll"] = STORY_REF_POLL_SECONDS
		var story_ref := _story_ref(config)
		if not story_ref.is_empty() and QuestManager.has_reached_story_ref(story_ref):
			_end_action(record, "story_resolved")
			return

	var victim := record["victim"] as Node
	if victim == null or not is_instance_valid(victim) or not victim.can_return_home():
		_end_action(record, "victim_gone")
		return
	_prune_pursuers(record)
	var pursuers := record["pursuers"] as Array
	if pursuers.is_empty():
		# "Một trong những actor bị sao đó": every hunter was defeated/spared.
		_end_action(record, "pursuers_gone")
		return

	# Re-assert control an outside system stole (battle cooldown, interaction
	# freeze); a fresh contact cooldown prevents chain battles off the player.
	for pursuer in pursuers:
		if not pursuer.is_live_action_engaged():
			var speeds := config.get("speeds", {}) as Dictionary
			pursuer.begin_live_action_chase(
				victim, float(speeds.get("pursuer_tiles_per_sec", DEFAULT_PURSUER_SPEED)),
			)
			pursuer.set_live_action_contact_cooldown(BATTLE_CONTACT_COOLDOWN)

	# Catch beat: a hunter reached the victim.
	if float(record["catch_grace"]) <= 0.0:
		var catch_distance := float(config.get("catch_distance_tiles", DEFAULT_CATCH_DISTANCE))
		for pursuer in pursuers:
			var distance_tiles: float = (pursuer as Node2D).global_position.distance_to(
				(victim as Node2D).global_position) / GameManager.TILE_SIZE
			if distance_tiles <= catch_distance:
				_begin_catch(record)
				return

	# Keep the victim orbiting.
	if victim.is_live_action_engaged() and (victim.live_action_idle() or float(record["waypoint_timer"]) <= 0.0):
		_issue_orbit_waypoint(record, victim)
		record["waypoint_timer"] = WAYPOINT_REFRESH_SECONDS


func _begin_catch(record: Dictionary) -> void:
	var config := record["config"] as Dictionary
	var behavior := config.get("catch_behavior", {}) as Dictionary
	if str(behavior.get("outcome", "cower")) == "end":
		_end_action(record, "target_caught")
		return
	var hold := maxf(float(behavior.get("hold_seconds", DEFAULT_HOLD_SECONDS)), 0.5)
	var victim := record["victim"] as Node
	if victim != null and is_instance_valid(victim):
		victim.live_action_hold()
	for pursuer in record["pursuers"] as Array:
		if is_instance_valid(pursuer):
			pursuer.live_action_hold(hold)
	record["hold_timer"] = hold
	record["state"] = STATE_CATCH


func _step_catch(record: Dictionary, delta: float) -> void:
	if not str(record["pending_end_reason"]).is_empty():
		_end_action(record, str(record["pending_end_reason"]))
		return
	record["hold_timer"] = float(record["hold_timer"]) - delta
	if float(record["hold_timer"]) > 0.0:
		return
	# Break away: dash a few tiles straight AWAY from the nearest hunter, then
	# fall back into the orbit loop.
	var victim := record["victim"] as Node
	_prune_pursuers(record)
	if victim != null and is_instance_valid(victim) and victim.is_live_action_engaged():
		var nearest := _nearest_pursuer(record, victim as Node2D)
		if nearest != null:
			var away: Vector2 = ((victim as Node2D).global_position - nearest.global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT.rotated(randf() * TAU)
			var escape_px: Vector2 = (victim as Node2D).global_position + away * 3.0 * float(GameManager.TILE_SIZE)
			victim.live_action_move_to(_pixel_to_tile(escape_px))
	record["catch_grace"] = CATCH_GRACE_SECONDS
	record["waypoint_timer"] = WAYPOINT_REFRESH_SECONDS
	record["state"] = STATE_RUNNING


# ── choreography helpers ────────────────────────────────────────────────────────

func _issue_orbit_waypoint(record: Dictionary, victim: Node) -> void:
	var config := record["config"] as Dictionary
	var area := config.get("area", {}) as Dictionary
	var radius_tiles := maxf(float(area.get("radius_tiles", DEFAULT_RADIUS_TILES)), 2.0)
	var center := _area_center(record, victim as Node2D)
	var tile_px := float(GameManager.TILE_SIZE)

	var to_victim: Vector2 = (victim as Node2D).global_position - center
	var angle: float = to_victim.angle() if to_victim.length() > 4.0 else randf() * TAU
	# Run AWAY around the ring: if the nearest hunter sits ahead on our orbit
	# direction, flip and circle the other way.
	var nearest := _nearest_pursuer(record, victim as Node2D)
	if nearest != null:
		var pursuer_angle: float = (nearest.global_position - center).angle()
		var ahead := wrapf(pursuer_angle - angle, -PI, PI)
		if signf(ahead) == signf(float(record["orbit_dir"])) and absf(ahead) < 1.2:
			record["orbit_dir"] = -float(record["orbit_dir"])

	for attempt in range(5):
		var next_angle: float = angle + float(record["orbit_dir"]) * (0.9 + 0.35 * float(attempt))
		var ring_radius: float = radius_tiles * randf_range(0.6, 1.0) * tile_px
		var target_px: Vector2 = center + Vector2(cos(next_angle), sin(next_angle)) * ring_radius
		if victim.live_action_move_to(_pixel_to_tile(target_px)):
			return
	# Ring fully blocked on this side — try the other way next tick.
	record["orbit_dir"] = -float(record["orbit_dir"])


func _area_center(record: Dictionary, victim: Node2D) -> Vector2:
	var config := record["config"] as Dictionary
	var area := config.get("area", {}) as Dictionary
	var center_tile: Variant = area.get("center_tile")
	if center_tile is Dictionary and not (center_tile as Dictionary).is_empty():
		return _tile_to_pixel_center(Vector2i(
			int((center_tile as Dictionary).get("x", 0)),
			int((center_tile as Dictionary).get("y", 0)),
		))
	var origins := record["origins"] as Dictionary
	var key := _actor_key(victim)
	return origins.get(key, victim.global_position) as Vector2


func _nearest_pursuer(record: Dictionary, victim: Node2D) -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for pursuer in record["pursuers"] as Array:
		if not is_instance_valid(pursuer):
			continue
		var distance: float = (pursuer as Node2D).global_position.distance_to(victim.global_position)
		if distance < best:
			best = distance
			nearest = pursuer as Node2D
	return nearest


func _prune_pursuers(record: Dictionary) -> void:
	var alive: Array = []
	for pursuer in record["pursuers"] as Array:
		if is_instance_valid(pursuer) and not (pursuer as Node).is_queued_for_deletion() \
				and pursuer.is_hostile():
			alive.append(pursuer)
		elif is_instance_valid(pursuer) and pursuer.is_in_live_action():
			# Spared mid-show: passive now — release it back to ordinary life.
			pursuer.end_live_action()
			_return_actor_home(record, pursuer)
	record["pursuers"] = alive


# ── ending ──────────────────────────────────────────────────────────────────────

func _end_action(record: Dictionary, reason: String) -> void:
	record["state"] = STATE_ENDED
	record["pending_end_reason"] = ""
	GameManager.mark_live_action_ended(str(record["id"]))
	var victim := record["victim"] as Node
	if victim != null and is_instance_valid(victim):
		if victim.is_in_live_action():
			victim.end_live_action()
		_return_actor_home(record, victim)
	for pursuer in record["pursuers"] as Array:
		if is_instance_valid(pursuer) and not (pursuer as Node).is_queued_for_deletion():
			pursuer.end_live_action()
			_return_actor_home(record, pursuer)
	print("[LiveAction] end id=%s reason=%s" % [record["id"], reason])


func _return_actor_home(record: Dictionary, actor: Node) -> void:
	## "Khi hoạt cảnh kết thúc, actor di chuyển về vị trí cũ" — walk (never snap)
	## back to the exact pre-show spot via the shared gameplay return machinery.
	var origins := record["origins"] as Dictionary
	var key := _actor_key(actor)
	if not origins.has(key):
		return
	if actor.has_method("can_return_home") and not actor.can_return_home():
		return
	if actor.has_method("return_home_to"):
		actor.return_home_to(origins[key] as Vector2)


# ── events / lookups ────────────────────────────────────────────────────────────

func _on_npc_talked(npc_id: String) -> void:
	for record in _records:
		if int(record["state"]) in [STATE_RUNNING, STATE_CATCH] \
				and str((record["config"] as Dictionary).get("target_npc_id", "")) == npc_id:
			record["talked"] = true


func _find_npc(npc_id: String) -> Node:
	if npc_id.is_empty() or _characters_root == null:
		return null
	for child in _characters_root.get_children():
		var data: Variant = child.get("npc_data")
		if data is Dictionary and str((data as Dictionary).get("id", "")) == npc_id \
				and child.has_method("begin_live_action"):
			return child
	return null


func _find_enemy(enemy_id: String) -> Node:
	if enemy_id.is_empty() or _characters_root == null:
		return null
	for child in _characters_root.get_children():
		var data: Variant = child.get("enemy_data")
		if data is Dictionary and str((data as Dictionary).get("id", "")) == enemy_id \
				and child.has_method("begin_live_action_chase"):
			return child
	return null


func _story_ref(config: Dictionary) -> String:
	return str((config.get("ends_when", {}) as Dictionary).get("story_ref_reached", ""))


func _actor_key(actor: Node) -> String:
	return str(actor.get_instance_id())


func _tile_to_pixel_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * GameManager.TILE_SIZE + Vector2.ONE * (GameManager.TILE_SIZE * 0.5)


func _pixel_to_tile(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(GameManager.TILE_SIZE)),
		floori(world_position.y / float(GameManager.TILE_SIZE)),
	)
