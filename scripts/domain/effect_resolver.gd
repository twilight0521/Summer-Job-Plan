class_name EffectResolver
extends RefCounted
## 把数据表里声明的 effects 应用到 GameState，并收集 ChangeSet。
## 支持两种写法：
##   Dictionary: {"money": -10, "mood": 3}          # 作用于玩家字段
##   Array:      [{"path":"flags.x","op":"set","value":true}, ...]
## op: add / sub / set / mul

## 成本字段的语义（与 effects 的“增量”不同）：
##   money / energy   正数表示扣除
##   hunger / fatigue 正数表示增加
##   mood 及其他      按数据里的正负号直接作为增量
const COST_DEDUCT_FIELDS := ["money", "energy"]
const COST_ADD_FIELDS := ["hunger", "fatigue"]

## 返回某个成本字段实际会造成的增量。
static func cost_delta(field: String, value: Variant) -> float:
	var v := float(value)
	if COST_DEDUCT_FIELDS.has(field):
		return -abs(v)
	if COST_ADD_FIELDS.has(field):
		return abs(v)
	return v

## 应用成本，统一按上面的语义结算。
## 体力消耗会按当前饥饿放大：越饿掉得越快。
static func apply_cost(state: GameState, cost: Variant, reason: String = "消耗") -> Array:
	var changes: Array = []
	if not (cost is Dictionary):
		return changes
	var hunger := float(state.player.get("hunger", 0))
	for key in cost:
		var field := str(key)
		if GameConfig.CLAMPS.has(field):
			var delta := cost_delta(field, cost[key])
			if field == "energy" and delta < 0.0:
				delta = -GameConfig.scale_energy_cost(-delta, hunger)
			changes.append(state.add_player(field, delta, reason))
		else:
			changes.append(state.set_flag(field, cost[key]))
	return changes

## 预览用：把声明成本里的体力按饥饿放大后返回副本。
static func preview_cost(state: GameState, cost: Variant) -> Dictionary:
	if not (cost is Dictionary):
		return {}
	var out: Dictionary = (cost as Dictionary).duplicate(true)
	if out.has("energy"):
		out["energy"] = GameConfig.scale_energy_cost(float(out["energy"]), float(state.player.get("hunger", 0)))
	return out

static func apply_combined(state: GameState, effects_dict: Variant, extra_array: Variant, reason: String = "") -> Array:
	var changes: Array = []
	if effects_dict is Dictionary:
		changes.append_array(apply_dict(state, effects_dict, reason))
	if extra_array is Array:
		changes.append_array(apply_array(state, extra_array, reason))
	return changes

static func apply_dict(state: GameState, effects: Dictionary, reason: String = "") -> Array:
	var changes: Array = []
	for key in effects:
		var field := str(key)
		var value: Variant = effects[key]
		if field.contains("."):
			# 支持 {"flags.x": true} / {"npcs.mom.relationship": 2} 写法
			var op := "set" if (value is bool) else "add"
			changes.append_array(apply_array(state, [{"path": field, "op": op, "value": value}], reason))
		elif GameConfig.CLAMPS.has(field):
			changes.append(state.add_player(field, float(value), reason))
		else:
			# 非资源键：当作 flag 处理（布尔或数值）
			changes.append(state.set_flag(field, value))
	return changes

static func apply_array(state: GameState, effects: Array, reason: String = "") -> Array:
	var changes: Array = []
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var e: Dictionary = raw
		var path := str(e.get("path", ""))
		var op := str(e.get("op", "add"))
		var value: Variant = e.get("value", 0)
		if path == "":
			continue
		var parts := path.split(".")
		if parts[0] == "player" and parts.size() >= 2:
			var field := parts[1]
			match op:
				"set":
					changes.append(state.set_player(field, value, reason))
				"sub":
					changes.append(state.add_player(field, -float(value), reason))
				"mul":
					changes.append(state.set_player(field, float(state.player.get(field, 0)) * float(value), reason))
				_:
					changes.append(state.add_player(field, float(value), reason))
		elif parts[0] == "flags" and parts.size() >= 2:
			var flag := parts[1]
			match op:
				"add":
					changes.append(state.add_flag(flag, float(value)))
				"sub":
					changes.append(state.add_flag(flag, -float(value)))
				_:
					changes.append(state.set_flag(flag, value))
		elif parts[0] == "npcs" and parts.size() >= 3:
			var npc_id := parts[1]
			var field := parts[2]
			if field == "relationship":
				changes.append(state.add_npc_relationship(npc_id, float(value), reason))
			elif field == "trust":
				changes.append(state.add_npc_trust(npc_id, float(value), reason))
	return changes
