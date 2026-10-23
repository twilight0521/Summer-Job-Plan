extends Control
## 标题 / 存档选择

var _load_panel: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_wrap)

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center.custom_minimum_size = Vector2(320, 0)
	center_wrap.add_child(center)

	var title := Label.new()
	title.text = "暑假工计划"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	center.add_child(title)

	var sub := Label.new()
	sub.text = "60 天，一个城镇，很多种人生。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	center.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	center.add_child(spacer)

	_add_button(center, "新游戏", _on_new_game)
	_add_button(center, "继续游戏", _on_continue, SaveRepository.has_save(SaveRepository.AUTO_SLOT))
	_add_button(center, "读取存档", _on_open_load)
	_add_button(center, "设置", _on_settings)
	_add_button(center, "退出", _on_quit)

	# 键盘可操作：默认聚焦第一个按钮
	for child in center.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

	var profile := SaveRepository.load_profile()
	var total := ContentLoader.get_endings().size()
	var count: int = profile.get("unlocked_endings", []).size()
	var endings_label := Label.new()
	endings_label.text = "已解锁结局：%d / %d" % [count, total]
	endings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	endings_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	center.add_child(endings_label)

	_build_load_panel()

func _add_button(parent: Control, text: String, handler: Callable, enabled: bool = true) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.custom_minimum_size = Vector2(200, 30)
	btn.pressed.connect(handler)
	parent.add_child(btn)

func _build_load_panel() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.visible = false
	add_child(wrap)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(dim)

	var panel := PanelContainer.new()
	wrap.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(280, 0)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "选择存档"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	for slot in SaveRepository.MANUAL_SLOTS + [SaveRepository.AUTO_SLOT]:
		var info := SaveRepository.read_info(slot)
		var text := _slot_text(slot, info)
		var btn := Button.new()
		btn.text = text
		btn.disabled = info.is_empty()
		btn.pressed.connect(_on_load_slot.bind(slot))
		box.add_child(btn)

	var cancel := Button.new()
	cancel.text = "返回"
	cancel.pressed.connect(func(): wrap.visible = false)
	box.add_child(cancel)

	_load_panel = wrap

func _slot_text(slot: String, info: Dictionary) -> String:
	var names := {"manual_1": "手动档 1", "manual_2": "手动档 2", "manual_3": "手动档 3", "auto": "自动档"}
	if info.is_empty():
		return "%s（空）" % names.get(slot, slot)
	return "%s · 第 %d 天 · %s" % [names.get(slot, slot), int(info.get("day", 1)), GameConfig.slot_name(int(info.get("slot", 0)))]

func _on_new_game() -> void:
	GameFlow.start_new_game()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_continue() -> void:
	if GameFlow.load_game(SaveRepository.AUTO_SLOT):
		get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_open_load() -> void:
	_load_panel.visible = true

func _on_load_slot(slot: String) -> void:
	if GameFlow.load_game(slot):
		get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")

func _on_quit() -> void:
	get_tree().quit()
