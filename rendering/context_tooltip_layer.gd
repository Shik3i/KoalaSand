class_name ContextTooltipLayer
extends Control

signal codex_requested(entry_id: String)

const DEFAULT_DELAY_SECONDS := 0.4
const MAX_WIDTH := 420.0

var delay_seconds := DEFAULT_DELAY_SECONDS
var _hovered: Control
var _hover_started_msec := 0
var _panel: PanelContainer
var _title: Label
var _description: Label
var _state: Label
var _disabled_reason: Label
var _shortcut: Label
var _secondary: Label
var _codex_button: Button
var _codex_id := ""
var _panel_hovered := false
var _hide_generation := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	_build_panel()
	set_process(true)


func bind_tree(root: Node) -> void:
	_bind_recursive(root)
	if not root.child_entered_tree.is_connected(_on_child_entered):
		root.child_entered_tree.connect(_on_child_entered)


func bind(control_node: Control, spec := {}) -> void:
	if control_node == self or control_node == _panel or control_node.has_meta("ux_tooltip_bound"):
		return
	var resolved: Dictionary = Dictionary(spec).duplicate(true)
	if resolved.is_empty() and control_node.has_meta("ux_tooltip_spec"):
		resolved = Dictionary(control_node.get_meta("ux_tooltip_spec")).duplicate(true)
	if resolved.is_empty() and not control_node.tooltip_text.strip_edges().is_empty():
		var stock := control_node.tooltip_text.strip_edges()
		var split := stock.split("\n", false, 1)
		resolved = {
			"title": split[0],
			"description": split[1] if split.size() > 1 else "Player control. Use the shown binding to open or activate it.",
		}
	if resolved.is_empty() or not HelpCatalog.valid(resolved):
		return
	HelpCatalog.attach(control_node, resolved)
	control_node.set_meta("ux_tooltip_bound", true)
	control_node.mouse_entered.connect(_on_control_entered.bind(control_node))
	control_node.mouse_exited.connect(_on_control_exited.bind(control_node))
	control_node.tree_exiting.connect(_on_control_removed.bind(control_node))


func show_virtual(spec: Dictionary, target_rect: Rect2) -> void:
	_hovered = null
	_show(spec, target_rect)


func hide_tooltip() -> void:
	_hovered = null
	_panel.hide()


func visible_text() -> String:
	if not _panel.visible:
		return ""
	var lines: Array[String] = [_title.text, _description.text]
	for label: Label in [_state, _disabled_reason, _shortcut, _secondary]:
		if label.visible and not label.text.is_empty():
			lines.append(label.text)
	return "\n".join(lines)


static func clamped_position(target_rect: Rect2, tooltip_size: Vector2, viewport_size: Vector2) -> Vector2:
	var margin := 12.0
	var result := Vector2(target_rect.position.x, target_rect.end.y + margin)
	if result.y + tooltip_size.y > viewport_size.y - margin:
		result.y = target_rect.position.y - tooltip_size.y - margin
	if result.y < margin:
		result.y = clampf(target_rect.get_center().y - tooltip_size.y * 0.5, margin, maxf(margin, viewport_size.y - tooltip_size.y - margin))
	result.x = clampf(result.x, margin, maxf(margin, viewport_size.x - tooltip_size.x - margin))
	return result


func _process(_delta: float) -> void:
	if _hovered == null or not is_instance_valid(_hovered) or _panel.visible:
		return
	if Time.get_ticks_msec() - _hover_started_msec >= roundi(delay_seconds * 1000.0):
		_show(Dictionary(_hovered.get_meta("ux_tooltip_spec", {})), _hovered.get_global_rect())


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "TooltipPanel"
	_panel.custom_minimum_size = Vector2(280, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.hide()
	_panel.mouse_entered.connect(func(): _panel_hovered = true; _hide_generation += 1)
	_panel.mouse_exited.connect(func(): _panel_hovered = false; _panel.hide())
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_title = Label.new(); _title.theme_type_variation = "SectionTitleLabel"; column.add_child(_title)
	_description = Label.new(); _description.custom_minimum_size.x = 300; column.add_child(_description)
	_state = Label.new(); _state.theme_type_variation = "SecondaryLabel"; column.add_child(_state)
	_disabled_reason = Label.new(); _disabled_reason.theme_type_variation = "WarningLabel"; column.add_child(_disabled_reason)
	_shortcut = Label.new(); _shortcut.theme_type_variation = "CaptionLabel"; column.add_child(_shortcut)
	_secondary = Label.new(); _secondary.theme_type_variation = "CaptionLabel"; column.add_child(_secondary)
	_codex_button = Button.new(); _codex_button.theme_type_variation = "QuietButton"; _codex_button.text = "Open in Codex"; _codex_button.pressed.connect(_open_codex); column.add_child(_codex_button)


func _show(spec: Dictionary, target_rect: Rect2) -> void:
	if not HelpCatalog.valid(spec):
		return
	_title.text = str(spec.get("title", ""))
	_description.text = _wrap_text(str(spec.get("description", "")))
	_set_optional(_state, _wrap_text(str(spec.get("state", ""))))
	var disabled_text := str(spec.get("disabled_reason", ""))
	_set_optional(_disabled_reason, _wrap_text("Unavailable · %s" % disabled_text) if not disabled_text.is_empty() else "")
	var action := StringName(str(spec.get("shortcut_action", "")))
	_set_optional(_shortcut, "Shortcut · %s" % InputGlyphs.action(action) if not action.is_empty() else "")
	_set_optional(_secondary, _wrap_text(str(spec.get("secondary", ""))))
	_codex_id = str(spec.get("codex_id", ""))
	_codex_button.visible = not _codex_id.is_empty()
	_panel.show()
	# Autowrapped Labels report an exaggerated minimum height before their first
	# layout pass. Size from bounded content instead so a tooltip can never turn
	# into a full-height panel on its first frame.
	var content_height := 84.0 + ceilf(float(_description.text.length()) / 46.0) * 20.0
	for label: Label in [_state, _disabled_reason, _shortcut, _secondary]:
		if label.visible: content_height += 24.0 + floorf(float(label.text.length()) / 50.0) * 16.0
	if _codex_button.visible: content_height += 42.0
	var tooltip_size := Vector2(360.0, clampf(content_height, 132.0, 292.0))
	_panel.size = tooltip_size
	_panel.position = clamped_position(target_rect, tooltip_size, get_viewport_rect().size)


func _set_optional(label: Label, value: String) -> void:
	label.text = value
	label.visible = not value.is_empty()


func _wrap_text(value: String, max_chars := 48) -> String:
	var lines: Array[String] = []
	for paragraph: String in value.split("\n"):
		var current := ""
		for word: String in paragraph.split(" ", false):
			if current.is_empty() or current.length() + word.length() + 1 <= max_chars:
				current += ("" if current.is_empty() else " ") + word
			else:
				lines.append(current); current = word
		if not current.is_empty(): lines.append(current)
	return "\n".join(lines)


func _bind_recursive(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_on_child_entered):
		node.child_entered_tree.connect(_on_child_entered)
	if node is Control:
		bind(node as Control)
	for child: Node in node.get_children():
		_bind_recursive(child)


func _on_child_entered(node: Node) -> void:
	call_deferred("_bind_recursive", node)


func _on_control_entered(control_node: Control) -> void:
	_hide_generation += 1
	_hovered = control_node
	_hover_started_msec = Time.get_ticks_msec()
	_panel.hide()


func _on_control_exited(control_node: Control) -> void:
	if _hovered == control_node:
		_hide_generation += 1
		_hide_after_grace(control_node, _hide_generation)


func _hide_after_grace(control_node: Control, generation: int) -> void:
	await get_tree().create_timer(0.14).timeout
	if generation != _hide_generation or _panel_hovered:
		return
	if _hovered == control_node:
		_hovered = null
		_panel.hide()


func _on_control_removed(control_node: Control) -> void:
	if _hovered == control_node:
		hide_tooltip()


func _open_codex() -> void:
	if not _codex_id.is_empty():
		codex_requested.emit(_codex_id)
