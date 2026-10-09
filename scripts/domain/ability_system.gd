class_name AbilitySystem
extends RefCounted
## 经验点与被动能力。经验在行动中累积，阶段结算时用于解锁被动。

func available(state: GameState) -> Array:
	var result: Array = []
	var exp := int(state.player.get("exp", 0))
	for passive in ContentLoader.all_passives():
		var id := str(passive.get("id", ""))
		if state.has_passive(id):
			continue
		if int(passive.get("cost", 0)) <= exp:
			result.append(passive)
	return result

func owned(state: GameState) -> Array:
	var result: Array = []
	for passive in ContentLoader.all_passives():
		if state.has_passive(str(passive.get("id", ""))):
			result.append(passive)
	return result

func validate(state: GameState, passive_id: String) -> Dictionary:
	var passive := ContentLoader.get_passive(passive_id)
	if passive.is_empty():
		return {"ok": false, "reason": "未知能力"}
	if state.has_passive(passive_id):
		return {"ok": false, "reason": "已经解锁过了"}
	if int(state.player.get("exp", 0)) < int(passive.get("cost", 0)):
		return {"ok": false, "reason": "经验点不足"}
	return {"ok": true, "passive": passive}

func unlock(state: GameState, passive_id: String) -> Dictionary:
	var check := validate(state, passive_id)
	if not check.get("ok", false):
		return {"ok": false, "message": str(check.get("reason", "无法解锁")), "changes": []}
	var passive: Dictionary = check["passive"]
	var cost := int(passive.get("cost", 0))
	var changes: Array = [state.add_player("exp", -cost, "解锁被动")]
	state.passives.append(passive_id)
	changes.append_array(EffectResolver.apply_dict(state, passive.get("effects", {}), "被动效果"))
	return {
		"ok": true,
		"passive_id": passive_id,
		"changes": changes,
		"message": "解锁被动：%s" % passive.get("name", passive_id),
	}
