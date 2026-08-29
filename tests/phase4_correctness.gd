extends SceneTree

const EMPTY := 0
const STONE := 1
const RAW := 2
const COAL_TERRAIN := 4
const BEDROCK := 5
const FINE := 6
const HEAVY := 7
const IRON_CONC := 8
const NONMAG := 9
const GLASS := 10
const IRON := 11
const GOLD := 12
const RESIDUE := 13
const COAL_CHUNK := 14
const ASH := 15
const CHARCOAL := 23
const FURNACE := 5
const SIEVE := 6
const MAGNETIC := 7
const PROCESS_SIEVE := 101
const PROCESS_MAGNETIC := 201

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cell_layout_and_signatures()
	_test_constituents_and_stable_processing()
	_test_harvest()
	_test_sieve()
	_test_magnetic()
	_test_furnace_and_fuel_mass()
	_test_recovery_routes()
	if failures.is_empty():
		print("PASS: %d checks across 7 Phase 4 suites" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("PHASE4: %s" % failure)
		print("FAIL: %d failures across %d checks" % [failures.size(), checks])
		quit(1)


func _world(seed := 44001) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world


func _test_cell_layout_and_signatures() -> void:
	var world: Variant = _world()
	var layout: Dictionary = world.get_memory_layout()
	check_equal(layout.material_bytes_per_cell, 2, "uint16 material storage")
	check_equal(layout.temperature_storage, "uint16", "absolute thermal storage uses unsigned 16-bit")
	check_equal(layout.mineral_signature_bytes_per_cell, 2, "uint16 mineral signature")
	check_equal(layout.simulation_bytes_per_cell, 9, "nine-byte simulation cell")
	check_equal(layout.invalid_api_sentinel, -1, "API sentinel remains signed")
	check_equal(layout.maximum_material_id, 27, "all stable IDs fit uint16")
	var cell := Vector2i(-37, -9)
	world.set_cell(cell, RAW)
	var signature: int = world.get_mineral_signature(cell)
	check(signature >= 0 and signature <= 65535, "signature covers uint16 range")
	world.set_cell(cell, EMPTY)
	check_equal(world.get_mineral_signature(cell), 0, "erase clears signature")
	world.set_cell(cell, RAW)
	check_equal(world.get_mineral_signature(cell), signature, "repaint regenerates deterministic signature")
	world.set_cell_with_metadata(Vector2i(0, 0), RAW, 1234, 41922)
	world.set_cell(Vector2i(0, 2), STONE)
	world.step()
	check_equal(world.get_mineral_signature(Vector2i(0, 1)), 41922, "fall preserves signature")
	var belt: Variant = _world(44002)
	belt.place_conveyor_line(Vector2i(62, 10), Vector2i(63, 10), 1)
	belt.set_cell(Vector2i(64, 10), STONE)
	belt.set_cell_with_metadata(Vector2i(63, 9), RAW, 381, 60001)
	belt.step()
	check_equal(belt.get_cell(Vector2i(64, 9)), RAW, "conveyor crosses chunk boundary")
	check_equal(belt.get_provenance(Vector2i(64, 9)), 381, "chunk crossing preserves provenance")
	check_equal(belt.get_mineral_signature(Vector2i(64, 9)), 60001, "chunk crossing preserves signature")


func _test_constituents_and_stable_processing() -> void:
	var world: Variant = _world(44003)
	var profile: int = world.geology_profile_id_at(Vector2i(300, 120))
	var counts := [0, 0, 0, 0, 0]
	for signature in 65536:
		counts[world.get_hidden_constituent(profile, signature)] += 1
	var geology: Dictionary = world.get_geology_profile(profile)
	check(absf(float(counts[0]) / 65536.0 - float(geology.silica_fraction)) < 0.002, "silica population matches profile")
	check(absf(float(counts[1]) / 65536.0 - float(geology.iron_fraction)) < 0.002, "iron population matches profile")
	var zero_gold_profile := profile & 0x1fff
	var gold_count := 0
	for signature in 65536:
		gold_count += 1 if world.get_hidden_constituent(zero_gold_profile, signature) == 3 else 0
	check_equal(gold_count, 0, "zero-gold profile has no gold-bearing grains")
	var first: int = world.process_material_for_test(RAW, profile, 41922, PROCESS_SIEVE)
	for _repeat in 100:
		check_equal(world.process_material_for_test(RAW, profile, 41922, PROCESS_SIEVE), first, "stable process is timing/machine independent")
	var sieve_result: int = world.process_material_for_test(RAW, profile, 50123, PROCESS_SIEVE)
	check(sieve_result == FINE or sieve_result == HEAVY, "Sieve produces one valid route")
	check(world.process_material_for_test(HEAVY, profile, 50123, PROCESS_MAGNETIC) in [IRON_CONC, NONMAG], "Magnetic produces one valid route")


func _test_harvest() -> void:
	var world: Variant = _world(44004)
	world.set_cell(Vector2i.ZERO, COAL_TERRAIN)
	check_equal(world.harvest_cell(Vector2i.ZERO), OK, "coal harvest succeeds")
	check_equal(world.get_cell(Vector2i.ZERO), COAL_CHUNK, "Coal terrain becomes physical Coal Chunk")
	world.set_cell(Vector2i(2, 0), BEDROCK)
	check_equal(world.harvest_cell(Vector2i(2, 0)), ERR_INVALID_PARAMETER, "Bedrock protected")
	check_equal(world.get_cell(Vector2i(2, 0)), BEDROCK, "Bedrock remains")


func _test_sieve() -> void:
	var world: Variant = _world(44005)
	check(world.place_structure(SIEVE, Vector2i(0, 10)) > 0, "Vibrating Screen placed")
	var fine_signature := _signature_for_size(world, 321, 0)
	var coarse_signature := _signature_for_size(world, 321, 2)
	world.set_cell_with_metadata(Vector2i(3, 12), RAW, 321, fine_signature)
	world.set_cell_with_metadata(Vector2i(6, 12), RAW, 321, coarse_signature)
	world.step()
	check_equal(world.get_cell(Vector2i(3, 13)), FINE, "fine grain physically passes mesh")
	check_equal(world.get_cell(Vector2i(6, 13)), EMPTY, "coarse grain remains supported above mesh")
	check_equal(world.get_provenance(Vector2i(3, 13)), 321, "Screen preserves provenance")
	check_equal(world.get_mineral_signature(Vector2i(3, 13)), fine_signature, "Screen preserves signature")
	check_equal(_row_count(world, 12, RAW) + _row_count(world, 13, FINE), 2, "Screen no duplication")
	var blocked: Variant = _world(44105)
	blocked.place_structure(SIEVE, Vector2i(0, 10))
	for x in range(1, 9): blocked.set_cell(Vector2i(x, 14), STONE)
	blocked.set_cell_with_metadata(Vector2i(3, 12), RAW, 321, fine_signature)
	blocked.step()
	blocked.step()
	check_equal(blocked.get_cell(Vector2i(3, 13)), FINE, "blocked lower collection backs up physically")
	check_equal(blocked.get_mineral_signature(Vector2i(3, 13)), fine_signature, "blocked Screen retains grain identity")


func _test_magnetic() -> void:
	var world: Variant = _world(44006)
	check(world.place_structure(MAGNETIC, Vector2i(0, 10)) > 0, "Overbelt Magnetic Separator placed")
	world.place_conveyor_line(Vector2i(-1, 16), Vector2i(12, 16), 1)
	var iron_signature := _signature_for_constituent(world, 411, 1)
	var nonmag_signature := _signature_for_constituent(world, 411, 0)
	world.set_cell_with_metadata(Vector2i(4, 15), HEAVY, 411, nonmag_signature)
	world.step()
	check_equal(_row_count(world, 15, HEAVY), 1, "nonmagnetic grain remains on lower route")
	world.set_cell_with_metadata(Vector2i(4, 15), HEAVY, 411, iron_signature)
	world.step()
	check_equal(world.get_cell(Vector2i(4, 14)), IRON_CONC, "magnetic grain lifts through simulated space")
	check_equal(world.get_mineral_signature(Vector2i(4, 14)), iron_signature, "Magnet preserves signature")
	check_equal(_row_count(world, 14, IRON_CONC), 1, "Magnet no duplication")
	var blocked: Variant = _world(44106)
	blocked.place_structure(MAGNETIC, Vector2i(0, 10))
	for x in range(-1, 13): blocked.set_cell(Vector2i(x, 16), STONE)
	blocked.set_cell(Vector2i(4, 14), STONE)
	blocked.set_cell_with_metadata(Vector2i(4, 15), HEAVY, 411, iron_signature)
	blocked.step()
	check_equal(blocked.get_cell(Vector2i(4, 15)), HEAVY, "blocked magnetic path prevents extraction")
	check_equal(blocked.get_mineral_signature(Vector2i(4, 15)), iron_signature, "blocked Magnet retains grain identity")


func _test_furnace_and_fuel_mass() -> void:
	var world: Variant = _world(44007)
	check(world.place_structure(FURNACE, Vector2i(0, 10)) > 0, "Radiant Crude Furnace placed")
	for x in range(1, 9): world.set_cell(Vector2i(x, 14), STONE)
	world.set_material_state(Vector2i(2, 13), CHARCOAL, 255, 3000)
	world.set_cell_with_metadata(Vector2i(4, 13), RAW, 777, 30000)
	var cold: int = world.get_temperature(Vector2i(4, 13))
	world.step()
	check(world.get_temperature(Vector2i(4, 13)) > cold, "Furnace applies physical heat locally")
	check_equal(world.get_cell(Vector2i(4, 13)), RAW, "one heat step does not teleport or instantly convert the grain")
	check_equal(world.get_structure(Vector2i(4, 13)), 0, "Furnace heating bay remains physically open")
	for _tick in 30: world.step()
	var product: int = world.get_cell(Vector2i(4, 13))
	check(product in [GLASS, IRON, GOLD, RESIDUE], "sustained heat reacts material in place")
	check_equal(world.get_provenance(Vector2i(4, 13)), 777, "thermal reaction preserves provenance")
	check_equal(world.get_mineral_signature(Vector2i(4, 13)), 30000, "thermal reaction preserves signature")
	check_equal(world.get_physical_processing_statistics().heat_reactions_total, 1, "one physical grain produces one reaction")
	check(world.get_temperature(Vector2i(4, 13)) >= 5893, "reaction retains physically accumulated absolute temperature")
	check_equal(_row_count(world, 13, product), 1, "Furnace reaction conserves one visible grain without hidden output")


func _test_recovery_routes() -> void:
	var world: Variant = _world(44008)
	var profile: int = world.geology_profile_id_at(Vector2i(1200, 180))
	var routes: Dictionary = world.evaluate_processing_routes(profile, 100000)
	for key in ["route_a", "route_b", "route_c"]:
		var route: Dictionary = routes[key]
		check_equal(route.glass + route.iron + route.gold + route.residue, 100000, "%s conserves 100k grains" % key)
		check_equal(route.coal, route.ash, "%s conserves fuel mass" % key)
	check(int(routes.route_b.glass) > int(routes.route_a.glass), "Sieve route materially improves Glass")
	check(int(routes.route_c.iron) > int(routes.route_a.iron), "specialized route materially improves Iron")
	var no_gold_profile := profile & 0x1fff
	var no_gold: Dictionary = world.evaluate_processing_routes(no_gold_profile, 100000)
	check_equal(no_gold.route_a.gold + no_gold.route_b.gold + no_gold.route_c.gold, 0, "zero-gold geology can never manufacture Gold")
	var anomaly_profile := 16 | (10 << 5) | (7 << 10) | (7 << 13)
	var anomaly: Dictionary = world.evaluate_processing_routes(anomaly_profile, 100000)
	check(int(anomaly.route_a.gold) > 0, "gold anomaly produces rare primitive Gold")
	check(int(anomaly.route_c.gold) > int(anomaly.route_a.gold) * 3, "specialized route materially improves Gold recovery")
	print("phase4_recovery profile=%d A=%s B=%s C=%s" % [profile, routes.route_a, routes.route_b, routes.route_c])
	print("phase4_gold_anomaly profile=%d A=%s B=%s C=%s" % [anomaly_profile, anomaly.route_a, anomaly.route_b, anomaly.route_c])


func _count_materials(world: Variant, cells: Array[Vector2i], accepted: Array[int]) -> int:
	var count := 0
	for cell in cells:
		count += 1 if world.get_cell(cell) in accepted else 0
	return count


func _signature_for_size(world: Variant, profile: int, size_class: int) -> int:
	for signature in 65536:
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, signature)
		if world.get_grain_size_class(Vector2i(9000, 9000)) == size_class:
			world.set_cell(Vector2i(9000, 9000), EMPTY)
			return signature
	world.set_cell(Vector2i(9000, 9000), EMPTY)
	return -1


func _signature_for_constituent(world: Variant, profile: int, constituent: int) -> int:
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) == constituent:
			return signature
	return -1


func _row_count(world: Variant, y: int, material_id: int) -> int:
	var count := 0
	for x in range(-4, 20): count += 1 if world.get_cell(Vector2i(x, y)) == material_id else 0
	return count


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func check_equal(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
