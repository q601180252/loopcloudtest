# LinX 完整连接日志实施计划

> **执行要求：** 使用 `superpowers:subagent-driven-development` 执行本计划；若 sub-agent 不可用，则使用 `superpowers:executing-plans`。每个步骤按复选框状态逐项完成。

**目标：** 将 LinX 首次添加和运行期间的诊断信息持续写入 `DeviceLog.json`，包含完整设备标识、key、IV、challenge、发送命令、加密接收包和解密包。

**方案：** 在 `LoopKitUI` 增加可选的首次添加日志能力，由 `DeviceDataManager` 注入现有 `PersistentDeviceLog` 写入器。临时 `MicroTechCGMManager` 在获得正式 delegate 前使用该入口，获得正式 delegate 后原子切换日志目的地。BLE 层记录扫描、连接和 GATT 操作，协议层记录完整密钥与数据包，所有消息使用稳定的 `stage`、`event` 字段和完整大写十六进制。

**技术范围：** Swift、XCTest、CoreBluetooth、LoopKit、LoopKitUI、`PersistentDeviceLog`、Xcode workspace/project。

---

## 文件范围

- 修改 `LoopKit/LoopKitUI/CGMManagerUI.swift`
  - 定义可选的首次添加日志能力。
- 修改 `Loop/Loop/Managers/DeviceDataManager.swift`
  - 创建并注入真实 `PersistentDeviceLog` 写入器。
- 修改 `Loop/LoopTests/LoopTests.swift`
  - 验证首次失败最终出现在真实导出的 `DeviceLog.json`。
- 修改 `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
  - 接收首次添加日志入口，并在扫描前交给临时 manager。
- 修改 `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
  - 保证首次添加与正式 delegate 之间没有遗漏和重复。
- 修改 `MicroTechCGM/MicroTechCGM/Extensions/OSLog.swift`
  - 提供完整数据与 `NSError` 的统一格式。
- 修改 `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
  - 记录扫描、连接、恢复、蓝牙状态和回调缺失。
- 修改 `MicroTechCGM/MicroTechCGM/MicroTechPeripheralManager.swift`
  - 记录全部 GATT 尝试、结果、超时和完整数据。
- 修改 `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`
  - 记录完整密钥、命令、加密包和解密包。
- 修改 `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`
  - 覆盖日志切换、扫描、连接和各 GATT 分支。
- 修改 `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
  - 覆盖完整握手材料、命令和数据包。
- 修改 `docs/工具与踩坑.md`
  - 记录首次添加日志盲区与敏感报告规则。
- 修改 `PROGRESS.md`
  - 记录完成内容、验证证据、commit 和真实 push 状态。

## 第一部分：首次添加日志持久化

### 任务 1：增加可选的首次添加日志能力

**涉及文件：**

- `LoopKit/LoopKitUI/CGMManagerUI.swift`
- `Loop/Loop/Managers/DeviceDataManager.swift`
- `Loop/LoopTests/LoopTests.swift`
- `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
- `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **步骤 1：先写 manager 与 coordinator 的失败测试**

新增：

```swift
func testSetupInstallsOnboardingLogHandlerBeforeScanning()
func testOnboardingLogHandlerReceivesScanFailureBeforeManagerCreation()
func testFormalDelegateSuppressesOnboardingHandlerToAvoidDuplicateLogs()
func testConcurrentFormalDelegateTransitionLogsEveryMessageExactlyOnce()
func testFailedSetupDoesNotCreateOrOnboardManager()
```

验证标准：

- `completeSetup()` 必须在 `scan(remoteIdentifier:)` 前安装日志入口。
- 模拟 scan 失败时，首次添加日志收到 `MicroTechLinXCGMManager`。
- 有效会话产生前，`didCreateCGMManager` 与 `didOnboardCGMManager` 均未调用。
- 正式 `CGMManagerDelegate` 安装后，同一条日志只进入正式 delegate。
- 并发切换时，所有带唯一编号的日志在两个目的地合计恰好出现一次。

- [ ] **步骤 2：在实现 factory 前写真实注入和导出失败测试**

在 `Loop/LoopTests/LoopTests.swift` 新增：

```swift
func testConfigureCGMOnboardingDeviceLoggingExportsLinXScanFailure()
```

建立同时符合 `CGMManagerOnboarding` 和新日志协议的最小 fake controller。测试必须调用 `DeviceDataManager.setupCGMManagerUI` 实际分支使用的同一个 helper，不能手工构造另一条 closure。

测试流程：

1. 在临时目录创建真实 `PersistentDeviceLog`。
2. 调用尚未实现的 `DeviceDataManager.configureCGMOnboardingDeviceLogging(...)`。
3. 通过 fake controller 收到的 handler 写入 LinX scan 失败。
4. 使用 `getLogEntries` 等待 Core Data 保存。
5. 调用 `PersistentDeviceLog.export(...)`。
6. 解码 JSON 并严格断言：

```text
managerIdentifier=MicroTechLinXCGMManager
deviceIdentifier=22222DKCZE
type=error
message=stage=scan event=failed reason=timeout
```

- [ ] **步骤 3：运行测试并确认 RED**

```bash
xcodebuild test \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopWorkspace \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:LoopTests/LoopTests/testConfigureCGMOnboardingDeviceLoggingExportsLinXScanFailure
```

预期：两个测试组均因日志协议、真实注入 helper 和路由状态不存在而失败。

- [ ] **步骤 4：在 `LoopKitUI` 增加可选能力**

在 `CGMManagerUI.swift` 增加：

```swift
public typealias CGMManagerOnboardingDeviceLogHandler = (
    _ managerIdentifier: String,
    _ deviceIdentifier: String?,
    _ type: DeviceLogEntryType,
    _ message: String
) -> Void

public protocol CGMManagerOnboardingDeviceLogging: AnyObject {
    var onboardingDeviceLogHandler: CGMManagerOnboardingDeviceLogHandler? { get set }
}
```

不得把它设为 `CGMManagerOnboarding` 的必选要求，其他 CGM 添加页面保持不变。

- [ ] **步骤 5：增加真实 handler factory 和实际注入分支**

在 `DeviceDataManager.swift` 增加可测试的内部 factory：

```swift
static func makeCGMOnboardingDeviceLogHandler(
    deviceLog: PersistentDeviceLog
) -> CGMManagerOnboardingDeviceLogHandler
```

该 closure 直接调用：

```swift
deviceLog.log(
    managerIdentifier: managerIdentifier,
    deviceIdentifier: deviceIdentifier,
    type: type,
    message: message
)
```

再增加：

```swift
static func configureCGMOnboardingDeviceLogging(
    on viewController: CGMManagerViewController,
    deviceLog: PersistentDeviceLog
)
```

`setupCGMManagerUI` 的 `.userInteractionRequired` 实际分支和集成测试必须调用这一 helper。handler 必须在页面返回给调用方前完成注入。

- [ ] **步骤 6：将 handler 接入临时 LinX manager**

让 `MicroTechUICoordinator` 符合 `CGMManagerOnboardingDeviceLogging`。在 `manager.scanForSensor()` 前完成适配，并补充：

```text
managerIdentifier=MicroTechLinXCGMManager
deviceIdentifier=当前可用的完整传感器序列号
```

禁止提前调用 `didCreateCGMManager`。只有 `hasValidSensorSession == true` 后，才能保持现有顺序调用 `didCreateCGMManager` 和 `didOnboardCGMManager`。

`MicroTechCGM` core 不得导入 `LoopKitUI`。在 core 内定义仅依赖 `LoopKit` 的类型：

```swift
public typealias MicroTechOnboardingDeviceLogHandler = (
    _ deviceIdentifier: String?,
    _ type: DeviceLogEntryType,
    _ message: String
) -> Void
```

`MicroTechUICoordinator` 负责补充 `MicroTechCGMManager.pluginIdentifier` 并完成两个 closure 类型之间的适配。

- [ ] **步骤 7：使用一个同步状态切换日志目的地**

在 `MicroTechCGMManager` 内增加受同一把锁保护的状态：

```swift
enum DeviceLogDestination {
    case onboarding(MicroTechOnboardingDeviceLogHandler)
    case formalDelegate
    case systemOnly
}
```

规则：

- 安装首次添加 handler 时切换为 `.onboarding`。
- 设置非空正式 delegate 时，先保存 delegate，再在同一同步边界切换为 `.formalDelegate` 并丢弃临时 handler。
- `logDeviceCommunication` 每条消息只读取一次目的地快照。
- `.formalDelegate` 不再向首次添加 handler 重复发送。
- `.systemOnly` 保留现有 OSLog 行为。

并发测试必须证明所有唯一编号无缺失、无重复。

- [ ] **步骤 8：运行任务 1 测试并确认 GREEN**

重新运行步骤 3 的两个命令。

预期：

- 所选 `MicroTechCGMManagerTests` 全部通过。
- Loop 集成测试能从真实导出的 JSON 读取目标日志。

### 任务 2：加强真实 `DeviceLog.json` 导出断言

**涉及文件：**

- `Loop/LoopTests/LoopTests.swift`
- `Loop/Loop/Managers/DeviceDataManager.swift`

- [ ] **步骤 1：补充测试输出流**

使用任务 1 的同一 factory，增加最小测试输出流：

```swift
private final class DeviceLogTestOutputStream: DataOutputStream {
    private(set) var data = Data()
    var streamError: Error? { nil }
    func write(_ data: Data) throws { self.data.append(data) }
    func finish(sync: Bool) throws {}
}
```

- [ ] **步骤 2：验证导出 JSON 的准确内容**

- 解码 JSON 数组，不做字符串片段匹配。
- 目标 LinX scan failure 必须恰好一条。
- 消息不得截断。
- fake controller 的 handler 必须由 `configureCGMOnboardingDeviceLogging` 注入。

重新运行任务 1 的 Loop 测试。预期完整包含 `MicroTechLinXCGMManager`、`22222DKCZE`、`error` 和完整 scan failure。

- [ ] **步骤 3：提交首次添加日志改动**

只提交任务 1 和任务 2 的文件，标题：

```text
新增 LinX 首次连接导出日志
```

commit 正文包含改动原因、改动清单、验证结果、影响范围。此时只做本地 commit，不提前 push。

## 第二部分：完整 BLE 与协议证据

### 任务 3：增加稳定格式及完整扫描、连接、GATT 日志

**涉及文件：**

- `MicroTechCGM/MicroTechCGM/Extensions/OSLog.swift`
- `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
- `MicroTechCGM/MicroTechCGM/MicroTechPeripheralManager.swift`
- `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **步骤 1：先写 formatter、scan、connect 失败测试**

新增：

```swift
func testDiagnosticErrorFieldsIncludeDomainCodeAndDescription()
func testScanLifecycleLogsStartedFoundAcceptedRejectedStoppedAndTimeout()
func testConnectionLifecycleLogsAttemptedSucceededFailedTimeoutAndDisconnected()
func testRestoredPeripheralLogsRestorationSourceAndIdentifier()
func testBluetoothStateLossLogsOldAndNewStateAndStoppedOperation()
func testMissingPeripheralManagerCallbackIncludesIdentifierAndCallback()
func testBluetoothSendAndReceiveTypesMapToDeviceLogTypes()
```

严格断言以下稳定结构：

```text
stage=scan event=started requestedIdentifier=...
stage=scan event=found identifier=... name=... advertisement=...
stage=scan event=accepted identifier=... reason=...
stage=scan event=rejected identifier=... reason=...
stage=scan event=stopped reason=...
stage=scan event=timeout requestedIdentifier=...
stage=connect event=attempted identifier=...
stage=connect event=succeeded identifier=...
stage=connect event=failed identifier=... errorDomain=... errorCode=... errorDescription=...
stage=connect event=timeout identifier=...
stage=connect event=disconnected identifier=... errorDomain=... errorCode=... errorDescription=...
stage=restore event=restored identifier=... source=centralManager
stage=bluetooth event=state_changed oldState=... newState=... stoppedOperation=...
```

名称和 advertisement 使用完整稳定格式，缺失值明确写为 `nil`。

- [ ] **步骤 2：为独立 GATT 分支写失败测试**

新增：

```swift
func testDiscoverServicesErrorLogsFailedWithNSErrorFields()
func testDiscoverCharacteristicsErrorLogsFailedWithNSErrorFields()
func testNotificationStateErrorLogsFailedWithNSErrorFields()
func testReadCallbackErrorLogsFailedWithNSErrorFields()
func testReadCallbackWithoutValueLogsFailedReasonMissingValue()
func testNotificationCallbackErrorLogsFailedWithNSErrorFields()
func testNotificationCallbackWithoutValueLogsFailedReasonMissingValue()
func testWriteCallbackErrorLogsFailedWithNSErrorFields()
func testGattOperationTimeoutLogsPendingOperationAndTarget()
func testWriteWithResponseLogsAttemptSucceededAndFullPayload()
func testWriteWithoutResponseLogsAttemptAndSubmittedWithoutSuccess()
```

必须通过真实 delegate callback 使用的同一个 helper 验证。若 XCTest 无法可靠构造 CoreBluetooth 对象，只增加最小内部 callback-result 接口，并让生产 callback 调用这一接口。

使用超过 32 bytes 的数据，断言尾部仍存在，且没有 `rawPrefix`、`prefix` 或 `...`。

`.withoutResponse` 只允许：

```text
event=attempted
event=submitted writeType=withoutResponse noCallback=true
```

不得产生 `event=succeeded`。

- [ ] **步骤 3：运行测试并确认 RED**

```bash
xcodebuild test \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

预期：稳定 formatter、scan/connect 生命周期、独立 GATT 分支和 send/receive 类型尚不存在，测试失败。

- [ ] **步骤 4：增加统一完整格式**

在 `Extensions/OSLog.swift` 增加：

```swift
enum MicroTechDiagnosticLog {
    static func dataFields(lengthName: String, hexName: String, data: Data) -> String
    static func errorFields(_ error: Error?) -> String
}
```

`errorFields` 将错误转为 `NSError`，完整输出：

```text
errorDomain=<domain> errorCode=<code> errorDescription=<localizedDescription>
```

`dataFields` 使用 `Data.microTechHexadecimalString`，不得截断。

- [ ] **步骤 5：实现稳定 scan/connect 生命周期日志**

生产 `CBCentralManagerDelegate` callback 与 timeout handler 必须使用同一 formatter：

- scan：开始、每个发现、接受或拒绝及原因、停止、超时。
- connect：尝试、成功、callback 失败、超时、断开。
- restore：完整 identifier 和恢复来源。
- Bluetooth state：旧状态、新状态和被中止的操作。
- callback：找不到对应 peripheral manager 时记录 callback 名与 identifier。

所有有系统错误的失败都记录完整 domain、code、description；每条消息保留当时可用的完整设备 identifier。

- [ ] **步骤 6：实现 GATT 操作生命周期日志**

给 `MicroTechBluetoothLogType` 增加 `.send`、`.receive`，分别映射到 `DeviceLogEntryType.send`、`.receive`。将 `MicroTechPeripheralManager` 的 handler 接到 `MicroTechBluetoothManager.logHandler`。

使用稳定消息：

```text
stage=gatt event=attempted operation=discoverServices service=...
stage=gatt event=succeeded operation=discoverServices services=...
stage=gatt event=failed operation=discoverServices ...error fields...
stage=gatt event=attempted operation=write characteristic=F002 writeType=withResponse len=... hex=...
stage=gatt event=succeeded operation=write characteristic=F002
stage=gatt event=submitted operation=write characteristic=F002 writeType=withoutResponse noCallback=true len=... hex=...
stage=gatt event=received operation=notification characteristic=F003 len=... hex=...
stage=gatt event=failed operation=read characteristic=F003 reason=missingValue
stage=gatt event=timeout operation=discoverCharacteristics service=F000
```

在调用 CoreBluetooth 前记录完整 write payload。service、characteristic、notification、read、write 各 callback 均需：

- 错误时记录 `failed` 和完整 `NSError`。
- read/notification 无 value 时记录 `reason=missingValue`。
- timeout 时记录待处理 operation 与 service/characteristic。
- 收到 value 后先记录完整数据，再向上传递。
- `.withoutResponse` 以 `submitted noCallback=true` 结束；只有 `.withResponse` callback 能记录 `succeeded`。

- [ ] **步骤 7：记录缺失 callback owner 和 Bluetooth 状态丢失**

将连接、断开和通知 callback 中静默返回的分支改为：

```text
stage=callback event=ignored callback=<name> identifier=<uuid> reason=missingPeripheralManager
```

扫描或连接期间 Bluetooth 离开 `poweredOn` 时，记录旧状态、新状态和被停止的操作。

- [ ] **步骤 8：运行任务 3 测试并确认 GREEN**

重新运行步骤 3 的命令。预期全部通过，所有独立失败分支均有稳定消息，长包完整，`.withoutResponse` 不会被误记为已确认成功。

### 任务 4：记录完整 Aidex 密钥、命令、加密包和解密包

**涉及文件：**

- `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`
- `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
- `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **步骤 1：先写完整 key 和 packet 失败测试**

新增或扩展：

```swift
func testHandshakeLogsCompleteBasePairingAndSessionMaterial()
func testHandshakeLogsCompleteCommandsBeforeWrite()
func testNotificationLogsCompleteEncryptedAndDecryptedPackets()
func testDecryptFailureKeepsCompleteEncryptedPacket()
func testParserFailureKeepsCompletePlainPacket()
func testHistoryAndActivationCommandsLogCompleteHex()
func testManagerAcceptedReadingLogsCompleteRawPacket()
```

逐字比较以下完整大写 hex：

- base key、base IV。
- 原始与标准化后的 F001 pairing key。
- F002 challenge。
- session key、session IV。
- cmd10。
- 激活命令。
- history request。
- 加密 F002/F003 输入。
- 解密后的明文数据。

至少一个输入超过旧的 32-byte prefix，并断言尾部存在。

- [ ] **步骤 2：运行测试并确认 RED**

```bash
xcodebuild test \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MicroTechCGMTests/MicroTechSensorHandshakeTests \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

预期：当前日志仍只有长度或 prefix，测试失败。

- [ ] **步骤 3：记录完整握手材料**

在 `MicroTechSensor.start()` 输出：

```text
stage=handshake event=base_material serial=... baseKey=... baseIV=...
stage=handshake event=pairing_key source=... rawPairingKey=... pairingKey=...
stage=handshake event=challenge characteristic=F002 len=... challengeHex=...
stage=handshake event=session_material sessionKey=... sessionIV=...
```

标准化前保留原始 F001 value，成功标准化后记录最终 key。

- [ ] **步骤 4：记录每条完整发送命令**

每次 write 前输出：

```text
stage=packet event=send_attempted characteristic=<F001|F002> command=<name> len=... hex=...
```

成功后输出 `event=send_succeeded`。失败时输出 `event=send_failed`、同一份完整 hex 和完整 `NSError`。

覆盖：

- F001 base key。
- F001 pairing response。
- cmd10。
- cmd31、cmd20、cmd35、cmd34、cmd11。
- history request。

- [ ] **步骤 5：记录完整加密和解密数据**

notification 入口：

```text
stage=packet event=received characteristic=F003 encryptedLen=... encryptedHex=...
```

解密后：

```text
stage=packet event=decrypted characteristic=F003 plainLen=... plainHex=...
```

解密失败保留 `encryptedHex`；CRC 或 parser 失败保留 `plainHex`；所有 LinX `rawPrefix`、`hexPrefix` 改为完整 `rawHex`、`plainHex`。

- [ ] **步骤 6：运行任务 4 测试并确认 GREEN**

重新运行步骤 2 的命令。预期所有完整 key、命令和 packet 的逐字断言通过。

- [ ] **步骤 7：提交完整 BLE 证据改动**

只提交任务 3 和任务 4 的文件，标题：

```text
新增 LinX 完整密钥与数据包日志
```

commit 正文包含改动原因、改动清单、验证结果、影响范围。此时只做本地 commit，不提前 push。

## 第三部分：文档与完整验证

### 任务 5：记录行为并完成全部验证

**涉及文件：**

- `docs/工具与踩坑.md`
- `PROGRESS.md`

- [ ] **步骤 1：更新排查文档**

增加 2026-07-30 LinX 条目，说明：

- 首次添加失败为什么没有出现在旧 `DeviceLog.json`。
- 独立首次添加 handler 如何补齐日志且不安装失败 manager。
- 如何用 `stage`、`event` 判断停止位置。
- Loop Report 现在包含完整 LinX key 和解密数据。
- 报告只能交给可信分析人员。

- [ ] **步骤 2：运行完整 MicroTech 测试**

```bash
xcodebuild test \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

预期：全部测试通过，0 failure。

- [ ] **步骤 3：运行 Loop 真实导出测试**

重新运行任务 1 的 Loop 测试命令。预期真实导出 JSON 测试通过。

- [ ] **步骤 4：构建 workspace**

```bash
xcodebuild build \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopWorkspace \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

如果 package resolution 使用失效的 `127.0.0.1:1081`，使用已经验证的单命令 `127.0.0.1:1082` 覆盖重跑，不修改用户全局 Git 配置。

预期：构建成功。若无关的既有 target 阻断构建，记录准确 target 与错误，然后运行能够覆盖 `Loop`、`LoopKitUI`、`MicroTechCGM`、`MicroTechCGMUI` 的最小构建。

- [ ] **步骤 5：检查格式与敏感文件边界**

```bash
git diff --check
git status --short
git diff --cached --name-only
```

确认：

- 没有空白格式错误。
- 未暂存 `LoopWorkspace.xcworkspace/xcuserdata/`。
- 未暂存 `log/`。
- 未将真实 key 或设备日志作为 fixture 提交。

- [ ] **步骤 6：本地提交实现与排查文档**

若任务 1 至任务 4 尚未按范围提交，先完成对应本地 commit。验证后再本地提交 `docs/工具与踩坑.md`，并记录实际 hash：

```bash
git log -3 --format='%H %s'
```

此时不 push，保证代码、说明、验证和第一版 `PROGRESS.md` 一起推送。

- [ ] **步骤 7：在 `PROGRESS.md` 先记录待推送状态**

新增最新条目，包含：

- 任务。
- 完整文件清单。
- RED/GREEN 测试证据。
- 完整测试与构建结果。
- Loop Report 敏感信息决定。
- 步骤 6 产生的真实实现与排查文档 commit hash。
- `push 状态：待推送`。

- [ ] **步骤 8：本地提交第一版进度记录**

标题：

```text
文档 更新 LinX 完整日志进展
```

commit 正文包含改动原因、改动清单、验证结果、影响范围。记录该 progress commit 的实际 hash：

```bash
git rev-parse HEAD
```

- [ ] **步骤 9：统一 push 并核对远端**

将所有本地 commit push 到 `origin/main`。失败时最多重试 3 次。全局 `1081` 不可用时，使用单命令 `1082` 覆盖，不修改全局配置。

```bash
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

记录真实结果：

- 成功：本地 `HEAD` 与远端 `refs/heads/main` 相同。
- 连续 3 次失败：保留最后一次完整错误，新 commit 均视为仅存在本地。

- [ ] **步骤 10：将待推送状态改为真实结果**

修改同一条 `PROGRESS.md`：

- 补充实现、排查文档和第一版进度记录的实际 commit hash。
- 成功时改为 `已推送到 origin/main`，并写入步骤 9 验证的远端 hash。
- 失败时改为 `本地 commit 未推送`，并写入最后一次准确错误。

本地提交该状态修正：

```text
文档 更新 LinX 日志推送状态
```

该 commit 不自我引用；条目引用的是已经实际核对远端状态的前一条 progress/document commit。

- [ ] **步骤 11：push 最终状态并完成远端验证**

步骤 9 成功时，push 最终状态 commit，失败最多重试 3 次。步骤 9 失败时，也对更新后的分支再尝试最多 3 次；如果这次成功，需再将 `PROGRESS.md` 从 `本地 commit 未推送` 修正为 `已推送到 origin/main`，提交、push 并重新验证。

```bash
git status --short --branch
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

完成标准：

- 本地 `HEAD`、`origin/main`、远端 `refs/heads/main` 相同。
- 用户已有 `xcuserdata` 和未跟踪 `log/` 保持不变。
- 若最终 push 连续 3 次仍失败，最新本地 `PROGRESS.md` 必须写明 `本地 commit 未推送`、准确错误和本地 hash，回复中不得声称远端可用。
