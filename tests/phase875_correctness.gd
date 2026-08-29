extends SceneTree

const SAND := 2
const CONVEYOR_RIGHT := 2

var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int = 8751) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 8)
	world.set_game_mode(1)
	world.allocate_chunk_rect(Rect2i(-4, -4, 8, 8))
	return world


func _run() -> void:
	_command_batch_and_history()
	_blueprints()
	_subsurface_layout()
	_subsurface_transport()
	_subsurface_serialization_and_determinism()
	_foundation_contracts_and_statistics()
	if failures.is_empty():
		print("PASS: %d checks across 6 Phase 8.75 suites" % checks)
		print("phase875_hashes command_batch=%s command_replay=%s blueprint=%s tunnel_replay=%s" % [evidence.command_batch, evidence.command_replay, evidence.blueprint, evidence.tunnel_replay])
		quit(0)
		return
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d Phase 8.75 checks failed" % [failures.size(), checks])
	quit(1)


func _command_batch_and_history() -> void:
	var world: Variant = _world()
	var bus := WorldCommandBus.new()
	var batch := CommandBatch.new("grid", 7, 1, "Grid", CommandBatch.ValidationMode.ATOMIC)
	for x in 100:
		batch.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": CONVEYOR_RIGHT, "x": x, "y": 0, "orientation": 0}))
	var roundtrip := CommandBatch.deserialize(batch.serialize())
	evidence.command_batch = batch.content_hash()
	_check(roundtrip != null and roundtrip.content_hash() == batch.content_hash(), "CommandBatch deterministic roundtrip")
	var result := bus.submit_batch(world, batch)
	_check_equal(result.applied, 100, "native structure batch applies ordered grid")
	_check_equal(result.rejected, 0, "native structure batch has no rejects")
	_check(result.has("validation_usec") and result.has("application_usec") and result.has("affected_region"), "compact batch result contract")
	var replay_world: Variant = _world()
	var replay_bus := WorldCommandBus.new()
	_check(replay_bus.replay_batches(replay_world, bus.serialize_batch_log()), "CommandBatch log replays")
	_check_equal(replay_world.authoritative_physical_hash(), world.authoritative_physical_hash(), "CommandBatch replay reaches identical physical hash")
	evidence.command_replay = replay_world.authoritative_physical_hash()
	var conflict := CommandBatch.new("conflict", 7, 2, "Atomic conflict", CommandBatch.ValidationMode.ATOMIC)
	conflict.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": CONVEYOR_RIGHT, "x": 200, "y": 0}))
	conflict.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": CONVEYOR_RIGHT, "x": 200, "y": 0}))
	result = bus.submit_batch(world, conflict)
	_check_equal(result.applied, 0, "atomic conflict applies nothing")
	_check_equal(world.get_structure(Vector2i(200, 0)), 0, "atomic conflict leaves world unchanged")
	var remove := CommandBatch.new("remove", 7, 3, "Remove", CommandBatch.ValidationMode.ATOMIC)
	var replace := CommandBatch.new("replace", 7, 4, "Replace", CommandBatch.ValidationMode.ATOMIC)
	remove.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": 10, "y": 0}))
	replace.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": CONVEYOR_RIGHT, "x": 10, "y": 0}))
	var history := ConstructionHistory.new(2)
	result = history.execute(world, bus, remove, replace)
	_check_equal(world.get_structure(Vector2i(10, 0)), 0, "construction history executes")
	history.undo(world, bus)
	_check_equal(world.get_structure(Vector2i(10, 0)), CONVEYOR_RIGHT, "construction undo restores command effect")
	history.redo(world, bus)
	_check_equal(world.get_structure(Vector2i(10, 0)), 0, "construction redo reapplies command effect")
	var pipe_history := ConstructionHistory.new()
	var pipe_forward := CommandBatch.new("pipe", 7, 5, "Pipe", CommandBatch.ValidationMode.ATOMIC)
	pipe_forward.add(WorldCommand.new(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": 0, "y0": 20, "x1": 4, "y1": 20}))
	var pipe_inverse := CommandBatch.new("undo-pipe", 7, 5, "Undo Pipe", CommandBatch.ValidationMode.ATOMIC)
	for x in 5: pipe_inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": x, "y": 20}))
	pipe_history.execute(world, bus, pipe_forward, pipe_inverse)
	_check(world.get_structure(Vector2i(2, 20)) > 0, "Pipe construction history executes")
	pipe_history.undo(world, bus)
	_check_equal(world.get_structure(Vector2i(2, 20)), 0, "Pipe construction undo removes current structure")
	var source := int(world.create_automation_component(1, Vector2i(0, 30), {"enabled": true}))
	var target := int(world.create_automation_component(6, Vector2i(2, 30), {}))
	var connection := int(world.create_automation_connection(source, 0, target, 0))
	var wire_history := ConstructionHistory.new()
	var wire_remove := CommandBatch.new("wire-remove", 7, 6, "Remove Wire", CommandBatch.ValidationMode.ATOMIC)
	wire_remove.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_CONNECTION, {"connection_id": connection}))
	var wire_restore := CommandBatch.new("wire-restore", 7, 6, "Restore Wire", CommandBatch.ValidationMode.ATOMIC)
	wire_restore.add(WorldCommand.new(WorldCommand.Type.CREATE_AUTOMATION_CONNECTION, {"source_component": source, "source_port": 0, "target_component": target, "target_port": 0}))
	wire_history.execute(world, bus, wire_remove, wire_restore)
	_check_equal(world.get_automation_statistics().wires_total, 0, "wire removal history executes")
	wire_history.undo(world, bus)
	_check_equal(world.get_automation_statistics().wires_total, 1, "wire undo restores topology without rewinding physics")
	var blueprint_history := ConstructionHistory.new()
	var blueprint := BlueprintDefinition.new("undo-blueprint", "Undo", "")
	blueprint.add_structure(1, CONVEYOR_RIGHT, Vector2i.ZERO)
	blueprint.add_structure(2, CONVEYOR_RIGHT, Vector2i(1, 0))
	var blueprint_forward := blueprint.instantiate(Vector2i(20, 20), 7, 7)
	var blueprint_inverse := CommandBatch.new("undo-blueprint", 7, 7, "Undo Blueprint", CommandBatch.ValidationMode.ATOMIC)
	blueprint_inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": 20, "y": 20}))
	blueprint_inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": 21, "y": 20}))
	blueprint_history.execute(world, bus, blueprint_forward, blueprint_inverse)
	blueprint_history.undo(world, bus)
	_check_equal(world.get_structure(Vector2i(20, 20)), 0, "Blueprint undo uses one inverse batch")


func _blueprints() -> void:
	var blueprint := BlueprintDefinition.new("splitter", "Splitter", "Relative IDs")
	blueprint.add_structure(2, CONVEYOR_RIGHT, Vector2i(2, 0), 0)
	blueprint.add_structure(1, CONVEYOR_RIGHT, Vector2i.ZERO, 0)
	blueprint.add_subsurface_channel(3, 1, Vector2i(0, 2), Vector2i(8, 2))
	blueprint.add_automation_component(10, 1, Vector2i(0, 5), {"enabled": true, "target_position": Vector2i(1, 6)})
	blueprint.add_automation_component(11, 6, Vector2i(2, 5), {})
	blueprint.add_connection(10, 0, 11, 0)
	var restored := BlueprintDefinition.deserialize(blueprint.serialize())
	evidence.blueprint = blueprint.content_hash()
	_check(restored != null and restored.content_hash() == blueprint.content_hash(), "Blueprint deterministic roundtrip")
	var rotated := blueprint.transformed(1, false, false)
	_check_equal(rotated.entries[0].position, Vector2i(0, 2), "Blueprint rotate transforms position")
	_check_equal(rotated.entries[2].configuration.target_position, Vector2i(-6, 1), "Blueprint rotate transforms automation target")
	var flipped := blueprint.transformed(0, true, false)
	_check_equal(flipped.entries[0].position, Vector2i(-2, 0), "Blueprint horizontal flip transforms position")
	var batch := restored.instantiate(Vector2i(40, 40), 9, 11)
	_check_equal(batch.commands[0].payload.relative_id, 1, "Blueprint instance canonicalizes relative IDs")
	_check_equal(batch.commands[2].payload.configuration.target_position, Vector2i(41, 46), "Blueprint instance resolves automation target relative to paste origin")
	var world: Variant = _world(8760)
	var result := WorldCommandBus.new().submit_batch(world, batch)
	_check_equal(result.rejected, 0, "Blueprint applies automation and linked entries")
	_check(result.relative_id_map.has(10) and result.relative_id_map.has(11), "Blueprint remaps automation relative IDs")
	_check_equal(world.get_automation_statistics().wires_total, 1, "Blueprint remapped wire connects allocated components")
	var debug_script: Script = load("res://debug/debug_world.gd")
	_check_equal(debug_script.blueprint_selection_rect(Vector2i(8, 6), Vector2i(3, 2)), Rect2i(3, 2, 6, 5), "rectangular Blueprint selection is inclusive in every drag direction")
	var debug_world: Node2D = debug_script.new()
	debug_world.world = world
	var captured: Dictionary = debug_world._capture_blueprint_region(Rect2i(39, 39, 11, 8))
	var captured_blueprint: BlueprintDefinition = captured.blueprint
	_check_equal(captured_blueprint.entries.size(), 4, "region copy captures structures and automation components once")
	_check_equal(captured_blueprint.connections.size(), 1, "region copy captures internal automation wires")
	_check_equal(captured_blueprint.subsurface_channels.size(), 1, "region copy captures fully enclosed Subsurface Channels")
	debug_world.free()
	var library := BlueprintLibrary.new(16)
	for index in 20:
		var item := BlueprintDefinition.new("bp-%d" % index, "BP", "")
		item.add_structure(1, CONVEYOR_RIGHT, Vector2i(index, 0))
		library.copy_to_clipboard(item)
	_check_equal(library.clipboard_history.size(), 16, "Blueprint clipboard history is bounded")
	_check(library.save(blueprint) and library.load_blueprint("splitter").content_hash() == blueprint.content_hash(), "in-memory Blueprint library")
	var library_copy := BlueprintLibrary.new()
	_check(library_copy.deserialize_state(library.serialize()), "Blueprint library serialized roundtrip")


func _subsurface_layout() -> void:
	var world: Variant = _world(8752)
	var first := int(world.place_subsurface_channel(0, Vector2i(0, 0), Vector2i(10, 0)))
	_check(first > 0, "depth I channel placed")
	_check_equal(world.get_structure(Vector2i(0, 0)), 18, "depth I entrance physical mouth")
	_check_equal(world.get_structure(Vector2i(10, 0)), 19, "depth I exit physical mouth")
	_check_equal(world.get_subsurface_channel_state(first).lane_cells, 9, "finite one-packet-per-spatial-cell lane")
	_check_equal(world.place_subsurface_channel(0, Vector2i(5, -5), Vector2i(5, 5)), 0, "same-depth overlap rejected")
	var crossing := int(world.place_subsurface_channel(1, Vector2i(5, -5), Vector2i(5, 5)))
	_check(crossing > 0, "different depths cross")
	_check_equal(world.get_subsurface_statistics().packet_bytes, 8, "compact full-state MaterialPacket")
	_check_equal(world.get_visible_subsurface_routes(Rect2i(-20, -20, 40, 40)).size(), 20, "visible route records for two channels")
	var occupied := int(world.place_subsurface_channel(2, Vector2i(0, 20), Vector2i(4, 20)))
	_check(world.seed_subsurface_packet_for_test(occupied, 0, SAND, 4321, 27, 99), "seed packet carries full state")
	_check(not world.remove_subsurface_channel(occupied, ConstructionPlanner.RemovalPolicy.MUST_DRAIN), "occupied channel enforces MUST_DRAIN")
	var component := int(world.create_automation_component(1, Vector2i(12, 20), {"enabled": true}))
	var unsafe_undo := CommandBatch.new("unsafe-tunnel-undo", 7, 12, "Unsafe tunnel undo", CommandBatch.ValidationMode.ATOMIC)
	unsafe_undo.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, {"component_id": component}))
	unsafe_undo.add(WorldCommand.new(WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL, {"channel_id": occupied, "removal_policy": ConstructionPlanner.RemovalPolicy.MUST_DRAIN}))
	var unsafe_result := WorldCommandBus.new().submit_batch(world, unsafe_undo)
	_check_equal(unsafe_result.applied, 0, "occupied tunnel rejects mixed atomic Undo before mutation")
	_check(not world.get_automation_component_state(component).is_empty(), "rejected mixed atomic Undo preserves earlier component")


func _subsurface_transport() -> void:
	var world: Variant = _world(8753)
	var channel := int(world.place_subsurface_channel(0, Vector2i(0, 0), Vector2i(6, 0)))
	world.set_cell(Vector2i(-2, 1), 1)
	world.set_cell(Vector2i(-1, 1), 1)
	world.set_cell(Vector2i(0, 1), 1)
	world.set_cell(Vector2i(7, 1), 1)
	world.set_cell_with_metadata(Vector2i(-1, 0), SAND, 33, 1234)
	for tick in 6:
		world.step()
	_check_equal(world.get_cell(Vector2i(7, 0)), SAND, "packet exits only beyond physical mouth")
	_check_equal(world.get_provenance(Vector2i(7, 0)), 33, "subsurface preserves uint16 provenance")
	_check_equal(world.get_mineral_signature(Vector2i(7, 0)), 1234, "subsurface preserves mineral signature")
	world.set_cell(Vector2i(7, 0), 1)
	for lane_index in 5:
		world.seed_subsurface_packet_for_test(channel, lane_index, SAND, 1173, lane_index, lane_index)
	world.step()
	var state: Dictionary = world.get_subsurface_channel_state(channel)
	_check(state.jammed and state.occupied_packets == 5, "blocked output creates local backpressure without loss")
	_check(world.get_subsurface_statistics().blocked > 0, "jam reports blocked work")


func _subsurface_serialization_and_determinism() -> void:
	var a: Variant = _world(8754)
	var channel := int(a.place_subsurface_channel(2, Vector2i(-8, 4), Vector2i(8, 4)))
	a.seed_subsurface_packet_for_test(channel, 3, SAND, 5050, 65535, 4242)
	var state: Dictionary = a.serialize_subsurface_state()
	var b: Variant = _world(8754)
	_check(b.deserialize_subsurface_state(state), "subsurface state deserializes")
	_check_equal(b.subsurface_state_hash(), a.subsurface_state_hash(), "subsurface serialized state exact hash")
	for tick in 20:
		a.step()
		b.step()
	evidence.tunnel_replay = a.subsurface_state_hash()
	_check_equal(b.subsurface_state_hash(), a.subsurface_state_hash(), "subsurface deterministic replay")
	_check_equal(b.authoritative_physical_hash(), a.authoritative_physical_hash(), "authoritative physical hash includes hidden packets")

func _foundation_contracts_and_statistics() -> void:
	var world: Variant = _world(8755)
	var architecture: Dictionary = world.get_factory_foundation_architecture()
	_check_equal(architecture.material_packet_bytes, 8, "MaterialPacket fixed width")
	_check_equal(architecture.permeability_rule_bytes, 16, "generic PermeabilityRule fixed width")
	_check_equal(architecture.physical_field_source_bytes, 16, "generic PhysicalFieldSource fixed width")
	_check_equal(architecture.linked_transport_endpoint_bytes, 40, "generic LinkedTransportEndpoint fixed width")
	_check(architecture.physical_field_kinds == ["MAGNETIC", "AIRFLOW", "HEAT_SOURCE", "GRAVITY_MODIFIER", "RADIATION"], "stable PhysicalFieldSource kinds")
	_check(not architecture.portal_implemented and not architecture.fan_implemented and architecture.heat_switch_implemented, "Phase 9 promotes Heat Switch while Portal and Fan remain unimplemented")
	_check(world.record_production_event_for_test(10, 7, true), "production event accepted")
	_check(world.record_production_event_for_test(2, 3, false), "consumption event accepted")
	var statistics: Dictionary = world.get_production_statistics()
	_check_equal(statistics.materials[9].produced_1m, 7, "rolling 1m production")
	_check_equal(statistics.materials[9].produced_lifetime, 7, "lifetime production")
	_check_equal(statistics.materials[1].consumed_30m, 3, "rolling 30m consumption")
	_check_equal(statistics.flows.size(), 6, "flow counter catalog is stable")
	_check_equal(statistics.flows[0].id, "water_world_to_pipe", "flow counters use stable IDs")
	var alert_manager := FactoryAlertManager.new()
	world.place_structure(8, Vector2i(0, 0))
	alert_manager.observe(world, Rect2i(-1, -1, 2, 2))
	_check_equal(alert_manager.alerts.size(), 0, "alert manager has no false positive")
	var hud_source := FileAccess.get_file_as_string("res://rendering/factory_hud.gd")
	_check(hud_source.contains("const PAGE_COUNT := 10"), "ten serialized Quickbar pages")
	var overlay_source := FileAccess.get_file_as_string("res://rendering/map_overlay_renderer.gd")
	for overlay_id in ["MATERIAL", "DENSITY", "PIPE_PRESSURE", "UNDERGROUND_LOGISTICS", "PRODUCTION"]:
		_check(overlay_source.contains(overlay_id), "overlay stable ID %s" % overlay_id)
	for action in ["copy", "cut", "paste", "undo", "redo", "pipette", "rotate", "flip_horizontal", "flip_vertical", "info_mode", "statistics", "overlay_selector", "blueprint"]:
		_check(InputMap.has_action(action), "InputMap action %s" % action)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
