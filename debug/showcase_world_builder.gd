class_name ShowcaseWorldBuilder
extends RefCounted

const X_MIN := -350
const X_MAX := 350
const Y_MIN := -118
const Y_MAX := 228


static func populate(world: Variant, materials: MaterialRegistry = null) -> void:
	var registry := materials
	if registry == null and world is CellWorld:
		registry = world.materials
	var stone := registry.get_id(&"stone") if registry != null else 1
	var sand := registry.get_id(&"raw_sand") if registry != null else 2
	var water := registry.get_id(&"water") if registry != null else 3

	for y in range(Y_MIN, Y_MAX + 1):
		for x in range(X_MIN, X_MAX + 1):
			if _is_showcase_stone(Vector2i(x, y)):
				world.initialize_cell(Vector2i(x, y), stone)

	_add_reservoir(world, stone, sand)
	_add_chute(world, stone)
	_add_settled_sand(world, stone, sand)
	_add_static_water_basin(world, water)
	if world is CellWorld:
		_sleep_non_granular_chunks(world)
	else:
		world.finalize_initialization()


static func _is_showcase_stone(cell: Vector2i) -> bool:
	var x := float(cell.x)
	var y := float(cell.y)
	var surface := 67.0 + sin((x + 35.0) / 46.0) * 10.0 + sin((x - 80.0) / 19.0) * 4.0
	var solid := y >= surface
	var broad_cave := pow((x + 92.0) / 178.0, 2.0) + pow((y - 132.0) / 63.0, 2.0) < 1.0
	var east_basin := pow((x - 205.0) / 112.0, 2.0) + pow((y - 131.0) / 57.0, 2.0) < 1.0
	var lower_gallery := pow((x + 12.0) / 128.0, 2.0) + pow((y - 211.0) / 34.0, 2.0) < 1.0
	var vertical_drop := absf(x - 116.0) < 11.0 and y > -72.0 and y < 132.0
	var slope_tunnel_center := -247.0 + (y + 24.0) * 0.72
	var slope_tunnel := y > -25.0 and y < 92.0 and absf(x - slope_tunnel_center) < 13.0
	if broad_cave or east_basin or lower_gallery or vertical_drop or slope_tunnel:
		solid = false
	var west_cliff := x < -315.0 and y > -45.0
	var east_cliff := x > 326.0 and y > -20.0
	return solid or west_cliff or east_cliff


static func _add_reservoir(world: Variant, stone: int, sand: int) -> void:
	for y in range(-104, -26):
		world.initialize_cell(Vector2i(-296, y), stone)
		world.initialize_cell(Vector2i(-202, y), stone)
	for x in range(-296, -251):
		world.initialize_cell(Vector2i(x, -25), stone)
	for x in range(-244, -201):
		world.initialize_cell(Vector2i(x, -25), stone)
	for y in range(-98, -31):
		for x in range(-290, -208):
			if ((x * 5 + y * 3) & 7) != 0:
				world.initialize_cell(Vector2i(x, y), sand)


static func _add_chute(world: Variant, stone: int) -> void:
	for y in range(-24, 92):
		var center := -247 + roundi(float(y + 24) * 0.72)
		for thickness in 3:
			world.initialize_cell(Vector2i(center - 14 - thickness, y), stone)
			world.initialize_cell(Vector2i(center + 14 + thickness, y), stone)
	for x in range(-182, -32):
		var ledge_y := 92 + roundi(sin(float(x) / 17.0) * 3.0)
		for thickness in 4:
			world.initialize_cell(Vector2i(x, ledge_y + thickness), stone)


static func _add_settled_sand(world: Variant, stone: int, sand: int) -> void:
	for x in range(-154, 66):
		var shelf_y := 188 + roundi(sin(float(x + 21) / 23.0) * 2.0)
		for thickness in 5:
			world.initialize_cell(Vector2i(x, shelf_y + thickness), stone)
	for y in range(174, 189):
		world.initialize_cell(Vector2i(-154, y), stone)
		world.initialize_cell(Vector2i(65, y), stone)
	for x in range(-126, 36):
		var pile_height := maxi(0, 28 - absi(x + 42) / 3)
		for y in range(154 - pile_height, 154):
			if world.get_cell(Vector2i(x, y)) == MaterialRegistry.EMPTY_ID:
				world.initialize_cell(Vector2i(x, y), sand)


static func _add_static_water_basin(world: Variant, water: int) -> void:
	var surface_y := 139
	for x in range(162, 253):
		var normalized := float(x - 207) / 46.0
		if absf(normalized) >= 1.0:
			continue
		var depth := roundi(sqrt(1.0 - normalized * normalized) * 34.0)
		for y in range(surface_y, surface_y + depth):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) == MaterialRegistry.EMPTY_ID:
				world.initialize_cell(cell, water)


static func _sleep_non_granular_chunks(world: CellWorld) -> void:
	for coordinate in world.get_chunk_coordinates():
		var chunk := world.get_chunk(coordinate)
		var contains_granular := false
		for material_id in chunk.material_ids:
			if world.materials.get_category(material_id) == MaterialDefinition.Category.GRANULAR:
				contains_granular = true
				break
		if not contains_granular:
			chunk.sleep()
