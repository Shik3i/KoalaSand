class_name SimulationClock
extends RefCounted

const VALID_SPEEDS: Array[int] = [0, 1, 2, 4]
const EPSILON := 0.000000001

var ticks_per_second: int
var tick_interval_seconds: float
var speed_multiplier: int = 1
var tick_index: int = 0
var _accumulator_seconds: float = 0.0


func _init(target_ticks_per_second: int = 30) -> void:
	assert(target_ticks_per_second > 0)
	ticks_per_second = target_ticks_per_second
	tick_interval_seconds = 1.0 / float(ticks_per_second)


func set_speed(multiplier: int) -> Error:
	if multiplier not in VALID_SPEEDS:
		return ERR_INVALID_PARAMETER
	speed_multiplier = multiplier
	return OK


func set_paused(paused: bool) -> void:
	speed_multiplier = 0 if paused else 1


func advance(render_delta_seconds: float) -> int:
	if render_delta_seconds <= 0.0 or speed_multiplier == 0:
		return 0
	_accumulator_seconds += render_delta_seconds * float(speed_multiplier)
	var due_ticks := floori((_accumulator_seconds + EPSILON) / tick_interval_seconds)
	if due_ticks <= 0:
		return 0
	_accumulator_seconds -= float(due_ticks) * tick_interval_seconds
	if _accumulator_seconds < 0.0 and _accumulator_seconds > -EPSILON:
		_accumulator_seconds = 0.0
	tick_index += due_ticks
	return due_ticks


func reset() -> void:
	tick_index = 0
	_accumulator_seconds = 0.0
