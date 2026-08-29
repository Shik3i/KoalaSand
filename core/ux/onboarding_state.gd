class_name OnboardingState
extends RefCounted

const SCHEMA_VERSION := 1
const GOALS := {
	GameModeCapabilities.Preset.FACTORY: ["MOVE_CAMERA", "BUILD_CONVEYOR", "BUILD_SCREEN", "DEPOSIT_RESEARCH", "UNLOCK_RESEARCH"],
	GameModeCapabilities.Preset.CHARACTER: ["MOVE", "JETPACK", "DIG", "DISCOVER_CAVE", "PLACE_STRUCTURE", "PROCESS", "RESEARCH"],
	GameModeCapabilities.Preset.CREATIVE: ["SELECT_TOOL", "PAINT_OR_ERASE", "BUILD", "PAUSE_OR_SPEED"],
}
const COPY := {
	"MOVE_CAMERA": "Move the view, then choose a build tool.",
	"BUILD_CONVEYOR": "Place a Conveyor to start a physical route.",
	"BUILD_SCREEN": "Fine material can pass through Mesh; a separate Vibration Actuator keeps it moving.",
	"DEPOSIT_RESEARCH": "Route processed material into a Research Bank.",
	"UNLOCK_RESEARCH": "A technology is ready to unlock.",
	"MOVE": "Move through the world.",
	"JETPACK": "Use the Basic Jetpack to gain height.",
	"DIG": "Dig nearby terrain; excavated matter remains physical.",
	"DISCOVER_CAVE": "Open or enter a cave to reveal it.",
	"PLACE_STRUCTURE": "Place a structure in the visible build range.",
	"PROCESS": "Build a small physical processing line.",
	"RESEARCH": "Deposit processed material and unlock Research.",
	"SELECT_TOOL": "Choose a material or structure.",
	"PAINT_OR_ERASE": "Paint or erase terrain with Creative tools.",
	"BUILD": "Place any structure without Research friction.",
	"PAUSE_OR_SPEED": "Pause or change simulation speed when useful.",
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
	completed[goal] = true


func current_hint() -> String:
	if not enabled:
		return ""
	for goal: String in GOALS[preset_id]:
		if not bool(completed.get(goal, false)):
			return str(COPY.get(goal, goal))
	return ""


func context_once(context: String, message: String) -> String:
	if not enabled or bool(shown_context.get(context, false)):
		return ""
	shown_context[context] = true
	return message


func serialize() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "enabled": enabled, "preset_id": preset_id, "completed": completed.duplicate(true), "shown_context": shown_context.duplicate(true)}


func deserialize(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	enabled = bool(state.get("enabled", true))
	preset_id = clampi(int(state.get("preset_id", 0)), 0, 2)
	completed = Dictionary(state.get("completed", {})).duplicate(true)
	shown_context = Dictionary(state.get("shown_context", {})).duplicate(true)
	return true
