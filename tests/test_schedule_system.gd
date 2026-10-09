class_name TestScheduleSystem
extends RefCounted

static func run(t) -> void:
	var state := GameState.new_run(12345, ContentLoader.characters)
	var schedule := ScheduleSystem.new()

	t.eq(state.day, 1, "初始第 1 天")
	t.eq(state.slot, 0, "初始时段 0")
	t.eq(state.phase, 1, "初始阶段 1")

	# 跨越 4 个时段进入第 2 天
	var result: Dictionary = {}
	for i in range(4):
		result = schedule.advance_slot(state)
	t.eq(state.day, 2, "跨 4 时段进入第 2 天")
	t.eq(state.slot, 0, "跨天后回到时段 0")
	t.eq(result.get("ended_day", false), true, "第 4 时段推进结束当天")

	# 主动睡觉：早睡标记
	state.slot = 3
	var sleep_result := schedule.sleep_and_end_day(state)
	t.eq(bool(state.get_flag("early_sleep_ok")), true, "主动睡觉标记早睡")
	t.eq(sleep_result.get("ended_day", false), true, "睡觉结束当天")

	# 熬夜：睡眠债增加
	state.slot = 3
	schedule.auto_end_day(state)
	t.gte(float(state.get_flag("sleep_debt")), 1, "熬夜增加睡眠债")

	# 资源上下限
	state.add_player("health", 999, "测试")
	t.eq(int(state.player["health"]), 100, "健康上限 100")
	state.add_player("money", -99999, "测试")
	t.eq(int(state.player["money"]), 0, "现金下限 0")

	# 第 60 天结束进入结局判定
	state.day = 60
	state.phase = GameConfig.phase_of_day(state.day)
	state.slot = 3
	var last := schedule.advance_slot(state)
	t.eq(last.get("game_over", false), true, "第 60 天结束触发结局")
	t.gte(int(last.get("phase_completed", 0)), 4, "第 60 天完成第 4 阶段")

	# 阶段边界：第 15 天结束完成第 1 阶段
	var s2 := GameState.new_run(1, ContentLoader.characters)
	s2.day = 15
	s2.slot = 3
	var r2 := schedule.advance_slot(s2)
	t.eq(int(r2.get("phase_completed", 0)), 1, "第 15 天完成第 1 阶段")
	t.eq(s2.phase, 2, "进入第 2 阶段")
