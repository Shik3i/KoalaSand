extends SceneTree

const INT32_MIN := -2147483648
const INT32_MAX := 2147483647

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [label, str(expected), str(actual)])


func _world(seed := 13701) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 4)
	world.set_game_mode(1)
	return world


func _run() -> void:
	print("phase137_stage coordinate_extremes")
	_test_coordinate_extremes()
	print("phase137_stage snapshot_rejection")
	_test_snapshot_rejection_is_transactional()
	print("phase137_stage save_parser")
	_test_save_parser_and_paths()
	print("phase137_stage command_blueprint")
	_test_command_and_blueprint_abuse()
	if not OS.get_cmdline_user_args().has("--phase137-quick"):
		print("phase137_stage conservation_10m")
		_test_large_conservation_fixture()
		print("phase137_stage worldgen_100k")
		_test_worldgen_seed_sweep()
	print("phase137_stage ui_state")
	_test_ui_state_stress()
	if failures.is_empty():
		print("PASS: %d Phase 13.7 hardening checks" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("PHASE137: " + failure)
	print("FAIL: %d of %d Phase 13.7 hardening checks" % [failures.size(), checks])
	quit(1)


func _test_coordinate_extremes() -> void:
	var world: Variant = _world()
	var coordinates := [
		Vector2i(INT32_MIN + 1, -65),
		Vector2i(-65, -64), Vector2i(-1, -1), Vector2i.ZERO,
		Vector2i(63, 64), Vector2i(INT32_MAX - 1, 65),
	]
	for index in coordinates.size():
		var cell: Vector2i = coordinates[index]
		_equal(world.set_material_state(cell, 2, 255, 1173, 4590, index), OK, "extreme coordinate write %s" % cell)
		_equal(world.get_cell(cell), 2, "extreme coordinate read %s" % cell)
	for cell in [Vector2i(INT32_MIN, INT32_MIN), Vector2i(INT32_MAX, INT32_MAX)]:
		_equal(world.set_material_state(cell, 2, 255, 1173, 4590, 1), ERR_INVALID_PARAMETER, "neighbor-unsafe coordinate rejected %s" % cell)
		_equal(world.get_cell(cell), 0, "rejected coordinate remains empty %s" % cell)
	_equal(world.fill_rect(Rect2i(INT32_MAX - 2, 0, 8, 1), 2), -1, "overflowing fill rectangle rejected")
	_equal(world.allocate_chunk_rect(Rect2i(INT32_MAX - 2, 0, 8, 1)), -1, "overflowing chunk rectangle rejected")
	var clear_result: Dictionary = world.clear_vegetation_rect(Rect2i(0, 0, 1000001, 2))
	_check(not bool(clear_result.get("accepted", false)), "oversized vegetation rectangle rejected")


func _test_snapshot_rejection_is_transactional() -> void:
	var world: Variant = _world(13702)
	world.set_material_state(Vector2i(4, 5), 2, 200, 1900, 4590, 19)
	world.place_pipe_line(Vector2i(8, 8), Vector2i(10, 8))
	world.set_pipe_fluid(Vector2i(9, 8), 3, 12000, 1500)
	var before: String = world.authoritative_physical_hash()
	var valid: Dictionary = world.serialize_world_snapshot()
	var mutations: Array[Dictionary] = []
	var wrong_chunks := valid.duplicate(true); wrong_chunks.chunks = "not-an-array"; mutations.append(wrong_chunks)
	var wrong_schema := valid.duplicate(true); wrong_schema.schema_version = 999; mutations.append(wrong_schema)
	var duplicate_chunk := valid.duplicate(true)
	if not duplicate_chunk.chunks.is_empty(): duplicate_chunk.chunks.append(Dictionary(duplicate_chunk.chunks[0]).duplicate(true))
	mutations.append(duplicate_chunk)
	var bad_core := valid.duplicate(true)
	if not bad_core.chunks.is_empty():
		var first_chunk: Dictionary = bad_core.chunks[0]
		var core: PackedInt32Array = first_chunk.core
		core[0] = 65536
		first_chunk.core = core
	mutations.append(bad_core)
	var bad_pipes := valid.duplicate(true); bad_pipes.pipes = [{"cell": Vector2i.ZERO, "fluid": 999}]; mutations.append(bad_pipes)
	var bad_composition := valid.duplicate(true); bad_composition.compositions = [{"id": 1, "masses": [1, 2]}]; mutations.append(bad_composition)
	var bad_ledger := valid.duplicate(true); bad_ledger.ledgers = [{"id": 1, "input": -1, "emitted": 0, "queued": 0, "materials": PackedInt32Array([1]), "pending": []}]; mutations.append(bad_ledger)
	for index in mutations.size():
		_check(not world.deserialize_world_snapshot(mutations[index]), "malformed native snapshot %d rejected" % index)
		_equal(world.authoritative_physical_hash(), before, "malformed native snapshot %d leaves world unchanged" % index)
	_check(world.deserialize_world_snapshot(valid), "valid native snapshot still accepted")
	_equal(world.authoritative_physical_hash(), before, "valid native snapshot exact round trip")


func _test_save_parser_and_paths() -> void:
	var root_path := "user://phase137-hardening"
	var manager := WorldSaveManager.new(root_path)
	var world: Variant = _world(13703)
	world.set_material_state(Vector2i.ZERO, 2, 255, 1173, 4590, 1)
	var names := ["../escape", "..\\escape", "C:\\escape", "CON", "PRN", "name.", "name<bad>", "München 世界", "normal name"]
	var paths: Dictionary = {}
	for name in names:
		var result: Dictionary = manager.save_world(name, world, {"mode": 1})
		_check(bool(result.get("ok", false)), "adversarial save name accepted safely: %s" % name)
		var path := str(result.get("path", ""))
		_check(path.begins_with(root_path + "/") and not path.contains("../") and not path.contains("..\\"), "save path remains inside root: %s" % name)
		_check(not paths.has(path), "adversarial save path collision avoided: %s" % name)
		paths[path] = true
	var baseline := manager.save_world("Fuzz Target", world, {"mode": 1})
	_check(bool(baseline.get("ok", false)), "fuzz baseline save succeeds")
	var fuzz_path := str(baseline.get("path", ""))
	var original := FileAccess.get_file_as_bytes(fuzz_path)
	for length in [0, 1, 3, 8, 31, maxi(0, original.size() - 1)]:
		var truncated := original.slice(0, length)
		_write_bytes(fuzz_path, truncated)
		_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "truncated save length %d rejected" % length)
	var magic_length := WorldSaveManager.FILE_MAGIC.to_utf8_buffer().size()
	var wrong_magic := original.duplicate(); wrong_magic[4] = 88
	_write_bytes(fuzz_path, wrong_magic)
	_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "wrong save magic rejected")
	var future_schema := original.duplicate()
	for offset in 4: future_schema[4 + magic_length + offset] = 0xff
	_write_bytes(fuzz_path, future_schema)
	_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "future envelope schema rejected")
	var absurd_length := original.duplicate()
	for offset in 8: absurd_length[4 + magic_length + 4 + offset] = 0xff
	_write_bytes(fuzz_path, absurd_length)
	_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "absurd payload length rejected before allocation")
	var wrong_checksum := original.duplicate(); wrong_checksum[4 + magic_length + 4 + 8] = wrong_checksum[4 + magic_length + 4 + 8] ^ 0xff
	_write_bytes(fuzz_path, wrong_checksum)
	_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "checksum mismatch rejected")
	var fuzz_cases := mini(512, original.size())
	for index in fuzz_cases:
		var corrupted := original.duplicate()
		var fuzz_start := 4 + magic_length
		var offset := fuzz_start + int((index * 104729 + 17) % (corrupted.size() - fuzz_start))
		corrupted[offset] = corrupted[offset] ^ (1 << (index % 8))
		_write_bytes(fuzz_path, corrupted)
		_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "single-bit save fuzz mutation %d rejected" % index)
	var trailing := original.duplicate(); trailing.append(0)
	_write_bytes(fuzz_path, trailing)
	_check(not bool(manager._read_envelope(fuzz_path).get("ok", false)), "trailing save bytes rejected")
	_write_bytes(fuzz_path, original)
	_check(bool(manager._read_envelope(fuzz_path).get("ok", false)), "unmodified save remains readable after fuzz")
	var async_result := manager.save_world_async("Race Target", world, {"sequence": 1})
	_check(bool(async_result.get("ok", false)), "async save starts")
	var manual_result := manager.save_world("Race Target", world, {"sequence": 2})
	_check(bool(manual_result.get("ok", false)), "same-path manual save serializes behind async save")
	_check(bool(manager.finish_async_save().get("ok", false)), "async save joins cleanly")
	var loaded := manager.load_world("Race Target")
	_check(bool(loaded.get("ok", false)), "same-path save race leaves valid envelope")
	for name in names + ["Fuzz Target", "Race Target"]:
		manager.delete_world(name, true)


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _test_command_and_blueprint_abuse() -> void:
	var world: Variant = _world(13704)
	var bus := WorldCommandBus.new()
	var invalid_payloads := [
		{}, {"x": "0", "y": 0, "material_id": 2}, {"x": 2147483648, "y": 0, "material_id": 2},
		{"x": 0, "y": 0, "material_id": []}, {"x": 0, "y": 0, "material_id": 2, "configuration": []},
	]
	for repeat in 10000:
		var command := WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, invalid_payloads[repeat % invalid_payloads.size()])
		_check(not bus.apply(world, command), "invalid world command %d rejected" % repeat)
	var blueprint := BlueprintDefinition.new("phase137", "Hardening fixture", "Transform and persistence fixture")
	blueprint.add_structure(1, 37, Vector2i(2, -3), 1)
	blueprint.add_automation_component(2, 18, Vector2i(-4, 5), {"orientation": 2, "target_position": Vector2i(9, -7)})
	blueprint.add_connection(2, 0, 1, 0)
	blueprint.add_subsurface_channel(3, 2, Vector2i(-6, 8), Vector2i(7, -9))
	_check(blueprint.is_valid(), "hardening blueprint valid")
	_equal(blueprint.transformed(4).content_hash(), blueprint.content_hash(), "four rotations return exact blueprint")
	_equal(blueprint.transformed(0, true).transformed(0, true).content_hash(), blueprint.content_hash(), "double horizontal flip returns exact blueprint")
	_equal(blueprint.transformed(0, false, true).transformed(0, false, true).content_hash(), blueprint.content_hash(), "double vertical flip returns exact blueprint")
	var malformed := blueprint.to_dictionary(); malformed.entries[1].relative_id = 1
	_check(BlueprintDefinition.deserialize(var_to_bytes(malformed)) == null, "duplicate relative blueprint ID rejected")
	var wrong_shape := blueprint.to_dictionary(); wrong_shape.connections = "many"
	_check(BlueprintDefinition.deserialize(var_to_bytes(wrong_shape)) == null, "malformed blueprint collection rejected")
	_check(BlueprintDefinition.deserialize(PackedByteArray()) == null, "empty blueprint rejected")


func _test_large_conservation_fixture() -> void:
	var world: Variant = _world(13705)
	var started := Time.get_ticks_usec()
	var events := 0
	var input_micro_mass := 0
	var accounted_micro_mass := 0
	var input_constituents := [0, 0, 0, 0, 0, 0]
	var accounted_constituents := [0, 0, 0, 0, 0, 0]
	var balanced := true
	for input_count in [1000000, 1000000, 500000]:
		var report: Dictionary = world.run_global_mass_fixture(input_count, 4590, 17)
		_check(not report.is_empty(), "large conservation batch %d accepted" % input_count)
		events += int(report.get("events", 0))
		input_micro_mass += int(report.get("input_micro_mass", 0))
		accounted_micro_mass += int(report.get("accounted_micro_mass", 0))
		balanced = balanced and bool(report.get("balanced", false))
		for constituent in 6:
			input_constituents[constituent] += int(report.get("input_constituents", [0, 0, 0, 0, 0, 0])[constituent])
			accounted_constituents[constituent] += int(report.get("accounted_constituents", [0, 0, 0, 0, 0, 0])[constituent])
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	_equal(events, 10000000, "ten million exact process events executed")
	_check(balanced, "ten million process events retain exact global mass")
	_equal(input_micro_mass, accounted_micro_mass, "ten million global mass equation")
	_equal(input_constituents, accounted_constituents, "ten million per-constituent equation")
	print("phase137_mass events=%d elapsed_ms=%.3f input_micro=%d accounted_micro=%d balanced=%s constituents=%s" % [events, elapsed_ms, input_micro_mass, accounted_micro_mass, str(balanced), str(accounted_constituents)])


func _test_worldgen_seed_sweep() -> void:
	var world: Variant = _world(13706)
	var samples: Array[float] = []
	var failures_total := 0
	for batch in 100:
		var started := Time.get_ticks_usec()
		var report: Dictionary = world.validate_world_seeds(batch * 1000 + 1, 1000)
		samples.append((Time.get_ticks_usec() - started) / 1000.0)
		failures_total += int(report.get("validation_failures", -1))
	samples.sort()
	_equal(failures_total, 0, "100,000 world-generation seeds validate")
	print("phase137_worldgen seeds=100000 failures=%d timing_ms_p50=%.3f p95=%.3f p99=%.3f max=%.3f" % [failures_total, samples[49], samples[94], samples[98], samples[99]])


func _test_ui_state_stress() -> void:
	var state := GameUIState.new()
	for index in 10000:
		var id := "modal-%d" % (index % 17)
		state.open_modal(id)
		if index % 3 == 0:
			state.close_modal("modal-%d" % ((index + 7) % 17))
		if index % 11 == 0:
			state.escape()
	_check(state.modal_stack.size() <= 17, "repeated UI open/close keeps modal stack bounded")
	while state.world_input_blocked():
		state.escape()
	_equal(state.top_modal(), "", "UI stress closes all modal state")
