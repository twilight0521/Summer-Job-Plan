extends Node
## 启动场景：加载主题、校验内容，然后进入标题。

func _ready() -> void:
	var theme := UiTheme.build()
	get_tree().root.theme = theme

	if not ContentLoader.loaded:
		_show_content_error()
		return

	# 让首帧完成后再切场景，保证主题生效
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")

func _show_content_error() -> void:
	var label := Label.new()
	label.text = "内容加载失败，请检查 data/ 目录：\n" + "\n".join(ContentLoader.load_errors)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_color", Color("e06c75"))
	add_child(label)
