class_name CharacterAccessibilityPreferences
extends RefCounted

const SCHEMA_VERSION := 1

var hover_toggle := true
var reduced_motion := false
var screen_shake := true
var ui_scale := 1.0


func serialize() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"hover_toggle": hover_toggle,
		"reduced_motion": reduced_motion,
		"screen_shake": screen_shake,
		"ui_scale": ui_scale,
	}


func deserialize(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	hover_toggle = bool(state.get("hover_toggle", true))
	reduced_motion = bool(state.get("reduced_motion", false))
	screen_shake = bool(state.get("screen_shake", true))
	ui_scale = clampf(float(state.get("ui_scale", 1.0)), 0.75, 2.0)
	return true
