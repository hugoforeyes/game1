extends Node
## Durable save/restore for one game run.
##
## This is what makes the game "remember": the protagonist's and companions' levels
## and XP, which enemies were beaten/spared, and — crucially for this feature — the
## conversation history (which dialogue beats have already paid out XP, so the player
## can't farm the same line twice). It also stores quest state, narrative flags, the
## inventory, the active party and the player's position in the chapter→zone flow, so
## "Continue" resumes exactly where the player left off.
##
## Everything is written to a single JSON file under user://saves/. Saving is
## debounced (request_autosave) so frequent events — gaining XP, talking, a battle
## ending — coalesce into one disk write per frame instead of many.

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/progress.json"
const SAVE_VERSION := 1

var _autosave_queued: bool = false
var _loading: bool = false  # suppress autosaves while we are applying a snapshot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ── public API ────────────────────────────────────────────────────────────────


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Coalesced save request — call this freely; the actual write happens once at the
## end of the frame. No-op while a snapshot is being applied.
func request_autosave() -> void:
	if _loading or _autosave_queued:
		return
	_autosave_queued = true
	_flush_autosave.call_deferred()


func _flush_autosave() -> void:
	if not _autosave_queued:
		return
	_autosave_queued = false
	save()


func save() -> void:
	if _loading:
		return
	# Only persist a real server-driven run — standalone scene previews (StartScene
	# importer / builtin world) have no chapter flow and must not write a save.
	var flow_node: Node = get_node_or_null("/root/ChapterFlow")
	if flow_node == null or not bool(flow_node.get("active")):
		return
	var snapshot := _build_snapshot()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[Save] could not open save file: %d" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.flush()


## Read the saved snapshot without applying it (for a Continue menu preview, etc.).
func peek() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Apply a previously-saved snapshot into the live managers. The chapter's quests /
## items / party catalogs must already be loaded (ChapterFlow.begin_current_chapter)
## so quest/inventory state lands on real definitions. Safe to call with {}.
func apply_to_managers(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_loading = true
	if snapshot.has("progress"):
		GameManager.apply_progress(snapshot.get("progress", {}) as Dictionary)
	if snapshot.has("party") and PartyManager.has_method("apply_save"):
		PartyManager.apply_save(snapshot.get("party", {}) as Dictionary)
	if snapshot.has("narrative") and NarrativeState.has_method("apply_save"):
		NarrativeState.apply_save(snapshot.get("narrative", {}) as Dictionary)
	if snapshot.has("inventory") and InventoryManager.has_method("apply_save"):
		InventoryManager.apply_save(snapshot.get("inventory", {}) as Dictionary)
	if snapshot.has("quests") and QuestManager.has_method("apply_save"):
		QuestManager.apply_save(snapshot.get("quests", {}) as Dictionary)
	_loading = false


# ── snapshot building ──────────────────────────────────────────────────────────


func _build_snapshot() -> Dictionary:
	var snapshot := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"progress": GameManager.serialize_progress(),
	}
	if PartyManager.has_method("serialize_save"):
		snapshot["party"] = PartyManager.serialize_save()
	if NarrativeState.has_method("serialize_save"):
		snapshot["narrative"] = NarrativeState.serialize_save()
	if InventoryManager.has_method("serialize_save"):
		snapshot["inventory"] = InventoryManager.serialize_save()
	if QuestManager.has_method("serialize_save"):
		snapshot["quests"] = QuestManager.serialize_save()
	var flow_node: Node = get_node_or_null("/root/ChapterFlow")
	if flow_node != null and flow_node.has_method("serialize_position"):
		snapshot["flow"] = flow_node.serialize_position()
	return snapshot
