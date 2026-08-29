extends SceneTree

const STEAM := 17

var checks := 0
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int = 10100) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 8)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_shaft_100k_stable()
	_shaft_10k_active_networks()
	_power_100k_stable()
	_power_10k_active_networks()
	_turbine_generator_fleet(300)
	print("PASS: Phase 10 performance gates (%d checks)" % checks if not failed else "FAIL: Phase 10 performance gates")
	quit(0 if not failed else 1)


func _shaft_100k_stable() -> void:
	var world: Variant = _world(10101)
	var started := Time.get_ticks_usec()
	world.configure_power_benchmark(0, 100000)
	var topology_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var result := _measure(world, 60)
	var stats: Dictionary = world.get_mechanical_statistics()
	print("phase10_mechanical scenario=stable_100k segments=%d networks=%d topology_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f mechanical_latest_ms=%.4f active=%d bytes_per_segment=%d bytes_per_network=%d hash=%s" % [
		stats.segments, stats.networks, topology_ms, result.avg, result.p95, result.p99, result.worst,
		float(stats.mechanical_usec) / 1000.0, stats.active_networks, stats.shaft_segment_bytes, stats.network_record_bytes, world.power_state_hash(),
	])
	_check_equal(stats.segments, 100000, "100k stable shafts")
	_check_equal(stats.networks, 1, "100k stable shaft component cache")
	_check(result.p99 <= 16.67, "100k stable shafts p99 <= 16.67 ms")


func _shaft_10k_active_networks() -> void:
	var world: Variant = _world(10102)
	var started := Time.get_ticks_usec()
	world.configure_power_benchmark(1, 10000)
	var topology_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var result := _measure(world, 60)
	var stats: Dictionary = world.get_mechanical_statistics()
	print("phase10_mechanical scenario=active_10k_networks segments=%d networks=%d topology_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f mechanical_latest_ms=%.4f active=%d" % [
		stats.segments, stats.networks, topology_ms, result.avg, result.p95, result.p99, result.worst, float(stats.mechanical_usec) / 1000.0, stats.active_networks,
	])
	_check_equal(stats.networks, 10000, "10k active mechanical networks")
	_check(result.p99 <= 16.67, "10k active mechanical networks p99 <= 16.67 ms")


func _power_100k_stable() -> void:
	var world: Variant = _world(10103)
	var started := Time.get_ticks_usec()
	world.configure_power_benchmark(2, 100000)
	var topology_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var result := _measure(world, 60)
	var stats: Dictionary = world.get_power_statistics()
	print("phase10_electrical scenario=stable_100k poles=%d edges=%d consumers=%d networks=%d topology_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f power_latest_ms=%.4f bytes_per_pole=%d bytes_per_edge=%d bytes_per_consumer=%d bytes_per_network=%d hash=%s" % [
		stats.poles, stats.edges, stats.consumers, stats.networks, topology_ms, result.avg, result.p95, result.p99, result.worst,
		float(stats.power_usec) / 1000.0, stats.pole_record_bytes, stats.edge_record_bytes, stats.consumer_record_bytes, stats.network_record_bytes, world.power_state_hash(),
	])
	_check_equal(stats.poles, 100000, "100k Power Poles")
	_check_equal(stats.consumers, 100000, "100k cached Power consumers")
	_check(result.p99 <= 16.67, "100k stable Power nodes p99 <= 16.67 ms")


func _power_10k_active_networks() -> void:
	var world: Variant = _world(10104)
	var started := Time.get_ticks_usec()
	world.configure_power_benchmark(4, 10000)
	var topology_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var result := _measure(world, 60)
	var stats: Dictionary = world.get_power_statistics()
	print("phase10_electrical scenario=active_10k_networks poles=%d consumers=%d networks=%d topology_ms=%.4f avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f power_latest_ms=%.4f active=%d" % [
		stats.poles, stats.consumers, stats.networks, topology_ms, result.avg, result.p95, result.p99, result.worst, float(stats.power_usec) / 1000.0, stats.active_networks,
	])
	_check_equal(stats.networks, 10000, "10k active electrical networks")
	_check(result.p99 <= 16.67, "10k active electrical networks p99 <= 16.67 ms")


func _turbine_generator_fleet(count: int) -> void:
	var world: Variant = _world(10105)
	world.fill_rect(Rect2i(-4, -4, count * 40 + 40, 16), 0)
	for index in count:
		var origin := Vector2i(index * 40, 0)
		world.place_structure(27, origin, 0)
		world.place_pipe_line(origin + Vector2i(-1, 1), origin + Vector2i(-1, 1))
		world.set_pipe_fluid(origin + Vector2i(-1, 1), STEAM, 30000, 2200)
		world.place_pipe_line(origin + Vector2i(6, 1), origin + Vector2i(6, 1))
		world.place_mechanical_shaft_line(origin + Vector2i(6, 2), origin + Vector2i(13, 2))
		world.place_structure(28, origin + Vector2i(14, 0), 0)
		world.place_structure(29, origin + Vector2i(20, 2), 0)
		world.place_structure(34, origin + Vector2i(29, 0), 0)
	world.finalize_initialization()
	var result := _measure(world, 20)
	var mechanical: Dictionary = world.get_mechanical_statistics()
	var power: Dictionary = world.get_power_statistics()
	var energy: Dictionary = world.get_energy_accounting()
	print("phase10_fleet turbines=%d generators=%d shaft_networks=%d power_networks=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f mechanical_latest_ms=%.4f power_latest_ms=%.4f mechanical_produced=%d electrical_produced=%d" % [
		count, power.generators, mechanical.networks, power.networks, result.avg, result.p95, result.p99, result.worst,
		float(mechanical.mechanical_usec) / 1000.0, float(power.power_usec) / 1000.0, energy.mechanical_produced, energy.electrical_produced,
	])
	_check_equal(power.generators, count, "300 Generator fleet")
	_check_equal(mechanical.networks, count, "300 isolated shaft networks")
	_check(int(energy.mechanical_produced) > 0, "fleet Turbines produce mechanical energy")
	_check(int(energy.electrical_produced) > 0, "fleet Generators produce electrical energy")
	_check(result.p99 <= 16.67, "300 Turbine/Generator fleet p99 <= 16.67 ms")


func _measure(world: Variant, ticks: int) -> Dictionary:
	var samples: Array[float] = []
	for tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	return {
		"avg": total / maxf(1.0, float(samples.size())),
		"p95": samples[clampi(ceili(samples.size() * 0.95) - 1, 0, samples.size() - 1)],
		"p99": samples[clampi(ceili(samples.size() * 0.99) - 1, 0, samples.size() - 1)],
		"worst": samples[-1],
	}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failed = true
	push_error("PERFORMANCE GATE FAILED: %s" % label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected: return
	failed = true
	push_error("PERFORMANCE GATE FAILED: %s expected=%s actual=%s" % [label, expected, actual])
