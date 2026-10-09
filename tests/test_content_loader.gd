class_name TestContentLoader
extends RefCounted

static func run(t) -> void:
	t.eq(ContentLoader.loaded, true, "所有内容表加载并校验通过")
	t.gte(ContentLoader.locations.size(), 9, "地点数量 ≥9")
	t.gte(ContentLoader.jobs.size(), 5, "职业数量 ≥5")
	t.gte(ContentLoader.characters.size(), 6, "NPC 数量 ≥6")
	t.gte(ContentLoader.get_endings().size(), 7, "结局数量 ≥7")
	t.gte(ContentLoader.actions.size(), 12, "普通行动数量 ≥12")
	t.gte(ContentLoader.all_passives().size(), 5, "被动能力数量 ≥5")

	var counts := {"normal": 0, "npc": 0, "street": 0, "hidden": 0}
	for event in ContentLoader.all_events():
		var cat := str(event.get("category", ""))
		if counts.has(cat):
			counts[cat] += 1
	t.gte(counts["normal"], 20, "普通事件 ≥20")
	t.gte(counts["npc"], 18, "NPC 事件 ≥18")
	t.gte(counts["street"], 12, "街头事件 ≥12")
	t.gte(counts["hidden"], 5, "隐藏事件 ≥5")

	# 每个 NPC 至少 3 个阶段事件
	for npc_id in ContentLoader.characters:
		var cfg: Dictionary = ContentLoader.characters[npc_id]
		t.gte(cfg.get("stages", []).size(), 3, "NPC %s 阶段事件 ≥3" % npc_id)

	# 所有工作都有地点与工资
	for job_id in ContentLoader.jobs:
		var job: Dictionary = ContentLoader.jobs[job_id]
		t.ok(not str(job.get("location_id", "")).is_empty(), "工作 %s 有地点" % job_id)
		t.gte(float(job.get("wage", 0)), 1, "工作 %s 有工资" % job_id)
