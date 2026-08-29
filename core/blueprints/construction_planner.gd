class_name ConstructionPlanner
extends RefCounted

enum RemovalPolicy {
	IMMEDIATE = 0,
	MUST_DRAIN = 1,
}


static func pipette(world: Variant, position: Vector2i) -> Dictionary:
	var type_id := int(world.get_structure(position))
	if type_id <= 0:
		return {}
	var result := {"type_id": type_id, "orientation": 0, "configuration": {}}
	if world.has_method("get_pipe_state"):
		var pipe_state: Dictionary = world.get_pipe_state(position)
		if not pipe_state.is_empty():
			result.orientation = int(pipe_state.get("orientation", 0))
			result.configuration = {
				"enabled": bool(pipe_state.get("enabled", true)),
				"valve_open": bool(pipe_state.get("valve_open", true)),
			}
	if world.has_method("get_machine_state_at"):
		var machine_state: Dictionary = world.get_machine_state_at(position)
		if not machine_state.is_empty():
			result.orientation = int(machine_state.get("orientation", 0))
			result.origin = Vector2i(machine_state.get("origin", position))
			result.configuration = Dictionary(machine_state.get("configuration", {})).duplicate(true)
	return result


static func fast_replace(actor_id: int, sequence: int, position: Vector2i, replacement: Dictionary) -> CommandBatch:
	var batch := CommandBatch.new("replace:%d" % sequence, actor_id, sequence, "Fast replace", CommandBatch.ValidationMode.ATOMIC)
	batch.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": position.x, "y": position.y}))
	batch.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {
		"type_id": int(replacement.get("type_id", 0)),
		"x": position.x,
		"y": position.y,
		"orientation": int(replacement.get("orientation", 0)),
		"configuration": Dictionary(replacement.get("configuration", {})).duplicate(true),
	}))
	return batch


static func plan_upgrade(actor_id: int, sequence: int, replacements: Array[Dictionary]) -> CommandBatch:
	var batch := CommandBatch.new("upgrade:%d" % sequence, actor_id, sequence, "Upgrade planner", CommandBatch.ValidationMode.ATOMIC)
	for replacement in replacements:
		var position := Vector2i(int(replacement.x), int(replacement.y))
		batch.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": position.x, "y": position.y}))
		batch.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {
			"type_id": int(replacement.type_id),
			"x": position.x,
			"y": position.y,
			"orientation": int(replacement.get("orientation", 0)),
			"configuration": Dictionary(replacement.get("configuration", {})).duplicate(true),
		}))
	return batch


static func plan_deconstruction(actor_id: int, sequence: int, cells: Array[Vector2i], policy: int = RemovalPolicy.IMMEDIATE) -> CommandBatch:
	var batch := CommandBatch.new("deconstruct:%d" % sequence, actor_id, sequence, "Deconstruction planner", CommandBatch.ValidationMode.BEST_EFFORT)
	for cell in cells:
		batch.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": cell.x, "y": cell.y, "removal_policy": policy}))
	return batch


static func plan_vegetation_clear(actor_id: int, sequence: int, area: Rect2i) -> CommandBatch:
	var batch := CommandBatch.new("vegetation:%d" % sequence, actor_id, sequence, "Vegetation clearing", CommandBatch.ValidationMode.BEST_EFFORT)
	batch.add(WorldCommand.new(WorldCommand.Type.CLEAR_VEGETATION_RECT, {
		"x": area.position.x,
		"y": area.position.y,
		"width": area.size.x,
		"height": area.size.y,
	}))
	return batch
