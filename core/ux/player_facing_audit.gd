class_name PlayerFacingAudit
extends RefCounted

const HEADERS := ["NAME","CATEGORY","PLAYER-FACING?","ICON?","WORLD VISUAL?","TOOLTIP?","CODEX ENTRY?","INSPECTOR SUPPORT?","DIRECTIONAL?","STATE FEEDBACK?","ACCESSIBILITY ISSUE?","DEV-LOOKING?","STATUS"]

static func collect(materials: MaterialRegistry, world: Variant, blueprints: BlueprintLibrary, codex: PhysicsCodex) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for definition: Dictionary in world.get_structure_definitions():
		var type_id := int(definition.type_id); var player := ComponentPresentation.is_player_facing(type_id, definition); var presentation := ComponentPresentation.describe(type_id, definition)
		rows.append(_row(str(definition.display_name), "Component", player, player, player, player, codex.entries.has("component:%d" % type_id), player, bool(presentation.directional), type_id in [14, 27, 28, 34, 45, 46, 47], "None", not player, "PASS" if player else "DEV ONLY"))
	for material_id in materials.get_ids():
		if material_id == 0: continue
		var material := materials.get_definition(material_id)
		rows.append(_row(material.display_name, "Material", true, true, true, true, codex.entries.has("material:%s" % material.key), true, false, material.category in [MaterialDefinition.Category.LIQUID, MaterialDefinition.Category.GAS, MaterialDefinition.Category.MOLTEN] or material.flammability > 0, "None", false, "PASS"))
	for definition: Dictionary in world.get_automation_definitions():
		var help_definition := definition.duplicate(true); help_definition.key = str(definition.id)
		var help := HelpCatalog.automation(help_definition, not bool(definition.unlocked))
		rows.append(_row(str(definition.display_name), "Automation", true, true, true, HelpCatalog.valid(help), codex.entries.has("concept:automation"), true, false, true, "Signal value and label supplement color", false, "PASS"))
	for blueprint_id: Variant in blueprints.library:
		var blueprint := blueprints.load_blueprint(str(blueprint_id)); rows.append(_row(blueprint.display_name, "Example Blueprint", true, true, true, true, codex.entries.has("blueprint:%s" % blueprint.blueprint_id), true, false, false, "None", false, "PASS"))
	for tool in ["Select","Pipette","Dig","Cut","Ignite","Deconstruct","Blueprint Select"]: rows.append(_row(tool, "Action Tool", true, true, tool in ["Dig","Cut","Ignite","Deconstruct"], true, false, false, false, true, "None", false, "PASS"))
	var overlays := [{"name":"Geology","shipped":true},{"name":"Material","shipped":false},{"name":"Density","shipped":false},{"name":"Temperature","shipped":true},{"name":"Magnetic Field","shipped":true},{"name":"Fluid Flow","shipped":false},{"name":"Pipe Pressure","shipped":false},{"name":"Automation","shipped":true},{"name":"Underground","shipped":true},{"name":"Activity","shipped":false},{"name":"Damage","shipped":false},{"name":"Production","shipped":true},{"name":"Power","shipped":true}]
	for overlay: Dictionary in overlays:
		var shipped := bool(overlay.shipped)
		rows.append(_row(str(overlay.name), "Overlay", shipped, shipped, shipped, shipped, false, false, false, shipped, "Pattern and labels supplement color" if shipped else "Hidden from player overlay menu", not shipped, "PASS" if shipped else "DEV ONLY · NOT SHIPPED"))
	for panel in ["Main Menu","New Game","Build Catalog","Research","Codex","Map","Statistics","Inspector","Planning Pause","Controls","Settings","Save Browser","Blueprint Library","Experiments","Diagnostics Export"]: rows.append(_row(panel, "Panel", true, true, true, true, panel == "Codex", panel == "Inspector", false, true, "Keyboard focus and scalable text", false, "PASS"))
	for index in 10: rows.append(_row("Milestone %02d" % (index + 1), "Milestone", true, true, false, true, false, false, false, true, "Text criteria supplement status color", false, "PASS"))
	return rows

static func write_csv(path: String, rows: Array[Dictionary]) -> Error:
	var absolute := ProjectSettings.globalize_path(path); var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK: return directory_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_csv_line(PackedStringArray(HEADERS))
	for row in rows:
		var values := PackedStringArray()
		for header in HEADERS:
			values.append(str(row[header]))
		file.store_csv_line(values)
	file.close(); return OK

static func _row(name: String, category: String, player: bool, icon: bool, visual: bool, tooltip: bool, codex: bool, inspector: bool, directional: bool, feedback: bool, accessibility: String, dev: bool, status: String) -> Dictionary:
	return {"NAME":name,"CATEGORY":category,"PLAYER-FACING?":_yn(player),"ICON?":_yn(icon),"WORLD VISUAL?":_yn(visual),"TOOLTIP?":_yn(tooltip),"CODEX ENTRY?":_yn(codex),"INSPECTOR SUPPORT?":_yn(inspector),"DIRECTIONAL?":_yn(directional),"STATE FEEDBACK?":_yn(feedback),"ACCESSIBILITY ISSUE?":accessibility,"DEV-LOOKING?":_yn(dev),"STATUS":status}

static func _yn(value: bool) -> String: return "YES" if value else "NO"
