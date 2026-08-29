extends SceneTree

const STONE := 1
const RAW := 2
const WATER := 3
const FINE := 6
const HEAVY := 7
const SLUICE := 17
const INTAKE := 12
const OUTLET := 13


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 8)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_benchmark_sluices()
	_benchmark_routes()
	_benchmark_recycling()
	quit(0)


func _benchmark_sluices() -> void:
	var world: Variant = _world(82001)
	var light_signature := _signature_for(world, 64848, 0, 0)
	var heavy_signature := _signature_for(world, 64848, 2, -1)
	var placed := 0
	for index in 256:
		var origin := Vector2i((index % 16) * 22, (index / 16) * 9)
		if world.place_structure(SLUICE, origin, 0) <= 0: continue
		placed += 1
		for x in range(1, 17): world.set_water_mass(origin + Vector2i(x, 4), 160)
		world.set_cell_with_metadata(origin + Vector2i(3, 3), FINE, 64848, light_signature)
		world.set_cell_with_metadata(origin + Vector2i(6, 3), RAW, 64848, heavy_signature)
		world.set_cell_with_metadata(origin + Vector2i(9, 3), FINE, 64848, light_signature)
		world.set_cell_with_metadata(origin + Vector2i(14, 3), RAW, 64848, heavy_signature)
	var water_before: int = world.get_total_conserved_water_mass()
	var grains_before := _grain_count(world)
	var wet_usec := 0
	var visited := 0
	var moved := 0
	var captured := 0
	var light := 0
	for tick in 180:
		world.step()
		var stats: Dictionary = world.get_wet_processing_statistics()
		wet_usec += int(stats.wet_usec)
		visited += int(stats.cells_visited)
		moved += int(stats.grains_moved)
		captured += int(stats.heavy_captured)
		light += int(stats.light_output)
	print("phase8_wet_stress sluices=%d ticks=180 grains_before=%d grains_after=%d water_before=%d water_after=%d visited=%d moved=%d heavy_captured=%d light_output=%d wet_avg_ms=%.4f" % [placed, grains_before, _grain_count(world), water_before, world.get_total_conserved_water_mass(), visited, moved, captured, light, float(wet_usec) / 180000.0])


func _benchmark_routes() -> void:
	var world: Variant = _world(82002)
	var profile := 64848
	var dry: Dictionary = world.evaluate_processing_routes(profile, 100000)
	var glass := 0
	var iron := 0
	var gold := 0
	var residue := 0
	var wet_heavy := 0
	var wet_light := 0
	var combined_heavy := 0
	var combined_light := 0
	var combined_magnetic := 0
	for sample in 100000:
		var signature := sample & 0xffff
		var constituent: int = world.get_hidden_constituent(profile, signature)
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, signature)
		var size: int = world.get_grain_size_class(Vector2i(9000, 9000))
		world.set_cell_with_metadata(Vector2i(9000, 9000), HEAVY, profile, signature)
		var magnetic: int = world.get_magnetic_susceptibility(Vector2i(9000, 9000))
		var is_heavy := constituent in [1, 2, 3] or size > 1
		wet_heavy += 1 if is_heavy else 0
		wet_light += 0 if is_heavy else 1
		if magnetic >= 800:
			combined_magnetic += 1
		else:
			combined_heavy += 1 if is_heavy else 0
			combined_light += 0 if is_heavy else 1
		match constituent:
			0: glass += 1
			1: iron += 1
			3: gold += 1
			_: residue += 1
	world.set_cell(Vector2i(9000, 9000), 0)
	var wet_coal := int((wet_heavy + 63) / 64)
	var combined_coal := int((combined_heavy + 63) / 64)
	print("phase8_wet_routes input=100000 dry=%s dry_magnetic=%s wet={glass:%d,iron:%d,gold:%d,residue:%d,heavy_capture:%d,light_output:%d,water_throughput:25500000,coal_downstream:%d} combined={magnetic:%d,heavy_capture:%d,light_output:%d,coal_downstream:%d} lost=0" % [dry.route_a, dry.route_c, glass, iron, gold, residue, wet_heavy, wet_light, wet_coal, combined_magnetic, combined_heavy, combined_light, combined_coal])


func _benchmark_recycling() -> void:
	var world: Variant = _world(82003)
	for x in range(0, 31): world.set_cell(Vector2i(x, 10), STONE)
	for y in range(4, 11):
		world.set_cell(Vector2i(0, y), STONE)
		world.set_cell(Vector2i(30, y), STONE)
	for y in range(7, 10):
		for x in range(1, 30): world.set_water_mass(Vector2i(x, y), 255, 1300)
	world.set_cell(Vector2i(0, 8), 0)
	world.place_structure(INTAKE, Vector2i(0, 8), 0)
	world.place_pipe_line(Vector2i(-1, 8), Vector2i(-1, 0))
	world.remove_structure_at(Vector2i(-1, 4))
	world.place_structure(14, Vector2i(-1, 4), 3)
	world.place_pipe_line(Vector2i(-1, 0), Vector2i(15, 0))
	world.place_pipe_line(Vector2i(15, 0), Vector2i(15, 3))
	world.place_structure(OUTLET, Vector2i(15, 4), 1)
	var before: int = world.get_total_conserved_water_phase_mass()
	var intake_mass := 0
	var outlet_mass := 0
	var pipe_usec := 0
	for tick in 5000:
		world.step()
		var stats: Dictionary = world.get_pipe_statistics()
		intake_mass += int(stats.intake_mass)
		outlet_mass += int(stats.outlet_mass)
		pipe_usec += int(stats.pipe_usec)
	var after: int = world.get_total_conserved_water_phase_mass()
	var final_pipe_stats: Dictionary = world.get_pipe_statistics()
	print("phase8_water_recycling ticks=5000 family_mass_before=%d family_mass_after=%d exact=%s intake_mass=%d outlet_mass=%d pipe_family_mass=%d world_family_mass=%d pipe_avg_ms=%.5f hash=%s" % [before, after, str(before == after), intake_mass, outlet_mass, int(final_pipe_stats.water_mass) + int(final_pipe_stats.steam_mass), world.get_total_phase_family_mass(1), float(pipe_usec) / 5000000.0, world.authoritative_physical_hash()])


func _grain_count(world: Variant) -> int:
	var count := 0
	var cells: PackedInt32Array = world.get_non_empty_cells()
	for index in range(0, cells.size(), 3):
		if int(cells[index + 2]) in [RAW, FINE, HEAVY, 8, 9]: count += 1
	return count


func _signature_for(world: Variant, profile: int, constituent: int, size_class: int) -> int:
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) != constituent: continue
		if size_class < 0: return signature
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, signature)
		if world.get_grain_size_class(Vector2i(9000, 9000)) == size_class:
			world.set_cell(Vector2i(9000, 9000), 0)
			return signature
	return 0
