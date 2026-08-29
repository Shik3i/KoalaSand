class_name MaterialRegistry
extends RefCounted

const EMPTY_ID := 0

var _by_id: Dictionary = {}
var _id_by_key: Dictionary = {}
var _category_by_id := PackedByteArray()


func load_directory(path: String = "res://data/materials") -> Error:
	clear()
	var files := DirAccess.get_files_at(path)
	files.sort()
	for file_name in files:
		var resource_name := file_name.trim_suffix(".remap") if file_name.ends_with(".tres.remap") else file_name
		if not resource_name.ends_with(".tres"):
			continue
		var definition := ResourceLoader.load(path.path_join(resource_name)) as MaterialDefinition
		if definition == null:
			clear()
			return ERR_FILE_CORRUPT
		var error := register(definition)
		if error != OK:
			clear()
			return error
	if not _by_id.has(EMPTY_ID):
		clear()
		return ERR_DOES_NOT_EXIST
	return OK


func register(definition: MaterialDefinition) -> Error:
	if definition == null or definition.stable_id < 0 or definition.key.is_empty():
		return ERR_INVALID_PARAMETER
	if _by_id.has(definition.stable_id) or _id_by_key.has(definition.key):
		return ERR_ALREADY_EXISTS
	_by_id[definition.stable_id] = definition
	_id_by_key[definition.key] = definition.stable_id
	if _category_by_id.size() <= definition.stable_id:
		_category_by_id.resize(definition.stable_id + 1)
	_category_by_id[definition.stable_id] = definition.category
	return OK


func get_definition(stable_id: int) -> MaterialDefinition:
	return _by_id.get(stable_id) as MaterialDefinition


func get_id(key: StringName) -> int:
	return _id_by_key.get(key, -1) as int


func is_valid_id(stable_id: int) -> bool:
	return _by_id.has(stable_id)


func get_category(stable_id: int) -> MaterialDefinition.Category:
	if stable_id < 0 or stable_id >= _category_by_id.size() or not _by_id.has(stable_id):
		return MaterialDefinition.Category.EMPTY
	return _category_by_id[stable_id] as MaterialDefinition.Category


func get_ids() -> Array[int]:
	var result: Array[int] = []
	for stable_id in _by_id.keys():
		result.append(stable_id as int)
	result.sort()
	return result


func size() -> int:
	return _by_id.size()


func clear() -> void:
	_by_id.clear()
	_id_by_key.clear()
	_category_by_id.clear()
