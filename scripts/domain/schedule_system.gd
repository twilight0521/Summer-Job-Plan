class_name ScheduleSystem
extends RefCounted
## 时段与阶段推进。统一 4 时段模型。
## slot: 0 凌晨 / 1 早上 / 2 下午 / 3 晚上
##
## 早班睡眠规则：只有在「晚上」时段主动睡觉才算 21:30 前入睡；
## 熬夜（撑到 24:00 自动结束）会产生睡眠债，睡眠债会降低体力上限。

const LAST_SLOT := 3
## 睡眠恢复量必须为正：睡眠债很高时公式会算出负值，
## 若直接取用会变成"睡一觉反而掉体力/涨疲劳"的死循环。
const SLEEP_FATIGUE_FLOOR := 10.0
const SLEEP_ENERGY_FLOOR := 20.0

var parent_system: ParentSystem

func _init() -> void:
	parent_system = ParentSystem.new()

func is_last_slot(state: GameState) -> bool:
	return state.slot >= LAST_SLOT

## 推进一个时段；若已是最后一个时段，则自动结束这一天。
func advance_slot(state: GameState) -> Dictionary:
	if state.slot < LAST_SLOT:
		state.slot += 1
		state.slot_used = false
		return {"advanced": true, "ended_day": false, "phase_completed": 0, "game_over": false}
	return auto_end_day(state)

## 无目标地消磨时间。过劳时无法继续发呆，会直接睡到次日。
func idle(state: GameState) -> Dictionary:
	if float(state.player.get("fatigue", 0)) >= 85.0 or float(state.player.get("energy", 0)) <= 10.0:
		var sleep_result := sleep_and_end_day(state)
		var sleep_messages: Array = ["你太累了，没能继续安排活动，直接睡着了。"]
		sleep_messages.append_array(sleep_result.get("messages", []))
		sleep_result["messages"] = sleep_messages
		sleep_result["forced_sleep"] = true
		return sleep_result
	var idle_message := ""
	var changes: Array = []
	if RandomSource.chance(0.5):
		changes.append(state.add_player("mood", 1, "发呆放松"))
		changes.append(state.add_player("fatigue", 2, "发呆"))
		idle_message = "你发了一会儿呆，心情稍微放松了。"
	else:
		changes.append(state.add_player("energy", -2, "发呆"))
		changes.append(state.add_player("fatigue", 1, "发呆"))
		idle_message = "你漫无目的地消磨了一个时段。"
	var result := advance_slot(state)
	var messages: Array = [idle_message]
	messages.append_array(result.get("messages", []))
	result["messages"] = messages
	changes.append_array(result.get("changes", []))
	result["changes"] = changes
	result["forced_sleep"] = false
	return result

## 玩家主动睡觉。晚上（slot 3）入睡视为 21:30 前早睡。
func sleep_and_end_day(state: GameState) -> Dictionary:
	var changes: Array = []
	var early := state.slot >= LAST_SLOT
	changes.append(state.set_flag("early_sleep_ok", early))
	var debt := maxi(0, int(state.get_flag("sleep_debt")) - 1)
	changes.append(state.set_flag("sleep_debt", debt))

	var recover := _sleep_recovery(state)
	changes.append(state.add_player("fatigue", -recover.fatigue, "睡眠"))
	changes.append(state.add_player("energy", recover.energy, "睡眠"))
	if debt >= 3:
		changes.append(state.add_player("health", -5, "长期睡眠不足"))
		changes.append(state.add_player("mood", -3, "长期睡眠不足"))

	var end := _end_day(state)
	changes.append_array(end.get("changes", []))
	end["changes"] = changes
	var msgs := ["你睡了一觉，进入第 %d 天。" % state.day]
	if early:
		msgs.append("睡得很早，明天可以按时起床。")
	else:
		msgs.append("白天补了一觉，作息有点乱。")
	msgs.append_array(end.get("messages", []))
	end["messages"] = msgs
	return end

## 未主动睡觉，硬撑到深夜后自动进入下一天（睡眠不足）。
func auto_end_day(state: GameState) -> Dictionary:
	var changes: Array = []
	changes.append(state.set_flag("early_sleep_ok", false))
	var debt := int(state.get_flag("sleep_debt")) + 1
	changes.append(state.set_flag("sleep_debt", debt))
	changes.append(state.add_player("health", -3, "熬夜"))
	changes.append(state.add_player("fatigue", 10, "熬夜"))

	var end := _end_day(state)
	changes.append_array(end.get("changes", []))
	end["changes"] = changes
	var msgs := ["你熬到深夜，直接昏睡过去。"]
	if debt >= GameConfig.OVERSLEEP_DEBT_THRESHOLD:
		msgs.append("连续睡眠不足，第二天恐怕起不来。")
	elif debt >= 2:
		msgs.append("连续睡眠不足，明天可能起不来。")
	msgs.append_array(end.get("messages", []))
	end["messages"] = msgs
	return end

## 睡眠恢复量必须为非负，见上方常量说明。
func _sleep_recovery(state: GameState) -> Dictionary:
	var debt := int(state.get_flag("sleep_debt"))
	var fatigue := float(state.player.get("fatigue", 0))
	# 疲劳恢复到 (50 - 5*debt) 为止；债高时最多只恢复到 SLEEP_FATIGUE_FLOOR。
	var fatigue_target := clampf(50.0 - float(debt) * 5.0, SLEEP_FATIGUE_FLOOR, 100.0)
	var fatigue_recover := 0.0
	if fatigue > 0.0:
		fatigue_recover = maxf(0.0, minf(fatigue, fatigue_target))
	return {
		"fatigue": fatigue_recover,
		"energy": maxf(SLEEP_ENERGY_FLOOR, 55.0 - float(debt) * 8.0),
	}

func _end_day(state: GameState) -> Dictionary:
	# 每日自然变化
	state.add_player("hunger", float(GameConfig.DAILY_DRIFT.get("hunger", 12)), "每日变化")
	state.add_player("fatigue", float(GameConfig.DAILY_DRIFT.get("fatigue", 4)), "每日变化")
	state.add_player("energy", float(GameConfig.DAILY_DRIFT.get("energy", -8)), "每日变化")

	# 连续锻炼中断
	if not bool(state.get_flag("exercise_today")):
		state.set_flag("exercise_streak", 0)
	state.set_flag("exercise_today", false)
	state.set_flag("lottery_streak", 0)

	# 伤势恢复
	var injury_days := int(state.get_flag("injury_days"))
	if injury_days > 0:
		injury_days -= 1
		state.set_flag("injury_days", injury_days)
		if injury_days == 0:
			state.set_flag("injury", "")

	# 健康联动：极度饥饿 / 过劳
	if float(state.player.get("hunger", 0)) >= 90:
		state.add_player("health", -4, "长期饥饿")
	if float(state.player.get("fatigue", 0)) >= 90:
		state.add_player("health", -3, "过度疲劳")

	# 父母每日反馈与奖励
	var parent_result := parent_system.on_day_end(state)

	var completed_phase := state.phase
	var game_over := state.day >= GameConfig.TOTAL_DAYS
	if not game_over:
		state.day += 1
		state.slot = 0
		state.slot_used = false
		state.phase = GameConfig.phase_of_day(state.day)

	# 连续睡眠不足：第二天起不来，错过早班并扣责任感
	var overslept := int(state.get_flag("sleep_debt")) >= GameConfig.OVERSLEEP_DEBT_THRESHOLD
	state.set_flag("overslept", overslept)
	if overslept:
		state.add_player("responsibility", -2, "连续熬夜起不来")
	var phase_completed := 0
	if game_over or (state.day - 1) % GameConfig.PHASE_LENGTH == 0:
		phase_completed = completed_phase

	return {
		"advanced": true,
		"ended_day": true,
		"phase_completed": phase_completed,
		"game_over": game_over,
		"messages": parent_result.get("messages", []),
		"changes": parent_result.get("changes", []),
	}
