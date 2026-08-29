class_name CommandBatch
extends RefCounted

enum ValidationMode {
	ATOMIC = 0,
	BEST_EFFORT = 1,
}

const SCHEMA_VERSION := 1
const MAX_SERIALIZED_BYTES := 64 * 1024 * 1024
const MAX_COMMANDS := 100000

var batch_id: String
var actor_id: int
var sequence: int
var label: String
var validation_mode: int
var commands: Array[WorldCommand] = []


func _init(
		id: String = "",
		actor: int = 0,
		batch_sequence: int = 0,
		batch_label: String = "",
		mode: int = ValidationMode.ATOMIC,
		ordered_commands: Array[WorldCommand] = []
) -> void:
	batch_id = id
	actor_id = actor
	sequence = batch_sequence
	label = batch_label
	validation_mode = mode
	commands = ordered_commands.duplicate()


func add(command: WorldCommand) -> CommandBatch:
	if command != null:
		commands.append(command)
	return self


func to_dictionary() -> Dictionary:
	var serialized_commands: Array[Dictionary] = []
	for command in commands:
		serialized_commands.append(command.to_dictionary())
	return {
		"schema": SCHEMA_VERSION,
		"batch_id": batch_id,
		"actor_id": actor_id,
		"sequence": sequence,
		"label": label,
		"validation_mode": validation_mode,
		"commands": serialized_commands,
	}


func serialize() -> PackedByteArray:
	return var_to_bytes(to_dictionary())


func content_hash() -> String:
	return serialize().hex_encode().sha256_text()


static func deserialize(bytes: PackedByteArray) -> CommandBatch:
	if bytes.is_empty() or bytes.size() > MAX_SERIALIZED_BYTES:
		return null
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if int(data.get("schema", 0)) != SCHEMA_VERSION:
		return null
	var mode := int(data.get("validation_mode", -1))
	if mode < ValidationMode.ATOMIC or mode > ValidationMode.BEST_EFFORT:
		return null
	var source_commands := Array(data.get("commands", []))
	if source_commands.size() > MAX_COMMANDS:
		return null
	var decoded_commands: Array[WorldCommand] = []
	for command_value: Variant in source_commands:
		if not command_value is Dictionary:
			return null
		var command := WorldCommand.deserialize(var_to_bytes(command_value))
		if command == null:
			return null
		decoded_commands.append(command)
	return CommandBatch.new(
		str(data.get("batch_id", "")),
		int(data.get("actor_id", 0)),
		int(data.get("sequence", 0)),
		str(data.get("label", "")),
		mode,
		decoded_commands
	)


static func result(applied: int, rejected: int, reasons: PackedInt32Array = PackedInt32Array(), region: Rect2i = Rect2i()) -> Dictionary:
	return {
		"applied": applied,
		"rejected": rejected,
		"reason_codes": reasons,
		"affected_region": region,
		"validation_usec": 0,
		"application_usec": 0,
	}
