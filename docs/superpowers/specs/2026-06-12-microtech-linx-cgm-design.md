# 微泰 LinX CGM 接入设计

## 目标

在 `LoopWorkspace` 中新增一个可用的微泰 LinX CGM 数据源。用户在 Loop 的 CGM 列表里选择微泰 LinX 后，App 能通过 BLE 连接设备，完成握手，接收实时血糖，解析为 Loop 可用的 CGM 数据。

本轮目标是完整 BLE 直连，不走 Nightscout 或其它远程中转。

## 依据

当前仓库已有 CGM 都通过插件加入：

- `PluginManager` 扫描 `Frameworks` 下的插件 bundle。
- 插件 `Info.plist` 提供 CGM 名称和唯一标识。
- 插件主类返回一个 `CGMManagerUI.Type`。
- `DeviceDataManager` 根据用户选择创建 CGM manager。
- CGM manager 通过 `CGMReadingResult.newData` 把血糖交给 Loop。

`aoji` 中已有 LinX/Aidex 连接方式：

- BLE service：`0000181f-0000-1000-8000-00805f9b34fb`
- characteristic：`F001`、`F002`、`F003`
- 连接顺序：订阅 `F002`，尝试订阅 `F001`，写 `F001` 初始 key，等待或回退 pairing key，写 `F001` 响应 key，读 `F002` challenge，派生 session key，订阅 `F003`，写 `cmd10`
- 数据加密：AES-CFB，key 由设备名中的序列号派生，session key 由 `F002` challenge 派生
- 实时包：解密后 packet type `0x01`
- 历史包：解密后 packet type `0x23`
- 启动链：`cmd31 -> cmd20 -> cmd35 -> cmd34 -> cmd11`，收到 `0x21` 表示启动时间回复

## 推荐架构

新增独立模块 `MicroTechCGM`，结构参考 `G7SensorKit`，不塞进 Dexcom 或 Libre 现有模块。

模块分层：

| 层 | 职责 |
|---|---|
| `MicroTechCGMManager` | 对接 Loop 的 `CGMManager` / `CGMManagerUI`，保存状态，输出血糖 |
| `MicroTechSensor` | 管理 LinX 设备语义：扫描、绑定、连接、启动、历史请求 |
| `MicroTechBluetoothManager` | 管理 CoreBluetooth 扫描、连接、断开和状态恢复 |
| `MicroTechPeripheralManager` | 发现 service / characteristic，执行读写和通知订阅 |
| `MicroTechAidexCrypto` | key/IV 派生、AES-CFB、CRC16 |
| `MicroTechAidexParser` | 解析 `0x01` 实时包和 `0x23` 历史包 |
| `MicroTechCGMUI` | 设置、绑定、状态页 |
| `MicroTechCGMPlugin` | Loop 插件入口 |

## 用户流程

1. 用户进入 Loop 的 CGM 添加入口。
2. 列表显示 `MicroTech LinX`。
3. 用户选择后进入绑定页。
4. App 扫描 LinX/Aidex BLE 广播。
5. 用户选择设备。
6. App 保存设备标识、设备名、传感器序列号。
7. App 连接设备并完成 `F001/F002/F003` 握手。
8. App 接收 `F003` 通知，解密并解析实时血糖。
9. App 把有效血糖转成 `NewGlucoseSample` 交给 Loop。
10. 用户可在设置页查看连接状态、最后通信时间、传感器状态，并可解除绑定。

## 数据处理

实时包 `0x01` 转换规则：

| 字段 | 来源 |
|---|---|
| 血糖值 | little-endian `uint16`，取低 10 bit，单位 mg/dL |
| 趋势 | signed byte |
| 样本序号 | little-endian `uint16` |
| 状态 | 包内 status 字段 |
| 设备信息 | `HKDevice`，manufacturer 使用 `MicroTech Medical`，model 使用 `LinX` |

历史包 `0x23` 第一版只用于补齐缺口，不显示为当前值。历史数据会以时间序号映射成过去时间点，再交给 Loop 存储。若时间换算证据不足，第一版只实现实时包，历史包只记录日志，不进入治疗数据。

无效数据处理：

- CRC 不通过：丢弃并记录设备日志。
- 解密失败：丢弃并记录设备日志。
- `sampleNumber <= 0`：视为未启动或启动前状态，不作为有效血糖。
- 暖机期：不作为有效治疗血糖。
- 血糖超出 LinX 标称范围：丢弃并记录。

## 状态保存

manager 的 `rawState` 至少保存：

- `remoteIdentifier`
- `deviceName`
- `sensorSerial`
- `activationTime`
- `lastReadingDate`
- `latestReading`
- `latestSampleNumber`
- `uploadReadings`

删除 CGM 时：

- 停止通知。
- 断开 BLE。
- 清理 manager 状态。
- 如设备当前可连接，尝试发送解除绑定命令；失败不阻塞删除。

## 插件接入

需要新增：

- `MicroTechCGM.xcodeproj`
- `MicroTechCGM.framework`
- `MicroTechCGMUI.framework`
- `MicroTechCGMPlugin.loopplugin`
- `MicroTechCGMPlugin/Info.plist`

插件元数据：

- display name：`MicroTech LinX`
- identifier：`MicroTechLinXCGMManager`
- principal class：`MicroTechCGMPlugin`

还需要：

- 把 `MicroTechCGM.xcodeproj` 加入 `LoopWorkspace.xcworkspace`
- 把 `MicroTechCGMPlugin.loopplugin` 加入 `LoopWorkspace.xcscheme`
- 确认主 App 构建时插件会被打进 `Frameworks`

## 错误处理

| 场景 | 行为 |
|---|---|
| 蓝牙未开启 | 设置页显示不可连接状态 |
| 未找到设备 | 绑定页停留并允许重新扫描 |
| service 缺失 | 断开并提示设备不匹配 |
| `F001` key 超时 | 按 `aoji` 逻辑回退初始 key |
| `F002` challenge 为空 | 握手失败，断开重试 |
| 连接断开 | manager 保留状态，等待下次扫描或系统恢复 |
| 解析失败 | 丢弃本帧，不清空已有有效数据 |

## 测试范围

单元测试：

- 序列号到 key/IV 派生。
- AES-CFB 加解密。
- CRC16。
- `0x01` 实时包解析。
- `0x23` 历史包解析。
- 状态序列化和恢复。
- 无效包丢弃。

集成测试：

- 模拟 BLE 连接完成握手。
- 模拟 `F003` 通知产生 `NewGlucoseSample`。
- 断线后 manager 状态不丢失。
- 插件 `Info.plist` 包含正确 display name、identifier、principal class。

手工验证：

- Xcode 能构建 `LoopWorkspace`。
- App 的 CGM 列表出现 `MicroTech LinX`。
- 真机可扫描到 LinX。
- 真机连接后能收到实时血糖。
- 删除 CGM 后可重新绑定。

## 不做的事

- 不把微泰数据接成 Nightscout Remote CGM。
- 不修改 Dexcom、Libre、Nightscout 现有行为。
- 不把历史包混入当前值。
- 不做用户校准功能。
- 不新增与微泰无关的 UI。

## 完成标准

第一阶段完成：

- 设计文档已确认。
- 实现计划已写出。
- 明确需要迁移的 `aoji` 代码和目标 Swift 文件。

最终完成：

- `MicroTech LinX` 出现在 Loop CGM 列表。
- 可在真机选择设备并完成 BLE 握手。
- 收到 `F003` 后产生 Loop 可用血糖。
- 断线后能保留绑定信息并重连。
- 相关单元测试通过。
- Xcode 构建通过。
