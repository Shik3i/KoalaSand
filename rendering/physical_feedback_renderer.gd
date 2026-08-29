class_name PhysicalFeedbackRenderer
extends Node2D

const MAX_EFFECTS := 96
const LIFETIME := 0.42

var cell_pixel_size := 2.0
var reduced_motion := false
var effects: Array[Dictionary] = []
var last_update_ms := 0.0
var dropped_effects := 0

func emit(kind: StringName, cell: Vector2i, intensity := 1.0, actual := true) -> void:
	if not actual: return
	if effects.size() >= MAX_EFFECTS:
		dropped_effects += 1
		return
	effects.append({"kind":kind, "position":(Vector2(cell) + Vector2(0.5, 0.5)) * cell_pixel_size, "age":0.0, "intensity":clampf(intensity, 0.1, 2.0)})
	queue_redraw()

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	for effect in effects: effect.age = float(effect.age) + delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return float(effect.age) < LIFETIME)
	if not effects.is_empty(): queue_redraw()
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _draw() -> void:
	for effect: Dictionary in effects:
		var life := 1.0 - float(effect.age) / LIFETIME
		var intensity := float(effect.intensity)
		var position: Vector2 = effect.position
		var radius := (2.5 + (1.0 - life) * (3.0 if reduced_motion else 8.0)) * intensity
		var color := _color_for(str(effect.kind)); color.a *= life * (0.45 if reduced_motion else 0.8)
		var kind := str(effect.kind)
		draw_circle(position, radius, color, false, 1.5)
		if reduced_motion: continue
		var count := 7 if kind in ["dig", "cut", "tree", "remove"] else 4
		for particle in count:
			var seed_angle := float((roundi(position.x) * 17 + roundi(position.y) * 31 + particle * 53) % 360) * PI / 180.0
			var vector := Vector2.RIGHT.rotated(seed_angle + float(effect.age) * (1.2 if kind == "fire" else 0.25))
			var travel := radius * (0.45 + float(particle % 3) * 0.22)
			var particle_position := position + vector * travel
			if kind in ["steam", "fire", "water"]:
				particle_position.y -= (1.0 - life) * radius * (1.4 if kind != "water" else 0.35)
				draw_circle(particle_position, maxf(0.8, life * 2.2), color)
			else:
				draw_line(particle_position - vector * 2.0, particle_position + vector * 2.0, color, 1.4)

func _color_for(kind: String) -> Color:
	match kind:
		"dig": return Color("c9a46a")
		"cut", "tree": return Color("a77545")
		"fire", "ignite": return Color("ff7a32")
		"steam": return Color("d9eef3")
		"water": return Color("4ca7d8")
		"invalid": return Color("ff524c")
		"remove": return Color("e06456")
		_: return Color("6dd5b7")
