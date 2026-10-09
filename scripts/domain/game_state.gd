class_name GameState
extends RefCounted
## 唯一权威的运行时状态。所有可持久化数据都集中在这里。
## 领域系统只通过本类的方法读写，并返回 ChangeSet 供 UI 展示。

var schema_version: int = GameConfig.SCHEMA_VERSION
var content_version: String = GameConfig.CONTENT_VERSION
var run_id: String = ""
var seed: int = 0
var day: int = 1
var slot: int = 0
var phase: int = 1
var location_id: String = "home"
var slot_used: bool = false

var player: Dictionary = {}
var npcs: Dictionary = {}
var flags: Dictionary = {}
var history: Array = []
var unlocked_endings: Array = []
var passives: Array = []
var meta: Dictionary = {}

var _resolved_actions: Array = []

# ---------------------------------------------------------------------------
# 创建 / 序列化
# ---------------------------------------------------------------------------

static func new_run(run_seed: int, character_configs: Dictionary) -> GameState:
	var state := GameState.new()
	state.seed = run_seed
	state.run_id = "run_%d_%d" % [run_seed, int(Time.get_unix_time_from_system())]
	state.player = GameConfig.PLAYER_INITIAL.duplicate(true)
	state.day = 1
	state.slot = 0
	state.phase = 1
	state.location_id = "home"
	for npc_id in character_configs:
		var cfg: Dictionary = character_configs[npc_id]
		state.npcs[npc_id] = {
			"relationship": int(cfg.get("relationship", 40)),
			"trust": int(cfg.get("initial_trust", 40)),
			"met": false,
		}
	return state

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"content_version": content_version,
		"run_id": run_id,
		"seed": seed,
		"day": day,
		"slot": slot,
		"phase": phase,
		"location_id": location_id,
		"slot_used": slot_used,
		"player": player.duplicate(true),
		"npcs": npcs.duplicate(true),
		"flags": flags.duplicate(true),
		"history": history.duplicate(true),
		"unlocked_endings": unlocked_endings.duplicate(),
		"passives": passives.duplicate(),
		"meta": meta.duplicate(true),
		"_resolved_actions": _resolved_actions.duplicate(),
	}

static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.schema_version = int(data.get("schema_version", GameConfig.SCHEMA_VERSION))
	state.content_version = str(data.get("content_version", GameConfig.CONTENT_VERSION))
	state.run_id = str(data.get("run_id", ""))
	state.seed = int(data.get("seed", 0))
	state.day = int(data.get("day", 1))
	state.slot = int(data.get("slot", 0))
	state.phase = int(data.get("phase", 1))
	state.location_id = str(data.get("location_id", "home"))
	state.slot_used = bool(data.get("slot_used", false))
	var raw_player: Variant = data.get("player", null)
	state.player = raw_player if raw_player is Dictionary else GameConfig.PLAYER_INITIAL.duplicate(true)
	var raw_npcs: Variant = data.get("npcs", null)
	state.npcs = raw_npcs if raw_npcs is Dictionary else {}
	var raw_flags: Variant = data.get("flags", null)
	state.flags = raw_flags if raw_flags is Dictionary else {}
	var raw_history: Variant = data.get("history", null)
	state.history = raw_history if raw_history is Array else []
	var raw_endings: Variant = data.get("unlocked_endings", null)
	state.unlocked_endings = raw_endings if raw_endings is Array else []
	var raw_passives: Variant = data.get("passives", null)
	state.passives = raw_passives if raw_passives is Array else []
	var raw_meta: Variant = data.get("meta", null)
	state.meta = raw_meta if raw_meta is Dictionary else {}
	var raw_resolved: Variant = data.get("_resolved_actions", null)
	state._resolved_actions = raw_resolved if raw_resolved is Array else []
	return state

func duplicate_state() -> GameState:
	return GameState.from_dict(to_dict())

# ---------------------------------------------------------------------------
# 字段读取
# ---------------------------------------------------------------------------

func get_field(path: String) -> Variant:
	var parts := path.split(".")
	match parts[0]:
		"player":
			if parts.size() < 2:
				return null
			return player.get(parts[1], 0)
		"flags":
			if parts.size() < 2:
				return null
			return flags.get(parts[1], 0)
		"npcs":
			if parts.size() < 3:
				return null
			var npc: Dictionary = npcs.get(parts[1], {})
			return npc.get(parts[2], 0)
		"day":
			return day
		"slot":
			return slot
		"phase":
			return phase
		"location_id":
			return location_id
		"computed":
			return _computed(parts[1] if parts.size() > 1 else "")
	return null

func _computed(key: String) -> Variant:
	match key:
		"count_high_relationship":
			return count_high_relationship(70)
		"phase":
			return phase
	return 0

func get_flag(name: String) -> Variant:
	return flags.get(name, 0)

func has_tag(tag: String) -> bool:
	# 标签来源：玩家布尔 flags，以及职业/身份标签
	if flags.has(tag):
		return bool(flags[tag])
	return false

func count_high_relationship(threshold: int) -> int:
	var count := 0
	for npc_id in npcs:
		if int(npcs[npc_id].get("relationship", 0)) >= threshold:
			count += 1
	return count

func has_passive(passive_id: String) -> bool:
	return passives.has(passive_id)

## 动态上限：睡眠不足会降低体力上限，被动能力可提升上限。
func max_for(field: String) -> float:
	match field:
		"energy":
			var cap := float(GameConfig.ENERGY_CAP_BASE) - float(get_flag("sleep_debt")) * float(GameConfig.SLEEP_DEBT_ENERGY_PENALTY)
			if has_passive("passive_early_bird"):
				cap += 5.0
			return clampf(cap, float(GameConfig.ENERGY_CAP_MIN), 120.0)
		_:
			if GameConfig.CLAMPS.has(field):
				return float(GameConfig.CLAMPS[field][1])
			return 999999.0

func _clamp_player(field: String, value: Variant) -> Variant:
	var v: float = GameConfig.clamp_field(field, value)
	if GameConfig.CLAMPS.has(field) and field != "money":
		v = minf(v, max_for(field))
	return v

# ---------------------------------------------------------------------------
# 变更（返回 ChangeSet）
# ---------------------------------------------------------------------------

func set_player(field: String, value: Variant, reason: String = "") -> Dictionary:
	var before: Variant = player.get(field, 0)
	var after: Variant = _clamp_player(field, value)
	player[field] = after
	return {"field": field, "before": before, "delta": _delta(before, after), "after": after, "reason": reason}

func add_player(field: String, delta: float, reason: String = "") -> Dictionary:
	var before: Variant = player.get(field, 0)
	var after: Variant = _clamp_player(field, float(before) + delta)
	player[field] = after
	return {"field": field, "before": before, "delta": _delta(before, after), "after": after, "reason": reason}

func add_npc_relationship(npc_id: String, delta: float, reason: String = "") -> Dictionary:
	if not npcs.has(npc_id):
		npcs[npc_id] = {"relationship": 40, "trust": 40, "met": false}
	var npc: Dictionary = npcs[npc_id]
	var before: int = int(npc.get("relationship", 0))
	var after: int = clampi(before + int(delta), 0, 100)
	npc["relationship"] = after
	npcs[npc_id] = npc
	return {"field": "npcs.%s.relationship" % npc_id, "before": before, "delta": after - before, "after": after, "reason": reason}

func add_npc_trust(npc_id: String, delta: float, reason: String = "") -> Dictionary:
	if not npcs.has(npc_id):
		npcs[npc_id] = {"relationship": 40, "trust": 40, "met": false}
	var npc: Dictionary = npcs[npc_id]
	var before: int = int(npc.get("trust", 0))
	var after: int = clampi(before + int(delta), 0, 100)
	npc["trust"] = after
	npcs[npc_id] = npc
	return {"field": "npcs.%s.trust" % npc_id, "before": before, "delta": after - before, "after": after, "reason": reason}

func set_flag(name: String, value: Variant) -> Dictionary:
	var before: Variant = flags.get(name, 0)
	flags[name] = value
	var delta: Variant = null
	if (before is int or before is float) and (value is int or value is float):
		delta = float(value) - float(before)
	return {"field": "flags." + name, "before": before, "delta": delta, "after": value, "reason": "flag"}

func add_flag(name: String, delta: float) -> Dictionary:
	var before: float = float(flags.get(name, 0))
	var after := before + delta
	flags[name] = int(after) if after == floor(after) else after
	return {"field": "flags." + name, "before": before, "delta": delta, "after": flags[name], "reason": "flag"}

func mark_npc_met(npc_id: String) -> void:
	if not npcs.has(npc_id):
		npcs[npc_id] = {"relationship": 40, "trust": 40, "met": false}
	npcs[npc_id]["met"] = true

# ---------------------------------------------------------------------------
# 幂等保护与日志
# ---------------------------------------------------------------------------

func is_action_resolved(instance_id: String) -> bool:
	return _resolved_actions.has(instance_id)

func mark_action_resolved(instance_id: String) -> void:
	if not _resolved_actions.has(instance_id):
		_resolved_actions.append(instance_id)
	if _resolved_actions.size() > 200:
		_resolved_actions = _resolved_actions.slice(_resolved_actions.size() - 100)

func log_entry(entry: Dictionary) -> void:
	entry["day"] = day
	entry["slot"] = slot
	history.append(entry)
	if history.size() > 400:
		history = history.slice(history.size() - 200)

func unlock_ending(ending_id: String) -> void:
	if not unlocked_endings.has(ending_id):
		unlocked_endings.append(ending_id)

func _delta(before: Variant, after: Variant) -> Variant:
	if (before is int or before is float) and (after is int or after is float):
		return float(after) - float(before)
	return null
