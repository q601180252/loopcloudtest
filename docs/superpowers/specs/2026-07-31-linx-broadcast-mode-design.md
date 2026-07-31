# LinX 广播数据模式设计

## 目标

在 MicroTech LinX 添加 CGM 时，让用户选择数据获取方式：

1. `直接连接`：保持现有 BLE 连接、配对、通知包和历史补包能力。
2. `广播数据`：只扫描 Aidex/LinX 广播包，从广播数据中解析最新血糖，不主动建立 GATT 连接。

本设计用于解决用户只想从微泰设备广播中获取最新血糖、减少与官方 App 连接冲突的问题。广播模式只负责最新或近实时血糖，不读取完整历史。

## 当前依据

当前仓库已有 MicroTech LinX 插件：

- `MicroTechCGMPlugin/Info.plist` 注册 `MicroTech LinX`。
- `MicroTechUICoordinator` 负责首次添加流程。
- `MicroTechCGMManager` 保存状态、扫描设备、接收血糖并转成 Loop `NewGlucoseSample`。
- `MicroTechBluetoothManager` 已在 `didDiscover` 中拿到完整 `advertisementData`，并能记录广播内容。
- `MicroTechAidexParser` 已支持连接后的 `0x01` 当前血糖包和 `0x23` 历史包。

`diaboxkotlin` 中 Aidex 代码已经验证广播包可解析血糖：

- 扫描回调读取 `scanRecord.bytes`。
- `GlucoseParser.parseAdvertis(...)` 查找厂商数据 `0x0059`。
- 厂商数据布局为 `timeOffset/status/calTemp/trend/records`。
- 每条广播记录 3 字节，第一字节是血糖值，最多取 3 条，第一条作为最新值。
- 广播解析不使用 AES key，不需要连接后通知包解密。

## 用户流程

### 首次添加

1. 用户进入 Loop 的 `Add CGM`。
2. 选择 `MicroTech LinX`。
3. MicroTech 添加页显示两个选项：

| 选项 | 说明 |
|---|---|
| `直接连接` | 连接 LinX，支持通知包、历史补包和完整连接日志 |
| `广播数据` | 不连接设备，只扫描广播包并读取最新血糖 |

4. 用户选择模式后点击继续。
5. 进入现有设置页并开始扫描。
6. 扫描到目标设备后：
   - 直接连接模式：沿用当前连接流程。
   - 广播数据模式：解析广播，拿到有效血糖后完成 CGM onboarding。

### 设置页

MicroTech 设置页新增显示当前数据模式：

- `Data Mode: Direct Connection`
- `Data Mode: Broadcast Data`

保留现有操作：

- `Scan for Sensor`
- `Upload Readings`
- `Delete CGM`

本轮不在设置页中做模式切换。要切换模式，删除 CGM 后重新添加。这样避免直连状态、广播状态、历史游标和设备标识混杂。

## 状态保存

`MicroTechCGMManagerState` 新增字段：

```text
connectionMode
```

取值：

| 值 | 含义 |
|---|---|
| `direct` | 直接连接 |
| `broadcast` | 广播数据 |

兼容旧状态：

- 旧版本没有 `connectionMode` 时，默认恢复为 `direct`。
- 删除 CGM 时清空模式相关运行状态，但保留默认直接连接行为。

## 广播解析

新增 `MicroTechAidexBroadcastParser`，只处理 BLE 广播包，不复用连接通知包解析器。

解析规则：

1. 输入为完整 BLE advertising payload 或 iOS `manufacturer data`。
2. 查找厂商数据 `0x0059`。
3. 按 little-endian 读取：
   - `timeOffset`：2 字节。
   - `status`：1 字节。
   - `calTemp`：1 字节。
   - `trend`：1 字节，有符号。
   - `records`：每条 3 字节，最多 3 条。
4. 每条记录：
   - 第 1 字节：`glucoseMgdl`。
   - 第 2 字节：保留字段，记录到 raw log，不作为治疗数据。
   - 第 3 字节：`quality`。
5. `records.first` 作为最新广播血糖。
6. 样本号使用该记录的 `timeOffset`。
7. `rawBytes` 保存广播厂商数据，方便后续诊断。

有效性规则：

- `timeOffset > 0`。
- 血糖在 `40...400 mg/dL`。
- 广播 quality 不能直接套用连接包的 `quality == 0` 规则；广播解析得到的记录按广播格式单独判断。
- 重复或旧 `timeOffset` 不再入库。

## 广播扫描行为

`MicroTechBluetoothManaging` 增加广播发现回调，或新增轻量的广播扫描 delegate。

广播模式下：

1. 扫描仍限定 Aidex/LinX service 或保存的设备标识。
2. `didDiscover` 产生广播事件后交给 `MicroTechCGMManager`。
3. manager 判断设备名或已保存序列号是否匹配。
4. 匹配后解析广播。
5. 有新血糖时更新 `latestReading`，生成 `NewGlucoseSample`，通知 Loop。
6. 不调用 `connect`，不配置 service/characteristic，不订阅 `F001/F002/F003`。
7. 扫描可继续运行，用于等待下一条广播。

直接连接模式下：

- 现有扫描、连接、握手、通知、历史请求和重连流程不变。
- 广播日志仍可记录，但不作为血糖来源。

## 日志

广播模式新增稳定日志字段：

```text
stage=broadcast event=found identifier=... name=... rssi=... manufacturerData=...
stage=broadcast event=parsed identifier=... serial=... timeOffset=... glucose=... trend=...
stage=broadcast event=accepted serial=... sampleNumber=... glucose=...
stage=broadcast event=rejected reason=...
```

拒绝原因至少包括：

- 没有厂商数据。
- 厂商 ID 不是 `0x0059`。
- 广播长度不足。
- 设备名或序列号不匹配。
- 血糖超出范围。
- 样本号不是更新数据。

## 错误处理

| 场景 | 行为 |
|---|---|
| 设备不广播 | 保持扫描，超时后记录 `scanTimeout` |
| 广播没有血糖字段 | 记录 `stage=broadcast event=rejected` |
| 广播数据格式不完整 | 丢弃，不影响已有血糖 |
| 官方 App 连接后设备停止广播 | Loop 表现为信号丢失 |
| 血糖重复 | 不重复写入 Loop |
| 用户需要历史数据 | 提示使用直接连接模式 |

## 不做的事

- 不监听其它 App 的 BLE 连接。
- 不尝试绕过 iOS 对 BLE 连接数据的隔离。
- 不在广播模式读取历史数据。
- 不自动在广播和直连之间切换。
- 不改变 Dexcom、Libre、Nightscout 或其它 CGM 行为。

## 测试范围

单元测试：

1. `MicroTechCGMManagerState` 能保存和恢复 `connectionMode`。
2. 旧 raw state 默认恢复为直接连接。
3. 广播 parser 能从示例 Aidex 广播包解析出最新血糖。
4. 广播 parser 拒绝缺失厂商数据、错误厂商 ID、长度不足和血糖越界。
5. 广播模式收到有效广播后产生 `NewGlucoseSample`。
6. 广播模式不会调用蓝牙连接。
7. 直接连接模式仍调用现有连接流程。
8. 设置页 view model 能显示当前数据模式。

手工验证：

1. `MicroTechCGM` 测试通过。
2. `LoopWorkspace` 可构建。
3. 真机添加 MicroTech LinX 时能看到两种模式。
4. 广播模式能扫描并写入最新血糖。
5. 直接连接模式仍能连接 LinX 并接收通知包。

## 完成标准

- 添加 CGM 时用户可选择 `直接连接` 或 `广播数据`。
- 选择会被保存，重启后保持不变。
- 广播模式能解析 Aidex/LinX 广播里的最新血糖并交给 Loop。
- 广播模式不主动连接设备。
- 直接连接模式保持现有行为。
- 日志能明确区分广播解析、广播拒绝、直接连接。
- 相关测试通过。
- 文档、`PROGRESS.md`、commit 和 push 完成。
