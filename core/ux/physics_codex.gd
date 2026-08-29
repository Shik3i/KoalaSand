class_name PhysicsCodex
extends RefCounted

const CATEGORY_NAMES := ["Empty", "Solid", "Granular", "Liquid", "Gas", "Molten"]

var entries: Dictionary = {}
var search_index: Array[Dictionary] = []

func rebuild(materials: MaterialRegistry, world: Variant, blueprints: BlueprintLibrary) -> void:
	entries.clear()
	search_index.clear()
	for material_id in materials.get_ids():
		var definition := materials.get_definition(material_id)
		if definition == null or material_id == 0:
			continue
		_add(_material_entry(definition))
	for raw_definition: Dictionary in world.get_structure_definitions():
		var type_id := int(raw_definition.get("type_id", 0))
		if ComponentPresentation.is_player_facing(type_id, raw_definition):
			_add(_component_entry(world, raw_definition))
	for research: Dictionary in world.get_research_definitions():
		var research_id := str(research.get("id", research.get("research_id", "unknown")))
		var research_name := str(research.get("name", research.get("display_name", research_id.capitalize())))
		var research_summary := str(research.get("description", research.get("summary", "Unlocks new physical capabilities through deposited Research material.")))
		var unlocks := str(research.get("unlock_summary", research.get("unlocks", [])))
		_add({"id":"research:%s" % research_id, "kind":"Research", "title":research_name, "summary":research_summary, "sections":{"UNLOCKS":unlocks}, "tags":["research", research_id], "related":[]})
	for blueprint_id: Variant in blueprints.library.keys():
		var blueprint := blueprints.load_blueprint(str(blueprint_id))
		if blueprint != null:
			_add(_blueprint_entry(blueprint))
	_add_concepts()

func get_entry(id: String) -> Dictionary:
	return Dictionary(entries.get(id, {})).duplicate(true)

func search(query: String, limit := 32) -> Array[Dictionary]:
	var needle := query.strip_edges().to_lower()
	var ranked: Array[Dictionary] = []
	for record: Dictionary in search_index:
		var haystack := str(record.search)
		var score := 0
		if needle.is_empty(): score = 1
		elif str(record.title).to_lower().begins_with(needle): score = 100
		elif (" " + haystack).contains(" " + needle): score = 60
		elif haystack.contains(needle): score = 20
		if score > 0:
			var copy := record.duplicate(true); copy["score"] = score; ranked.append(copy)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score) if int(a.score) != int(b.score) else str(a.title) < str(b.title))
	if ranked.size() > limit: ranked.resize(limit)
	return ranked

func _add(entry: Dictionary) -> void:
	if not entry.has("id") or not entry.has("title"): return
	var id := str(entry.get("id", ""))
	entries[id] = entry.duplicate(true)
	var terms := [str(entry.title), str(entry.get("summary", "")), str(entry.get("tags", [])), str(entry.get("sections", {}))]
	search_index.append({"id":id, "title":str(entry.title), "kind":str(entry.kind), "search":" ".join(terms).to_lower()})

func _material_entry(definition: MaterialDefinition) -> Dictionary:
	var category: String = CATEGORY_NAMES[clampi(definition.category, 0, CATEGORY_NAMES.size() - 1)]
	var properties: Array[String] = ["Density: %.0f kg/m³" % definition.density_kg_m3, "Thermal conductivity: %d" % definition.thermal_conductivity, "Specific heat: %d" % definition.specific_heat_units]
	if definition.mobility > 0: properties.append("Mobility: %d/255" % definition.mobility)
	if definition.flammability > 0: properties.append("Flammability: %d/255" % definition.flammability)
	if definition.moisture_capacity > 0: properties.append("Moisture capacity: %d/255" % definition.moisture_capacity)
	if not definition.phase_family.is_empty(): properties.append("Phase family: %s" % definition.phase_family)
	var interactions: Array[String] = []
	if definition.pipe_compatible: interactions.append("Can occupy Pipes as finite physical mass.")
	if definition.boil_to != &"": interactions.append("Sufficient heat changes it to %s." % definition.boil_to)
	if definition.melt_to != &"": interactions.append("Sufficient heat changes it to %s." % definition.melt_to)
	if definition.condense_to != &"": interactions.append("Cooling can condense it to %s." % definition.condense_to)
	if definition.flammability > 0: interactions.append("Heat and oxidizer can drive combustion; moisture delays ignition.")
	if definition.key == &"raw_sand": interactions.append("May contain silica, iron-bearing, heavy-mineral, clay and trace Gold constituents; a specific hidden cell remains unknown without measurement.")
	return {"id":"material:%s" % definition.key, "kind":"Material", "title":definition.display_name, "summary":"%s matter governed by density, heat and local physical interactions." % category, "sections":{"CATEGORY":category, "PROPERTIES":"\n".join(properties), "INTERACTIONS":"\n".join(interactions)}, "tags":Array(definition.tags) + [str(definition.key), category.to_lower()], "related":_material_related(definition)}

func _material_related(definition: MaterialDefinition) -> Array[String]:
	var related: Array[String] = []
	if definition.key == &"raw_sand": related.append_array(["component:41", "component:43", "component:46", "concept:screening"])
	if definition.key == &"water": related.append_array(["component:10", "component:14", "component:43", "concept:wet_separation"])
	if definition.key == &"steam": related.append_array(["component:10", "component:27", "concept:pressure"])
	if definition.flammability > 0: related.append("concept:combustion")
	return related

func _component_entry(world: Variant, definition: Dictionary) -> Dictionary:
	var type_id := int(definition.type_id)
	var detail := ComponentPresentation.describe(type_id, definition)
	var physical: Dictionary = world.get_structure_physical_properties(type_id)
	var inputs := Array(detail.ports).filter(func(value: Variant) -> bool: return str(value).contains("in") or str(value) in ["power", "automation", "mechanical", "fluid"])
	var sections := {"WHAT IT DOES":detail.principle, "WHAT IT DOES NOT DO":detail.not_do, "IMPORTANT CONNECTIONS":"None" if detail.ports.is_empty() else ", ".join(detail.ports), "PHYSICAL PROPERTIES":"Aperture %d · conductivity %d · max temperature %d · magnetic strength %d" % [int(physical.get("aperture", 0)), int(physical.get("conductivity", 0)), int(physical.get("maximum_temperature", 0)), int(physical.get("magnetic_strength", 0))], "COMMON USES":_common_use(type_id)}
	return {"id":"component:%d" % type_id, "kind":"Component", "title":detail.name, "summary":detail.principle, "sections":sections, "tags":[detail.category, detail.motif, "directional" if detail.directional else "nondirectional"] + inputs, "related":detail.related}

func _common_use(type_id: int) -> String:
	if type_id == 41: return "Dry screening surfaces assembled with a separate Vibration Actuator."
	if type_id == 43: return "Open wet-separation channels with real Water flow."
	if type_id in [38, 39]: return "Editable walls and open vessels whose material changes heat transfer."
	if type_id in [40, 42, 44, 47]: return "Player-shaped combustion and high-temperature regions; no Furnace entity is detected."
	if type_id in [26, 27, 28, 29, 31]: return "Physical Steam-power trains and electrical distribution."
	return "Reusable physical construction and factory layouts."

func _blueprint_entry(blueprint: BlueprintDefinition) -> Dictionary:
	var components: Array[String] = []
	for entry: Dictionary in blueprint.entries:
		var type_id := int(entry.get("type_id", 0))
		var component_name := str(ComponentPresentation.describe(type_id).name) if str(entry.get("kind", "structure")) == "structure" else "Automation Component"
		components.append("%s at %s" % [component_name, str(entry.get("position", Vector2i.ZERO))])
	return {"id":"blueprint:%s" % blueprint.blueprint_id, "kind":"Example Blueprint", "title":blueprint.display_name, "summary":blueprint.description, "sections":{"PRINCIPLE":blueprint.description, "COMPONENTS":"\n".join(components), "IDENTITY":"Example only — the placed structure has no hidden machine identity."}, "tags":["example", "blueprint", blueprint.blueprint_id], "related":[]}

func _add_concepts() -> void:
	var concepts := {
		"screening":["Screening", "Aperture, grain size and actual vibration decide pass and retained flow.", ["component:41", "component:45", "material:raw_sand"]],
		"wet_separation":["Wet Separation", "Real Water flow and raised Riffles let dense grains settle while lighter tailings continue.", ["component:43", "material:water", "material:heavy_concentrate"]],
		"heat":["Heat", "Temperature changes through conduction, phase change, combustion and finite energy transfer.", ["component:38", "component:39", "component:44"]],
		"combustion":["Combustion", "Fuel temperature, moisture and local oxidizer control physical burning, Smoke, Charcoal and Ash.", ["material:wood", "material:charcoal", "component:47"]],
		"pressure":["Pressure", "Finite Pipe contents, pumps, flow resistance and outlets create pressure and backpressure; excess can cause local breaches.", ["component:10", "component:14", "component:15", "material:steam"]],
		"power":["Power", "Steam expands through a Turbine, drives Shafts and a Generator, then a Pole network distributes finite electricity.", ["component:27", "component:26", "component:28", "component:29"]],
		"automation":["Automation", "Sensors observe permitted physical state; logic produces deterministic signals; actuators change Components.", ["component:9", "component:30"]],
		"flow":["Material Flow", "Matter moves through ordinary gravity, surfaces, conveyors, fluids and pressure without hidden teleportation.", ["component:1", "component:3", "material:water"]],
		"gravity":["Gravity", "Unsupported granular matter and liquids move downward through open physical geometry.", ["component:3", "material:raw_sand", "material:water"]],
		"research":["Research", "Eligible physical products deposited in Research Banks fund general capabilities and Components.", ["component:8"]],
		"storage":["Physical Storage", "Bins and vessels contain ordinary world cells; no hidden inventory exists.", ["component:4", "component:38", "component:39"]],
		"underground":["Subsurface Logistics", "Paired endpoints carry finite packets through explicit depth channels with capacity and obstruction rules.", ["component:18", "component:19"]],
		"construction":["Construction", "Individual Components define geometry, fields and connections. Example Blueprints remain editable ordinary Components.", ["component:37", "blueprint:basic_screen"]],
		"magnetism":["Magnetism", "A powered field moves existing susceptible constituent mass; it neither creates Iron nor reveals hidden Gold.", ["component:46", "material:iron_concentrate"]],
	}
	for id: String in concepts:
		var data: Array = concepts[id]
		_add({"id":"concept:%s" % id, "kind":"Physics", "title":data[0], "summary":data[1], "sections":{"PRINCIPLE":data[1]}, "tags":[id, str(data[0]).to_lower()], "related":data[2]})
