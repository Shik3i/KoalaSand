class_name PhysicalInspector
extends RefCounted

const AMBIENT_Q4 := 1173

static func inspect(world: Variant, materials: MaterialRegistry, cell: Vector2i, character_limited := false, owner_id := 1) -> Dictionary:
	if character_limited and world.has_method("is_cell_live_visible") and not world.is_cell_live_visible(owner_id, cell):
		return {"title":"UNKNOWN AREA", "summary":["No live observation available."], "advanced":[], "causes":["Move within line of sight to inspect local physical state."], "codex_id":""}
	var type_id := int(world.get_structure(cell))
	if type_id > 0:
		return _inspect_structure(world, materials, cell, type_id)
	return _inspect_material(world, materials, cell, character_limited)

static func _inspect_material(world: Variant, materials: MaterialRegistry, cell: Vector2i, character_limited: bool) -> Dictionary:
	var material_id := int(world.get_cell(cell))
	var definition := materials.get_definition(material_id)
	if definition == null or material_id == 0:
		return {"title":"EMPTY SPACE", "summary":["No material at this location."], "advanced":[], "causes":[], "codex_id":"concept:flow"}
	var amount := int(world.get_material_amount(cell)) if world.has_method("get_material_amount") else 255
	var temperature := int(world.get_temperature(cell))
	var summary: Array[String] = ["Amount  %d / 255" % amount, "Temperature  %.1f °C" % _celsius(temperature), "State  %s" % _material_state(definition, temperature)]
	var organic: Dictionary = world.get_organic_state(cell) if world.has_method("get_organic_state") else {}
	if not organic.is_empty() and int(organic.get("material_id", 0)) == material_id:
		summary.append("Moisture  %d / 255" % int(organic.get("moisture", 0)))
		summary.append("Local oxidizer  %d / 255" % int(organic.get("oxidizer", 0)))
	var causes: Array[String] = []
	if definition.flammability > 0:
		if int(organic.get("moisture", 0)) > 128: causes.append("FUEL WET")
		if int(organic.get("oxidizer", 255)) < 48: causes.append("OXYGEN STARVED")
		if temperature < definition.ignition_temperature: causes.append("BELOW IGNITION TEMPERATURE")
	var advanced: Array[String] = ["Thermal conductivity  %d" % definition.thermal_conductivity, "Specific heat  %d" % definition.specific_heat_units]
	if not character_limited:
		advanced.append("Provenance  %d · signature %d" % [int(world.get_provenance(cell)), int(world.get_mineral_signature(cell))])
	return {"title":definition.display_name, "summary":summary, "advanced":advanced, "causes":causes, "codex_id":"material:%s" % definition.key}

static func _inspect_structure(world: Variant, materials: MaterialRegistry, cell: Vector2i, type_id: int) -> Dictionary:
	var definition := _structure_definition(world, type_id)
	var presentation := ComponentPresentation.describe(type_id, definition)
	var summary: Array[String] = []
	var advanced: Array[String] = []
	var causes: Array[String] = []
	match type_id:
		41, 45:
			var physical: Dictionary = world.get_physical_processing_statistics()
			var vibration := int(physical.get("vibration_cells", physical.get("active_screens", 0)))
			summary.append("Aperture  %d" % int(world.get_structure_physical_properties(41).get("aperture", 0)))
			summary.append("Vibration  %s" % ("ACTIVE" if vibration > 0 else "NONE"))
			summary.append("Pass / retained  %d / %d" % [int(physical.get("screen_passes", 0)), int(physical.get("screen_retained", physical.get("screen_grains", 0)))])
			if vibration <= 0: causes.append("NO VIBRATION")
			if int(physical.get("screen_grains", 0)) > 0 and int(physical.get("screen_passes", 0)) == 0: causes.append("MATERIAL TOO COARSE OR OUTPUT BLOCKED")
		43:
			var wet: Dictionary = world.get_wet_processing_statistics()
			summary.append("Water flow  %d" % int(wet.get("water_throughput", wet.get("water_moved", 0))))
			summary.append("Material throughput  %d" % int(wet.get("grains_moved", 0)))
			summary.append("Heavy capture / tailings  %d / %d" % [int(wet.get("heavy_captured", 0)), int(wet.get("light_output", 0))])
			if int(wet.get("water_throughput", wet.get("water_moved", 0))) <= 0: causes.append("INSUFFICIENT WATER FLOW")
			if int(wet.get("grains_moved", 0)) > 0 and int(wet.get("heavy_captured", 0)) == 0: causes.append("NO DENSE FRACTION CAPTURED")
		38, 39:
			var vessel := _measure_open_vessel(world, cell, type_id)
			summary.append("Contained Water estimate  %d" % int(vessel.water_mass))
			summary.append("Average Water temperature  %.1f °C" % _celsius(int(vessel.average_temperature)))
			summary.append("Wall  %s · conductivity %d" % [presentation.name, int(world.get_structure_physical_properties(type_id).get("conductivity", 0))])
			summary.append("Steam generation  %d" % int(world.get_gas_statistics().get("steam_generated", 0)))
			if int(vessel.water_mass) > 0 and int(vessel.average_temperature) < 1492: causes.append("WATER BELOW BOILING TEMPERATURE")
		40, 42, 44, 47:
			var local := _measure_region(world, cell, 4)
			summary.append("Local temperature  %.1f °C" % _celsius(int(local.average_temperature)))
			summary.append("Oxidizer  %d / 255" % int(local.average_oxidizer))
			summary.append("Fuel cells  %d · burning %d" % [int(local.fuel_cells), int(local.burning_cells)])
			summary.append("Nearby insulation  %d" % int(local.insulation_cells))
			if int(local.fuel_cells) > 0 and int(local.average_oxidizer) < 48: causes.append("OXYGEN STARVED")
			if int(local.fuel_cells) > 0 and int(local.average_temperature) < 1892: causes.append("BELOW REACTION TEMPERATURE")
			if int(local.fuel_cells) > 0 and int(local.insulation_cells) == 0: causes.append("LOSING HEAT RAPIDLY")
		10, 11, 12, 13, 14, 15:
			var pipe: Dictionary = world.get_pipe_state(cell)
			var fluid := materials.get_definition(int(pipe.get("fluid_type", 0)))
			summary.append("Contents  %s · %d / 65535" % [fluid.display_name if fluid != null else "Empty", int(pipe.get("mass", 0))])
			summary.append("Pressure  %d · flow %d" % [int(pipe.get("pressure", 0)), int(pipe.get("flow", 0))])
			summary.append("Temperature  %.1f °C · health %d" % [_celsius(int(pipe.get("temperature", AMBIENT_Q4))), int(pipe.get("health", 0))])
			if int(pipe.get("mass", 0)) > 0 and int(pipe.get("flow", 0)) == 0: causes.append("NO FLOW OR BACKPRESSURE")
			if int(pipe.get("pressure", 0)) > 48000: causes.append("HIGH PRESSURE")
		26, 27, 28, 29, 30, 31, 33, 34:
			var power: Dictionary = world.get_power_state_at(cell)
			summary.append("Shaft speed  %d mRPM" % int(power.get("speed_millirpm", 0)))
			summary.append("Generation / demand  %d / %d" % [int(power.get("electrical_output", 0)), int(power.get("requested_rate", 0))])
			summary.append("Power satisfaction  %d / 1000" % int(power.get("satisfaction", 0)))
			if int(power.get("requested_rate", 0)) > 0 and int(power.get("satisfaction", 0)) < 1000: causes.append("POWER DEFICIT")
			if type_id == 27 and int(power.get("speed_millirpm", 0)) == 0: causes.append("NO STEAM FLOW OR EXHAUST BACKPRESSURE")
		_:
			summary.append(str(presentation.principle))
	advanced.append("World cell  %s" % cell)
	advanced.append("Component type  %d" % type_id)
	advanced.append("Ports  %s" % ("none" if presentation.ports.is_empty() else ", ".join(presentation.ports)))
	return {"title":presentation.name, "summary":summary, "advanced":advanced, "causes":causes, "codex_id":"component:%d" % type_id}

static func _measure_open_vessel(world: Variant, cell: Vector2i, type_id: int) -> Dictionary:
	var water_mass := 0
	var temperature_total := 0
	var samples := 0
	for y in range(-5, 2):
		for x in range(-6, 7):
			var probe := cell + Vector2i(x, y)
			if int(world.get_cell(probe)) == 3:
				var mass := int(world.get_material_amount(probe)); water_mass += mass; temperature_total += int(world.get_temperature(probe)) * mass; samples += mass
	return {"water_mass":water_mass, "average_temperature":temperature_total / maxi(1, samples), "wall_type":type_id}

static func _measure_region(world: Variant, cell: Vector2i, radius: int) -> Dictionary:
	var temperature_total := 0; var oxidizer_total := 0; var samples := 0; var fuel_cells := 0; var burning_cells := 0; var insulation_cells := 0
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			var probe := Vector2i(x, y); var material_id := int(world.get_cell(probe)); temperature_total += int(world.get_temperature(probe)); oxidizer_total += int(world.get_oxidizer(probe)); samples += 1
			if material_id in [14, 21, 22, 23]: fuel_cells += 1
			var organic: Dictionary = world.get_organic_state(probe)
			if int(organic.get("reaction_state", 0)) > 0: burning_cells += 1
			if int(world.get_structure(probe)) == 44: insulation_cells += 1
	return {"average_temperature":temperature_total / maxi(1, samples), "average_oxidizer":oxidizer_total / maxi(1, samples), "fuel_cells":fuel_cells, "burning_cells":burning_cells, "insulation_cells":insulation_cells}

static func _structure_definition(world: Variant, type_id: int) -> Dictionary:
	for definition: Dictionary in world.get_structure_definitions():
		if int(definition.get("type_id", 0)) == type_id: return definition
	return {"type_id":type_id, "display_name":"Component %d" % type_id, "category":"Component"}

static func _material_state(definition: MaterialDefinition, temperature: int) -> String:
	if definition.flammability > 0 and temperature >= definition.ignition_temperature: return "heated / combustible"
	if not definition.phase_family.is_empty(): return "%s phase" % definition.phase_family
	return ["empty", "solid", "granular", "liquid", "gas", "molten"][clampi(definition.category, 0, 5)]

static func _celsius(q4: int) -> float:
	return float(q4) * 0.25 - 273.15
