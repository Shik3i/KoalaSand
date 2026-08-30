class_name UILayoutAudit
extends RefCounted

const TOLERANCE := 1.0


static func within(inner: Rect2, outer: Rect2, tolerance := TOLERANCE) -> bool:
	return inner.position.x >= outer.position.x - tolerance and inner.position.y >= outer.position.y - tolerance \
		and inner.end.x <= outer.end.x + tolerance and inner.end.y <= outer.end.y + tolerance


static func separated(a: Rect2, b: Rect2, tolerance := TOLERANCE) -> bool:
	return UILayoutPolicy.overlap_area(a.grow(-tolerance), b.grow(-tolerance)) <= 0.0


static func surface_overflow(surface: Control) -> Array[String]:
	var failures: Array[String] = []
	_collect_surface_overflow(surface, surface.get_global_rect(), failures)
	return failures


static func catalog_card_failures(rects: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var card: Rect2 = rects.card
	for key in ["icon", "name", "category"]:
		if not within(rects[key], card): failures.append("%s outside card" % key)
	if not separated(rects.icon, rects.name): failures.append("icon/name overlap")
	if not separated(rects.icon, rects.category): failures.append("icon/category overlap")
	if not separated(rects.name, rects.category): failures.append("name/category overlap")
	if rects.badge.has_area() and (not within(rects.badge, card) or not separated(rects.badge, rects.name)):
		failures.append("badge collision")
	return failures


static func _collect_surface_overflow(node: Node, bounds: Rect2, failures: Array[String]) -> void:
	for child: Node in node.get_children():
		if not child is Control or not (child as Control).visible:
			continue
		var control := child as Control
		if not within(control.get_global_rect(), bounds):
			failures.append("%s outside %s" % [control.name, (node as Control).name])
		_collect_surface_overflow(control, bounds, failures)
