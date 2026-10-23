# 暑假工计划

一个使用 Godot 4 制作的中文像素风人生模拟游戏。玩家将在 60 天暑假中安排工作、学习、休息和社交，在金钱、能力、健康与人际关系之间做出选择，最终走向不同的人生结局。

## 项目状态

当前版本为 MVP 原型，核心数据、领域系统、场景和测试框架已经纳入项目，并提供 macOS、Windows、Android 三个平台的导出预设。内容采用 JSON 驱动，便于继续增加职业、事件、角色和结局。

最近一轮（2026-10-23）以稳定性和内容正确性为主，不含新玩法：

- 睡眠恢复量加下限，修掉高睡眠债时「越熬夜越睡不回来」的死循环。
- NPC 剧情事件绑定角色常驻地点，不再在无关地点弹出。
- 营业时间区间改为左闭右开，凌晨班次不再误占早上时段。
- 内容加载新增字段校验，`effects` / 条件里拼错的字段会在启动时报错，而不是静默写成 flag。
- 存档写入改为「备份 → 替换 → 清理」，失败可还原；读档不再残留上一局的推进意图。
- 界面刷新改为先摘出再释放，消除同帧新旧节点共存导致的重复显示与焦点错乱。

自动化测试现为 139 条用例（新增回归与全流程通关测试），全部通过。

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

无需安装 Godot 的玩家可以直接前往 [GitHub Releases](https://github.com/twilight0521/Summer-Job-Plan/releases/latest) 下载 Windows、macOS 或 Android 安装包。

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

### 上传新版本到 GitHub

`builds/` 已在忽略规则内，构建产物不进仓库，只作为 Release 附件上传：

1. 先确认测试通过：`godot --headless --path . --scene tests/test_runner.tscn`（当前 139 条用例，应全绿）。
2. 更新 `CHANGELOG.md`，按 `git add -A && git commit -m "release: vX.Y.Z" && git push origin main` 提交源码。
3. 打标签并推送：`git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`。
4. 打开仓库 Releases 页面，基于该标签新建 Release，上传 `builds/` 下的 `暑假工计划-Windows.zip`、`暑假工计划-macOS.dmg`、`暑假工计划.apk`，发布说明直接复制 CHANGELOG 对应条目。

> 已发布的 `v0.1.0` 构建产物早于 2026-10-23 的修复，仓库源码比下载包新。要让玩家拿到这些修复，需要按上述步骤重新导出并发布新的版本号。

## 运行测试

项目包含基于 GDScript 的测试场景，位于 `tests/test_runner.tscn`，当前共 139 条用例，覆盖内容加载、日程、事件、存档迁移、结局、边界条件、回归问题和一次完整 60 天通关。使用 Godot 编辑器运行该场景即可执行测试；也可以使用 Godot 的无头模式运行测试场景：

```bash
godot --headless --path . --scene tests/test_runner.tscn
```

测试通过时以退出码 0 结束，失败会打印失败用例并以非 0 退出，可直接用于 CI。测试运行在独立的 `user://test_saves/` 目录，不会覆盖玩家真实的 `auto.json` 和 `profile.json`。

`tests/test_regressions.gd` 逐条锁定历史修复点（睡眠恢复下限、NPC 事件地点、营业时间区间、字段校验、存档备份等），`tests/test_playthrough.gd` 走 `GameFlow` 全链路跑到第 60 天，防止流程级回归。

## 目录结构

```text
data/         游戏内容 JSON：职业、行动、事件、角色、物品、结局
scenes/       启动、标题、游戏和设置场景
scripts/app/  应用流程、输入和教程协调
scripts/domain/  日程、行动、工作、事件、考试、关系和结局规则
scripts/infrastructure/  内容加载、存档、随机数和条件判断
scripts/ui/   游戏界面与主题
tests/        内容加载、进度、事件、存档、结局、回归与全流程通关测试
```

## 设计文档

- [产品需求文档](PRD.md)：玩法目标、用户、系统和 MVP 范围。
- [架构设计文档](ARCHITECTURE.md)：运行时分层、状态模型、结算管线和数据规范。
- [更新日志](CHANGELOG.md)：版本变更和后续计划。

## 开发约定

- 游戏规则集中在 `scripts/domain/`，界面层不直接修改持久化状态。
- 可扩展内容优先写入 `data/` 下的 JSON，而不是硬编码在 UI 中。
- Godot 导入缓存目录 `.godot/`、本地构建目录 `builds/`、编辑器与工具产生的本地目录和 macOS 临时文件不会提交到 Git。

## 许可证

项目暂未发布正式开源许可证，代码和素材的使用范围以仓库维护者后续声明为准。
