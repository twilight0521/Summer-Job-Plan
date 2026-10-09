class_name TestGuards
extends RefCounted
## 针对资源成本、考试/事件结算入口、存档 schema 的防护测试。

static func run(t) -> void:
	_cost_gate(t)
	_exam_gate(t)
	_event_gate(t)
	_save_schema(t)

static func _cost_gate(t) -> void:
	var state := GameState.new_run(101, ContentLoader.characters)
	state.location_id = "convenience_store"
	var sys := ActionSystem.new()

	state.player["money"] = 0
	t.eq(sys.availability_report(state, "eat_convenience").get("ok", false), false, "现金不足时付费行动不可用")

	state.player["money"] = 100
	t.eq(sys.availability_report(state, "eat_convenience").get("ok", false), true, "现金充足时行动可用")

	var before := int(state.player["money"])
	sys.commit(state, "eat_convenience")
	t.eq(int(state.player["money"]), before - 12, "成本被正确扣除而非增加")

	# 体力不足时高消耗行动不可用
	state.location_id = "gym_park"
	state.slot = 1
	state.player["energy"] = 3
	t.eq(sys.availability_report(state, "exercise").get("ok", false), false, "体力不足时行动不可用")

static func _exam_gate(t) -> void:
	var state := GameState.new_run(102, ContentLoader.characters)
	state.set_flag("library_math_count", 5)
	var exams := ExamSystem.new()

	var bad_choice := exams.commit(state, "math_basic", "not_a_choice")
	t.eq(bad_choice.get("ok", false), false, "非法考试选项被拒绝")
	t.eq(bool(state.get_flag("exam_taken_phase_1_math_basic")), false, "非法考试不消耗阶段名额")

	var locked := exams.commit(state, "accounting_entry", "careful")
	t.eq(locked.get("ok", false), false, "未解锁考试被拒绝")

	var ok_result := exams.commit(state, "math_basic", "careful")
	t.eq(ok_result.get("ok", false), true, "已解锁考试可参加")
	t.eq(bool(state.get_flag("exam_taken_phase_1_math_basic")), true, "合法考试记录阶段名额")

static func _event_gate(t) -> void:
	var state := GameState.new_run(103, ContentLoader.characters)
	state.location_id = "commercial_street"
	state.slot = 2
	var events := EventSystem.new()
	var wallet := ContentLoader.get_event("street_01")

	var bad := events.resolve(state, wallet, "zzz")
	t.eq(bad.get("ok", false), false, "非法事件选项被拒绝")
	t.eq(bool(state.get_flag("event_fired_street_01")), false, "非法选项不标记事件已触发")

	# 条件选项：仅当条件满足时才可选
	var cond_event := {
		"id": "test_cond", "title": "t", "text": "t",
		"choices": [{"id": "a", "text": "a", "conditions": {"all": [{"field": "player.money", "op": "gte", "value": 99999}]}}]
	}
	t.eq(events.resolve(state, cond_event, "a").get("ok", false), false, "条件不满足的选项被拒绝")

static func _save_schema(t) -> void:
	var slot := "test_guards_schema"

	var bad := {
		"schema_version": 1,
		"content_version": "x",
		"state": {"player": [], "day": 1, "slot": 0, "phase": 1, "location_id": "home"},
	}
	var f := FileAccess.open(SaveRepository.SAVE_DIR + slot + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(bad))
	f.close()
	var loaded := SaveRepository.load_slot(slot)
	t.eq(loaded.get("ok", false), false, "非法存档结构被拒绝")

	# 地点引用不存在
	var bad_loc := {
		"schema_version": 1, "content_version": "x",
		"state": {"player": {"money": 1}, "npcs": {}, "flags": {}, "history": [],
			"day": 3, "slot": 1, "phase": 1, "location_id": "nowhere"},
	}
	var f2 := FileAccess.open(SaveRepository.SAVE_DIR + slot + ".json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(bad_loc))
	f2.close()
	t.eq(SaveRepository.load_slot(slot).get("ok", false), false, "非法地点引用被拒绝")

	SaveRepository.delete(slot)
