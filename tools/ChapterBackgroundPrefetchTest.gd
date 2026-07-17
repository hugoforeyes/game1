extends "res://autoloads/ChapterFlow.gd"
## Regression: the background worker must finish the requested chapter before it
## starts the following chapter, and a failed current chapter must stop the chain.

var _requested_indices: Array[int] = []
var _results: Array[bool] = []


func _ready() -> void:
	active = true
	chapter_index = 2

	_results = [true, true]
	prefetch_remaining_zones()
	await get_tree().process_frame
	assert(_requested_indices == [2, 3],
		"prefetch must cache the current chapter before the next chapter")

	_requested_indices.clear()
	_results = [false]
	prefetch_remaining_zones()
	await get_tree().process_frame
	assert(_requested_indices == [2],
		"prefetch must not start the next chapter when the current chapter failed")

	print("[ChapterBackgroundPrefetchTest] sequential next-chapter prefetch passed")
	get_tree().quit()


func _prefetch_chapter_zones(target_chapter_index: int) -> bool:
	_requested_indices.append(target_chapter_index)
	return _results.pop_front()
