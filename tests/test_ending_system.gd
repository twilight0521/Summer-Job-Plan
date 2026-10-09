class_name TestEndingSystem
extends RefCounted

static func run(t) -> void:
	var endings := EndingSystem.new()

	# 会计路线
	var state := GameState.new_run(7, ContentLoader.characters)
	state.set_flag("accounting_exam_passed", true)
	state.set_flag("accounting_hired", true)
	state.set_flag("accounting_shifts_done", 3)
	var best := endings.best_ending(state)
	t.eq(str(best.get("id", "")), "little_accountant", "满足会计条件时优先小小会计师")

	# 街坊口碑
	var s2 := GameState.new_run(8, ContentLoader.characters)
	s2.player["trust"] = 85
	s2.set_flag("good_deeds", 3)
	t.eq(str(endings.best_ending(s2).get("id", "")), "neighborhood_fame", "高信任+助人触发街坊口碑")

	# 第一桶金
	var s3 := GameState.new_run(9, ContentLoader.characters)
	s3.player["money"] = 3000
	t.eq(str(endings.best_ending(s3).get("id", "")), "first_bucket", "现金达标触发第一桶金")

	# 过载兜底
	var s4 := GameState.new_run(10, ContentLoader.characters)
	s4.player["health"] = 20
	t.eq(str(endings.best_ending(s4).get("id", "")), "summer_overload", "低健康触发暑假过载")

	# 无特殊条件时回退到稳稳的暑假
	var s5 := GameState.new_run(11, ContentLoader.characters)
	var fallback := endings.best_ending(s5)
	t.ok(not fallback.is_empty(), "无匹配时仍有兜底结局")

	# 条件解释器：all / any / not
	t.eq(ConditionEvaluator.evaluate({"all": [{"field": "day", "op": "gte", "value": 1}]}, s5), true, "all 条件")
	t.eq(ConditionEvaluator.evaluate({"any": [{"field": "day", "op": "gte", "value": 99}, {"field": "day", "op": "eq", "value": 1}]}, s5), true, "any 条件")
	t.eq(ConditionEvaluator.evaluate({"not": {"field": "day", "op": "eq", "value": 1}}, s5), false, "not 条件")
