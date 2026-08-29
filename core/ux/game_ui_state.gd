class_name GameUIState
extends RefCounted

signal state_changed

const SCHEMA_VERSION := 1

var modal_stack: Array[String] = []
var placement_active := false
var notification := ""
var notification_ticks := 0


func open_modal(id: String) -> void:
	modal_stack.erase(id)
	modal_stack.append(id)
	state_changed.emit()


func close_modal(id: String) -> void:
	if modal_stack.has(id):
		modal_stack.erase(id)
		state_changed.emit()


func top_modal() -> String:
	return modal_stack[-1] if not modal_stack.is_empty() else ""


func world_input_blocked() -> bool:
	return not modal_stack.is_empty()


func escape() -> String:
	if placement_active:
		placement_active = false
		state_changed.emit()
		return "CANCEL_PLACEMENT"
	if not modal_stack.is_empty():
		var closed: String = modal_stack.pop_back()
		state_changed.emit()
		return "CLOSE_%s" % closed.to_upper()
	return "OPEN_PAUSE"


func notify(message: String, ticks := 180) -> void:
	notification = message
	notification_ticks = maxi(1, ticks)
	state_changed.emit()


func tick() -> void:
	if notification_ticks <= 0:
		return
	notification_ticks -= 1
	if notification_ticks == 0:
		notification = ""
		state_changed.emit()


func serialize() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "modal_stack": modal_stack.duplicate(), "placement_active": placement_active}
