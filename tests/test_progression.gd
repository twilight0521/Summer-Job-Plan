class_name TestProgression
extends RefCounted
## 睡眠规则、经验与被动、父母奖励、考试阶段限制。

static func run(t) -> void:
	_sleep_rules(t)
	_experience_and_passives(t)
	_parent_rewards(t)
	_exam_phase_gate(t)
	_idle_and_plans(t)
	_plan_ui_smoke(t)

static func _sleep_rules(t) -> void:
	var sched := ScheduleSystem.new()

	var s := GameState.new_run(201, ContentLoader.characters)
	s.slot = 3
	sched.sleep_and_end_day(s)
	t.eq(bool(s.get_flag("early_sleep_ok")), true, "晚上主动睡觉算早睡")

	var s2 := GameState.new_run(202, ContentLoader.characters)
	s2.slot = 3
	sched.auto_end_day(s2)
	t.eq(bool(s2.get_flag("early_sleep_ok")), false, "熬夜不算早睡")
	t.gte(float(s2.get_flag("sleep_debt")), 1, "熬夜增加睡眠债")
	t.ok(s2.max_for("energy") < 100.0, "睡眠债降低体力上限")

	# 连续熬夜到阈值触发起不来
	var s3 := GameState.new_run(203, ContentLoader.characters)
	s3.set_flag("sleep_debt", GameConfig.OVERSLEEP_DEBT_THRESHOLD)
	s3.slot = 3
	sched.auto_end_day(s3)
	t.eq(bool(s3.get_flag("overslept")), true, "连续睡眠不足标记起不来")

	var s4 := GameState.new_run(209, ContentLoader.characters)
	s4.day = 60
	s4.slot = 3
	var last := sched.advance_slot(s4)
	t.eq(last.get("game_over", false), true, "第 60 天结束触发结局")
	t.eq(s4.day, 60, "结局不会创建第 61 天")

static func _experience_and_passives(t) -> void:
	var actions := ActionSystem.new()
	var s := GameState.new_run(204, ContentLoader.characters)
	var before := int(s.player.get("exp", 0))
	actions.commit(s, "rest")
	t.gte(int(s.player.get("exp", 0)), before + 1, "行动获得经验点")

	var ab := AbilitySystem.new()
	var s2 := GameState.new_run(205, ContentLoader.characters)
	s2.player["exp"] = 30
	var result := ab.unlock(s2, "passive_early_bird")
	t.eq(result.get("ok", false), true, "经验足够时解锁被动")
	t.eq(s2.has_passive("passive_early_bird"), true, "被动已记录")
	t.eq(int(s2.player["exp"]), 10, "解锁扣除经验点")
	t.eq(ab.unlock(s2, "passive_early_bird").get("ok", false), false, "重复解锁被拒绝")
	t.eq(ab.unlock(s2, "passive_tough_body").get("ok", false), false, "经验不足时无法解锁")

static func _parent_rewards(t) -> void:
	var ps := ParentSystem.new()
	var s := GameState.new_run(206, ContentLoader.characters)
	s.day = 5
	s.player["money"] = 10
	var res := ps.on_day_end(s)
	t.gte(int(s.player.get("money", 0)), GameConfig.PARENT_ALLOWANCE, "低现金且健康时发放生活费")

	# 连续按时 5 天奖励
	var s2 := GameState.new_run(207, ContentLoader.characters)
	s2.set_flag("on_time_streak", GameConfig.PARENT_ON_TIME_STREAK_REQUIRED - 1)
	s2.set_flag("early_sleep_ok", true)
	var money_before := int(s2.player.get("money", 0))
	ps.on_day_end(s2)
	t.gte(int(s2.player.get("money", 0)), money_before + GameConfig.PARENT_ON_TIME_BONUS, "连续按时获得父母奖励")

	var s3 := GameState.new_run(210, ContentLoader.characters)
	s3.set_flag("on_time_streak", GameConfig.PARENT_ON_TIME_STREAK_REQUIRED - 1)
	s3.set_flag("worked_today", true)
	s3.set_flag("worked_on_time_today", false)
	var before := int(s3.player.get("money", 0))
	ps.on_day_end(s3)
	t.eq(int(s3.player.get("money", 0)), before, "强行早班不计入按时奖励")

static func _exam_phase_gate(t) -> void:
	var actions := ActionSystem.new()
	var s := GameState.new_run(208, ContentLoader.characters)
	s.set_flag("library_math_count", 5)
	s.location_id = "library"
	s.slot = 2
	t.eq(actions.availability_report(s, "take_exam").get("ok", false), false, "非阶段末不能参加考试")
	s.day = 14
	t.eq(actions.availability_report(s, "take_exam").get("ok", false), true, "阶段末可以参加考试")

static func _idle_and_plans(t) -> void:
	var sched := ScheduleSystem.new()
	var normal := GameState.new_run(211, ContentLoader.characters)
	var idle_result := sched.idle(normal)
	t.eq(idle_result.get("forced_sleep", true), false, "状态正常时发呆不会强制睡眠")
	t.eq(normal.slot, 1, "发呆推进一个时段")
	t.ok(float(normal.player.get("fatigue", 0)) > 0.0, "发呆产生状态变化")

	var exhausted := GameState.new_run(212, ContentLoader.characters)
	exhausted.slot = 2
	exhausted.player["fatigue"] = 85
	var sleep_result := sched.idle(exhausted)
	t.eq(sleep_result.get("forced_sleep", false), true, "疲劳达到阈值自动睡眠")
	t.eq(exhausted.day, 2, "过劳睡眠进入下一天")

	var old_state: GameState = GameFlow.state
	GameFlow.state = GameState.new_run(213, ContentLoader.characters)
	t.eq(GameFlow.plan_cards().size(), 3, "短期计划提供三条路线")
	t.eq(GameFlow.choose_plan("study"), true, "可选择数学计划")
	t.eq(GameFlow.claim_plan_reward("study"), false, "未达标不能领取计划奖励")
	GameFlow.state.player["math"] = 45
	t.eq(GameFlow.claim_plan_reward("study"), true, "达标后可领取计划奖励")
	t.eq(int(GameFlow.state.player["exp"]), 4, "首段计划奖励经验")
	t.eq(GameFlow.claim_plan_reward("study"), false, "同一阶段不能重复领取")
	t.eq(int(GameFlow.state.meta.get("plan_levels", {}).get("study", 0)), 1, "计划阶段保存到状态")
	t.eq(GameFlow.choose_plan("study"), true, "可以重新追踪下一阶段")
	t.eq(GameFlow.claim_plan_reward("study"), false, "下一阶段需要新目标")
	GameFlow.state.player["math"] = 60
	t.eq(GameFlow.claim_plan_reward("study", "invalid"), false, "非法奖励选项被拒绝")
	t.eq(GameFlow.claim_plan_reward("study", "share"), true, "可选择分享计划成果")
	t.eq(int(GameFlow.state.player["exp"]), 4, "分享奖励不会重复增加经验")
	t.gte(int(GameFlow.state.player["trust"]), 52, "分享成果增加信任")
	GameFlow.state = old_state

static func _plan_ui_smoke(t) -> void:
	var old_state: GameState = GameFlow.state
	GameFlow.state = GameState.new_run(214, ContentLoader.characters)
	GameFlow.state.meta["intro_seen"] = true
	var scene: PackedScene = load("res://scenes/game/game.tscn")
	var screen := scene.instantiate()
	t.add_child(screen)
	t.eq(screen.plan_box.get_child_count(), 3, "底栏显示三条计划卡片")
	t.eq(screen.bottom_panel.size.y > 120.0, true, "计划底栏有足够高度")
	screen.queue_free()
	GameFlow.state = old_state
