# PROGRESS

## 当前状态

- 已安装本项目 AI 开发规则入口：`AGENTS.md`。
- 已保留通用规则来源文档：`docs/通用开发规则模板.md`。
- 当前固定信息：仓库 `q601180252/loopcloudtest`，默认分支 `main`，主 workspace `LoopWorkspace.xcworkspace`。
- 测试入口尚未固定；涉及代码或构建改动时，需要按当前任务确认 scheme 与 destination。

## 进展日志

### 2026-06-13 004 - 接入微泰 LinX CGM

- **任务**：把微泰 LinX CGM 作为新的 CGM 来源接入 Loop。
- **核心交付**：
  1. `MicroTechCGM/`：新增 MicroTech 核心框架、UI 框架、`.loopplugin` 插件和测试。
  2. LinX/Aidex BLE 连接链路：服务与特征常量、CRC、AES-CFB、key 派生、命令生成、握手、通知解析、实时读数转换。
  3. `MicroTechCGMManager`：状态保存、读数去重、Loop glucose sample 输出、上传开关、删除和重连扫描入口。
  4. MicroTech 设置界面与插件入口：`MicroTech LinX` 显示名、插件 metadata、setup/settings/status highlight。
  5. `LoopWorkspace.xcworkspace`：加入 `MicroTechCGM.xcodeproj`，主 `LoopWorkspace` scheme 加入 `MicroTechCGMPlugin.loopplugin`。
- **验证结果**：
  - `git diff --check` 已通过。
  - `xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17'` 已通过，42 个测试 0 失败。
  - `xcodebuild build -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 已通过。
  - `xmllint --noout LoopWorkspace.xcworkspace/contents.xcworkspacedata LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme` 已通过。
  - `xcodebuild -workspace LoopWorkspace.xcworkspace -list` 已显示 `Shared (MicroTechCGM project)`。
  - `xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme LoopWorkspace -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 在构建前停止，原因是本机缺少 `watchOS 26.5`，未进入 MicroTech 编译阶段。
- **commit hash**：`a954bd5`（LoopWorkspace 集成），`75984e5`（Task 8 测试补齐）；完整实现见 `microtech-linx-cgm` 分支提交历史。
- **push 状态**：已推送到 `origin/microtech-linx-cgm`。

### 2026-06-12 003 - 编写微泰 LinX CGM 实现计划

- **任务**：在设计文档确认后，编写微泰 LinX CGM 接入的可执行实现计划。
- **核心交付**：
  1. `docs/superpowers/plans/2026-06-12-microtech-linx-cgm.md`：微泰 LinX CGM 实现计划。
- **验证结果**：`git diff --check` 已通过；计划文档已检查无未定项。
- **commit hash**：`5fe63f8`
- **push 状态**：已随本轮推送到 `origin/main`。

### 2026-06-12 002 - 设计微泰 LinX CGM 接入

- **任务**：观察 Loop 现有 CGM 插件接入方式，并结合 `aoji` 中 LinX/Aidex BLE 连接方式，形成微泰 LinX CGM 完整 BLE 直连接入设计。
- **核心交付**：
  1. `docs/superpowers/specs/2026-06-12-microtech-linx-cgm-design.md`：微泰 LinX CGM 接入设计。
- **验证结果**：`git diff --check` 已通过；设计文档已检查无未定项。
- **commit hash**：`673447a`
- **push 状态**：已随本轮推送到 `origin/main`。

### 2026-06-12 001 - 安装通用开发规则

- **任务**：读取 `docs/通用开发规则模板.md`，将规则适配为本项目开发要求。
- **核心交付**：
  1. `AGENTS.md`：本项目 AI 协作、开发、验证、提交规则。
  2. `PROGRESS.md`：倒序进展日志入口。
  3. `docs/通用开发规则模板.md`：保留通用规则来源。
- **验证结果**：`git diff --check` 已通过；`AGENTS.md` 与 `PROGRESS.md` 已读取确认。
- **commit hash**：89a7387
- **push 状态**：已随本轮推送到 `origin/main`。
