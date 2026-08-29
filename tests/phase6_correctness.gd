extends SceneTree

const CHARCOAL := 23

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_definitions_and_research()
	_test_delay_fanout_disconnect_cycle()
	_test_boolean_and_comparator()
	_test_material_sensor()
	_test_level_sensor()
	_test_conveyor_and_gate()
	_test_machine_control_and_sensor()
	_test_timer_and_latch()
	_test_serialization_and_determinism()
	if failures.is_empty():
		print("PASS: %d checks across 9 Phase 6 automation suites" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d checks failed" % [failures.size(), checks])
	quit(1)

func _world(seed: int = 6001) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world

func _test_definitions_and_research() -> void:
	var world: Variant = _world()
	_check_equal(world.get_automation_definitions().size(), 24, "21 prior plus 3 Power automation definitions")
	_check_equal(world.get_research_definitions().size(), 35, "33 prior plus Wood Processing and Cookware nodes; Combustion Control deferred without a Vent/Fan/Grate")
	var ids: Dictionary = {}
	for definition: Dictionary in world.get_research_definitions(): ids[definition.id] = definition
	for research_id in ["automation.basic_sensing", "automation.logic_control", "automation.machine_control", "automation.advanced_routing", "automation.timed_control"]:
		_check(ids.has(research_id), "research exists: %s" % research_id)
	_check_equal(ids["automation.basic_sensing"].costs, {"glass": 800, "iron": 15, "gold": 0}, "basic sensing tuned cost")
	_check_equal(ids["automation.advanced_routing"].costs.gold, 1, "advanced routing has small Gold cost")
	world.set_game_mode(0)
	_check_equal(world.create_automation_component(1, Vector2i.ZERO), 0, "locked component rejected by native layer")

func _test_delay_fanout_disconnect_cycle() -> void:
	var world: Variant = _world()
	var source: int = world.create_automation_component(1, Vector2i(0, 0))
	var first: int = world.create_automation_component(4, Vector2i(2, 0))
	var second: int = world.create_automation_component(4, Vector2i(2, 2))
	var wire_a: int = world.create_automation_connection(source, 0, first, 0)
	var wire_b: int = world.create_automation_connection(source, 0, second, 0)
	_check(wire_a > 0 and wire_b > 0, "fan-out accepts two downstream inputs")
	_check_equal(world.create_automation_connection(second, 0, first, 0), 0, "one source per input enforced")
	world.step()
	world.set_manual_switch(source, true)
	world.step()
	_check_equal(world.get_automation_component_state(first).output, 1, "downstream still reads previous committed input")
	world.step()
	_check_equal(world.get_automation_component_state(first).output, 0, "one-stage signal arrives next tick")
	_check_equal(world.get_automation_component_state(second).output, 0, "fan-out values identical")
	_check(world.remove_automation_connection(wire_a), "wire disconnect succeeds")
	world.set_manual_switch(source, false)
	world.step(); world.step()
	_check_equal(world.get_automation_component_state(first).input_a, 0, "disconnected input resets to zero")
	_check_equal(world.get_automation_component_state(second).output, 1, "remaining fan-out branch still propagates")
	var cycle_a: int = world.create_automation_component(4, Vector2i(6, 0))
	var cycle_b: int = world.create_automation_component(4, Vector2i(8, 0))
	world.create_automation_connection(cycle_a, 0, cycle_b, 0)
	world.create_automation_connection(cycle_b, 0, cycle_a, 0)
	for tick in 200: world.step()
	_check(world.get_automation_statistics().components_awake <= 2, "cycle remains bounded without recursion")
	_check(world.automation_state_hash().length() == 8, "cycle produces deterministic hash")

func _test_boolean_and_comparator() -> void:
	var world: Variant = _world()
	var not_id: int = world.create_automation_component(4, Vector2i.ZERO)
	var and_id: int = world.create_automation_component(5, Vector2i.ZERO)
	var or_id: int = world.create_automation_component(6, Vector2i.ZERO)
	for value in [-2147483647, -9, 0, 1, 2147483647]:
		world.set_automation_input_for_test(not_id, 0, value); world.step()
		_check_equal(world.get_automation_component_state(not_id).output, 1 if value == 0 else 0, "NOT arbitrary int32 %d" % value)
	for pair in [[0, 0], [0, -5], [7, 0], [-3, 9]]:
		world.set_automation_input_for_test(and_id, 0, pair[0]); world.set_automation_input_for_test(and_id, 1, pair[1])
		world.set_automation_input_for_test(or_id, 0, pair[0]); world.set_automation_input_for_test(or_id, 1, pair[1]); world.step()
		_check_equal(world.get_automation_component_state(and_id).output, 1 if pair[0] != 0 and pair[1] != 0 else 0, "AND truth table %s" % [pair])
		_check_equal(world.get_automation_component_state(or_id).output, 1 if pair[0] != 0 or pair[1] != 0 else 0, "OR truth table %s" % [pair])
	for operator in 6:
		var comparator: int = world.create_automation_component(7, Vector2i(operator, 2), {"operator": operator, "threshold": 0})
		for value in [-2147483647, -1, 0, 1, 2147483647]:
			world.set_automation_input_for_test(comparator, 0, value); world.step()
			var expected: Array[bool] = [value > 0, value >= 0, value < 0, value <= 0, value == 0, value != 0]
			_check_equal(world.get_automation_component_state(comparator).output, 1 if expected[operator] else 0, "Comparator op %d value %d" % [operator, value])

func _test_material_sensor() -> void:
	var world: Variant = _world()
	for x in range(-2, 5): world.set_cell(Vector2i(x, 2), 1)
	var present: int = world.create_automation_component(2, Vector2i.ZERO, {"material_id": 12, "mode": 0, "probe_size": Vector2i(3, 1), "target_position": Vector2i(-1, 1)})
	var count: int = world.create_automation_component(2, Vector2i.ZERO, {"material_id": 12, "mode": 1, "probe_size": Vector2i(3, 1), "target_position": Vector2i(-1, 1)})
	var pulse: int = world.create_automation_component(2, Vector2i.ZERO, {"material_id": 12, "mode": 2, "probe_size": Vector2i(1, 1), "target_position": Vector2i(64, -1)})
	world.set_cell(Vector2i(63, 0), 1); world.set_cell(Vector2i(64, 0), 1); world.set_cell(Vector2i(65, 0), 1)
	world.step()
	_check_equal(world.get_automation_component_state(present).output, 0, "Material PRESENT empty")
	world.set_cell(Vector2i(0, 1), 12); world.set_cell(Vector2i(1, 1), 12); world.step()
	_check_equal(world.get_automation_component_state(present).output, 1, "Material PRESENT detects visible Gold ID")
	_check_equal(world.get_automation_component_state(count).output, 2, "Material COUNT exact")
	world.set_cell(Vector2i(64, -1), 12); world.step()
	_check_equal(world.get_automation_component_state(pulse).output, 1, "Material PULSE rises at cross-chunk negative coordinate")
	world.step()
	_check_equal(world.get_automation_component_state(pulse).output, 0, "Material PULSE lasts one tick")
	var before := int(world.get_automation_statistics().sensor_evaluations)
	world.step()
	_check_equal(world.get_automation_statistics().sensor_evaluations, 0, "unchanged material sensors sleep")
	_check(before >= 1, "sensor wake was localized")
	world.set_cell_with_metadata(Vector2i(2, 1), 2, 65535, 65535); world.step()
	_check_equal(world.get_automation_component_state(present).output, 1, "hidden provenance does not match Gold sensor")
	for wall in [Vector2i(19, 20), Vector2i(19, 21), Vector2i(19, 22), Vector2i(19, 23), Vector2i(20, 23), Vector2i(21, 20), Vector2i(21, 21), Vector2i(21, 22), Vector2i(21, 23)]: world.place_structure(9, wall)
	var vertical: int = world.create_automation_component(2, Vector2i.ZERO, {"material_id": 12, "mode": 1, "probe_size": Vector2i(3, 1), "orientation": 1, "target_position": Vector2i(20, 20)})
	for y in range(20, 23): world.set_cell(Vector2i(20, y), 12)
	world.step()
	_check_equal(world.get_automation_component_state(vertical).output, 3, "Material probe orientation rotates 3x1 to vertical")
	for x in range(30, 33): world.place_structure(9, Vector2i(x, 11))
	var crossing: int = world.create_automation_component(2, Vector2i.ZERO, {"material_id": 12, "mode": 2, "probe_size": Vector2i(3, 1), "target_position": Vector2i(30, 10)})
	world.set_cell(Vector2i(30, 10), 12); world.step(); world.step()
	world.set_cell(Vector2i(30, 10), 0); world.set_cell(Vector2i(31, 10), 12); world.step()
	_check_equal(world.get_automation_component_state(crossing).output, 1, "Material PULSE detects entry when probe count is unchanged")

func _test_level_sensor() -> void:
	var world: Variant = _world()
	var sensor: int = world.create_automation_component(3, Vector2i.ZERO, {"mode": 1, "probe_size": Vector2i(2, 2), "target_position": Vector2i(10, 10)})
	world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 0, "empty fill percent is zero")
	for y in 2:
		for x in 2: world.set_cell(Vector2i(10 + x, 10 + y), 1)
	world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 1000, "full fill percent uses 0..1000 scale")
	world.set_cell(Vector2i(10, 10), 0); world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 750, "removal updates cached watched region")
	world.configure_automation_component(sensor, {"mode": 0, "probe_size": Vector2i(2, 2), "target_position": Vector2i(10, 10)}); world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 3, "Level COUNT reports occupied cells")
	world.configure_automation_component(sensor, {"mode": 2, "probe_size": Vector2i(2, 2), "target_position": Vector2i(10, 10), "threshold": 700}); world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 1, "ABOVE_THRESHOLD works")
	world.configure_automation_component(sensor, {"mode": 3, "probe_size": Vector2i(2, 2), "target_position": Vector2i(10, 10), "threshold": 800}); world.step()
	_check_equal(world.get_automation_component_state(sensor).output, 1, "BELOW_THRESHOLD works")
	world.place_structure(4, Vector2i(40, 10))
	var bin_sensor: int = world.create_automation_component(3, Vector2i.ZERO, {"mode": 0, "probe_size": Vector2i(1, 6), "target_position": Vector2i(41, 11)})
	for y in range(11, 17): world.set_cell(Vector2i(41, y), 1)
	world.step()
	_check_equal(world.get_automation_component_state(bin_sensor).output, 6, "Level Sensor counts physical Storage Bin interior")

func _test_conveyor_and_gate() -> void:
	var world: Variant = _world()
	world.place_structure(2, Vector2i(0, 1))
	world.set_cell(Vector2i(-1, 1), 1)
	world.set_cell(Vector2i(1, 1), 1)
	var control: int = world.create_automation_component(11, Vector2i(-2, 1), {"target_position": Vector2i(0, 1)})
	world.set_automation_input_for_test(control, 0, 0); world.step()
	world.set_cell(Vector2i(0, 0), 2)
	for tick in 3: world.step()
	_check_equal(world.get_cell(Vector2i(0, 0)), 2, "controlled Conveyor signal 0 stops transport")
	_check_equal(world.get_structure(Vector2i(0, 1)), 2, "disabled Conveyor remains physical support")
	world.set_automation_input_for_test(control, 0, 1); world.step(); world.step(); world.step()
	_check_equal(world.get_cell(Vector2i(1, 0)), 2, "controlled Conveyor signal 1 resumes transport")
	world.place_structure(9, Vector2i(10, 10))
	var gate: int = world.create_automation_component(13, Vector2i(10, 8), {"target_position": Vector2i(10, 10)})
	world.set_automation_input_for_test(gate, 0, 1); world.step()
	_check(world.get_automation_component_state(gate).gate_actual_open, "gate opens and collision retracts")
	world.set_cell(Vector2i(9, 11), 1); world.set_cell(Vector2i(10, 11), 1); world.set_cell(Vector2i(11, 11), 1)
	world.set_cell(Vector2i(10, 10), 2)
	world.set_automation_input_for_test(gate, 0, 0); world.step()
	var blocked: Dictionary = world.get_automation_component_state(gate)
	_check(blocked.gate_actual_open and blocked.gate_close_blocked, "occupied gate reports CLOSE_BLOCKED and stays open")
	_check_equal(world.get_cell(Vector2i(10, 10)), 2, "blocked close never deletes material")
	world.set_cell(Vector2i(10, 10), 0); world.step()
	_check(not world.get_automation_component_state(gate).gate_actual_open, "gate closes after cell becomes empty")
	_check_equal(world.remove_structure_at(Vector2i(10, 10)), 1, "tile-like Control Gate can be removed")
	_check(world.get_automation_component_state(gate).is_empty(), "removing Control Gate removes its attached actuator")

func _test_machine_control_and_sensor() -> void:
	var world: Variant = _world()
	var machine_id: int = world.place_structure(5, Vector2i(20, 20))
	var control: int = world.create_automation_component(12, Vector2i(16, 20), {"target_machine_id": machine_id, "target_position": Vector2i(20, 20)})
	var sensor: int = world.create_automation_component(8, Vector2i(17, 17), {"mode": 10, "target_position": Vector2i(20, 20)})
	world.set_automation_input_for_test(control, 0, 0); world.step(); world.step()
	_check_equal(world.get_machine_state_at(Vector2i(20, 20)).state, 10, "machine ENABLE 0 produces DISABLED state")
	_check_equal(world.get_automation_component_state(sensor).output, 1, "Machine State Sensor reports DISABLED")
	for x in range(21, 29): world.set_cell(Vector2i(x, 24), 1)
	world.set_cell(Vector2i(24, 23), 2)
	var cold: int = world.get_temperature(Vector2i(24, 23))
	for tick in 4: world.step()
	_check_equal(world.get_temperature(Vector2i(24, 23)), cold, "disabled physical Furnace applies no heat")
	_check_equal(world.get_cell(Vector2i(24, 23)), 2, "disabled physical Furnace cannot react or consume the grain")
	world.set_material_state(Vector2i(22, 23), CHARCOAL, 255, 3000)
	world.set_automation_input_for_test(control, 0, 1); world.step(); world.step()
	_check(world.get_machine_state_at(Vector2i(20, 20)).state != 10, "machine ENABLE nonzero resumes")
	_check(world.get_temperature(Vector2i(24, 23)) > cold, "enabled physical Furnace resumes local heating")
	var running: int = world.create_automation_component(8, Vector2i(18, 17), {"mode": 3, "target_position": Vector2i(20, 20)})
	world.step()
	_check_equal(world.get_automation_component_state(running).output, 1, "Machine State Sensor reports active physical processor")

	var bank: Variant = _world(6103)
	bank.place_structure(8, Vector2i(0, 10))
	var reject_blocked: int = bank.create_automation_component(8, Vector2i(-2, 8), {"mode": 8, "target_position": Vector2i(0, 10)})
	bank.set_cell(Vector2i(8, 14), 1); bank.set_cell(Vector2i(8, 15), 1); bank.set_cell(Vector2i(7, 14), 1)
	bank.set_cell_with_metadata(Vector2i(3, 9), 8, 8, 9)
	bank.step(); bank.step()
	_check_equal(bank.get_automation_component_state(reject_blocked).output, 1, "Machine State Sensor reports Research Bank REJECT_BLOCKED")

func _test_timer_and_latch() -> void:
	var world: Variant = _world()
	var timer: int = world.create_automation_component(9, Vector2i.ZERO, {"mode": 0, "period_ticks": 3})
	world.set_automation_input_for_test(timer, 0, 1)
	world.step(); _check_equal(world.get_automation_component_state(timer).output, 0, "delay timer tick 1")
	world.step(); _check_equal(world.get_automation_component_state(timer).output, 0, "delay timer tick 2")
	world.step(); _check_equal(world.get_automation_component_state(timer).output, 1, "delay timer exact tick 3")
	var repeating: int = world.create_automation_component(9, Vector2i.ZERO, {"mode": 2, "period_ticks": 4, "on_ticks": 2})
	world.set_automation_input_for_test(repeating, 0, 1)
	var pattern: Array[int] = []
	for tick in 8:
		world.step(); pattern.append(world.get_automation_component_state(repeating).output)
	_check_equal(pattern, [1, 0, 0, 1, 1, 0, 0, 1], "repeating timer deterministic simulation-tick pattern")
	var latch: int = world.create_automation_component(10, Vector2i.ZERO)
	world.set_automation_input_for_test(latch, 0, 1); world.step()
	_check_equal(world.get_automation_component_state(latch).output, 1, "Latch SET")
	world.set_automation_input_for_test(latch, 1, 1); world.step()
	_check_equal(world.get_automation_component_state(latch).output, 0, "Latch RESET wins simultaneous SET/RESET")

func _test_serialization_and_determinism() -> void:
	var first: Variant = _world(6010)
	var switch_id: int = first.create_automation_component(1, Vector2i(-4, 3), {"enabled": true})
	var latch_id: int = first.create_automation_component(10, Vector2i(2, 3))
	first.create_automation_connection(switch_id, 0, latch_id, 0)
	for tick in 3: first.step()
	var serialized: Dictionary = first.serialize_automation_state()
	var second: Variant = _world(9999)
	_check(second.deserialize_automation_state(serialized), "automation state round-trip loads")
	_check_equal(second.serialize_automation_state(), serialized, "automation serialization round-trip exact")
	_check_equal(second.automation_state_hash(), first.automation_state_hash(), "automation round-trip hash identical")
	for tick in 100:
		first.step(); second.step()
	_check_equal(second.automation_state_hash(), first.automation_state_hash(), "automation deterministic replay hash")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s: expected %s, got %s" % [label, expected, actual])
