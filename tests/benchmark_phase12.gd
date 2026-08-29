extends SceneTree

const WATER := 3
const STONE := 1
const RAW_FOOD := 25


func _initialize() -> void:
	call_deferred("_run")


func _new_world(seed := 12100, workers := 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world


func _samples(world: Variant, ticks: int) -> Array[int]:
	var values: Array[int] = []
	for tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		values.append(Time.get_ticks_usec() - started)
	return values


func _report(label: String, values: Array[int], world: Variant) -> void:
	values.sort()
	var total := 0
	for value in values: total += value
	var p95: int = values[mini(values.size() - 1, int(values.size() * 0.95))]
	var p99: int = values[mini(values.size() - 1, int(values.size() * 0.99))]
	var organic: Dictionary = world.get_organic_statistics()
	print("phase12_benchmark scenario=%s ticks=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f reaction_ms=%.4f atmosphere_ms=%.4f cluster_ms=%.4f collision_samples=%d active_clusters=%d hash=%s" % [
		label, values.size(), float(total) / values.size() / 1000.0, float(p95) / 1000.0, float(p99) / 1000.0,
		float(values[-1]) / 1000.0, float(organic.reaction_usec) / 1000.0, float(organic.atmosphere_usec) / 1000.0,
		float(organic.cluster_usec) / 1000.0, organic.cluster_collision_samples, organic.active_clusters, world.organic_state_hash(),
	])


func _run() -> void:
	var scenario := "all-light"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scenario="): scenario = argument.trim_prefix("--scenario=")
	match scenario:
		"idle-trees":
			var world: Variant = _new_world(); var config: Dictionary = world.configure_phase12_benchmark(0, 100000)
			_report("idle-trees-100k records=%d" % config.simulation_records, _samples(world, 120), world)
		"tree-falls-100":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(1, 100)
			_report("tree-falls-100", _samples(world, 90), world)
		"tree-falls-1000":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(1, 1000)
			_report("tree-falls-1000", _samples(world, 90), world)
		"wood-equilibrium":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(8, 1000000)
			world.step()
			_report("wood-equilibrium-1m", _samples(world, 12), world)
		"burning-100k":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(4, 100000)
			_report("burning-100k", _samples(world, 4), world)
		"ambient-1m":
			var world: Variant = _new_world(); var config: Dictionary = world.configure_phase12_benchmark(2, 1000000)
			_report("ambient-1m explicit=%d" % config.explicit_work, _samples(world, 120), world)
		"atmosphere-256k":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(3, 256000)
			_report("atmosphere-256k", _samples(world, 8), world)
		"smoke-1m":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(5, 1000000)
			world.step() # Exclude allocation/cold-start work; the gate is explicitly after warmup.
			_report("smoke-1m", _samples(world, 8), world)
		"kilns-256":
			var world: Variant = _new_world(); world.configure_phase12_benchmark(6, 4096)
			_report("kilns-256", _samples(world, 64), world)
		"cookware-1000":
			var world: Variant = _new_world()
			for index in 1000:
				var origin := Vector2i((index % 40) * 12, (index / 40) * 10)
				world.place_structure(35, origin, 0)
				world.set_material_state(origin + Vector2i(4, 4), WATER, 255, 1172)
				world.set_material_state(origin + Vector2i(4, 3), RAW_FOOD, 255, 1400)
				world.set_material_state(origin + Vector2i(4, 6), STONE, 255, 3000)
			_report("cookware-1000", _samples(world, 16), world)
		_:
			for pair in [[0,100000],[2,1000000]]:
				var world: Variant = _new_world(12100 + pair[0]); world.configure_phase12_benchmark(pair[0], pair[1]); _report("light-%d" % pair[0], _samples(world, 30), world)
	quit(0)
