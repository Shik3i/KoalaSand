extends SceneTree

const WATER := 3
const STEAM := 17

var failed := false
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int, workers: int = 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_steam_worker_scaling()
	_pipe_active(50000, true)
	_pipe_active(100000, false)
	_pipe_stable_100k()
	_pipe_steam_burst()
	_pipe_rupture_storm()
	print("PASS: Phase 9.5 performance gates (%d checks)" % checks if not failed else "FAIL: Phase 9.5 performance gates")
	quit(0 if not failed else 1)


func _steam_worker_scaling() -> void:
	var hashes: Array[String] = []
	var worker_counts: Array[int] = [1, 2, 4, 8]
	for workers: int in worker_counts:
		var world: Variant = _world(9510, workers)
		world.fill_pattern_state(Rect2i(0, 0, 1024, 1024), STEAM, 64, 192, 1700, 1700)
		var mass_before: int = world.get_total_phase_family_mass(1)
		var energy_before: int = world.get_total_thermal_enthalpy()
		var cold_ms := _step_ms(world)
		var result := _measure(world, 32)
		var hash_value: String = world.authoritative_physical_hash()
		hashes.append(hash_value)
		print("phase95_steam scenario=active_1m workers=%d cold_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f active_avg=%.0f active_peak=%d visited_avg=%.0f transfers_avg=%.0f barrier_avg_ms=%.4f worker_utilization_percent=%.1f hash=%s" % [
			workers, cold_ms, result.avg, result.p95, result.p99, result.worst,
			result.fluid_active_avg, result.fluid_active_peak, result.fluid_visited_avg, result.fluid_transfers_avg,
			result.fluid_barrier_avg, result.worker_utilization, hash_value,
		])
		_check_equal(world.get_total_phase_family_mass(1), mass_before, "1M Steam mass exact workers=%d" % workers)
		_check_equal(world.get_total_thermal_enthalpy(), energy_before, "1M Steam enthalpy exact workers=%d" % workers)
		_check(result.fluid_active_peak == 1048576, "1M Steam active count workers=%d" % workers)
		if workers == 8:
			_check(result.avg <= 8.0, "1M Steam average exceeds preferred 8 ms")
			_check(result.p99 <= 16.67, "1M Steam p99 exceeds 16.67 ms")
	for index in range(1, hashes.size()):
		_check_equal(hashes[index], hashes[0], "1M Steam worker hash workers=%d" % worker_counts[index])


func _pipe_active(segment_count: int, hard_gate: bool) -> void:
	var world: Variant = _world(9520 + segment_count)
	world.place_pipe_line(Vector2i.ZERO, Vector2i(segment_count - 1, 0))
	for x in segment_count:
		world.set_pipe_fluid(Vector2i(x, 0), STEAM, 16384 if x % 2 == 0 else 49152, 1800)
	var mass_before: int = world.get_pipe_statistics().steam_mass
	var energy_before: int = world.get_total_thermal_enthalpy()
	var cold_ms := _step_ms(world)
	var result := _measure(world, 32 if hard_gate else 16)
	var stats: Dictionary = world.get_pipe_statistics()
	print("phase95_pipe scenario=active_%dk cold_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f active_avg=%.0f active_peak=%d visited_avg=%.0f transfers_avg=%.0f pressure_avg=%.0f damage_avg=%.0f phase_avg=%.0f gather_avg_ms=%.4f state_avg_ms=%.4f flow_avg_ms=%.4f schedule_avg_ms=%.4f hash=%s" % [
		segment_count / 1000, cold_ms, result.avg, result.p95, result.p99, result.worst,
		result.pipe_active_avg, result.pipe_active_peak, result.pipe_visited_avg, result.pipe_transfers_avg,
		result.pipe_pressure_avg, result.pipe_damage_avg, result.pipe_phase_avg,
		result.pipe_gather_avg, result.pipe_state_avg, result.pipe_flow_avg, result.pipe_schedule_avg,
		world.authoritative_physical_hash(),
	])
	print("phase95_pipe_memory segments=%d record_bytes=%d active_key_bytes=%d persistent_buffer_capacity_bytes=%d thermal_scale_lookup_bytes=%d" % [
		segment_count, stats.record_bytes, stats.scheduler_key_bytes, stats.scheduler_buffer_capacity_bytes, stats.thermal_scale_lookup_bytes,
	])
	_check_equal(int(stats.steam_mass), mass_before, "%dk Pipe Steam mass exact" % (segment_count / 1000))
	_check_equal(world.get_total_thermal_enthalpy(), energy_before, "%dk Pipe Steam enthalpy exact" % (segment_count / 1000))
	_check(result.pipe_active_peak == segment_count, "%dk active Pipe count" % (segment_count / 1000))
	if hard_gate:
		_check(result.avg <= 8.0, "50k active Steam Pipe average exceeds 8 ms")
		_check(result.p99 <= 16.67, "50k active Steam Pipe p99 exceeds 16.67 ms")


func _pipe_stable_100k() -> void:
	var world: Variant = _world(9530)
	world.place_pipe_line(Vector2i.ZERO, Vector2i(99999, 0))
	for x in 100000:
		world.set_pipe_fluid(Vector2i(x, 0), STEAM, 32768, 1800)
	var mass_before: int = world.get_pipe_statistics().steam_mass
	var energy_before: int = world.get_total_thermal_enthalpy()
	for tick in 16:
		world.step()
	var result := _measure(world, 30)
	print("phase95_pipe scenario=stable_100k avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f active_avg=%.0f visited_avg=%.0f transfers_avg=%.0f" % [
		result.avg, result.p95, result.p99, result.worst, result.pipe_active_avg, result.pipe_visited_avg, result.pipe_transfers_avg,
	])
	_check_equal(world.get_pipe_statistics().steam_mass, mass_before, "stable 100k Pipe mass exact")
	_check_equal(world.get_total_thermal_enthalpy(), energy_before, "stable 100k Pipe enthalpy exact")
	_check(result.pipe_active_avg == 0.0, "stable 100k Pipes have zero active work")
	_check(result.pipe_visited_avg == 0.0, "stable 100k Pipes have zero visited work")


func _pipe_steam_burst() -> void:
	var world: Variant = _world(9540)
	world.place_pipe_line(Vector2i.ZERO, Vector2i(9999, 0))
	for x in range(0, 10000, 32):
		world.remove_structure_at(Vector2i(x, 0))
		world.place_structure(14, Vector2i(x, 0), 0)
	for x in 10000:
		# Canonical setter stores this as Water near the end of latent boiling.
		world.set_pipe_fluid(Vector2i(x, 0), WATER, 32768, 1819)
		world.set_material_state(Vector2i(x, 1), 1, 255, 9000)
	var mass_before: int = int(world.get_pipe_statistics().water_mass) + world.get_total_phase_family_mass(1)
	var energy_before: int = world.get_total_thermal_enthalpy()
	var result := _measure(world, 240)
	var stats: Dictionary = world.get_pipe_statistics()
	var mass_after: int = int(stats.water_mass) + int(stats.steam_mass) + world.get_total_phase_family_mass(1)
	print("phase95_pipe scenario=steam_transition_burst segments=10000 avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f active_peak=%d visited_peak=%d transfers_peak=%d pressure_peak=%d damage_peak=%d phase_peak=%d steam_mass=%d" % [
		result.avg, result.p95, result.p99, result.worst, result.pipe_active_peak, result.pipe_visited_peak,
		result.pipe_transfers_peak, result.pipe_pressure_peak, result.pipe_damage_peak, result.pipe_phase_peak, stats.steam_mass,
	])
	_check(int(stats.steam_mass) > 0, "Steam transition burst produces Pipe Steam")
	_check_equal(mass_after, mass_before, "Steam transition burst mass exact")
	_check_equal(world.get_total_thermal_enthalpy(), energy_before, "Steam transition burst enthalpy exact")


func _pipe_rupture_storm() -> void:
	var world: Variant = _world(9550)
	world.place_pipe_line(Vector2i.ZERO, Vector2i(4999, 0))
	for x in 5000:
		world.set_pipe_fluid(Vector2i(x, 0), STEAM, 65535, 3000)
	var mass_before: int = world.get_pipe_statistics().steam_mass
	var energy_before: int = world.get_total_thermal_enthalpy()
	var result := _measure(world, 16)
	var stats: Dictionary = world.get_pipe_statistics()
	var mass_after: int = int(stats.water_mass) + int(stats.steam_mass) + world.get_total_phase_family_mass(1)
	print("phase95_pipe scenario=rupture_storm segments=5000 avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f active_peak=%d visited_peak=%d transfers_peak=%d pressure_peak=%d damage_peak=%d phase_peak=%d breaches=%d leak_mass=%d world_family_mass=%d" % [
		result.avg, result.p95, result.p99, result.worst, result.pipe_active_peak, result.pipe_visited_peak,
		result.pipe_transfers_peak, result.pipe_pressure_peak, result.pipe_damage_peak, result.pipe_phase_peak,
		stats.breached_segments, stats.leak_mass_total, world.get_total_phase_family_mass(1),
	])
	_check(int(stats.breached_segments) > 0, "rupture storm breaches segments")
	_check(int(stats.leak_mass_total) > 0, "rupture storm emits world matter")
	_check_equal(mass_after, mass_before, "rupture storm mass exact")
	_check_equal(world.get_total_thermal_enthalpy(), energy_before, "rupture storm enthalpy exact")


func _measure(world: Variant, ticks: int) -> Dictionary:
	var wall: Array[float] = []
	var fluid_active := 0.0
	var fluid_active_peak := 0
	var fluid_visited := 0.0
	var fluid_transfers := 0.0
	var fluid_barrier := 0.0
	var worker_utilization := 0.0
	var pipe_active := 0.0
	var pipe_active_peak := 0
	var pipe_visited := 0.0
	var pipe_visited_peak := 0
	var pipe_transfers := 0.0
	var pipe_transfers_peak := 0
	var pipe_pressure := 0.0
	var pipe_pressure_peak := 0
	var pipe_damage := 0.0
	var pipe_damage_peak := 0
	var pipe_phase := 0.0
	var pipe_phase_peak := 0
	var pipe_gather := 0.0
	var pipe_state := 0.0
	var pipe_flow := 0.0
	var pipe_schedule := 0.0
	for tick in ticks:
		wall.append(_step_ms(world))
		var fluid: Dictionary = world.get_fluid_statistics()
		var pipe: Dictionary = world.get_pipe_statistics()
		var current_fluid_active := int(fluid.fluid_cells_active)
		var current_pipe_active := int(pipe.segments_active)
		var current_pipe_visited := int(pipe.segments_visited)
		var current_pipe_transfers := int(pipe.transfers)
		var current_pipe_pressure := int(pipe.pressure_edges)
		var current_pipe_damage := int(pipe.damage_checks)
		var current_pipe_phase := int(pipe.phase_checks)
		fluid_active += current_fluid_active
		fluid_active_peak = maxi(fluid_active_peak, current_fluid_active)
		fluid_visited += int(fluid.fluid_cells_visited)
		fluid_transfers += int(fluid.fluid_transfers)
		fluid_barrier += float(fluid.fluid_barrier_usec) / 1000.0
		worker_utilization += _worker_utilization(fluid)
		pipe_active += current_pipe_active
		pipe_active_peak = maxi(pipe_active_peak, current_pipe_active)
		pipe_visited += current_pipe_visited
		pipe_visited_peak = maxi(pipe_visited_peak, current_pipe_visited)
		pipe_transfers += current_pipe_transfers
		pipe_transfers_peak = maxi(pipe_transfers_peak, current_pipe_transfers)
		pipe_pressure += current_pipe_pressure
		pipe_pressure_peak = maxi(pipe_pressure_peak, current_pipe_pressure)
		pipe_damage += current_pipe_damage
		pipe_damage_peak = maxi(pipe_damage_peak, current_pipe_damage)
		pipe_phase += current_pipe_phase
		pipe_phase_peak = maxi(pipe_phase_peak, current_pipe_phase)
		pipe_gather += float(pipe.gather_usec) / 1000.0
		pipe_state += float(pipe.state_usec) / 1000.0
		pipe_flow += float(pipe.flow_usec) / 1000.0
		pipe_schedule += float(pipe.schedule_usec) / 1000.0
	wall.sort()
	var denominator := maxf(1.0, float(ticks))
	return {
		"avg": _avg(wall), "p95": _pct(wall, 0.95), "p99": _pct(wall, 0.99), "worst": wall[-1],
		"fluid_active_avg": fluid_active / denominator, "fluid_active_peak": fluid_active_peak,
		"fluid_visited_avg": fluid_visited / denominator, "fluid_transfers_avg": fluid_transfers / denominator,
		"fluid_barrier_avg": fluid_barrier / denominator, "worker_utilization": worker_utilization / denominator,
		"pipe_active_avg": pipe_active / denominator, "pipe_active_peak": pipe_active_peak,
		"pipe_visited_avg": pipe_visited / denominator, "pipe_visited_peak": pipe_visited_peak,
		"pipe_transfers_avg": pipe_transfers / denominator, "pipe_transfers_peak": pipe_transfers_peak,
		"pipe_pressure_avg": pipe_pressure / denominator, "pipe_pressure_peak": pipe_pressure_peak,
		"pipe_damage_avg": pipe_damage / denominator, "pipe_damage_peak": pipe_damage_peak,
		"pipe_phase_avg": pipe_phase / denominator, "pipe_phase_peak": pipe_phase_peak,
		"pipe_gather_avg": pipe_gather / denominator, "pipe_state_avg": pipe_state / denominator,
		"pipe_flow_avg": pipe_flow / denominator, "pipe_schedule_avg": pipe_schedule / denominator,
	}


func _worker_utilization(fluid: Dictionary) -> float:
	var values: Array = fluid.get("fluid_worker_usec", [])
	if values.is_empty():
		return 0.0
	var total := 0
	var peak := 0
	var workers_used := 0
	for value: Variant in values:
		var usec := int(value)
		if usec <= 0:
			continue
		total += usec
		peak = maxi(peak, usec)
		workers_used += 1
	return float(total) * 100.0 / maxf(1.0, float(peak * workers_used))


func _step_ms(world: Variant) -> float:
	var started := Time.get_ticks_usec()
	world.step()
	return float(Time.get_ticks_usec() - started) / 1000.0


func _avg(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(1.0, float(values.size()))


func _pct(values: Array[float], percentile: float) -> float:
	return values[clampi(ceili(float(values.size()) * percentile) - 1, 0, values.size() - 1)]


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("PHASE95 PERF: " + message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])
