extends Node
## 轻量测试运行器。用法：
##   godot --headless --path . res://tests/test_runner.tscn
## 退出码非 0 表示存在失败用例。

var passed := 0
var failed := 0
var failures: Array[String] = []

func _ready() -> void:
	print("=== 暑假工计划 · 自动测试 ===")
	_run(TestContentLoader, "ContentLoader")
	_run(TestScheduleSystem, "ScheduleSystem")
	_run(TestEventSystem, "EventSystem")
	_run(TestSaveMigration, "SaveMigration")
	_run(TestEndingSystem, "EndingSystem")
	_run(TestGuards, "Guards")
	_run(TestProgression, "Progression")
	print("---")
	print("通过 %d，失败 %d" % [passed, failed])
	for f in failures:
		print("  ✗ " + f)
	if failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)

func _run(test_class, label: String) -> void:
	print("\n[" + label + "]")
	var instance = test_class.new()
	instance.run(self)

# ---------------------------------------------------------------------------
# 断言 API（供测试类调用）
# ---------------------------------------------------------------------------

func ok(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("  ✓ " + message)
	else:
		failed += 1
		failures.append(message)
		print("  ✗ " + message)

func eq(actual, expected, message: String) -> void:
	ok(actual == expected, "%s（期望 %s，实际 %s）" % [message, str(expected), str(actual)])

func gte(actual: float, minimum: float, message: String) -> void:
	ok(actual >= minimum, "%s（≥%s，实际 %s）" % [message, str(minimum), str(actual)])
