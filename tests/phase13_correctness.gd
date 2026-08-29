extends SceneTree

const FULL := 65280
const RAW_SAND := 2

var checks := 0
var suites := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _world(seed := 13001, workers := 4) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_architecture()
	_gold_matrix()
	_non_integer_matrix()
	_variable_order()
	_global_mass_matrix()
	_components()
	_sediment_water_and_thermal_fractionation()
	_mid_fraction_save_load()
	_repeated_snapshot_cycles()
	_progression_and_milestones()
	if failures.is_empty():
		print("PASS: %d checks across %d Phase 13 suites" % [checks, suites])
		quit(0)
	else:
		for failure in failures: push_error("PHASE13: " + failure)
		print("FAIL: %d of %d Phase 13 checks" % [failures.size(), checks])
		quit(1)


func _architecture() -> void:
	suites += 1
	var world: Variant = _world()
	var architecture: Dictionary = world.get_conservation_architecture()
	_eq(architecture.full_cell_micro_mass, FULL, "canonical full-cell micro mass")
	_eq(architecture.amount_unit_micro_mass, 256, "existing amount unit converts exactly")
	_eq(architecture.full_cell_amount_units, 255, "255 amount units remain one cell")
	_eq(architecture.base_cell_bytes, 9, "optional composition does not increase base cell")
	_check(not architecture.yield_rng, "processing yield RNG disabled")
	for signature in [0, 1, 65535]:
		var composition: Dictionary = world.derive_material_composition(4590, signature)
		_eq(composition.total, FULL, "derived composition sums exactly signature=%d" % signature)


func _gold_matrix() -> void:
	suites += 1
	var world: Variant = _world()
	for count in [1, 19, 20, 21, 100, 1000]:
		var report: Dictionary = world.run_fractionation_fixture(5, 100, count, 0)
		var expected_gold_micro: int = count * (FULL * 5 / 100)
		_eq(report.gold_emitted_quanta, expected_gold_micro / FULL, "5%% Gold emitted quanta count=%d" % count)
		_eq(report.gold_retained_micro_mass, expected_gold_micro % FULL, "5%% Gold retained count=%d" % count)
		_check(report.balanced, "5%% fixture exact balance count=%d" % count)
	print("phase13_gold_exact counts=[1,19,20,21,100,1000] full=%d gold_per_input=%d" % [FULL, FULL * 5 / 100])


func _non_integer_matrix() -> void:
	suites += 1
	var world: Variant = _world()
	for ratio in [[1,100], [3,100], [7,100], [1,8], [1,3]]:
		var report: Dictionary = world.run_fractionation_fixture(ratio[0], ratio[1], 1000, 0)
		_check(report.balanced, "fraction %d/%d exact balance" % ratio)
		_eq(report.input_micro_mass, 1000 * FULL, "fraction %d/%d input mass" % ratio)
		_eq(report.input_micro_mass, report.emitted_micro_mass + report.retained_micro_mass + report.queued_micro_mass, "fraction %d/%d equation" % ratio)
		print("phase13_fraction ratio=%d/%d input=%d emitted=%d retained=%d" % [ratio[0], ratio[1], report.input_micro_mass, report.emitted_micro_mass, report.retained_micro_mass])


func _variable_order() -> void:
	suites += 1
	var world: Variant = _world()
	var a: Dictionary = world.run_variable_composition_fixture([9, 1, 9, 1, 7, 3], 100, 0)
	var b: Dictionary = world.run_variable_composition_fixture([1, 3, 7, 9, 1, 9], 100, 0)
	_eq(a.input_micro_mass, b.input_micro_mass, "variable order input total")
	_eq(a.emitted_micro_mass, b.emitted_micro_mass, "variable order emitted total")
	_eq(a.retained_micro_mass, b.retained_micro_mass, "variable order retained total")
	_check(a.balanced and b.balanced, "variable order both balanced")


func _global_mass_matrix() -> void:
	suites += 1
	var world: Variant = _world(13006)
	var ten_thousand: Dictionary = world.run_global_mass_fixture(10000, 4590, 17)
	_check(ten_thousand.balanced, "10,000-input multi-stage constituent ledger has zero drift")
	_eq(ten_thousand.input_micro_mass, ten_thousand.accounted_micro_mass, "10,000-input global mass equation")
	_eq(ten_thousand.input_constituents, ten_thousand.accounted_constituents, "10,000-input per-constituent trace")
	var million_events: Dictionary = world.run_global_mass_fixture(250000, 4590, 17)
	_check(million_events.balanced, "1,000,000 process events have zero cumulative drift")
	_eq(million_events.events, 1000000, "one million exact split events executed")
	print("phase13_global_mass inputs=10000 events=%d input_micro=%d accounted_micro=%d balanced=%s" % [ten_thousand.events, ten_thousand.input_micro_mass, ten_thousand.accounted_micro_mass, str(ten_thousand.balanced)])


func _components() -> void:
	suites += 1
	var world: Variant = _world()
	var classes: Dictionary = world.get_component_classification()
	for id in [5, 6, 7, 17, 35]: _eq(classes[str(id)], "DEV_FIXTURE", "legacy prefab classification %d" % id)
	for id in range(37, 48): _eq(classes[str(id)], "KEEP_COMPONENT", "component classification %d" % id)
	_check(world.get_structure_physical_properties(38).conductivity > world.get_structure_physical_properties(39).conductivity, "Metal conducts faster than Ceramic")
	_check(world.get_structure_physical_properties(40).maximum_temperature > world.get_structure_physical_properties(38).maximum_temperature, "Refractory survives more heat than Metal")
	var metal: Variant = _world(13021)
	metal.place_structure(38, Vector2i.ZERO, 0)
	metal.set_material_state(Vector2i(-1, 0), 1, 255, 6200)
	metal.set_material_state(Vector2i(1, 0), 3, 255, 1172)
	for x in range(-2, 3): metal.set_material_state(Vector2i(x, 1), 1, 255, 1172)
	metal.set_material_state(Vector2i(2, 0), 1, 255, 1172)
	var ceramic: Variant = _world(13021)
	ceramic.place_structure(39, Vector2i.ZERO, 0)
	ceramic.set_material_state(Vector2i(-1, 0), 1, 255, 6200)
	ceramic.set_material_state(Vector2i(1, 0), 3, 255, 1172)
	for x in range(-2, 3): ceramic.set_material_state(Vector2i(x, 1), 1, 255, 1172)
	ceramic.set_material_state(Vector2i(2, 0), 1, 255, 1172)
	for tick in 4:
		metal.step()
		ceramic.step()
	_check(metal.get_temperature(Vector2i(1, 0)) > ceramic.get_temperature(Vector2i(1, 0)), "replacing Ceramic with Metal physically increases heat transfer")
	var containment: Variant = _world(13022)
	for x in range(-1, 2): containment.set_material_state(Vector2i(x, 3), 1, 255, 1172)
	containment.place_structure(37, Vector2i(0, 2), 0)
	containment.place_structure(37, Vector2i(-1, 1), 0)
	containment.place_structure(37, Vector2i(1, 1), 0)
	containment.place_structure(37, Vector2i(-1, 2), 0)
	containment.place_structure(37, Vector2i(1, 2), 0)
	containment.set_water_mass(Vector2i(0, 1), 255, 1172)
	containment.step()
	_eq(containment.get_liquid_mass(Vector2i(0, 1)), 255, "component wall geometry contains Water")
	_eq(containment.remove_structure_at(Vector2i(0, 2)), 1, "empty component wall can be removed")
	for tick in 3: containment.step()
	_check(containment.get_liquid_mass(Vector2i(0, 1)) < 255, "deleting wall changes containment behavior")
	var no_actuator: Variant = _world(13023)
	no_actuator.place_structure(41, Vector2i(1, 1), 0)
	no_actuator.set_material_state(Vector2i(0, 0), 1, 255, 1173)
	no_actuator.set_material_state(Vector2i(2, 0), 1, 255, 1173)
	no_actuator.set_material_state(Vector2i(1, 0), RAW_SAND, 255, 1173, 4590, 1)
	no_actuator.step()
	_eq(no_actuator.get_conservation_architecture().ledger_count, 0, "Mesh alone has no hidden screening ledger")
	_eq(world.place_structure(45, Vector2i(0, 1), 0), 1, "place Vibration Actuator")
	_eq(world.place_structure(41, Vector2i(1, 1), 0), 1, "place individual Mesh")
	_eq(world.place_structure(37, Vector2i(2, 1), 0), 1, "place coarse-output support")
	for index in 3:
		world.set_material_state(Vector2i(1, 0), RAW_SAND, 255, 1173, 4590, index + 1)
		world.step()
	var before_remove: Dictionary = world.get_conservation_architecture()
	_check(before_remove.ledger_count > 0, "component-built screen owns authoritative carry")
	_eq(world.remove_structure_at(Vector2i(0, 1)), 0, "component with carry rejects removal")
	_check(world.get_conservation_architecture().rejected_removals > 0, "removal rejection is diagnosed")
	var wet_riffle: Variant = _world(13024)
	wet_riffle.place_structure(43, Vector2i.ZERO, 0)
	wet_riffle.place_structure(37, Vector2i(-1, 0), 0)
	wet_riffle.place_structure(37, Vector2i(1, 0), 0)
	wet_riffle.place_structure(37, Vector2i(-2, 0), 0)
	wet_riffle.place_structure(37, Vector2i(2, 0), 0)
	wet_riffle.set_material_state(Vector2i(-2, -1), 1, 255, 1173)
	wet_riffle.set_material_state(Vector2i(2, -1), 1, 255, 1173)
	wet_riffle.set_water_mass(Vector2i(-1, -1), 255, 1173)
	wet_riffle.set_water_mass(Vector2i(1, -1), 255, 1173)
	wet_riffle.set_material_state(Vector2i(0, -1), RAW_SAND, 255, 1173, 4590, 2)
	wet_riffle.step()
	_check(not wet_riffle.get_fractional_ledger(0).is_empty(), "Riffle plus real Water performs density separation")
	var no_riffle: Variant = _world(13025)
	no_riffle.set_water_mass(Vector2i(-1, -1), 255, 1173)
	no_riffle.set_material_state(Vector2i(0, -1), RAW_SAND, 255, 1173, 4590, 2)
	no_riffle.step()
	_check(no_riffle.get_conservation_architecture().ledger_count == 0, "removing Riffle removes wet separation behavior")


func _sediment_water_and_thermal_fractionation() -> void:
	suites += 1
	var wet: Variant = _world(13004)
	wet.set_material_state(Vector2i.ZERO, RAW_SAND, 255, 1173, 4590, 17)
	wet.set_material_state(Vector2i(1, 0), 3, 40, 1173)
	var binding: Dictionary = wet.bind_water_to_sediment(Vector2i.ZERO, Vector2i(1, 0), 25)
	_eq(binding.accepted, 25, "physical Water binds to sediment")
	_check(binding.mass_balanced, "binding conserves free plus bound Water")
	_eq(wet.get_material_amount(Vector2i(1, 0)), 15, "binding removes exact free Water mass")
	_eq(wet.get_bound_water_mass(), 25, "bound Water is authoritative optional state")
	wet.set_material_state(Vector2i.ZERO, RAW_SAND, 255, 1700, 4590, 17)
	wet.step()
	_check(wet.get_bound_water_mass() < 25, "heated wet sediment releases bound Water")
	_eq(wet.get_total_phase_family_mass(1) + wet.get_bound_water_mass(), 40, "drying conserves free plus bound Water")

	var thermal: Variant = _world(13005)
	_eq(thermal.place_structure(40, Vector2i(0, 1), 0), 1, "place ordinary Refractory Wall")
	for input in 2:
		thermal.set_material_state(Vector2i.ZERO, RAW_SAND, 255, 6500, 4590, 17 + input)
		thermal.step()
	var ledger: Dictionary = thermal.get_fractional_ledger(1)
	_eq(ledger.input_micro_mass, FULL * 2, "hot sediment contributes exact constituent mass")
	_check(ledger.balanced, "silica, impurities, outputs and carry remain exact")
	_check(int(ledger.channels[0].emitted_micro_mass) >= FULL, "sufficient hot silica emits physical Molten Glass")
	_check(int(ledger.channels[3].micro_mass) > 0, "thermal impurities remain retained residue")
	_eq(thermal.remove_structure_at(Vector2i(0, 1)), 0, "Refractory ledger cannot be removed while carrying constituents")


func _mid_fraction_save_load() -> void:
	suites += 1
	var world: Variant = _world(13002)
	for index in 19: world.accumulate_fraction_for_test(9001, 5, 100, 0, true)
	var before: Dictionary = world.get_fractional_ledger(9001)
	_eq(before.channels[0].micro_mass, FULL * 95 / 100, "19x5% retains 95% Gold")
	var snapshot: Dictionary = world.serialize_world_snapshot()
	var loaded: Variant = _world(1)
	_check(loaded.deserialize_world_snapshot(snapshot), "world snapshot loads")
	_eq(loaded.phase13_state_hash(), world.phase13_state_hash(), "fractional state hash survives Save/Load")
	var after: Dictionary = loaded.accumulate_fraction_for_test(9001, 5, 100, 0, true)
	_eq(after.channels[0].micro_mass, 0, "20th 5% input clears Gold carry")
	_eq(after.channels[0].emitted_micro_mass, FULL, "20th 5% input emits exactly one Gold quantum")


func _repeated_snapshot_cycles() -> void:
	suites += 1
	var world: Variant = _world(13003)
	world.set_material_state(Vector2i(2, 2), 21, 255, 2300)
	world.set_organic_moisture(Vector2i(2, 2), 31)
	world.accumulate_fraction_for_test(77, 7, 100, 0, true)
	var expected_hash: String = world.phase13_state_hash()
	var expected_physical: String = world.authoritative_physical_hash()
	for cycle in 100:
		var snapshot: Dictionary = world.serialize_world_snapshot()
		var loaded: Variant = _world(1)
		_check(loaded.deserialize_world_snapshot(snapshot), "snapshot cycle %d loads" % cycle)
		world = loaded
	_eq(world.phase13_state_hash(), expected_hash, "100 Save/Load cycles preserve carry")
	_eq(world.authoritative_physical_hash(), expected_physical, "100 Save/Load cycles preserve physical state")


func _progression_and_milestones() -> void:
	suites += 1
	var world: Variant = _world()
	for minutes in [15, 30, 60, 90]:
		var report: Dictionary = world.evaluate_mvp_playthrough(minutes, 4590)
		_check(report.mass_balanced and not report.softlocked, "%d-minute playthrough balanced and recoverable" % minutes)
		_check(report.idle_percent < 20, "%d-minute playthrough is not waiting game" % minutes)
	_check(world.evaluate_mvp_playthrough(60, 4590).powered_factory, "60-minute model reaches powered factory")
	var milestones: Dictionary = world.get_milestone_state()
	_check(milestones.has("powered_factory_established"), "final MVP milestone exists")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
