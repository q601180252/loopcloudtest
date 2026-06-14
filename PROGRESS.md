# PROGRESS

## 当前状态

- 已安装本项目 AI 开发规则入口：`AGENTS.md`。
- 已保留通用规则来源文档：`docs/通用开发规则模板.md`。
- 当前固定信息：仓库 `q601180252/loopcloudtest`，默认分支 `main`，主 workspace `LoopWorkspace.xcworkspace`。
- 当前 LinX 添加流程自动化测试入口：`LoopUITests` scheme，真机 destination `id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F`，要求手机已安装 `com.libre.loopkit3.Loop`。

## 进展日志

### 2026-06-14 003 - 新增 LinX 添加流程真机自动化测试

- **任务**：为添加 CGM 选择 `MicroTech LinX` 的关键路径新增自动化测试。
- **核心交付**：
  1. `Loop/LoopUITests/LoopCGMSetupUITests.swift`：新增真机 UI 测试，直接启动手机上已安装的 `com.libre.loopkit3.Loop`，自动从状态页进入 `Settings`，点击 `Add CGM`，选择 `MicroTech LinX`，并确认不会停在 `Unable to Open CGM`，最终看到 LinX 设置页和输入框；如果当前已配置 CGM，会明确提示先移除当前 CGM。
  2. `Loop/Loop.xcodeproj/project.pbxproj`、`Loop/Loop.xcodeproj/xcshareddata/xcschemes/LoopUITests.xcscheme`：新增独立 `LoopUITests` 测试目标和纯测试 scheme，避免本机缺少 watchOS 平台时重新构建 Watch App。
  3. `Loop/Loop/View Controllers/StatusTableViewController.swift`、`Loop/Loop/Views/SettingsView.swift`、`MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`：补充测试用页面标识，不改变用户可见界面。
  4. `docs/工具与踩坑.md`：记录真机 UI 测试入口、Watch 平台限制和本次测试发现。
- **验证结果**：先运行同一 UI 测试确认失败点为缺少 `status.settings`；补齐标识和状态页返回逻辑后，`xcodebuild test -quiet -workspace LoopWorkspace.xcworkspace -scheme LoopUITests -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -disableAutomaticPackageResolution -only-testing:LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过，结果包 `Test-LoopUITests-2026.06.14_08-39-19-+0800.xcresult` 显示 `status=succeeded`、`testsCount=1`；`git diff --check` 已通过；`plutil -lint Loop/LoopUITests/Info.plist` 已通过；`xmllint --noout Loop/Loop.xcodeproj/xcshareddata/xcschemes/LoopUITests.xcscheme` 已通过；`xcodebuild -list -workspace LoopWorkspace.xcworkspace` 已确认 `LoopUITests` scheme 存在；正式 Watch 构建配置仍保留。
- **关键发现**：Xcode UI 测试启动后会恢复上次页面，本机曾停在“已输注胰岛素”详情页，因此测试需要先回到状态页；LinX 页面实际已打开，但 SwiftUI 文本标识在 UI 层级里不稳定，测试保留标识并同时使用可见文字兜底；如果 `LoopUITests` scheme 绑定 App 构建，本机缺少 watchOS 26.5 会在测试前失败，因此该 scheme 只构建测试包，测试时启动已安装 App。
- **commit hash**：未提交
- **push 状态**：未推送。

### 2026-06-14 002 - 修复 LinX 提示 Unable to Open CGM

- **任务**：修复在添加 CGM 时选择 `MicroTech LinX` 后提示 `Unable to Open CGM` 的问题。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`：移除 LinX 工程中错误的 Swift Package 版本 `LoopKit`/`LoopKitUI` 引用，改为引用主 App 已包含的 `LoopKit.framework`/`LoopKitUI.framework`。
  2. `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`：将 LinX 目标最低 iOS 版本从 15.0 对齐到主工程的 15.1。
  3. `docs/工具与踩坑.md`：记录 `Unable to Open CGM` 的真实原因和验证方式。
- **验证结果**：`xcodebuild build -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -derivedDataPath /Users/liyang/Library/Developer/Xcode/DerivedData/LoopWorkspace-exnvvofyspxgrgfhgxypmjkymqtl` 已通过；主 App Debug 构建已通过；最终 `Loop.app` 内 `MicroTechCGMPlugin.framework` 和 `MicroTechCGMUI.framework` 已确认引用 `LoopKit.framework`/`LoopKitUI.framework`，不再引用 `LoopKitUI_D1D06EAA165FD69_PackageProduct.framework`；已覆盖安装并启动 `com.libre.loopkit3.Loop`；进程 5 秒后仍存在；`git diff --check` 已通过；临时 Watch 构建改动已恢复。
- **commit hash**：未提交
- **push 状态**：未推送。

### 2026-06-14 001 - 修复 Settings 中选择 LinX 后无反应

- **任务**：修复在 `Settings` 中添加 CGM，选择 `MicroTech LinX` 后看不到后续页面的问题。
- **核心交付**：
  1. `Loop/Loop/Extensions/UIViewController.swift`：关闭当前页面或上层页面承载的弹窗后，再弹出目标页面。
  2. `Loop/Loop/View Controllers/StatusTableViewController.swift`：添加 CGM、打开现有 CGM、打开 Pump 设置时改为弹出页面；CGM 打开失败时在手机上显示错误提示。
  3. `Loop/LoopTests/LoopTests.swift`：补充当前页面和上层页面两种弹出顺序回归测试。
  4. `docs/工具与踩坑.md`：记录本次页面遮挡问题和本机 Watch 测试阻断。
- **验证结果**：`xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme Loop -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -disableAutomaticPackageResolution` 已通过；安装包内确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`，插件显示名为 `MicroTech LinX`；已覆盖安装并启动 `com.libre.loopkit3.Loop`；进程 5 秒后仍存在；`git diff --check` 已通过；`Loop/Loop.xcodeproj/project.pbxproj` 临时 Watch 构建改动已恢复。`LoopTests` 受本机 Watch 目标构建问题阻断，未执行到测试断言。
- **关键发现**：手机上存在多个显示名为 `Loop` 的 App，本次安装和启动目标为 `com.libre.loopkit3.Loop`。
- **commit hash**：未提交
- **push 状态**：未推送。

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
