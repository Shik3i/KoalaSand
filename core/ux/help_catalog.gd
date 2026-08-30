class_name HelpCatalog
extends RefCounted

const MATERIAL_BEHAVIOR := {
	&"raw_sand": "Mixed granular sediment. Screen, wash, separate magnetically or heat it to reveal useful fractions.",
	&"fine_sand": "Fine granular material that can pass through a suitable Mesh aperture.",
	&"heavy_concentrate": "Dense granular fraction enriched by screening or flowing Water; its exact hidden composition remains unreported.",
	&"nonmagnetic_concentrate": "Granular concentrate left after susceptible material responds to a magnetic field.",
	&"iron_concentrate": "Magnetically susceptible granular concentrate that can be heated and reduced physically.",
	&"crude_residue": "Mixed processing residue. It remains ordinary conserved matter and may still respond to later separation.",
	&"rock_debris": "Coarse mineral fragments that resist fine screening and can obstruct narrow paths.",
	&"stone": "Dense solid terrain and construction matter that blocks ordinary flow.",
	&"bedrock": "Permanent world boundary material that normal tools cannot remove.",
	&"coal": "Combustible granular carbon-bearing material that releases heat, Smoke and Ash with enough oxidizer.",
	&"coal_chunk": "A coarse combustible piece of Coal that can be moved, broken and burned.",
	&"wood": "Combustible organic solid. Heating with limited fresh air can leave Charcoal.",
	&"leaves": "Light combustible organic matter that ignites readily and carries moisture.",
	&"charcoal": "Carbon-rich solid made by heating Wood while limiting fresh air; burns hotter than wet Wood.",
	&"ash": "Non-combustible granular residue left after fuel reactions.",
	&"smoke": "Hot gas and particles that rise, spread and leave through open geometry.",
	&"water": "Conserved liquid that flows, carries grains, fills vessels and becomes Steam when heated.",
	&"ice": "Solid Water that melts when local temperature rises.",
	&"steam": "Hot gaseous Water. It expands, builds pressure and can drive a Turbine before condensing.",
	&"glass": "Solid heat-formed material that can melt again and must cool into shape.",
	&"molten_glass": "Hot flowing Glass. Contain and cool it physically; no hidden casting recipe exists.",
	&"iron": "Dense solid metal recovered from susceptible mineral matter through separation and heat.",
	&"molten_iron": "Hot flowing Iron that must be contained, shaped and cooled physically.",
	&"gold": "Very dense nonmagnetic metal. Flowing Water can concentrate its grains without creating them.",
	&"raw_food": "Moist organic food that changes gradually as heat reaches it.",
	&"cooked_food": "Food heated through a useful temperature range; continued heating can burn it.",
	&"burnt_food": "Overheated organic residue with little remaining food value.",
}

const AUTOMATION_BEHAVIOR := {
	"manual_switch": "Provides a player-controlled signal for connected Automation.",
	"material_sensor": "Samples nearby physical cells and signals when configured material is present.",
	"level_sensor": "Measures how full a configured physical region is.",
	"not": "Outputs the opposite of its input signal.",
	"and": "Outputs a signal only while both inputs are active.",
	"or": "Outputs a signal while either input is active.",
	"comparator": "Compares an input value with a configured threshold.",
	"machine_state_sensor": "Reads the live state or blocker of a targeted Component.",
	"timer": "Generates a deterministic timed signal from simulation ticks.",
	"latch": "Remembers a signal until its reset input changes that state.",
	"conveyor_control": "Enables or stops a targeted Conveyor without moving material internally.",
	"machine_control": "Enables or stops a targeted powered Component.",
	"control_gate": "Opens or closes a physical Control Gate from a signal.",
	"pump_enable": "Enables a targeted Pump when its input signal is active.",
	"pipe_valve": "Opens or closes a targeted Pipe Valve from a signal.",
	"flow_meter": "Measures current physical flow through a targeted Pipe segment.",
	"pipe_fill_sensor": "Measures contained mass in a targeted Pipe segment.",
	"temperature_sensor": "Measures local world temperature in a configured region.",
	"pipe_temperature_sensor": "Measures the temperature of contained Pipe material.",
	"pipe_pressure_sensor": "Measures local pressure in a targeted Pipe segment.",
	"thermal_switch": "Opens or closes a targeted Thermal Switch from a signal.",
	"power_network_sensor": "Measures generation, demand or satisfaction on a targeted electrical network.",
	"shaft_speed_sensor": "Measures rotational speed on a targeted Shaft network.",
	"power_switch": "Connects or separates a targeted Power Switch from a signal.",
}

const CONTROL_HELP := {
	"pipette": {"title":"Pipette", "description":"Copies the Component and orientation under the pointer for immediate placement.", "shortcut_action":&"pipette", "codex_id":"concept:construction"},
	"planning_pause": {"title":"Planning Pause", "description":"Freezes physics while camera, inspection and construction remain available.", "shortcut_action":&"planning_pause", "codex_id":"concept:construction"},
	"overlay": {"title":"Information overlays", "description":"Shows measured temperature, flow, Automation, underground routes or power without changing physics.", "shortcut_action":&"overlay_selector"},
	"info_mode": {"title":"Info Mode", "description":"Select physical cells and Components to inspect live state and blockers.", "shortcut_action":&"info_mode"},
	"blueprint": {"title":"Blueprint tools", "description":"Copy ordinary Component layouts. Examples contain no hidden machine behavior.", "shortcut_action":&"blueprint", "codex_id":"concept:construction"},
	"map": {"title":"World Map", "description":"Factory shows the generated world; Character shows only live and previously discovered areas.", "shortcut_action":&"map"},
	"experiments": {"title":"Experiments", "description":"Optional physical challenges that teach interactions without required currency rewards.", "shortcut_action":&"open_experiments"},
	"research": {"title":"Research", "description":"Deposit eligible physical outputs in a Research Bank, then choose a capability to unlock.", "shortcut_action":&"open_research", "codex_id":"concept:research"},
	"catalog": {"title":"Build Catalog", "description":"Browse physical Components, see Research requirements and assign tools to the Quickbar.", "shortcut_action":&"build_catalog", "codex_id":"concept:construction"},
	"codex": {"title":"Physics Codex", "description":"Explains known materials, Components and physical principles without revealing hidden geology.", "shortcut_action":&"open_codex"},
	"controls": {"title":"Controls", "description":"Shows the current bindings for movement, construction, inspection and planning."},
	"quickbar_previous": {"title":"Previous Quickbar page", "description":"Shows the previous saved page of Component shortcuts."},
	"quickbar_next": {"title":"Next Quickbar page", "description":"Shows the next saved page of Component shortcuts."},
}

const PROPERTY_HELP := {
	"Aperture": "Largest particle size that can pass through this opening.",
	"Vibration": "Local oscillation that helps physical grains move across a Mesh.",
	"Oxidizer": "Available local atmosphere for combustion, shown from 0 to 255.",
	"Pressure": "Local force from contained fluid or gas mass.",
	"Backpressure": "Downstream pressure opposing flow or Turbine exhaust.",
	"Satisfaction": "Share of requested electrical demand currently delivered.",
	"Throughput": "Physical material or fluid that crossed this system during the measured interval.",
	"Conductivity": "How readily heat passes through this material or Component.",
	"Temperature": "Local thermal state. °C is shown for ordinary play; the simulation stores deterministic fixed-point heat.",
	"MW": "Megawatts of electrical generation, demand or delivery.",
	"mRPM": "Thousandths of a revolution per minute in the deterministic Shaft simulation.",
}

const FAILURE_HELP := {
	"NO VIBRATION": {"title":"No vibration", "description":"A Mesh can pass fine material, but grains move across it much more effectively beside a Vibration Actuator.", "codex_id":"concept:screening"},
	"INSUFFICIENT WATER FLOW": {"title":"Water is not flowing", "description":"Riffles need moving Water to perform density separation.", "codex_id":"concept:wet_separation"},
	"OUTPUT BLOCKED": {"title":"Output blocked", "description":"Physical material cannot disappear. Clear space for the accumulated output.", "codex_id":"concept:flow"},
	"OXYGEN STARVED": {"title":"Not enough oxidizer", "description":"Combustion slows or stops when fresh air cannot reach the fuel.", "codex_id":"concept:combustion"},
	"BELOW REACTION TEMPERATURE": {"title":"Below reaction temperature", "description":"Improve heat input or reduce heat loss before the material can react.", "codex_id":"concept:heat"},
	"NO FLOW OR BACKPRESSURE": {"title":"No flow or backpressure", "description":"Downstream pressure or a closed path is preventing contained mass from moving.", "codex_id":"concept:pressure"},
	"NO STEAM FLOW OR EXHAUST BACKPRESSURE": {"title":"Steam flow limited", "description":"The Turbine needs inlet flow and a lower-pressure exhaust path.", "codex_id":"concept:pressure"},
	"POWER DEFICIT": {"title":"Power deficit", "description":"Demand exceeds available generation and stored electrical energy.", "codex_id":"concept:power"},
}

static func control(id: String, disabled_reason := "") -> Dictionary:
	var result: Dictionary = Dictionary(CONTROL_HELP.get(id, {"title":id.capitalize(), "description":"Player control."})).duplicate(true)
	if not disabled_reason.is_empty(): result.disabled_reason = disabled_reason
	return result

static func component(type_id: int, definition: Dictionary, locked := false) -> Dictionary:
	var detail := ComponentPresentation.describe(type_id, definition)
	var result := {"title":str(detail.name), "description":str(detail.principle), "secondary":str(detail.not_do), "codex_id":"component:%d" % type_id}
	if locked:
		var unlock_key := str(definition.get("unlock_key", "required Research"))
		result.disabled_reason = "Requires Research: %s" % unlock_key
	return result

static func automation(definition: Dictionary, locked := false) -> Dictionary:
	var key := str(definition.get("key", ""))
	var result := {"title":str(definition.get("display_name", key.capitalize())), "description":str(AUTOMATION_BEHAVIOR.get(key, "Reads or changes the physical factory through deterministic signals.")), "codex_id":"concept:automation"}
	if locked: result.disabled_reason = "Requires Research: %s" % str(definition.get("unlock_key", "Automation"))
	return result

static func material(definition: MaterialDefinition, amount := -1, temperature_c := NAN) -> Dictionary:
	var description := str(MATERIAL_BEHAVIOR.get(definition.key, "%s matter governed by local density, heat and flow." % _category_name(definition.category)))
	var state_parts: Array[String] = [_category_name(definition.category)]
	if amount >= 0: state_parts.append("Amount %d / 255" % amount)
	if not is_nan(temperature_c): state_parts.append("%.1f °C" % temperature_c)
	return {"title":definition.display_name, "description":description, "state":" · ".join(state_parts), "codex_id":"material:%s" % definition.key}

static func property(name: String) -> Dictionary:
	return {"title":name, "description":str(PROPERTY_HELP.get(name, "Live physical value measured by the Inspector."))}

static func failure(cause: String) -> Dictionary:
	return Dictionary(FAILURE_HELP.get(cause.to_upper(), {"title":cause.capitalize(), "description":"Inspect the live values and connected physical path to find the cause."})).duplicate(true)

static func attach(control_node: Control, spec: Dictionary) -> void:
	control_node.set_meta("ux_tooltip_spec", spec.duplicate(true))
	control_node.set_meta("accessibility_name", str(spec.get("title", control_node.name)))
	control_node.set_meta("accessibility_description", str(spec.get("description", "")))
	control_node.tooltip_text = ""

static func valid(spec: Dictionary) -> bool:
	var title := str(spec.get("title", "")).strip_edges()
	var description := str(spec.get("description", "")).strip_edges()
	if title.is_empty() or description.length() < 8: return false
	for raw in ["ACTUATOR_MISSING", "STATE_NO_FLOW", "STRUCTURE_ID_", "visibility_policy_", "ERR_CONTENTS_PRESENT"]:
		if raw in title or raw in description: return false
	return true

static func plain_text(spec: Dictionary) -> String:
	var lines: Array[String] = [str(spec.get("title", "")), str(spec.get("description", ""))]
	if not str(spec.get("state", "")).is_empty(): lines.append("State: %s" % str(spec.state))
	if not str(spec.get("disabled_reason", "")).is_empty(): lines.append("Unavailable: %s" % str(spec.disabled_reason))
	if spec.get("shortcut_action", &"") != &"": lines.append("Shortcut: %s" % InputGlyphs.action(StringName(spec.shortcut_action)))
	if not str(spec.get("secondary", "")).is_empty(): lines.append(str(spec.secondary))
	if not str(spec.get("codex_id", "")).is_empty(): lines.append("Open in Codex")
	return "\n".join(lines)

static func _category_name(category: int) -> String:
	return ["Empty", "Solid", "Granular", "Liquid", "Gas", "Molten"][clampi(category, 0, 5)]
