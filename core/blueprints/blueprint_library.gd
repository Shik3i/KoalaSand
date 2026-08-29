class_name BlueprintLibrary
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_CLIPBOARD_CAPACITY := 16
const MAX_STATE_BYTES := 128 * 1024 * 1024
const MAX_LIBRARY_ENTRIES := 10000

var clipboard_capacity: int
var clipboard_history: Array[PackedByteArray] = []
var library: Dictionary = {}


func _init(capacity: int = DEFAULT_CLIPBOARD_CAPACITY) -> void:
	clipboard_capacity = clampi(capacity, 10, 20)


func copy_to_clipboard(blueprint: BlueprintDefinition) -> void:
	if blueprint == null:
		return
	var bytes := blueprint.serialize()
	if not clipboard_history.is_empty() and clipboard_history.back() == bytes:
		return
	clipboard_history.append(bytes)
	while clipboard_history.size() > clipboard_capacity:
		clipboard_history.pop_front()


func clipboard(index_from_latest: int = 0) -> BlueprintDefinition:
	var index := clipboard_history.size() - 1 - index_from_latest
	if index < 0 or index >= clipboard_history.size():
		return null
	return BlueprintDefinition.deserialize(clipboard_history[index])


func save(blueprint: BlueprintDefinition) -> bool:
	if blueprint == null or not blueprint.is_valid() or (not library.has(blueprint.blueprint_id) and library.size() >= MAX_LIBRARY_ENTRIES):
		return false
	library[blueprint.blueprint_id] = blueprint.serialize()
	return true


func load_blueprint(blueprint_id: String) -> BlueprintDefinition:
	if not library.has(blueprint_id):
		return null
	return BlueprintDefinition.deserialize(library[blueprint_id])


func serialize() -> PackedByteArray:
	var ids := library.keys()
	ids.sort()
	var ordered_library: Array[Dictionary] = []
	for id: Variant in ids:
		ordered_library.append({"id": str(id), "data": library[id]})
	return var_to_bytes({
		"schema": SCHEMA_VERSION,
		"clipboard_capacity": clipboard_capacity,
		"clipboard_history": clipboard_history,
		"library": ordered_library,
	})


func deserialize_state(bytes: PackedByteArray) -> bool:
	if bytes.is_empty() or bytes.size() > MAX_STATE_BYTES:
		return false
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary or int(value.get("schema", 0)) != SCHEMA_VERSION:
		return false
	clipboard_capacity = clampi(int(value.get("clipboard_capacity", DEFAULT_CLIPBOARD_CAPACITY)), 10, 20)
	clipboard_history.clear()
	if not value.get("clipboard_history", null) is Array or not value.get("library", null) is Array:
		return false
	for encoded: Variant in Array(value.clipboard_history):
		if not encoded is PackedByteArray or BlueprintDefinition.deserialize(encoded) == null:
			return false
		clipboard_history.append(encoded)
	library.clear()
	var source_library := Array(value.library)
	if source_library.size() > MAX_LIBRARY_ENTRIES:
		return false
	for entry: Variant in source_library:
		if not entry is Dictionary:
			return false
		var data: PackedByteArray = entry.get("data", PackedByteArray())
		if BlueprintDefinition.deserialize(data) == null:
			return false
		var decoded := BlueprintDefinition.deserialize(data)
		var id := str(entry.get("id", ""))
		if decoded == null or id != decoded.blueprint_id or library.has(id):
			return false
		library[id] = data
	return true
