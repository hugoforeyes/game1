extends Node
class_name LiveActionDirector
## Runtime director for the zone's REAL-TIME ambient live actions
## (scene_package.live_actions, authored by SceneBuilder's scene_live_actions step).
##
## NOT a cutscene: gameplay never pauses and ui_blocking_input is never touched.
## The zone's own NPC/enemy bodies keep living in the world — this director only
## overrides WHERE they move (NPCController/EnemyController State.LIVE_ACTION)
## so they act out a continuous story moment while the player plays.
##
## Four stage verbs (kinds), each a movement program over the same primitives
## (A* waypoints, chase-a-node, hold, face, return-home):
##   chase    — hunters run a victim NPC in circles (đuổi bắt)
##   standoff — two sides hold a confrontation line with feint lunges (giằng co)
##   sentry   — guards orbit a protected NPC or spot (canh gác)
##   shuttle  — NPCs hurry back and forth between two anchors (tất bật qua lại)
##
## Lifecycle per live action:
##   PENDING — waits for the zone to settle (start_delay, no ui block), skips
##             shows that already resolved (persisted id / defeated hostiles /
##             story ref already reached).
##   RUNNING — the kind's program drives the cast. Deliberate player contact
##             with a hostile actor still opens the battle; talking to the
##             show's NPC is the peaceful intervention.
##   CATCH   — (chase only) a hunter reached the victim: brief cower beat, then
##             the victim breaks away and the loop resumes.
##   ENDED   — hostiles all defeated/spared, an NPC actor was lost, the gating
##             objective completed, the player intervened, a timeout elapsed, or
##             a real cutscene took the stage. Every surviving controlled actor
##             walks back to its pre-show position (return_home_to) and resumes
##             normal behavior; the id is persisted so the show never replays.

const STATE_PENDING := 0
const STATE_RUNNING := 1
const STATE_CATCH := 2
const STATE_ENDED := 3

const DEFAULT_TARGET_SPEED := 2.4    # tiles/sec — NPC side
const DEFAULT_PURSUER_SPEED := 2.05  # tiles/sec — enemy side
const DEFAULT_CATCH_DISTANCE := 0.9  # tiles
const DEFAULT_HOLD_SECONDS := 2.5
const DEFAULT_START_DELAY := 2.0
const DEFAULT_RADIUS_TILES := 5
const DEFAULT_GAP_TILES := 3
const DEFAULT_PAUSE_SECONDS := 1.5
const CATCH_GRACE_SECONDS := 1.5     # no re-catch right after a cower beat
const WAYPOINT_REFRESH_SECONDS := 1.2
const STORY_REF_POLL_SECONDS := 0.5
const BATTLE_CONTACT_COOLDOWN := 4.0
const SENTRY_RING_SPEED := 0.35      # rad/sec the guard ring rotates
const SENTRY_WAYPOINT_SECONDS := 0.7
const STANDOFF_SPACING_TILES := 1.3  # perpendicular slot spacing on each line
const STANDOFF_LUNGE_MIN := 2.2
const STANDOFF_LUNGE_MAX := 3.8
const STANDOFF_SHIFT_MIN := 3.5
const STANDOFF_SHIFT_MAX := 5.5
const SHUTTLE_ARRIVE_TILES := 1.5
const SHUTTLE_STAGGER_SECONDS := 1.2

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
		var kind := str(config.get("kind", "chase"))
		if id.is_empty() or not kind in ["chase", "standoff", "sentry", "shuttle"]:
			continue
		_records.append({
			"config": config,
			"id": id,
			"kind": kind,
			"state": STATE_PENDING,
			"delay": maxf(float(config.get("start_delay_seconds", DEFAULT_START_DELAY)), 0.0),
			"npc_actors": [],
			"enemy_actors": [],
			"watch_npcs": [],
			"talk_npc_ids": [],
			"origins": {},
			"elapsed": 0.0,
			"story_poll": 0.0,
			"talked": false,
			"pending_end_reason": "",
			# chase
			"orbit_dir": 1.0,
			"waypoint_timer": 0.0,
			"hold_timer": 0.0,
			"catch_grace": 0.0,
			# standoff
			"posts": {},
			"standoff_center": Vector2.ZERO,
			"standoff_axis": Vector2.RIGHT,
			"lunge_timer": randf_range(STANDOFF_LUNGE_MIN, STANDOFF_LUNGE_MAX),
			"lunger": null,
			"lunge_phase": "",
			"shift_timer": randf_range(STANDOFF_SHIFT_MIN, STANDOFF_SHIFT_MAX),
			# sentry
			"ring_angle": randf() * TAU,
			# shuttle
			"legs": {},
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
		# The situation this show dramatizes is already resolved — never stage it.
		record["state"] = STATE_ENDED
		GameManager.mark_live_action_ended(str(record["id"]))
		return
	record["delay"] = float(record["delay"]) - delta
	if float(record["delay"]) > 0.0:
		return

	if not _cast_record(record):
		return
	record["state"] = STATE_RUNNING
	print("[LiveAction] start id=%s kind=%s npcs=%d hostiles=%d" % [
		record["id"], record["kind"],
		(record["npc_actors"] as Array).size(), (record["enemy_actors"] as Array).size(),
	])


func _cast_record(record: Dictionary) -> bool:
	## Resolve the kind's cast from live zone nodes and put every controlled actor
	## into live-action mode. On an unmeetable cast the record ends (persisted when
	## the show can never come back — e.g. its hostiles are already defeated).
	var config := record["config"] as Dictionary
	var kind := str(record["kind"])
	var speeds := config.get("speeds", {}) as Dictionary
	var npc_speed := float(speeds.get("target_tiles_per_sec", DEFAULT_TARGET_SPEED))
	var enemy_speed := float(speeds.get("pursuer_tiles_per_sec", DEFAULT_PURSUER_SPEED))

	var npc_actors: Array = []
	var watch_npcs: Array = []
	var enemy_actors: Array = []
	var talk_ids: Array = []

	match kind:
		"chase":
			var victim := _find_npc(str(config.get("target_npc_id", "")))
			if victim == null or not victim.can_return_home():
				record["state"] = STATE_ENDED
				return false
			npc_actors = [victim]
			talk_ids = [str(config.get("target_npc_id", ""))]
			enemy_actors = _resolve_enemies(config.get("pursuer_enemy_ids"))
		"standoff":
			for holder_id in config.get("holder_npc_ids", []) as Array:
				var holder := _find_npc(str(holder_id))
				if holder != null and holder.can_return_home():
					npc_actors.append(holder)
					talk_ids.append(str(holder_id))
			if npc_actors.is_empty():
				record["state"] = STATE_ENDED
				return false
			enemy_actors = _resolve_enemies(config.get("aggressor_enemy_ids"))
		"sentry":
			enemy_actors = _resolve_enemies(config.get("sentry_enemy_ids"))
			var protected_id := str(config.get("protected_npc_id", ""))
			if not protected_id.is_empty():
				var protected := _find_npc(protected_id)
				if protected == null or not protected.can_return_home():
					record["state"] = STATE_ENDED
					return false
				# Watched, never controlled: the protected NPC keeps its normal
				# ambient life inside the guard ring.
				watch_npcs = [protected]
				talk_ids = [protected_id]
		"shuttle":
			for carrier_id in config.get("carrier_npc_ids", []) as Array:
				var carrier := _find_npc(str(carrier_id))
				if carrier != null and carrier.can_return_home():
					npc_actors.append(carrier)
					talk_ids.append(str(carrier_id))
			var anchor := _find_npc(str(config.get("to_npc_id", "")))
			if npc_actors.is_empty() or anchor == null or not anchor.can_return_home():
				record["state"] = STATE_ENDED
				return false
			watch_npcs = [anchor]

	# Every kind except shuttle needs its hostile side alive; defeated ids persist
	# across loads, so an empty side here means the show is permanently resolved.
	if kind != "shuttle" and enemy_actors.is_empty():
		record["state"] = STATE_ENDED
		GameManager.mark_live_action_ended(str(record["id"]))
		return false

	var origins := {}
	for actor in npc_actors + enemy_actors:
		origins[_actor_key(actor)] = (actor as Node2D).global_position
	record["npc_actors"] = npc_actors
	record["enemy_actors"] = enemy_actors
	record["watch_npcs"] = watch_npcs
	record["talk_npc_ids"] = talk_ids
	record["origins"] = origins

	for npc in npc_actors:
		npc.begin_live_action(npc_speed)
	for enemy in enemy_actors:
		if kind == "chase":
			enemy.begin_live_action_chase(npc_actors[0], enemy_speed)
		else:
			enemy.begin_live_action(enemy_speed)
	if kind == "standoff":
		_setup_standoff_posts(record)
	if kind == "shuttle":
		var legs := {}
		var index := 0
		for carrier in npc_actors:
			legs[_actor_key(carrier)] = {
				"phase": "pause_a",
				"timer": float(index) * SHUTTLE_STAGGER_SECONDS + 0.1,
			}
			index += 1
		record["legs"] = legs
	return true


func _resolve_enemies(raw_ids: Variant) -> Array:
	var out: Array = []
	for enemy_id in raw_ids if raw_ids is Array else []:
		var enemy := _find_enemy(str(enemy_id))
		if enemy != null and enemy.is_hostile():
			out.append(enemy)
	return out


# ── running (shared checks + kind dispatch) ─────────────────────────────────────

func _step_running(record: Dictionary, delta: float) -> void:
	if not str(record["pending_end_reason"]).is_empty():
		_end_action(record, str(record["pending_end_reason"]))
		return
	var config := record["config"] as Dictionary
	var kind := str(record["kind"])
	record["elapsed"] = float(record["elapsed"]) + delta
	record["catch_grace"] = maxf(float(record["catch_grace"]) - delta, 0.0)
	record["waypoint_timer"] = float(record["waypoint_timer"]) - delta

	# Shared end conditions first.
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

	# NPC side: losing any controlled or watched NPC ends the show.
	for npc in (record["npc_actors"] as Array) + (record["watch_npcs"] as Array):
		if npc == null or not is_instance_valid(npc) or not npc.can_return_home():
			_end_action(record, "npc_lost")
			return
	# Hostile side: prune defeated/spared actors; empty side resolves the show
	# ("một trong những actor bị sao đó").
	_prune_enemy_actors(record)
	if kind != "shuttle" and (record["enemy_actors"] as Array).is_empty():
		_end_action(record, "hostiles_gone")
		return

	# Re-assert control an outside system stole (battle cooldown, passivation);
	# a fresh contact cooldown prevents chain battles off the player.
	var speeds := config.get("speeds", {}) as Dictionary
	for enemy in record["enemy_actors"] as Array:
		if not enemy.is_live_action_engaged():
			if kind == "chase":
				enemy.begin_live_action_chase(
					(record["npc_actors"] as Array)[0],
					float(speeds.get("pursuer_tiles_per_sec", DEFAULT_PURSUER_SPEED)),
				)
			else:
				enemy.begin_live_action(float(speeds.get("pursuer_tiles_per_sec", DEFAULT_PURSUER_SPEED)))
			enemy.set_live_action_contact_cooldown(BATTLE_CONTACT_COOLDOWN)

	match kind:
		"chase":
			_run_chase(record)
		"standoff":
			_run_standoff(record, delta)
		"sentry":
			_run_sentry(record, delta)
		"shuttle":
			_run_shuttle(record, delta)


# ── kind program: chase ─────────────────────────────────────────────────────────

func _run_chase(record: Dictionary) -> void:
	var config := record["config"] as Dictionary
	var victim := (record["npc_actors"] as Array)[0] as Node

	# Catch beat: a hunter reached the victim.
	if float(record["catch_grace"]) <= 0.0:
		var catch_distance := float(config.get("catch_distance_tiles", DEFAULT_CATCH_DISTANCE))
		for pursuer in record["enemy_actors"] as Array:
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
	var victim := (record["npc_actors"] as Array)[0] as Node
	if victim != null and is_instance_valid(victim):
		victim.live_action_hold()
	for pursuer in record["enemy_actors"] as Array:
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
	var victim := (record["npc_actors"] as Array)[0] as Node
	_prune_enemy_actors(record)
	if victim != null and is_instance_valid(victim) and victim.is_live_action_engaged():
		var nearest := _nearest_enemy(record, victim as Node2D)
		if nearest != null:
			var away: Vector2 = ((victim as Node2D).global_position - nearest.global_position).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT.rotated(randf() * TAU)
			var escape_px: Vector2 = (victim as Node2D).global_position + away * 3.0 * float(GameManager.TILE_SIZE)
			victim.live_action_move_to(_pixel_to_tile(escape_px))
	record["catch_grace"] = CATCH_GRACE_SECONDS
	record["waypoint_timer"] = WAYPOINT_REFRESH_SECONDS
	record["state"] = STATE_RUNNING


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
	var nearest := _nearest_enemy(record, victim as Node2D)
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


# ── kind program: standoff ──────────────────────────────────────────────────────

func _setup_standoff_posts(record: Dictionary) -> void:
	## Two formation lines facing each other across the gap, derived from where
	## the two sides actually stand right now.
	var config := record["config"] as Dictionary
	var gap := maxf(float(config.get("gap_tiles", DEFAULT_GAP_TILES)), 2.0)
	var tile_px := float(GameManager.TILE_SIZE)
	var npc_centroid := _centroid(record["npc_actors"] as Array)
	var enemy_centroid := _centroid(record["enemy_actors"] as Array)
	var axis := (npc_centroid - enemy_centroid)
	axis = axis.normalized() if axis.length() > 1.0 else Vector2.RIGHT
	var center := (npc_centroid + enemy_centroid) * 0.5
	var perp := axis.orthogonal()
	record["standoff_center"] = center
	record["standoff_axis"] = axis

	var posts := {}
	var slot_offsets := [0.0, STANDOFF_SPACING_TILES, -STANDOFF_SPACING_TILES]
	var enemy_actors := record["enemy_actors"] as Array
	for i in range(enemy_actors.size()):
		var slot: float = slot_offsets[i % slot_offsets.size()]
		posts[_actor_key(enemy_actors[i])] = center - axis * (gap * 0.5) * tile_px + perp * slot * tile_px
	var npc_actors := record["npc_actors"] as Array
	for i in range(npc_actors.size()):
		var slot: float = slot_offsets[i % slot_offsets.size()]
		posts[_actor_key(npc_actors[i])] = center + axis * (gap * 0.5) * tile_px + perp * slot * tile_px
	record["posts"] = posts


func _run_standoff(record: Dictionary, delta: float) -> void:
	var config := record["config"] as Dictionary
	var tile_px := float(GameManager.TILE_SIZE)
	var axis := record["standoff_axis"] as Vector2
	var posts := record["posts"] as Dictionary
	var gap := maxf(float(config.get("gap_tiles", DEFAULT_GAP_TILES)), 2.0)

	# Everyone holds their post and faces the other line.
	for actor in (record["npc_actors"] as Array) + (record["enemy_actors"] as Array):
		if not is_instance_valid(actor) or not actor.is_live_action_engaged():
			continue
		if actor == record["lunger"]:
			continue
		var post: Vector2 = posts.get(_actor_key(actor), (actor as Node2D).global_position)
		var away: float = (actor as Node2D).global_position.distance_to(post) / tile_px
		if away > 0.8 and actor.live_action_idle():
			_move_actor_near(actor, post)
		elif actor.live_action_idle():
			var facing_sign := 1.0 if (record["enemy_actors"] as Array).has(actor) else -1.0
			actor.live_action_face_toward((actor as Node2D).global_position + axis * facing_sign * tile_px)

	# Feint lunges: one aggressor at a time darts toward the holders' line.
	var lunger: Variant = record["lunger"]
	if lunger != null and (not is_instance_valid(lunger) or not (lunger as Node).is_live_action_engaged()):
		record["lunger"] = null
		record["lunge_phase"] = ""
		lunger = null
	if lunger == null:
		record["lunge_timer"] = float(record["lunge_timer"]) - delta
		if float(record["lunge_timer"]) <= 0.0:
			var candidates: Array = []
			for enemy in record["enemy_actors"] as Array:
				if is_instance_valid(enemy) and enemy.is_live_action_engaged() and enemy.live_action_idle():
					candidates.append(enemy)
			if not candidates.is_empty():
				var chosen: Node = candidates.pick_random()
				var post: Vector2 = (record["posts"] as Dictionary).get(_actor_key(chosen), (chosen as Node2D).global_position)
				record["lunger"] = chosen
				record["lunge_phase"] = "out"
				_move_actor_near(chosen, post + axis * (gap - 1.0) * tile_px)
			record["lunge_timer"] = randf_range(STANDOFF_LUNGE_MIN, STANDOFF_LUNGE_MAX)
	else:
		var node := lunger as Node
		if node.live_action_idle():
			if str(record["lunge_phase"]) == "out":
				record["lunge_phase"] = "back"
				node.live_action_hold(0.35)
				_move_actor_near(node, (record["posts"] as Dictionary).get(_actor_key(node), (node as Node2D).global_position))
			else:
				record["lunger"] = null
				record["lunge_phase"] = ""

	# Holders shuffle nervously along their line now and then.
	record["shift_timer"] = float(record["shift_timer"]) - delta
	if float(record["shift_timer"]) <= 0.0:
		var holders: Array = []
		for npc in record["npc_actors"] as Array:
			if is_instance_valid(npc) and npc.is_live_action_engaged() and npc.live_action_idle():
				holders.append(npc)
		if not holders.is_empty():
			var holder: Node = holders.pick_random()
			var perp := axis.orthogonal()
			var side := 1.0 if randf() < 0.5 else -1.0
			_move_actor_near(holder, (holder as Node2D).global_position + perp * side * tile_px)
		record["shift_timer"] = randf_range(STANDOFF_SHIFT_MIN, STANDOFF_SHIFT_MAX)


# ── kind program: sentry ────────────────────────────────────────────────────────

func _run_sentry(record: Dictionary, delta: float) -> void:
	var config := record["config"] as Dictionary
	var area := config.get("area", {}) as Dictionary
	var radius_px := maxf(float(area.get("radius_tiles", DEFAULT_RADIUS_TILES)), 2.0) * float(GameManager.TILE_SIZE)
	var anchor: Vector2
	var watch := record["watch_npcs"] as Array
	if not watch.is_empty() and is_instance_valid(watch[0]):
		anchor = (watch[0] as Node2D).global_position
	else:
		anchor = _area_center_static(record)
	record["ring_angle"] = float(record["ring_angle"]) + SENTRY_RING_SPEED * delta

	if float(record["waypoint_timer"]) > 0.0:
		return
	record["waypoint_timer"] = SENTRY_WAYPOINT_SECONDS
	var sentries := record["enemy_actors"] as Array
	var count := maxi(sentries.size(), 1)
	for i in range(sentries.size()):
		var sentry := sentries[i] as Node
		if not is_instance_valid(sentry) or not sentry.is_live_action_engaged():
			continue
		var slot_angle: float = float(record["ring_angle"]) + TAU * float(i) / float(count)
		var point: Vector2 = anchor + Vector2(cos(slot_angle), sin(slot_angle)) * radius_px
		var away: float = (sentry as Node2D).global_position.distance_to(point) / float(GameManager.TILE_SIZE)
		if away > 0.9:
			if sentry.live_action_idle():
				_move_actor_near(sentry, point)
		elif sentry.live_action_idle():
			# On station: scan outward, back to the watch.
			sentry.live_action_face_toward((sentry as Node2D).global_position * 2.0 - anchor)


# ── kind program: shuttle ───────────────────────────────────────────────────────

func _run_shuttle(record: Dictionary, delta: float) -> void:
	var config := record["config"] as Dictionary
	var pause := maxf(float(config.get("pause_seconds", DEFAULT_PAUSE_SECONDS)), 0.3)
	var watch := record["watch_npcs"] as Array
	if watch.is_empty() or not is_instance_valid(watch[0]):
		return
	var anchor_b := watch[0] as Node2D
	var legs := record["legs"] as Dictionary
	var tile_px := float(GameManager.TILE_SIZE)
	var origins := record["origins"] as Dictionary

	for carrier in record["npc_actors"] as Array:
		if not is_instance_valid(carrier) or not carrier.is_live_action_engaged():
			continue
		var key := _actor_key(carrier)
		var leg := legs.get(key, {"phase": "pause_a", "timer": 0.1}) as Dictionary
		var origin: Vector2 = origins.get(key, (carrier as Node2D).global_position)
		match str(leg["phase"]):
			"pause_a":
				leg["timer"] = float(leg["timer"]) - delta
				if float(leg["timer"]) <= 0.0:
					leg["phase"] = "to_b"
					_move_actor_near(carrier, anchor_b.global_position)
			"to_b":
				var to_b: float = (carrier as Node2D).global_position.distance_to(anchor_b.global_position) / tile_px
				if to_b <= SHUTTLE_ARRIVE_TILES:
					leg["phase"] = "pause_b"
					leg["timer"] = pause
					carrier.live_action_hold()
					carrier.live_action_face_toward(anchor_b.global_position)
				elif carrier.live_action_idle():
					# Path failed/blocked — take another run at the (moving) anchor.
					_move_actor_near(carrier, anchor_b.global_position)
			"pause_b":
				leg["timer"] = float(leg["timer"]) - delta
				if float(leg["timer"]) <= 0.0:
					leg["phase"] = "to_a"
					_move_actor_near(carrier, origin)
			"to_a":
				var to_a: float = (carrier as Node2D).global_position.distance_to(origin) / tile_px
				if to_a <= SHUTTLE_ARRIVE_TILES:
					leg["phase"] = "pause_a"
					leg["timer"] = pause
					carrier.live_action_hold()
					carrier.live_action_face_toward(anchor_b.global_position)
				elif carrier.live_action_idle():
					_move_actor_near(carrier, origin)
		legs[key] = leg


# ── choreography helpers ────────────────────────────────────────────────────────

func _move_actor_near(actor: Node, target_px: Vector2) -> bool:
	## Walk an actor to the tile at target_px, or the nearest neighbor when that
	## exact tile is unwalkable/occupied (e.g. the tile under another NPC's feet).
	var base := _pixel_to_tile(target_px)
	var offsets := [
		Vector2i.ZERO,
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for offset in offsets:
		if actor.live_action_move_to(base + (offset as Vector2i)):
			return true
	return false


func _area_center(record: Dictionary, fallback_node: Node2D) -> Vector2:
	var center := _area_center_static(record)
	if center != Vector2.INF:
		return center
	var origins := record["origins"] as Dictionary
	return origins.get(_actor_key(fallback_node), fallback_node.global_position) as Vector2


func _area_center_static(record: Dictionary) -> Vector2:
	var config := record["config"] as Dictionary
	var area := config.get("area", {}) as Dictionary
	var center_tile: Variant = area.get("center_tile")
	if center_tile is Dictionary and not (center_tile as Dictionary).is_empty():
		return _tile_to_pixel_center(Vector2i(
			int((center_tile as Dictionary).get("x", 0)),
			int((center_tile as Dictionary).get("y", 0)),
		))
	# Fall back to wherever the hostile cast started.
	var origins := record["origins"] as Dictionary
	var enemy_actors := record["enemy_actors"] as Array
	if not enemy_actors.is_empty():
		var sum := Vector2.ZERO
		var counted := 0
		for enemy in enemy_actors:
			var key := _actor_key(enemy)
			if origins.has(key):
				sum += origins[key] as Vector2
				counted += 1
		if counted > 0:
			return sum / float(counted)
	return Vector2.INF


func _centroid(actors: Array) -> Vector2:
	var sum := Vector2.ZERO
	var counted := 0
	for actor in actors:
		if is_instance_valid(actor):
			sum += (actor as Node2D).global_position
			counted += 1
	return sum / float(maxi(counted, 1))


func _nearest_enemy(record: Dictionary, from_node: Node2D) -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for enemy in record["enemy_actors"] as Array:
		if not is_instance_valid(enemy):
			continue
		var distance: float = (enemy as Node2D).global_position.distance_to(from_node.global_position)
		if distance < best:
			best = distance
			nearest = enemy as Node2D
	return nearest


func _prune_enemy_actors(record: Dictionary) -> void:
	var alive: Array = []
	for enemy in record["enemy_actors"] as Array:
		if is_instance_valid(enemy) and not (enemy as Node).is_queued_for_deletion() \
				and enemy.is_hostile():
			alive.append(enemy)
		elif is_instance_valid(enemy) and enemy.is_in_live_action():
			# Spared mid-show: passive now — release it back to ordinary life.
			enemy.end_live_action()
			_return_actor_home(record, enemy)
	record["enemy_actors"] = alive


# ── ending ──────────────────────────────────────────────────────────────────────

func _end_action(record: Dictionary, reason: String) -> void:
	record["state"] = STATE_ENDED
	record["pending_end_reason"] = ""
	record["lunger"] = null
	GameManager.mark_live_action_ended(str(record["id"]))
	for npc in record["npc_actors"] as Array:
		if npc != null and is_instance_valid(npc):
			if npc.is_in_live_action():
				npc.end_live_action()
			_return_actor_home(record, npc)
	for enemy in record["enemy_actors"] as Array:
		if is_instance_valid(enemy) and not (enemy as Node).is_queued_for_deletion():
			enemy.end_live_action()
			_return_actor_home(record, enemy)
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
				and (record["talk_npc_ids"] as Array).has(npc_id):
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
