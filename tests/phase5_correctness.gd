extends SceneTree

const RAW := 2
const GLASS := 10
const IRON := 11
const GOLD := 12
const RESIDUE := 13
const COAL_CHUNK := 14
const FURNACE := 5
const SIEVE := 6
const MAGNETIC := 7
const BANK := 8
const HEAVY := 7
const IRON_CONC := 8

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fresh_state_and_tree()
	_test_bank_accounting()
	_test_bank_reject_and_blockage()
	_test_multiple_banks_and_large_ledger()
	_test_research_atomicity_and_enforcement()
	_test_global_upgrades()
	_test_serialization_and_determinism()
	_test_progression_pacing()
	if failures.is_empty():
		print("PASS: %d checks across 8 Phase 5 suites" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("PHASE5: " + failure)
	print("FAIL: %d failures across %d checks" % [failures.size(), checks])
	quit(1)


func _world(seed := 55001) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	return world


func _fund(world: Variant, glass: int, iron: int, gold: int = 0) -> void:
	world.set_game_mode(1)
	check(world.credit_research_material_for_test(GLASS, glass), "creative Glass fixture credit")
	check(world.credit_research_material_for_test(IRON, iron), "creative Iron fixture credit")
	if gold > 0:
		check(world.credit_research_material_for_test(GOLD, gold), "creative Gold fixture credit")
	world.set_game_mode(0)


func _test_fresh_state_and_tree() -> void:
	var world: Variant = _world()
	var state: Dictionary = world.get_progression_state()
	check_equal(state.schema_version, 1, "progression schema v1")
	check_equal(state.game_mode, 0, "fresh mode is Progression")
	check_equal(state.glass + state.iron + state.gold, 0, "fresh reserves zero")
	check_equal(state.unlocked, ["foundation.basic_industry"], "only Foundation unlocked")
	var phase5_ids := [
		"foundation.basic_industry", "processing.dry_separation", "logistics.belt_drive_1",
		"furnace.fuel_economy_1", "processing.ferrous_separation", "furnace.throughput_1",
		"logistics.high_throughput_handling", "processing.precision_screening", "processing.concentrate_recovery",
	]
	var phase5_nodes := 0
	for definition: Dictionary in world.get_research_definitions():
		if str(definition.id) in phase5_ids:
			phase5_nodes += 1
	check_equal(phase5_nodes, 9, "nine Phase-5 research nodes remain intact")
	check(world.is_structure_unlocked(BANK), "Research Bank initially available")
	check(not world.is_structure_unlocked(SIEVE), "Sieve initially locked")
	check(not world.is_structure_unlocked(MAGNETIC), "Magnetic initially locked")
	check_equal(world.place_structure(SIEVE, Vector2i(0, 10)), 0, "native layer rejects locked Sieve")
	world.set_game_mode(1)
	check(world.place_structure(SIEVE, Vector2i(0, 10)) > 0, "explicit Creative override allows Sieve")


func _test_bank_accounting() -> void:
	var world: Variant = _world(55002)
	check(world.place_structure(BANK, Vector2i(0, 10)) > 0, "Bank placed in Progression")
	world.set_cell_with_metadata(Vector2i(3, 9), GLASS, 123, 456)
	world.step()
	var state: Dictionary = world.get_progression_state()
	check_equal(state.glass, 1, "single Glass deposit credits once")
	check_equal(world.get_cell(Vector2i(3, 9)), 0, "accepted physical cell consumed")
	world.step()
	check_equal(world.get_progression_state().glass, 1, "idle Bank cannot duplicate credit")
	var stats: Dictionary = world.get_bank_statistics()
	check_equal(stats.accepted_total, 1, "Bank lifetime accounting exact")
	check_equal(stats.banks_total, 1, "Bank counted independently")


func _test_bank_reject_and_blockage() -> void:
	var world: Variant = _world(55003)
	world.place_structure(BANK, Vector2i(0, 10))
	world.set_cell_with_metadata(Vector2i(3, 9), RESIDUE, 777, 33333)
	world.step()
	check_equal(world.get_progression_state().glass + world.get_progression_state().iron + world.get_progression_state().gold, 0, "invalid material grants no reserve")
	world.step()
	check_equal(world.get_cell(Vector2i(8, 14)), RESIDUE, "invalid material exits reject physically")
	check_equal(world.get_provenance(Vector2i(8, 14)), 777, "reject preserves provenance")
	check_equal(world.get_mineral_signature(Vector2i(8, 14)), 33333, "reject preserves signature")
	var blocked: Variant = _world(55004)
	blocked.place_structure(BANK, Vector2i(0, 10))
	blocked.set_cell(Vector2i(8, 14), 1)
	blocked.set_cell(Vector2i(8, 15), 1)
	blocked.set_cell(Vector2i(7, 14), 1)
	blocked.set_cell_with_metadata(Vector2i(3, 9), RESIDUE, 8, 9)
	blocked.step()
	blocked.step()
	blocked.set_cell_with_metadata(Vector2i(3, 9), GLASS, 4, 5)
	blocked.step()
	check_equal(blocked.get_cell(Vector2i(3, 9)), GLASS, "blocked reject stalls incoming factory")
	check_equal(blocked.get_progression_state().glass, 0, "blocked Bank cannot consume later input")
	check_equal(blocked.get_machine_state_at(Vector2i(0, 10)).state, 8, "Bank reports REJECT_BLOCKED")


func _test_multiple_banks_and_large_ledger() -> void:
	var world: Variant = _world(55005)
	world.place_structure(BANK, Vector2i(0, 10))
	world.place_structure(BANK, Vector2i(20, 10))
	world.set_cell(Vector2i(3, 9), GLASS)
	world.set_cell(Vector2i(23, 9), IRON)
	world.step()
	check_equal(world.get_progression_state().glass, 1, "Bank A contributes globally")
	check_equal(world.get_progression_state().iron, 1, "Bank B contributes globally")
	world.set_game_mode(1)
	check(world.credit_research_material_for_test(GLASS, 5000000000), "64-bit test deposit accepted")
	check_equal(world.get_progression_state().glass, 5000000001, "ledger exceeds 32-bit safely")
	var full: Variant = _world(55105)
	full.set_game_mode(1)
	check(full.credit_research_material_for_test(GLASS, 9223372036854775807), "ledger accepts signed 64-bit maximum")
	check(not full.credit_research_material_for_test(GLASS, 1), "ledger rejects overflow atomically")
	full.set_game_mode(0)
	full.place_structure(BANK, Vector2i(0, 10))
	full.set_cell(Vector2i(3, 9), GLASS)
	full.step()
	check_equal(full.get_cell(Vector2i(3, 9)), GLASS, "full ledger leaves physical deposit untouched")
	check_equal(full.get_progression_state().glass, 9223372036854775807, "full ledger never wraps")
	check_equal(full.get_machine_state_at(Vector2i(0, 10)).state, 9, "full ledger reports INPUT_BLOCKED")


func _test_research_atomicity_and_enforcement() -> void:
	var world: Variant = _world(55006)
	check(not world.try_unlock_research("processing.ferrous_separation"), "child prerequisite locked")
	check(not world.try_unlock_research("processing.dry_separation"), "insufficient purchase rejected")
	check_equal(world.get_progression_state().glass, 0, "failed purchase deducts nothing")
	_fund(world, 2400, 40)
	check(world.try_unlock_research("processing.dry_separation"), "exact Dry cost succeeds")
	check_equal(world.get_progression_state().glass + world.get_progression_state().iron, 0, "exact multi-material cost consumed atomically")
	check(not world.try_unlock_research("processing.dry_separation"), "already unlocked cannot spend twice")
	check(world.is_structure_unlocked(SIEVE), "Sieve placement unlock updates immediately")
	check(world.place_structure(SIEVE, Vector2i(0, 10)) > 0, "native placement succeeds after unlock")
	check(world.get_research_state("processing.ferrous_separation").available, "downstream node available immediately")
	_fund(world, 3000, 179)
	var before: Dictionary = world.serialize_progression_state()
	check(not world.try_unlock_research("processing.ferrous_separation"), "atomic cost rejects one-short Iron")
	check_equal(world.serialize_progression_state().glass, before.glass, "failed multi-cost preserves Glass")
	check_equal(world.serialize_progression_state().iron, before.iron, "failed multi-cost preserves Iron")


func _test_global_upgrades() -> void:
	var world: Variant = _world(55007)
	world.set_game_mode(1)
	world.place_structure(FURNACE, Vector2i(0, 10))
	world.place_conveyor_line(Vector2i(19, 10), Vector2i(22, 10), 1)
	world.set_game_mode(0)
	world.set_cell_with_metadata(Vector2i(120, 0), GLASS, 1234, 32123)
	world.set_cell(Vector2i(119, 1), 1)
	world.set_cell(Vector2i(120, 1), 1)
	world.set_cell(Vector2i(121, 1), 1)
	var produced_before: Dictionary = {"material": world.get_cell(Vector2i(120, 0)), "provenance": world.get_provenance(Vector2i(120, 0)), "signature": world.get_mineral_signature(Vector2i(120, 0))}
	_fund(world, 30000, 2000, 5)
	check(world.try_unlock_research("processing.dry_separation"), "Dry Separation unlock for upgrade graph")
	check(world.try_unlock_research("processing.ferrous_separation"), "Ferrous Separation unlock for upgrade graph")
	world.set_game_mode(1)
	world.place_structure(SIEVE, Vector2i(40, 10))
	world.place_structure(MAGNETIC, Vector2i(65, 10))
	world.set_game_mode(0)
	check(world.try_unlock_research("logistics.belt_drive_1"), "Belt Drive unlock")
	check(world.try_unlock_research("furnace.fuel_economy_1"), "Fuel Economy unlock")
	check(world.try_unlock_research("furnace.throughput_1"), "Furnace Throughput unlock")
	check(world.try_unlock_research("logistics.high_throughput_handling"), "High-Throughput Handling unlock")
	check(world.try_unlock_research("processing.precision_screening"), "Precision Screening unlock")
	check(world.try_unlock_research("processing.concentrate_recovery"), "Concentrate Recovery unlock")
	world.set_cell(Vector2i(-1, 14), 1)
	world.set_cell(Vector2i(-2, 14), 1)
	world.set_cell(Vector2i(-1, 16), 1)
	world.set_cell(Vector2i(-2, 16), 1)
	world.set_cell(Vector2i(-1, 13), COAL_CHUNK)
	world.set_cell_with_metadata(Vector2i(4, 9), RAW, 77, 12345)
	for _tick in 4:
		world.step()
	var machine: Dictionary = world.get_machine_state_at(Vector2i(0, 10))
	check(machine.physical, "existing Furnace remains a physical processor after research")
	check_equal(machine.process_ticks, 0, "existing Furnace exposes no hidden recipe timer")
	check_equal(world.get_machine_state_at(Vector2i(65, 10)).process_ticks, 0, "existing Magnet exposes no hidden recipe timer")
	world.set_game_mode(1)
	check(world.place_structure(FURNACE, Vector2i(90, 10)) > 0, "future Furnace placed after upgrades")
	check(world.place_structure(MAGNETIC, Vector2i(105, 10)) > 0, "future Magnetic placed after upgrades")
	world.set_game_mode(0)
	check(world.get_machine_state_at(Vector2i(90, 10)).physical, "future Furnace uses physical architecture")
	check(world.get_machine_state_at(Vector2i(105, 10)).physical, "future Magnet uses physical architecture")
	world.set_cell(Vector2i(20, 9), RAW)
	world.step()
	check_equal(world.get_cell(Vector2i(21, 9)), RAW, "existing Belt moves every upgraded tick")
	var profile := 16 | (10 << 5) | (7 << 10) | (4 << 13)
	var precision_signature := -1
	for signature in 65536:
		if world.process_material_for_test(RAW, profile, signature, 101) != world.process_material_for_test(RAW, profile, signature, 102):
			precision_signature = signature
			break
	check(precision_signature >= 0, "precision process has deterministic changed route")
	world.set_cell_with_metadata(Vector2i(43, 9), RAW, profile, precision_signature)
	world.step()
	check_equal(world.get_machine_state_at(Vector2i(40, 10)).result_waiting, 0, "existing Screen has no hidden result slot")
	check_equal(world.get_cell(Vector2i(120, 0)), produced_before.material, "upgrade does not mutate existing product material")
	check_equal(world.get_provenance(Vector2i(120, 0)), produced_before.provenance, "upgrade does not mutate existing provenance")
	check_equal(world.get_mineral_signature(Vector2i(120, 0)), produced_before.signature, "upgrade does not mutate existing signature")


func _test_serialization_and_determinism() -> void:
	var source: Variant = _world(55008)
	_fund(source, 5000, 500, 3)
	check(source.try_unlock_research("processing.dry_separation"), "serialization fixture unlock")
	var encoded: Dictionary = source.serialize_progression_state()
	var restored: Variant = _world(55008)
	check(restored.deserialize_progression_state(encoded), "progression deserialize succeeds")
	check_equal(restored.serialize_progression_state().glass, encoded.glass, "Glass round trip")
	check_equal(restored.serialize_progression_state().iron, encoded.iron, "Iron round trip")
	check_equal(restored.serialize_progression_state().gold, encoded.gold, "Gold round trip")
	check_equal(restored.serialize_progression_state().unlocked, encoded.unlocked, "unlock set round trip")
	var unsupported := encoded.duplicate(true)
	unsupported.schema_version = 2
	check(not restored.deserialize_progression_state(unsupported), "unsupported schema rejected")
	check_equal(restored.serialize_progression_state().unlocked, encoded.unlocked, "failed deserialize is atomic")


func _test_progression_pacing() -> void:
	var world: Variant = _world(55009)
	var profile: int = world.geology_profile_id_at(Vector2i(1200, 180))
	var pacing: Dictionary = world.evaluate_progression_pacing(profile, 200000)
	check(pacing.dry_separation_primitive.reached, "normal profile reaches Dry Separation")
	check(int(pacing.dry_separation_primitive.raw_sand) >= 3000 and int(pacing.dry_separation_primitive.raw_sand) <= 10000, "Dry pacing in 3k-10k target")
	check(pacing.ferrous_via_sieve.reached, "Sieve route reaches Ferrous")
	check(int(pacing.ferrous_via_sieve.raw_sand) < int(pacing.ferrous_primitive_comparison.raw_sand), "Sieve materially accelerates Ferrous")
	print("phase5_progression profile=%d pacing=%s" % [profile, pacing])


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func check_equal(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
