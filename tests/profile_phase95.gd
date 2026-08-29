extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int, workers: int = 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_profile_steam()
	_profile_steam_pipes()
	quit(0)


func _profile_steam() -> void:
	var world: Variant = _world(95101)
	world.fill_pattern_state(Rect2i(0, 0, 1024, 1024), 17, 64, 192, 1700, 1700)
	var samples: Array[Dictionary] = []
	var worker_jobs := PackedInt64Array(); worker_jobs.resize(8)
	var worker_cells := PackedInt64Array(); worker_cells.resize(8)
	var worker_usec := PackedInt64Array(); worker_usec.resize(8)
	for tick in 32:
		var started := Time.get_ticks_usec()
		world.step()
		var wall := Time.get_ticks_usec() - started
		var fluid: Dictionary = world.get_fluid_statistics()
		var gas: Dictionary = world.get_gas_statistics()
		var thermal: Dictionary = world.get_thermal_statistics()
		samples.append({
			"tick": tick, "wall": wall, "fluid": int(fluid.fluid_usec),
			"schedule": int(fluid.fluid_schedule_usec), "traversal": int(fluid.fluid_traversal_usec),
			"barrier": int(fluid.fluid_barrier_usec), "commit": int(fluid.fluid_commit_usec),
			"settle": int(fluid.fluid_settle_usec), "thermal": int(thermal.thermal_usec),
			"active": int(gas.active_cells), "visited": int(gas.visited_cells),
			"transfers": int(gas.transfers), "cross": int(gas.cross_chunk_transfers),
			"vertical": int(gas.vertical_attempts), "diagonal": int(gas.diagonal_attempts),
			"lateral": int(gas.lateral_attempts), "phase": int(thermal.phase_changes),
		})
		for worker in 8:
			worker_jobs[worker] += int(fluid.fluid_worker_jobs[worker])
			worker_cells[worker] += int(fluid.fluid_worker_cells[worker])
			worker_usec[worker] += int(fluid.fluid_worker_usec[worker])
	_print_profile("steam_1m", samples)
	print("phase95_profile_steam workers_jobs=%s workers_cells=%s workers_usec=%s" % [worker_jobs, worker_cells, worker_usec])


func _profile_steam_pipes() -> void:
	var world: Variant = _world(95102)
	world.place_pipe_line(Vector2i(0, 0), Vector2i(49999, 0))
	for x in 50000:
		world.set_pipe_fluid(Vector2i(x, 0), 17, 16384 if x % 2 == 0 else 49152, 1800)
	var samples: Array[Dictionary] = []
	for tick in 32:
		var started := Time.get_ticks_usec()
		world.step()
		var wall := Time.get_ticks_usec() - started
		var pipe: Dictionary = world.get_pipe_statistics()
		samples.append({
			"tick": tick, "wall": wall, "pipe": int(pipe.pipe_usec),
			"gather": int(pipe.gather_usec), "state": int(pipe.state_usec),
			"flow": int(pipe.flow_usec), "schedule": int(pipe.schedule_usec),
			"active": int(pipe.segments_active), "visited": int(pipe.segments_visited),
			"transfers": int(pipe.transfers), "pressure": int(pipe.pressure_edges),
			"damage": int(pipe.damage_checks), "phase": int(pipe.phase_checks),
			"heat": int(pipe.heat_edges), "automation": int(pipe.automation_hooks),
		})
	_print_profile("steam_pipe_50k", samples)


func _print_profile(label: String, samples: Array[Dictionary]) -> void:
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.wall) < int(b.wall))
	var average: Dictionary = {}
	for key: Variant in samples[0].keys():
		if key == "tick": continue
		var total := 0
		for sample: Dictionary in samples: total += int(sample[key])
		average[key] = float(total) / float(samples.size())
	var p95: Dictionary = samples[clampi(ceili(samples.size() * 0.95) - 1, 0, samples.size() - 1)]
	var p99: Dictionary = samples[clampi(ceili(samples.size() * 0.99) - 1, 0, samples.size() - 1)]
	print("phase95_profile scenario=%s average=%s p95=%s p99=%s" % [label, average, p95, p99])
