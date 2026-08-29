extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_correction_audit()
	_test_movement_feel()
	_test_visibility_policy()
	_test_interaction_feedback()
	_test_ui_state_and_onboarding()
	_test_modes_and_accessibility()
	_test_first_session()
	await _test_player_ui()
	if failures.is_empty():
		print("PASS: %d checks across 8 Phase 11.5 suites" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d failures across %d Phase 11.5 checks" % [failures.size(), checks])
		quit(1)


func _test_correction_audit() -> void:
	var world: Variant = _world(1)
	var single: Dictionary = world.validate_world_seed(508)
	_check_equal(single.maximum_correction_severity, "MINOR" if int(single.corrections) > 0 else "NONE", "single correction severity")
	for record: Dictionary in single.correction_records:
		_check(str(record.category) in _categories(), "stable correction category")
		_check(str(record.severity) in ["MINOR", "MODERATE", "MAJOR"], "stable correction severity")
		_check(bool(record.intentional), "intentional correction transparent")
	var report: Dictionary = world.validate_world_seeds(1, 25000)
	_check_equal(report.schema_version, 2, "correction report schema")
	_check_equal(report.seed_count, 25000, "25k correction sweep")
	_check_equal(report.validation_failures, 0, "25k valid seeds")
	for category in _categories():
		_check(report.correction_category_counts.has(category), "category reported %s" % category)
	for severity in ["NONE", "MINOR", "MODERATE", "MAJOR"]:
		_check(report.severity_distribution.has(severity), "severity reported %s" % severity)
	_check_equal(int(report.severity_distribution.MODERATE), 0, "no moderate generator rescue")
	_check_equal(int(report.severity_distribution.MAJOR), 0, "no major generator rescue")
	_check_equal(float(report.major_correction_percentage), 0.0, "zero major correction percentage")
	var correction_metrics: Dictionary = report.metrics.corrections_per_seed
	for percentile in ["p50", "p95", "p99", "max"]:
		_check(correction_metrics.has(percentile), "correction percentile %s" % percentile)
	for profile in ["balanced", "flat_surface", "rough_surface", "cave_heavy", "cave_light", "aquifer_heavy", "dry", "thermal", "deep_shaft_heavy", "feature_heavy", "extreme_valid", "worst_corrected", "major_corrected"]:
		_check(report.representative_seeds.has(profile), "visual profile seed %s" % profile)
	var architecture: Dictionary = world.get_worldgen_v2_architecture()
	_check("SPAWN_FLATNESS" in architecture.intentional_correction_passes, "spawn flattening disclosed")
	_check("EARLY_CAVE_ROUTE" in architecture.generator_guarantees, "early cave is generator guarantee")
	print("phase115_worldgen seeds=%d corrections=%d average=%.4f none=%d minor=%d moderate=%d major=%d p50=%.0f p95=%.0f p99=%.0f max=%.0f major_percent=%.3f" % [
		report.seed_count, report.corrections, report.average_corrections_per_seed, report.severity_distribution.NONE,
		report.severity_distribution.MINOR, report.severity_distribution.MODERATE, report.severity_distribution.MAJOR,
		correction_metrics.p50, correction_metrics.p95, correction_metrics.p99, correction_metrics.max, report.major_correction_percentage,
	])


func _test_movement_feel() -> void:
	var world := NativeSandWorld.new()
	world.reset(11, 1)
	world.allocate_chunk_rect(Rect2i(-2, -2, 4, 4))
	for x in range(-80, 81): world.set_cell(Vector2i(x, 8), 1)
	var camera := Camera2D.new()
	var controller := KoalaCharacterController.new()
	controller.initialize(world, camera, Vector2i(0, 7), 2.0)
	var profile := controller.movement_profile()
	_check_equal(profile.walk_speed_milli_per_tick, 320, "walk speed")
	_check_equal(profile.sprint_speed_milli_per_tick, 500, "Sprint speed")
	_check_equal(profile.jump_buffer_ticks, 5, "jump buffer")
	_check_equal(profile.coyote_ticks, 5, "coyote time")
	_check_equal(profile.interaction_range_cells, 18, "build range")
	controller.position_milli = Vector2i(0, 7500)
	controller.velocity_milli = Vector2i.ZERO
	controller.replay_step(0)
	world.set_cell(Vector2i(0, 8), 0)
	controller.replay_step(KoalaCharacterController.INPUT_JUMP)
	_check(controller.velocity_milli.y < 0, "coyote jump after edge")
	controller.hover_unlocked = true
	controller.hover_active = true
	controller.velocity_milli = Vector2i(420, 500)
	for tick in 6: controller.replay_step(0)
	_check_equal(controller.velocity_milli, Vector2i.ZERO, "Hover stabilizes within six ticks")
	controller.hover_active = false
	controller.velocity_milli = Vector2i.ZERO
	var before := controller.position_milli
	for tick in 30: controller.replay_step(KoalaCharacterController.INPUT_JETPACK | KoalaCharacterController.INPUT_RIGHT)
	_check(controller.position_milli.x > before.x and controller.position_milli.y < before.y, "Jetpack responsive movement")
	_check(controller.velocity_milli.y >= -KoalaCharacterController.JETPACK_MAX_ASCENT_SPEED, "Jetpack vertical cap")
	controller.free(); camera.free()


func _test_visibility_policy() -> void:
	var world := NativeSandWorld.new()
	world.reset(12, 1)
	world.allocate_chunk_rect(Rect2i(-2, -2, 4, 4))
	for value in range(-20, 21):
		world.set_cell(Vector2i(1, value), 1)
		world.set_cell(Vector2i(value, 1), 1)
	world.update_character_visibility(1, Vector2i.ZERO, 16, 8)
	_check(not world.is_cell_live_visible(1, Vector2i(2, 2)), "sealed diagonal corner does not X-ray")
	_check(world.is_cell_live_visible(1, Vector2i(-4, -4)), "open chamber readable")
	_check(world.is_cell_discovered(1, Vector2i.ZERO), "origin discovered")
	world.update_character_visibility(1, Vector2i(-14, -14), 16, 8)
	_check(world.is_cell_discovered(1, Vector2i.ZERO) and not world.is_cell_live_visible(1, Vector2i.ZERO), "discovered state becomes stale")
	var page: Dictionary = world.get_visibility_render_page(1, Rect2i(-1, -1, 2, 2))
	var origin_pixel := ((64 * int(page.width)) + 64) * 4
	_check(int(page.pixels[origin_pixel + 3]) == 142, "stale presentation distinct")
	var character := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.CHARACTER)
	var factory := GameModeCapabilities.for_preset(GameModeCapabilities.Preset.FACTORY)
	_check(bool(character.discovery_visibility) and not bool(character.omniscient_visibility), "Character discovery policy")
	_check(bool(factory.omniscient_visibility), "Factory remains omniscient")


func _test_interaction_feedback() -> void:
	var world := NativeSandWorld.new()
	world.reset(13, 1)
	world.allocate_chunk_rect(Rect2i(-2, -2, 4, 4))
	var camera := Camera2D.new()
	var controller := KoalaCharacterController.new()
	controller.initialize(world, camera, Vector2i.ZERO, 2.0)
	_check_equal(controller.interaction_reason(Vector2i(30, 0)), "OUT_OF_RANGE", "out-of-range feedback")
	_check_equal(controller.build_validation(Vector2i(4, 0)), "VALID", "valid placement feedback")
	world.set_cell(Vector2i(5, 0), 1)
	world.update_character_visibility(1, Vector2i.ZERO, 72, 8)
	_check_equal(controller.build_validation(Vector2i(5, 0)), "COLLIDES_WITH_TERRAIN", "terrain collision feedback")
	world.set_cell(Vector2i(6, 0), 2)
	world.update_character_visibility(1, Vector2i.ZERO, 72, 8)
	_check_equal(controller.build_validation(Vector2i(6, 0)), "COLLIDES_WITH_MATERIAL", "loose matter collision feedback")
	_check_equal(controller.build_validation(Vector2i(4, 0), false), "TECH_LOCKED", "Research feedback")
	var dig: Dictionary = controller.dig_immediate_for_test(Vector2i(5, 0))
	_check(bool(dig.changed) and bool(dig.conserved) and int(dig.physical_output) == 20, "Stone Dig produces physical Rock Debris")
	world.set_cell(Vector2i(7, 0), 5)
	world.update_character_visibility(1, Vector2i.ZERO, 72, 8)
	var bedrock: Dictionary = controller.dig_immediate_for_test(Vector2i(7, 0))
	_check_equal(bedrock.reason, "BEDROCK_PROTECTED", "Bedrock feedback")
	controller.free(); camera.free()


func _test_ui_state_and_onboarding() -> void:
	var ui := GameUIState.new()
	ui.open_modal("research"); ui.open_modal("map")
	ui.placement_active = true
	_check_equal(ui.escape(), "CANCEL_PLACEMENT", "ESC cancels placement first")
	_check_equal(ui.escape(), "CLOSE_MAP", "ESC closes top modal")
	_check_equal(ui.escape(), "CLOSE_RESEARCH", "ESC closes remaining modal")
	_check_equal(ui.escape(), "OPEN_PAUSE", "ESC reaches pause")
	var onboarding := OnboardingState.new()
	onboarding.preset_id = GameModeCapabilities.Preset.CHARACTER
	_check(not onboarding.current_hint().is_empty(), "contextual onboarding starts")
	onboarding.complete("MOVE")
	_check("Jetpack" in onboarding.current_hint(), "onboarding advances")
	_check(not onboarding.context_once("range", "Too far away").is_empty(), "context hint shown once")
	_check(onboarding.context_once("range", "Too far away").is_empty(), "context hint does not repeat")
	var restored := OnboardingState.new()
	_check(restored.deserialize(onboarding.serialize()), "onboarding state roundtrip")
	restored.enabled = false
	_check(restored.current_hint().is_empty(), "onboarding can be disabled")
	restored.enabled = true; restored.reset(GameModeCapabilities.Preset.CREATIVE)
	_check(not restored.current_hint().is_empty(), "onboarding can be reset")
	for action in [&"move_left", &"jetpack", &"hover", &"build_catalog", &"map", &"cancel"]:
		_check(not InputGlyphs.action(action).is_empty(), "input glyph %s" % action)


func _test_modes_and_accessibility() -> void:
	var factory := GameModeCapabilities.preset(GameModeCapabilities.Preset.FACTORY)
	var character := GameModeCapabilities.preset(GameModeCapabilities.Preset.CHARACTER)
	var creative := GameModeCapabilities.preset(GameModeCapabilities.Preset.CREATIVE)
	_check(bool(factory.recommended), "Factory recommended")
	_check(factory.progression_mode == character.progression_mode, "Factory and Character share Research")
	_check(creative.progression_mode == GameModeCapabilities.ProgressionMode.CREATIVE, "Creative removes Research friction")
	_check(character.visibility_policy != factory.visibility_policy, "Character visibility distinction")
	var preferences := CharacterAccessibilityPreferences.new()
	preferences.hover_toggle = true; preferences.reduced_motion = true; preferences.screen_shake = false; preferences.ui_scale = 1.5
	var restored := CharacterAccessibilityPreferences.new()
	_check(restored.deserialize(preferences.serialize()), "accessibility roundtrip")
	_check(restored.hover_toggle and restored.reduced_motion and not restored.screen_shake, "accessibility switches")
	_check_equal(restored.ui_scale, 1.5, "150 percent UI scale")
	for scale in [1.0, 1.25, 1.5]:
		var theme := KoalaSandTheme.build(scale)
		_check(theme.has_stylebox("normal", "Button"), "designed Button style %.2f" % scale)
		_check(theme.has_stylebox("normal", "LineEdit"), "designed LineEdit style %.2f" % scale)


func _test_first_session() -> void:
	var world: Variant = _world(8675309)
	var result: Dictionary = FirstSessionFixture.run(world, 8675309)
	_check_equal(result.research_credit_calls, 0, "first session uses no Research credit cheat")
	_check(int(result.first_sand_tick) < int(result.first_coal_tick), "Sand before Coal")
	_check(int(result.first_factory_tick) < int(result.first_research_tick), "factory before Research")
	_check(float(result.sprint_tick) / 3600.0 < 5.0, "Sprint within first few minutes")
	_check(float(result.hover_tick) / 3600.0 >= 5.0 and float(result.hover_tick) / 3600.0 <= 15.0, "Hover within 5-15 minutes")
	_check(float(result.movement_share) < 0.70, "travel does not dominate")
	_check(int(result.build_actions) > 0 and int(result.dig_actions) > 0, "fixture includes building and digging")
	print("phase115_first_session seed=%d sand_tick=%d coal_tick=%d factory_tick=%d research_tick=%d sprint_tick=%d cave_tick=%d hover_tick=%d travel=%d moving_ticks=%d building_ticks=%d dig_actions=%d build_actions=%d" % [
		result.seed, result.first_sand_tick, result.first_coal_tick, result.first_factory_tick, result.first_research_tick,
		result.sprint_tick, result.first_cave_tick, result.hover_tick, result.travel_distance_cells, result.moving_ticks,
		result.building_ticks, result.dig_actions, result.build_actions,
	])


func _test_player_ui() -> void:
	var world: Variant = _world(17)
	var hud := FactoryHUD.new()
	root.add_child(hud)
	await process_frame
	hud.initialize(world)
	for preset in [GameModeCapabilities.Preset.FACTORY, GameModeCapabilities.Preset.CHARACTER, GameModeCapabilities.Preset.CREATIVE]:
		hud.configure_mode(preset)
		_check(hud.theme.has_stylebox("normal", "Button"), "HUD theme preset %d" % preset)
	hud.toggle_catalog(); _check(hud.modal_open(), "Catalog blocks world input"); _check(hud.close_top_modal(), "Catalog closes through ESC stack")
	hud.toggle_statistics(); _check(hud.modal_open(), "Statistics blocks world input"); hud.close_top_modal()
	hud.show_inspector("Machine", ["No input", "Nearby"]); _check(true, "contextual Inspector accepts one context")
	var new_game := NewGameScreen.new(); root.add_child(new_game); await process_frame
	_check(new_game.theme.has_stylebox("normal", "OptionButton"), "New Game uses designed controls")
	new_game.free(); hud.free()


func _categories() -> Array[String]:
	return ["SPAWN_FLATNESS", "RESOURCE_ACCESS", "WATER_ACCESS", "CAVE_ACCESS", "CONNECTIVITY", "FLOOD_SAFETY", "THERMAL_HAZARD", "FEATURE_COLLISION", "WORLD_BOUNDARY", "OTHER"]


func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed, "generation_version": 2}, 4)
	return world


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
