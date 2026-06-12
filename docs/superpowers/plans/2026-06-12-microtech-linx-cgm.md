# MicroTech LinX CGM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a MicroTech LinX CGM source to Loop that appears in the CGM picker, connects to LinX over BLE, completes Aidex authentication, and emits Loop glucose samples from real-time packets.

**Architecture:** Add a standalone `MicroTechCGM` module shaped like `G7SensorKit`: core framework, UI framework, and `.loopplugin` bundle. Keep Aidex crypto/parsing independent from CoreBluetooth so it is unit-tested before the BLE session and Loop manager are wired in. History packets are parsed and logged, but first release only emits current glucose from `0x01` packets.

**Tech Stack:** Swift, XCTest, CoreBluetooth, LoopKit, LoopKitUI, HealthKit, CryptoKit for MD5, CommonCrypto for AES block encryption used by Aidex AES-CFB.

---

## Completion Standards

- `MicroTech LinX` appears in Loop's CGM add list.
- A selected LinX device is saved in manager state and survives app relaunch.
- BLE handshake follows the verified Aidex order: subscribe `F002`, try subscribe `F001`, write initial `F001` key, wait or fall back to pairing key, write pairing key, read `F002` challenge, derive session key, subscribe `F003`, write `cmd10`.
- `F003` real-time `0x01` notifications become `NewGlucoseSample`.
- CRC, AES-CFB, command generation, parser, state restore, duplicate filtering, and plugin metadata are covered by tests.
- `git diff --check` passes.
- `xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17'` passes.
- `xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme Loop -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` reaches a deterministic pass or a single documented signing-only stop.
- `PROGRESS.md` is updated after implementation, verification, commit, and push.

## File Structure

- Create: `MicroTechCGM/MicroTechCGM.xcodeproj`
- Create: `MicroTechCGM/MicroTechCGM/Info.plist`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexProfile.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexCrypto.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexCommandBuilder.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexPacket.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexParser.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechGlucoseReading.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechPeripheralManager.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/Data.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/Locked.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/OSLog.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Info.plist`
- Create: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechCGMManager+UI.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsView.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsViewModel.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Extensions/Bundle.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/LocalizedString.swift`
- Create: `MicroTechCGM/MicroTechCGMPlugin/Info.plist`
- Create: `MicroTechCGM/MicroTechCGMPlugin/MicroTechCGMPlugin.swift`
- Create: `MicroTechCGM/MicroTechCGMPlugin/MicroTechCGMPlugin.h`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexCryptoTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`
- Modify: `LoopWorkspace.xcworkspace/contents.xcworkspacedata`
- Modify: `LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme`
- Modify: `PROGRESS.md`

Reference sources:

- `G7SensorKit/G7SensorKit/G7CGMManager/G7CGMManager.swift`
- `G7SensorKit/G7SensorKit/G7CGMManager/G7Sensor.swift`
- `G7SensorKit/G7SensorKit/G7CGMManager/G7BluetoothManager.swift`
- `G7SensorKit/G7SensorKit/G7CGMManager/G7PeripheralManager.swift`
- `G7SensorKit/G7SensorKitUI/G7CGMManager/G7CGMManager+UI.swift`
- `G7SensorKit/G7SensorPlugin/G7SensorPlugin.swift`
- `/Users/liyang/Documents/codex/aoji/lib/features/collector/domain/aidex/aidex_crypto.dart`
- `/Users/liyang/Documents/codex/aoji/lib/features/collector/domain/aidex/aidex_protocol.dart`
- `/Users/liyang/Documents/codex/aoji/lib/features/collector/domain/linx_record.dart`
- `/Users/liyang/Documents/codex/aoji/lib/features/collector/application/linx_aidex_collector.dart`

### Task 1: Create MicroTech Project Skeleton

**Files:**
- Create: `MicroTechCGM/`
- Create: `MicroTechCGM/MicroTechCGM.xcodeproj`
- Create: `MicroTechCGM/MicroTechCGM/Info.plist`
- Create: `MicroTechCGM/MicroTechCGMUI/Info.plist`
- Create: `MicroTechCGM/MicroTechCGMPlugin/Info.plist`
- Create: `MicroTechCGM/MicroTechCGMTests/Info.plist`

- [ ] **Step 1: Verify clean baseline**

Run:

```bash
git status --short --branch
```

Expected: only `LoopWorkspace.xcworkspace/xcuserdata/liyang.xcuserdatad/UserInterfaceState.xcuserstate` may be modified before this task starts.

- [ ] **Step 2: Create folders**

Run:

```bash
mkdir -p MicroTechCGM/MicroTechCGM/Extensions
mkdir -p MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager
mkdir -p MicroTechCGM/MicroTechCGMUI/Views
mkdir -p MicroTechCGM/MicroTechCGMUI/Extensions
mkdir -p MicroTechCGM/MicroTechCGMPlugin
mkdir -p MicroTechCGM/MicroTechCGMTests
```

Expected: all folders exist.

- [ ] **Step 3: Generate a minimal Xcode project using the local `xcodeproj` gem**

Run this Ruby script from the repository root:

```bash
ruby - <<'RUBY'
require 'xcodeproj'

project_path = 'MicroTechCGM/MicroTechCGM.xcodeproj'
project = Xcodeproj::Project.new(project_path)

ios = '15.0'

microtech = project.new_target(:framework, 'MicroTechCGM', :ios, ios)
ui = project.new_target(:framework, 'MicroTechCGMUI', :ios, ios)
plugin = project.new_target(:framework, 'MicroTechCGMPlugin', :ios, ios)
tests = project.new_target(:unit_test_bundle, 'MicroTechCGMTests', :ios, ios)

[microtech, ui, plugin, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "org.loopkit.#{target.name}"
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  end
end

microtech.build_configurations.each { |config| config.build_settings['PRODUCT_NAME'] = 'MicroTechCGM' }
ui.build_configurations.each { |config| config.build_settings['PRODUCT_NAME'] = 'MicroTechCGMUI' }
plugin.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'MicroTechCGMPlugin'
  config.build_settings['WRAPPER_EXTENSION'] = 'loopplugin'
end

tests.add_dependency(microtech)
ui.add_dependency(microtech)
plugin.add_dependency(microtech)
plugin.add_dependency(ui)

project.save
RUBY
```

Expected: `MicroTechCGM/MicroTechCGM.xcodeproj/project.pbxproj` exists and `xcodebuild -project MicroTechCGM/MicroTechCGM.xcodeproj -list` lists the four targets.

- [ ] **Step 4: Add plist files**

Create `MicroTechCGM/MicroTechCGM/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
</dict>
</plist>
```

Create `MicroTechCGM/MicroTechCGMUI/Info.plist` with the same content and bundle name.

Create `MicroTechCGM/MicroTechCGMTests/Info.plist` with the same content, changing `CFBundlePackageType` to `BNDL`.

Create `MicroTechCGM/MicroTechCGMPlugin/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>NSPrincipalClass</key>
	<string>MicroTechCGMPlugin</string>
	<key>com.loopkit.Loop.CGMManagerDisplayName</key>
	<string>MicroTech LinX</string>
	<key>com.loopkit.Loop.CGMManagerIdentifier</key>
	<string>MicroTechLinXCGMManager</string>
</dict>
</plist>
```

- [ ] **Step 5: Attach plist paths to targets**

Run:

```bash
ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('MicroTechCGM/MicroTechCGM.xcodeproj')
{
  'MicroTechCGM' => 'MicroTechCGM/Info.plist',
  'MicroTechCGMUI' => 'MicroTechCGMUI/Info.plist',
  'MicroTechCGMPlugin' => 'MicroTechCGMPlugin/Info.plist',
  'MicroTechCGMTests' => 'MicroTechCGMTests/Info.plist'
}.each do |target_name, plist|
  target = project.targets.find { |item| item.name == target_name }
  target.build_configurations.each do |config|
    config.build_settings['INFOPLIST_FILE'] = plist
  end
end
project.save
RUBY
```

Expected: each target has a concrete `INFOPLIST_FILE`.

- [ ] **Step 6: Verify and commit skeleton**

Run:

```bash
xcodebuild -project MicroTechCGM/MicroTechCGM.xcodeproj -list
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech CGM 工程骨架"
```

Expected: project list command succeeds, diff check passes, and commit is created.

### Task 2: Add Aidex Constants, Data Helpers, and CRC

**Files:**
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexProfile.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/Data.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexCrypto.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexCryptoTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MicroTechCGM/MicroTechCGMTests/MicroTechAidexCryptoTests.swift` with:

```swift
import XCTest
@testable import MicroTechCGM

final class MicroTechAidexCryptoTests: XCTestCase {
    func testProfileUUIDs() {
        XCTAssertEqual("0000181F-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.serviceUUID.uuidString)
        XCTAssertEqual("0000F001-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f001UUID.uuidString)
        XCTAssertEqual("0000F002-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f002UUID.uuidString)
        XCTAssertEqual("0000F003-0000-1000-8000-00805F9B34FB", MicroTechAidexProfile.f003UUID.uuidString)
    }

    func testHexRoundTripAndLittleEndian() throws {
        let data = try Data(microTechHexadecimalString: "01 02 0A ff")
        XCTAssertEqual("01020AFF", data.microTechHexadecimalString)
        XCTAssertEqual(0x0201, data.microTechUInt16(at: 0))
        XCTAssertEqual(-246, Data([0x0A, 0xFF]).microTechInt16(at: 0))
        XCTAssertEqual(-1, Data([0xFF]).microTechInt8(at: 0))
    }

    func testCRC16Ccitt() throws {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(0xADAD, MicroTechAidexCrypto.crc16Ccitt(data))
        XCTAssertEqual(try Data(microTechHexadecimalString: "010203ADAD"), MicroTechAidexCrypto.appendingCRC(to: data))
        XCTAssertTrue(MicroTechAidexCrypto.hasValidTrailingCRC(try Data(microTechHexadecimalString: "010203ADAD")))
        XCTAssertFalse(MicroTechAidexCrypto.hasValidTrailingCRC(try Data(microTechHexadecimalString: "010203ADAE")))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexCryptoTests
```

Expected: fails because `MicroTechAidexProfile`, hex helpers, and CRC are not implemented.

- [ ] **Step 3: Add constants and helpers**

Create `MicroTechCGM/MicroTechCGM/MicroTechAidexProfile.swift`:

```swift
import CoreBluetooth

public enum MicroTechAidexProfile {
    public static let serviceUUID = CBUUID(string: "0000181F-0000-1000-8000-00805F9B34FB")
    public static let f001UUID = CBUUID(string: "0000F001-0000-1000-8000-00805F9B34FB")
    public static let f002UUID = CBUUID(string: "0000F002-0000-1000-8000-00805F9B34FB")
    public static let f003UUID = CBUUID(string: "0000F003-0000-1000-8000-00805F9B34FB")
}
```

Create `MicroTechCGM/MicroTechCGM/Extensions/Data.swift`:

```swift
import Foundation

public enum MicroTechDataError: Error, Equatable {
    case oddLengthHexString
    case invalidHexByte(String)
    case offsetOutOfBounds
}

public extension Data {
    init(microTechHexadecimalString string: String) throws {
        let normalized = string.filter { !$0.isWhitespace }
        guard normalized.count.isMultiple(of: 2) else {
            throw MicroTechDataError.oddLengthHexString
        }

        var bytes: [UInt8] = []
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let token = String(normalized[index..<nextIndex])
            guard let value = UInt8(token, radix: 16) else {
                throw MicroTechDataError.invalidHexByte(token)
            }
            bytes.append(value)
            index = nextIndex
        }
        self.init(bytes)
    }

    var microTechHexadecimalString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    func microTechUInt16(at offset: Int) -> UInt16 {
        precondition(offset >= 0 && offset + 1 < count)
        return UInt16(self[self.index(startIndex, offsetBy: offset)]) |
            UInt16(self[self.index(startIndex, offsetBy: offset + 1)]) << 8
    }

    func microTechInt16(at offset: Int) -> Int16 {
        Int16(bitPattern: microTechUInt16(at: offset))
    }

    func microTechInt8(at offset: Int) -> Int8 {
        precondition(offset >= 0 && offset < count)
        return Int8(bitPattern: self[self.index(startIndex, offsetBy: offset)])
    }
}
```

Add the CRC part of `MicroTechCGM/MicroTechCGM/MicroTechAidexCrypto.swift`:

```swift
import Foundation

public enum MicroTechAidexCryptoError: Error, Equatable {
    case invalidKeyLength(Int)
    case invalidIVLength(Int)
    case aesFailure(Int32)
    case emptyChallenge
    case keyTooShort(Int)
}

public enum MicroTechAidexCrypto {
    public static func crc16Ccitt(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    public static func appendingCRC(to payload: Data) -> Data {
        let crc = crc16Ccitt(payload)
        var data = payload
        data.append(UInt8(crc & 0x00FF))
        data.append(UInt8((crc >> 8) & 0x00FF))
        return data
    }

    public static func hasValidTrailingCRC(_ packet: Data) -> Bool {
        guard packet.count >= 3 else {
            return false
        }
        let payload = packet.dropLast(2)
        let expected = packet.microTechUInt16(at: packet.count - 2)
        return crc16Ccitt(Data(payload)) == expected
    }
}
```

- [ ] **Step 4: Add source files to Xcode target**

Run:

```bash
ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('MicroTechCGM/MicroTechCGM.xcodeproj')
target = project.targets.find { |item| item.name == 'MicroTechCGM' }
tests = project.targets.find { |item| item.name == 'MicroTechCGMTests' }
group = project.main_group.find_subpath('MicroTechCGM', true)
test_group = project.main_group.find_subpath('MicroTechCGMTests', true)
[
  'MicroTechCGM/MicroTechAidexProfile.swift',
  'MicroTechCGM/Extensions/Data.swift',
  'MicroTechCGM/MicroTechAidexCrypto.swift'
].each do |path|
  ref = group.new_file(path)
  target.add_file_references([ref])
end
ref = test_group.new_file('MicroTechCGMTests/MicroTechAidexCryptoTests.swift')
tests.add_file_references([ref])
project.save
RUBY
```

Expected: these files appear in the correct target source phases.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexCryptoTests
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech Aidex 基础协议工具"
```

Expected: crypto helper tests pass, diff check passes, and commit is created.

### Task 3: Implement Aidex AES-CFB, Key Derivation, and Commands

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechAidexCrypto.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexCommandBuilder.swift`
- Modify: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexCryptoTests.swift`

- [ ] **Step 1: Extend failing tests with known vectors**

Append to `MicroTechAidexCryptoTests`:

```swift
func testSerialKeyDerivation() throws {
    let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
    XCTAssertEqual("ABC123", material.sensorSerial)
    XCTAssertEqual("C21D3C97C38DD60B2B0E129EC9EA1C84", material.key.microTechHexadecimalString)
    XCTAssertEqual("5A837629840E30374590EE4D7DF612DE", material.iv.microTechHexadecimalString)

    let fromName = MicroTechAidexKeyMaterial.derive(deviceName: "LinX-ABC123")
    XCTAssertEqual(material, fromName)
}

func testAESCfbRoundTrip() throws {
    let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
    let plain = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
    let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: plain)
    XCTAssertEqual("A11963C33AD331B94B3352FFBF39B9455B9C01", encrypted.microTechHexadecimalString)
    let decrypted = try MicroTechAidexCrypto.decryptCfb128(key: material.key, iv: material.iv, cipher: encrypted)
    XCTAssertEqual(plain, decrypted)
}

func testCommandBuilderVectors() throws {
    let builder = MicroTechAidexCommandBuilder(keyMaterial: .derive(serial: "ABC123"))
    XCTAssertEqual("B0D893", try builder.cmd10().microTechHexadecimalString)
    XCTAssertEqual("B1F983", try builder.cmd11().microTechHexadecimalString)
    XCTAssertEqual("9118EA07", try builder.cmd31().microTechHexadecimalString)
    XCTAssertEqual("94181FF8", try builder.cmd34().microTechHexadecimalString)
    XCTAssertEqual("95182ECB", try builder.cmd35().microTechHexadecimalString)
    XCTAssertEqual("8333601BEA", try builder.cmd23(index: 42).microTechHexadecimalString)
    XCTAssertEqual("53955E", try builder.clearStorage().microTechHexadecimalString)
}

func testSessionMaterialFromChallenge() throws {
    let base = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
    let pairingKey = base.key
    let plainSessionKey = try Data(microTechHexadecimalString: "00112233445566778899AABBCCDDEEFF")
    let encryptedChallenge = try MicroTechAidexCrypto.encryptCfb128(key: pairingKey, iv: base.iv, plain: plainSessionKey)
    let session = try MicroTechAidexKeyMaterial.deriveSessionMaterial(baseMaterial: base, encryptedChallenge: encryptedChallenge, pairingKey: pairingKey)
    XCTAssertEqual("00112233445566778899AABBCCDDEEFF", session.key.microTechHexadecimalString)
    XCTAssertEqual(base.iv, session.iv)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexCryptoTests
```

Expected: fails because key derivation, AES-CFB, and command builder are missing.

- [ ] **Step 3: Implement key material and AES-CFB**

Extend `MicroTechAidexCrypto.swift`:

```swift
import CommonCrypto
import CryptoKit
import Foundation

public struct MicroTechAidexKeyMaterial: Equatable {
    public let sensorSerial: String
    public let key: Data
    public let iv: Data

    public static func derive(deviceName: String) -> MicroTechAidexKeyMaterial {
        let serial = deviceName.split(separator: "-").last.map(String.init) ?? deviceName
        return derive(serial: serial)
    }

    public static func derive(serial: String) -> MicroTechAidexKeyMaterial {
        let serialBytes = serial.compactMap { character -> UInt8? in
            guard let scalar = character.unicodeScalars.first else {
                return nil
            }
            let value = scalar.value
            if value >= 0x30 && value <= 0x39 {
                return UInt8(value - 0x30)
            }
            if value >= 0x41 && value <= 0x5A {
                return UInt8(value - 0x41 + 10)
            }
            if value >= 0x61 && value <= 0x7A {
                return UInt8(value - 0x61 + 10)
            }
            return UInt8(value & 0xFF)
        }

        let keyInput = Data(serialBytes.map { UInt8((UInt16($0) * 13 + 61) & 0xFF) })
        let ivInput = Data(serialBytes.map { UInt8((UInt16($0) * 17 + 19) & 0xFF) })
        return MicroTechAidexKeyMaterial(
            sensorSerial: serial,
            key: Data(Insecure.MD5.hash(data: keyInput)),
            iv: Data(Insecure.MD5.hash(data: ivInput))
        )
    }

    public static func deriveSessionMaterial(baseMaterial: MicroTechAidexKeyMaterial, encryptedChallenge: Data, pairingKey: Data) throws -> MicroTechAidexKeyMaterial {
        guard !encryptedChallenge.isEmpty else {
            throw MicroTechAidexCryptoError.emptyChallenge
        }
        let normalizedPairingKey = try normalizeKey(pairingKey)
        let decrypted = try MicroTechAidexCrypto.decryptCfb128(key: normalizedPairingKey, iv: baseMaterial.iv, cipher: encryptedChallenge)
        return MicroTechAidexKeyMaterial(
            sensorSerial: baseMaterial.sensorSerial,
            key: try normalizeKey(decrypted),
            iv: baseMaterial.iv
        )
    }

    public static func normalizeKey(_ key: Data) throws -> Data {
        guard key.count >= 16 else {
            throw MicroTechAidexCryptoError.keyTooShort(key.count)
        }
        return key.prefix(16)
    }
}

public extension MicroTechAidexCrypto {
    static func encryptCfb128(key: Data, iv: Data, plain: Data) throws -> Data {
        try cfb128(key: key, iv: iv, input: plain, encrypting: true)
    }

    static func decryptCfb128(key: Data, iv: Data, cipher: Data) throws -> Data {
        try cfb128(key: key, iv: iv, input: cipher, encrypting: false)
    }

    private static func cfb128(key: Data, iv: Data, input: Data, encrypting: Bool) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw MicroTechAidexCryptoError.invalidKeyLength(key.count)
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw MicroTechAidexCryptoError.invalidIVLength(iv.count)
        }

        var feedback = [UInt8](iv)
        let inputBytes = [UInt8](input)
        var output = [UInt8](repeating: 0, count: inputBytes.count)

        var offset = 0
        while offset < inputBytes.count {
            let encryptedFeedback = try aesEncryptBlock(Data(feedback), key: key)
            let blockLength = min(kCCBlockSizeAES128, inputBytes.count - offset)
            let encryptedBytes = [UInt8](encryptedFeedback)
            for index in 0..<blockLength {
                let inputByte = inputBytes[offset + index]
                let outputByte = inputByte ^ encryptedBytes[index]
                output[offset + index] = outputByte
                feedback[index] = encrypting ? outputByte : inputByte
            }
            offset += blockLength
        }

        return Data(output)
    }

    private static func aesEncryptBlock(_ block: Data, key: Data) throws -> Data {
        precondition(block.count == kCCBlockSizeAES128)
        var output = Data(count: kCCBlockSizeAES128)
        var outputLength = 0
        let status = key.withUnsafeBytes { keyBytes in
            block.withUnsafeBytes { blockBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        blockBytes.baseAddress,
                        block.count,
                        outputBytes.baseAddress,
                        output.count,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw MicroTechAidexCryptoError.aesFailure(status)
        }
        return output.prefix(outputLength)
    }
}
```

- [ ] **Step 4: Implement command builder**

Create `MicroTechCGM/MicroTechCGM/MicroTechAidexCommandBuilder.swift`:

```swift
import Foundation

public struct MicroTechAidexCommandBuilder {
    public let keyMaterial: MicroTechAidexKeyMaterial

    public init(keyMaterial: MicroTechAidexKeyMaterial) {
        self.keyMaterial = keyMaterial
    }

    public func cmd10() throws -> Data {
        try encrypt(hex: "10C1F3")
    }

    public func cmd11() throws -> Data {
        try decryptPlain(hex: "11E0E3")
    }

    public func cmd20(dateTimeBytes: Data) throws -> Data {
        var payload = Data([0x20])
        payload.append(dateTimeBytes)
        return try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: payload))
    }

    public func cmd23(index: Int) throws -> Data {
        var payload = Data([0x23])
        payload.append(UInt8(index & 0xFF))
        payload.append(UInt8((index >> 8) & 0xFF))
        return try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: payload))
    }

    public func cmd31() throws -> Data {
        try decryptPlain(hex: "31018A3B")
    }

    public func cmd34() throws -> Data {
        try decryptPlain(hex: "34017FC4")
    }

    public func cmd35() throws -> Data {
        try decryptPlain(hex: "35014EF7")
    }

    public func unpair() throws -> Data {
        try decryptPlain(data: MicroTechAidexCrypto.appendingCRC(to: Data([0xF2])))
    }

    public func clearStorage() throws -> Data {
        try encrypt(hex: "F38C3E")
    }

    public func decryptNotification(_ encrypted: Data) throws -> Data {
        try MicroTechAidexCrypto.decryptCfb128(key: keyMaterial.key, iv: keyMaterial.iv, cipher: encrypted)
    }

    private func encrypt(hex: String) throws -> Data {
        try MicroTechAidexCrypto.encryptCfb128(
            key: keyMaterial.key,
            iv: keyMaterial.iv,
            plain: Data(microTechHexadecimalString: hex)
        )
    }

    private func decryptPlain(hex: String) throws -> Data {
        try decryptPlain(data: Data(microTechHexadecimalString: hex))
    }

    private func decryptPlain(data: Data) throws -> Data {
        try MicroTechAidexCrypto.decryptCfb128(
            key: keyMaterial.key,
            iv: keyMaterial.iv,
            cipher: data
        )
    }
}
```

- [ ] **Step 5: Add command file to target**

Run:

```bash
ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('MicroTechCGM/MicroTechCGM.xcodeproj')
target = project.targets.find { |item| item.name == 'MicroTechCGM' }
group = project.main_group.find_subpath('MicroTechCGM', true)
ref = group.new_file('MicroTechCGM/MicroTechAidexCommandBuilder.swift')
target.add_file_references([ref])
project.save
RUBY
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexCryptoTests
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech Aidex 加密和命令生成"
```

Expected: all crypto tests pass and commit is created.

### Task 4: Implement Aidex Packet Parser

**Files:**
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexPacket.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechAidexParser.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechGlucoseReading.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift`

- [ ] **Step 1: Write parser tests**

Create `MicroTechCGM/MicroTechCGMTests/MicroTechAidexParserTests.swift`:

```swift
import XCTest
@testable import MicroTechCGM

final class MicroTechAidexParserTests: XCTestCase {
    func testCurrentPacket() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .current(let current) = parsed else {
            return XCTFail("Expected current packet")
        }
        XCTAssertEqual(0x01, current.packetType)
        XCTAssertEqual(-1, current.trend)
        XCTAssertEqual(42, current.timeOffset)
        XCTAssertEqual(123, current.glucose)
        XCTAssertEqual(0, current.quality)
        XCTAssertEqual(12.34, current.i1)
        XCTAssertEqual(25.0, current.i2)
        XCTAssertEqual(30.0, current.vc)
        XCTAssertEqual(3, current.status)
        XCTAssertEqual(1, current.byte14Flag)
    }

    func testHistoryPacket() throws {
        let packet = try Data(microTechHexadecimalString: "2300E8036F007000FFFFFB1A")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .history(let history) = parsed else {
            return XCTFail("Expected history packet")
        }
        XCTAssertEqual(1000, history.startTimeOffset)
        XCTAssertEqual(2, history.records.count)
        XCTAssertEqual(1000, history.records[0].timeOffset)
        XCTAssertEqual(111, history.records[0].glucose)
        XCTAssertEqual(1001, history.records[1].timeOffset)
        XCTAssertEqual(112, history.records[1].glucose)
    }

    func testInvalidCRCThrows() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC4")
        XCTAssertThrowsError(try MicroTechAidexParser.parse(packet)) { error in
            XCTAssertEqual(error as? MicroTechAidexParserError, .invalidCRC)
        }
    }

    func testReadingConversionFiltersInvalidValues() throws {
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let parsed = try MicroTechAidexParser.parse(packet)
        guard case .current(let current) = parsed else {
            return XCTFail("Expected current packet")
        }
        let reading = MicroTechGlucoseReading(current: current, sensorSerial: "ABC123", receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(123, reading.glucoseMgdl)
        XCTAssertEqual("ABC123-42", reading.syncIdentifier)
        XCTAssertEqual(.flat, reading.trendType)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexParserTests
```

Expected: fails because parser types are missing.

- [ ] **Step 3: Add packet models**

Create `MicroTechCGM/MicroTechCGM/MicroTechAidexPacket.swift`:

```swift
import Foundation

public enum MicroTechAidexParserError: Error, Equatable {
    case emptyPacket
    case invalidCRC
    case invalidPacket
    case unsupportedPacket(UInt8)
}

public enum MicroTechAidexPacket: Equatable {
    case current(MicroTechAidexCurrentPacket)
    case history(MicroTechAidexHistoryPacket)
    case startTime(MicroTechAidexStartTimePacket)
}

public struct MicroTechAidexCurrentPacket: Equatable {
    public let rawBytes: Data
    public let packetType: UInt8
    public let trend: Int
    public let timeOffset: Int
    public let glucoseRaw: Int
    public let glucose: Int
    public let quality: Int
    public let i1: Double
    public let i2: Double
    public let vc: Double
    public let status: Int
    public let byte14Flag: Int
}

public struct MicroTechAidexHistoryRecord: Equatable {
    public let timeOffset: Int
    public let glucose: Int
    public let rawValue: Int
}

public struct MicroTechAidexHistoryPacket: Equatable {
    public let rawBytes: Data
    public let startTimeOffset: Int
    public let records: [MicroTechAidexHistoryRecord]
}

public struct MicroTechAidexStartTimePacket: Equatable {
    public let rawBytes: Data
    public let startTimeByte: UInt8
    public let timestamp: Date?
}
```

- [ ] **Step 4: Add parser and reading conversion**

Create `MicroTechCGM/MicroTechCGM/MicroTechAidexParser.swift`:

```swift
import Foundation

public enum MicroTechAidexParser {
    public static func parse(_ packet: Data) throws -> MicroTechAidexPacket {
        guard let packetType = packet.first else {
            throw MicroTechAidexParserError.emptyPacket
        }
        if packetType != 0x21 && !MicroTechAidexCrypto.hasValidTrailingCRC(packet) {
            throw MicroTechAidexParserError.invalidCRC
        }
        switch packetType {
        case 0x01:
            return .current(try parseCurrent(packet))
        case 0x21:
            return .startTime(parseStartTime(packet))
        case 0x23:
            return .history(try parseHistory(packet))
        default:
            throw MicroTechAidexParserError.unsupportedPacket(packetType)
        }
    }

    private static func parseCurrent(_ data: Data) throws -> MicroTechAidexCurrentPacket {
        guard data.count >= 17 else {
            throw MicroTechAidexParserError.invalidPacket
        }
        let glucoseRaw = Int(data.microTechUInt16(at: 6))
        return MicroTechAidexCurrentPacket(
            rawBytes: data,
            packetType: 0x01,
            trend: Int(data.microTechInt8(at: 3)),
            timeOffset: Int(data.microTechUInt16(at: 4)),
            glucoseRaw: glucoseRaw,
            glucose: glucoseRaw & 0x03FF,
            quality: (glucoseRaw >> 10) & 0x03,
            i1: Double(data.microTechInt16(at: 8)) / 100.0,
            i2: Double(data.microTechInt16(at: 10)) / 100.0,
            vc: Double(data.microTechUInt16(at: 12)) / 100.0,
            status: Int(data[data.index(data.startIndex, offsetBy: 2)]),
            byte14Flag: Int(data[data.index(data.startIndex, offsetBy: 14)])
        )
    }

    private static func parseHistory(_ data: Data) throws -> MicroTechAidexHistoryPacket {
        guard data.count >= 8 else {
            throw MicroTechAidexParserError.invalidPacket
        }
        var timeOffset = Int(data.microTechUInt16(at: 2))
        var records: [MicroTechAidexHistoryRecord] = []
        var position = 4
        while position + 1 < data.count - 2 {
            let rawValue = Int(data.microTechUInt16(at: position))
            if rawValue == 0xFFFF {
                break
            }
            records.append(MicroTechAidexHistoryRecord(timeOffset: timeOffset, glucose: rawValue & 0x03FF, rawValue: rawValue))
            timeOffset += 1
            position += 2
        }
        return MicroTechAidexHistoryPacket(rawBytes: data, startTimeOffset: Int(data.microTechUInt16(at: 2)), records: records)
    }

    private static func parseStartTime(_ data: Data) -> MicroTechAidexStartTimePacket {
        MicroTechAidexStartTimePacket(rawBytes: data, startTimeByte: data.count > 2 ? data[data.index(data.startIndex, offsetBy: 2)] : 0, timestamp: parseDate(in: data))
    }

    private static func parseDate(in data: Data) -> Date? {
        guard data.count >= 7 else {
            return nil
        }
        let bytes = [UInt8](data)
        for index in 0...(bytes.count - 7) {
            let year = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            let month = Int(bytes[index + 2])
            let day = Int(bytes[index + 3])
            let hour = Int(bytes[index + 4])
            let minute = Int(bytes[index + 5])
            let second = Int(bytes[index + 6])
            guard year >= 2000 && year <= 2100,
                  month >= 1 && month <= 12,
                  day >= 1 && day <= 31,
                  hour <= 23,
                  minute <= 59,
                  second <= 59 else {
                continue
            }
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        }
        return nil
    }
}
```

Create `MicroTechCGM/MicroTechCGM/MicroTechGlucoseReading.swift`:

```swift
import Foundation
import HealthKit
import LoopKit

public struct MicroTechGlucoseReading: Equatable, GlucoseDisplayable {
    public let sensorSerial: String
    public let sampleNumber: Int
    public let glucoseMgdl: Int
    public let trend: Int
    public let receivedAt: Date
    public let status: Int
    public let quality: Int
    public let rawBytes: Data

    public init(current: MicroTechAidexCurrentPacket, sensorSerial: String, receivedAt: Date) {
        self.sensorSerial = sensorSerial
        self.sampleNumber = current.timeOffset
        self.glucoseMgdl = current.glucose
        self.trend = current.trend
        self.receivedAt = receivedAt
        self.status = current.status
        self.quality = current.quality
        self.rawBytes = current.rawBytes
    }

    public var syncIdentifier: String {
        "\(sensorSerial)-\(sampleNumber)"
    }

    public var isValidForTherapy: Bool {
        sampleNumber > 0 && glucoseMgdl >= 40 && glucoseMgdl <= 400 && quality == 0
    }

    public var glucoseQuantity: HKQuantity? {
        HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucoseMgdl))
    }

    public var isStateValid: Bool {
        isValidForTherapy
    }

    public var trendRate: HKQuantity? {
        HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: Double(trend))
    }

    public var trendType: GlucoseTrend? {
        switch trend {
        case let value where value <= -3:
            return .downDownDown
        case -2:
            return .downDown
        case -1:
            return .down
        case 0:
            return .flat
        case 1:
            return .up
        case 2:
            return .upUp
        case let value where value >= 3:
            return .upUpUp
        default:
            return nil
        }
    }

    public var glucoseRangeCategory: GlucoseRangeCategory? {
        if glucoseMgdl < 40 {
            return .belowRange
        }
        if glucoseMgdl > 400 {
            return .aboveRange
        }
        return nil
    }

    public var isLocal: Bool {
        true
    }
}
```

- [ ] **Step 5: Add files to target**

Run:

```bash
ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('MicroTechCGM/MicroTechCGM.xcodeproj')
target = project.targets.find { |item| item.name == 'MicroTechCGM' }
tests = project.targets.find { |item| item.name == 'MicroTechCGMTests' }
group = project.main_group.find_subpath('MicroTechCGM', true)
test_group = project.main_group.find_subpath('MicroTechCGMTests', true)
[
  'MicroTechCGM/MicroTechAidexPacket.swift',
  'MicroTechCGM/MicroTechAidexParser.swift',
  'MicroTechCGM/MicroTechGlucoseReading.swift'
].each do |path|
  ref = group.new_file(path)
  target.add_file_references([ref])
end
ref = test_group.new_file('MicroTechCGMTests/MicroTechAidexParserTests.swift')
tests.add_file_references([ref])
project.save
RUBY
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechAidexParserTests
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech Aidex 数据解析"
```

Expected: parser tests pass and commit is created.

### Task 5: Implement Manager State and Loop Sample Conversion

**Files:**
- Create: `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/Locked.swift`
- Create: `MicroTechCGM/MicroTechCGM/Extensions/OSLog.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **Step 1: Write state tests**

Create `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerStateTests.swift`:

```swift
import XCTest
@testable import MicroTechCGM

final class MicroTechCGMManagerStateTests: XCTestCase {
    func testRawStateRoundTrip() throws {
        let reading = MicroTechGlucoseReading(
            current: MicroTechAidexCurrentPacket(rawBytes: Data([0x01]), packetType: 0x01, trend: 1, timeOffset: 42, glucoseRaw: 123, glucose: 123, quality: 0, i1: 1, i2: 2, vc: 3, status: 3, byte14Flag: 1),
            sensorSerial: "ABC123",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let state = MicroTechCGMManagerState(
            remoteIdentifier: UUID(uuidString: "90FB6D6F-1E69-460B-A8A7-F9B80540859B")!,
            deviceName: "LinX-ABC123",
            sensorSerial: "ABC123",
            activationTime: Date(timeIntervalSince1970: 1_699_999_000),
            lastReadingDate: reading.receivedAt,
            latestReading: reading,
            latestSampleNumber: 42,
            uploadReadings: true
        )

        let restored = MicroTechCGMManagerState(rawValue: state.rawValue)
        XCTAssertEqual(state, restored)
    }
}
```

- [ ] **Step 2: Write manager tests**

Create `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`:

```swift
import HealthKit
import LoopKit
import XCTest
@testable import MicroTechCGM

final class MicroTechCGMManagerTests: XCTestCase {
    func testManagerCreatesLoopSampleFromValidReading() throws {
        let manager = MicroTechCGMManager()
        let current = MicroTechAidexCurrentPacket(rawBytes: Data([0x01]), packetType: 0x01, trend: 1, timeOffset: 42, glucoseRaw: 123, glucose: 123, quality: 0, i1: 1, i2: 2, vc: 3, status: 3, byte14Flag: 1)
        let reading = MicroTechGlucoseReading(current: current, sensorSerial: "ABC123", receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let sample = manager.makeSample(from: reading)
        XCTAssertEqual(123, sample.quantity.doubleValue(for: .milligramsPerDeciliter))
        XCTAssertEqual(reading.receivedAt, sample.date)
        XCTAssertEqual("ABC123-42", sample.syncIdentifier)
        XCTAssertEqual("MicroTech Medical", sample.device?.manufacturer)
        XCTAssertEqual("LinX", sample.device?.model)
    }

    func testManagerRejectsDuplicateSampleNumber() throws {
        let manager = MicroTechCGMManager()
        let current = MicroTechAidexCurrentPacket(rawBytes: Data([0x01]), packetType: 0x01, trend: 1, timeOffset: 42, glucoseRaw: 123, glucose: 123, quality: 0, i1: 1, i2: 2, vc: 3, status: 3, byte14Flag: 1)
        let reading = MicroTechGlucoseReading(current: current, sensorSerial: "ABC123", receivedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNotNil(manager.accept(reading))
        XCTAssertNil(manager.accept(reading))
    }
}
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechCGMManagerStateTests -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
```

Expected: fails because manager state and manager are missing.

- [ ] **Step 4: Implement state**

Create `MicroTechCGM/MicroTechCGM/MicroTechCGMManagerState.swift`:

```swift
import Foundation
import LoopKit

public struct MicroTechCGMManagerState: RawRepresentable, Equatable {
    public typealias RawValue = CGMManager.RawStateValue

    public var remoteIdentifier: UUID?
    public var deviceName: String?
    public var sensorSerial: String?
    public var activationTime: Date?
    public var lastReadingDate: Date?
    public var latestReading: MicroTechGlucoseReading?
    public var latestSampleNumber: Int?
    public var uploadReadings: Bool

    public init(
        remoteIdentifier: UUID? = nil,
        deviceName: String? = nil,
        sensorSerial: String? = nil,
        activationTime: Date? = nil,
        lastReadingDate: Date? = nil,
        latestReading: MicroTechGlucoseReading? = nil,
        latestSampleNumber: Int? = nil,
        uploadReadings: Bool = false
    ) {
        self.remoteIdentifier = remoteIdentifier
        self.deviceName = deviceName
        self.sensorSerial = sensorSerial
        self.activationTime = activationTime
        self.lastReadingDate = lastReadingDate
        self.latestReading = latestReading
        self.latestSampleNumber = latestSampleNumber
        self.uploadReadings = uploadReadings
    }

    public init(rawValue: RawValue) {
        remoteIdentifier = (rawValue["remoteIdentifier"] as? String).flatMap(UUID.init(uuidString:))
        deviceName = rawValue["deviceName"] as? String
        sensorSerial = rawValue["sensorSerial"] as? String
        activationTime = rawValue["activationTime"] as? Date
        lastReadingDate = rawValue["lastReadingDate"] as? Date
        latestSampleNumber = rawValue["latestSampleNumber"] as? Int
        uploadReadings = rawValue["uploadReadings"] as? Bool ?? false
        latestReading = nil
    }

    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue["remoteIdentifier"] = remoteIdentifier?.uuidString
        rawValue["deviceName"] = deviceName
        rawValue["sensorSerial"] = sensorSerial
        rawValue["activationTime"] = activationTime
        rawValue["lastReadingDate"] = lastReadingDate
        rawValue["latestSampleNumber"] = latestSampleNumber
        rawValue["uploadReadings"] = uploadReadings
        return rawValue
    }
}
```

Adjust the test to assert persisted scalar fields; keep `latestReading` in memory only unless encoded explicitly in this same task.

- [ ] **Step 5: Implement manager sample conversion**

Create `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`:

```swift
import Foundation
import HealthKit
import LoopKit
import os.log

public final class MicroTechCGMManager: CGMManager {
    public static let pluginIdentifier = "MicroTechLinXCGMManager"
    public let localizedTitle = "MicroTech LinX"
    public let isOnboarded = true
    public var providesBLEHeartbeat: Bool = true
    public var managedDataInterval: TimeInterval? = .hours(3)

    private let lockedState: Locked<MicroTechCGMManagerState>
    private let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get { delegate.delegate }
        set { delegate.delegate = newValue }
    }

    public var delegateQueue: DispatchQueue! {
        get { delegate.queue }
        set { delegate.queue = newValue }
    }

    public var state: MicroTechCGMManagerState {
        lockedState.value
    }

    public var shouldSyncToRemoteService: Bool {
        state.uploadReadings
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        state.latestReading
    }

    public var cgmManagerStatus: CGMManagerStatus {
        CGMManagerStatus(hasValidSensorSession: state.sensorSerial != nil, lastCommunicationDate: state.lastReadingDate, device: device)
    }

    public init() {
        lockedState = Locked(MicroTechCGMManagerState())
    }

    public required init?(rawState: RawStateValue) {
        lockedState = Locked(MicroTechCGMManagerState(rawValue: rawState))
    }

    public var rawState: RawStateValue {
        state.rawValue
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        completion(.noData)
    }

    public func accept(_ reading: MicroTechGlucoseReading) -> NewGlucoseSample? {
        guard reading.isValidForTherapy else {
            return nil
        }
        guard state.latestSampleNumber != reading.sampleNumber else {
            return nil
        }
        mutateState { state in
            state.sensorSerial = reading.sensorSerial
            state.latestReading = reading
            state.lastReadingDate = reading.receivedAt
            state.latestSampleNumber = reading.sampleNumber
        }
        return makeSample(from: reading)
    }

    public func makeSample(from reading: MicroTechGlucoseReading) -> NewGlucoseSample {
        NewGlucoseSample(
            date: reading.receivedAt,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(reading.glucoseMgdl)),
            condition: reading.glucoseRangeCategory.map { category in
                switch category {
                case .belowRange: return .belowRange
                case .aboveRange: return .aboveRange
                }
            },
            trend: reading.trendType,
            trendRate: reading.trendRate,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: reading.syncIdentifier,
            device: device
        )
    }

    private var device: HKDevice? {
        HKDevice(
            name: state.deviceName ?? state.sensorSerial ?? "MicroTech LinX",
            manufacturer: "MicroTech Medical",
            model: "LinX",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: state.remoteIdentifier?.uuidString,
            udiDeviceIdentifier: nil
        )
    }

    private func mutateState(_ changes: (inout MicroTechCGMManagerState) -> Void) {
        let oldValue = lockedState.value
        let newValue = lockedState.mutate { state in
            changes(&state)
        }
        if oldValue != newValue {
            delegate.notify { delegate in
                delegate?.cgmManagerDidUpdateState(self)
                delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
            }
        }
    }
}
```

Copy `Locked.swift` and `OSLog.swift` from `G7SensorKit/Common/Locked.swift` and `G7SensorKit/G7SensorKit/OSLog.swift`, renaming only module-specific categories if needed.

- [ ] **Step 6: Add files to target**

Run the Xcode project update script for all new files in this task.

- [ ] **Step 7: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechCGMManagerStateTests -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech CGM 状态和样本转换"
```

Expected: manager state and manager tests pass.

### Task 6: Implement BLE Handshake with Mockable Peripheral

**Files:**
- Create: `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift`
- Create: `MicroTechCGM/MicroTechCGM/MicroTechPeripheralManager.swift`
- Create: `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`

- [ ] **Step 1: Write handshake tests with a fake peripheral session**

Create `MicroTechCGM/MicroTechCGMTests/MicroTechSensorHandshakeTests.swift`:

```swift
import CoreBluetooth
import XCTest
@testable import MicroTechCGM

final class MicroTechSensorHandshakeTests: XCTestCase {
    func testHandshakeOrder() throws {
        let peripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "90FB6D6F-1E69-460B-A8A7-F9B80540859B")!,
            deviceName: "LinX-ABC123",
            f001PairingKey: MicroTechAidexKeyMaterial.derive(serial: "ABC123").key,
            f002Challenge: try MicroTechAidexCrypto.encryptCfb128(
                key: MicroTechAidexKeyMaterial.derive(serial: "ABC123").key,
                iv: MicroTechAidexKeyMaterial.derive(serial: "ABC123").iv,
                plain: MicroTechAidexKeyMaterial.derive(serial: "ABC123").key
            )
        )
        let sensor = MicroTechSensor(session: peripheral, now: { Date(timeIntervalSince1970: 1_700_000_000) })

        try sensor.start()

        XCTAssertEqual([
            "subscribe:0000F002-0000-1000-8000-00805F9B34FB",
            "subscribe:0000F001-0000-1000-8000-00805F9B34FB",
            "write:0000F001-0000-1000-8000-00805F9B34FB:C21D3C97C38DD60B2B0E129EC9EA1C84",
            "write:0000F001-0000-1000-8000-00805F9B34FB:C21D3C97C38DD60B2B0E129EC9EA1C84",
            "read:0000F002-0000-1000-8000-00805F9B34FB",
            "subscribe:0000F003-0000-1000-8000-00805F9B34FB",
            "write:0000F002-0000-1000-8000-00805F9B34FB:B0D893"
        ], peripheral.events)
    }

    func testF003CurrentNotificationEmitsReading() throws {
        let material = MicroTechAidexKeyMaterial.derive(serial: "ABC123")
        let packet = try Data(microTechHexadecimalString: "010003FF2A007B00D204C409B80B0100003FC5")
        let encrypted = try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: packet)
        let peripheral = FakeMicroTechPeripheralSession(
            deviceIdentifier: UUID(uuidString: "90FB6D6F-1E69-460B-A8A7-F9B80540859B")!,
            deviceName: "LinX-ABC123",
            f001PairingKey: material.key,
            f002Challenge: try MicroTechAidexCrypto.encryptCfb128(key: material.key, iv: material.iv, plain: material.key)
        )
        let sensor = MicroTechSensor(session: peripheral, now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let observer = ReadingObserver()
        sensor.delegate = observer

        try sensor.start()
        try sensor.handleNotification(characteristic: MicroTechAidexProfile.f003UUID, value: encrypted, receivedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(123, observer.readings.single?.glucoseMgdl)
        XCTAssertEqual(42, observer.readings.single?.sampleNumber)
    }
}
```

Include `FakeMicroTechPeripheralSession`, `ReadingObserver`, and `Array.single` in the same test file. The fake must record `subscribe`, `write`, and `read` calls in order and return the configured challenge for `F002`.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechSensorHandshakeTests
```

Expected: fails because sensor and peripheral session types are missing.

- [ ] **Step 3: Add a mockable peripheral session protocol**

Create `MicroTechCGM/MicroTechCGM/MicroTechPeripheralManager.swift` with:

```swift
import CoreBluetooth
import Foundation

public protocol MicroTechPeripheralSession {
    var deviceIdentifier: UUID { get }
    var deviceName: String { get }
    func subscribe(_ characteristic: CBUUID) throws
    func write(_ value: Data, to characteristic: CBUUID) throws
    func read(_ characteristic: CBUUID) throws -> Data
    func disconnect()
}
```

Then extend this file with the CoreBluetooth implementation modeled on `G7PeripheralManager`: discover service `MicroTechAidexProfile.serviceUUID`, discover `f001UUID`, `f002UUID`, `f003UUID`, subscribe and read/write by characteristic. Keep the public protocol above unchanged so tests remain isolated from CoreBluetooth.

- [ ] **Step 4: Add sensor orchestration**

Create `MicroTechCGM/MicroTechCGM/MicroTechSensor.swift`:

```swift
import CoreBluetooth
import Foundation
import os.log

public protocol MicroTechSensorDelegate: AnyObject {
    func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading)
    func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket)
    func microTechSensor(_ sensor: MicroTechSensor, didError error: Error)
    func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession)
    func microTechSensorDidDisconnect(_ sensor: MicroTechSensor)
}

public struct MicroTechAidexSession: Equatable {
    public let remoteIdentifier: UUID
    public let deviceName: String
    public let sensorSerial: String
}

public final class MicroTechSensor {
    public weak var delegate: MicroTechSensorDelegate?

    private let session: MicroTechPeripheralSession
    private let now: () -> Date
    private var commandBuilder: MicroTechAidexCommandBuilder?
    private var currentSession: MicroTechAidexSession?

    public init(session: MicroTechPeripheralSession, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    public func start() throws {
        let baseMaterial = MicroTechAidexKeyMaterial.derive(deviceName: session.deviceName)
        let aidexSession = MicroTechAidexSession(remoteIdentifier: session.deviceIdentifier, deviceName: session.deviceName, sensorSerial: baseMaterial.sensorSerial)
        currentSession = aidexSession

        try session.subscribe(MicroTechAidexProfile.f002UUID)
        try session.subscribe(MicroTechAidexProfile.f001UUID)
        try session.write(baseMaterial.key, to: MicroTechAidexProfile.f001UUID)
        let pairingKey = baseMaterial.key
        try session.write(pairingKey, to: MicroTechAidexProfile.f001UUID)
        let challenge = try session.read(MicroTechAidexProfile.f002UUID)
        let sessionMaterial = try MicroTechAidexKeyMaterial.deriveSessionMaterial(baseMaterial: baseMaterial, encryptedChallenge: challenge, pairingKey: pairingKey)
        commandBuilder = MicroTechAidexCommandBuilder(keyMaterial: sessionMaterial)
        try session.subscribe(MicroTechAidexProfile.f003UUID)
        try session.write(commandBuilder!.cmd10(), to: MicroTechAidexProfile.f002UUID)
        delegate?.microTechSensorDidConnect(self, session: aidexSession)
    }

    public func handleNotification(characteristic: CBUUID, value: Data, receivedAt: Date) throws {
        guard characteristic == MicroTechAidexProfile.f002UUID || characteristic == MicroTechAidexProfile.f003UUID else {
            return
        }
        guard let builder = commandBuilder, let currentSession else {
            return
        }
        let decrypted = try builder.decryptNotification(value)
        let packet = try MicroTechAidexParser.parse(decrypted)
        switch packet {
        case .current(let current):
            delegate?.microTechSensor(self, didRead: MicroTechGlucoseReading(current: current, sensorSerial: currentSession.sensorSerial, receivedAt: receivedAt))
        case .history(let history):
            delegate?.microTechSensor(self, didReadHistory: history)
        case .startTime:
            return
        }
    }

    public func stop() {
        session.disconnect()
        delegate?.microTechSensorDidDisconnect(self)
    }
}
```

After tests pass, replace the synchronous mock-only `start()` with the real asynchronous flow only if the public tests remain green. The final production flow must keep the same observable call order and notification behavior.

- [ ] **Step 5: Add Bluetooth manager**

Create `MicroTechCGM/MicroTechCGM/MicroTechBluetoothManager.swift` by adapting `G7BluetoothManager.swift`:

- scan using `MicroTechAidexProfile.serviceUUID`
- connect by known `remoteIdentifier` when available
- allow binding by name prefix containing `LinX` or `AiDEX`
- preserve state restoration identifier `com.loopkit.MicroTechCGM`
- delegate discovered sessions back to `MicroTechSensor`

- [ ] **Step 6: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechSensorHandshakeTests
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech LinX 蓝牙握手流程"
```

Expected: handshake tests pass and commit is created.

### Task 7: Connect Sensor Events to CGM Manager

**Files:**
- Modify: `MicroTechCGM/MicroTechCGM/MicroTechCGMManager.swift`
- Modify: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **Step 1: Add manager event tests**

Add tests that call `microTechSensor(_:didRead:)`, `microTechSensorDidConnect(_:session:)`, and `microTechSensor(_:didReadHistory:)`. Assert:

```swift
XCTAssertEqual("ABC123", manager.state.sensorSerial)
XCTAssertEqual("LinX-ABC123", manager.state.deviceName)
XCTAssertEqual(42, manager.state.latestSampleNumber)
```

For history, assert `latestSampleNumber` is unchanged and no `NewGlucoseSample` is emitted.

- [ ] **Step 2: Implement delegate conformance**

Extend `MicroTechCGMManager`:

```swift
extension MicroTechCGMManager: MicroTechSensorDelegate {
    public func microTechSensorDidConnect(_ sensor: MicroTechSensor, session: MicroTechAidexSession) {
        mutateState { state in
            state.remoteIdentifier = session.remoteIdentifier
            state.deviceName = session.deviceName
            state.sensorSerial = session.sensorSerial
        }
    }

    public func microTechSensorDidDisconnect(_ sensor: MicroTechSensor) {
        delegate.notify { delegate in
            delegate?.cgmManager(self, didUpdate: self.cgmManagerStatus)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didRead reading: MicroTechGlucoseReading) {
        guard let sample = accept(reading) else {
            delegateQueue?.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .noData)
            }
            return
        }
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: .newData([sample]))
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didReadHistory history: MicroTechAidexHistoryPacket) {
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: .noData)
        }
    }

    public func microTechSensor(_ sensor: MicroTechSensor, didError error: Error) {
        delegateQueue?.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(error))
        }
    }
}
```

- [ ] **Step 3: Implement deletion**

Add to `MicroTechCGMManager`:

```swift
public func delete(completion: @escaping () -> Void) {
    sensor?.stop()
    mutateState { state in
        state.remoteIdentifier = nil
        state.deviceName = nil
        state.sensorSerial = nil
        state.activationTime = nil
        state.lastReadingDate = nil
        state.latestReading = nil
        state.latestSampleNumber = nil
    }
    notifyDelegateOfDeletion(completion: completion)
}
```

Store the active sensor in `private var sensor: MicroTechSensor?`.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests
git diff --check
git add MicroTechCGM
git commit -m "连接 MicroTech 传感器事件到 Loop 管理器"
```

Expected: manager tests pass and commit is created.

### Task 8: Add UI and Plugin

**Files:**
- Create: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechCGMManager+UI.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsView.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSettingsViewModel.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/LocalizedString.swift`
- Create: `MicroTechCGM/MicroTechCGMUI/Extensions/Bundle.swift`
- Create: `MicroTechCGM/MicroTechCGMPlugin/MicroTechCGMPlugin.swift`
- Create: `MicroTechCGM/MicroTechCGMPlugin/MicroTechCGMPlugin.h`

- [ ] **Step 1: Create plugin class**

Create `MicroTechCGM/MicroTechCGMPlugin/MicroTechCGMPlugin.swift`:

```swift
import LoopKitUI
import MicroTechCGM
import MicroTechCGMUI
import os.log

class MicroTechCGMPlugin: NSObject, CGMManagerUIPlugin {
    public var cgmManagerType: CGMManagerUI.Type? {
        MicroTechCGMManager.self
    }
}
```

- [ ] **Step 2: Add manager UI conformance**

Create `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechCGMManager+UI.swift`:

```swift
import LoopKit
import LoopKitUI
import MicroTechCGM
import UIKit

extension MicroTechCGMManager: CGMManagerUI {
    public static var onboardingImage: UIImage? {
        nil
    }

    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        .userInteractionRequired(MicroTechUICoordinator(colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference))
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> CGMManagerViewController {
        MicroTechUICoordinator(cgmManager: self, colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference)
    }

    public var smallImage: UIImage? {
        nil
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        guard state.lastReadingDate == nil || state.lastReadingDate!.timeIntervalSinceNow < -.minutes(15) else {
            return nil
        }
        return MicroTechDeviceStatusHighlight(localizedMessage: "Signal\nLoss", imageName: "exclamationmark.circle.fill", state: .warning)
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        nil
    }

    public var cgmStatusBadge: DeviceStatusBadge? {
        nil
    }
}

struct MicroTechDeviceStatusHighlight: DeviceStatusHighlight {
    let localizedMessage: String
    let imageName: String
    let state: DeviceStatusHighlightState
}
```

- [ ] **Step 3: Add coordinator and views**

Create `MicroTechUICoordinator` following `G7UICoordinator`: setup creates `MicroTechCGMManager`, calls `didCreateCGMManager`, calls `didOnboardCGMManager`, then completes. Settings view shows device name, sensor serial, last reading time, last glucose, upload toggle, scan button, and delete button. The setup screen must contain one continue button labeled `Continue` and one cancel button labeled `Cancel`.

- [ ] **Step 4: Add UI and plugin files to targets**

Use `xcodeproj` to add:

- UI files to `MicroTechCGMUI`
- plugin files to `MicroTechCGMPlugin`
- link `MicroTechCGM` into `MicroTechCGMUI`
- link `MicroTechCGM` and `MicroTechCGMUI` into `MicroTechCGMPlugin`
- link `LoopKit` and `LoopKitUI` the same way G7 links them

- [ ] **Step 5: Verify plugin metadata**

Run:

```bash
plutil -p MicroTechCGM/MicroTechCGMPlugin/Info.plist
xcodebuild build -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git diff --check
git add MicroTechCGM
git commit -m "新增 MicroTech CGM 界面和插件入口"
```

Expected: plist contains `MicroTech LinX` and `MicroTechLinXCGMManager`; project build reaches pass or a single documented signing-only stop.

### Task 9: Add Workspace and Loop Scheme Integration

**Files:**
- Modify: `LoopWorkspace.xcworkspace/contents.xcworkspacedata`
- Modify: `LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme`

- [ ] **Step 1: Add project to workspace**

Insert this file reference before `</Workspace>`:

```xml
   <FileRef
      location = "group:MicroTechCGM/MicroTechCGM.xcodeproj">
   </FileRef>
```

- [ ] **Step 2: Add plugin build action to LoopWorkspace scheme**

Open `LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme` and mirror the `G7SensorPlugin` build action entry with:

- target name `MicroTechCGMPlugin`
- buildable name `MicroTechCGMPlugin.loopplugin`
- blueprint name `MicroTechCGMPlugin`
- referenced container `container:MicroTechCGM/MicroTechCGM.xcodeproj`

- [ ] **Step 3: Verify Loop can discover plugin metadata after build**

Run:

```bash
xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme LoopWorkspace -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: build completes, or stops only at signing. If it stops before compiling MicroTech targets, fix project references and rerun.

- [ ] **Step 4: Commit workspace integration**

Run:

```bash
git diff --check
git add LoopWorkspace.xcworkspace/contents.xcworkspacedata LoopWorkspace.xcworkspace/xcshareddata/xcschemes/LoopWorkspace.xcscheme MicroTechCGM
git commit -m "接入 MicroTech CGM 到 LoopWorkspace"
```

Expected: commit contains workspace, scheme, and any final target metadata changes.

### Task 10: Full Verification, Device Check, Progress, and Push

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Run full test suite for new module**

Run:

```bash
xcodebuild test -project MicroTechCGM/MicroTechCGM.xcodeproj -scheme Shared -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: all `MicroTechCGMTests` pass.

- [ ] **Step 2: Run Loop workspace build**

Run:

```bash
xcodebuild build -workspace LoopWorkspace.xcworkspace -scheme LoopWorkspace -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: build passes. If signing is still reached despite `CODE_SIGNING_ALLOWED=NO`, record the exact signing stop and verify all MicroTech targets compiled first.

- [ ] **Step 3: Run metadata checks**

Run:

```bash
plutil -p MicroTechCGM/MicroTechCGMPlugin/Info.plist
rg -n "MicroTech LinX|MicroTechLinXCGMManager|MicroTechCGMPlugin" MicroTechCGM LoopWorkspace.xcworkspace
git diff --check
```

Expected: metadata appears in plugin plist, project, workspace, scheme; diff check passes.

- [ ] **Step 4: Manual iPhone verification**

Install on the iPhone using the repository's existing signing flow. Verify:

- CGM add list contains `MicroTech LinX`.
- Setup creates a MicroTech manager.
- Scan finds the LinX device by name or known remote identifier.
- Connection log shows `F001`, `F002`, and `F003` steps in order.
- First valid `F003` `0x01` reading appears in Loop.
- Deleting CGM removes manager state and allows another setup.

- [ ] **Step 5: Update progress log**

Append a new top entry in `PROGRESS.md`:

```markdown
### 2026-06-12 003 - 实现微泰 LinX CGM 接入

- **任务**：新增 MicroTech LinX CGM 插件、BLE 握手、Aidex 解析、Loop 样本转换和基础 UI。
- **核心交付**：
  1. `MicroTechCGM/`：微泰 LinX CGM framework、UI framework、plugin 和测试。
  2. `LoopWorkspace.xcworkspace/`：加入 MicroTech CGM 工程和构建入口。
- **验证结果**：记录本轮实际通过的 `xcodebuild`、plist、搜索、真机验证结果。
- **commit hash**：提交后记录。
- **push 状态**：推送后记录。
```

- [ ] **Step 6: Commit and push**

Run:

```bash
git status --short --branch
git add PROGRESS.md
git commit -m "同步 微泰 LinX CGM 接入进展"
git push origin main
git status --short --branch
git log --oneline -5
```

Expected: remote `origin/main` includes all MicroTech commits; only `LoopWorkspace.xcworkspace/xcuserdata/liyang.xcuserdatad/UserInterfaceState.xcuserstate` may remain uncommitted.

## Self-Review Checklist

- Spec coverage: plugin picker, BLE handshake, Aidex crypto, real-time parser, history boundary, manager state, UI, deletion, tests, build, and manual device verification are each covered by a task.
- Type consistency: `MicroTechAidexKeyMaterial`, `MicroTechAidexCommandBuilder`, `MicroTechAidexParser`, `MicroTechGlucoseReading`, `MicroTechSensor`, and `MicroTechCGMManager` names match across tests and implementation steps.
- Risk points: Xcode project linking and CommonCrypto Swift import are isolated in early build steps; BLE behavior is protected by mock handshake tests before real CoreBluetooth integration.
