class_name GranularFixtures
extends RefCounted

const GOLDEN_TICKS := {
	"single_falling_column": 40,
	"small_sand_pile": 70,
	"narrow_funnel": 90,
	"split_over_obstacle": 100,
	"cross_chunk_pile": 80,
}


static func build(name: String, seed: int = 24681357) -> CellWorld:
	var materials := MaterialRegistry.new()
	assert(materials.load_directory() == OK)
	var world := CellWorld.new(seed, materials)
	var sand := materials.get_id(&"raw_sand")
	var stone := materials.get_id(&"stone")
	populate(world, name, sand, stone)
	return world


static func populate(world: Variant, name: String, sand: int = 2, stone: int = 1) -> void:
	match name:
		"single_falling_column":
			_add_floor(world, stone, 20, -5, 5)
			for y in range(0, 6):
				world.set_cell(Vector2i(0, y), sand)
		"small_sand_pile":
			_add_floor(world, stone, 18, -12, 12)
			for y in range(0, 9):
				for x in range(-4, 5):
					world.set_cell(Vector2i(x, y), sand)
		"narrow_funnel":
			_add_floor(world, stone, 28, -15, 15)
			for y in range(9, 20):
				var inset: int = (y - 9) / 2
				world.set_cell(Vector2i(-11 + inset, y), stone)
				world.set_cell(Vector2i(11 - inset, y), stone)
			for y in range(-2, 8):
				for x in range(-8, 9):
					if (x + y) % 3 != 0:
						world.set_cell(Vector2i(x, y), sand)
		"split_over_obstacle":
			_add_floor(world, stone, 30, -18, 18)
			for layer in range(0, 8):
				for x in range(-layer, layer + 1):
					world.set_cell(Vector2i(x, 29 - layer), stone)
			for y in range(-3, 14):
				for x in range(-5, 6):
					world.set_cell(Vector2i(x, y), sand)
		"cross_chunk_pile":
			_add_floor(world, stone, 136, 114, 142)
			for y in range(112, 127):
				for x in range(120, 136):
					if (x * 3 + y) % 4 != 0:
						world.set_cell(Vector2i(x, y), sand)
		_:
			assert(false, "Unknown granular fixture: %s" % name)
	if not world is CellWorld:
		world.finalize_initialization()


static func _add_floor(world: Variant, stone: int, y: int, x_min: int, x_max: int) -> void:
	for x in range(x_min, x_max + 1):
		world.set_cell(Vector2i(x, y), stone)
