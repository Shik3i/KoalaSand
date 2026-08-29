extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [label, str(expected), str(actual)])


func _world(seed := 13001) -> Variant:
	var result := NativeSandWorld.new()
	result.reset(seed, 4)
	result.set_game_mode(1)
	return result


func _build_power_fixture(world: Variant, origin := Vector2i(100, 100)) -> void:
	_check(world.place_structure(27, origin, 0), "save fixture places Steam Turbine")
	_equal(world.place_pipe_line(origin + Vector2i(-1, 1), origin + Vector2i(-1, 1)), 1, "save fixture places turbine inlet Pipe")
	_equal(world.set_pipe_fluid(origin + Vector2i(-1, 1), 17, 30000, 2200), 0, "save fixture fills physical Steam")
	_equal(world.place_pipe_line(origin + Vector2i(6, 1), origin + Vector2i(6, 1)), 1, "save fixture places turbine exhaust Pipe")
	_equal(world.place_mechanical_shaft_line(origin + Vector2i(6, 2), origin + Vector2i(13, 2)), 8, "save fixture places shaft")
	_check(world.place_structure(28, origin + Vector2i(14, 0), 0), "save fixture places Generator")
	_check(world.place_structure(29, origin + Vector2i(20, 2), 0), "save fixture places Power Pole")
	_check(world.place_structure(31, origin + Vector2i(24, 0), 0), "save fixture places Accumulator")
	_check(world.place_structure(34, origin + Vector2i(29, 0), 0), "save fixture places Resistive Heater")
	_check(world.configure_power_structure(origin + Vector2i(29, 0), {"priority": 1}), "save fixture configures power priority")
	world.set_material_state(origin + Vector2i(0, 5), 1, 255, 1173)
	world.finalize_initialization()


func _run() -> void:
	var root := "user://phase13-persistence-fixture"
	var manager := WorldSaveManager.new(root)
	manager.delete_world("Fraction Carry", true)
	var world: Variant = _world()
	for _input in 19:
		world.accumulate_fraction_for_test(130013, 5, 100, 0, true)
	_check(world.credit_research_material_for_test(10, 2400), "save fixture credits Glass research cost")
	_check(world.credit_research_material_for_test(11, 40), "save fixture credits Iron research cost")
	world.set_game_mode(0)
	_check(world.try_unlock_research("processing.dry_separation"), "save fixture unlocks research")
	world.set_game_mode(1)
	_build_power_fixture(world)
	for _tick in 30: world.step()
	_check(int(world.get_power_state_at(Vector2i(100, 100)).speed_millirpm) > 0, "save fixture shaft rotates before save")
	world.set_material_state(Vector2i(0, 0), 22, 40, 2300)
	world.ignite_cell(Vector2i(0, 0), 24000000)
	for x in range(7, 14): world.set_material_state(Vector2i(x, 12), 1, 255, 1172)
	for y in range(3, 11): world.set_material_state(Vector2i(10, y), 21, 255, 1172)
	for cell in [Vector2i(9, 3), Vector2i(11, 3), Vector2i(9, 4), Vector2i(11, 4)]: world.set_material_state(cell, 22, 255, 1172)
	var falling_tree: Dictionary = world.character_cut_cell(Vector2i(10, 10))
	_check(bool(falling_tree.get("accepted", false)), "active Tree fall starts before save")
	_equal(int(world.get_organic_statistics().active_clusters), 1, "save fixture contains active falling Tree")
	var expected_fraction_hash: String = world.phase13_state_hash()
	var expected_physical_hash: String = world.authoritative_physical_hash()
	var expected_power_hash: String = world.power_state_hash()
	var context := {
		"playtime_seconds": 901,
		"mode": 1,
		"session": {"schema_version": 1, "preset_id": 0},
		"character": {"position_q8": Vector2i(13, 21)},
		"onboarding": {"completed": {"JETPACK": true}},
		"settings": {"autosave_minutes": 5, "ui_scale": 1.25},
		"objectives": {"first_material_flow": true},
		"blueprints": MvpExampleBlueprints.basic_screen().serialize(),
	}
	var saved := manager.save_world("Fraction Carry", world, context)
	_check(bool(saved.get("ok", false)), "atomic save succeeds")
	_check(int(saved.get("bytes", 0)) > 0, "save has bytes")
	_check(str(saved.get("sha256", "")).length() == 64, "save reports SHA-256")
	_check(int(saved.get("capture_usec", -1)) >= 0 and int(saved.get("write_usec", -1)) >= 0, "save timings reported")
	var listed := manager.list_worlds()
	_equal(listed.size(), 1, "save list contains world")
	_equal(str(listed[0].world_name), "Fraction Carry", "metadata world name")
	_equal(int(listed[0].playtime_seconds), 901, "metadata playtime")
	_equal(int(listed[0].seed), 13001, "metadata seed")
	var loaded_world: Variant = _world(1)
	var loaded := manager.restore_world("Fraction Carry", loaded_world)
	_check(bool(loaded.get("ok", false)), "save loads")
	_equal(loaded_world.phase13_state_hash(), expected_fraction_hash, "fractional ledger restores exactly")
	_equal(loaded_world.authoritative_physical_hash(), expected_physical_hash, "authoritative physical state restores exactly")
	_equal(loaded_world.power_state_hash(), expected_power_hash, "active mechanical and electrical state restores exactly")
	_check(int(loaded_world.get_power_state_at(Vector2i(100, 100)).speed_millirpm) > 0, "rotating shaft restores")
	_check(bool(loaded_world.get_research_state("processing.dry_separation").unlocked), "research unlock restores")
	_equal(int(loaded_world.get_organic_statistics().active_clusters), 1, "active Tree fall restores")
	_check(int(loaded_world.get_organic_statistics().reactive_cells) > 0, "active fire restores")
	_equal(int(loaded.context.playtime_seconds), 901, "session context restores")
	var completed: Dictionary = loaded_world.accumulate_fraction_for_test(130013, 5, 100, 0, true)
	var gold_channel: Dictionary = completed.channels[0]
	_equal(int(gold_channel.emitted_micro_mass) / 65280, 1, "19x5% save plus one input emits one Gold quantum")
	_equal(int(gold_channel.micro_mass), 0, "20x5% has zero Gold remainder")

	var second := manager.save_world("Fraction Carry", world, context)
	_check(bool(second.get("ok", false)), "second atomic save succeeds")
	var primary_path := root + "/Fraction_Carry.ksave"
	var corrupt := FileAccess.open(primary_path, FileAccess.WRITE)
	corrupt.store_string("corrupt")
	corrupt.flush()
	corrupt.close()
	var recovered := manager.load_world("Fraction Carry")
	_check(bool(recovered.get("ok", false)), "corrupt primary recovers")
	_check(bool(recovered.get("recovered_from_backup", false)), "backup recovery is explicit")
	var no_confirm := manager.delete_world("Fraction Carry", false)
	_equal(str(no_confirm.get("error", "")), "CONFIRMATION_REQUIRED", "delete requires confirmation")
	_check(bool(manager.delete_world("Fraction Carry", true).get("ok", false)), "confirmed delete succeeds")
	_equal(manager.list_worlds().size(), 0, "deleted save leaves no listed world")

	var async_started := manager.save_world_async("Async Autosave", world, context)
	_check(bool(async_started.get("ok", false)) and bool(async_started.get("pending", false)), "autosave captures consistent snapshot and starts background write")
	_check(int(async_started.get("capture_usec", -1)) >= 0, "autosave reports main-thread capture time")
	var async_finished := manager.finish_async_save()
	_check(bool(async_finished.get("ok", false)) and not bool(async_finished.get("pending", true)), "autosave background write completes")
	_check(int(async_finished.get("write_usec", -1)) >= 0, "autosave reports background duration")
	var async_loaded_world: Variant = _world(2)
	_check(bool(manager.restore_world("Async Autosave", async_loaded_world).get("ok", false)), "autosave is loadable")
	_equal(async_loaded_world.authoritative_physical_hash(), expected_physical_hash, "autosave snapshot is deterministic")
	manager.delete_world("Async Autosave", true)

	var library := BlueprintLibrary.new()
	MvpExampleBlueprints.install(library)
	_equal(library.library.size(), 6, "six MVP example Blueprints installed")
	for blueprint in MvpExampleBlueprints.all():
		_check(not blueprint.entries.is_empty(), "%s contains component geometry" % blueprint.display_name)
		for entry in blueprint.entries:
			_check(int(entry.type_id) >= 37 and int(entry.type_id) <= 47, "%s uses only ordinary Phase-13 components" % blueprint.display_name)
	var screen := MvpExampleBlueprints.basic_screen()
	var original_hash := screen.content_hash()
	screen.entries.remove_at(1)
	_check(screen.content_hash() != original_hash, "deleting one Mesh changes Blueprint geometry")
	var vessel := MvpExampleBlueprints.basic_metal_vessel()
	var metal_hash := vessel.content_hash()
	for entry in vessel.entries: entry.type_id = 39
	_check(vessel.content_hash() != metal_hash, "replacing Metal with Ceramic changes geometry/material definition")
	_check(not library.serialize().is_empty(), "Blueprint library persists geometry")
	_check(not library.serialize().hex_encode().contains(expected_fraction_hash), "Blueprint library does not copy runtime carry")

	print("phase13_persistence save_capture_ms=%.3f save_write_ms=%.3f load_ms=%.3f" % [manager.last_capture_usec / 1000.0, manager.last_write_usec / 1000.0, manager.last_load_usec / 1000.0])
	if failures == 0:
		print("PASS: %d Phase 13 persistence/Blueprint checks" % checks)
		quit(0)
	else:
		push_error("FAIL: %d/%d Phase 13 persistence/Blueprint checks" % [failures, checks])
		quit(1)
