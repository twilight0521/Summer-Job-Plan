extends Node
## 应用层核心：持有当前 run，协调各领域系统，向 UI 广播信号。
## 所有游戏推进都必须经过这里，UI 不直接改状态。

signal state_changed
signal message(text: String)
signal action_resolved(result: Dictionary)
signal event_requested(view: Dictionary)
signal event_resolved(result: Dictionary)
signal exam_requested(exams: Array)
signal exam_result(result: Dictionary)
signal phase_summary_requested(phase: int, summary: Dictionary)
signal game_over(summary: Dictionary)
signal shop_requested(items: Array)
signal save_completed(slot: String)

var state: GameState = null
var action_system: ActionSystem
var job_system: JobSystem
var event_system: EventSystem
var exam_system: ExamSystem
var schedule_system: ScheduleSystem
var relationship_system: RelationshipSystem
var ending_system: EndingSystem
var ability_system: AbilitySystem
var tutorial: TutorialCoordinator

var _pending_event: Dictionary = {}
var _pending_slot_advance: bool = false
var _awaiting_phase_continue: bool = false

func _ready() -> void:
	_register_input_actions()
	action_system = ActionSystem.new()
	job_system = action_system.job_system
	event_system = EventSystem.new()
	exam_system = ExamSystem.new()
	schedule_system = ScheduleSystem.new()
	relationship_system = RelationshipSystem.new()
	ending_system = EndingSystem.new()
	ability_system = AbilitySystem.new()
	tutorial = TutorialCoordinator.new()

func _register_input_actions() -> void:
	if not InputMap.has_action("advance_slot"):
		InputMap.add_action("advance_slot")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("advance_slot", key)

# ---------------------------------------------------------------------------
# 开局 / 读档
# ---------------------------------------------------------------------------

func start_new_game(run_seed: int = -1) -> void:
	if run_seed < 0:
		RandomSource.randomize_run()
		run_seed = RandomSource.get_seed()
	else:
		RandomSource.use_seed(run_seed)
	state = GameState.new_run(run_seed, ContentLoader.characters)
	_reset_pending()
	tutorial.reset()
	state_changed.emit()
	message.emit("暑假开始了。今天想做点什么？")

func load_game(slot: String) -> bool:
	var result := SaveRepository.load_slot(slot)
	if not result.get("ok", false):
		message.emit("读取失败：" + str(result.get("error", "")))
		return false
	var loaded_state: GameState = result["state"]
	if bool(loaded_state.meta.get("finished", false)):
		message.emit("这局游戏已经结束。")
		return false
	state = loaded_state
	_pending_event = state.meta.get("pending_event", {})
	_pending_slot_advance = bool(state.meta.get("pending_slot_advance", false))
	_awaiting_phase_continue = false
	state_changed.emit()
	message.emit("已读取存档。")
	return true

func _reset_pending() -> void:
	_pending_event = {}
	_pending_slot_advance = false
	_awaiting_phase_continue = false

func has_active_run() -> bool:
	return state != null

func is_game_finished() -> bool:
	return state != null and bool(state.meta.get("finished", false))

func has_pending_event() -> bool:
	return not _pending_event.is_empty()

## 游戏场景完成信号连接后调用，避免标题场景加载时丢失事件弹窗。
func resume_pending_event() -> bool:
	if _pending_event.is_empty() or state == null:
		return false
	if not EventSystem.EVENT_FIRED_PREFIX.is_empty() and bool(state.get_flag(EventSystem.EVENT_FIRED_PREFIX + str(_pending_event.get("id", "")))):
		return _clear_stale_pending_event()
	var view := event_system.present(state, _pending_event)
	if view.get("choices", []).is_empty():
		return _clear_stale_pending_event()
	event_requested.emit(view)
	return true

func _clear_stale_pending_event() -> bool:
	message.emit("待处理事件已失效，已清除未完成的推进。")
	_pending_event = {}
	_pending_slot_advance = false
	state.meta.erase("pending_event")
	state.meta.erase("pending_slot_advance")
	SaveRepository.save_auto(state)
	state_changed.emit()
	return false

# ---------------------------------------------------------------------------
# 行动
# ---------------------------------------------------------------------------

func available_actions() -> Array:
	if state == null:
		return []
	return action_system.actions_at(state, state.location_id)

func action_preview(action_id: String) -> Dictionary:
	if state == null:
		return {}
	return action_system.preview(state, action_id)

func perform_action(action_id: String) -> Dictionary:
	if state == null:
		return {}
	# 有事件在等待选择时不接受新行动，避免 pending 状态被绕过后错乱。
	if not _pending_event.is_empty():
		message.emit("请先处理眼前的事件。")
		return {"ok": false, "messages": ["请先处理眼前的事件。"]}
	var action := ContentLoader.get_action(action_id)
	var consumes := int(action.get("duration_slots", 1)) > 0
	# 幂等保护：只有消耗时段的行动才记录实例 ID，商店等界面行动可重复打开。
	var instance_id := "%d_%d_%s" % [state.day, state.slot, action_id]
	if consumes and state.is_action_resolved(instance_id):
		return {"ok": false, "messages": ["这个时段已经执行过该行动。"]}

	# 在临时副本上结算，保存成功后才提交，避免半结算或保存失败导致的不一致。
	var working := state.duplicate_state()
	var result := action_system.commit(working, action_id)
	if not result.get("ok", false):
		message.emit("；".join(result.get("messages", [])))
		return result

	if bool(result.get("consume_slot", false)):
		working.mark_action_resolved(instance_id)

	if not SaveRepository.save_auto(working):
		message.emit("保存失败，行动未执行。")
		return {"ok": false, "messages": ["保存失败，行动未执行。"]}
	state = working

	for msg in result.get("messages", []):
		message.emit(str(msg))
	action_resolved.emit(result)
	tutorial.on_action(action_id)

	# 商店 / 考试等特殊界面，不推进时段
	if result.get("special", "") == "shop":
		shop_requested.emit(ContentLoader.all_items())
		state_changed.emit()
		return result
	if result.get("special", "") == "exam":
		var exams := exam_system.available_exams(state)
		if exams.is_empty():
			# 入口行动本身不消耗任何资源，这里只提示，不再空推一个时段。
			message.emit("目前没有可以参加的考试。")
		else:
			exam_requested.emit(exams)
		state_changed.emit()
		return result

	# 结束当天（睡觉）优先，不再触发随机事件
	if result.get("end_day", false):
		_end_day(true)
		state_changed.emit()
		return result

	# 事件优先于时段推进
	if _try_trigger_event(result.get("event_pool", [])):
		state_changed.emit()
		return result

	_advance_slot()
	state_changed.emit()
	return result

## 返回是否结算成功；失败时 UI 应保留事件弹窗让玩家换一个选项。
func choose_event_choice(choice_id: String) -> bool:
	if _pending_event.is_empty():
		return false
	# 事务化：在副本上结算并保存成功后才提交。
	var working := state.duplicate_state()
	var result := event_system.resolve(working, _pending_event, choice_id)
	if not result.get("ok", false):
		message.emit(str(result.get("result_text", "无法选择该选项")))
		state_changed.emit()
		return false
	var advance_after_event := _pending_slot_advance
	working.meta.erase("pending_event")
	working.meta.erase("pending_slot_advance")
	if not SaveRepository.save_auto(working):
		message.emit("保存失败，选择未生效。")
		state_changed.emit()
		return false
	state = working
	_pending_event = {}
	event_resolved.emit(result)
	if advance_after_event:
		_pending_slot_advance = false
		_advance_slot()
	state_changed.emit()
	return true

func take_exam(exam_id: String, choice_id: String) -> void:
	if state == null:
		return
	var working := state.duplicate_state()
	var result := exam_system.commit(working, exam_id, choice_id)
	if not result.get("ok", false):
		message.emit(str(result.get("message", "无法参加考试")))
		state_changed.emit()
		return
	if not SaveRepository.save_auto(working):
		message.emit("保存失败，考试未生效。")
		state_changed.emit()
		return
	state = working
	exam_result.emit(result)
	message.emit(str(result.get("message", "")))
	_advance_slot()
	state_changed.emit()

func buy_item(item_id: String) -> bool:
	if state == null:
		return false
	var item := ContentLoader.get_item(item_id)
	if item.is_empty():
		return false
	# 非消耗品（护具/文具/衣服等）不允许重复购买：
	# 之前可以无限买「新衣服」刷心情，破坏资源循环。
	if not bool(item.get("consumable", true)):
		var effects: Variant = item.get("effects", {})
		if effects is Dictionary:
			for key in effects:
				var field := str(key)
				if field.begins_with("flags.") and bool(state.get_flag(field.substr("flags.".length()))):
					message.emit("你已经拥有「%s」了。" % str(item.get("name", item_id)))
					return false
	var price := int(item.get("price", 0))
	if state.has_passive("passive_frugal"):
		price = int(round(price * 0.8))
	if int(state.player.get("money", 0)) < price:
		message.emit("现金不足。")
		return false
	var working := state.duplicate_state()
	working.add_player("money", -price, "购买 " + str(item.get("name", item_id)))
	EffectResolver.apply_dict(working, item.get("effects", {}), "物品效果")
	if not SaveRepository.save_auto(working):
		message.emit("保存失败，购买未生效。")
		return false
	state = working
	message.emit("购买了「%s」。" % item.get("name", item_id))
	state_changed.emit()
	return true

# ---------------------------------------------------------------------------
# 经验 / 被动能力
# ---------------------------------------------------------------------------

func available_passives() -> Array:
	if state == null:
		return []
	return ability_system.available(state)

func unlock_passive(passive_id: String) -> bool:
	if state == null:
		return false
	var working := state.duplicate_state()
	var result := ability_system.unlock(working, passive_id)
	if not result.get("ok", false):
		message.emit(str(result.get("message", "无法解锁")))
		return false
	if not SaveRepository.save_auto(working):
		message.emit("保存失败，能力未解锁。")
		return false
	state = working
	message.emit(str(result.get("message", "")))
	state_changed.emit()
	return true

# ---------------------------------------------------------------------------
# 导航与时段
# ---------------------------------------------------------------------------

func move_to(location_id: String) -> void:
	if state == null:
		return
	var loc := ContentLoader.get_location(location_id)
	if loc.is_empty():
		return
	if state.location_id == location_id:
		return
	if not location_is_open(location_id):
		message.emit("「%s」现在还没开门。" % loc.get("name", location_id))
		return
	if float(state.player.get("energy", 0)) < float(GameConfig.MOVE_ENERGY_COST):
		message.emit("体力不足，无法移动。")
		return
	var working := state.duplicate_state()
	working.location_id = location_id
	working.add_player("energy", -float(GameConfig.MOVE_ENERGY_COST), "移动")
	if not SaveRepository.save_auto(working):
		message.emit("保存失败，未能移动。")
		return
	state = working
	message.emit("你来到了「%s」。" % loc.get("name", location_id))
	state_changed.emit()

func location_is_open(location_id: String) -> bool:
	var loc := ContentLoader.get_location(location_id)
	if loc.is_empty():
		return false
	var now := GameConfig.slot_minutes(state.slot)
	var range_arr: Variant = loc.get("open_minutes", [0, 1440])
	return now >= int(range_arr[0]) and now <= int(range_arr[1])

func rest_until_next_slot() -> void:
	idle_until_next_slot()

## 不安排具体行动时的默认选择：发呆消磨一个时段；状态过差则自动睡着。
func idle_until_next_slot() -> void:
	if state == null:
		return
	if not _pending_event.is_empty():
		message.emit("请先处理眼前的事件。")
		return
	var working := state.duplicate_state()
	var result := schedule_system.idle(working)
	if not SaveRepository.save_auto(working):
		message.emit("自动存档失败，发呆未生效。")
		return
	state = working
	for msg in result.get("messages", []):
		message.emit(str(msg))
	if result.get("ended_day", false):
		_after_day_end(result)
	state_changed.emit()

## 当前地点按常用路线给出一个“确认”按钮对应的行动。
func primary_location_action() -> Dictionary:
	if state == null:
		return {}
	var preferred: Array = []
	match state.location_id:
		"breakfast_shop": preferred = ["breakfast_shift", "eat_breakfast"]
		"library": preferred = ["math_study", "study_library"]
		"home": preferred = ["tutor_shift", "study_home", "rest"]
		"convenience_store": preferred = ["eat_convenience"]
		"tea_shop": preferred = ["tea_shop_shift", "socialize"]
		"gym_park": preferred = ["exercise"]
		"hardware_store": preferred = ["construction_shift", "collect_scrap"]
		"bank_office": preferred = ["accounting_shift", "apply_accounting"]
		"commercial_street": preferred = ["stroll", "socialize"]
	for action_id in preferred:
		if not ContentLoader.get_action(action_id).is_empty() and action_system.is_available(state, action_id):
			return {"action_id": action_id, "label": _primary_action_label(action_id), "preview": action_preview(action_id)}
	return {}

func _primary_action_label(action_id: String) -> String:
	match action_id:
		"breakfast_shift", "tea_shop_shift", "construction_shift", "tutor_shift", "accounting_shift": return "确认工作"
		"math_study", "study_library", "study_home", "take_exam": return "确认学习"
		"exercise": return "确认锻炼"
		"stroll", "socialize": return "确认社交"
		"eat_breakfast", "eat_convenience": return "确认吃饭"
		"rest": return "确认休息"
		"collect_scrap": return "确认捡废品"
		"apply_accounting": return "确认申请"
	return "确认行动"

func sleep_now() -> void:
	if state == null:
		return
	_end_day(true)

# ---------------------------------------------------------------------------
# 内部推进
# ---------------------------------------------------------------------------

func _try_trigger_event(pool: Variant) -> bool:
	var event: Dictionary = {}
	if pool is Array and not pool.is_empty():
		event = event_system.pick_event(state, pool)
	else:
		event = event_system.pick_event(state)
	if event.is_empty():
		return false
	# 所有选项都被条件过滤掉时不弹窗，避免出现无法关闭的事件界面。
	if event_system.present(state, event).get("choices", []).is_empty():
		return false
	_pending_event = event
	_pending_slot_advance = true
	state.meta["pending_event"] = event.duplicate(true)
	state.meta["pending_slot_advance"] = true
	if not SaveRepository.save_auto(state):
		state.meta.erase("pending_event")
		state.meta.erase("pending_slot_advance")
		_pending_event = {}
		_pending_slot_advance = false
		return false
	event_requested.emit(event_system.present(state, event))
	return true

func _advance_slot() -> bool:
	# 事务化：先在副本上推进并保存，成功后才提交。
	var working := state.duplicate_state()
	var result := schedule_system.advance_slot(working)
	if not SaveRepository.save_auto(working):
		message.emit("自动存档失败，时段未推进。")
		return false
	state = working
	if result.get("ended_day", false):
		for msg in result.get("messages", []):
			message.emit(str(msg))
		_after_day_end(result)
	else:
		message.emit("现在是第 %d 天 %s。" % [state.day, GameConfig.slot_name(state.slot)])
	return true

func _end_day(explicit_sleep: bool) -> bool:
	var working := state.duplicate_state()
	var result: Dictionary
	if explicit_sleep:
		result = schedule_system.sleep_and_end_day(working)
	else:
		result = schedule_system.auto_end_day(working)
	if not SaveRepository.save_auto(working):
		message.emit("自动存档失败，进度未推进。")
		return false
	state = working
	for msg in result.get("messages", []):
		message.emit(str(msg))
	_after_day_end(result)
	return true

func _after_day_end(result: Dictionary) -> void:
	if result.get("game_over", false):
		_trigger_ending()
		return
	var phase := int(result.get("phase_completed", 0))
	if phase > 0:
		_awaiting_phase_continue = true
		phase_summary_requested.emit(phase, _build_phase_summary(phase))
		return
	message.emit("新的一天开始了。")

func continue_after_phase_summary() -> void:
	if not _awaiting_phase_continue:
		return
	_awaiting_phase_continue = false
	message.emit("第 %d 阶段结束，继续加油。" % state.phase)
	state_changed.emit()

func _build_phase_summary(phase: int) -> Dictionary:
	return {
		"phase": phase,
		"day": state.day,
		"money": int(state.player.get("money", 0)),
		"health": int(state.player.get("health", 0)),
		"mood": int(state.player.get("mood", 0)),
		"trust": int(state.player.get("trust", 0)),
		"study": int(state.player.get("study", 0)),
		"exp": int(state.player.get("exp", 0)),
		"work_days": int(state.get_flag("work_days")),
		"relationships": relationship_system.summary(state),
	}

func _trigger_ending() -> void:
	var ending := ending_system.best_ending(state)
	if ending.is_empty():
		message.emit("这个暑假结束了。")
		return
	var ending_id := str(ending.get("id", ""))
	# 与其它流程一致：在副本上结算，保存成功后才提交。
	var working := state.duplicate_state()
	working.unlock_ending(ending_id)
	working.meta["finished"] = true
	SaveRepository.record_ending(ending_id)
	if not SaveRepository.save_auto(working):
		message.emit("结局存档失败，仍保留当前结局页面。")
	state = working
	var summary := ending_system.summary(state, ending, relationship_system)
	summary["key_choices"] = ending_system.key_choices(state)
	game_over.emit(summary)

# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

func save_manual(slot: String) -> bool:
	if state == null:
		return false
	var ok := SaveRepository.save(slot, state)
	if ok:
		save_completed.emit(slot)
		message.emit("已保存到 " + slot)
	return ok

func auto_save() -> void:
	if state != null:
		SaveRepository.save_auto(state)
