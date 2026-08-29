extends SceneTree

const PIPE := 10
const PUMP := 14
const VALVE := 15

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 8)
	world.set_game_mode(1)
	return world


func _build_rows(world: Variant, rows: int, columns: int) -> void:
	for y in rows: world.place_pipe_line(Vector2i(0, y * 2), Vector2i(columns - 1, y * 2))


func _run() -> void:
	_idle_100k()
	_stable_filled_100k()
	_active_50k()
	_uphill_1000()
	print("PASS: Phase 8 Pipe performance gates" if not failed else "FAIL: Phase 8 Pipe performance gates")
	quit(0 if not failed else 1)


func _idle_100k() -> void:
	var world: Variant = _world(8101)
	_build_rows(world, 100, 1000)
	for tick in 12: world.step()
	_measure("idle_100k", world, 120)
	var stats: Dictionary = world.get_pipe_statistics()
	_check(int(stats.segments_total) == 100000, "idle fixture segment count")
	_check(int(stats.segments_active) == 0, "idle 100k sleeps")


func _stable_filled_100k() -> void:
	var world: Variant = _world(8102)
	_build_rows(world, 100, 1000)
	for y in 100:
		for x in 1000: world.set_pipe_mass(Vector2i(x, y * 2), 32768, 1600)
	var mass_before: int = world.get_total_pipe_water_mass()
	for tick in 16: world.step()
	_measure("stable_filled_100k", world, 120)
	var stats: Dictionary = world.get_pipe_statistics()
	_check_equal(world.get_total_pipe_water_mass(), mass_before, "stable filled conservation")
	_check(int(stats.segments_active) == 0, "stable filled 100k sleeps")


func _active_50k() -> void:
	var world: Variant = _world(8103)
	_build_rows(world, 50, 1000)
	for y in 50:
		for x in range(0, 1000, 2): world.set_pipe_mass(Vector2i(x, y * 2), 65535, 1300)
		for x in range(99, 1000, 100):
			world.remove_structure_at(Vector2i(x, y * 2))
			world.place_structure(PUMP if int(x / 100) % 2 == 0 else VALVE, Vector2i(x, y * 2), 0)
	var mass_before: int = world.get_total_conserved_water_phase_mass()
	var measured: Dictionary = _measure("active_50k", world, 30)
	_check_equal(world.get_total_conserved_water_phase_mass(), mass_before, "active Pipe/world Water-family conservation including physical leaks")
	_check(int(measured.max_visited) >= 40000, "active fixture exercises many segments")


func _uphill_1000() -> void:
	var world: Variant = _world(8104)
	world.place_pipe_line(Vector2i(0, 0), Vector2i(0, 1000))
	for y in range(999, 0, -128):
		world.remove_structure_at(Vector2i(0, y))
		world.place_structure(PUMP, Vector2i(0, y), 3)
	for y in range(872, 1001): world.set_pipe_mass(Vector2i(0, y), 65535, 1300)
	var mass_before: int = world.get_total_conserved_water_phase_mass()
	for tick in 8000: world.step()
	var stats: Dictionary = world.get_pipe_statistics()
	var highest_reached := 1000
	for y in 1001:
		if world.get_pipe_state(Vector2i(0, y)).mass > 0: highest_reached = mini(highest_reached, y)
	print("phase8_uphill cells=1001 pumps=%d highest_y=%d top_mass=%d mass_before=%d mass_after=%d hash=%s pipe_ms=%.4f" % [stats.pumps, highest_reached, world.get_pipe_state(Vector2i(0, 0)).mass, mass_before, world.get_total_conserved_water_phase_mass(), world.pipe_state_hash(), float(stats.pipe_usec) / 1000.0])
	_check_equal(world.get_total_conserved_water_phase_mass(), mass_before, "1000-cell uphill Water-family conservation")
	_check(world.get_pipe_state(Vector2i(0, 0)).mass > 0, "finite series Pumps lift across 1000 cells")


func _measure(name: String, world: Variant, ticks: int) -> Dictionary:
	var samples: Array[float] = []
	var pipe_samples: Array[float] = []
	var max_visited := 0
	var transfers := 0
	var pump_work := 0
	var valve_work := 0
	for tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		var stats: Dictionary = world.get_pipe_statistics()
		pipe_samples.append(float(stats.pipe_usec) / 1000.0)
		max_visited = maxi(max_visited, int(stats.segments_visited))
		transfers += int(stats.transfers)
		pump_work += int(stats.pump_work)
		valve_work += int(stats.valve_work)
	samples.sort(); pipe_samples.sort()
	var average: float = _average(samples)
	var stats: Dictionary = world.get_pipe_statistics()
	print("phase8_pipe scenario=%s segments_total=%d segments_active=%d visited_peak=%d transfers_total=%d pump_work=%d valve_work=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f pipe_avg_ms=%.4f pipe_p95_ms=%.4f memory_bytes=%d scheduler_bytes=%d mass=%d hash=%s" % [name, stats.segments_total, stats.segments_active, max_visited, transfers, pump_work, valve_work, average, _percentile(samples, 0.95), _percentile(samples, 0.99), samples[-1], _average(pipe_samples), _percentile(pipe_samples, 0.95), stats.record_bytes, stats.scheduler_key_bytes, stats.mass_total, world.pipe_state_hash()])
	return {"average_ms": average, "max_visited": max_visited}


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, float(values.size()))


func _percentile(values: Array[float], quantile: float) -> float:
	return values[clampi(int(ceil(quantile * values.size())) - 1, 0, values.size() - 1)]


func _check(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("PHASE8 PERFORMANCE: " + message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [message, expected, actual])
