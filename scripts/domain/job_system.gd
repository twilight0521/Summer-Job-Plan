class_name JobSystem
extends RefCounted
## 工作班次：前置条件、迟到、重体力硬干、受伤、连续出勤。

func extra_blockers(state: GameState, job_id: String) -> Array:
	var job: Dictionary = ContentLoader.get_job(job_id)
	var reasons: Array = []

	# 早班：没有按时入睡时，睡眠债过高直接禁止
	if job.has("early_shift"):
		var cfg: Dictionary = job["early_shift"]
		var flag_ok := bool(state.get_flag(str(cfg.get("required_flag", "early_sleep_ok"))))
		var debt := int(state.get_flag("sleep_debt"))
		if bool(state.get_flag("overslept")):
			reasons.append("连续熬夜，今天没能按时起床，错过了早班。")
		elif not flag_ok and debt > int(cfg.get("max_sleep_debt", 2)):
			reasons.append("连续熬夜，身体撑不住早班，必须先睡个好觉。")

	# 骨折锁定重体力
	if job_id == "construction_shift" and str(state.get_flag("injury")) == "fracture" and int(state.get_flag("injury_days")) > 0:
		reasons.append("你还在骨折恢复期，不能干重体力活。")

	return reasons

func preview_warnings(state: GameState, job_id: String) -> Array:
	var warnings: Array = []
	var job: Dictionary = ContentLoader.get_job(job_id)
	if job.has("hard_work"):
		var hw: Dictionary = job["hard_work"]
		var muscle := int(state.player.get("muscle", 0))
		var health := int(state.player.get("health", 0))
		if muscle < int(hw.get("muscle_threshold", 40)):
			if muscle < int(hw.get("forbid_muscle_below", 25)) or health < int(hw.get("forbid_health_below", 50)):
				warnings.append("肌肉度/健康过低，禁止硬干。")
			else:
				warnings.append("肌肉度不足，只能硬干：收入减半且可能受伤。")
	if job.has("early_shift"):
		var cfg: Dictionary = job["early_shift"]
		if not bool(state.get_flag(str(cfg.get("required_flag", "early_sleep_ok")))):
			warnings.append("睡眠不足：本班收入下降，健康受损。")
	return warnings

func commit(state: GameState, job_id: String) -> Dictionary:
	var job: Dictionary = ContentLoader.get_job(job_id)
	var result := {
		"ok": true,
		"action_id": job_id,
		"changes": [],
		"messages": [],
		"event_id": "",
		"event_pool": job.get("risk_event_pool", []).duplicate(),
		"end_day": false,
		"consume_slot": int(job.get("duration_slots", 1)) > 0,
		"open_shop": false,
		"special": "job",
	}

	var wage := float(job.get("wage", 0))
	var hard_work := false
	var forced_early := false

	# 早班睡眠不足：强行上班，收入下降
	if job.has("early_shift"):
		var cfg: Dictionary = job["early_shift"]
		if not bool(state.get_flag(str(cfg.get("required_flag", "early_sleep_ok")))):
			forced_early = true
			wage *= float(cfg.get("forced_wage_multiplier", 0.6))
			result.changes.append(state.add_player("health", -float(cfg.get("forced_health_cost", 5)), "睡眠不足"))
			result.changes.append(state.add_player("mood", -float(cfg.get("forced_mood_cost", 3)), "睡眠不足"))
			result.messages.append("你顶着黑眼圈上了班。")

	# 重体力：肌肉度不足则硬干
	if job.has("hard_work"):
		var hw: Dictionary = job["hard_work"]
		var muscle := int(state.player.get("muscle", 0))
		var health := int(state.player.get("health", 0))
		var threshold := int(hw.get("muscle_threshold", 40))
		if muscle < threshold:
			if muscle < int(hw.get("forbid_muscle_below", 25)) or health < int(hw.get("forbid_health_below", 50)):
				result.ok = false
				result.messages.append("身体条件不允许硬干，先去锻炼或休息。")
				return result
			hard_work = true
			wage *= float(hw.get("wage_multiplier", 0.5))
			result.messages.append("肌肉度不足，你只能硬干，收入减半。")

	# 消耗（体力按饥饿放大）
	var hunger := float(state.player.get("hunger", 0))
	result.changes.append_array(EffectResolver.apply_cost(state, job.get("cost", {}), "工作消耗"))
	var hunger_note := GameConfig.hunger_energy_note(hunger)
	if hunger_note != "" and job.get("cost", {}).has("energy"):
		result.messages.append(hunger_note)

	# 工资与收益
	var money_delta := int(round(wage))

	# 饥饿降低工作效率，并提醒该吃饭
	if hunger >= 90.0:
		money_delta = int(round(money_delta * 0.6))
		result.messages.append("你饿得发慌，效率很低，工资打折。该吃饭了。")
	elif hunger >= 70.0:
		money_delta = int(round(money_delta * 0.8))
		result.messages.append("空着肚子干活，效率不高。先填饱肚子会好一些。")

	# 被动：早起的鸟儿提升早班收入
	if job.has("early_shift") and state.has_passive("passive_early_bird"):
		money_delta = int(round(money_delta * 1.2))

	result.changes.append(state.add_player("money", money_delta, "工资"))
	result.changes.append_array(EffectResolver.apply_dict(state, job.get("effects", {}), "工作成长"))
	result.changes.append(state.add_player("exp", float(GameConfig.EXP_PER_JOB), "工作经验"))

	# 连续出勤与专属计数
	_track_attendance(state, job_id, result)

	# 硬干受伤判定
	if hard_work:
		_roll_injury(state, job["hard_work"], result)

	# 上班成功即视为按时起床
	if job.has("early_shift"):
		state.set_flag("early_sleep_ok", false)

	result.messages.append("完成班次，获得 ¥%d。" % money_delta)
	return result

func _track_attendance(state: GameState, job_id: String, result: Dictionary) -> void:
	var streak := int(state.get_flag("work_streak")) + 1
	state.set_flag("work_streak", streak)
	state.set_flag("work_days", int(state.get_flag("work_days")) + 1)
	state.set_flag("worked_today", true)
	var on_time := true
	var job := ContentLoader.get_job(job_id)
	if job.has("early_shift"):
		on_time = bool(state.get_flag(str(job["early_shift"].get("required_flag", "early_sleep_ok"))))
	state.set_flag("worked_on_time_today", on_time)

	match job_id:
		"accounting_shift":
			var done := int(state.get_flag("accounting_shifts_done")) + 1
			state.set_flag("accounting_shifts_done", done)
			result.messages.append("会计助理累计班次：%d/3。" % done)
		"tutor_shift":
			state.set_flag("tutor_shifts_done", int(state.get_flag("tutor_shifts_done")) + 1)
		"breakfast_shift":
			state.set_flag("breakfast_shifts_done", int(state.get_flag("breakfast_shifts_done")) + 1)

func _roll_injury(state: GameState, hard_work: Dictionary, result: Dictionary) -> void:
	var weights: Dictionary = hard_work.get("injury_weights", {"sore": 40, "sprain": 20, "fracture": 6})
	var keys: Array = ["sore", "sprain", "fracture"]
	var w: Array = []
	for k in keys:
		var weight := float(weights.get(k, 0))
		if bool(state.get_flag("has_protective_gear")):
			weight *= 0.5 if k != "fracture" else 0.3
		if state.has_passive("passive_tough_body"):
			weight *= 0.4
		w.append(weight)
	var idx := RandomSource.weighted_pick(w)
	if idx < 0:
		return
	var kind: String = keys[idx]
	match kind:
		"sore":
			result.changes.append(state.add_player("health", -3, "肌肉酸痛"))
			result.changes.append(state.add_player("fatigue", 8, "肌肉酸痛"))
			result.messages.append("你全身酸痛。")
		"sprain":
			state.set_flag("injury", "sprain")
			state.set_flag("injury_days", 2)
			result.changes.append(state.add_player("health", -8, "扭伤"))
			result.messages.append("你扭伤了，需要休息两天。")
		"fracture":
			state.set_flag("injury", "fracture")
			state.set_flag("injury_days", 5)
			state.set_flag("hospitalized", true)
			result.changes.append(state.add_player("health", -18, "骨折"))
			result.changes.append(state.add_player("money", -200, "医疗费"))
			result.changes.append(state.add_player("mood", -6, "骨折"))
			result.messages.append("你骨折了，医药费 ¥200，重体力活暂时不能干了。")
