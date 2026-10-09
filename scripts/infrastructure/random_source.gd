extends Node
## 所有随机数的唯一来源，便于固定 seed 复现和测试。
## 领域系统不得直接调用 randi() / randf()。

var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _fixed: bool = false

func _ready() -> void:
	randomize_run()

func randomize_run() -> void:
	_seed = randi()
	_rng.seed = _seed
	_fixed = false

func use_seed(value: int) -> void:
	_seed = value
	_rng.seed = value
	_fixed = true

func get_seed() -> int:
	return _seed

func is_fixed() -> bool:
	return _fixed

func randf() -> float:
	return _rng.randf()

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)

func chance(probability: float) -> bool:
	return _rng.randf() < clampf(probability, 0.0, 1.0)

## 按权重抽取一个下标；权重 <=0 的项不会被抽中。
func weighted_pick(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += maxf(0.0, float(weights[i]))
		if roll <= acc:
			return i
	return weights.size() - 1

## 从 [{weight:..}, ...] 形式的字典数组中按 weight 抽取。
func weighted_pick_dict(items: Array) -> int:
	var weights: Array = []
	for it in items:
		weights.append(float(it.get("weight", 1.0)))
	return weighted_pick(weights)
