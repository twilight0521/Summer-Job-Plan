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
