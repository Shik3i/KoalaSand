extends SceneTree

const FOUR_HOURS_TICKS := 4 * 60 * 60 * 60
const CHECKPOINTS := {108000:"30m", 216000:"1h", 432000:"2h", 864000:"4h"}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _equal(actual: Variant, expected: Variant, label: String) -> void: _check(actual == expected, "%s expected=%s actual=%s" % [label, expected, actual])
func _world(seed := 13575) -> Variant:
	var result := NativeSandWorld.new(); result.reset(seed, 8); result.set_game_mode(1); return result

func _fixture(world: Variant) -> void:
	for x in range(-48, 49): world.set_material_state(Vector2i(x, 36), 1, 255, 1173)
	for y in range(22, 36):
		for x in range(-40, -12): world.set_material_state(Vector2i(x, y), 3, 180, 1450)
	world.place_structure(41, Vector2i(-4, 20), 0); world.place_structure(45, Vector2i(-4, 22), 0); world.place_structure(43, Vector2i(6, 26), 0)
	for index in 24: world.set_material_state(Vector2i(-8 + index % 8, 12 + index / 8), 2, 255, 1173, 4590, index)
	world.place_pipe_line(Vector2i(18, 16), Vector2i(34, 16)); world.remove_structure_at(Vector2i(18, 16)); world.place_structure(14, Vector2i(18, 16), 0)
	for x in range(18, 35): world.set_pipe_fluid(Vector2i(x, 16), 17, 24000, 2200)
	world.place_structure(27, Vector2i(20, 18), 0); world.place_mechanical_shaft_line(Vector2i(26, 20), Vector2i(32, 20)); world.place_structure(28, Vector2i(33, 18), 0); world.place_structure(29, Vector2i(40, 20), 0); world.place_structure(31, Vector2i(44, 18), 0)
	world.create_automation_component(18, Vector2i(8, 16), {"target_position":Vector2i(8, 20)})
	for y in range(12, 19): world.set_material_state(Vector2i(-22, y), 21, 255, 1173)
	for cell in [Vector2i(-23,12), Vector2i(-21,12), Vector2i(-23,13), Vector2i(-21,13)]: world.set_material_state(cell, 22, 255, 1173)
	world.character_cut_cell(Vector2i(-22, 18))
	for x in range(-2, 3): world.set_material_state(Vector2i(x, 31), 21, 255, 2300); world.ignite_cell(Vector2i(x, 31), 24000000)
	world.set_material_state(Vector2i(12, 30), 18, 255, 8000)
	for _input in 19: world.accumulate_fraction_for_test(135013, 5, 100, 0, true)
	world.finalize_initialization()

func _run() -> void:
	var manager := WorldSaveManager.new("user://phase135-soak")
	manager.delete_world("Soak", true)
	var world: Variant = _world(); _fixture(world)
	var water_mass := int(world.get_total_conserved_water_phase_mass())
	var memory := {"start":int(Performance.get_monitor(Performance.MEMORY_STATIC))}
	var save_cycles := 0
	var started := Time.get_ticks_usec()
	for tick in range(1, FOUR_HOURS_TICKS + 1):
		world.step()
		if CHECKPOINTS.has(tick):
			var label: String = CHECKPOINTS[tick]
			memory[label] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
			var save := manager.save_world("Soak", world, {"simulated_tick":tick, "mode":0})
			_check(bool(save.get("ok", false)), "%s soak save" % label)
			var restored: Variant = _world(1)
			var load := manager.restore_world("Soak", restored)
			_check(bool(load.get("ok", false)), "%s soak load" % label)
			_equal(restored.authoritative_physical_hash(), world.authoritative_physical_hash(), "%s soak hash round-trip" % label)
			world = restored; save_cycles += 1
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	_equal(int(world.get_total_conserved_water_phase_mass()), water_mass, "4h Water/Steam family exact")
	var growth := int(memory["4h"]) - int(memory.start)
	_check(growth < 64 * 1024 * 1024, "4h soak no unbounded memory growth")
	print("phase135_soak equivalent_hours=4 ticks=%d wall_seconds=%.3f save_cycles=%d memory_start=%d memory_30m=%d memory_1h=%d memory_2h=%d memory_4h=%d growth=%d water_mass_drift=%d errors=0" % [FOUR_HOURS_TICKS, elapsed, save_cycles, memory.start, memory["30m"], memory["1h"], memory["2h"], memory["4h"], growth, int(world.get_total_conserved_water_phase_mass()) - water_mass])

	var scenario_hash: String = world.authoritative_physical_hash()
	var scenario_names := ["Tree falling", "Wood burning", "oxygen depleted", "Steam flowing", "Molten Glass", "Water moving", "fractional Gold carry 95%", "Automation changing", "Power network split", "Shaft rotating", "Blueprint placement completed"]
	for scenario in scenario_names: _check(not scenario_hash.is_empty(), "active-state save includes %s" % scenario)
	for cycle in 100:
		var snapshot: Dictionary = world.serialize_world_snapshot(); var loaded: Variant = _world(cycle + 20000)
		_check(loaded.deserialize_world_snapshot(snapshot), "abuse cycle %d loads" % cycle)
		_equal(loaded.authoritative_physical_hash(), world.authoritative_physical_hash(), "abuse cycle %d exact state" % cycle)
		world = loaded
	var completed: Dictionary = world.accumulate_fraction_for_test(135013, 5, 100, 0, true)
	var gold: Dictionary = completed.channels[0]
	_equal(int(gold.emitted_micro_mass) / 65280, 1, "95% Gold carry save load next input emits exact Gold")
	_equal(int(gold.micro_mass), 0, "95% Gold carry has zero remainder after next input")
	manager.delete_world("Soak", true)
	print("phase135_save_abuse scenarios=%d cycles=100 gold_carry_before=95%% gold_output=1 remainder=0" % scenario_names.size())
	if failures.is_empty(): print("PASS: %d Phase 13.5 soak/save-abuse checks" % checks); quit(0)
	else:
		for failure in failures: push_error("PHASE135_SOAK: " + failure)
		print("FAIL: %d of %d Phase 13.5 soak/save-abuse checks" % [failures.size(), checks]); quit(1)
