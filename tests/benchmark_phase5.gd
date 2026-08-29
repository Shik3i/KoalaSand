extends SceneTree

const GLASS := 10
const IRON := 11
const GOLD := 12
const RESIDUE := 13
const BANK := 8

var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_benchmark_idle_10k_banks()
	_benchmark_active_network()
	_benchmark_progression_pacing()
	print("PASS: Phase 5 Bank and progression performance gates" if not failed else "FAIL: Phase 5 performance gates")
	quit(0 if not failed else 1)


func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	return world


func _benchmark_idle_10k_banks() -> void:
	var world: Variant = _world(56001)
	var placed := 0
	for row in 100:
		for column in 100:
			placed += 1 if world.place_structure(BANK, Vector2i(column * 10, row * 8)) > 0 else 0
	for _tick in 3:
		world.step()
	var started := Time.get_ticks_usec()
	for _tick in 240:
		world.step()
	var elapsed := Time.get_ticks_usec() - started
	var stats: Dictionary = world.get_bank_statistics()
	print("phase5_bank_idle banks=%d active=%d visited=%d bank_ms=%.6f wall_tick_ms=%.6f" % [
		placed, stats.banks_active, stats.banks_visited, float(stats.bank_usec) / 1000.0, float(elapsed) / 240000.0,
	])
	_gate(placed == 10000, "10k idle Bank fixture incomplete")
	_gate(int(stats.banks_visited) == 0, "idle Bank scheduler visits entities")
	_gate(float(elapsed) / 240000.0 < 1.0, "10k idle Banks exceed 1 ms/tick")


func _benchmark_active_network() -> void:
	var world: Variant = _world(56002)
	var origins: Array[Vector2i] = []
	for row in 20:
		for column in 20:
			var origin := Vector2i(column * 12, row * 9)
			if world.place_structure(BANK, origin) > 0:
				origins.append(origin)
	var total_accepted := 0
	var total_rejected := 0
	var total_bank_usec := 0
	var peak_visited := 0
	var started := Time.get_ticks_usec()
	for tick in 180:
		for index in origins.size():
			var input := origins[index] + Vector2i(3, -1)
			if world.get_cell(input) == 0:
				var material: int = [GLASS, IRON, GOLD, RESIDUE][(index + tick) % 4]
				world.set_cell(input, material)
		world.step()
		var stats: Dictionary = world.get_bank_statistics()
		total_accepted += int(stats.accepted_cells)
		total_rejected += int(stats.rejected_cells)
		total_bank_usec += int(stats.bank_usec)
		peak_visited = maxi(peak_visited, int(stats.banks_visited))
		for origin in origins:
			var reject := origin + Vector2i(8, 4)
			if world.get_cell(reject) == RESIDUE:
				world.set_cell(reject, 0)
	var wall_usec := Time.get_ticks_usec() - started
	var final_stats: Dictionary = world.get_bank_statistics()
	print("phase5_bank_active banks=%d peak_visited=%d accepted=%d rejected=%d blocked=%d bank_avg_ms=%.3f wall_tick_ms=%.3f" % [
		origins.size(), peak_visited, total_accepted, total_rejected, final_stats.blocked_banks,
		float(total_bank_usec) / 180000.0, float(wall_usec) / 180000.0,
	])
	_gate(total_accepted > 10000, "active Banks accepted insufficient cells")
	_gate(total_rejected > 1000, "active Banks did not physically reject mixed stream")
	_gate(float(total_bank_usec) / 180000.0 < 8.0, "active Bank network exceeds 8 ms/tick")


func _benchmark_progression_pacing() -> void:
	var world: Variant = _world(56003)
	var profile: int = world.geology_profile_id_at(Vector2i(1200, 180))
	var pacing: Dictionary = world.evaluate_progression_pacing(profile, 200000)
	print("phase5_pacing profile=%d dry=%s ferrous_sieve=%s ferrous_primitive=%s belt=%s later=%s" % [
		profile, pacing.dry_separation_primitive, pacing.ferrous_via_sieve,
		pacing.ferrous_primitive_comparison, pacing.belt_drive_after_dry, pacing.concentrate_recovery_cumulative,
	])
	_gate(bool(pacing.dry_separation_primitive.reached), "Dry pacing unreachable")
	_gate(int(pacing.ferrous_via_sieve.raw_sand) < int(pacing.ferrous_primitive_comparison.raw_sand), "Sieve has no progression advantage")
	_gate(bool(pacing.concentrate_recovery_cumulative.reached), "later recovery path unreachable")


func _gate(condition: bool, label: String) -> void:
	if not condition:
		failed = true
		push_error("PHASE5 BENCHMARK: " + label)
