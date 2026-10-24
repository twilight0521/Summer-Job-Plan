extends Node
## 全局静态配置：时间模型、资源上下限、初始数值。
## 不含任何运行时状态，只被其他系统读取。

const CONTENT_VERSION := "mvp-0.1"
const SCHEMA_VERSION := 1
const TOTAL_DAYS := 60
const PHASE_LENGTH := 15
const PHASE_COUNT := 4

# slot -> 该时段起始分钟（00:00 起算）
const SLOT_START_MINUTES := [180, 420, 720, 1080]
const SLOT_NAMES := ["凌晨", "早上", "下午", "晚上"]

# 早班入睡判定：前一天必须在此分钟前入睡
const EARLY_SLEEP_DEADLINE := 21 * 60 + 30
const LATE_SLEEP_DEADLINE := 22 * 60

# 经验与被动
const EXP_PER_ACTION := 1
const EXP_PER_JOB := 2
const ENERGY_CAP_BASE := 100
const ENERGY_CAP_MIN := 50
const SLEEP_DEBT_ENERGY_PENALTY := 10
const OVERSLEEP_DEBT_THRESHOLD := 3

# 父母奖励
const PARENT_ON_TIME_STREAK_REQUIRED := 5
const PARENT_ON_TIME_BONUS := 100
const PARENT_LOW_CASH := 50
const PARENT_ALLOWANCE := 80
const PARENT_HOSPITAL_COVER := 100

# 移动消耗少量行动力（不消耗时段）
const MOVE_ENERGY_COST := 2

# 考试只允许在阶段末参加
const PHASE_END_EXAM_DAYS := [14, 15, 29, 30, 44, 45, 59, 60]

# 随机事件：有候选时也要先过触发概率，避免可重复事件每次行动必弹。
# 行动自带 pool（闲逛 / NPC / 打工风险）略高；地点氛围池 / 全局池更低。
const EVENT_CHANCE_AMBIENT := 0.32
const EVENT_CHANCE_POOLED := 0.55
# 非 once 事件默认冷却天数（可用事件 JSON 的 cooldown_days 覆盖）。
const EVENT_REPEAT_COOLDOWN_DAYS := 2
const EVENT_LAST_DAY_PREFIX := "event_last_day_"

# 资源与属性上下限
const CLAMPS := {
	"money": [0, 999999],
	"energy": [0, 120],
	"mood": [0, 100],
	"hunger": [0, 100],
	"fatigue": [0, 100],
	"muscle": [0, 100],
	"health": [0, 100],
	"luck": [0, 100],
	"trust": [0, 100],
	"study": [0, 100],
	"math": [0, 100],
	"fitness": [0, 100],
	"communication": [0, 100],
	"skill": [0, 100],
	"responsibility": [0, 100],
	"sleep_debt": [0, 10],
	"exp": [0, 9999],
}

const PLAYER_INITIAL := {
	"money": 300,
	"energy": 100,
	"mood": 70,
	"hunger": 20,
	"fatigue": 0,
	"muscle": 30,
	"health": 100,
	"luck": 50,
	"trust": 50,
	"study": 40,
	"math": 35,
	"fitness": 35,
	"communication": 40,
	"skill": 35,
	"responsibility": 40,
	"sleep_debt": 0,
	"exp": 0,
}

# 每天结算时的自然衰减 / 增长
const DAILY_DRIFT := {
	"hunger": 12,
	"fatigue": 4,
	"energy": -8,
}

# 饥饿越高越要吃饭；超过软阈值后，行动/移动/日结的体力消耗加快。
# 饥饿 0–40：无额外消耗；100：最多 +60% 体力消耗。
const HUNGER_ENERGY_SOFT := 40.0
const HUNGER_ENERGY_EXTRA_MAX := 0.6

const ATTRIBUTE_FIELDS := [
	"study", "math", "fitness", "communication", "skill", "responsibility"
]

const RESOURCE_FIELDS := [
	"money", "energy", "mood", "hunger", "fatigue",
	"muscle", "health", "luck", "trust"
]

# 显示用中文名、图标与悬停说明（图标为占位字符，后续可替换为像素图）
const FIELD_META := {
	"money": {
		"name": "现金", "icon": "¥",
		"tip": "买东西、交通和娱乐都靠它；部分事件和工作也有现金门槛。",
	},
	"energy": {
		"name": "体力", "icon": "⚡",
		"tip": "行动会消耗体力；过低时工作效率下降，也可能错过机会。",
	},
	"mood": {
		"name": "心情", "icon": "☺",
		"tip": "影响行动结果和事件选项；休息、社交和娱乐可以恢复。",
	},
	"hunger": {
		"name": "饥饿", "icon": "🍚",
		"tip": "数值越高越饿。饿了要吃饭，否则行动体力消耗会加快。",
	},
	"fatigue": {
		"name": "疲劳", "icon": "💤",
		"tip": "影响起床、工作效率与受伤概率；睡觉可以恢复。",
	},
	"muscle": {
		"name": "肌肉度", "icon": "💪",
		"tip": "搬砖等重体力工作的安全门槛；锻炼和体力活可提升。",
	},
	"health": {
		"name": "健康", "icon": "❤",
		"tip": "受伤、生病和长期熬夜会降低；过低会限制可做的事。",
	},
	"luck": {
		"name": "幸运", "icon": "🍀",
		"tip": "影响随机捡钱和好机会的概率；投机或欺骗可能降低它。",
	},
	"trust": {
		"name": "信任", "icon": "🤝",
		"tip": "影响父母、老板和街区人物是否愿意帮你；口碑结局也看它。",
	},
	"study": {
		"name": "学习", "icon": "📖",
		"tip": "影响升学、证书和家长期待类结果；图书馆自习可提升。",
	},
	"math": {
		"name": "数学", "icon": "➗",
		"tip": "会计考试与会计助理路线的核心属性；图书馆可专项练习。",
	},
	"fitness": {
		"name": "体能", "icon": "🏃",
		"tip": "影响搬运、外卖、工地等体力工作；锻炼可提升。",
	},
	"communication": {
		"name": "沟通", "icon": "💬",
		"tip": "影响服务业收入和 NPC 关系；打工与社交都能练到。",
	},
	"skill": {
		"name": "技能", "icon": "🔧",
		"tip": "影响维修、剪辑、编程等高收益工作；动手与专项练习可提升。",
	},
	"responsibility": {
		"name": "责任感", "icon": "📌",
		"tip": "影响连续出勤、合同和家庭事件；守时与扛事会涨。",
	},
	"exp": {
		"name": "经验", "icon": "✦",
		"tip": "阶段结算时用于解锁被动能力；工作与行动都会积累。",
	},
}

func field_tip(field: String) -> String:
	var meta: Dictionary = FIELD_META.get(field, {})
	return str(meta.get("tip", ""))

func clamp_field(field: String, value: float) -> float:
	if CLAMPS.has(field):
		var bounds: Array = CLAMPS[field]
		return clampf(value, float(bounds[0]), float(bounds[1]))
	return value

## 饥饿 → 体力消耗倍率。饥饿越高越饿，同样行动掉更多体力。
func hunger_energy_multiplier(hunger: float) -> float:
	var span := 100.0 - HUNGER_ENERGY_SOFT
	if span <= 0.0:
		return 1.0
	var t := clampf((float(hunger) - HUNGER_ENERGY_SOFT) / span, 0.0, 1.0)
	return 1.0 + t * HUNGER_ENERGY_EXTRA_MAX

## 把基础体力消耗（正数表示要扣多少）按当前饥饿放大。
func scale_energy_cost(base_cost: float, hunger: float) -> float:
	var base := absf(float(base_cost))
	if base <= 0.0:
		return 0.0
	var mult := hunger_energy_multiplier(hunger)
	if mult <= 1.0:
		return base
	return float(ceili(base * mult - 0.000001))

func hunger_energy_note(hunger: float) -> String:
	if float(hunger) < HUNGER_ENERGY_SOFT + 5.0:
		return ""
	if float(hunger) >= 90.0:
		return "你很饿，体力消耗明显加快。"
	if float(hunger) >= 70.0:
		return "肚子饿了，体力消耗加快。"
	return "有点饿，体力掉得稍快。"

func slot_name(slot: int) -> String:
	if slot >= 0 and slot < SLOT_NAMES.size():
		return SLOT_NAMES[slot]
	return "?"

func phase_of_day(day: int) -> int:
	return clampi(int(ceil(float(day) / float(PHASE_LENGTH))), 1, PHASE_COUNT)

func slot_minutes(slot: int) -> int:
	if slot >= 0 and slot < SLOT_START_MINUTES.size():
		return SLOT_START_MINUTES[slot]
	return 0

## 时段覆盖的分钟区间终点（左闭右开）：晚上时段一直延伸到 24:00。
func slot_end_minutes(slot: int) -> int:
	if slot < 0:
		return 0
	if slot >= SLOT_START_MINUTES.size() - 1:
		return 1440
	return SLOT_START_MINUTES[slot + 1]

func minutes_to_clock(minutes: int) -> String:
	var m := int(minutes) % 1440
	var h := m / 60
	var mm := m % 60
	return "%02d:%02d" % [h, mm]

func parse_clock(text: String) -> int:
	var parts := text.split(":")
	if parts.size() != 2:
		return 0
	return int(parts[0]) * 60 + int(parts[1])
