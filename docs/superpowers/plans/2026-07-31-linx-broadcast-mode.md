# LinX Broadcast Mode Implementation Plan

> **历史记录：此计划对应已取消的 LinX 广播模式添加方案，不再代表当前添加流程。当前方案见 [LinX 添加流程固定直连设计](../specs/2026-07-31-linx-direct-only-setup-design.md) 和 [LinX 固定直连实施计划](2026-07-31-linx-direct-only-setup.md)。**

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a MicroTech LinX setup choice between direct connection and broadcast data, and let broadcast mode read the latest Aidex/LinX glucose from BLE advertisements without connecting.

**Architecture:** Persist the selected connection mode in `MicroTechCGMManagerState`. Keep direct connection on the existing scan/connect/GATT path, and add an independent broadcast scan path that only forwards advertisement data to the manager. Parse Aidex manufacturer data in a new parser, then accept broadcast readings through a separate manager path that updates Loop with latest glucose only.

**Tech Stack:** Swift, SwiftUI, CoreBluetooth, XCTest, HealthKit, LoopKit.

---

## Completion Criteria

- Adding `MicroTech LinX` shows a clear choice between `直接连接` and `广播数据`.
- `direct` mode keeps the current connection, pairing, notification, history and logging behavior unchanged.
- `broadcast` mode scans advertisements and never calls CoreBluetooth connect, connected-peripheral restore, GATT configure or history request.
- Aidex manufacturer data `0x0059` can be parsed from CoreBluetooth advertisement dictionaries, Android-style full advertising payloads and manufacturer payloads without company ID.
- The first valid broadcast during onboarding stores `remoteIdentifier`, `deviceName`, `sensorSerial`, `lastReadingDate`, `latestReading`, `latestSampleNumber`, `hasConnectedSensorSession` and `connectionMode = broadcast`.
- Broadcast duplicate and stale samples are ignored with existing sample-number wrap comparison.
- Settings show the active data mode.
- `MicroTechCGM` tests pass, relevant workspace build passes or the exact existing blocker is documented.
- `PROGRESS.md` is updated, changes are committed and pushed to `origin/main`.

## Reference Documents

- Spec: `docs/superpowers/specs/2026-07-31-linx-broadcast-mode-design.md`
- Existing full connection logging plan: `docs/superpowers/plans/2026-07-30-linx-full-connection-logging.md`
- Existing progress log: `PROGRESS.md`

## File Structure

- Create `MicroTechCGM/MicroTechCGM/MicroTechAidexBroadcastParser.swift`
  - Owns Aidex advertisement parsing.
  - Exposes three parser entrances:
    - `parseAdvertisementData(_:)`
    - `parseAdvertisingPayload(_:)`
    - `parseManufacturerPayload(_:)`
  - Defines `MicroTechAidexBroadcastReading` and `MicroTechAidexBroadcastRecord`.

- Modify `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`
  - Adds new production and test Swift files to the correct targets.
  - Required because this project lists source files explicitly.

- Modify `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`
  - Adds `MicroTechCGMConnectionMode`.
  - Persists `connectionMode`.
  - Defaults missing legacy state to `.direct`.

- Modify `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
  - Extends `MicroTechBluetoothManaging` with `scanForBroadcast(remoteIdentifier:)`.
  - Adds a broadcast discovery delegate callback.
  - Keeps broadcast scanning separate from direct scanning.
  - Guards restore and connection-event auto-connect so they only apply to direct mode.

- Modify `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
  - Routes scanning by `state.connectionMode`.
  - Adds `acceptBroadcastReading(...)`.
  - Handles broadcast discovery, serial binding, duplicate filtering and Loop sample creation.
  - Keeps direct connection path unchanged.

- Modify `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
  - Passes the selected mode from onboarding into the manager before scanning.

- Modify `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`
  - Adds setup UI choice for `直接连接` and `广播数据`.

- Modify `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsViewModel.swift`
  - Publishes a data-mode display string.

- Modify `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsView.swift`
  - Shows the active data mode.

- Modify `MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift`
  - Adds broadcast parser coverage.

- Modify `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift`
  - Adds state persistence and legacy default coverage.

- Create `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift`
  - Adds manager routing, onboarding, duplicate, stale, wrap, no-connect, no-history, parser rejection and settings display coverage.
  - Keeps new broadcast tests out of the already-large `MicroTechCGMManagerTests.swift`.

- Create `MicroTechCGM/MicroTechCGMTests/MicroTechBluetoothBroadcastScanTests.swift`
  - Adds concrete Bluetooth scan-policy coverage for broadcast mode not calling retrieve, connected-peripheral restore, connection-event registration or connect.

- Modify `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`
  - Only add or expose shared test helpers if reuse is required.

- Modify `PROGRESS.md`
  - Adds implementation progress and final validation results.

## Chunk 1: State And Broadcast Parser

### Task 1: Persist Connection Mode

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift`

- [ ] **Step 1: Add failing state round-trip tests**

Add tests that assert:

```swift
func testStatePersistsBroadcastConnectionMode() throws {
    var state = MicroTechCGMManagerState()
    state.connectionMode = .broadcast

    let restored = try MicroTechCGMManagerState(rawValue: state.rawValue)

    XCTAssertEqual(restored.connectionMode, .broadcast)
}

func testLegacyStateDefaultsToDirectConnectionMode() throws {
    let legacyRawValue: MicroTechCGMManagerState.RawValue = [
        "deviceName": "LinX-222227JKFK",
        "sensorSerial": "222227JKFK",
        "hasConnectedSensorSession": true
    ]

    let restored = try MicroTechCGMManagerState(rawValue: legacyRawValue)

    XCTAssertEqual(restored.connectionMode, .direct)
}
```

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechCGMManagerStateTests
```

Expected: fails because `connectionMode` does not exist.

- [ ] **Step 3: Add minimal state implementation**

Add:

```swift
public enum MicroTechCGMConnectionMode: String, Codable, Equatable {
    case direct
    case broadcast
}
```

Add to `MicroTechCGMManagerState`:

```swift
public var connectionMode: MicroTechCGMConnectionMode = .direct
```

Persist under raw key:

```swift
"connectionMode": connectionMode.rawValue
```

Restore with legacy default:

```swift
connectionMode = MicroTechCGMConnectionMode(rawValue: rawValue["connectionMode"] as? String ?? "") ?? .direct
```

- [ ] **Step 4: Run state tests**

Run the same `xcodebuild test ... MicroTechCGMManagerStateTests` command.

Expected: all `MicroTechCGMManagerStateTests` pass.

### Task 2: Add Broadcast Parser

**Files:**
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexBroadcastParser.swift`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift`

- [ ] **Step 1: Add failing parser tests**

Add these fixtures:

```swift
private let aidexFullAdvertisingPayload = Data(hexadecimalString: "02010603021f1817ff590060540100026e80436c80416a80410000f33ee04e1309416944455820582d3232323232374a4b464b08ff590003f9054b360000")!
private let aidexManufacturerData = Data(hexadecimalString: "590060540100026e80436c80416a80410000f33ee04e")!
private let aidexManufacturerPayload = Data(hexadecimalString: "60540100026e80436c80416a80410000f33ee04e")!
```

Add tests that assert:

- `parseAdvertisingPayload(_:)` returns `timeOffset == 21600`, `status == 1`, `calTemp == 0`, `trend == 2`.
- `records.count == 3`.
- `records[0]` is latest with `sampleNumber == 21600`, `glucoseMgdl == 110`, `quality == 67`.
- `records[1]` has `sampleNumber == 21599`, `glucoseMgdl == 108`, `quality == 65`.
- `records[2]` has `sampleNumber == 21598`, `glucoseMgdl == 106`, `quality == 65`.
- `parseAdvertisementData([CBAdvertisementDataManufacturerDataKey: aidexManufacturerData])` returns the same latest record.
- `parseManufacturerPayload(aidexManufacturerPayload)` returns the same latest record.
- All three parser entrances retain `rawManufacturerPayload == aidexManufacturerPayload`.
- A negative trend fixture with trend byte `0xfe` parses as `-2`, not `254`.
- Missing manufacturer data, company ID not `59 00`, payload shorter than 8 bytes, and glucose outside `40...400` throw or return a typed rejection.

- [ ] **Step 2: Run parser tests and confirm they fail**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexParserTests
```

Expected: fails because the broadcast parser does not exist.

- [ ] **Step 3: Implement parser types and errors**

Implement these internal types:

```swift
struct MicroTechAidexBroadcastReading: Equatable {
    let timeOffset: Int
    let status: UInt8
    let calibrationTemperature: UInt8
    let trend: Int8
    let records: [MicroTechAidexBroadcastRecord]
    let rawManufacturerPayload: Data

    var latestRecord: MicroTechAidexBroadcastRecord? {
        records.first
    }
}

struct MicroTechAidexBroadcastRecord: Equatable {
    let sampleNumber: Int
    let glucoseMgdl: Int
    let reserved: UInt8
    let quality: UInt8
}

enum MicroTechAidexBroadcastParserError: Error, Equatable {
    case missingManufacturerData
    case wrongCompanyIdentifier
    case payloadTooShort
    case noRecords
    case glucoseOutOfRange(Int)
}
```

Keep parser logic deterministic:

- CoreBluetooth manufacturer data includes company ID at bytes `0...1`.
- Company ID must be `0x0059`, encoded as `59 00`.
- Manufacturer payload after company ID starts with `timeOffset` little-endian.
- Decode trend with signed-byte semantics, for example `Int8(bitPattern: trendByte)`.
- Parse at most three records.
- Record sample numbers decrement from the top-level `timeOffset` using existing wrap size `65536`.
- First record is latest.
- Store the exact payload after company ID in `rawManufacturerPayload`; do not truncate to the latest record.
- Add `MicroTechAidexBroadcastParser.swift` to the `MicroTechCGM` target in `MicroTechCGM.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Run parser tests**

Run the same `xcodebuild test ... MicroTechAidexParserTests` command.

Expected: all parser tests pass.

- [ ] **Step 5: Commit Chunk 1**

Run:

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift MicroTechCGM/MicroTechCGM/MicroTechAidexBroadcastParser.swift MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj
git commit -m "新增 LinX 广播解析状态" -m "改动原因：LinX 需要保存直连或广播数据模式，并能解析 Aidex 广播里的最新血糖。" -m "改动清单：新增 connectionMode 状态；新增 Aidex 广播 parser；补充状态和 parser 单元测试。" -m "验证结果：MicroTechCGMManagerStateTests 与 MicroTechAidexParserTests 通过。" -m "影响范围：MicroTech LinX CGM 状态恢复与广播数据解析。"
```

## Chunk 2: Broadcast Scan And Manager Acceptance

### Task 3: Add Broadcast Scan Entry And No-Connect Policy

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechBluetoothBroadcastScanTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift`
- Modify: `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing concrete scan-policy tests**

Create `MicroTechBluetoothBroadcastScanTests.swift` and add tests:

```swift
func testBroadcastScanUsesServiceUUIDAndDoesNotRetrieveRegisterOrConnect() throws
func testBroadcastFilteredTimeoutStartsSingleUnfilteredFallbackWhenEnabled() throws
func testBroadcastFinalTimeoutStopsAndLogsScanTimeoutWithoutImmediateRescan() throws
func testBluetoothManagerIsInitializedWithPersistedBroadcastModeBeforeRestoreCallbacks() throws
func testBroadcastModeDisallowsRestoreAutoConnect() throws
func testBroadcastModeDisallowsConnectionEventAutoConnect() throws
func testBroadcastScanFallbackUsesUnfilteredScanOnlyAfterFilteredTimeout() throws
```

Use a narrow fake central wrapper with call counters:

```swift
final class FakeMicroTechCentralManager {
    var state: CBManagerState = .poweredOn
    var isScanning = false
    private(set) var retrievePeripheralsCallCount = 0
    private(set) var retrieveConnectedPeripheralsCallCount = 0
    private(set) var registerForConnectionEventsCallCount = 0
    private(set) var connectCallCount = 0
    private(set) var stopScanCallCount = 0
    private(set) var scanForPeripheralsServices: [[CBUUID]?] = []
}
```

Expected assertions:

- `scanForBroadcast(remoteIdentifier:)` starts with `scanForPeripherals(withServices: [MicroTechAidexProfile.serviceUUID], options: nil)`.
- Broadcast scan call counts stay at zero for:
  - `retrievePeripherals`
  - `retrieveConnectedPeripherals`
  - `registerForConnectionEvents`
  - `connect`
- A Bluetooth manager created for a restored broadcast-mode CGM has broadcast policy set during `MicroTechBluetoothManager` initialization, before `CBCentralManager` can deliver restore callbacks.
- Broadcast restore and connection-event policy returns `false`; direct mode returns `true`.
- Filtered broadcast timeout has its own `phase=filtered` log and may start one unfiltered fallback only when foreground fallback is enabled.
- Final broadcast timeout has `phase=final`, logs `stage=broadcast event=rejected reason=scanTimeout`, calls `stopScan`, and does not immediately rescan in the same timeout callback.
- Unfiltered fallback still keeps all retrieve/register/connect counts at zero.

- [ ] **Step 2: Add failing manager routing tests**

Create `MicroTechBroadcastModeTests.swift` and add a local fake Bluetooth manager:

```swift
private(set) var scanForBroadcastRemoteIdentifiers: [UUID?] = []
private(set) var scanRemoteIdentifiers: [UUID?] = []
private(set) var refreshConnectedPeripheralCallCount = 0

func scanForBroadcast(remoteIdentifier: UUID?) {
    scanForBroadcastRemoteIdentifiers.append(remoteIdentifier)
    isScanning = true
}
```

Add tests:

```swift
func testBroadcastModeStartsBroadcastScanInsteadOfDirectScan() throws
func testDirectModeStillStartsDirectScan() throws
func testBroadcastModeDoesNotRefreshConnectedPeripheral() throws
```

Expected assertions:

- Broadcast mode calls `scanForBroadcast(remoteIdentifier:)`.
- Broadcast mode does not call `scan(remoteIdentifier:)`.
- Broadcast mode does not call `refreshConnectedPeripheral()`.
- Direct mode still calls `scan(remoteIdentifier:)`.

- [ ] **Step 3: Run scan tests and confirm they fail**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechBluetoothBroadcastScanTests -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testBroadcastModeStartsBroadcastScanInsteadOfDirectScan -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testDirectModeStillStartsDirectScan -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testBroadcastModeDoesNotRefreshConnectedPeripheral
```

Expected: fails because broadcast scan entry does not exist.

- [ ] **Step 4: Implement protocol, concrete scan entry and no-connect policy**

Update `MicroTechBluetoothManaging`:

```swift
func configureConnectionMode(_ mode: MicroTechCGMConnectionMode)
func scanForBroadcast(remoteIdentifier: UUID?)
```

Add delegate callback:

```swift
func microTechBluetoothManager(_ manager: MicroTechBluetoothManaging, didDiscoverBroadcast advertisement: MicroTechBroadcastAdvertisement)
```

Add advertisement carrier:

```swift
struct MicroTechBroadcastAdvertisement {
    let identifier: UUID
    let name: String?
    let advertisementData: [String: Any]
    let rssi: NSNumber
}
```

In concrete `MicroTechBluetoothManager`:

- Add an internal scan mode enum with `.direct` and `.broadcast`.
- Add initializer support:

```swift
init(initialConnectionMode: MicroTechCGMConnectionMode = .direct)
```

- Store the initial mode before constructing `CBCentralManager`.
- `MicroTechCGMManager` must create the real Bluetooth manager with `initialConnectionMode: state.connectionMode`.
- If a Bluetooth manager is injected, `MicroTechCGMManager` must call `bluetoothManager.configureConnectionMode(state.connectionMode)` during manager initialization before scanning.
- Setup mode changes must call both manager state configuration and Bluetooth manager configuration before scan.
- `scan(remoteIdentifier:)` sets `.direct`.
- `scanForBroadcast(remoteIdentifier:)` sets `.broadcast`.
- Split direct and broadcast scan bodies so broadcast scan never enters the direct restore/connect body.
- Keep direct scan behavior in the existing path:
  - restored peripheral lookup.
  - `retrievePeripherals`.
  - `retrieveConnectedPeripherals`.
  - `registerForConnectionEvents`.
  - `connectIfNeeded`.
- Broadcast scan behavior:
  - stores `remoteIdentifier` only for post-filter.
  - starts `scanForPeripherals(withServices: [MicroTechAidexProfile.serviceUUID], options: nil)`.
  - tracks scan phase as `.filtered` or `.unfilteredFallback`.
  - on filtered timeout, if foreground fallback is enabled and not already tried, logs `phase=filtered`, stops the filtered scan, starts one fallback scan with `withServices: nil`, and keeps post-filter only.
  - on final timeout, logs `phase=final reason=scanTimeout`, stops the current scan and waits for the next `fetchNewDataIfNeeded` or user scan to start another round.
- In `didDiscover`, if mode is `.broadcast`, log `stage=broadcast event=found`, call the broadcast delegate callback, and return without calling `connectIfNeeded`.
- Guard `willRestoreState` and `connectionEventDidOccur` through the initialization-time connection-mode policy so auto-connect only runs in `.direct`.
- Add a narrow internal central wrapper or equivalent test seam so `MicroTechBluetoothBroadcastScanTests` can prove broadcast mode does not call `retrievePeripherals`, `retrieveConnectedPeripherals`, `registerForConnectionEvents` or `connect`.
- Keep direct mode existing behavior unchanged.
- Add `MicroTechBluetoothBroadcastScanTests.swift` and `MicroTechBroadcastModeTests.swift` to the `MicroTechCGMTests` target in `project.pbxproj`.

- [ ] **Step 5: Run scan routing and no-connect tests**

Run the same targeted `xcodebuild test ... MicroTechBluetoothBroadcastScanTests ... MicroTechBroadcastModeTests/...` command.

Expected: targeted scan routing tests pass.

### Task 4: Accept Broadcast Readings In Manager

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift`

- [ ] **Step 1: Add failing broadcast acceptance tests**

Add tests:

```swift
func testBroadcastModeForwardsAdvertisementToParserAndCreatesNewGlucoseSample() throws
func testBroadcastModeFirstValidAdvertisementStoresCompleteSensorState() throws
func testBroadcastModeRejectsParserFailureWithStableReason() throws
func testBroadcastModeRejectsMissingSerial() throws
func testBroadcastModeRejectsIdentifierMismatchWhenOnlyIdentifierIsSaved() throws
func testBroadcastModeRejectsSerialMismatchWhenSerialIsSaved() throws
func testBroadcastModeRejectsDuplicateSampleNumber() throws
func testBroadcastModeRejectsOlderSampleNumber() throws
func testBroadcastModeUsesSampleNumberWrapComparison() throws
func testBroadcastModeDoesNotScheduleHistoryBackfill() throws
func testBroadcastModeDoesNotRequireConnectionPacketQualityZero() throws
func testBroadcastModeLogsFoundParsedAcceptedAndRejectedEvents() throws
```

Use manufacturer data:

```swift
let advertisementData: [String: Any] = [
    CBAdvertisementDataLocalNameKey: "AiDEX X-222227JKFK",
    CBAdvertisementDataManufacturerDataKey: Data(hexadecimalString: "590060540100026e80436c80416a80410000f33ee04e")!
]
```

Expected assertions:

- New sample glucose is `110 mg/dL`.
- New sample date is derived from manager sensor start date plus sample offset if activation time is present, otherwise uses current receipt date consistently with existing manager conventions.
- First valid broadcast stores:
  - `remoteIdentifier`.
  - `deviceName`.
  - `sensorSerial == "222227JKFK"`.
  - `lastReadingDate`.
  - `latestReading` with glucose `110`.
  - `latestSampleNumber == 21600`.
  - `hasConnectedSensorSession == true`.
  - `connectionMode == .broadcast`.
- The manager delegate receives one `NewGlucoseSample`.
- Missing or unparsable name rejects the broadcast and produces no sample.
- Missing manufacturer data, wrong company ID, short payload and glucose out of range reject with stable `reason=...` logs.
- If only `remoteIdentifier` is saved, a different identifier is rejected.
- If `sensorSerial` is saved, a different serial is rejected even when the identifier matches.
- Repeating the same sample number produces no new sample.
- An older sample number produces no new sample.
- Wrap comparison treats `0` or `1` after `65535` as new and treats pre-wrap values after post-wrap latest as old.
- Broadcast `quality == 67` is accepted when glucose range is valid.
- History request count remains `0`.
- Logs include `stage=broadcast event=found`, `parsed`, `accepted` and `rejected reason=...`.

- [ ] **Step 2: Run broadcast acceptance tests and confirm they fail**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests
```

Expected: fails because manager has no broadcast acceptance path.

- [ ] **Step 3: Implement manager broadcast handling**

Add manager methods:

```swift
func configureConnectionMode(_ mode: MicroTechCGMConnectionMode)

func acceptBroadcastReading(
    _ reading: MicroTechAidexBroadcastReading,
    identifier: UUID,
    name: String?,
    receivedAt: Date
)
```

Implementation rules:

- `scanForSensor(clearingConnectionError:)` calls `bluetoothManager.scanForBroadcast(remoteIdentifier:)` when `state.connectionMode == .broadcast`.
- Direct mode keeps existing `bluetoothManager.scan(remoteIdentifier:)`.
- `fetchNewDataIfNeeded` in broadcast mode starts broadcast scan and returns `.noData` unless a broadcast arrives asynchronously, matching current async scan behavior.
- Implement the new delegate method that receives `MicroTechBroadcastAdvertisement`.
- The delegate method calls `MicroTechAidexBroadcastParser.parseAdvertisementData(_:)`.
- Parser success calls `acceptBroadcastReading(...)`.
- Parser failure logs `stage=broadcast event=rejected reason=...` and produces no sample.
- Serial source:
  - first `CBAdvertisementDataLocalNameKey`
  - then `CBPeripheral.name` passed through the advertisement carrier
  - parse with existing `advertisedSensorSerial(from:)`
- If state already has `sensorSerial`, reject broadcasts with non-matching serial.
- If state only has `remoteIdentifier`, reject non-matching identifiers and allow matching identifiers to bind serial once available.
- Reject missing serial during first binding with `stage=broadcast event=rejected reason=missingSerial`.
- Use existing sample-number wrap helper to ignore duplicate or older `timeOffset`.
- Update state and notify delegate with a `NewGlucoseSample`.
- Log parsed, accepted and each rejection reason from the spec:
  - no manufacturer data.
  - wrong company ID.
  - short payload.
  - missing serial.
  - device mismatch.
  - glucose out of range.
  - duplicate or older sample.
- Do not call `requestHistoryBackfillIfNeeded`, stale watchdog setup, direct `MicroTechSensor` handlers or `MicroTechGlucoseReading.isValidForTherapy`.

- [ ] **Step 4: Run broadcast acceptance tests**

Run the same targeted `xcodebuild test ... MicroTechBroadcastModeTests` command.

Expected: all targeted broadcast acceptance tests pass.

- [ ] **Step 5: Run direct connection regression tests**

Run existing direct path tests that cover scanning, connection, reconnect, current packets and history:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testScanForSensorWithoutConfiguredSensorStartsNearbyBluetoothScan -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testNearbyScanConnectsDiscoveredLinxAndSavesSensor -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testActiveSensorDisconnectRestartsScanForSavedPeripheral -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testLinxF003CurrentNotificationFromDeviceLogEmitsNewDataAndDiagnosticLogs -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testCurrentReadRequestsHistoryBackfillFromWarmupIndex -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSensorHistoryReadHandlesSampleNumberRollover
```

Expected: direct connection scan, connect, reconnect, current packet and history behavior still pass.

- [ ] **Step 6: Commit Chunk 2**

Run:

```bash
git add MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift MicroTechCGM/MicroTechCGMTests/MicroTechBluetoothBroadcastScanTests.swift MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj
git commit -m "新增 LinX 广播扫描入库" -m "改动原因：广播模式需要只扫描广告包并把最新血糖交给 Loop，不能进入连接流程。" -m "改动清单：新增广播扫描入口；新增广播发现回调；新增 manager 广播入库路径；补充 no-connect、no-history、重复样本和首绑测试。" -m "验证结果：MicroTechBluetoothBroadcastScanTests、MicroTechBroadcastModeTests 相关用例通过，直连回归测试通过。" -m "影响范围：MicroTech LinX CGM 蓝牙扫描、onboarding 和最新血糖入库。"
```

## Chunk 3: Setup UI, Settings UI, Docs And Verification

### Task 5: Add Setup And Settings UI

**Files:**
- Modify: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
- Modify: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`
- Modify: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsViewModel.swift`
- Modify: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsView.swift`
- Test: `MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift`

- [ ] **Step 1: Add failing UI behavior tests**

Add tests that assert:

```swift
func testSettingsViewModelShowsDirectConnectionMode() throws
func testSettingsViewModelShowsBroadcastDataMode() throws
func testCoordinatorStartsSetupWithSelectedBroadcastMode() throws
```

Expected strings:

- `.direct` -> `Direct Connection`
- `.broadcast` -> `Broadcast Data`

Expected coordinator behavior:

- Completing setup with `.broadcast` creates or configures a manager whose state has `.broadcast`.
- Completing setup with `.direct` keeps `.direct`.

- [ ] **Step 2: Run UI-related tests and confirm they fail**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testSettingsViewModelShowsDirectConnectionMode -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testSettingsViewModelShowsBroadcastDataMode -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testCoordinatorStartsSetupWithSelectedBroadcastMode
```

Expected: fails because UI mode display and coordinator selection do not exist.

- [ ] **Step 3: Implement setup mode selection**

Update `MicroTechSetupView`:

- Add `@State private var selectedConnectionMode: MicroTechCGMConnectionMode = .direct`.
- Use a segmented `Picker` or two selectable rows with exact labels:
  - `直接连接`
  - `广播数据`
- Keep default `.direct`.
- Pass selected mode to the continue action:

```swift
var didContinue: (MicroTechCGMConnectionMode) -> Void
```

Update `MicroTechUICoordinator`:

- Accept selected mode from setup.
- Before scan, call `manager.configureConnectionMode(selectedMode)`.
- Keep existing onboarding log configuration unchanged.

- [ ] **Step 4: Implement settings display**

Update `MicroTechSettingsViewModel`:

```swift
var connectionModeDescription: String {
    switch state.connectionMode {
    case .direct:
        return "Direct Connection"
    case .broadcast:
        return "Broadcast Data"
    }
}
```

Update `MicroTechSettingsView` to show:

```text
Data Mode
Direct Connection
```

or:

```text
Data Mode
Broadcast Data
```

Do not add mode switching in settings.

- [ ] **Step 5: Run UI-related tests**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testSettingsViewModelShowsDirectConnectionMode -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testSettingsViewModelShowsBroadcastDataMode -only-testing:MicroTechCGMTests/MicroTechBroadcastModeTests/testCoordinatorStartsSetupWithSelectedBroadcastMode
```

Expected: UI-related tests pass.

- [ ] **Step 6: Manually verify setup and settings UI**

Run the app on simulator or a connected iPhone and verify:

- `Add CGM` -> `MicroTech LinX` shows both `直接连接` and `广播数据`.
- Default selection is `直接连接`.
- Selecting `广播数据` starts onboarding in broadcast mode.
- Settings show `Data Mode: Broadcast Data` for broadcast mode.
- Settings show `Data Mode: Direct Connection` for direct mode.
- Settings do not provide a mode switch; changing mode requires deleting and re-adding CGM.

Record the manual result in `PROGRESS.md`. If no runnable simulator or device is available, record the exact reason and do not claim this manual UI verification passed.

### Task 6: Full Verification, Docs, Commit And Push

**Files:**
- Modify: `PROGRESS.md`
- Create or modify: `docs/工具与踩坑.md` only if a new build or test pitfall is found.

- [ ] **Step 1: Run full MicroTechCGM tests**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: all `MicroTechCGM` tests pass.

- [ ] **Step 2: Run workspace build**

Run:

```bash
xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme LoopWorkspace -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds. If an existing unrelated build blocker appears, record the exact file, error and command in `PROGRESS.md`; do not mark the build as passed.

- [ ] **Step 3: Run real-device BLE verification when hardware is available**

Use a connected iPhone and LinX device to verify:

- First add flow shows both modes on device.
- Broadcast mode receives at least one valid Aidex/LinX broadcast and writes the latest glucose into Loop.
- Broadcast mode logs `stage=broadcast event=found/parsed/accepted`.
- Broadcast mode does not log direct connection, GATT configure or history request during the broadcast test.
- Direct mode still connects and receives an F003 current glucose notification.

Record exact device, time window and result in `PROGRESS.md`. If hardware is not available, record `未执行` with the exact blocker; do not claim broadcast hardware verification passed.

- [ ] **Step 4: Run preliminary formatting check**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 5: Update progress before commit**

Add a top entry to `PROGRESS.md` with:

- 日期和序号。
- 任务：实现 LinX 广播数据模式。
- 核心交付：setup choice, persisted mode, broadcast parser, no-connect scan path, broadcast入库, settings display.
- 验证结果：paste exact fresh test/build/check results.
- 关键发现：only if any meaningful blocker or behavior is discovered.
- commit hash: `待提交`.
- push 状态: `待推送`.

- [ ] **Step 6: Run formatting check after progress update**

Run:

```bash
git diff --check
```

Expected: no whitespace errors after code, docs and `PROGRESS.md` changes.

- [ ] **Step 7: Commit implementation and initial progress**

Run:

```bash
git add MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsViewModel.swift MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsView.swift MicroTechCGM/MicroTechCGMTests/MicroTechBroadcastModeTests.swift MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj PROGRESS.md
test -e docs/工具与踩坑.md && git add docs/工具与踩坑.md || true
git commit -m "新增 LinX 广播数据模式" -m "改动原因：用户需要在不连接微泰官方 App 蓝牙会话的情况下，让 Loop 读取 LinX 广播中的最新血糖。" -m "改动清单：添加添加页模式选择；保存模式；显示当前数据模式；接入广播扫描、解析和入库；补充相关测试与进展记录。" -m "验证结果：MicroTechCGM 全量测试通过；LoopWorkspace 构建结果按 PROGRESS 记录；git diff --check 通过。" -m "影响范围：MicroTech LinX CGM 添加流程、蓝牙扫描、最新血糖读取和设置页展示。"
```

- [ ] **Step 8: Push implementation with retry**

Run:

```bash
git -c http.proxy=http://127.0.0.1:1082 -c https.proxy=http://127.0.0.1:1082 push origin main
git -c http.proxy=http://127.0.0.1:1082 -c https.proxy=http://127.0.0.1:1082 ls-remote origin refs/heads/main
```

Expected: push succeeds and remote `refs/heads/main` matches local `HEAD`.

If push fails, retry the same push command 2 to 3 times. If it still fails, keep the local commit, record the exact failure in `PROGRESS.md`, run `git diff --check`, commit the failure record if possible, and report that the local commit was not pushed.

- [ ] **Step 9: Update progress with commit hash and push status**

After push succeeds:

```bash
git rev-parse --short HEAD
git -c http.proxy=http://127.0.0.1:1082 -c https.proxy=http://127.0.0.1:1082 ls-remote origin refs/heads/main
```

Update the newest `PROGRESS.md` entry:

- Replace `commit hash: 待提交` with the implementation commit hash.
- Replace `push 状态: 待推送` with the verified remote state.

Run formatting check after the `PROGRESS.md` correction:

```bash
git diff --check
```

Expected: no whitespace errors in the final progress correction.

Commit and push the progress correction:

```bash
git add PROGRESS.md
git commit -m "文档 更新 LinX 广播模式推送状态" -m "改动原因：补齐 LinX 广播数据模式实现提交后的真实 commit hash 和 push 状态。" -m "改动清单：更新 PROGRESS.md 最新条目的 commit hash 与远端状态。" -m "验证结果：git diff --check 通过；远端 refs/heads/main 已核对。" -m "影响范围：项目进展记录。"
git -c http.proxy=http://127.0.0.1:1082 -c https.proxy=http://127.0.0.1:1082 push origin main
git -c http.proxy=http://127.0.0.1:1082 -c https.proxy=http://127.0.0.1:1082 ls-remote origin refs/heads/main
```

Apply the same 2 to 3 retry rule on this push.

## Implementation Notes

- Do not change Dexcom, Libre, Nightscout or other CGM plugins.
- Do not add background BLE interception of other Apps; iOS does not allow reading another App's active BLE connection data.
- Do not log or persist new secrets for broadcast mode. Existing LinX direct-connection full packet/key logging remains unchanged.
- Do not commit `LoopWorkspace.xcworkspace/xcuserdata/`, `build/` or `log/`.
- If a test command uses a simulator name not available on the machine, run `xcrun simctl list devices available` and choose an installed iPhone simulator. Record the actual destination in `PROGRESS.md`.
