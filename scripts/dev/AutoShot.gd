extends Node
## Dev helper: saves a viewport screenshot every couple of seconds to
## /tmp/gv_shots so visuals can be reviewed from automated runs.

var _timer: float = 0.0
var _index: int = 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/gv_shots")

func _process(delta: float) -> void:
	_timer += delta
	if _timer < 2.0:
		return
	_timer = 0.0
	_index += 1
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("/tmp/gv_shots/shot_%03d.png" % _index)
