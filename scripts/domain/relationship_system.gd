class_name RelationshipSystem
extends RefCounted
## NPC 关系值、标签与阶段事件辅助。

const LABELS := [
	{"min": 0, "label": "陌生人"},
	{"min": 20, "label": "认识"},
	{"min": 40, "label": "熟人"},
	{"min": 60, "label": "朋友"},
	{"min": 80, "label": "挚友"},
]

func label(value: int) -> String:
	var result := "陌生人"
	for entry in LABELS:
		if value >= int(entry["min"]):
			result = str(entry["label"])
	return result

func get_relationship(state: GameState, npc_id: String) -> int:
	return int(state.npcs.get(npc_id, {}).get("relationship", 0))

func get_trust(state: GameState, npc_id: String) -> int:
	return int(state.npcs.get(npc_id, {}).get("trust", 0))

func high_relationships(state: GameState, threshold: int = 70) -> Array:
	var result: Array = []
	for npc_id in state.npcs:
		if get_relationship(state, npc_id) >= threshold:
			result.append(npc_id)
	return result

## 当前阶段该 NPC 的剧情事件（若尚未触发）。
func stage_event_for(state: GameState, npc_id: String) -> String:
	var cfg := ContentLoader.get_character(npc_id)
	for stage in cfg.get("stages", []):
		if int(stage.get("phase", 0)) == state.phase:
			return str(stage.get("event_id", ""))
	return ""

func summary(state: GameState) -> Array:
	var result: Array = []
	for npc_id in state.npcs:
		var cfg := ContentLoader.get_character(npc_id)
		var value := get_relationship(state, npc_id)
		result.append({
			"id": npc_id,
			"name": cfg.get("name", npc_id),
			"relationship": value,
			"label": label(value),
			"met": bool(state.npcs[npc_id].get("met", false)),
		})
	return result
