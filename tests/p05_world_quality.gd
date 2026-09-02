extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_architecture_and_order()
	_test_content_and_structure()
	_test_player_induced_chaos()
	if failures.is_empty():
		print("PASS: %d P0.5 world-quality checks" % checks); quit(0)
	else:
		for failure in failures: push_error("P05_WORLD_QUALITY: " + failure)
		print("FAIL: %d of %d P0.5 checks" % [failures.size(), checks]); quit(1)

func _test_architecture_and_order() -> void:
	var architecture: Dictionary = _world(412, 4).get_worldgen_v2_architecture()
	_equal(int(architecture.generation_version), 4, "new worlds use generation version 4")
	_equal(int(architecture.macro_region_scale_cells), 512, "V4 macro provinces span eight simulation chunks")
	_check(bool(architecture.chunk_order_independent_descriptors), "V4 features use global order-independent descriptors")
	for grammar in ["DIRECTIONAL_TUNNEL", "CHAMBER", "FISSURE", "RARE_LARGE_CAVERN", "SURFACE_ENTRANCE", "FLOODED_POCKET"]:
		_check(grammar in architecture.cave_grammars, "cave grammar %s exposed" % grammar)
	var orders := [[Vector2i(0,0),Vector2i(1,0),Vector2i(2,0)],[Vector2i(2,0),Vector2i(0,0),Vector2i(1,0)],[Vector2i(1,0),Vector2i(2,0),Vector2i(0,0)]]
	var hashes: Array[String] = []
	for order: Array in orders:
		var world: Variant = _world(99173, 4)
		for coordinate: Vector2i in order: world.request_chunk(coordinate, 1)
		world.flush_generation(); hashes.append(world.get_region_content_hash(Rect2i(0,0,3,1)))
	_equal(hashes[0], hashes[1], "A-B-C equals C-A-B")
	_equal(hashes[0], hashes[2], "A-B-C equals B-C-A")
	var legacy: Variant = _world(99173, 3); legacy.request_chunk_region(Rect2i(0,0,3,1), 1); legacy.flush_generation()
	_check(legacy.get_region_content_hash(Rect2i(0,0,3,1)) != hashes[0], "V3 content remains separately addressable")

func _test_content_and_structure() -> void:
	var area := Rect2i(-4, -1, 9, 14)
	var total_sand := 0; var total_water := 0; var total_caves := 0; var total_ores := 0
	var seeds_with_water := 0; var seeds_with_dynamic := 0
	for seed in [3,41,2965,8191,15508,18076,33191,45613,71317,8675309,99173,120011]:
		var world: Variant = _world(seed, 4); world.request_chunk_region(area, 1); world.flush_generation()
		var stable: Dictionary = world.get_generation_stability_report(area)
		var quality: Dictionary = world.get_worldgen_quality_report(area)
		var content: Dictionary = quality.content; var structure: Dictionary = quality.structure
		var maxima: Array = stable.maximum_chunk_void_fraction_by_depth_band
		var limits: Array = stable.void_fraction_limits
		if int(structure.isolated_void_cells) > 0: print("p05_isolated_voids seed=%d cells=%d" % [seed,int(structure.isolated_void_cells)])
		_equal(int(stable.initially_active_dynamic_cells), 0, "seed %d starts in equilibrium" % seed)
		_check(int(content.sand_cells) > 0, "seed %d contains physical Sand" % seed)
		_check(int(content.sand_deposits) > 0, "seed %d contains a Sand deposit" % seed)
		_check(int(content.cave_systems) > 0, "seed %d contains cave systems" % seed)
		_check(int(content.ore_veins) > 0, "seed %d contains ore veins" % seed)
		_check(float(content.stable_dynamic_region_percentage) >= 99.9, "seed %d dynamic material regions sleep" % seed)
		_check(int(structure.longest_flat_run_cells) < 420, "seed %d avoids extreme flat terrain" % seed)
		_check(int(structure.isolated_void_cells) <= 1, "seed %d isolated void artifacts remain bounded" % seed)
		for band in 3:
			_check(float(maxima[band]) <= float(limits[band]) + 0.0001, "seed %d depth band %d stays inside its void budget max=%.6f limit=%.6f" % [seed, band, float(maxima[band]), float(limits[band])])
		total_sand += int(content.sand_cells); total_water += int(content.water_cells)
		total_caves += int(content.cave_systems); total_ores += int(content.ore_veins)
		seeds_with_water += 1 if int(content.water_cells) > 0 else 0
		seeds_with_dynamic += 1 if float(content.dynamic_region_percentage) > 0.0 else 0
	print("p05_content seeds=12 sand_cells=%d water_cells=%d seeds_with_water=%d cave_systems=%d ore_veins=%d dynamic_seeds=%d" % [total_sand,total_water,seeds_with_water,total_caves,total_ores,seeds_with_dynamic])
	_check(total_sand > 10000, "sample contains substantial physical Sand")
	_check(total_water > 1000, "sample contains substantial physical Water")
	_check(seeds_with_water >= 3, "Water appears across varied seeds")
	_equal(seeds_with_dynamic, 12, "every sampled world contains stable dynamic material")

func _test_player_induced_chaos() -> void:
	var area := Rect2i(-5,-1,12,14)
	var sand_world: Variant = _world(8675309,4); sand_world.request_chunk_region(area,0); sand_world.flush_generation()
	var sand := _find_cell(sand_world,area,2); _check(sand.x < 900000,"stable V4 Sand deposit found")
	if sand.x < 900000:
		var before := _count_material(sand_world,area,2); sand_world.set_cell(sand + Vector2i.DOWN,0)
		var moved := 0
		for tick in 120: sand_world.step(); moved += int(sand_world.get_statistics().cells_moved)
		_check(moved > 0,"removing support wakes and moves Sand")
		_equal(_count_material(sand_world,area,2),before,"Sand cell count conserved after support removal")
	var water_world: Variant = _world(18076,4); water_world.request_chunk_region(area,0); water_world.flush_generation()
	var breach: Array = _find_water_wall(water_world,area); _check(not breach.is_empty(),"stable V4 aquifer wall found")
	if not breach.is_empty():
		var water: Vector2i = breach[0]; var direction: Vector2i = breach[1]
		var mass_before := int(water_world.get_total_conserved_water_phase_mass())
		for offset in range(1,9):
			var target := water + direction * offset
			if water_world.get_cell(target) != 3: water_world.set_cell(target,0)
		var transfers := 0
		for tick in 180: water_world.step(); transfers += int(water_world.get_fluid_statistics().fluid_transfers)
		_check(transfers > 0,"opening an aquifer wall wakes Water")
		_equal(int(water_world.get_total_conserved_water_phase_mass()),mass_before,"aquifer breach conserves Water-family mass")

func _find_cell(world: Variant, area: Rect2i, material: int) -> Vector2i:
	var first := area.position * 64; var end := (area.position + area.size) * 64
	for y in range(first.y + 2,end.y - 2):
		for x in range(first.x + 2,end.x - 10):
			var cell := Vector2i(x,y)
			if world.get_cell(cell) == material and world.get_cell(cell + Vector2i.DOWN) in [1,4,5]: return cell
	return Vector2i(999999,999999)

func _find_water_wall(world: Variant, area: Rect2i) -> Array:
	var first := area.position * 64; var end := (area.position + area.size) * 64
	for y in range(first.y + 10,end.y - 10):
		for x in range(first.x + 10,end.x - 10):
			var water := Vector2i(x,y)
			if world.get_cell(water) != 3: continue
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if world.get_cell(water + direction) in [1,4,5]: return [water,direction]
	return []

func _count_material(world: Variant, area: Rect2i, material: int) -> int:
	var result := 0; var first := area.position * 64; var end := (area.position + area.size) * 64
	for y in range(first.y,end.y):
		for x in range(first.x,end.x): result += int(world.get_cell(Vector2i(x,y)) == material)
	return result

func _world(seed: int, version: int) -> Variant:
	var world := NativeSandWorld.new(); world.configure_world({"seed":seed,"generation_version":version},6); return world

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label,expected,actual])
