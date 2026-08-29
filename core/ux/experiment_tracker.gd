class_name ExperimentTracker
extends RefCounted

const SCHEMA_VERSION := 1
const DEFINITIONS := [
	{"id":"wet_and_dry", "title":"Wet Sand, Dry Sand", "description":"Make Sand wet and dry it again.", "codex":"concept:wet_separation"},
	{"id":"heavy_concentrate", "title":"Heavy Things Settle", "description":"Separate a heavy concentrate with real flow.", "codex":"component:43"},
	{"id":"physical_charcoal", "title":"Air Changes Fire", "description":"Produce Charcoal without a machine identity.", "codex":"concept:combustion"},
	{"id":"constructed_boil", "title":"Build a Vessel", "description":"Boil Water inside a vessel you constructed.", "codex":"material:water"},
	{"id":"wall_conductivity", "title":"Material Matters", "description":"Make Water boil faster by changing vessel wall material.", "codex":"component:38"},
	{"id":"oxygen_starved", "title":"Starve the Flame", "description":"Reduce local oxidizer until a fire stalls.", "codex":"concept:combustion"},
	{"id":"routed_steam", "title":"Contain the Gas", "description":"Produce Steam and route it into a Pipe.", "codex":"concept:pressure"},
	{"id":"improved_furnace", "title":"Iterate the Furnace", "description":"Modify an example Furnace and improve its measured temperature.", "codex":"component:40"},
]

var completed: Dictionary = {}
var insights: Array[String] = []

func observe(authoritative: Dictionary) -> Array[String]:
	var newly_completed: Array[String] = []
	var rules := {
		"wet_and_dry": int(authoritative.get("wet_then_dry_events", 0)) > 0,
		"heavy_concentrate": int(authoritative.get("heavy_captured", 0)) > 0,
		"physical_charcoal": int(authoritative.get("charcoal_produced", 0)) > 0,
		"constructed_boil": int(authoritative.get("vessel_steam_generated", 0)) > 0,
		"wall_conductivity": int(authoritative.get("vessel_material_comparisons", 0)) > 0,
		"oxygen_starved": int(authoritative.get("oxygen_starved_events", 0)) > 0,
		"routed_steam": int(authoritative.get("pipe_steam_mass", 0)) > 0,
		"improved_furnace": int(authoritative.get("modified_furnace_temperature_gain", 0)) > 0,
	}
	for id: String in rules:
		if bool(rules[id]) and not bool(completed.get(id, false)):
			completed[id] = true; newly_completed.append(id); insights.append(id)
	return newly_completed

func serialize() -> Dictionary:
	return {"schema_version":SCHEMA_VERSION, "completed":completed.duplicate(true), "insights":insights.duplicate()}

func deserialize(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION: return false
	completed = Dictionary(state.get("completed", {})).duplicate(true)
	insights.assign(Array(state.get("insights", [])))
	return true
