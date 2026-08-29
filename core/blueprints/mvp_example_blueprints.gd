class_name MvpExampleBlueprints
extends RefCounted


static func install(library: BlueprintLibrary) -> void:
	for blueprint in all():
		library.save(blueprint)


static func all() -> Array[BlueprintDefinition]:
	return [basic_screen(), basic_wet_sluice(), basic_charcoal_chamber(), basic_furnace(), basic_metal_vessel(), basic_steam_boiler()]


static func basic_screen() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_screen", "Basic Screen", "Editable Mesh surface driven by a separate Vibration Actuator.")
	blueprint.add_structure(1, 45, Vector2i.ZERO)
	for x in range(1, 6): blueprint.add_structure(10 + x, 41, Vector2i(x, 0))
	return blueprint


static func basic_wet_sluice() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_wet_sluice", "Basic Wet Sluice", "Open Structural Wall channel with Riffles; requires real Water flow.")
	for x in range(8):
		blueprint.add_structure(10 + x, 37, Vector2i(x, 2))
	for x in [2, 4, 6]: blueprint.add_structure(30 + x, 43, Vector2i(x, 1))
	blueprint.add_structure(50, 37, Vector2i(0, 1))
	return blueprint


static func basic_charcoal_chamber() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_charcoal_chamber", "Basic Charcoal Chamber", "Low-oxygen Refractory enclosure. The opening is deliberately editable.")
	for x in range(7): blueprint.add_structure(10 + x, 40, Vector2i(x, 4))
	for y in range(1, 4):
		blueprint.add_structure(30 + y, 40, Vector2i(0, y))
		blueprint.add_structure(40 + y, 40, Vector2i(6, y))
	for x in range(1, 6): blueprint.add_structure(50 + x, 40, Vector2i(x, 0))
	blueprint.add_structure(70, 42, Vector2i(3, 3))
	return blueprint


static func basic_furnace() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_furnace", "Basic Furnace", "Refractory geometry, Grate, Insulation and optional Blower; no recipe identity.")
	for x in range(8): blueprint.add_structure(10 + x, 40, Vector2i(x, 5))
	for y in range(1, 5):
		blueprint.add_structure(30 + y, 40, Vector2i(0, y))
		blueprint.add_structure(40 + y, 40, Vector2i(7, y))
	for x in range(1, 7): blueprint.add_structure(50 + x, 44, Vector2i(x, 0))
	for x in range(2, 6): blueprint.add_structure(70 + x, 42, Vector2i(x, 4))
	blueprint.add_structure(90, 47, Vector2i(-1, 3))
	return blueprint


static func basic_metal_vessel() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_metal_vessel", "Basic Metal Vessel", "Open Metal Plate vessel. Replace plates with Ceramic to change heat transfer.")
	for x in range(7): blueprint.add_structure(10 + x, 38, Vector2i(x, 4))
	for y in range(4):
		blueprint.add_structure(30 + y, 38, Vector2i(0, y))
		blueprint.add_structure(40 + y, 38, Vector2i(6, y))
	return blueprint


static func basic_steam_boiler() -> BlueprintDefinition:
	var blueprint := BlueprintDefinition.new("basic_steam_boiler", "Basic Steam Boiler", "Ceramic Water vessel with a physical Steam outlet; heat and pressure remain simulated.")
	for x in range(8): blueprint.add_structure(10 + x, 39, Vector2i(x, 5))
	for y in range(1, 5):
		blueprint.add_structure(30 + y, 39, Vector2i(0, y))
		blueprint.add_structure(40 + y, 39, Vector2i(7, y))
	for x in range(1, 6): blueprint.add_structure(50 + x, 39, Vector2i(x, 0))
	blueprint.add_structure(70, 44, Vector2i(3, 6))
	return blueprint
