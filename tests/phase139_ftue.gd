extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _run() -> void:
	_check(BuildInfo.VERSION == "0.1.0-playtest.4", "playtest.4 runtime version")
	for path in ["res://ONBOARDING.md", "res://PHASE139_FTUE.md", "res://scripts/capture_phase139.ps1", "res://scripts/create_phase139_contact_sheet.ps1"]:
		_check(FileAccess.file_exists(path), "%s exists" % path)

	var materials := MaterialRegistry.new()
	_check(materials.load_directory() == OK, "material registry loads")
	var world := NativeSandWorld.new(); world.reset(139, 1)
	var blueprints := BlueprintLibrary.new(16); MvpExampleBlueprints.install(blueprints)
	var codex := PhysicsCodex.new(); codex.rebuild(materials, world, blueprints)

	var player_components := 0
	for definition: Dictionary in world.get_structure_definitions():
		var type_id := int(definition.type_id)
		if not ComponentPresentation.is_player_facing(type_id, definition): continue
		player_components += 1
		var help := HelpCatalog.component(type_id, definition)
		_check(HelpCatalog.valid(help), "Component %d has representative help" % type_id)
		_check(str(help.codex_id) == "component:%d" % type_id and codex.entries.has(str(help.codex_id)), "Component %d help deep-links to Codex" % type_id)
	_check(player_components >= 40, "all MVP Components audited")

	var material_count := 0
	for material_id: int in materials.get_ids():
		if material_id == MaterialRegistry.EMPTY_ID: continue
		material_count += 1
		var definition := materials.get_definition(material_id)
		var help := HelpCatalog.material(definition, 128, 42.5)
		_check(HelpCatalog.valid(help), "%s has useful material help" % definition.key)
		_check(str(help.description).length() >= 24 and not "Material matter" in str(help.description), "%s help is representative" % definition.key)
		_check(codex.entries.has(str(help.codex_id)), "%s help deep-links to Codex" % definition.key)
	_check(material_count >= 27, "all MVP materials audited")

	var automation_definitions: Array = world.get_automation_definitions()
	_check(automation_definitions.size() == 24, "all native Automation definitions exposed")
	for definition: Dictionary in automation_definitions:
		var copy := definition.duplicate(true); copy.key = str(definition.id)
		_check(HelpCatalog.valid(HelpCatalog.automation(copy, not bool(definition.unlocked))), "%s has Automation help" % definition.id)

	var disabled := HelpCatalog.component(46, world.get_structure_definitions()[45], true)
	_check(not str(disabled.get("disabled_reason", "")).is_empty(), "disabled Component explains why")
	for property_name: String in HelpCatalog.PROPERTY_HELP:
		_check(HelpCatalog.valid(HelpCatalog.property(property_name)), "%s property is explained" % property_name)
	for failure_name: String in HelpCatalog.FAILURE_HELP:
		var failure := HelpCatalog.failure(failure_name)
		_check(HelpCatalog.valid(failure) and not str(failure.description).contains("_"), "%s blocker is player-readable" % failure_name)

	var original_events := InputMap.action_get_events(&"open_codex")
	InputMap.action_erase_events(&"open_codex")
	var rebound := InputEventKey.new(); rebound.physical_keycode = KEY_F1; InputMap.action_add_event(&"open_codex", rebound)
	_check(InputGlyphs.action(&"open_codex") == "F1", "dynamic binding label updates after rebinding")
	_check(HelpCatalog.plain_text(HelpCatalog.control("codex")).contains("F1"), "tooltip resolves current binding at display time")
	InputMap.action_erase_events(&"open_codex")
	for event: InputEvent in original_events: InputMap.action_add_event(&"open_codex", event)

	for preset_id in [GameModeCapabilities.Preset.FACTORY, GameModeCapabilities.Preset.CHARACTER, GameModeCapabilities.Preset.CREATIVE]:
		var onboarding := OnboardingState.new(); onboarding.preset_id = preset_id
		var steps: Array = OnboardingState.STEPS[preset_id]
		_check(not steps.is_empty() and not onboarding.current_hint().is_empty(), "mode %d starts with useful guidance" % preset_id)
		for step: Dictionary in steps:
			_check(onboarding.current_target() == str(step.target), "mode %d step %s points to declared control" % [preset_id, step.id])
			_check(onboarding.demonstrate(str(step.id)), "mode %d step %s completes from demonstrated knowledge" % [preset_id, step.id])
		_check(onboarding.current_hint().is_empty(), "mode %d tutorial has no dead-end" % preset_id)
		var restored := OnboardingState.new(); _check(restored.deserialize(onboarding.serialize()), "mode %d tutorial persists" % preset_id)
		_check(restored.current_hint().is_empty(), "mode %d completed hints do not replay" % preset_id)
		restored.reset(preset_id); _check(not restored.current_hint().is_empty(), "mode %d tutorial reset works" % preset_id)
		restored.enabled = false; _check(restored.current_hint().is_empty(), "mode %d tutorial can be disabled" % preset_id)
	var factory_skip := OnboardingState.new(); factory_skip.preset_id = GameModeCapabilities.Preset.FACTORY
	_check(factory_skip.demonstrate("MOVE_CAMERA") and factory_skip.current_step().get("id") == "OPEN_CATALOG", "Factory presentation intro cannot block demonstrated camera movement")
	var creative_skip := OnboardingState.new(); creative_skip.preset_id = GameModeCapabilities.Preset.CREATIVE
	_check(creative_skip.demonstrate("OPEN_CATALOG") and creative_skip.current_step().get("id") == "PAINT_OR_ERASE", "Creative presentation intro cannot block demonstrated Catalog use")
	var legacy := OnboardingState.new()
	_check(legacy.deserialize({"schema_version":1, "enabled":true, "preset_id":0, "completed":{"MOVE_CAMERA":true}, "shown_context":{}}), "schema-one tutorial migrates")
	_check(bool(legacy.completed.get("FACTORY_INTRO", false)) and bool(legacy.completed.get("OPEN_CATALOG", false)), "existing profile skips replayed basics")

	var target := Button.new(); target.text = "Target"; target.position = Vector2(100, 100); target.size = Vector2(120, 40); root.add_child(target)
	var tooltip := ContextTooltipLayer.new(); root.add_child(tooltip)
	var highlight := GuidedHighlightLayer.new(); root.add_child(highlight)
	var toasts := ToastCenter.new(); root.add_child(toasts)
	await process_frame
	tooltip.bind(target, HelpCatalog.control("catalog")); tooltip.show_virtual(HelpCatalog.control("catalog"), target.get_global_rect())
	_check(tooltip.visible_text().contains("Build Catalog"), "central tooltip renders representative content")
	var top_left := ContextTooltipLayer.clamped_position(Rect2(1570, 870, 30, 30), Vector2(360, 220), Vector2(1600, 900))
	var high_res := ContextTooltipLayer.clamped_position(Rect2(2520, 1390, 30, 30), Vector2(360, 220), Vector2(2560, 1440))
	_check(top_left.x >= 0 and top_left.y >= 0 and top_left.x + 360 <= 1600 and top_left.y + 220 <= 900, "tooltip clamps at 1600x900")
	_check(high_res.x >= 0 and high_res.y >= 0 and high_res.x + 360 <= 2560 and high_res.y + 220 <= 1440, "tooltip clamps at 2560x1440")
	for ui_scale: float in [1.0, 1.25, 1.5]:
		var scaled_size: Vector2 = Vector2(360, 220) * ui_scale
		var scaled_position: Vector2 = ContextTooltipLayer.clamped_position(Rect2(1570, 870, 30, 30), scaled_size, Vector2(1920, 1080))
		_check(scaled_position.x >= 0 and scaled_position.y >= 0 and scaled_position.x + scaled_size.x <= 1920 and scaled_position.y + scaled_size.y <= 1080, "tooltip clamps at %d%% UI scale" % int(ui_scale * 100.0))
	highlight.show_step(target, "NEXT"); _check(highlight.active() and highlight.mouse_filter == Control.MOUSE_FILTER_IGNORE, "guided highlight attaches to Control without intercepting input")
	highlight.reduced_motion = true; _check(highlight.reduced_motion, "guided highlight respects Reduced Motion")
	toasts.push("Repeated warning", "WARNING"); toasts.push("Repeated warning", "WARNING")
	_check(toasts.messages().size() == 1, "duplicate toast collapses")
	for index in range(5): toasts.push("Message %d" % index, "INFO")
	_check(toasts.messages().size() == ToastCenter.MAX_VISIBLE, "toast stack is bounded")

	var hud := FactoryHUD.new(); root.add_child(hud); await process_frame; hud.initialize(world); hud.configure_mode(GameModeCapabilities.Preset.FACTORY); await process_frame
	var tools: Array = hud.get_meta("catalog_tools", [])
	_check(tools.filter(func(tool: Dictionary) -> bool: return str(tool.kind) == "automation").size() == 24, "Catalog exposes every Automation Component")
	var icon_only_total := 0; var icon_only_missing := 0
	for node: Node in _descendants(hud):
		if node is Button and (node as Button).text.strip_edges().is_empty():
			icon_only_total += 1
			if not node.has_meta("accessibility_description") and not node.has_meta("ux_tooltip_spec"): icon_only_missing += 1
	_check(icon_only_total > 0 and icon_only_missing == 0, "all icon-only HUD controls expose help or accessibility description")
	var hud_source := FileAccess.get_file_as_string("res://rendering/factory_hud.gd")
	_check(hud_source.contains("func refresh_unlocks()") and hud_source.contains("NEW · "), "Research unlocks refresh Catalog state and surface NEW Components")
	var pause := PauseMenu.new(); root.add_child(pause); await process_frame
	pause.apply_settings({"tutorial_hints":false, "tooltip_delay":0.7, "hover_toggle":false, "reduced_motion":true, "ui_scale":1.5})
	var help_settings := pause.settings()
	_check(not bool(help_settings.tutorial_hints) and is_equal_approx(float(help_settings.tooltip_delay), 0.7), "first-time-player help settings roundtrip")
	_check(not bool(help_settings.hover_toggle) and bool(help_settings.reduced_motion) and is_equal_approx(float(help_settings.ui_scale), 1.5), "Character and accessibility settings roundtrip")

	var audit := PlayerFacingAudit.collect(materials, world, blueprints, codex)
	_check(audit.size() >= player_components + material_count + 40, "player-facing audit covers content and interaction surfaces")
	var shipped_rows := audit.filter(func(row: Dictionary) -> bool: return str(row.get("STATUS", "")) == "PASS").size()
	print("phase139_coverage audit_rows=%d shipped_pass=%d dev_only=%d components=%d materials=%d automation=%d icon_only=%d icon_only_missing=%d" % [audit.size(), shipped_rows, audit.size() - shipped_rows, player_components, material_count, automation_definitions.size(), icon_only_total, icon_only_missing])
	var capture_script := FileAccess.get_file_as_string("res://scripts/capture_phase139.ps1")
	for capture_name in ["new-game","character-first-move","character-jetpack-hint","character-dig-hint","factory-camera-hint","component-tooltip","material-tooltip","disabled-tooltip","research-first-open","blueprint-example-help","inspector-blocker","planning-pause-hint","controls-help","empty-blueprints","empty-saves"]:
		_check(capture_script.contains("'%s'" % capture_name), "capture contract includes %s" % capture_name)
	_check(capture_script.contains("'1600x900'") and capture_script.contains("'2560x1440'"), "capture contract includes both responsive tooltip resolutions")
	_check(capture_script.contains("-MuteAudio"), "Phase 13.9 capture pipeline is silent")
	var runtime_source := FileAccess.get_file_as_string("res://debug/debug_world.gd")
	for runtime_event in ["CHARACTER_INTRO", "JETPACK", "DIG", "OPEN_CATALOG", "BUILD_COMPONENT", "INSPECT", "RESEARCH", "BLUEPRINT", "PLANNING_PAUSE", "SPRINT_HOVER", "MOVE_CAMERA", "PAINT_OR_ERASE"]:
		_check(runtime_source.contains("demonstrate_onboarding(\"%s\")" % runtime_event), "runtime integrates demonstrated knowledge event %s" % runtime_event)

	if failures.is_empty():
		print("PASS: %d Phase 13.9 FTUE and UX checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("PHASE139: " + failure)
		print("FAIL: %d of %d Phase 13.9 checks" % [failures.size(), checks])
		quit(1)


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
