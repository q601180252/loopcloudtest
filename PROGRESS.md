# PROGRESS

## 当前状态

- 已安装本项目 AI 开发规则入口：`AGENTS.md`。
- 已保留通用规则来源文档：`docs/通用开发规则模板.md`。
- 当前固定信息：仓库 `q601180252/loopcloudtest`，默认分支 `main`，主 workspace `LoopWorkspace.xcworkspace`。
- 当前已实现首页通用血糖历史页面：任意 CGM 已配置时显示入口，支持 `6 Hours / 12 Hours / 24 Hours`，共用 Loop `GlucoseStore` 的实际血糖曲线和倒序明细，默认显示最近 6 小时；当前手机未配置 CGM，配置后的真机页面验收待完成。
- 当前 LinX 和血糖历史真机自动化入口为 `LoopUITests` scheme，要求手机已安装 `com.libre.loopkit3.Loop`；Xcode destination 使用 `xcrun xctrace list devices` 查询，`devicectl` 设备标识使用 `xcrun devicectl list devices` 查询，不混用两类标识。
- 当前完整插件 Debug 包已使用 `LoopWorkspace` scheme 构建并安装，包内已确认包含 `NightscoutRemoteCGMPlugin`、`NightscoutRemoteCGM` 和 `MicroTechCGMPlugin`；禁止使用 `Loop` scheme 生成真机安装包。
- 当前 LinX 接入复验结果：`MicroTechCGM` 单元测试 193 个通过；首次添加、扫描、连接、恢复、GATT、握手、完整密钥和完整数据包已写入同一设备日志并可随 Loop Report 导出；最新完整 App 已安装到 iPhone XR 并启动，20 秒后进程仍存在；LinX 已从 `disconnecting -> timeout` 循环恢复，最终包安装后 11:20 到 11:26 连续写入当前血糖，状态文件显示最新 sample=888、84 mg/dL、时间 2026-06-18 11:27:44+08:00；最终包安装后连接超时为 0；0x04 状态包已降级为 receive 日志，不再作为错误。
- 当前 MicroTech LinX 新添加流程固定使用直接连接；添加页不再显示 `直接连接 / 广播数据` 选择，点击搜索后只进入原有蓝牙直连流程。
- LinX 底层广播解析、状态兼容、诊断日志和测试仍保留，用于历史排障，但新添加页已没有广播入口。
- 当前已确认 LinX 重连采用单一 60 秒恢复周期：已完成过握手的直连 LinX 在 60 秒内未再次完成握手时，按顺序关闭旧蓝牙管理器、保留传感器配置、清除旧蓝牙标识并创建新管理器继续扫描；设计已确认，代码实现待完成。
- 最新 TestFlight 上传包 `Loop 3.9.1 (66)` 已完成 App Store Connect 处理并分发给内部测试人员，Actions run `30621494193` 显示 `Successfully finished processing the build 3.9.1 - 66 for IOS`；发布源提交为 `7ee9b15`，IPA 内包含 `MicroTechCGMPlugin`、`NightscoutRemoteCGMPlugin` 和 `NightscoutRemoteCGM`，签名与 watchOS `11.6` 兼容检查通过，`Loop.app` 最低 iOS 为 `15.1`。

## 进展日志

### 2026-08-03 043 - 明确 LinX 60 秒重连恢复设计

- **任务**：解决 LinX 断线后长期停留在 `peripheralDisconnecting`、持续发现设备却无法重新连接的问题。
- **核心交付**：
  1. 新增 `docs/superpowers/specs/2026-08-03-linx-60-second-reconnect-recovery-design.md`，明确使用一个连续的 60 秒恢复周期，不再按连续两次 30 秒失败判断。
  2. 只有已经完成过握手的直连 LinX 使用恢复周期；首次添加、广播兼容和其他 CGM 不受影响。
  3. 定义 `idle -> timing(id) -> shuttingDown(id) -> timing(newID)` 状态转换，关闭旧管理器期间禁止扫描、刷新或排队重试抢先创建新管理器。
  4. 明确旧蓝牙管理器关闭契约、旧管理器和旧传感器回调隔离、传感器配置与历史状态保留边界，以及可检索日志和测试标准。
- **验证结果**：设计经过三轮独立审查后通过；未修改代码的 `MicroTechCGMTests` 基线 193 项通过、0 失败；完整 `LoopWorkspace` 基线构建在本机因缺少未纳入仓库的 `LibreTransmitter/LibreTransmitter/NotificationHelperOverride.swift` 被阻断，未写成通过；`git diff --check` 通过。
- **决策结论**：从重连开始只计一个 60 秒周期，只有完成 LinX 握手才算成功；到期仍未成功时，先完成旧蓝牙管理器内部关闭，再创建新管理器按原传感器序列号继续扫描。
- **commit hash**：`fec0581`。
- **push 状态**：待推送到 `origin/main`。

### 2026-07-31 042 - 修改 LinX 添加流程固定直连

- **任务**：移除 LinX 添加页面的连接方式选择，使所有新添加的 LinX 固定进入直接连接流程。
- **核心交付**：
  1. 添加页删除 `直接连接 / 广播数据` 选择，只保留原有说明、搜索和取消操作。
  2. 添加流程改为无连接方式参数，并在开始扫描前显式设置为 `.direct`。
  3. 单元测试增加无参数添加动作和强制直连断言；真机 UI 自动化改为断言连接方式控件、`直接连接` 和 `广播数据` 均不存在，搜索按钮仍存在。
  4. 真机 UI 自动化发现已有 CGM 时明确失败，不再把打开现有 LinX 设置页当作新添加流程通过。
  5. 底层广播解析、状态兼容、诊断日志和既有测试保留，但不再提供新添加入口。
  6. 当前说明、排障文档和旧广播设计入口同步区分现行固定直连与历史广播记录。
- **验证结果**：新增 3 项固定直连测试通过；`MicroTechCGM` 全量 193 项通过、0 失败；`LoopWorkspace` 完整开发签名构建通过；安装包内 `MicroTechCGMPlugin`、`NightscoutRemoteCGMPlugin` 和 `NightscoutRemoteCGM` 均存在，完整签名检查通过；新版已安装并启动到 iPhone XR，20 秒后主程序仍在运行；移除原有 CGM 后，真机 UI 自动化 1 项通过，确认 LinX 添加页没有连接方式控件、`直接连接` 或 `广播数据`，且搜索按钮存在。测试没有开始扫描或保存新 CGM。
- **TestFlight**：`Loop 3.9.1 (66)` 已完成 App Store Connect 处理并分发给内部测试人员；Actions run `30621494193` 成功，发布源提交为 `7ee9b15`；下载的 IPA 包含 LinX 和 Nightscout 组件，完整签名及 watchOS `11.6` 兼容检查通过，SHA256 为 `81f79d46386870759461f3fdd91fdeb61e9ddecc69d0bfaf90dd8218b181a765`。
- **commit hash**：`7ee9b15`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 041 - 确认 LinX 添加流程固定直连设计

- **任务**：移除 LinX 添加页面的 `直接连接 / 广播数据` 选择，新添加的 LinX 统一使用直接连接。
- **核心交付**：
  1. 新增 `docs/superpowers/specs/2026-07-31-linx-direct-only-setup-design.md`，明确页面、连接行为、保留范围和验证标准。
  2. 确认底层广播解析、日志和测试暂时保留，但不再提供用户入口。
  3. TestFlight run `30617464818` 已在上传前取消，避免发布仍带模式选择的旧页面。
- **验证结果**：设计范围已确认；代码实现、完整测试、真机检查和重新发布待完成。
- **决策结论**：采用最小改动方案；不处理尚未发布的广播配置。
- **commit hash**：`305a158`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 040 - 整理血糖历史与 Nightscout 文档

- **任务**：整理本仓库定制功能、血糖历史页面状态和 Nightscout 完整插件构建说明，形成可重复使用的文档入口。
- **核心交付**：
  1. `README.md` 增加本仓库定制功能和文档导航，并明确完整 App 使用 `LoopWorkspace` scheme。
  2. 血糖历史设计和实施计划标明已完成内容，以及真实 CGM 真机页面验收仍待完成的边界。
  3. `docs/工具与踩坑.md` 增加快速导航和 Nightscout 完整构建、插件检查、签名、安装及启动命令。
  4. Nightscout 子项目 README 增加统一排障文档入口；可执行命令中的开发团队、设备标识和本机路径改为变量或仓库相对路径。
- **验证结果**：文档目标和相对链接已检查；`git diff --check` 通过。
- **commit hash**：`98c6600`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 039 - 新增通用血糖历史页面并修复完整插件安装

- **任务**：在 Loop 首页为任意已配置 CGM 增加血糖历史入口，支持查看最近 6、12、24 小时，并解决重新安装后添加 CGM 列表缺少 Nightscout 的问题。
- **核心交付**：
  1. 首页在任意 CGM 已配置时显示 `Glucose History` 入口，不限定 MicroTech LinX；CGM 切换后会自动刷新入口。
  2. 历史页直接读取 Loop `GlucoseStore`，支持 6、12、24 小时三种范围，显示实际血糖曲线和按时间倒序的明细，不显示预测线或模拟数据。
  3. 图表横轴按范围使用 1、2、4 小时间隔，并严格覆盖所选时间起止点；页面支持新血糖、前台恢复、错误重试和单位变化自动刷新。
  4. 历史页隐藏首页底部工具栏；真机自动检查使用当前范围专属完成标识，避免把旧范围结果误认为 24 小时结果。
  5. 真机安装流程改用 `LoopWorkspace` scheme，完整构建并携带 Nightscout、MicroTech 等 CGM 插件。
  6. `LoopKitTests` 补齐 `LoopKitUI` 依赖，全新 DerivedData 下图表测试不再依赖旧缓存。
- **验证结果**：全新 DerivedData 下 `ChartsManagerTests` 和 `PredictedGlucoseChartTests` 共 11 项通过、0 失败；历史数据模型、页面和首页入口共 19 项通过、0 失败；MicroTech 全量 191 项通过、0 失败；`LoopUITests` 真机测试包构建通过；`LoopWorkspace` 无签名完整构建和真机签名完整构建均通过；安装包内 `NightscoutRemoteCGMPlugin`、`NightscoutRemoteCGM` 和 `MicroTechCGMPlugin` 均存在，完整签名校验通过；新包已安装并启动到 iPhone XR，20 秒后进程仍存在。真机历史页自动检查未通过，失败点是当前手机没有配置 CGM，因此首页按设计不显示历史入口；未删除或替换用户设备配置。
- **关键发现**：此前使用 clean DerivedData 和 `Loop` scheme 构建时，只生成主 App，`Install Plugins` 不会补建 Nightscout 插件，导致添加 CGM 列表缺少 Nightscout；源码和插件注册并未删除。
- **决策结论**：所有真机安装和后续发布使用 `LoopWorkspace` scheme；配置任意 CGM 后均可从首页进入同一历史页。
- **commit hash**：`ebfa670` 至 `c3b429d`。
- **push 状态**：已推送到 `origin/main`，远端状态提交为 `e518b51`。

### 2026-07-31 038 - 编写首页血糖历史页面实施计划

- **任务**：把已确认的首页血糖历史页面设计整理成可直接执行和逐步验证的实施计划。
- **核心交付**：
  1. `docs/superpowers/plans/2026-07-31-glucose-history-page.md`：分为横轴与数据模型、历史页面、首页接入与交付三个审查块。
  2. 计划明确 6、12、24 小时范围、同源图表与明细、通知生命周期、错误重试、首页入口和真实 LinX 验收。
  3. 每项功能按先失败测试、最小实现、通过测试和独立提交拆分。
  4. 真机步骤区分 Xcode destination 与 `devicectl` 标识，并固定构建、安装、启动和 20 秒进程检查命令。
- **验证结果**：三个计划块均通过独立审查；每块少于 1000 行；无占位内容；`git diff --check` 通过。
- **决策结论**：执行阶段使用 `superpowers:subagent-driven-development`，逐任务实现并进行代码和设计两轮审查。
- **commit hash**：`b5170ba`
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 037 - 明确首页血糖历史页面设计

- **任务**：为 Loop 首页增加血糖历史入口，支持查看最近 6 小时、12 小时和 24 小时。
- **核心交付**：
  1. `docs/superpowers/specs/2026-07-31-glucose-history-page-design.md`：定义首页独立历史入口、三段时间选择、曲线、倒序明细、空状态、错误和自动刷新。
  2. 历史页面直接查询 Loop `GlucoseStore`，不在 MicroTech 插件中复制历史数据。
  3. MicroTech LinX 直接连接继续负责当前值和历史补包；历史页面只展示已经写入 Loop 的真实数据。
  4. 首页现有 Glucose 曲线点击行为和底部五个工具按钮保持不变。
- **验证结果**：独立设计审查通过；设计文档存在且关键内容可读；`git diff --check` 通过。
- **决策结论**：首页本身隐藏导航栏，因此采用状态区下方的独立历史入口；历史页默认 6 小时，支持 6、12、24 小时三个 Tab，上方曲线、下方明细。
- **commit hash**：`aaa6697`
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 036 - 修复 LinX 广播无效血糖入库

- **任务**：解决 LinX 广播已找到设备，但把 `value=255 quality=255` 当成血糖写入 Loop 的问题。
- **核心交付**：
  1. 使用 iPhone XR 设备日志中的真实广播包 `59000000010300FFFFFFFFFFFFFFFFFFFFFFED99C18B` 建立回归测试。
  2. 广播解析拒绝 `timeOffset < 7` 的未开始或预热数据。
  3. 广播解析明确拒绝 `0xFF` 血糖占位值，不再将其转换为 `255 mg/dL`。
  4. 设备名识别增加 `BWCGM-序列号`；真机有效广播可解析为 sample `21570`、血糖 `152`。
  5. 无 service 过滤扫描增加厂商标识 `0x0059` 的后置过滤，附近其它 BLE 设备不再进入 LinX 日志和解析。
  6. 无效广播不保存传感器、样本号或最新血糖，继续等待后续有效广播。
  7. 最新记录有效而后续历史位置为 `0xFF` 时保留最新值；读取旧版状态时清除已保存的预热或 `255 mg/dL` 占位血糖。
  8. 日志队列使用独立身份标记，避免 `flush` 偶发提前返回，保证广播诊断日志完整。
- **验证结果**：新增测试分别先因缺少预热判断、`BWCGM` 名称识别、厂商数据后置过滤、旧占位状态清理和后续 `0xFF` 处理而失败；修复后 `MicroTechCGM` 全量 191 个测试通过、0 失败；三项日志队列测试连续执行 10 轮通过；`git diff --check` 通过；`LoopWorkspace` generic iOS 构建通过；真机开发签名构建和签名校验通过；新包已安装并启动到 iPhone XR，20 秒后进程仍存在。完整扫描周期日志只有 started、timeout、fallback、stopped，没有附近其它 BLE 设备日志，也没有 `value=255` accepted。该周期目标设备未发出广播，因此有效值使用同一手机此前抓到的 `BWCGM` 真实包回归验证为 sample `21570`、血糖 `152`、quality `76`。
- **关键发现**：广播扫描和厂商数据字段解析均正常；首个问题是单字节 `0xFF` 转为 255 后落入原有 `40...400` 判断范围，同时缺少 Aidex 7 分钟就绪判断；第二个问题是有效 `BWCGM` 广播已解析但因设备名未识别而没有 serial；第三个问题是无过滤扫描把附近所有 BLE 设备写入 LinX 日志。
- **决策结论**：修复广播有效性、`BWCGM` 名称识别和无关设备过滤；保留已绑定序列号匹配，不自动切换到附近其它传感器，不修改未知 quality 规则。
- **commit hash**：`c26aac1`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 035 - 修复 LinX 广播扫描过滤问题

- **任务**：读取当前日志并分析“直连能搜索到 LinX，广播数据搜索不到”的原因。
- **核心交付**：
  1. 检查 `log/Export-20260730T001910Z` 中 7 个 `DeviceLog.json`，未发现 MicroTech、LinX、broadcast 或 scan 记录；该导出只包含 `LibreTransmitterManagerV3` / `MiaomiaoClient`，不是当前广播测试日志。
  2. 检查本地 6 月 Loop Report，确认这些是旧 LinX 直连日志，不包含新广播模式事件。
  3. 确认代码中广播扫描只使用 Aidex service UUID 过滤；如果 LinX 实时血糖广播只带厂商数据 `0x0059`、不带 service UUID，iOS 会在进入回调前过滤掉，表现为广播模式搜不到。
  4. 广播扫描新增 fallback：先用 Aidex service UUID 过滤扫描；若超时未发现，则记录 `stage=broadcast event=fallback reason=filteredTimeout`，停止过滤扫描，再用 `withServices: nil` 扫描，后续仍只由名称、identifier 和厂商数据判断是否接受。
- **验证结果**：新增 fallback 测试先失败，失败点为缺少广播扫描阶段、无过滤扫描参数和 fallback 日志；修复后广播相关 10 个测试通过；`MicroTechCGM` 全量测试两次均在旧日志队列测试出现时序波动，失败项单独和合并复跑通过；`LoopWorkspace` generic iOS 构建通过；`git diff --check` 通过。
- **关键发现**：当前本地没有这次真机问题的 Loop Report；根因判断来自现象与代码路径比对。
- **决策结论**：保留直连流程不变；广播模式增加一次无 service 过滤 fallback，解决只广播厂商数据的 LinX 包被系统过滤的问题。
- **commit hash**：`d553e3b`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 034 - 补齐 LinX 广播模式诊断日志

- **任务**：确认 LinX 广播方式日志是否齐全，并补齐会影响快速定位的问题。
- **核心交付**：
  1. 广播扫描停止和超时改为 `stage=broadcast event=stopped/timeout`，不再只显示普通扫描日志。
  2. 广播发现时按当前模式选择日志阶段；广播模式只写 `stage=broadcast event=found`，不再额外写 `stage=scan event=found`。
  3. 广播解析成功新增 `stage=broadcast event=parsed`。
  4. 广播解析失败日志补充 identifier、name、localName、peripheralName、RSSI 和广告内容。
  5. 广播 accepted 日志补充 identifier、name、RSSI、trend、status、records，并继续保留完整 rawHex。
- **验证结果**：新增日志测试先失败，失败点为缺少广播 timeout/stopped 日志和发现日志模式选择；修复后广播日志相关 9 个测试通过；`MicroTechCGM` 全量 182 个测试通过、0 失败；`LoopWorkspace` generic iOS 构建通过；`git diff --check` 通过。
- **关键发现**：修复前能看出是否 accepted/rejected，但不能快速区分“收到广播但解析成功后被过滤”和“广播扫描超时”；广播发现还会混入普通扫描日志。
- **决策结论**：广播问题排查按 `started -> found -> parsed -> accepted/rejected`，或 `started -> timeout/stopped` 判断。
- **commit hash**：`68aa2c4`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 033 - 新增 LinX 广播连接选择

- **任务**：修复添加 CGM 选择 `MicroTech LinX` 后没有 `直接连接 / 广播数据` 选择的问题，并接入广播模式读取最新血糖。
- **核心交付**：
  1. `MicroTechSetupView` 新增 `直接连接 / 广播数据` 分段选择，继续按钮会按所选方式开始添加。
  2. 直连方式保持原有连接流程；广播方式只扫描 Aidex 广播，不主动连接设备。
  3. 广播方式会解析厂商数据中的最新血糖，保存设备、序列号、最新 sample 和血糖值，并把新数据交给 Loop。
  4. 设置页新增 `Data Mode`，可看到当前是 `Direct Connection` 还是 `Broadcast Data`。
  5. `LoopCGMSetupUITests` 增加添加页选择项断言，防止后续再次丢失该控件。
- **验证结果**：新增广播模式测试 5 个通过；`MicroTechCGM` 全量测试首跑 179 个测试中 3 个日志队列时序测试失败，3 个失败项单独复跑通过；`LoopWorkspace` generic iOS 构建通过；Debug 真机签名构建通过；已安装并启动到 iPhone XR；真机 UI 自动化被 XCTest 自动化模式超时阻断，未跑到页面断言。
- **关键发现**：添加页之前只有搜索按钮，没有模式选择；广播模式需要在添加前保存选择，否则会继续走直连扫描。
- **决策结论**：采用同一个 `MicroTech LinX` 入口内选择模式的方案，不新增第二个 CGM 类型。
- **commit hash**：`3015e6f`、`cb59b42`、`71a931e`、`e2f3479`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-31 032 - 完成 LinX 广播数据模式实施计划

- **任务**：将已确认的 LinX 广播数据模式设计拆分为可执行、可验证的实施步骤。
- **核心交付**：
  1. `docs/superpowers/plans/2026-07-31-linx-broadcast-mode.md`：明确新增直连 / 广播数据选择、状态保存、广播 parser、独立广播扫描、广播入库、设置页显示、验证和提交顺序。
  2. 计划要求新增 `MicroTechAidexBroadcastParser`，并覆盖 CoreBluetooth 广播字典、完整 advertising payload、manufacturer payload、负数 trend、原始厂商 payload 保留和异常拒绝。
  3. 计划要求广播模式在 Bluetooth manager 初始化时加载已保存模式，并验证不会调用恢复外设、已连接外设、连接事件注册或 `connect`。
  4. 计划将广播相关测试拆到独立测试文件，避免继续扩大现有 `MicroTechCGMManagerTests.swift`。
  5. 计划包含 setup/settings 手工验证、真机 BLE 验证、push 重试和 `PROGRESS.md` commit hash / push 状态补写步骤。
- **验证结果**：计划文件存在且关键内容可读；三块计划审查均通过；`git diff --check` 通过。
- **决策结论**：按三块实施：状态与广播解析、广播扫描与入库、UI 与最终验证。
- **commit hash**：`965be30`。
- **push 状态**：已推送到 `origin/main`，远端 `refs/heads/main` 已核对为 `965be306657b33e949d26f5c4c6ffeb1df97d2da`。

### 2026-07-31 031 - 明确 LinX 广播数据模式设计

- **任务**：在添加 MicroTech LinX CGM 时增加“直接连接 / 广播数据”选择，并确认广播模式作为最新血糖来源的设计边界。
- **核心交付**：
  1. `docs/superpowers/specs/2026-07-31-linx-broadcast-mode-design.md`：定义首次添加时选择数据模式，直接连接保持现有完整 BLE 能力，广播数据只扫描广播并解析最新血糖。
  2. 明确广播解析使用 Aidex 厂商数据 `0x0059`，解析 `timeOffset/status/calTemp/trend/records`，第一条记录作为最新血糖。
  3. 明确新增 `connectionMode` 状态字段，旧状态默认恢复为直接连接。
  4. 明确广播模式不主动连接设备、不读取历史、不监听其它 App 的 BLE 连接数据。
- **验证结果**：文件存在且关键内容可读；`PROGRESS.md` 新条目可读；`git diff --check` 通过；规格复核首轮发现 6 个问题，已补齐独立广播扫描入口、独立广播入库路径、首次绑定 serial 来源、CoreBluetooth 广播解析入口、扫描过滤与超时行为、`timeOffset` 回绕规则，二轮复核通过。
- **决策结论**：采用“在 MicroTech LinX 添加页先选择模式”的方案；不新增第二个 CGM 类型，不做自动模式切换。
- **commit hash**：`9f02dca`、`5779b72`、`6f926e9`。
- **push 状态**：已推送到 `origin/main`。

### 2026-07-30 030 - 补齐 LinX 首次添加和完整连接日志

- **任务**：解决 LinX 首次添加失败后 Loop Report 缺少连接证据的问题，并补齐全运行周期的完整诊断日志。
- **核心交付**：
  1. 首次添加开始扫描前接入真实 `PersistentDeviceLog`，添加失败时也能在 `DeviceLog.json` 中看到扫描、连接和超时信息；正式 manager 接管后继续使用同一日志入口，不漏记也不重复。
  2. 扫描、连接、系统恢复、Bluetooth 状态、service、characteristic、notification、read、write 和 timeout 均记录稳定的 `stage`、`event` 与完整错误信息。
  3. 握手与通信持续记录完整设备 identifier、base key、pairing key、session key、IV、challenge、发送命令、加密包、解密包和解析失败原始数据，不脱敏、不截断。
  4. `docs/工具与踩坑.md` 已记录排查方法、真实测试入口和 Loop Report 的敏感信息限制。
  5. 最终审查发现并修复日志回调与状态读取互相等待、首次 Bluetooth 状态可能丢失、GATT 缓存和同步失败缺少稳定节点、日志流状态长期累积的问题；本轮新增测试中的真实设备序列号已替换为虚构值。
- **验证结果**：`MicroTechCGM` 全量 170 个测试通过、0 失败；串行日志关键测试独立运行 3 次均通过；`LoopTests` 的真实 `DeviceLog.json` 导出测试 1 个通过，确认包含 `stage=scan event=failed reason=timeout`；`LoopWorkspace` 使用 `generic/platform=iOS` 且 `CODE_SIGNING_ALLOWED=NO` 构建成功；最终规格与代码质量复核均通过；`git diff --check` 通过。
- **关键发现**：直接用 `LoopWorkspace` scheme 运行指定导出测试会被仓库现有 `OmniBLETests/Driver/Comm/message/MessagePacketTests.swift:52` 编译错误阻断，原因是 `RawSpan` 没有 `toHexString`；使用独立 `LoopTests` scheme、明确 Simulator id 和 `MAIN_APP_BUNDLE_IDENTIFIER` 后测试通过。
- **决策结论**：为满足本次问题分析要求，LinX 日志保留完整密钥和通信数据；Loop Report 只能交给可信分析人员，不得公开分享。
- **commit hash**：`ccac881`、`a9edde7`、`043d8dd`、`44c9031`、`03bdfe9`、`27bc79e`。
- **push 状态**：已推送到 `origin/main`；首次远端核对为 `4248da21f020bfee6065b1d641d10cdfe9060d31`。

### 2026-07-30 029 - 完成 LinX 完整连接日志实施计划

- **任务**：将已确认的 LinX 全连接日志设计拆分为可执行、可验证的开发步骤。
- **核心交付**：
  1. `docs/superpowers/plans/2026-07-30-linx-full-connection-logging.md`：明确首次添加日志写入真实 `DeviceLog.json` 的实现与测试顺序。
  2. 分别覆盖扫描、连接、恢复、Bluetooth 状态、service、characteristic、notification、read、write 和 timeout 的独立失败分支。
  3. 明确完整 key、IV、challenge、发送命令、加密接收包和解密包的记录与逐字测试。
  4. 明确正式 delegate 切换期间日志无缺失、无重复，以及文档、commit、push、`PROGRESS.md` 的真实状态记录顺序。
- **验证结果**：实施计划经过两轮复审并通过；文件存在且关键内容可读；`git diff --check` 和 staged diff check 通过。
- **决策结论**：按计划使用 TDD 分三部分实施；完成真实导出测试、全量 MicroTech 测试和 workspace 构建后才能判定完成。
- **commit hash**：`cede19f`。
- **push 状态**：已推送到 `origin/main`，远端 `refs/heads/main` 已核对为 `cede19f05154bf75f7d3fc502785a2b3071d9531`。

### 2026-07-30 028 - 明确 LinX 全连接日志设计

- **任务**：解决 LinX 首次添加失败时 Loop Report 没有扫描、连接和配对证据的问题，并明确全运行周期完整通信日志范围。
- **核心交付**：
  1. `docs/superpowers/specs/2026-07-30-linx-full-connection-logging-design.md`：定义首次添加独立日志入口，不提前安装临时 manager。
  2. 明确持续记录设备信息、基础 key、pairing key、challenge、session key、IV、完整发送包、完整加密接收包和完整解密包。
  3. 明确扫描、连接、service、characteristic、通知、读写、配对、解密、CRC 和解析失败的稳定日志字段。
  4. 要求使用真实 `PersistentDeviceLog` 导出 `DeviceLog.json` 做集成验证。
- **验证结果**：设计文档两轮审查后通过；文件存在且关键内容可读；`git diff --check` 和 staged diff check 通过。
- **关键发现**：首次添加 LinX 成功前 manager 没有正式 `CGMManagerDelegate`，现有扫描和配对信息不会进入 Loop Report；提前调用 `didCreateCGMManager` 会改变添加状态，因此采用独立 onboarding 日志入口。
- **决策结论**：LinX 全运行周期持续记录完整密钥和完整通信数据，不脱敏、不截断；Loop Report 只能交给可信分析人员。
- **commit hash**：`b54886c`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-29 027 - 确认 TestFlight Watch 发布处理通过

- **任务**：确认最新 TestFlight 包是否已经支持 Apple Watch Series 8、watchOS `11.6.2 (22U95)`。
- **核心交付**：
  1. 确认 GitHub Actions run `28347545488` 已成功完成，TestFlight 上传步骤等待 App Store Connect 处理并通过。
  2. 下载 run `28347545488` 的 `Loop.ipa` artifact，复验 Watch 兼容性和 `WatchKitSupport2/WK` 配对。
  3. 更新当前状态，避免继续引用旧的 `90484`、`90487`、`90589` 失败结果。
- **验证结果**：Actions 日志显示 `Skipping Watch app shell to preserve WatchKit WK pairing`、`Preserved top-level IPA entries: Payload Symbols WatchKitSupport2`、`Watch compatibility verified for /Users/runner/work/loopcloudtest/loopcloudtest/Loop.ipa`、`Successfully uploaded the new binary to App Store Connect`、`Successfully finished processing the build 3.9.1 - 64 for IOS`；`Scripts/verify_watchos_testflight_compatibility.sh /tmp/loopcloudtest-watch-final-28347545488/build-artifacts/artifacts/Loop.ipa 11.6` 通过；包内版本为 `3.9.1 (64)`；`Loop.app` 最低 iOS 为 `15.1`；`WatchApp.app` 和 `WatchApp Extension.appex` 最低 watchOS 均为 `9.0`；`WatchKitSupport2/WK` 与 `WatchApp.app/_WatchKitStub/WK` SHA256 均为 `5d3149a79cbdb2d2b785869e3079bba91499813fbe5ed110b317d60212857db0`；artifact IPA SHA256 为 `34b0881ba6972814f2e60f37cec9e32e91c719f7eadf4d7df1b684f411b800d9`。
- **关键发现**：App Store Connect 处理通过的是当前重新上传后的 `3.9.1 (64)`；此前同 build number 的 `90484`、`90487`、`90589` 邮件属于旧失败包。
- **commit hash**：`7c49b84`，对应已处理通过的 workflow head；`4be7060`，对应本次发布验证记录更新。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-29 026 - 避免处理 Watch app 壳导致 WK 不匹配

- **任务**：处理 App Store Connect 返回 `90487 Invalid WatchKit Support`，错误提示 `WK don’t match` 且要求不要 post-process Watch app 内的 `WK`。
- **核心交付**：
  1. `Scripts/patch_watchos_testflight_compatibility.sh`：跳过 `WatchApp.app` 主壳，不再修正其主二进制，只修正 `WatchApp Extension.appex` 和 extension 内的 watchOS framework。
  2. `Scripts/verify_watchos_testflight_compatibility.sh`：新增 `WatchKitSupport2/WK` 与 `WatchApp.app/_WatchKitStub/WK` 的 SHA256 一致性检查；兼容性 minos 检查同步跳过 Watch app 壳。
  3. `docs/工具与踩坑.md`：记录 `90487` 的原因和避免规则。
- **验证结果**：旧原始 IPA 经新脚本处理后输出 `Skipping Watch app shell to preserve WatchKit WK pairing`；修正后保留顶层 `Payload Symbols WatchKitSupport2`；`WatchKitSupport2/WK` 与 `WatchApp.app/_WatchKitStub/WK` SHA256 都是 `5d3149a79cbdb2d2b785869e3079bba91499813fbe5ed110b317d60212857db0`；`WatchApp Extension` 的 `arm64` slice 为 `minos 9.0`；`WatchApp` 主壳保持 `minos 26.0`；新验证脚本通过；`ruby -c fastlane/Fastfile` 通过；两个脚本 `bash -n` 通过；`git diff --check` 通过。
- **关键发现**：`WATCHOS_DEPLOYMENT_TARGET` 已是 `9.0`，但 Xcode 26 导出的 Watch arm64 slice 仍为 `minos 26.0`；App Store Connect 同时禁止处理 Watch app 壳内的 WatchKit `WK` 配对文件，因此本轮只处理 Watch extension 层。
- **commit hash**：`5567c4b`。
- **push 状态**：已推送到 `origin/main`；后续 run `28347545488` 已确认 TestFlight 上传和 App Store Connect 处理通过。

### 2026-06-29 025 - 修复 WatchKitSupport2 丢失导致的处理失败

- **任务**：处理 App Store Connect 返回 `90589 Invalid WatchKit Support` 和 `90484 WatchKitSupport2 folder is missing`，重新准备可处理通过的 TestFlight 包。
- **核心交付**：
  1. `Scripts/verify_watchos_testflight_compatibility.sh`：新增 `WatchKitSupport2/` 存在且非空检查，防止只验证 Watch 最低版本但漏掉 WatchKit 支持目录。
  2. `Scripts/patch_watchos_testflight_compatibility.sh`：重新压包时保留 Xcode 导出的所有 IPA 顶层目录，不再只压 `Payload/`，避免丢失 `WatchKitSupport2/` 和 `Symbols/`。
  3. `fastlane/Fastfile`：`upload_to_testflight` 改为等待 App Store Connect 处理结果，避免上传成功但处理失败时 workflow 误报成功。
  4. `docs/工具与踩坑.md`：记录 `90484`、`90589` 的直接原因和发布流程要求。
- **验证结果**：`Loop 3.9.1 (64)` artifact 用新验证脚本检查会失败，失败点为 `WatchKitSupport2 folder missing from IPA`；上一版原始 IPA 先因 Watch `arm64` slice `minos=26.0 > 11.6` 失败，复制后执行 `WATCHOS_COMPAT_CODESIGN_IDENTITY='-' Scripts/patch_watchos_testflight_compatibility.sh ... 9.0`，输出 `Preserved top-level IPA entries: Payload Symbols WatchKitSupport2`，随后新验证脚本通过；`ruby -c fastlane/Fastfile` 通过；两个脚本 `bash -n` 通过；`git diff --check` 通过。
- **关键发现**：`28345506128` 的 TestFlight 上传步骤成功只代表包已上传，不能代表 App Store Connect 后续处理通过；本次必须等处理完成后再判定发布成功。
- **commit hash**：`e759d5d`。
- **push 状态**：已推送到 `origin/main`；后续 App Store Connect 返回 `90487`，需继续修正。

### 2026-06-29 024 - 修正 TestFlight Watch 包兼容性

- **任务**：处理 TestFlight 版本无法安装到 Apple Watch Series 8、watchOS `11.6.2 (22U95)` 的问题，并重新准备兼容包发布流程。
- **核心交付**：
  1. `Scripts/patch_watchos_testflight_compatibility.sh`：导出 IPA 后修正 Watch 相关 `arm64` slice 的 watchOS 最低版本标记，并重新签名嵌套 Watch 内容和主 App。
  2. `Scripts/verify_watchos_testflight_compatibility.sh`：验证 IPA 内 `WatchApp.app`、`WatchApp Extension.appex` 存在，检查 Watch 二进制最低系统不高于 `watchOS 11.6`，并执行深度签名校验。
  3. `fastlane/Fastfile`：`build_loop` 在 `gym` 后自动执行 Watch 兼容性修正和验证，再进入 artifact 保存与 TestFlight 上传流程；脚本调用使用 `GITHUB_WORKSPACE` 计算绝对路径，并通过 `bash` 执行，避免受 fastlane 当前目录影响。
  4. `docs/工具与踩坑.md`：记录 TestFlight Watch 安装失败的包内原因、处理方式和后续避免规则。
- **验证结果**：旧 TestFlight IPA 先用 `Scripts/verify_watchos_testflight_compatibility.sh /tmp/loopcloudtest-watch-check/build-artifacts/artifacts/Loop.ipa 11.6` 验证失败，失败点为 `WatchApp`、`WatchApp Extension`、`LoopCore.framework`、`LoopKit.framework` 的 `arm64` slice 都是 `minos=26.0 > 11.6`；对 IPA 副本执行 `WATCHOS_COMPAT_CODESIGN_IDENTITY='-' Scripts/patch_watchos_testflight_compatibility.sh ... 9.0` 后，验证脚本通过，`codesign --verify --deep --strict` 通过，`WatchApp Extension` 的 `arm64` slice 显示 `minos 9.0`；`ruby -c fastlane/Fastfile` 通过；两个脚本 `bash -n` 通过；GitHub Actions run `28344391069` 已确认 IPA 原始导出成功，但因 `Scripts/patch_watchos_testflight_compatibility.sh` 缺少 `./` 前缀导致 fastlane 找不到脚本；run `28345016900` 已确认 `./Scripts/...` 仍受 fastlane 当前目录影响；run `28345506128` 已通过 `Build Loop`、Watch 兼容性修正、Watch 兼容性验证、TestFlight 上传和 artifact 上传。
- **发布包**：TestFlight 已上传 `Loop 3.9.1 (64)`；artifact IPA SHA256 为 `879e10071ff73eb5f53193ef044b13aa62aa77b444e8c9e3d284ce995b2babd1`；包内 `Loop.app` 最低 iOS 为 `15.1`，`WatchApp.app` 和 `WatchApp Extension.appex` 最低 watchOS 为 `9.0`；Watch `arm64` slice 的 `LC_BUILD_VERSION` 已显示 `minos 9.0`。
- **关键发现**：TestFlight 上传要求 Watch 包保留 `arm64`，不能简单回退到只含 `arm64_32`；本次修正保留 `arm64`，只修正其最低系统标记并重新签名。
- **commit hash**：`b2c17f1`、`e534656`、`39d0653`、`91f7b09`。
- **push 状态**：已推送到 `origin/main`；TestFlight 发布 workflow 已完成。

### 2026-06-18 023 - 修复 LinX disconnecting 重连循环和 0x04 误报并重新安装

- **任务**：继续确认 LinX 长连 CGM 状态，修复真机日志中反复出现的 `disconnecting -> connect timed out` 循环，并处理 0x04 状态包被误记为错误的问题。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：发现 `.disconnecting` 外设时不再占用当前连接名额、不再启动连接超时，主动取消旧连接后继续扫描；保存设备恢复和已连接设备取回只有在真正可连接时才停止扫描流程。
  2. `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`：LinX 0x04 状态包按可忽略包处理，只记录 receive 日志，不再上报为血糖错误。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`、`MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`：新增 `.disconnecting` 不占用连接、0x04 不产生错误的回归测试。
  4. `build/ipa/Loop-3.9.1-57-20260618-084646.ipa`：已导出的开发签名 IPA。
- **验证结果**：`.disconnecting` 相关测试先因缺少 `shouldClaimPeripheralForConnection` 和新日志接口失败，修复后目标测试通过；0x04 状态包测试先失败，失败点为仍被当成 `unsupportedPacket(4)` 错误，修复后目标测试 2 个通过；`MicroTechCGM` 全量测试 109 个通过、0 失败；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `65f1dae1aac109ac29426298a6fa28b95d517f930e71de52d0c095c3e5ecadd8`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-084646.ipa`；已启动 `com.libre.loopkit3.Loop`；20 秒后主进程仍存在，进程号为 `1344`。
- **真机 LinX 日志**：最终包安装后状态仍为 `MicroTechLinXCGMManager`，设备 `AiDEX X-22222DKCZE`，传感器序列号 `22222DKCZE`；11:20 到 11:26 连续写入当前血糖，sample 881 到 887；状态文件显示 11:27:44 已更新到 sample 888、84 mg/dL；最终包安装后 `connect timed out` 数量为 0；0x04 包记录为 `receive MicroTech LinX ignored unsupported packet type 0x04`，未再出现 `unsupportedPacket(4)` 错误。
- **关键发现**：本轮真机证据证明 LinX 已从连接超时循环恢复，当前连接、握手、解密、解析、入库都在持续工作；本轮未做锁屏过夜测试，因此过夜级后台保活仍需要后续长时间 Loop Report 证明。
- **commit hash**：`b544011`。
- **push 状态**：已随本轮推送到 `origin/main`。

### 2026-06-18 022 - 修复 LinX 配置阶段静默卡住保护并重新安装

- **任务**：真机已可用后，继续确认 LinX 长连 CGM 状态，修复 `didConnect` 后配置阶段可能静默卡住的问题，并重新打包安装验证。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：配置阶段新增独立超时保护；重复进入配置会写出明确日志；配置超时会断开当前设备、上报错误并重新扫描；旧连接的迟到失败回调不再覆盖当前连接状态。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：配置超时会计入保存蓝牙标识失败，连续失败后回退为按传感器序列号搜索附近设备。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增配置超时时长、配置进度日志、配置超时回退附近设备搜索等回归测试。
  4. `build/ipa/Loop-3.9.1-57-20260618-060210.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增测试先因缺少 `configureTimeout`、配置超时时长和配置日志接口失败；修复后目标测试 4 个通过；`MicroTechCGM` 全量测试 107 个通过、0 失败；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `7c1967945ad8390f502ebd26d6e40eea82ade030dc302c49123c4bb2dfafcffa`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-060210.ipa`；已启动 `com.libre.loopkit3.Loop`；20 秒后主进程仍存在，进程号为 `1101`。
- **真机 LinX 日志**：当前配置仍是 `MicroTechLinXCGMManager`，设备为 `AiDEX X-22222DKCZE`，传感器序列号 `22222DKCZE`；安装前已存在一笔 91 mg/dL，时间为 2026-06-18 04:32，本次安装后没有新血糖；06:55 到 06:57 的新日志显示已恢复保存设备并扫描，但最终是 `connect timed out` 和 `scan timed out`，最近发现设备的 RSSI 约为 `-94`。
- **关键发现**：配置阶段静默卡住保护已补齐，当前包能安装启动且不会启动即崩溃；真机仍未证明 LinX 已达到成熟长连标准，因为本轮没有产生新血糖，最新阻断点是蓝牙连接/扫描超时。
- **commit hash**：`0e76b5c`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 021 - 补齐 LinX 后台恢复来源日志并重新安装

- **任务**：继续检查 LinX 长连 CGM 证据，补齐保存设备恢复连接的日志来源，方便后续 Loop Report 判断是真正的系统后台恢复，还是普通保存设备取回。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：保存设备恢复日志现在会明确写出来源，分别为 `CoreBluetooth restore` 和 `retrievePeripherals`。
  2. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增 `testSavedPeripheralLogMessageIdentifiesCoreBluetoothRestoreSource`，锁定后台恢复来源日志不能丢。
  3. `build/ipa/Loop-3.9.1-57-20260618-051045.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增测试先因缺少恢复来源日志接口失败；修复后该测试通过；`MicroTechCGM` 全量测试 104 个通过、0 失败；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `a471e145c3b3d33422986d316eabf68968df7c926754d60a75ba0f585ce3ca35`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-051045.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在，进程号为 `1051`。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 针对最新包执行 2 次，均没有返回页面断言；第一次 11 分钟未结束后手动终止，第二次带 120/180 秒超时仍未由 Xcode 返回，手动终止；两次期间 iPhone 上 `Loop` 主进程一直存在，卡住的是 UI 测试 Runner。结果包为 `build/test-results/LinxUI-20260618-051045.xcresult` 和 `build/test-results/LinxUI-20260618-051045-timeout.xcresult`。
- **关键发现**：当前包已能安装启动，日志可以区分后台恢复来源；真机 UI 自动化本轮卡在测试 Runner，不是 `Unable to Open CGM` 或 App 启动崩溃。成熟长连标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑 Loop Report 证明。
- **commit hash**：`e8159f9`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 020 - 修复 LinX 历史补包同步写入并重新安装

- **任务**：继续检查 LinX 是否已达到成熟长连 CGM 标准，补齐当前代码层最明显的连接稳定性风险，并在可用 iPhone 上重新安装验证。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`：历史补包请求不再直接同步写入 F002，而是复用已有命令调度队列，避免在当前蓝牙通知调用链里等待底层写入响应。
  2. `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`：新增 `testHistoryRequestIsScheduledOutsideNotificationCallback`，锁定历史补包请求必须离开当前调用栈后才写入。
  3. `build/ipa/Loop-3.9.1-57-20260618-044120.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增测试先失败，失败点为历史请求已直接写入；修复后该测试通过；相关历史补包测试 2 个通过；`MicroTechCGM` 全量测试 103 个通过、0 失败；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `7cc63b1d98b6c7f6a77f9119127c2797d798575bd48fb5d662a862821f00e518`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-044120.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在，进程号为 `1033`。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 针对最新包重试 2 次，均未进入页面断言，失败点为 iPhone 自动化模式启用超时：`Timed out while enabling automation mode`；结果包为 `build/test-results/LinxUI-20260618-044120.xcresult` 和 `build/test-results/LinxUI-20260618-044120-retry.xcresult`。
- **关键发现**：代码层历史补包同步写入风险已修复；当前 iPhone 可安装启动，但最新包的真机 UI 自动化受手机自动化模式阻断；成熟长连标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑 Loop Report 证明。
- **commit hash**：`926a815`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 019 - 补齐 LinX 入库日志标识并重新安装

- **任务**：确认 LinX 长连链路当前证据是否足够，并补齐后续 Loop Report 快速判断 LinX 是否把血糖写入 Loop 的日志。
- **核心交付**：
  1. `Loop/Loop/Managers/DeviceDataManager.swift`：CGM 血糖写入成功或失败时，日志会记录 `manager=MicroTechLinXCGMManager`、请求样本数、实际写入数、样本 ID 和血糖值。
  2. `Loop/LoopTests/LoopTests.swift`：新增 CGM 入库日志字段测试，锁定 manager 标识、样本数、样本 ID 和血糖值不会丢。
  3. `build/ipa/Loop-3.9.1-57-20260618-041121.ipa`：已导出的开发签名 IPA。
- **验证结果**：`LoopTests` 单条新增测试尝试 3 次，均被当前环境的 Watch target 构建问题拦住，未执行到断言；`git diff --check` 通过；`LoopWorkspace` Debug 真机通用构建成功；`MicroTechCGM` 全量测试 102 个通过、0 失败；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `4c56ff225bfa0b8aede7ee541804e907f5ed2871a5f7210f3a91849c7f4acc10`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-041121.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-041121.xcresult`，1 个测试通过、0 失败；当前手机已有 CGM 配置，测试点开当前 CGM 后成功进入 `MicroTech LinX` 页面，未出现 `Unable to Open CGM`。
- **关键发现**：后续 Loop Report 可以直接通过入库日志判断 LinX 是否写入血糖；成熟长连产品标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑日志证明。
- **commit hash**：`1ef4d97`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 018 - 补齐 LinX 后台恢复后首笔血糖日志并重新安装

- **任务**：补齐 LinX 从保存设备后台恢复扫描后，第一笔当前血糖是否真正恢复的可追踪日志，并在可用 iPhone 上重新安装验证。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：保存过的 LinX 在 delegate queue 配好后自动恢复扫描时，会记录恢复原因；第一笔当前血糖日志会带上 `recoveredAfterReconnect reason=delegate queue configured`，手动重新搜索会清掉旧恢复原因。
  2. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增 `testRestoredSavedSensorHandshakeEmitsRecoveredCurrentReadingAfterDelegateQueueResume`，覆盖保存设备恢复扫描、F001 握手、F003 当前血糖、`.newData` 输出和恢复日志。
  3. `build/ipa/Loop-3.9.1-57-20260618-034500.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增测试先因未模拟 F001 握手失败，补齐测试流程后又因缺恢复日志失败；代码修复后该测试通过；`MicroTechCGM` 全量测试 102 个通过、0 失败；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `62d36a2e82ae4b9d81bbaeeab3c5d6a178869562e896fa894ca0b5111fd6fd37`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-034500.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-034500.xcresult`，1 个测试通过、0 失败。
- **关键发现**：代码层面的保存设备后台恢复扫描、重新握手、当前血糖输出和恢复日志已补齐；成熟长连产品标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑日志证明。
- **commit hash**：`8c3932a`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 017 - 补齐 LinX stale 重连恢复日志并重新安装

- **任务**：补齐 LinX stale watchdog 触发重连后，第一笔恢复血糖的可追踪日志，并重新打包安装到 iPhone。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：stale connection 被断开并重新搜索后，下一笔当前血糖日志会带上 `recoveredAfterReconnect reason=...`，可以直接判断重连后是否真的恢复出血糖。
  2. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增 `testStaleWatchdogReconnectsAndLogsRecoveredCurrentReading`，覆盖旧连接断开、重新搜索、重新连接、恢复当前血糖和恢复日志。
  3. `build/ipa/Loop-3.9.1-57-20260618-032000.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增 LinX stale 重连恢复测试先失败后通过；`MicroTechCGM` 全量测试最终 101 个通过、0 失败；中间一次全量测试暴露 `testDuplicateReadyCallbacksDoNotStartHandshakeTwiceAfterFailure` 偶发失败，单独重跑通过，全量重跑也通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`；IPA SHA256 为 `376fb4fd35a111f6ec53feb40275f49d0e5f8c50fb95de1f89ccd355ab5f5bb3`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-032000.ipa`；已启动 `com.libre.loopkit3.Loop`；测试后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-032000.xcresult`，结果为 `Passed`，1 个测试通过、0 失败。
- **关键发现**：代码层面的 stale 重连恢复链路和日志已补齐；成熟长连产品标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑日志证明。
- **commit hash**：`6b0fa07`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 016 - 补齐 LinX 当前血糖全链路日志并安装到 iPhone

- **任务**：确认 LinX 当前血糖解析链路和日志是否足够定位问题，并在可用 iPhone 上重新安装验证。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`：当前血糖解析日志增加包类型和原始数据前缀，后续能直接确认解析的是哪类 LinX 通知。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：当前血糖入库前日志增加包类型和原始数据前缀，后续能把解密、解析、接收三段日志串起来。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增真实 LinX 0x03 当前血糖通知全链路测试，覆盖加密通知、解密、解析、接收和 `.newData` 输出。
  4. `build/ipa/Loop-3.9.1-57-20260618-024014.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增 LinX 0x03 当前血糖全链路测试先失败后通过；`MicroTechCGM` 测试 100 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `b45e9eb50ca1daefe63da990403927af93544b0b2e01e39f772f9a1ffa0673eb`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-024014.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-024014.xcresult`，1 个测试通过、0 失败。
- **关键发现**：代码层面的当前血糖链路和日志已补齐；成熟长连产品标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑日志证明。
- **commit hash**：`277ed85`。
- **push 状态**：已推送到 `origin/main`。

### 2026-06-18 015 - 修复 LinX 自恢复检查导致的真机崩溃并重新安装

- **任务**：iPhone 可用后复测最新包，修复 `LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 中出现的 MicroTech 崩溃。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：蓝牙管理器在自己的蓝牙回调队列里读取连接状态时不再同步等待自己，避免系统触发 `dispatch_sync called on queue already owned by current thread` 后终止 App。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：LinX 自恢复检查登记时不再同步读取蓝牙连接状态，改为根据已连接传感器状态登记；陈旧连接断开和传感器断开时会清掉对应检查状态。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增当前血糖刷新自恢复检查时不读取蓝牙连接状态的回归测试，并保留 15 分钟无数据自动重连测试。
  4. `build/ipa/Loop-3.9.1-57-20260618-021516.ipa`：已导出的开发签名 IPA。
- **验证结果**：针对性 LinX 自恢复测试 3 个通过；`MicroTechCGM` 测试 99 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `09ae6bd3f7ccc9a6335b6acf7e53b7853bdcd9b3b28e580023fddce319913872`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-021516.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-022417.xcresult`，结果为 `Passed`，1 个测试通过、0 失败。
- **关键发现**：上一轮 Add CGM 失败不是入口缺失，而是 MicroTech 在蓝牙回调队列里同步读取连接状态导致真机崩溃；本轮已修复并在同一台 iPhone 上通过 UI 测试。成熟长连产品标准仍需要真实 LinX 设备的锁屏后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-18 014 - 补齐 LinX 失败回退和历史拒收日志并安装到 iPhone

- **任务**：在可用 iPhone 上重新验证当前 LinX 包，并补齐后续排查无血糖所需日志。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：历史血糖被拒收时，日志会写出无效值、重复值、过新值和时间过滤的具体样本，后续 Loop Report 可以直接定位为什么没有入库。
  2. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：蓝牙连接失败会带上失败设备标识，保存过的蓝牙标识连续失败后会回退为附近设备搜索。
  3. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：外设处于断开中或未知状态时也会安排连接超时，避免长时间卡住。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：补充历史拒收明细、连接失败回退、断开中超时的回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260618-003635.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 96 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `2d2129601c1f82981f8181800d9a3af416e3db828b8ab5359818a7d1124e90f5`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260618-003635.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；结果包为 `build/test-results/LinxUI-20260618-011220.xcresult`。
- **关键发现**：代码层面的失败回退、卡住超时和日志明细已补齐并验证；是否达到成熟长连产品标准，仍需要真实 LinX 设备的连接、锁屏后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-17 013 - 补齐 LinX 已配置 UI 测试和长连边界复验

- **任务**：在 iPhone 可用后重新验证当前 LinX 包，并补齐保存过的蓝牙标识失效后的重连边界。
- **核心交付**：
  1. `Loop/LoopUITests/LoopCGMSetupUITests.swift`：真机已配置 MicroTech LinX 时，不再要求看到 Add CGM，而是直接验证当前 LinX 设置页可打开。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：保存的蓝牙标识连续扫描或连接失败后，会清掉旧标识，改为按传感器序列号扫描附近设备，避免一直卡在失效的蓝牙 ID。
  3. `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`：前台/后台恢复后拿到已连接外设时，会重新订阅并重走握手，避免连接看似存在但通知没有恢复。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`、`MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`：补充保存蓝牙标识扫描失败、连接失败、已连接刷新重新握手的回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260617-232929.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增连接超时用例通过；`MicroTechCGM` 测试 93 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `0a000f0fdb8f856c17c693c126f71ff7373d66f6bb71250022ef9c392d7330e3`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260617-232929.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过；执行方式为 `build-for-testing` 后 `test-without-building`，复用已安装 App，未再触发未签名 Debug App 安装问题。
- **关键发现**：代码层面的已配置 UI、失效蓝牙标识回退、已连接刷新重新握手已修复并验证；是否达到成熟长连产品标准，仍需要真实 LinX 设备的连接、锁屏后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-17 012 - 修复 LinX 蓝牙回调卡住风险并安装到 iPhone

- **任务**：继续检查 LinX 作为长连 CGM 的连接、重连和后台恢复风险，在可用 iPhone 上重新安装验证。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：传感器断开、连续异常、扫描超时后的重新搜索改为延后执行，避免在蓝牙回调里同步触发搜索造成卡住。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：扫描超时通过传感器错误返回时，会进入蓝牙失败重试路径，不再被当作普通传感器异常后停住。
  3. `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`：激活握手后续写命令改为排队执行，避免在通知回调里直接写蓝牙命令。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`、`MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`：补充断开后延后重搜、扫描超时重试、连续异常重启、通知回调外写命令的回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260617-205837.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 90 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `29b28850e232e81384361bba5bc2ef60b2c89a430038520125f4503133062ae6`。
- **真机状态**：iPhone XR `E30C92D5-FE26-5AE1-B5FB-C787E4401F4F` 可用；已安装 `build/ipa/Loop-3.9.1-57-20260617-205837.ipa`；已启动 `com.libre.loopkit3.Loop`；5 秒后进程仍存在。
- **UI 测试状态**：`LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 未跑到页面断言；Xcode 尝试安装 `DerivedData/.../Build/Products/Debug-iphoneos/Loop.app`，iPhone 返回 `No code signature found`，不是已安装 IPA 的启动崩溃。
- **关键发现**：代码层面的蓝牙回调卡住风险、扫描超时重试和激活命令排队已修复；是否达到成熟长连产品标准，仍需要真实 LinX 设备的连接、锁屏后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-17 011 - 修复 LinX 搜索超时后卡住风险并重新打包 IPA

- **任务**：继续检查 LinX 作为长连 CGM 的连接、重连和后台恢复风险，修复搜索超时后可能卡住的路径。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：保存过的 LinX 搜索超时后，会在安全时机重新搜索，不再直接卡在蓝牙回调里。
  2. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：补充搜索超时重试不能立刻同步触发的回归测试，防止真实蓝牙队列被卡住。
  3. `build/ipa/Loop-3.9.1-57-20260617-201451.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增测试先失败后修复；`MicroTechCGM` 测试 88 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `6823398e4479b89523ff6e9481029b49af670d262de37828c7cef6d2abb32947`。
- **真机状态**：当前可见 iPhone 全部是 `unavailable`，未执行安装和长时间后台验证。
- **关键发现**：代码层面的搜索超时、重试、后台恢复识别和日志路径已继续补强；是否达到成熟长连产品标准，仍需要真实 iPhone 上锁屏、后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-17 010 - 修复 LinX 搜索超时重试和后台恢复识别风险并重新打包 IPA

- **任务**：继续检查 LinX 是否满足长连 CGM 的连接、重连和后台恢复要求，修复会导致长连卡住的代码路径。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：保存过的 LinX 搜索超时后会保留错误提示并继续重新搜索，不再一次超时后停住。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：恢复连接时可按已保存的蓝牙标识接受设备，即使恢复出来的设备名为空；同时避免已保存设备场景误接其他 LinX。
  3. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：后台恢复出来的外设会缓存，后续按保存的蓝牙标识重新连接，不依赖设备名。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增搜索超时自动重试、保存设备无名字恢复识别的回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260617-195232.ipa`：已导出的开发签名 IPA。
- **验证结果**：新增 2 个测试先失败后修复；`MicroTechCGM` 测试 88 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `8ee2f6282d6339ce6f142383a0b0ee7d2779f1d79d474862d0e98f8602bce37b`。
- **真机状态**：`devicectl` 当前列出的 iPhone 全部是 `unavailable`，未执行安装和长时间后台验证。
- **关键发现**：代码层面的搜索超时重试和后台恢复识别风险已补齐；是否达到成熟长连产品标准，仍需要真实 iPhone 上锁屏、后台、离线重连和过夜长跑日志证明。
- **push 状态**：未推送。

### 2026-06-17 009 - 重新打包 IPA

- **任务**：按当前代码重新导出可安装 IPA。
- **核心交付**：
  1. `build/ipa/Loop-3.9.1-57-20260617-193118.ipa`：已导出的开发签名 IPA。
  2. `build/archive/Loop-20260617-193118.xcarchive`：对应归档。
  3. `build/export/Loop-20260617-193118`：对应导出目录。
- **验证结果**：`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；后台模式包含 `bluetooth-central`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；IPA SHA256 为 `1d592d0b478a9d43db82d5305aabfb24906f2be32eca7e71da191d6b8833c1d3`。
- **真机状态**：本次仅打包和包体验证，未执行安装验证。
- **push 状态**：未推送。

### 2026-06-17 008 - 修复 LinX 错误提示保留并重新打包 IPA

- **任务**：修复 LinX 自动重连时失败原因被清掉的问题，并重新导出可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：自动重连、后台恢复扫描、无首条血糖重连不再清掉最后一次失败原因；用户主动重新搜索、连接成功、读到数据后才清除旧错误。
  2. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：Bluetooth 不可用和搜索超时会返回可见错误，避免设置页只显示一直扫描。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：补充连续 `invalidCRC` 后自动重连仍保留错误、主动重新搜索清除旧错误、Bluetooth 错误文本可读的回归测试。
  4. `build/ipa/Loop-3.9.1-57-20260617-191657.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 86 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；后台模式包含 `bluetooth-central`；IPA SHA256 为 `2aa9de62a90bba07cb5125f50aded40418dd466670855697e47e9107473ca41b`。
- **真机状态**：`devicectl` 当前列出的 iPhone 全部是 `unavailable`，未执行安装验证。
- **关键发现**：代码层面的失败原因展示、自动重连错误保留、Bluetooth 不可用提示、搜索超时提示已补齐；后台长时间保活、系统蓝牙恢复和离线重连仍需要真实 iPhone 长时间日志证明。
- **push 状态**：未推送。

### 2026-06-17 007 - 重新打包 IPA 并完成包体验证

- **任务**：按当前工作区重新导出可安装 IPA。
- **核心交付**：
  1. `build/ipa/Loop-3.9.1-57-20260617-184959.ipa`：已导出的开发签名 IPA。
  2. `build/archive/Loop-20260617-184959.xcarchive`：对应归档。
  3. `build/export/Loop-20260617-184959`：对应导出目录。
- **验证结果**：`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内版本为 `3.9.1 (57)`；Bundle ID 为 `com.libre.loopkit3.Loop`；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`、`LibreTransmitter.framework`；后台模式包含 `bluetooth-central`。
- **真机状态**：`devicectl` 当前列出的 iPhone 全部是 `unavailable`，未执行安装验证。
- **push 状态**：未推送。

### 2026-06-17 006 - 补齐 LinX 已连接刷新和断开后立即重搜并重新打包 IPA

- **任务**：继续修复 LinX 长连和重连风险，并重新导出可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：蓝牙已处于连接状态时，会重新绑定并刷新当前连接，避免后台恢复或重复进入时停在“已连接但无后续动作”。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：主动断开陈旧连接、首条血糖超时、连续异常重启后，会马上重新搜索保存过的 LinX 设备。
  3. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：补充已连接刷新和断开后立即重搜的回归测试。
  4. `build/ipa/Loop-3.9.1-57-20260617-152026.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 83 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：代码层面的已连接刷新和断开后重搜已补齐；后台长时间保活、系统蓝牙恢复和离线重连仍需要真实 iPhone 长时间日志证明。
- **push 状态**：未推送。

### 2026-06-17 005 - 补齐 LinX 无首条读数重连、连续异常重连与后台恢复日志并重新打包 IPA

- **任务**：继续检查 LinX 长连、重连和后台恢复代码路径，补齐连接后一直没有首条血糖、连续解析异常、后台恢复日志不足这三个风险点，并重新导出可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：连接后超过 15 分钟仍没有任何血糖时会主动断开并重新搜索，避免表面已连接但一直无数据。
  2. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：连续 3 次传感器异常后会主动重启连接，避免解析失败后长期停住。
  3. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：后台蓝牙恢复日志会记录是否恢复到设备、恢复数量和设备标识，便于真机日志快速定位。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：补充无首条血糖重连、连续异常重连、后台恢复标识稳定性和不关闭泵蓝牙心跳的回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260617-140545.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 82 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：代码层面的长连、异常重连和后台恢复日志已补齐；后台长时间保活、系统蓝牙恢复和离线重连仍需要真实 iPhone 长时间日志证明，当前不能只凭代码判断为成熟产品完成。
- **push 状态**：未推送。

### 2026-06-17 004 - 补齐前台返回刷新 CGM 并重新打包 IPA

- **任务**：确认 LinX 长连、重连和后台恢复相关代码路径，补齐 App 回到前台后 CGM 不主动刷新的缺口，并重新导出可安装 IPA。
- **核心交付**：
  1. `Loop/Loop/Managers/DeviceDataManager.swift`：App 回到前台时会同时刷新 CGM，避免只更新泵蓝牙偏好而不触发 LinX 恢复。
  2. `Loop/LoopTests/LoopTests.swift`：新增前台返回刷新 CGM 的回归测试。
  3. `build/ipa/Loop-3.9.1-57-20260617-130045.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 78 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：`LoopTests` 单条新增测试仍被当前环境的 watchOS/simulator 构建问题拦住，未执行到断言；这不是 LinX 代码导致。后台长时间保活、系统蓝牙恢复和离线重连仍需要真实 iPhone 日志证明，当前不能只凭代码判断为成熟产品完成。
- **push 状态**：未推送。

### 2026-06-17 003 - 修复 LinX 选择无反馈、序号 0 过滤与陈旧连接重连并重新打包 IPA

- **任务**：修复 LinX 选择后界面无反馈、序号回绕后 0 号血糖被过滤、已连接但长时间无新血糖时无法自动恢复的问题，并重新导出可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：扫描到 LinX/AiDEX 后立即保存设备名称、序列号和蓝牙标识；真正握手成功后才允许完成 CGM 添加。
  2. `MicroTechCGM/MicroTechCGM/MicroTechGlucoseReading.swift`：当前血糖允许 0 号序列，避免 65535 回绕到 0 时被误判为无效。
  3. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：历史血糖同样允许 0 号序列，并在已连接但 15 分钟无新血糖时主动断开以触发重连。
  4. `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`：新增“已连接确认”状态，防止只发现设备就被当成添加完成。
  5. `build/ipa/Loop-3.9.1-57-20260617-123519.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 78 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：后台恢复和长时间真机保活仍需要真实 iPhone 日志证明；当前完成的是代码路径修复、自动化测试和 IPA 打包。
- **push 状态**：未推送。

### 2026-06-17 002 - 修复 LinX 添加空设备与历史回绕并重新打包 IPA

- **任务**：修复选择 LinX 后未连接真实设备就完成添加的问题，补齐历史包序号回绕处理，并重新导出可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`：选择 LinX 后只进入附近设备搜索；必须等真实 LinX/AiDEX 设备连接成功后，才完成 CGM 添加。
  2. `MicroTechCGM/MicroTechCGM/MicroTechAidexParser.swift`：历史数据包在 65535 后正确回到 0，避免跨边界历史值被错误排序或过滤。
  3. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：补齐状态观察通知，保证连接到有效探头后 UI 添加流程能收到状态变化。
  4. `LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme`：主 workspace 测试列表包含 `MicroTechCGMTests`。
  5. `build/ipa/Loop-3.9.1-57-20260617-113839.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 73 个全部通过；`git diff --check` 通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；App 签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：主 workspace 已能识别 `MicroTechCGMTests`，但主 workspace 测试命令仍被当前环境的 watchOS `LoopKit.framework` 缺失问题拦住；这不是 LinX 代码导致。
- **push 状态**：未推送。

### 2026-06-17 001 - 修复 LinX 数据过滤与连接超时并打包 IPA

- **任务**：修复 LinX 无血糖数据风险点，补充连接失败退出路径和日志，并打包可安装 IPA。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`：当前值和历史值使用相同过滤口径，并支持 16 位序号回绕，避免跨周期数据被误过滤。
  2. `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`：连接卡住时会超时退出并恢复搜索，避免长时间停在无反应状态。
  3. `Loop/Loop/Managers/DeviceDataManager.swift`：补充 CGM 血糖写入日志，能区分成功、失败、无数据和不可靠数据。
  4. `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`：新增当前值过滤、历史值回绕和连接超时回归测试。
  5. `build/ipa/Loop-3.9.1-57-20260617-084214.ipa`：已导出的开发签名 IPA。
- **验证结果**：`MicroTechCGM` 测试 69 个通过；主 App 通用 iOS 构建通过；`LoopWorkspace` Debug archive 成功；IPA 导出成功；签名校验通过；包内已确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`。
- **关键发现**：`Loop` scheme 的 archive 会在当前环境报 `LoopKit` 依赖解析失败；可用的打包入口是 `LoopWorkspace` scheme。Release archive 同样卡在该依赖解析点，本次 IPA 使用现有开发签名 Debug 导出路径。
- **push 状态**：未推送。

### 2026-06-14 004 - 复验 LinX 接入完成状态

- **任务**：按当前代码和当前设备状态复验 LinX 设备接入是否完成，并确认自动化测试覆盖关键路径。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechCGMManager+UI.swift`：为 LinX UI 扩展添加明确的 `@retroactive` 协议适配标记，消除本次新增代码触发的 Swift warning。
  2. `docs/工具与踩坑.md`：记录 LinX 单元测试应使用 iOS Simulator，添加流程测试使用真机 `LoopUITests`。
- **验证结果**：`xcodebuild test -quiet -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /Users/liyang/Library/Developer/Xcode/DerivedData/LoopWorkspace-exnvvofyspxgrgfhgxypmjkymqtl -disableAutomaticPackageResolution` 已通过，结果包 `Test-Shared-2026.06.14_08-59-12-+0800.xcresult` 显示 `status=succeeded`、`testsCount=46`；`xcodebuild test -quiet -workspace LoopWorkspace.xcworkspace -scheme LoopUITests -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -disableAutomaticPackageResolution -only-testing:LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过，结果包 `Test-LoopUITests-2026.06.14_08-55-34-+0800.xcresult` 显示 `status=succeeded`、`testsCount=1`。
- **关键发现**：`MicroTechCGMTests` 不能直接跑在真机上，真机会提示 tool-hosted testing unavailable；该测试目标应使用 iOS Simulator。LinX 添加流程 UI 测试已在 iPhone XR 真机上通过。
- **commit hash**：`131308c`
- **push 状态**：已推送到 `origin/main`。

### 2026-06-14 003 - 新增 LinX 添加流程真机自动化测试

- **任务**：为添加 CGM 选择 `MicroTech LinX` 的关键路径新增自动化测试。
- **核心交付**：
  1. `Loop/LoopUITests/LoopCGMSetupUITests.swift`：新增真机 UI 测试，直接启动手机上已安装的 `com.libre.loopkit3.Loop`，自动从状态页进入 `Settings`，点击 `Add CGM`，选择 `MicroTech LinX`，并确认不会停在 `Unable to Open CGM`，最终看到 LinX 设置页和输入框；如果当前已配置 CGM，会明确提示先移除当前 CGM。
  2. `Loop/Loop.xcodeproj/project.pbxproj`、`Loop/Loop.xcodeproj/xcshareddata/xcschemes/LoopUITests.xcscheme`：新增独立 `LoopUITests` 测试目标和纯测试 scheme，避免本机缺少 watchOS 平台时重新构建 Watch App。
  3. `Loop/Loop/View Controllers/StatusTableViewController.swift`、`Loop/Loop/Views/SettingsView.swift`、`MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`：补充测试用页面标识，不改变用户可见界面。
  4. `docs/工具与踩坑.md`：记录真机 UI 测试入口、Watch 平台限制和本次测试发现。
- **验证结果**：先运行同一 UI 测试确认失败点为缺少 `status.settings`；补齐标识和状态页返回逻辑后，`xcodebuild test -quiet -workspace LoopWorkspace.xcworkspace -scheme LoopUITests -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -disableAutomaticPackageResolution -only-testing:LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings` 已通过，结果包 `Test-LoopUITests-2026.06.14_08-39-19-+0800.xcresult` 显示 `status=succeeded`、`testsCount=1`；`git diff --check` 已通过；`plutil -lint Loop/LoopUITests/Info.plist` 已通过；`xmllint --noout Loop/Loop.xcodeproj/xcshareddata/xcschemes/LoopUITests.xcscheme` 已通过；`xcodebuild -list -workspace LoopWorkspace.xcworkspace` 已确认 `LoopUITests` scheme 存在；正式 Watch 构建配置仍保留。
- **关键发现**：Xcode UI 测试启动后会恢复上次页面，本机曾停在“已输注胰岛素”详情页，因此测试需要先回到状态页；LinX 页面实际已打开，但 SwiftUI 文本标识在 UI 层级里不稳定，测试保留标识并同时使用可见文字兜底；如果 `LoopUITests` scheme 绑定 App 构建，本机缺少 watchOS 26.5 会在测试前失败，因此该 scheme 只构建测试包，测试时启动已安装 App。
- **commit hash**：`bba0a61`
- **push 状态**：已推送到 `origin/main`。

### 2026-06-14 002 - 修复 LinX 提示 Unable to Open CGM

- **任务**：修复在添加 CGM 时选择 `MicroTech LinX` 后提示 `Unable to Open CGM` 的问题。
- **核心交付**：
  1. `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`：移除 LinX 工程中错误的 Swift Package 版本 `LoopKit`/`LoopKitUI` 引用，改为引用主 App 已包含的 `LoopKit.framework`/`LoopKitUI.framework`。
  2. `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`：将 LinX 目标最低 iOS 版本从 15.0 对齐到主工程的 15.1。
  3. `docs/工具与踩坑.md`：记录 `Unable to Open CGM` 的真实原因和验证方式。
- **验证结果**：`xcodebuild build -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -derivedDataPath /Users/liyang/Library/Developer/Xcode/DerivedData/LoopWorkspace-exnvvofyspxgrgfhgxypmjkymqtl` 已通过；主 App Debug 构建已通过；最终 `Loop.app` 内 `MicroTechCGMPlugin.framework` 和 `MicroTechCGMUI.framework` 已确认引用 `LoopKit.framework`/`LoopKitUI.framework`，不再引用 `LoopKitUI_D1D06EAA165FD69_PackageProduct.framework`；已覆盖安装并启动 `com.libre.loopkit3.Loop`；进程 5 秒后仍存在；`git diff --check` 已通过；临时 Watch 构建改动已恢复。
- **commit hash**：`bba0a61`
- **push 状态**：已推送到 `origin/main`。

### 2026-06-14 001 - 修复 Settings 中选择 LinX 后无反应

- **任务**：修复在 `Settings` 中添加 CGM，选择 `MicroTech LinX` 后看不到后续页面的问题。
- **核心交付**：
  1. `Loop/Loop/Extensions/UIViewController.swift`：关闭当前页面或上层页面承载的弹窗后，再弹出目标页面。
  2. `Loop/Loop/View Controllers/StatusTableViewController.swift`：添加 CGM、打开现有 CGM、打开 Pump 设置时改为弹出页面；CGM 打开失败时在手机上显示错误提示。
  3. `Loop/LoopTests/LoopTests.swift`：补充当前页面和上层页面两种弹出顺序回归测试。
  4. `docs/工具与踩坑.md`：记录本次页面遮挡问题和本机 Watch 测试阻断。
- **验证结果**：`xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme Loop -configuration Debug -destination 'id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F' -allowProvisioningUpdates -allowProvisioningDeviceRegistration -disableAutomaticPackageResolution` 已通过；安装包内确认存在 `MicroTechCGM.framework`、`MicroTechCGMPlugin.framework`、`MicroTechCGMUI.framework`，插件显示名为 `MicroTech LinX`；已覆盖安装并启动 `com.libre.loopkit3.Loop`；进程 5 秒后仍存在；`git diff --check` 已通过；`Loop/Loop.xcodeproj/project.pbxproj` 临时 Watch 构建改动已恢复。`LoopTests` 受本机 Watch 目标构建问题阻断，未执行到测试断言。
- **关键发现**：手机上存在多个显示名为 `Loop` 的 App，本次安装和启动目标为 `com.libre.loopkit3.Loop`。
- **commit hash**：`bba0a61`
- **push 状态**：已推送到 `origin/main`。

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
