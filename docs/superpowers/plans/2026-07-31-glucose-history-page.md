# Loop 血糖历史页面 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Loop 首页增加血糖历史入口，并提供最近 6、12、24 小时的实际血糖图表和倒序明细。

**Architecture:** 页面属于 Loop 主 App，直接查询 `DeviceDataManager.glucoseStore`，不修改 MicroTech 的连接、补包和数据所有权。历史页使用 SwiftUI 和现有 `PredictedGlucoseChartView`，由独立 ViewModel 管理时间范围、查询次序和通知生命周期；首页继续由 `StatusTableViewController` 负责入口和导航。

**Tech Stack:** Swift、UIKit、SwiftUI、Combine、HealthKit、LoopKit、LoopKitUI、SwiftCharts、XCTest、XCUITest、Xcode

---

## 执行状态

本计划的代码、单元测试、构建、完整插件检查、真机安装、文档、合并和推送已完成。当前手机未配置 CGM，因此“使用真实 LinX 数据验收”及配置 CGM 后的真机页面操作仍为待完成；不得写成已通过。

下方复选框保留原始执行计划，不再作为当前状态来源。实际结果以 [PROGRESS.md 第 039 条](../../../PROGRESS.md) 为准，最终页面说明见 [血糖历史页面设计](../specs/2026-07-31-glucose-history-page-design.md)。

## Chunk 1: 可执行计划

## 完成标准

- 首页状态区下方、现有图表上方显示 `Glucose History` 入口；未配置 CGM 时隐藏。
- 历史页默认 6 小时，可切换 12、24 小时。
- 图表和列表使用同一次 `GlucoseStore` 查询结果，不二次去重。
- 列表最新数据在上方，显示时间、当前单位的血糖值、趋势和手动输入标识。
- 6、12、24 小时分别使用 1、2、4 小时横轴标签间隔。
- 新数据、App 回到前台时自动刷新；退出页面后停止监听，迟到查询不能覆盖新结果。
- 新增单元测试和 UI 测试通过；现有 MicroTech 测试和 `LoopWorkspace` 构建通过。
- 签名构建安装到当前 iPhone XR，启动不崩溃，真实 LinX 历史数据可在三个范围中查看。

## 文件结构

### 新增

- `Loop/Loop/View Models/GlucoseHistoryViewModel.swift`
  - 时间范围、查询、排序、加载状态、通知生命周期和图表配置。
- `Loop/Loop/Views/GlucoseHistoryView.swift`
  - 三段时间选择、实际血糖散点图、错误/空状态和倒序明细。
- `Loop/LoopTests/ViewModels/GlucoseHistoryViewModelTests.swift`
  - ViewModel 的时间、排序、竞态、通知和错误测试。
- `Loop/LoopTests/Views/GlucoseHistoryViewTests.swift`
  - 血糖值单位、趋势和手动输入行内容测试。
- `Loop/LoopTests/ViewControllers/StatusTableViewControllerTests.swift`
  - 配置和未配置 CGM 时的首页入口显示规则。
- `Loop/LoopUITests/LoopGlucoseHistoryUITests.swift`
  - 首页入口、导航、三个时间选项和切换行为。
- `LoopKit/LoopKitTests/Charts/ChartsManagerTests.swift`
  - 横轴标签间隔的默认值和 1/2/4 小时间隔测试。

### 修改

- `LoopKit/LoopKitUI/View Controllers/ChartsManager.swift`
  - 增加可配置的横轴标签间隔，默认行为保持一小时。
- `LoopKit/LoopKit.xcodeproj/project.pbxproj`
  - 将 `ChartsManagerTests.swift` 加入 `LoopKitTests`。
- `Loop/Loop/View Controllers/StatusTableViewController.swift`
  - 增加首页入口行、显示条件和页面导航。
- `Loop/Loop.xcodeproj/project.pbxproj`
  - 将新增 App、单元测试和 UI 测试文件加入正确 target。
- `PROGRESS.md`
  - 记录实现、测试、真机安装和推送结果。
- `docs/工具与踩坑.md`
  - 仅在出现新的非平凡构建或真机问题时补充。

### 不修改

- `MicroTechCGM/`
  - 当前值和历史补包流程已经把数据交给 Loop，本任务不改变蓝牙连接。
- `LoopWorkspace.xcworkspace/xcuserdata/`
  - 个人 Xcode 状态不得提交。
- `build/`、`log/`
  - 只作为本地验证产物，不提交。

### Task 1: 支持长时间横轴标签间隔

**Files:**
- Create: `LoopKit/LoopKitTests/Charts/ChartsManagerTests.swift`
- Modify: `LoopKit/LoopKitUI/View Controllers/ChartsManager.swift`
- Modify: `LoopKit/LoopKit.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写横轴间隔失败测试**

新增测试，固定 24 小时时间范围，验证默认一小时和自定义四小时间隔。为避免测试依赖界面截图，将 `ChartsManager.xAxisValues` 改为模块内只读、私有写入，测试只读取生成后的轴值。

```swift
import XCTest
import SwiftCharts
@testable import LoopKitUI

final class ChartsManagerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testDefaultXAxisLabelIntervalIsOneHour() {
        let manager = makeManager()
        XCTAssertEqual(manager.xAxisLabelInterval, .hours(1))
    }

    func testFourHourIntervalGeneratesSevenAxisValuesForTwentyFourHours() {
        let manager = makeManager(xAxisLabelInterval: .hours(4))
        manager.startDate = start
        manager.maxEndDate = start.addingTimeInterval(.hours(24))
        manager.updateEndDate(start.addingTimeInterval(.hours(24)))

        manager.prerender()

        XCTAssertEqual(manager.xAxisValues?.count, 7)
        let dates = manager.xAxisValues?.compactMap {
            ($0 as? ChartAxisValueDate)?.date
        }
        XCTAssertEqual(dates?.first, start)
        XCTAssertEqual(dates?.last, start.addingTimeInterval(.hours(24)))
    }

    func testChangingIntervalInvalidatesAndRegeneratesAxisValues() {
        let manager = makeManager()
        manager.startDate = start
        manager.maxEndDate = start.addingTimeInterval(.hours(12))
        manager.updateEndDate(start.addingTimeInterval(.hours(12)))
        manager.prerender()
        let oneHourCount = manager.xAxisValues?.count

        manager.xAxisLabelInterval = .hours(2)
        XCTAssertNil(manager.xAxisValues)
        manager.prerender()

        XCTAssertEqual(oneHourCount, 13)
        XCTAssertEqual(manager.xAxisValues?.count, 7)
    }

    private func makeManager(
        xAxisLabelInterval: TimeInterval = .hours(1)
    ) -> ChartsManager {
        ChartsManager(
            colors: ChartColorPalette(
                axisLine: .black,
                axisLabel: .black,
                grid: .lightGray,
                glucoseTint: .blue,
                insulinTint: .orange,
                carbTint: .green
            ),
            settings: .default,
            charts: [],
            traitCollection: .current,
            xAxisLabelInterval: xAxisLabelInterval
        )
    }
}
```

- [ ] **Step 2: 将测试文件加入 `LoopKitTests`**

在 `LoopKit/LoopKit.xcodeproj/project.pbxproj` 中增加：

- 一个 `PBXFileReference`。
- 一个 `PBXBuildFile`。
- `LoopKitTests/Charts` group 下的文件引用。
- `LoopKitTests` target 的 Sources build phase 条目。

只增加 `ChartsManagerTests.swift`，不要改已有 target 或 scheme。

- [ ] **Step 3: 运行测试确认失败**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme 'Shared (LoopKit project)' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopKitTests/ChartsManagerTests
```

Expected: FAIL，原因是 `ChartsManager` 尚无 `xAxisLabelInterval` 参数和可读的 `xAxisValues`。

- [ ] **Step 4: 实现可配置横轴间隔**

在 `ChartsManager` 增加：

```swift
public var xAxisLabelInterval: TimeInterval {
    didSet {
        precondition(xAxisLabelInterval > 0)
        if xAxisLabelInterval != oldValue {
            xAxisValues = nil
        }
    }
}
```

初始化参数放在末尾并提供默认值，保证全部现有调用不需要修改。在现有 initializer 内新增 `precondition`，并在 `self.colors = colors` 之前赋值；其它现有赋值顺序不变：

```swift
public init(
    colors: ChartColorPalette,
    settings: ChartSettings,
    axisLabelFont: UIFont = .systemFont(ofSize: 14),
    charts: [ChartProviding],
    traitCollection: UITraitCollection,
    xAxisLabelInterval: TimeInterval = .hours(1)
) {
    precondition(xAxisLabelInterval > 0)
    self.xAxisLabelInterval = xAxisLabelInterval
    self.colors = colors
    self.chartSettings = settings
    self.charts = charts
    self.traitCollection = traitCollection
    self.chartsCache = Array(repeating: nil, count: charts.count)
    axisLabelSettings = ChartLabelSettings(
        font: axisLabelFont,
        fontColor: colors.axisLabel
    )
    guideLinesLayerSettings = ChartGuideLinesLayerSettings(
        linesColor: colors.grid
    )
}
```

将 `xAxisValues` 从完全私有改为模块内只读，完整属性为：

```swift
internal private(set) var xAxisValues: [ChartAxisValue]? {
    didSet {
        if let xAxisValues = xAxisValues, xAxisValues.count > 1 {
            xAxisModel = ChartAxisModel(
                axisValues: xAxisValues,
                lineColor: colors.axisLine,
                labelSpaceReservationMode: .fixed(20)
            )
        } else {
            xAxisModel = nil
        }

        chartsCache.replaceAllElements(with: nil)
    }
}
```

修改横轴生成：

```swift
let segments = ceil(
    endDate.timeIntervalSince(startDate) / xAxisLabelInterval
)

let xAxisValues = ChartAxisValuesStaticGenerator.generateXAxisValuesWithChartPoints(
    points,
    minSegmentCount: segments - 1,
    maxSegmentCount: segments + 1,
    multiple: xAxisLabelInterval,
    axisValueGenerator: {
        ChartAxisValueDate(
            date: ChartAxisValueDate.dateFromScalar($0),
            formatter: timeFormatter,
            labelSettings: self.axisLabelSettings
        )
    },
    addPaddingSegmentIfEdge: false
)
```

- [ ] **Step 5: 运行新测试和现有图表测试**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme 'Shared (LoopKit project)' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopKitTests/ChartsManagerTests \
  -only-testing:LoopKitTests/PredictedGlucoseChartTests
```

Expected: PASS，现有图表仍使用默认一小时间隔。

- [ ] **Step 6: 提交横轴改动**

```bash
git add \
  'LoopKit/LoopKitUI/View Controllers/ChartsManager.swift' \
  LoopKit/LoopKitTests/Charts/ChartsManagerTests.swift \
  LoopKit/LoopKit.xcodeproj/project.pbxproj
git commit -m "修改 血糖历史图表横轴间隔" \
  -m "改动原因：24 小时图表使用每小时标签会重叠。

改动清单：为 ChartsManager 增加默认兼容的横轴间隔；新增默认值、变更刷新和四小时间隔测试。

验证结果：ChartsManagerTests 和 PredictedGlucoseChartTests 通过。

影响范围：LoopKitUI 图表横轴；现有页面保持一小时默认值。"
```

### Task 2: 实现历史数据 ViewModel

**Files:**
- Create: `Loop/Loop/View Models/GlucoseHistoryViewModel.swift`
- Create: `Loop/LoopTests/ViewModels/GlucoseHistoryViewModelTests.swift`
- Modify: `Loop/Loop.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写范围、排序和查询竞态失败测试**

测试使用固定时间和可控 loader，不创建第二份数据库。

```swift
import HealthKit
import LoopKit
import UIKit
import XCTest
@testable import Loop

@MainActor
final class GlucoseHistoryViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private var requests: [
        (
            start: Date,
            end: Date,
            completion: (Result<[StoredGlucoseSample], Error>) -> Void
        )
    ] = []
    private var notificationCenter: NotificationCenter!
    private var notificationObject: NSObject!
    private var viewModel: GlucoseHistoryViewModel!
    private var loaderCallExpectation: XCTestExpectation?

    override func setUp() {
        super.setUp()
        requests = []
        notificationCenter = NotificationCenter()
        notificationObject = NSObject()
        viewModel = GlucoseHistoryViewModel(
            loader: { [weak self] start, end, completion in
                self?.requests.append((start, end, completion))
                self?.loaderCallExpectation?.fulfill()
            },
            notificationCenter: notificationCenter,
            glucoseStoreNotificationObject: notificationObject,
            now: { self.now }
        )
    }

    override func tearDown() {
        viewModel.stopObserving()
        viewModel = nil
        loaderCallExpectation = nil
        notificationObject = nil
        notificationCenter = nil
        super.tearDown()
    }

    func testStartDefaultsToSixHours() {
        viewModel.startObserving()

        XCTAssertEqual(viewModel.selectedRange, .sixHours)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].start, now.addingTimeInterval(-.hours(6)))
        XCTAssertEqual(requests[0].end, now)
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(1))
    }

    func testSelectingTwelveAndTwentyFourHoursUsesExpectedRanges() {
        viewModel.startObserving()
        viewModel.selectRange(.twelveHours)
        XCTAssertEqual(requests[1].start, now.addingTimeInterval(-.hours(12)))
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(2))

        viewModel.selectRange(.twentyFourHours)

        XCTAssertEqual(requests[2].start, now.addingTimeInterval(-.hours(24)))
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(4))
    }

    func testStoreOrderIsPreservedAndListOrderIsReversedWithoutDeduplication() async {
        let samples = [
            sample(minutesAgo: 10, value: 100),
            sample(minutesAgo: 5, value: 110),
            sample(minutesAgo: 5, value: 111)
        ]
        viewModel.startObserving()

        requests[0].completion(.success(samples))
        await drainMainQueue()

        XCTAssertEqual(viewModel.chartSamples, samples)
        XCTAssertEqual(viewModel.listSamples, Array(samples.reversed()))
        XCTAssertEqual(viewModel.chartSamples.count, 3)
        XCTAssertEqual(viewModel.glucoseValues.count, 3)
        XCTAssertEqual(viewModel.listSamples.count, 3)
    }

    func testLateOldRequestCannotReplaceNewestRange() async {
        let oldSamples = [sample(minutesAgo: 20, value: 90)]
        let newSamples = [sample(minutesAgo: 2, value: 120)]
        viewModel.startObserving()
        viewModel.selectRange(.twentyFourHours)

        requests[1].completion(.success(newSamples))
        await drainMainQueue()
        requests[0].completion(.success(oldSamples))
        await drainMainQueue()

        XCTAssertEqual(viewModel.chartSamples, newSamples)
        XCTAssertEqual(viewModel.selectedRange, .twentyFourHours)
    }

    func testRangeCompletionUpdatesChartAndListFromSameSamples() async {
        let samples = [
            sample(minutesAgo: 15, value: 95),
            sample(minutesAgo: 3, value: 125)
        ]
        viewModel.startObserving()
        viewModel.selectRange(.twelveHours)

        requests[1].completion(.success(samples))
        await drainMainQueue()

        XCTAssertEqual(viewModel.chartSamples, samples)
        XCTAssertEqual(viewModel.listSamples, Array(samples.reversed()))
    }

    private func sample(minutesAgo: Double, value: Double) -> StoredGlucoseSample {
        StoredGlucoseSample(
            startDate: now.addingTimeInterval(-.minutes(minutesAgo)),
            quantity: HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: value
            )
        )
    }

    private func drainMainQueue() async {
        await Task.yield()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }
}
```

- [ ] **Step 2: 写通知生命周期和状态失败测试**

在同一测试类补充：

```swift
func testGlucoseChangeAndForegroundRefreshCurrentRange() async {
    viewModel.startObserving()
    viewModel.selectRange(.twelveHours)
    let countBeforeNotifications = requests.count
    loaderCallExpectation = expectation(description: "Two refresh requests")
    loaderCallExpectation?.expectedFulfillmentCount = 2

    notificationCenter.post(
        name: GlucoseStore.glucoseSamplesDidChange,
        object: notificationObject
    )
    notificationCenter.post(
        name: UIApplication.willEnterForegroundNotification,
        object: nil
    )
    await fulfillment(of: [loaderCallExpectation!], timeout: 1)

    XCTAssertEqual(requests.count, countBeforeNotifications + 2)
    XCTAssertEqual(requests.last?.start, now.addingTimeInterval(-.hours(12)))
}

func testConsecutiveGlucoseNotificationsIgnoreLateOlderResult() async {
    let older = [sample(minutesAgo: 8, value: 100)]
    let newest = [sample(minutesAgo: 1, value: 130)]
    viewModel.startObserving()
    loaderCallExpectation = expectation(description: "Two glucose refresh requests")
    loaderCallExpectation?.expectedFulfillmentCount = 2

    notificationCenter.post(
        name: GlucoseStore.glucoseSamplesDidChange,
        object: notificationObject
    )
    notificationCenter.post(
        name: GlucoseStore.glucoseSamplesDidChange,
        object: notificationObject
    )
    await fulfillment(of: [loaderCallExpectation!], timeout: 1)
    XCTAssertEqual(requests.count, 3)

    requests[2].completion(.success(newest))
    await drainMainQueue()
    requests[1].completion(.success(older))
    await drainMainQueue()

    XCTAssertEqual(viewModel.chartSamples, newest)
}

func testStopObservingIgnoresNotificationsAndLateCompletion() async {
    viewModel.startObserving()
    let completion = requests[0].completion
    viewModel.stopObserving()

    notificationCenter.post(
        name: GlucoseStore.glucoseSamplesDidChange,
        object: notificationObject
    )
    completion(.success([sample(minutesAgo: 1, value: 130)]))
    await drainMainQueue()

    XCTAssertEqual(requests.count, 1)
    XCTAssertTrue(viewModel.chartSamples.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
}

func testEmptyAndFailureStates() async {
    viewModel.startObserving()
    requests[0].completion(.success([]))
    await drainMainQueue()
    XCTAssertTrue(viewModel.isEmpty)

    viewModel.refresh()
    requests[1].completion(.failure(TestError.expected))
    await drainMainQueue()
    XCTAssertNotNil(viewModel.errorDescription)
    XCTAssertFalse(viewModel.isLoading)
}

private enum TestError: Error {
    case expected
}
```

- [ ] **Step 3: 将新文件加入 App 和 `LoopTests` target**

在 `Loop/Loop.xcodeproj/project.pbxproj` 中：

- 将 `GlucoseHistoryViewModel.swift` 加入 `Loop/View Models` group 和 App Sources。
- 将 `GlucoseHistoryViewModelTests.swift` 加入 `LoopTests/ViewModels` group 和 `LoopTests` Sources。
- 不加入 Watch、Widget 或 Extension target。

- [ ] **Step 4: 运行测试确认失败**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iOS Simulator ID>' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopTests/GlucoseHistoryViewModelTests \
  MAIN_APP_BUNDLE_IDENTIFIER=com.libre.loopkit3.Loop
```

Expected: FAIL，原因是 `GlucoseHistoryViewModel` 和 `GlucoseHistoryRange` 尚不存在。

- [ ] **Step 5: 实现范围和 ViewModel**

核心类型：

```swift
import Combine
import HealthKit
import LoopKit
import LoopKitUI
import UIKit

enum GlucoseHistoryRange: CaseIterable, Equatable, Identifiable {
    case sixHours
    case twelveHours
    case twentyFourHours

    var id: Self { self }

    var title: String {
        switch self {
        case .sixHours:
            return NSLocalizedString("6 Hours", comment: "Six hour glucose history range")
        case .twelveHours:
            return NSLocalizedString("12 Hours", comment: "Twelve hour glucose history range")
        case .twentyFourHours:
            return NSLocalizedString("24 Hours", comment: "Twenty-four hour glucose history range")
        }
    }

    var duration: TimeInterval {
        switch self {
        case .sixHours: return .hours(6)
        case .twelveHours: return .hours(12)
        case .twentyFourHours: return .hours(24)
        }
    }

    var xAxisLabelInterval: TimeInterval {
        switch self {
        case .sixHours: return .hours(1)
        case .twelveHours: return .hours(2)
        case .twentyFourHours: return .hours(4)
        }
    }
}

@MainActor
final class GlucoseHistoryViewModel: ObservableObject {
    typealias Loader = (
        Date,
        Date,
        @escaping (Result<[StoredGlucoseSample], Error>) -> Void
    ) -> Void

    @Published private(set) var selectedRange: GlucoseHistoryRange = .sixHours
    @Published private(set) var chartSamples: [StoredGlucoseSample] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?

    var listSamples: [StoredGlucoseSample] {
        Array(chartSamples.reversed())
    }

    var glucoseValues: [GlucoseValue] {
        chartSamples.map { $0 as GlucoseValue }
    }

    var isEmpty: Bool {
        !isLoading && errorDescription == nil && chartSamples.isEmpty
    }

    var chartDateInterval: DateInterval {
        let end = lastQueryEnd ?? now()
        return DateInterval(
            start: end.addingTimeInterval(-selectedRange.duration),
            end: end
        )
    }

    let chartManager: ChartsManager

    private let loader: Loader
    private let notificationCenter: NotificationCenter
    private let glucoseStoreNotificationObject: Any?
    private let now: () -> Date
    private var observerTokens: [NSObjectProtocol] = []
    private var requestGeneration: UInt = 0
    private var isObserving = false
    private var lastQueryEnd: Date?

    init(
        loader: @escaping Loader,
        notificationCenter: NotificationCenter = .default,
        glucoseStoreNotificationObject: Any? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.loader = loader
        self.notificationCenter = notificationCenter
        self.glucoseStoreNotificationObject = glucoseStoreNotificationObject
        self.now = now

        let chart = PredictedGlucoseChart(
            predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil
        )
        chart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        chartManager = ChartsManager(
            colors: .primary,
            settings: .default,
            charts: [chart],
            traitCollection: .current,
            xAxisLabelInterval: GlucoseHistoryRange.sixHours.xAxisLabelInterval
        )
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        observerTokens = [
            notificationCenter.addObserver(
                forName: GlucoseStore.glucoseSamplesDidChange,
                object: glucoseStoreNotificationObject,
                queue: .main
            ) { [weak self] _ in
                self?.refreshOnMain()
            },
            notificationCenter.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshOnMain()
            }
        ]
        refresh()
    }

    func stopObserving() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
        isObserving = false
        requestGeneration &+= 1
        isLoading = false
    }

    func selectRange(_ range: GlucoseHistoryRange) {
        guard range != selectedRange else { return }
        selectedRange = range
        chartManager.xAxisLabelInterval = range.xAxisLabelInterval
        if isObserving {
            refresh()
        }
    }

    func refresh() {
        guard isObserving else { return }
        requestGeneration &+= 1
        let generation = requestGeneration
        let end = now()
        let start = end.addingTimeInterval(-selectedRange.duration)
        lastQueryEnd = end
        isLoading = true
        errorDescription = nil

        loader(start, end) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.isObserving,
                      generation == self.requestGeneration
                else {
                    return
                }
                self.isLoading = false
                switch result {
                case .success(let samples):
                    self.chartSamples = samples
                case .failure(let error):
                    self.errorDescription = error.localizedDescription
                }
            }
        }
    }

    private nonisolated func refreshOnMain() {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}
```

实现时保留一个事实来源：`GlucoseHistoryRange` 同时提供标题、时长和横轴间隔。

- [ ] **Step 6: 运行 ViewModel 测试**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iOS Simulator ID>' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopTests/GlucoseHistoryViewModelTests \
  MAIN_APP_BUNDLE_IDENTIFIER=com.libre.loopkit3.Loop
```

Expected: PASS，所有请求范围、原样数量、倒序、竞态和通知生命周期断言通过。

- [ ] **Step 7: 提交 ViewModel**

```bash
git add \
  'Loop/Loop/View Models/GlucoseHistoryViewModel.swift' \
  Loop/LoopTests/ViewModels/GlucoseHistoryViewModelTests.swift \
  Loop/Loop.xcodeproj/project.pbxproj
git commit -m "新增 血糖历史数据模型" \
  -m "改动原因：历史页面需要统一管理时间范围、查询和刷新生命周期。

改动清单：新增 6/12/24 小时范围和 GlucoseStore 查询模型；覆盖排序、竞态、通知、退出和错误测试。

验证结果：GlucoseHistoryViewModelTests 通过。

影响范围：Loop 主 App 的新增历史页面能力，不修改 CGM 数据写入。"
```

## Chunk 2: 历史页面

### Task 3: 实现历史图表和明细页面

**Files:**
- Create: `Loop/Loop/Views/GlucoseHistoryView.swift`
- Create: `Loop/LoopTests/Views/GlucoseHistoryViewTests.swift`
- Modify: `Loop/Loop.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写页面状态、动作和行内容失败测试**

```swift
import HealthKit
import LoopKit
import LoopKitUI
import XCTest
@testable import Loop

@MainActor
final class GlucoseHistoryViewTests: XCTestCase {
    func testRowContentUsesCurrentUnitTrendAndManualMarker() {
        let preference = DisplayGlucosePreference(
            displayGlucoseUnit: .milligramsPerDeciliter
        )
        let sample = StoredGlucoseSample(
            startDate: Date(timeIntervalSinceReferenceDate: 0),
            quantity: HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: 123
            ),
            trend: .up,
            wasUserEntered: true
        )

        let mgdl = GlucoseHistoryRowContent(
            sample: sample,
            displayGlucosePreference: preference
        )
        XCTAssertEqual(mgdl.formattedValue, preference.format(sample.quantity))
        XCTAssertEqual(mgdl.trend, .up)
        XCTAssertTrue(mgdl.isManual)

        preference.unitDidChange(to: .millimolesPerLiter)
        let mmol = GlucoseHistoryRowContent(
            sample: sample,
            displayGlucosePreference: preference
        )
        XCTAssertEqual(mmol.formattedValue, preference.format(sample.quantity))
        XCTAssertNotEqual(mmol.formattedValue, mgdl.formattedValue)
    }

    func testPageContentContainsRangesChartAndRowsUsingSameSamples() async {
        var requests: [
            (
                start: Date,
                end: Date,
                completion: (Result<[StoredGlucoseSample], Error>) -> Void
            )
        ] = []
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let samples = [sample(at: now, value: 123)]
        let viewModel = GlucoseHistoryViewModel(
            loader: { start, end, completion in
                requests.append((start, end, completion))
            },
            now: { now }
        )
        viewModel.startObserving()
        requests[0].completion(.success(samples))
        await drainMainQueue()
        let content = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: DisplayGlucosePreference(
                displayGlucoseUnit: .milligramsPerDeciliter
            )
        )

        XCTAssertEqual(
            content.ranges.map(\.title),
            ["6 Hours", "12 Hours", "24 Hours"]
        )
        XCTAssertEqual(content.chartSamples, samples)
        XCTAssertEqual(content.rows.map(\.sample), Array(samples.reversed()))
        XCTAssertEqual(GlucoseHistoryViewContent.chartHeight, 220)

        content.selectRange(.twelveHours)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.start, now.addingTimeInterval(-.hours(12)))
    }

    func testPageContentReformatsRowsWhenUnitChanges() async {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        let preference = DisplayGlucosePreference(
            displayGlucoseUnit: .milligramsPerDeciliter
        )
        let samples = [sample(at: now, value: 123)]
        let viewModel = GlucoseHistoryViewModel(
            loader: { _, _, completion in
                completion(.success(samples))
            },
            now: { now }
        )
        viewModel.startObserving()
        await drainMainQueue()
        let mgdl = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        preference.unitDidChange(to: .millimolesPerLiter)
        let mmol = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        XCTAssertNotEqual(
            mmol.rows[0].formattedValue,
            mgdl.rows[0].formattedValue
        )
        XCTAssertEqual(
            mmol.rows[0].formattedValue,
            preference.format(
                HKQuantity(
                    unit: .milligramsPerDeciliter,
                    doubleValue: 123
                )
            )
        )
    }

    func testFailureContentShowsErrorAndRetryInvokesLoader() async {
        var loadCount = 0
        let viewModel = GlucoseHistoryViewModel(
            loader: { _, _, completion in
                loadCount += 1
                completion(.failure(TestError.expected))
            }
        )
        viewModel.startObserving()
        await drainMainQueue()
        let content = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: DisplayGlucosePreference(
                displayGlucoseUnit: .milligramsPerDeciliter
            )
        )

        XCTAssertNotNil(content.errorDescription)
        XCTAssertTrue(content.canRetry)
        content.retry()
        XCTAssertEqual(loadCount, 2)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func sample(at date: Date, value: Double) -> StoredGlucoseSample {
        StoredGlucoseSample(
            startDate: date,
            quantity: HKQuantity(
                unit: .milligramsPerDeciliter,
                doubleValue: value
            )
        )
    }

    private enum TestError: Error {
        case expected
    }
}
```

将测试加入 `LoopTests/Views` group 和 `LoopTests` Sources。

- [ ] **Step 2: 运行页面内容测试确认失败**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iOS Simulator ID>' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopTests/GlucoseHistoryViewTests \
  MAIN_APP_BUNDLE_IDENTIFIER=com.libre.loopkit3.Loop
```

Expected: FAIL，原因是 `GlucoseHistoryViewContent` 和 `GlucoseHistoryRowContent` 尚不存在。

- [ ] **Step 3: 创建页面并加入 App target**

页面使用现有图表包装，不增加新绘图库：

```swift
import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

struct GlucoseHistoryRowContent {
    let sample: StoredGlucoseSample
    let formattedValue: String
    let trend: GlucoseTrend?
    let isManual: Bool

    init(
        sample: StoredGlucoseSample,
        displayGlucosePreference: DisplayGlucosePreference
    ) {
        self.sample = sample
        formattedValue = displayGlucosePreference.format(sample.quantity)
        trend = sample.trend
        isManual = sample.wasUserEntered
    }
}

@MainActor
struct GlucoseHistoryViewContent {
    static let chartHeight: CGFloat = 220

    let ranges: [GlucoseHistoryRange]
    let selectedRange: GlucoseHistoryRange
    let chartSamples: [StoredGlucoseSample]
    let glucoseValues: [GlucoseValue]
    let rows: [GlucoseHistoryRowContent]
    let isLoading: Bool
    let errorDescription: String?
    let canRetry: Bool
    let isEmpty: Bool
    let selectRange: (GlucoseHistoryRange) -> Void
    let retry: () -> Void

    init(
        viewModel: GlucoseHistoryViewModel,
        displayGlucosePreference: DisplayGlucosePreference
    ) {
        ranges = GlucoseHistoryRange.allCases
        selectedRange = viewModel.selectedRange
        chartSamples = viewModel.chartSamples
        glucoseValues = viewModel.glucoseValues
        rows = viewModel.listSamples.map {
            GlucoseHistoryRowContent(
                sample: $0,
                displayGlucosePreference: displayGlucosePreference
            )
        }
        isLoading = viewModel.isLoading
        errorDescription = viewModel.errorDescription
        canRetry = errorDescription != nil
        isEmpty = viewModel.isEmpty
        selectRange = viewModel.selectRange
        retry = viewModel.refresh
    }
}

struct GlucoseHistoryView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @ObservedObject var viewModel: GlucoseHistoryViewModel
    @State private var isInteractingWithChart = false

    var body: some View {
        let page = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: displayGlucosePreference
        )

        return VStack(spacing: 0) {
            Picker(
                selection: Binding(
                    get: { page.selectedRange },
                    set: page.selectRange
                ),
                label: Text("History Range", comment: "Glucose history range picker label")
            ) {
                ForEach(page.ranges) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("glucoseHistory.range")

            content(page)
        }
        .navigationTitle(Text("Glucose History", comment: "Glucose history screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: viewModel.startObserving)
        .onDisappear(perform: viewModel.stopObserving)
    }

    private func content(_ page: GlucoseHistoryViewContent) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PredictedGlucoseChartView(
                    chartManager: viewModel.chartManager,
                    glucoseUnit: displayGlucosePreference.unit,
                    glucoseValues: page.glucoseValues,
                    predictedGlucoseValues: [],
                    targetGlucoseSchedule: nil,
                    preMealOverride: nil,
                    scheduleOverride: nil,
                    dateInterval: viewModel.chartDateInterval,
                    isInteractingWithChart: $isInteractingWithChart
                )

                if page.isLoading {
                    ProgressView()
                        .padding(8)
                }
            }
            .frame(height: GlucoseHistoryViewContent.chartHeight)
            .accessibilityIdentifier("glucoseHistory.chart")

            Divider()

            detailContent(page)
        }
    }

    @ViewBuilder
    private func detailContent(_ page: GlucoseHistoryViewContent) -> some View {
        if let error = page.errorDescription {
            VStack(spacing: 12) {
                Text(error)
                    .multilineTextAlignment(.center)
                Button(action: page.retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("glucoseHistory.retry")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("glucoseHistory.error")
        } else if page.chartSamples.isEmpty {
            if page.isLoading {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(
                    "No glucose data in this period",
                    comment: "Empty glucose history message"
                )
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("glucoseHistory.empty")
            }
        } else {
            List {
                Section(
                    header: Text(
                        "Readings",
                        comment: "Glucose history readings section"
                    )
                ) {
                    ForEach(
                        Array(page.rows.enumerated()),
                        id: \.offset
                    ) { index, row in
                        glucoseRow(row, index: index)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("glucoseHistory.list")
        }
    }

    private func glucoseRow(
        _ content: GlucoseHistoryRowContent,
        index: Int
    ) -> some View {
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.sample.startDate, style: .time)
                if content.isManual {
                    Text("Manual", comment: "Manual glucose history marker")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(content.formattedValue)
                .font(.body.monospacedDigit())

            if let trend = content.trend {
                trend.filledImage
                    .accessibilityLabel(trend.localizedDescription)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(content.formattedValue)
        .accessibilityIdentifier("glucoseHistory.row.\(index)")
    }
}
```

在 `Loop/Loop.xcodeproj/project.pbxproj` 中将文件加入 `Loop/Views` group 和 App Sources，不加入其它 target。

- [ ] **Step 4: 运行页面内容测试确认通过**

重复 Step 2 命令。

Expected: PASS；页面直接使用的 `GlucoseHistoryViewContent` 包含三个范围、固定图表高度和同源明细，选择动作会查询 12 小时；重新计算内容时 mg/dL 与 mmol/L 实时更新；趋势和手动输入标识来自同一条 sample；错误状态允许重试且重试动作会再次查询。

- [ ] **Step 5: 构建确认页面代码可编译**

```bash
xcodebuild build \
  -workspace LoopWorkspace.xcworkspace \
  -scheme Loop \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`。若 Swift 版本对 `nonisolated` 或 `ForEach` 推断有差异，只做保持同一行为的最小语法调整，并补相应测试。

- [ ] **Step 6: 提交页面**

```bash
git add \
  Loop/Loop/Views/GlucoseHistoryView.swift \
  Loop/LoopTests/Views/GlucoseHistoryViewTests.swift \
  Loop/Loop.xcodeproj/project.pbxproj
git commit -m "新增 血糖历史查看页面" \
  -m "改动原因：用户需要在 Loop 内查看超过一小时的血糖历史。

改动清单：新增 6/12/24 小时选择、实际血糖图表、倒序明细、空状态、错误和重试界面。

验证结果：GlucoseHistoryViewTests 和 Loop Simulator Debug 构建通过。

影响范围：新增历史页面，尚未改变首页入口。"
```

## Chunk 3: 首页接入与交付

### Task 4: 在首页增加入口并完成导航

**Files:**
- Modify: `Loop/Loop/View Controllers/StatusTableViewController.swift`
- Create: `Loop/LoopTests/ViewControllers/StatusTableViewControllerTests.swift`
- Create: `Loop/LoopUITests/LoopGlucoseHistoryUITests.swift`
- Modify: `Loop/Loop.xcodeproj/project.pbxproj`

- [ ] **Step 1: 写入口显示规则和首页导航失败测试**

使用纯布尔输入锁定“配置 CGM 时显示、未配置时隐藏”，不删除或替换真机上的 LinX：

```swift
import XCTest
@testable import Loop

final class StatusTableViewControllerTests: XCTestCase {
    func testGlucoseHistoryEntryVisibilityFollowsCGMConfiguration() {
        XCTAssertFalse(
            StatusTableViewController.shouldShowGlucoseHistoryEntry(
                hasConfiguredCGM: false
            )
        )
        XCTAssertTrue(
            StatusTableViewController.shouldShowGlucoseHistoryEntry(
                hasConfiguredCGM: true
            )
        )
    }
}
```

当前真机已经配置 MicroTech LinX。UI 测试必须使用这个真实配置，不注入模拟血糖：

```swift
import XCTest

final class LoopGlucoseHistoryUITests: XCTestCase {
    private let loopBundleIdentifier = "com.libre.loopkit3.Loop"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConfiguredCGMOpensGlucoseHistoryAndSwitchesRanges() {
        let app = XCUIApplication(bundleIdentifier: loopBundleIdentifier)
        app.launchArguments.append("-loop-ui-tests")
        app.launch()

        handleSystemAlerts(in: app)
        navigateToStatusScreenIfNeeded(in: app)

        let entry = app.cells["status.glucoseHistory"]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 15),
            "Glucose History requires a configured CGM on this device."
        )
        entry.tap()

        XCTAssertTrue(
            app.navigationBars["Glucose History"].waitForExistence(timeout: 5)
        )
        let picker = app.segmentedControls["glucoseHistory.range"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["6 Hours"].isSelected)

        picker.buttons["12 Hours"].tap()
        XCTAssertTrue(picker.buttons["12 Hours"].isSelected)
        picker.buttons["24 Hours"].tap()
        XCTAssertTrue(picker.buttons["24 Hours"].isSelected)

        XCTAssertTrue(
            app.otherElements["glucoseHistory.chart"].waitForExistence(timeout: 10) ||
            app.staticTexts["glucoseHistory.empty"].waitForExistence(timeout: 10)
        )
    }

    private func navigateToStatusScreenIfNeeded(in app: XCUIApplication) {
        if app.buttons["status.settings"].waitForExistence(timeout: 3) {
            return
        }

        for _ in 0..<4 {
            if app.buttons["status.settings"].exists {
                return
            }

            let status = app.navigationBars.buttons["Status"]
            let localizedStatus = app.navigationBars.buttons["状态"]
            if status.exists {
                status.tap()
            } else if localizedStatus.exists {
                localizedStatus.tap()
            } else {
                break
            }
        }
    }

    private func handleSystemAlerts(in app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for title in [
                "Allow", "OK", "Continue", "Not Now",
                "允许", "好", "继续", "以后", "稍后"
            ] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.tap()
    }
}
```

将 `StatusTableViewControllerTests.swift` 加入 `LoopTests`，将 `LoopGlucoseHistoryUITests.swift` 加入 `LoopUITests`。

- [ ] **Step 2: 运行显示规则测试确认失败**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iOS Simulator ID>' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopTests/StatusTableViewControllerTests \
  MAIN_APP_BUNDLE_IDENTIFIER=com.libre.loopkit3.Loop
```

Expected: FAIL，原因是 `shouldShowGlucoseHistoryEntry` 尚不存在。

- [ ] **Step 3: 构建安装无入口版本并确认 UI 测试失败**

```bash
xcodebuild build \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopWorkspace \
  -configuration Debug \
  -destination 'id=<Xcode destination ID>' \
  -derivedDataPath build/GlucoseHistoryFullPluginsDerivedData \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -disableAutomaticPackageResolution

xcrun devicectl device install app \
  --device '<devicectl device identifier>' \
  build/GlucoseHistoryFullPluginsDerivedData/Build/Products/Debug-iphoneos/Loop.app

xcodebuild test -quiet \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopUITests \
  -configuration Debug \
  -destination 'id=<Xcode destination ID>' \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -disableAutomaticPackageResolution \
  -only-testing:LoopUITests/LoopGlucoseHistoryUITests/testConfiguredCGMOpensGlucoseHistoryAndSwitchesRanges
```

Expected: FAIL，找不到 `status.glucoseHistory`。

- [ ] **Step 4: 增加首页独立入口 section**

在 `StatusTableViewController` 内增加可测试的显示规则，并让页面只从这一处读取：

```swift
static func shouldShowGlucoseHistoryEntry(
    hasConfiguredCGM: Bool
) -> Bool {
    hasConfiguredCGM
}

private var shouldShowGlucoseHistoryEntry: Bool {
    Self.shouldShowGlucoseHistoryEntry(
        hasConfiguredCGM: deviceManager.cgmManager != nil
    )
}
```

`StatusTableViewController.Section` 顺序改为：

```swift
private enum Section: Int, CaseIterable {
    case alertWarning
    case hud
    case status
    case glucoseHistory
    case charts
}
```

行数：

```swift
case .glucoseHistory:
    return shouldShowGlucoseHistoryEntry ? 1 : 0
```

Cell 使用默认样式，触控高度至少 44 点：

```swift
case .glucoseHistory:
    let reuseIdentifier = "GlucoseHistoryEntryCell"
    let cell = tableView.dequeueReusableCell(
        withIdentifier: reuseIdentifier
    ) ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)

    var content = cell.defaultContentConfiguration()
    content.text = NSLocalizedString(
        "Glucose History",
        comment: "Status screen glucose history entry"
    )
    content.image = UIImage(systemName: "chart.xyaxis.line")
        ?? UIImage(systemName: "chart.bar")
    content.imageProperties.tintColor = .glucoseTintColor
    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    cell.selectionStyle = .default
    cell.isAccessibilityElement = true
    cell.accessibilityLabel = content.text
    cell.accessibilityIdentifier = "status.glucoseHistory"
    return cell
```

高度：

```swift
case .glucoseHistory:
    return 44
```

`tableView(_:updateSubtitleFor:at:)` 的非图表分支明确改为：

```swift
case .glucoseHistory, .hud, .status, .alertWarning:
    break
```

五个 `Section` switch 必须全部显式包含 `.glucoseHistory`：

1. `tableView(_:numberOfRowsInSection:)`
2. `tableView(_:cellForRowAt:)`
3. `tableView(_:updateSubtitleFor:at:)`
4. `tableView(_:heightForRowAt:)`
5. `tableView(_:didSelectRowAt:)`

- [ ] **Step 5: 增加页面导航**

选择入口：

```swift
case .glucoseHistory:
    tableView.deselectRow(at: indexPath, animated: true)
    showGlucoseHistory()
```

页面创建：

```swift
private func showGlucoseHistory() {
    let glucoseStore = deviceManager.glucoseStore
    let viewModel = GlucoseHistoryViewModel(
        loader: { start, end, completion in
            glucoseStore.getGlucoseSamples(
                start: start,
                end: end,
                completion: completion
            )
        },
        glucoseStoreNotificationObject: glucoseStore
    )
    let view = GlucoseHistoryView(viewModel: viewModel)
        .environmentObject(deviceManager.displayGlucosePreference)
    let controller = UIHostingController(rootView: view)
    navigationController?.pushViewController(controller, animated: true)
}
```

首页现有 `viewWillDisappear` 会在 push 时显示导航栏，历史页使用系统返回按钮；返回首页后现有 `viewWillAppear` 再隐藏导航栏。

在 `.CGMManagerChanged` 回调内刷新入口 section：

```swift
self?.tableView.reloadSections(
    IndexSet(integer: Section.glucoseHistory.rawValue),
    with: .automatic
)
```

- [ ] **Step 6: 运行显示规则测试确认通过**

重复 Step 2 命令。

Expected: PASS，`false` 隐藏、`true` 显示，不改变真机 CGM 配置。

- [ ] **Step 7: 重新构建安装并运行 UI 测试**

重复 Step 3 的三个命令：签名构建、`devicectl` 安装、指定 UI 测试。

Expected: PASS；首页入口可见，历史页打开，默认 6 小时，12 和 24 小时可切换。

- [ ] **Step 8: 回归首页现有行为**

真机手动确认：

- Glucose 图表点击后仍进入预测页面。
- 底部五个按钮位置和功能不变。
- 返回历史页前后，首页导航栏隐藏状态不变。
- `StatusTableViewControllerTests` 已验证未配置 CGM 时隐藏；不删除真机 LinX 配置。

- [ ] **Step 9: 提交首页入口**

```bash
git add \
  'Loop/Loop/View Controllers/StatusTableViewController.swift' \
  Loop/LoopTests/ViewControllers/StatusTableViewControllerTests.swift \
  Loop/LoopUITests/LoopGlucoseHistoryUITests.swift \
  Loop/Loop.xcodeproj/project.pbxproj
git commit -m "新增 首页血糖历史入口" \
  -m "改动原因：历史页面需要从 Loop 首页快速进入。

改动清单：增加配置 CGM 时可见的独立入口行、页面导航和 UI 测试；保留预测页与底部按钮行为。

验证结果：StatusTableViewControllerTests 和 LoopGlucoseHistoryUITests 真机测试通过。

影响范围：Loop 首页新增一个条件显示的入口。"
```

### Task 5: 全量验证、真机安装和文档

**Files:**
- Modify: `PROGRESS.md`
- Modify if needed: `docs/工具与踩坑.md`

- [ ] **Step 1: 运行完整 LoopKit 图表测试**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme 'Shared (LoopKit project)' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopKitTests/ChartsManagerTests \
  -only-testing:LoopKitTests/PredictedGlucoseChartTests
```

Expected: PASS，新增间隔与现有血糖图表测试无失败。

- [ ] **Step 2: 运行完整历史页面测试**

```bash
xcodebuild test \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<iOS Simulator ID>' \
  -disableAutomaticPackageResolution \
  -only-testing:LoopTests/GlucoseHistoryViewModelTests \
  -only-testing:LoopTests/GlucoseHistoryViewTests \
  -only-testing:LoopTests/StatusTableViewControllerTests \
  MAIN_APP_BUNDLE_IDENTIFIER=com.libre.loopkit3.Loop
```

Expected: PASS，历史数据、页面内容和入口规则测试无失败。

- [ ] **Step 3: 运行完整 MicroTech 回归测试**

```bash
xcodebuild test \
  -project MicroTechCGM/MicroTechCGM.xcodeproj \
  -scheme Shared \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -disableAutomaticPackageResolution
```

Expected: PASS，MicroTech 当前值和历史补包回归测试无失败。

- [ ] **Step 4: 运行无签名 workspace 构建**

```bash
xcodebuild build \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopWorkspace \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 运行签名真机构建**

```bash
xcodebuild build \
  -workspace LoopWorkspace.xcworkspace \
  -scheme LoopWorkspace \
  -configuration Debug \
  -destination 'id=<Xcode destination ID>' \
  -derivedDataPath build/GlucoseHistoryFullPluginsDerivedData \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -disableAutomaticPackageResolution
```

Expected: `BUILD SUCCEEDED`，生成可安装的 `Loop.app`。

- [ ] **Step 6: 安装并启动当前 iPhone XR**

使用 Step 5 的固定 `derivedDataPath`：

```bash
xcrun devicectl device install app \
  --device '<devicectl device identifier>' \
  build/GlucoseHistoryFullPluginsDerivedData/Build/Products/Debug-iphoneos/Loop.app

xcrun devicectl device process launch \
  --device '<devicectl device identifier>' \
  --terminate-existing \
  com.libre.loopkit3.Loop

sleep 20
xcrun devicectl device info processes \
  --device '<devicectl device identifier>' \
  | rg '/Loop.app/Loop|com.libre.loopkit3.Loop'
```

Expected: 安装和启动成功，20 秒后的进程清单仍包含 Loop。

- [ ] **Step 7: 使用真实 LinX 数据验收**

保持 Loop 直接连接 MicroTech LinX：

- 首页显示 `Glucose History` 入口。
- 6 小时页面默认打开且列表最新值在上。
- 12、24 小时切换后查询范围和显示数据发生对应变化。
- 图表只显示实际血糖散点，不出现预测线。
- LinX 历史补包到达时页面自动增加数据，无需退出重进。
- iPhone XR 竖屏下三个范围的横轴文字不重叠。
- 图表、Picker、列表、返回按钮无重叠。
- 列表数值与 Loop 已保存数据一致，不显示测试或模拟值。

- [ ] **Step 8: 运行格式和敏感文件检查**

```bash
git diff --check
git status --short
git diff --cached --name-only
if git diff --cached --name-only | rg -q \
  '(^|/)xcuserdata/|^build/|^log/'; then
  echo "Local-only file is staged"
  exit 1
fi
```

Expected:

- `git diff --check` 无输出。
- 暂存文件清单不包含 `xcuserdata`、`build/`、`log/`。
- `git status --short` 可以显示这些本地改动，但不得清理或提交。
- 新文件全部属于预期 App 或测试 target。

- [ ] **Step 9: 更新进展文档**

在 `PROGRESS.md` 顶部新增倒序记录，包含：

- 首页入口、6/12/24 小时、图表和明细。
- `GlucoseStore` 同源读取与自动刷新。
- 单元测试、UI 测试、Workspace 构建、真机安装和真实 LinX 验收结果。
- 每个实际 commit hash。
- push 状态先写“待推送”，不能提前写成成功。

只有遇到新的非平凡工具问题时，才在 `docs/工具与踩坑.md` 增加问题、原因、解决方式和验证。

- [ ] **Step 10: 提交待推送状态并最多重试三次**

```bash
git diff --check
git add PROGRESS.md
git add docs/工具与踩坑.md  # 仅当本次确实修改
git diff --cached --check
git diff --cached --name-only
unexpected="$(
  git diff --cached --name-only \
    | rg -v '^(PROGRESS\.md|docs/工具与踩坑\.md)$' || true
)"
test -z "$unexpected"
git commit -m "文档 记录血糖历史页面验证" \
  -m "改动原因：记录血糖历史页面的实际交付和验收证据。

改动清单：补充测试、构建、真机安装、真实 LinX 数据和提交状态。

验证结果：相关测试、构建、安装和真机验收通过；git diff --check 通过。

影响范围：项目进展和必要的工具记录。"
```

使用已验证代理最多重试三次：

```bash
for attempt in 1 2 3; do
  git -c http.proxy=http://127.0.0.1:1082 \
    -c https.proxy=http://127.0.0.1:1082 \
    push origin main && break
  if [ "$attempt" -eq 3 ]; then
    exit 1
  fi
  sleep 2
done
```

Expected: 推送成功；禁止 `--force` 和 `--no-verify`。

- [ ] **Step 11: 回填真实推送状态并再次推送**

将 `PROGRESS.md` 当前条目的 commit hash 和 push 状态改为真实值，再提交：

```bash
git diff --check
git add PROGRESS.md
git diff --cached --check
git diff --cached --name-only
test "$(git diff --cached --name-only)" = "PROGRESS.md"
git commit -m "文档 更新血糖历史页面状态" \
  -m "改动原因：功能和验证记录已经推送，需要回填真实提交与推送状态。

改动清单：更新 commit hash 和 origin/main 推送状态。

验证结果：git diff --check 通过。

影响范围：仅 PROGRESS 进展记录。"

for attempt in 1 2 3; do
  git -c http.proxy=http://127.0.0.1:1082 \
    -c https.proxy=http://127.0.0.1:1082 \
    push origin main && break
  if [ "$attempt" -eq 3 ]; then
    exit 1
  fi
  sleep 2
done
```

- [ ] **Step 12: 验证远端 `main`**

```bash
remote_main="$(
  git -c http.proxy=http://127.0.0.1:1082 \
    -c https.proxy=http://127.0.0.1:1082 \
    ls-remote origin refs/heads/main \
    | awk '{print $1}'
)"
test "$remote_main" = "$(git rev-parse HEAD)"
git status --short --branch
```

Expected: 远端 hash 与本地 `HEAD` 完全一致；工作区只剩用户原有 `xcuserdata` 和本地 `build/`、`log/`。
