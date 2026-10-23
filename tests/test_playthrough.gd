class_name TestPlaythrough
extends RefCounted
## 完整 60 天通关（走 GameFlow 全链路）：验证第 15 节验收第 1、4、7 项。
## 驱动方式模拟真实玩家：优先行动，晚上睡觉，事件选第一个选项，
## 考试选第一个选项，阶段总结点击继续。

const MAX_STEPS := 4000

static func run(t) -> void:
	_run_to_ending(t)

static func _run_to_ending(t) -> void:
	# 用字典做持有器：lambda 里可就地写入（直接对外部局部变量重新赋值不会回传）。
	var cap := {"event": {}, "exams": [], "phase": {}, "ending": {}}
	var h_event := func(view): cap["event"] = view
	var h_exams := func(exams): cap["exams"] = exams
	var h_phase := func(phase, summary): cap["phase"] = {"phase": phase}
	var h_end := func(summary): cap["ending"] = summary
	GameFlow.event_requested.connect(h_event)
	GameFlow.exam_requested.connect(h_exams)
	GameFlow.phase_summary_requested.connect(h_phase)
	GameFlow.game_over.connect(h_end)

	GameFlow.start_new_game(4242)
	t.ok(GameFlow.has_active_run(), "新游戏已开始")

	var steps := 0
	while steps < MAX_STEPS and cap["ending"].is_empty():
		steps += 1

		# 阶段总结：点击“继续”
		if not cap["phase"].is_empty():
			cap["phase"] = {}
			GameFlow.continue_after_phase_summary()
			continue

		# 考试：选第一个选项
		if not cap["exams"].is_empty():
			var exams: Array = cap["exams"]
			cap["exams"] = []
			var exam: Dictionary = exams[0]
			var exam_choices: Array = exam.get("choices", [])
			if exam_choices.is_empty():
				t.ok(false, "考试弹窗缺少选项")
				break
			GameFlow.take_exam(str(exam.get("id", "")), str(exam_choices[0].get("id", "")))
			continue

		# 事件：选第一个可选项
		if not cap["event"].is_empty():
			var view: Dictionary = cap["event"]
			cap["event"] = {}
			var event_choices: Array = view.get("choices", [])
			if event_choices.is_empty():
				t.ok(false, "事件弹窗缺少可选项")
				break
			GameFlow.choose_event_choice(str(event_choices[0].get("id", "")))
			continue

		var st: GameState = GameFlow.state
		if st == null:
			break
		if st.day > GameConfig.TOTAL_DAYS:
			break

		if st.slot >= 3:
			# 晚上：睡觉结束当天
			GameFlow.sleep_now()
			continue

		var before_day := st.day
		var before_slot := st.slot
		var acted := false
		for raw in GameFlow.available_actions():
			var action_id := str(raw)
			if action_id.is_empty():
				continue
			var def := ContentLoader.get_action(action_id)
			if def.is_empty():
				continue
			# 跳过不消耗时段的界面行动（商店等），避免空转
			if int(def.get("duration_slots", 1)) <= 0:
				continue
			var result := GameFlow.perform_action(action_id)
			if result.get("ok", false):
				acted = true
				break
		if not acted:
			GameFlow.idle_until_next_slot()

		# 安全阀：完全没有进展时强制推进，避免死循环
		if GameFlow.state != null \
			and GameFlow.state.day == before_day \
			and GameFlow.state.slot == before_slot \
			and cap["event"].is_empty() \
			and cap["phase"].is_empty() \
			and cap["exams"].is_empty() \
			and cap["ending"].is_empty():
			GameFlow.idle_until_next_slot()

	GameFlow.event_requested.disconnect(h_event)
	GameFlow.exam_requested.disconnect(h_exams)
	GameFlow.phase_summary_requested.disconnect(h_phase)
	GameFlow.game_over.disconnect(h_end)

	# ---- 断言 ----
	t.ok(steps < MAX_STEPS, "通关未卡死（共 %d 步，上限 %d）" % [steps, MAX_STEPS])
	t.ok(not cap["ending"].is_empty(), "完成 60 天并看到结局")
	if cap["ending"].is_empty():
		return
	var summary: Dictionary = cap["ending"]
	t.ok(str(summary.get("name", "")) != "", "结局有名称")
	t.ok(str(summary.get("description", "")) != "", "结局有描述")
	t.eq(int(summary.get("stats", {}).get("day", -1)), 60, "结局发生在第 60 天")
	t.ok(GameFlow.state != null and GameFlow.state.day == 60, "结局不会创建第 61 天")
	t.eq(int(GameFlow.state.phase), 4, "结束时处于第 4 阶段")
	# 第 15 节第 4 项：中途关闭后能从最近自动保存继续
	t.ok(SaveRepository.has_save(SaveRepository.AUTO_SLOT), "通关过程写入了自动存档")
	# 重新读取自动存档，确认状态可恢复并继续
	t.eq(GameFlow.load_game(SaveRepository.AUTO_SLOT), true, "自动存档可读取")
	if GameFlow.state != null:
		t.eq(int(GameFlow.state.day), 60, "读档后恢复到第 60 天")
		t.eq(int(GameFlow.state.phase), 4, "读档后恢复到第 4 阶段")
		t.ok(not GameFlow.state.unlocked_endings.is_empty(), "读档后保留已解锁结局")
