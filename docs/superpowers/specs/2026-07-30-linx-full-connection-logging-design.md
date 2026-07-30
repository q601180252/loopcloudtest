# LinX 全连接日志设计

## 目标

让 LinX 从首次添加到长期运行的全部连接过程进入现有 Loop Report。导出 `DeviceLog.json` 后，应能直接判断问题发生在扫描、设备筛选、蓝牙连接、服务配置、配对、数据解密、数据解析或自动重连中的哪一步。

本设计按用户确认的要求，持续记录 LinX 密钥、完整发送包、完整加密接收包和完整解密包，不做截断或隐藏。

## 当前问题

LinX 首次添加时，`MicroTechUICoordinator` 会创建临时 manager 并开始扫描，但只有完成有效传感器会话后才通知 Loop 已创建 CGM manager。

`MicroTechCGMManager` 的设备日志通过 `CGMManagerDelegate` 写入 `PersistentDeviceLog`。首次连接成功前 manager 尚未交给 `DeviceDataManager`，因此没有 delegate，扫描、连接和配对日志只进入系统日志，不会进入 Loop Report。

这会形成观测盲区：首次连接越早失败，导出的 `DeviceLog.json` 越没有 LinX 证据。

## 设计结论

### 1. 为首次添加注入独立日志入口

不提前调用 `didCreateCGMManager`，避免首次连接失败时把未完成配置的 LinX 安装成当前 CGM。

在 `LoopKitUI` 增加一个可选能力协议：

```swift
public protocol CGMManagerOnboardingDeviceLogging: AnyObject {
    var onboardingDeviceLogHandler: ((
        _ managerIdentifier: String,
        _ deviceIdentifier: String?,
        _ type: DeviceLogEntryType,
        _ message: String
    ) -> Void)? { get set }
}
```

只有需要在创建完成前记录日志的添加页面实现该协议，不修改其它 CGM 的现有行为。

`DeviceDataManager.setupCGMManagerUI` 得到 `.userInteractionRequired` 的添加页面后：

1. 检查页面是否实现 `CGMManagerOnboardingDeviceLogging`。
2. 注入一个写入现有 `PersistentDeviceLog` 的 closure。
3. closure 使用添加页面提供的 `managerIdentifier`、`deviceIdentifier`、日志类型和消息原样保存。

`MicroTechUICoordinator` 实现该协议。点击搜索并创建 `MicroTechCGMManager` 时，把 handler 传给 manager，再启动扫描。

`MicroTechCGMManager.logDeviceCommunication` 的选择顺序为：

1. manager 已有正式 `CGMManagerDelegate` 时，只通过正式 delegate 写日志。
2. 尚未完成添加且没有正式 delegate 时，通过 onboarding handler 写日志。
3. 两个入口都不存在时，仍保留现有系统日志。

完成有效传感器会话后，原有流程继续调用：

```swift
cgmManagerOnboardingDelegate?.cgmManagerOnboarding(
    didCreateCGMManager: manager
)
cgmManagerOnboardingDelegate?.cgmManagerOnboarding(
    didOnboardCGMManager: manager
)
```

正式 delegate 安装后清除 onboarding handler，避免重复写入。添加失败、关闭页面或 App 重启都不会把临时 manager 持久化为当前 CGM；重新进入添加页面会得到新的临时 manager 和新的日志入口。

### 2. 连接日志沿用 `DeviceLog.json`

不新增独立日志文件。所有 LinX 日志继续使用：

```text
managerIdentifier = MicroTechLinXCGMManager
```

并按现有类型写入：

- `connection`：扫描、连接、配置、订阅、配对状态和断开。
- `send`：完整发送数据。
- `receive`：完整接收数据、完整解密数据和解析结果。
- `error`：超时、拒绝、连接失败、配置失败、配对失败、解密失败和解析失败。

首次添加、前台恢复、后台恢复、自动重连、历史请求和正常接收血糖都使用同一日志入口。

### 3. 必须记录的连接阶段

#### 扫描

- 扫描请求时间。
- CoreBluetooth 当前状态。
- 目标 service UUID。
- 保存的蓝牙标识。
- 每个发现设备的蓝牙标识、广播名称、系统名称和 RSSI。
- 接受或拒绝设备的结果及原因。
- 扫描停止和扫描超时。

#### 蓝牙连接

- 开始连接。
- 连接成功。
- 连接超时。
- 系统连接失败。
- 主动断开。
- 被设备断开。
- 系统错误 domain、code 和完整描述。
- CoreBluetooth 恢复来源。

#### service 和 characteristic

- service 发现 `attempted`、`succeeded` 或 `failed`。
- characteristic 发现 `attempted`、`succeeded` 或 `failed`。
- `F001`、`F002`、`F003` 是否存在。
- 通知订阅 `attempted`、`succeeded` 或 `failed`。
- 读取 `attempted`、`succeeded` 或 `failed`。
- 写入 `attempted`、`succeeded` 或 `failed`。
- 通知回调返回 error 或没有 value。
- 无响应写入在提交给 CoreBluetooth 前记录完整数据，并明确记录没有成功回调。
- 每一步的超时位置。

#### Aidex 配对

- 设备名称和传感器序列号。
- 基础 key。
- 基础 IV。
- `F001` 收到的原始 pairing key。
- 规范化后的 pairing key。
- `F002` challenge 完整内容。
- 派生后的 session key。
- 派生后的 session IV。
- pairing key 来源是 `F001` 还是 fallback。
- 配对超时原因。
- 握手最终成功或失败。

#### 回调和状态异常

- 扫描期间蓝牙状态变为非 `poweredOn`。
- 连接、断开或通知回调找不到对应 peripheral manager。
- service、characteristic、通知、读取或写入回调返回 error。
- 读取回调没有 value。
- 发送数据在进入 CoreBluetooth 前构造失败。
- 解密失败时保留完整 encrypted hex。
- CRC 或解析失败时保留完整 plain hex。
- 所有系统错误记录 domain、code 和完整描述。

### 4. 必须记录的完整通信数据

所有二进制内容使用大写十六进制，不带空格，不截断：

```text
characteristic=F002 direction=send len=18 hex=...
characteristic=F003 direction=receive encryptedLen=20 encryptedHex=...
characteristic=F003 direction=decrypt plainLen=20 plainHex=...
```

需要覆盖：

- `F001` 的全部读写和通知。
- `F002` 的全部读写和通知。
- `F003` 的全部通知。
- `cmd10`。
- 激活命令 `cmd31`、`cmd20`、`cmd35`、`cmd34`、`cmd11`。
- 历史请求命令和历史返回。
- 当前血糖包。
- 状态包和暂不支持的包。
- CRC、解密和解析失败时的完整输入。

同一数据允许在不同阶段重复记录，例如加密输入、解密输出和解析结果分别记录，以便核对数据在哪一步发生变化。

### 5. 日志格式

连接阶段日志使用稳定字段，避免只写自然语言：

```text
stage=scan event=started service=181F remoteIdentifier=nil
stage=connect event=failed identifier=... errorDomain=... errorCode=...
stage=handshake event=session_material sessionKey=... sessionIV=...
stage=packet event=received characteristic=F003 len=... encryptedHex=...
stage=packet event=decrypted characteristic=F003 len=... plainHex=...
```

稳定字段用于后续脚本统计，自然语言说明只作为补充。

每个可失败操作至少记录 `attempted`，并以 `succeeded` 或 `failed` 结束。日志自身已有时间戳，本轮不额外计算操作耗时。

### 6. 数据保留与共享风险

LinX 全运行周期持续记录以下内容：

- 可用于识别设备的信息。
- 配对和会话密钥。
- 完整蓝牙通信数据。
- 解密后的传感器数据。

这些内容会随 Loop Report 一起导出，并按现有 `PersistentDeviceLog` 保留周期清理。报告只能发送给可信分析人员，不应公开上传或附在公开 issue。

本轮不增加隐藏、脱敏、截断、开关或自动清除逻辑。

## 测试设计

### 首次添加日志

- `DeviceDataManager` 必须为实现 `CGMManagerOnboardingDeviceLogging` 的添加页面注入真实日志入口。
- 创建 manager 后，onboarding handler 必须在 `scanForSensor()` 前设置。
- 扫描失败时，日志通过 onboarding handler 进入 `PersistentDeviceLog`。
- 添加失败、关闭页面或重启时不得把临时 manager 保存为当前 CGM。
- 正式 delegate 安装后不得重复写入同一条日志。
- `didOnboardCGMManager` 在有效会话前不得发生。
- `didCreateCGMManager` 在有效会话前不得发生。
- 有效会话后只调用一次 `didCreateCGMManager`。
- 有效会话后只调用一次 `didOnboardCGMManager`。

### `DeviceLog.json` 集成验证

使用临时目录创建真实 `PersistentDeviceLog`：

1. 通过 `DeviceDataManager` 使用的 onboarding handler 入口写入一次模拟扫描失败。
2. 等待异步保存完成。
3. 调用现有 Critical Event Log 导出接口生成 JSON。
4. 解码导出结果。
5. 断言存在：
   - `managerIdentifier=MicroTechLinXCGMManager`
   - 正确的 `deviceIdentifier`
   - `type=error`
   - `stage=scan`
   - 完整消息内容

该测试必须读取实际导出 JSON，不能只断言 closure 被调用。

### 密钥日志

- 基础 key 和 IV 完整记录。
- `F001` 原始 pairing key 与规范化 pairing key 完整记录。
- `F002` challenge 完整记录。
- session key 和 session IV 完整记录。
- 测试断言日志中没有 `prefix`、省略号或截断结果。

### 数据包日志

- 发送命令包含 characteristic、长度和完整 hex。
- 接收通知包含 characteristic、长度和完整 encrypted hex。
- 解密成功包含完整 plain hex。
- 解密失败仍保留完整 encrypted hex。
- CRC 或解析失败仍保留完整 plain hex。
- 无响应写入在调用 CoreBluetooth 前记录完整 hex 和 `attempted`。
- service、characteristic、通知、读取和写入的 error 回调包含 `failed`、error domain、code 和完整描述。
- 蓝牙状态在扫描期间关闭时包含扫描终止原因。
- 找不到 peripheral manager 的回调包含 peripheral identifier 和回调名称。
- 当前包、历史包、状态包和未知包都保留完整内容。

### 回归验证

- `MicroTechCGM` 全量测试通过。
- LinX 添加流程测试通过。
- `git diff --check` 通过。
- `LoopWorkspace` 使用当前有效 scheme 完成最小构建验证。

## 完成标准

- 首次添加 LinX 失败后导出的 `DeviceLog.json` 包含 LinX 扫描或连接日志。
- 每次失败都能从最后一条 `stage` 日志判断停止位置。
- 密钥、完整发送包、完整加密接收包和完整解密包均可在 Loop Report 中找到。
- 已连接后的后台恢复和自动重连继续记录相同级别的完整日志。
- 首次连接失败不会把临时 LinX manager 保存为当前 CGM。
- 正式连接后 onboarding 与正式日志入口之间无缺失、无重复。
- 不新增独立导出步骤。
- 测试、文档、`PROGRESS.md`、commit 和 push 全部完成。
