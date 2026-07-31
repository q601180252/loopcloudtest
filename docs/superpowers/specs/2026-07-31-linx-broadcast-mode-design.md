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

解析入口拆成三层：

| 入口 | 输入 | 职责 |
|---|---|---|
| `parseAdvertisementData(_:)` | CoreBluetooth `advertisementData` 字典 | 读取 `CBAdvertisementDataManufacturerDataKey`，验证 company ID |
| `parseAdvertisingPayload(_:)` | 完整 BLE advertising payload | 解析 Android 风格 AD 结构，查找 `0xFF` 厂商数据 |
| `parseManufacturerPayload(_:)` | 去掉 company ID 后的 Aidex 厂商 payload | 解析 Aidex 广播字段 |

company ID 使用 little-endian 字节序识别 `59 00`。iOS CoreBluetooth 入口只接收 `advertisementData` 字典，不假设存在 Android 的完整 `scanRecord.bytes`。

解析规则：

1. 输入为完整 BLE advertising payload、iOS `advertisementData` 或去掉 company ID 后的 manufacturer payload。
2. 查找或验证厂商数据 `0x0059`。
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

- `timeOffset` 小于 7 表示探头未开始或仍在预热，广播不入库；7 及以上使用现有样本号比较规则去重。
- 血糖在 `40...400 mg/dL`。
- 广播记录中的 `0xFF` 是无效占位值，即使转换后为 `255`，也不能作为血糖入库。
- 最新记录有效、后续历史位置为 `0xFF` 时保留最新记录，并停止读取后续占位位置。
- 广播 quality 不能直接套用连接包的 `quality == 0` 规则；广播解析得到的记录按广播格式单独判断。
- 重复或旧 `timeOffset` 不再入库。
- 读取旧版广播状态时，清除已保存的预热样本或 `255 mg/dL` 占位血糖，保留已绑定的传感器信息。

## 广播扫描行为

新增独立的广播扫描入口，例如：

```text
scanForBroadcast(remoteIdentifier:)
```

该入口与现有直连扫描入口分开，避免复用会自动连接的路径。

广播模式下：

1. 扫描优先使用 Aidex/LinX service UUID 过滤。
2. `didDiscover` 产生广播事件后交给 `MicroTechCGMManager`。
3. 保存的 `remoteIdentifier` 只能作为发现后的 post-filter，不能通过 `retrievePeripherals` 或连接事件恢复来查找。
4. manager 判断设备名或已保存序列号是否匹配。
5. 匹配后解析广播。
6. 有新血糖时更新 `latestReading`，生成 `NewGlucoseSample`，通知 Loop。
7. 不调用 `connect`，不配置 service/characteristic，不订阅 `F001/F002/F003`。
8. 扫描超时后记录原因并停止本轮扫描；下次 `fetchNewDataIfNeeded` 或用户手动扫描再启动新一轮扫描。

广播模式必须绕开这些现有直连路径：

- `retrievePeripherals`
- `retrieveConnectedPeripherals`
- `registerForConnectionEvents`
- `willRestoreState` 中的自动连接
- `connectionEventDidOccur` 中的自动连接
- `connectIfNeeded`
- `centralManager.connect`
- GATT configure

直接连接模式下：

- 现有扫描、连接、握手、通知、历史请求和重连流程不变。
- 广播日志仍可记录，但不作为血糖来源。

如果 service UUID 过滤在真机上无法收到 Aidex 广播，实施时允许在首次添加前台页面中增加显式的无 service 过滤扫描 fallback；该 fallback 仍必须只做 post-filter，不得连接非目标设备。

无 service 过滤扫描只把厂商数据以 `59 00` 开头的 MicroTech 广播交给上层；附近其它蓝牙设备不写入 LinX 日志，也不进入广播解析。

## 首次广播绑定

广播 payload 本身不提供传感器序列号。首次添加时序列号来源为广播设备名：

1. 优先从 `CBAdvertisementDataLocalNameKey` 解析。
2. 其次使用 `CBPeripheral.name`。
3. 沿用现有 `advertisedSensorSerial(from:)` 规则，从 `LinX-...`、`AiDEX X-...` 或 `BWCGM-...` 中提取 serial。
4. 设备名不能解析 serial 时，广播模式拒绝该广播并记录 `reason=missingSerial`。

首次有效广播接受后，manager 必须写入：

- `remoteIdentifier`
- `deviceName`
- `sensorSerial`
- `lastReadingDate`
- `latestReading`
- `latestSampleNumber`
- `hasConnectedSensorSession = true`
- `connectionMode = broadcast`

后续广播若已有 `sensorSerial`，必须继续按 serial 匹配；若只有 `remoteIdentifier`，可按 iOS peripheral identifier 匹配，但拿到 serial 后仍以 serial 作为稳定身份。

## 广播入库路径

新增独立的广播读数路径，不能直接复用连接通知包路径：

| 类型 | 职责 |
|---|---|
| `MicroTechBroadcastReading` | 表示从广播解析出的最新血糖 |
| `acceptBroadcastReading(...)` | 广播读数去重、状态更新、生成 `NewGlucoseSample` |

`acceptBroadcastReading(...)` 只做广播模式需要的状态更新和 Loop 通知：

1. 用广播自己的有效性规则判断血糖。
2. 使用现有样本号回绕比较规则去重。
3. 生成 `NewGlucoseSample`。
4. 通知 `CGMManagerDelegate`。

它不得触发：

- history request。
- 连接态 stale watchdog。
- `MicroTechSensor` 的当前包处理。
- `MicroTechGlucoseReading.isValidForTherapy` 中连接包专用的 `quality == 0` 规则。

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
- 设备名无法解析序列号。
- 设备名或序列号不匹配。
- 血糖超出范围。
- 样本号不是更新数据。

## 错误处理

| 场景 | 行为 |
|---|---|
| 设备不广播 | 本轮扫描超时后停止并记录 `scanTimeout`，下次取数或手动扫描再重启 |
| 广播没有血糖字段 | 记录 `stage=broadcast event=rejected` |
| 广播数据格式不完整 | 丢弃，不影响已有血糖 |
| `timeOffset` 小于 7 | 记录探头未开始或预热中，不写入 Loop，继续扫描 |
| 最新血糖为 `0xFF` | 记录无效占位数据，不写入 Loop，继续扫描 |
| 最新血糖有效、后续历史位置为 `0xFF` | 接受最新血糖，忽略后续占位位置 |
| 官方 App 连接后设备停止广播 | Loop 表现为信号丢失 |
| 血糖重复 | 不重复写入 Loop |
| 用户需要历史数据 | 提示使用直接连接模式 |
| 设备名没有序列号 | 拒绝该广播，继续扫描 |

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
3. 广播 parser 能从完整 BLE advertising payload 解析出最新血糖。
4. 广播 parser 能从 CoreBluetooth `advertisementData` 字典解析出最新血糖。
5. 广播 parser 能从去掉 company ID 后的 manufacturer payload 解析出最新血糖。
6. 广播 parser 拒绝缺失厂商数据、错误厂商 ID、长度不足和血糖越界。
7. 广播模式收到有效广播后产生 `NewGlucoseSample`。
8. 广播模式首次有效广播会保存 `remoteIdentifier`、`deviceName`、`sensorSerial` 和 `connectionMode`。
9. 广播模式无法从设备名解析 serial 时拒绝广播。
10. 广播模式不会调用蓝牙连接。
11. 广播模式不会通过 CoreBluetooth restore、已连接 peripheral 或 connection event 进入连接。
12. 广播模式不会触发 history request。
13. 直接连接模式仍调用现有连接流程。
14. 设置页 view model 能显示当前数据模式。

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
