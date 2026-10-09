extends Control
## 设置：音量、文字速度、退出到标题。

var profile: Dictionary

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	profile = SaveRepository.load_profile()
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wrap)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.custom_minimum_size = Vector2(320, 0)
	wrap.add_child(center)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	center.add_child(_slider_row("音乐音量", "bgm_volume"))
	center.add_child(_slider_row("音效音量", "sfx_volume"))
	center.add_child(_slider_row("文字速度", "text_speed"))

	var back := Button.new()
	back.text = "返回标题"
	back.custom_minimum_size = Vector2(160, 30)
	back.pressed.connect(func():
		SaveRepository.save_profile(profile)
		get_tree().change_scene_to_file("res://scenes/title/title.tscn")
	)
	center.add_child(back)
	back.grab_focus()

func _slider_row(label_text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.1
	slider.custom_minimum_size = Vector2(160, 0)
	slider.value = float(profile.get("settings", {}).get(key, 0.8))
	slider.value_changed.connect(func(v: float):
		var settings: Dictionary = profile.get("settings", {})
		settings[key] = v
		profile["settings"] = settings
		SaveRepository.save_profile(profile)
	)
	row.add_child(slider)
	return row
