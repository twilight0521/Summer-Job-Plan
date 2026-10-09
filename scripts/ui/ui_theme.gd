class_name UiTheme
extends RefCounted
## 全局 UI 主题：系统字体（支持中文）+ 统一的像素风配色。

const BG := Color("17181f")
const PANEL := Color("23252f")
const PANEL_LIGHT := Color("2e3140")
const TEXT := Color("e8e6df")
const TEXT_DIM := Color("a9a79f")
const ACCENT := Color("f2c14e")
const GOOD := Color("7ec96a")
const BAD := Color("e06c75")

static func build() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"PingFang SC", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
		"Heiti SC", "WenQuanYi Micro Hei", "sans-serif"
	])
	font.allow_system_fallback = true
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED

	ThemeDB.fallback_font = font
	ThemeDB.fallback_font_size = 15

	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	theme.set_stylebox("normal", "Button", _button_style(PANEL_LIGHT))
	theme.set_stylebox("hover", "Button", _button_style(Color("3a3e50")))
	theme.set_stylebox("pressed", "Button", _button_style(Color("4a4f66")))
	theme.set_stylebox("disabled", "Button", _button_style(Color("20222b")))
	theme.set_stylebox("panel", "Panel", _button_style(PANEL))
	theme.set_stylebox("panel", "PanelContainer", _button_style(PANEL))
	return theme

static func _button_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color("121319")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
