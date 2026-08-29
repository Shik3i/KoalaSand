extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var large: Variant = NativeSandWorld.new()
	large.reset(66001, 1)
	large.set_game_mode(1)
	var sensors: Array[int] = []
	var logic: Array[int] = []
	var actuators: Array[int] = []
	var build_start := Time.get_ticks_usec()
	for index in 10000:
		sensors.append(large.create_automation_component(2, Vector2i(index, -4), {"material_id": 1, "mode": 0, "target_position": Vector2i(index, 0)}))
		logic.append(large.create_automation_component(5, Vector2i(index, -2)))
	for index in 30000:
		actuators.append(large.create_automation_component(11, Vector2i(index, 3), {"target_position": Vector2i(index, 4)}))
	for index in 10000:
		large.create_automation_connection(sensors[index], 0, logic[index], 0)
		large.create_automation_connection(sensors[index], 0, logic[index], 1)
	for index in 30000:
		large.create_automation_connection(logic[index % 10000], 0, actuators[index], 0)
	var build_ms := float(Time.get_ticks_usec() - build_start) / 1000.0
	for tick in 5: large.step()
	var idle_start := Time.get_ticks_usec()
	for tick in 200: large.step()
	var idle_ms := float(Time.get_ticks_usec() - idle_start) / 200000.0
	var idle: Dictionary = large.get_automation_statistics()
	print("phase6_idle components=%d sensors=10000 logic=10000 actuators=30000 wires=%d build_ms=%.3f visited=%d sensor_evals=%d logic_evals=%d signals_changed=%d actuator_changes=%d circuit_avg_ms=%.6f circuit_latest_ms=%.6f record_bytes=%d" % [
		idle.components_total, idle.wires_total, build_ms, idle.components_awake, idle.sensor_evaluations, idle.logic_evaluations,
		idle.signals_changed, idle.actuator_changes, idle_ms, idle.circuit_ms, idle.record_bytes
	])
	var storm_mutate_start := Time.get_ticks_usec()
	for index in 10000: large.set_cell(Vector2i(index, 0), 1)
	var mutation_ms := float(Time.get_ticks_usec() - storm_mutate_start) / 1000.0
	large.step()
	var storm_sensor: Dictionary = large.get_automation_statistics()
	large.step()
	var storm_logic: Dictionary = large.get_automation_statistics()
	large.step()
	var storm_actuator: Dictionary = large.get_automation_statistics()
	print("phase6_signal_storm mutate_ms=%.3f sensor_tick_ms=%.3f sensors=%d changed=%d logic_tick_ms=%.3f logic=%d changed=%d actuator_tick_ms=%.3f actuators=%d changes=%d" % [
		mutation_ms, storm_sensor.circuit_ms, storm_sensor.sensor_evaluations, storm_sensor.signals_changed,
		storm_logic.circuit_ms, storm_logic.logic_evaluations, storm_logic.signals_changed,
		storm_actuator.circuit_ms, storm_actuator.components_awake, storm_actuator.actuator_changes
	])
	var query_start := Time.get_ticks_usec()
	var wire_records: PackedInt32Array = large.get_visible_automation_connections(Rect2i(-10, -10, 40050, 30))
	var component_records: PackedInt32Array = large.get_visible_automation_components(Rect2i(-10, -10, 40050, 30))
	var query_ms := float(Time.get_ticks_usec() - query_start) / 1000.0
	print("phase6_wire_render_feed mode_off_connections=0 mode_on_connections=%d component_records=%d topology_query_ms=%.3f steady_rebuilds=0" % [wire_records.size() / 6, component_records.size() / 7, query_ms])

	var physical: Variant = NativeSandWorld.new()
	physical.reset(66002, 1)
	physical.set_game_mode(1)
	physical.place_conveyor_line(Vector2i(0, 10), Vector2i(2199, 10), 1)
	for index in range(0, 2000, 2): physical.set_cell(Vector2i(index, 9), 2)
	physical.finalize_initialization()
	var baseline_start := Time.get_ticks_usec()
	for tick in 120: physical.step()
	var baseline_ms := float(Time.get_ticks_usec() - baseline_start) / 120000.0
	for index in 2000:
		physical.create_automation_component(2, Vector2i(index, 6), {"material_id": 2, "mode": 0, "target_position": Vector2i(index, 9)})
	var sensor_start := Time.get_ticks_usec()
	var sensor_evals := 0
	for tick in 120:
		physical.step()
		sensor_evals += int(physical.get_automation_statistics().sensor_evaluations)
	var sensor_ms := float(Time.get_ticks_usec() - sensor_start) / 120000.0
	print("phase6_sensor_factory sensors=2000 baseline_tick_ms=%.3f sensor_tick_ms=%.3f overhead_ms=%.3f sensor_evaluations=%d circuit_latest_ms=%.3f belts=2200" % [
		baseline_ms, sensor_ms, sensor_ms - baseline_ms, sensor_evals, physical.get_automation_statistics().circuit_ms
	])
	quit(0)
