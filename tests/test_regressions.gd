class_name TestRegressions
extends RefCounted
## 针对代码 review 修复项的回归测试，避免同类问题再次出现。

static func run(t) -> void:
	_sleep_debt_no_penalty_recovery(t)
	_time_window_half_open(t)
	_npc_event_location_bound(t)
	_condition_field_whitelist(t)
	_effect_key_whitelist(t)
	_apply_job_uses_declared_flag(t)
	_lottery_scold_fires(t)
	_exam_entry_no_precharge(t)
	_exam_choice_effects_applied(t)
	_night_events_reachable(t)
	_rng_derived_after_load(t)
	_shop_nonconsumable_once(t)
	_third_act_window(t)
	_job_marks_slot_used(t)
	_global_pool_excludes_job_events(t)
	_lottery_multiple_tickets_scold(t)
	_lottery_expected_return(t)
	_pending_event_survives_load(t)
	_hidden_partner_ending(t)

## 睡眠债很高时，睡觉不能倒扣体力或增加疲劳（否则会进入死亡螺旋）。
static func _sleep_debt_no_penalty_recovery(t) -> void:
	var sched := ScheduleSystem.new()
	var s := GameState.new_run(301, ContentLoader.characters)
	s.set_flag("sleep_debt", 10)
	s.slot = 3
	s.player["energy"] = 20.0
	s.player["fatigue"] = 60.0
	var energy_before := float(s.player["energy"])
	var fatigue_before := float(s.player["fatigue"])
	sched.sleep_and_end_day(s)
	t.ok(float(s.player["energy"]) > 0.0,
		"高睡眠债睡觉后体力不为 0（%s → %s）" % [energy_before, s.player["energy"]])
	t.ok(float(s.player["fatigue"]) < fatigue_before,
		"高睡眠债睡觉后疲劳下降（%s → %s）" % [fatigue_before, s.player["fatigue"]])

## 营业时间区间取左闭右开：时段起点等于打烊时间时不应算作开放。
static func _time_window_half_open(t) -> void:
	var sys := ActionSystem.new()
	var s := GameState.new_run(302, ContentLoader.characters)
	s.location_id = "breakfast_shop"
	s.slot = 0
	t.eq(sys.is_available(s, "breakfast_shift"), true, "凌晨可以上早餐班")
	s.slot = 1
	t.eq(sys.is_available(s, "breakfast_shift"), false, "07:00 不再算早餐班营业时间")

## NPC 剧情事件绑定 NPC 常驻地点，不会在无关地点随机弹出。
static func _npc_event_location_bound(t) -> void:
	var events := EventSystem.new()
	var s := GameState.new_run(303, ContentLoader.characters)
	var event := ContentLoader.get_event("npc_mom_01")
	s.location_id = "library"
	t.eq(events.is_eligible(s, event), false, "妈妈的事件不会在图书馆触发")
	s.location_id = "home"
	t.eq(events.is_eligible(s, event), true, "妈妈的事件在家里可以触发")

## 条件里的字段名必须在加载期校验，拼错不能静默取 0。
static func _condition_field_whitelist(t) -> void:
	t.ok(ConditionEvaluator.validate({"field": "player.nope", "op": "gte", "value": 1}).size() > 0,
		"未知玩家字段被拒绝")
	t.ok(ConditionEvaluator.validate({"field": "npcs.mom.realtionship", "op": "gte", "value": 1}).size() > 0,
		"NPC 字段拼错被拒绝")
	t.ok(ConditionEvaluator.validate({"field": "computed.nothing", "op": "gte", "value": 1}).size() > 0,
		"未知计算字段被拒绝")
	var valid := {"all": [
		{"field": "player.money", "op": "gte", "value": 1},
		{"field": "npcs.mom.relationship", "op": "gte", "value": 1},
	]}
	t.eq(ConditionEvaluator.validate(valid).size(), 0, "合法条件通过校验")

## effects 里拼错的字段会静默变成 flag，必须在加载期报错。
static func _effect_key_whitelist(t) -> void:
	var before := ContentLoader.load_errors.size()
	ContentLoader._validate_effect_entry("测试", {"effects": {"mony": 10}})
	t.ok(ContentLoader.load_errors.size() > before, "effect 里拼错的字段被拒绝")
	ContentLoader.load_errors.resize(before)
	ContentLoader._validate_effect_entry("测试", {
		"effects": {"money": 10, "flags.ok": true, "npcs.mom.relationship": 2},
	})
	t.eq(ContentLoader.load_errors.size(), before, "合法 effect 不报错")

## 求职行动写入数据声明的 hired_flag，而不是固定写会计岗的 flag。
static func _apply_job_uses_declared_flag(t) -> void:
	var sys := ActionSystem.new()
	var s := GameState.new_run(304, ContentLoader.characters)
	s.location_id = "bank_office"
	s.slot = 2
	s.set_flag("accounting_exam_passed", true)
	s.player["responsibility"] = 50
	var result := sys.commit(s, "apply_accounting")
	t.eq(result.get("ok", false), true, "满足条件时可以申请会计助理")
	t.eq(bool(s.get_flag("accounting_hired")), true, "录用写入数据声明的 accounting_hired")

## 当天购买三张彩票会在日结时触发父母训话。
static func _lottery_scold_fires(t) -> void:
	var parents := ParentSystem.new()
	var s := GameState.new_run(305, ContentLoader.characters)
	s.day = 10
	s.set_flag("lottery_tickets_today", 3)
	var mom_before := int(s.npcs["mom"]["relationship"])
	var mood_before := float(s.player["mood"])
	parents.on_day_end(s)
	t.eq(int(s.npcs["mom"]["relationship"]), mom_before - 4, "连买彩票会被妈妈训话（关系 -4）")
	t.eq(float(s.player["mood"]), mood_before - 3.0, "连买彩票被训话扣心情")
	t.eq(int(s.get_flag("lottery_tickets_today")), 0, "日结后彩票张数清零")

## 考试入口不预扣体力：取消考试不该白花体力或占住时段。
static func _exam_entry_no_precharge(t) -> void:
	var sys := ActionSystem.new()
	var s := GameState.new_run(306, ContentLoader.characters)
	s.day = 14
	s.slot = 2
	s.set_flag("library_math_count", 5)
	var energy_before := float(s.player["energy"])
	var result := sys.commit(s, "take_exam")
	t.eq(result.get("ok", false), true, "阶段末可以打开考试入口")
	t.eq(bool(result.get("consume_slot", true)), false, "考试入口不占用时段")
	t.eq(float(s.player["energy"]), energy_before, "考试入口不预扣体力")
	t.eq(s.slot_used, false, "考试入口不标记本时段已行动")

## 考试选项自带的 effects 必须真正结算（之前是死数据）。
static func _exam_choice_effects_applied(t) -> void:
	var exams := ExamSystem.new()
	var s := GameState.new_run(307, ContentLoader.characters)
	s.set_flag("library_math_count", 5)
	var energy_before := float(s.player["energy"])
	var result := exams.commit(s, "math_basic", "careful")
	t.eq(result.get("ok", false), true, "考试可以正常结算")
	# 考试成本 15 + 「仔细检查」选项 5
	t.eq(float(s.player["energy"]), energy_before - 20.0, "考试成本与选项消耗都被结算")

## 深夜事件（22:00–24:00）必须能在晚上时段触发，否则隐藏夜班线不可达。
static func _night_events_reachable(t) -> void:
	var events := EventSystem.new()
	var s := GameState.new_run(308, ContentLoader.characters)
	s.day = 20
	s.slot = 3
	t.eq(events.is_eligible(s, ContentLoader.get_event("normal_20")), true, "深夜事件在晚上时段可触发")
	s.slot = 2
	t.eq(events.is_eligible(s, ContentLoader.get_event("normal_20")), false, "深夜事件不会在下午时段触发")
	s.slot = 3
	s.day = 25
	s.set_flag("night_cat_contact", true)
	t.eq(events.is_eligible(s, ContentLoader.get_event("hidden_01")), true, "夜班猫的代练单在晚上可触发")

## 读档不能把随机流重置回开局种子，否则同一存档可以反复刷随机结果。
static func _rng_derived_after_load(t) -> void:
	var s := GameState.new_run(309, ContentLoader.characters)
	s.day = 7
	s.slot = 2
	t.eq(SaveRepository.save_auto(s), true, "写入测试自动档")
	var loaded := SaveRepository.load_slot(SaveRepository.AUTO_SLOT)
	t.eq(loaded.get("ok", false), true, "测试自动档可读取")
	t.eq(RandomSource.get_seed(), 309 + 7 * 100003 + 2 * 1009, "读档后随机流用派生种子而不是开局种子")
	SaveRepository.delete(SaveRepository.AUTO_SLOT)

## 非消耗品不能重复购买（否则可以无限买衣服刷心情）。
static func _shop_nonconsumable_once(t) -> void:
	GameFlow.start_new_game(310)
	GameFlow.state.player["money"] = 500
	t.eq(GameFlow.buy_item("clothes"), true, "第一次可以购买新衣服")
	GameFlow.state.player["mood"] = 0.0
	t.eq(GameFlow.buy_item("clothes"), false, "非消耗品不能重复购买")
	t.eq(float(GameFlow.state.player["mood"]), 0.0, "重复购买不会重复给心情")
	t.eq(GameFlow.buy_item("energy_drink"), true, "消耗品可以重复购买")

static func _third_act_window(t) -> void:
	var events := EventSystem.new()
	var s := GameState.new_run(311, ContentLoader.characters)
	s.location_id = "home"
	var third_act_ids := ["npc_mom_03", "npc_zhou_03", "npc_lin_03", "npc_chen_03", "npc_akai_03", "npc_cat_02"]
	for event_id in third_act_ids:
		var event := ContentLoader.get_event(event_id)
		t.eq(event.get("days", [0, 0])[0], 46, "%s 从第 46 天开始" % event_id)
	for day in [41, 45]:
		s.day = day
		s.phase = GameConfig.phase_of_day(day)
		t.eq(events.is_eligible(s, ContentLoader.get_event("npc_mom_03")), false, "第三幕事件第 %d 天不提前触发" % day)
	s.day = 46
	s.phase = GameConfig.phase_of_day(46)
	t.eq(events.is_eligible(s, ContentLoader.get_event("npc_mom_03")), true, "第三幕妈妈事件第 46 天可触发")

static func _job_marks_slot_used(t) -> void:
	var sys := ActionSystem.new()
	var s := GameState.new_run(312, ContentLoader.characters)
	s.location_id = "tea_shop"
	s.slot = 2
	var result := sys.commit(s, "tea_shop_shift")
	t.eq(result.get("ok", false), true, "满足条件时奶茶店工作可以结算")
	t.eq(s.slot_used, true, "工作行动标记本时段已行动")

static func _global_pool_excludes_job_events(t) -> void:
	var events := EventSystem.new()
	var s := GameState.new_run(313, ContentLoader.characters)
	s.location_id = "tea_shop"
	s.slot = 2
	var candidates := events.eligible_events(s)
	for event in candidates:
		t.ok(str(event.get("category", "")) != "job", "全局事件池不包含工作专属事件")

static func _lottery_multiple_tickets_scold(t) -> void:
	var sys := ActionSystem.new()
	var s := GameState.new_run(314, ContentLoader.characters)
	s.location_id = "convenience_store"
	s.slot = 1
	for ticket in range(3):
		s.slot_used = false
		var result := sys.commit(s, "lottery")
		t.eq(result.get("ok", false), true, "当天第 %d 张彩票可以购买" % (ticket + 1))
	t.eq(int(s.get_flag("lottery_tickets_today")), 3, "三张彩票均计入当日次数")
	var parents := ParentSystem.new()
	var mom_before := int(s.npcs["mom"]["relationship"])
	parents.on_day_end(s)
	t.eq(int(s.npcs["mom"]["relationship"]), mom_before - 4, "当日购买三张彩票触发父母训话")

static func _hidden_partner_ending(t) -> void:
	var endings := EndingSystem.new()
	var s := GameState.new_run(315, ContentLoader.characters)
	s.set_flag("business_partner", true)
	s.set_flag("night_cat_met", true)
	t.eq(str(endings.best_ending(s).get("id", "")), "night_shift_partner", "夜班合伙线有独立结局")

static func _lottery_expected_return(t) -> void:
	var gross_ev := 0.01 * 500.0 + 0.04 * 50.0 + 0.15 * 10.0
	t.ok(gross_ev < 10.0, "彩票理论奖金期望低于 ¥10 成本")

static func _pending_event_survives_load(t) -> void:
	GameFlow.start_new_game(316)
	GameFlow.state.location_id = "commercial_street"
	GameFlow.state.slot = 2
	GameFlow.state.day = 5
	GameFlow.state.phase = GameConfig.phase_of_day(5)
	GameFlow.state.set_flag("event_fired_street_01", true)
	GameFlow.state.set_flag("event_fired_street_02", true)
	GameFlow.state.set_flag("event_fired_street_03", true)
	GameFlow.state.set_flag("event_fired_street_04", true)
	GameFlow.state.set_flag("event_fired_street_05", true)
	GameFlow.state.set_flag("event_fired_street_06", true)
	GameFlow.state.set_flag("event_fired_street_07", true)
	GameFlow.state.set_flag("event_fired_street_08", true)
	GameFlow.state.set_flag("event_fired_street_09", true)
	GameFlow.state.set_flag("event_fired_street_10", true)
	GameFlow.state.set_flag("event_fired_street_11", true)
	GameFlow.state.set_flag("event_fired_street_12", true)
	GameFlow.state.set_flag("event_fired_normal_18", true)
	GameFlow.state.set_flag("event_fired_normal_19", true)
	GameFlow.state.set_flag("event_fired_normal_20", true)
	GameFlow.state.set_flag("event_fired_npc_akai_04", true)
	GameFlow.state.set_flag("event_fired_npc_lin_03", true)
	GameFlow.state.set_flag("event_fired_npc_chen_03", true)
	GameFlow.state.set_flag("event_fired_npc_mom_03", true)
	GameFlow.state.set_flag("event_fired_npc_zhou_03", true)
	GameFlow.state.set_flag("event_fired_npc_akai_03", true)
	GameFlow.state.set_flag("event_fired_npc_cat_03", true)
	GameFlow.state.set_flag("event_fired_npc_cat_02", true)
	GameFlow.state.set_flag("event_fired_npc_cat_01", true)
	var event := ContentLoader.get_event("normal_11")
	GameFlow._pending_event = event
	GameFlow._pending_slot_advance = true
	GameFlow.state.meta["pending_event"] = event.duplicate(true)
	GameFlow.state.meta["pending_slot_advance"] = true
	t.eq(SaveRepository.save_auto(GameFlow.state), true, "pending 事件自动档写入成功")
	GameFlow._pending_event = {}
	var event_signal_count := [0]
	var capture := func(_view): event_signal_count[0] += 1
	GameFlow.event_requested.connect(capture)
	t.eq(GameFlow.load_game(SaveRepository.AUTO_SLOT), true, "可以读取含 pending 事件的自动档")
	t.eq(event_signal_count[0], 0, "读档时不在标题场景提前发送弹窗信号")
	t.eq(str(GameFlow._pending_event.get("id", "")), "normal_11", "读取后恢复待选择事件")
	t.eq(GameFlow.resume_pending_event(), true, "游戏场景连接监听后可以恢复事件弹窗")
	t.eq(event_signal_count[0], 1, "恢复接口向游戏场景发送事件弹窗")
	GameFlow.event_requested.disconnect(capture)
