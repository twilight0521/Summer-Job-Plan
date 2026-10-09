class_name InputRouter
extends RefCounted
## 统一输入映射：鼠标与键盘映射到同一命令。
## UI 只消费 Command，不直接读 Input。

enum Command {
	CONFIRM,
	CANCEL,
	UP,
	DOWN,
	LEFT,
	RIGHT,
	NEXT_SLOT,
	TOGGLE_LOG,
	SAVE,
	OPEN_MAP,
}

static func command_for_input(event: InputEvent) -> int:
	if event.is_action_pressed("ui_accept"):
		return Command.CONFIRM
	if event.is_action_pressed("ui_cancel"):
		return Command.CANCEL
	if event.is_action_pressed("ui_up"):
		return Command.UP
	if event.is_action_pressed("ui_down"):
		return Command.DOWN
	if event.is_action_pressed("ui_left"):
		return Command.LEFT
	if event.is_action_pressed("ui_right"):
		return Command.RIGHT
	if event.is_action_pressed("advance_slot"):
		return Command.NEXT_SLOT
	return -1

static func is_keyboard(event: InputEvent) -> bool:
	return event is InputEventKey
