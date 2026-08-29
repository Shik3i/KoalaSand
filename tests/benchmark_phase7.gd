extends SceneTree

const EMPTY := 0
const STONE := 1
const SAND := 2
const WATER := 3

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("KoalaSand Phase 7 production unified-matter performance matrix")
	for workers in [1, 2, 4, 8]: _active_sand_1m(workers)
	for workers in [1, 2, 4, 8]: _active_water_1m(workers)
	_active_water_256k()
	_settled_reservoir_1m()
	_dam_break()
	_persistent_4m()
	_mixed_500k_500k()
	print("PASS: Phase 7 production performance gates" if not failed else "FAIL: Phase 7 production performance gates")
	quit(0 if not failed else 1)


func _world(seed: int, workers: int, chunks: Rect2i) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.allocate_chunk_rect(chunks)
	return world


func _active_sand_1m(workers: int) -> void:
	var world: Variant = _world(71000, workers, Rect2i(0, 0, 32, 33))
	var written: int = world.fill_rect(Rect2i(0, 0, 2048, 2048), SAND, 2)
	world.fill_rect(Rect2i(0, 2111, 2048, 1), STONE)
	world.finalize_initialization()
	var result := _measure("active_sand_1m", world, 20, workers)
	_check(written >= 1048576, "1M Sand fixture contains genuine active cells")
	_check(result.max_visited >= 1000000, "1M Sand evaluates approximately one million cells")
	if workers == 8: _check(result.average_ms <= 16.67, "1M production Sand exceeds 60 Hz")


func _active_water_1m(workers: int) -> void:
	var world: Variant = _world(72000, workers, Rect2i(0, 0, 32, 33))
	var written: int = world.fill_rect(Rect2i(0, 0, 2048, 2048), WATER, 2)
	world.fill_rect(Rect2i(0, 2111, 2048, 1), STONE)
	world.finalize_initialization()
	var mass_before: int = world.get_total_water_mass()
	var result := _measure("active_water_1m", world, 20, workers)
	_check(written >= 1048576, "1M Water fixture contains genuine active cells")
	_check(result.max_fluid_visited >= 1000000, "1M Water evaluates approximately one million cells")
	_check_equal(world.get_total_water_mass(), mass_before, "1M Water exact mass conservation worker %d" % workers)
	if workers == 8: _check(result.average_ms <= 16.67, "1M production Water exceeds 60 Hz")


func _active_water_256k() -> void:
	var world: Variant = _world(73001, 8, Rect2i(0, 0, 16, 17))
	world.fill_rect(Rect2i(0, 0, 1024, 1024), WATER, 2)
	world.fill_rect(Rect2i(0, 1087, 1024, 1), STONE)
	world.finalize_initialization()
	_measure("active_water_256k", world, 30, 8)


func _settled_reservoir_1m() -> void:
	var world: Variant = _world(73002, 8, Rect2i(-1, -1, 18, 18))
	world.fill_rect(Rect2i(0, 0, 1024, 1024), WATER)
	world.fill_rect(Rect2i(-1, 0, 1, 1025), STONE)
	world.fill_rect(Rect2i(1024, 0, 1, 1025), STONE)
	world.fill_rect(Rect2i(-1, 1024, 1026, 1), STONE)
	world.finalize_initialization()
	var before: int = world.get_total_water_mass()
	var result := _measure("settled_water_1m", world, 120, 8)
	_check_equal(world.get_total_water_mass(), before, "settled reservoir mass conservation")
	_check_equal(result.max_fluid_visited, 0, "settled million-cell reservoir visits zero")


func _dam_break() -> void:
	var world: Variant = _world(73003, 8, Rect2i(-1, -1, 18, 10))
	world.fill_rect(Rect2i(0, 384, 1024, 1), STONE)
	world.fill_rect(Rect2i(0, 100, 1, 284), STONE)
	world.fill_rect(Rect2i(512, 100, 1, 284), STONE)
	world.fill_rect(Rect2i(1, 128, 511, 256), WATER)
	world.finalize_initialization()
	for y in range(300, 384): world.set_cell(Vector2i(512, y), EMPTY)
	var before: int = world.get_total_water_mass()
	var result := _measure("dam_break", world, 300, 8)
	_check_equal(world.get_total_water_mass(), before, "dam break mass conservation")
	_check(result.total_transfers > 0, "dam break produces transfers")


func _persistent_4m() -> void:
	var world: Variant = _world(73004, 8, Rect2i(0, 0, 32, 32))
	for origin in [Vector2i(64, 64), Vector2i(640, 256), Vector2i(1152, 768), Vector2i(1664, 1408)]:
		world.fill_rect(Rect2i(origin.x, origin.y, 256, 128), WATER)
		world.fill_rect(Rect2i(origin.x - 1, origin.y + 128, 258, 1), STONE)
		world.fill_rect(Rect2i(origin.x - 1, origin.y, 1, 129), STONE)
		world.fill_rect(Rect2i(origin.x + 256, origin.y, 1, 129), STONE)
	world.finalize_initialization()
	_measure("persistent_4m", world, 120, 8)


func _mixed_500k_500k() -> void:
	var world: Variant = _world(73005, 8, Rect2i(0, 0, 32, 17))
	var water_cells: int = world.fill_rect(Rect2i(0, 0, 2048, 1024), WATER, 2)
	var sand_cells: int = world.fill_rect(Rect2i(1, 1, 2048, 1024), SAND, 2)
	world.fill_rect(Rect2i(0, 1087, 2048, 1), STONE)
	world.finalize_initialization()
	var water_before: int = world.get_total_water_mass()
	var result := _measure("mixed_500k_sand_500k_water", world, 30, 8)
	_check(water_cells >= 524288 and sand_cells >= 524288, "mixed fixture reaches approximately 1M matter cells")
	_check_equal(world.get_total_water_mass(), water_before, "mixed stress conserves Water")
	_check(result.total_moves > 0 and result.total_transfers > 0, "mixed stress executes both matter paths")


func _measure(name: String, world: Variant, ticks: int, workers: int) -> Dictionary:
	var samples: Array[float] = []
	var fluid_samples: Array[float] = []
	var granular_samples: Array[float] = []
	var barrier_samples: Array[float] = []
	var max_active := 0
	var max_visited := 0
	var max_fluid_visited := 0
	var total_transfers := 0
	var total_mass_transferred := 0
	var total_moves := 0
	for tick in ticks:
		var start := Time.get_ticks_usec()
		world.step()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
		var stats: Dictionary = world.get_statistics()
		fluid_samples.append(float(stats.fluid_usec) / 1000.0)
		granular_samples.append(float(stats.granular_usec) / 1000.0)
		barrier_samples.append(float(stats.fluid_barrier_usec + stats.granular_barrier_usec) / 1000.0)
		max_active = maxi(max_active, int(stats.fluid_cells_active))
		max_visited = maxi(max_visited, int(stats.cells_visited))
		max_fluid_visited = maxi(max_fluid_visited, int(stats.fluid_cells_visited))
		total_transfers += int(stats.fluid_transfers)
		total_mass_transferred += int(stats.fluid_mass_transferred)
		total_moves += int(stats.cells_moved)
	samples.sort()
	fluid_samples.sort()
	granular_samples.sort()
	barrier_samples.sort()
	var stats: Dictionary = world.get_statistics()
	var result := {
		"average_ms": _average(samples),
		"max_visited": max_visited,
		"max_fluid_visited": max_fluid_visited,
		"total_transfers": total_transfers,
		"total_moves": total_moves,
	}
	print("phase7_benchmark scenario=%s workers=%d ticks=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f granular_avg_ms=%.4f fluid_avg_ms=%.4f barrier_avg_ms=%.4f active_peak=%d granular_visited_peak=%d fluid_visited_peak=%d transfers_total=%d mass_units_transferred_total=%d moves_total=%d worker_utilization_percent=%.1f fluid_mass=%d fluid_plane_chunks=%d fluid_plane_bytes=%d activity_bytes=%d hash=%s" % [
		name, workers, ticks, result.average_ms, _percentile(samples, 0.95), _percentile(samples, 0.99), samples[-1],
		_average(granular_samples), _average(fluid_samples), _average(barrier_samples), max_active, max_visited, max_fluid_visited,
		total_transfers, total_mass_transferred, total_moves, float(stats.simulation_worker_utilization_percent), world.get_total_water_mass(),
		int(stats.fluid_plane_chunks), int(stats.fluid_plane_bytes), int(stats.fluid_activity_bytes), world.authoritative_physical_hash()
	])
	return result


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, float(values.size()))


func _percentile(values: Array[float], quantile: float) -> float:
	return values[clampi(int(ceil(quantile * values.size())) - 1, 0, values.size() - 1)]


func _check(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("PHASE7 PERFORMANCE: " + message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [message, expected, actual])
