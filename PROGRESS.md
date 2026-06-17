# PROGRESS

## 当前状态

- 已安装本项目 AI 开发规则入口：`AGENTS.md`。
- 已保留通用规则来源文档：`docs/通用开发规则模板.md`。
- 当前固定信息：仓库 `q601180252/loopcloudtest`，默认分支 `main`，主 workspace `LoopWorkspace.xcworkspace`。
- 当前 LinX 添加流程自动化测试入口：`LoopUITests` scheme，真机 destination `id=E30C92D5-FE26-5AE1-B5FB-C787E4401F4F`，要求手机已安装 `com.libre.loopkit3.Loop`。
- 当前 LinX 接入复验结果：`MicroTechCGM` 单元测试 107 个通过；最新 IPA 已安装到 iPhone XR 并启动，20 秒后进程仍存在；配置阶段已增加超时保护和明确日志；真机当前仍没有新血糖，最新日志显示 LinX 卡在连接超时和扫描超时，状态仍停留在 2026-06-18 04:32 的 91 mg/dL。
- 最新 IPA：`build/ipa/Loop-3.9.1-57-20260618-060210.ipa`，SHA256 `7c1967945ad8390f502ebd26d6e40eea82ade030dc302c49123c4bb2dfafcffa`。

## 进展日志

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
