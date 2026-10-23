class_name ConditionEvaluator
extends RefCounted
## 通用条件表达式解释器。只读状态，无副作用。
## 支持 all / any / not，以及叶子条件：
##   {"field":"player.health","op":"gte","value":50}
##   {"flag":"math_exam_passed","op":"eq","value":true}
##   {"tag":"has_protective_gear","op":"has_tag"}

const KNOWN_OPS := ["gte", "lte", "gt", "lt", "eq", "ne", "between", "in", "has_tag"]
const KNOWN_ROOTS := ["player", "flags", "npcs", "day", "slot", "phase", "location_id", "computed"]
const KNOWN_NPC_FIELDS := ["relationship", "trust"]
const KNOWN_COMPUTED_FIELDS := ["count_high_relationship", "phase"]

static func evaluate(condition: Variant, state) -> bool:
	if condition == null:
		return true
	if not (condition is Dictionary):
		return false
	var cond: Dictionary = condition
	if cond.is_empty():
		return true

	if cond.has("all"):
		for sub in cond["all"]:
			if not evaluate(sub, state):
				return false
		return true
	if cond.has("any"):
		for sub in cond["any"]:
			if evaluate(sub, state):
				return true
		return false
	if cond.has("not"):
		return not evaluate(cond["not"], state)

	# 叶子条件
	return _evaluate_leaf(cond, state)

static func _evaluate_leaf(cond: Dictionary, state) -> bool:
	var op: String = str(cond.get("op", "eq"))
	var expected: Variant = cond.get("value", true)
	var actual: Variant = _resolve(cond, state)

	match op:
		"gte":
			return float(actual) >= float(expected)
		"lte":
			return float(actual) <= float(expected)
		"gt":
			return float(actual) > float(expected)
		"lt":
			return float(actual) < float(expected)
		"eq":
			return _loose_equal(actual, expected)
		"ne":
			return not _loose_equal(actual, expected)
		"between":
			if not (expected is Array) or expected.size() < 2:
				return false
			return float(actual) >= float(expected[0]) and float(actual) <= float(expected[1])
		"in":
			if not (expected is Array):
				return false
			for v in expected:
				if _loose_equal(actual, v):
					return true
			return false
		"has_tag":
			return _has_tag(state, str(cond.get("tag", "")))
	return false

static func _resolve(cond: Dictionary, state) -> Variant:
	if state == null:
		return null
	if cond.has("field"):
		return state.get_field(str(cond["field"]))
	if cond.has("flag"):
		return state.get_flag(str(cond["flag"]))
	if cond.has("tag"):
		return _has_tag(state, str(cond["tag"]))
	return null

static func _has_tag(state, tag: String) -> bool:
	if state == null:
		return false
	if state.has_method("has_tag"):
		return state.has_tag(tag)
	return false

static func _loose_equal(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == b
	if (a is bool) or (b is bool):
		return bool(a) == bool(b)
	if (a is String) or (b is String):
		return str(a) == str(b)
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b

## 仅做结构校验，不依赖运行状态。
static func validate(condition: Variant) -> Array:
	var errors: Array = []
	_validate_recursive(condition, errors)
	return errors

static func _validate_recursive(condition: Variant, errors: Array) -> void:
	if condition == null:
		return
	if not (condition is Dictionary):
		errors.append("条件必须是对象")
		return
	var cond: Dictionary = condition
	if cond.is_empty():
		return
	for key in ["all", "any"]:
		if cond.has(key):
			if not (cond[key] is Array):
				errors.append("%s 必须是数组" % key)
				return
			for sub in cond[key]:
				_validate_recursive(sub, errors)
			return
	if cond.has("not"):
		_validate_recursive(cond["not"], errors)
		return
	var op: String = str(cond.get("op", "eq"))
	if not KNOWN_OPS.has(op):
		errors.append("未知操作符: " + op)
	if cond.has("field"):
		var path: String = str(cond["field"])
		var parts := path.split(".")
		var root: String = parts[0]
		if not KNOWN_ROOTS.has(root):
			errors.append("未知字段根: " + path)
		elif root == "player":
			# 只校验字段名，拼错会静默取到 0，所以必须挡在加载阶段。
			if parts.size() < 2 or not GameConfig.CLAMPS.has(parts[1]):
				errors.append("未知玩家字段: " + path)
		elif root == "npcs":
			if parts.size() < 3 or not KNOWN_NPC_FIELDS.has(parts[2]):
				errors.append("未知 NPC 字段: " + path)
		elif root == "computed":
			if parts.size() < 2 or not KNOWN_COMPUTED_FIELDS.has(parts[1]):
				errors.append("未知计算字段: " + path)
	elif cond.has("flag"):
		pass
	elif cond.has("tag"):
		pass
	else:
		errors.append("叶子条件缺少 field/flag/tag")
