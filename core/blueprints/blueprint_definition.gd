class_name BlueprintDefinition
extends RefCounted

enum BuildExecutionMode {
	IMMEDIATE = 0,
	GHOST = 1,
}

const SCHEMA_VERSION := 1
const MAX_SERIALIZED_BYTES := 64 * 1024 * 1024
const MAX_ENTRIES := 100000
const MAX_CONNECTIONS := 200000
const MAX_CHANNELS := 100000
const MAX_ID_LENGTH := 128
const MAX_TEXT_LENGTH := 1024

var blueprint_id: String
var display_name: String
var description: String
var execution_mode := BuildExecutionMode.IMMEDIATE
var entries: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var subsurface_channels: Array[Dictionary] = []


func _init(id: String = "", name: String = "", details: String = "") -> void:
	blueprint_id = id
	display_name = name
	description = details


func add_structure(relative_id: int, type_id: int, position: Vector2i, orientation: int = 0, configuration: Dictionary = {}) -> BlueprintDefinition:
	entries.append({
		"kind": "structure",
		"relative_id": relative_id,
		"type_id": type_id,
		"position": position,
		"orientation": orientation & 3,
		"configuration": configuration.duplicate(true),
	})
	return self

func add_automation_component(relative_id: int, type_id: int, position: Vector2i, configuration: Dictionary = {}) -> BlueprintDefinition:
	entries.append({
		"kind": "automation",
		"relative_id": relative_id,
		"type_id": type_id,
		"position": position,
		"orientation": int(configuration.get("orientation", 0)) & 3,
		"configuration": configuration.duplicate(true),
	})
	return self


func add_connection(source_id: int, source_port: int, target_id: int, target_port: int) -> BlueprintDefinition:
	connections.append({
		"source_id": source_id,
		"source_port": source_port,
		"target_id": target_id,
		"target_port": target_port,
	})
	return self


func add_subsurface_channel(relative_id: int, depth: int, entrance: Vector2i, exit: Vector2i) -> BlueprintDefinition:
	subsurface_channels.append({
		"relative_id": relative_id,
		"depth": depth,
		"entrance": entrance,
		"exit": exit,
	})
	return self


func transformed(quarter_turns: int = 0, flip_horizontal: bool = false, flip_vertical: bool = false) -> BlueprintDefinition:
	var copy := BlueprintDefinition.new(blueprint_id, display_name, description)
	copy.execution_mode = execution_mode
	for entry in entries:
		var transformed_entry := entry.duplicate(true)
		transformed_entry.position = _transform_point(Vector2i(entry.position), quarter_turns, flip_horizontal, flip_vertical)
		transformed_entry.orientation = _transform_orientation(int(entry.orientation), quarter_turns, flip_horizontal, flip_vertical)
		if str(entry.get("kind", "structure")) == "automation":
			var configuration := Dictionary(transformed_entry.get("configuration", {})).duplicate(true)
			configuration.orientation = transformed_entry.orientation
			if configuration.has("target_position"):
				configuration.target_position = _transform_point(Vector2i(configuration.target_position), quarter_turns, flip_horizontal, flip_vertical)
			transformed_entry.configuration = configuration
		copy.entries.append(transformed_entry)
	for connection in connections:
		copy.connections.append(connection.duplicate(true))
	for channel in subsurface_channels:
		var transformed_channel := channel.duplicate(true)
		transformed_channel.entrance = _transform_point(Vector2i(channel.entrance), quarter_turns, flip_horizontal, flip_vertical)
		transformed_channel.exit = _transform_point(Vector2i(channel.exit), quarter_turns, flip_horizontal, flip_vertical)
		copy.subsurface_channels.append(transformed_channel)
	return copy


func instantiate(origin: Vector2i, actor_id: int, sequence: int, label: String = "Blueprint") -> CommandBatch:
	var batch := CommandBatch.new("%s:%d" % [blueprint_id, sequence], actor_id, sequence, label, CommandBatch.ValidationMode.ATOMIC)
	var ordered_entries := entries.duplicate(true)
	ordered_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.relative_id) < int(b.relative_id))
	for entry in ordered_entries:
		var position: Vector2i = origin + Vector2i(entry.position)
		var configuration := Dictionary(entry.configuration).duplicate(true)
		if str(entry.get("kind", "structure")) == "automation":
			configuration.orientation = int(entry.orientation)
			if configuration.has("target_position"):
				configuration.target_position = origin + Vector2i(configuration.target_position)
		var payload := {
			"relative_id": int(entry.relative_id),
			"type_id": int(entry.type_id),
			"x": position.x,
			"y": position.y,
			"orientation": int(entry.orientation),
			"configuration": configuration,
		}
		batch.add(WorldCommand.new(WorldCommand.Type.CREATE_AUTOMATION_COMPONENT if str(entry.get("kind", "structure")) == "automation" else WorldCommand.Type.PLACE_STRUCTURE, payload))
	var ordered_channels := subsurface_channels.duplicate(true)
	ordered_channels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.relative_id) < int(b.relative_id))
	for channel in ordered_channels:
		var entrance: Vector2i = origin + Vector2i(channel.entrance)
		var exit: Vector2i = origin + Vector2i(channel.exit)
		batch.add(WorldCommand.new(WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL, {
			"relative_id": int(channel.relative_id),
			"depth": int(channel.depth),
			"x0": entrance.x,
			"y0": entrance.y,
			"x1": exit.x,
			"y1": exit.y,
		}))
	for connection in connections:
		batch.add(WorldCommand.new(WorldCommand.Type.CREATE_AUTOMATION_CONNECTION, connection.duplicate(true)))
	return batch


func to_dictionary() -> Dictionary:
	var ordered_entries := entries.duplicate(true)
	ordered_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.relative_id) < int(b.relative_id))
	var ordered_connections := connections.duplicate(true)
	ordered_connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.source_id) < int(b.source_id) or (int(a.source_id) == int(b.source_id) and int(a.target_id) < int(b.target_id))
	)
	var ordered_channels := subsurface_channels.duplicate(true)
	ordered_channels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.relative_id) < int(b.relative_id))
	return {
		"schema": SCHEMA_VERSION,
		"blueprint_id": blueprint_id,
		"display_name": display_name,
		"description": description,
		"execution_mode": execution_mode,
		"entries": ordered_entries,
		"connections": ordered_connections,
		"subsurface_channels": ordered_channels,
	}


func serialize() -> PackedByteArray:
	return var_to_bytes(to_dictionary())


func content_hash() -> String:
	return serialize().hex_encode().sha256_text()


func is_valid() -> bool:
	if blueprint_id.is_empty() or blueprint_id.length() > MAX_ID_LENGTH or display_name.length() > MAX_TEXT_LENGTH or description.length() > MAX_TEXT_LENGTH:
		return false
	if execution_mode < BuildExecutionMode.IMMEDIATE or execution_mode > BuildExecutionMode.GHOST:
		return false
	if entries.size() > MAX_ENTRIES or connections.size() > MAX_CONNECTIONS or subsurface_channels.size() > MAX_CHANNELS:
		return false
	var relative_ids: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("relative_id", null) is int or not entry.get("type_id", null) is int or not entry.get("position", null) is Vector2i or not entry.get("orientation", null) is int or not entry.get("configuration", null) is Dictionary:
			return false
		var relative_id := int(entry.relative_id)
		var kind := str(entry.get("kind", "structure"))
		if relative_id <= 0 or relative_ids.has(relative_id) or kind not in ["structure", "automation"]:
			return false
		if (kind == "structure" and (int(entry.type_id) < 1 or int(entry.type_id) > 47)) or (kind == "automation" and int(entry.type_id) < 1):
			return false
		relative_ids[relative_id] = true
	for channel in subsurface_channels:
		if not channel is Dictionary or not channel.get("relative_id", null) is int or not channel.get("depth", null) is int or not channel.get("entrance", null) is Vector2i or not channel.get("exit", null) is Vector2i:
			return false
		var relative_id := int(channel.relative_id)
		if relative_id <= 0 or relative_ids.has(relative_id) or int(channel.depth) < 1 or int(channel.depth) > 3:
			return false
		relative_ids[relative_id] = true
	for connection in connections:
		if not connection is Dictionary:
			return false
		for key in ["source_id", "source_port", "target_id", "target_port"]:
			if not connection.get(key, null) is int:
				return false
		if not relative_ids.has(int(connection.source_id)) or not relative_ids.has(int(connection.target_id)) or int(connection.source_port) < 0 or int(connection.target_port) < 0:
			return false
	return true


static func deserialize(bytes: PackedByteArray) -> BlueprintDefinition:
	if bytes.is_empty() or bytes.size() > MAX_SERIALIZED_BYTES:
		return null
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if int(data.get("schema", 0)) != SCHEMA_VERSION:
		return null
	var blueprint := BlueprintDefinition.new(str(data.get("blueprint_id", "")), str(data.get("display_name", "")), str(data.get("description", "")))
	blueprint.execution_mode = int(data.get("execution_mode", BuildExecutionMode.IMMEDIATE))
	if not data.get("entries", null) is Array or not data.get("connections", null) is Array or not data.get("subsurface_channels", null) is Array:
		return null
	for entry: Variant in Array(data.entries):
		if not entry is Dictionary:
			return null
		blueprint.entries.append(Dictionary(entry).duplicate(true))
	for connection: Variant in Array(data.connections):
		if not connection is Dictionary:
			return null
		blueprint.connections.append(Dictionary(connection).duplicate(true))
	for channel: Variant in Array(data.subsurface_channels):
		if not channel is Dictionary:
			return null
		blueprint.subsurface_channels.append(Dictionary(channel).duplicate(true))
	return blueprint if blueprint.is_valid() else null


static func _transform_point(point: Vector2i, quarter_turns: int, flip_horizontal: bool, flip_vertical: bool) -> Vector2i:
	var result := point
	if flip_horizontal:
		result.x = -result.x
	if flip_vertical:
		result.y = -result.y
	for _turn in posmod(quarter_turns, 4):
		result = Vector2i(-result.y, result.x)
	return result


static func _transform_orientation(orientation: int, quarter_turns: int, flip_horizontal: bool, flip_vertical: bool) -> int:
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var direction: Vector2i = directions[orientation & 3]
	direction = _transform_point(direction, quarter_turns, flip_horizontal, flip_vertical)
	if direction == Vector2i.DOWN:
		return 1
	if direction == Vector2i.LEFT:
		return 2
	if direction == Vector2i.UP:
		return 3
	return 0
