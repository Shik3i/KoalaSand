class_name ComponentPresentation
extends RefCounted

const DEV_TYPES := {5: true, 6: true, 7: true, 17: true, 35: true, 36: true}
const DIRECTIONAL_TYPES := {1: true, 2: true, 3: true, 9: true, 12: true, 13: true, 14: true, 15: true, 18: true, 19: true, 20: true, 21: true, 22: true, 23: true, 24: true, 25: true, 27: true, 30: true, 45: true, 46: true, 47: true}

const DETAILS := {
	1: {"motif":"chevrons", "principle":"Carries physical material left across its exposed surface.", "not_do":"Does not teleport, sort or create material.", "ports":["material in", "material out"], "related":["component:3", "concept:flow"]},
	2: {"motif":"chevrons", "principle":"Carries physical material right across its exposed surface.", "not_do":"Does not teleport, sort or create material.", "ports":["material in", "material out"], "related":["component:3", "concept:flow"]},
	3: {"motif":"taper", "principle":"Guides falling physical matter toward a narrow outlet.", "not_do":"Does not store or transform contents.", "ports":["material in", "material out"], "related":["component:1", "concept:gravity"]},
	4: {"motif":"open_vessel", "principle":"Contains ordinary world material behind solid walls.", "not_do":"Has no hidden inventory.", "ports":["open top"], "related":["concept:storage", "material:raw_sand"]},
	8: {"motif":"bank", "principle":"Accepts eligible physical outputs as Research reserves.", "not_do":"Does not reveal hidden geology.", "ports":["material input"], "related":["concept:research"]},
	9: {"motif":"gate", "principle":"Opens or blocks an ordinary material path from an Automation signal.", "not_do":"Does not route material internally.", "ports":["material path", "automation"], "related":["concept:automation", "component:1"]},
	10: {"motif":"pipe", "principle":"Contains finite fluid or gas mass and transmits pressure locally.", "not_do":"Does not create Water or Steam.", "ports":["fluid"], "related":["component:14", "concept:pressure"]},
	11: {"motif":"junction", "principle":"Joins connected Pipe segments into a physical flow path.", "not_do":"Does not increase pressure.", "ports":["fluid"], "related":["component:10", "component:14"]},
	12: {"motif":"intake", "principle":"Transfers nearby physical world fluid into a connected Pipe.", "not_do":"Does not duplicate fluid.", "ports":["world fluid in", "pipe out"], "related":["component:10", "material:water"]},
	13: {"motif":"outlet", "principle":"Releases contained Pipe fluid into the physical world.", "not_do":"Does not destroy excess pressure.", "ports":["pipe in", "world fluid out"], "related":["component:10", "material:water"]},
	14: {"motif":"impeller", "principle":"Adds finite pressure head to connected Pipe contents while operating.", "not_do":"Does not pull through closed Valves or blocked outputs.", "ports":["fluid in", "fluid out", "automation", "power"], "related":["component:10", "component:15", "concept:pressure"]},
	15: {"motif":"valve", "principle":"Restricts or permits physical Pipe flow.", "not_do":"Does not change the contained material.", "ports":["fluid in", "fluid out", "automation"], "related":["component:10", "component:14"]},
	16: {"motif":"heavy_wall", "principle":"Forms a durable boundary for ordinary world liquids.", "not_do":"Has no hidden Reservoir inventory.", "ports":[], "related":["material:water", "concept:storage"]},
	18: {"motif":"down_arrow", "principle":"Begins a depth-I physical subsurface route.", "not_do":"Does not bypass endpoint capacity.", "ports":["surface in", "subsurface out"], "related":["component:19", "concept:underground"]},
	19: {"motif":"up_arrow", "principle":"Ends a depth-I physical subsurface route.", "not_do":"Does not create transported material.", "ports":["subsurface in", "surface out"], "related":["component:18", "concept:underground"]},
	20: {"motif":"down_arrow_double", "principle":"Begins a depth-II physical subsurface route.", "not_do":"Does not bypass endpoint capacity.", "ports":["surface in", "subsurface out"], "related":["component:21", "concept:underground"]},
	21: {"motif":"up_arrow_double", "principle":"Ends a depth-II physical subsurface route.", "not_do":"Does not create transported material.", "ports":["subsurface in", "surface out"], "related":["component:20", "concept:underground"]},
	22: {"motif":"down_arrow_triple", "principle":"Begins a depth-III physical subsurface route.", "not_do":"Does not bypass endpoint capacity.", "ports":["surface in", "subsurface out"], "related":["component:23", "concept:underground"]},
	23: {"motif":"up_arrow_triple", "principle":"Ends a depth-III physical subsurface route.", "not_do":"Does not create transported material.", "ports":["subsurface in", "surface out"], "related":["component:22", "concept:underground"]},
	24: {"motif":"thermal_gate", "principle":"Opens or closes local conductive heat transfer.", "not_do":"Does not generate heat.", "ports":["thermal in", "thermal out", "automation"], "related":["component:25", "concept:heat"]},
	25: {"motif":"counterflow", "principle":"Transfers heat between adjacent physical regions through conductive contact.", "not_do":"Does not mix or transmute their contents.", "ports":["thermal side A", "thermal side B"], "related":["component:24", "concept:heat"]},
	26: {"motif":"shaft", "principle":"Transmits finite rotational energy and load through connected shaft cells.", "not_do":"Does not generate rotation.", "ports":["mechanical"], "related":["component:27", "component:28"]},
	27: {"motif":"turbine", "principle":"Expands physical Steam from inlet to exhaust to drive a Shaft.", "not_do":"Does not consume a hidden fuel or Steam inventory.", "ports":["steam inlet", "steam exhaust", "mechanical shaft"], "related":["material:steam", "component:26", "component:28"]},
	28: {"motif":"generator", "principle":"Loads a rotating Shaft and supplies an electrical network.", "not_do":"Does not create energy without mechanical input.", "ports":["mechanical shaft", "power"], "related":["component:26", "component:29"]},
	29: {"motif":"pole", "principle":"Connects nearby electrical producers, storage and consumers.", "not_do":"Does not produce or store energy.", "ports":["power"], "related":["component:28", "component:31"]},
	30: {"motif":"switch", "principle":"Connects or separates an electrical network under player or Automation control.", "not_do":"Does not consume or produce energy.", "ports":["power side A", "power side B", "automation"], "related":["component:29", "concept:power"]},
	31: {"motif":"battery", "principle":"Stores finite electrical energy with deterministic losses.", "not_do":"Does not generate energy.", "ports":["power"], "related":["component:29", "concept:power"]},
	33: {"motif":"flywheel", "principle":"Stores finite rotational energy and smooths Shaft load.", "not_do":"Does not generate rotation.", "ports":["mechanical shaft"], "related":["component:26", "concept:power"]},
	34: {"motif":"heater", "principle":"Converts delivered electrical energy into local physical heat.", "not_do":"Does not perform recipes or target products.", "ports":["power", "thermal field"], "related":["component:29", "concept:heat"]},
	37: {"motif":"stone_blocks", "principle":"Provides ordinary solid structural geometry.", "not_do":"Does not insulate or process by identity.", "ports":[], "related":["concept:construction"]},
	38: {"motif":"riveted_plate", "principle":"Provides conductive metal geometry for walls and vessels.", "not_do":"Has no hidden vessel inventory.", "ports":[], "related":["material:iron", "concept:heat"]},
	39: {"motif":"ceramic_tiles", "principle":"Provides lower-conductivity ceramic geometry for walls and vessels.", "not_do":"Has no hidden vessel inventory.", "ports":[], "related":["component:38", "concept:heat"]},
	40: {"motif":"furnace_brick", "principle":"Survives high temperature and shapes a physical heated region.", "not_do":"Is not a Furnace machine and performs no recipe.", "ports":[], "related":["component:42", "component:47", "concept:combustion"]},
	41: {"motif":"perforated_grid", "principle":"Allows sufficiently fine physical material to pass through its aperture.", "not_do":"Does not convert Raw Sand into Fine Sand.", "ports":["retained side", "pass side", "vibration field"], "related":["component:45", "concept:screening", "material:raw_sand"]},
	42: {"motif":"slotted_grate", "principle":"Supports coarse solids while allowing smaller matter and gases through.", "not_do":"Does not burn fuel or create heat.", "ports":["supported side", "pass side"], "related":["component:40", "concept:combustion"]},
	43: {"motif":"raised_ribs", "principle":"Retards dense grains within real flowing Water so a heavy fraction can settle.", "not_do":"Does not convert material or work without Water flow.", "ports":["water/material flow", "capture surface"], "related":["material:water", "concept:wet_separation"]},
	44: {"motif":"insulation_hatch", "principle":"Reduces conductive heat loss through its occupied geometry.", "not_do":"Does not generate heat.", "ports":[], "related":["component:40", "concept:heat"]},
	45: {"motif":"oscillator", "principle":"Applies a local vibration field to connected processing Components while enabled.", "not_do":"Does not screen material by itself.", "ports":["vibration field", "automation", "power"], "related":["component:41", "concept:screening"]},
	46: {"motif":"coil", "principle":"Applies a local magnetic field that moves existing susceptible constituent mass.", "not_do":"Does not create Iron or identify hidden Gold.", "ports":["magnetic field", "automation", "power"], "related":["concept:magnetism", "material:iron_concentrate"]},
	47: {"motif":"fan", "principle":"Pushes local atmosphere and oxidizer through open physical geometry.", "not_do":"Does not create oxygen or heat.", "ports":["atmosphere in", "atmosphere out", "automation", "power"], "related":["concept:combustion", "component:40"]},
}

static func is_player_facing(type_id: int, definition: Dictionary = {}) -> bool:
	return not DEV_TYPES.has(type_id) and str(definition.get("category", "")).to_lower() not in ["dev fixture", "test"]

static func describe(type_id: int, definition: Dictionary = {}) -> Dictionary:
	var detail: Dictionary = Dictionary(DETAILS.get(type_id, {})).duplicate(true)
	detail["type_id"] = type_id
	detail["name"] = str(definition.get("display_name", definition.get("name", "Component %d" % type_id)))
	detail["category"] = str(definition.get("category", "Component"))
	detail["directional"] = DIRECTIONAL_TYPES.has(type_id)
	detail["motif"] = str(detail.get("motif", "distinct_geometry"))
	detail["principle"] = str(detail.get("principle", "Acts on the ordinary physical world through its geometry and connected systems."))
	detail["not_do"] = str(detail.get("not_do", "Does not create matter or energy."))
	detail["ports"] = Array(detail.get("ports", []))
	detail["related"] = Array(detail.get("related", []))
	return detail

static func orientation_vector(orientation: int) -> Vector2i:
	return [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][posmod(orientation, 4)]
