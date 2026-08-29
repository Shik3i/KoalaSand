extends SceneTree

var failed := false
var checks := 0

func _initialize() -> void: call_deferred("_run")

func _world(seed: int, workers: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world

func _measure(world: Variant, ticks: int) -> Dictionary:
	var samples: Array[float] = []
	var thermal: Array[float] = []
	var gas: Array[float] = []
	var fluid: Array[float] = []
	var pipe: Array[float] = []
	var visited_peak := 0
	var pipe_active_peak := 0
	var phase_changes_total := 0
	for tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		var ts: Dictionary = world.get_thermal_statistics()
		var gs: Dictionary = world.get_gas_statistics()
		var fs: Dictionary = world.get_fluid_statistics()
		var ps: Dictionary = world.get_pipe_statistics()
		thermal.append(float(ts.get("thermal_usec", 0)) / 1000.0)
		gas.append(float(gs.get("gas_usec", 0)) / 1000.0)
		fluid.append(float(fs.get("fluid_usec", 0)) / 1000.0)
		pipe.append(float(ps.get("pipe_usec", 0)) / 1000.0)
		visited_peak = maxi(visited_peak, int(ts.get("visited_cells", 0)))
		pipe_active_peak = maxi(pipe_active_peak, int(ps.get("segments_active", 0)))
		phase_changes_total = int(ts.get("phase_changes_total", phase_changes_total))
	samples.sort(); thermal.sort(); gas.sort(); fluid.sort(); pipe.sort()
	return {
		"avg": _avg(samples), "p95": _pct(samples, 0.95), "p99": _pct(samples, 0.99), "worst": samples[-1],
		"thermal_avg": _avg(thermal), "thermal_p99": _pct(thermal, 0.99),
		"gas_avg": _avg(gas), "gas_p99": _pct(gas, 0.99), "fluid_avg": _avg(fluid),
		"pipe_avg": _avg(pipe), "pipe_p99": _pct(pipe, 0.99),
		"visited_peak": visited_peak, "pipe_active_peak": pipe_active_peak, "phase_changes_total": phase_changes_total,
	}

func _run() -> void:
	_uniform_idle()
	_thermal_256k()
	_thermal_scaling()
	_steam_256k()
	_steam_active()
	_steam_settled()
	_steam_plume()
	_condensation()
	_molten()
	_water_molten()
	_pipe_steam()
	_thermal_progression()
	print("PASS: Phase 9 performance gates (%d checks)" % checks if not failed else "FAIL: Phase 9 performance gates")
	quit(0 if not failed else 1)

func _uniform_idle() -> void:
	var world: Variant = _world(9100, 8)
	world.fill_pattern_state(Rect2i(0, 0, 2048, 2048), 1, 255, 255, 5000, 5000)
	world.step(); world.step(); world.step()
	var r := _measure(world, 30)
	var stats: Dictionary = world.get_thermal_statistics()
	print("phase9_thermal scenario=uniform_hot_4m avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f visited=%d" % [r.avg, r.p95, r.p99, stats.visited_cells])
	_check(int(stats.visited_cells) == 0, "uniform 4M thermal field sleeps")

func _thermal_scaling() -> void:
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(9101, workers)
		world.fill_pattern_state(Rect2i(0, 0, 1024, 1024), 1, 255, 255, 800, 6200)
		var r := _measure(world, 24)
		hashes.append(world.authoritative_physical_hash())
		print("phase9_thermal scenario=active_1m workers=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f thermal_avg_ms=%.4f thermal_p99_ms=%.4f visited_peak=%d hash=%s" % [workers, r.avg, r.p95, r.p99, r.worst, r.thermal_avg, r.thermal_p99, r.visited_peak, hashes[-1]])
		if workers == 8: _check(r.thermal_p99 <= 16.67, "1M active thermal exceeds 16.67 ms")
	for index in range(1, hashes.size()): _check(hashes[index] == hashes[0], "thermal performance worker parity")

func _thermal_256k() -> void:
	var world: Variant = _world(9104, 8)
	world.fill_pattern_state(Rect2i(0, 0, 512, 512), 1, 255, 255, 800, 6200)
	var r := _measure(world, 24)
	print("phase9_thermal scenario=active_256k avg_ms=%.4f p99_ms=%.4f thermal_avg_ms=%.4f thermal_p99_ms=%.4f visited_peak=%d" % [r.avg, r.p99, r.thermal_avg, r.thermal_p99, r.visited_peak])
	_check(r.thermal_p99 < 16.67, "256k active thermal exceeds 16.67 ms")

func _steam_256k() -> void:
	var world: Variant = _world(9105, 8)
	world.fill_pattern_state(Rect2i(0, 0, 512, 512), 17, 64, 192, 1700, 1700)
	var r := _measure(world, 24)
	print("phase9_gas scenario=active_256k avg_ms=%.4f p99_ms=%.4f gas_avg_ms=%.4f gas_p99_ms=%.4f visited_peak=%d" % [r.avg, r.p99, r.gas_avg, r.gas_p99, r.visited_peak])
	_check(r.gas_p99 < 16.67, "256k active Steam exceeds 16.67 ms")

func _steam_active() -> void:
	var world: Variant = _world(9102, 8)
	world.fill_pattern_state(Rect2i(0, 0, 1024, 1024), 17, 64, 192, 1700, 1700)
	var mass: int = world.get_total_phase_family_mass(1)
	var r := _measure(world, 24)
	print("phase9_gas scenario=active_1m avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f gas_avg_ms=%.4f gas_p99_ms=%.4f fluid_avg_ms=%.4f mass=%d" % [r.avg, r.p95, r.p99, r.worst, r.gas_avg, r.gas_p99, r.fluid_avg, mass])
	_check(world.get_total_phase_family_mass(1) == mass, "1M Steam mass conserved")
	_check(r.fluid_avg <= 16.67, "1M active Steam exceeds 16.67 ms")

func _steam_settled() -> void:
	var world: Variant = _world(9103, 8)
	world.fill_pattern_state(Rect2i(0, 0, 1024, 1024), 17, 255, 255, 1700, 1700)
	for tick in 8: world.step()
	var r := _measure(world, 30)
	print("phase9_gas scenario=settled_1m avg_ms=%.4f p99_ms=%.4f fluid_avg_ms=%.4f active=%d" % [r.avg, r.p99, r.fluid_avg, world.get_gas_statistics().active_cells])
	_check(world.get_fluid_statistics().fluid_cells_visited == 0, "settled 1M Steam sleeps")

func _steam_plume() -> void:
	var world: Variant = _world(9106, 8)
	world.fill_rect(Rect2i(-128, 120, 256, 1), 1)
	world.fill_rect_state(Rect2i(-48, 64, 96, 48), 17, 160, 1900)
	var mass: int = world.get_total_phase_family_mass(1)
	var r := _measure(world, 60)
	var gas: Dictionary = world.get_gas_statistics()
	print("phase9_gas scenario=steam_plume avg_ms=%.4f p99_ms=%.4f gas_avg_ms=%.4f gas_p99_ms=%.4f active=%d visited=%d transfers=%d mass=%d" % [r.avg, r.p99, r.gas_avg, r.gas_p99, gas.active_cells, gas.visited_cells, gas.transfers, mass])
	_check(world.get_total_phase_family_mass(1) == mass, "Steam plume mass conserved")

func _condensation() -> void:
	var world: Variant = _world(9107, 8)
	world.fill_rect_state(Rect2i(-64, 0, 128, 64), 17, 192, 1500)
	for x in range(-64, 64, 4): world.fill_rect_state(Rect2i(x, 0, 3, 64), 1, 255, 0)
	world.fill_rect_state(Rect2i(-65, -1, 130, 1), 1, 255, 0)
	world.fill_rect_state(Rect2i(-65, 64, 130, 1), 1, 255, 0)
	world.fill_rect_state(Rect2i(-65, 0, 1, 64), 1, 255, 0)
	world.fill_rect_state(Rect2i(64, 0, 1, 64), 1, 255, 0)
	var mass: int = world.get_total_phase_family_mass(1)
	var r := _measure(world, 4000)
	var gas: Dictionary = world.get_gas_statistics()
	print("phase9_phase scenario=condensation avg_ms=%.4f p99_ms=%.4f thermal_avg_ms=%.4f gas_avg_ms=%.4f condensed=%d phase_changes=%d" % [r.avg, r.p99, r.thermal_avg, r.gas_avg, gas.steam_condensed, r.phase_changes_total])
	_check(world.get_total_phase_family_mass(1) == mass, "condensation mass conserved")
	_check(int(gas.steam_condensed) > 0, "condensation benchmark produces Water")

func _molten() -> void:
	for material in [18, 19]:
		var world: Variant = _world(9110 + material, 8)
		world.fill_pattern_state(Rect2i(0, 0, 512, 512), material, 64, 192, 8000, 8000)
		var r := _measure(world, 24)
		print("phase9_molten material=%d cells=262144 avg_ms=%.4f p99_ms=%.4f fluid_avg_ms=%.4f" % [material, r.avg, r.p99, r.fluid_avg])
		_check(r.p99 < 16.67, "256k molten workload")

func _water_molten() -> void:
	var world: Variant = _world(9130, 8)
	world.fill_rect(Rect2i(-128, 128, 256, 1), 1)
	for stripe in range(-112, 112, 8):
		world.fill_rect_state(Rect2i(stripe, 16, 4, 96), 3, 192, 1450)
		world.fill_rect_state(Rect2i(stripe + 4, 16, 4, 96), 19, 192, 9500)
	var water_mass: int = world.get_total_phase_family_mass(1)
	var iron_mass: int = world.get_total_phase_family_mass(3)
	var r := _measure(world, 360)
	print("phase9_mixed scenario=water_molten_iron avg_ms=%.4f p99_ms=%.4f thermal_avg_ms=%.4f thermal_p99_ms=%.4f fluid_avg_ms=%.4f gas_avg_ms=%.4f phase_changes=%d" % [r.avg, r.p99, r.thermal_avg, r.thermal_p99, r.fluid_avg, r.gas_avg, r.phase_changes_total])
	_check(world.get_total_phase_family_mass(1) == water_mass and world.get_total_phase_family_mass(3) == iron_mass, "Water plus molten family mass conserved")
	_check(int(r.phase_changes_total) > 0, "Water plus molten interaction causes phase changes")

func _pipe_steam() -> void:
	var world: Variant = _world(9120, 8)
	world.place_pipe_line(Vector2i(0, 0), Vector2i(49999, 0))
	for x in 50000: world.set_pipe_fluid(Vector2i(x, 0), 17, 16384 if x % 2 == 0 else 49152, 1800)
	var r := _measure(world, 20)
	print("phase9_pipe_steam segments=50000 avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f pipe_avg_ms=%.4f pipe_p99_ms=%.4f active_peak=%d steam_mass=%d" % [r.avg, r.p95, r.p99, r.pipe_avg, r.pipe_p99, r.pipe_active_peak, world.get_pipe_statistics().steam_mass])
	_check(world.get_pipe_statistics().steam_mass > 0, "50k Steam Pipe mass retained")
	_check(r.pipe_active_peak == 50000, "50k Steam Pipe segments active")

func _thermal_progression() -> void:
	var world: Variant = _world(9140, 8)
	var stage: Dictionary = world.evaluate_progression_pacing(4590, 200000).concentrate_recovery_cumulative
	var branch_cost := {"glass": 12400, "iron": 820, "gold": 1}
	print("phase9_progression path=basic_thermodynamics>phase_processing>steam_handling>molten_processing cost_glass=%d cost_iron=%d cost_gold=%d raw_sand=%d output_glass=%d output_iron=%d output_gold=%d coal=%d throughput_raw_per_s=240 estimated_upper_bound_s=%.3f" % [branch_cost.glass, branch_cost.iron, branch_cost.gold, stage.raw_sand, stage.glass, stage.iron, stage.gold, stage.coal, stage.estimated_seconds])
	_check(bool(stage.reached), "thermal progression pacing fixture reaches late processing")
	_check(int(stage.glass) >= branch_cost.glass and int(stage.iron) >= branch_cost.iron and int(stage.gold) >= branch_cost.gold, "thermal branch cumulative cost is reachable")

func _avg(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, float(values.size()))

func _pct(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(float(values.size()) * percentile) - 1, 0, values.size() - 1)]

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failed = true
	push_error("PHASE9 PERF: " + message)
