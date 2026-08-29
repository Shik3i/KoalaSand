extends SceneTree

const WORKERS_MAX := 8
const SAND := 2
const STONE := 1

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("KoalaSand Phase 1.5 native performance matrix")
	print("godot=%s os=%s cpu=%s logical_cores=%d workers=%d renderer=%s" % [
		Engine.get_version_info().get("string", "unknown"),
		OS.get_name(),
		OS.get_processor_name(),
		OS.get_processor_count(),
		_worker_count(),
		RenderingServer.get_current_rendering_method(),
	])
	_run_sparse_activity()
	_run_medium_falling_mass()
	_run_one_million_active()
	_run_four_million_persistent()
	print("PASS: Phase 1.5 performance matrix work invariants" if not _failed else "FAIL: Phase 1.5 performance matrix work invariants")
	quit(0 if not _failed else 1)


func _run_sparse_activity() -> void:
	var world: Variant = _new_world(7001)
	world.allocate_chunk_rect(Rect2i(0, 0, 16, 16))
	world.fill_rect(Rect2i(0, 110, 65, 1), STONE)
	world.fill_rect(Rect2i(20, 0, 25, 31), SAND)
	world.finalize_initialization()
	var result: Dictionary = _measure("A_sparse_activity", world, 60)
	_check(result["max_visited"] < world.total_allocated_cells() / 64, "sparse activity visited too much allocated space")


func _run_medium_falling_mass() -> void:
	var world: Variant = _new_world(7002)
	world.allocate_chunk_rect(Rect2i(0, 0, 8, 8))
	world.fill_rect(Rect2i(0, 300, 512, 1), STONE)
	for y in range(18, 59):
		world.fill_rect(Rect2i(16, y, 481, 1), SAND, 2)
	world.finalize_initialization()
	_measure("B_medium_falling_mass", world, 45)


func _run_one_million_active() -> void:
	var world: Variant = _new_world(7003)
	world.fill_rect(Rect2i(0, 0, 1024, 1024), SAND)
	world.fill_rect(Rect2i(0, 1024, 1024, 1), STONE)
	world.finalize_initialization()
	var result: Dictionary = _measure("C_one_million_active_pathological", world, 12, false)
	_check(result["max_visited"] >= 1000000, "1M stress did not visit approximately one million active cells")


func _run_four_million_persistent() -> void:
	var world: Variant = _new_world(7004)
	world.allocate_chunk_rect(Rect2i(0, 0, 32, 32))
	for origin in [Vector2i(96, 80), Vector2i(608, 336), Vector2i(1120, 720), Vector2i(1632, 1440)]:
		world.fill_rect(Rect2i(origin.x - 32, origin.y + 90, 96, 1), STONE)
		world.fill_rect(Rect2i(origin.x, origin.y, 32, 48), SAND)
	world.finalize_initialization()
	var result: Dictionary = _measure("D_four_million_persistent", world, 60, false)
	_check(result["max_visited"] < world.total_allocated_cells() / 16, "4M persistent world cost scales with allocation")


func _new_world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, _worker_count())
	return world


func _worker_count() -> int:
	return clampi(OS.get_processor_count() - 1, 1, WORKERS_MAX)


func _measure(name: String, world: Variant, ticks: int, include_render: bool = true) -> Dictionary:
	if include_render:
		world.consume_dirty_render_chunks()
	var total_usec := 0
	var worst_usec := 0
	var total_visited := 0
	var max_visited := 0
	var total_moved := 0
	for _tick in ticks:
		var start_usec := Time.get_ticks_usec()
		world.step()
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		total_usec += elapsed_usec
		worst_usec = maxi(worst_usec, elapsed_usec)
		var statistics: Dictionary = world.get_statistics()
		var visited: int = statistics["cells_visited"]
		total_visited += visited
		max_visited = maxi(max_visited, visited)
		total_moved += statistics["cells_moved"]
	var render_ms := -1.0
	if include_render:
		var render_start := Time.get_ticks_usec()
		world.consume_dirty_render_chunks()
		render_ms = float(Time.get_ticks_usec() - render_start) / 1000.0
	var final_statistics: Dictionary = world.get_statistics()
	var average_ms := float(total_usec) / float(ticks) / 1000.0
	print(
		"matrix scenario=%s allocated_cells=%d simulation_mib=%.2f presentation_mib=%.2f active_chunks=%d active_rectangles=%d active_region_cells=%d ticks=%d avg_ms_per_tick=%.3f worst_ms_per_tick=%.3f sim_hz=%.1f avg_cells_visited=%d max_cells_visited=%d cells_moved=%d cells_skipped=%d workers=%d worker_utilization_percent=%.1f render_extract_ms=%.3f dirty_render_pixels=%d upload_pixels=%d"
		% [
			name,
			world.total_allocated_cells(),
			float(world.simulation_backing_bytes()) / 1048576.0,
			float(world.presentation_backing_bytes()) / 1048576.0,
			final_statistics["active_chunks"],
			final_statistics["active_rectangles"],
			final_statistics["active_region_cells"],
			ticks,
			average_ms,
			float(worst_usec) / 1000.0,
			float(ticks) * 1000000.0 / float(total_usec),
			total_visited / ticks,
			max_visited,
			total_moved,
			final_statistics["cells_skipped"],
			final_statistics["worker_count"],
			final_statistics["worker_utilization_percent"],
			render_ms,
			final_statistics["dirty_render_pixels"],
			final_statistics["render_upload_pixels"],
		]
	)
	return {"average_ms": average_ms, "worst_usec": worst_usec, "max_visited": max_visited}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PERFORMANCE INVARIANT: %s" % message)
