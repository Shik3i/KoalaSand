class_name CodexPanel
extends PanelContainer

signal closed

var _codex: PhysicsCodex
var _history: Array[String] = []
var _history_index := -1
var _search := LineEdit.new()
var _results := ItemList.new()
var _title := Label.new()
var _kind := Label.new()
var _body := RichTextLabel.new()
var _related := HFlowContainer.new()
var _result_ids: Array[String] = []
var _empty := Label.new()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -570
	offset_top = -350
	offset_right = 570
	offset_bottom = 350
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = KoalaSandTheme.build()
	theme_type_variation = "ModalPanel"
	visible = false
	_build_ui()

func initialize(codex: PhysicsCodex) -> void:
	_codex = codex
	_refresh_results("")

func open_entry(id := "") -> void:
	KoalaSandTheme.show_panel(self, true)
	if not id.is_empty():
		_navigate(id, true)
	elif _history_index < 0 and not _result_ids.is_empty():
		_navigate(_result_ids[0], true)
	_search.grab_focus()

func close() -> void:
	KoalaSandTheme.hide_panel(self, func() -> void: closed.emit())

func current_entry_id() -> String:
	return _history[_history_index] if _history_index >= 0 else ""

func _build_ui() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	var bar := HBoxContainer.new(); column.add_child(bar)
	var heading := Label.new(); heading.text = "Physics Codex"; heading.theme_type_variation = "ScreenTitleLabel"; heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.add_child(heading)
	var back := Button.new(); back.text = "←"; back.tooltip_text = "Back"; back.pressed.connect(_history_step.bind(-1)); bar.add_child(back)
	var forward := Button.new(); forward.text = "→"; forward.tooltip_text = "Forward"; forward.pressed.connect(_history_step.bind(1)); bar.add_child(forward)
	var close_button := Button.new(); close_button.theme_type_variation = "QuietButton"; close_button.text = "Close  [%s]" % InputGlyphs.action(&"open_codex"); close_button.pressed.connect(close); bar.add_child(close_button)
	_search.placeholder_text = "Search materials, Components and physics: heat, steam, screen, gold, oxygen…"
	_search.text_changed.connect(_refresh_results); column.add_child(_search)
	var content := HSplitContainer.new(); content.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.split_offset = 330; column.add_child(content)
	_results.custom_minimum_size.x = 310; _results.item_selected.connect(_select_result); content.add_child(_results)
	var detail_scroll := ScrollContainer.new(); content.add_child(detail_scroll)
	var detail := VBoxContainer.new(); detail.custom_minimum_size.x = 720; detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL; detail_scroll.add_child(detail)
	_kind.theme_type_variation = "CaptionLabel"; detail.add_child(_kind)
	_title.theme_type_variation = "ScreenTitleLabel"; detail.add_child(_title)
	_body.bbcode_enabled = true; _body.fit_content = true; _body.custom_minimum_size.y = 220; detail.add_child(_body)
	_empty.text = "No matching entries\nTry a material, component, process or physical property."; _empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _empty.theme_type_variation = "SecondaryLabel"; _empty.visible = false; detail.add_child(_empty)
	var related_title := Label.new(); related_title.text = "RELATED"; related_title.theme_type_variation = "SectionTitleLabel"; detail.add_child(related_title)
	detail.add_child(_related)
	var footer := Label.new(); footer.text = "Known physics only · undiscovered local geology stays hidden in Character mode"; footer.theme_type_variation = "CaptionLabel"; footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(footer)

func _refresh_results(query: String) -> void:
	if _codex == null: return
	_results.clear(); _result_ids.clear()
	for record: Dictionary in _codex.search(query):
		_result_ids.append(str(record.id))
		_results.add_item("%s  ·  %s" % [str(record.title), str(record.kind).to_upper()])
	_empty.visible = _result_ids.is_empty()
	if not _result_ids.is_empty() and _history_index < 0: _navigate(_result_ids[0], true)

func _select_result(index: int) -> void:
	if index >= 0 and index < _result_ids.size(): _navigate(_result_ids[index], true)

func _navigate(id: String, record_history: bool) -> void:
	if _codex == null: return
	var entry := _codex.get_entry(id)
	if entry.is_empty(): return
	if record_history:
		if _history_index + 1 < _history.size(): _history.resize(_history_index + 1)
		if _history.is_empty() or _history.back() != id: _history.append(id)
		_history_index = _history.size() - 1
	_kind.text = "CODEX  /  %s" % str(entry.kind).to_upper()
	_title.text = str(entry.title)
	var summary := str(entry.get("summary", ""))
	var sections := Dictionary(entry.get("sections", {}))
	var text := ""
	# Many entries repeat the summary verbatim as their first section; printing both reads
	# as a copy-paste slip rather than as a lead paragraph.
	var duplicated := false
	for value: Variant in sections.values():
		if str(value) == summary: duplicated = true
	if not summary.is_empty() and not duplicated:
		text = "[font_size=16][color=#b9cbc7]%s[/color][/font_size]\n\n" % summary
	for section: String in sections:
		text += "[color=#e8d58d][b]%s[/b][/color]\n%s\n\n" % [section, str(sections[section])]
	_body.text = text
	for child in _related.get_children(): child.queue_free()
	for related_id: String in Array(entry.get("related", [])):
		var related_entry := _codex.get_entry(related_id)
		if related_entry.is_empty(): continue
		var button := Button.new(); button.theme_type_variation = "QuietButton"; button.text = str(related_entry.title); button.pressed.connect(_navigate.bind(related_id, true)); _related.add_child(button)

func _history_step(delta: int) -> void:
	var next := _history_index + delta
	if next < 0 or next >= _history.size(): return
	_history_index = next
	_navigate(_history[_history_index], false)
