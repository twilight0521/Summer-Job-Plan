class_name EndingSystem
extends RefCounted
## 结局由条件配置驱动，按 priority 从高到低取第一个满足项。

const FALLBACK_ENDING := "steady_summer"

## 返回所有满足条件的结局 id，按优先级降序；同优先级按 id 排序保证可复现。
func evaluate(state: GameState) -> Array:
	var matched: Array = []
	for ending in ContentLoader.get_endings():
		if ConditionEvaluator.evaluate(ending.get("conditions", {}), state):
			matched.append(ending)
	matched.sort_custom(func(a, b):
		var pa := int(a.get("priority", 0))
		var pb := int(b.get("priority", 0))
		if pa == pb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return pa > pb
	)
	var ids: Array = []
	for e in matched:
		ids.append(str(e.get("id", "")))
	return ids

func best_ending(state: GameState) -> Dictionary:
	var all := ContentLoader.get_endings()
	if all.is_empty():
		return {}
	var ids := evaluate(state)
	if not ids.is_empty():
		for ending in all:
			if str(ending.get("id", "")) == str(ids[0]):
				return ending
	for ending in all:
		if str(ending.get("id", "")) == FALLBACK_ENDING:
			return ending
	return all[0]

func summary(state: GameState, ending: Dictionary, relationship_system: RelationshipSystem) -> Dictionary:
	var highlights: Array = []
	for key in ending.get("highlights", []):
		highlights.append(str(key))
	var stats := {
		"day": state.day,
		"money": int(state.player.get("money", 0)),
		"health": int(state.player.get("health", 0)),
		"mood": int(state.player.get("mood", 0)),
		"trust": int(state.player.get("trust", 0)),
		"study": int(state.player.get("study", 0)),
		"math": int(state.player.get("math", 0)),
		"skill": int(state.player.get("skill", 0)),
		"responsibility": int(state.player.get("responsibility", 0)),
		"work_days": int(state.get_flag("work_days")),
	}
	return {
		"ending_id": ending.get("id", ""),
		"name": ending.get("name", ""),
		"tagline": ending.get("tagline", ""),
		"description": ending.get("description", ""),
		"highlights": highlights,
		"stats": stats,
		"relationships": relationship_system.summary(state),
		"history": state.history.slice(maxi(0, state.history.size() - 12)),
	}

## 关键选择回放：从历史中抽取有结果差异的选择。
func key_choices(state: GameState, limit: int = 8) -> Array:
	var picks: Array = []
	for entry in state.history:
		if str(entry.get("type", "")) == "event":
			picks.append(entry)
	picks.reverse()
	return picks.slice(0, limit)
