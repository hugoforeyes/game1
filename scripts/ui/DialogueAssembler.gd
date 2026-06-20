class_name DialogueAssembler
extends RefCounted
## Builds the conversation tree the game actually plays when the player talks to an
## NPC, by combining the two authored dialogue layers:
##
##   - world_dialogue  : the EVERGREEN tree (place/history/the NPC) — always shown.
##   - story_dialogue  : an ordered list of progress-gated STAGES; the latest stage
##                       the player has unlocked is the timely one.
##
## The merge mirrors utils/npc_dialogue_common.merge_world_and_story_trees on the
## SceneBuilder side (which packages the back-compat single tree). Keep them in sync.
##
## Active stage = the unlocked stage with the highest `order` (QuestManager decides
## what is unlocked). The story stage leads the greeting + top menu; a single
## "Hỏi chuyện khác." option dives into the world layer.

const ROOT := "root"
const END := "__end__"


## Resolve the tree to play for this NPC. Prefers the two-layer fields; falls back
## to the legacy packaged `conversation_tree`. Returns {} if the NPC has neither.
static func build_active_tree(npc_data: Dictionary) -> Dictionary:
	var world_tree: Dictionary = npc_data.get("world_dialogue", {}) as Dictionary if npc_data.get("world_dialogue") is Dictionary else {}
	var story: Dictionary = npc_data.get("story_dialogue", {}) as Dictionary if npc_data.get("story_dialogue") is Dictionary else {}
	var story_tree: Dictionary = _active_story_tree(story)

	if not world_tree.is_empty() or not story_tree.is_empty():
		return merge_trees(world_tree, story_tree)

	# Legacy package: a single pre-merged tree.
	var legacy: Variant = npc_data.get("conversation_tree")
	if legacy is Dictionary and not ((legacy as Dictionary).get("nodes", []) as Array).is_empty():
		return legacy as Dictionary
	return {}


static func has_dialogue(npc_data: Dictionary) -> bool:
	return not build_active_tree(npc_data).is_empty()


static func _active_story_tree(story: Dictionary) -> Dictionary:
	var stages: Array = story.get("stages", []) as Array if story.get("stages") is Array else []
	var best: Dictionary = {}
	var best_order: int = -2147483648
	for stage in stages:
		if not (stage is Dictionary):
			continue
		var s: Dictionary = stage as Dictionary
		var unlock: Dictionary = s.get("unlock", {}) as Dictionary if s.get("unlock") is Dictionary else {}
		if not QuestManager.stage_unlocked(unlock):
			continue
		var order: int = int(s.get("order", 0))
		if order >= best_order:
			var tree: Variant = s.get("tree")
			if tree is Dictionary and not ((tree as Dictionary).get("nodes", []) as Array).is_empty():
				best_order = order
				best = tree as Dictionary
	return best


# ── merge (mirror of the Python algorithm) ──────────────────────────────────────


static func _rewrite_goto(goto: String, prefix: String, root_target: String) -> String:
	if goto == END:
		return END
	if goto == ROOT:
		return root_target
	return prefix + goto


static func _namespace_nodes(nodes: Array, prefix: String, root_target: String) -> Array:
	var out: Array = []
	for node in nodes:
		if not (node is Dictionary):
			continue
		var nd: Dictionary = (node as Dictionary).duplicate(true)
		nd["id"] = prefix + str(nd.get("id", ""))
		var new_opts: Array = []
		for opt in (nd.get("options", []) as Array):
			if not (opt is Dictionary):
				continue
			var od: Dictionary = (opt as Dictionary).duplicate(true)
			od["goto"] = _rewrite_goto(str(od.get("goto", END)), prefix, root_target)
			new_opts.append(od)
		nd["options"] = new_opts
		out.append(nd)
	return out


static func _find_root(nodes: Array) -> Dictionary:
	for node in nodes:
		if node is Dictionary and str((node as Dictionary).get("id", "")) == ROOT:
			return node as Dictionary
	return {}


static func merge_trees(world_tree: Dictionary, story_tree: Dictionary) -> Dictionary:
	var world_ok: bool = not world_tree.is_empty() and not (world_tree.get("nodes", []) as Array).is_empty()
	var story_ok: bool = not story_tree.is_empty() and not (story_tree.get("nodes", []) as Array).is_empty()
	if not story_ok:
		return world_tree if world_ok else {}
	if not world_ok:
		return story_tree

	var story_nodes: Array = story_tree.get("nodes", []) as Array
	var world_nodes: Array = world_tree.get("nodes", []) as Array
	var story_root: Dictionary = _find_root(story_nodes)
	var world_root: Dictionary = _find_root(world_nodes)
	if story_root.is_empty():
		return world_tree
	if world_root.is_empty():
		return story_tree

	var npc_id := str(story_tree.get("npc_id", world_tree.get("npc_id", "")))
	var name := str(story_tree.get("name", world_tree.get("name", npc_id)))

	# Story subtree (minus root) → "root" points to the combined root.
	var story_children: Array = []
	for node in story_nodes:
		if node is Dictionary and str((node as Dictionary).get("id", "")) != ROOT:
			story_children.append(node)
	var merged_nodes: Array = _namespace_nodes(story_children, "s:", ROOT)
	# World subtree (root included) → "root" stays inside the world layer (w:root).
	merged_nodes.append_array(_namespace_nodes(world_nodes, "w:", "w:root"))

	# Combined root: greeting from the story stage, story topics first, then the
	# doorway into the evergreen world layer, then a single leave.
	var combined_options: Array = []
	for opt in (story_root.get("options", []) as Array):
		if not (opt is Dictionary):
			continue
		var goto := _rewrite_goto(str((opt as Dictionary).get("goto", END)), "s:", ROOT)
		if goto == END:
			continue
		var od: Dictionary = (opt as Dictionary).duplicate(true)
		od["goto"] = goto
		combined_options.append(od)
	combined_options.append({"player_text": "Hỏi chuyện khác.", "goto": "w:root"})
	combined_options.append({"player_text": "Tạm biệt.", "goto": END})

	var combined_root: Dictionary = {
		"id": ROOT,
		"npc_line": str(story_root.get("npc_line", "")),
		"emotion": str(story_root.get("emotion", "neutral")),
		"topic": str(story_root.get("topic", "greeting")),
		"reveals": str(story_root.get("reveals", "")),
		"options": combined_options,
	}
	if story_root.has("effects"):
		combined_root["effects"] = story_root["effects"]

	var all_nodes: Array = [combined_root]
	all_nodes.append_array(merged_nodes)
	return {
		"npc_id": npc_id,
		"name": name,
		"start_node": ROOT,
		"nodes": all_nodes,
	}
