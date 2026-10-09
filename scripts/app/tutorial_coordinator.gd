class_name TutorialCoordinator
extends RefCounted
## 新手引导：3 步，不锁功能，只用提示。

enum Step { HUD = 0, FIRST_JOB = 1, REST = 2, DONE = 3 }

var step: int = Step.HUD

const TIPS := {
	Step.HUD: "先看顶部天数和右侧资源，再决定今天做什么。",
	Step.FIRST_JOB: "试试去奶茶店打一次工，赚钱又能练沟通。",
	Step.REST: "累了就休息，然后用「睡觉」进入第二天。",
}

func reset() -> void:
	step = Step.HUD

func current_tip() -> String:
	return str(TIPS.get(step, ""))

func is_done() -> bool:
	return step == Step.DONE

func advance() -> void:
	if step < Step.DONE:
		step += 1

## 根据玩家行动推进引导进度。
func on_action(action_id: String) -> void:
	match step:
		Step.HUD:
			advance()
		Step.FIRST_JOB:
			if action_id == "tea_shop_shift":
				advance()
		Step.REST:
			if action_id == "rest" or action_id == "sleep":
				advance()
		_:
			pass
