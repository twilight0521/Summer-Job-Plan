class_name TestEventSystem
extends RefCounted

static func run(t) -> void:
	var state := GameState.new_run(999, ContentLoader.characters)
	var events := EventSystem.new()

	# 条件筛选：钱包事件在商业街时段外不应可选
	state.location_id = "commercial_street"
	state.slot = 2
	var wallet := ContentLoader.get_event("street_01")
	t.eq(events.is_eligible(state, wallet), true, "捡到钱包在商业街可选")

	state.location_id = "home"
	t.eq(events.is_eligible(state, wallet), false, "捡到钱包在家不可选")

	# once 事件触发后不再可选
	state.location_id = "commercial_street"
	events.resolve(state, wallet, "a")
	t.eq(bool(state.get_flag("event_fired_street_01")), true, "事件触发标记写入")
	t.eq(events.is_eligible(state, wallet), false, "once 事件不会重复触发")

	# 固定 seed 下抽取可复现
	RandomSource.use_seed(42)
	var pick_a := events.pick_event(state, ["street_02", "street_03", "street_05"])
	RandomSource.use_seed(42)
	var pick_b := events.pick_event(state, ["street_02", "street_03", "street_05"])
	t.eq(str(pick_a.get("id", "")), str(pick_b.get("id", "")), "固定 seed 抽取结果可复现")

	# 选项结算产生 ChangeSet 且信任值变化
	var before_trust := int(state.player.get("trust", 0))
	var beggar := ContentLoader.get_event("street_02")
	events.resolve(state, beggar, "b")
	t.ok(int(state.player.get("trust", 0)) != before_trust, "助人事件改变信任值")

	# 阿凯的发财诱惑会按幸运与关系值展示不同风险分支。
	var fortune := ContentLoader.get_event("npc_akai_04")
	var lucky_state := GameState.new_run(1001, ContentLoader.characters)
	lucky_state.day = 21
	lucky_state.phase = 2
	lucky_state.player["luck"] = 70
	lucky_state.npcs["akai"]["relationship"] = 40
	var lucky_choices: Array = events.present(lucky_state, fortune).get("choices", [])
	var lucky_ids: Array = []
	for choice in lucky_choices:
		lucky_ids.append(str(choice.get("id", "")))
	t.ok(lucky_ids.has("a") and lucky_ids.has("b") and not lucky_ids.has("c"), "高幸运或高信任展示可靠发财分支")
	var lucky_result := events.resolve(lucky_state, fortune, "a")
	t.eq(lucky_result.get("ok", false), true, "可靠发财分支可结算")
	t.eq(bool(lucky_state.get_flag("heard_insider_tip")), true, "可靠发财分支记录标记")

	var risky_state := GameState.new_run(1002, ContentLoader.characters)
	risky_state.day = 21
	risky_state.phase = 2
	risky_state.player["luck"] = 20
	risky_state.npcs["akai"]["relationship"] = 40
	var risky_choices: Array = events.present(risky_state, fortune).get("choices", [])
	var risky_ids: Array = []
	for choice in risky_choices:
		risky_ids.append(str(choice.get("id", "")))
	t.ok(risky_ids.has("b") and risky_ids.has("c") and not risky_ids.has("a"), "低幸运低信任展示高风险分支")
	var risky_result := events.resolve(risky_state, fortune, "c")
	t.eq(risky_result.get("ok", false), true, "高风险分支可结算")
	t.eq(bool(risky_state.get_flag("fell_for_overseas_scam")), true, "高风险分支记录骗局标记")

	# 负现金选项不能在余额不足时被当作免费选择。
	state.day = 3
	state.player["money"] = 0
	var collision := ContentLoader.get_event("street_04")
	var unaffordable := events.resolve(state, collision, "b")
	t.eq(unaffordable.get("ok", false), false, "现金不足时事件付费选项被拒绝")

	# 权重为 0 的事件不被抽取
	var zero := {"id": "z", "weight": 0, "category": "normal"}
	var idx := RandomSource.weighted_pick([0, 5, 0])
	t.ok(idx == 1, "权重为 0 的项不被抽取")
