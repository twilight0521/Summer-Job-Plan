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
