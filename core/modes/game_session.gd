class_name GameSession
extends RefCounted

const SCHEMA_VERSION := 1

var control_mode := GameModeCapabilities.ControlMode.GOD
var progression_mode := GameModeCapabilities.ProgressionMode.NORMAL
var visibility_policy := GameModeCapabilities.VisibilityPolicy.OMNISCIENT
var capabilities: Dictionary = {}
var preset_id := GameModeCapabilities.Preset.FACTORY


func apply_preset(next_preset: GameModeCapabilities.Preset) -> void:
	preset_id = next_preset
	var axes := GameModeCapabilities.preset(next_preset)
	control_mode = int(axes.control_mode)
	progression_mode = int(axes.progression_mode)
	visibility_policy = int(axes.visibility_policy)
	capabilities = GameModeCapabilities.capabilities(control_mode, progression_mode, visibility_policy)


func serialize() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"preset_id": preset_id,
		"control_mode": control_mode,
		"progression_mode": progression_mode,
		"visibility_policy": visibility_policy,
	}


func deserialize(state: Dictionary) -> bool:
	if int(state.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	control_mode = clampi(int(state.get("control_mode", 0)), 0, 2)
	progression_mode = clampi(int(state.get("progression_mode", 0)), 0, 1)
	visibility_policy = clampi(int(state.get("visibility_policy", 0)), 0, 2)
	preset_id = clampi(int(state.get("preset_id", 0)), 0, 2)
	capabilities = GameModeCapabilities.capabilities(control_mode, progression_mode, visibility_policy)
	return true
