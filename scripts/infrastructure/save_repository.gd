extends Node
## 本地 JSON 存档。3 个手动档 + 1 个自动档 + 1 个备份档。
## 写入采用临时文件 + rename，避免半文件。

const SAVE_DIR := "user://saves/"
const MANUAL_SLOTS := ["manual_1", "manual_2", "manual_3"]
const AUTO_SLOT := "auto"
const BACKUP_SLOT := "backup"
const PROFILE_PATH := "user://profile.json"

signal saved(slot: String)
signal load_failed(slot: String, reason: String)

func _ready() -> void:
	_ensure_dir()

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"

func has_save(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))

func list_saves() -> Array:
	var result: Array = []
	for slot in MANUAL_SLOTS + [AUTO_SLOT, BACKUP_SLOT]:
		result.append({"slot": slot, "exists": has_save(slot), "info": read_info(slot)})
	return result

func read_info(slot: String) -> Dictionary:
	if not has_save(slot):
		return {}
	var text := FileAccess.get_file_as_string(_path(slot))
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return {}
	var state: Variant = data.get("state", {})
	if not (state is Dictionary):
		return {}
	return {
		"day": int(state.get("day", 1)),
		"slot": int(state.get("slot", 0)),
		"saved_at": data.get("saved_at", ""),
		"content_version": data.get("content_version", ""),
	}

func save(slot: String, state: GameState) -> bool:
	_ensure_dir()
	if slot == AUTO_SLOT and has_save(AUTO_SLOT):
		_copy_file(_path(AUTO_SLOT), _path(BACKUP_SLOT))
	var payload := {
		"schema_version": GameConfig.SCHEMA_VERSION,
		"content_version": GameConfig.CONTENT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
		"state": state.to_dict(),
	}
	var text := JSON.stringify(payload, "\t")
	var tmp_path := _path(slot) + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveRepository] 无法写入: " + tmp_path)
		return false
	file.store_string(text)
	file.close()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	if dir.file_exists(slot + ".json"):
		dir.remove(slot + ".json")
	var err := dir.rename(slot + ".json.tmp", slot + ".json")
	if err != OK:
		push_error("[SaveRepository] rename 失败: %s" % err)
		return false
	saved.emit(slot)
	return true

func save_auto(state: GameState) -> bool:
	return save(AUTO_SLOT, state)

func load_slot(slot: String) -> Dictionary:
	if not has_save(slot):
		return {"ok": false, "error": "存档不存在"}
	var data := _read_json(_path(slot))
	if data.is_empty():
		return _recover_or_fail(slot, "存档损坏")
	var version := int(data.get("schema_version", 1))
	if version > GameConfig.SCHEMA_VERSION:
		load_failed.emit(slot, "需要更新游戏")
		return {"ok": false, "error": "存档来自更高版本，请更新游戏"}
	var state_data: Variant = data.get("state", null)
	if not (state_data is Dictionary):
		return _recover_or_fail(slot, "存档结构损坏")
	var schema_error := validate_state_data(state_data)
	if schema_error != "":
		return _recover_or_fail(slot, schema_error)
	var migrated := _migrate(data, version)
	var state := GameState.from_dict(migrated.get("state", {}))
	RandomSource.use_seed(state.seed)
	return {"ok": true, "state": state}

## 校验存档 state 的类型、范围与引用，返回错误文本（空串表示通过）。
func validate_state_data(state_data: Dictionary) -> String:
	for key in ["player", "npcs", "flags"]:
		if not (state_data.get(key, {}) is Dictionary):
			return "存档字段 %s 类型错误" % key
	if not (state_data.get("history", []) is Array):
		return "存档字段 history 类型错误"
	if not (state_data.get("unlocked_endings", []) is Array):
		return "存档字段 unlocked_endings 类型错误"
	var passives: Variant = state_data.get("passives", [])
	if not (passives is Array):
		return "存档字段 passives 类型错误"
	for passive_id in passives:
		if not (passive_id is String):
			return "passives 含非字符串项"

	var day := int(state_data.get("day", 1))
	if day < 1 or day > GameConfig.TOTAL_DAYS + 1:
		return "存档天数超出范围"
	var slot := int(state_data.get("slot", 0))
	if slot < 0 or slot > 3:
		return "存档时段超出范围"
	var phase := int(state_data.get("phase", 1))
	if phase < 1 or phase > GameConfig.PHASE_COUNT:
		return "存档阶段超出范围"
	var loc_id := str(state_data.get("location_id", ""))
	if not ContentLoader.locations.has(loc_id):
		return "存档地点不存在: " + loc_id

	# 玩家字段必须都是数字，且包含全部必要字段
	var player: Dictionary = state_data.get("player", {})
	for required in GameConfig.PLAYER_INITIAL:
		if not player.has(required):
			return "玩家缺少字段: " + required
	for field in player:
		if not (player[field] is int or player[field] is float):
			return "玩家字段 %s 类型错误" % field

	# phase 必须与 day 一致
	if phase != GameConfig.phase_of_day(day):
		return "存档阶段与天数不一致"

	# NPC 记录字段级校验
	var npcs: Dictionary = state_data.get("npcs", {})
	for npc_id in npcs:
		var npc: Variant = npcs[npc_id]
		if not (npc is Dictionary):
			return "NPC 记录 %s 类型错误" % npc_id
		for stat in ["relationship", "trust"]:
			if npc.has(stat) and not (npc[stat] is int or npc[stat] is float):
				return "NPC %s.%s 类型错误" % [npc_id, stat]
		if npc.has("met") and not (npc["met"] is bool):
			return "NPC %s.met 类型错误" % npc_id

	# 幂等记录必须是字符串数组
	var resolved: Variant = state_data.get("_resolved_actions", [])
	if not (resolved is Array):
		return "_resolved_actions 类型错误"
	for entry in resolved:
		if not (entry is String):
			return "_resolved_actions 含非字符串项"
	return ""

func _recover_or_fail(slot: String, reason: String) -> Dictionary:
	if slot == AUTO_SLOT and has_save(BACKUP_SLOT):
		var backup := load_slot(BACKUP_SLOT)
		if backup.get("ok", false):
			return backup
	load_failed.emit(slot, reason)
	return {"ok": false, "error": reason}

func load_auto() -> Dictionary:
	return load_slot(AUTO_SLOT)

func delete(slot: String) -> void:
	if has_save(slot):
		var dir := DirAccess.open(SAVE_DIR)
		if dir:
			dir.remove(slot + ".json")

# ---------------------------------------------------------------------------

func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

func _copy_file(from: String, to: String) -> void:
	if not FileAccess.file_exists(from):
		return
	var content := FileAccess.get_file_as_string(from)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()

func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var version := from_version
	# 预留逐步迁移；当前只有 v1。
	while version < GameConfig.SCHEMA_VERSION:
		match version:
			_:
				version += 1
		data["schema_version"] = version
	return data

# ---------------------------------------------------------------------------
# 全局档案（跨周目：已解锁结局、设置、教程）
# ---------------------------------------------------------------------------

func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {"unlocked_endings": [], "settings": {"bgm_volume": 0.8, "sfx_volume": 0.8, "text_speed": 1.0}, "tutorial_done": false}
	var text := FileAccess.get_file_as_string(PROFILE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {"unlocked_endings": [], "settings": {}, "tutorial_done": false}

func save_profile(profile: Dictionary) -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(profile, "\t"))
	file.close()

func record_ending(ending_id: String) -> Dictionary:
	var profile := load_profile()
	var list: Array = profile.get("unlocked_endings", [])
	if not list.has(ending_id):
		list.append(ending_id)
	profile["unlocked_endings"] = list
	save_profile(profile)
	return profile
