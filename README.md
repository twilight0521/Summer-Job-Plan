# 暑假工计划

一个使用 Godot 4 制作的中文像素风人生模拟游戏。玩家将在 60 天暑假中安排工作、学习、休息和社交，在金钱、能力、健康与人际关系之间做出选择，最终走向不同的人生结局。

## 项目状态

当前版本为 MVP 原型，核心数据、领域系统、场景和测试框架已经纳入项目。当前版本补充了 1280×720 游戏视口、发呆消磨时段、过劳自动睡眠，以及阿凯 NPC 对话和街头机会内容，并提供 macOS、Windows、Android 三个平台的导出预设。内容采用 JSON 驱动，便于继续增加职业、事件、角色和结局。

## 核心玩法

- 60 天暑假，分为 4 个阶段，每天包含凌晨、早上、下午和晚上 4 个时段。
- 在工作、学习、锻炼、消费、休息和社交之间安排时间。
- 管理现金、体力、健康、心情、饥饿、疲劳、能力和关系等状态。
- 通过随机事件、考试、工作风险和人物关系形成不同路线。
- 结算多个结局，并支持本地存档与继续游玩。
- 无目标时可以发呆消磨一个时段；体力或疲劳过低会自动进入睡眠流程。
- 在商业街与阿凯对话，发现临时工作机会和风险事件。

## 开始运行

1. 安装 Godot 4.7.x stable。
2. 在 Godot Project Manager 中导入本目录。
3. 打开 `project.godot`，运行项目主场景。

项目默认启动场景为 `scenes/boot/boot.tscn`，窗口逻辑分辨率为 1280×720。

## 发布给其他人（Windows / Android / macOS）

项目已包含三套导出预设：`macOS`、`Windows` 和 `Android`。首次导出前，在 Godot 编辑器中打开 `Editor > Manage Export Templates`，安装与当前编辑器完全一致的 `4.7.2.stable` 导出模板。

在项目根目录执行：

```bash
mkdir -p builds
godot --headless --path . --export-release "macOS" builds/暑假工计划.app
ditto -c -k --sequesterRsrc --keepParent builds/暑假工计划.app builds/暑假工计划-macOS.zip
godot --headless --path . --export-release "Windows" builds/暑假工计划.exe
godot --headless --path . --export-release "Android" builds/暑假工计划.apk
```

macOS 和 Windows 导出后可以分别压缩分发。当前 Android 预设默认生成可直接安装的 APK；如果要提交 Google Play，再将 `gradle/export_format` 改为 `aab`，并配置 Android keystore 签名。

未签名的 macOS 版本首次启动时，需要右键应用并选择“打开”；Windows 版本通常可直接运行。公开分发给大量用户时，建议配置 Apple Developer 签名/公证和 Windows 代码签名，减少系统安全警告。

## 运行测试

项目包含基于 GDScript 的测试场景，位于 `tests/test_runner.tscn`。使用 Godot 编辑器运行该场景即可执行测试；也可以使用 Godot 的无头模式运行测试场景：

```bash
godot --headless --path . --scene tests/test_runner.tscn
```

## 目录结构

```text
data/         游戏内容 JSON：职业、行动、事件、角色、物品、结局
scenes/       启动、标题、游戏和设置场景
scripts/app/  应用流程、输入和教程协调
scripts/domain/  日程、行动、工作、事件、考试、关系和结局规则
scripts/infrastructure/  内容加载、存档、随机数和条件判断
scripts/ui/   游戏界面与主题
tests/        内容加载、进度、事件、存档和结局测试
```

## 设计文档

- [产品需求文档](PRD.md)：玩法目标、用户、系统和 MVP 范围。
- [架构设计文档](ARCHITECTURE.md)：运行时分层、状态模型、结算管线和数据规范。
- [更新日志](CHANGELOG.md)：版本变更和后续计划。

## 开发约定

- 游戏规则集中在 `scripts/domain/`，界面层不直接修改持久化状态。
- 可扩展内容优先写入 `data/` 下的 JSON，而不是硬编码在 UI 中。
- Godot 导入缓存目录 `.godot/` 和 macOS 临时文件不会提交到 Git。

## 许可证

项目暂未发布正式开源许可证，代码和素材的使用范围以仓库维护者后续声明为准。
