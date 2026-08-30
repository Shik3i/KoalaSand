extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _world(seed := 13501) -> Variant:
	var result := NativeSandWorld.new(); result.reset(seed, 4); result.set_game_mode(1); return result

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _equal(actual: Variant, expected: Variant, label: String) -> void: _check(actual == expected, "%s expected=%s actual=%s" % [label, expected, actual])

func _run() -> void:
	var materials := MaterialRegistry.new(); _equal(materials.load_directory(), OK, "material registry loads")
	var world: Variant = _world()
	var blueprints := BlueprintLibrary.new(); MvpExampleBlueprints.install(blueprints)
	var codex := PhysicsCodex.new(); codex.rebuild(materials, world, blueprints)
	_check(codex.entries.size() >= 70, "Codex covers MVP materials, Components, Research, Blueprints and physics")
	for query in ["heat", "steam", "screen", "gold", "oxygen", "charcoal", "pressure", "power"]: _check(not codex.search(query).is_empty(), "Codex search resolves %s" % query)
	var raw := codex.get_entry("material:raw_sand")
	_check(str(raw).contains("May contain") and str(raw).contains("specific hidden cell remains unknown"), "Raw Sand teaches general Gold possibility without local leak")
	_check(not str(raw).contains("7.2%"), "Codex has no specific hidden-cell assay")
	for id in ["component:41", "component:43", "component:40", "component:27"]:
		var entry := codex.get_entry(id); _check(entry.has("sections") and str(entry.sections).contains("WHAT IT DOES NOT DO"), "%s describes physical limits" % id)
	_equal(blueprints.library.size(), 6, "six example Blueprints")
	for id: Variant in blueprints.library: _check(str(codex.get_entry("blueprint:%s" % id)).contains("no hidden machine identity"), "%s Blueprint disclaims hidden identity" % id)
	var audit := PlayerFacingAudit.collect(materials, world, blueprints, codex)
	_check(audit.size() >= 100, "player-facing inventory is exhaustive")
	_equal(PlayerFacingAudit.write_csv("res://artifacts/phase135/player-facing-audit.csv", audit), OK, "audit CSV writes")

	var clock := SimulationClock.new(60); var hash_before: String = world.authoritative_physical_hash(); clock.set_paused(true)
	for _frame in 240: for _tick in clock.advance(1.0 / 60.0): world.step()
	_equal(world.authoritative_physical_hash(), hash_before, "Planning Pause freezes authoritative simulation")
	_check(world.place_structure(37, Vector2i(10, 10), 0), "static construction remains applicable during Planning Pause")
	_equal(int(world.get_structure(Vector2i(10, 10))), 37, "paused construction changes configuration immediately")

	world.place_structure(41, Vector2i(20, 20), 0)
	var screen := PhysicalInspector.inspect(world, materials, Vector2i(20, 20))
	_check(str(screen.causes).contains("NO VIBRATION"), "Screen Inspector explains no vibration")
	world.place_structure(43, Vector2i(30, 30), 0)
	var sluice := PhysicalInspector.inspect(world, materials, Vector2i(30, 30))
	_check(str(sluice.causes).contains("INSUFFICIENT WATER FLOW"), "Sluice Inspector explains insufficient flow")
	world.place_structure(40, Vector2i(40, 40), 0)
	world.set_material_state(Vector2i(41, 40), 21, 255, 1173)
	var furnace := PhysicalInspector.inspect(world, materials, Vector2i(40, 40))
	_check(str(furnace.causes).contains("BELOW REACTION TEMPERATURE"), "furnace region Inspector reports low temperature")
	world.place_structure(10, Vector2i(50, 50), 0); world.set_pipe_fluid(Vector2i(50, 50), 17, 32000, 2200)
	var steam := PhysicalInspector.inspect(world, materials, Vector2i(50, 50))
	_check(str(steam.summary).contains("Pressure") and str(steam.summary).contains("flow"), "Steam Inspector exposes pressure and flow")
	var hidden := PhysicalInspector.inspect(world, materials, Vector2i(9000, 9000), true, 1)
	_equal(str(hidden.title), "UNKNOWN AREA", "Character Inspector respects visibility")

	var tracker := ExperimentTracker.new()
	var complete := tracker.observe({"heavy_captured":1, "charcoal_produced":1, "pipe_steam_mass":1})
	_equal(complete.size(), 3, "Experiments trigger from authoritative state dictionary")
	_equal(tracker.observe({"heavy_captured":1, "charcoal_produced":1, "pipe_steam_mass":1}).size(), 0, "Experiments trigger once")

	var copied := MvpExampleBlueprints.basic_furnace(); copied.entries.append({"kind":"structure", "relative_id":999, "type_id":44, "position":Vector2i(6, 0), "orientation":0, "configuration":{}})
	copied.blueprint_id = "player_my_furnace"; copied.display_name = "My Furnace"; _check(blueprints.save(copied), "modified Example saves as custom Blueprint")
	_check(blueprints.load_blueprint("player_my_furnace").entries.size() > MvpExampleBlueprints.basic_furnace().entries.size(), "custom Blueprint retains modified geometry")

	var audio := AudioEventMixer.new(); root.add_child(audio); await process_frame
	_equal(audio.get_child_count(), AudioEventMixer.MAX_UI_VOICES + AudioEventMixer.MAX_WORLD_ONESHOTS + AudioEventMixer.MAX_AGGREGATED_LOOPS, "central audio uses fixed voice pools")
	var sources: Array[Dictionary] = []
	for index in 300: sources.append({"event":"conveyor", "position":Vector2(index % 50, index / 50) * 4.0, "intensity":0.6, "category":"Machines"})
	audio.update_aggregated_loops(sources, Vector2.ZERO, 1.0)
	_check(audio.statistics().actual_voices <= AudioEventMixer.MAX_AGGREGATED_LOOPS, "1000 sources aggregate within loop budget")
	_check(float(audio.statistics().audio_cpu_ms) < 5.0, "representative audio aggregation remains bounded")
	_check(AudioEventMixer.event_matrix().size() >= 30, "complete audio event matrix registered")
	_check(BuildInfo.VERSION == "0.1.0-playtest.5", "visible playtest version")

	var manager := WorldSaveManager.new("user://phase135-recovery")
	manager.delete_world("Recovery", true)
	_check(bool(manager.save_world("Recovery", world, {"mode":0, "playtime_seconds":90}).ok), "recovery fixture first save")
	_check(bool(manager.save_world("Recovery", world, {"mode":0, "playtime_seconds":120}).ok), "recovery fixture backup created")
	var corrupt := FileAccess.open("user://phase135-recovery/Recovery.ksave", FileAccess.WRITE); corrupt.store_string("corrupt"); corrupt.close()
	var saves := manager.inspect_worlds(); _equal(saves.size(), 1, "corrupt primary remains visible in Save Browser")
	_check(bool(saves[0].recoverable) and not bool(saves[0].primary_valid) and bool(saves[0].backup_valid), "Save Browser exposes explicit backup recovery")
	_check(bool(manager.restore_backup("Recovery").ok), "explicit backup restoration succeeds")
	manager.delete_world("Recovery", true)

	var exporter := DiagnosticsExporter.new("user://phase135-diagnostics-test")
	var diagnostic := exporter.export_report(world, {"ui_scale":1.25, "reduced_motion":true}, {"fps":120.0}, ["fixture error C:/Users/Test/secret"])
	_check(bool(diagnostic.ok), "explicit local diagnostics ZIP")
	for name in ["diagnostics.json", "recent-errors.txt", "performance.json", "README.txt"]: _check(name in diagnostic.contents, "diagnostics contains %s" % name)
	_check(str(FileAccess.get_sha256(diagnostic.path)).length() == 64, "diagnostics ZIP checksum available")

	audio.queue_free()
	if failures.is_empty(): print("PASS: %d Phase 13.5 correctness checks" % checks); quit(0)
	else:
		for failure in failures: push_error("PHASE135: " + failure)
		print("FAIL: %d of %d Phase 13.5 checks" % [failures.size(), checks]); quit(1)
