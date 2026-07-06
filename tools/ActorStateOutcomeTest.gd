extends Node
## Runtime QA for generic actor lifecycle states carried by narrative outcomes.

const MainScript = preload("res://scripts/world/Main.gd")
const NPCControllerScript = preload("res://scripts/npc/NPCController.gd")
const ChatBoxScript = preload("res://scripts/ui/ChatBox.gd")


func _ready() -> void:
	NarrativeState.reset()

	var recorded: bool = NarrativeState.record_choice(
		"chapter_1:quest_01:o7",
		"quest_01",
		"o7",
		"a",
		{
			"actor_states": [
				{
					"actor_id": "npc_dead",
					"state": "dead",
					"presentation": "corpse",
				},
			],
			"despawn_npcs": ["npc_hidden"],
		}
	)
	assert(recorded)
	assert(NarrativeState.actor_state_name("npc_dead") == "dead")
	assert(NarrativeState.actor_presentation("npc_dead") == "corpse")
	assert(not NarrativeState.should_hide_actor("npc_dead"))
	assert(NarrativeState.should_hide_actor("npc_hidden"))

	var snapshot: Dictionary = NarrativeState.serialize_save()
	NarrativeState.reset()
	assert(NarrativeState.actor_state("npc_dead").is_empty())
	NarrativeState.apply_save(snapshot)
	assert(NarrativeState.actor_state_name("npc_dead") == "dead")
	assert(NarrativeState.should_hide_actor("npc_hidden"))

	NarrativeState.apply_actor_state_changes({
		"actor_state": {"actor_id": "npc_dead", "state": "alive"},
	})
	assert(NarrativeState.actor_state("npc_dead").is_empty())

	NarrativeState.apply_actor_state_changes({
		"dead_npcs": ["npc_dead"],
	})
	assert(NarrativeState.actor_state_name("npc_dead") == "dead")
	assert(NarrativeState.actor_presentation("npc_dead") == "corpse")

	NarrativeState.apply_actor_state_changes({
		"actor_states": [
			{"npc_id": "npc_dead", "state": "saved", "presentation": "normal"},
		],
	})
	assert(NarrativeState.actor_state_name("npc_dead") == "saved")
	assert(not NarrativeState.should_hide_actor("npc_dead"))

	var chatbox = ChatBoxScript.new()
	chatbox.call("_apply_dialogue_effects", [
		{"type": "actor_state", "actor_id": "npc_dialogue", "state": "dead"},
	])
	assert(NarrativeState.actor_state_name("npc_dialogue") == "dead")
	chatbox.free()

	print("[ActorStateOutcomeTest] actor-state narrative outcome passed")
	get_tree().quit()
