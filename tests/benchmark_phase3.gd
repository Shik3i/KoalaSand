extends SceneTree

const SAND := 2

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("KoalaSand Phase 3 logistics performance matrix")
	print("godot=%s os=%s cpu=%s logical_cores=%d" % [
		Engine.get_version_info().get("string", "unknown"), OS.get_name(), OS.get_processor_name(), OS.get_processor_count()
	])
	_benchmark_idle_50k()
	_benchmark_moderate()
	_benchmark_active_50k()
	_benchmark_long_distance()
	print("PASS: Phase 3 logistics performance gates" if not _failed else "FAIL: Phase 3 logistics performance gates")
	quit(0 if not _failed else 1)


func _benchmark_idle_50k() -> void:
	var world: Variant = _factory_world(31001, 50, 1000, false, 0)
	var result: Dictionary = _measure("A_idle_50k", world, 120)
	_check(result["average_ms"] < 1.0, "50k idle belts exceed 1 ms/tick")
	_check(result["max_considered"] == 0, "idle belts considered material")


func _benchmark_moderate() -> void:
	var world: Variant = _factory_world(31002, 10, 1000, true, 2)
	var result: Dictionary = _measure("B_moderate_10k_belts_20k_material", world, 60)
	_check(result["average_ms"] < 16.67, "moderate factory exceeds 60 Hz")
	_check(result["moves"] > 0, "moderate factory moved no material")


func _benchmark_active_50k() -> void:
	var world: Variant = _factory_world(31003, 50, 1000, true, 1)
	var result: Dictionary = _measure("C_dense_50k_active", world, 30)
	_check(result["average_ms"] < 16.67, "dense 50k active stress exceeds 60 Hz")
	_check(result["max_considered"] > 20000, "dense fixture did not activate a large belt fraction")


func _benchmark_long_distance() -> void:
	var world := NativeSandWorld.new()
	world.reset(31004, 1)
	world.set_game_mode(1)
	world.place_conveyor_line(Vector2i(-1005, 40), Vector2i(1105, 40), 1)
	world.set_cell_with_provenance(Vector2i(-1000, 39), SAND, 54321)
	var started := Time.get_ticks_usec()
	for _tick in 4010:
		world.step()
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var final_x := -2147483648
	var count := 0
	for x in range(-1010, 1120):
		for y in range(30, 50):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) == SAND and world.get_provenance(cell) == 54321:
				final_x = x
				count += 1
	print("matrix scenario=E_long_distance distance_cells=%d ticks=4010 wall_ms=%.3f count=%d provenance=54321 hash=%s" % [
		final_x + 1000, elapsed_ms, count, world.logistics_state_hash()
	])
	_check(final_x >= 1000 and count == 1, "long-distance provenance transport failed")


func _factory_world(seed: int, lines: int, length: int, add_material: bool, material_rows: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	for line in lines:
		var belt_y := 20 + line * 4
		world.place_conveyor_line(Vector2i(0, belt_y), Vector2i(length - 1, belt_y), 1 if (line & 1) == 0 else -1)
		if add_material:
			for row in material_rows:
				world.fill_rect(Rect2i(1, belt_y - 1 - row, length - 2, 1), SAND)
	world.finalize_initialization()
	return world


func _measure(name: String, world: Variant, ticks: int) -> Dictionary:
	var total_usec := 0
	var worst_usec := 0
	var logistics_usec := 0
	var max_considered := 0
	var total_moves := 0
	var total_skipped := 0
	var total_blocked := 0
	for _tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		worst_usec = maxi(worst_usec, elapsed)
		var statistics: Dictionary = world.get_structure_statistics()
		logistics_usec += int(statistics["logistics_usec"])
		max_considered = maxi(max_considered, int(statistics["belts_considered"]))
		total_moves += int(statistics["belt_moves"])
		total_skipped += int(statistics["belts_skipped"])
		total_blocked += int(statistics["blocked_belt_attempts"])
	var average_ms := float(total_usec) / ticks / 1000.0
	var statistics: Dictionary = world.get_structure_statistics()
	print("matrix scenario=%s structures=%d structure_chunks=%d structure_mib=%.3f belts_total=%d belts_active=%d ticks=%d avg_sim_ms=%.3f worst_sim_ms=%.3f avg_logistics_ms=%.3f max_belts_considered=%d avg_belts_skipped=%d belt_moves=%d blocked_attempts=%d hash=%s" % [
		name, statistics["structures_allocated"], statistics["structure_bearing_chunks"],
		float(statistics["structure_backing_bytes"]) / 1048576.0, statistics["belts_total"], statistics["belts_active"],
		ticks, average_ms, float(worst_usec) / 1000.0, float(logistics_usec) / ticks / 1000.0,
		max_considered, total_skipped / ticks, total_moves, total_blocked, world.logistics_state_hash()
	])
	return {"average_ms": average_ms, "max_considered": max_considered, "moves": total_moves}


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PERFORMANCE INVARIANT: %s" % message)
