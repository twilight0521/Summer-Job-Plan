class_name ParentSystem
extends RefCounted
## 父母奖励系统：每天根据出勤、学习、健康和消费给予反馈与一次性奖励。

func on_day_end(state: GameState) -> Dictionary:
	var changes: Array = []
	var messages: Array = []

	_on_time_reward(state, changes, messages)
	_low_cash_allowance(state, changes, messages)
	_hospital_cover(state, changes, messages)
	_scold(state, changes, messages)
	_idle_check(state, changes, messages)

	messages.append(_daily_line(state))
	state.set_flag("worked_today", false)
	state.set_flag("worked_on_time_today", false)
	state.set_flag("lottery_tickets_today", 0)
	return {"messages": messages, "changes": changes}

func _on_time_reward(state: GameState, changes: Array, messages: Array) -> void:
	var on_time := bool(state.get_flag("early_sleep_ok")) or bool(state.get_flag("worked_on_time_today"))
	var streak := int(state.get_flag("on_time_streak"))
	streak = streak + 1 if on_time else 0
	state.set_flag("on_time_streak", streak)
	if streak >= GameConfig.PARENT_ON_TIME_STREAK_REQUIRED:
		changes.append(state.add_player("money", float(GameConfig.PARENT_ON_TIME_BONUS), "父母奖励"))
		changes.append(state.add_npc_relationship("mom", 3, "父母奖励"))
		messages.append("连续 %d 天按时作息或上班，爸妈奖励了 ¥%d。" % [
			GameConfig.PARENT_ON_TIME_STREAK_REQUIRED, GameConfig.PARENT_ON_TIME_BONUS
		])
		state.set_flag("on_time_streak", 0)

func _low_cash_allowance(state: GameState, changes: Array, messages: Array) -> void:
	var last_day := int(state.get_flag("allowance_day"))
	var cooldown_ok := (state.day - last_day) >= 3
	if float(state.player.get("money", 0)) < float(GameConfig.PARENT_LOW_CASH) and float(state.player.get("health", 0)) >= 50.0 and cooldown_ok:
		changes.append(state.add_player("money", float(GameConfig.PARENT_ALLOWANCE), "父母生活费"))
		messages.append("爸妈看你手头紧，塞给你 ¥%d 生活费。" % GameConfig.PARENT_ALLOWANCE)
		state.set_flag("allowance_day", state.day)

func _hospital_cover(state: GameState, changes: Array, messages: Array) -> void:
	if bool(state.get_flag("hospitalized")):
		changes.append(state.add_player("money", float(GameConfig.PARENT_HOSPITAL_COVER), "父母承担医疗费"))
		changes.append(state.add_npc_relationship("mom", -3, "担心你受伤"))
		messages.append("爸妈替你承担了部分医疗费，但很担心你。")
		state.set_flag("hospitalized", false)

func _scold(state: GameState, changes: Array, messages: Array) -> void:
	var scold := false
	if bool(state.get_flag("did_shady_job")):
		scold = true
		state.set_flag("did_shady_job", false)
	if int(state.get_flag("lottery_tickets_today")) >= 3:
		scold = true
	if scold:
		changes.append(state.add_player("mood", -3, "被训话"))
		changes.append(state.add_npc_relationship("mom", -4, "被训话"))
		messages.append("爸妈发现你乱花钱或走了歪路，训了你一顿。")

func _idle_check(state: GameState, changes: Array, messages: Array) -> void:
	if not bool(state.get_flag("worked_today")) and state.day > 5:
		var idle := int(state.get_flag("idle_days")) + 1
		state.set_flag("idle_days", idle)
		if idle >= 3:
			changes.append(state.add_player("responsibility", -1, "连续旷工"))
			changes.append(state.add_npc_relationship("mom", -2, "连续旷工"))
			messages.append("你好几天没干活了，妈妈忍不住说了你几句。")
			state.set_flag("idle_days", 0)
	else:
		state.set_flag("idle_days", 0)

func _daily_line(state: GameState) -> String:
	var health := float(state.player.get("health", 100))
	var money := float(state.player.get("money", 0))
	if health < 40.0:
		return "妈妈皱着眉说：身体是本钱，别硬撑。"
	if money < 30.0:
		return "妈妈问：钱够不够花？不够就说。"
	if bool(state.get_flag("early_sleep_ok")):
		return "妈妈点点头：今天起得挺早。"
	return "妈妈随口问了几句今天的情况。"
