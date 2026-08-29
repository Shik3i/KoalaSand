extends SceneTree

const V2_SETTINGS := {
	"seed": 8675309,
	"width": 16384,
	"depth": 4096,
	"sky": 512,
	"surface_baseline": 0,
	"surface_amplitude": 72,
	"sediment_depth": 18,
	"cave_density": 0.52,
	"coal_frequency": 0.73,
	"water_frequency": 0.72,
	"geology_scale": 512,
	"generation_version": 2,
}

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_test_mode_axes()
	_test_world_identity_and_pipeline()
	_test_v2_generation_and_determinism()
	_test_validation_and_features()
	_test_interest_regions()
	_test_character_collision_and_digging()
	_test_visibility_and_memory()
	_test_character_replay_and_state()
	_test_mobility_and_input()
	_test_fresh_character_loop()
	if failures.is_empty():
		print("PASS: %d checks across 10 Phase 11 suites" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d failures across %d checks" % [failures.size(), checks])
		quit(1)


func _test_mode_axes() -> void:
	var factory := GameModeCapabilities.preset(GameModeCapabilities.Preset.FACTORY)
	var character := GameModeCapabilities.preset(GameModeCapabilities.Preset.CHARACTER)
	var creative := GameModeCapabilities.preset(GameModeCapabilities.Preset.CREATIVE)
	_check_equal(factory.control_mode, GameModeCapabilities.ControlMode.GOD, "Factory ControlMode.GOD")
	_check_equal(factory.progression_mode, GameModeCapabilities.ProgressionMode.NORMAL, "Factory ProgressionMode.NORMAL")
	_check_equal(factory.visibility_policy, GameModeCapabilities.VisibilityPolicy.OMNISCIENT, "Factory VisibilityPolicy.OMNISCIENT")
	_check(bool(factory.recommended), "Factory is Recommended")
	_check_equal(character.control_mode, GameModeCapabilities.ControlMode.CHARACTER, "Character ControlMode.CHARACTER")
	_check_equal(character.progression_mode, GameModeCapabilities.ProgressionMode.NORMAL, "Character ProgressionMode.NORMAL")
	_check_equal(character.visibility_policy, GameModeCapabilities.VisibilityPolicy.DISCOVERED, "Character VisibilityPolicy.DISCOVERED")
	_check_equal(creative.control_mode, GameModeCapabilities.ControlMode.GOD, "Creative ControlMode.GOD")
	_check_equal(creative.progression_mode, GameModeCapabilities.ProgressionMode.CREATIVE, "Creative ProgressionMode.CREATIVE")
	_check_equal(creative.visibility_policy, GameModeCapabilities.VisibilityPolicy.OMNISCIENT, "Creative VisibilityPolicy.OMNISCIENT")
	var factory_caps := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.FACTORY)
	var character_caps := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.CHARACTER)
	var creative_caps := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.CREATIVE)
	_check(bool(factory_caps.free_camera) and bool(factory_caps.build_anywhere), "Factory free camera/build anywhere")
	_check(not bool(factory_caps.creative_erase), "Factory does not receive Creative Erase")
	_check(bool(character_caps.control_character) and bool(character_caps.build_in_range), "Character uses local physical control/build")
	_check(bool(character_caps.jetpack) and bool(character_caps.dig), "Character starts with Jetpack and Dig capabilities")
	_check(not bool(character_caps.creative_erase) and not bool(character_caps.free_camera), "Character has no Creative Erase/free camera")
	_check(bool(creative_caps.creative_paint) and bool(creative_caps.creative_erase), "Creative paint/erase enabled")
	var spectator := GameModeCapabilities.capabilities(GameModeCapabilities.ControlMode.SPECTATOR, GameModeCapabilities.ProgressionMode.NORMAL, GameModeCapabilities.VisibilityPolicy.DISCOVERED)
	_check(not bool(spectator.commands) and not bool(spectator.build), "Spectator cannot mutate")
	_check(not bool(spectator.remote_view) and not bool(spectator.remote_build), "future remote capabilities remain disabled")
	var session := GameSession.new()
	session.apply_preset(GameModeCapabilities.Preset.CHARACTER)
	var roundtrip := GameSession.new()
	_check(roundtrip.deserialize(session.serialize()), "mode axes deserialize")
	_check_equal(roundtrip.serialize(), session.serialize(), "mode axes roundtrip exact")


func _test_world_identity_and_pipeline() -> void:
	var world: Variant = _new_v2_world(8675309, 2)
	var identity: Dictionary = world.get_world_identity()
	_check_equal(identity.schema_version, 1, "WorldIdentity schema")
	_check_equal(identity.seed, 8675309, "WorldIdentity seed")
	_check_equal(identity.generation_version, 2, "WorldIdentity V2")
	_check(not str(identity.generator_settings_hash).is_empty(), "settings hash populated")
	var before := identity.duplicate(true)
	world.set_game_mode(1)
	_check_equal(world.get_world_identity(), before, "mode cannot alter WorldIdentity")
	var architecture: Dictionary = world.get_worldgen_v2_architecture()
	_check_equal(architecture.macro_scale_cells, 64, "macro scale")
	_check_equal((architecture.passes as Array).size(), 10, "ten explicit generator passes")
	for grammar in ["CAVERN", "TUNNEL", "CRACK", "SHAFT", "POCKET"]:
		_check(grammar in architecture.cave_grammars, "cave grammar %s" % grammar)
	for region in ["SURFACE", "SEDIMENT_SHALLOW", "UNDERGROUND", "CAVERNS", "DEEP_THERMAL", "BEDROCK"]:
		_check(region in architecture.depth_regions, "depth region %s" % region)
	_check(bool(architecture.native_data_oriented), "native data-oriented generation")
	_check(bool(architecture.lazy_chunk_generation), "lazy generation")
	_check(bool(architecture.physical_water) and bool(architecture.physical_temperature), "physical Water/temperature")
	var macro: Dictionary = world.get_macro_sample(Vector2i.ZERO)
	for field in ["surface_elevation", "sediment_depth", "cave_tendency", "water_table", "aquifer_strength", "geology_province", "thermal_tendency", "feature_density"]:
		_check(macro.has(field), "macro field %s" % field)
	var preview: Dictionary = world.get_macro_preview(160, 90)
	_check_equal(preview.width, 160, "preview width")
	_check_equal(preview.height, 90, "preview height")
	_check_equal((preview.pixels as PackedByteArray).size(), 160 * 90 * 4, "preview RGBA payload")
	_check_equal(preview.source, "macro_world_v2", "preview shares macro source")
	_check(not bool(preview.hidden_geology_revealed), "preview hides geology treasure")
	var gd_identity := WorldIdentity.from_native(world)
	_check(gd_identity.stable_key().contains(":v2:"), "GDScript WorldIdentity stable key")
	_check_equal(gd_identity.serialize().generator_settings_hash, identity.generator_settings_hash, "WorldIdentity bridge")


func _test_v2_generation_and_determinism() -> void:
	var region := Rect2i(-3, -2, 7, 12)
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _new_v2_world(8675309, workers)
		world.request_chunk_region(region, 1)
		world.flush_generation()
		hashes.append(world.get_region_content_hash(region))
		_check_equal(world.chunk_count(), region.get_area(), "all requested chunks publish workers=%d" % workers)
		_check(int(world.get_total_water_mass()) >= 0, "physical Water query workers=%d" % workers)
	for hash_value in hashes:
		_check_equal(hash_value, hashes[0], "V2 worker parity")
	print("phase11_v2_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])
	var ordered: Variant = _new_v2_world(8675309, 4)
	var reverse: Variant = _new_v2_world(8675309, 4)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			ordered.request_chunk(Vector2i(x, y), 1)
	for y in range(region.end.y - 1, region.position.y - 1, -1):
		for x in range(region.end.x - 1, region.position.x - 1, -1):
			reverse.request_chunk(Vector2i(x, y), 1)
	ordered.flush_generation()
	reverse.flush_generation()
	_check_equal(ordered.get_region_content_hash(region), reverse.get_region_content_hash(region), "generation order parity")
	var pass_hashes: Dictionary = ordered.get_worldgen_pass_hashes(region)
	for field in ["macro", "surface", "cave", "aquifer", "geology", "thermal", "feature", "final"]:
		_check(pass_hashes.has(field) and not str(pass_hashes[field]).is_empty(), "pass hash %s" % field)
	print("phase11_v2_hashes %s" % JSON.stringify(pass_hashes))
	var different: Variant = _new_v2_world(8675310, 4)
	different.request_chunk_region(region, 1)
	different.flush_generation()
	_check(different.get_region_content_hash(region) != ordered.get_region_content_hash(region), "different V2 seed changes world")
	var same_seed_factory: Variant = _new_v2_world(1234567, 2)
	var same_seed_character: Variant = _new_v2_world(1234567, 2)
	var same_seed_creative: Variant = _new_v2_world(1234567, 2)
	same_seed_factory.set_game_mode(0)
	same_seed_character.set_game_mode(0)
	same_seed_creative.set_game_mode(1)
	for candidate in [same_seed_factory, same_seed_character, same_seed_creative]:
		candidate.request_chunk_region(region, 1)
		candidate.flush_generation()
	_check_equal(same_seed_factory.get_region_content_hash(region), same_seed_character.get_region_content_hash(region), "Factory/Character same world")
	_check_equal(same_seed_factory.get_region_content_hash(region), same_seed_creative.get_region_content_hash(region), "Factory/Creative same world")
	var v1 := NativeSandWorld.new()
	var v1_settings := V2_SETTINGS.duplicate(true)
	v1_settings.generation_version = 1
	v1.configure_world(v1_settings, 2)
	v1.request_chunk_region(Rect2i(-1, -1, 3, 5), 1)
	v1.flush_generation()
	_check_equal(v1.get_region_content_hash(Rect2i(-1, -1, 3, 5)), "86dee9f0", "V1 golden remains unchanged")


func _test_validation_and_features() -> void:
	var world: Variant = _new_v2_world(17, 2)
	var validation: Dictionary = world.validate_world_seed(17)
	_check(bool(validation.valid), "single seed valid after deterministic correction")
	_check(not bool(validation.seed_rerolled), "validator never rerolls displayed seed")
	_check(int(validation.spawn_flatness) <= 3, "spawn flatness guaranteed")
	_check(int(validation.coal_distance) <= 70, "Coal reachable")
	_check(int(validation.water_distance) <= 192, "Water reachable")
	_check(int(validation.first_cave_distance) <= 72, "early cave route reachable")
	_check(int(validation.hot_hazard_distance) >= 640, "thermal spawn safety")
	_check((validation.failure_categories as Array).is_empty(), "no post-correction failure categories")
	for metric in ["nearby_cave_volume", "largest_nearby_cave", "cave_connectivity", "aquifer_volume", "deep_thermal_distance", "geology_distribution", "gold_anomaly_distribution", "feature_count"]:
		_check(validation.has(metric), "validator metric %s" % metric)
	var sweep: Dictionary = world.validate_world_seeds(1, 10000)
	_check_equal(sweep.seed_count, 10000, "10k macro seed sweep")
	_check_equal(sweep.validation_failures, 0, "10k seeds valid after corrections")
	_check(float(sweep.seeds_per_second) > 1000.0, "macro validation throughput")
	_check(int(sweep.corrections) >= 0, "correction count reported")
	for profile in ["balanced", "cave_heavy", "aquifer_heavy", "thermal", "extreme_valid", "worst_corrected"]:
		_check((sweep.representative_seeds as Dictionary).has(profile), "representative seed %s" % profile)
	for metric in ["spawn_flatness", "raw_sand_distance", "coal_distance", "water_distance", "first_cave_distance", "nearby_cave_volume", "largest_nearby_cave", "cave_connectivity", "aquifer_volume", "deep_thermal_distance", "hot_hazard_distance", "geology_distribution", "gold_anomaly_distribution", "feature_count"]:
		var percentiles: Dictionary = sweep.metrics[metric]
		_check(percentiles.has("min") and percentiles.has("p50") and percentiles.has("p95") and percentiles.has("p99") and percentiles.has("max"), "percentiles %s" % metric)
	print("phase11_seed_sweep seeds=%d elapsed_ms=%.3f seeds_per_second=%.1f failures=%d corrections=%d" % [sweep.seed_count, sweep.elapsed_ms, sweep.seeds_per_second, sweep.validation_failures, sweep.corrections])
	var templates: Array = world.get_world_feature_templates()
	_check_equal(templates.size(), 6, "small authored template catalog")
	for template: Dictionary in templates:
		_check(int(template.version) == 1 and not str(template.reward_tag).is_empty(), "versioned feature with future reward tag")
		_check((template.placement_exclusions as Array).size() >= 4, "feature exclusions")
	var anchors: Array = world.get_world_feature_anchors(Rect2i(-20, 2, 40, 20))
	_check(not anchors.is_empty(), "deterministic authored feature anchors")
	var repeat: Array = world.get_world_feature_anchors(Rect2i(-20, 2, 40, 20))
	_check_equal(anchors, repeat, "feature anchor determinism")
	var ruin_anchor: Dictionary = {}
	for anchor: Dictionary in anchors:
		if int(anchor.template_index) == 1:
			ruin_anchor = anchor
			break
	_check(not ruin_anchor.is_empty(), "industrial ruin anchor available")
	if not ruin_anchor.is_empty():
		var macro_coordinate: Vector2i = ruin_anchor.macro_coordinate
		world.request_chunk_region(Rect2i(macro_coordinate - Vector2i.ONE, Vector2i(3, 3)), 1)
		world.flush_generation()
		var structure_stats: Dictionary = world.get_structure_statistics()
		_check(int(structure_stats.structures_allocated) > 0, "authored ruin uses actual structure cells")
		var wall_found := false
		var center: Vector2i = ruin_anchor.world_cell
		for y in range(center.y - 32, center.y + 33):
			for x in range(center.x - 32, center.x + 33):
				if world.get_structure(Vector2i(x, y)) == 16:
					wall_found = true
					break
			if wall_found:
				break
		_check(wall_found, "industrial ruin stamps physical reservoir-wall geometry")


func _test_interest_regions() -> void:
	var world: Variant = _new_v2_world(323, 2)
	var character := InterestRegion.new(1, 0, Rect2i(-2, -1, 5, 4), InterestRegion.Purpose.CHARACTER, 32)
	_check_equal(character.request(world), 20, "Character InterestRegion requests vicinity")
	var camera := InterestRegion.new(2, 1, Rect2i(8, 0, 3, 3), InterestRegion.Purpose.GOD_CAMERA, 32)
	_check_equal(camera.request(world), 9, "God Camera InterestRegion requests bounds")
	var spectator := InterestRegion.new(3, 2, Rect2i(20, 0, 1000, 10), InterestRegion.Purpose.SPECTATOR, 8)
	_check(int(spectator.request(world)) <= 8, "Spectator generation budget enforced")
	var state := character.serialize()
	_check_equal(state.source_id, 1, "InterestRegion stable source ID")
	_check_equal(state.purpose, InterestRegion.Purpose.CHARACTER, "InterestRegion purpose")
	_check_equal(state.bounds, Rect2i(-2, -1, 5, 4), "InterestRegion bounds")


func _test_character_collision_and_digging() -> void:
	var world := NativeSandWorld.new()
	world.reset(99, 1)
	world.allocate_chunk_rect(Rect2i(-1, -1, 3, 3))
	world.set_cell(Vector2i(0, 0), 1)
	var collision: Dictionary = world.query_character_collision(Rect2i(-1, -5, 3, 6))
	_check(bool(collision.blocked), "character collides with Stone")
	_check_equal(collision.cells_sampled, 18, "compact body samples 18 cells")
	world.set_cell(Vector2i(0, 0), 2)
	_check(not bool(world.query_character_collision(Rect2i(-1, -5, 3, 6)).blocked), "loose Raw Sand is not Bedrock wall")
	world.set_cell(Vector2i(0, 0), 0)
	world.place_structure(5, Vector2i(0, 0), 0)
	_check(bool(world.query_character_collision(Rect2i(-1, -5, 3, 6)).blocked), "solid structure collision")
	world.remove_structure_at(Vector2i(0, 0))
	world.set_cell(Vector2i(2, 0), 1)
	var rock: Dictionary = world.character_dig_cell(Vector2i(2, 0))
	_check(bool(rock.changed) and bool(rock.conserved), "Stone excavation conserves matter")
	_check_equal(rock.physical_output, 20, "Stone becomes Rock Debris")
	_check_equal(world.get_cell(Vector2i(2, 0)), 20, "Rock Debris exists in world")
	world.set_cell(Vector2i(3, 0), 4)
	var coal: Dictionary = world.character_dig_cell(Vector2i(3, 0))
	_check_equal(coal.physical_output, 14, "Coal becomes Coal Chunk")
	_check_equal(world.get_cell(Vector2i(3, 0)), 14, "Coal Chunk exists in world")
	world.set_cell(Vector2i(4, 0), 5)
	var bedrock: Dictionary = world.character_dig_cell(Vector2i(4, 0))
	_check(not bool(bedrock.changed), "Bedrock cannot be dug")
	_check_equal(world.get_cell(Vector2i(4, 0)), 5, "Bedrock remains")
	world.set_cell(Vector2i(5, 0), 2)
	var sand: Dictionary = world.character_dig_cell(Vector2i(5, 0))
	_check_equal(sand.physical_output, 2, "Raw Sand remains physical Raw Sand")
	_check_equal(world.get_cell(Vector2i(5, 0)), 2, "Raw Sand is not deleted")
	_check(world.get_memory_layout().maximum_material_id >= 20, "Rock Debris stable material ID included")


func _test_visibility_and_memory() -> void:
	var world := NativeSandWorld.new()
	world.reset(123, 1)
	world.allocate_chunk_rect(Rect2i(-2, -2, 5, 5))
	for y in range(-80, 81):
		world.set_cell(Vector2i(8, y), 1)
	var first: Dictionary = world.update_character_visibility(1, Vector2i.ZERO, 48, 6)
	_check(float(first.visibility_usec) >= 0.0, "FOV cost reported")
	_check(world.is_cell_live_visible(1, Vector2i(0, 0)), "origin live visible")
	_check(world.is_cell_discovered(1, Vector2i(7, 0)), "front wall shell discovered")
	_check(not world.is_cell_discovered(1, Vector2i(20, 0)), "no vision through deep terrain")
	world.character_dig_cell(Vector2i(8, 0))
	# Open a real tunnel through the wall; FOV reveals the cave through physics state.
	for y in range(-3, 4):
		world.set_cell(Vector2i(8, y), 0)
	world.update_character_visibility(1, Vector2i.ZERO, 48, 6)
	_check(world.is_cell_live_visible(1, Vector2i(20, 0)), "opening wall reveals cave naturally")
	world.update_character_visibility(1, Vector2i(-32, 0), 24, 6)
	_check(world.is_cell_discovered(1, Vector2i(20, 0)), "discovery remains remembered")
	_check(not world.is_cell_live_visible(1, Vector2i(20, 0)), "remembered remote cell becomes stale")
	var stats: Dictionary = world.get_visibility_statistics(1)
	_check_equal(stats.discovered_mask_bytes_per_chunk, 512, "discovery mask 512 bytes/chunk")
	_check_equal(stats.live_mask_bytes_per_chunk, 512, "live mask 512 bytes/chunk")
	_check_equal(stats.last_known_bytes_per_chunk, 4096, "compact byte last-known material page")
	_check(int(stats.total_bytes) > 0, "lazy discovered memory reported")
	var saved: Dictionary = world.serialize_visibility_state(1)
	var hash_before: String = world.visibility_state_hash(1)
	world.clear_visibility(1)
	_check(not world.is_cell_discovered(1, Vector2i(20, 0)), "clear removes discovery")
	_check(world.deserialize_visibility_state(saved), "visibility deserialize")
	_check_equal(world.visibility_state_hash(1), hash_before, "discovery serialization roundtrip hash")
	var page: Dictionary = world.get_visibility_render_page(1, Rect2i(-1, -1, 2, 2))
	_check_equal((page.pixels as PackedByteArray).size(), 128 * 128 * 4, "visibility page RGBA")
	print("phase11_discovery_replay hash=%s chunks=%d bytes=%d fov_ms=%.4f" % [hash_before, stats.discovered_chunks, stats.total_bytes, float(stats.visibility_usec) / 1000.0])


func _test_character_replay_and_state() -> void:
	var a_world := NativeSandWorld.new()
	var b_world := NativeSandWorld.new()
	a_world.reset(456, 1)
	b_world.reset(456, 1)
	a_world.allocate_chunk_rect(Rect2i(-2, -2, 5, 5))
	b_world.allocate_chunk_rect(Rect2i(-2, -2, 5, 5))
	for x in range(-100, 101):
		a_world.set_cell(Vector2i(x, 12), 1)
		b_world.set_cell(Vector2i(x, 12), 1)
	var camera_a := Camera2D.new()
	var camera_b := Camera2D.new()
	var a := KoalaCharacterController.new()
	var b := KoalaCharacterController.new()
	a.initialize(a_world, camera_a, Vector2i(0, 6), 2.0)
	b.initialize(b_world, camera_b, Vector2i(0, 6), 2.0)
	var replay: Array[int] = []
	for index in range(180):
		replay.append(KoalaCharacterController.INPUT_RIGHT | (KoalaCharacterController.INPUT_JETPACK if index in range(30, 90) else 0))
	for mask in replay:
		a.replay_step(mask)
		b.replay_step(mask)
	_check_equal(a.serialize_state(), b.serialize_state(), "fixed-tick Character replay deterministic")
	_check_equal(a_world.visibility_state_hash(1), b_world.visibility_state_hash(1), "Character path discovery deterministic")
	_check(a.jetpack_unlocked, "Basic Jetpack unlocked tick 0")
	_check(a.world_cell().x > 0, "Character walk/aerial control moves")
	var state := a.serialize_state()
	var restored := KoalaCharacterController.new()
	restored.initialize(a_world, camera_a, Vector2i.ZERO, 2.0)
	_check(restored.deserialize_state(state), "Character state deserialize")
	_check_equal(restored.serialize_state(), state, "Character state roundtrip")
	var session := GameSession.new()
	session.apply_preset(GameModeCapabilities.Preset.CHARACTER)
	var player_state := KoalaPlayerState.new()
	player_state.capture(a_world, session, a)
	var encoded: Dictionary = player_state.serialize()
	var decoded := KoalaPlayerState.new()
	_check(decoded.deserialize(encoded), "combined player state deserialize")
	_check_equal(decoded.serialize(), encoded, "combined player state roundtrip exact")
	var expected_discovery_hash: String = a_world.visibility_state_hash(1)
	a_world.clear_visibility(1)
	a.replay_step(KoalaCharacterController.INPUT_LEFT)
	session.apply_preset(GameModeCapabilities.Preset.FACTORY)
	_check(decoded.restore(a_world, session, a), "combined player state restore")
	_check_equal(a.serialize_state(), state, "combined player state restores Character")
	_check_equal(a_world.visibility_state_hash(1), expected_discovery_hash, "combined player state restores discovery")
	_check_equal(session.preset_id, GameModeCapabilities.Preset.CHARACTER, "combined player state restores mode axes")
	print("phase11_character_replay hash=%s discovery=%s" % [a.replay_hash(), a_world.visibility_state_hash(1)])
	a.free(); b.free(); restored.free(); camera_a.free(); camera_b.free()


func _test_mobility_and_input() -> void:
	var world := NativeSandWorld.new()
	world.reset(1, 1)
	var definitions: Dictionary = {}
	for definition: Dictionary in world.get_research_definitions():
		definitions[str(definition.id)] = definition
	_check(definitions.has("mobility.sprint"), "Sprint Research ID")
	_check(definitions.has("mobility.hover"), "Hover Research ID")
	_check(int(definitions["mobility.sprint"].costs.glass) <= 600, "Sprint very cheap")
	_check(int(definitions["mobility.sprint"].costs.iron) <= 10, "Sprint early iron cost")
	_check(int(definitions["mobility.hover"].costs.gold) <= 1, "Hover small Gold cost")
	_check("mobility.sprint" in definitions["mobility.hover"].prerequisites, "Hover follows Sprint")
	for action in ["move_left", "move_right", "jump", "jetpack", "sprint", "hover", "interact", "dig", "center_camera"]:
		_check(InputMap.has_action(action), "InputMap action %s" % action)
	var caps := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.CHARACTER)
	_check(bool(caps.jetpack), "Jetpack capability not Research gated")
	_check(not caps.has("health") and not caps.has("hunger") and not caps.has("thirst"), "no survival-stat systems")
	var preferences := CharacterAccessibilityPreferences.new()
	preferences.hover_toggle = false
	preferences.reduced_motion = true
	preferences.ui_scale = 1.5
	var restored_preferences := CharacterAccessibilityPreferences.new()
	_check(restored_preferences.deserialize(preferences.serialize()), "accessibility preferences roundtrip")
	var controller := KoalaCharacterController.new()
	controller.apply_accessibility_preferences(restored_preferences)
	_check(not controller.hover_toggle and controller.reduced_motion, "Hover hold/reduced-motion preferences applied")
	_check_equal(restored_preferences.ui_scale, 1.5, "UI scale preference retained")
	controller.free()


func _test_fresh_character_loop() -> void:
	var world: Variant = _new_v2_world(8675309, 4)
	var spawn: Vector2i = world.get_character_spawn()
	var spawn_chunk := Vector2i(floori(spawn.x / 64.0), floori(spawn.y / 64.0))
	world.request_chunk_region(Rect2i(spawn_chunk - Vector2i(3, 2), Vector2i(7, 6)), 0)
	world.flush_generation()
	var camera := Camera2D.new()
	var character := KoalaCharacterController.new()
	character.initialize(world, camera, spawn, 2.0)
	_check(world.is_cell_discovered(1, spawn), "fresh Character discovers spawn")
	var dig_target := Vector2i.ZERO
	for y in range(spawn.y, spawn.y + 17):
		for x in range(spawn.x - 12, spawn.x + 13):
			var candidate := Vector2i(x, y)
			if world.get_cell(candidate) == 2 and character.can_interact(candidate):
				dig_target = candidate
				break
		if dig_target != Vector2i.ZERO:
			break
	_check(dig_target != Vector2i.ZERO, "fresh Character has accessible Raw Sand")
	if dig_target != Vector2i.ZERO:
		var dig: Dictionary = character.dig_immediate_for_test(dig_target)
		_check(not bool(dig.changed) and bool(dig.conserved) and int(dig.physical_output) == 2, "fresh Dig keeps already-physical Raw Sand")
	var build_cell := spawn + Vector2i(6, -1)
	_check(character.can_build_cells([build_cell]), "fresh Character build cell in range")
	_check(world.place_structure(2, build_cell, 0) > 0, "fresh Character builds primitive Conveyor")
	var before_jetpack := character.position_milli.y
	for tick in range(30):
		character.replay_step(KoalaCharacterController.INPUT_JETPACK | KoalaCharacterController.INPUT_RIGHT)
	_check(character.position_milli.y < before_jetpack and character.position_milli.x > 0, "fresh Basic Jetpack explores from tick 0")
	var cave_cell := Vector2i.ZERO
	for x in range(64, 137):
		for y in range(spawn.y + 24, spawn.y + 145):
			if world.get_cell(Vector2i(x, y)) == 0:
				cave_cell = Vector2i(x, y)
				break
		if cave_cell != Vector2i.ZERO:
			break
	_check(cave_cell != Vector2i.ZERO, "corrected early cave exists")
	if cave_cell != Vector2i.ZERO:
		world.update_character_visibility(KoalaCharacterController.VISIBILITY_OWNER_ID, cave_cell, 72, 8)
		_check(world.is_cell_discovered(1, cave_cell), "fresh Character discovers early cave through FOV")
	world.set_game_mode(1)
	world.credit_research_material_for_test(10, 10000)
	world.credit_research_material_for_test(11, 1000)
	world.credit_research_material_for_test(12, 10)
	world.set_game_mode(0)
	_check(world.try_unlock_research("mobility.sprint"), "fresh loop unlocks Sprint")
	_check(world.try_unlock_research("automation.basic_sensing"), "fresh loop unlocks sensing prerequisite")
	_check(world.try_unlock_research("mobility.hover"), "fresh loop reaches Hover")
	character._refresh_unlocks()
	_check(character.sprint_unlocked and character.hover_unlocked, "fresh mobility progression applied to Character")
	character.free()
	camera.free()


func _new_v2_world(seed: int, workers: int) -> Variant:
	var world := NativeSandWorld.new()
	var settings := V2_SETTINGS.duplicate(true)
	settings.seed = seed
	world.configure_world(settings, workers)
	return world


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [label, expected, actual])
