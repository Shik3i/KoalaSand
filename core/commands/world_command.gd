class_name WorldCommand
extends RefCounted

enum Type {
	CREATIVE_PAINT = 1,
	CREATIVE_ERASE = 2,
	HARVEST = 3,
	PLACE_STRUCTURE = 4,
	PLACE_CONVEYOR_LINE = 5,
	REMOVE_STRUCTURE = 6,
	SET_MANUAL_SWITCH = 7,
	CREATE_AUTOMATION_COMPONENT = 8,
	REMOVE_AUTOMATION_COMPONENT = 9,
	CREATE_AUTOMATION_CONNECTION = 10,
	REMOVE_AUTOMATION_CONNECTION = 11,
	CONFIGURE_AUTOMATION_COMPONENT = 12,
	PLACE_PIPE_LINE = 13,
	SET_PIPE_DEVICE = 14,
	DAMAGE_PIPE = 15,
	PLACE_SUBSURFACE_CHANNEL = 16,
	REMOVE_SUBSURFACE_CHANNEL = 17,
	SET_MATERIAL_STATE = 18,
	SET_PIPE_FLUID = 19,
	SET_THERMAL_SWITCH = 20,
	SET_POWER_SWITCH = 21,
	SET_POWER_PRIORITY = 22,
	CONFIGURE_POWER_PORT = 23,
	CUT_ORGANIC = 24,
	IGNITE = 25,
	CLEAR_VEGETATION_RECT = 26,
	# A brush stroke is one player gesture, not one command per cell it covers.
	PAINT_STROKE = 27,
	HARVEST_STROKE = 28,
}

var canonical_tick: int
var canonical_order: int
var player_id: int
var type: Type
var payload: Dictionary

func _init(command_type: Type = Type.CREATIVE_PAINT, command_payload: Dictionary = {}, tick: int = 0, order: int = 0, source_player: int = 0) -> void:
	type = command_type
	payload = command_payload.duplicate(true)
	canonical_tick = tick
	canonical_order = order
	player_id = source_player

func to_dictionary() -> Dictionary:
	return {
		"schema": 1,
		"tick": canonical_tick,
		"order": canonical_order,
		"player": player_id,
		"type": int(type),
		"payload": payload,
	}

func serialize() -> PackedByteArray:
	return var_to_bytes(to_dictionary())

static func deserialize(bytes: PackedByteArray) -> WorldCommand:
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if int(data.get("schema", 0)) != 1 or not data.get("payload", null) is Dictionary:
		return null
	var command_type := int(data.get("type", 0))
	if command_type < Type.CREATIVE_PAINT or command_type > Type.HARVEST_STROKE:
		return null
	return WorldCommand.new(command_type, Dictionary(data.payload), int(data.get("tick", 0)), int(data.get("order", 0)), int(data.get("player", 0)))
