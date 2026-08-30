class_name ToastCenter
extends VBoxContainer

const MAX_VISIBLE := 3
const LIFETIME_SECONDS := 3.2

var reduced_motion := false
var _active: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -410
	offset_top = 216
	offset_right = -18
	offset_bottom = 300
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 800


func push(message: String, kind := "INFO") -> void:
	var clean := message.strip_edges()
	if clean.is_empty():
		return
	for entry: Dictionary in _active:
		if entry.message == clean and entry.kind == kind:
			entry.count = int(entry.count) + 1
			entry.expires = Time.get_ticks_msec() + roundi(LIFETIME_SECONDS * 1000.0)
			_refresh_entry(entry)
			return
	while _active.size() >= MAX_VISIBLE:
		_remove_entry(_active[0])
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ElevatedPanel"
	var label := Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.custom_minimum_size = Vector2(340, 0); panel.add_child(label)
	add_child(panel)
	var entry := {"message":clean, "kind":kind.to_upper(), "count":1, "expires":Time.get_ticks_msec() + roundi(LIFETIME_SECONDS * 1000.0), "panel":panel, "label":label}
	_active.append(entry)
	_refresh_entry(entry)
	if not reduced_motion:
		KoalaSandTheme.animate_in(panel)
	set_process(true)


func messages() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in _active:
		result.append(str(entry.message))
	return result


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for entry: Dictionary in _active.duplicate():
		if now >= int(entry.expires):
			_remove_entry(entry)
	if _active.is_empty():
		set_process(false)


func _refresh_entry(entry: Dictionary) -> void:
	var prefix: String = str({"INFO":"ℹ", "SUCCESS":"✓", "WARNING":"!", "ERROR":"×"}.get(str(entry.kind), "ℹ"))
	(entry.label as Label).text = "%s  %s%s" % [prefix, entry.message, "  ×%d" % int(entry.count) if int(entry.count) > 1 else ""]
	(entry.label as Label).add_theme_color_override("font_color", {"INFO":KoalaSandTheme.COLOR_INFO, "SUCCESS":KoalaSandTheme.COLOR_SUCCESS, "WARNING":KoalaSandTheme.COLOR_WARNING, "ERROR":KoalaSandTheme.COLOR_DANGER}.get(str(entry.kind), KoalaSandTheme.COLOR_TEXT))


func _remove_entry(entry: Dictionary) -> void:
	_active.erase(entry)
	var panel := entry.panel as Control
	if is_instance_valid(panel):
		panel.queue_free()
