class_name ExperimentsPanel
extends PanelContainer

var tracker: ExperimentTracker
var _list := VBoxContainer.new()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -470; offset_top = -320; offset_right = -20; offset_bottom = 320
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = KoalaSandTheme.build()
	theme_type_variation = "ElevatedPanel"
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	var row := HBoxContainer.new(); column.add_child(row)
	var title := Label.new(); title.text = "Experiments"; title.theme_type_variation = "ScreenTitleLabel"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(title)
	var close_button := Button.new(); close_button.theme_type_variation = "QuietButton"; close_button.text = "Close"; close_button.pressed.connect(func(): visible = false); row.add_child(close_button)
	var note := Label.new(); note.text = "Ideas for discovering how the physical world behaves."; note.theme_type_variation = "SecondaryLabel"; column.add_child(note)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	scroll.add_child(_list)

func initialize(value: ExperimentTracker) -> void:
	tracker = value
	refresh()

func refresh() -> void:
	if tracker == null: return
	for child in _list.get_children(): child.queue_free()
	for definition: Dictionary in ExperimentTracker.DEFINITIONS:
		var complete := bool(tracker.completed.get(str(definition.id), false))
		var label := Label.new()
		label.text = "%s  %s\n     %s" % ["✓" if complete else "○", str(definition.title), str(definition.description)]
		label.add_theme_color_override("font_color", KoalaSandTheme.COLOR_SUCCESS if complete else KoalaSandTheme.COLOR_TEXT_SECONDARY)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(label)
