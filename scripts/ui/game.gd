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
var primary_action_button: Button
var overlay: Control
var top_panel: PanelContainer
var left_panel: PanelContainer
var center_panel: PanelContainer
var right_panel: PanelContainer
var bottom_panel: PanelContainer
var _modal_open: bool = false
## 强制选择类弹窗（事件 / 阶段总结 / 结局）不允许 Esc 关闭：
## 关掉会跳过事件且留下未决的 pending 状态，导致时段推进错乱。
var _modal_dismissible: bool = true
var _last_phase: int = 0
var _last_phase_summary: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_flow()
	if GameFlow.state == null:
		GameFlow.start_new_game()
	else:
		GameFlow.resume_pending_flow()
	_refresh()
	_maybe_show_intro()

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
	_layout_ui()

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

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_layout_ui()

func _layout_ui() -> void:
	if top_panel == null or bottom_panel == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var margin := clampf(viewport_size.x * 0.012, 8.0, 20.0)
	var gap := clampf(viewport_size.x * 0.008, 6.0, 14.0)
	var top_height := clampf(viewport_size.y * 0.075, 42.0, 64.0)
	var bottom_height := clampf(viewport_size.y * 0.14, 76.0, 112.0)
	var content_y := margin + top_height + gap
	var content_bottom := viewport_size.y - margin - bottom_height - gap
	var content_height := maxf(120.0, content_bottom - content_y)
	var available_width := viewport_size.x - margin * 2.0 - gap * 2.0
	var left_width := clampf(available_width * 0.24, 210.0, 330.0)
	var right_width := clampf(available_width * 0.23, 210.0, 330.0)
	var center_width := available_width - left_width - right_width
	if center_width < 320.0:
		var deficit := 320.0 - center_width
		left_width = maxf(180.0, left_width - deficit * 0.5)
		right_width = maxf(180.0, right_width - deficit * 0.5)
		center_width = available_width - left_width - right_width
	top_panel.position = Vector2(margin, margin)
	top_panel.size = Vector2(viewport_size.x - margin * 2.0, top_height)
	left_panel.position = Vector2(margin, content_y)
	left_panel.size = Vector2(left_width, content_height)
	center_panel.position = Vector2(margin + left_width + gap, content_y)
	center_panel.size = Vector2(center_width, content_height)
	right_panel.position = Vector2(margin + left_width + gap + center_width + gap, content_y)
	right_panel.size = Vector2(right_width, content_height)
	bottom_panel.position = Vector2(margin, content_bottom + gap)
	bottom_panel.size = Vector2(viewport_size.x - margin * 2.0, bottom_height)
	if log_label != null:
		log_label.custom_minimum_size = Vector2(maxf(240.0, bottom_panel.size.x - 190.0), 0)
	if action_box != null:
		action_box.custom_minimum_size = Vector2(0, maxf(120.0, content_height * 0.45))

func _build_top_bar() -> void:
	top_panel = _make_panel(Rect2(0, 0, 0, 0))
	add_child(top_panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	top_panel.add_child(box)
	top_label = Label.new()
	box.add_child(top_label)
	tip_label = Label.new()
	tip_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(tip_label)

func _build_left_panel() -> void:
	left_panel = _make_panel(Rect2(0, 0, 0, 0))
	add_child(left_panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.focus_mode = Control.FOCUS_NONE
	left_panel.add_child(scroll)
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
	center_panel = _make_panel(Rect2(0, 0, 0, 0))
	add_child(center_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	center_panel.add_child(vbox)

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
	right_panel = _make_panel(Rect2(0, 0, 0, 0))
	add_child(right_panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.focus_mode = Control.FOCUS_NONE
	right_panel.add_child(scroll)
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
	bottom_panel = _make_panel(Rect2(0, 0, 0, 0))
	add_child(bottom_panel)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	bottom_panel.add_child(hbox)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(380, 0)
	hbox.add_child(log_label)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	hbox.add_child(buttons)
	_add_small_button(buttons, "发呆 / 随机", func(): GameFlow.idle_until_next_slot())
	primary_action_button = _add_small_button(buttons, "确认行动", _on_primary_action_pressed)

func _section(text: String) -> Label:
	var label := Label.new()
	label.text = "— " + text
	label.add_theme_color_override("font_color", UiTheme.ACCENT)
	return label

func _stat_row(field: String, store: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var tip := GameConfig.field_tip(field)
	if tip != "":
		row.tooltip_text = tip
	var meta: Dictionary = GameConfig.FIELD_META.get(field, {"name": field, "icon": "•"})
	var name_label := Label.new()
	name_label.text = "%s%s" % [meta.get("icon", ""), meta.get("name", field)]
	name_label.custom_minimum_size = Vector2(78, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(value_label)
	store[field] = value_label
	return row

func _add_small_button(parent: Control, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn

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
	_refresh_primary_action()
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
	_clear_children(location_box)
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
	_clear_children(action_box)
	var actions := GameFlow.location_actions()
	if actions.is_empty():
		var label := Label.new()
		label.text = "这里现在没什么可做的。"
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		action_box.add_child(label)
		return
	for action_id in actions:
		var preview := GameFlow.action_preview(str(action_id))
		var btn := Button.new()
		var ok := bool(preview.get("ok", false))
		btn.text = str(preview.get("name", action_id))
		if not ok:
			btn.text += "（不可用）"
		btn.disabled = not ok
		btn.tooltip_text = _preview_tooltip(preview)
		if ok:
			btn.pressed.connect(_on_action_pressed.bind(str(action_id), preview))
		action_box.add_child(btn)
	# 确保纯键盘启动时有可操作的焦点；弹窗会自行聚焦首个按钮。
	if not _modal_open and get_viewport().gui_get_focus_owner() == null and not action_box.get_children().is_empty():
		for child in action_box.get_children():
			if child is Button and not child.disabled:
				child.grab_focus()
				break

func _refresh_primary_action() -> void:
	if primary_action_button == null:
		return
	var candidate := GameFlow.primary_location_action()
	primary_action_button.disabled = candidate.is_empty()
	primary_action_button.text = str(candidate.get("label", "确认行动")) if not candidate.is_empty() else "当前无可确认行动"
	if not candidate.is_empty():
		primary_action_button.tooltip_text = _preview_tooltip(candidate.get("preview", {}))

func _on_primary_action_pressed() -> void:
	var candidate := GameFlow.primary_location_action()
	if candidate.is_empty():
		return
	_on_action_pressed(str(candidate.get("action_id", "")), candidate.get("preview", {}))

func _refresh_relationships() -> void:
	_clear_children(rel_box)
	for entry in GameFlow.relationship_system.summary(GameFlow.state):
		var label := Label.new()
		label.text = "%s  %d（%s）" % [entry.get("name", ""), int(entry.get("relationship", 0)), entry.get("label", "")]
		if not bool(entry.get("met", false)):
			label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		rel_box.add_child(label)

func _format_value(field: String, value: Variant) -> String:
	if field == "money":
		return "¥%d" % int(value)
	if field == "hunger":
		# 饥饿越高越饿、越该吃饭；后缀避免和「数值高=好」的属性搞混。
		var v := int(value)
		if v >= 90:
			return "%d·很饿" % v
		if v >= 70:
			return "%d·偏饿" % v
		if v >= 40:
			return "%d·微饿" % v
		return "%d·尚可" % v
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
	if not bool(preview.get("ok", true)):
		for reason in preview.get("reasons", []):
			lines.append("× " + str(reason))
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
	var selected_action := ContentLoader.get_action(action_id)
	var handler := str(selected_action.get("handler", ""))
	# 考试/商店入口本身不推进时段；真正作答或取消后再决定。
	if GameFlow.state.slot >= 3 and int(selected_action.get("duration_slots", 1)) > 0 \
		and handler != "sleep" and handler != "exam" and handler != "shop":
		var late_warning := Label.new()
		late_warning.text = "晚上行动后将直接熬夜进入明天：健康 -3、疲劳 +10，并增加睡眠债。选择“睡觉”可正常恢复。"
		late_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		late_warning.add_theme_color_override("font_color", UiTheme.BAD)
		late_warning.custom_minimum_size = Vector2(300, 0)
		box.add_child(late_warning)

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
	_show_modal(box, false)

func _choose_event(choice_id: String) -> void:
	# 只有结算成功才关弹窗；失败（如付不起钱）时保留弹窗换一个选项。
	if GameFlow.choose_event_choice(choice_id):
		# 结算期间可能同步打开阶段总结或结局，不能再关闭新弹窗。
		if not GameFlow.is_game_finished() and not GameFlow.is_awaiting_phase_continue():
			_close_modal()

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
		var cost: Dictionary = exam.get("cost", {})
		var cost_text := ""
		if cost.has("energy"):
			cost_text = " · 体力 -%d" % int(absf(float(cost["energy"])))
		label.text = "%s（及格线 %d%s）" % [exam.get("name", exam_id), int(exam.get("pass_score", 60)), cost_text]
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
	var exam_id := str(result.get("exam_id", ""))
	var exam := ContentLoader.get_exam(exam_id)
	var exam_name := str(exam.get("name", exam_id))
	var lines: Array = ["【%s】%d 分" % [exam_name, int(result.get("score", 0))]]
	for line in result.get("breakdown", []):
		lines.append("· " + str(line))
	lines.append("结果：" + ("通过！" if bool(result.get("passed", false)) else "未通过"))
	_on_message("\n".join(lines))
	_show_toast(result.get("changes", []))

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
	# 买完保持商店打开，方便连续采购；现金标题随状态刷新。
	_on_shop_requested(ContentLoader.all_items())

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
	_show_modal(box, false)

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
		_maybe_show_intro()
	)
	buttons.add_child(again)
	var to_title := Button.new()
	to_title.text = "回到标题"
	to_title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title/title.tscn"))
	buttons.add_child(to_title)

	_show_modal(box, false)

# ---------------------------------------------------------------------------
# 开局介绍
# ---------------------------------------------------------------------------

func _maybe_show_intro() -> void:
	if not GameFlow.should_show_intro():
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "暑假开始了"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)

	var body := Label.new()
	body.text = "\n".join([
		"你是一名准备过暑假的高中生。接下来有 60 天，",
		"可以在这个小镇里打工赚钱、补课学习、社交消费，",
		"也可以什么都不做——但每一天都会留下痕迹。",
		"",
		"主线没有唯一正确答案。你会慢慢走向不同结局：",
		"· 攒下第一桶金，体验一点独立",
		"· 认真备考，走到会计实习路线",
		"· 经营人际与口碑，成为街坊都认识的人",
		"· 或是体力心情透支，迎来吐槽式收尾",
		"",
		"每天分凌晨、早上、下午、晚上四个时段。",
		"出门选地点、做选择，睡觉进入下一天；",
		"第 15 / 30 / 45 / 60 天会有阶段总结。",
		"",
		"左边是状态，右边是能力与关系。",
		"把鼠标移到各项数值上，可以看到它们各自的作用。",
	])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(360, 0)
	box.add_child(body)

	var ok := Button.new()
	ok.text = "开始安排今天"
	ok.pressed.connect(func():
		GameFlow.mark_intro_seen()
		_close_modal()
	)
	box.add_child(ok)
	_show_modal(box, false)

# ---------------------------------------------------------------------------
# 弹窗 / 提示
# ---------------------------------------------------------------------------

func _show_modal(content: Control, dismissible: bool = true) -> void:
	_close_modal()
	_modal_dismissible = dismissible
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
	_clear_children(overlay)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_open = false
	_modal_dismissible = true
	_set_background_focus(true)

## 先摘出再释放：queue_free 的节点要到帧末才真正消失，
## 直接 queue_free 后立刻 add_child 会让新旧节点在同一帧共存（重复显示、焦点错乱）。
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

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
	_log_line(_escape_bbcode(text))

## 内容文案直接进 RichTextLabel 会被当成 BBCode 解析，方括号需要转义。
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

## 已经带好 BBCode 标记的文本走这里，不做转义。
func _log_line(text: String) -> void:
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
		var field_name := _change_field_name(field)
		var color := "#7ec96a" if delta > 0 else "#e06c75"
		parts.append("[color=%s]%s %+d[/color]" % [color, field_name, int(delta)])
	if not parts.is_empty():
		_log_line("变化：" + "，".join(parts))

func _change_field_name(field: String) -> String:
	var meta: Dictionary = GameConfig.FIELD_META.get(field, {})
	if not meta.is_empty():
		return str(meta.get("name", field))
	var parts := field.split(".")
	if parts.size() >= 3 and parts[0] == "npcs":
		var character := ContentLoader.get_character(parts[1])
		var character_name := str(character.get("name", parts[1]))
		var property_name: String = str({"relationship": "关系", "trust": "信任"}.get(parts[2], parts[2]))
		return "%s%s" % [character_name, property_name]
	if parts.size() >= 2 and parts[0] == "player":
		return str(GameConfig.FIELD_META.get(parts[1], {"name": parts[1]}).get("name", parts[1]))
	if parts.size() >= 2 and parts[0] == "flags":
		return "状态：%s" % parts[1]
	return field

func _unhandled_input(event: InputEvent) -> void:
	var command := InputRouter.command_for_input(event)
	if command == InputRouter.Command.CANCEL:
		if _modal_open:
			# 强制选择类弹窗（事件/阶段总结/结局）不接受 Esc 关闭。
			if _modal_dismissible:
				_close_modal()
		else:
			get_tree().change_scene_to_file("res://scenes/title/title.tscn")
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
