extends SceneTree

const TICKS := 360
const WARMUP := 60


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := NativeSandWorld.new()
	world.reset(67502, 8)
	world.set_game_mode(1)
	var profile := 64848
	var iron_signature := 0
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) == 1:
			iron_signature = signature
			break
	for index in 300:
		var origin := Vector2i((index % 30) * 24, (index / 30) * 14)
		var type_id := 7 if index < 120 else (6 if index < 240 else 5)
		world.place_structure(type_id, origin)
		var support_y := 6 if type_id == 7 else 4
		world.place_conveyor_line(origin + Vector2i(-2, support_y), origin + Vector2i(13, support_y), 1)
		for x in [2, 5, 8]: world.set_cell_with_metadata(origin + Vector2i(x, support_y - 1), 7 if type_id == 7 else 2, profile, iron_signature + x)
	world.finalize_initialization()
	var fluid := NativeFluidPrototype.new()
	fluid.configure_representative(8)
	for tick in WARMUP:
		_feed_factory(world, profile, iron_signature)
		world.step()
		fluid.step_representative()
	var simulation_samples: Array[float] = []
	var fluid_samples: Array[float] = []
	var visited := 0
	var transfers := 0
	var latest: Dictionary
	for tick in TICKS:
		_feed_factory(world, profile, iron_signature)
		var started := Time.get_ticks_usec()
		world.step()
		latest = fluid.step_representative()
		simulation_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		fluid_samples.append(float(latest.fluid_usec) / 1000.0)
		visited += int(latest.visited_cells)
		transfers += int(latest.transfers)
	simulation_samples.sort()
	fluid_samples.sort()
	var memory: Dictionary = fluid.get_memory_statistics()
	print("phase675_mixed allocated_fluid_cells=%d active_latest=%d visited_avg=%d transfers_avg=%d simulation_avg_ms=%.4f simulation_p95_ms=%.4f simulation_p99_ms=%.4f simulation_worst_ms=%.4f fluid_avg_ms=%.4f fluid_p95_ms=%.4f workers=%d factory_structures=%d fluid_state_bytes=%d activity_bytes=%d hash=%s" % [
		latest.allocated_cells, latest.active_cells, visited / TICKS, transfers / TICKS,
		_average(simulation_samples), _percentile(simulation_samples, 0.95), _percentile(simulation_samples, 0.99), simulation_samples[-1],
		_average(fluid_samples), _percentile(fluid_samples, 0.95), latest.workers,
		world.get_structure_statistics().machine_entities, memory.fluid_state_bytes, memory.activity_metadata_bytes, fluid.state_hash(),
	])
	quit(0)


func _feed_factory(world: Variant, profile: int, iron_signature: int) -> void:
	for index in 300:
		var origin := Vector2i((index % 30) * 24, (index / 30) * 14)
		var type_id := 7 if index < 120 else (6 if index < 240 else 5)
		var support_y := 6 if type_id == 7 else 4
		world.set_cell_with_metadata(origin + Vector2i(5, support_y - 1), 7 if type_id == 7 else 2, profile, iron_signature + 5)


func _average(values: Array[float]) -> float:
	var sum := 0.0
	for value in values: sum += value
	return sum / maxi(1, values.size())


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]
