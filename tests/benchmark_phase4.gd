extends SceneTree

const RAW := 2
const HEAVY := 7
const COAL_CHUNK := 14
const FURNACE := 5
const SIEVE := 6
const MAGNETIC := 7


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_benchmark_idle_10k()
	_benchmark_representative()
	_benchmark_stress_1500()
	_benchmark_recovery()
	quit(0)


func _new_world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world


func _benchmark_idle_10k() -> void:
	var world: Variant = _new_world(45001)
	var placed := 0
	for row in 100:
		for column in 100:
			placed += 1 if world.place_structure(SIEVE, Vector2i(column * 10, row * 8), 0) > 0 else 0
	for _warmup in 12:
		world.step()
	var started := Time.get_ticks_usec()
	for _tick in 240:
		world.step()
	var elapsed := Time.get_ticks_usec() - started
	var stats: Dictionary = world.get_processing_statistics()
	print("phase4_idle machines=%d active=%d sleeping=%d visited_per_tick=%d scheduler_avg_ms=%.6f wall_tick_avg_ms=%.6f port_watch_cells=%d" % [
		placed, stats.machines_active, stats.machines_sleeping, stats.machines_visited,
		float(stats.machine_processing_usec) / 1000.0, float(elapsed) / 240000.0, stats.port_watch_cells,
	])


func _benchmark_representative() -> void:
	var world: Variant = _new_world(45002)
	for row in 100:
		var y := 1100 + row * 3
		world.place_conveyor_line(Vector2i(0, y), Vector2i(99, y), 1)
		for x in range(0, 100, 2):
			world.set_cell_with_metadata(Vector2i(x, y - 1), RAW, 2386, (row * 997 + x * 313) & 0xffff)
	var machines := 0
	for index in 300:
		var type_id: int = [SIEVE, MAGNETIC, FURNACE][index % 3]
		var origin := Vector2i((index % 25) * 14, (index / 25) * 11)
		if world.place_structure(type_id, origin, 0) <= 0:
			continue
		machines += 1
		if type_id == SIEVE:
			world.place_structure(2, origin + Vector2i(-1, 6))
			world.place_structure(2, origin + Vector2i(7, 6))
			world.set_cell(origin + Vector2i(-1, 4), 1)
			world.set_cell(origin + Vector2i(7, 4), 1)
		elif type_id == MAGNETIC:
			world.place_structure(2, origin + Vector2i(-1, 6))
			world.place_structure(2, origin + Vector2i(8, 6))
			world.set_cell(origin + Vector2i(-1, 4), 1)
			world.set_cell(origin + Vector2i(8, 4), 1)
		else:
			world.place_conveyor_line(origin + Vector2i(-2, 4), origin + Vector2i(-1, 4), 1)
			world.place_structure(2, origin + Vector2i(9, 4))
			world.place_structure(2, origin + Vector2i(-1, 6))
			world.set_cell(origin + Vector2i(9, 3), 1)
			world.set_cell(origin + Vector2i(-1, 5), 1)
	world.step()
	for index in 300:
		var type_id: int = [SIEVE, MAGNETIC, FURNACE][index % 3]
		var origin := Vector2i((index % 25) * 14, (index / 25) * 11)
		var profile := 2386
		var input_material: int = HEAVY if type_id == MAGNETIC else RAW
		var input_x := 4 if type_id != SIEVE else 3
		for offset in range(1, 9):
			world.set_cell_with_metadata(origin + Vector2i(input_x, -offset), input_material, profile, (index * 251 + offset * 7919) & 0xffff)
		if type_id == FURNACE:
			world.set_cell(origin + Vector2i(-1, 3), COAL_CHUNK)
	var total_machine_usec := 0
	var worst_machine_usec := 0
	var total_tick_usec := 0
	var worst_tick_usec := 0
	var visited_total := 0
	for _tick in 120:
		var started := Time.get_ticks_usec()
		world.step()
		var tick_usec := Time.get_ticks_usec() - started
		var processing: Dictionary = world.get_processing_statistics()
		total_tick_usec += tick_usec
		worst_tick_usec = maxi(worst_tick_usec, tick_usec)
		total_machine_usec += int(processing.machine_processing_usec)
		worst_machine_usec = maxi(worst_machine_usec, int(processing.machine_processing_usec))
		visited_total += int(processing.machines_visited)
	var final: Dictionary = world.get_processing_statistics()
	var logistics: Dictionary = world.get_structure_statistics()
	print("phase4_representative belts=%d machines=%d active=%d visited_avg=%.1f tick_avg_ms=%.3f tick_worst_ms=%.3f machine_avg_ms=%.3f machine_worst_ms=%.3f logistics_last_ms=%.3f processed_sieve=%d processed_magnetic=%d processed_furnace=%d outputs=%d blocked=%d" % [
		logistics.belts_total, machines, final.machines_active, float(visited_total) / 120.0,
		float(total_tick_usec) / 120000.0, float(worst_tick_usec) / 1000.0,
		float(total_machine_usec) / 120000.0, float(worst_machine_usec) / 1000.0,
		float(logistics.logistics_usec) / 1000.0, final.sieve_processed_total, final.magnetic_processed_total,
		final.furnace_processed_total, final.outputs_emitted, final.blocked_machines,
	])


func _benchmark_stress_1500() -> void:
	var world: Variant = _new_world(45003)
	var placed := 0
	for index in 1500:
		var origin := Vector2i((index % 50) * 11, (index / 50) * 9)
		if world.place_structure(SIEVE, origin, 0) <= 0:
			continue
		placed += 1
		world.set_cell(origin + Vector2i(-1, 4), 1)
		world.set_cell(origin + Vector2i(7, 4), 1)
	world.step()
	for index in 1500:
		var origin := Vector2i((index % 50) * 11, (index / 50) * 9)
		world.set_cell_with_metadata(origin + Vector2i(3, -1), RAW, 2386, (index * 3571) & 0xffff)
	var total_usec := 0
	var worst_usec := 0
	var visited_peak := 0
	for _tick in 12:
		var started := Time.get_ticks_usec()
		world.step()
		var elapsed := Time.get_ticks_usec() - started
		total_usec += elapsed
		worst_usec = maxi(worst_usec, elapsed)
		visited_peak = maxi(visited_peak, int(world.get_processing_statistics().machines_visited))
	var stats: Dictionary = world.get_processing_statistics()
	print("phase4_stress machines=%d active=%d visited_peak=%d tick_avg_ms=%.3f tick_worst_ms=%.3f machine_last_ms=%.3f blocked=%d production_path=true" % [
		placed, stats.machines_active, visited_peak, float(total_usec) / 12000.0, float(worst_usec) / 1000.0,
		float(stats.machine_processing_usec) / 1000.0, stats.blocked_machines,
	])


func _benchmark_recovery() -> void:
	var world: Variant = _new_world(45004)
	for cell in [Vector2i(1200, 180), Vector2i(-2200, 600), Vector2i(3400, 900)]:
		var profile: int = world.geology_profile_id_at(cell)
		var routes: Dictionary = world.evaluate_processing_routes(profile, 100000)
		print("phase4_route_sample source=%s profile=%d route_a=%s route_b=%s route_c=%s" % [cell, profile, routes.route_a, routes.route_b, routes.route_c])
