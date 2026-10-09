class_name ActionSystem
extends RefCounted
## 行动定义与结算。工作类行动委托给 JobSystem。

var job_system: JobSystem

func _init() -> void:
	job_system = JobSystem.new()

# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func actions_at(state: GameState, location_id: String) -> Array:
	var loc: Dictionary = ContentLoader.get_location(location_id)
	var result: Array = []
	for action_id in loc.get("actions", []):
		if ContentLoader.get_action(action_id).is_empty():
			continue
		var action: Dictionary = ContentLoader.get_action(action_id)
		if action.get("handler", "action") == "buy_item" or action_id == "buy_item":
			result.append(action_id)
			continue
		if is_available(state, action_id):
			result.append(action_id)
	return result

func is_available(state: GameState, action_id: String) -> bool:
	return availability_report(state, action_id).get("ok", false)

## 返回 {ok, reasons:[...]}，reasons 用中文解释为什么不能执行。
func availability_report(state: GameState, action_id: String) -> Dictionary:
	var reasons: Array = []
	var action: Dictionary = ContentLoader.get_action(action_id)
	if action.is_empty():
		return {"ok": false, "reasons": ["未知行动"]}

	# 地点
	var raw_loc: Variant = action.get("location_id", "")
	var loc_id: String = "" if raw_loc == null else str(raw_loc)
	if loc_id != "" and loc_id != state.location_id:
		reasons.append("需要先前往「%s」" % ContentLoader.get_location(loc_id).get("name", loc_id))

	# 时段
	if not _time_ok(state, action):
		reasons.append("当前时段不开放（%s）" % _time_range_text(action))

	# 每 slot 一次主行动
	var duration := int(action.get("duration_slots", 1))
	if duration > 0 and state.slot_used:
		reasons.append("这个时段已经行动过了")

	# 资源是否负担得起（现金 / 体力）
	reasons.append_array(cost_blockers(state, action.get("cost", {})))

	# 前置条件
	var req: Variant = action.get("requires", {})
	if not ConditionEvaluator.evaluate(req, state):
		var hints: Dictionary = action.get("fail_hints", {})
		var added := false
		for key in hints:
			if not _single_condition_ok(req, state, key):
				reasons.append(str(hints[key]))
				added = true
		if not added:
			reasons.append("还不满足条件")

	# 工作专属：重体力规则
	if job_system and ContentLoader.jobs.has(action_id):
		reasons.append_array(job_system.extra_blockers(state, action_id))

	return {"ok": reasons.is_empty(), "reasons": reasons}

## 检查行动成本是否付得起（现金 / 体力为硬门槛）。
func cost_blockers(state: GameState, cost: Variant) -> Array:
	var reasons: Array = []
	if not (cost is Dictionary):
		return reasons
	var gates := {"money": "现金", "energy": "体力"}
	for key in gates:
		if cost.has(key):
			var need := absf(float(cost[key]))
			if need > 0.0 and float(state.player.get(key, 0)) < need:
				reasons.append("%s不足（需要 %d，当前 %d）" % [
					gates[key], int(ceil(need)), int(state.player.get(key, 0))
				])
	return reasons

func preview(state: GameState, action_id: String) -> Dictionary:
	var action: Dictionary = ContentLoader.get_action(action_id)
	var report := availability_report(state, action_id)
	var cost: Dictionary = action.get("cost", {})
	var effects: Dictionary = action.get("effects", {})
	var warnings: Array = []
	if job_system and ContentLoader.jobs.has(action_id):
		warnings.append_array(job_system.preview_warnings(state, action_id))
	return {
		"action_id": action_id,
		"name": action.get("name", action_id),
		"description": action.get("description", ""),
		"cost": cost,
		"effects": effects,
		"ok": report.ok,
		"reasons": report.reasons,
		"warnings": warnings,
	}

# ---------------------------------------------------------------------------
# 结算
# ---------------------------------------------------------------------------

func commit(state: GameState, action_id: String) -> Dictionary:
	var action: Dictionary = ContentLoader.get_action(action_id)
	if action.is_empty():
		return _fail("未知行动")
	var report := availability_report(state, action_id)
	if not report.ok:
		return _fail("；".join(report.reasons))

	# 工作
	if ContentLoader.jobs.has(action_id):
		return job_system.commit(state, action_id)

	var handler: String = str(action.get("handler", "action"))
	var result := _empty_result(action_id)
	result.consume_slot = int(action.get("duration_slots", 1)) > 0

	# 不消耗资源的界面类行动
	if handler == "shop":
		result.consume_slot = false
		result.special = "shop"
		return result

	# 先结算成本，再结算收益
	result.changes.append_array(EffectResolver.apply_cost(state, action.get("cost", {}), "消耗"))
	_apply_effects(state, action, result)
	_apply_passive_bonus(state, action, result)

	match handler:
		"action":
			pass
		"math_study":
			state.add_flag("library_math_count", 1)
			result.messages.append("累计学数学 %d 次。" % int(state.get_flag("library_math_count")))
		"exercise":
			var streak := int(state.get_flag("exercise_streak")) + 1
			state.set_flag("exercise_streak", streak)
			state.set_flag("exercise_today", true)
			if streak > 0 and streak % 3 == 0:
				result.changes.append(state.add_player("muscle", 2, "连续锻炼奖励"))
				result.changes.append(state.add_player("mood", 3, "连续锻炼奖励"))
				result.messages.append("连续锻炼 %d 天，额外提升！" % streak)
		"lottery":
			_resolve_lottery(state, result)
		"scrap":
			_resolve_scrap(state, result)
		"social":
			result.messages.append("你和周围的人聊了一会儿。")
		"stroll":
			result.event_pool = ["street_01", "street_02", "street_03", "street_04", "street_05", "street_06", "street_07", "street_08", "street_09", "street_10", "street_11", "street_12"]
			result.messages.append("你在街上逛了一圈。")
		"npc_talk":
			var npc_id := str(action.get("npc_id", ""))
			state.mark_npc_met(npc_id)
			result.event_pool = _npc_event_pool(npc_id)
		"exam":
			result.special = "exam"
		"apply_job":
			_apply_job(state, action, result)
		"sleep":
			result.end_day = true
			result.special = "sleep"
		_:
			pass

	state.slot_used = state.slot_used or result.consume_slot
	# 经验：消耗时段的行动才给经验
	if result.consume_slot and not result.end_day:
		result.changes.append(state.add_player("exp", float(GameConfig.EXP_PER_ACTION), "经验"))
	return result

## 被动能力带来的额外收益。
func _apply_passive_bonus(state: GameState, action: Dictionary, result: Dictionary) -> void:
	var handler := str(action.get("handler", "action"))
	var id := str(action.get("id", ""))
	if state.has_passive("passive_scholar"):
		if handler == "math_study":
			result.changes.append(state.add_player("math", 1, "学霸模式"))
		elif id == "study_home" or id == "study_library":
			result.changes.append(state.add_player("study", 1, "学霸模式"))
	if state.has_passive("passive_social") and handler == "social":
		result.changes.append(state.add_player("mood", 3, "社交达人"))

func _apply_effects(state: GameState, action: Dictionary, result: Dictionary) -> void:
	result.changes.append_array(EffectResolver.apply_dict(state, action.get("effects", {}), "收益"))
	if action.has("extra"):
		result.changes.append_array(EffectResolver.apply_array(state, action["extra"], "收益"))

# ---------------------------------------------------------------------------
# 特殊 handler
# ---------------------------------------------------------------------------

func _resolve_lottery(state: GameState, result: Dictionary) -> void:
	var luck := int(state.player.get("luck", 50))
	var bonus := int(luck / 25)
	var roll := RandomSource.randi_range(1, 100)
	var prize := 0
	if roll <= 2 + bonus:
		prize = 500
		result.messages.append("中了大奖！")
	elif roll <= 10 + bonus * 2:
		prize = 50
		result.messages.append("小赚一笔。")
	elif roll <= 30:
		prize = 10
		result.messages.append("刚好回本。")
	else:
		result.messages.append("谢谢参与。")
	if prize > 0:
		result.changes.append(state.add_player("money", prize, "彩票中奖"))
	# 连续购买增加冲动消费
	var streak := int(state.get_flag("lottery_streak")) + 1
	state.set_flag("lottery_streak", streak)
	if streak >= 3:
		result.changes.append(state.add_player("mood", -4, "冲动消费"))
		result.messages.append("你有点上头了，心情 -4。")

func _resolve_scrap(state: GameState, result: Dictionary) -> void:
	var amount := RandomSource.randi_range(10, 60)
	result.changes.append(state.add_player("money", amount, "卖废品"))
	result.changes.append(state.add_player("fitness", 1, "体力劳动"))
	result.messages.append("你捡废品卖了 ¥%d。" % amount)
	var streak := int(state.get_flag("scrap_count")) + 1
	state.set_flag("scrap_count", streak)
	if streak >= 3 and RandomSource.chance(0.5):
		state.set_flag("has_job_lead", true)
		result.messages.append("你在废品里发现一张招工名片。")

func _apply_job(state: GameState, action: Dictionary, result: Dictionary) -> void:
	var job_id := str(action.get("job_id", "accounting_shift"))
	# 到达这里说明 action.requires 已通过校验，直接录用。
	state.set_flag("accounting_hired", true)
	result.changes.append(state.set_flag("accounting_hired", true))
	result.messages.append("面试通过，你拿到了「%s」的岗位。" % ContentLoader.get_job(job_id).get("name", job_id))

func _npc_event_pool(npc_id: String) -> Array:
	var pool: Array = []
	for event in ContentLoader.all_events():
		if str(event.get("npc", "")) == npc_id:
			pool.append(event.get("id", ""))
	return pool

# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _time_ok(state: GameState, action: Dictionary) -> bool:
	var now := GameConfig.slot_minutes(state.slot)
	var range_arr: Variant = action.get("available_minutes", null)
	if range_arr is Array and range_arr.size() >= 2:
		return now >= int(range_arr[0]) and now <= int(range_arr[1])
	return true

func _time_range_text(action: Dictionary) -> String:
	var range_arr: Variant = action.get("available_minutes", null)
	if range_arr is Array and range_arr.size() >= 2:
		return "%s–%s" % [GameConfig.minutes_to_clock(int(range_arr[0])), GameConfig.minutes_to_clock(int(range_arr[1]))]
	return "全天"

func _single_condition_ok(requires: Variant, state: GameState, key: String) -> bool:
	# 只判断与 fail_hint 对应的那一条叶子条件，避免展示无关提示。
	if not (requires is Dictionary):
		return false
	var cond: Dictionary = requires
	var leaves: Array = []
	if cond.has("all"):
		leaves = cond["all"]
	else:
		leaves = [cond]
	for sub in leaves:
		if not (sub is Dictionary):
			continue
		var sub_key := str(sub.get("field", sub.get("flag", "")))
		if sub_key == key:
			return ConditionEvaluator.evaluate(sub, state)
	return false

func _empty_result(action_id: String) -> Dictionary:
	return {
		"ok": true,
		"action_id": action_id,
		"changes": [],
		"messages": [],
		"event_id": "",
		"event_pool": [],
		"end_day": false,
		"consume_slot": false,
		"open_shop": false,
		"special": "",
	}

func _fail(message: String) -> Dictionary:
	var r := _empty_result("")
	r.ok = false
	r.messages.append(message)
	return r
