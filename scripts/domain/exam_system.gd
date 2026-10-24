class_name ExamSystem
extends RefCounted
## 学习进度、考试与证书路线。

func available_exams(state: GameState) -> Array:
	var result: Array = []
	for exam in ContentLoader.all_exams():
		var id := str(exam.get("id", ""))
		if bool(state.get_flag("exam_passed_" + id)):
			continue
		if bool(state.get_flag("exam_taken_phase_%d_%s" % [state.phase, id])):
			continue
		if ConditionEvaluator.evaluate(exam.get("unlock_requires", {}), state):
			result.append(exam)
	return result

func is_exam_unlocked(state: GameState, exam_id: String) -> bool:
	var exam := ContentLoader.get_exam(exam_id)
	if exam.is_empty():
		return false
	if bool(state.get_flag("exam_passed_" + exam_id)):
		return false
	return ConditionEvaluator.evaluate(exam.get("unlock_requires", {}), state)

## 计算分数，并给出可解释的扣分/加分原因。
func score(state: GameState, exam_id: String, choice_id: String) -> Dictionary:
	var exam := ContentLoader.get_exam(exam_id)
	var weights: Dictionary = exam.get("weights", {"attribute": 0.7, "fatigue": 0.2, "choice": 0.1})
	var field := str(exam.get("attribute_field", "player.math"))
	var attr := float(state.get_field(field))
	var fatigue := float(state.player.get("fatigue", 0))

	var attr_part := attr * float(weights.get("attribute", 0.7))
	var fatigue_part := (100.0 - fatigue) * float(weights.get("fatigue", 0.2))

	var choice_delta := 0.0
	var choice_text := ""
	for choice in exam.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			choice_delta = float(choice.get("score_delta", 0))
			choice_text = str(choice.get("text", ""))
			break
	var choice_part := (50.0 + choice_delta * 5.0) * float(weights.get("choice", 0.1))

	var bonuses: Array = []
	var bonus := 0.0
	if bool(state.get_flag("has_stationery")):
		bonus += 3.0
		bonuses.append("携带文具 +3")
	if fatigue <= 20.0:
		bonus += 3.0
		bonuses.append("睡眠充足 +3")
	if float(state.player.get("hunger", 0)) <= 30.0:
		bonus += 2.0
		bonuses.append("状态良好 +2")

	var total := attr_part + fatigue_part + choice_part + bonus
	var breakdown := [
		"基础能力 %d × %.0f%% = %.1f" % [int(attr), float(weights.get("attribute", 0.7)) * 100.0, attr_part],
		"疲劳状态 %.0f 分 = %.1f" % [fatigue, fatigue_part],
		"临场选择「%s」= %.1f" % [choice_text, choice_part],
	]
	breakdown.append_array(bonuses)
	return {
		"score": int(round(clampf(total, 0.0, 100.0))),
		"breakdown": breakdown,
		"choice_id": choice_id,
	}

## 二次校验：考试是否存在、是否解锁、本阶段是否已考、选项是否合法。
func validate(state: GameState, exam_id: String, choice_id: String) -> Dictionary:
	var exam := ContentLoader.get_exam(exam_id)
	if exam.is_empty():
		return {"ok": false, "reason": "考试不存在"}
	if bool(state.get_flag("exam_passed_" + exam_id)):
		return {"ok": false, "reason": "这门考试你已经通过了"}
	if bool(state.get_flag("exam_taken_phase_%d_%s" % [state.phase, exam_id])):
		return {"ok": false, "reason": "本阶段已经考过这门考试"}
	if not ConditionEvaluator.evaluate(exam.get("unlock_requires", {}), state):
		return {"ok": false, "reason": "尚未解锁该考试"}
	var found := false
	for choice in exam.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			found = true
			break
	if not found:
		return {"ok": false, "reason": "无效的考试选项"}
	return {"ok": true, "reason": "", "exam": exam}

func commit(state: GameState, exam_id: String, choice_id: String) -> Dictionary:
	var check := validate(state, exam_id, choice_id)
	if not check.get("ok", false):
		return {"ok": false, "message": str(check.get("reason", "无法参加考试")), "changes": []}
	var exam: Dictionary = check["exam"]
	# 考试成本在这里结算（入口行动只做展示与门槛判断），取消考试不产生任何扣除。
	var blockers := ActionSystem.cost_blockers(state, exam.get("cost", {}))
	if not blockers.is_empty():
		return {"ok": false, "message": "；".join(blockers), "changes": []}

	var scored := score(state, exam_id, choice_id)
	var value: int = scored["score"]
	var pass_score := int(exam.get("pass_score", 60))
	var passed := value >= pass_score

	var changes: Array = []
	changes.append_array(EffectResolver.apply_cost(state, exam.get("cost", {}), "参加考试"))
	# 考试选项自带的小额效果：如「仔细检查」多耗体力、「快速交卷」省点体力。
	for choice in exam.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			changes.append_array(EffectResolver.apply_dict(state, choice.get("effects", {}), "考试选择"))
			break
	state.set_flag("exam_taken_phase_%d_%s" % [state.phase, exam_id], true)

	if passed:
		state.set_flag("exam_passed_" + exam_id, true)
		changes.append_array(EffectResolver.apply_dict(state, exam.get("success_effects", {}), "考试通过"))
		var money_bonus := int(exam.get("success_money_bonus", 0))
		if money_bonus > 0:
			changes.append(state.add_player("money", money_bonus, "考试奖励"))
		if exam_id == "math_basic":
			# 首次通过考试，父母奖励
			changes.append(state.add_player("money", 200, "父母奖励"))
	else:
		changes.append_array(EffectResolver.apply_dict(state, exam.get("fail_effects", {}), "考试未通过"))

	state.log_entry({
		"type": "exam",
		"id": exam_id,
		"title": exam.get("name", exam_id),
		"score": value,
		"passed": passed,
	})

	return {
		"ok": true,
		"exam_id": exam_id,
		"score": value,
		"pass_score": pass_score,
		"passed": passed,
		"breakdown": scored["breakdown"],
		"changes": changes,
		"message": "%s：%d 分（及格线 %d）" % [exam.get("name", exam_id), value, pass_score],
	}
