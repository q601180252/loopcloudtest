# LinX Packet Silence Reconnect Implementation Plan

> 状态：代码实现和自动化测试已完成；真实 LinX 正常通信与 `peripheralDisconnecting` 卡死恢复仍待真机复验。最终构建、提交和推送结果以 `PROGRESS.md` 最新记录为准。

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让已经成功连接过的 LinX 在 5 分钟没有收到任何数据包时自动重连，并在单次重连持续 60 秒仍未完成握手时重建蓝牙连接环境。

**Architecture:** `MicroTechSensor` 在解密和解析前上报 F001/F002/F003 原始通知，`MicroTechCGMManager` 用独立状态保存当前传感器的数据包静默检查和 60 秒恢复周期。60 秒超时后先异步关闭并废弃旧 `MicroTechBluetoothManager`，完成后才创建新管理器；所有旧管理器和旧传感器回调都按对象身份失效。

**Tech Stack:** Swift, CoreBluetooth, LoopKit, XCTest, Xcode workspace

---

## 完成标准

- [x] 已连接 LinX 收到任意 F001/F002/F003 通知时刷新 5 分钟计时，通知无需解密或解析成功。
- [x] 握手后从未收到通知，也会在 5 分钟后断开并开始重连。
- [x] 数据包静默检查不修改 `lastReadingDate`，广播兼容模式、旧传感器和已删除 CGM 不受影响。
- [x] 已成功连接过的直连 LinX 开始重连后只保留一个 60 秒周期，扫描重试、发现设备和连接尝试不延长时间。
- [x] 60 秒内完成握手会取消恢复；超时则关闭旧管理器，清除旧蓝牙标识并使用原序列号创建新管理器继续扫描。
- [x] 旧管理器关闭完成前不会创建新管理器，旧管理器和旧传感器的迟到回调不能改变当前状态。
- [x] 首次添加、广播兼容模式和其他 CGM 行为不变。
- [x] 新增测试完成真实 red-green 验证，`MicroTechCGMTests` 全量通过，`LoopWorkspace` 完整构建通过。
- [ ] 文档、`PROGRESS.md`、commit 和 `origin/main` 同步完成；真机不能稳定制造卡死时明确保留该项实机复验。

## 文件结构

- Modify: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
  - 为蓝牙管理器协议和实现增加异步关闭契约；清理扫描、连接、配置、外设、delegate 和日志回调。
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`
  - 在解密、协议处理和解析前上报当前 F001/F002/F003 原始通知。
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
  - 保存数据包静默状态、60 秒恢复状态和管理器身份；协调断开、关闭、重建、扫描与旧回调隔离。
- Modify: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`
  - 扩展 fake manager 和可控 scheduler，覆盖关闭顺序、恢复周期、静默检查、并发失效与日志。
- Modify: `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
  - 验证 F001/F002/F003 原始通知回调发生在提前返回、解密和解析之前。
- Modify: `docs/superpowers/specs/2026-08-03-linx-60-second-reconnect-recovery-design.md`
  - 实现后记录已完成范围和仍需真实卡死复验的边界。
- Modify: `docs/工具与踩坑.md`
  - 记录当前仓库运行 LinX 单测应使用 `LoopWorkspace`，以及只覆盖当前命令的可用代理方式。
- Modify: `PROGRESS.md`
  - 顶部状态与倒序进展记录实现、验证、commit 和 push 状态。

## Chunk 1: 蓝牙管理器关闭与 60 秒恢复周期

### Task 1: 增加可验证的异步关闭契约

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift:41-68, 144-162, 208-348, 811-1115`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift:3909-3980`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift:234-270`

- [x] **Step 1: 扩展 fake manager 并写关闭契约失败测试**

在 `FakeMicroTechBluetoothManager`、`ReentrantLogHandlerMicroTechBluetoothManager` 和 `BroadcastFakeMicroTechBluetoothManager` 中增加：

```swift
private(set) var shutdownCallCount = 0
private var shutdownCompletions: [() -> Void] = []

func shutdown(completion: @escaping () -> Void) {
    shutdownCallCount += 1
    shutdownCompletions.append(completion)
}

func completeShutdown(at index: Int = 0) {
    shutdownCompletions.remove(at: index)()
}
```

增加以下失败测试：

```swift
func testBluetoothManagerShutdownCompletionIsExplicit()
func testRealBluetoothManagerShutdownClearsCallbacksBeforeCompletion()
func testConnectionTimeoutControllerCancelAllInvalidatesScheduledHandlers()
func testShutdownManagerIgnoresLateCallbacksAndCannotRestartScanning()
```

fake 测试要求完成回调在显式触发前不会执行；真实 manager 测试要求 completion 中 `delegate` 和 `logHandler` 已为 nil；timeout controller 测试要求 `cancelAll()` 后排队 handler 不执行。测试先因 `MicroTechBluetoothManaging` 没有 `shutdown(completion:)` 且 timeout controller 没有 `cancelAll()` 而无法编译。

- [x] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: FAIL because `shutdown(completion:)`、`cancelAll()` 和永久关闭状态尚不存在。保存失败输出作为本任务全部新增测试的 red 证据。

- [x] **Step 3: 实现协议与真实管理器关闭**

把关闭方法加入协议，不提供立即完成的默认实现：

```swift
func shutdown(completion: @escaping () -> Void)
```

真实管理器在 `managerQueue` 上按以下顺序完成：

```swift
public func shutdown(completion: @escaping () -> Void) {
    managerQueue.async {
        guard !self.isShutdown else {
            completion()
            return
        }
        self.isShutdown = true
        self.stopScanningOnQueue(reason: "shutdown")
        self.cancelScanTimeout()
        self.connectionTimeouts.cancelAll()
        self.configurationTimeouts.cancelAll()

        let managers = Array(self.managedPeripherals.values)
        managers.forEach { self.removeManager($0, cancelConnection: true) }
        self.activePeripheralManager = nil
        self.managedPeripherals.removeAll()
        self.restoredPeripherals.removeAll()
        self.configuringPeripheralIDs.removeAll()
        self.delegate = nil
        self.logHandler = nil
        completion()
    }
}
```

`isShutdown` 只能在 `managerQueue` 上访问，且一旦为 true 永不恢复。`configureConnectionMode`、`scan`、`scanForBroadcast`、`refreshConnectedPeripheral`、自动 `scanIfReady`、所有 CoreBluetooth delegate 和 peripheral delegate 入口都必须先检查该标识；关闭后的迟到回调不得扫描、连接或上报。`MicroTechConnectionTimeoutController` 增加遍历现有 work item 并取消的 `cancelAll()`；不要等待 CoreBluetooth 的断开回调。

- [x] **Step 4: 运行目标测试并检查现有 fake 全部满足协议**

Run: 与 Step 2 相同。

Expected: PASS，且 `MicroTechCGMTests` 中所有 `MicroTechBluetoothManaging` fake 均能编译。

- [x] **Step 5: 提交关闭契约**

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift
git commit -m "新增 LinX 蓝牙管理器关闭接口" -m "改动原因：60 秒超时后必须先停止旧蓝牙环境再创建新管理器。\n\n改动清单：增加异步关闭契约，清理扫描、超时、外设和回调，并扩展测试替身。\n\n验证结果：关闭契约目标测试通过。\n\n影响范围：仅 MicroTech LinX 蓝牙管理器内部生命周期。"
```

### Task 2: 实现单一 60 秒恢复状态机

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift:144-162, 280-348`
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift:18-169, 261-350, 640-687, 810-946, 1232-1346, 1737-1766`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift:1836-2475, 3909-3980`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift:234-270`

- [x] **Step 1: 写恢复周期失败测试**

用两个 `FakeMicroTechBluetoothManager`、可控 `reconnectRecoveryScheduler` 和工厂调用计数覆盖：

```swift
func testSavedDirectSensorReconnectStartsOnlyOneSixtySecondRecoveryCycle()
func testDiscoveryAndRetryDoNotResetReconnectRecoveryDeadline()
func testHandshakeCancelsReconnectRecoveryCycle()
func testRecoveryTimeoutWaitsForShutdownBeforeCreatingReplacementManager()
func testShutdownCompletionRechecksDeletionAndConnectionMode()
func testReplacementManagerScansBySerialWithoutSavedIdentifier()
func testFirstOnboardingAndBroadcastModeDoNotStartReconnectRecovery()
func testOldRecoveryTimeoutCannotReplaceNewConnection()
func testReconnectEligibilityRequiresPriorHandshakeSerialDirectModeNotDeletedAndNotCurrentlyConnected()
func testOldBluetoothManagerShouldConnectReadyFailureDisconnectBroadcastAndDataCallbacksAreIgnored()
func testOldSensorConnectDisconnectReadingHistoryActivationIgnoredAndErrorCallbacksAreIgnored()
func testShuttingDownIgnoresScanFetchInternalAndQueuedRetryWithoutCallingFactory()
func testShutdownCompletionTransitionsDirectlyToNextTimingCycle()
func testRecoveryRebuildPreservesDeviceActivationLatestReadingAndHistoryDedupButClearsPendingHistory()
func testUserRepeatedScanAndConnectionAttemptsDoNotExtendRecoveryDeadline()
func testShutdownCompletionAfterSuccessfulHandshakeDoesNotRebuild()
func testDeleteBetweenReplacementCreationAndActivationTerminatesReplacement()
func testModeChangeBetweenReplacementCreationAndActivationTerminatesReplacement()
func testRebuildLogsFirstHandshakeAndFirstCurrentReadingOnlyOnce()
```

关键断言：第一次有效重连只安排 `60`；重复扫描、发现、连接尝试不增加 scheduler 数量；`shuttingDown` 时用户 scan、fetch、内部 retry 和已排队 retry 均不调用工厂；超时只调用旧 manager 的 `shutdown`；显式执行完成回调后工厂才创建第二个 manager；状态从 `.shuttingDown(oldID)` 直接变成 `.timing(newID)`；`remoteIdentifier == nil`，`sensorSerial`、`deviceName`、激活时间、latest reading、last reading date 和历史去重集合保留，pending history 清除。

- [x] **Step 2: 运行恢复周期测试并确认失败原因**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: FAIL because没有 60 秒 scheduler、状态机、manager generation 或 replacement activation。Task 1 的关闭测试应继续通过；保存本次全部恢复测试的 red 证据。

- [x] **Step 3: 增加恢复依赖与状态**

构造器增加独立 scheduler，避免复用 5 分钟检查的命名：

```swift
private let reconnectRecoveryScheduler: (TimeInterval, @escaping () -> Void) -> Void

private enum MicroTechReconnectRecoveryState {
    case idle
    case timing(id: UUID)
    case shuttingDown(id: UUID)
}

private struct MicroTechBluetoothManagerGeneration {
    let id: UUID
    let manager: MicroTechBluetoothManaging
}
```

`MicroTechCGMManagerProtectedState` 保存 `reconnectRecoveryState`；使用唯一 `reconnectRecoveryInterval = 60`。新增小函数集中完成以下转换：

```swift
startReconnectRecoveryIfNeeded(reason:)
runReconnectRecoveryTimeout(identifier:)
completeBluetoothManagerShutdown(recoveryIdentifier:)
cancelReconnectRecovery(reason:)
```

把 eligibility 判断做成单一纯函数，输入删除状态、连接模式、`hasConnectedSensorSession`、`sensorSerial` 和当前是否已握手，供开始周期与 shutdown completion 共用。表驱动测试从完整有效条件开始，逐项翻转 prior handshake、空 serial、mode、deleted 和 current handshake 并断言 false；不要为测试增加可修改 private state 的生产接口。

所有 eligibility 检查统一要求：未删除、`.direct`、`hasConnectedSensorSession == true`、非空 `sensorSerial`、尚未握手成功。为所有真实 manager delegate 方法增加统一入口：

```swift
private func isCurrentBluetoothManager(_ manager: MicroTechBluetoothManaging) -> Bool
```

由于 public delegate 参数是具体 `MicroTechBluetoothManager`，再增加可由 `@testable` 测试调用的 internal forwarding helpers；public `shouldConnect`、`didReady`、`didReceive`、`didDisconnect`、`didDiscoverBroadcast`、`didFail` 只负责转交。helper 首先比较当前 manager generation 和对象身份，旧来源只写 ignored 日志，不更新状态、不报错、不扫描。现有 `isCurrentSensor` 覆盖 sensor 的 connect、disconnect、reading、history、ignored packet、error 和新增 raw packet callback。

重构 `scanForSensor`，不得在 `lockedManagerState` mutation 中调用 manager 的 `configureConnectionMode`、`isScanning`、`isConnected` 或其他同步 API。先在锁内领取当前 generation 和操作意图，再在锁外读取 manager 状态，最后用 generation 复核结果是否仍适用。这样 manager queue 上的 callback 等待 CGM lock 时，不会遇到持锁线程同步等待 manager queue。

- [x] **Step 4: 把所有重连入口接入同一周期**

在以下现有入口启动或复用周期，不在内部 retry 时换 ID：

- `resumeSavedSensorScanIfNeeded`
- 当前 sensor `didDisconnect`
- 连续 sensor error 触发的 disconnect
- `recordBluetoothFailure` 的扫描重试和 identifier fallback
- 用户 `scanForSensor` / `fetchNewDataIfNeeded` 对已连接过设备发起恢复时

`microTechSensorDidConnect` 被接受时取消周期。删除 CGM、离开 `.direct`、换传感器时取消周期。

- [x] **Step 5: 实现超时后的严格关闭与重建顺序**

超时的同一次 `mutateProtectedState` 中完成：

```swift
reconnectRecoveryState = .shuttingDown(id: id)
bluetoothManager = nil
state.remoteIdentifier = nil
retireActiveSensor()
sensorIdentity.clearPendingHistoryRequest()
```

锁外调用捕获的旧 manager `shutdown`。完成回调重新核对同一 `shuttingDown(id)` 和 eligibility，在一次 state mutation 中创建带新 generation 的 replacement manager，并直接进入 `.timing(newID)`，绝不经过 `.idle`。

随后调用统一 `activateReplacementManager(manager:generation:recoveryID:)`：先在锁内复核 manager、generation、`.timing(newID)`、未删除和 `.direct`，锁外只调用 manager 的单一 `activateDirectScan(delegate:logHandler:remoteIdentifier:)`。该方法在 `managerQueue` 的一个 block 内先检查 `isShutdown`，然后一次完成 delegate、log handler、direct mode 和空 identifier 扫描；不得在 CGM 层分开设置 handler 与扫描。删除 CGM 或离开 `.direct` 必须在锁内移除并失效 replacement generation，锁外对捕获对象调用 `shutdown`。activation 与 shutdown 在同一 manager queue 串行：shutdown 先执行时 activation 不会重新绑定，activation 先执行时随后 shutdown 会清空并停止。两个竞态测试用 fake activation barrier 固定复现两种顺序，并同时断言最终 `delegate == nil`、`logHandler == nil`、没有活动扫描和迟到日志。历史保留测试在重建后再次发送已接收 history sample，断言不会重复输出；同时断言旧 pending request 已清除且新连接可以重新申请补数。

- [x] **Step 6: 增加恢复日志断言**

日志只包含恢复 ID、原因、60 秒时长、关闭完成、重建扫描和成功取消，不新增密钥或数据包内容。目标测试验证超时消息同时包含 `60` 和 `rebuild`（或最终采用的稳定事件字段），并验证握手取消消息。

- [x] **Step 7: 运行 Task 2 全部目标测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: `MicroTechCGMManagerTests` PASS，现有 saved identifier fallback、scan retry、删除和 broadcast 测试继续通过。

- [x] **Step 8: 提交 60 秒恢复**

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift \
  MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift
git commit -m "新增 LinX 六十秒重连恢复" -m "改动原因：旧蓝牙连接卡死时普通扫描会持续复用异常状态。\n\n改动清单：增加单一 60 秒恢复周期、关闭后重建、旧回调隔离和恢复日志。\n\n验证结果：MicroTechCGMManagerTests 通过。\n\n影响范围：仅已成功连接过的直连 LinX 自动重连。"
```

## Chunk 2: 原始通知与 5 分钟数据包静默检查

### Task 3: 在解析前上报 LinX 原始通知

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift:8-35, 180-267`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [x] **Step 1: 写原始通知顺序失败测试**

向 `MicroTechSensorDelegate` 增加预期接口的测试调用记录：

```swift
func microTechSensor(
    _ sensor: MicroTechSensor,
    didReceivePacketFor characteristic: CBUUID,
    receivedAt: Date
)
```

覆盖：

```swift
func testF001ReportsRawPacketBeforePairingResponseReturns()
func testF002ReportsRawPacketBeforeDecryptFailure()
func testF003ReportsRawPacketBeforeParseFailure()
func testUnrelatedCharacteristicDoesNotReportRawPacket()
```

事件数组必须证明 `packet` 位于 pairing/decrypt/parse 结果之前；不要在事件中保存 raw payload。

- [x] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechSensorHandshakeTests
```

Expected: FAIL because delegate 没有 raw packet callback。

- [x] **Step 3: 实现同步 callback**

`handleNotification` 先只判断 characteristic：

```swift
guard characteristic == MicroTechAidexProfile.f001UUID ||
      characteristic == MicroTechAidexProfile.f002UUID ||
      characteristic == MicroTechAidexProfile.f003UUID else {
    return
}

delegate?.microTechSensor(
    self,
    didReceivePacketFor: characteristic,
    receivedAt: receivedAt
)
```

callback 必须位于 F001 的 pairing key 保存与 `return` 之前，也位于 command builder、session、decrypt、protocol response 和 parser 之前。保持当前 CoreBluetooth delegate 串行调用顺序。

在 `MicroTechSensorDelegate` 的 public extension 中先提供该新方法的 no-op 默认实现，使现有 conformer 在 Task 3 可编译；`ReadingObserver` 覆写方法记录顺序。`MicroTechCGMManager` 的实际处理在 Task 4 加入。

- [x] **Step 4: 运行原始通知测试**

Run: 与 Step 2 相同。

Expected: PASS；F001/F002/F003 都回调一次，无关 characteristic 为零次。

- [x] **Step 5: 提交原始通知回调**

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechSensor.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift
git commit -m "新增 LinX 原始数据包活动回调" -m "改动原因：连接保活必须独立于解密、解析和血糖有效性。\n\n改动清单：在 F001、F002、F003 处理前同步上报数据包活动，并增加顺序测试。\n\n验证结果：MicroTechSensorHandshakeTests 通过。\n\n影响范围：仅增加 LinX 连接活动信号，不改变数据包解析。"
```

### Task 4: 用 5 分钟数据包检查替换 15 分钟读数检查

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift:850-946, 1232-1237, 1243-1293, 1348-1678, 1737-1766`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift:1836-2076, 2480-3460`

- [x] **Step 1: 把旧 stale reading 测试改成 packet silence 失败测试**

删除对 15 分钟 `lastReadingDate` 的语义断言，改为：

```swift
func testHandshakeStartsFiveMinutePacketSilenceWatchdog()
func testNoPacketForFiveMinutesDisconnectsAndStartsRecovery()
func testAnyPacketRefreshesWatchdogWithoutChangingLastReadingDate()
func testDecryptAndParseFailurePacketsRefreshWatchdog()
func testOldWatchdogCannotDisconnectAfterCurrentPacket()
func testPreHandshakePacketDoesNotStartOrRefreshWatchdog()
func testRetiredSensorPacketDoesNotRefreshCurrentWatchdog()
func testPacketAtDeadlineWinsWhenItClaimsStateFirst()
func testDeleteModeChangeAndSensorReplacementInvalidatePacketWatchdog()
func testNormalSensorDisconnectInvalidatesPacketWatchdog()
func testBroadcastModeNeverStartsPacketWatchdog()
func testBluetoothFailureInvalidatesPacketWatchdogBeforeStartingRecovery()
func testPacketAfterSilenceTimeoutCannotRestartWatchdog()
func testRetiredSensorPacketDoesNotRefreshReplacementWatchdog()
func testPacketWatchdogNeverReadsBluetoothConnectionStateWhileHoldingManagerStateLock()
func testMaintenanceHistoryInvalidAndDuplicatePacketsDoNotChangeLastReadingDate()
```

所有 scheduler 断言使用 `5 * 60`。`lastReadingDate` 先设置为固定值，maintenance/history/invalid/duplicate packet 后仍等于固定值。history 用可被接受并输出的有效 sample，证明 history 处理成功也不会覆盖最后实时血糖时间。

- [x] **Step 2: 运行核心失败测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: FAIL because当前代码安排 15 分钟并只按 accepted glucose 刷新。此前 Task 1、2 测试应继续通过；保存全部 packet watchdog 新测试的 red 证据。

- [x] **Step 3: 增加独立 packet watchdog 状态**

用传感器身份和 manager 代次共同约束检查：

```swift
private enum MicroTechPacketWatchdogState {
    case idle
    case monitoring(
        id: UUID,
        sensorID: ObjectIdentifier,
        managerID: ObjectIdentifier,
        lastPacketAt: Date
    )
    case recovering(id: UUID, sensorID: ObjectIdentifier)
}
```

`MicroTechCGMManagerProtectedState` 保存该状态。把常量改为唯一 `packetSilenceInterval: TimeInterval = 5 * 60`，删除 `activeSensorConnectedAt`、`staleConnectionWatchdogIdentifier` 和 `staleReadingReconnectInterval`。`.monitoring` 只能由已接受的握手创建，sensor disconnect、retire、删除和模式变化必须先把它清成 `.idle`，因此它同时是受保护状态内的“当前连接仍有效”依据。

- [x] **Step 4: 握手成功后初始化检查，任意当前 packet 刷新**

`microTechSensorDidConnect` 只有在 `acceptSensorConnection` 返回 true 后，用同一次状态变更记录 `dateProvider()`、当前 sensor ID 和当前 manager ID，随后安排 5 分钟任务。

实现 delegate callback：

```swift
public func microTechSensor(
    _ sensor: MicroTechSensor,
    didReceivePacketFor characteristic: CBUUID,
    receivedAt: Date
)
```

只允许当前 sensor、`.direct`、未删除、状态为同 sensor 的 `.monitoring` 时，以 `receivedAt` 替换 ID 和 `lastPacketAt` 并安排新任务。`.idle` 和 `.recovering` 不因 packet 自动启动或恢复。

- [x] **Step 5: 原子领取 5 分钟超时并启动 60 秒恢复**

timeout closure 在单次 `mutateProtectedState` 中核对 watchdog ID、sensor ID、manager ID、模式、删除状态、当前 manager 对象身份、`.monitoring` 连接状态和时间差。不得在持有 `lockedManagerState` 时读取 `manager.isConnected`：原始通知来自 manager queue，这会形成 manager queue 与 CGM state lock 的交叉等待。成功后把 packet 状态改为 `.recovering`，同时要求 60 秒状态为 `.idle` 并原子改为 `.timing(newID)`，再捕获当前 `remoteIdentifier`；锁外直接向同一 manager 排队断开和扫描，避免重新进入会同步读取 manager 状态的 `scanForSensor`：

```swift
manager.disconnect()
manager.scan(remoteIdentifier: remoteIdentifier)
```

`monitoring` 与 `.timing`、`.shuttingDown` 保持互斥。其他恢复入口先使 packet watchdog 失效，再启动或保留唯一的 60 秒周期；5 分钟旧任务发现恢复状态不是 `.idle` 时直接失效，不断开连接、不新增 scheduler。

只有成功领取 timeout 的任务能断开。packet、删除、模式变化或传感器替换先修改状态时，旧任务直接返回。

- [x] **Step 6: 清理所有旧 reading watchdog 接口**

移除 `fetchNewDataIfNeeded` 中按 `lastReadingDate` 主动断开的分支，以及 current/history accepted sample 后重新安排 stale watchdog 的调用。只有 accepted current reading 更新 `lastReadingDate`；history 继续负责样本输出、去重和补数状态，但即使有有效样本也不修改 `lastReadingDate`。

- [x] **Step 7: 运行 packet watchdog 和 manager 全部测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: PASS；没有测试继续断言 15 分钟 reading staleness。

- [x] **Step 8: 提交 5 分钟静默检查**

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift
git commit -m "修改 LinX 为五分钟数据包检查" -m "改动原因：有效蓝牙通信不能只用最后血糖时间判断。\n\n改动清单：用独立数据包时间替换 15 分钟读数检查，静默后进入 60 秒恢复。\n\n验证结果：MicroTechCGMManagerTests 通过。\n\n影响范围：仅直连 LinX 的连接保活；血糖时间和广播兼容不变。"
```

## Chunk 3: 回归、文档与主分支交付

### Task 5: 完整回归和文档同步

**Files:**
- Modify: `docs/superpowers/specs/2026-08-03-linx-60-second-reconnect-recovery-design.md`
- Modify: `docs/superpowers/plans/2026-08-03-linx-packet-silence-reconnect.md`
- Modify: `docs/工具与踩坑.md`
- Modify: `PROGRESS.md`

- [x] **Step 1: 运行 MicroTechCGMTests 全量测试**

Run:

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme 'Shared (MicroTechCGM project)' \
  -destination 'platform=iOS Simulator,id=EB9BC703-48AF-483D-87CA-A69B4BCFFC1C' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-derived \
  -disableAutomaticPackageResolution test \
  -only-testing:MicroTechCGMTests
```

Expected: `** TEST SUCCEEDED **`，0 failures。记录实际测试数量，不沿用旧数量。

- [x] **Step 2: 运行完整 workspace 构建**

`LibreTransmitter/LibreTransmitter/NotificationHelperOverride.swift` 是仓库明确忽略的本地配置文件。构建前用 `apply_patch` 临时创建，不提交：

```swift
enum NotificationHelperOverride {
    static var shouldOverrideRequestCriticalPermissions: Bool {
        false
    }
}
```

先验证它确实被忽略且未被跟踪：

```bash
git check-ignore -v LibreTransmitter/LibreTransmitter/NotificationHelperOverride.swift
git ls-files --error-unmatch LibreTransmitter/LibreTransmitter/NotificationHelperOverride.swift
```

Expected: 第一条显示 `LibreTransmitter/LibreTransmitter/.gitignore`；第二条以非零状态结束并说明文件未跟踪。然后运行：

```bash
xcodebuild -workspace LoopWorkspace.xcworkspace -scheme LoopWorkspace \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/loopcloudtest-linx-packet-watchdog-build \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。若出现另一个已在仓库说明且被忽略的本地模板文件，按其现有文档创建最小默认值后重试；若缺少的是应被 Git 跟踪的源码，则本任务仍未满足完成标准，保存精确错误并作为真正阻碍处理，不得写成通过。

无论构建成功或失败，使用 `apply_patch` 删除临时 `NotificationHelperOverride.swift`，再确认 `git status --short` 不显示该文件。

- [x] **Step 3: 汇总每个任务的 red-green 证据**

核对 Task 1 至 Task 4 各自保存的失败输出和随后同一 test class 的通过输出。每一组新增行为都必须在实现前失败、实现后通过；缺少任一组证据时回到对应任务重新执行，不用事后临时反转代替。

- [x] **Step 4: 更新设计、踩坑和进展文档**

设计文档标记代码已实现的条目，并保留“真实 `peripheralDisconnecting` 卡死复验待完成”。`docs/工具与踩坑.md` 记录：

```text
MicroTechCGM 独立 project 的 Shared scheme 在当前 worktree 可能因 LoopKit 搜索路径失败；以 LoopWorkspace.xcworkspace 中的 Shared (MicroTechCGM project) scheme 为权威测试入口。
全局 Git 代理端口失效时，只对当前 xcodebuild 用 GIT_CONFIG_COUNT 覆盖 socks5h://127.0.0.1:1080，不修改用户全局配置。
```

`PROGRESS.md` 顶部状态改为实际结果，并新增倒序日志，commit hash 在最终提交后补齐。

- [x] **Step 5: 检查差异和敏感内容**

Run:

```bash
git diff --check
git status --short
git diff -- MicroTechCGM docs PROGRESS.md
rg -n "PRIVATE KEY|BEGIN CERTIFICATE|token=|password=" MicroTechCGM docs PROGRESS.md
```

Expected: `git diff --check` 无输出；仅计划内文件有改动；不包含密钥、完整数据包、账号、token、证书或本机设备日志。

- [x] **Step 6: 提交文档和最终验证记录**

```bash
git add docs/superpowers/specs/2026-08-03-linx-60-second-reconnect-recovery-design.md \
  docs/superpowers/plans/2026-08-03-linx-packet-silence-reconnect.md \
  docs/工具与踩坑.md PROGRESS.md
git commit -m "文档 记录 LinX 重连验证结果" -m "改动原因：同步 5 分钟数据包检查和 60 秒恢复的实际完成状态。\n\n改动清单：更新设计状态、测试入口、已知限制和进展记录。\n\n验证结果：记录当前 MicroTechCGMTests 与 LoopWorkspace 的真实结果。\n\n影响范围：项目说明与排障文档。"
```

- [ ] **Step 7: 真机正常连接安全检查**

在用户允许且 iPhone 与 LinX 可用时，用完整 `LoopWorkspace` Debug 包安装并启动，确认正常握手后持续收到数据包的 5 分钟内不会误触发重建。若检查失败，先修复、重新执行目标测试、全量测试和完整 build，再进入最终审查。若硬件不可用，明确记录该项待验证；无法稳定制造 `peripheralDisconnecting` 卡死时，只把真实 60 秒重建标为待复验，不得声称真机卡死已验证。

- [x] **Step 8: 独立最终审查**

使用 fresh reviewer 逐条对照设计文档的 26 项验证标准，先做 spec compliance review，再做 code quality review。任何问题由原实现任务修复并重新运行相关测试，直到两轮均批准。

- [x] **Step 9: 提交审查修复并重新完成回归**

每轮审查修复后必须：运行对应目标测试、重新运行 `MicroTechCGMTests` 全量、按 Step 2 重新运行完整 build、更新 `PROGRESS.md` 的实际结果，并用符合 AGENTS.md 的中文 commit 提交。两轮审查批准后执行：

```bash
git diff --check
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: `git diff --check` 无输出；feature worktree 无未提交文件；所有实现、审查修复和文档提交都位于 `origin/main..HEAD`。

- [ ] **Step 10: 合并到 main 并推送**

确认主工作区只有用户原有的 `xcuserdata`、`build/`、`log/` 变化，不纳入提交。然后：

```bash
git -C /Users/liyang/Documents/codex/loopbuild/loopcloudtest merge --ff-only linx-packet-watchdog
git -C /Users/liyang/Documents/codex/loopbuild/loopcloudtest \
  -c http.proxy=socks5h://127.0.0.1:1080 \
  -c https.proxy=socks5h://127.0.0.1:1080 \
  push origin main
git -C /Users/liyang/Documents/codex/loopbuild/loopcloudtest status --short --branch
```

若 push 失败，以同一命令最多再重试两次，不修改全局代理、不使用 `--force`。Expected: `origin/main` 指向最终提交；用户原有未提交文件保持不变；不推送 feature branch。
