extends TileMap

const TILE_SIZE := 36
const MAP_WIDTH := 32
const MAP_HEIGHT := 32

func _ready() -> void:
	_build_tileset()
	_fill_map()

func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Grass tile
	ts.add_source(_make_source(Color(0.25, 0.55, 0.20)), 0)

	tile_set = ts

func _fill_map() -> void:
	for x in MAP_WIDTH:
		for y in MAP_HEIGHT:
			set_cell(0, Vector2i(x, y), 0, Vector2i(0, 0))

func _make_source(color: Color) -> TileSetAtlasSource:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(color)

	# Darker border so tiles are distinguishable
	for i in TILE_SIZE:
		img.set_pixel(i, 0, color.darkened(0.3))
		img.set_pixel(i, TILE_SIZE - 1, color.darkened(0.3))
		img.set_pixel(0, i, color.darkened(0.3))
		img.set_pixel(TILE_SIZE - 1, i, color.darkened(0.3))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(Vector2i(0, 0))
	return source

func get_map_pixel_size() -> Vector2:
	return Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)
