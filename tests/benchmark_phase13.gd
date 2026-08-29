extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int) -> Variant:
	var world: Variant = NativeSandWorld.new()
	world.reset(seed, 8)
	world.set_game_mode(1)
	return world


func _measure(name: String, world: Variant, ticks: int) -> void:
	for warmup in 3: world.step()
	var samples: Array[float] = []
	for tick in ticks:
		var started := Time.get_ticks_usec()
		world.step()
		samples.append((Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	print("phase13_benchmark scenario=%s ticks=%d avg_ms=%.4f p95_ms=%.4f p99_ms=%.4f worst_ms=%.4f" % [name, ticks, total / ticks, samples[int((ticks - 1) * 0.95)], samples[int((ticks - 1) * 0.99)], samples[-1]])


func _run() -> void:
	var fractions: Variant = _world(13100)
	var fraction_started := Time.get_ticks_usec()
	var fraction_report: Dictionary = fractions.run_global_mass_fixture(250000, 4590, 17)
	var fraction_ms := (Time.get_ticks_usec() - fraction_started) / 1000.0
	print("phase13_benchmark scenario=fractionation events=%d elapsed_ms=%.4f events_per_second=%.1f balanced=%s" % [fraction_report.events, fraction_ms, float(fraction_report.events) * 1000.0 / fraction_ms, str(fraction_report.balanced)])
	for minutes in [15, 30, 60, 90]:
		print("phase13_playthrough %s" % JSON.stringify(fractions.evaluate_mvp_playthrough(minutes, 4590)))

	var screens: Variant = _world(13101)
	for index in 1024:
		var origin := Vector2i((index % 32) * 5, (index / 32) * 5)
		screens.place_structure(45, origin, 0)
		screens.place_structure(41, origin + Vector2i(1, 0), 0)
		screens.set_material_state(origin + Vector2i(1, -1), 2, 255, 1173, 4590, index & 65535)
	_measure("screen_network_1024", screens, 30)

	var riffles: Variant = _world(13102)
	for index in 1024:
		var origin := Vector2i((index % 32) * 7, (index / 32) * 5)
		riffles.place_structure(43, origin, 0)
		for offset in [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(2, 0)]: riffles.place_structure(37, origin + offset, 0)
		riffles.set_water_mass(origin + Vector2i(-1, -1), 255, 1173)
		riffles.set_water_mass(origin + Vector2i(1, -1), 255, 1173)
		riffles.set_material_state(origin + Vector2i(0, -1), 2, 255, 1173, 4590, index & 65535)
	_measure("riffle_field_1024", riffles, 30)

	var magnets: Variant = _world(13103)
	for index in 1024:
		var origin := Vector2i((index % 32) * 6, (index / 32) * 5)
		magnets.place_structure(46, origin, 0)
		magnets.set_material_state(origin + Vector2i(0, 1), 7, 255, 1173, 4590, index & 65535)
	_measure("magnetic_concentrate_1024", magnets, 30)

	var wet: Variant = _world(13104)
	for index in 16384:
		var sediment := Vector2i((index % 128) * 2, index / 128)
		var water := sediment + Vector2i(1, 0)
		wet.set_material_state(sediment, 2, 255, 1500, 4590, index & 65535)
		wet.set_water_mass(water, 32, 1173)
		wet.bind_water_to_sediment(sediment, water, 24)
	_measure("wet_sediment_clay_fines_16384", wet, 30)

	var furnaces: Variant = _world(13105)
	for index in 1024:
		var origin := Vector2i((index % 32) * 6, (index / 32) * 6)
		furnaces.place_structure(40, origin, 0)
		furnaces.set_material_state(origin + Vector2i(0, -1), 2, 255, 6500, 4590, index & 65535)
	_measure("component_furnace_1024", furnaces, 30)

	var vessels: Variant = _world(13106)
	for index in 1024:
		var origin := Vector2i((index % 32) * 5, (index / 32) * 4)
		vessels.place_structure(38 if index % 2 == 0 else 39, origin, 0)
		vessels.set_material_state(origin + Vector2i(-1, 0), 1, 255, 6200)
		vessels.set_material_state(origin + Vector2i(1, 0), 3, 255, 1173)
		vessels.set_material_state(origin + Vector2i(1, 1), 1, 255, 1173)
	_measure("component_vessel_1024", vessels, 30)
	quit(0)
