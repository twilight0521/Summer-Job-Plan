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

const ATTRIBUTE_FIELDS := [
	"study", "math", "fitness", "communication", "skill", "responsibility"
]

const RESOURCE_FIELDS := [
	"money", "energy", "mood", "hunger", "fatigue",
	"muscle", "health", "luck", "trust"
]

# 显示用中文名与图标（图标为占位字符，后续可替换为像素图）
const FIELD_META := {
	"money": {"name": "现金", "icon": "¥"},
	"energy": {"name": "体力", "icon": "⚡"},
	"mood": {"name": "心情", "icon": "☺"},
	"hunger": {"name": "饥饿", "icon": "🍚"},
	"fatigue": {"name": "疲劳", "icon": "💤"},
	"muscle": {"name": "肌肉度", "icon": "💪"},
	"health": {"name": "健康", "icon": "❤"},
	"luck": {"name": "幸运", "icon": "🍀"},
	"trust": {"name": "信任", "icon": "🤝"},
	"study": {"name": "学习", "icon": "📖"},
	"math": {"name": "数学", "icon": "➗"},
	"fitness": {"name": "体能", "icon": "🏃"},
	"communication": {"name": "沟通", "icon": "💬"},
	"skill": {"name": "技能", "icon": "🔧"},
	"responsibility": {"name": "责任感", "icon": "📌"},
	"exp": {"name": "经验", "icon": "✦"},
}

func clamp_field(field: String, value: float) -> float:
	if CLAMPS.has(field):
		var bounds: Array = CLAMPS[field]
		return clampf(value, float(bounds[0]), float(bounds[1]))
	return value

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
