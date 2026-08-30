class_name OnboardingState
extends RefCounted

const SCHEMA_VERSION := 2
const LEGACY_STEP_IDS := {
	"MOVE":"CHARACTER_INTRO",
	"SELECT_TOOL":"OPEN_CATALOG",
	"BUILD_CONVEYOR":"BUILD_COMPONENT",
	"PLACE_STRUCTURE":"BUILD_COMPONENT",
	"BUILD":"BUILD_COMPONENT",
	"PAUSE_OR_SPEED":"PLANNING_PAUSE",
}
const STEPS := {
	GameModeCapabilities.Preset.FACTORY: [
		{"id":"FACTORY_INTRO", "target":"catalog", "text":"Factory Mode: plan and build anywhere. Research remains active. {catalog} opens Components."},
		{"id":"MOVE_CAMERA", "target":"status", "text":"Move the camera with middle-drag or the movement keys; use the wheel to zoom."},
		{"id":"OPEN_CATALOG", "target":"catalog", "text":"Open the Build Catalog with {catalog}; locked entries explain their Research requirement."},
		{"id":"BUILD_COMPONENT", "target":"quickbar", "text":"Choose a Component, then place it in the world. Matter never enters a hidden inventory."},
		{"id":"PLANNING_PAUSE", "target":"planning_pause", "text":"Use {planning_pause} to freeze physics while you inspect and build."},
		{"id":"INSPECT", "target":"info", "text":"Use {info_mode}, then select a cell or Component to see live state and blockers."},
		{"id":"RESEARCH", "target":"research", "text":"Open Research with {open_research}; deposit eligible physical outputs in a Research Bank."},
		{"id":"BLUEPRINT", "target":"blueprints", "text":"Blueprints copy ordinary layouts; they never add hidden processing behavior."},
	],
	GameModeCapabilities.Preset.CHARACTER: [
		{"id":"CHARACTER_INTRO", "target":"status", "text":"You are the koala. Move with {move_left}/{move_right}, jump with {jump}; the camera follows you."},
		{"id":"JETPACK", "target":"status", "text":"Hold {jetpack} for the Basic Jetpack. Fuel and movement remain physical."},
		{"id":"DIG", "target":"dig", "text":"Use {character_cut} beside terrain. Excavated matter stays in the world."},
		{"id":"OPEN_CATALOG", "target":"catalog", "text":"Open the Build Catalog with {catalog}; Character Mode enforces visibility and build range."},
		{"id":"BUILD_COMPONENT", "target":"quickbar", "text":"Place a Component inside the visible build range."},
		{"id":"INSPECT", "target":"info", "text":"Use {info_mode} to inspect live physical state and understand a blockage."},
		{"id":"RESEARCH", "target":"research", "text":"Research still requires real processed matter deposited in a Research Bank."},
		{"id":"BLUEPRINT", "target":"blueprints", "text":"Blueprints copy visible ordinary Components; placement still obeys range and Research."},
		{"id":"PLANNING_PAUSE", "target":"planning_pause", "text":"Use {planning_pause} to plan safely without advancing physics."},
		{"id":"SPRINT_HOVER", "target":"controls", "text":"Open Controls to see the current Sprint and Hover bindings."},
	],
	GameModeCapabilities.Preset.CREATIVE: [
		{"id":"CREATIVE_INTRO", "target":"catalog", "text":"Creative removes progression friction, not physical simulation."},
		{"id":"OPEN_CATALOG", "target":"catalog", "text":"Open {catalog} to choose materials and Components."},
		{"id":"PAINT_OR_ERASE", "target":"quickbar", "text":"Paint or erase matter directly; placed matter still flows, burns and exchanges heat."},
		{"id":"BUILD_COMPONENT", "target":"quickbar", "text":"Place Components freely and observe their ordinary physical interactions."},
		{"id":"PLANNING_PAUSE", "target":"planning_pause", "text":"Use {planning_pause} or the speed controls when comparing a setup."},
	],
}

var enabled := true
var preset_id := GameModeCapabilities.Preset.FACTORY
var completed := {}
var shown_context := {}


func reset(next_preset := -1) -> void:
	if next_preset >= 0:
		preset_id = clampi(next_preset, 0, 2)
	completed.clear()
	shown_context.clear()


func complete(goal: String) -> void:
	completed[str(LEGACY_STEP_IDS.get(goal, goal))] = true


func demonstrate(event_id: String) -> bool:
	var changed := false
	var current := current_step()
	var current_id := str(current.get("id", ""))
	if current_id in ["FACTORY_INTRO", "CREATIVE_INTRO"] and event_id != current_id:
		complete(current_id)
		changed = true
	for step: Dictionary in STEPS[preset_id]:
		if str(step.id) == event_id:
			changed = not bool(completed.get(event_id, false)) or changed
			complete(event_id)
			return changed
	return changed


func current_step() -> Dictionary:
	if not enabled:
		return {}
	for step: Dictionary in STEPS[preset_id]:
		if not bool(completed.get(str(step.id), false)):
			return step.duplicate(true)
	return {}


func current_hint() -> String:
	var step := current_step()
	return _expand_bindings(str(step.get("text", "")))


func current_target() -> String:
	return str(current_step().get("target", ""))


func context_once(context: String, message: String) -> String:
	if not enabled or bool(shown_context.get(context, false)):
		return ""
	shown_context[context] = true
	return message


func serialize() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "enabled": enabled, "preset_id": preset_id, "completed": completed.duplicate(true), "shown_context": shown_context.duplicate(true)}


func deserialize(state: Dictionary) -> bool:
	var schema := int(state.get("schema_version", 0))
	if schema not in [1, SCHEMA_VERSION]:
		return false
	enabled = bool(state.get("enabled", true))
	preset_id = clampi(int(state.get("preset_id", 0)), 0, 2)
	completed = Dictionary(state.get("completed", {})).duplicate(true)
	shown_context = Dictionary(state.get("shown_context", {})).duplicate(true)
	if schema == 1:
		_migrate_schema_one()
	return true


func _migrate_schema_one() -> void:
	# Existing players retain their progress and do not replay basic prompts.
	for basic in ["FACTORY_INTRO", "CHARACTER_INTRO", "CREATIVE_INTRO", "MOVE_CAMERA", "OPEN_CATALOG"]:
		completed[basic] = true
	for old_id: String in LEGACY_STEP_IDS:
		if bool(completed.get(old_id, false)):
			completed[str(LEGACY_STEP_IDS[old_id])] = true


func _expand_bindings(text: String) -> String:
	var result := text
	var actions := ["catalog", "planning_pause", "info_mode", "open_research", "move_left", "move_right", "jump", "jetpack", "character_cut"]
	for action: String in actions:
		var input_action := "build_catalog" if action == "catalog" else action
		result = result.replace("{%s}" % action, InputGlyphs.action(StringName(input_action)))
	return result
