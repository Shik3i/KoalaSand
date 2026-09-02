class_name WorldCommandBus
extends RefCounted

enum Reason {
	NONE = 0,
	INVALID_COMMAND = 1,
	VALIDATION_FAILED = 2,
	APPLICATION_FAILED = 3,
	NOTHING_TO_DO = 4,
	UNSUPPORTED_ATOMIC_MIX = 5,
}

# The command and batch logs are a diagnostic tail used by the determinism tests, not a durable
# journal: nothing in a save file reads them. They used to grow without limit, so a minute of
# painting left tens of thousands of serialised commands in memory that no one would ever read.
# Keep the most recent window and let the rest go.
const LOG_CAPACITY := 4096
# Trimming copies the whole retained window, so trim in blocks rather than on every command
# once the window is full.
const LOG_TRIM_SLACK := 512

var _next_order := 1
var _log: Array[PackedByteArray] = []
var _batch_log: Array[PackedByteArray] = []
var last_result: Variant = null

func submit(world: Variant, command: WorldCommand) -> bool:
	if command == null:
		return false
	if command.canonical_order <= 0:
		command.canonical_order = _next_order
		_next_order += 1
	var applied := apply(world, command)
	if applied:
		_record_command(command)
	return applied

func apply(world: Variant, command: WorldCommand) -> bool:
	if world == null or command == null or not _payload_valid(command):
		last_result = {"error": "INVALID_PAYLOAD"}
		return false
	var p := command.payload
	last_result = null
	match command.type:
		WorldCommand.Type.CREATIVE_PAINT:
			last_result = world.set_cell(Vector2i(p.x, p.y), int(p.material_id))
			return last_result == OK
		WorldCommand.Type.CREATIVE_ERASE:
			last_result = world.set_cell(Vector2i(p.x, p.y), 0)
			return last_result == OK
		WorldCommand.Type.PAINT_STROKE:
			last_result = world.paint_stroke(Vector2i(p.x0, p.y0), Vector2i(p.x1, p.y1), int(p.radius), int(p.material_id))
			return int(last_result) >= 0
		WorldCommand.Type.HARVEST_STROKE:
			last_result = world.harvest_stroke(Vector2i(p.x0, p.y0), Vector2i(p.x1, p.y1), int(p.radius))
			return int(last_result) >= 0
		WorldCommand.Type.HARVEST:
			last_result = world.harvest_cell(Vector2i(p.x, p.y))
			return last_result == OK
		WorldCommand.Type.PLACE_STRUCTURE:
			last_result = world.place_structure(int(p.type_id), Vector2i(p.x, p.y), int(p.get("orientation", 0)))
			if int(last_result) <= 0:
				return false
			var structure_configuration := Dictionary(p.get("configuration", {}))
			if not structure_configuration.is_empty() and (int(p.type_id) >= 26 or int(p.type_id) in [6, 7, 14]):
				return world.configure_power_structure(Vector2i(p.x, p.y), structure_configuration)
			return true
		WorldCommand.Type.PLACE_CONVEYOR_LINE:
			last_result = world.place_conveyor_line(Vector2i(p.x0, p.y), Vector2i(p.x1, p.y), int(p.direction))
			return int(last_result) >= 0
		WorldCommand.Type.REMOVE_STRUCTURE:
			last_result = world.remove_structure_at(Vector2i(p.x, p.y))
			return int(last_result) > 0
		WorldCommand.Type.SET_MANUAL_SWITCH:
			last_result = world.set_manual_switch(int(p.component_id), bool(p.enabled))
			return bool(last_result)
		WorldCommand.Type.CREATE_AUTOMATION_COMPONENT:
			last_result = world.create_automation_component(int(p.type_id), Vector2i(p.x, p.y), Dictionary(p.get("configuration", {})))
			return int(last_result) > 0
		WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT:
			last_result = world.remove_automation_component(int(p.component_id))
			return bool(last_result)
		WorldCommand.Type.CREATE_AUTOMATION_CONNECTION:
			last_result = world.create_automation_connection(int(p.get("source_component", 0)), int(p.source_port), int(p.get("target_component", 0)), int(p.target_port))
			return int(last_result) > 0
		WorldCommand.Type.REMOVE_AUTOMATION_CONNECTION:
			last_result = world.remove_automation_connection(int(p.connection_id))
			return bool(last_result)
		WorldCommand.Type.CONFIGURE_AUTOMATION_COMPONENT:
			last_result = world.configure_automation_component(int(p.component_id), Dictionary(p.configuration))
			return bool(last_result)
		WorldCommand.Type.PLACE_PIPE_LINE:
			last_result = world.place_pipe_line(Vector2i(p.x0, p.y0), Vector2i(p.x1, p.y1))
			return int(last_result) >= 0
		WorldCommand.Type.SET_PIPE_DEVICE:
			last_result = world.set_pipe_valve_open(Vector2i(p.x, p.y), bool(p.enabled)) if bool(p.get("valve", false)) else world.set_pipe_device_enabled(Vector2i(p.x, p.y), bool(p.enabled))
			return bool(last_result)
		WorldCommand.Type.DAMAGE_PIPE:
			last_result = world.damage_pipe(Vector2i(p.x, p.y), int(p.damage), int(p.get("cause", 0)))
			return int(last_result) >= 0
		WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL:
			last_result = world.place_subsurface_channel(int(p.depth), Vector2i(p.x0, p.y0), Vector2i(p.x1, p.y1))
			return int(last_result) > 0
		WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL:
			last_result = world.remove_subsurface_channel(int(p.channel_id), int(p.get("removal_policy", 1)))
			return bool(last_result)
		WorldCommand.Type.SET_MATERIAL_STATE:
			last_result = world.set_material_state(Vector2i(p.x, p.y), int(p.material_id), int(p.get("amount", 255)), int(p.get("temperature", 1173)), int(p.get("provenance", 0)), int(p.get("mineral_signature", 0)))
			return int(last_result) == OK
		WorldCommand.Type.SET_PIPE_FLUID:
			last_result = world.set_pipe_fluid(Vector2i(p.x, p.y), int(p.fluid_type), int(p.mass), int(p.get("temperature", 1173)))
			return int(last_result) == OK
		WorldCommand.Type.SET_THERMAL_SWITCH:
			last_result = world.set_thermal_switch_open(Vector2i(p.x, p.y), bool(p.open))
			return bool(last_result)
		WorldCommand.Type.SET_POWER_SWITCH:
			last_result = world.set_power_switch_closed(Vector2i(p.x, p.y), bool(p.closed))
			return bool(last_result)
		WorldCommand.Type.SET_POWER_PRIORITY:
			last_result = world.set_power_consumer_priority(Vector2i(p.x, p.y), int(p.priority))
			return bool(last_result)
		WorldCommand.Type.CONFIGURE_POWER_PORT:
			last_result = world.configure_power_structure(Vector2i(p.x, p.y), Dictionary(p.configuration))
			return bool(last_result)
		WorldCommand.Type.CUT_ORGANIC:
			last_result = world.character_cut_cell(Vector2i(p.x, p.y))
			return bool(last_result.get("accepted", false))
		WorldCommand.Type.IGNITE:
			last_result = world.ignite_cell(Vector2i(p.x, p.y), int(p.get("energy", 24000000)))
			return bool(last_result.get("accepted", false))
		WorldCommand.Type.CLEAR_VEGETATION_RECT:
			last_result = world.clear_vegetation_rect(Rect2i(int(p.x), int(p.y), int(p.width), int(p.height)))
			return bool(last_result.get("accepted", false))
	return false


func submit_batch(world: Variant, batch: CommandBatch) -> Dictionary:
	if batch == null or batch.commands.is_empty():
		return CommandBatch.result(0, 1, PackedInt32Array([Reason.INVALID_COMMAND]))
	for command in batch.commands:
		if command == null:
			return CommandBatch.result(0, batch.commands.size(), PackedInt32Array([Reason.INVALID_COMMAND]))
		if command.canonical_order <= 0:
			command.canonical_order = _next_order
			_next_order += 1
		command.player_id = batch.actor_id
	var native_result := _try_native_structure_batch(world, batch)
	if not native_result.is_empty():
		if int(native_result.get("applied", 0)) > 0:
			_record_batch(batch)
			for command in batch.commands:
				_record_command(command)
		last_result = native_result
		return native_result
	var validation_started := Time.get_ticks_usec()
	if batch.validation_mode == CommandBatch.ValidationMode.ATOMIC:
		for command in batch.commands:
			if not _validate(world, command):
				var failed := CommandBatch.result(0, batch.commands.size(), PackedInt32Array([Reason.VALIDATION_FAILED]), _affected_region(batch))
				failed.validation_usec = Time.get_ticks_usec() - validation_started
				last_result = failed
				return failed
	var validation_usec := Time.get_ticks_usec() - validation_started
	var application_started := Time.get_ticks_usec()
	var applied := 0
	var rejected := 0
	var reasons := PackedInt32Array()
	var relative_ids: Dictionary = {}
	for command in batch.commands:
		_resolve_relative_ids(command, relative_ids)
		if apply(world, command):
			applied += 1
			if command.payload.has("relative_id") and command.type in [WorldCommand.Type.CREATE_AUTOMATION_COMPONENT, WorldCommand.Type.CREATE_AUTOMATION_CONNECTION, WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL]:
				relative_ids[int(command.payload.relative_id)] = int(last_result)
		else:
			rejected += 1
			reasons.append(Reason.APPLICATION_FAILED)
			if batch.validation_mode == CommandBatch.ValidationMode.ATOMIC:
				break
	var result := CommandBatch.result(applied, rejected, reasons, _affected_region(batch))
	result.validation_usec = validation_usec
	result.application_usec = Time.get_ticks_usec() - application_started
	result.relative_id_map = relative_ids
	if applied > 0:
		_record_batch(batch)
		for index in applied:
			_record_command(batch.commands[index])
	last_result = result
	return result


func _try_native_structure_batch(world: Variant, batch: CommandBatch) -> Dictionary:
	if not world.has_method("apply_structure_batch"):
		return {}
	var operations := PackedInt32Array()
	for command in batch.commands:
		if not _payload_valid(command):
			return {}
		if command.type == WorldCommand.Type.PLACE_STRUCTURE:
			if not Dictionary(command.payload.get("configuration", {})).is_empty():
				return {}
			operations.append_array(PackedInt32Array([1, int(command.payload.type_id), int(command.payload.x), int(command.payload.y), int(command.payload.get("orientation", 0))]))
		elif command.type == WorldCommand.Type.REMOVE_STRUCTURE:
			operations.append_array(PackedInt32Array([2, 0, int(command.payload.x), int(command.payload.y), 0]))
		else:
			return {}
	return world.apply_structure_batch(operations, batch.validation_mode)


func _validate(world: Variant, command: WorldCommand) -> bool:
	if world == null or command == null or not _payload_valid(command):
		return false
	var p := command.payload
	match command.type:
		WorldCommand.Type.PLACE_STRUCTURE:
			return world.can_place_structure(int(p.type_id), Vector2i(p.x, p.y), int(p.get("orientation", 0)))
		WorldCommand.Type.REMOVE_STRUCTURE:
			return int(world.get_structure(Vector2i(p.x, p.y))) > 0
		WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT:
			return not world.get_automation_component_state(int(p.component_id)).is_empty()
		WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL:
			return not world.has_method("can_place_subsurface_channel") or world.can_place_subsurface_channel(int(p.depth), Vector2i(p.x0, p.y0), Vector2i(p.x1, p.y1))
		WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL:
			var state: Dictionary = world.get_subsurface_channel_state(int(p.channel_id))
			return not state.is_empty() and int(state.get("occupied_packets", 0)) == 0
		WorldCommand.Type.CUT_ORGANIC, WorldCommand.Type.IGNITE:
			return int(world.get_cell(Vector2i(p.x, p.y))) in [14, 21, 22, 23, 25, 26, 27]
		WorldCommand.Type.CLEAR_VEGETATION_RECT:
			return int(p.get("width", 0)) > 0 and int(p.get("height", 0)) > 0
	return true


func _payload_valid(command: WorldCommand) -> bool:
	var payload := command.payload
	if not payload is Dictionary:
		return false
	var required: Array[String] = []
	match command.type:
		WorldCommand.Type.CREATIVE_PAINT:
			required = ["x", "y", "material_id"]
		WorldCommand.Type.PAINT_STROKE:
			required = ["x0", "y0", "x1", "y1", "radius", "material_id"]
		WorldCommand.Type.HARVEST_STROKE:
			required = ["x0", "y0", "x1", "y1", "radius"]
		WorldCommand.Type.CREATIVE_ERASE, WorldCommand.Type.HARVEST, WorldCommand.Type.REMOVE_STRUCTURE, WorldCommand.Type.CUT_ORGANIC, WorldCommand.Type.IGNITE:
			required = ["x", "y"]
		WorldCommand.Type.PLACE_STRUCTURE, WorldCommand.Type.CREATE_AUTOMATION_COMPONENT:
			required = ["type_id", "x", "y"]
		WorldCommand.Type.PLACE_CONVEYOR_LINE:
			required = ["x0", "x1", "y", "direction"]
		WorldCommand.Type.SET_MANUAL_SWITCH, WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, WorldCommand.Type.CONFIGURE_AUTOMATION_COMPONENT:
			required = ["component_id"]
		WorldCommand.Type.CREATE_AUTOMATION_CONNECTION:
			required = ["source_port", "target_port"]
		WorldCommand.Type.REMOVE_AUTOMATION_CONNECTION:
			required = ["connection_id"]
		WorldCommand.Type.PLACE_PIPE_LINE:
			required = ["x0", "y0", "x1", "y1"]
		WorldCommand.Type.SET_PIPE_DEVICE:
			required = ["x", "y"]
		WorldCommand.Type.DAMAGE_PIPE:
			required = ["x", "y", "damage"]
		WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL:
			required = ["depth", "x0", "y0", "x1", "y1"]
		WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL:
			required = ["channel_id"]
		WorldCommand.Type.SET_MATERIAL_STATE:
			required = ["x", "y", "material_id"]
		WorldCommand.Type.SET_PIPE_FLUID:
			required = ["x", "y", "fluid_type", "mass"]
		WorldCommand.Type.SET_THERMAL_SWITCH, WorldCommand.Type.SET_POWER_SWITCH, WorldCommand.Type.SET_POWER_PRIORITY, WorldCommand.Type.CONFIGURE_POWER_PORT:
			required = ["x", "y"]
		WorldCommand.Type.CLEAR_VEGETATION_RECT:
			required = ["x", "y", "width", "height"]
		_:
			return false
	for key in required:
		if not payload.has(key) or not payload[key] is int:
			return false
	if command.type == WorldCommand.Type.CREATE_AUTOMATION_CONNECTION:
		var source_valid := (payload.get("source_component", null) is int) or (payload.get("source_id", null) is int)
		var target_valid := (payload.get("target_component", null) is int) or (payload.get("target_id", null) is int)
		if not source_valid or not target_valid:
			return false
	var coordinate_keys := ["x", "y", "x0", "y0", "x1", "y1"]
	for key in coordinate_keys:
		if payload.has(key) and (not payload[key] is int or int(payload[key]) < -2147483648 or int(payload[key]) > 2147483647):
			return false
	if payload.has("configuration") and not payload.configuration is Dictionary:
		return false
	for key in ["enabled", "valve", "open", "closed"]:
		if payload.has(key) and not payload[key] is bool:
			return false
	if command.type == WorldCommand.Type.SET_MANUAL_SWITCH and not payload.get("enabled", null) is bool:
		return false
	if command.type == WorldCommand.Type.SET_PIPE_DEVICE and not payload.get("enabled", null) is bool:
		return false
	if command.type == WorldCommand.Type.SET_THERMAL_SWITCH and not payload.get("open", null) is bool:
		return false
	if command.type == WorldCommand.Type.SET_POWER_SWITCH and not payload.get("closed", null) is bool:
		return false
	if command.type in [WorldCommand.Type.CONFIGURE_AUTOMATION_COMPONENT, WorldCommand.Type.CONFIGURE_POWER_PORT] and not payload.get("configuration", null) is Dictionary:
		return false
	return true


func _resolve_relative_ids(command: WorldCommand, id_map: Dictionary) -> void:
	if command.type != WorldCommand.Type.CREATE_AUTOMATION_CONNECTION:
		return
	if command.payload.has("source_id"):
		command.payload.source_component = int(id_map.get(int(command.payload.source_id), 0))
	if command.payload.has("target_id"):
		command.payload.target_component = int(id_map.get(int(command.payload.target_id), 0))


func _record_command(command: WorldCommand) -> void:
	_log.append(command.serialize())
	if _log.size() > LOG_CAPACITY + LOG_TRIM_SLACK:
		_log = _log.slice(_log.size() - LOG_CAPACITY)


func _record_batch(batch: CommandBatch) -> void:
	_batch_log.append(batch.serialize())
	if _batch_log.size() > LOG_CAPACITY + LOG_TRIM_SLACK:
		_batch_log = _batch_log.slice(_batch_log.size() - LOG_CAPACITY)


func _affected_region(batch: CommandBatch) -> Rect2i:
	var has_position := false
	var minimum := Vector2i.ZERO
	var maximum := Vector2i.ZERO
	for command in batch.commands:
		var p := command.payload
		var points: Array[Vector2i] = []
		if p.has("x") and p.has("y") and p.x is int and p.y is int:
			points.append(Vector2i(p.x, p.y))
		if p.has("x0") and p.has("y0") and p.x0 is int and p.y0 is int:
			points.append(Vector2i(p.x0, p.y0))
		if p.has("x1") and p.has("y1") and p.x1 is int and p.y1 is int:
			points.append(Vector2i(p.x1, p.y1))
		for point in points:
			if not has_position:
				minimum = point
				maximum = point
				has_position = true
			else:
				minimum = Vector2i(mini(minimum.x, point.x), mini(minimum.y, point.y))
				maximum = Vector2i(maxi(maximum.x, point.x), maxi(maximum.y, point.y))
	if not has_position:
		return Rect2i()
	var width := int(maximum.x) - int(minimum.x) + 1
	var height := int(maximum.y) - int(minimum.y) + 1
	if width <= 0 or height <= 0 or width > 2147483647 or height > 2147483647:
		return Rect2i()
	return Rect2i(minimum, Vector2i(width, height))

func serialize_log() -> Array[PackedByteArray]:
	return _log.duplicate()


func serialize_batch_log() -> Array[PackedByteArray]:
	return _batch_log.duplicate()

func replay(world: Variant, serialized_commands: Array[PackedByteArray]) -> bool:
	var commands: Array[WorldCommand] = []
	for bytes in serialized_commands:
		var command := WorldCommand.deserialize(bytes)
		if command == null:
			return false
		commands.append(command)
	commands.sort_custom(func(a: WorldCommand, b: WorldCommand) -> bool:
		return a.canonical_tick < b.canonical_tick or (a.canonical_tick == b.canonical_tick and a.canonical_order < b.canonical_order)
	)
	for command in commands:
		if not apply(world, command):
			return false
	return true


func replay_batches(world: Variant, serialized_batches: Array[PackedByteArray]) -> bool:
	var batches: Array[CommandBatch] = []
	for bytes in serialized_batches:
		var batch := CommandBatch.deserialize(bytes)
		if batch == null:
			return false
		batches.append(batch)
	batches.sort_custom(func(a: CommandBatch, b: CommandBatch) -> bool:
		return a.sequence < b.sequence or (a.sequence == b.sequence and a.batch_id < b.batch_id)
	)
	for batch in batches:
		var result := submit_batch(world, batch)
		if int(result.get("rejected", 0)) > 0:
			return false
	return true
