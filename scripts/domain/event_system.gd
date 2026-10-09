class_name EventSystem
extends RefCounted
## 事件筛选、权重抽取、选项结果。全部数据驱动。

const EVENT_FIRED_PREFIX := "event_fired_"

# ---------------------------------------------------------------------------
# 筛选与抽取
# ---------------------------------------------------------------------------

func is_eligible(state: GameState, event: Dictionary, location_id: String = "") -> bool:
	var days: Variant = event.get("days", null)
	if days is Array and days.size() >= 2:
		if state.day < int(days[0]) or state.day > int(days[1]):
			return false

	if event.has("phase"):
		if state.phase != int(event["phase"]):
			return false

	var time: Variant = event.get("time", null)
	if time is Dictionary:
		var now := GameConfig.slot_minutes(state.slot)
		var from := GameConfig.parse_clock(str(time.get("from", "00:00")))
		var to := GameConfig.parse_clock(str(time.get("to", "24:00")))
		if now < from or now > to:
			return false

	var raw_loc: Variant = event.get("location", "")
	var loc: String = "" if raw_loc == null else str(raw_loc)
	if loc != "":
		var check_loc := location_id if location_id != "" else state.location_id
		if loc != check_loc:
			return false

	if bool(event.get("once", false)) and bool(state.get_flag(EVENT_FIRED_PREFIX + str(event.get("id", "")))):
		return false

	if not ConditionEvaluator.evaluate(event.get("conditions", {}), state):
		return false

	return true

func eligible_events(state: GameState, location_id: String = "", pool: Variant = null, category: String = "") -> Array:
	var result: Array = []
	var source: Array = []
	if pool is Array and not pool.is_empty():
		for id in pool:
			source.append(ContentLoader.get_event(str(id)))
	else:
		source = ContentLoader.all_events()
	for event in source:
		if event.is_empty():
			continue
		if category != "" and str(event.get("category", "")) != category:
			continue
		if is_eligible(state, event, location_id):
			result.append(event)
	return result

func pick_event(state: GameState, pool: Variant = null, category: String = "") -> Dictionary:
	var candidates := eligible_events(state, state.location_id, pool, category)
	if candidates.is_empty():
		return {}
	var idx := RandomSource.weighted_pick_dict(candidates)
	if idx < 0:
		return {}
	return candidates[idx]

# ---------------------------------------------------------------------------
# 展示与结算
# ---------------------------------------------------------------------------

func present(state: GameState, event: Dictionary) -> Dictionary:
	var choices: Array = []
	for choice in event.get("choices", []):
		if choice.has("conditions") and not ConditionEvaluator.evaluate(choice["conditions"], state):
			continue
		choices.append({
			"id": choice.get("id", ""),
			"text": choice.get("text", ""),
		})
	return {
		"id": event.get("id", ""),
		"title": event.get("title", ""),
		"text": event.get("text", ""),
		"npc": event.get("npc", ""),
		"choices": choices,
	}

func resolve(state: GameState, event: Dictionary, choice_id: String) -> Dictionary:
	# 结算前重新校验，避免 stale UI 或非法选项。
	if event.is_empty():
		return {"ok": false, "changes": [], "result_text": "事件不存在"}
	if not is_eligible(state, event):
		return {"ok": false, "changes": [], "result_text": "该事件当前已不可触发"}

	var chosen: Dictionary = {}
	for choice in event.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			chosen = choice
			break
	if chosen.is_empty():
		return {"ok": false, "changes": [], "result_text": "选项不存在"}
	if chosen.has("conditions") and not ConditionEvaluator.evaluate(chosen["conditions"], state):
		return {"ok": false, "changes": [], "result_text": "该选项当前不可选"}
	var affordability := _choice_cost_blockers(state, chosen)
	if not affordability.is_empty():
		return {"ok": false, "changes": [], "result_text": "；".join(affordability)}

	var changes: Array = []
	var result_text := str(chosen.get("result_text", ""))
	changes.append_array(EffectResolver.apply_dict(state, chosen.get("effects", {}), "事件结果"))
	if chosen.has("extra"):
		changes.append_array(EffectResolver.apply_array(state, chosen["extra"], "事件结果"))

	state.set_flag(EVENT_FIRED_PREFIX + str(event.get("id", "")), true)
	var raw_npc: Variant = event.get("npc", "")
	var npc_id: String = "" if raw_npc == null else str(raw_npc)
	if npc_id != "":
		state.mark_npc_met(npc_id)

	state.log_entry({
		"type": "event",
		"id": event.get("id", ""),
		"title": event.get("title", ""),
		"choice": chosen.get("text", ""),
	})

	return {
		"ok": true,
		"changes": changes,
		"result_text": result_text,
		"event_id": event.get("id", ""),
	}

## 事件选项使用 effects 声明成本：负 money/energy 表示支付。
func _choice_cost_blockers(state: GameState, choice: Dictionary) -> Array:
	var required := {"money": 0.0, "energy": 0.0}
	var effects: Variant = choice.get("effects", {})
	if effects is Dictionary:
		for key in required:
			if effects.has(key) and float(effects[key]) < 0.0:
				required[key] += -float(effects[key])
	var extra: Variant = choice.get("extra", [])
	if extra is Array:
		for raw in extra:
			if not (raw is Dictionary):
				continue
			var parts := str(raw.get("path", "")).split(".")
			if parts.size() < 2 or parts[0] != "player" or not required.has(parts[1]):
				continue
			var op := str(raw.get("op", "add"))
			var value := float(raw.get("value", 0))
			var delta := value if op == "add" else -value if op == "sub" else 0.0
			if delta < 0.0:
				required[parts[1]] += -delta
	var labels := {"money": "现金", "energy": "体力"}
	var reasons: Array = []
	for key in required:
		if required[key] > 0.0 and float(state.player.get(key, 0)) < required[key]:
			reasons.append("%s不足（需要 %d，当前 %d）" % [labels[key], int(ceil(required[key])), int(state.player.get(key, 0))])
	return reasons

## 结算由行动直接指定的单个事件。
func resolve_by_id(state: GameState, event_id: String, choice_id: String) -> Dictionary:
	var event := ContentLoader.get_event(event_id)
	if event.is_empty():
		return {"ok": false, "changes": [], "result_text": "事件不存在"}
	return resolve(state, event, choice_id)
