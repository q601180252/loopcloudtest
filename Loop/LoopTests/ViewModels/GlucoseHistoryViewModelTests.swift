//
//  GlucoseHistoryViewModelTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import UIKit
import XCTest
@testable import Loop

@MainActor
final class GlucoseHistoryViewModelTests: XCTestCase {
    private static let now = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    private var notificationCenter: NotificationCenter!
    private var glucoseStoreNotificationObject: NSObject!
    private var loader: ControllableGlucoseHistoryLoader!
    private var viewModel: GlucoseHistoryViewModel!

    override func setUp() {
        super.setUp()

        notificationCenter = NotificationCenter()
        glucoseStoreNotificationObject = NSObject()
        loader = ControllableGlucoseHistoryLoader()
        viewModel = GlucoseHistoryViewModel(
            loader: loader.load,
            notificationCenter: notificationCenter,
            glucoseStoreNotificationObject: glucoseStoreNotificationObject,
            now: { Self.now }
        )
    }

    override func tearDown() {
        viewModel.stopObserving()
        viewModel = nil
        loader = nil
        glucoseStoreNotificationObject = nil
        notificationCenter = nil

        super.tearDown()
    }

    func testStartObservingLoadsDefaultSixHourRange() {
        XCTAssertEqual(GlucoseHistoryRange.allCases.map(\.title), ["6 Hours", "12 Hours", "24 Hours"])
        XCTAssertEqual(GlucoseHistoryRange.allCases.map(\.duration), [.hours(6), .hours(12), .hours(24)])
        XCTAssertEqual(GlucoseHistoryRange.allCases.map(\.xAxisLabelInterval), [.hours(1), .hours(2), .hours(4)])
        XCTAssertEqual(GlucoseHistoryRange.sixHours.id, .sixHours)

        viewModel.startObserving()

        XCTAssertEqual(viewModel.selectedRange, .sixHours)
        XCTAssertEqual(loader.requests.count, 1)
        assertRequest(loader.requests[0], range: .sixHours)
        XCTAssertEqual(viewModel.chartDateInterval, DateInterval(start: Self.now - .hours(6), end: Self.now))
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(1))
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testSelectingTwelveAndTwentyFourHoursLoadsExactRangesAndUpdatesAxisInterval() {
        viewModel.startObserving()

        viewModel.selectRange(.twelveHours)

        XCTAssertEqual(loader.requests.count, 2)
        assertRequest(loader.requests[1], range: .twelveHours)
        XCTAssertEqual(viewModel.chartDateInterval, DateInterval(start: Self.now - .hours(12), end: Self.now))
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(2))

        viewModel.selectRange(.twentyFourHours)

        XCTAssertEqual(loader.requests.count, 3)
        assertRequest(loader.requests[2], range: .twentyFourHours)
        XCTAssertEqual(viewModel.chartDateInterval, DateInterval(start: Self.now - .hours(24), end: Self.now))
        XCTAssertEqual(viewModel.chartManager.xAxisLabelInterval, .hours(4))
    }

    func testSuccessPreservesChartOrderReversesListAndDoesNotDeduplicateSamples() async {
        let first = sample(value: 101, date: Self.now - .minutes(10))
        let second = sample(value: 202, date: first.startDate)
        let third = sample(value: 303, date: Self.now - .minutes(20))
        let returnedSamples = [first, second, third]
        viewModel.startObserving()

        loader.completeRequest(at: 0, with: .success(returnedSamples))
        await drainMainActor()

        XCTAssertEqual(viewModel.chartSamples, returnedSamples)
        XCTAssertEqual(viewModel.listSamples, Array(returnedSamples.reversed()))
        XCTAssertEqual(viewModel.chartSamples.count, 3)
        XCTAssertEqual(viewModel.listSamples.count, 3)
        XCTAssertEqual(viewModel.glucoseValues.count, 3)
        XCTAssertEqual(
            viewModel.glucoseValues.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) },
            [101, 202, 303]
        )
    }

    func testOlderRangeRequestCannotOverwriteNewerRangeResult() async {
        let oldSample = sample(value: 90, date: Self.now - .hours(5))
        let newSample = sample(value: 140, date: Self.now - .hours(10))
        viewModel.startObserving()
        viewModel.selectRange(.twelveHours)

        loader.completeRequest(at: 1, with: .success([newSample]))
        await drainMainActor()
        loader.completeRequest(at: 0, with: .success([oldSample]))
        await drainMainActor()

        XCTAssertEqual(viewModel.chartSamples, [newSample])
    }

    func testRangeCompletionUsesSameSamplesForChartAndList() async {
        let samples = [
            sample(value: 111, date: Self.now - .hours(20)),
            sample(value: 122, date: Self.now - .hours(12)),
            sample(value: 133, date: Self.now - .hours(4))
        ]
        viewModel.startObserving()
        viewModel.selectRange(.twentyFourHours)

        loader.completeRequest(at: 1, with: .success(samples))
        await drainMainActor()

        XCTAssertEqual(viewModel.chartSamples, samples)
        XCTAssertEqual(Array(viewModel.listSamples.reversed()), viewModel.chartSamples)
    }

    func testGlucoseChangeAndForegroundEachRefreshCurrentRange() async {
        viewModel.startObserving()
        viewModel.selectRange(.twelveHours)
        let refreshes = expectation(description: "Notification refreshes")
        refreshes.expectedFulfillmentCount = 2
        loader.onRequest = { refreshes.fulfill() }

        notificationCenter.post(
            name: GlucoseStore.glucoseSamplesDidChange,
            object: glucoseStoreNotificationObject
        )
        notificationCenter.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        await fulfillment(of: [refreshes], timeout: 1)

        XCTAssertEqual(loader.requests.count, 4)
        assertRequest(loader.requests[2], range: .twelveHours)
        assertRequest(loader.requests[3], range: .twelveHours)
    }

    func testOlderNotificationRequestCannotOverwriteNewerNotificationResult() async {
        let oldSample = sample(value: 95, date: Self.now - .hours(2))
        let newSample = sample(value: 155, date: Self.now - .hours(1))
        viewModel.startObserving()
        let refreshes = expectation(description: "Glucose notification refreshes")
        refreshes.expectedFulfillmentCount = 2
        loader.onRequest = { refreshes.fulfill() }

        notificationCenter.post(
            name: GlucoseStore.glucoseSamplesDidChange,
            object: glucoseStoreNotificationObject
        )
        notificationCenter.post(
            name: GlucoseStore.glucoseSamplesDidChange,
            object: glucoseStoreNotificationObject
        )
        await fulfillment(of: [refreshes], timeout: 1)

        loader.completeRequest(at: 2, with: .success([newSample]))
        await drainMainActor()
        loader.completeRequest(at: 1, with: .success([oldSample]))
        await drainMainActor()

        XCTAssertEqual(viewModel.chartSamples, [newSample])
    }

    func testStopObservingPreventsRefreshAndIgnoresLateCompletion() async {
        let lateSample = sample(value: 180, date: Self.now - .minutes(30))
        viewModel.startObserving()

        viewModel.stopObserving()
        notificationCenter.post(
            name: GlucoseStore.glucoseSamplesDidChange,
            object: glucoseStoreNotificationObject
        )
        await drainMainActor()
        loader.completeRequest(at: 0, with: .success([lateSample]))
        await drainMainActor()

        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertTrue(viewModel.chartSamples.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testEmptySuccessAndSubsequentFailureExposeExpectedStates() async {
        viewModel.startObserving()

        loader.completeRequest(at: 0, with: .success([]))
        await drainMainActor()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorDescription)

        viewModel.refresh()
        loader.completeRequest(
            at: 1,
            with: .failure(NSError(domain: "GlucoseHistoryViewModelTests", code: 1))
        )
        await drainMainActor()

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorDescription)
    }

    func testStartObservingAndSelectingCurrentRangeAreIdempotent() {
        viewModel.startObserving()
        viewModel.startObserving()
        viewModel.selectRange(.sixHours)

        XCTAssertEqual(loader.requests.count, 1)
    }

    private func assertRequest(
        _ request: ControllableGlucoseHistoryLoader.Request,
        range: GlucoseHistoryRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(request.end, Self.now, file: file, line: line)
        XCTAssertEqual(request.start, Self.now - range.duration, file: file, line: line)
        XCTAssertEqual(request.end.timeIntervalSince(request.start), range.duration, accuracy: 0, file: file, line: line)
    }

    private func sample(value: Double, date: Date) -> StoredGlucoseSample {
        StoredGlucoseSample(
            uuid: UUID(),
            startDate: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value)
        )
    }

    private func drainMainActor() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class ControllableGlucoseHistoryLoader {
    struct Request {
        let start: Date
        let end: Date
        let completion: (Result<[StoredGlucoseSample], Error>) -> Void
    }

    private(set) var requests: [Request] = []
    var onRequest: (() -> Void)?

    func load(
        start: Date,
        end: Date,
        completion: @escaping (Result<[StoredGlucoseSample], Error>) -> Void
    ) {
        requests.append(Request(start: start, end: end, completion: completion))
        onRequest?()
    }

    func completeRequest(at index: Int, with result: Result<[StoredGlucoseSample], Error>) {
        requests[index].completion(result)
    }
}
