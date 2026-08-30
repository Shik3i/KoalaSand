class_name UILayoutPolicy
extends RefCounted

const LAYER_HUD := 100
const LAYER_PANEL := 300
const LAYER_MODAL := 500
const LAYER_HIGHLIGHT := 900
const LAYER_TOOLTIP := 1000
const VIEWPORT_MARGIN := 12.0
const TOOLTIP_GAP := 12.0


static func catalog_columns(available_width: float, ui_scale: float) -> int:
	var minimum_card_width := 236.0 * clampf(ui_scale, 0.75, 2.0)
	return clampi(floori((available_width + 8.0) / (minimum_card_width + 8.0)), 2, 4)


static func overlap_area(a: Rect2, b: Rect2) -> float:
	var intersection := a.intersection(b)
	return intersection.size.x * intersection.size.y if intersection.has_area() else 0.0


static func inside_viewport(rect: Rect2, viewport_size: Vector2, margin := VIEWPORT_MARGIN) -> bool:
	return rect.position.x >= margin - 0.1 and rect.position.y >= margin - 0.1 \
		and rect.end.x <= viewport_size.x - margin + 0.1 and rect.end.y <= viewport_size.y - margin + 0.1


static func clamp_rect(rect: Rect2, viewport_size: Vector2, margin := VIEWPORT_MARGIN) -> Rect2:
	var maximum := Vector2(
		maxf(margin, viewport_size.x - rect.size.x - margin),
		maxf(margin, viewport_size.y - rect.size.y - margin)
	)
	return Rect2(Vector2(
		clampf(rect.position.x, margin, maximum.x),
		clampf(rect.position.y, margin, maximum.y)
	), rect.size)


static func tooltip_candidates(target: Rect2, tooltip_size: Vector2) -> Array[Rect2]:
	return [
		Rect2(Vector2(target.end.x + TOOLTIP_GAP, target.get_center().y - tooltip_size.y * 0.5), tooltip_size),
		Rect2(Vector2(target.position.x - tooltip_size.x - TOOLTIP_GAP, target.get_center().y - tooltip_size.y * 0.5), tooltip_size),
		Rect2(Vector2(target.get_center().x - tooltip_size.x * 0.5, target.end.y + TOOLTIP_GAP), tooltip_size),
		Rect2(Vector2(target.get_center().x - tooltip_size.x * 0.5, target.position.y - tooltip_size.y - TOOLTIP_GAP), tooltip_size),
	]


static func best_tooltip_rect(target: Rect2, tooltip_size: Vector2, viewport_size: Vector2, reserved_regions: Array[Rect2] = [], modal_regions: Array[Rect2] = []) -> Rect2:
	var best := Rect2(Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN), tooltip_size)
	var best_score := INF
	var exclusions: Array[Rect2] = [target]
	exclusions.append_array(reserved_regions)
	exclusions.append_array(modal_regions)
	for raw_candidate: Rect2 in tooltip_candidates(target, tooltip_size):
		var x_positions: Array[float] = [raw_candidate.position.x]
		var y_positions: Array[float] = [raw_candidate.position.y]
		for exclusion: Rect2 in exclusions:
			x_positions.append(exclusion.position.x - tooltip_size.x - TOOLTIP_GAP)
			x_positions.append(exclusion.end.x + TOOLTIP_GAP)
			y_positions.append(exclusion.position.y - tooltip_size.y - TOOLTIP_GAP)
			y_positions.append(exclusion.end.y + TOOLTIP_GAP)
		for candidate_x: float in x_positions:
			for candidate_y: float in y_positions:
				var candidate := clamp_rect(Rect2(Vector2(candidate_x, candidate_y), tooltip_size), viewport_size)
				var score := overlap_area(candidate, target) * 100000.0
				for region: Rect2 in reserved_regions:
					score += overlap_area(candidate, region) * 10000.0
				for region: Rect2 in modal_regions:
					score += overlap_area(candidate, region) * 1000.0
				score += raw_candidate.position.distance_squared_to(candidate.position)
				score += candidate.get_center().distance_squared_to(target.get_center()) * 0.0001
				if score < best_score:
					best_score = score
					best = candidate
	return best
