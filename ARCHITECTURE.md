# 《暑假工计划》架构设计与技术选型

> 基于 PRD v0.1 MVP（2026-09-22）
> 
> 目标：Windows 单机、30–60 分钟一局、60 天模拟、数据驱动、首发包 ≤50 MB。

## 1. 架构结论

采用 **Godot 4.x + GDScript + 纯本地数据驱动** 的单体游戏架构：

- 场景负责展示和输入，领域系统负责规则，数据文件负责内容。
- 运行时只有一个权威 `GameState`；行动通过命令进入结算管线，产生可回放的 `GameEvent`。
- 职业、行动、地点、随机事件、NPC、结局全部配置化，避免把内容写死在 UI 或大量 if/else 中。
- MVP 不引入后端、数据库、联网 SDK、ECS、复杂插件和第三方运行时。

### 推荐技术栈

| 层 | 选择 | 原因 |
|---|---|---|
| 引擎 | Godot 4.7.x stable 系列 | 2D、场景编辑、输入、音频、Windows 导出完整；体积和授权适合小型单机 |
| 语言 | GDScript | 与 Godot 场景/信号集成直接，MVP 迭代速度快 |
| UI | Godot Control 节点 + Theme | 面板、弹窗、键鼠操作和低分辨率布局足够 |
| 数据 | JSON（运行时）+ CSV（批量编辑可选） | 易读、易 diff、可由非程序成员维护 |
| 存档 | `user://saves/*.json` | 跨 Windows，调试方便，支持版本迁移 |
| 版本管理 | Git + LFS（仅大型源素材） | 文本配置可审查，像素资源可追踪 |
| 自动化校验 | Godot headless + GDScript 校验脚本 | 启动时和 CI 中检查数据引用、条件和数值范围 |
| 打包 | Godot Windows Desktop 导出 | 先交付 Windows；不依赖平台专属 API |

Godot 官方文档支持基于逻辑分辨率的缩放和整数缩放，适合本项目像素画面；截至 PRD 日期，官方归档中的 4.7.2 为 stable，4.8 仍为开发版，因此项目应锁定一个 4.7.x stable 小版本，不跟随开发版升级。

## 2. 运行时分层

```
Presentation
  Title / HUD / Map / Location / Event / Summary / Ending / Settings
        │ signals + view models
Application
  GameFlow  SaveCoordinator  InputRouter  TutorialCoordinator
        │ commands / results
Domain
  Schedule  Action  Job  Event  Exam  Relationship  Ending
        │ reads/writes
State
  GameState  DayState  PlayerState  NPCState  Flags  History
        │
Infrastructure
  ContentLoader  SaveRepository  RandomSource  AudioService  Logger
```

### 依赖规则

1. `UI -> Application -> Domain -> State` 单向依赖。
2. Domain 不直接访问节点、场景树、`Input` 或文件系统。
3. ContentLoader 在启动时把 JSON 转成已校验的配置对象。
4. SaveSystem 只保存状态和必要历史，不保存 Node、纹理或场景引用。
5. 所有随机数通过 `RandomSource` 注入，调试和复现时可固定 seed。

## 3. Godot 目录建议

```
res://
  project.godot
  scenes/
    boot/boot.tscn
    title/title.tscn
    game/game.tscn
    locations/location_view.tscn
    event/event_view.tscn
    summary/stage_summary.tscn
    ending/ending_view.tscn
  scripts/
    app/
      game_flow.gd
      input_router.gd
      tutorial_coordinator.gd
    domain/
      game_state.gd
      schedule_system.gd
      action_system.gd
      job_system.gd
      event_system.gd
      exam_system.gd
      ending_system.gd
      relationship_system.gd
    infrastructure/
      content_loader.gd
      save_repository.gd
      random_source.gd
      audio_service.gd
    ui/
      hud_controller.gd
      action_panel.gd
      event_dialog.gd
      stat_change_toast.gd
  data/
    locations.json
    actions.json
    jobs.json
    events.json
    characters.json
    endings.json
    exams.json
    items.json
  art/
  audio/
  tests/
    test_content_loader.gd
    test_schedule_system.gd
    test_event_system.gd
    test_save_migration.gd
```

## 4. 核心状态模型

只允许 `GameState` 改变可持久化状态，系统返回变更结果，不直接让 UI 改数值。

```gdscript
class_name GameState
extends RefCounted

var schema_version: int = 1
var run_id: String
var seed: int
var day: int = 1                 # 1..60
var slot: int = 0                # 0..3: 凌晨/早上/下午/晚上
var phase: int = 1               # ceil(day / 15)
var location_id: String = "home"
var player: Dictionary
var npcs: Dictionary
var flags: Dictionary
var history: Array[Dictionary]   # 只保留结局回放所需摘要
var unlocked_endings: Array[String]
var meta: Dictionary             # 教程完成、设置、统计，不影响本局规则
```

资源和属性统一约束：

- 现金：下限 0；健康、体力、心情、信任、幸运等按配置分别 clamp。
- 属性：0–100。
- 每次结算都生成 `ChangeSet`：`{field, before, delta, after, reason}`。
- 资源变化先在临时副本上计算，通过校验后一次性提交，避免 UI 中途扣资源导致半结算。

## 5. 一天的结算管线

```
玩家点击行动
  -> ActionSystem.validate()
  -> 生成 ActionContext 快照
  -> ActionSystem.preview()        # UI 展示成本/风险
  -> 玩家确认
  -> ActionSystem.commit()
  -> Job/Exam/Relationship 等规则结算
  -> EventSystem.resolve()
  -> ChangeSet + EventResult + LogEntry
  -> SaveRepository.save_auto()
  -> 进入下一个时段
```

关键接口：

```gdscript
func preview_action(action_id: String, state: GameState) -> ActionPreview
func commit_action(action_id: String, state: GameState) -> ActionResult
func resolve_event(event_id: String, choice_id: String, state: GameState) -> EventResult
func advance_slot(state: GameState) -> AdvanceResult
func evaluate_endings(state: GameState) -> Array[String]
```

行动必须幂等保护：每次行动生成 `action_instance_id`，保存成功后才允许推进；重复点击不会重复发钱。

## 6. 时间模型的统一口径

PRD 的核心循环明确为每天 4 个时段，因此架构采用 4 段：

| slot | 名称 | 默认时间 |
|---:|---|---|
| 0 | 凌晨 | 03:00–07:00 |
| 1 | 早上 | 07:00–12:00 |
| 2 | 下午 | 12:00–18:00 |
| 3 | 晚上 | 18:00–24:00 |

“3 个时段”只保留为 Milestone 0 的简化原型方案；进入 MVP 前统一为 4 个。工作营业时间用分钟区间判断，不直接依赖 slot，避免早餐店 03:00–07:00 这类边界问题。

每天结束流程：

1. 处理饥饿、疲劳、连续出勤和睡眠标记。
2. 检查阶段事件（15/30/45/60 天）。
3. 写自动档。
4. `day += 1, slot = 0`；第 60 天进入 Ending，不再创建第 61 天。

## 7. 数据驱动规范

### 7.1 通用条件表达式

MVP 支持：

```json
{"all":[
  {"field":"player.health","op":"gte","value":50},
  {"field":"day","op":"between","value":[3,59]},
  {"flag":"math_exam_unlocked","op":"eq","value":true}
]}
```

支持 `all`、`any`、`not`、`gte`、`lte`、`eq`、`between`、`in`、`has_tag`。条件解释器只读状态，不产生副作用。

字段路径在加载期校验：`player.*` 必须是 `GameConfig.CLAMPS` 里的字段，`npcs.<id>.*` 只允许 `relationship`/`trust`，`computed.*` 只允许已实现的派生项。拼错的路径不会静默取 0，而是直接报内容错误。

### 7.2 Action / Job / Event / Ending

```json
{
  "id": "tea_shop_shift",
  "type": "job",
  "location_id": "tea_shop",
  "available_minutes": [600, 1320],
  "duration_slots": 1,
  "requires": {"all":[{"field":"player.health","op":"gte","value":50}]},
  "cost": {"energy": 20, "hunger": 8},
  "effects": {"money": 80, "communication": 1},
  "risk_event_pool": ["job_customer_01"]
}
```

`available_minutes` 是左闭右开区间，判定时使用当前时段的**起点分钟**：`from <= now < to`。因此 `[180, 420]` 只覆盖凌晨（03:00），不会把 07:00 的早上时段算进去。

事件的 `time` 区间语义不同：只要**时段区间与事件时间窗有重叠**就可能触发（事件发生在时段内的某一刻），否则 `22:00–24:00` 这类深夜窗口在“时段起点”判定下永远匹配不上。比较用 `slot_from < to and from < slot_to`。

考试的体力成本写在 `exams.json` 的 `cost` 里，由 `ExamSystem.commit` 在真正作答时结算；`take_exam` 行动入口只做门槛判断与弹窗，不预扣成本，取消考试不产生消耗。

`effects` / `cost` 里的键必须是已知玩家字段，或带 `flags.` / `npcs.` 前缀；未知键会在加载期报错，避免拼错后静默写成 flag。

事件没有显式 `location` 时，若带 `npc` 字段则绑定到该角色在 `characters.json` 里声明的 `location`，避免剧情在无关地点弹出。

事件结果只允许声明式 effect：

```json
{"effects":[
  {"path":"player.money","op":"add","value":30},
  {"path":"player.mood","op":"add","value":3},
  {"path":"flags.wallet_returned","op":"set","value":true},
  {"path":"npcs/mom/relationship","op":"add","value":2}
]}
```

禁止在 JSON 中写脚本代码。特殊规则（考试评分、骨折分级、连续早班）由领域系统实现，并由配置传入参数。

### 7.3 数据校验

启动时和开发构建时执行：

- ID 唯一、引用存在、文件字段完整。
- 条件字段路径可解析。
- 资源、属性、关系变化不超过允许范围。
- 职业营业时间和地点存在。
- 结局之间没有明显互斥配置错误。
- 事件可达性抽样：至少能从新游戏走到每个 MVP 结局的前置条件。

## 8. 存档设计

存档槽位：

- `manual_1.json`–`manual_3.json`
- `auto.json`
- `backup.json`（写入前保留上一份自动档）

保存时采用临时文件 + rename，避免进程中断造成半文件。格式：

```json
{
  "schema_version": 1,
  "content_version": "mvp-0.1",
  "saved_at": "2026-09-22T12:00:00Z",
  "state": { "...": "GameState 序列化内容" }
}
```

`SaveMigrator` 按版本逐步迁移；遇到更高版本存档时显示“需要更新游戏”，不静默覆盖。

## 9. 场景和 UI 设计

- `Boot`：加载配置、校验数据、读取设置，进入标题。
- `Game`：持有当前 run 的应用控制器；内部切换 HUD、地点和事件面板。
- 地图/地点不单独创建一套规则状态，只发送 `select_location` 和 `select_action` 命令。
- 采用单一 Theme、少量可复用组件：`StatBar`、`ActionButton`、`DialogBox`、`ChangeToast`、`ConditionHint`。
- 输入统一走 `InputRouter`：鼠标点击和键盘快捷键映射到同一命令；Tab/方向键移动焦点，Enter 确认，Esc 返回。

像素显示建议：逻辑分辨率先定为 320×180；窗口允许整数倍缩放，关闭纹理过滤；重要文本和 UI 用 Control 布局，避免直接按屏幕像素硬编码。

## 10. 测试策略

### 自动测试（必须）

- 时间：跨 slot、跨天、15/30/45/60 天边界。
- 资源：上下限、负数保护、过劳、饥饿和健康联动。
- 条件：`all/any/not`、营业时间、前置事件和隐藏标签。
- 随机：固定 seed 时结果可复现；权重为 0 的事件不抽取。
- 存档：保存/读取一致；v1 -> v2 迁移；损坏档回退 backup。
- 内容：所有工作、事件、NPC、结局引用完整。

### 人工试玩指标

记录首次有效决策时间、首次卡住位置、第一次理解行动成本的时间、30 天前是否出现一次明显取舍、60 天完成率。5 人试玩结果作为平衡调整依据，不把试玩观察硬编码成规则。

## 11. 里程碑拆解

### M0：可玩骨架（1 周）

- 4 slot 时间模型、GameState、3 个行动、自动档。
- 一个地点、奶茶店工作、休息、跨天。
- 一个可配置事件和一个结局。
- 先完成内容校验脚本。

### M1：内容 MVP（2–3 周）

- 5 个职业、6 个 NPC、数据表和事件解释器。
- 5 个场景、HUD、事件弹窗、阶段总结、7 个结局。
- 手动档、迁移框架、键盘完整流程。

### M2：打磨和发布候选（1–2 周）

- 数值平衡、文本和音效、无障碍输入。
- 分辨率、窗口、存档损坏和安装包测试。
- Windows 导出、启动时间和体积检查。

## 12. PRD 决策项

1. **时段**：MVP 采用 4 个；M0 的三时段仅作为临时原型。
2. **事件数量**：验收口径以“20 普通 + 18 NPC + 12 街头 + 5 隐藏”为准；“40+”视为粗略描述。
3. **场景命名**：将“学校”统一映射为图书馆/银行办公楼等可玩的地点，避免制作不可交互的学校场景。
4. **行动力**：PRD 同时使用“每天 4 点行动力”和“4 个时段”。架构将两者分离：slot 是时间推进单位，energy/action_points 是资源；MVP 默认每 slot 至多一次主行动，特殊行动可配置消耗多个点。
5. **内容作者工作流**：先用 JSON，字段稳定后再提供 CSV 导入脚本；不要让 CSV 成为运行时唯一格式。
6. **长线解锁**：MVP 只保存结局解锁和统计，不做跨周目属性继承。

## 13. 不建议引入的技术

- Unity/Unreal：对 2D 小体量项目会增加包体、工程复杂度和迭代成本。
- SQLite：当前没有查询复杂度，JSON 更容易调试和迁移。
- ECS：内容规模和实体数量不足以抵消复杂度。
- 云存档、账号、联网分析：与单机 MVP 目标冲突。
- 复杂行为树：NPC 只需要关系值、阶段事件和关键选择。

