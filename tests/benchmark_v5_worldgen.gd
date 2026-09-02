extends SceneTree

# V4 vs V5 generation benchmark on the same traversal fixture, plus per-chunk latency
# percentiles and a wide statistical sample.

func _init() -> void:
	var v4: Dictionary = _traversal(4)
	var v5: Dictionary = _traversal(5)
	print("v5_before_after v4_avg_ms=%.4f v5_avg_ms=%.4f change=%+.2f%% v4_worst_ms=%.4f v5_worst_ms=%.4f v4_wall_ms=%.3f v5_wall_ms=%.3f v4_first_tick_ms=%.4f v5_first_tick_ms=%.4f v4_active=%d v5_active=%d" % [
		float(v4.avg), float(v5.avg), (float(v5.avg) / float(v4.avg) - 1.0) * 100.0,
		float(v4.worst), float(v5.worst), float(v4.wall), float(v5.wall),
		float(v4.tick), float(v5.tick), int(v4.active), int(v5.active)])

	var latency := _latency(5, 900)
	print("v5_latency chunks=%d mean_ms=%.4f p50_ms=%.4f p90_ms=%.4f p95_ms=%.4f p99_ms=%.4f max_ms=%.4f" % [
		int(latency.count), float(latency.mean), float(latency.p50), float(latency.p90),
		float(latency.p95), float(latency.p99), float(latency.max)])
	var latency_v4 := _latency(4, 900)
	print("v4_latency chunks=%d mean_ms=%.4f p50_ms=%.4f p90_ms=%.4f p95_ms=%.4f p99_ms=%.4f max_ms=%.4f" % [
		int(latency_v4.count), float(latency_v4.mean), float(latency_v4.p50), float(latency_v4.p90),
		float(latency_v4.p95), float(latency_v4.p99), float(latency_v4.max)])

	_seed_sample(100)
	_statistics(1000)

	if int(v5.active) == 0 and float(latency.p99) < 12.0 and float(latency.mean) < 6.0:
		print("PASS: V5 worldgen benchmark"); quit(0); return
	push_error("V5_BENCHMARK: stability or latency budget failed"); quit(1)

func _traversal(version: int) -> Dictionary:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 8675309, "generation_version": version}, 8)
	var started := Time.get_ticks_usec()
	var requests := 0
	var resident_peak := 0
	for chunk_x in range(-30, 31, 5):
		requests += int(world.request_chunk_region(Rect2i(chunk_x - 4, -1, 9, 13), 1))
		world.flush_generation()
		world.evict_pristine_outside(Rect2i(chunk_x - 7, -2, 15, 16), 256)
		resident_peak = maxi(resident_peak, int(world.chunk_count()))
	var wall := (Time.get_ticks_usec() - started) / 1000.0
	var inspect := Rect2i(26, -1, 9, 13)
	world.request_chunk_region(inspect, 0); world.flush_generation()
	var stability: Dictionary = world.get_generation_stability_report(inspect)
	started = Time.get_ticks_usec(); world.step()
	var tick := (Time.get_ticks_usec() - started) / 1000.0
	var generation: Dictionary = world.get_generation_statistics()
	print("v5_traversal version=%d requests=%d wall_ms=%.3f resident_peak=%d resident_final=%d avg_ms=%.4f worst_ms=%.4f first_tick_ms=%.4f active=%d" % [
		version, requests, wall, resident_peak, int(world.chunk_count()),
		float(generation.generation_usec_average) / 1000.0, float(generation.generation_usec_worst) / 1000.0,
		tick, int(stability.initially_active_dynamic_cells)])
	return {"wall": wall, "avg": float(generation.generation_usec_average) / 1000.0,
		"worst": float(generation.generation_usec_worst) / 1000.0, "tick": tick,
		"active": int(stability.initially_active_dynamic_cells)}

func _latency(version: int, budget: int) -> Dictionary:
	# Per-chunk wall time, measured one chunk at a time so the sample is real latency rather
	# than a throughput average smeared across the worker pool.
	var samples: Array[float] = []
	for seed_index in 6:
		var world := NativeSandWorld.new()
		world.configure_world({"seed": 4000 + seed_index * 7919, "generation_version": version}, 1)
		for chunk_y in range(-1, 14):
			for chunk_x in range(-5, 6):
				if samples.size() >= budget: break
				var started := Time.get_ticks_usec()
				world.request_chunk(Vector2i(chunk_x, chunk_y), 1)
				world.flush_generation()
				samples.append((Time.get_ticks_usec() - started) / 1000.0)
	return _dist(samples)

func _seed_sample(count: int) -> void:
	var sand: Array[float] = []; var water: Array[float] = []; var coal: Array[float] = []
	var generation: Array[float] = []; var void_shallow: Array[float] = []; var void_deep: Array[float] = []
	var unstable := 0; var dry := 0; var empty_sand := 0; var over_budget := 0
	var area := Rect2i(-3, -1, 7, 20)
	for index in count:
		var world := NativeSandWorld.new()
		world.configure_world({"seed": 1000 + index * 7919, "generation_version": 5}, 6)
		world.request_chunk_region(area, 1); world.flush_generation()
		var stable: Dictionary = world.get_generation_stability_report(area)
		var quality: Dictionary = world.get_worldgen_quality_report(area)
		if int(stable.initially_active_dynamic_cells) > 0:
			unstable += 1
			print("v5_unstable seed=%d sand=%d water=%d sand_sample=%s water_sample=%s" % [
				1000 + index * 7919, int(stable.unsupported_sand_cells), int(stable.initially_active_water_cells),
				str(stable.unsupported_sand_sample_xy), str(stable.active_water_sample_xy)])
		var limits: Array = stable.void_fraction_limits
		var fractions: Array = stable.void_fraction_by_depth_band
		for band in 3:
			if float(fractions[band]) > float(limits[band]) + 0.0001: over_budget += 1
		dry += 1 if int(quality.content.water_cells) == 0 else 0
		empty_sand += 1 if int(quality.content.sand_cells) == 0 else 0
		sand.append(float(quality.content.sand_cells)); water.append(float(quality.content.water_cells))
		coal.append(float(quality.content.ore_cells))
		void_shallow.append(float(fractions[0])); void_deep.append(float(fractions[2]))
		generation.append(float(world.get_generation_statistics().generation_usec_average) / 1000.0)
	print("v5_seed_sample seeds=%d unstable=%d dry=%d empty_sand=%d over_budget=%d sand=%s water=%s coal=%s void_shallow=%s void_deep=%s generation_ms=%s" % [
		count, unstable, dry, empty_sand, over_budget, str(_dist(sand)), str(_dist(water)),
		str(_dist(coal)), str(_dist(void_shallow)), str(_dist(void_deep)), str(_dist(generation))])

	# Cave topology over a smaller sample: full connected-component analysis is expensive.
	var components: Array[float] = []; var largest: Array[float] = []; var isolated: Array[float] = []
	var widths: Array[float] = []; var flooded: Array[float] = []; var median_size: Array[float] = []
	var surface_linked: Array[float] = []
	var topology_area := Rect2i(-5, -1, 10, 12)
	for index in 24:
		var world := NativeSandWorld.new()
		world.configure_world({"seed": 500 + index * 4441, "generation_version": 5}, 6)
		world.request_chunk_region(topology_area, 1); world.flush_generation()
		var report: Dictionary = world.get_cave_topology_report(topology_area)
		components.append(float(report.components)); largest.append(float(report.largest_component_fraction))
		isolated.append(float(report.isolated_small_components)); widths.append(float(report.passage_width.p50))
		flooded.append(float(report.flooded_fraction)); median_size.append(float(report.component_size.p50))
		surface_linked.append(float(report.surface_connected_components))
	print("v5_topology_sample seeds=24 components=%s largest_fraction=%s isolated=%s passage_width_p50=%s component_size_p50=%s flooded_fraction=%s surface_connected=%s" % [
		str(_dist(components)), str(_dist(largest)), str(_dist(isolated)), str(_dist(widths)),
		str(_dist(median_size)), str(_dist(flooded)), str(_dist(surface_linked))])

func _statistics(count: int) -> void:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 1, "generation_version": 5}, 1)
	var stats: Dictionary = world.get_worldgen_v5_statistics(1, count)
	print("v5_statistics seeds=%d elapsed_ms=%.1f without_water=%d without_sand=%d without_caves=%d" % [
		int(stats.seed_count), float(stats.elapsed_ms), int(stats.seeds_without_water),
		int(stats.seeds_without_sand), int(stats.seeds_without_caves)])
	print("v5_biome_coverage %s" % JSON.stringify(stats.biome_coverage_percentage))
	print("v5_province_coverage %s" % JSON.stringify(stats.province_coverage_percentage))
	var metrics: Dictionary = stats.metrics
	for key: String in metrics.keys():
		print("v5_metric %-30s %s" % [key, JSON.stringify(metrics[key])])

func _dist(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total := 0.0
	for value in values: total += value
	var pick := func(p: float) -> float: return values[clampi(int(round((values.size() - 1) * p)), 0, values.size() - 1)]
	return {"count": values.size(), "mean": total / values.size(), "p50": pick.call(0.50),
		"p90": pick.call(0.90), "p95": pick.call(0.95), "p99": pick.call(0.99),
		"min": values[0], "max": values[-1]}
