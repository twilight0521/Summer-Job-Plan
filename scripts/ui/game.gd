extends Control
## 日程主界面：HUD + 地点/行动 + 属性/关系 + 日志 + 各类弹窗。

const RESOURCE_ORDER := ["money", "energy", "mood", "hunger", "fatigue", "health"]
const ATTR_ORDER := ["study", "math", "fitness", "communication", "skill", "responsibility"]

var stat_labels: Dictionary = {}
var attr_labels: Dictionary = {}
var rel_box: VBoxContainer
var action_box: VBoxContainer
var location_box: VBoxContainer
var log_label: RichTextLabel
var top_label: Label
var tip_label: Label
var overlay: Control
var _modal_open: bool = false
var _last_phase: int = 0
var _last_phase_summary: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_flow()
	if GameFlow.state == null:
		GameFlow.start_new_game()
	_refresh()

func _connect_flow() -> void:
	GameFlow.state_changed.connect(_refresh)
	GameFlow.message.connect(_on_message)
	GameFlow.action_resolved.connect(_on_action_resolved)
	GameFlow.event_requested.connect(_on_event_requested)
	GameFlow.event_resolved.connect(_on_event_resolved)
	GameFlow.exam_requested.connect(_on_exam_requested)
	GameFlow.exam_result.connect(_on_exam_result)
	GameFlow.phase_summary_requested.connect(_on_phase_summary)
	GameFlow.game_over.connect(_on_game_over)
	GameFlow.shop_requested.connect(_on_shop_requested)

func _on_action_resolved(result: Dictionary) -> void:
	_show_toast(result.get("changes", []))

# ---------------------------------------------------------------------------
# 构建界面
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_top_bar()
	_build_left_panel()
	_build_center_panel()
	_build_right_panel()
	_build_bottom_bar()

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.PANEL
	sb.set_border_width_all(1)
	sb.border_color = Color("121319")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _make_panel(rect: Rect2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.position = rect.position
	panel.size = rect.size
	return panel

func _build_top_bar() -> void:
	var panel := _make_panel(Rect2(4, 4, 632, 26))
	add_child(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	top_label = Label.new()
	box.add_child(top_label)
	tip_label = Label.new()
	tip_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(tip_label)

func _build_left_panel() -> void:
	var panel := _make_panel(Rect2(4, 34, 176, 268))
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.focus_mode = Control.FOCUS_NONE
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	var avatar := ColorRect.new()
	avatar.color = Color("3a3d4d")
	avatar.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(avatar)
	var avatar_label := Label.new()
	avatar_label.text = "  [ 玩家 ]"
	avatar.add_child(avatar_label)

	vbox.add_child(_section("状态"))
	for field in RESOURCE_ORDER:
		vbox.add_child(_stat_row(field, stat_labels))
	vbox.add_child(_section("其它"))
	vbox.add_child(_stat_row("luck", stat_labels))
	vbox.add_child(_stat_row("trust", stat_labels))
	vbox.add_child(_stat_row("exp", stat_labels))

func _build_center_panel() -> void:
	var panel := _make_panel(Rect2(184, 34, 288, 268))
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	vbox.add_child(_section("街区"))
	location_box = VBoxContainer.new()
	location_box.add_theme_constant_override("separation", 2)
	vbox.add_child(location_box)

	vbox.add_child(_section("可执行"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	vbox.add_child(scroll)
	action_box = VBoxContainer.new()
	action_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_box.add_theme_constant_override("separation", 3)
	scroll.add_child(action_box)

func _build_right_panel() -> void:
	var panel := _make_panel(Rect2(476, 34, 160, 268))
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.focus_mode = Control.FOCUS_NONE
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	vbox.add_child(_section("属性"))
	for field in ATTR_ORDER:
		vbox.add_child(_stat_row(field, attr_labels))
	vbox.add_child(_section("关系"))
	rel_box = VBoxContainer.new()
	rel_box.add_theme_constant_override("separation", 2)
	vbox.add_child(rel_box)

func _build_bottom_bar() -> void:
	var panel := _make_panel(Rect2(4, 306, 632, 50))
	add_child(panel)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(380, 0)
	hbox.add_child(log_label)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	hbox.add_child(buttons)
	_add_small_button(buttons, "跳过时段", func(): GameFlow.rest_until_next_slot())
	_add_small_button(buttons, "保存", func(): GameFlow.save_manual("manual_1"))
	_add_small_button(buttons, "标题", func(): get_tree().change_scene_to_file("res://scenes/title/title.tscn"))

func _section(text: String) -> Label:
	var label := Label.new()
	label.text = "— " + text
	label.add_theme_color_override("font_color", UiTheme.ACCENT)
	return label

func _stat_row(field: String, store: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var meta: Dictionary = GameConfig.FIELD_META.get(field, {"name": field, "icon": "•"})
	var name_label := Label.new()
	name_label.text = "%s%s" % [meta.get("icon", ""), meta.get("name", field)]
	name_label.custom_minimum_size = Vector2(78, 0)
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	store[field] = value_label
	return row

func _add_small_button(parent: Control, text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	parent.add_child(btn)

# ---------------------------------------------------------------------------
# 刷新
# ---------------------------------------------------------------------------

func _refresh() -> void:
	var state := GameFlow.state
	if state == null:
		return
	var weather := _weather_for(state)
	top_label.text = "第 %d / %d 天 · %s · 第 %d 阶段 · %s" % [
		state.day, GameConfig.TOTAL_DAYS, GameConfig.slot_name(state.slot), state.phase, weather
	]
	tip_label.text = GameFlow.tutorial.current_tip() if not GameFlow.tutorial.is_done() else ""

	for field in stat_labels:
		var value: Variant = state.player.get(field, 0)
		stat_labels[field].text = _format_value(field, value)
		stat_labels[field].add_theme_color_override("font_color", _color_for(field, value))
	for field in attr_labels:
		var value: Variant = state.player.get(field, 0)
		attr_labels[field].text = str(int(value))
		attr_labels[field].add_theme_color_override("font_color", _color_for(field, value))

	_refresh_locations()
	_refresh_actions()
	_refresh_relationships()
	if not _modal_open:
		_focus_first_action()

func _focus_first_action() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	for child in action_box.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return

func _refresh_locations() -> void:
	for child in location_box.get_children():
		child.queue_free()
	var state := GameFlow.state
	for loc in ContentLoader.all_locations():
		var loc_id := str(loc.get("id", ""))
		var btn := Button.new()
		var open := GameFlow.location_is_open(loc_id)
		var here := loc_id == state.location_id
		btn.text = "%s%s" % ["▶ " if here else "   ", loc.get("name", loc_id)]
		if not open:
			btn.text += "（未营业）"
		btn.disabled = here
		btn.pressed.connect(_on_location_pressed.bind(loc_id))
		location_box.add_child(btn)

func _on_location_pressed(loc_id: String) -> void:
	GameFlow.move_to(loc_id)

func _refresh_actions() -> void:
	for child in action_box.get_children():
		child.queue_free()
	var state := GameFlow.state
	var actions := GameFlow.available_actions()
	if actions.is_empty():
		var label := Label.new()
		label.text = "这里现在没什么可做的。"
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		action_box.add_child(label)
		return
	for action_id in actions:
		var preview := GameFlow.action_preview(action_id)
		var btn := Button.new()
		btn.text = str(preview.get("name", action_id))
		btn.tooltip_text = _preview_tooltip(preview)
		btn.pressed.connect(_on_action_pressed.bind(action_id, preview))
		action_box.add_child(btn)
	# 确保纯键盘启动时有可操作的焦点；弹窗会自行聚焦首个按钮。
	if not _modal_open and get_viewport().gui_get_focus_owner() == null and not action_box.get_children().is_empty():
		var first := action_box.get_child(0)
		if first is Control:
			first.grab_focus()

func _refresh_relationships() -> void:
	for child in rel_box.get_children():
		child.queue_free()
	for entry in GameFlow.relationship_system.summary(GameFlow.state):
		var label := Label.new()
		label.text = "%s  %d（%s）" % [entry.get("name", ""), int(entry.get("relationship", 0)), entry.get("label", "")]
		if not bool(entry.get("met", false)):
			label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		rel_box.add_child(label)

func _format_value(field: String, value: Variant) -> String:
	if field == "money":
		return "¥%d" % int(value)
	return str(int(value))

func _color_for(field: String, value: Variant) -> Color:
	match field:
		"health", "mood", "energy":
			var v := float(value)
			if v <= 25.0:
				return UiTheme.BAD
			if v >= 70.0:
				return UiTheme.GOOD
		"hunger", "fatigue":
			var v2 := float(value)
			if v2 >= 70.0:
				return UiTheme.BAD
			if v2 <= 30.0:
				return UiTheme.GOOD
		"money":
			return UiTheme.ACCENT
	return UiTheme.TEXT

func _weather_for(state: GameState) -> String:
	var weathers := ["晴", "多云", "阴", "小雨", "闷热"]
	var idx := absi(state.seed + state.day * 7) % weathers.size()
	return weathers[idx]

func _preview_tooltip(preview: Dictionary) -> String:
	var lines: Array = [str(preview.get("description", ""))]
	var cost: Dictionary = preview.get("cost", {})
	if not cost.is_empty():
		var parts: Array = []
		for key in cost:
			var meta: Dictionary = GameConfig.FIELD_META.get(key, {"name": key})
			parts.append("%s %+d" % [meta.get("name", key), int(EffectResolver.cost_delta(key, cost[key]))])
		lines.append("消耗：" + "，".join(parts))
	for w in preview.get("warnings", []):
		lines.append("⚠ " + str(w))
	return "\n".join(lines)

# ---------------------------------------------------------------------------
# 行动确认
# ---------------------------------------------------------------------------

func _on_action_pressed(action_id: String, preview: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = str(preview.get("name", action_id))
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var desc := Label.new()
	desc.text = str(preview.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 0)
	box.add_child(desc)

	var cost: Dictionary = preview.get("cost", {})
	if not cost.is_empty():
		var cost_label := Label.new()
		cost_label.text = _preview_tooltip({"cost": cost, "warnings": preview.get("warnings", [])})
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost_label.custom_minimum_size = Vector2(300, 0)
		box.add_child(cost_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var ok := Button.new()
	ok.text = "确认"
	ok.pressed.connect(func():
		_close_modal()
		GameFlow.perform_action(action_id)
	)
	buttons.add_child(ok)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_close_modal)
	buttons.add_child(cancel)

	_show_modal(box)

# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

func _on_event_requested(view: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = str(view.get("title", "事件"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)
	var text := Label.new()
	text.text = str(view.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(340, 0)
	box.add_child(text)
	for choice in view.get("choices", []):
		var btn := Button.new()
		btn.text = str(choice.get("text", ""))
		btn.pressed.connect(_choose_event.bind(str(choice.get("id", ""))))
		box.add_child(btn)
	_show_modal(box)

func _choose_event(choice_id: String) -> void:
	_close_modal()
	GameFlow.choose_event_choice(choice_id)

func _on_event_resolved(result: Dictionary) -> void:
	var text := str(result.get("result_text", ""))
	if text != "":
		_on_message(text)
	_show_toast(result.get("changes", []))

# ---------------------------------------------------------------------------
# 考试
# ---------------------------------------------------------------------------

func _on_exam_requested(exams: Array) -> void:
	if exams.is_empty():
		_on_message("目前没有可以参加的考试。")
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "参加考试"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for exam in exams:
		var exam_id := str(exam.get("id", ""))
		var label := Label.new()
		label.text = "%s（及格线 %d）" % [exam.get("name", exam_id), int(exam.get("pass_score", 60))]
		box.add_child(label)
		for choice in exam.get("choices", []):
			var btn := Button.new()
			btn.text = "  " + str(choice.get("text", ""))
			btn.pressed.connect(_on_exam_choice.bind(exam_id, str(choice.get("id", ""))))
			box.add_child(btn)
	var cancel := Button.new()
	cancel.text = "不考了"
	cancel.pressed.connect(_close_modal)
	box.add_child(cancel)
	_show_modal(box)

func _on_exam_choice(exam_id: String, choice_id: String) -> void:
	_close_modal()
	GameFlow.take_exam(exam_id, choice_id)

func _on_exam_result(result: Dictionary) -> void:
	var lines: Array = ["【%s】%d 分" % [result.get("exam_id", ""), int(result.get("score", 0))]]
	for line in result.get("breakdown", []):
		lines.append("· " + str(line))
	lines.append("结果：" + ("通过！" if bool(result.get("passed", false)) else "未通过"))
	_on_message("\n".join(lines))

# ---------------------------------------------------------------------------
# 商店
# ---------------------------------------------------------------------------

func _on_shop_requested(items: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "购买（现金 ¥%d）" % int(GameFlow.state.player.get("money", 0))
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	for item in items:
		var item_id := str(item.get("id", ""))
		var btn := Button.new()
		btn.text = "%s  ¥%d — %s" % [item.get("name", item_id), int(item.get("price", 0)), item.get("description", "")]
		btn.pressed.connect(_on_buy_pressed.bind(item_id))
		box.add_child(btn)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(_close_modal)
	box.add_child(close)
	_show_modal(box)

func _on_buy_pressed(item_id: String) -> void:
	GameFlow.buy_item(item_id)
	_close_modal()

# ---------------------------------------------------------------------------
# 阶段总结 / 结局
# ---------------------------------------------------------------------------

func _on_phase_summary(phase: int, summary: Dictionary) -> void:
	_last_phase = phase
	_last_phase_summary = summary
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "第 %d 阶段总结" % phase
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)
	box.add_child(_kv_label("现金", "¥%d" % int(summary.get("money", 0))))
	box.add_child(_kv_label("健康 / 心情", "%d / %d" % [int(summary.get("health", 0)), int(summary.get("mood", 0))]))
	box.add_child(_kv_label("学习 / 信任", "%d / %d" % [int(summary.get("study", 0)), int(summary.get("trust", 0))]))
	box.add_child(_kv_label("累计工作天数", str(int(summary.get("work_days", 0)))))
	box.add_child(_kv_label("经验点", str(int(summary.get("exp", 0)))))

	var passives := GameFlow.available_passives()
	if not passives.is_empty():
		var heading := Label.new()
		heading.text = "解锁被动能力"
		heading.add_theme_color_override("font_color", UiTheme.ACCENT)
		box.add_child(heading)
		for passive in passives:
			var passive_id := str(passive.get("id", ""))
			var btn := Button.new()
			btn.text = "%s（%d 经验）— %s" % [passive.get("name", passive_id), int(passive.get("cost", 0)), passive.get("description", "")]
			btn.pressed.connect(_on_unlock_passive.bind(passive_id))
			box.add_child(btn)

	var ok := Button.new()
	ok.text = "继续"
	ok.pressed.connect(func():
		_close_modal()
		GameFlow.continue_after_phase_summary()
	)
	box.add_child(ok)
	_show_modal(box)

func _on_unlock_passive(passive_id: String) -> void:
	GameFlow.unlock_passive(passive_id)
	if GameFlow.state != null:
		_last_phase_summary["exp"] = int(GameFlow.state.player.get("exp", 0))
	_on_phase_summary(_last_phase, _last_phase_summary)

func _on_game_over(summary: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "结局：" + str(summary.get("name", ""))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)
	var tagline := Label.new()
	tagline.text = str(summary.get("tagline", ""))
	tagline.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(tagline)
	var desc := Label.new()
	desc.text = str(summary.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(360, 0)
	box.add_child(desc)

	var stats: Dictionary = summary.get("stats", {})
	box.add_child(_kv_label("最终现金", "¥%d" % int(stats.get("money", 0))))
	box.add_child(_kv_label("学习 / 数学 / 技能", "%d / %d / %d" % [int(stats.get("study", 0)), int(stats.get("math", 0)), int(stats.get("skill", 0))]))
	box.add_child(_kv_label("健康 / 心情 / 信任", "%d / %d / %d" % [int(stats.get("health", 0)), int(stats.get("mood", 0)), int(stats.get("trust", 0))]))

	var keys: Array = summary.get("key_choices", [])
	if not keys.is_empty():
		var key_title := Label.new()
		key_title.text = "关键选择回放"
		key_title.add_theme_color_override("font_color", UiTheme.ACCENT)
		box.add_child(key_title)
		for entry in keys:
			var line := Label.new()
			line.text = "第 %d 天：%s → %s" % [int(entry.get("day", 0)), entry.get("title", ""), entry.get("choice", "")]
			line.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
			box.add_child(line)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var again := Button.new()
	again.text = "再来一局"
	again.pressed.connect(func():
		_close_modal()
		GameFlow.start_new_game()
		_refresh()
	)
	buttons.add_child(again)
	var to_title := Button.new()
	to_title.text = "回到标题"
	to_title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title/title.tscn"))
	buttons.add_child(to_title)

	_show_modal(box)

# ---------------------------------------------------------------------------
# 弹窗 / 提示
# ---------------------------------------------------------------------------

func _show_modal(content: Control) -> void:
	_close_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.name = "ModalDim"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.name = "ModalPanel"
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 300)
	scroll.focus_mode = Control.FOCUS_NONE
	panel.add_child(scroll)
	scroll.add_child(content)

	_modal_open = true
	_set_background_focus(false)
	var first := _first_button(content)
	if first != null:
		first.grab_focus()

func _close_modal() -> void:
	for child in overlay.get_children():
		child.queue_free()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_open = false
	_set_background_focus(true)

func _first_button(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null

func _all_buttons(node: Node) -> Array:
	var arr: Array = []
	if node is Button:
		arr.append(node)
	for child in node.get_children():
		arr.append_array(_all_buttons(child))
	return arr

func _set_background_focus(enabled: bool) -> void:
	for button in _all_buttons(self):
		if overlay.is_ancestor_of(button):
			continue
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _kv_label(key: String, value: String) -> Label:
	var label := Label.new()
	label.text = "%s：%s" % [key, value]
	return label

func _on_message(text: String) -> void:
	if log_label == null:
		return
	log_label.append_text("[color=#a9a79f]·[/color] " + text + "\n")

func _show_toast(changes: Array) -> void:
	if changes.is_empty():
		return
	var parts: Array = []
	for change in changes:
		if change.get("delta", null) == null:
			continue
		var delta := float(change["delta"])
		if is_zero_approx(delta):
			continue
		var field := str(change.get("field", ""))
		var meta: Dictionary = GameConfig.FIELD_META.get(field, {"name": field})
		var color := "#7ec96a" if delta > 0 else "#e06c75"
		parts.append("[color=%s]%s %+d[/color]" % [color, meta.get("name", field), int(delta)])
	if not parts.is_empty():
		_on_message("变化：" + "，".join(parts))

func _unhandled_input(event: InputEvent) -> void:
	var command := InputRouter.command_for_input(event)
	if command == InputRouter.Command.CANCEL:
		if _modal_open:
			_close_modal()
			get_viewport().set_input_as_handled()
		return
	if _modal_open:
		return
	if command == InputRouter.Command.NEXT_SLOT:
		GameFlow.rest_until_next_slot()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				GameFlow.save_manual("manual_1")
				get_viewport().set_input_as_handled()
			KEY_R:
				GameFlow.rest_until_next_slot()
				get_viewport().set_input_as_handled()
