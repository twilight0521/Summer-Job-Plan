extends Node
## 启动时加载并校验所有 JSON 内容表。
## 只做读取和校验，不持有本局状态。

const DATA_DIR := "res://data/"
const EFFECT_CONTAINERS := ["effects", "cost", "success_effects", "fail_effects"]
const KNOWN_EFFECT_ROOTS := ["player", "flags", "npcs"]
const KNOWN_NPC_FIELDS := ["relationship", "trust"]

var locations: Dictionary = {}
var actions: Dictionary = {}
var jobs: Dictionary = {}
var events: Dictionary = {}
var characters: Dictionary = {}
var endings: Array = []
var exams: Dictionary = {}
var items: Dictionary = {}
var passives: Dictionary = {}

var load_errors: Array[String] = []
var loaded: bool = false

func _ready() -> void:
	load_all()

func load_all() -> bool:
	load_errors.clear()
	locations = _index_by_id(_load_array("locations.json", "locations"), "id")
	actions = _index_by_id(_load_array("actions.json", "actions"), "id")
	jobs = _index_by_id(_load_array("jobs.json", "jobs"), "id")
	events = _index_by_id(_load_array("events.json", "events"), "id")
	exams = _index_by_id(_load_array("exams.json", "exams"), "id")
	items = _index_by_id(_load_array("items.json", "items"), "id")
	passives = _index_by_id(_load_array("passives.json", "passives"), "id")
	endings = _load_array("endings.json", "endings")

	var chars: Variant = _load_file("characters.json")
	if chars is Dictionary and chars.has("characters"):
		characters = _index_by_id(chars["characters"], "id")
	else:
		load_errors.append("characters.json 缺少 characters 数组")

	_validate()
	loaded = load_errors.is_empty()
	for err in load_errors:
		push_warning("[ContentLoader] " + err)
	return loaded

func _load_array(file_name: String, key: String) -> Array:
	var data: Variant = _load_file(file_name)
	if data is Dictionary and data.has(key):
		return data[key]
	load_errors.append("%s 缺少 %s 数组" % [file_name, key])
	return []

func _load_file(file_name: String) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		load_errors.append("找不到数据文件: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		load_errors.append("JSON 解析失败: " + path)
	return parsed

func _index_by_id(items_arr: Array, key: String) -> Dictionary:
	var result := {}
	for item in items_arr:
		if not (item is Dictionary) or not item.has(key):
			load_errors.append("条目缺少 %s 字段" % key)
			continue
		var id: String = str(item[key])
		if result.has(id):
			load_errors.append("ID 重复: " + id)
		result[id] = item
	return result

# ---------------------------------------------------------------------------
# 访问器
# ---------------------------------------------------------------------------

func get_location(id: String) -> Dictionary:
	return locations.get(id, {})

func get_action(id: String) -> Dictionary:
	if actions.has(id):
		return actions[id]
	if jobs.has(id):
		return jobs[id]
	return {}

## 工作也是行动的一种，返回全部可执行条目（含 job 类型）。
func get_all_actions() -> Dictionary:
	var merged := {}
	merged.merge(actions)
	merged.merge(jobs)
	return merged

func get_job(id: String) -> Dictionary:
	return jobs.get(id, {})

func get_event(id: String) -> Dictionary:
	return events.get(id, {})

func get_character(id: String) -> Dictionary:
	return characters.get(id, {})

func get_exam(id: String) -> Dictionary:
	return exams.get(id, {})

func get_item(id: String) -> Dictionary:
	return items.get(id, {})

func get_passive(id: String) -> Dictionary:
	return passives.get(id, {})

func all_passives() -> Array:
	return passives.values()

func all_events() -> Array:
	return events.values()

func all_locations() -> Array:
	return locations.values()

func all_items() -> Array:
	return items.values()

func all_exams() -> Array:
	return exams.values()

func get_endings() -> Array:
	return endings

# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------

func _validate() -> void:
	# 地点引用的行动必须存在
	for loc_id in locations:
		var loc: Dictionary = locations[loc_id]
		for action_id in loc.get("actions", []):
			if not actions.has(action_id) and not jobs.has(action_id):
				load_errors.append("地点 %s 引用了不存在的行动 %s" % [loc_id, action_id])
		for event_id in loc.get("event_pool", []):
			if not events.has(event_id):
				load_errors.append("地点 %s 引用了不存在的事件 %s" % [loc_id, event_id])

	# 工作地点、事件池
	for job_id in jobs:
		var job: Dictionary = jobs[job_id]
		var loc_id: String = _reference_id(job.get("location_id", ""))
		if loc_id != "" and not locations.has(loc_id):
			load_errors.append("工作 %s 引用了不存在的地点 %s" % [job_id, loc_id])
		for event_id in job.get("risk_event_pool", []):
			if not events.has(event_id):
				load_errors.append("工作 %s 引用了不存在的事件 %s" % [job_id, event_id])

	# 行动地点
	for action_id in actions:
		var action: Dictionary = actions[action_id]
		var loc_id: String = _reference_id(action.get("location_id", ""))
		if loc_id != "" and not locations.has(loc_id):
			load_errors.append("行动 %s 引用了不存在的地点 %s" % [action_id, loc_id])
		if action.get("handler", "action") == "npc_talk":
			var npc_id: String = _reference_id(action.get("npc_id", ""))
			if not characters.has(npc_id):
				load_errors.append("行动 %s 引用了不存在的 NPC %s" % [action_id, npc_id])

	# 事件：NPC 存在、结局条件字段可解析
	for event_id in events:
		var event: Dictionary = events[event_id]
		var npc_id: String = _reference_id(event.get("npc", ""))
		if npc_id != "" and not characters.has(npc_id):
			load_errors.append("事件 %s 引用了不存在的 NPC %s" % [event_id, npc_id])
		var loc_id: String = _reference_id(event.get("location", ""))
		if loc_id != "" and not locations.has(loc_id):
			load_errors.append("事件 %s 引用了不存在的地点 %s" % [event_id, loc_id])
		if event.has("conditions"):
			for condition_error in ConditionEvaluator.validate(event["conditions"]):
				load_errors.append("事件 %s 条件错误: %s" % [event_id, condition_error])
		for choice in event.get("choices", []):
			_validate_effect_entry("事件 %s 选项 %s" % [event_id, choice.get("id", "?")], choice)
		for choice in event.get("choices", []):
			if choice.has("conditions"):
				for condition_error in ConditionEvaluator.validate(choice["conditions"]):
					load_errors.append("事件 %s 选项 %s 条件错误: %s" % [event_id, choice.get("id", "?"), condition_error])

	# 角色常驻地点与阶段事件存在
	for char_id in characters:
		var char_loc: String = _reference_id(characters[char_id].get("location", ""))
		if char_loc != "" and not locations.has(char_loc):
			load_errors.append("角色 %s 引用了不存在的地点 %s" % [char_id, char_loc])
		for stage in characters[char_id].get("stages", []):
			var eid: String = str(stage.get("event_id", ""))
			if not events.has(eid):
				load_errors.append("角色 %s 的阶段事件不存在: %s" % [char_id, eid])

	# 结局条件字段可解析
	for ending in endings:
		var cond: Variant = ending.get("conditions", {})
		var errs := ConditionEvaluator.validate(cond)
		for e in errs:
			load_errors.append("结局 %s 条件错误: %s" % [ending.get("id", "?"), e])
	_validate_conditions("行动", actions, ["requires", "conditions"])
	_validate_conditions("工作", jobs, ["requires", "conditions"])
	_validate_conditions("考试", exams, ["requires", "conditions", "unlock_requires"])
	for exam_id in exams:
		for choice in exams[exam_id].get("choices", []):
			_validate_effect_entry("考试 %s 选项 %s" % [exam_id, choice.get("id", "?")], choice)

	# 数值改动字段必须存在：否则打错字会被静默写成一个 flag。
	_validate_effects("actions", actions)
	_validate_effects("jobs", jobs)
	_validate_effects("events", events)
	_validate_effects("exams", exams)
	_validate_effects("items", items)
	_validate_effects("passives", passives)
	for event_id in events:
		for choice in events[event_id].get("choices", []):
			_validate_effect_entry("事件 %s 的选项 %s" % [event_id, choice.get("id", "?")], choice)

func _validate_effects(label: String, entries: Dictionary) -> void:
	for entry_id in entries:
		var entry: Variant = entries[entry_id]
		if entry is Dictionary:
			_validate_effect_entry("%s/%s" % [label, entry_id], entry)

func _validate_conditions(label: String, entries: Dictionary, keys: Array) -> void:
	for entry_id in entries:
		var entry: Dictionary = entries[entry_id]
		for key in keys:
			if entry.has(key):
				for condition_error in ConditionEvaluator.validate(entry[key]):
					load_errors.append("%s %s 条件错误: %s" % [label, entry_id, condition_error])
		for choice in entry.get("choices", []):
			if choice.has("conditions"):
				for condition_error in ConditionEvaluator.validate(choice["conditions"]):
					load_errors.append("%s %s 选项 %s 条件错误: %s" % [label, entry_id, choice.get("id", "?"), condition_error])

func _validate_effect_entry(owner: String, entry: Dictionary) -> void:
	for container in EFFECT_CONTAINERS:
		var raw: Variant = entry.get(container, null)
		if not (raw is Dictionary):
			continue
		for field in raw:
			_validate_effect_key(owner, container, str(field))
	var extra: Variant = entry.get("extra", null)
	if extra is Array:
		for raw_effect in extra:
			if raw_effect is Dictionary and str(raw_effect.get("path", "")) != "":
				_validate_effect_path(owner, str(raw_effect["path"]))

func _validate_effect_key(owner: String, container: String, field: String) -> void:
	if field.contains("."):
		_validate_effect_path(owner, field)
		return
	if not GameConfig.CLAMPS.has(field):
		load_errors.append("%s 的 %s 里字段不存在: %s（会被静默当成 flag）" % [owner, container, field])

func _validate_effect_path(owner: String, path: String) -> void:
	var parts := path.split(".")
	var root: String = parts[0]
	if not KNOWN_EFFECT_ROOTS.has(root):
		load_errors.append("%s 的 effect 路径根未知: %s" % [owner, path])
		return
	if root == "player" and (parts.size() < 2 or not GameConfig.CLAMPS.has(parts[1])):
		load_errors.append("%s 的 effect 玩家字段不存在: %s" % [owner, path])
	elif root == "flags" and parts.size() < 2:
		load_errors.append("%s 的 effect flag 名为空: %s" % [owner, path])
	elif root == "npcs":
		if parts.size() < 3 or not KNOWN_NPC_FIELDS.has(parts[2]):
			load_errors.append("%s 的 effect NPC 字段未知: %s" % [owner, path])
		elif not characters.has(parts[1]):
			load_errors.append("%s 的 effect NPC 不存在: %s" % [owner, path])

func _reference_id(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)
