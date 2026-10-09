class_name TestSaveMigration
extends RefCounted

static func run(t) -> void:
	var state := GameState.new_run(2024, ContentLoader.characters)
	state.day = 17
	state.phase = GameConfig.phase_of_day(state.day)
	state.slot = 2
	state.player["money"] = 1234
	state.set_flag("test_flag", true)

	var slot := "test_migration_roundtrip"
	t.eq(SaveRepository.save(slot, state), true, "写入存档成功")
	t.eq(SaveRepository.has_save(slot), true, "存档文件存在")

	var loaded := SaveRepository.load_slot(slot)
	t.eq(loaded.get("ok", false), true, "读取存档成功")
	var restored: GameState = loaded["state"]
	t.eq(restored.day, 17, "天数一致")
	t.eq(restored.slot, 2, "时段一致")
	t.eq(int(restored.player["money"]), 1234, "现金一致")
	t.eq(bool(restored.get_flag("test_flag")), true, "flag 一致")

	# 序列化往返
	var round_trip := GameState.from_dict(state.to_dict())
	t.eq(int(round_trip.player["money"]), 1234, "序列化往返保留数据")

	# 高版本存档应被拒绝
	var future := {
		"schema_version": GameConfig.SCHEMA_VERSION + 5,
		"content_version": "future",
		"state": state.to_dict(),
	}
	var future_slot := "test_migration_future"
	var f := FileAccess.open(SaveRepository.SAVE_DIR + future_slot + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(future))
	f.close()
	var rejected := SaveRepository.load_slot(future_slot)
	t.eq(rejected.get("ok", false), false, "高版本存档被拒绝")

	# 清理
	SaveRepository.delete(slot)
	SaveRepository.delete(future_slot)
