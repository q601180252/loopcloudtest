# LinX Fixed Direct Setup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the LinX connection-mode choice from onboarding and make every new LinX setup start the existing direct connection flow.

**Architecture:** Keep the broadcast parser, state compatibility and diagnostics unchanged. Narrow only the onboarding API and UI: the setup view emits a parameterless continue action, and the coordinator explicitly configures `.direct` before scanning. Update the existing UI test to prove the mode controls are absent and the search action remains available.

**Tech Stack:** Swift, SwiftUI, UIKit coordinator, XCTest, XCUITest, Xcode, GitHub Actions, fastlane.

---

## Chunk 1: Behavior And Tests

### Task 1: Make The Existing UI Test Describe The New Page

**Files:**
- Modify: `Loop/LoopUITests/LoopCGMSetupUITests.swift`
- Modify: `MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift`

- [ ] **Step 1: Add a failing setup-view API test**

Add this test beside the existing setup tests:

```swift
func testSetupViewContinueActionDoesNotExposeConnectionMode() {
    var didContinue = false
    let view = MicroTechSetupView(
        didContinue: {
            didContinue = true
        },
        didCancel: nil
    )

    view.didContinue?()

    XCTAssertTrue(didContinue)
}
```

Add a second test proving the coordinator exposes only a parameterless direct-setup action:

```swift
func testSetupCoordinatorExposesParameterlessDirectAction() {
    var state = MicroTechCGMManagerState()
    state.connectionMode = .broadcast
    let bluetoothManager = FakeMicroTechBluetoothManager()
    let manager = MicroTechCGMManager(
        state: state,
        bluetoothManagerFactory: { bluetoothManager }
    )
    let coordinator = MicroTechUICoordinator(
        colorPalette: EnvironmentValues().colorPalette,
        displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: Self.mgdlUnit),
        allowDebugFeatures: false,
        makeCGMManager: { manager }
    )
    let completeSetup: () -> Void = coordinator.completeSetup

    completeSetup()

    XCTAssertEqual(manager.state.connectionMode, .direct)
    XCTAssertEqual(bluetoothManager.scanRemoteIdentifiers, [nil])
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
xcodebuild test -quiet \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSetupViewContinueActionDoesNotExposeConnectionMode \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSetupCoordinatorExposesParameterlessDirectAction
```

Expected: build FAIL because the current view callback and coordinator method both expose a connection-mode parameter and cannot be used as parameterless actions.

- [ ] **Step 3: Replace the old mode-picker assertions**

In `testMicroTechLinXSetupOpensFromSettings`, assert:

```swift
XCTAssertFalse(app.segmentedControls["microtech.setup.connectionMode"].exists)
XCTAssertFalse(app.buttons["直接连接"].exists)
XCTAssertFalse(app.buttons["广播数据"].exists)
```

Keep the existing setup-title and search-button assertions.

- [ ] **Step 4: Remove the configured-CGM early success**

Do not open an existing MicroTech CGM and return success. If `settings.cgm.current` exists, fail with a clear message and leave the configuration untouched. A run that does not enter the add-CGM page is not an acceptance result.

- [ ] **Step 5: Run the true-device UI test and verify RED**

```bash
XCODE_DEVICE_ID="<Xcode destination ID>"
xcodebuild test -quiet \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopUITests \
  -configuration Debug \
  -destination "id=$XCODE_DEVICE_ID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -disableAutomaticPackageResolution \
  -only-testing:LoopUITests/LoopCGMSetupUITests/testMicroTechLinXSetupOpensFromSettings
```

Expected: FAIL because the current setup page still contains the connection-mode picker and mode buttons.

If the phone already has a CGM configured, STOP. Do not change or delete it, do not treat the run as passed, and do not publish until the true-device add-page test can run.

### Task 2: Fix Onboarding To Use Direct Connection Only

**Files:**
- Modify: `MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift`
- Modify: `MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift`

- [ ] **Step 1: Remove the setup picker**

In `MicroTechSetupView`:

- Change `didContinue` to `(() -> Void)?`.
- Remove `connectionMode` state.
- Remove the `Picker`.
- Make the search button call `didContinue?()`.
- Remove the now-unused `MicroTechCGM` import.

- [ ] **Step 2: Narrow the coordinator API**

In `MicroTechUICoordinator`:

- Change the setup callback to call `completeSetup()` with no mode.
- Change `completeSetup(connectionMode:)` to parameterless `completeSetup()`.
- Call `manager.configureConnectionMode(.direct)` before installing logging and scanning.

- [ ] **Step 3: Run the focused setup tests**

```bash
xcodebuild test -quiet \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSetupViewContinueActionDoesNotExposeConnectionMode \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSetupCoordinatorExposesParameterlessDirectAction \
  -only-testing:MicroTechCGMTests/MicroTechCGMManagerTests/testSetupInstallsOnboardingLogHandlerBeforeScanning
```

Expected: all three tests PASS.

- [ ] **Step 4: Run the true-device UI test and verify GREEN**

Run the command from Task 1 Step 5.

Expected: PASS. The test must actually enter the add-CGM page, prove the mode controls are absent and prove the search button is present.

## Chunk 2: Regression, Documentation And Release

### Task 3: Update Current Documentation Without Rewriting History

**Files:**
- Modify: `README.md`
- Modify: `PROGRESS.md`
- Modify: `docs/工具与踩坑.md`
- Modify: `docs/superpowers/specs/2026-07-31-linx-broadcast-mode-design.md`
- Modify: `docs/superpowers/plans/2026-07-31-linx-broadcast-mode.md`

- [ ] **Step 1: Update current descriptions**

- State that new LinX setup uses direct connection only.
- Mark the broadcast design and plan as historical.
- Preserve past progress entries unchanged.
- Add a new top `PROGRESS.md` entry that records the implementation scope. Leave verification, TestFlight and final commit fields explicitly pending until those steps finish.

- [ ] **Step 2: Validate documents**

```bash
test -f docs/superpowers/specs/2026-07-31-linx-direct-only-setup-design.md
git diff --check
```

Expected: both commands exit successfully.

### Task 4: Run Full Regression And Build The Complete App

**Files:**
- No additional source files.

- [ ] **Step 1: Run all MicroTech tests**

```bash
xcodebuild test -quiet \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution
```

Expected: all MicroTech tests PASS with zero failures.

- [ ] **Step 2: Build the complete signed app**

Use `LoopWorkspace` and the reusable command in `docs/工具与踩坑.md`.

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Check the complete plugin package**

Confirm these directories exist in `Loop.app/Frameworks`:

- `MicroTechCGMPlugin.framework`
- `NightscoutRemoteCGMPlugin.framework`
- `NightscoutRemoteCGM.framework`

Run `codesign --verify --deep --strict` on `Loop.app`.

Expected: all plugin checks and signature verification PASS.

- [ ] **Step 4: Install, launch and run the UI test**

Install the complete app on the connected iPhone, launch it, confirm the process remains running, then run the true-device UI test from Task 1.

Expected: app launches without a new crash and the UI test passes after actually entering the add-CGM page. A configured CGM or an early return is a blocking result; do not publish.

### Task 5: Commit, Push And Publish To TestFlight

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Commit and push implementation**

Stage only the intended source, test and documentation files. Do not stage `xcuserdata`, `build/` or `log/`.

Update the newest `PROGRESS.md` entry with the actual focused tests, full MicroTech count, complete build, plugin, signature, install, launch and true-device UI results. Keep TestFlight fields pending.

```bash
git diff --check
git add -- \
  MicroTechCGM/MicroTechCGMUI/Views/MicroTechSetupView.swift \
  MicroTechCGM/MicroTechCGMUI/MicroTechCGMManager/MicroTechUICoordinator.swift \
  MicroTechCGM/MicroTechCGMTests/MicroTechCGMManagerTests.swift \
  Loop/LoopUITests/LoopCGMSetupUITests.swift \
  README.md \
  PROGRESS.md \
  docs/工具与踩坑.md \
  docs/superpowers/specs/2026-07-31-linx-broadcast-mode-design.md \
  docs/superpowers/plans/2026-07-31-linx-broadcast-mode.md
git commit -m '修改 LinX 添加流程固定使用直连' \
  -m '改动原因：LinX 添加页面不再需要区分直连和广播。' \
  -m '改动清单：删除模式选择；新添加显式使用直连；更新单元测试、真机测试和当前说明。' \
  -m '验证结果：MicroTech 全量测试、完整插件构建、签名、安装、启动和真机添加流程通过。' \
  -m '影响范围：MicroTech LinX 新添加流程；底层广播兼容保留。'

push_succeeded=false
for attempt in 1 2 3; do
  if git -c http.proxy=http://127.0.0.1:1082 \
    -c https.proxy=http://127.0.0.1:1082 \
    push origin main; then
    push_succeeded=true
    break
  fi
  if test "$attempt" -lt 3; then
    sleep 2
  fi
done
test "$push_succeeded" = true
```

Expected: commit succeeds and `origin/main` contains the implementation commit. Do not use `--force`.

- [ ] **Step 2: Trigger TestFlight**

```bash
RUN_URL="$(gh workflow run 4_build_loop.yml --ref main)"
RUN_ID="${RUN_URL##*/}"
printf 'run_id=%s\nrun_url=%s\n' "$RUN_ID" "$RUN_URL"
```

- [ ] **Step 3: Wait for App Store Connect processing**

```bash
gh run watch "$RUN_ID" --interval 20 --exit-status
test "$(gh run view "$RUN_ID" --json conclusion --jq '.conclusion')" = "success"
RUN_LOG="/tmp/loopcloudtest-testflight-$RUN_ID.log"
gh run view "$RUN_ID" --log > "$RUN_LOG"
rg -q 'Successfully finished processing the build' "$RUN_LOG"
rg 'Successfully finished processing the build' "$RUN_LOG"
```

Expected: workflow conclusion is `success` and the log separately proves successful App Store Connect processing. A successful transport upload without the processing-complete line fails this step.

- [ ] **Step 4: Verify the uploaded artifact**

```bash
ARTIFACT_DIR="/tmp/loopcloudtest-testflight-$RUN_ID"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
gh run download "$RUN_ID" --name build-artifacts --dir "$ARTIFACT_DIR"

IPA="$(find "$ARTIFACT_DIR" -type f -name 'Loop.ipa' -print -quit)"
test -n "$IPA"
APP_DIR="$ARTIFACT_DIR/unpacked"
mkdir -p "$APP_DIR"
ditto -x -k "$IPA" "$APP_DIR"
APP="$(find "$APP_DIR/Payload" -maxdepth 1 -type d -name 'Loop.app' -print -quit)"

test -d "$APP/Frameworks/MicroTechCGMPlugin.framework"
test -d "$APP/Frameworks/NightscoutRemoteCGMPlugin.framework"
test -d "$APP/Frameworks/NightscoutRemoteCGM.framework"
bash Scripts/verify_watchos_testflight_compatibility.sh "$IPA" 11.6
shasum -a 256 "$IPA"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist"
```

Expected: all plugin directories exist, Watch verification passes, and version, build number and SHA256 are captured.

- [ ] **Step 5: Record and push the final result**

Update the newest `PROGRESS.md` entry with:

- Source commit.
- Test counts and true-device result.
- TestFlight run ID and URL.
- App version and build number.
- App Store Connect processing result.
- IPA SHA256 and plugin checks.
- Final push status.

Then validate, commit and push:

```bash
git diff --check
git add PROGRESS.md
git commit -m '文档 记录 LinX 直连版本发布结果' \
  -m '改动原因：记录已确认的测试、真机和 TestFlight 处理结果。' \
  -m '改动清单：回填发布 run、版本、构建号、IPA 校验值和插件检查。' \
  -m '验证结果：TestFlight workflow、App Store Connect 处理和包内容检查通过。' \
  -m '影响范围：仅 PROGRESS.md。'
push_succeeded=false
for attempt in 1 2 3; do
  if git -c http.proxy=http://127.0.0.1:1082 \
    -c https.proxy=http://127.0.0.1:1082 \
    push origin main; then
    push_succeeded=true
    break
  fi
  if test "$attempt" -lt 3; then
    sleep 2
  fi
done
test "$push_succeeded" = true
```
