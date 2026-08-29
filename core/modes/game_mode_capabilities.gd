class_name GameModeCapabilities
extends RefCounted

enum ControlMode { GOD, CHARACTER, SPECTATOR }
enum ProgressionMode { NORMAL, CREATIVE }
enum VisibilityPolicy { OMNISCIENT, DISCOVERED, TEAM }
enum Preset { FACTORY, CHARACTER, CREATIVE }

# Phase-6.5 compatibility. New code composes the independent axes above.
enum Mode { CREATIVE, CHARACTER, SPECTATOR }

const PRESETS := {
	Preset.FACTORY: {
		"id": "factory", "display_name": "Factory", "recommended": true,
		"control_mode": ControlMode.GOD,
		"progression_mode": ProgressionMode.NORMAL,
		"visibility_policy": VisibilityPolicy.OMNISCIENT,
	},
	Preset.CHARACTER: {
		"id": "character", "display_name": "Character", "recommended": false,
		"control_mode": ControlMode.CHARACTER,
		"progression_mode": ProgressionMode.NORMAL,
		"visibility_policy": VisibilityPolicy.DISCOVERED,
	},
	Preset.CREATIVE: {
		"id": "creative", "display_name": "Creative", "recommended": false,
		"control_mode": ControlMode.GOD,
		"progression_mode": ProgressionMode.CREATIVE,
		"visibility_policy": VisibilityPolicy.OMNISCIENT,
	},
}


static func preset(preset_id: Preset) -> Dictionary:
	return (PRESETS.get(preset_id, PRESETS[Preset.FACTORY]) as Dictionary).duplicate(true)


static func capabilities(control_mode: ControlMode, progression_mode: ProgressionMode, visibility_policy: VisibilityPolicy) -> Dictionary:
	var mutates_world := control_mode != ControlMode.SPECTATOR
	var character := control_mode == ControlMode.CHARACTER
	var creative := progression_mode == ProgressionMode.CREATIVE
	return {
		"free_camera": control_mode != ControlMode.CHARACTER,
		"control_character": character,
		"creative_paint": mutates_world and creative,
		"creative_erase": mutates_world and creative,
		"world_regenerate": control_mode == ControlMode.GOD and creative,
		"place_structures": mutates_world,
		"configure_structures": mutates_world,
		"unlock_research": mutates_world,
		"build_anywhere": control_mode == ControlMode.GOD,
		"build_in_range": character,
		"omniscient_visibility": visibility_policy == VisibilityPolicy.OMNISCIENT,
		"discovery_visibility": visibility_policy in [VisibilityPolicy.DISCOVERED, VisibilityPolicy.TEAM],
		"remote_view": false,
		"remote_build": false,
		"jetpack": character,
		"dig": character,
		"commands": mutates_world,
		"research": mutates_world,
		"build": mutates_world,
		"character": character,
		"world_edit": mutates_world and creative,
	}


static func for_preset(preset_id: Preset) -> Dictionary:
	var axes := preset(preset_id)
	return capabilities(axes.control_mode, axes.progression_mode, axes.visibility_policy)


static func for_mode(mode: Mode) -> Dictionary:
	match mode:
		Mode.CREATIVE:
			return for_preset(Preset.CREATIVE)
		Mode.CHARACTER:
			return for_preset(Preset.CHARACTER)
		Mode.SPECTATOR:
			return capabilities(ControlMode.SPECTATOR, ProgressionMode.NORMAL, VisibilityPolicy.DISCOVERED)
	return {}
