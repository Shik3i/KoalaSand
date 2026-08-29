extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_benchmark_seed_validation()
	_benchmark_full_seed_sample()
	_benchmark_chunk_generation()
	_benchmark_character_collision()
	_benchmark_fov_and_discovery()
	_benchmark_streaming_traversal()
	if failures.is_empty():
		print("PASS: Phase 11 performance gates (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: Phase 11 performance gates %d/%d" % [failures.size(), checks])
		quit(1)


func _benchmark_seed_validation() -> void:
	var world: Variant = _world(1, 8)
	var report: Dictionary = world.validate_world_seeds(1, 10000)
	print("phase11_seed_validation seeds=%d elapsed_ms=%.3f seeds_per_second=%.1f failures=%d corrections=%d worst_corrected_seed=%d" % [
		report.seed_count, report.elapsed_ms, report.seeds_per_second, report.validation_failures, report.corrections, report.worst_corrected_seed,
	])
	_check_equal(report.seed_count, 10000, "10k seeds evaluated")
	_check_equal(report.validation_failures, 0, "10k post-correction failures")
	_check(float(report.seeds_per_second) > 1000.0, "seed sweep >1000 seeds/s")


func _benchmark_full_seed_sample() -> void:
	var started := Time.get_ticks_usec()
	var hashes: Dictionary = {}
	var chunks := 0
	for seed in range(1, 101):
		var world: Variant = _world(seed, 4)
		var region := Rect2i(-2, -1, 5, 7)
		world.request_chunk_region(region, 1)
		world.flush_generation()
		chunks += world.chunk_count()
		hashes[world.get_region_content_hash(region)] = true
		_check(world.chunk_count() == region.get_area(), "full selected seed %d publishes" % seed)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase11_full_seeds seeds=100 chunks=%d elapsed_ms=%.3f distinct_hashes=%d" % [chunks, elapsed_ms, hashes.size()])
	_check(hashes.size() >= 95, "selected seeds have varied generated worlds")


func _benchmark_chunk_generation() -> void:
	var world: Variant = _world(8675309, 8)
	var region := Rect2i(-5, 0, 10, 10)
	var started := Time.get_ticks_usec()
	world.request_chunk_region(region, 1)
	world.flush_generation()
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var stats: Dictionary = world.get_generation_statistics()
	print("phase11_chunk_generation chunks=100 wall_ms=%.3f generation_avg_ms=%.4f generation_worst_ms=%.4f publish_last_ms=%.4f generated_cells=%d resident=%d" % [
		elapsed_ms, float(stats.generation_usec_average) / 1000.0, float(stats.generation_usec_worst) / 1000.0,
		float(stats.publish_usec_last_frame) / 1000.0, world.total_allocated_cells(), world.chunk_count(),
	])
	_check(world.chunk_count() == 100, "100 chunks generated")
	_check(float(stats.generation_usec_average) < 5.0 * 1000.0, "chunk generation bounded")


func _benchmark_character_collision() -> void:
	var world := NativeSandWorld.new()
	world.reset(7, 1)
	world.allocate_chunk_rect(Rect2i(-2, -2, 4, 4))
	for x in range(-100, 101):
		world.set_cell(Vector2i(x, 8), 1)
	var started := Time.get_ticks_usec()
	var blocked := 0
	for index in range(100000):
		var result: Dictionary = world.query_character_collision(Rect2i(Vector2i(index % 160 - 80, 3), Vector2i(3, 6)))
		blocked += int(bool(result.blocked))
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var per_query_ms := elapsed_ms / 100000.0
	print("phase11_character_collision queries=100000 total_ms=%.3f avg_ms=%.6f blocked=%d cells_per_query=18" % [elapsed_ms, per_query_ms, blocked])
	_check(per_query_ms < 0.2, "Character collision well below 0.2 ms/query")
	_check(blocked > 0, "collision workload exercises solids")


func _benchmark_fov_and_discovery() -> void:
	var open_world := NativeSandWorld.new()
	open_world.reset(9, 1)
	open_world.allocate_chunk_rect(Rect2i(-5, -5, 11, 11))
	var open_samples: Array[float] = []
	for index in range(40):
		var started := Time.get_ticks_usec()
		open_world.update_character_visibility(1, Vector2i(index * 3 - 60, 0), 72, 8)
		open_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var irregular := NativeSandWorld.new()
	irregular.reset(11, 1)
	irregular.allocate_chunk_rect(Rect2i(-5, -5, 11, 11))
	for y in range(-90, 91):
		for x in range(-90, 91):
			if x * x + y * y > 44 * 44 and x * x + y * y < 58 * 58 and ((x * 7 + y * 11) & 3) != 0:
				irregular.set_cell(Vector2i(x, y), 1)
	var shell_samples: Array[float] = []
	for index in range(20):
		var started := Time.get_ticks_usec()
		irregular.update_character_visibility(1, Vector2i(index % 5 - 2, index / 5 - 2), 72, 8)
		shell_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	open_samples.sort()
	shell_samples.sort()
	var open_avg := _average(open_samples)
	var open_p99 := _percentile(open_samples, 0.99)
	var shell_avg := _average(shell_samples)
	var shell_p99 := _percentile(shell_samples, 0.99)
	var stats: Dictionary = open_world.get_visibility_statistics(1)
	print("phase11_fov open_avg_ms=%.4f open_p99_ms=%.4f shell_avg_ms=%.4f shell_p99_ms=%.4f sampled=%d discovered_chunks=%d bytes=%d bytes_per_chunk=%d" % [
		open_avg, open_p99, shell_avg, shell_p99, stats.cells_sampled, stats.discovered_chunks, stats.total_bytes, stats.bytes_per_discovered_chunk,
	])
	_check(open_avg < 3.0, "open FOV average bounded")
	_check(shell_avg < 3.0, "solid-shell FOV average bounded")
	_check(open_p99 < 5.0 and shell_p99 < 5.0, "FOV no hitch")
	_check(int(stats.bytes_per_discovered_chunk) <= 5200, "discovery memory <=5200 bytes/chunk")
	# Historical discovery does not change local update complexity.
	var historical_before := _average(open_samples)
	for x in range(-1200, 1201, 48):
		open_world.update_character_visibility(1, Vector2i(x, 0), 48, 6)
	var scaled: Array[float] = []
	for index in range(20):
		var started := Time.get_ticks_usec()
		open_world.update_character_visibility(1, Vector2i(index - 10, 0), 72, 8)
		scaled.append(float(Time.get_ticks_usec() - started) / 1000.0)
	print("phase11_discovery_scaling historical_chunks=%d local_before_ms=%.4f local_after_ms=%.4f" % [open_world.get_visibility_statistics(1).discovered_chunks, historical_before, _average(scaled)])
	_check(_average(scaled) < historical_before * 3.0 + 0.3, "FOV scales with local live region")


func _benchmark_streaming_traversal() -> void:
	var world: Variant = _world(64848, 8)
	var started := Time.get_ticks_usec()
	var generated := 0
	var publish_ms := 0.0
	var resident_peak := 0
	for x in range(-5000, 5001, 192):
		var center := Vector2i(floori(x / 64.0), 8)
		var interest := InterestRegion.new(1, 0, Rect2i(center - Vector2i(3, 3), Vector2i(7, 7)), InterestRegion.Purpose.CHARACTER, 64)
		generated += interest.request(world)
		world.flush_generation()
		publish_ms += float(world.get_generation_statistics().publish_usec_last_frame) / 1000.0
		world.evict_pristine_outside(Rect2i(center - Vector2i(6, 5), Vector2i(13, 11)), 64)
		resident_peak = maxi(resident_peak, world.chunk_count())
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var stats: Dictionary = world.get_generation_statistics()
	print("phase11_character_traversal distance_cells=10000 requests=%d wall_ms=%.3f generation_queue_peak=%d publish_ms_total=%.3f resident_peak=%d resident_final=%d generated_total=%d evicted_total=%d backing_mib=%.3f" % [
		generated, elapsed_ms, stats.queue_peak, publish_ms, resident_peak, world.chunk_count(), stats.generated_total, stats.evicted_total,
		float(world.simulation_backing_bytes() + world.presentation_backing_bytes()) / 1048576.0,
	])
	_check(generated > 0, "10k-cell traversal generated unseen terrain")
	_check(resident_peak < 220, "Character traversal resident chunks bounded")
	_check(int(stats.queued) == 0 and int(stats.in_flight) == 0, "generation queue drained")


func _world(seed: int, workers: int) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed, "generation_version": 2}, workers)
	return world


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(1, values.size())


func _percentile(values: Array[float], percentile: float) -> float:
	return values[clampi(roundi((values.size() - 1) * percentile), 0, values.size() - 1)]


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [label, expected, actual])
