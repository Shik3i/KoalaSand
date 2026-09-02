extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	var before := _benchmark_version(2)
	var after := _benchmark_version(3)
	print("p0_worldgen_comparison v2_active_dynamic=%d v3_active_dynamic=%d v2_active_sand_chunks=%d v3_active_sand_chunks=%d v2_active_fluid_chunks=%d v3_active_fluid_chunks=%d v2_generation_avg_ms=%.4f v3_generation_avg_ms=%.4f v2_generation_worst_ms=%.4f v3_generation_worst_ms=%.4f v2_first_step_ms=%.4f v3_first_step_ms=%.4f v2_first_step_moves=%d v3_first_step_moves=%d v2_settle_ticks=%d v3_settle_ticks=%d" % [
		before.active_dynamic, after.active_dynamic, before.active_sand_chunks, after.active_sand_chunks,
		before.active_fluid_chunks, after.active_fluid_chunks, before.generation_avg_ms, after.generation_avg_ms,
		before.generation_worst_ms, after.generation_worst_ms, before.first_step_ms, after.first_step_ms,
		before.first_step_moves, after.first_step_moves, before.settle_ticks, after.settle_ticks,
	])
	_check(int(after.active_dynamic) == 0, "V3 streaming starts with zero active dynamic cells")
	_check(int(after.active_sand_chunks) == 0 and int(after.active_fluid_chunks) == 0, "V3 streaming publishes sleeping dynamic material")
	_check(int(after.first_step_moves) == 0, "V3 untouched terrain does not move on first simulation tick")
	_check(int(after.settle_ticks) == 0, "V3 untouched terrain needs no settle ticks")
	_check(float(after.generation_avg_ms) < 12.0, "V3 average generation remains bounded")
	if failures.is_empty():
		print("PASS: P0 recovery worldgen/activity benchmark (%d checks)" % checks); quit(0)
	else:
		for failure: String in failures: push_error("P0_BENCHMARK: " + failure)
		print("FAIL: %d of %d P0 benchmark checks" % [failures.size(), checks]); quit(1)


func _benchmark_version(version: int) -> Dictionary:
	var world := NativeSandWorld.new(); world.configure_world({"seed":8675309, "generation_version":version}, 8)
	var generated_requests := 0
	var resident_peak := 0
	var start := Time.get_ticks_usec()
	for chunk_x in range(-30, 31, 5):
		var region := Rect2i(chunk_x - 4, -1, 9, 13)
		generated_requests += world.request_chunk_region(region, 1)
		world.flush_generation()
		world.evict_pristine_outside(Rect2i(chunk_x - 7, -2, 15, 16), 256)
		resident_peak = maxi(resident_peak, world.chunk_count())
	var wall_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var inspect_area := Rect2i(26, -1, 9, 13)
	world.request_chunk_region(inspect_area, 0); world.flush_generation()
	var stability: Dictionary = world.get_generation_stability_report(inspect_area)
	var step_start := Time.get_ticks_usec(); world.step(); var first_step_ms := float(Time.get_ticks_usec() - step_start) / 1000.0
	var first_stats: Dictionary = world.get_statistics()
	var settle_ticks := 0
	while settle_ticks < 60 and (world.active_chunk_count() > 0 or int(world.get_generation_stability_report(inspect_area).active_fluid_chunks) > 0):
		world.step(); settle_ticks += 1
	var generation: Dictionary = world.get_generation_statistics()
	print("p0_worldgen version=%d traversal_requests=%d wall_ms=%.3f resident_peak=%d resident_final=%d backing_mib=%.3f active_dynamic=%d active_sand_chunks=%d active_fluid_chunks=%d void_fraction=%s max_chunk_void_fraction=%s roof_min=%d generation_avg_ms=%.4f generation_worst_ms=%.4f first_step_ms=%.4f first_step_moves=%d settle_ticks=%d" % [
		version, generated_requests, wall_ms, resident_peak, world.chunk_count(),
		float(world.simulation_backing_bytes() + world.presentation_backing_bytes()) / 1048576.0,
		stability.initially_active_dynamic_cells, stability.active_sand_chunks, stability.active_fluid_chunks,
		str(stability.void_fraction_by_depth_band), str(stability.maximum_chunk_void_fraction_by_depth_band),
		stability.minimum_surface_roof_cells, float(generation.generation_usec_average) / 1000.0,
		float(generation.generation_usec_worst) / 1000.0, first_step_ms, first_stats.cells_moved, settle_ticks,
	])
	return {
		"active_dynamic":stability.initially_active_dynamic_cells,
		"active_sand_chunks":stability.active_sand_chunks,
		"active_fluid_chunks":stability.active_fluid_chunks,
		"generation_avg_ms":float(generation.generation_usec_average) / 1000.0,
		"generation_worst_ms":float(generation.generation_usec_worst) / 1000.0,
		"first_step_ms":first_step_ms,
		"first_step_moves":first_stats.cells_moved,
		"settle_ticks":settle_ticks,
	}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
