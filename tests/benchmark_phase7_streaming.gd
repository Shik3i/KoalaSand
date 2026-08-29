extends SceneTree

const WATER := 3


func _init() -> void:
	var world := NativeSandWorld.new()
	world.configure_world({
		"seed": 70170, "width": 4096, "depth": 2048, "sky": 1024,
		"surface_baseline": 900, "surface_amplitude": 0, "water_frequency": 0.5,
	}, 2)
	world.set_game_mode(1)
	world.request_chunk(Vector2i(0, -15), 0)
	world.flush_generation()
	for y in range(-940, -936):
		for x in range(-2, 2): world.set_water_mass(Vector2i(x, y), 255)
	var mass_before: int = world.get_total_water_mass()
	var samples: Array[float] = []
	var peak_chunks := world.chunk_count()
	var border_crossings := 0
	for tick in 720:
		var started := Time.get_ticks_usec()
		world.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		border_crossings += int(world.get_fluid_statistics().fluid_border_crossings)
		world.flush_generation()
		if (tick & 15) == 15:
			var front_chunk_y := floori((-938.0 + float(tick)) / 64.0)
			world.evict_pristine_outside(Rect2i(-2, front_chunk_y - 2, 5, 5), 64)
		peak_chunks = maxi(peak_chunks, world.chunk_count())
	samples.sort()
	var mass_after: int = world.get_total_water_mass()
	var lowest_y := -10000
	for y in range(-940, -150):
		for x in range(-16, 17):
			if world.get_liquid_mass(Vector2i(x, y)) > 0: lowest_y = maxi(lowest_y, y)
	print("phase7_streaming ticks=720 vertical_chunks_crossed=%.1f border_crossings=%d peak_chunks=%d resident_chunks=%d mass_before=%d mass_after=%d sim_avg_ms=%.4f sim_p95_ms=%.4f sim_p99_ms=%.4f sim_worst_ms=%.4f lowest_y=%d" % [
		float(lowest_y + 940) / 64.0, border_crossings, peak_chunks, world.chunk_count(), mass_before, mass_after,
		_average(samples), _percentile(samples, 0.95), _percentile(samples, 0.99), samples[-1], lowest_y,
	])
	if mass_after != mass_before or lowest_y < -350 or border_crossings <= 0 or peak_chunks > 96:
		push_error("Phase 7 streaming Water gate failed")
		quit(1)
	else:
		print("PASS: Phase 7 long-distance streaming Water")
		quit(0)


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, float(values.size()))


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)]
