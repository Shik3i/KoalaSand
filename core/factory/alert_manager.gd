class_name FactoryAlertManager
extends RefCounted

signal alert_emitted(alert: Dictionary)
signal focus_requested(world_cell: Vector2i)

enum Type {
	PIPE_RUPTURE,
	PIPE_OVERPRESSURE,
	BANK_REJECT,
	PIPE_OVERTEMPERATURE,
	POWER_BROWNOUT,
	GENERATOR_OVERLOAD,
	TURBINE_OVERSPEED,
	TURBINE_BACKPRESSURE,
}

const MAX_ALERTS := 32
const RATE_LIMIT_TICKS := 120

var alerts: Array[Dictionary] = []
var _last_counts: Dictionary = {}
var _last_emitted_tick: Dictionary = {}

func observe(world: Variant, visible_chunks: Rect2i) -> void:
	if world == null:
		return
	# get_tick(), not the full diagnostic assembly: this observes on a frame cadence, and
	# get_statistics() walks every resident chunk several times over to reach one integer.
	var tick := int(world.get_tick())
	var pipe: Dictionary = world.get_pipe_statistics()
	var bank: Dictionary = world.get_bank_statistics()
	var visible_issues := _scan_visible_pipe_issues(world, visible_chunks)
	var power: Dictionary = world.get_power_statistics() if world.has_method("get_power_statistics") else {}
	_observe_counter(Type.PIPE_RUPTURE, int(pipe.get("breached_segments", 0)), "PIPE RUPTURE · LOCAL LEAK", tick, Vector2i(visible_issues.rupture_position))
	_observe_counter(Type.PIPE_OVERPRESSURE, int(visible_issues.overpressure_count), "PIPE OVERPRESSURE", tick, Vector2i(visible_issues.overpressure_position))
	_observe_counter(Type.PIPE_OVERTEMPERATURE, int(visible_issues.overtemperature_count), "PIPE OVERTEMPERATURE", tick, Vector2i(visible_issues.overtemperature_position))
	_observe_counter(Type.BANK_REJECT, int(bank.get("rejected_total", 0)), "RESEARCH BANK REJECTED MATERIAL", tick, Vector2i.ZERO)
	_observe_counter(Type.POWER_BROWNOUT, int(power.get("brownout_networks", 0)), "POWER BROWNOUT · PRIORITY SHEDDING", tick, Vector2i.ZERO)
	_observe_counter(Type.GENERATOR_OVERLOAD, int(power.get("overloaded_generators", 0)), "GENERATOR OVERLOAD", tick, Vector2i.ZERO)
	_observe_counter(Type.TURBINE_OVERSPEED, int(power.get("overspeed_turbines", 0)), "TURBINE OVERSPEED", tick, Vector2i.ZERO)
	_observe_counter(Type.TURBINE_BACKPRESSURE, int(power.get("backpressure_turbines", 0)), "TURBINE BACKPRESSURE", tick, Vector2i.ZERO)

func focus(alert_index: int) -> void:
	if alert_index < 0 or alert_index >= alerts.size():
		return
	focus_requested.emit(Vector2i(alerts[alert_index].world_cell))

func clear() -> void:
	alerts.clear()
	_last_counts.clear()
	_last_emitted_tick.clear()

func _observe_counter(type: int, count: int, message: String, tick: int, world_cell: Vector2i) -> void:
	var previous := int(_last_counts.get(type, count))
	_last_counts[type] = count
	if count <= previous:
		return
	if tick - int(_last_emitted_tick.get(type, -RATE_LIMIT_TICKS)) < RATE_LIMIT_TICKS:
		return
	_last_emitted_tick[type] = tick
	var alert := {"type": type, "message": message, "world_cell": world_cell, "tick": tick, "count": count}
	alerts.push_front(alert)
	while alerts.size() > MAX_ALERTS:
		alerts.pop_back()
	alert_emitted.emit(alert)

func _scan_visible_pipe_issues(world: Variant, visible_chunks: Rect2i) -> Dictionary:
	var records: PackedInt32Array = world.get_visible_pipe_segments(visible_chunks)
	var rupture_position := Vector2i.ZERO
	var overpressure_position := Vector2i.ZERO
	var rupture_found := false
	var overpressure_count := 0
	var overtemperature_position := Vector2i.ZERO
	var overtemperature_count := 0
	for index in range(0, records.size(), 11):
		var cell := Vector2i(records[index], records[index + 1])
		var flags := int(records[index + 6])
		if not rupture_found and (flags & 0x04) != 0:
			rupture_position = cell
			rupture_found = true
		var total_pressure := clampi(int(records[index + 4]) * 48000 / 65535 + int(records[index + 9]), 0, 65535)
		if total_pressure > 60000:
			if overpressure_count == 0:
				overpressure_position = cell
			overpressure_count += 1
		if int(records[index + 10]) > 5893:
			if overtemperature_count == 0:
				overtemperature_position = cell
			overtemperature_count += 1
	return {
		"rupture_position": rupture_position,
		"overpressure_position": overpressure_position,
		"overpressure_count": overpressure_count,
		"overtemperature_position": overtemperature_position,
		"overtemperature_count": overtemperature_count,
	}
