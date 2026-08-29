extends SceneTree

const RAW := 2
const HEAVY := 7
const SCREEN := 6
const MAGNET := 7

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_benchmark_idle_magnets()
	_benchmark_active_magnets(300, "representative")
	_benchmark_active_magnets(1200, "stress")
	_benchmark_screens()
	_benchmark_separation_quality()
	quit(0)

func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world

func _benchmark_idle_magnets() -> void:
	var world: Variant = _world(65501)
	var placed := 0
	for row in 100:
		for column in 100:
			placed += 1 if world.place_structure(MAGNET, Vector2i(column * 14, row * 7), 0) > 0 else 0
	for _tick in 3: world.step()
	var started := Time.get_ticks_usec()
	for _tick in 300: world.step()
	var elapsed := Time.get_ticks_usec() - started
	var stats: Dictionary = world.get_physical_processing_statistics()
	print("phase65_idle_magnets total=%d active=%d cells_tested=%d magnetic_ms=%.6f wall_tick_ms=%.6f" % [placed, stats.magnets_active, stats.magnetic_cells_tested, float(stats.magnetic_usec) / 1000.0, float(elapsed) / 300000.0])

func _benchmark_active_magnets(count: int, label: String) -> void:
	var world: Variant = _world(65502 + count)
	var profile := 2386
	var iron_signature := _signature_for(world, profile, 1)
	var placed := 0
	for index in count:
		var origin := Vector2i((index % 40) * 16, (index / 40) * 8)
		if world.place_structure(MAGNET, origin, 0) <= 0: continue
		placed += 1
		world.place_conveyor_line(origin + Vector2i(-1, 6), origin + Vector2i(12, 6), 1)
		for x in [2, 5, 8]: world.set_cell_with_metadata(origin + Vector2i(x, 5), HEAVY, profile, iron_signature)
	var total_usec := 0
	var tested := 0
	var moves := 0
	for _tick in 12:
		world.step()
		var stats: Dictionary = world.get_physical_processing_statistics()
		total_usec += int(stats.magnetic_usec); tested += int(stats.magnetic_cells_tested); moves += int(stats.magnetic_moves)
	print("phase65_magnets_%s total=%d active_last=%d regions=%d cells_tested=%d moves=%d magnetic_avg_ms=%.4f" % [label, placed, world.get_physical_processing_statistics().magnets_active, world.get_physical_processing_statistics().registered_region_chunks, tested, moves, float(total_usec) / 12000.0])

func _benchmark_screens() -> void:
	var world: Variant = _world(65503)
	var profile := 2386
	var fine := _signature_for_size(world, profile, 0)
	var coarse := _signature_for_size(world, profile, 2)
	var placed := 0
	for index in 500:
		var origin := Vector2i((index % 40) * 12, (index / 40) * 7)
		if world.place_structure(SCREEN, origin, 0) <= 0: continue
		placed += 1
		for x in [2, 4, 6, 8]: world.set_cell_with_metadata(origin + Vector2i(x, 2), RAW, profile, fine if x in [2, 6] else coarse)
	var total_usec := 0
	var tests := 0
	var vibration := 0
	for _tick in 12:
		world.step()
		var stats: Dictionary = world.get_physical_processing_statistics()
		total_usec += int(stats.screen_usec); tests += int(stats.screen_grains_tested); vibration += int(stats.vibration_evaluations)
	var final: Dictionary = world.get_physical_processing_statistics()
	print("phase65_screens total=%d active_last=%d grains_tested=%d vibration=%d passes_total=%d screen_avg_ms=%.4f" % [placed, final.screens_active, tests, vibration, final.screen_passes_total, float(total_usec) / 12000.0])

func _benchmark_separation_quality() -> void:
	var world: Variant = _world(65504)
	var profile := 64848
	var old: Dictionary = world.evaluate_processing_routes(profile, 100000)
	var magnetic := 0
	var nonmagnetic := 0
	var fine := 0
	var coarse := 0
	var gold_retained := 0
	for signature in 100000:
		var stable_signature := signature & 0xffff
		var constituent: int = world.get_hidden_constituent(profile, stable_signature)
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, stable_signature)
		var size: int = world.get_grain_size_class(Vector2i(9000, 9000))
		fine += 1 if size == 0 else 0
		coarse += 1 if size != 0 else 0
		world.set_cell_with_metadata(Vector2i(9000, 9000), HEAVY, profile, stable_signature)
		var susceptibility: int = world.get_magnetic_susceptibility(Vector2i(9000, 9000))
		magnetic += 1 if susceptibility >= 800 else 0
		nonmagnetic += 1 if susceptibility < 800 else 0
		gold_retained += 1 if constituent == 3 and susceptibility < 800 else 0
	world.set_cell(Vector2i(9000, 9000), 0)
	print("phase65_separation input=100000 old_A=%s old_B=%s old_C=%s fine=%d coarse=%d magnetic=%d nonmagnetic=%d gold_retained=%d lost=0" % [old.route_a, old.route_b, old.route_c, fine, coarse, magnetic, nonmagnetic, gold_retained])

func _signature_for(world: Variant, profile: int, constituent: int) -> int:
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) == constituent: return signature
	return 0

func _signature_for_size(world: Variant, profile: int, size_class: int) -> int:
	for signature in 65536:
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, signature)
		if world.get_grain_size_class(Vector2i(9000, 9000)) == size_class:
			world.set_cell(Vector2i(9000, 9000), 0)
			return signature
	return 0
