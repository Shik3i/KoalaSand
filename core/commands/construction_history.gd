class_name ConstructionHistory
extends RefCounted

const DEFAULT_CAPACITY := 64

var capacity: int
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func _init(history_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, history_capacity)


func execute(world: Variant, bus: WorldCommandBus, forward: CommandBatch, inverse: CommandBatch) -> Dictionary:
	var result := bus.submit_batch(world, forward)
	if int(result.get("rejected", 0)) == 0 and int(result.get("applied", 0)) == forward.commands.size():
		record(forward, inverse)
	return result

func record(forward: CommandBatch, inverse: CommandBatch) -> void:
	if forward == null or inverse == null or forward.commands.is_empty() or inverse.commands.is_empty():
		return
	_undo.append({"forward": forward.serialize(), "inverse": inverse.serialize()})
	if _undo.size() > capacity:
		_undo.pop_front()
	_redo.clear()


func undo(world: Variant, bus: WorldCommandBus) -> Dictionary:
	if _undo.is_empty():
		return CommandBatch.result(0, 1, PackedInt32Array([WorldCommandBus.Reason.NOTHING_TO_DO]))
	var entry: Dictionary = _undo.pop_back()
	var inverse := CommandBatch.deserialize(entry.inverse)
	var result := bus.submit_batch(world, inverse)
	if int(result.get("rejected", 0)) == 0:
		_redo.append(entry)
	else:
		_undo.append(entry)
	return result


func redo(world: Variant, bus: WorldCommandBus) -> Dictionary:
	if _redo.is_empty():
		return CommandBatch.result(0, 1, PackedInt32Array([WorldCommandBus.Reason.NOTHING_TO_DO]))
	var entry: Dictionary = _redo.pop_back()
	var forward := CommandBatch.deserialize(entry.forward)
	var result := bus.submit_batch(world, forward)
	if int(result.get("rejected", 0)) == 0:
		_undo.append(entry)
	else:
		_redo.append(entry)
	return result


func clear() -> void:
	_undo.clear()
	_redo.clear()


func get_state() -> Dictionary:
	return {"capacity": capacity, "undo_count": _undo.size(), "redo_count": _redo.size()}
