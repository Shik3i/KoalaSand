extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 15)
	world.set_game_mode(1)
	return world

func _structure_batch(count: int, place: bool, sequence: int) -> CommandBatch:
	var side := ceili(sqrt(float(count)))
	var batch := CommandBatch.new("benchmark-%d-%s" % [count, "place" if place else "undo"], 0, sequence, "%d structures" % count, CommandBatch.ValidationMode.ATOMIC)
	for index in count:
		var cell := Vector2i(index % side, index / side)
		batch.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE if place else WorldCommand.Type.REMOVE_STRUCTURE, {"type_id": 2, "x": cell.x, "y": cell.y, "orientation": 0}))
	return batch

func _run() -> void:
	for count in [100, 1000, 10000]:
		var construction: Variant = _world(875900 + count)
		var side := ceili(sqrt(float(count)))
		construction.allocate_chunk_rect(Rect2i(0, 0, ceili(float(side) / 64.0), ceili(float(side) / 64.0)))
		var bus := WorldCommandBus.new()
		var response := bus.submit_batch(construction, _structure_batch(count, true, count))
		print("phase875_batch commands=%d applied=%d rejected=%d validation_ms=%.3f application_ms=%.3f" % [count, response.applied, response.rejected, float(response.validation_usec) / 1000.0, float(response.application_usec) / 1000.0])
		if count == 10000:
			var undo := bus.submit_batch(construction, _structure_batch(count, false, count + 1))
			print("phase875_undo commands=%d applied=%d rejected=%d validation_ms=%.3f application_ms=%.3f" % [count, undo.applied, undo.rejected, float(undo.validation_usec) / 1000.0, float(undo.application_usec) / 1000.0])

	var active: Variant = _world(875901)
	var run_count := 1563
	var packets_to_seed := 50000
	var seeded := 0
	for run_index in run_count:
		var id := int(active.place_subsurface_channel(run_index % 3, Vector2i(0, run_index * 2), Vector2i(65, run_index * 2)))
		for lane_index in 64:
			if seeded >= packets_to_seed:
				break
			if (lane_index + run_index) % 2 == 0 and active.seed_subsurface_packet_for_test(id, lane_index, 2, 1173, run_index & 65535, lane_index):
				seeded += 1
	var samples: Array[float] = []
	for tick in 120:
		var started := Time.get_ticks_usec()
		active.step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var active_stats: Dictionary = active.get_subsurface_statistics()
	print("phase875_subsurface active runs=%d lane_cells=%d packets=%d median_ms=%.3f p95_ms=%.3f worst_ms=%.3f visited=%d moves=%d blocked=%d memory_bytes=%d" % [run_count, active_stats.packet_capacity, seeded, samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples.back(), active_stats.visited, active_stats.moves, active_stats.blocked, active_stats.packet_backing_bytes])

	var idle: Variant = _world(875902)
	for run_index in run_count:
		idle.place_subsurface_channel(run_index % 3, Vector2i(0, run_index * 2), Vector2i(65, run_index * 2))
	idle.step()
	var idle_samples: Array[float] = []
	for tick in 120:
		var started := Time.get_ticks_usec()
		idle.step()
		idle_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	idle_samples.sort()
	var idle_stats: Dictionary = idle.get_subsurface_statistics()
	print("phase875_subsurface_idle runs=%d median_ms=%.4f p95_ms=%.4f visited=%d active=%d" % [run_count, idle_samples[idle_samples.size() / 2], idle_samples[int(idle_samples.size() * 0.95)], idle_stats.visited, idle_stats.active])

	var event_benchmark: Dictionary = idle.benchmark_production_events(1000000)
	var query_started := Time.get_ticks_usec()
	idle.get_production_statistics()
	var query_ms := float(Time.get_ticks_usec() - query_started) / 1000.0
	print("phase875_production events=%d total_ms=%.3f ns_per_event=%.2f query_ms=%.4f" % [event_benchmark.events, float(event_benchmark.usec) / 1000.0, event_benchmark.nanoseconds_per_event, query_ms])
	quit(0)
